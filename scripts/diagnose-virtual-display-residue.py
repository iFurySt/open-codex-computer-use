#!/usr/bin/env python3
"""Read-only macOS virtual-display residue summary. Never modifies system state."""
import collections
import ctypes
import json
import pathlib
import plistlib
import subprocess
import sys


def main():
    if sys.platform != 'darwin':
        raise SystemExit('This diagnostic is macOS-only')
    report = {'read_only': True, 'profiles': [], 'windowserver_preferences': [], 'errors': []}
    roots = [pathlib.Path('/Library/ColorSync/Profiles/Displays'),
             pathlib.Path.home() / 'Library/ColorSync/Profiles']
    for root in roots:
        matches = []
        try:
            for path in root.rglob('Open Computer Use Virtual Display-*.icc'):
                # Confirm profile payload as well as name; never classify physical profiles by vendor alone.
                data = path.read_bytes()
                if b'Open Computer Use' in data or 'Open Computer Use'.encode('utf-16-be') in data:
                    matches.append(path)
            report['profiles'].append({'scope': 'system' if root.is_relative_to('/Library') else 'user',
                                       'ocu_count': len(matches),
                                       'bytes': sum(path.stat().st_size for path in matches)})
        except (OSError, ValueError) as error:
            report['errors'].append(str(error))
    for path in (pathlib.Path.home() / 'Library/Preferences/ByHost').glob('com.apple.windowserver.displays*.plist'):
        try:
            value = plistlib.loads(path.read_bytes())
            uuids, counts = set(), collections.Counter()
            def walk(item):
                if isinstance(item, dict):
                    for key, child in item.items():
                        counts[key] += 1
                        if 'uuid' in key.lower() and isinstance(child, str):
                            uuids.add(child)
                        walk(child)
                elif isinstance(item, list):
                    for child in item:
                        walk(child)
            walk(value)
            report['windowserver_preferences'].append({'bytes': path.stat().st_size,
                'distinct_uuid_values': len(uuids), 'display_uuid_entries': counts['UUID'],
                'ownership': 'mixed; counts cannot be attributed solely to OCU'})
        except (OSError, ValueError, plistlib.InvalidFileException) as error:
            report['errors'].append(str(error))
    try:
        cg = ctypes.CDLL('/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics')
        cg.CGDisplayVendorNumber.restype = ctypes.c_uint32
        cg.CGDisplaySerialNumber.restype = ctypes.c_uint32
        ids = (ctypes.c_uint32 * 64)()
        count = ctypes.c_uint32()
        cg.CGGetOnlineDisplayList.argtypes = [ctypes.c_uint32, ctypes.POINTER(ctypes.c_uint32), ctypes.POINTER(ctypes.c_uint32)]
        status = cg.CGGetOnlineDisplayList(64, ids, ctypes.byref(count))
        if status:
            raise RuntimeError(f'CGGetOnlineDisplayList failed: {status}')
        report['online_displays'] = [{'id': int(display), 'ocu_vendor': cg.CGDisplayVendorNumber(display) == 0x4f43,
            'serial': cg.CGDisplaySerialNumber(display)} for display in ids[:count.value]]
    except (OSError, RuntimeError) as error:
        report['errors'].append(str(error))
    process_lines = subprocess.run(['ps', '-axo', 'pid,pcpu,comm'], text=True, capture_output=True, check=True).stdout.splitlines()
    report['processes'] = [line.strip() for line in process_lines if any(name in line for name in
        ('colorsync.displayservices', '/colorsyncd', '/WindowServer', '/VirtualDisplayHost'))]
    print(json.dumps(report, indent=2, ensure_ascii=False))


if __name__ == '__main__':
    main()
