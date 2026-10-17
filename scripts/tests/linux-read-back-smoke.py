#!/usr/bin/env python3
"""Exercise native Linux MCP actions against an isolated real GTK fixture."""

import argparse
import json
import os
from pathlib import Path
import re
import select
import subprocess
import sys
import tempfile
import time


def fixture(name, state_file):
    import gi

    gi.require_version("Gtk", "3.0")
    gi.require_version("Gdk", "3.0")
    from gi.repository import Gdk, GLib, Gtk

    GLib.set_prgname(name)
    GLib.set_application_name(name)
    window = Gtk.Window(title=name)
    window.set_default_size(500, 240)
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=20)
    window.add(box)
    entry = Gtk.Entry()
    entry.get_accessible().set_name("Read-back input")
    button = Gtk.Button(label="Increment")
    label = Gtk.Label(label="Counter: 0")
    for widget in (entry, button, label):
        box.pack_start(widget, False, False, 0)
    state = {"count": 0, "text": "", "activated": 0}

    def publish(*_args):
        state["text"] = entry.get_text()
        state["focused"] = entry.has_focus()
        temporary = state_file.with_suffix(".tmp")
        temporary.write_text(json.dumps(state))
        temporary.replace(state_file)

    def increment(*_args):
        state["count"] += 1
        label.set_text("Counter: " + str(state["count"]))
        entry.grab_focus()
        window.get_window().focus(Gdk.CURRENT_TIME)
        publish()

    def activate(*_args):
        state["activated"] += 1
        publish()

    button.connect("clicked", increment)
    entry.connect("changed", publish)
    entry.connect("activate", activate)
    window.connect("destroy", Gtk.main_quit)
    window.show_all()
    entry.grab_focus()
    window.get_window().focus(Gdk.CURRENT_TIME)
    publish()
    Gtk.main()


def wait_for(predicate, description):
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.03)
    raise AssertionError("Timed out: " + description)


class MCP:
    def __init__(self, native, read_back, stderr):
        env = dict(os.environ)
        env.pop("OPEN_COMPUTER_USE_ACTION_READ_BACK", None)
        if read_back is not None:
            env["OPEN_COMPUTER_USE_ACTION_READ_BACK"] = read_back
        self.process = subprocess.Popen(
            [native, "mcp"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=stderr, env=env, text=True,
        )
        self.next_id = 0
        try:
            self.request("initialize", {"protocolVersion": "2025-03-26", "capabilities": {},
                                        "clientInfo": {"name": "linux-read-back-smoke", "version": "1"}})
            self.process.stdin.write(json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}) + "\n")
            self.process.stdin.flush()
        except Exception:
            self.close()
            raise

    def request(self, method, params):
        self.next_id += 1
        self.process.stdin.write(json.dumps({"jsonrpc": "2.0", "id": self.next_id,
                                            "method": method, "params": params}) + "\n")
        self.process.stdin.flush()
        ready, _, _ = select.select([self.process.stdout], [], [], 40)
        if not ready:
            raise AssertionError("MCP response timed out: " + method)
        line = self.process.stdout.readline()
        if not line:
            raise AssertionError("Native MCP exited before responding: " + method)
        response = json.loads(line)
        assert response.get("id") == self.next_id, response
        assert "error" not in response, response
        return response["result"]

    def call(self, tool, app, **arguments):
        return self.request("tools/call", {"name": tool, "arguments": {"app": app, **arguments}})

    def close(self):
        try:
            self.process.stdin.close()
        except BrokenPipeError:
            pass
        try:
            self.process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait()


def text(result):
    return "\n".join(item["text"] for item in result["content"] if item["type"] == "text")


def expect_snapshot(result):
    assert not result.get("isError"), result
    assert "Window:" in text(result) and "Read-back input" in text(result), text(result)


def element_index(result, name):
    matches = re.findall(r"^\s*(\d+)\s+[^\n]*" + re.escape(name) + r"(?:\s|$)", text(result), re.MULTILINE)
    assert len(matches) == 1, (name, text(result))
    return matches[0]


def smoke(native):
    with tempfile.TemporaryDirectory(prefix="ocu-read-back-smoke-") as directory:
        directory = Path(directory)
        state_file = directory / "state.json"
        name = "OCUReadBackFixture" + str(os.getpid())
        with (directory / "stderr.log").open("w+") as stderr:
            process = subprocess.Popen([sys.executable, __file__, "--fixture", name,
                                        "--state-file", str(state_file)], stderr=stderr)
            clients = []
            try:
                wait_for(state_file.exists, "GTK fixture startup")
                client = MCP(native, " OFF ", stderr)
                clients.append(client)
                # AT-SPI registration follows GTK startup asynchronously.
                wait_for(lambda: not client.call("get_app_state", name).get("isError"), "AT-SPI registration")
                observed = client.call("get_app_state", name)
                expect_snapshot(observed)
                input_index = element_index(observed, "Read-back input")
                button_index = element_index(observed, "Increment")

                def state_is(**expected):
                    actual = json.loads(state_file.read_text())
                    return all(actual[key] == value for key, value in expected.items())

                def acknowledged(tool, **arguments):
                    result = client.call(tool, name, **arguments)
                    assert not result.get("isError"), result
                    assert result["content"] == [{"type": "text", "text": "ok"}], result

                acknowledged("set_value", element_index=input_index, value="hello-中文-🙂")
                wait_for(lambda: state_is(text="hello-中文-🙂"), "real entry set_value")
                for count in (1, 2):
                    acknowledged("click", element_index=button_index, click_method="accessibility")
                    wait_for(lambda: state_is(count=count), "cached-index button click")
                acknowledged("perform_secondary_action", element_index=button_index, action="click")
                wait_for(lambda: state_is(count=3), "real secondary action")
                acknowledged("type_text", text="-typed")
                wait_for(lambda: state_is(text="hello-中文-🙂-typed"), "real entry insertion")
                acknowledged("press_key", key="Return")
                wait_for(lambda: state_is(activated=1), "real Return delivery")
                for tool, arguments in (
                    ("set_value", {"element_index": button_index, "value": "invalid"}),
                    ("perform_secondary_action", {"element_index": button_index, "action": "not-an-action"}),
                ):
                    result = client.call(tool, name, **arguments)
                    assert result.get("isError") and text(result) != "ok", result
                refreshed = client.call("get_app_state", name)
                expect_snapshot(refreshed)
                assert "hello-中文-🙂-typed" in text(refreshed), text(refreshed)
                assert "Counter: 3" in text(refreshed), text(refreshed)
                print("Disabled read-back: real actions, preserved indexes, errors and explicit observation passed.")

                default = MCP(native, None, stderr)
                clients.append(default)
                observed = default.call("get_app_state", name)
                expect_snapshot(observed)
                result = default.call("set_value", name, element_index=element_index(observed, "Read-back input"), value="default-read-back")
                expect_snapshot(result)
                assert "default-read-back" in text(result), text(result)
                wait_for(lambda: state_is(text="default-read-back"), "default action state")
                print("Default read-back: real action returns an updated snapshot.")
            except Exception:
                if state_file.exists():
                    print("Fixture state:", state_file.read_text(), file=sys.stderr)
                stderr.flush()
                stderr.seek(0)
                print(stderr.read(), file=sys.stderr)
                raise
            finally:
                for client in clients:
                    client.close()
                process.terminate()
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native")
    parser.add_argument("--fixture")
    parser.add_argument("--state-file", type=Path)
    args = parser.parse_args()
    if args.fixture:
        fixture(args.fixture, args.state_file)
    else:
        if not args.native:
            parser.error("--native is required")
        smoke(str(Path(args.native).resolve()))
