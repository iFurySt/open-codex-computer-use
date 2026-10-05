#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN
/// Runtime-only bridge; private classes never appear in the Swift API.
NSObject * _Nullable OCUCreateVirtualDisplay(uint32_t width, uint32_t height,
    uint32_t scale, uint32_t serial, NSError * _Nullable * _Nullable error);
uint32_t OCUVirtualDisplayID(NSObject *display);
NS_ASSUME_NONNULL_END
