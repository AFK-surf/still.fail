# Components

mbui's components are Radix Primitives' set (radix-ui.com/primitives), drawn by mbui itself: behaviour as Radix
documents it (its keyboard, its focus, its dismissing, its states), adapted to touch where a phone has no keyboard or
pointer; motion as Motion (motion.dev) models it. They live in `src/kit` (`@kit.switch(c, …)`); what they stand on
lives in `src/ui` (the theme, the response, the semantics tree, the focus, the layers over the page). `src/kitdemo` is
the gallery: every component in its states, light beside dark (`APP=kitdemo`, `MBUI_SCREEN=<page>`).

## The rules

1. **Behaviour is mbui's, the look is the app's to change.** A component owns its input, focus, keys, state
   machine, timing, semantics and rules (a code complete is handed on once; a menu's item closes the menu). It draws
   a default look from the theme. An app restyles it through the theme and the call's own parameters, or replaces
   the look whole: each component takes a `look` function given its state (on, hovered, pressed, focus shown,
   disabled, how far its motion has gone), and the component lays out nothing of its own around it but the box that
   takes its input (Radix and shadcn/ui's split). An app's own design system (still.fail's `@sf`) is a set of looks.
2. **The theme is in the Ctx** (SwiftUI's environment, Compose's CompositionLocal, egui's Style): `Ctx::set_theme`
   once, `Ctx::with_theme` for a part. Widgets read their defaults from it; what a call says wins. **The default is
   still.fail's** (its web's and apps' tokens): `Theme::light` and `Theme::dark` the wide screen's (the white canvas,
   ink, ember orange), `Theme::narrow_light` and `Theme::narrow_dark` the phone's (warm paper, words a size up).
   The components' default looks are still.fail's parts: pill buttons and fields, the ink for what is to be done (a
   solid button, a checked box, a tooltip, a toast), the accent for what is on or moving (a switch, a slider,
   progress), small panels 6 in with rows on the hover's ground. `Theme::ios_light` and `Theme::ios_dark` keep the
   iOS colours mbui had (the demo's).
3. **Interactive widgets return a `Response`** (egui's): clicked, long-pressed, right-clicked, hovered, pressed,
   focused, focus shown, changed, rect. A widget with a value returns `Changed[T]`: the value and the response.
   Widgets that returned a Bool (`Ctx::button`) still do.
4. **Values are the app's** (Compose's state hoisting): a component is given its value (checked, open, the slider's
   number) and returns what it became; the app keeps it. A component keeps only what is passing (focus, a press, a
   motion, a hover's timer) in the Ctx by its id, forgotten with its page.
5. **Determinism.** No wall clock, no randomness: time is the Ctx's clock (`Ctx::now`), which a Tester moves.
   Every Tester starts with a fresh Ctx (and the tables outside it emptied and checked: what is left over fails the
   next Tester, not a test elsewhere).
6. **Semantics.** Every widget says its node's role, label, state (checked, expanded, selected, pressed, disabled,
   value, range) and actions (`Ctx::semantics`). Tests find widgets as a screen reader would (`Tester::get(Button,
   label="Save")`, `Tester::click`, `Tester::act`, `Tester::semantics_dump`), not by coordinates. A modal hides what
   is under it; `Ctx::hidden_from_semantics` hides decoration. The tree is made to be handed to VoiceOver, TalkBack
   and UI Automation later (roles and actions are theirs; an action comes to its widget as input does).
7. **Each component is tested and shown**: behaviour with a Tester (pointer, touch, keys, its value given from
   outside, disabled), its semantics asserted, and its states in the gallery, light and dark, as screenshots
   (`scripts/shots.sh kit`, goldens `goldens/mac-kit-*.png`).

## Focus, keys and layers (src/ui)

- `Ctx::interact(id)` registers what can take the focus, in build order. Tab and Shift+Tab move among them; a press
  gives the focus only to what takes it so (a field, a slider's thumb) and otherwise lets it go from anything but a
  field. The focus ring shows only when the focus came by the keyboard (`Response::focus_shown`).
- `Ctx::roving(key, orientation)` makes a group one Tab stop with the arrows (Home, End) moving inside it, mirrored
  right to left (Radix's RovingFocusGroup).
- Keys are dealt with as the frame starts, from what the last frame built: a key a widget used is taken, and the
  view's `Ctx::key_pressed` no longer sees it.
- `Ctx::overlay(key, modal~, …, body)` is a layer over the page (Portal + DismissableLayer + FocusScope): stacked in
  the order opened, dismissed by Escape, the system's back and a press outside (layer by layer from the top), the
  focus trapped in a modal one, moved into it as it opens and back as it goes. `Ctx::place` puts content by an
  anchor (Popper: side, along, offset, flip, kept in the window).
- `Ctx::with_direction(Rtl)` (DirectionProvider): rows run from the right, start padding is the right, the arrows
  that move along a row swap, a popover's start is its right.

## Time and motion (src/kit/time.mbt)

Everything in a component that waits or moves goes through one small interface, on the Ctx's clock, so that a Tester
moves it and a later scheduler (effect.mb's fibers, on the same clock) can stand behind it. Nothing counts frames of
its own.

| | what | as in |
|---|---|---|
| `after(c, key, on, ms, keep?)` | true once `on` has held `ms`; off, it starts again (`keep`: it waits where it was: a toast's time paused under the pointer) | a tooltip's delay, a toast's duration |
| `presence(c, key, shown, enter?, exit?)` | whether to build it, and how far in it is (0 → 1): it comes in by `enter`, and once not shown stays built, inert, until its exit has played | Motion's `AnimatePresence`, `initial`/`animate`/`exit` |
| `animate(c, key, target, transition?)` | a number going to `target` by a transition (a spring or a tween), from where it is and as fast as it goes | Motion's `animate`, Compose's `animate*AsState` |

Transitions are `@motion.Spec` (Motion's: `spring()`, `tween(ms, ease)`); reduced motion and screenshots
(`Ctx::still`) put every one at its end at once.

## The components

The gallery's page for each is `MBUI_SCREEN=<page>`.

| Radix | mbui | page |
|---|---|---|
| Label | `@kit.label(c, text, for_id?, field?)`: a tap turns its control, or focuses its field | controls |
| Separator | `@kit.separator(c, vertical?, decorative?)` | controls |
| AspectRatio | `@kit.aspect_ratio(c, ratio, body)` | controls |
| Avatar | `@kit.avatar(c, src, name, size?, radius?)`: the picture, else the name's initials | controls |
| Progress | `@kit.progress(c, value?, max?)`: `None` not known (a band runs; still in screenshots) | controls |
| Switch | `@kit.switch(c, key, checked) -> Changed[Bool]` | controls |
| Checkbox | `@kit.checkbox(c, key, check) -> Changed[Check]` (`Off`, `On`, `Mixed`) | controls |
| Toggle | `@kit.toggle(c, label, pressed) -> Changed[Bool]` | controls |
| ToggleGroup | `@kit.toggle_group(c, key, items, value, multiple?) -> Changed[Array[String]]`, a roving group | controls |
| RadioGroup | `@kit.radio_group(c, key, items, value) -> Changed[String]`: the arrows check what they reach | controls |
| Slider | `@kit.slider(c, key, value, min?, max?, step?) -> Changed[Double]` | controls |
| (a one-line field) | `@kit.text_field(c, key, placeholder?) -> Field`: still.fail's pill field | |
| Password Toggle Field | `@kit.password_field(c, key, visible) -> Password`: the words, whether they show | controls |
| One-Time Password Field | `Ctx::code_field` (src/ui): a code complete is handed on once | |
| Dialog | `@kit.dialog(c, key, open, title, description?, modal?) -> Changed[Bool]`: in the window's middle; Escape, the back, a press outside, its close button close it | overlays |
| AlertDialog | `@kit.alert_dialog(c, key, open, title, action, cancel?, danger?) -> Alert`: opens on cancel; a press outside leaves it | overlays |
| Popover | `@kit.popover(c, key, open, anchor, side?, along?) -> Changed[Bool]`: by its trigger, the focus in it | overlays |
| HoverCard | `@kit.hover_card(c, key, trigger, open_delay?, close_delay?) -> Bool`: a mouse resting on its trigger | overlays |
| Tooltip | `@kit.tooltip(c, key, trigger, text, delay?, skip?) -> Bool`: the pointer resting, or the keyboard's focus at once | overlays |
| Toast | `@kit.toaster(c, key, toasts, duration?) -> Toasts`: at the bottom of the window in its middle, paused under the pointer, swiped away (F8 waits for the hosts' function keys) | overlays |
| DropdownMenu | `@kit.dropdown_menu(c, key, open, trigger, entries) -> Menu`: entries by `menu_item`, `menu_check`, `menu_radio`, `menu_sub`, `menu_separator`, `menu_label`; letters typed find an item | menus |
| ContextMenu | `@kit.context_menu(c, key, area, entries) -> Menu`: a right click or a long press, at the pointer | menus |
| Menubar | `@kit.menubar(c, key, menus) -> String?` | menus |
| Select | `@kit.select(c, key, value, options, placeholder?) -> Changed[String]`: a listbox on the chosen option | menus |
| Toolbar | `@kit.toolbar(c, key, body)`: one roving group | menus |
| NavigationMenu | `@kit.navigation_menu(c, key, items) -> String?`: `nav_trigger` (content by a resting pointer), `nav_link` | menus |
| (a sheet) | `@kit.sheet(c, key, open, h, body) -> Changed[Bool]`: from the bottom (Vaul's Drawer), modal, closed by a drag down by its grabber | |
| Collapsible | `@kit.collapsible(c, key, open, label, body) -> Changed[Bool]`: its content grows to its height | disclosure |
| Accordion | `@kit.accordion(c, key, items, value, multiple?, collapsible?) -> Changed[Array[String]]`: items by `fold`; its triggers one roving group | disclosure |
| Tabs | `@kit.tabs(c, key, tabs, value, panel, manual?) -> Changed[String]`: the arrows choose as they move unless `manual` | disclosure |
| ScrollArea | `@kit.scroll_area(c, key, h, body)`: a list's scrolling (wheel, drag, keys, its bar) round what is taller than its room | disclosure |
| Form | `@kit.form(c, key, fields, submit?) -> FormResult`: fields by `form_field` (needed, an email, a number, the view's check); what is wrong shows once left or handed on | disclosure |

## Radix's utilities

| Radix | mbui |
|---|---|
| Portal | `Ctx::overlay`: built where the view asks, laid over the window, over everything outside a layer |
| DirectionProvider | `Ctx::set_direction`, `Ctx::with_direction` |
| VisuallyHidden | `Ctx::visually_hidden(label)`: in the semantics tree, not drawn |
| AccessibleIcon | `@kit.accessible_icon`: the icon hidden from the tree, its label in it |
| Slot (`asChild`) | React's way of merging a component's props into the element given as its child; it does not apply. What it is for, the component's behaviour on the app's own element, is the `look` function (rule 1) |
