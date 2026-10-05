#!/usr/bin/env python3
"""Attended lid-backend smoke: no forced sleep or session unlock; restores on exit."""
import argparse,json,pathlib,subprocess,time,os,signal
p=argparse.ArgumentParser();p.add_argument('--app',required=True);p.add_argument('--seconds',type=int,default=8)
a=p.parse_args()
if not 1<=a.seconds<=60:raise SystemExit('--seconds must be 1...60')
app=pathlib.Path(a.app).resolve();binary=app/'Contents/MacOS/OCUPowerHost'
def call(*args):return json.loads(subprocess.check_output([str(binary),*args],text=True,timeout=15))
def until(check,seconds=10):
    deadline=time.monotonic()+seconds
    while time.monotonic()<deadline:
        if check():return
        time.sleep(.2)
    raise AssertionError('Expected restoration/state was not observed')
doctor=call('doctor')
if not doctor.get('developer_id_valid') or doctor.get('registration_status')!=1 or doctor.get('helper_confirmed') is not False:
    raise SystemExit('Signed, approved helper and initial SleepDisabled=0 are required. Run doctor/install first.')
if doctor['coordinator_running']:raise SystemExit('Stop existing coordinator before this isolated test.')
hold=None
try:
    hold=call('acquire','--options',json.dumps({'prevent_lid_sleep':True,'lifetime':'timed','seconds':a.seconds}))
    status=call('status',hold['id']);assert status['confirmed']['lid'] and status['lid_state_known']
    assert call('doctor')['sleep_disabled'] is True
    until(lambda: call('status',hold['id'])['holds'][0]['phase']=='ended',a.seconds+10)
    until(lambda: call('doctor')['sleep_disabled'] is False)
    call('release',hold['id']);hold=None
    # Kill only the coordinator identified by ownership of this user's socket.
    hold=call('acquire','--options',json.dumps({'prevent_lid_sleep':True}))
    before=call('doctor');assert before['sleep_disabled'] is True
    suffix='.dev' if app.name.endswith('(Dev).app') else ''
    path=f'/tmp/ocu-power-{os.getuid()}{suffix}/control.sock'
    raw=subprocess.check_output(['/usr/sbin/lsof','-t','-a','-u',str(os.getuid()),path],text=True)
    pids=set(int(x) for x in raw.split())
    if len(pids)!=1:raise AssertionError('Cannot unambiguously identify this smoke coordinator')
    pid=pids.pop()
    # Verify process executable identity before sending any signal.
    command=subprocess.check_output(['/bin/ps','-p',str(pid),'-o','command='],text=True).strip()
    if not command.startswith(str(binary)+' serve'):raise AssertionError('Coordinator identity did not match this test app')
    os.kill(pid,signal.SIGKILL);hold=None
    until(lambda: call('doctor')['sleep_disabled'] is False,40)
    print('PASS: real lid override, timed restoration and coordinator crash restoration (no physical lid closure)')
finally:
    if hold:
        try:call('release',hold['id'])
        except Exception:pass
    try:call('shutdown')
    except Exception:pass
    if call('doctor').get('sleep_disabled'):
        raise SystemExit('Restoration not confirmed; keep helper installed and inspect doctor before continuing.')
