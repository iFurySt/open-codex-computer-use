#!/usr/bin/env python3
"""Validate signed host policy without registering services or changing power settings."""
import pathlib,subprocess,re,os,tempfile,shutil,plistlib,json
root=pathlib.Path(__file__).resolve().parents[1]
identities=subprocess.check_output(['security','find-identity','-v','-p','codesigning'],text=True)
match=re.search(r'"(Developer ID Application: [^\"]+)"',identities)
if not match:raise SystemExit('Developer ID identity required for signing tests')
env=os.environ.copy();env['OPEN_COMPUTER_USE_CODESIGN_IDENTITY']=match.group(1)
build=subprocess.run([str(root/'scripts/build-power-hold-app.sh'),'debug'],env=env,capture_output=True,text=True)
if build.returncode:raise SystemExit(build.stderr)
app=root/'dist/power-hold/debug/Open Computer Use Power (Dev).app'
def valid(candidate):
    result=json.loads(subprocess.check_output([str(candidate/'Contents/MacOS/OCUPowerHost'),'doctor'],text=True,timeout=20))
    return result['developer_id_valid']
assert valid(app), 'Production policy should accept the signed dev host'
with tempfile.TemporaryDirectory(prefix='ocu-power-signing-') as temp:
    temp=pathlib.Path(temp)
    debug=temp/'Injectable.app';shutil.copytree(app,debug)
    ent=temp/'debug.plist';ent.write_bytes(plistlib.dumps({'com.apple.security.get-task-allow':True}))
    subprocess.run(['codesign','--force','--options','runtime','--sign',match.group(1),'--entitlements',str(ent),str(debug)],check=True,capture_output=True)
    assert not valid(debug), 'Debug-injectable host must be rejected'
    wrong=temp/'WrongRole.app';shutil.copytree(app,wrong)
    info=wrong/'Contents/Info.plist';data=plistlib.loads(info.read_bytes());data['CFBundleIdentifier']='com.opencomputeruse.power.other';info.write_bytes(plistlib.dumps(data))
    subprocess.run(['codesign','--force','--options','runtime','--sign',match.group(1),str(wrong)],check=True,capture_output=True)
    assert not valid(wrong), 'Same-signer wrong role must be rejected'
print('PASS: Developer ID host accepted; injectable and wrong-role hosts rejected')
