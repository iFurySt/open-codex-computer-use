// Standalone private-API reproducer. No OCU library, AppKit application, AX or capture.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/message.h>
#import <dispatch/dispatch.h>
#include <stdio.h>

static void emit(NSString *stage, NSObject *display, BOOL applied) {
    uint32_t identifier = display ? ((uint32_t (*)(id, SEL))objc_msgSend)(display, NSSelectorFromString(@"displayID")) : 0;
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"stage":stage, @"display_id":@(identifier), @"applied":@(applied)} options:0 error:nil];
    fwrite(data.bytes, 1, data.length, stdout); fputc('\n', stdout); fflush(stdout);
}

int main(int argc, const char **argv) {
    // Use an already-warmed OCU slot, never a random identity. Controller owns allocation lock.
    if (argc != 2) return 2;
    char *end = NULL;
    unsigned long slot = strtoul(argv[1], &end, 10);
    if (!*argv[1] || *end || slot >= 32) return 2;
    @autoreleasepool {
        Class descriptorClass = NSClassFromString(@"CGVirtualDisplayDescriptor");
        Class displayClass = NSClassFromString(@"CGVirtualDisplay");
        Class modeClass = NSClassFromString(@"CGVirtualDisplayMode");
        Class settingsClass = NSClassFromString(@"CGVirtualDisplaySettings");
        if (!descriptorClass || !displayClass || !modeClass || !settingsClass) return 3;
        NSObject *descriptor = nil, *display = nil;
        BOOL applied = NO;
        char command[32];
        emit(@"idle", nil, NO);
        @try {
            while (fgets(command, sizeof(command), stdin)) {
                if (!strcmp(command, "descriptor\n") && !descriptor) {
                    descriptor = [[descriptorClass alloc] init];
                    [descriptor setValue:@"Open Computer Use Virtual Display" forKey:@"name"];
                    [descriptor setValue:dispatch_queue_create("display.minimal", DISPATCH_QUEUE_SERIAL) forKey:@"queue"];
                    [descriptor setValue:@1920 forKey:@"maxPixelsWide"];
                    [descriptor setValue:@1080 forKey:@"maxPixelsHigh"];
                    [descriptor setValue:@0x4f43 forKey:@"vendorID"];
                    [descriptor setValue:@1 forKey:@"productID"];
                    [descriptor setValue:@(0x4f430000 + slot) forKey:@"serialNum"];
                    [descriptor setValue:[NSValue valueWithSize:NSMakeSize(1920 * 25.4 / 110, 1080 * 25.4 / 110)] forKey:@"sizeInMillimeters"];
                    emit(@"descriptor", nil, NO);
                } else if (!strcmp(command, "init\n") && descriptor && !display) {
                    display = ((id (*)(id, SEL, id))objc_msgSend)([displayClass alloc], NSSelectorFromString(@"initWithDescriptor:"), descriptor);
                    if (!display) return 4;
                    emit(@"init", display, NO);
                } else if (!strcmp(command, "apply\n") && display && !applied) {
                    NSObject *mode = ((id (*)(id, SEL, NSUInteger, NSUInteger, double))objc_msgSend)([modeClass alloc], NSSelectorFromString(@"initWithWidth:height:refreshRate:"), 1920, 1080, 60.0);
                    NSObject *settings = [[settingsClass alloc] init];
                    if (!mode) return 5;
                    [settings setValue:@[mode] forKey:@"modes"];
                    [settings setValue:@NO forKey:@"hiDPI"];
                    applied = ((BOOL (*)(id, SEL, id))objc_msgSend)(display, NSSelectorFromString(@"applySettings:"), settings);
                    if (!applied) return 6;
                    emit(@"apply", display, YES);
                } else if (!strcmp(command, "stop\n")) {
                    break;
                } else {
                    return 7;
                }
            }
            // ARC + autoreleasepool release the private object; controller verifies actual removal.
            display = nil;
            descriptor = nil;
        } @catch (NSException *exception) {
            fprintf(stderr, "%s\n", exception.reason.UTF8String);
            return 8;
        }
    }
    return 0;
}
