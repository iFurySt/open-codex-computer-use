import importlib.util
import pathlib
import os
import signal
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

    def prepare_x11(self):
        entry = types.SimpleNamespace(group=0, level=0, keycode=53)
        self.runtime.Gdk.Display = types.SimpleNamespace(get_default=lambda: types.SimpleNamespace(__gtype__=types.SimpleNamespace(name="GdkX11Display")))
        self.runtime.Gdk.Keymap = types.SimpleNamespace(get_for_display=lambda _: types.SimpleNamespace(get_entries_for_keyval=lambda _: (True, [entry])))

    def test_explicit_hold_uses_hardware_press_then_release(self):
        self.prepare_x11()
        with mock.patch.object(self.runtime.time, 'sleep') as sleep:
            # Fake delivery must explicitly report success, as real AT-SPI does.
            self.runtime.Atspi.generate_keyboard_event = lambda *args: self.events.append(args) or True
            self.runtime.send_key('x', 50)
        self.assertEqual(self.events, [(53, None, 'PRESS'), (53, None, 'RELEASE')])
        sleep.assert_called_once_with(.05)

    def test_release_and_modifiers_cleaned_up_when_hold_interrupted(self):
        self.prepare_x11()
        self.runtime.Atspi.generate_keyboard_event = lambda *args: self.events.append(args) or True
        with mock.patch.object(self.runtime.time, 'sleep', side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt):
                self.runtime.send_key('ctrl+x', 50)
        self.assertEqual(self.events[-2:], [(53, None, 'RELEASE'), (4, None, 'UNLOCKMODIFIERS')])

    def test_invalid_hold_is_rejected_before_any_events(self):
        for value in (0, -1, 1.5, True, '50', 5001):
            with self.assertRaises(RuntimeError):
                self.runtime.send_key('x', value)
        self.assertEqual(self.events, [])

    def test_release_failure_is_reported_and_modifier_unlocked(self):
        self.prepare_x11()
        def deliver(*args):
            self.events.append(args)
            return args[2] != 'RELEASE'
        self.runtime.Atspi.generate_keyboard_event = deliver
        with mock.patch.object(self.runtime.time, 'sleep'):
            with self.assertRaisesRegex(RuntimeError, 'release failed'):
                self.runtime.send_key('ctrl+x', 50)
        self.assertEqual(self.events[-1], (4, None, 'UNLOCKMODIFIERS'))

    def test_sigterm_during_hold_releases_and_restores_handler(self):
        self.prepare_x11()
        self.runtime.Atspi.generate_keyboard_event = lambda *args: self.events.append(args) or True
        before = signal.getsignal(signal.SIGTERM)
        with mock.patch.object(self.runtime.time, 'sleep', side_effect=lambda _: os.kill(os.getpid(), signal.SIGTERM)):
            with self.assertRaises(KeyboardInterrupt):
                self.runtime.send_key('ctrl+x', 50)
        self.assertEqual(self.events[-2:], [(53, None, 'RELEASE'), (4, None, 'UNLOCKMODIFIERS')])
        self.assertEqual(signal.getsignal(signal.SIGTERM), before)

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


if __name__ == "__main__":
    unittest.main()
