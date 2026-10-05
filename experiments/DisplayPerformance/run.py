#!/usr/bin/env python3
"""Bounded independent display experiment. No daemon/profile/preference cleanup."""
import argparse, collections, datetime, fcntl, hashlib, json, os, pathlib, plistlib
import select, stat, statistics, subprocess, time

ROOT = pathlib.Path(__file__).resolve().parents[2]
ROLES = ('WindowServer', 'colorsync.displayservices', 'colorsyncd')

def cpu_seconds(value):
    days, sep, rest = value.partition('-')
    total = int(days) * 86400 if sep else 0
    parts = (rest if sep else value).split(':')
    for position, part in enumerate(reversed(parts)):
        total += float(part) * 60 ** position
    return total

def cpu_times():
    output = subprocess.check_output(['ps', '-axo', 'pid,time,comm'], text=True)
    result = {}
    for line in output.splitlines()[1:]:
        parts = line.strip().split(None, 2)
        if len(parts) != 3: continue
        role = pathlib.Path(parts[2]).name
        if role in ROLES:
            result[int(parts[0])] = (role, cpu_seconds(parts[1]))
    return result

def snapshot(probe):
    display = json.loads(subprocess.check_output([probe, 'list'], text=True))
    profiles = {}
    for root in [pathlib.Path('/Library/ColorSync/Profiles/Displays'), pathlib.Path.home() / 'Library/ColorSync/Profiles']:
        for path in root.rglob('Open Computer Use Virtual Display-*.icc'):
            data = path.read_bytes()
            if b'Open Computer Use' in data or 'Open Computer Use'.encode('utf-16-be') in data:
                profiles[path.name] = hashlib.sha256(data).hexdigest()
    uuids = set(); configs = 0
    def walk(value):
        nonlocal configs
        if isinstance(value, dict):
            if 'ConfigVersion' in value: configs += 1
            for key, child in value.items():
                if 'uuid' in key.lower() and isinstance(child, str): uuids.add(child)
                walk(child)
        elif isinstance(value, list):
            for child in value: walk(child)
    for path in (pathlib.Path.home() / 'Library/Preferences/ByHost').glob('com.apple.windowserver.displays*.plist'):
        walk(plistlib.loads(path.read_bytes()))
    return dict(display, profiles=profiles, mixed_windowserver_uuid_count=len(uuids), mixed_windowserver_config_count=configs)

def log_counts(start, end):
    fmt = '%Y-%m-%d %H:%M:%S'
    args = ['/usr/bin/log', 'show', '--start', time.strftime(fmt, time.localtime(start)),
            '--end', time.strftime(fmt, time.localtime(end + 1)), '--style', 'ndjson',
            '--predicate', 'process == "colorsync.displayservices" OR process == "colorsyncd"']
    proc = subprocess.run(args, capture_output=True, text=True, timeout=30)
    profiles = collections.Counter(); messages = 0; requests = 0
    for line in proc.stdout.splitlines():
        try:
            event = json.loads(line); stamp = datetime.datetime.fromisoformat(event['timestamp']).timestamp()
            if not start <= stamp < end: continue
        except (ValueError, KeyError): continue
        messages += 1; message = event.get('eventMessage', '')
        if 'received XPC_DISPLAY_INFO_REQUEST' in message:
            requests += 1
        if 'ColorSyncProfileCreateDeviceProfile' in message:
            description = message.partition('Profile desc: ')[2] or '(no description)'
            profiles[description] += 1
    return {'events': messages, 'profile_calls': dict(profiles),
            'profile_calls_per_second': sum(profiles.values()) / max(end - start, .001),
            'display_info_requests': requests,
            'display_info_requests_per_second': requests / max(end - start, .001),
            'log_exit': proc.returncode, 'stderr': proc.stderr[:200]}

class Experiment:
    def __init__(self, args):
        self.args = args; self.records = []; self.helpers = []; self.helper_displays = {}
        self.out = pathlib.Path(args.output); self.out.mkdir(parents=True, exist_ok=True)
    def write(self):
        data = {'duration_per_phase': self.args.seconds, 'phases': self.records,
                'limitations': ['Existing production capture/session may continue: measures incremental workload, not absence of OCU.',
                                'CPU/log association does not prove daemon caller stack.',
                                'No profile/registry isolation: historical residue cost remains untested.']}
        temporary = self.out / 'report.json.tmp'; temporary.write_text(json.dumps(data, indent=2))
        temporary.replace(self.out / 'report.json')
    def phase(self, name, workload=None):
        before = snapshot(self.args.probe)
        start = time.time(); samples = []; previous = cpu_times(); previous_t = time.monotonic()
        print(json.dumps({'phase': name, 'event': 'begin', 'profile_count': len(before['profiles'])}), flush=True)
        proc = subprocess.Popen(workload, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) if workload else None
        try:
            while time.time() < start + self.args.seconds or (proc and proc.poll() is None and time.time() < start + self.args.seconds + 15):
                time.sleep(1)
                current = cpu_times(); now = time.monotonic(); dt = now - previous_t
                point = {role: 0.0 for role in ROLES}
                for pid, (role, elapsed) in current.items():
                    if pid in previous:
                        point[role] += max(0, elapsed - previous[pid][1]) / dt * 100
                samples.append(dict(point, elapsed=time.time() - start))
                previous, previous_t = current, now
            native = None
            if proc:
                stdout, stderr = proc.communicate(timeout=15)
                native = {'exit': proc.returncode, 'stdout': stdout.strip(), 'stderr': stderr[:1000]}
        finally:
            if proc and proc.poll() is None:
                # Only our bounded workload; no apps or shared helpers are terminated.
                proc.terminate(); proc.wait(timeout=5)
        end = time.time(); after = snapshot(self.args.probe)
        cpu = {}
        for role in ROLES:
            values = [s[role] for s in samples]
            cpu[role] = {'mean': statistics.mean(values), 'median': statistics.median(values),
                         'max': max(values), 'p95': sorted(values)[max(0, int(len(values) * .95) - 1)]}
        result = {'name': name, 'start': start, 'end': end, 'cpu': cpu, 'samples': samples,
                  'logs': log_counts(start, end), 'before': before, 'after': after, 'native': native,
                  'added_profiles': sorted(set(after['profiles']) - set(before['profiles'])),
                  'topology_changed': before['displays'] != after['displays']}
        self.records.append(result); self.write()
        print(json.dumps({'phase': name, 'event': 'end', 'cpu_mean': {k: round(v['mean'], 1) for k,v in cpu.items()},
                          'profile_calls_per_second': round(result['logs']['profile_calls_per_second'], 2),
                          'added_profiles': len(result['added_profiles']), 'native': native}), flush=True)
        return result
    def create(self, serial):
        lock_path = pathlib.Path.home() / 'Library/Caches/OpenComputerUse/virtual-display-identity.lock'
        fd = os.open(lock_path, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
        try:
            metadata = os.fstat(fd)
            if metadata.st_uid != os.getuid() or not stat.S_ISREG(metadata.st_mode):
                raise RuntimeError('Unsafe identity lock owner/type')
            deadline = time.monotonic() + 15
            while True:
                try: fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB); break
                except BlockingIOError:
                    if time.monotonic() > deadline: raise RuntimeError('Identity lock busy')
                    time.sleep(.05)
            info = json.loads(subprocess.check_output([self.args.probe, 'list'], text=True))
            if serial in {d['serial'] for d in info['displays']}: raise RuntimeError('Requested serial is already online')
            before = snapshot(self.args.probe)
            process = subprocess.Popen([self.args.helper], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            self.helpers.append(process)
            process.stdin.write((json.dumps({'width':1920,'height':1080,'scale':1,'serial':serial})+'\n').encode());process.stdin.flush()
            deadline = time.monotonic() + 15; line = b''
            while time.monotonic() < deadline:
                if select.select([process.stdout], [], [], .1)[0]:
                    byte = os.read(process.stdout.fileno(), 1)
                    if not byte: raise RuntimeError('Helper exited before ready')
                    if byte == b'\n': break
                    line += byte
            reply = json.loads(line)
            if 'error' in reply: raise RuntimeError(reply['error'])
            self.helper_displays[process.pid] = reply['display_id']
            self.records.append({'name':'create_event','serial':serial,'reply':reply,'before':before,'after':snapshot(self.args.probe),'timestamp':time.time()});self.write()
            return process, reply['display_id']
        finally: fcntl.flock(fd, fcntl.LOCK_UN);os.close(fd)
    def stop(self, process, display_id):
        if process.poll() is None:
            process.stdin.write(b'stop\n');process.stdin.flush();process.stdin.close();process.wait(timeout=8)
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            displays = json.loads(subprocess.check_output([self.args.probe,'list'],text=True))['displays']
            if display_id not in {d['id'] for d in displays}:
                self.records.append({'name':'remove_event','display_id':display_id,'after':snapshot(self.args.probe),'timestamp':time.time()});self.write();return
            time.sleep(.1)
        raise RuntimeError('Demo display did not disappear')
    def run(self):
        if self.args.mode == 'observe':
            self.phase('baseline')
            for mode,hz in [('cg-query',2),('cg-query',20),('shareable-query',2)]:
                self.phase(f'{mode}-{hz}Hz',[self.args.probe,mode,str(self.args.seconds),str(hz)])
                self.phase('recovery-'+mode+str(hz))
            for mode in ['capture','capture-render']:
                current = snapshot(self.args.probe)
                virtuals = [d for d in current['displays'] if d['vendor']==0x4f43]
                if not virtuals or not current['screen_recording']:
                    self.records.append({'name': mode, 'skipped': 'No online virtual display or capture permission'})
                    self.write(); continue
                self.phase(mode,[self.args.probe,mode,str(self.args.seconds),'30',str(virtuals[0]['id'])])
                self.phase('recovery-'+mode)
        elif self.args.mode == 'hotplug':
            baseline = self.phase('baseline-hotplug')
            if any(d['vendor']==0x4f43 for d in baseline['after']['displays']):
                raise RuntimeError('Another runtime owns a virtual display: coordinate idle test window first')
            occupied = {d['serial'] for d in baseline['before']['displays']}
            slots = [0x4f430000+i for i in reversed(range(32)) if 0x4f430000+i not in occupied][:3]
            if len(slots)<3: raise RuntimeError('Need three unused bounded serial slots')
            for label, serial in [('stable-first',slots[0]),('stable-repeat',slots[0]),('changed-first',slots[1]),('changed-second',slots[2])]:
                process, display_id = self.create(serial)
                held = self.phase(label+'-held')
                foreign = [d for d in held['after']['displays'] if d['vendor']==0x4f43 and d['id']!=display_id]
                if foreign: raise RuntimeError('A production virtual display appeared: stop demo and coordinate another window')
                if label == 'stable-first':
                    for mode in ['capture','capture-render']:
                        self.phase(mode,[self.args.probe,mode,str(self.args.seconds),'30',str(display_id)])
                        self.phase('recovery-'+mode)
                self.stop(process,display_id)
                self.phase(label+'-removed')
        else: raise RuntimeError('Unknown mode')
        self.write()
    def cleanup(self):
        for process in self.helpers:
            try:
                display_id = self.helper_displays.get(process.pid)
                if display_id is not None:
                    self.stop(process, display_id)
                elif process.poll() is None:
                    process.stdin.close(); process.wait(timeout=8)
                self.records.append({'name': 'cleanup_event', 'helper_exit': process.returncode,
                                     'display_id': display_id, 'verified': display_id is not None})
            except Exception as error:
                self.records.append({'name': 'cleanup_error', 'helper_pid': process.pid, 'error': str(error)})
                # Never force terminate an application or system service.
            self.write()

if __name__ == '__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--probe',required=True);parser.add_argument('--output',required=True)
    parser.add_argument('--mode',choices=['observe','hotplug'],default='observe')
    parser.add_argument('--seconds',type=int,default=20)
    parser.add_argument('--helper',default=str(ROOT/'dist/Open Computer Use.app/Contents/Helpers/VirtualDisplayHost'))
    args=parser.parse_args()
    if not 10<=args.seconds<=60: parser.error('seconds must be 10..60')
    experiment=Experiment(args)
    try: experiment.run()
    finally: experiment.cleanup()
