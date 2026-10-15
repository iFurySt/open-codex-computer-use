#include <Security/AuthorizationPlugin.h>
#include <assert.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
#include <stdint.h>

static unsigned results, deactivations, markers;
static AuthorizationResult expectedResult = kAuthorizationResultDeny;
static OSStatus setContext(AuthorizationEngineRef engine, AuthorizationString key,
                          AuthorizationContextFlags flags, const AuthorizationValue *value) {
    const char marker[] = "OCULockAuth-loaded-v1";
    assert(engine);
    if (strcmp(key, "dev.opencomputeruse.locked-use.load-check.audit-session") == 0) {
        assert(flags == kAuthorizationContextFlagExtractable && value && value->length == sizeof(uint32_t));
        return errAuthorizationSuccess;
    }
    assert(strcmp(key, "dev.opencomputeruse.locked-use.load-check") == 0);
    assert(flags == kAuthorizationContextFlagExtractable);
    assert(value && value->length == sizeof(marker) && memcmp(value->data, marker, sizeof(marker)) == 0);
    markers++;
    return errAuthorizationSuccess;
}
static OSStatus setResult(AuthorizationEngineRef engine, AuthorizationResult result) {
    assert(engine && result == expectedResult);
    results++;
    return errAuthorizationSuccess;
}
static OSStatus deactivate(AuthorizationEngineRef engine) {
    assert(engine); deactivations++;
    return errAuthorizationSuccess;
}

int main(int argc, char **argv) {
    assert(argc == 2);
    void *handle = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!handle) { fprintf(stderr, "%s\n", dlerror()); return 1; }
    typedef OSStatus (*Create)(const AuthorizationCallbacks *, AuthorizationPluginRef *, const AuthorizationPluginInterface **);
    Create create = (Create)dlsym(handle, "AuthorizationPluginCreate");
    assert(create);
    AuthorizationCallbacks callbacks = {.version = 1, .SetResult = setResult, .DidDeactivate = deactivate, .SetContextValue = setContext};
    AuthorizationPluginRef plugin = NULL;
    const AuthorizationPluginInterface *interface = NULL;
    assert(create(NULL, &plugin, &interface) != errAuthorizationSuccess);
    assert(create(&callbacks, &plugin, &interface) == errAuthorizationSuccess);
    AuthorizationMechanismRef mechanism = NULL;
    assert(interface->MechanismCreate(plugin, (AuthorizationEngineRef)&callbacks, "allow", &mechanism) != errAuthorizationSuccess);
    assert(!mechanism);
    assert(interface->MechanismCreate(plugin, (AuthorizationEngineRef)&callbacks, "remote", &mechanism) == errAuthorizationSuccess);
    // This test process is never an approved Apple authorizationhosthelper peer.
    // Even if a Broker is installed it must not grant this caller a permit.
    assert(interface->MechanismInvoke(mechanism) == errAuthorizationSuccess);
    assert(results == 1);
    assert(interface->MechanismInvoke(mechanism) != errAuthorizationSuccess);
    assert(results == 1);
    assert(interface->MechanismDeactivate(mechanism) == errAuthorizationSuccess);
    assert(deactivations == 1);
    assert(interface->MechanismDestroy(mechanism) == errAuthorizationSuccess);
    // Cancellation before invoke must never allow or send a late result.
    assert(interface->MechanismCreate(plugin, (AuthorizationEngineRef)&callbacks, "remote", &mechanism) == errAuthorizationSuccess);
    assert(interface->MechanismDeactivate(mechanism) == errAuthorizationSuccess);
    assert(interface->MechanismInvoke(mechanism) != errAuthorizationSuccess);
    assert(results == 1);
    assert(interface->MechanismDestroy(mechanism) == errAuthorizationSuccess);
    expectedResult = kAuthorizationResultAllow; // Only the independent load-check right.
    assert(interface->MechanismCreate(plugin, (AuthorizationEngineRef)&callbacks, "load-check", &mechanism) == errAuthorizationSuccess);
    assert(interface->MechanismInvoke(mechanism) == errAuthorizationSuccess);
    assert(results == 2 && markers == 1); // Grant proves load-check only, not a screensaver permission.
    assert(interface->MechanismInvoke(mechanism) != errAuthorizationSuccess);
    assert(results == 2 && markers == 1);
    assert(interface->MechanismDestroy(mechanism) == errAuthorizationSuccess);
    // A failed/missing context callback cannot grant even the load-check right.
    expectedResult = kAuthorizationResultDeny;
    callbacks.SetContextValue = NULL;
    assert(interface->MechanismCreate(plugin, (AuthorizationEngineRef)&callbacks, "load-check", &mechanism) == errAuthorizationSuccess);
    assert(interface->MechanismInvoke(mechanism) == errAuthorizationSuccess);
    assert(results == 3 && markers == 1);
    assert(interface->MechanismDestroy(mechanism) == errAuthorizationSuccess);
    assert(interface->PluginDestroy(plugin) == errAuthorizationSuccess);
    assert(dlclose(handle) == 0);
    puts("Remote mechanism offline ABI: deny without approved Broker permit, replay/cancellation rejected; no rights evaluated.");
    return 0;
}
