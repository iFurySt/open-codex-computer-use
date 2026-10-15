import importlib.util
import pathlib
import sys
import types
import unittest
from unittest import mock


class FakeText:
    @staticmethod
    def get_character_count(_interface):
        return 5

    @staticmethod
    def get_text(_interface, _start, _end):
        return "hello"


class FakeEditableText:
    @staticmethod
    def insert_text(_interface, _offset, _text, _length):
        return True

    @staticmethod
    def set_text_contents(_interface, _text):
        return True


def load_runtime():
    gi = types.ModuleType("gi")
    gi.require_version = lambda *_args: None
    repository = types.ModuleType("gi.repository")
    repository.Atspi = types.SimpleNamespace(
        Text=FakeText,
        EditableText=FakeEditableText,
    )
    repository.Gdk = types.SimpleNamespace()
    gi.repository = repository

    runtime_path = pathlib.Path(__file__).with_name("runtime.py")
    spec = importlib.util.spec_from_file_location("open_computer_use_linux_runtime", runtime_path)
    module = importlib.util.module_from_spec(spec)
    with mock.patch.dict(
        sys.modules,
        {"gi": gi, "gi.repository": repository},
    ):
        spec.loader.exec_module(module)
    return module


class InterfaceOnlyAccessible:
    def __init__(self, interfaces):
        self.interfaces = interfaces

    def get_interfaces(self):
        return self.interfaces

    def get_text_iface(self):
        return self

    def get_editable_text_iface(self):
        return self

    def get_child_count(self):
        return 0


class RuntimeInterfaceDetectionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.runtime = load_runtime()

    def test_text_value_uses_accessible_interfaces(self):
        node = InterfaceOnlyAccessible(["Accessible", "Text"])

        self.assertEqual(self.runtime.text_value(node), "hello")

    def test_insert_text_uses_accessible_interfaces(self):
        node = InterfaceOnlyAccessible(["Accessible", "Text", "EditableText"])

        self.assertTrue(self.runtime.insert_text(node, "hello"))

    def test_set_value_uses_accessible_interfaces(self):
        node = InterfaceOnlyAccessible(["Accessible", "Text", "EditableText"])

        self.assertTrue(self.runtime.set_element_value(node, "hello"))


class FakeKeySynthType:
    PRESS = "PRESS"
    RELEASE = "RELEASE"
    PRESSRELEASE = "PRESSRELEASE"
    SYM = "SYM"
    STRING = "STRING"
    LOCKMODIFIERS = "LOCKMODIFIERS"
    UNLOCKMODIFIERS = "UNLOCKMODIFIERS"


class FakeModifierType:
    SHIFT = 0
    CONTROL = 2
    ALT = 3
    META3 = 6


KEYSYMS = {"Return": 0xFF0D, "Tab": 0xFF09, "Down": 0xFF54}


class RuntimeKeyTests(unittest.TestCase):
    def setUp(self):
        self.runtime = load_runtime()
        self.events = []
        self.runtime.Atspi = types.SimpleNamespace(
            KeySynthType=FakeKeySynthType,
            ModifierType=FakeModifierType,
            generate_keyboard_event=lambda value, text, synth: self.events.append(
                (value, text, synth)
            ),
        )
        self.runtime.Gdk = types.SimpleNamespace(
            # Like GDK, unknown names map to VoidSymbol rather than 0.
            keyval_from_name=lambda name: KEYSYMS.get(name, 0xFFFFFF),
            unicode_to_keyval=lambda codepoint: codepoint,
        )

    def test_named_key_is_sent_as_keysym(self):
        self.runtime.send_key("Enter")

        self.assertEqual(self.events, [(0xFF0D, None, "SYM")])

    def test_modifiers_are_held_around_the_key(self):
        self.runtime.send_key("ctrl+shift+Tab")

        mask = (1 << FakeModifierType.CONTROL) | (1 << FakeModifierType.SHIFT)
        self.assertEqual(
            self.events,
            [
                (mask, None, "LOCKMODIFIERS"),
                (0xFF09, None, "SYM"),
                (mask, None, "UNLOCKMODIFIERS"),
            ],
        )

    def test_modified_character_is_sent_as_keysym(self):
        self.runtime.send_key("ctrl+a")

        mask = 1 << FakeModifierType.CONTROL
        self.assertEqual(self.events[1], (ord("a"), None, "SYM"))
        self.assertEqual(self.events[0], (mask, None, "LOCKMODIFIERS"))

    def test_modified_punctuation_is_sent_as_keysym(self):
        self.runtime.send_key("ctrl+/")

        self.assertEqual(self.events[1], (ord("/"), None, "SYM"))

    def test_unknown_key_name_is_rejected(self):
        with self.assertRaises(RuntimeError):
            self.runtime.send_key("NoSuchKey")

        self.assertEqual(self.events, [])

    def test_plain_character_is_typed(self):
        self.runtime.send_key("a")

        self.assertEqual(self.events, [(0, "a", "STRING")])

    def test_unknown_modifier_is_rejected(self):
        with self.assertRaises(RuntimeError):
            self.runtime.send_key("hyper+a")

        self.assertEqual(self.events, [])


class TextDeliveryTests(unittest.TestCase):
    def setUp(self):
        self.runtime = load_runtime()
        self.runtime.Atspi.StateType = types.SimpleNamespace(ACTIVE="active")
        self.runtime.Gdk.unicode_to_keyval = lambda codepoint: codepoint

    def perform(self, method, text="  中文🙂\n\t ", active=True):
        with mock.patch.object(self.runtime, "resolve_app"), \
             mock.patch.object(self.runtime, "main_window", return_value=(0, object())), \
             mock.patch.object(self.runtime, "extents"), \
             mock.patch.object(self.runtime, "find_element"), \
             mock.patch.object(self.runtime, "state_contains", return_value=active), \
             mock.patch.object(self.runtime, "build_snapshot", return_value={}), \
             mock.patch.object(self.runtime.time, "sleep"):
            return self.runtime.perform_operation({"tool": "type_text", "app": "Editor", "text": text, "text_method": method})

    def test_keyboard_and_paste_do_not_search_for_other_editable_controls(self):
        for method, handler in (("keyboard", "send_text"), ("paste", "paste_text")):
            with self.subTest(method=method), \
                 mock.patch.object(self.runtime, "insert_text") as insert, \
                 mock.patch.object(self.runtime, handler) as delivery:
                self.perform(method)
                self.assertEqual(delivery.call_args.args[0], "  中文🙂\n\t ")
                insert.assert_not_called()

    def test_default_auto_retains_legacy_fallback(self):
        with mock.patch.object(self.runtime, "insert_text", return_value=False) as insert, \
             mock.patch.object(self.runtime, "send_text") as keyboard:
            self.perform("auto", "hello")
        insert.assert_called_once()
        keyboard.assert_called_once_with("hello")

    def test_explicit_delivery_refuses_inactive_window_and_does_not_fallback(self):
        for method in ("keyboard", "paste"):
            with self.subTest(method=method), \
                 mock.patch.object(self.runtime, "send_text") as keyboard, \
                 mock.patch.object(self.runtime, "paste_text") as paste, \
                 mock.patch.object(self.runtime, "insert_text") as insert:
                with self.assertRaisesRegex(RuntimeError, "active"):
                    self.perform(method, active=False)
                keyboard.assert_not_called(); paste.assert_not_called(); insert.assert_not_called()

    def test_paste_preserves_unicode_and_uses_explicit_shortcut(self):
        clipboard = mock.Mock()
        self.runtime.Atspi.ModifierType = FakeModifierType
        with mock.patch.object(self.runtime, "x11_clipboard", return_value=(object(), clipboard)), \
             mock.patch.object(self.runtime, "send_key") as key, \
             mock.patch.object(self.runtime, "service_clipboard") as service:
            self.runtime.paste_text("  中文🙂\n\t ", "ctrl+shift+v")
        clipboard.set_text.assert_called_once_with("  中文🙂\n\t ", -1)
        key.assert_called_once_with("ctrl+shift+v")
        service.assert_called_once()
        clipboard.store.assert_called_once()

    def test_paste_failure_is_not_retried_as_keyboard_or_ax(self):
        with mock.patch.object(self.runtime, "paste_text", side_effect=RuntimeError("clipboard unavailable")), \
             mock.patch.object(self.runtime, "send_text") as keyboard, \
             mock.patch.object(self.runtime, "insert_text") as insert:
            with self.assertRaisesRegex(RuntimeError, "clipboard unavailable"):
                self.perform("paste")
        keyboard.assert_not_called(); insert.assert_not_called()

    def test_invalid_shortcut_does_not_replace_clipboard(self):
        with mock.patch.object(self.runtime, "x11_clipboard") as clipboard:
            with self.assertRaisesRegex(RuntimeError, "Unsupported modifier"):
                self.runtime.paste_text("secret", "invalid+v")
        clipboard.assert_not_called()


if __name__ == "__main__":
    unittest.main()
