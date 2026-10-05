#import "VirtualDisplayBridge.h"
#import <objc/message.h>

static BOOL require(Class cls, NSArray<NSString *> *selectors, NSError **error) {
    for (NSString *name in selectors) {
        if (!cls || ![cls instancesRespondToSelector:NSSelectorFromString(name)]) {
            if (error) *error = [NSError errorWithDomain:@"OCUVirtualDisplay" code:1
                userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Missing private display capability %@.%@", cls, name]}];
            return NO;
        }
    }
    return YES;
}

NSObject *OCUCreateVirtualDisplay(uint32_t width, uint32_t height,
    uint32_t scale, uint32_t serial, NSError **error) {
    Class descriptorClass = NSClassFromString(@"CGVirtualDisplayDescriptor");
    Class settingsClass = NSClassFromString(@"CGVirtualDisplaySettings");
    Class modeClass = NSClassFromString(@"CGVirtualDisplayMode");
    Class displayClass = NSClassFromString(@"CGVirtualDisplay");
    if (!require(descriptorClass, @[@"init", @"setName:", @"setQueue:", @"setMaxPixelsWide:", @"setMaxPixelsHigh:", @"setVendorID:", @"setProductID:", @"setSerialNum:", @"setSizeInMillimeters:"], error) ||
        !require(settingsClass, @[@"init", @"setModes:", @"setHiDPI:"], error) ||
        !require(modeClass, @[@"initWithWidth:height:refreshRate:"], error) ||
        !require(displayClass, @[@"initWithDescriptor:", @"applySettings:", @"displayID"], error)) return nil;
    @try {
        NSObject *descriptor = [[descriptorClass alloc] init];
        [descriptor setValue:@"Open Computer Use Virtual Display" forKey:@"name"];
        [descriptor setValue:dispatch_queue_create("com.ifuryst.ocu.virtual-display", DISPATCH_QUEUE_SERIAL) forKey:@"queue"];
        [descriptor setValue:@(width * scale) forKey:@"maxPixelsWide"];
        [descriptor setValue:@(height * scale) forKey:@"maxPixelsHigh"];
        [descriptor setValue:@(0x4f43) forKey:@"vendorID"];
        [descriptor setValue:@(1) forKey:@"productID"];
        [descriptor setValue:@(serial) forKey:@"serialNum"];
        if ([descriptor respondsToSelector:NSSelectorFromString(@"setSerialNumber:")])
            [descriptor setValue:@(serial) forKey:@"serialNumber"];
        [descriptor setValue:[NSValue valueWithSize:NSMakeSize(width * 25.4 / 110.0, height * 25.4 / 110.0)] forKey:@"sizeInMillimeters"];
        NSObject *display = ((id (*)(id, SEL, id))objc_msgSend)([displayClass alloc], NSSelectorFromString(@"initWithDescriptor:"), descriptor);
        NSObject *mode = ((id (*)(id, SEL, NSUInteger, NSUInteger, double))objc_msgSend)([modeClass alloc], NSSelectorFromString(@"initWithWidth:height:refreshRate:"), width, height, 60.0);
        NSObject *settings = [[settingsClass alloc] init];
        if (!display || !mode) @throw [NSException exceptionWithName:@"CreationFailure" reason:@"CGVirtualDisplay initialization returned nil" userInfo:nil];
        [settings setValue:@[mode] forKey:@"modes"];
        [settings setValue:@(scale == 2) forKey:@"hiDPI"];
        BOOL applied = ((BOOL (*)(id, SEL, id))objc_msgSend)(display, NSSelectorFromString(@"applySettings:"), settings);
        if (!applied || !OCUVirtualDisplayID(display)) @throw [NSException exceptionWithName:@"SettingsFailure" reason:@"Virtual display settings were rejected" userInfo:nil];
        return display;
    } @catch (NSException *exception) {
        if (error) *error = [NSError errorWithDomain:@"OCUVirtualDisplay" code:2 userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: exception.name}];
        return nil;
    }
}

uint32_t OCUVirtualDisplayID(NSObject *display) {
    return ((uint32_t (*)(id, SEL))objc_msgSend)(display, NSSelectorFromString(@"displayID"));
}
