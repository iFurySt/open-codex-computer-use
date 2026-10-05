#include "PowerNative.h"
#include <CoreFoundation/CoreFoundation.h>
#include <Security/Security.h>
#include <xpc/xpc.h>
#include <dispatch/dispatch.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/acl.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <ctype.h>
#include <errno.h>
#include <stdatomic.h>
#ifdef OCU_POWER_DEV
#define HELPER_ID "com.opencomputeruse.power.helper.dev"
#define HOST_ID "com.opencomputeruse.power.host.dev"
#else
#define HELPER_ID "com.opencomputeruse.power.helper"
#define HOST_ID "com.opencomputeruse.power.host"
#endif
static xpc_connection_t client, server;
static char *signing_requirement(const char *identifier) {
    SecCodeRef code = NULL; CFDictionaryRef info = NULL;
    if (SecCodeCopySelf(kSecCSDefaultFlags, &code) != errSecSuccess) return NULL;
    OSStatus status = SecCodeCopySigningInformation(code, kSecCSSigningInformation, &info);
    CFRelease(code);
    if (status != errSecSuccess || !info) return NULL;
    CFStringRef team = CFDictionaryGetValue(info, kSecCodeInfoTeamIdentifier);
    char team_text[64] = {0};
    bool valid = team && CFGetTypeID(team) == CFStringGetTypeID() && CFStringGetCString(team, team_text, sizeof(team_text), kCFStringEncodingUTF8);
    CFRelease(info);
    if (!valid || !strlen(team_text)) return NULL;
    for (size_t i = 0; team_text[i]; i++) if (!isalnum((unsigned char)team_text[i])) return NULL;
    char *result = NULL;
    asprintf(&result, "anchor apple generic and identifier \"%s\" and certificate leaf[subject.OU] = \"%s\" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and ! entitlement[\"com.apple.security.get-task-allow\"] exists", identifier, team_text);
    return result;
}
static int valid_self(const char *identifier) {
    char *text = signing_requirement(identifier);
    if (!text) return 0;
    CFStringRef string = CFStringCreateWithCString(kCFAllocatorDefault, text, kCFStringEncodingUTF8);
    free(text);
    SecRequirementRef requirement = NULL; SecCodeRef code = NULL;
    OSStatus status = SecRequirementCreateWithString(string, kSecCSDefaultFlags, &requirement);
    CFRelease(string);
    if (status == errSecSuccess) status = SecCodeCopySelf(kSecCSDefaultFlags, &code);
    if (status == errSecSuccess) status = SecCodeCheckValidity(code, kSecCSStrictValidate, requirement);
    if (code) CFRelease(code);
    if (requirement) CFRelease(requirement);
    return status == errSecSuccess;
}
int ocu_power_is_signed_host(void) { return valid_self(HOST_ID); }
typedef struct {
    _Atomic unsigned references;
    dispatch_semaphore_t done;
    char *text;
} reply_state;
static void release_reply(reply_state *state) {
    if (atomic_fetch_sub(&state->references, 1) == 1) {
        dispatch_release(state->done); free(state->text); free(state);
    }
}
char *ocu_power_helper_request(const char *json) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        char *requirement = signing_requirement(HELPER_ID);
        if (!requirement) return;
        client = xpc_connection_create_mach_service(HELPER_ID, NULL, XPC_CONNECTION_MACH_SERVICE_PRIVILEGED);
        int status = xpc_connection_set_peer_code_signing_requirement(client, requirement);
        free(requirement);
        if (status) { xpc_release(client); client = NULL; return; }
        xpc_connection_set_event_handler(client, ^(xpc_object_t event) {});
        xpc_connection_resume(client);
    });
    if (!client) return strdup("{\"error\":\"A Developer ID signed bundle is required for the lid helper\"}");
    xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_string(message, "request", json);
    reply_state *state = calloc(1, sizeof(*state));
    state->references = 2; state->done = dispatch_semaphore_create(0);
    xpc_connection_send_message_with_reply(client, message, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^(xpc_object_t reply) {
        const char *value = xpc_get_type(reply) == XPC_TYPE_DICTIONARY ? xpc_dictionary_get_string(reply, "response") : NULL;
        state->text = strdup(value ?: "{\"error\":\"Lid helper unavailable or signature rejected\"}");
        dispatch_semaphore_signal(state->done); release_reply(state);
    });
    xpc_release(message);
    long timeout = dispatch_semaphore_wait(state->done, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
    char *result = strdup(timeout ? "{\"error\":\"Lid helper request timed out\"}" : state->text);
    release_reply(state);
    return result;
}
int ocu_power_helper_listen(ocu_power_handler handler) {
    char *requirement = signing_requirement(HOST_ID);
    if (!requirement || geteuid() != 0 || !valid_self(HELPER_ID)) { free(requirement); return -1; }
    // Immutable requirement and listener intentionally live for the daemon lifetime.
    dispatch_queue_t queue = dispatch_queue_create("com.opencomputeruse.power.helper.ipc", DISPATCH_QUEUE_SERIAL);
    server = xpc_connection_create_mach_service(HELPER_ID, queue, XPC_CONNECTION_MACH_SERVICE_LISTENER);
    xpc_connection_set_event_handler(server, ^(xpc_object_t peer) {
        if (xpc_get_type(peer) != XPC_TYPE_CONNECTION) return;
        if (xpc_connection_set_peer_code_signing_requirement(peer, requirement)) { xpc_connection_cancel(peer); return; }
        CFUUIDRef uuid = CFUUIDCreate(kCFAllocatorDefault);
        CFStringRef uuid_string = CFUUIDCreateString(kCFAllocatorDefault, uuid);
        char identity[64]; CFStringGetCString(uuid_string, identity, sizeof(identity), kCFStringEncodingUTF8);
        CFRelease(uuid_string); CFRelease(uuid);
        char *connection_id = strdup(identity);
        xpc_connection_set_event_handler(peer, ^(xpc_object_t event) {
            const char *request = xpc_get_type(event) == XPC_TYPE_DICTIONARY ? xpc_dictionary_get_string(event, "request") : NULL;
            if (!request) {
                if (event == XPC_ERROR_CONNECTION_INVALID) {
                    char *response = handler("{\"operation\":\"disconnect\"}", (uint32_t)xpc_connection_get_euid(peer), xpc_connection_get_pid(peer), connection_id);
                    free(response); free(connection_id);
                }
                return;
            }
            char *response = strlen(request) <= 8192 ? handler(request, (uint32_t)xpc_connection_get_euid(peer), xpc_connection_get_pid(peer), connection_id) : strdup("{\"error\":\"Request too large\"}");
            xpc_object_t reply = xpc_dictionary_create_reply(event);
            if (reply) {
                xpc_dictionary_set_string(reply, "response", response ?: "{\"error\":\"Empty response\"}");
                xpc_connection_send_message(peer, reply); xpc_release(reply);
            }
            free(response);
        });
        xpc_connection_resume(peer);
    });
    xpc_connection_resume(server); dispatch_release(queue);
    return 0;
}
void ocu_power_free(char *value) { free(value); }
int ocu_power_peer_uid(int fd, uint32_t *uid) {
    uid_t user; gid_t group;
    if (getpeereid(fd, &user, &group)) return -1;
    *uid = user; return 0;
}
int ocu_power_no_extended_acl(const char *path) {
    errno = 0;
    acl_t acl = acl_get_file(path, ACL_TYPE_EXTENDED);
    if (!acl) {
        int error = errno;
        struct stat st;
        return error == ENOENT && lstat(path, &st) == 0 ? 0 : -1;
    }
    acl_entry_t entry;
    errno = 0;
    int result = acl_get_entry(acl, ACL_FIRST_ENTRY, &entry);
    int error = errno;
    acl_free(acl);
    // Darwin returns 0 for an entry and -1/EINVAL for an empty OS-provided ACL.
    return result == -1 && error == EINVAL ? 0 : -1;
}
int ocu_power_secure_root_file(const char *path) {
    struct stat st;
    if (lstat(path, &st) || !S_ISREG(st.st_mode) || st.st_uid != 0 || (st.st_mode & 077) || st.st_nlink != 1) return -1;
    return ocu_power_no_extended_acl(path);
}
int ocu_power_secure_root_directory(const char *path) {
    struct stat st;
    if (lstat(path, &st) || !S_ISDIR(st.st_mode) || st.st_uid != 0 || (st.st_mode & 077)) return -1;
    return ocu_power_no_extended_acl(path);
}

#include <IOKit/IOKitLib.h>
#include <mach/mach.h>
#include <math.h>
// Private AppleSMC user-client ABI. Only metadata/read commands for PSTR.
typedef struct { uint32_t size, type; uint8_t attributes; } ocu_smc_info;
typedef struct {
    uint32_t key;
    uint8_t version[6], limits[16];
    ocu_smc_info info;
    uint8_t result, status, command;
    uint32_t index;
    uint8_t bytes[32];
} ocu_smc_packet;
_Static_assert(sizeof(ocu_smc_packet) == 80, "Unexpected SMC ABI layout");
static int smc_read_call(io_connect_t port, ocu_smc_packet *input, ocu_smc_packet *output) {
    size_t count = sizeof(*output);
    return IOConnectCallStructMethod(port, 2, input, sizeof(*input), output, &count) == KERN_SUCCESS
        && count == sizeof(*output) && output->result == 0;
}
int ocu_power_system_watts(double *watts) {
#if !defined(__arm64__)
    return -1; // This decoder is validated on Apple Silicon only.
#endif
    if (!watts) return -1;
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) return -1;
    io_connect_t port = 0;
    kern_return_t result = IOServiceOpen(service, mach_task_self(), 0, &port);
    IOObjectRelease(service);
    if (result != KERN_SUCCESS) return -1;
    ocu_smc_packet input = {0}, output = {0};
    input.key = 0x50535452; input.command = 9; // PSTR, read metadata
    int valid = smc_read_call(port, &input, &output);
    if (valid && output.info.type == 0x666c7420 && output.info.size == 4) { // flt
        input.info.size = 4; input.command = 5;
        memset(&output, 0, sizeof(output));
        valid = smc_read_call(port, &input, &output);
        float value = 0;
        memcpy(&value, output.bytes, sizeof(value));
        valid = valid && isfinite(value) && value >= 0 && value <= 2000;
        if (valid) *watts = value;
    } else { valid = 0; }
    IOServiceClose(port);
    return valid ? 0 : -1;
}
