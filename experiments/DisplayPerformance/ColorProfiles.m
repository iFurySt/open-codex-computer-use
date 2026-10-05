#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ColorSync/ColorSync.h>

// Read-only profile inspection; never sets custom profiles or registers devices.
static NSString *fileName(id value) {
    return [value isKindOfClass:NSURL.class] ? [(NSURL *)value lastPathComponent] : nil;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        int repeats = argc == 3 && strcmp(argv[1], "--repeat") == 0 ? atoi(argv[2]) : 1;
        if (repeats < 1 || repeats > 16) return 2;
        CGDirectDisplayID displays[64]; uint32_t count = 0;
        if (CGGetOnlineDisplayList(64, displays, &count) != kCGErrorSuccess) return 1;
        NSMutableArray *result = [NSMutableArray array];
        for (int pass = 0; pass < repeats; pass++) {
        for (uint32_t i = 0; i < count; i++) {
            CFUUIDRef uuid = CGDisplayCreateUUIDFromDisplayID(displays[i]);
            double started = NSProcessInfo.processInfo.systemUptime;
            CFDictionaryRef raw = uuid ? ColorSyncDeviceCopyDeviceInfo(kColorSyncDisplayDeviceClass, uuid) : NULL;
            double deviceInfoMs = (NSProcessInfo.processInfo.systemUptime - started) * 1000;
            NSDictionary *info = (__bridge NSDictionary *)raw;
            NSDictionary *factory = info[(__bridge NSString *)kColorSyncFactoryProfiles];
            NSDictionary *custom = info[(__bridge NSString *)kColorSyncCustomProfiles];
            NSMutableArray *factoryFiles = [NSMutableArray array], *customFiles = [NSMutableArray array];
            for (id entry in factory.allValues) {
                if (![entry isKindOfClass:NSDictionary.class]) continue;
                NSString *name = fileName(entry[(__bridge NSString *)kColorSyncDeviceProfileURL]);
                if (name) [factoryFiles addObject:name];
            }
            for (id entry in custom.allValues) {
                NSString *name = fileName(entry);
                if (name) [customFiles addObject:name];
            }
            started = NSProcessInfo.processInfo.systemUptime;
            ColorSyncProfileRef profile = ColorSyncProfileCreateWithDisplayID(displays[i]);
            double profileMs = (NSProcessInfo.processInfo.systemUptime - started) * 1000;
            CFErrorRef errors = NULL, warnings = NULL;
            BOOL usable = profile && ColorSyncProfileVerify(profile, &errors, &warnings);
            CFStringRef description = profile ? ColorSyncProfileCopyDescriptionString(profile) : NULL;
            NSString *currentFile = profile ? fileName((__bridge id)ColorSyncProfileGetURL(profile, NULL)) : nil;
            [result addObject:@{
                @"display_id": @(displays[i]), @"device_info_available": @(raw != NULL),
                @"device_info_query_ms": @(deviceInfoMs), @"profile_query_ms": @(profileMs),
                @"factory_files": factoryFiles, @"custom_files": customFiles,
                @"current_file": currentFile ?: NSNull.null,
                @"current_description": (__bridge NSString *)description ?: NSNull.null,
                @"profile_usable": @(usable), @"verify_error_code": errors ? @(CFErrorGetCode(errors)) : NSNull.null,
                @"verify_warning_code": warnings ? @(CFErrorGetCode(warnings)) : NSNull.null,
                @"current_matches_factory_file": @(currentFile && [factoryFiles containsObject:currentFile])
            }];
            if (description) CFRelease(description);
            if (errors) CFRelease(errors);
            if (warnings) CFRelease(warnings);
            if (profile) CFRelease(profile);
            if (raw) CFRelease(raw);
            if (uuid) CFRelease(uuid);
        }
        }
        // An explicit flag checks OCU files only, without printing UUID filenames.
        if (argc == 2 && strcmp(argv[1], "--verify-ocu-files") == 0) {
            NSString *directory = @"/Library/ColorSync/Profiles/Displays";
            NSArray *files = [NSFileManager.defaultManager contentsOfDirectoryAtPath:directory error:nil];
            NSUInteger checked = 0, failed = 0, warned = 0;
            for (NSString *name in files) {
                if (![name hasPrefix:@"Open Computer Use Virtual Display-"] || ![name hasSuffix:@".icc"]) continue;
                NSURL *url = [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:name]];
                CFErrorRef errors = NULL, warnings = NULL;
                ColorSyncProfileRef profile = ColorSyncProfileCreateWithURL((__bridge CFURLRef)url, &errors);
                if (profile) {
                    if (errors) { CFRelease(errors); errors = NULL; }
                    if (!ColorSyncProfileVerify(profile, &errors, &warnings)) failed++;
                } else failed++;
                checked++; if (warnings) warned++;
                if (profile) CFRelease(profile);
                if (errors) CFRelease(errors);
                if (warnings) CFRelease(warnings);
            }
            [result addObject:@{@"ocu_files_checked": @(checked), @"ocu_files_failed": @(failed), @"ocu_files_warned": @(warned)}];
        }
        NSData *data = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil];
        if (!data) return 1;
        fwrite(data.bytes, 1, data.length, stdout); fputc('\n', stdout);
    }
    return 0;
}
