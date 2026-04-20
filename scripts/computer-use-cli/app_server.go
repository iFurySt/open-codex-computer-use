package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync/atomic"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

const (
	transportAuto                  = "auto"
	transportDirect                = "direct"
	transportAppServer             = "app-server"
	appServerBinEnvVar             = "CODEX_APP_SERVER_BIN"
	defaultAppServerServerName     = "computer-use"
	defaultAppServerApprovalPolicy = "never"
	defaultAppServerSandbox        = "danger-full-access"
	defaultCodexAppBinary          = "/Applications/Codex.app/Contents/Resources/codex"
)

type appServerSession struct {
	cmd      *exec.Cmd
	stdin    io.WriteCloser
	messages chan appServerMessage
	readErr  chan error
	nextID   int64
}

type appServerInitializeParams struct {
	ClientInfo *mcp.Implementation `json:"clientInfo"`
}

type appServerListMcpStatusParams struct {
	Detail string `json:"detail,omitempty"`
}

type appServerListMcpStatusResult struct {
	Data []*appServerMcpStatus `json:"data"`
}

type appServerMcpStatus struct {
	Name       string               `json:"name"`
	Tools      map[string]*mcp.Tool `json:"tools"`
	AuthStatus string               `json:"authStatus"`
}

type appServerThreadStartParams struct {
	ApprovalPolicy string `json:"approvalPolicy,omitempty"`
	Cwd            string `json:"cwd,omitempty"`
	Ephemeral      bool   `json:"ephemeral"`
	Sandbox        string `json:"sandbox,omitempty"`
}

type appServerThreadStartResult struct {
	Thread appServerThread `json:"thread"`
}

type appServerThread struct {
	ID string `json:"id"`
}

type appServerToolCallParams struct {
	ThreadID  string         `json:"threadId"`
	Server    string         `json:"server"`
	Tool      string         `json:"tool"`
	Arguments map[string]any `json:"arguments,omitempty"`
}

type appServerMessage struct {
	ID     any             `json:"id,omitempty"`
	Method string          `json:"method,omitempty"`
	Params json.RawMessage `json:"params,omitempty"`
	Result json.RawMessage `json:"result,omitempty"`
	Error  *appServerError `json:"error,omitempty"`
}

type appServerError struct {
	Code    int             `json:"code"`
	Message string          `json:"message"`
	Data    json.RawMessage `json:"data,omitempty"`
}

func (e *appServerError) Error() string {
	if e == nil {
		return ""
	}
	return fmt.Sprintf("code %d: %s", e.Code, e.Message)
}

func resolveTransport(flags commonFlags) (string, error) {
	switch flags.transport {
	case "", transportAuto:
		if flags.appServerBin != "" {
			return transportAppServer, nil
		}
		if flags.serverBin == "" && flags.pluginRoot == "" {
			return transportAppServer, nil
		}

		target, err := resolveTarget(flags)
		if err != nil {
			return "", err
		}
		if isSkyComputerUseBinary(target.ServerBin) {
			return transportAppServer, nil
		}
		return transportDirect, nil
	case transportDirect, transportAppServer:
		return flags.transport, nil
	default:
		return "", fmt.Errorf("invalid --transport %q: want %q, %q, or %q", flags.transport, transportAuto, transportDirect, transportAppServer)
	}
}

func connectAppServer(ctx context.Context, flags commonFlags) (*appServerSession, error) {
	appServerBin, err := resolveAppServerBinary(flags)
	if err != nil {
		return nil, err
	}

	threadCwd, err := resolveThreadCwd(flags)
	if err != nil {
		return nil, err
	}

	cmd := exec.Command(appServerBin, "app-server")
	cmd.Dir = threadCwd
	cmd.Stderr = os.Stderr

	stdin, err := cmd.StdinPipe()
	if err != nil {
		return nil, fmt.Errorf("open stdin for %q: %w", appServerBin, err)
	}
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return nil, fmt.Errorf("open stdout for %q: %w", appServerBin, err)
	}
	if err := cmd.Start(); err != nil {
		return nil, fmt.Errorf("start %q: %w", appServerBin, err)
	}

	session := &appServerSession{
		cmd:      cmd,
		stdin:    stdin,
		messages: make(chan appServerMessage, 32),
		readErr:  make(chan error, 1),
	}
	go session.readLoop(stdout)

	connectCtx, cancel := context.WithTimeout(ctx, flags.timeout)
	defer cancel()
	if err := session.initialize(connectCtx); err != nil {
		_ = session.Close()
		return nil, fmt.Errorf("initialize app-server session: %w", err)
	}
	return session, nil
}

func (s *appServerSession) Close() error {
	if s.stdin != nil {
		_ = s.stdin.Close()
	}
	if s.cmd != nil && s.cmd.Process != nil {
		_ = s.cmd.Process.Kill()
		_ = s.cmd.Wait()
	}
	return nil
}

func (s *appServerSession) initialize(ctx context.Context) error {
	var result map[string]any
	if err := s.request(ctx, "initialize", appServerInitializeParams{
		ClientInfo: &mcp.Implementation{
			Name:    cliName,
			Version: cliVersion,
			Title:   cliName,
		},
	}, &result); err != nil {
		return err
	}

	return s.notify("initialized", map[string]any{})
}

func (s *appServerSession) listToolsViaAppServer(ctx context.Context, serverName string) (*mcp.ListToolsResult, error) {
	var result appServerListMcpStatusResult
	if err := s.request(ctx, "mcpServerStatus/list", appServerListMcpStatusParams{
		Detail: "toolsAndAuthOnly",
	}, &result); err != nil {
		return nil, err
	}

	status, err := findAppServerStatus(result.Data, serverName)
	if err != nil {
		return nil, err
	}

	return &mcp.ListToolsResult{Tools: sortToolMap(status.Tools)}, nil
}

func (s *appServerSession) callToolViaAppServer(
	ctx context.Context,
	flags commonFlags,
	toolName string,
	toolArgs map[string]any,
) (*mcp.CallToolResult, error) {
	threadID, err := s.startEphemeralThread(ctx, flags)
	if err != nil {
		return nil, err
	}

	return s.callToolOnThread(ctx, threadID, flags.serverName, toolName, toolArgs)
}

func (s *appServerSession) startEphemeralThread(ctx context.Context, flags commonFlags) (string, error) {
	threadCwd, err := resolveThreadCwd(flags)
	if err != nil {
		return "", err
	}

	var thread appServerThreadStartResult
	if err := s.request(ctx, "thread/start", appServerThreadStartParams{
		ApprovalPolicy: flags.approvalPolicy,
		Cwd:            threadCwd,
		Ephemeral:      true,
		Sandbox:        flags.sandbox,
	}, &thread); err != nil {
		return "", fmt.Errorf("start ephemeral thread: %w", err)
	}
	if thread.Thread.ID == "" {
		return "", fmt.Errorf("app-server returned an empty thread id")
	}
	return thread.Thread.ID, nil
}

func (s *appServerSession) callToolOnThread(
	ctx context.Context,
	threadID string,
	serverName string,
	toolName string,
	toolArgs map[string]any,
) (*mcp.CallToolResult, error) {
	var result mcp.CallToolResult
	if err := s.request(ctx, "mcpServer/tool/call", appServerToolCallParams{
		ThreadID:  threadID,
		Server:    serverName,
		Tool:      toolName,
		Arguments: toolArgs,
	}, &result); err != nil {
		return nil, err
	}
	return &result, nil
}

func callToolSequenceViaAppServer(
	ctx context.Context,
	session *appServerSession,
	flags commonFlags,
	calls []toolCallSpec,
) ([]toolCallOutput, error) {
	threadCtx, cancel := context.WithTimeout(ctx, flags.timeout)
	threadID, err := session.startEphemeralThread(threadCtx, flags)
	cancel()
	if err != nil {
		return nil, err
	}

	results := make([]toolCallOutput, 0, len(calls))
	for i, call := range calls {
		callCtx, cancel := context.WithTimeout(ctx, flags.timeout)
		result, err := session.callToolOnThread(callCtx, threadID, flags.serverName, call.Tool, call.Args)
		cancel()
		if err != nil {
			return nil, fmt.Errorf("call #%d %q via app-server: %w", i+1, call.Tool, err)
		}
		results = append(results, toolCallOutput{
			Tool:   call.Tool,
			Result: result,
		})
	}
	return results, nil
}

func (s *appServerSession) request(ctx context.Context, method string, params any, out any) error {
	requestID := atomic.AddInt64(&s.nextID, 1)

	if err := s.sendMessage(map[string]any{
		"id":     requestID,
		"method": method,
		"params": params,
	}); err != nil {
		return fmt.Errorf("write %q request: %w", method, err)
	}

	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case err := <-s.readErr:
			return fmt.Errorf("read %q response: %w", method, err)
		case message := <-s.messages:
			if message.Method != "" {
				if message.ID != nil {
					return fmt.Errorf("server sent unexpected request %q while waiting for %q", message.Method, method)
				}
				continue
			}

			if !appServerMessageIDMatches(message.ID, requestID) {
				continue
			}
			if message.Error != nil {
				return fmt.Errorf("%q failed: %w", method, message.Error)
			}
			if out == nil || len(message.Result) == 0 {
				return nil
			}
			if err := json.Unmarshal(message.Result, out); err != nil {
				return fmt.Errorf("decode %q response: %w", method, err)
			}
			return nil
		}
	}
}

func (s *appServerSession) notify(method string, params any) error {
	if err := s.sendMessage(map[string]any{
		"method": method,
		"params": params,
	}); err != nil {
		return fmt.Errorf("write %q notification: %w", method, err)
	}
	return nil
}

func (s *appServerSession) sendMessage(message any) error {
	data, err := json.Marshal(message)
	if err != nil {
		return err
	}
	if _, err := s.stdin.Write(append(data, '\n')); err != nil {
		return err
	}
	return nil
}

func (s *appServerSession) readLoop(stdout io.Reader) {
	reader := bufio.NewReader(stdout)
	for {
		line, err := reader.ReadBytes('\n')
		if len(bytes.TrimSpace(line)) > 0 {
			var message appServerMessage
			if unmarshalErr := json.Unmarshal(bytes.TrimSpace(line), &message); unmarshalErr != nil {
				s.readErr <- fmt.Errorf("decode app-server message: %w", unmarshalErr)
				return
			}
			s.messages <- message
		}

		if err != nil {
			s.readErr <- err
			return
		}
	}
}

func appServerMessageIDMatches(rawID any, want int64) bool {
	switch value := rawID.(type) {
	case nil:
		return false
	case float64:
		return int64(value) == want
	case json.Number:
		got, err := value.Int64()
		return err == nil && got == want
	case string:
		return value == strconv.FormatInt(want, 10)
	default:
		return fmt.Sprint(value) == strconv.FormatInt(want, 10)
	}
}

func resolveAppServerBinary(flags commonFlags) (string, error) {
	if path := firstNonEmpty(flags.appServerBin, os.Getenv(appServerBinEnvVar)); path != "" {
		return validateAppServerBinary(path)
	}

	candidates := []string{defaultCodexAppBinary}
	if path, err := exec.LookPath("codex"); err == nil {
		candidates = append(candidates, path)
	}

	var checked []string
	for _, candidate := range candidates {
		if strings.TrimSpace(candidate) == "" {
			continue
		}
		normalized, err := validateAppServerBinary(candidate)
		if err == nil {
			return normalized, nil
		}
		checked = append(checked, candidate)
	}

	return "", fmt.Errorf(
		"could not find a usable Codex binary for app-server mode; checked %s; pass --app-server-bin or set %s",
		strings.Join(checked, ", "),
		appServerBinEnvVar,
	)
}

func validateAppServerBinary(path string) (string, error) {
	normalized, err := normalizePath(path)
	if err != nil {
		return "", err
	}

	info, err := os.Stat(normalized)
	if err != nil {
		return "", fmt.Errorf("stat app-server binary %q: %w", normalized, err)
	}
	if info.IsDir() {
		return "", fmt.Errorf("app-server binary %q is a directory", normalized)
	}
	return normalized, nil
}

func resolveThreadCwd(flags commonFlags) (string, error) {
	if flags.cwd != "" {
		return normalizePath(flags.cwd)
	}

	wd, err := os.Getwd()
	if err != nil {
		return "", fmt.Errorf("resolve current working directory: %w", err)
	}
	return normalizePath(wd)
}

func isSkyComputerUseBinary(path string) bool {
	cleanPath := filepath.Clean(path)
	return filepath.Base(cleanPath) == "SkyComputerUseClient" && strings.HasSuffix(cleanPath, filepath.Clean(defaultServerRelativeBin))
}

func findAppServerStatus(statuses []*appServerMcpStatus, serverName string) (*appServerMcpStatus, error) {
	available := make([]string, 0, len(statuses))
	for _, status := range statuses {
		if status == nil {
			continue
		}
		available = append(available, status.Name)
		if status.Name == serverName {
			return status, nil
		}
	}
	sort.Strings(available)
	return nil, fmt.Errorf("server %q not found in app-server inventory; available servers: %s", serverName, strings.Join(available, ", "))
}

func sortToolMap(toolMap map[string]*mcp.Tool) []*mcp.Tool {
	if len(toolMap) == 0 {
		return nil
	}

	names := make([]string, 0, len(toolMap))
	for name := range toolMap {
		names = append(names, name)
	}
	sort.Strings(names)

	tools := make([]*mcp.Tool, 0, len(names))
	for _, name := range names {
		tool := toolMap[name]
		if tool == nil {
			tool = &mcp.Tool{Name: name}
		} else if tool.Name == "" {
			tool.Name = name
		}
		tools = append(tools, tool)
	}
	return tools
}
