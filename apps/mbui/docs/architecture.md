# One app: the screen, the input, pages and the shell

still.fail's mbui app is one app on every device (the user, 2026-10-24: 「应该得打成同一个 app 了」). There is no phone
app and desktop app. How it is laid out follows the screen: its kind (a touch device or a computer) and its size, in
three tiers. How it answers the hand follows the input, and only that: the input never decides what is shown, where,
or how big (the user, 2026-10-25: 「布局不是按屏幕类型和尺寸来的，而是跟操作方式有关……我怀疑是系统性问题」). A tablet given a
trackpad, a laptop touched on its screen, stays laid out as it was. Each page exists once and is drawn into whichever
tier it lands in, on either kind of screen, with either hand.

This replaces the earlier "the desktop and the phone are two apps" (two page sets: `sfapp`'s, ported from the Kotlin
app, and `sfdesk`'s, ported from the web's desktop files). The way from here to there is at the end.

## The screen and the input, each read in one place

| What | Read by | What it is |
|---|---|---|
| The screen's kind | `@sf.touch_system()` (sf/tokens.mbt) | A touch device (a phone, a tablet: iOS, Android) or a computer (macOS, Windows). The platform's, the same for the whole run; a Tester's by its `platform`. |
| The tier | `@sf.layout(width)` (sf/tokens.mbt) | `Small`, `Medium`, `Large`, by the window's width in points on every screen (600, 840): which way up it is held, its height and its size say nothing of the panes, the height only how much of them shows. The one exception the crease: a fold half open, crease across, is `Small`'s chat. Held while the app holds the device sideways (`@hostapi.sideways()`). |
| The input | `@ui.pointing()` | `Finger` or `Mouse`. It may change while the app runs. |

A phone is used upright only (a touch device whose short side is under 600 points: a phone, a fold's outer screen):
Android's activity asks for portrait there (`Host.upright`), an iPhone supports portrait alone (ios_app.m `mb_upright`).
The app turning it itself is the exception (a film full screen, a station's screen: `@hostapi.set_sideways(true)`); back
upright after. A tablet and an opened fold's inner screen turn as they are held.

- **The layout is the screen's.** Its kind and its tier, and a page's own width (below), decide everything about what
  is shown, where and how big. Nothing else does: `wide_on`, `@settings.wide`, `t.narrow`, the viewer host's `narrow`
  and `set_web_lines(wide)` go, and so does every use of the input for any of these.
  - **The tier:** how the shell arranges the panes, and where something opened goes (pushed, a pane, a side tab).
  - **The kind:**
    - the look: the theme's palette, type scale and row heights, and touch targets (44 at least on a touch device);
      a touch device's is the phone's, a computer's the web's. The panes side by side are told apart by their grounds in
      both, as the web's: the sidebar a step under the page's ground (touch: the page's beige `bg`, the sidebar a step
      under it, what is chosen in it a step under that);
    - what a page offers to reach things: on a touch device the search field at the top of the chats' list, on a
      computer ⌘K;
    - the keyboard: on a computer Enter sends and the composer takes the focus as a chat opens; on a touch device Enter
      makes a new line and nothing raises the keyboard unasked.
  - **Both:** how a menu, a pick or a confirm shows (Presenters, below): a sheet on a touch device short of Large,
    else a popover or a dialog. And where ⌘K's search shows: its panel over the window, or in `Small` the search page.
- **The input only says how a thing answers the hand.** Changing hands changes none of the layout:
  - feedback: `c.lit` lights on hover with a mouse and on press with a finger;
  - what a pointer over a thing shows (`c.hovered`: a row's time, its 归档), which a finger reaches otherwise (the
    row's menu);
  - menus: `c.menu_asked`, a right click or a long press, opening the same menu, shown as the screen says;
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

What differs comes of two things alone, the screen's kind and a width, and none of it is decided in a page:

| What differs | By | Decided in |
|---|---|---|
| Sizes: the type, row heights, density, touch targets (44 at least on a touch device) | the screen's kind | the theme, chosen once (`@sf.begin`) |
| What only a pointer's hover would show (a row's 归档, its time, its ⋯): on a touch device always there, or on a long press | the screen's kind | the library's parts (sf/hand.mbt) |
| A menu, a pick, a confirm: a sheet from the foot, or a popover or a dialog | the screen's kind and the tier | the presenters |
| Reaching things: the search field over the chats' list or ⌘K; the bottom bar or the rail | the screen's kind and the tier | the shell |
| Enter makes a new line or sends; the keyboard raised as a chat opens or not | the screen's kind | the library's fields |
| Scroll bars: none on a touch device | the screen's kind | the library (`scroll_bar.mbt`) |
| The panes: one stack, the tape, columns | the tier (the window's width) | the shell |
| A page's anatomy: narrow, under 640 (back over a large title, its rows grouped on inset cards under their headings), or wide (its head, one column at most 760 in the middle, sections with their titles, lists and cards) | the page's own width | the library's parts |

So:
- **A phone:** Small, a page at a time, laid out narrow, a touch device's sizes, sheets, the bottom bar, swiped back,
  upright.
- **A tablet:** the tape held upright (Medium), columns on its side (Large); each pane laid out by its own width (a
  narrow one narrow); a touch device's sizes and targets; sheets on the tape, popovers in columns; the rail; turned as
  it is held.
- **A computer:** columns (Large), laid out wide, the web's sizes and density, popovers and dialogs, ⌘K and the keys,
  what a pointer's hover shows. A window made narrow takes the tape or the stack and the narrow anatomy, at a
  computer's sizes.

## Three kinds of UI code

### The library (`src/sf`)

Parts, tokens, motion (its kinds, rules and presets: docs/motion.md), the viewers (Reader, Player, ViewerBar and the
frame around them), and the **presenters**:

- `@sf.menu`, `@sf.pick`, `@sf.panel` (a small panel of rows or fields), `@sf.confirm`, `@sf.ask`.
  - A sheet spans the window, not the pane that opened it: on the tape it is over every panel.
- A page says what it shows; the presenter decides how:
  - on a touch device in Small or Medium, it shows as a bottom sheet;
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
or one width's look alone: a page cannot reach for a wrong one. (Today they are two sets: sfdesk's `page_look.mbt`
`look_*` know both widths; the library's `@sf.section`, `@sf.switch_row` and the desk's card know only the web's
desktop, and a page made of them is the desktop's on a phone (#1675's Profile, #1599's station, #1576's connect). They
become one set, in the library.)

### Pages

One implementation per function: the chats' list, a chat, a new chat, a history, 奏, the files and a folder, each
settings page, each place, sign-in, the landing. There is no phone copy and desk copy.

- **Its box:** it draws into the box it is given. `c.width` and `c.height` are its pane's; it never subtracts a rail
  or a sidebar itself.
- **What it reads:** its own width for its arrangement (columns that drop, tools into ⋯), its anatomy through the
  library's parts, and nothing of the screen's kind: what differs by it is the theme's, the parts', the presenters'
  and the shell's (the table above). A page that needs something to differ by the screen asks the library for a part
  that does it, and the part holds the difference for every page; no page draws a touch device's piece and a
  computer's piece under an `if`. detlint's `page-screen` counts what reads `@sf.touch_system()` in the pages
  (`pages.roots`), each file's bar only falling, to 0. The input reaches it only through the library's primitives
  (above). Never the tier, and never `@ui.pointing()` itself.
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
  | Medium | The tape: list, page and detail are separate panels, one active. A press on what shows of another brings it over; dragged across there it comes with the finger (2026-10-25), a drag on the one in use is that one's own; the list never folds by itself. | A full-window layer (a screen, the viewer) first; then detail → page; page → list when the stack holds only the chat, else a pop | The rail |
  | Large | Columns: the rail and the list, the page, the detail. | The web's (⌘[, the chat's neighbours) | The rail |

- **One model:** `app.nav` stays the one model of where the person is. One table in the shell says, for each `Page`,
  which pane it is.
- **What a page is given:** its box (width and height) and its insets (where its bar's back goes, the room under it:
  a tape panel's own inset, the keyboard). A page does not work these out from the tier.
- **What it owns:**
  - reading the screen's kind and the tier;
  - the stack's motion, the tape and the columns;
  - back, the bars, the rail and the window's inset;
  - the presenters' host, toasts and the keys (⌘K, ⌘/, the core's keymap);
  - the app-level things: signing in, links, notifications, the dock and the menu bar (sfbase).

## The packages

| Package | Holds |
|---|---|
| `src/sf` | The library. |
| `src/sfbase` | The model: `Source`, the core's views, the navigation (`Page`, `app.nav`), the app-level things, and the machinery pages share (drafts and references, flights, thumbnails). The settings' `Core` and `Route` stay where it reaches them. |
| `src/sfpages` | The pages, each file named after the web's. |
| `src/sfshell` | The shell, and the app's `view`, which the main calls. |

- **What goes:** `src/sfapp` and `src/sfdesk`. A merged page moves into `sfpages`; the frames' pieces (the phone's
  stack and bottom bar, the desk's frame, tape, rail and columns) move into `sfshell`.
- **detlint holds it:** `sfpages` may not read `@sf.layout`, `wide_on`, `@ui.pointing()`, or the stack's or the tape's
  state, and may not call a sheet or dialog host but through the presenters.

## Tests

- **Each page** is tested in the Tester at a width of each tier, on a touch device and on a computer (the Tester's
  `platform`), each with its usual hand.
  - And once with the other hand on each (`Tester::new(pointing=…)`): what is laid out is the same, box for box; only
    how it answers differs.
  - The platform also says the tier on a touch device and the core's `client.device`, and a replay recorded on one
    platform keeps it.
- **The screenshots** (`screens.sh`) cover the three tiers.
- **Replays** recorded at one tier keep their traces. A flow that only one tier has (the bottom bar, the tape) is that
  tier's.
- **The rest is as before:** time is declared, and nothing waits for motion (AGENTS.md).

## The way there

1. **The screen and the input read once.** This is the shell's work (the chat 按屏幕分三档布局). The hidden axes go:
   `wide_on`, `@settings.wide`, the viewer's `narrow`.
   - To do (2026-10-25): what was put on the input that is the layout's goes back to the screen's kind: `@sf.begin`'s
     theme and density, the presenters' sheet, and every page's own read of `@ui.pointing()` for its look, its rows or
     what it offers (the search field). The pages then read the input only through the library's primitives, and
     detlint's fence holds it.
   - Done: `wide_on` is gone (the shell reads `@sf.layout` where it arranges, and the phone pages' wide branches,
     never drawn, with it), and `@sf.begin`'s theme follows `@ui.pointing()`, not the system: a finger's the phone's, a
     mouse's the web's; laid out Small still the phone's whatever the hand, as the phone's pages carry its palette in
     places, until step 4 makes them one with the web's. A Tester or a program says the hand apart from its system
     (`Tester::new(pointing=…)`, `@ui.set_pointing`: the phone's screens recorded on a Mac are a finger's).
   - Done too: the viewer host's `narrow` (the reader and the player go by the tier, as the file viewer's frame does).
   - Left to the merge that rewrites its readers: `@settings.wide` (the settings pages, merged, go by their own width).
2. **The presenters** land in the library, and the three sheet hosts and the desk's dialogs move onto them.
3. **Navigation by what is opened,** with the pane table in the shell.
   - Begun: sfbase's `Shell` has `open` (a `Page`) and `detail` (a chat's tab), called as `@sfbase.open_page` and
     `@sfbase.open_detail`; the shell (sfapp's `pages_shell`) answers by the layout at the moment (`open_where`,
     `detail_where`): Small the phone's stack (a new chat risen), the wide frame the page pushed and a chat's detail
     its side panel's tab (sfdesk's `main_page` lays a detail asked as a page beside its chat, also when the layout
     changes under a stack). sfbase's routers (links, search, jump, the settings' core) and sfpages open so; a merged
     page does too. The phone's and the desk's own pages still push until they merge.
   - A chat opened on the wide frame (`open_chat_beside`, from a list's row, a search, ⌘K, a link) is the page pane's
     in place of what was there, never over it; from another place the chats come first; the chat open already,
     nothing.
   - A place gone to is sfbase's `go_place`, for the bottom bar and the rail alike.
   - Back is sfbase's `back_step` / `go_back` (`Shell`'s `back`), by the tiers' table: Small (sfapp's `back_where`)
     a page popped, a place's top page back to the chats; Medium and Large sfdesk's `wide_back` (Large: none from the
     new chat beside the chats alone, the page there never empty). Both frames take the
     system's back, the back key and ⌘[ through it; the Small stack's swipe is the stack's own and pops as it does.
     A page's own back (its bar's) is `go_back`; its 关闭 or 取消 (a screen, the reader, the player, a new chat, a
     chat archived) is `close_page`, the page taken off where it lies. What still pops: the shell's own ways to the
     root and the frames' (nav_home, desk_home, the rail's), and the routers that open a page where it goes.
4. **The pages merge, by area, in parallel,** once 2 has landed:
   - the settings and the places;
   - the files and the viewer;
   - the chat: the page, the message list, the composer, the side panel, the history, 奏;
   - the lists and the way in: the chats' list, search and ⌘K, a new chat, sign-in, the landing, the places'
     chooser.
     - Done: the chats' lists (sfpages' `sidebar.mbt`, `chat_row.mbt`, `chat_mark.mbt`, `row_picture.mbt`,
       `changelog.mbt`): one track of 全部, 我参与的, 监控中 and its rows in every tier, a finger's rows the phone's and a
       mouse's the web's desktop's; the frame says what is over them and at their foot and what it adds to them
       (`ListsFrame`: the phone's search field, the update's news and what is left up long, the desk's 奏 and 已归档). The filter's menu
       is one (`filter_menu`), each bar's button opening it. The bars over the lists (Home's top bar, the sidebar's
       band) are left for the places' chooser and the shell.
     - Done: the page of a device waiting in the workspace's lock (sfpages' `lock_wait.mbt`, `pair_steps` also
       设置 › 安全's): the web's mobile screen on a touch device, its desktop page on a computer; the shell puts it in
       the page's place (laid out Small under Home's bar, over the navigation bar).

   Each merged page is drawn in all three tiers with both inputs and tested so, its old copies are deleted, and its
   films (old and new) are made per tier.
5. **The names and the fence:** `sfpages` and `sfshell` take the code, `sfapp` and `sfdesk` are gone, and detlint's rules
   are in.
