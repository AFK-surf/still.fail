# One app: the screen, the input, pages and the shell

still.fail's app is one app on every device (the user, 2026-10-24: 「应该得打成同一个 app 了」). There is no phone
app and desktop app. How it is arranged follows the screen, in three tiers, each arranged as is best for it (the user,
2026-10-26: 「没必要把布局也三屏统一吧」「不然屏跟屏之间还有啥差距」). The input (touch, or keyboard and mouse) decides how
it answers the hand and the size words and icons are drawn at, and only that: never what is shown, where, nor how much
room a thing has to be pressed (the user, 2026-10-25: 「布局不是按屏幕类型和尺寸来的，而是跟操作方式有关……我怀疑是系统性问题」).
A tablet given a trackpad, a laptop touched on its screen, stays arranged as it was. Each function exists once, one
code and one data, and is drawn into whichever tier it lands in, on either kind of screen, with either hand.

This replaces the earlier "the desktop and the phone are two apps" (two page sets: `sfapp`'s, the phone's, and
`sfdesk`'s, ported from the web's desktop files). The way from here to there is at the end.

## Six principles (the user, 2026-10-26)

Everything below follows from these; where something below says otherwise, these hold.

1. **Every function is as easy to reach with either input; the ways may differ.** Hover, a right click, ⌘K and the
   keys are keyboard and mouse's ways; a swipe and a long press are touch's. Nothing is reached by the keys alone.
2. **What always shows and is pressed has room to be pressed, overlapping no other's: 44×44 at least with touch,
   36×36 with keyboard and mouse** (by the native input; the user, 2026-10-27: 大屏按最小 36 来设计，不用 44, a large
   screen being a computer's, made touch-friendly, not for touch first, as the touch Mac is to be). It may be drawn
   smaller; its room is not: a press reaches it from round it, a finger's or a pointer's. What shows only under a
   hovering pointer is mouse's way, and may be mouse's size only where touch has an equal way to the same.
3. **Steps one after another stay near each other.** On `Small` a menu, a pick and a confirm rise from the foot; on
   `Medium` and `Large` a menu and a pick float beside what opened them, a confirm in the middle. The screen decides
   it, not the input.
4. **The screen decides the arrangement; the input only how things answer:** lit under a hovering pointer or a press,
   a right click and a long press opening the same menu, the keys, the size words and icons are drawn at (rule 2
   untouched).
5. **What is shown and what can be done are the same on the three screens; each is arranged as is best for it.** A
   narrow page puts one thing on a line. A wide page uses its width: what goes together on one line, a row's actions
   at its end, short things side by side in columns, things compared in a table, fields not the column's whole width,
   its content in a column of about 760. Which arrangement is the library's parts' choice, by `look()`; a page is
   written once.
6. **Actions stay near what they act on:** a row's in the row, a page's in its head; a switch is not hidden on the
   next page.

## The terms (术语)

Four things decide how the app looks and answers, each with one name. PR descriptions, the docs and what is said to
people use these words and no others: not 电脑版, 手机版, 桌面端, 移动端 or 触屏设备, nor "the desktop app", "the
phone app", "a touch device", "the screen's kind".

| 术语 | Term | Read by | What it decides |
|---|---|---|---|
| 屏幕 | the screen | `@sf.layout(width)` | Three tiers, 小屏 / 中屏 / 大屏 (`Small`, `Medium`, `Large`), plus the special screens: a fold half open with its crease across lays a chat out as 小屏 does, a phone is used upright only. How the panes are arranged, where something opened goes, and how a menu, a pick or a confirm shows (from the foot on `Small`, beside what opened it or in the middle on the others). |
| 原生操控 | the native input | `@sf.native_input()` | Touch (`Finger`) or keyboard and mouse (`Mouse`), as the app was started, the same the whole run. The size words, icons and rows are drawn at (never a press's room: rule 2), what shows only under a pointer and touch's way to the same, what Enter does, scroll bars, how search is opened (the field over the list or ⌘K). |
| 当前操控 | the current input | `@ui.pointing()` | Touch or keyboard and mouse as it is used at the moment; it may change while the app runs. How a thing answers the hand alone (`c.lit`, how a menu is asked for, tips, drags); never what is shown, where or how big. |
| 页面宽窄 | a page's width | `@sf.look()` | 窄排法 / 宽排法 (`Narrow`, `Wide`): how a page arranges itself in the box it is given, by that box's width. |

The size things are drawn at (words, icons, row heights) follows the native input, not the tier: a tablet's 大屏 has
touch's sizes, a computer's narrow window keyboard and mouse's. So does the room a thing always shown is pressed in:
44×44 at least with touch, 36×36 with keyboard and mouse, overlapping no other's (rule 2).

## The screen and the input, each read in one place

| What | Read by | What it is |
|---|---|---|
| The native input | `@sf.native_input()` (sf/tokens.mbt) | Touch (`Finger`: a phone, a tablet, iOS and Android, for now) or keyboard and mouse (`Mouse`: macOS, Windows), as the app was started, the same for the whole run; a Tester's by its `platform`. |
| The tier | `@sf.layout(width)` (sf/tokens.mbt) | `Small`, `Medium`, `Large`, by the window's width in points on every screen (600, 840): which way up it is held, its height and its size say nothing of the panes, the height only how much of them shows. The one exception the crease: a fold half open, crease across, is `Small`'s chat. Held while the app holds the device sideways or lets a phone turn (`@hostapi.sideways()`). |
| The current input | `@ui.pointing()` | `Finger` or `Mouse`. It may change while the app runs. |

A phone is used upright only (touch as its native input and its short side under 600 points: a phone, a fold's outer screen):
Android's activity asks for portrait there (`Host.upright`), an iPhone supports portrait alone (ios_app.m `mb_upright`).
The app turning it itself is the exception (a film full screen, a station's screen: `@hostapi.set_sideways(true)`); back
upright after. A station's screen looked at lets a phone turn as it is held too (`@hostapi.set_turnable(true)`: Android's
user rotation, so with the rotation lock on the system offers its turn button), upright only again as it is left; the
tier is held meanwhile as while sideways. A tablet and an opened fold's inner screen turn as they are held.

- **The arrangement is the screen's.** The tier, and a page's own width (below), decide what is shown where. Nothing
  else does: `wide_on`, `@settings.wide`, `t.narrow`, the viewer host's `narrow` and `set_web_lines(wide)` go, and so
  does every use of the input for it.
  - **The tier:** how the shell arranges the panes, where something opened goes (pushed, a pane, a side tab), how a
    menu, a pick or a confirm shows (Presenters, below: from the foot on `Small`; on `Medium` and `Large` a menu or a
    pick beside what opened it, a confirm in the middle), and where ⌘K's search shows (its panel over the window, or
    on `Small` the search page).
  - **The native input** (the ways and the sizes, not the arrangement):
    - the sizes: the type scale, icons and row heights; touch's are the phone's, keyboard and mouse's the web's.
      What is drawn smaller keeps its room to be pressed (rule 2: 44×44 with touch, 36×36 with keyboard and mouse,
      overlapping no other's; a button
      drawn its own size, a press reaching it from round it, a finger's or a pointer's alike, mbui's press_reach: what
      shows and what a press takes need not be the same, the user, 2026-10-26). The colours are neither the screen's nor the input's: one palette
      everywhere, the phone's (warm paper, white cards on it), light or dark as set. The panes side by side are told
      apart by their grounds: the sidebar a step under the page's beige `bg`, what is chosen in it a step under that;
    - what a page offers to reach things (rule 1, each input a way as easy): with touch the search field at the top of
      the chats' list, with keyboard and mouse ⌘K;
    - the keyboard: with keyboard and mouse Enter sends and the composer takes the focus as a chat opens; with touch
      Enter makes a new line and nothing raises the keyboard unasked.
- **The current input only says how a thing answers the hand.** Changing hands changes none of the layout:
  - feedback: `c.lit` lights on hover with a mouse and on press with a finger;
  - what a pointer over a thing shows (`c.hovered`: a row's time, its 归档), which a finger reaches otherwise (the
    row's menu);
  - menus: `c.menu_asked`, a right click or a long press, opening the same menu, shown as the screen says; a right
    click is on what a press there would be on (the innermost asker under it, never what lies under what is over it:
    an open menu, the file preview, a panel on the tape not in use), one right click one menu;
  - tips: on hover, or on a long press;
  - lists scrolled by a finger's drag or by the wheel, words picked by a drag or a hold, drag and drop.

  A page asks these of the library (`c.lit`, `c.menu_asked`; sf/hand.mbt: `pointed_or_finger` for what a pointer
  over a thing shows, `press_ripple`, `menu_held`, `menu_along`, and `pointer_rests` for an answer that turns on whether
  the hand rests over things), not `@ui.pointing()`. detlint's `page-hand` counts what reads it in the pages
  (`pages.roots`), each file's bar only falling, to 0.
- **A page's own width** (the box it is drawn in) decides its inner arrangement: columns that drop, tools that go into
  ⋯, a side part that gives way. This is the web's container query. It is not the tier: a page never asks which tier
  it is in.

### The same on every screen, and what differs

The same on a phone, a tablet and a computer: each page's content, what can be done there and its words; the parts it
is made of; the palette, the corner ladder, the icons, the kinds of motion and the type's hierarchy; the presenters and
the shell's ways; the room a thing always shown is pressed in (rule 2).

Not the same: the arrangement. Each screen is arranged as is best for it (rule 5): its blocks may be put otherwise,
side by side or one under another, in a table or a list, so long as what is shown and what can be done are the same.

What differs comes of two axes, and none of it is decided in a page:

**The screen (its tier, and the width of the box a page is drawn in): the arrangement.**

| What differs | By | Decided in |
|---|---|---|
| The panes: one stack, the tape, columns | the tier (the window's width) | the shell |
| A menu, a pick: a sheet from the foot (`Small`), or floating beside what opened it (`Medium`, `Large`); a confirm: from the foot (`Small`), or a dialog in the middle | the tier | the presenters |
| Reaching places: the bottom bar or the rail; ⌘K's search as a page (`Small`) or a panel over the window | the tier | the shell |
| A page's head and column: narrow, under 640 (back over a large title, the page's room 12 at its sides), or wide (its head, the page's actions at its end, one column at most 760 in the middle) | the page's own width | the library's page (`@sf.page`) |
| A page's parts: narrow, one thing on a line; wide, using the width (what goes together on one line, a row's actions at its end, short things side by side, things compared in a table, fields not the column's whole width, rows denser). On both, its sections under their titles (one level: no heading under a section's), a section's rows on a list card (`@sf.group`), words with their buttons on a content card (the user, 2026-10-26: 「设置感觉很乱」, a wide page's rows were on the page or on cards for no reason) | the page's own width (`look()`) | the library's parts |

**The input: the ways and the sizes, never the arrangement or a press's room.**

| What differs | By | Decided in |
|---|---|---|
| The size words, icons and rows are drawn at, and the density (never a press's room under 44×44 with touch, 36×36 with keyboard and mouse, nor two overlapping: rule 2) | the native input | the theme, chosen once (`@sf.begin`) |
| What only a pointer's hover would show (a row's 归档, its time, its ⋯): touch's as easy a way to the same (the row's menu on a long press, a swipe), or always there | the native input | the library's parts (sf/hand.mbt) |
| Reaching things: the search field over the chats' list or ⌘K; the keys | the native input | the shell |
| Enter makes a new line or sends; the keyboard raised as a chat opens or not | the native input | the library's fields |
| Scroll bars: none with touch | the native input | the library (`scroll_bar.mbt`) |
| How a thing answers: lit under a hovering pointer or a press, a right click or a long press for the same menu, tips | the current input | the library's primitives (`c.lit`, `c.menu_asked`) |

So:
- **A phone:** Small, a page at a time, laid out narrow, touch's sizes, menus, picks and confirms from the foot, the
  bottom bar, swiped back, upright.
- **A tablet:** the tape held upright (Medium), columns on its side (Large); each pane laid out by its own width (a
  narrow one narrow); touch's sizes; menus and picks beside what opened them, confirms in the middle; the rail; turned
  as it is held.
- **A computer:** columns (Large), laid out wide, the web's sizes and density, menus and picks beside what opened
  them, dialogs, ⌘K and the keys, what a pointer's hover shows. A window made narrow takes the tape or the stack and
  the narrow arrangement, at keyboard and mouse's sizes, its presses' room still 36×36.

## Three kinds of UI code

### The library (`src/sf`)

Parts, tokens, motion (its kinds, rules and presets: docs/motion.md), what is drawn over what (docs/strata.md), the viewers (Reader, Player, ViewerBar and the
frame around them), and the **presenters**:

- `@sf.menu`, `@sf.pick`, `@sf.panel` (a small panel of rows or fields), `@sf.confirm`, `@sf.ask`.
  - A sheet spans the window, not the pane that opened it: on the tape it is over every panel.
- A page says what it shows; the presenter decides how:
  - in `Small`, it shows as a bottom sheet;
  - in `Medium` and `Large`, as a popover anchored to what opened it (menu, pick, panel) or a centred dialog
    (confirm, ask);
  - by the tier alone, with either input (rule 3).
- One host draws them all, over the shell. Today's hosts become it: the app's `sheet.mbt`, `decide.mbt`'s `dui.sheet`,
  `settings/sheet.mbt`, and sfdesk's dialogs.

And **a page's parts**: its frame (back and title, or a head of its own: a mark, a name, what it is, what it does),
sections, groups of rows, rows (to another page, a value, a switch, a pick), cards, notes, choices, buttons and
fields. Each is laid out as the page it is in is (the anatomy above): the page's frame decides that once, by the
page's width, and its parts take it from there. A part has an arrangement of its own for each width (`look()`), each
the best for it, not the narrow one stretched: a wide row puts what goes together on one line and its actions at its
end, wide rows are denser, a wide field is not the column's whole width; its rows' height by the input, their room to
be pressed by rule 2. A part never measures its own box for it (a section in a 380 column
of a wide page is a wide page's section, and a computer's 480 dialog is no narrow page: what a presenter holds is laid
out as the presenter says), and a page never passes it to them. Each takes its sizes from the theme. So a page made of
them is right in any box on either screen. There is one of each, and none draws one screen's
or one width's look alone: a page cannot reach for a wrong one. (One page frame is left, the library's `@sf.page`; the
settings' pages still draw some pieces of one arrangement themselves, `narrow_*` and `desk_*`, counted by detlint's
`page-look`, until the settings' merge makes them the library's parts.)

### Pages

One implementation per function: the chats' list, a chat, a new chat, a history, the files and a folder, each
settings page, each place, sign-in, the landing. There is no phone copy and desk copy.

- **Its box:** it draws into the box it is given. `c.width` and `c.height` are its pane's; it never subtracts a rail
  or a sidebar itself.
- **What it reads:** its own width for its arrangement (columns that drop, tools into ⋯), its anatomy through the
  library's parts, and nothing of the native input: what differs by it is the theme's, the parts', the presenters'
  and the shell's (the table above). A page that needs something to differ by the native input asks the library for a part
  that does it, and the part holds the difference for every page; no page draws touch's piece and
  keyboard and mouse's piece under an `if`. detlint's `page-screen` counts what reads `@sf.native_input()` in the pages
  (`pages.roots`), each file's bar only falling, to 0. The current input reaches it only through the library's primitives
  (above). Never the tier, and never `@ui.pointing()` itself.
- **What it works out of the core's data:** the view is built again each frame, so whatever a page works out as it
  builds is worked out again each frame. A field or two of a topic's value it reads as it is; what it makes of the whole
  of it (a chat's messages, the chats' list, a folder's entries, an agent's history, a job's output) is a computed
  (mbui's `signals`: alien-signals, ported), sfbase's `Derived` (what a topic's value makes) or a `Kept` of its own,
  whose getter reads topics (`src.topic`) and the page's own inputs as signals (只看收发, the theme's ink). The core's
  changes are pushed all the way: each subscription's changes are a signal the core client sets as the core's message
  comes (src/core `Sub.changes`), and reading a topic reads it, so a computed follows every topic it read, through
  other computeds too, and is worked out again only as one changes. It is given what it made last: what the core's
  deltas did not touch is the same JSON, and what was made of it is kept (`made_again`: a chat's messages, the chats'
  rows), so one message come is one message read. A made-up core says its changes too (the fixture's
  `@settings.fixture_changed`; a test's topic worked out as it is read, `topic_as_read`). Never a loop over a topic in
  the frame (the user, 2026-10-26: 「不应该有个跟 preact signals 一样的机制来保证只计算一次吗」「实现可以抄一下
  alien-signals」「让这套 signals 机制从 core 到 ui 能完整连上」). The chat's and the chats' list's converters are sfbase's
  own: a page has their views only from `view_of_chat` and `chats_of`. What a frame does with what was worked out goes
  over only what changed, too: a chat's list's rows and keys are made again only as its entries (the same array while
  nothing changed), whether it follows its end, what was sent from here or a row waiting its turn change (row_keys'
  `RowsMade`), and its motion is told the same keys (`@motion.list_keys` goes over none while they are the same, and
  over only those between the rows alike at the start and the end as they change): a frame of a chat of 3000 messages
  goes over none of them while nothing changed (the user, 2026-10-26: 「中型屏下内容很多的 chat 性能好像比较差」).
- **Opening things:** it says what to open: a page (`Page`), or a detail of the chat (a history, a service, a
  visualization, jobs, letters, files). The shell decides where that goes. A page never pushes onto the stack or moves
  the tape itself.
- **Menus and dialogs:** it shows menus, picks, panels, confirms and questions only through the presenters.
- **Its bar:** it says what its bar holds (title, lead, actions). The shell frames it: a back where there is one to
  go to, the window buttons' inset, the glass.
- **Its design:** made once, from what the page is for: what a person comes to it to see and to do, and in what
  order. What it shows and what can be done there are the same on every screen; how it is arranged is each screen's
  best (rule 5), and that choice is the library's parts', by `look()`, not the page's.
  - The web's desktop and mobile files for it are read for why they are as they are and so as to miss nothing. They
    are not copied, and none is picked, neither one for every screen nor one for each screen
    (the user, 2026-10-25: 「做最合理的，而不是从两个里选一个」; 「是不是又代码里 if 一下，直接把手机版代码复制进去」). Where
    they differ, the reason that holds decides; where both fall short, the page does better. Its PR says why it is
    laid out so before it is built.
  - What it shows and does is the core's, and so is its logic.
  - Two copies merged: neither is kept and the other dropped. The page is no worse on a phone than the phone's copy
    was, nor on a computer than the desktop's; its PR shows both screens before and after. Where both copies'
    arrangements are reasonable for their screens, both stay, as the parts' narrow and wide ones: one code, not one
    arrangement.
- **Decisions that stay:** the touch idioms the user decided:
  - swipe back, and long-press menus;
  - a row swiped to archive;
  - the bottom bar;
  - the viewer's message first on screen;
  - the round-knob switches.

### The shell

One shell. It arranges the same panes in every tier:

- **The panes:**
  - List: the place's list (the chats, the files' places, the settings, the stations, the profiles).
  - Page.
  - Detail: the chat's side panel and its tabs.
  - Over all of them: the full-window layers (a screen, the viewer) and the overlays (the presenters' host, toasts,
    ⌘K).
- **The tiers:**

  | Tier | Arrangement | Back | Places |
  |---|---|---|---|
  | Small | One stack. The list is the root, a page is pushed onto it, a detail is pushed onto that. | A swipe from the edge (finger); the back key or ⌘[ (mouse) | The bottom bar, on a place's root |
  | Medium | The tape: list, page and detail are separate panels, one active: the page or the detail as wide as the window leaves past a strip of each beside it (`tape_shows`, 56: 2026-10-26), the list its own width, the page beside it showing the rest; the edge between the list or the detail in use and the page dragged, its width (`tape_edge`). A press on what shows of another brings it over; dragged across there it comes with the finger (2026-10-25), a drag on the one in use is that one's own; what is chosen to be shown in the page (a list's row, a search's, ⌘K's, a link's) shows in it: beside the list in use, the list staying in use (2026-10-27), with the detail in use the page brought over (`show_page`); 新建对话 brings its page over (`bring_page`); the list never folds by itself. | A full-window layer (a screen, the viewer) first; then detail → page; a page opened from the page (pushed over it: `Nav::push_over`) taken off, sliding as a phone's; the page chosen from the list → list; another place's list → the chats'. Both follow the system's back gesture as it goes (the page's stack `Ctx::nav_flat(stacks=)`, the tape `Ctx::follow_back`), as a phone's page does | The rail |
  | Large | Columns: the rail and the list, the page, the detail. | The web's (⌘[, the chat's neighbours) | The rail |

- **What is not in use is not built again:** on the tape the panels behind the one in use are kept as they were
  drawn (mbui's `Ctx::kept_part`, as Zed's GPUI keeps a cached view): a frame in which nothing that changes them came
  (a list scrolled in the panel in use, by a finger or a wheel, flung on) draws them again from their last build, none
  of them built, laid out or painted. The core's data they read (followed as signals), any event from outside the
  hand on another panel (a press, a key, a message, a timer), their size, place and ground, a motion of their own, a
  press held or a wheel turned on them builds them anew.
- **One model:** `app.nav` stays the one model of where the person is. One table in the shell says, for each `Page`,
  which pane it is.
- **What a page is given:** its box (width and height) and its insets (where its bar's back goes, the room under it:
  a tape panel's own inset, the keyboard). A page does not work these out from the tier.
- **What it owns:**
  - reading the native input and the tier;
  - the stack's motion, the tape and the columns;
  - back, the bars, the rail and the window's inset;
  - the presenters' host, toasts and the keys (⌘K, ⌘/, the core's keymap);
  - the app-level things: signing in, links, notifications and the menu bar (sfbase).

## The packages

Four, at the end of the way there:

| Package | Holds |
|---|---|
| `src/sf` | The library: the parts, the presenters, a page's frame (`@sf.page`: what its frame gives it, `PageFrame`; what it says to a bar of the frame's over it, `PageBar`), the viewers. |
| `src/sfbase` | The model: `Source`, the core's views, the navigation (`Page`, `app.nav`, `open_page`, `go_place`, what back over a page says), the app-level things, and the machinery pages share (drafts and references, flights, thumbnails). The settings' `Core` and `Route` stay where it reaches them. |
| `src/sfpages` | The pages, each file named after the web's. |
| `src/sfshell` | The shell, and the app's `view`, which the main calls. |

And a fifth, not the app's: `src/sffixture`, the made-up core the tests and the tools run the app over (what each topic
says, how each call is answered, each area's made-up data), below the pages (it imports sfbase and the library), so a
page's own tests in sfpages read the same data as the app's. The app's code says none of it (detlint's
`fixture-import`): what it needs of a made-up core it is given through sfbase's wires (`made_reset`, `made_frame`, set as
the made-up core is linked); only what opens a mode over the app (sfapp's `fixture_open.mbt`, the tests' and sffix's
one way in) names it until the last step.

- **What goes:** `src/sfapp` and `src/sfdesk`. A page moves into `sfpages`; what is left, the frames' pieces (the
  phone's stack, bars and bottom bar, the desk's frame, tape, rail, columns and switcher), is renamed `sfshell`.
- **Which way they import:** `sfshell` imports `sfpages`, `sfpages` imports `sfbase`, all three the library. What a
  page needs of the shell it is given through sfbase or the library as the app starts (a wire: the bar over a page in a
  panel of its own is the shell's, `@sf.pane_bar`), never by importing it.
- **detlint holds it:** `page-shell-import` (`sfpages` imports no `sfshell`), `tier-outside-shell` (`@sf.layout`,
  `wide_on`, the stack's and the tape's state read only in `sfshell`), and `page-screen` at 0 in `sfpages`; a page
  calls no sheet or dialog host but through the presenters.
- **One function, one page:** one code and one data; its arrangement may differ wholly between the screens, done by the
  library's parts by `look()`. `page-look` only keeps a page from judging its width itself; it does not ask the
  arrangements to be the same, and a wide one uses the width.

## Tests

- **Each page** is tested in the Tester at a width of each tier, with touch and with keyboard and mouse (the
  Tester's `platform`), each with its usual hand.
  - And once with the other hand on each (`Tester::new(pointing=…)`): what is laid out is the same, box for box; only
    how it answers differs.
  - The platform also says the tier with touch and the core's `client.device`, and a replay recorded on one
    platform keeps it.
- **A press's room** (rules 1 and 2): on every screen the corner rule opens, in each window, what always shows and
  takes presses has its room to be pressed in (44×44 with touch, 36×36 with keyboard and mouse), no two such rooms
  overlapping, and what shows only under a resting
  pointer stands on what opens a menu on a hold (mbui's `rooms.mbt`, Tester::room_faults, hover_only_faults); each
  rule's faults kept to their bars in sfapp's `rooms_known_wbtest.mbt`, only falling.
- **The screenshots** (`screens.sh`) cover the three tiers.
- **Replays** recorded at one tier keep their traces. A flow that only one tier has (the bottom bar, the tape) is that
  tier's.
- **The rest is as before:** time is declared, and nothing waits for motion (AGENTS.md).

## The way there

Before it (done): the screen and the input are read once (`@sf.layout`, `@sf.native_input()`; `wide_on` and the
viewer's `narrow` gone, `@settings.wide` left to the settings' merge), the presenters are the library's and the sheet
hosts and the desk's dialogs moved onto them, and a page opens by saying what (`@sfbase.open_page`,
`@sfbase.open_detail`, `go_place`, `go_back`, `close_page`; the shell's `open_where` / `detail_where` and its back by
the tiers' table). What still pops: the shell's own ways to the root and the frames' (nav_home, desk_home, the
rail's), and the routers that open a page where it goes. Merged into `sfpages` so far: the chats' lists (one track of
全部, 我参与的, 监控中 in every tier, `ListsFrame`), the device waiting in the workspace's lock, the composer, 接力.

Four steps, each one PR or a few. What changes nothing on screen merges once green; what changes something is
shown before and after, a batch at a time. The shell stays where it is until the pages have left it (2026-10-26: moved
first, the whole app's tests would have moved with it and again as the pages left).

1. **The pages' ways into the shell cut** (done), nothing on screen changed, one kind a PR:
   - the settings' pages' frame (sfdesk's `page_look.mbt`): they call the library's `@sf.page` itself, which takes
     what its frame gives it (`PageFrame`), says a place's top page's actions to the bar over it (`@sf.named_actions`)
     and, in a panel of its own on the tape, its title, back and actions to the shell's bar there (`@sf.pane_bar`);
     what back says is sfbase's `back_label`. The pieces of one arrangement those pages still draw (`narrow_*`,
     `desk_*`) wait in `settings_page.mbt` for the settings' merge (step 3);
   - the sidebars' rows into the library (`side_rows.mbt`); the sidebar's top row stays the shell's;
   - a way (`way.mbt`: the crumbs of the files, the folder picker, the station picker) the library's; the files' tabs
     as the core keeps them (`files_tabs.mbt`) sfbase's; the settings' core one, sfbase's (`settings_core`: the
     shell's way home, the pages' login card given as the app starts); what a list chose shown through the shell
     (`show_chosen`, Shell's `show`); a place gone to `go_place`; a chat's side panel asks whether its page is a panel
     of its own (`@sf.in_pane`), not the tape. The toast was never a page's: the shell draws it from what sfbase says.
2. **The rule:** `tier-outside-shell` (detlint.json `shell.files`, the shell's files in sfapp and sfdesk; `shell.reads`,
   `shell.state`): a page reading the tier or the shell's state (`@sf.layout`, `is_wide`, `wide.*`, the room of the
   system bars, `status_top` / `nav_foot`) counted, its bars only falling. What room a page keeps for the system bars
   and the shell's own is the shell's, given it as its frame (`PageFrame`'s `top`, `foot`); `page-screen` counts no
   shell file.
3. **The pages moved into `sfpages`,** each area taking its tests and fixtures with it, its counts falling to 0:
   - those of one copy as they are (the screen and the player; the settings' pages only the desk has; the rest),
     what they read of the tier handed to the library or the shell as they go;
   - those of two copies merged, an area a PR, as the pages above are (what the page is for, said first; drawn and
     tested in the three tiers with both inputs; both old copies deleted): the settings and the places, the files and
     the viewer, the history and 奏, a new chat, the chat (the page, the message list, the side panel) last. Before
     each, what each copy has is listed, so nothing is lost. One copy is one code and one data, not one arrangement:
     where both copies' arrangements are reasonable, both stay, the narrow and the wide, through the library's parts by
     `look()`; the wide one uses the width, not the narrow one stretched.
4. **The shell named:** what is left of `sfapp` and `sfdesk` (the shell's files and the whole app's tests) one package,
   `sfshell`, its `view` the main's; `@sfapp.` and `@sfdesk.` are `@sfshell.` everywhere, nothing else changed. The
   tape's files with it, the day it is made. `page-shell-import` (`sfpages` imports no `sfshell`) in; `tier-outside-shell`
   and `page-screen` at 0. What opens a mode over the app (`fixture_open.mbt`) and the whole app's tests that call it
   go to the tests' side then, the app no longer linking the made-up core; what those tests read of the shell's own
   is asked through its public ways, or the test written again, not made public for them.

A station destination opened from a chat on Medium or Large stays beside that chat: screens use `screen:[station,screen]`, files use `drive:[station]`, and machine details use `station:[station]`. Reopening focuses the existing tab. Folder navigation is independent for each chat and station; choosing a pinned folder changes that station's location. Small keeps these destinations on the page stack. Hidden screen tabs release their stream and decoder and reopen when selected.
