// Minimal remote mechanism. No credential context/hints are read or written.
// The diagnostic deny-only plugin remains a separate artifact/right.
#import <Foundation/Foundation.h>
#import <Security/AuthorizationPlugin.h>
#import <Security/Security.h>
#include "LockedUseNative.h"
#include <arpa/inet.h>
#include <fcntl.h>
#include <poll.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

#ifndef OCU_SIGNING_TEAM
#error "Remote mechanism requires a fixed Developer ID signing team"
#endif

static const char *socketPath = "/Library/Application Support/OpenComputerUse/LockedUse/run/plugin.sock";
static double monotonic(void) {
    struct timespec value;
    if (clock_gettime(CLOCK_MONOTONIC, &value) != 0) return -1;
    return value.tv_sec + value.tv_nsec / 1e9;
}

static bool ready(int fd, short events, double deadline) {
    for (;;) {
        double remaining = deadline - monotonic();
        if (remaining <= 0 || remaining > 3) return false;
        struct pollfd entry = {.fd = fd, .events = events};
        int result = poll(&entry, 1, (int)(remaining * 1000 + 1));
        if (result < 0 && errno == EINTR) continue;
        return result > 0 && !(entry.revents & POLLNVAL);
    }
}

static bool transfer(int fd, void *bytes, size_t length, bool sending, double deadline) {
    size_t offset = 0;
    while (offset < length) {
        if (!ready(fd, sending ? POLLOUT : POLLIN, deadline)) return false;
        ssize_t count = sending ? write(fd, (char *)bytes + offset, length - offset)
                                : read(fd, (char *)bytes + offset, length - offset);
        if (count < 0 && (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK)) continue;
        if (count <= 0) return false;
        offset += (size_t)count;
    }
    return true;
}

static bool verifyBroker(int fd) {
    OCUPeerIdentity peer;
    if (ocu_copy_peer_identity(fd, &peer) != 0 || peer.effective_user_id != 0) return false;
    NSData *audit = [NSData dataWithBytes:peer.audit_token length:sizeof(peer.audit_token)];
    NSDictionary *attributes = @{(__bridge NSString *)kSecGuestAttributeAudit: audit};
    SecCodeRef guest = NULL;
    SecRequirementRef requirement = NULL;
    SecStaticCodeRef staticCode = NULL;
    CFDictionaryRef info = NULL;
    CFStringRef text = CFSTR("identifier \"dev.opencomputeruse.locked-use.broker\" and anchor apple generic and certificate leaf[subject.OU] = \"" OCU_SIGNING_TEAM "\"");
    bool valid = SecCodeCopyGuestWithAttributes(NULL, (__bridge CFDictionaryRef)attributes, kSecCSDefaultFlags, &guest) == errSecSuccess
        && SecRequirementCreateWithString(text, kSecCSDefaultFlags, &requirement) == errSecSuccess
        && SecCodeCheckValidity(guest, kSecCSDefaultFlags, requirement) == errSecSuccess
        && SecCodeCopyStaticCode(guest, kSecCSDefaultFlags, &staticCode) == errSecSuccess
        && SecCodeCopySigningInformation(staticCode, kSecCSSigningInformation, &info) == errSecSuccess;
    if (valid) {
        NSDictionary *metadata = (__bridge NSDictionary *)info;
        unsigned int flags = [metadata[(__bridge NSString *)kSecCodeInfoFlags] unsignedIntValue];
        NSDictionary *entitlements = metadata[(__bridge NSString *)kSecCodeInfoEntitlementsDict];
        valid = (flags & kSecCodeSignatureRuntime) != 0;
        for (NSString *key in @[@"get-task-allow", @"com.apple.security.get-task-allow",
            @"com.apple.security.cs.disable-library-validation", @"com.apple.security.cs.allow-dyld-environment-variables",
            @"com.apple.security.cs.allow-unsigned-executable-memory"]) {
            if ([entitlements[key] boolValue]) valid = false;
        }
        valid = valid && SecCodeCheckValidity(guest, kSecCSDefaultFlags, requirement) == errSecSuccess;
    }
    if (info) CFRelease(info);
    if (staticCode) CFRelease(staticCode);
    if (requirement) CFRelease(requirement);
    if (guest) CFRelease(guest);
    return valid;
}

static NSDictionary *exchange(int fd, NSString *operation, NSDictionary *extra, double deadline) {
    NSString *identifier = NSUUID.UUID.UUIDString;
    NSMutableDictionary *request = [@{@"version": @1, @"id": identifier, @"operation": operation} mutableCopy];
    [request addEntriesFromDictionary:extra ?: @{}];
    NSData *payload = [NSJSONSerialization dataWithJSONObject:request options:0 error:NULL];
    if (!payload || payload.length == 0 || payload.length > 16384) return nil;
    uint32_t size = htonl((uint32_t)payload.length);
    if (!transfer(fd, &size, sizeof(size), true, deadline)
        || !transfer(fd, (void *)payload.bytes, payload.length, true, deadline)
        || !transfer(fd, &size, sizeof(size), false, deadline)) return nil;
    size = ntohl(size);
    if (size == 0 || size > 16384) return nil;
    NSMutableData *response = [NSMutableData dataWithLength:size];
    if (!transfer(fd, response.mutableBytes, size, false, deadline)) return nil;
    id decoded = [NSJSONSerialization JSONObjectWithData:response options:0 error:NULL];
    if (![decoded isKindOfClass:NSDictionary.class] || ![decoded[@"id"] isEqual:identifier]
        || ![decoded[@"version"] isEqual:@1]) return nil;
    return decoded;
}

@interface OCUPlugin : NSObject
@property(nonatomic, assign) const AuthorizationCallbacks *callbacks;
@end
@implementation OCUPlugin
@end

@interface OCUMechanism : NSObject
@property(nonatomic, strong) OCUPlugin *plugin;
@property(nonatomic, strong) NSRecursiveLock *mutex;
@property(nonatomic, assign) AuthorizationEngineRef engine;
@property(nonatomic, assign) int descriptor;
@property(nonatomic, assign) BOOL cancelled;
@property(nonatomic, assign) BOOL invoked;
@end
@implementation OCUMechanism
@end

static OSStatus pluginDestroy(AuthorizationPluginRef ref) {
    if (!ref) return errAuthorizationInvalidRef;
    (void)CFBridgingRelease(ref);
    return errAuthorizationSuccess;
}

static OSStatus mechanismCreate(AuthorizationPluginRef pluginRef, AuthorizationEngineRef engine,
                               AuthorizationMechanismId name, AuthorizationMechanismRef *out) {
    if (!out) return errAuthorizationInvalidPointer;
    *out = NULL;
    if (!pluginRef || !engine || !name) return errAuthorizationInvalidRef;
    if (strcmp(name, "remote") != 0) return errAuthorizationInternal;
    OCUMechanism *mechanism = [OCUMechanism new];
    mechanism.plugin = (__bridge OCUPlugin *)pluginRef;
    mechanism.mutex = [NSRecursiveLock new];
    mechanism.engine = engine;
    mechanism.descriptor = -1;
    *out = (AuthorizationMechanismRef)CFBridgingRetain(mechanism);
    return errAuthorizationSuccess;
}

static OSStatus mechanismInvoke(AuthorizationMechanismRef ref) {
    if (!ref) return errAuthorizationInvalidRef;
    @autoreleasepool {
        OCUMechanism *mechanism = (__bridge OCUMechanism *)ref;
        [mechanism.mutex lock];
        if (mechanism.cancelled || mechanism.invoked) {
            [mechanism.mutex unlock]; return errAuthorizationInternal;
        }
        mechanism.invoked = YES;
        int fd = socket(AF_UNIX, SOCK_STREAM, 0);
        mechanism.descriptor = fd;
        [mechanism.mutex unlock];
        BOOL allowed = NO;
        double deadline = monotonic() + 2;
        if (fd >= 0) {
            int value = 1;
            struct sockaddr_un address = {.sun_family = AF_UNIX, .sun_len = sizeof(struct sockaddr_un)};
            strlcpy(address.sun_path, socketPath, sizeof(address.sun_path));
            BOOL configured = fcntl(fd, F_SETFD, FD_CLOEXEC) == 0 && fcntl(fd, F_SETFL, O_NONBLOCK) == 0
                && setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &value, sizeof(value)) == 0;
            int result = configured ? connect(fd, (struct sockaddr *)&address, sizeof(address)) : -1;
            if (result < 0 && configured && errno == EINPROGRESS && ready(fd, POLLOUT, deadline)) {
                int failure = 0;
                socklen_t size = sizeof(failure);
                if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &failure, &size) == 0 && failure == 0) result = 0;
            }
            if (result == 0 && verifyBroker(fd)) {
                NSDictionary *claim = exchange(fd, @"pluginClaim", nil, deadline);
                NSString *lease = [claim[@"leaseID"] isKindOfClass:NSString.class] ? claim[@"leaseID"] : nil;
                NSString *token = [claim[@"token"] isKindOfClass:NSString.class] ? claim[@"token"] : nil;
                NSData *nonce = token ? [[NSData alloc] initWithBase64EncodedString:token options:0] : nil;
                if ([claim[@"phase"] isEqual:@"authorizing"] && lease && [[NSUUID alloc] initWithUUIDString:lease] && nonce.length == 32) {
                    NSDictionary *reply = exchange(fd, @"pluginConsume", @{@"leaseID": lease, @"token": token}, deadline);
                    allowed = [reply[@"result"] isEqual:@"authorized"] && [reply[@"phase"] isEqual:@"unlocking"];
                }
            }
        }
        [mechanism.mutex lock];
        OSStatus status = errAuthorizationSuccess;
        if (!mechanism.cancelled) {
            status = mechanism.plugin.callbacks->SetResult(mechanism.engine,
                allowed ? kAuthorizationResultAllow : kAuthorizationResultDeny);
        }
        [mechanism.mutex unlock];
        if (fd >= 0) {
            // Best effort completion, bounded by the same absolute deadline.
            (void)exchange(fd, @"pluginFinished", allowed && status == errAuthorizationSuccess
                ? nil : @{@"stopReason": @"operationFailed"}, deadline);
            [mechanism.mutex lock];
            mechanism.descriptor = -1;
            close(fd);
            [mechanism.mutex unlock];
        }
        return status;
    }
}

static OSStatus mechanismDeactivate(AuthorizationMechanismRef ref) {
    if (!ref) return errAuthorizationInvalidRef;
    OCUMechanism *mechanism = (__bridge OCUMechanism *)ref;
    [mechanism.mutex lock];
    mechanism.cancelled = YES;
    if (mechanism.descriptor >= 0) shutdown(mechanism.descriptor, SHUT_RDWR);
    OSStatus status = mechanism.plugin.callbacks->DidDeactivate(mechanism.engine);
    [mechanism.mutex unlock];
    return status;
}

static OSStatus mechanismDestroy(AuthorizationMechanismRef ref) {
    if (!ref) return errAuthorizationInvalidRef;
    OCUMechanism *mechanism = CFBridgingRelease(ref);
    [mechanism.mutex lock];
    mechanism.cancelled = YES;
    if (mechanism.descriptor >= 0) shutdown(mechanism.descriptor, SHUT_RDWR);
    [mechanism.mutex unlock];
    return errAuthorizationSuccess;
}

static const AuthorizationPluginInterface interface = {
    .version = kAuthorizationPluginInterfaceVersion,
    .PluginDestroy = pluginDestroy, .MechanismCreate = mechanismCreate,
    .MechanismInvoke = mechanismInvoke, .MechanismDeactivate = mechanismDeactivate,
    .MechanismDestroy = mechanismDestroy
};

__attribute__((visibility("default")))
OSStatus AuthorizationPluginCreate(const AuthorizationCallbacks *callbacks,
                                   AuthorizationPluginRef *out, const AuthorizationPluginInterface **outInterface) {
    if (out) *out = NULL;
    if (outInterface) *outInterface = NULL;
    if (!callbacks || !out || !outInterface || callbacks->version < 1 || !callbacks->SetResult || !callbacks->DidDeactivate)
        return errAuthorizationInvalidPointer;
    OCUPlugin *plugin = [OCUPlugin new];
    plugin.callbacks = callbacks;
    *out = (AuthorizationPluginRef)CFBridgingRetain(plugin);
    *outInterface = &interface;
    return errAuthorizationSuccess;
}
