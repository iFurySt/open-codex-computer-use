package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestReadToolArgsAcceptsJSONObject(t *testing.T) {
	t.Parallel()

	args, err := readToolArgs(`{"app":"Feishu","clicks":2}`, "")
	if err != nil {
		t.Fatalf("readToolArgs returned error: %v", err)
	}

	if got, want := args["app"], "Feishu"; got != want {
		t.Fatalf("app = %#v, want %#v", got, want)
	}

	number, ok := args["clicks"].(json.Number)
	if !ok {
		t.Fatalf("clicks type = %T, want json.Number", args["clicks"])
	}
	if got, want := number.String(), "2"; got != want {
		t.Fatalf("clicks = %q, want %q", got, want)
	}
}

func TestReadToolArgsRejectsNonObject(t *testing.T) {
	t.Parallel()

	if _, err := readToolArgs(`["not","an","object"]`, ""); err == nil {
		t.Fatal("readToolArgs should reject non-object JSON")
	}
}

func TestReadToolCallSequenceAcceptsJSONArray(t *testing.T) {
	t.Parallel()

	calls, err := readToolCallSequence(`[{"tool":"get_app_state","args":{"app":"TextEdit"}},{"tool":"scroll","args":{"pages":1}}]`, "")
	if err != nil {
		t.Fatalf("readToolCallSequence returned error: %v", err)
	}
	if got, want := len(calls), 2; got != want {
		t.Fatalf("len(calls) = %d, want %d", got, want)
	}
	if got, want := calls[0].Tool, "get_app_state"; got != want {
		t.Fatalf("calls[0].Tool = %q, want %q", got, want)
	}

	number, ok := calls[1].Args["pages"].(json.Number)
	if !ok {
		t.Fatalf("pages type = %T, want json.Number", calls[1].Args["pages"])
	}
	if got, want := number.String(), "1"; got != want {
		t.Fatalf("pages = %q, want %q", got, want)
	}
}

func TestReadToolCallSequenceRejectsMissingTool(t *testing.T) {
	t.Parallel()

	if _, err := readToolCallSequence(`[{"args":{"app":"TextEdit"}}]`, ""); err == nil {
		t.Fatal("readToolCallSequence should reject a call without a tool name")
	}
}

func TestDiscoverPluginRootChoosesNewestCandidate(t *testing.T) {
	tempHome := t.TempDir()
	t.Setenv("HOME", tempHome)

	parent := filepath.Join(tempHome, defaultPluginVersionsDir)
	if err := os.MkdirAll(parent, 0o755); err != nil {
		t.Fatalf("mkdir parent: %v", err)
	}

	older := filepath.Join(parent, "1.0.0")
	newer := filepath.Join(parent, "1.0.1")
	createFakePluginRoot(t, older)
	createFakePluginRoot(t, newer)

	past := time.Now().Add(-time.Hour)
	if err := os.Chtimes(older, past, past); err != nil {
		t.Fatalf("chtimes older: %v", err)
	}

	root, err := discoverPluginRoot()
	if err != nil {
		t.Fatalf("discoverPluginRoot returned error: %v", err)
	}
	if got, want := root, newer; got != want {
		t.Fatalf("discoverPluginRoot = %q, want %q", got, want)
	}
}

func TestResolveTransportDefaultsToAppServer(t *testing.T) {
	t.Parallel()

	transport, err := resolveTransport(commonFlags{})
	if err != nil {
		t.Fatalf("resolveTransport returned error: %v", err)
	}
	if got, want := transport, transportAppServer; got != want {
		t.Fatalf("transport = %q, want %q", got, want)
	}
}

func TestResolveTransportUsesAppServerForBundledSkyBinary(t *testing.T) {
	t.Parallel()

	root := t.TempDir()
	createFakePluginRoot(t, root)

	transport, err := resolveTransport(commonFlags{pluginRoot: root})
	if err != nil {
		t.Fatalf("resolveTransport returned error: %v", err)
	}
	if got, want := transport, transportAppServer; got != want {
		t.Fatalf("transport = %q, want %q", got, want)
	}
}

func TestResolveTransportUsesDirectForExplicitNonSkyBinary(t *testing.T) {
	t.Parallel()

	root := t.TempDir()
	serverBin := filepath.Join(root, "open-computer-use.sh")
	if err := os.WriteFile(serverBin, []byte("#!/bin/sh\n"), 0o755); err != nil {
		t.Fatalf("write server bin: %v", err)
	}

	transport, err := resolveTransport(commonFlags{serverBin: serverBin})
	if err != nil {
		t.Fatalf("resolveTransport returned error: %v", err)
	}
	if got, want := transport, transportDirect; got != want {
		t.Fatalf("transport = %q, want %q", got, want)
	}
}

func TestResolveAppServerBinaryPrefersExplicitPath(t *testing.T) {
	t.Parallel()

	root := t.TempDir()
	appServerBin := filepath.Join(root, "codex")
	if err := os.WriteFile(appServerBin, []byte("#!/bin/sh\n"), 0o755); err != nil {
		t.Fatalf("write app-server bin: %v", err)
	}

	resolved, err := resolveAppServerBinary(commonFlags{appServerBin: appServerBin})
	if err != nil {
		t.Fatalf("resolveAppServerBinary returned error: %v", err)
	}
	if got, want := resolved, appServerBin; got != want {
		t.Fatalf("resolved binary = %q, want %q", got, want)
	}
}

func createFakePluginRoot(t *testing.T, root string) {
	t.Helper()

	serverBin := filepath.Join(root, defaultServerRelativeBin)
	if err := os.MkdirAll(filepath.Dir(serverBin), 0o755); err != nil {
		t.Fatalf("mkdir plugin root: %v", err)
	}
	if err := os.WriteFile(serverBin, []byte("stub"), 0o755); err != nil {
		t.Fatalf("write fake server bin: %v", err)
	}
}
