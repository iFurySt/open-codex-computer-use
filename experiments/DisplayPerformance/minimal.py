#!/usr/bin/env python3
"""Staged single-cycle standalone reproducer. Measurements are passive between calls."""
import argparse, fcntl, json, os, pathlib, select, stat, subprocess, time
from run import Experiment, snapshot


def read_reply(process, expected, seconds=15):
    line = b''
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if select.select([process.stdout], [], [], .1)[0]:
            byte = os.read(process.stdout.fileno(), 1)
            if not byte:
                raise RuntimeError('Standalone demo exited before acknowledgement')
            if byte == b'\n':
                result = json.loads(line)
                if result.get('stage') != expected:
                    raise RuntimeError('Unexpected standalone stage')
                return result
            line += byte
            if len(line) > 4096:
                raise RuntimeError('Oversized standalone acknowledgement')
    raise RuntimeError('Standalone stage timed out')


def run(args):
    if not 0 <= args.slot < 32 or not 10 <= args.seconds <= 60:
        raise ValueError('Fixed slot 0..31 and 10..60 seconds required')
    e = Experiment(args)
    initial = snapshot(args.probe)
    if any(d['vendor'] == 0x4f43 for d in initial['displays']):
        raise RuntimeError('Other OCU display online')
    process = None
    fd = None
    try:
        baseline = e.phase('baseline')
        if sum(baseline['cpu'][k]['mean'] for k in ('colorsync.displayservices', 'colorsyncd')) > 20:
            raise RuntimeError('Combined ColorSync baseline above 20%; no creation')
        process = subprocess.Popen([args.helper, str(args.slot)], stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        e.helpers.append(process)
        read_reply(process, 'idle')
        stages = ['descriptor', 'init'] + (['apply'] if args.apply else [])
        for stage in stages:
            if stage == 'init':
                lock = pathlib.Path.home() / 'Library/Caches/OpenComputerUse/virtual-display-identity.lock'
                fd = os.open(lock, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
                info = os.fstat(fd)
                if info.st_uid != os.getuid() or not stat.S_ISREG(info.st_mode):
                    raise RuntimeError('Invalid identity lock')
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                if any(d['serial'] == 0x4f430000 + args.slot for d in snapshot(args.probe)['displays']):
                    raise RuntimeError('Requested identity occupied')
            process.stdin.write((stage+'\n').encode()); process.stdin.flush()
            reply = read_reply(process, stage)
            if reply['display_id']:
                e.helper_displays[process.pid] = reply['display_id']
            e.records.append({'name':'stage_reply', 'reply':reply})
            e.write()
            # Once online, ordinary production allocation can see this identity.
            online = snapshot(args.probe)
            if fd is not None and any(d['id'] == reply['display_id'] for d in online['displays']):
                fcntl.flock(fd, fcntl.LOCK_UN); os.close(fd); fd = None
            r = e.phase(stage)
            if len(r['after']['profiles']) != len(initial['profiles']):
                raise RuntimeError('ICC count changed; abort single cycle')
            own_id = reply['display_id']
            physical = [d for d in r['after']['displays'] if d['id'] != own_id]
            if physical != initial['displays']:
                raise RuntimeError('Physical topology changed')
            if sum(r['cpu'][k]['mean'] for k in ('colorsync.displayservices', 'colorsyncd')) > 25:
                raise RuntimeError('Combined ColorSync above 25%; stop')
        process.stdin.write(b'stop\n');process.stdin.flush();process.stdin.close();process.wait(timeout=8)
        e.cleanup()
        if fd is not None:
            fcntl.flock(fd, fcntl.LOCK_UN); os.close(fd); fd = None
        e.phase('after-exit')
    except Exception as error:
        e.records.append({'name':'batch_error','error':str(error)});e.write()
        raise
    finally:
        if fd is not None:
            fcntl.flock(fd, fcntl.LOCK_UN); os.close(fd)
        if process is not None:
            e.cleanup()
            if process.poll() is not None:
                (e.out/'demo.stderr').write_bytes(process.stderr.read())


if __name__ == '__main__':
    p=argparse.ArgumentParser()
    p.add_argument('--probe',required=True);p.add_argument('--helper',required=True)
    p.add_argument('--output',required=True);p.add_argument('--slot',required=True,type=int)
    p.add_argument('--seconds',default=20,type=int);p.add_argument('--apply',action='store_true')
    run(p.parse_args())
