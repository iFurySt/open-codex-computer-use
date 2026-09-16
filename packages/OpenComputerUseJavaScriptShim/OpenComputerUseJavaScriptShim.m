#import "OpenComputerUseJavaScriptShim.h"
#import <JavaScriptCore/JavaScriptCore.h>

// JSContextGroupSetExecutionTimeLimit / ...Clear are exported by
// JavaScriptCore.framework but declared only in its private header, so the
// prototypes are restated here. The symbols are confirmed present in the
// framework's exported symbol table.
typedef bool (*OCUJSShouldTerminateCallback)(JSContextRef ctx, void *context);
extern void JSContextGroupSetExecutionTimeLimit(
    JSContextGroupRef group, double limit, OCUJSShouldTerminateCallback callback, void *context);
extern void JSContextGroupClearExecutionTimeLimit(JSContextGroupRef group);

static bool ocu_js_should_terminate(JSContextRef ctx, void *context) {
    (void)ctx;
    (void)context;
    return true;
}

void ocu_js_set_time_limit(void *context_ref, double seconds) {
    if (context_ref == NULL) {
        return;
    }
    JSContextRef ctx = (JSContextRef)context_ref;
    JSContextGroupRef group = JSContextGetGroup(ctx);
    JSContextGroupSetExecutionTimeLimit(group, seconds, ocu_js_should_terminate, NULL);
}

void ocu_js_clear_time_limit(void *context_ref) {
    if (context_ref == NULL) {
        return;
    }
    JSContextRef ctx = (JSContextRef)context_ref;
    JSContextGroupRef group = JSContextGetGroup(ctx);
    JSContextGroupClearExecutionTimeLimit(group);
}
