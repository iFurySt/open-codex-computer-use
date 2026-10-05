#!/usr/bin/env python3
"""Read-only native sensors, isolated SQLite; never acquires a power hold."""
import json,pathlib,subprocess,tempfile,time
root=pathlib.Path(__file__).resolve().parents[1]
package=root/'packages/OpenComputerUsePower'
subprocess.run(['swift','build','--package-path',str(package),'--product','OCUPowerHost'],check=True)
binary=pathlib.Path(subprocess.check_output(['swift','build','--package-path',str(package),'--show-bin-path'],text=True).strip())/'OCUPowerHost'
def call(*args):return json.loads(subprocess.check_output([str(binary),*args],text=True,timeout=15))
def until(check):
    end=time.monotonic()+10
    while time.monotonic()<end:
        if check():return
        time.sleep(.2)
    raise AssertionError('Metrics smoke timed out')
if subprocess.run([str(binary),'status'],capture_output=True,timeout=15).returncode==0:
    raise SystemExit('Existing coordinator: refusing to replace it')
with tempfile.TemporaryDirectory() as temporary, tempfile.TemporaryFile() as log:
    database=pathlib.Path(temporary)/'data/metrics.sqlite3'
    def launch():return subprocess.Popen([str(binary),'serve','--metrics-path',str(database)],stdout=log,stderr=log)
    host=launch()
    try:
        until(lambda: subprocess.run([str(binary),'status'],capture_output=True,timeout=15).returncode==0)
        until(lambda: bool(call('metrics')['samples']))
        first=call('metrics')['samples'][-1]
        assert first['active_holds']==0 and not any(first['confirmed'].values())
        for key in ['system_power_watts','battery_net_power_watts']:
            assert key in first['readings']
        call('metrics-configure',json.dumps({'enabled':True,'interval_seconds':1,'retention_seconds':60}))
        until(lambda: len(call('metrics')['samples'])>=3)
        limited=call('metrics','--query',json.dumps({'limit':1}))
        assert limited['truncated'] and len(limited['samples'])==1
        call('metrics-configure',json.dumps({'enabled':False,'interval_seconds':1,'retention_seconds':60}))
        count=len(call('metrics')['samples']);time.sleep(2)
        assert len(call('metrics')['samples'])==count
        call('shutdown');host.wait(timeout=5)
        host=launch()
        until(lambda: subprocess.run([str(binary),'status'],capture_output=True,timeout=15).returncode==0)
        reopened=call('metrics')
        assert not reopened['configuration']['enabled'] and len(reopened['samples'])==count
        assert database.stat().st_mode & 0o077==0
        call('metrics-clear');assert call('metrics')['samples']==[]
        call('shutdown');host.wait(timeout=5)
        print('PASS: native sensors, no holds, SQLite persistence, bounds, disable/restart and clear')
        print(json.dumps({'power_readings':{k:first['readings'][k] for k in ['system_power_watts','battery_net_power_watts']}}))
    finally:
        if host.poll() is None:
            host.terminate()
            try:host.wait(timeout=5)
            except subprocess.TimeoutExpired:host.kill();host.wait()
        log.seek(0);diagnostic=log.read().decode(errors='replace')
        if diagnostic:print(diagnostic.strip())
