#!/usr/bin/env python3
"""Explicit bounded 1..30-cycle standalone stress test; no per-cycle OCU linkage."""
import argparse, fcntl, json, os, pathlib, stat, subprocess, time
from minimal import read_reply
from run import Experiment, snapshot


def create(experiment, slot):
    lock = pathlib.Path.home() / 'Library/Caches/OpenComputerUse/virtual-display-identity.lock'
    fd = os.open(lock, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    try:
        info = os.fstat(fd)
        if info.st_uid != os.getuid() or not stat.S_ISREG(info.st_mode):
            raise RuntimeError('Invalid identity lock')
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        before = snapshot(experiment.args.probe)
        if any(d['vendor']==0x4f43 for d in before['displays']):
            raise RuntimeError('Another OCU display is online')
        process = subprocess.Popen([experiment.args.helper,str(slot)],stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        experiment.helpers.append(process)
        read_reply(process,'idle')
        reply = None
        for stage in ('descriptor','init','apply'):
            process.stdin.write((stage+'\n').encode());process.stdin.flush()
            reply = read_reply(process,stage)
            if reply['display_id']:
                experiment.helper_displays[process.pid]=reply['display_id']
        if not reply['applied'] or not reply['display_id']:
            raise RuntimeError('Minimal demo failed to apply mode')
        deadline=time.monotonic()+8
        while time.monotonic()<deadline:
            after=snapshot(experiment.args.probe)
            if reply['display_id'] in {d['id'] for d in after['displays']}:break
            time.sleep(.05)
        else:raise RuntimeError('Minimal display never came online')
        experiment.records.append({'name':'create_event','before':before,'after':after,
                                   'reply':reply,'serial':0x4f430000+slot,'timestamp':time.time()})
        experiment.write()
        return process,reply['display_id']
    finally:
        fcntl.flock(fd,fcntl.LOCK_UN);os.close(fd)


def verify_resources(initial, current):
    if current['profiles'] != initial['profiles']:
        raise RuntimeError('ICC count/content changed')
    if current['displays'] != initial['displays']:
        raise RuntimeError('Physical topology changed or virtual display remains')


def run(args):
    if not 1<=args.cycles<=30 or not 0<=args.slot<32:
        raise ValueError('Explicit 1..30 cycles and slot 0..31 required')
    args.seconds=30
    e=Experiment(args); initial=snapshot(args.probe)
    if any(d['vendor']==0x4f43 for d in initial['displays']):
        raise RuntimeError('Another OCU display is online')
    try:
        e.phase('baseline'); e.phase('no-hotplug-control')
        verify_resources(initial,snapshot(args.probe))
        for cycle in range(1,args.cycles+1):
            verify_resources(initial,snapshot(args.probe))
            process,identifier=create(e,args.slot)
            time.sleep(4)
            e.stop(process,identifier)
            stderr=process.stderr.read().decode(errors='replace')
            (e.out/f'helper-{cycle}.stderr').write_text(stderr)
            if process.returncode!=0:raise RuntimeError('Minimal demo exit failed')
            verify_resources(initial,snapshot(args.probe))
            e.records.append({'name':'cycle_complete','cycle':cycle,'exit':process.returncode})
            e.write();print(json.dumps({'completed_cycles':cycle}),flush=True)
            time.sleep(2)
            if cycle%3==0 or cycle==args.cycles:
                e.phase(f'after-{cycle}-cycles')
        for index in range(1,4):e.phase(f'final-passive-{index}')
    except Exception as error:
        e.records.append({'name':'batch_error','error':str(error)});e.write();raise
    finally:
        e.cleanup()


if __name__=='__main__':
    p=argparse.ArgumentParser()
    p.add_argument('--probe',required=True);p.add_argument('--helper',required=True)
    p.add_argument('--output',required=True);p.add_argument('--cycles',required=True,type=int)
    p.add_argument('--slot',required=True,type=int)
    run(p.parse_args())
