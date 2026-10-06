#!/usr/bin/env python3
"""One bounded lifecycle variant batch. Raw diagnostic output stays local."""
import argparse, json, time
from run import Experiment, snapshot


def diagnostics(stderr):
    events = []
    for line in stderr.splitlines():
        try:
            value = json.loads(line)
        except ValueError:
            continue
        if isinstance(value, dict):
            events.append({key: value[key] for key in
                           ('display_dealloc', 'object_released_before_exit', 'display_online_before_exit')
                           if key in value})
    return [event for event in events if event]


def run(args):
    if not 1 <= args.cycles <= 3 or not 0 <= args.slot < 32:
        raise ValueError('At most three cycles and a fixed identity slot are required')
    if not 10 <= args.seconds <= 60 or not 0 <= args.max_baseline_cpu <= 20:
        raise ValueError('Use a 10..60 second window and a 0..20 percent CPU threshold')
    e = Experiment(args)
    initial = snapshot(args.probe)
    if any(d['vendor'] == 0x4f43 for d in initial['displays']):
        raise RuntimeError('Another OCU display is online')
    try:
        baseline = e.phase('baseline')
        if (baseline['cpu']['colorsync.displayservices']['mean'] > args.max_baseline_cpu or
                baseline['cpu']['colorsyncd']['mean'] > args.max_baseline_cpu):
            raise RuntimeError('Baseline above bounded test threshold; no hotplug performed')
        for cycle in range(1, args.cycles + 1):
            if any(d['vendor'] == 0x4f43 for d in snapshot(args.probe)['displays']):
                raise RuntimeError('Another OCU display appeared')
            process, display_id = e.create(0x4f430000 + args.slot)
            time.sleep(4)
            e.stop(process, display_id)
            stderr = process.stderr.read().decode(errors='replace')
            (e.out / f'helper-{cycle}.stderr').write_text(stderr)
            e.records.append({'name': 'lifecycle_diagnostics', 'cycle': cycle,
                              'exit': process.returncode, 'events': diagnostics(stderr)})
            e.write()
            after = snapshot(args.probe)
            if after['profiles'] != initial['profiles']:
                raise RuntimeError('ICC identity/content changed; stop batch')
            if after['displays'] != initial['displays']:
                raise RuntimeError('Physical topology changed; stop batch')
            time.sleep(2)
        e.phase('post-batch')
    except Exception as error:
        e.records.append({'name': 'batch_error', 'error': str(error)})
        e.write()
        raise
    finally:
        e.cleanup()


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--probe', required=True)
    parser.add_argument('--helper', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--slot', required=True, type=int)
    parser.add_argument('--cycles', default=3, type=int)
    parser.add_argument('--seconds', default=20, type=int)
    parser.add_argument('--max-baseline-cpu', default=5, type=float)
    run(parser.parse_args())
