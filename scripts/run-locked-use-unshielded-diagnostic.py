#!/usr/bin/env python3
"""Explicit visible-desktop unlock diagnostic. No shields or application tools."""
import argparse
import json
import math
import os
import select
from pathlib import Path
import subprocess
import time
from locked_use_report import LiveAuthenticationTrace, write_report, authentication_windows


def touch_id_intervened(timeline):
    windows = authentication_windows(timeline)
    return any(event['category'] == 'LoginWindow' and event['message'] == 'touchIDMatchObserved'
               and any(window['startedAt'] <= event['elapsedSeconds'] <= window['endedAt']
                       for window in windows if window['endedAt'] is not None)
               for event in timeline)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--confirm-visible-desktop-test', action='store_true', required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    binary = root / '.build/locked-use/components/Open Computer Use Guardian (Dev).app/Contents/MacOS/OpenComputerUseGuardian'
    started = time.time()
    events = []
    def record(event, elapsed=None, **fields):
        entry = dict(event=event, elapsedSeconds=round(time.time()-started if elapsed is None else elapsed, 3), **fields)
        events.append(entry); print(json.dumps(entry), flush=True)
    native_anchor = None
    anchor_elapsed = None
    def state():
        nonlocal native_anchor, anchor_elapsed
        result = subprocess.run([str(binary), '--session-only'], capture_output=True, check=True, timeout=3)
        entry = next(json.loads(line) for line in result.stdout.splitlines() if json.loads(line).get('event') == 'sessionState')
        if native_anchor is None:
            native_anchor = entry['uptime']; anchor_elapsed = time.time() - started
        return entry['session']
    if state() != 'unlocked': raise RuntimeError('Unlock normally before starting the diagnostic')
    trace = LiveAuthenticationTrace(started); trace.start()
    failure = None
    try:
        print('Locking in 5 seconds; no shields, no input filters. Wait up to 20 seconds or immediate relock before manual unlock.', flush=True)
        time.sleep(5)
        subprocess.run([str(binary), '--request-lock'], check=True, stdout=subprocess.DEVNULL, timeout=3)
        for _ in range(25):
            if state() == 'locked': break
            time.sleep(0.2)
        if state() != 'locked': raise RuntimeError('Initial lock not observed')
        record('lockedObserved')
        allowed = {'unshieldedDiagnosticStarted', 'unshieldedUnlockObserved', 'unshieldedDiagnosticEnded'}
        process = subprocess.Popen([str(binary), '--unshielded-unlock-diagnostic', '--confirm-visible-desktop-test'],
                                   stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        buffer = b''
        deadline = time.monotonic() + 32
        try:
            while time.monotonic() < deadline:
                ready, _, _ = select.select([process.stdout], [], [], 0.2)
                if not ready: continue
                chunk = os.read(process.stdout.fileno(), 4096)
                if not chunk: break
                buffer += chunk
                if len(buffer) > 65536: raise RuntimeError('Native diagnostic record exceeded bound')
                while b'\n' in buffer:
                    line, buffer = buffer.split(b'\n', 1)
                    try: entry = json.loads(line)
                    except (ValueError, TypeError): continue
                    if not isinstance(entry, dict) or entry.get('event') not in allowed: continue
                    uptime = entry.get('uptime')
                    if not isinstance(uptime, (int, float)) or not math.isfinite(uptime): continue
                    elapsed = uptime - native_anchor + anchor_elapsed
                    if not 0 <= elapsed <= 40: raise RuntimeError('Native diagnostic clock outside run')
                    fields = {k:v for k,v in entry.items() if k in {'shieldProcesses', 'inputFilters', 'maximumSeconds',
                              'productionEvidenceEligible', 'unlockObserved', 'permitConsumed', 'relockObserved', 'guiActionsPerformed'}}
                    record(entry['event'], elapsed=elapsed, **fields)
            else: raise TimeoutError('Native diagnostic exceeded deadline')
            if process.wait(timeout=2): raise RuntimeError('Unshielded native diagnostic failed; see curated timeline')
        finally:
            if process.poll() is None:
                process.terminate()  # Only this unshielded UI probe, no guards.
                try: process.wait(timeout=2)
                except subprocess.TimeoutExpired: process.kill(); process.wait(timeout=2)
            process.stdout.close()
    except Exception as exc:
        failure = type(exc).__name__; record('failed', failureType=failure)
        raise
    finally:
        timeline, trace_status = trace.finish()
        path = write_report(root, started, events, failure,
                            live_events=timeline, trace_status=trace_status)
        payload = json.loads(path.read_text())
        intervened = touch_id_intervened(payload['systemEvents'])
        summary = {'event': 'diagnosticAttribution', 'touchIDIntervened': intervened,
                   'automaticUnlockSupported': False if intervened else None,
                   'productionEvidenceEligible': False}
        payload['controllerEvents'].append(dict(summary, elapsedSeconds=round(time.time()-started, 3)))
        path.write_text(json.dumps(payload, ensure_ascii=False, indent=2))
        print(json.dumps(summary), flush=True)
        print(json.dumps({'event': 'diagnosticReportSaved', 'path': str(path)}), flush=True)


if __name__ == '__main__': main()
