#!/usr/bin/env python3
"""Build experimental source variants outside the repo; never patch production in place."""
import argparse, hashlib, json, pathlib, subprocess

ROOT = pathlib.Path(__file__).resolve().parents[2]


def replace_once(source, old, new):
    if source.count(old) != 1:
        raise ValueError('Production source anchor changed; review variant before testing')
    return source.replace(old, new, 1)


def sources(variant):
    swift = (ROOT / 'apps/VirtualDisplayHost/Sources/main.swift').read_text()
    bridge = (ROOT / 'packages/VirtualDisplayBridge/VirtualDisplayBridge.m').read_text()
    if variant == 'drain':
        swift = replace_once(swift,
            'guard let display = OCUCreateVirtualDisplay(UInt32(width), UInt32(height), UInt32(scale), serial, &creationError) else {',
            'var display: NSObject? = autoreleasepool { OCUCreateVirtualDisplay(UInt32(width), UInt32(height), UInt32(scale), serial, &creationError) }\n    guard display != nil else {')
        swift = replace_once(swift, 'let displayID = OCUVirtualDisplayID(display)',
                             'let displayID = OCUVirtualDisplayID(display!)\n    weak var weakDisplay = display')
        swift = replace_once(swift,
            'withExtendedLifetime(display) {\n        while let command = readLine(), command != "stop" {}\n    }',
            '''while let command = readLine(), command != "stop" {}
    autoreleasepool { display = nil }
    let teardownDeadline = Date(timeIntervalSinceNow: 1)
    while Date() < teardownDeadline {
        _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
    }
    let diagnostics: [String: Any] = ["object_released_before_exit": weakDisplay == nil,
        "display_online_before_exit": CGDisplayIsOnline(displayID) != 0]
    if let data = try? JSONSerialization.data(withJSONObject: diagnostics) {
        FileHandle.standardError.write(data)
        FileHandle.standardError.write(Data([10]))
    }''')
    elif variant == 'primaries':
        anchor = '        NSObject *display = ((id (*)(id, SEL, id))objc_msgSend)'
        insert = '''        // Experimental explicit chromaticities, as used by Chromium's mac test helper.
        // Source: https://chromium.googlesource.com/chromium/src/+/HEAD/ui/display/mac/test/virtual_display_util_mac.mm
        [descriptor setValue:[NSValue valueWithPoint:NSMakePoint(0.6797, 0.3203)] forKey:@"redPrimary"];
        [descriptor setValue:[NSValue valueWithPoint:NSMakePoint(0.2559, 0.6983)] forKey:@"greenPrimary"];
        [descriptor setValue:[NSValue valueWithPoint:NSMakePoint(0.1494, 0.0557)] forKey:@"bluePrimary"];
        [descriptor setValue:[NSValue valueWithPoint:NSMakePoint(0.3125, 0.3291)] forKey:@"whitePoint"];
'''
        bridge = replace_once(bridge, anchor, insert + anchor)
    elif variant != 'current':
        raise ValueError('Unknown variant')
    # Instrument only the helper's private-class dealloc; no CoreGraphics calls in hook.
    hook = '''
#import <objc/runtime.h>
static IMP isolationOriginalDealloc;
static void isolationDealloc(__unsafe_unretained id object, SEL selector) {
    fprintf(stderr, "{\\"display_dealloc\\":\\"begin\\"}\\n"); fflush(stderr);
    ((void (*)(__unsafe_unretained id, SEL))isolationOriginalDealloc)(object, selector);
    fprintf(stderr, "{\\"display_dealloc\\":\\"end\\"}\\n"); fflush(stderr);
}
static void installIsolationHook(Class cls) {
    Method method = class_getInstanceMethod(cls, NSSelectorFromString(@"dealloc"));
    if (!method) return;
    isolationOriginalDealloc = method_getImplementation(method);
    class_replaceMethod(cls, NSSelectorFromString(@"dealloc"), (IMP)isolationDealloc, method_getTypeEncoding(method));
}
'''
    bridge = replace_once(bridge, '#import <objc/message.h>', '#import <objc/message.h>\n' + hook)
    bridge = replace_once(bridge, '    @try {', '    installIsolationHook(displayClass);\n    @try {')
    return swift, bridge


def build(args):
    folder = pathlib.Path(args.output).resolve() / args.variant
    folder.mkdir(parents=True, exist_ok=False)
    swift, bridge = sources(args.variant)
    (folder / 'Host').mkdir(); (folder / 'Bridge/include').mkdir(parents=True)
    (folder / 'Host/main.swift').write_text(swift)
    (folder / 'Bridge/VirtualDisplayBridge.m').write_text(bridge)
    header = ROOT / 'packages/VirtualDisplayBridge/include/VirtualDisplayBridge.h'
    (folder / 'Bridge/include/VirtualDisplayBridge.h').write_text(header.read_text())
    (folder / 'Package.swift').write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "DisplayIsolation", platforms: [.macOS(.v14)],
    products: [.executable(name: "IsolationHost", targets: ["IsolationHost"])], targets: [
    .target(name: "VirtualDisplayBridge", path: "Bridge", publicHeadersPath: "include", linkerSettings: [.linkedFramework("CoreGraphics")]),
    .executableTarget(name: "IsolationHost", dependencies: ["VirtualDisplayBridge"], path: "Host")])
''')
    subprocess.run(['swift', 'build', '--package-path', str(folder), '--product', 'IsolationHost'], check=True)
    binary_dir = subprocess.check_output(['swift', 'build', '--package-path', str(folder), '--show-bin-path'], text=True).strip()
    binary = pathlib.Path(binary_dir) / 'IsolationHost'
    if args.sign:
        subprocess.run(['codesign', '--force', '--options', 'runtime', '--timestamp', '--sign', args.sign, str(binary)], check=True)
        subprocess.run(['codesign', '--verify', '--strict', str(binary)], check=True)
    manifest = {'variant': args.variant, 'source_head': subprocess.check_output(['git','rev-parse','HEAD'], cwd=ROOT, text=True).strip(),
                'swift_sha256': hashlib.sha256(swift.encode()).hexdigest(), 'bridge_sha256': hashlib.sha256(bridge.encode()).hexdigest(),
                'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(), 'binary': str(binary)}
    (folder / 'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
    print(json.dumps({'variant': args.variant, 'binary': str(binary)}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--variant', choices=['current','drain','primaries'], required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--sign')
    build(parser.parse_args())
