#include <Security/AuthorizationPlugin.h>
#include <assert.h>
#include <dlfcn.h>
#include <stdio.h>

static unsigned results = 0, deactivations = 0;
static AuthorizationResult lastResult;
static OSStatus setResult(AuthorizationEngineRef engine, AuthorizationResult result) {
    assert(engine);
    results++;
    lastResult = result;
    return errAuthorizationSuccess;
}
static OSStatus deactivate(AuthorizationEngineRef engine) {
    assert(engine);
    deactivations++;
    return errAuthorizationSuccess;
}

int main(int argc, char **argv) {
    assert(argc == 2);
    void *handle = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!handle) { fprintf(stderr, "%s\n", dlerror()); return 1; }
    typedef OSStatus (*Create)(const AuthorizationCallbacks *, AuthorizationPluginRef *, const AuthorizationPluginInterface **);
    Create create = (Create)dlsym(handle, "AuthorizationPluginCreate");
    assert(create);
    AuthorizationCallbacks callbacks = { .version = 1, .SetResult = setResult, .DidDeactivate = deactivate };
    AuthorizationPluginRef plugin = NULL;
    const AuthorizationPluginInterface *interface = NULL;
    assert(create(NULL, &plugin, &interface) != errAuthorizationSuccess);
    assert(!plugin && !interface);
    assert(create(&callbacks, &plugin, &interface) == errAuthorizationSuccess);
    assert(interface->version == kAuthorizationPluginInterfaceVersion);
    AuthorizationMechanismRef mechanism = NULL;
    // A probe may never be repurposed as an "allow" mechanism by changing auth.db.
    assert(interface->MechanismCreate(plugin, (AuthorizationEngineRef)&callbacks, "allow", &mechanism) != errAuthorizationSuccess);
    assert(!mechanism);
    assert(interface->MechanismCreate(plugin, (AuthorizationEngineRef)&callbacks, "preflight", &mechanism) == errAuthorizationSuccess);
    assert(interface->MechanismInvoke(mechanism) == errAuthorizationSuccess);
    assert(results == 1 && lastResult == kAuthorizationResultDeny);
    assert(interface->MechanismDeactivate(mechanism) == errAuthorizationSuccess);
    assert(deactivations == 1);
    assert(interface->MechanismDestroy(mechanism) == errAuthorizationSuccess);
    assert(interface->PluginDestroy(plugin) == errAuthorizationSuccess);
    assert(dlclose(handle) == 0);
    puts("Authorization plugin ABI probe passed; mechanism denied; no system rights evaluated.");
    return 0;
}
