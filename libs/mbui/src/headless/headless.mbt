// Headless components (无头组件; the user, 2026-11-14): each is one kind of control as a part of the window's tree, made
// once, that is all the control is to the hand, the keyboard and a screen reader, and draws nothing. Its look is its
// caller's: an app's library of looks (or a default one) is written over these, and writes looks only.
//
// Three layers, and what is whose:
//
//   the framework (src/view)   what any node has, whatever it is: whose a press is and when it runs (on_press, presses;
//                              asked by what is no hand, View::press), the keyboard's focus, its order and what gives
//                              it back (focusable, takes_keys, in_use), the keys that press what has it, actions and
//                              their keys (on_action, the keymap), what is read out and what a screen reader asks
//                              (says, Activate), the pointer over a node and held on it (pointed, pressed), layers, a
//                              list's window (scrolls_window). A component uses these and does none of them again.
//   a headless component       one kind of control made of those: the node it is, the role and the name it says, when
//   (this package)             it takes a press and the focus and when neither, what a press does however it came
//                              (the pointer, a key, a screen reader), and what its look reads of it (a struct of
//                              functions: followed where a binding reads them). It sets nothing that is drawn or laid
//                              out, and knows no theme.
//   a look (an app's library)  all that is seen: sizes, padding, grounds, words and their ink, icons, the focus ring,
//                              the pointer's shape, what moves and how (a way set off by a state it reads here), and
//                              what the control holds besides (a spinner, a tip).
//
// The rule a control is divided by. The button (button.mbt) is its sample (「在这里先做按钮当样板」): a control of one
// node, pressed one way. What it answers, and what it leaves open, is said here; a later component that finds the rule
// wanting changes it here, with its reason.
//
// Whose a thing is. Four judge it: a screen reader, the keyboard, a test that finds by role and name, and the hand.
//
//   - what a screen reader, the keyboard or such a test could tell changed is the component's;
//   - so is what the hand could: when a pointer's press counts (how far it may move first, how long it may be held, let
//     go off it). For a node pressed plainly that is the framework's press, and the component adds nothing. A control
//     that wants more of the pointer (a hold of its own beside its press, or a press held past a hold's time and let go
//     on it) is given it by its component, as a parameter (`Hold` on `button` and `toggle`, `hold_press` on `toggle`):
//     still.fail's icon button and bar tool hold their tip up by a finger's long press (`Hold`), and its switch turns on
//     a press held however long and let go on it (`hold_press`). The tip is that app's; when a press counts is the
//     component's;
//   - what only an eye could tell is the look's;
//   - what every node has whatever it is is the framework's: used, never written again here. What a component needs of
//     the tree and is not there is added to src/view (View::press, for a press asked by what is no hand), never gone
//     around here: of mbui this package's own files import the tree alone (moon.pkg);
//   - what one app alone wants of a control stays in that app's look, over the component: never a parameter here.
//
// State. Who keeps it: the caller. A component is controlled: what decides what the control takes or says (the
// button's `disabled`; a toggle's `on`, what opens something's `open`, a choice's `chosen`) is a function its caller
// gives it, and what the hand asks is told the caller (the button's `press`), who writes it. The component keeps only
// what nobody outside needs (which of a menu's items the keys are on). A state only the eye is told is the look's and
// no parameter here, the look taking it from its own caller. The sample's own case: a button at work takes no press and
// no focus, which to all four judges is disabled (a node says no such word: view's Said), so a library gives
// `disabled() || busy()` and its look reads `busy` for its spinner; and which of the states light a ground (the focus
// shown, hovered, pressed) is a look's choice, made of the readings. A state crosses from look to component as one of
// the four comes to be told it: were a screen reader to hear "busy", that is first a word of Said in src/view, then a
// parameter of the button, which says it.
//
// From look to component nothing flows that is not said: a component never reads what its look set. Where the
// keyboard's part depends on what is also seen (which way a slider runs; the side a menu opens on, which decides the
// arrow key that closes a submenu), that is a parameter the caller gives the component, the look given the same.
//
// What a component says of its node, and what a look may. A component makes its node at its caller's place (`loc~`:
// the look's line; `made_for`, where a library's part over it was asked for), hands that node and what is read of it
// to `look` once, as it is made, and then says its own words of the node (the button's: presses, focusable, says,
// on_press). Said after the look has run, those stand whatever the look said of them then, and that is all the order
// gives. A look keeps the node: it can say anything of it later (in a handler, a reaction); and other words of a node
// change what the component promised without touching its own: hides (not read out), in_use (no keys), bones (no
// press), modal, takes (where a finger is taken), on_drag and gesture (the pointer theirs, never reaching on_press: the
// icon button's debt above). So it is a convention, held by no check: of a component's node a look says what is drawn and
// laid out, and none of these.
//
// A control of several parts (radio_group.mbt: a group of radio buttons or a bar's tabs, its items fixed or made by
// `each`): the component makes the group's node, hands it and the group (`RadioGroup[K]`) to its look once, and each
// `RadioGroup::item` makes that item's node, hands it and what is read of it (`RadioItem`) to the item's look once,
// and says the item's own words after its look has run, keeping the roving Tab stop and the arrow keys across the
// living enabled items.
//
// A component is tested under a look of the tests' own, found by role and name, each window made by the tests'
// `window` (window_test.mbt), which holds of every node in it that nothing said from this package's own files is drawn
// or laid out by.
