# still.fail's motion: nine kinds, three rules

Every motion in the app is one of nine kinds. A kind says what the motion tells the person, what sets it off, where
it goes from and to, and which presets it may use. Nothing moves outside these kinds, and nothing is set off another
way (the user, 2026-10-25: 「我感觉现在有不少动效 bug 是因为用了类似 css 的"过渡"效果，而没有准确地去控制什么时候应该去哪，而是直接检测差值」
「应该系统性规划一下不同动效的使用，先要归类一下整个 app 里哪些需要动效，需要多少种动效」).

Why. A motion found by comparing frames (a node's place differs from last frame's, a measured height from the one
before) cannot know its cause. The composer moves or grows because it was typed in, because its page changed, because
words were sent; and also because the window was resized, the sidebar dragged, a keyboard came up, the tier changed.
Only the first should move it. Code that detects the difference rules the others out one at a time: the composer's
place taken from the page's foot to dodge the keyboard and the tape (#1496, #1507), its duration chosen by guessing
whether its page changed, the agent's line not gliding "when older messages came, while words fly, while its avatar is
away". There is always one more, and two causes at once stack. A motion set off by its cause knows its curve and its
ends from the start; every other change is not a motion.

Reduced motion is unchanged: the same clock going fast (docs/ui-panels.md 减少动效).

## The nine kinds

| Kind | It tells | For example | Set off by | From, to | mbui |
|---|---|---|---|---|---|
| 1. In the hand | it is in your hand | scrolling, a row swiped away, a card or a sheet dragged, the pictures' strip, swiping back | the pointer | with the hand while held; let go, on at the hand's speed to where the gesture chose | `Anim::animate(…, velocity=)` at the release; the lists, the pager, the sheet, zoom |
| 2. Coming and going | where it came from, where it went | menus, popovers, sheets, dialogs, toasts, a new message, the agent's line, bars hidden and shown | whether it is shown | from what it hangs on (its trigger, the window's foot, its own place); going, a copy where it was | `@motion.presence`, the presenters, `list_keys`' enter and exit |
| 3. Moved or reshaped | the same thing, elsewhere or in another shape | the composer growing with its words or going to another page; the sidebar folding; a side panel; rows making way | its cause, said | from where it is drawn now to where the frame of its cause lays it out; a layout changed with no cause is there at once | `Ctx::move_state`; `@motion.layout` given its cause (the way there, 2) |
| 4. Flying | this became that, over there | words sent into their bubble; a message out of an agent's avatar; a thumbnail into the viewer | the action | to the arrival point: the real thing at its end, drawn from the start and let go there | `@motion.fly`, sfbase's flight.mbt and emit.mbt, the viewer |
| 5. Another page | you went somewhere | pushed and popped, risen, another place on the bar, the tape | navigation | its way says where the page is (deeper, over, beside); what is on the page does not move of its own as it comes | `@ui.Nav`, the shell |
| 6. Scrolled to | the view goes where you should look | new rows at the end followed, words sent, a message jumped to | its cause (rows came, a send, a jump) | one law, the glide | `Ctx::list_to_end`, `glide_on_growth` |
| 7. A control answering | it took your hand, or its value changed | a ripple, a hover, a switch, a segmented thumb, a fill, "copied" | the control's own state | a value of its own look, never its layout | `@motion.animate` / `follow` on that state, `@motion.ripple`, `Ctx::cover` |
| 8. Waiting | something is under way | the skeleton's breath, a spinner, a progress band | the clock, as a cycle | only these three (docs/ui-panels.md 等待) | `Ctx::cycle`, `Ctx::every` |
| 9. Emphasis | look here | a message jumped to, lit; a search's strokes; a mark's pop | its cause (the jump, the match) | lit, then gone | `Anim::animate` told at the cause |

Kind 7 is the only one where "its state changed, so it eases to the new value", what a CSS transition does, is
right: the state is the control's alone and means one thing.

## What does not move

- What its container does to it: the window resized, the sidebar dragged wider, a keyboard coming or going, another
  tier, the device turned. It is laid out where it now goes, in the same frame. When the container itself moves (a
  page sliding in, the tape), it goes with it, as part of it.
- Content swapped: another chat in the same pane, a page's data read again. A whole page never crossfades.

## Three rules

1. **No motion from a layout's difference.** A place or a size moves only when its cause says so, from the frame of
   its cause. No node moves because its laid-out box differs from last frame's, and no measured size (`measured`,
   `measured_rect`, `laid_size`, `laid_rect`, `rect_of`) is the target of a follow. What follows another's layout is
   placed in the same layout (docs/determinism.md in the framework: `Ctx::cover`, `place_by_size`).
2. **No time window as a cause.** "Moves within 150 ms of a list's change are the list's", "half a second after it
   is put in place it may glide": a window lets through whatever falls into it and holds back what falls outside. A
   cause is an event, or a state that changed.
3. **No logic reads whether a motion runs.** What is shown, what can be pressed and when state is cleared follow from
   the cause and the motion's declared end (`ends()`), never from `moving()` (the framework's determinism.md: logic
   waits for no motion's end).

## Presets

Each kind has a few, named in `src/sf/motion.mbt` (the way there, 7), and every motion uses one of them. Their
numbers are the web's at the same place (paths from the repository's root), not made up here.

| Kind | Preset | Value | The web's |
|---|---|---|---|
| 1 | let go, small: a row, a card | spring 0.28 s, no bounce | `MOVE`, web/ui/src/motion.ts:26 |
| 1 | let go, large: a sheet, the pictures' strip | spring 0.32 s, no bounce | web/src/mobile/app.tsx:526 (a sheet), web/src/FilePreview.tsx:743 (`SLIDE`) |
| 2 | by its trigger: a menu, a popover, a picker, the `@` menu, the switcher, a hover's card | in 140 ms ease-out, from 0.97 and clear; out at once | web/ui/src/styles/controls.css.ts:71 (`popKeyframes`) |
| 2 | a tip | in 120 ms ease-out, a fade | web/ui/src/parts.css.ts:336 |
| 2 | a sheet | up 380 ms `--m-ease`, down 300 ms; its scrim to 0.28 over 300 ms | web/src/mobile/app.css.ts:82-97 |
| 2 | a dialog | 200 ms ease-out; its ground's fade 180 ms | web/ui/src/parts.css.ts:180, 193 |
| 2 | a row of a list, a message | in 220 ms ease-out, up from 6 below; out 200 ms, a copy shrinking to 0.9 | `ENTER`, `LEAVE`, web/ui/src/motion.ts:19-22 |
| 2 | a bar | in 380 ms `--m-ease`, out 300 ms | web/src/mobile/Bar.css.ts:17 |
| 2 | a toast | in 200 ms ease-out, out 150 ms | web/ui/src/toast.css.ts:16-18 |
| 3 | a shape: the composer, a card | 260 ms ease-out | web/src/morph.ts `useMorph` |
| 3 | a layout switched: the sidebar, a side panel, the tape | 380 ms ease-out | `moveState`, web/ui/src/motion.ts:287 |
| 3 | rows making way | spring 0.28 s | `MOVE`, web/src/listMotion.ts |
| 4 | words sent | 520 ms on the flight's curve (0.6, 0, 0.2, 1) | web/src/madeChat.ts:329-331 (sfbase/flight.mbt) |
| 4 | a picture into the viewer and back | 320 ms `--m-ease`; back 280 ms | none on the web, which fades it in over 140 ms (web/src/FilePreview.css.ts); Android's FilePreview.kt (sfbase/viewer.mbt) |
| 5 | pushed, popped | 300 ms `--m-standard`; swiped back and let go, 200 ms | web/src/mobile/app.css.ts:16, 22-30 |
| 5 | risen | 380 ms `--m-ease` | web/src/mobile/app.css.ts:32 |
| 5 | another place on the bar | 220 ms `--m-ease`, from its side | web/src/mobile/app.css.ts:34 |
| 6 | the glide | a share of what is left, τ 100 ms | `GLIDE_TAU`, web/ui/src/motion.ts:33 |
| 7 | pressed, pointed at | 140 ms ease-out | `--dur`, web/src/styles/global.css.ts:104 |
| 7 | a value moved: a segmented thumb, a switch, a fill | 240 ms ease-out | web/ui/src/parts.css.ts:64 |
| 7 | a finger's ripple | in 450 ms, out 375 ms | none on the web (Android's RippleDrawable) |
| 8 | breath, spinner, band | 1400 ms; 800 ms a turn; 1400 ms | web/ui/src/waiting.css.ts, web/ui/src/styles/spinner.css.ts |
| 9 | a message gone to | in 160 ms, held to 900 ms, gone by 1700 ms | web/src/Jobs.css.ts:199 |
| 9 | a passage gone to | 2400 ms | web/src/styles/global.css.ts:299 |
| 9 | a search's strokes | 520 ms each, 180 ms apart | web/src/styles/global.css.ts:278, 290 |

### Not settled yet

Where mbui differs from the web today, or the web from itself. Each is settled when its kind's step comes (the way
there), old and new side by side:

- A new message on a phone: the phone's web rises it over 320 ms on `--m-standard` (web/src/mobile/styles/root.css.ts:124),
  the computer's over 220 ms.
- Words sent on a phone fly 600 ms (Android's ChatHost.kt), on a computer 520 ms.
- The composer going to another page: 340 ms (web/src/styles/global.css.ts:257, the view transition) against a layout
  switched's 380 ms.
- A menu has two comings in mbui (`@sf.pop_in` 140 ms over kit's presence 120 / 80 ms); a popover kit's 150 / 100 ms,
  a dialog kit's 150 / 100 ms, where the web has 140, 200 / 180.
- Pointed at: buttons ease on a spring (k 900, sf/parts.mbt), the sidebar's rows over 140 ms.
- A switch on `spring()`, the web's thumb over 240 ms; a known progress moves over 200 ms on the web
  (web/ui/src/waiting.css.ts:61), mbui's band jumps.
- The player's bars fade 200 / 200 ms, the viewer's bar 120 / 320 ms, on the same screen.
- The agent's line making way on its own spring (k 300, sfpages/chat_list.mbt) against rows' 0.28 s.
- Zoom's glide (260 ms, Soft) is written three times; "copied" three ways (1500 / 1600 / 1600 ms); the breath two
  ways (sf/waiting.mbt, sfdesk/jobs.mbt); two curve enums (`@motion.Ease`, `@ui.Curve`) and two sheet springs carry
  the same numbers.

## The way there

From the inventory of 2026-10-25: about 300 motions, most set off rightly (the presenters, the sidebar's moves, the
list's turns, words flying, everything in the hand). Each step below is a PR; a visible change shows before and after.

1. This document (#1626). Done.
2. **The library.** Done: `@motion.layout` moves only for its cause (`by`), a node moved by nothing it names placed at
   once (#1634); a list's rows move for the list's change in that frame, not for 150 ms after (#1637); a box reshaped
   draws its ground from the shape it had to the new one (`@motion.reshape`, morph.ts `grow`: #1640); detlint's
   `follow-layout` and `motion-read` only let what is left fall (#1639).
3. **The composer** (sfpages/composer.mbt, every tier's since #1646). Done: reshaped for what it holds (its words,
   files, quotes, its being opened, its error) and for its page, its ＋, words, send and choices carried from where
   they showed by the same cause; for its page, what it holds there and did not here (a new chat's choices) carried
   on its ground until that is there (`@motion.reshape` `carry`, morph.ts `morph`); held for words sent; nothing for
   the window, the sidebar, a keyboard or the tier.
   Laid out as it ends at once, its page's foot and the ↓ button follow what it is laid out as. The page's foot stays
   what its parts take their places from (`@motion.scope`): the page moving, with the composer in it, moves none of
   them.
4. **Sheets.** Done: a sheet's height is what it holds as this frame lays it out (read back, the frame built again
   at once), there in its first frame and with it as that changes, never sprung to what the frame before measured
   (`@kit.sheet`, the presenters, the chat's sheets, a station file's); one found taller than a sheet's most stays
   that tall while open. Its rising, sinking and a finger's drag are its only motions. The hosts becoming one (the
   presenters for the chat's, the settings', the drive's and the link menu) goes with each of those pages' merge.
5. **The chat's list.** Done: a turn waits for the list's glide after what came, as the list was last laid out, not
   for the reader's hand (ListInfo's `glide_rest`, listQueue.ts listStill); the list glides after a row new to it the
   frame it comes, with no half second after it was shown first (what was there or caught up on is there at once)
   (#1683). The agent's line and words not yet in the chat make way for the newest row that came in over them, their
   one cause (row_keys's `came`, `makes_way`): not for the page before, words flying in or their own message out of
   the avatar, with no stand-ins for those (#1691). What is drawn where real things are while they move is placed as
   this frame lays them out (`@motion.placed`), never a frame behind, moved from where it is laid out: the avatar
   flying out of an activity to its message and back, a new chat's list drawn up behind its first words and the
   pictures flying with them (#1697). The line folding to its avatar goes from the width it was shown at as it starts
   folding (the shape it had), no target.
6. **The sidebar and the side panel.** Done: the sidebar moves for what it is asked (folded or opened as chosen,
   shown a while, a place with no sidebar of its own, another place's own width: brand.tsx moveSidebar's callers), not
   for the window's room (a tablet's too narrow, a fold, the tape coming or going), which puts it there at once. A side
   panel moves when it is opened or closed by what the page asks (side_change, from its header, its tabs, a link, a
   menu: the web's useSidePanel `changing`), and is so at once as a page opens with its tabs as they were left or a
   chat made from the new chat opens its 文件 with it; that was already so.
   Logic that reads a motion, now its cause and the end it declared as it was told (`Anim::over`, mbui): a new chat
   leaving, 奏's cards going off and going back (the phone's and the desktop's), the search going back, a row swiped away
   (archived at that end, not when it is seen at its place), the bar's panel (its spring's declared rest, `Spr::end`); a
   stroke, a picture's way in and a row's rise started once by what they are told, not by whether they move; what only
   logs a motion logs it while it is off its target. A message out of an avatar (its poses), words sent (their
   way) and the viewer's strip likewise.
7. **Presets.** `src/sf/motion.mbt` holds the table above; every motion uses a preset; one curve enum; the copies in
   sfapp that nothing calls go (emit_flyer.mbt, flash.mbt, `composer_page*`, …).
8. **The page crossfade** between a new chat and a chat on a computer (sfdesk/switch.mbt). Done: the new chat's scene
   leaves by its own way up (as one become its chat does), what comes in is there at once, the composer moves between
   their places.

The inventory's list, site by site, is in the chat that made this (still.fail chat c-70f465c94a, 动效盘点.md); it is
not kept here, as it goes out of date with each step.
