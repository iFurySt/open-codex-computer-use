#!/usr/bin/env python3
"""One configured display held across passive windows, then safely removed."""
import argparse, time
from minimal_cycles import create, verify_resources
from run import Experiment, snapshot


def run(args):
    if not 0<=args.slot<32 or not 1<=args.windows<=3:
        raise ValueError('Slot 0..31 and 1..3 windows required')
    args.seconds=20;e=Experiment(args);initial=snapshot(args.probe)
    if any(d['vendor']==0x4f43 for d in initial['displays']):raise RuntimeError('Other OCU display online')
    process=None
    try:
        baseline=e.phase('baseline')
        if sum(baseline['cpu'][k]['mean'] for k in ('colorsync.displayservices','colorsyncd'))>12:
            raise RuntimeError('Baseline above 12%; no creation')
        process,identifier=create(e,args.slot)
        for index in range(1,args.windows+1):
            r=e.phase(f'held-{index}')
            current=r['after']
            verify_resources(initial,dict(current,displays=[d for d in current['displays'] if d['id']!=identifier]))
            if identifier not in {d['id'] for d in current['displays']}:raise RuntimeError('Own held display disappeared')
            if sum(r['cpu'][k]['mean'] for k in ('colorsync.displayservices','colorsyncd'))>25:
                raise RuntimeError('Held CPU above 25%; stop')
        e.stop(process,identifier)
        if process.returncode!=0:raise RuntimeError('Demo exit failed')
        verify_resources(initial,snapshot(args.probe))
        e.phase('after-exit')
    except Exception as error:
        e.records.append({'name':'batch_error','error':str(error)});e.write();raise
    finally:
        e.cleanup()
        if process is not None and process.poll() is not None:
            (e.out/'demo.stderr').write_bytes(process.stderr.read())


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--probe',required=True);p.add_argument('--helper',required=True)
    p.add_argument('--output',required=True);p.add_argument('--slot',required=True,type=int)
    p.add_argument('--windows',default=1,type=int);run(p.parse_args())
