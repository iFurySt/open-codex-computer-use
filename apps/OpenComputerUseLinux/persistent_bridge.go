package main

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"syscall"
	"time"
)

// One bridge belongs to one MCP session. Requests are serialized, never replayed,
// and a failed/timed-out transport is killed before a later request can restart it.
type pythonBridge struct {
	mu     sync.Mutex
	cmd    *exec.Cmd
	stdin  io.WriteCloser
	reader *bufio.Reader
	dir    string
	closed bool
}

func (b *pythonBridge) start() error {
	dir, err := os.MkdirTemp("", "open-computer-use-linux-session-*")
	if err != nil {
		return err
	}
	b.dir = dir
	script := filepath.Join(dir, "runtime.py")
	if err := os.WriteFile(script, []byte(linuxRuntimeScript), 0o600); err != nil {
		b.stop()
		return err
	}
	cmd := exec.Command("python3", script, "--serve")
	cmd.Env = linuxRuntimeEnvironment(os.Environ())
	// Do not leave a desktop automation bridge behind if the native MCP dies.
	cmd.SysProcAttr = &syscall.SysProcAttr{Pdeathsig: syscall.SIGKILL}
	input, err := cmd.StdinPipe()
	if err != nil {
		b.stop()
		return err
	}
	output, err := cmd.StdoutPipe()
	if err != nil {
		input.Close()
		b.stop()
		return err
	}
	cmd.Stderr = os.Stderr
	if err := cmd.Start(); err != nil {
		input.Close()
		output.Close()
		b.stop()
		return err
	}
	b.cmd, b.stdin, b.reader = cmd, input, bufio.NewReader(output)
	return nil
}

// stop is called with the mutex held and waits until the old worker is gone.
func (b *pythonBridge) stop() {
	if b.stdin != nil {
		b.stdin.Close()
	}
	if b.cmd != nil {
		_ = b.cmd.Process.Kill()
		_ = b.cmd.Wait()
	}
	if b.dir != "" {
		_ = os.RemoveAll(b.dir)
	}
	b.cmd, b.stdin, b.reader, b.dir = nil, nil, nil, ""
}

func (b *pythonBridge) close() {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.closed = true
	b.stop()
}

func (b *pythonBridge) call(ctx context.Context, request linuxRequest) (*linuxResponse, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	if b.closed {
		return nil, fmt.Errorf("Linux bridge session is closed")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if b.cmd == nil {
		if err := b.start(); err != nil {
			return nil, err
		}
	}
	data, err := json.Marshal(request)
	if err != nil {
		return nil, err
	}
	input, reader := b.stdin, b.reader
	type result struct {
		response *linuxResponse
		err      error
	}
	finished := make(chan result, 1)
	go func() {
		if _, err := input.Write(append(data, '\n')); err != nil {
			finished <- result{err: err}
			return
		}
		line, err := reader.ReadBytes('\n')
		if err != nil {
			finished <- result{err: err}
			return
		}
		var response linuxResponse
		if err := json.Unmarshal(line, &response); err != nil {
			finished <- result{err: err}
			return
		}
		finished <- result{response: &response}
	}()
	select {
	case result := <-finished:
		if result.err != nil {
			b.stop()
			return nil, fmt.Errorf("Linux persistent bridge failed: %w", result.err)
		}
		return result.response, nil
	case <-ctx.Done():
		b.stop()
		// Killing/reaping the worker closes both pipes and joins the I/O goroutine.
		<-finished
		return nil, fmt.Errorf("Linux persistent bridge request cancelled: %w", ctx.Err())
	}
}

func (s *service) runPython(request linuxRequest) (*linuxResponse, error) {
	if s.bridge == nil {
		return runPython(request)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	return s.bridge.call(ctx, request)
}
