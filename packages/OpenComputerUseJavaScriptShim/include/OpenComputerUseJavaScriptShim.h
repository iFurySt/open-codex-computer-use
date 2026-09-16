// OpenComputerUseJavaScriptShim — exposes JavaScriptCore's execution
// time-limit C API, which is not surfaced to Swift's JavaScriptCore module, so
// the js tool can bound a runaway script. The context is passed as an opaque
// pointer (the JSGlobalContextRef) to keep the Swift interface free of
// JavaScriptCore C types.
#ifndef OPEN_COMPUTER_USE_JAVASCRIPT_SHIM_H
#define OPEN_COMPUTER_USE_JAVASCRIPT_SHIM_H

#ifdef __cplusplus
extern "C" {
#endif

/// Arm a wall-clock limit for scripts run in `context_ref`'s group; when it is
/// exceeded the running script is terminated with a JavaScript exception.
void ocu_js_set_time_limit(void *context_ref, double seconds);

/// Remove any limit previously set for `context_ref`'s group.
void ocu_js_clear_time_limit(void *context_ref);

#ifdef __cplusplus
}
#endif

#endif
