#!/usr/bin/env python3
"""Real ordinary assertions and cross-process lifecycle; never changes disablesleep."""
import argparse,json,pathlib,subprocess,time,signal,tempfile,os
p=argparse.ArgumentParser();p.add_argument('--binary');a=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[1]
if a.binary:
    binary=pathlib.Path(a.binary)
else:
    package=root/'packages/OpenComputerUsePower'
    subprocess.run(['swift','build','--package-path',str(package),'--product','OCUPowerHost'],check=True)
    binary=pathlib.Path(subprocess.check_output(['swift','build','--package-path',str(package),'--show-bin-path'],text=True).strip())/'OCUPowerHost'
def call(*args):
    return json.loads(subprocess.check_output([str(binary),*args],text=True,timeout=15))
def status(hold):return call('status',hold['id'])['holds'][0]
def until(check):
    deadline=time.monotonic()+8
    while time.monotonic()<deadline:
        if check():return
        time.sleep(.1)
    raise AssertionError('Timed out waiting for expected power state')
# Do not take over any manually started coordinator.
probe=subprocess.run([str(binary),'status'],capture_output=True,text=True,timeout=15)
if probe.returncode==0:raise SystemExit('An existing coordinator is running. Shut it down before this isolated smoke.')
with tempfile.TemporaryFile() as log:
    host=subprocess.Popen([str(binary),'serve'],stdout=log,stderr=log)
    try:
        until(lambda: subprocess.run([str(binary),'status'],capture_output=True,timeout=15).returncode==0)
        manual=call('acquire')
        assert status(manual)['phase']=='active'
        assertions=subprocess.check_output(['pmset','-g','assertions'],text=True)
        assert 'Open Computer Use explicit power hold' in assertions
        timed=call('acquire','--options',json.dumps({'lifetime':'timed','seconds':1}))
        until(lambda: status(timed)['phase']=='ended')
        assert status(manual)['phase']=='active'
        run=subprocess.Popen([str(binary),'run','--','/bin/sleep','30'],stdout=subprocess.PIPE,text=True,start_new_session=True)
        until(lambda: len([h for h in call('status')['holds'] if h['phase']=='active'])==2)
        run.kill();run.wait(timeout=5)
        try:os.killpg(run.pid,signal.SIGTERM)
        except ProcessLookupError:pass
        until(lambda: len([h for h in call('status')['holds'] if h['phase']=='active'])==1)
        call('release',manual['id']); assert not call('status')['confirmed']['idle']
        crash=call('acquire'); assert status(crash)['phase']=='active'
        host.kill();host.wait(timeout=5)
        until(lambda: 'Open Computer Use explicit power hold' not in subprocess.check_output(['pmset','-g','assertions'],text=True))
        host=subprocess.Popen([str(binary),'serve'],stdout=log,stderr=log)
        until(lambda: subprocess.run([str(binary),'status'],capture_output=True,timeout=15).returncode==0)
        assert call('status')['holds']==[]
        call('shutdown'); host.wait(timeout=5)
        print('PASS: real assertions, manual persistence, timer, connection death, crash cleanup and restart')
    finally:
        if host.poll() is None:
            host.terminate()
            try:host.wait(timeout=5)
            except subprocess.TimeoutExpired:host.kill();host.wait()
        log.seek(0)
        diagnostic=log.read().decode(errors='replace')
        if diagnostic:print(diagnostic.strip())
