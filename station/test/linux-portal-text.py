#!/usr/bin/python3
"""Regression checks for Wayland committed text and keyboard lock handling, without a desktop session."""
import importlib.util
from collections import namedtuple
from pathlib import Path
import time
import unittest
from unittest.mock import patch

path = Path(__file__).resolve().parents[1] / "src/screens/linux-portal.py"
spec = importlib.util.spec_from_file_location("linux_portal_test", path)
portal = importlib.util.module_from_spec(spec)
spec.loader.exec_module(portal)


def wait_until(predicate):
    context = portal.GLib.MainContext.default()
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline:
        while context.pending():
            context.iteration(False)
        if predicate():
            return
        time.sleep(.005)
    raise AssertionError("text operation did not finish")


class KeyboardMap:
    """A single US-like layout, where Caps Lock reverses the effect of Shift on letters."""
    Entry = namedtuple("Entry", "keycode")
    Translation = namedtuple("Translation", "valid keyval")

    def get_modifier_state(self):
        return 0  # A Wayland client without focus may not have received the compositor's modifier state.

    def get_entries_for_keyval(self, value):
        code = {ord("h"): 43, ord("H"): 43, ord("1"): 10, ord("!"): 10}.get(value)
        return bool(code), [self.Entry(code)] if code else []

    def translate_keyboard_state(self, code, state, _group):
        state = int(state)
        shifted, locked = bool(state & 1), bool(state & 2)
        if code == 43:
            value = ord("H") if shifted != locked else ord("h")
        else:
            value = ord("!") if shifted else ord("1")
        return self.Translation(True, value)


class PortalTextTests(unittest.TestCase):
    def test_committed_uppercase_symbols_and_unicode_are_inserted_without_keysym_loss(self):
        for value in ("Hi! 123", "Hi!你好"):
            with self.subTest(value=value), patch.object(portal, "insert_focused_text", return_value="inserted") as insert:
                view = portal.Portal(session_bus=False)
                view.typing = True
                view.type_text(value)
                wait_until(lambda: not view.typing)
                self.assertEqual(insert.call_args.args[0], value)

    def test_an_uncertain_edit_is_not_retried_as_keyboard_input(self):
        view = portal.Portal(session_bus=False)
        view.typing = True
        with patch.object(portal, "insert_focused_text", return_value="unsafe"), \
             patch.object(view, "keymap_events") as keymap, patch.object(portal, "status") as status:
            view.type_text("Hi!")
            wait_until(view.stopped.is_set)
            keymap.assert_not_called()
            status.assert_called_once_with("input_error", code="textUnsupported")

    def test_unfocused_keymap_requires_a_known_caps_state_for_letters(self):
        view = portal.Portal(session_bus=False)
        view.keymap = KeyboardMap()
        with patch.object(view, "caps_lock_state", return_value=True):
            self.assertEqual(view.keymap_events("Hh!"), [
                (35, True), (35, False),
                (42, True), (35, True), (35, False), (42, False),
                (42, True), (2, True), (2, False), (42, False),
            ])
        with patch.object(view, "caps_lock_state", return_value=None):
            self.assertIsNone(view.keymap_events("H"))
            self.assertEqual(view.keymap_events("!"), [(42, True), (2, True), (2, False), (42, False)])

    def test_caps_state_is_used_only_when_visible_sessions_agree(self):
        class Bus:
            def __init__(self, states):
                self.states = states

            def call_sync(self, _service, path, _interface, method, *_args):
                if method == "Introspect":
                    nodes = "".join('<node name="u%d"/>' % i for i in range(len(self.states)))
                    return portal.GLib.Variant("(s)", ("<node>" + nodes + "</node>",))
                index = int(path.rsplit("u", 1)[1])
                return portal.GLib.Variant("(v)", (portal.GLib.Variant("b", self.states[index]),))

        view = portal.Portal(session_bus=False)
        for states, expected in (([True], True), ([False, False], False), ([True, False], None), ([], None)):
            with self.subTest(states=states):
                view.bus = Bus(states)
                self.assertIs(view.caps_lock_state(), expected)


if __name__ == "__main__":
    unittest.main()
