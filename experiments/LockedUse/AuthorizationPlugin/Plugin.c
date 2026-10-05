/* Experimental ABI probe only. No unlock mechanism is shipped until the
 * loginwindow + Keychain + guardian gates pass. This plugin ALWAYS denies.
 * It does not read or write username/password/authentication context. */
#include <Security/AuthorizationPlugin.h>
#include <os/log.h>
#include <stdlib.h>
#include <string.h>

struct Plugin { const AuthorizationCallbacks *callbacks; };
struct Mechanism { struct Plugin *plugin; AuthorizationEngineRef engine; };

static OSStatus destroyPlugin(AuthorizationPluginRef ref) {
    if (!ref) return errAuthorizationInvalidRef;
    free((void *)ref);
    return errAuthorizationSuccess;
}

static OSStatus createMechanism(AuthorizationPluginRef ref, AuthorizationEngineRef engine,
                               AuthorizationMechanismId name, AuthorizationMechanismRef *out) {
    if (!out) return errAuthorizationInvalidPointer;
    *out = NULL;
    if (!ref || !engine || !name) return errAuthorizationInvalidRef;
    if (strcmp(name, "preflight") != 0) return errAuthorizationInternal;
    struct Mechanism *mechanism = calloc(1, sizeof(*mechanism));
    if (!mechanism) return errAuthorizationInternal;
    mechanism->plugin = (struct Plugin *)ref;
    mechanism->engine = engine;
    *out = (AuthorizationMechanismRef)mechanism;
    return errAuthorizationSuccess;
}

static OSStatus invokeMechanism(AuthorizationMechanismRef ref) {
    if (!ref) return errAuthorizationInvalidRef;
    struct Mechanism *mechanism = (struct Mechanism *)ref;
    os_log(OS_LOG_DEFAULT, "OpenComputerUseAuthorizationProbe invoked; denying without reading credentials");
    return mechanism->plugin->callbacks->SetResult(mechanism->engine, kAuthorizationResultDeny);
}

static OSStatus deactivateMechanism(AuthorizationMechanismRef ref) {
    if (!ref) return errAuthorizationInvalidRef;
    struct Mechanism *mechanism = (struct Mechanism *)ref;
    return mechanism->plugin->callbacks->DidDeactivate(mechanism->engine);
}

static OSStatus destroyMechanism(AuthorizationMechanismRef ref) {
    if (!ref) return errAuthorizationInvalidRef;
    free((void *)ref);
    return errAuthorizationSuccess;
}

static const AuthorizationPluginInterface interface = {
    .version = kAuthorizationPluginInterfaceVersion,
    .PluginDestroy = destroyPlugin,
    .MechanismCreate = createMechanism,
    .MechanismInvoke = invokeMechanism,
    .MechanismDeactivate = deactivateMechanism,
    .MechanismDestroy = destroyMechanism
};

__attribute__((visibility("default")))
OSStatus AuthorizationPluginCreate(const AuthorizationCallbacks *callbacks,
                                   AuthorizationPluginRef *outPlugin,
                                   const AuthorizationPluginInterface **outInterface) {
    if (outPlugin) *outPlugin = NULL;
    if (outInterface) *outInterface = NULL;
    if (!callbacks || !outPlugin || !outInterface || !callbacks->SetResult || !callbacks->DidDeactivate)
        return errAuthorizationInvalidPointer;
    if (callbacks->version < 1) return errAuthorizationInternal;
    struct Plugin *plugin = calloc(1, sizeof(*plugin));
    if (!plugin) return errAuthorizationInternal;
    plugin->callbacks = callbacks;
    *outPlugin = (AuthorizationPluginRef)plugin;
    *outInterface = &interface;
    return errAuthorizationSuccess;
}
