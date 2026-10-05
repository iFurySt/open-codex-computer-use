"""Private diagnostic timeline. Never retain raw OS records, AX strings or images."""
import datetime
import json
import math
import os
import pathlib
import re
import subprocess
import time
import uuid

BOOL = r"(?:true|false)"
PHASE = r"(?:idle|preparing|authorizing|unlocking|active|relocking|awaitingManualUnlock)"
PATTERNS = {
    "Broker": [rf"phase={PHASE}", rf"denied operation=[A-Za-z]+ sessionMatches={BOOL} auditUserMatches={BOOL}",
               r"peerRejected endpoint=(?:agent|guardian|plugin|observer|admin)", "installationPolicyInvalidated"],
    "UnlockTrigger": [r"displayWakeReturned status=-?[0-9]+ authenticationRequested=false",
                      rf"lockUISettled elapsed=[0-9.]+ notificationObserved={BOOL}",
                      rf"AXProbe nodes=[0-9]+ primaryMatches=[0-9]+ fallbackMatches=[0-9]+ complete={BOOL}",
                      rf"AXProbe writable={BOOL} status=-?[0-9]+", r"AXProbe fixedValueWrite status=-?[0-9]+",
                      r"AXProbe process(?:Unavailable|SignatureRejected)=true"],
    "AuthorizationMechanism": ["mechanismInvoked", "brokerVerified", r"resultDelivered allowed=[01] status=-?[0-9]+",
                               r"brokerVerification guest=-?[0-9]+ requirement=-?[0-9]+ validity=-?[0-9]+ static=-?[0-9]+ info=-?[0-9]+"],
    "AgentRecovery": ["actionDrainSubmitting", "recoveryProbeAcquireEnded",
                      rf"actionDrainReply phase={PHASE} denied={BOOL}",
                      rf"actionDrainDeferred brokerAvailable={BOOL} leaseAvailable={BOOL}",
                      "brokerPollingFailed recoveryDeadlineArmed=true", "actionDrainRPCFailed recoveryDeadlinePending=true"],
    "NativeValidation": ["fixtureValidationStarted", r"fixtureBeforeCaptured counter=[0-9]+",
                         "fixtureChanged counterIncremented=true imageChanged=true",
                         rf"isolatedKeychainVerified dataProtectionIncluded={BOOL}"],
    "WatchdogBroker": ["registered"],
}


def curate(records, started):
    events = []
    if not isinstance(records, list): return events
    for entry in records[:2000]:
        if not isinstance(entry, dict): continue
        if not all(isinstance(entry.get(key, ""), str) for key in ["processImagePath", "category", "eventMessage", "timestamp"]): continue
        process = pathlib.Path(entry.get("processImagePath", "")).name
        if process not in {"OpenComputerUse", "OpenComputerUseGuardian", "OpenComputerUseLockedUseBroker",
                           "SecurityAgentHelper-arm64", "SecurityAgentHelper-x86_64"}: continue
        category = entry.get("category", "")
        message = entry.get("eventMessage", "")
        if not any(re.fullmatch(pattern, message) for pattern in PATTERNS.get(category, [])): continue
        try: timestamp = datetime.datetime.fromisoformat(entry["timestamp"]).timestamp()
        except (KeyError, ValueError): continue
        if timestamp < started: continue
        events.append({"elapsedSeconds": round(timestamp-started, 3), "category": category, "message": message})
    return events


def write_report(root, started, events, error=None):
    records = []
    try:
        result = subprocess.run(["/usr/bin/log", "show", "--last", f"{math.ceil(time.time()-started)+2}s",
                                 "--style", "json", "--predicate", 'subsystem == "dev.opencomputeruse.locked-use"'],
                                capture_output=True, timeout=5, check=True)
        if len(result.stdout) <= 4*1024*1024: records = json.loads(result.stdout)
    except (subprocess.SubprocessError, ValueError): pass
    timeline = curate(records, started)
    payload = {"schemaVersion": 1, "diagnosticOnly": True, "productionEvidenceEligible": False,
               "elapsedSeconds": round(time.time()-started, 3), "controllerEvents": events,
               "systemEvents": timeline, "failureType": error}
    directory = pathlib.Path(root)/".build/locked-use/reports"
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    path = directory/(uuid.uuid4().hex+".json")
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(descriptor, "w") as output: json.dump(payload, output, ensure_ascii=False, indent=2)
    return path
