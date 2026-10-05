#!/usr/bin/env python3
"""One bounded warm-identity batch; subjective assessment happens between runs."""
import argparse
import json
import pathlib
import threading
import time

from run import Experiment, ROLES, cpu_times, log_counts, snapshot


def run_batch(args):
    if not 1 <= args.cycles <= 3:
        raise ValueError('Each batch is limited to 1..3 cycles')
    if not 0 <= args.slot < 32:
        raise ValueError('Use a bounded production identity slot')
    args.seconds = 30
    experiment = Experiment(args)
    before = snapshot(args.probe)
    if any(d['vendor'] == 0x4f43 for d in before['displays']):
        raise RuntimeError('Another OCU virtual display is online; coordinate the test window')
    samples = []
    done = threading.Event()

    def measure():
        previous = cpu_times(); previous_t = time.monotonic()
        while not done.wait(1):
            current = cpu_times(); now = time.monotonic()
            point = {role: 0.0 for role in ROLES}
            for pid, (role, elapsed) in current.items():
                if pid in previous:
                    point[role] += max(0, elapsed - previous[pid][1]) / (now - previous_t) * 100
            samples.append(dict(point, elapsed=now - beginning))
            previous, previous_t = current, now

    beginning = time.monotonic(); start = time.time()
    sampler = threading.Thread(target=measure, daemon=True); sampler.start()
    finished = False
    try:
        for index in range(args.cycles):
            current = snapshot(args.probe)
            if any(d['vendor'] == 0x4f43 for d in current['displays']):
                raise RuntimeError('A production virtual display appeared; abort batch')
            process, display_id = experiment.create(0x4f430000 + args.slot)
            print(json.dumps({'cycle': index + 1, 'event': 'created'}), flush=True)
            time.sleep(4)
            experiment.stop(process, display_id)
            print(json.dumps({'cycle': index + 1, 'event': 'removed'}), flush=True)
            time.sleep(2)
            if len(snapshot(args.probe)['profiles']) != len(before['profiles']):
                raise RuntimeError('ICC count changed; this was not a warm-identity-only batch')
        finished = True
    finally:
        experiment.cleanup()
        done.set(); sampler.join(timeout=5)
        end = time.time(); after = snapshot(args.probe)
        result = {'start': start, 'end': end, 'samples': samples, 'logs': log_counts(start, end),
                  'before': before, 'after': after,
                  'finished': finished,
                  'created_cycles': sum(r['name'] == 'create_event' for r in experiment.records),
                  'cleanup_errors': [r for r in experiment.records if r['name'] == 'cleanup_error']}
        (pathlib.Path(args.output) / 'batch.json').write_text(json.dumps(result, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--probe', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--helper', required=True)
    parser.add_argument('--slot', type=int, default=28)
    parser.add_argument('--cycles', type=int, default=3)
    run_batch(parser.parse_args())
