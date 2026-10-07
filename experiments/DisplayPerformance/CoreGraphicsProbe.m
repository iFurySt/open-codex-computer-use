// Read-only enumeration; no AppKit, capture framework, Metal or permission API.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
int main(int argc, const char **argv) {
    if (argc != 2 || strcmp(argv[1], "list")) return 2;
    @autoreleasepool {
        CGDirectDisplayID identifiers[64];uint32_t count=0;
        if (CGGetOnlineDisplayList(64, identifiers, &count)!=kCGErrorSuccess) return 3;
        NSMutableArray *displays=[NSMutableArray array];
        for (uint32_t index=0;index<count;index++) {
            uint32_t identifier=identifiers[index];CGRect frame=CGDisplayBounds(identifier);
            [displays addObject:@{@"id":@(identifier),@"serial":@(CGDisplaySerialNumber(identifier)),
                @"vendor":@(CGDisplayVendorNumber(identifier)),@"main":@(identifier==CGMainDisplayID()),
                @"uuid":[NSNull null],@"frame":@{@"x":@(frame.origin.x),@"y":@(frame.origin.y),
                @"width":@(frame.size.width),@"height":@(frame.size.height)}}];
        }
        NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"displays":displays} options:0 error:nil];
        fwrite(data.bytes,1,data.length,stdout);fputc('\n',stdout);
    }
    return 0;
}
