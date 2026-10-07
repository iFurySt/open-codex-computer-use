#!/usr/bin/env python3
"""Build one external standalone candidate. Original source stays unchanged."""
import argparse, hashlib, json, pathlib, subprocess
from build_isolation import ROOT, replace_once


def source(variant):
    original=(ROOT/'experiments/DisplayPerformance/MinimalDisplay.m').read_text()
    if variant=='global':
        return replace_once(original,'dispatch_queue_create("display.minimal", DISPATCH_QUEUE_SERIAL)',
                            'dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0)')
    if variant=='typed':
        declarations='''// Typed init signatures audit ARC init-family ownership and integer ABI.
@interface OCUPrivateDisplaySignature : NSObject
- (instancetype)initWithDescriptor:(id)descriptor;
@end
@interface OCUPrivateModeSignature : NSObject
- (instancetype)initWithWidth:(unsigned int)width height:(unsigned int)height refreshRate:(double)rate;
@end
'''
        result=replace_once(original,'static void emit(',declarations+'\nstatic void emit(')
        result=replace_once(result,'((id (*)(id, SEL, id))objc_msgSend)([displayClass alloc], NSSelectorFromString(@"initWithDescriptor:"), descriptor)',
                            '[(OCUPrivateDisplaySignature *)[displayClass alloc] initWithDescriptor:descriptor]')
        return replace_once(result,'((id (*)(id, SEL, NSUInteger, NSUInteger, double))objc_msgSend)([modeClass alloc], NSSelectorFromString(@"initWithWidth:height:refreshRate:"), 1920, 1080, 60.0)',
                            '[(OCUPrivateModeSignature *)[modeClass alloc] initWithWidth:1920 height:1080 refreshRate:60.0]')
    raise ValueError('Unknown source variant')


def build(args):
    folder=pathlib.Path(args.output).resolve()/args.variant;folder.mkdir(parents=True,exist_ok=False)
    text=source(args.variant);path=folder/'MinimalDisplay.m';path.write_text(text);binary=folder/'MinimalDisplay'
    subprocess.run(['clang','-fobjc-arc','-O0','-Wall','-Wextra','-framework','Foundation','-framework','CoreGraphics',str(path),'-o',str(binary)],check=True)
    if args.sign:
        subprocess.run(['codesign','--force','--options','runtime','--timestamp','--sign',args.sign,str(binary)],check=True)
        subprocess.run(['codesign','--verify','--strict',str(binary)],check=True)
    manifest={'variant':args.variant,'source_sha256':hashlib.sha256(text.encode()).hexdigest(),
              'binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),'binary':str(binary),
              'source_head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()}
    (folder/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n');print(json.dumps(manifest))


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--variant',choices=['global','typed'],required=True)
    p.add_argument('--output',required=True);p.add_argument('--sign');build(p.parse_args())
