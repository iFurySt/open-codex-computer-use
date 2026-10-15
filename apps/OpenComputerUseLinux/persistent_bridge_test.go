package main

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"
)

func fakePersistentPython(t *testing.T) {
	t.Helper()
	python, err := exec.LookPath("python3")
	if err != nil {
		t.Fatal(err)
	}
	dir := t.TempDir()
	code := "#!" + python + ` 
import json,os,sys,time
for line in sys.stdin:
    request=json.loads(line)
    tool=request['tool']
    if tool=='hang': time.sleep(60)
    if tool=='crash': os._exit(3)
    if tool=='malformed': print('invalid JSON',flush=True); continue
    print(json.dumps({'ok':tool!='error','error':'action failed' if tool=='error' else '', 'text':str(os.getpid())}),flush=True)
`
	if err := os.WriteFile(filepath.Join(dir, "python3"), []byte(code), 0o700); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
}

func workerPID(t *testing.T, response *linuxResponse) int {
	t.Helper()
	pid, err := strconv.Atoi(response.Text)
	if err != nil {
		t.Fatal(err)
	}
	return pid
}

func TestPersistentBridgeReusesWorkerAndCleansUp(t *testing.T) {
	fakePersistentPython(t)
	b := &pythonBridge{}
	t.Cleanup(b.close)
	a, err := b.call(context.Background(), linuxRequest{Tool: "first"})
	if err != nil {
		t.Fatal(err)
	}
	dir := b.dir
	if b.cmd.SysProcAttr.Pdeathsig != syscall.SIGKILL {
		t.Fatal("worker does not terminate when its MCP parent dies")
	}
	second, err := b.call(context.Background(), linuxRequest{Tool: "second"})
	if err != nil || a.Text != second.Text {
		t.Fatalf("worker not reused: %v, %v", second, err)
	}
	pid := workerPID(t, a)
	b.close()
	if _, err := os.Stat(dir); !os.IsNotExist(err) {
		t.Fatalf("bridge directory retained: %v", err)
	}
	if err := syscall.Kill(pid, 0); !errors.Is(err, syscall.ESRCH) {
		t.Fatalf("worker remains: %v", err)
	}
	if _, err := b.call(context.Background(), linuxRequest{Tool: "after-close"}); err == nil {
		t.Fatal("closed bridge restarted")
	}
}

func TestPersistentBridgeFailureDoesNotReplayAndNextRequestRestarts(t *testing.T) {
	for _, tool := range []string{"hang", "crash", "malformed"} {
		t.Run(tool, func(t *testing.T) {
			fakePersistentPython(t)
			b := &pythonBridge{}
			t.Cleanup(b.close)
			first, err := b.call(context.Background(), linuxRequest{Tool: "first"})
			if err != nil {
				t.Fatal(err)
			}
			pid := workerPID(t, first)
			dir := b.dir
			ctx, cancel := context.WithTimeout(context.Background(), 80*time.Millisecond)
			defer cancel()
			if _, err := b.call(ctx, linuxRequest{Tool: tool}); err == nil {
				t.Fatal("transport failure reported as success")
			}
			if b.cmd != nil {
				t.Fatal("failed worker retained")
			}
			if err := syscall.Kill(pid, 0); !errors.Is(err, syscall.ESRCH) {
				t.Fatalf("worker remains: %v", err)
			}
			if _, err := os.Stat(dir); !os.IsNotExist(err) {
				t.Fatal("failed session directory retained")
			}
			next, err := b.call(context.Background(), linuxRequest{Tool: "next"})
			if err != nil {
				t.Fatal(err)
			}
			if next.Text == first.Text {
				t.Fatal("failed worker reused")
			}
		})
	}
}

func TestPersistentBridgeApplicationErrorsKeepSession(t *testing.T) {
	fakePersistentPython(t)
	b := &pythonBridge{}
	t.Cleanup(b.close)
	a, err := b.call(context.Background(), linuxRequest{Tool: "error"})
	if err != nil || a.OK || a.Error != "action failed" {
		t.Fatalf("error response lost: %v %v", a, err)
	}
	next, err := b.call(context.Background(), linuxRequest{Tool: "next"})
	if err != nil || next.Text != a.Text {
		t.Fatal("application error unnecessarily restarted worker")
	}
}

func TestNoReadBackActionsReuseTheSessionWorker(t *testing.T) {
	fakePersistentPython(t)
	t.Setenv("OPEN_COMPUTER_USE_ACTION_READ_BACK", "0")
	s := newService()
	s.bridge = &pythonBridge{}
	t.Cleanup(s.bridge.close)
	first, err := s.runPython(linuxRequest{Tool: "list_apps"})
	if err != nil {
		t.Fatal(err)
	}
	pid := workerPID(t, first)
	s.rememberSnapshot("Editor", &appSnapshot{App: appDescriptor{Name: "Editor", PID: 42}})
	if result := s.pressKey("Editor", "Return", "auto"); result.IsError || result.Content[0].Text != "ok" {
		t.Fatalf("no-read-back action failed: %#v", result)
	}
	if s.bridge.cmd.Process.Pid != pid {
		t.Fatal("action bypassed the session worker")
	}
}

func TestMCPSessionClosesCurrentWorkerAfterTurnBoundaryAndEOF(t *testing.T) {
	fakePersistentPython(t)
	t.Setenv("OPEN_COMPUTER_USE_LINUX_PERSISTENT_BRIDGE", "1")
	input, write := io.Pipe()
	output, read := io.Pipe()
	done := make(chan error, 1)
	go func() { done <- runMCP(input, read); read.Close() }()
	// Pipe writer/reader pairs deliberately keep the MCP alive between boundaries.
	defer input.Close()
	defer write.Close()
	defer output.Close()
	send := func(message string) string {
		t.Helper()
		go func() { _, _ = io.WriteString(write, message+"\n") }()
		line := make([]byte, 4096)
		n, err := output.Read(line)
		if err != nil {
			t.Fatal(err)
		}
		return string(line[:n])
	}
	request := `{"id":1,"method":"tools/call","params":{"name":"list_apps","arguments":{}}}`
	first := send(request)
	if !strings.Contains(first, `"isError":false`) {
		t.Fatal(first)
	}
	_, _ = io.WriteString(write, `{"method":"notifications/turn-ended"}`+"\n")
	second := send(request)
	if first == second {
		t.Fatal("turn boundary did not replace worker")
	}
	pidFromResult := func(line string) int {
		t.Helper()
		var response struct {
			Result toolCallResult `json:"result"`
		}
		if err := json.Unmarshal([]byte(line), &response); err != nil {
			t.Fatal(err)
		}
		pid, err := strconv.Atoi(response.Result.Content[0].Text)
		if err != nil {
			t.Fatal(err)
		}
		return pid
	}
	if err := syscall.Kill(pidFromResult(first), 0); !errors.Is(err, syscall.ESRCH) {
		t.Fatal("turn-end worker remains alive")
	}
	write.Close()
	select {
	case err := <-done:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("MCP EOF cleanup stalled")
	}
	if err := syscall.Kill(pidFromResult(second), 0); !errors.Is(err, syscall.ESRCH) {
		t.Fatal("replacement worker remains alive after EOF")
	}
}
