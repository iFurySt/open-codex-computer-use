"""Private diagnostic timeline. Never retain raw OS records, AX strings or images."""
import datetime
import json
import math
import os
import pathlib
import re
import subprocess
import threading
import time
import uuid

BOOL = r"(?:true|false)"
PHASE = r"(?:idle|preparing|authorizing|unlocking|active|relocking|awaitingManualUnlock)"
PATTERNS = {
    "LockPresentation": [r"releaseBarrier state=(?:waitingForLock|waitingForCoverage|stabilizing|ready)"],
    "LockUIClickFilter": [r"clickAdmitted filter=(?:main|watchdog) type=(?:down|up)",
                         r"clickFlags raw=[0-9]+ modifiers=[0-9]+",
                         r"clickRejected filter=(?:main|watchdog) reason=(?:type|flags|window|inactive|timing|capability|source|target|sequence)"],
    "Watchdog": [r"stopping reason=(?:filterEvent|hardwareActivity|hardwareMonitorFailure|parentPipeFailed|parentHeartbeatExpired|protectionUnavailable|filterDisabled)"],
    "Broker": [rf"pluginDecision operation=(?:pluginClaim|pluginConsume|pluginFinished) result=(?:ok|waiting|denied|authorized|active|relock|release) phase={PHASE} sessionMatches={BOOL} auditUserMatches={BOOL}", rf"phase={PHASE}(?: stopReason=[A-Za-z]+)?", rf"denied operation=[A-Za-z]+ sessionMatches={BOOL} auditUserMatches={BOOL}",
               r"peerRejected endpoint=(?:agent|guardian|plugin|observer|admin)", "installationPolicyInvalidated", r"observerStage=(?:accepting|authenticated|readStarted|verified|handling|handled|persisting|persisted)", r"permitIssued maximumLifetimeSeconds=5",
               r"verificationSlow endpoint=(?:agent|guardian|plugin|observer|admin) elapsedMilliseconds=[0-9]+", r"originalClientVerificationSlow elapsedMilliseconds=[0-9]+"],
    "UnlockTrigger": [r"displayWakeReturned status=-?[0-9]+ authenticationRequested=false",
                      rf"lockUISettled elapsed=[0-9.]+ notificationObserved={BOOL}",
                      rf"AXProbe nodes=[0-9]+ primaryMatches=[0-9]+ fallbackMatches=[0-9]+ complete={BOOL}",
                      rf"AXProbe writable={BOOL} status=-?[0-9]+", r"AXProbe fixedValueWrite status=-?[0-9]+",
                      r"AXPublication attempt=[0-9]+", r"AXTrigger emptyValueWrite status=-?[0-9]+",
                      r"AXPublication followup=true",
                      r"AXTrigger clickTap=(?:hid|session)",
                      rf"AXTrigger passwordConfirmSupported={BOOL} status=-?[0-9]+",
                      r"AXTrigger passwordConfirm status=-?[0-9]+ authenticationEvidence=false",
                      r"AXTrigger passwordConfirmTimeout milliseconds=[0-9]+ status=-?[0-9]+",
                      r"AXTrigger passwordConfirmElapsed milliseconds=[0-9]+ status=-?[0-9]+",
                      r"AXTrigger passwordConfirmDispatching=true",
                      r"AXTrigger passwordConfirmSkipped=deadline",
                      rf"AXTrigger annotatedClickQueued={BOOL}", r"AXTrigger annotatedClickTargetAvailable=false",
                      r"AXTrigger annotatedClickWindowAvailable=false", r"AXTrigger annotatedClickWindowMatches=[0-9]+",
                      rf"AXTrigger sessionClickQueued={BOOL}", r"AXTrigger sessionClickTargetAvailable=false",
                      r"AXTrigger sessionClickWindowAvailable=false", r"AXTrigger sessionClickWindowMatches=[0-9]+",
                      r"AXTrigger sessionClickWindowEncodingAvailable=false",
                      r"AXTrigger focusedUserPress status=-?[0-9]+ authenticationEvidence=false",
                      rf"AXTrigger targetedClickQueued={BOOL} authenticationEvidence=false",
                      r"AXTrigger clickGeometryAvailable=false", rf"AXTrigger returnQueued={BOOL} authenticationEvidence=false",
                      r"AXProbe process(?:Unavailable|SignatureRejected)=true"],
    "AuthorizationMechanism": [r"brokerTaskVerification status=-?[0-9]+", r"brokerConnect connected=[01]", r"pluginClaim replied=[01] authorizing=[01] denied=[01]", r"pluginConsume replied=[01] allowed=[01]", "mechanismInvoked", "brokerVerified", r"resultDelivered allowed=[01] status=-?[0-9]+",
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
PATTERNS["Watchdog"].extend([r"stopping reason=shieldBoundsMismatch expected=[0-9.,{} -]+ actual=[0-9.,{} -]+", r"stopping reason=(?:topologyChanged|shieldNotVisible|shieldNotInWindowServer|shieldLayerMismatch|hardwareMonitorUnhealthy|inputTapDisabled|parentDisconnected)"])
PATTERNS["UnlockTrigger"].append(r"lockUIState=(?:candidateFound|candidateUnavailable|unknown) authenticationEvidence=false")
PATTERNS["Broker"].append(rf"guardLostEvidence guardianAgeMilliseconds=[0-9]+ watchdogAgeMilliseconds=[0-9]+ watchdogProtected={BOOL}")
PATTERNS["UnlockTrigger"].extend([r"AXProbe passwordUI enabledButtons=[0-9]+ disabledButtons=[0-9]+ unknownButtons=[0-9]+", rf"AXProbe passwordFocused={BOOL} status=-?[0-9]+"])

PATTERNS["UnlockTrigger"].extend(["AXTrigger returnDispatching=true keyCode=36 tap=hid", rf"AXTrigger returnPairQueued={BOOL} authenticationEvidence=false"])

PATTERNS["LockUIClickFilter"].extend([r"returnAdmitted filter=(?:main|watchdog) type=(?:down|up)", r"returnRejected filter=(?:main|watchdog) reason=(?:inactive|timing|capability|source|target|key|sequence)"])

# Normalize markers into enums; never retain the surrounding user/context text.
SYSTEM_MARKERS = {
    "loginwindow": [
        ("loginPressed", "localSubmitObserved"),
        ("return in secure textfield", "secureReturnObserved"),
        ("authBegan", "localAuthenticationBegan"),
        ("_authCopyRightsWithUsername", "loginwindowRightsRequested"),
        ("APEventTouchIDMatch", "touchIDMatchObserved"),
        ("evaluatePolicy", "localAuthenticationEvaluationObserved"),
        ("askForPasswordSecAgent", "securityAgentUIRequested"),
        ("Screensaver authorization succeeded", "screensaverAuthorizationSucceeded"),
        ("Unlock succeeded", "sessionUnlockReported"),
        ("did NOT unlock the user's keychain", "keychainUnlockSkipped"),
        ("SecKeychainLogin failed", "keychainLoginFailed"),
        ("attempting to unlock with empty might rekey", "emptyInputKeychainPathObserved"),
    ],
}
LOG_PREDICATE = ('subsystem == "dev.opencomputeruse.locked-use" OR process == "loginwindow" '
                 'OR process == "authd" OR process == "SecurityAgentHelper-arm64" '
                 'OR process == "SecurityAgentHelper-x86_64"')


def curate(records, started):
    events = []
    if not isinstance(records, list): return events
    for entry in records[:2000]:
        if not isinstance(entry, dict): continue
        if not all(isinstance(entry.get(key, ""), str) for key in ["processImagePath", "category", "eventMessage", "timestamp"]): continue
        process = pathlib.Path(entry.get("processImagePath", "")).name
        try: timestamp = datetime.datetime.fromisoformat(entry["timestamp"]).timestamp()
        except (KeyError, ValueError, OverflowError): continue
        if not math.isfinite(timestamp) or timestamp < started: continue
        def emit(category, message):
            events.append({"elapsedSeconds": round(timestamp-started, 3), "category": category, "message": message})
        message = entry["eventMessage"]
        if process == "authd":
            if "system.login.screensaver" in message:
                action = "systemRightSucceeded" if "Succeeded authorizing right" in message else "systemRightFailed" if "Failed authorizing right" in message else "systemRightEvaluationObserved" if "evaluates" in message and "rights" in message else None
                if action: emit("SystemAuthorization", action)
            if "running mechanism OpenComputerUseLockedUseAuthorizationPlugin:remote" in message:
                emit("SystemAuthorization", "remoteMechanismRunning")
            continue
        if process in SYSTEM_MARKERS:
            for marker, action in SYSTEM_MARKERS[process]:
                if marker in message: emit("LoginWindow", action)
            continue
        if process in {"SecurityAgentHelper-arm64", "SecurityAgentHelper-x86_64"}:
            emit("SecurityAgentHost", "helperActivityObserved")
        if process not in {"OpenComputerUse", "OpenComputerUseGuardian", "OpenComputerUseLockedUseBroker",
                           "SecurityAgentHelper-arm64", "SecurityAgentHelper-x86_64"}: continue
        category = entry.get("category", "")
        message = entry.get("eventMessage", "")
        if not any(re.fullmatch(pattern, message) for pattern in PATTERNS.get(category, [])): continue
        emit(category, message)
    return events


def authentication_windows(events):
    """Keep manual recovery outside the permit window. Silence is not absence."""
    windows = []
    current = None
    for event in sorted(events, key=lambda item: item["elapsedSeconds"]):
        message = event["message"]
        if event["category"] == "Broker" and message == "phase=authorizing stopReason=none":
            # Streaming and historical logs may report the same transition with
            # slightly different timestamps. A repeated phase is not a new lease.
            if current: continue
            current = {"startedAt": event["elapsedSeconds"], "endedAt": None,
                       "permitIssuedObservedAt": None, "rightEvaluationObserved": False, "mechanismObserved": False,
                       "allowObserved": False, "localAuthenticationObserved": False}
            windows.append(current)
        elif event["category"] == "Broker" and message.split(" ")[0] in {
            "phase=relocking", "phase=awaitingManualUnlock", "phase=idle"} and current:
            current["endedAt"] = event["elapsedSeconds"]
            current = None
        if current:
            if event["category"] == "Broker" and message == "permitIssued maximumLifetimeSeconds=5":
                if current["permitIssuedObservedAt"] is None: current["permitIssuedObservedAt"] = event["elapsedSeconds"]
            if event["category"] == "SystemAuthorization" and message in {
                "systemRightEvaluationObserved", "systemRightSucceeded", "systemRightFailed"}:
                current["rightEvaluationObserved"] = True
            if message in {"mechanismInvoked", "remoteMechanismRunning"}:
                current["mechanismObserved"] = True
            if message == "resultDelivered allowed=1 status=0": current["allowObserved"] = True
            if event["category"] == "LoginWindow" and message in {
                "localSubmitObserved", "touchIDMatchObserved", "localAuthenticationEvaluationObserved"}:
                current["localAuthenticationObserved"] = True
    return windows


class LiveAuthenticationTrace:
    """Read debug logs before a lock; retain bounded enums in memory only.

    This collector never invokes authentication or holds protection. A broken
    stream is diagnostic only, never permission to unlock or remove a shield.
    """
    def __init__(self, started, max_seconds=150):
        self.started = started
        self.max_seconds = max_seconds
        self.events = []
        self.process = None
        self.thread = None
        self.stop = threading.Event()
        self.status = "unavailable"

    def start(self):
        try:
            self.process = subprocess.Popen(["/usr/bin/log", "stream", "--level", "debug",
                                            "--style", "ndjson", "--predicate", LOG_PREDICATE],
                                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        except OSError: return
        self.status = "started"
        self.thread = threading.Thread(target=self._read, daemon=True)
        self.thread.start()

    def _read(self):
        import select
        deadline = time.monotonic() + self.max_seconds
        buffer = b""
        discarding = False
        try:
            while not self.stop.is_set() and time.monotonic() < deadline:
                ready, _, _ = select.select([self.process.stdout], [], [], 0.2)
                if not ready: continue
                chunk = os.read(self.process.stdout.fileno(), 16384)
                if not chunk:
                    self.status = "stopped" if self.stop.is_set() else "ended"
                    return
                self.status = "receiving"
                for part in chunk.splitlines(keepends=True):
                    ended = part.endswith(b"\n")
                    if not discarding: buffer += part
                    if len(buffer) > 65536:
                        buffer = b""
                        discarding = True
                    if ended:
                        if not discarding:
                            try: record = json.loads(buffer)
                            except (ValueError, UnicodeError): record = None
                            if len(self.events) < 2000:
                                self.events.extend(curate([record], self.started)[:2000-len(self.events)])
                        buffer = b""
                        discarding = False
            if not self.stop.is_set(): self.status = "deadlineReached"
        except (OSError, ValueError): self.status = "readFailed"
        finally:
            if self.process.poll() is None: self.process.terminate()

    def finish(self):
        self.stop.set()
        if self.process and self.process.poll() is None: self.process.terminate()
        if self.thread: self.thread.join(timeout=1)
        if self.process:
            try: self.process.wait(timeout=1)
            except subprocess.TimeoutExpired:
                self.process.kill()  # Only this read-only collector.
                self.process.wait(timeout=1)
            if self.process.stdout: self.process.stdout.close()
        return list(self.events), self.status


def write_report(root, started, events, error=None, live_events=None, trace_status="notStarted"):
    records = []
    try:
        result = subprocess.run(["/usr/bin/log", "show", "--last", f"{math.ceil(time.time()-started)+2}s",
                                 "--style", "json", "--predicate", LOG_PREDICATE],
                                capture_output=True, timeout=5, check=True)
        if len(result.stdout) <= 4*1024*1024: records = json.loads(result.stdout)
    except (OSError, subprocess.SubprocessError, ValueError): pass
    timeline = curate(records, started) + (live_events or [])
    timeline = sorted({(event["elapsedSeconds"], event["category"], event["message"]): event
                       for event in timeline}.values(), key=lambda item: item["elapsedSeconds"])
    payload = {"schemaVersion": 2, "diagnosticOnly": True, "productionEvidenceEligible": False,
               "elapsedSeconds": round(time.time()-started, 3), "controllerEvents": events,
               "systemEvents": timeline, "failureType": error,
               "liveTraceStatus": trace_status, "missingEventsProveAbsence": False,
               "authorizationWindows": authentication_windows(timeline)}
    directory = pathlib.Path(root)/".build/locked-use/reports"
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    path = directory/(uuid.uuid4().hex+".json")
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(descriptor, "w") as output: json.dump(payload, output, ensure_ascii=False, indent=2)
    return path
