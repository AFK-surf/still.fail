# One app: the screen, the input, pages and the shell

still.fail's mbui app is one app on every device (the user, 2026-10-24: 「应该得打成同一个 app 了」). There is no phone
app and desktop app. How it is laid out follows the screen, in three tiers, and the native input (touch, or keyboard and
mouse, as the app was started). How it answers the hand follows the input, and only that: the input never decides what is shown, where,
or how big (the user, 2026-10-25: 「布局不是按屏幕类型和尺寸来的，而是跟操作方式有关……我怀疑是系统性问题」). A tablet given a
trackpad, a laptop touched on its screen, stays laid out as it was. Each page exists once and is drawn into whichever
tier it lands in, on either kind of screen, with either hand.

This replaces the earlier "the desktop and the phone are two apps" (two page sets: `sfapp`'s, ported from the Kotlin
app, and `sfdesk`'s, ported from the web's desktop files). The way from here to there is at the end.

## The terms (术语)

Four things decide how the app looks and answers, each with one name. PR descriptions, the docs and what is said to
people use these words and no others: not 电脑版, 手机版, 桌面端, 移动端 or 触屏设备, nor "the desktop app", "the
phone app", "a touch device", "the screen's kind".

| 术语 | Term | Read by | What it decides |
|---|---|---|---|
| 屏幕 | the screen | `@sf.layout(width)` | Three tiers, 小屏 / 中屏 / 大屏 (`Small`, `Medium`, `Large`), plus the special screens: a fold half open with its crease across lays a chat out as 小屏 does, a phone is used upright only. How the panes are arranged and where something opened goes. |
| 原生操控 | the native input | `@sf.native_input()` | Touch (`Finger`) or keyboard and mouse (`Mouse`), as the app was started, the same the whole run. The theme's sizes (words, row heights, what a press reaches), what shows only under a pointer and how else it is reached, what Enter does, scroll bars; with the screen's tier, how a menu or a pick shows (a sheet or beside what opened it) and how search is opened (the field over the list or ⌘K). |
| 当前操控 | the current input | `@ui.pointing()` | Touch or keyboard and mouse as it is used at the moment; it may change while the app runs. How a thing answers the hand alone (`c.lit`, how a menu is asked for, tips, drags); never what is shown, where or how big. |
| 页面宽窄 | a page's width | `@sf.look()` | 窄排法 / 宽排法 (`Narrow`, `Wide`): how a page arranges itself in the box it is given, by that box's width. |

Sizes (words, row heights, touch targets) follow the native input, not the tier: a tablet's 大屏 has touch's sizes, a
computer's narrow window keyboard and mouse's.

## The screen and the input, each read in one place

| What | Read by | What it is |
|---|---|---|
| The native input | `@sf.native_input()` (sf/tokens.mbt) | Touch (`Finger`: a phone, a tablet, iOS and Android, for now) or keyboard and mouse (`Mouse`: macOS, Windows), as the app was started, the same for the whole run; a Tester's by its `platform`. |
| The tier | `@sf.layout(width)` (sf/tokens.mbt) | `Small`, `Medium`, `Large`, by the window's width in points on every screen (600, 840): which way up it is held, its height and its size say nothing of the panes, the height only how much of them shows. The one exception the crease: a fold half open, crease across, is `Small`'s chat. Held while the app holds the device sideways (`@hostapi.sideways()`). |
| The current input | `@ui.pointing()` | `Finger` or `Mouse`. It may change while the app runs. |

A phone is used upright only (touch as its native input and its short side under 600 points: a phone, a fold's outer screen):
Android's activity asks for portrait there (`Host.upright`), an iPhone supports portrait alone (ios_app.m `mb_upright`).
The app turning it itself is the exception (a film full screen, a station's screen: `@hostapi.set_sideways(true)`); back
upright after. A tablet and an opened fold's inner screen turn as they are held.

- **The layout is the screen's and the native input's.** The native input and the tier, and a page's own width (below), decide everything about what
  is shown, where and how big. Nothing else does: `wide_on`, `@settings.wide`, `t.narrow`, the viewer host's `narrow`
  and `set_web_lines(wide)` go, and so does every use of the input for any of these.
  - **The tier:** how the shell arranges the panes, and where something opened goes (pushed, a pane, a side tab).
  - **The native input:**
    - the look: the theme's palette, type scale and row heights, and touch targets (44 at least with touch: a row that
      high; a button drawn its own size, a finger reaching it from round it, mbui's finger_reach: what shows and what a
      finger takes need not be the same, the user, 2026-10-26);
      touch's is the phone's, keyboard and mouse's the web's. The panes side by side are told apart by their grounds in
      both, as the web's: the sidebar a step under the page's ground (touch: the page's beige `bg`, the sidebar a step
      under it, what is chosen in it a step under that);
    - what a page offers to reach things: with touch the search field at the top of the chats' list, with keyboard
      and mouse ⌘K;
    - the keyboard: with keyboard and mouse Enter sends and the composer takes the focus as a chat opens; with touch
      Enter makes a new line and nothing raises the keyboard unasked.
  - **Both:** how a menu, a pick or a confirm shows (Presenters, below): a sheet with touch short of Large,
    else a popover or a dialog. And where ⌘K's search shows: its panel over the window, or in `Small` the search page.
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

The same on a phone, a tablet and a computer: each page's content, its blocks and their order, what can be done there
and its words; the parts it is made of; the palette, the corner ladder, the icons, the kinds of motion and the type's
hierarchy; the presenters and the shell's ways.

What differs comes of two things alone, the native input and a width, and none of it is decided in a page:

| What differs | By | Decided in |
|---|---|---|
| Sizes: the type, row heights, density, touch targets (44 at least with touch: rows; buttons reached from round them, drawn their own size) | the native input | the theme, chosen once (`@sf.begin`) |
| What only a pointer's hover would show (a row's 归档, its time, its ⋯): with touch always there, or on a long press | the native input | the library's parts (sf/hand.mbt) |
| A menu, a pick, a confirm: a sheet from the foot, or a popover or a dialog | the native input and the tier | the presenters |
| Reaching things: the search field over the chats' list or ⌘K; the bottom bar or the rail | the native input and the tier | the shell |
| Enter makes a new line or sends; the keyboard raised as a chat opens or not | the native input | the library's fields |
| Scroll bars: none with touch | the native input | the library (`scroll_bar.mbt`) |
| The panes: one stack, the tape, columns | the tier (the window's width) | the shell |
| A page's head and column: narrow, under 640 (back over a large title, the page's room 12 at its sides), or wide (its head, one column at most 760 in the middle). On both, its sections under their titles (one level: no heading under a section's), a section's rows on a list card (`@sf.group`), words with their buttons on a content card (the user, 2026-10-26: 「设置感觉很乱」, a wide page's rows were on the page or on cards for no reason) | the page's own width | the library's parts |

So:
- **A phone:** Small, a page at a time, laid out narrow, touch's sizes, sheets, the bottom bar, swiped back,
  upright.
- **A tablet:** the tape held upright (Medium), columns on its side (Large); each pane laid out by its own width (a
  narrow one narrow); touch's sizes and targets; sheets on the tape, popovers in columns; the rail; turned as
  it is held.
- **A computer:** columns (Large), laid out wide, the web's sizes and density, popovers and dialogs, ⌘K and the keys,
  what a pointer's hover shows. A window made narrow takes the tape or the stack and the narrow anatomy, at
  keyboard and mouse's sizes.

## Three kinds of UI code

### The library (`src/sf`)

Parts, tokens, motion (its kinds, rules and presets: docs/motion.md), the viewers (Reader, Player, ViewerBar and the
frame around them), and the **presenters**:

- `@sf.menu`, `@sf.pick`, `@sf.panel` (a small panel of rows or fields), `@sf.confirm`, `@sf.ask`.
  - A sheet spans the window, not the pane that opened it: on the tape it is over every panel.
- A page says what it shows; the presenter decides how:
  - with touch in Small or Medium, it shows as a bottom sheet;
  - otherwise, as a popover anchored to what opened it (menu, pick, panel) or a centred dialog (confirm, ask).
- One host draws them all, over the shell. Today's hosts become it: the app's `sheet.mbt`, `decide.mbt`'s `dui.sheet`,
  `settings/sheet.mbt`, and sfdesk's dialogs.

And **a page's parts**: its frame (back and title, or a head of its own: a mark, a name, what it is, what it does),
sections, groups of rows, rows (to another page, a value, a switch, a pick), cards, notes, choices, buttons and
fields. Each is laid out as the page it is in is (the anatomy above): the page's frame decides that once, by the
page's width, and its parts take it from there. A part never measures its own box for it (a section in a 380 column
of a wide page is a wide page's section, and a computer's 480 dialog is no narrow page: what a presenter holds is laid
out as the presenter says), and a page never passes it to them. Each takes its sizes from the theme. So a page made of
them is right in any box on either screen. There is one of each, and none draws one screen's
or one width's look alone: a page cannot reach for a wrong one. (One page frame is left, the library's `@sf.page`; the
settings' pages still draw some pieces of one arrangement themselves, `narrow_*` and `desk_*`, counted by detlint's
`page-look`, until the settings' merge makes them the library's parts.)

### Pages

One implementation per function: the chats' list, a chat, a new chat, a history, 奏, the files and a folder, each
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
  order. Its structure is the same on every screen; what differs is the table's above, not the page's.
  - The web's desktop and mobile files for it, and the Kotlin app's, are read for why they are as they are and so as
    to miss nothing. They are not copied, and none is picked, neither one for every screen nor one for each screen
    (the user, 2026-10-25: 「做最合理的，而不是从两个里选一个」; 「是不是又代码里 if 一下，直接把手机版代码复制进去」). Where
    they differ, the reason that holds decides; where both fall short, the page does better. Its PR says why it is
    laid out so before it is built.
  - What it shows and does is the core's, and so is its logic.
  - Two copies merged: neither is kept and the other dropped. The page is no worse on a phone than the phone's copy
    was, nor on a computer than the desktop's; its PR shows both screens before and after.
- **Decisions that stay:** the touch idioms the user decided:
  - swipe back, and long-press menus;
  - a row swiped to archive;
  - the 奏 deck's swipes (left 待定, right 不再提醒);
  - the bottom bar;
  - the viewer's message first on screen;
  - the round-knob switches.

### The shell

One shell. It arranges the same panes in every tier:

- **The panes:**
  - List: the place's list (the chats, 奏, the files' places, the settings, the stations, the profiles).
  - Page.
  - Detail: the chat's side panel and its tabs.
  - Over all of them: the full-window layers (a screen, the viewer) and the overlays (the presenters' host, toasts,
    ⌘K).
- **The tiers:**

  | Tier | Arrangement | Back | Places |
  |---|---|---|---|
  | Small | One stack. The list is the root, a page is pushed onto it, a detail is pushed onto that. | A swipe from the edge (finger); the back key or ⌘[ (mouse) | The bottom bar, on a place's root |
  | Medium | The tape: list, page and detail are separate panels, one active: the page or the detail as wide as the window leaves past a strip of each beside it (`tape_shows`, 56: 2026-10-26), the list its own width, the page beside it showing the rest; the edge between the list or the detail in use and the page dragged, its width (`tape_edge`). A press on what shows of another brings it over; dragged across there it comes with the finger (2026-10-25), a drag on the one in use is that one's own; what is chosen to be shown in the page (a list's row, a search's, ⌘K's, a link's) brings the page over (`show_page`); the list never folds by itself. | A full-window layer (a screen, the viewer) first; then detail → page; a page opened from the page (pushed over it: `Nav::push_over`) taken off, sliding as a phone's; the page chosen from the list → list; another place's list → the chats'. Both follow the system's back gesture as it goes (the page's stack `Ctx::nav_flat(stacks=)`, the tape `Ctx::follow_back`), as a phone's page does | The rail |
  | Large | Columns: the rail and the list, the page, the detail. | The web's (⌘[, the chat's neighbours) | The rail |

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

- **What goes:** `src/sfapp` and `src/sfdesk`. A page moves into `sfpages`; the frames' pieces (the phone's stack,
  bars and bottom bar, the desk's frame, tape, rail, columns and switcher) move into `sfshell`.
- **Which way they import:** `sfshell` imports `sfpages`, `sfpages` imports `sfbase`, all three the library. What a
  page needs of the shell it is given through sfbase or the library as the app starts (a wire: the bar over a page in a
  panel of its own is the shell's, `@sf.pane_bar`), never by importing it.
- **detlint holds it:** `page-shell-import` (`sfpages` imports no `sfshell`), `tier-outside-shell` (`@sf.layout`,
  `wide_on`, the stack's and the tape's state read only in `sfshell`), and `page-screen` at 0 in `sfpages`; a page
  calls no sheet or dialog host but through the presenters.

## Tests

- **Each page** is tested in the Tester at a width of each tier, with touch and with keyboard and mouse (the
  Tester's `platform`), each with its usual hand.
  - And once with the other hand on each (`Tester::new(pointing=…)`): what is laid out is the same, box for box; only
    how it answers differs.
  - The platform also says the tier with touch and the core's `client.device`, and a replay recorded on one
    platform keeps it.
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

Five steps, each one PR or a few. What changes nothing on screen merges once green; what changes something is
shown before and after, a batch at a time.

1. **The shell apart, `sfshell`.** The shell and the pages call each other today, so this goes in two halves:
   - **1a, the pages' ways into the shell cut,** nothing on screen changed, one kind a PR:
     - Done: the settings' pages' frame (sfdesk's `page_look.mbt`): they call the library's `@sf.page` itself, which
       takes what its frame gives it (`PageFrame`), says a place's top page's actions to the bar over it
       (`@sf.named_actions`) and, in a panel of its own on the tape, its title, back and actions to the shell's bar
       there (`@sf.pane_bar`); what back says is sfbase's `back_label`. The pieces of one arrangement those pages still
       draw (`narrow_*`, `desk_*`) wait in `settings_page.mbt` for the settings' merge (step 3).
     - Done: the sidebars' rows into the library (`side_rows.mbt`: `nav_row`, `nav_item` over `list_row`, the band's
       action, the list under the band, a row's ground); the sidebar's top row stays the shell's.
     - The files' way and tabs (`way.mbt`, `tabs.mbt`) and the chat's side panel (`panel.mbt`) into `sfpages`.
     - What pages read of the shell: `nav_foot`, `status_top` from `@ui.system_bars()`; `toast` the library's
       (`sf/toast.mbt`); `settings_core` into sfbase; `show_page`, `rail_go` through `open_page`, `go_place`.
   - **1b, the shell moved** as it is into `sfshell`, its `view` the main's; `tier-outside-shell` in, its bars as they
     are then, only falling. The tape's files (`frame`, `chats`, `brand`) in one PR, merged the day it is made.
2. **The pages of one copy moved** into `sfpages` by area (the screen and the player; the settings' pages only the
   desk has; the rest), what they read of the tier handed to the library or the shell as they go.
3. **The pages of two copies merged,** an area a PR, as the pages above are (what the page is for, said first; drawn
   and tested in the three tiers with both inputs; both old copies deleted): the settings and the places, the files and
   the viewer, the history and 奏, a new chat, the chat (the page, the message list, the side panel) last. Before each,
   what each copy has is listed, so nothing is lost.
4. **The tests and fixtures follow the code:** a page's into `sfpages`, the shell's into `sfshell`; sfapp's tests by
   what they test (`open_fixture_over` with them).
5. **Closed:** `sfapp` and `sfdesk` deleted, `page-shell-import` and `tier-outside-shell` at 0, `page-screen` 0 in
   `sfpages`.
