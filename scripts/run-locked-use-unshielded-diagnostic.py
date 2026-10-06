#!/usr/bin/env python3
"""Explicit visible-desktop unlock diagnostic. No shields or application tools."""
import argparse
import json
from pathlib import Path
import subprocess
import time
from locked_use_report import LiveAuthenticationTrace, write_report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--confirm-visible-desktop-test', action='store_true', required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    binary = root / '.build/locked-use/components/Open Computer Use Guardian (Dev).app/Contents/MacOS/OpenComputerUseGuardian'
    started = time.time()
    events = []
    def record(event, **fields):
        entry = dict(event=event, elapsedSeconds=round(time.time()-started, 3), **fields)
        events.append(entry); print(json.dumps(entry), flush=True)
    def state():
        result = subprocess.run([str(binary), '--session-only'], capture_output=True, check=True, timeout=3)
        return next(json.loads(line)['session'] for line in result.stdout.splitlines() if json.loads(line).get('event') == 'sessionState')
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
        result = subprocess.run([str(binary), '--unshielded-unlock-diagnostic', '--confirm-visible-desktop-test'],
                                capture_output=True, timeout=32)
        allowed = {'unshieldedDiagnosticStarted', 'unshieldedUnlockObserved', 'unshieldedDiagnosticEnded'}
        for line in result.stdout.splitlines():
            try: entry = json.loads(line)
            except (ValueError, TypeError): continue
            if entry.get('event') in allowed:
                fields = {k:v for k,v in entry.items() if k in {'shieldProcesses', 'inputFilters', 'maximumSeconds',
                          'productionEvidenceEligible', 'unlockObserved', 'permitConsumed', 'relockObserved', 'guiActionsPerformed'}}
                record(entry['event'], **fields)
        if result.returncode: raise RuntimeError('Unshielded native diagnostic failed; see curated timeline')
    except Exception as exc:
        failure = type(exc).__name__; record('failed', failureType=failure)
        raise
    finally:
        trace.close()
        path = write_report(root, started, events, failure,
                            live_events=trace.events, trace_status=trace.status)
        print(json.dumps({'event': 'diagnosticReportSaved', 'path': str(path)}), flush=True)


if __name__ == '__main__': main()
