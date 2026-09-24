// OpenComputerUseVirtualDisplayShim — the only place that touches the private
// CGVirtualDisplay classes (CoreGraphics). Every class is resolved with
// NSClassFromString at runtime, so nothing here is a hard link dependency; a
// macOS without the classes reports "unsupported" and the caller fails closed.
#ifndef OPEN_COMPUTER_USE_VIRTUAL_DISPLAY_SHIM_H
#define OPEN_COMPUTER_USE_VIRTUAL_DISPLAY_SHIM_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 1 when the private CGVirtualDisplay classes exist on this system.
int ocu_virtual_display_is_supported(void);

/// Create a virtual display of `width` x `height` points at `refresh_rate` Hz.
/// Returns the CGDirectDisplayID (0 on failure) and stores an opaque retained
/// handle in `handle_out`; pass it to `ocu_virtual_display_destroy` to remove
/// the display again.
uint32_t ocu_virtual_display_create(const char *name, uint32_t width, uint32_t height, double refresh_rate, void **handle_out);

/// Remove the display and release the handle.
void ocu_virtual_display_destroy(void *handle);

#ifdef __cplusplus
}
#endif

#endif
