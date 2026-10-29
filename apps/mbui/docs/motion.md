# still.fail's motion: nine kinds, four rules

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
| 8. Waiting | something is under way | the skeleton's breath, a spinner, a progress band | the clock, as a cycle, drawn each frame while it shows (gone when what it waits for comes); what stays up as long as something elsewhere lasts steps, below | only these three (docs/ui-panels.md 等待) | `Ctx::cycle_look` (a look: never built anew for it), `Ctx::cycle`, `Ctx::every` |
| 9. Emphasis | look here | a message jumped to, lit; a search's strokes; a mark's pop | its cause (the jump, the match) | lit, then gone | `Anim::animate` told at the cause |

A mark that stays up for as long as something elsewhere goes on (a chat at work's spokes, a station's glyph blinking
while it works, a chat's waiting dots and watching beat, a service's breath while it is alive or restarting) is not a
wait: it can be up for hours, so it steps on one clock, a frame each 100 ms, never on each of the display's frames
(still.fail's 「进行中」逐格走: `Ctx::cycle(resident=true)`, `@sf.spoke_step_ms`). A wait is short and watched, so it is
drawn smooth, as the web's CSS loops are (2026-10-25, the user: waits stepped with the rest looked choppy, 「某些非常驻的不应该降」).
What changes of such a mark is its look (how strong it is, how big, how far turned: the spokes and the segments turned
an eighth a step, a spinner turned, a dot breathing or beating), so it is a look by the clock (`Ctx::cycle_look`):
worked out as each frame is drawn, never read as it is built, so what holds it (a chats' list, a sidebar) is not built
again for it (2026-10-27: each step of a chat's spokes built the phone's whole sidebar again, 10 ms ten times a
second).

Kind 7 is the only one where "its state changed, so it eases to the new value", what a CSS transition does, is
right: the state is the control's alone and means one thing.

## What does not move

- What its container does to it: the window resized, the sidebar dragged wider, a keyboard coming or going, another
  tier, the device turned. It is laid out where it now goes, in the same frame. When the container itself moves (a
  page sliding in, the tape), it goes with it, as part of it.
- Content swapped: another chat in the same pane, a page's data read again. A whole page never crossfades. Existing chat messages show at full opacity in their first frame, including older rows loaded above; only genuinely new messages enter.

## A page's first frame comes before its motion

A page brought in (kind 5: pushed, risen, gone back to) is built whole in the frame its slide starts in: its words
shaped and its rows laid out for the first time, which can take longer than the display's frame. That frame draws it
where it starts; the display says how late it reached the screen (the host's `frame_late`), and the slide's clock
starts that much later (at most `nav_late_most`, 100 ms, as long as a page waits for what it shows). The wait comes
before the page moves, not as a skipped step in the middle of its slide (UIKit's and Android's transitions build the
page before they start too). The cause is still the push; its moment moved on by what the display said, an input as
a touch's time is, kept on a run's tape (`LATE`) and given again to a Tester.

On 中屏's tape the same: what is brought over to the page (新建对话, what is shown with the side panel in use) is put
on the page, and the tape brings the page over once the page shows it (`Nav::top_shows`: the core's answer waited for as a pushed page waits for it, at most `LOCAL_MS`), not
sliding over with the page before on it and swapping it mid-way. Every move of a state (`Ctx::move_state`: the tape,
the sidebar, a side panel) waits for its first frame's lateness as a slide does.

## Four rules

1. **No motion from a layout's difference.** A place or a size moves only when its cause says so, from the frame of
   its cause. No node moves because its laid-out box differs from last frame's, and no measured size (`measured`,
   `measured_size`, `measured_rect`, `laid_size`, `laid_rect`, `rect_of`) is the target of a follow. What follows
   another's layout is placed in the same layout (docs/determinism.md in the framework: `Ctx::cover`, `place_by_size`).
2. **No time window as a cause.** "Moves within 150 ms of a list's change are the list's", "half a second after it
   is put in place it may glide": a window lets through whatever falls into it and holds back what falls outside. A
   cause is an event, or a state that changed.
3. **No logic reads whether a motion runs.** What is shown, what can be pressed and when state is cleared follow from
   the cause and the motion's declared end (`ends()`), never from `moving()` (the framework's determinism.md: logic
   waits for no motion's end).
4. **No words over words while it moves.** At no moment of a motion are one thing's words drawn where another's are,
   both seen (the user, 2026-10-29: 「查一下现在哪些动效会存在文字叠文字的问题」「加」). Held on every frame a Tester
   draws while something moves (mbui's words_over.mbt); what is over others now is each test file's known number
   (`words_over_known`), which only falls. What grows for its cause while it moves (`@motion.layout` outside a list:
   the composer's field a line taller) shows only as tall as it showed, going to its new height with its move, so what
   it has more comes out as it gets there, not over what stands by it (its ＋ and send, 2026-10-29), fading to its edge
   by each pixel (half a line out shows its half), over no more than it has gone and no more than it has to go: what
   showed is never faded, nothing lights at once as it ends (2026-10-30: a fade by the line dimmed and lit again its
   last two lines); a list's rows make room for each other instead (`makes_room`). A soft cut fades by each pixel
   everywhere (scene.mbt 52-55), never a whole line by its foot.

## Curves

How a motion goes from its start to its end says what it is, so there is one way for each, and a motion uses the
one of what it is (the user, 2026-10-29: 「整体看一下我们动效的曲线，看看能不能系统性规范一下」). A timed motion's curve
is one of `@ui.Ease`, which has no other; a spring is one of `@motion`'s (detlint's `motion-spring` lets the app's own
only fall). The web says the same curves (`@stillfail/ui/curves.ts`: `moveEase`, and in styles `--ease-out`,
`--ease-leave`, `--ease-move`); its moves' lengths are still the three by kind (`MOVE_*_MS`) until it goes by the way's
length too (Lengths, below).

| What it is | Curve | Length |
|---|---|---|
| A move: seen where it was and where it goes, going there (kinds 3 and 5, a picture flown open, the search rising, a sheet rising and sinking) | `Move`: a critically damped spring's way, from rest or as fast as it went | as long as this way is far (Lengths, below): `@ui.move_ms`, 200 + 7.5·√points ms, 200 to 500; nine tenths of the way by half of it |
| What the hand let go of on its way somewhere (a page swiped back or let go short, a row swiped off, a card flung off or let go short) | `Move`, set out as fast as the hand went | as long as what is left of its way is far |
| What the hand let go of with no end of its own, or what makes way (kind 1: a strip, a picture's fling; rows making way) | a spring: `move_spring`, `sheet_spring`, given the hand's speed | the spring's own |
| What comes (faded in, from a little smaller, up from a line below) and a control answering (kind 7) | `Out` (.2, .7, .2, 1), the web's --ease-out | the presets below: 120–240 ms |
| What goes (faded out, shrinking, off the screen) | `Leave` (.4, 0, 1, 1) | shorter than its coming |
| What the hand holds or lifts: a switch's knob held, a ripple's sink, a card lifted, the long-press menu, the loupe | `lift_spring`, the one with a bounce | the spring's own |
| A loop's each way, a stroke drawn | `InOut` | its own |
| Words sent | `Flight` (.6, 0, .2, 1), from rest as a move is | 520 ms over a sent message's usual way (200 points), longer or shorter as a Move of its way is (`flight_way_ms`) |
| Progress handed to another curve, a cycle's turn | `Linear` | |

### Lengths

A move takes as long as its way is far, this time: from where it is drawn as it is told to where it goes (the user,
2026-10-30: 「有些动效不应该固定播放时间，因为它的距离是不固定的」). A length by what kind of thing moves (a row 300, a
page 350, across the window 450) made a row a line taller as slow as one four hundred points taller, which went its
first frames in a leap; and a move told again with a little left of its way took its whole length again. So:

- `@ui.move_ms(points)`: 200 + 7.5·√points ms, between 200 and 500, to whole frames (50 ms: three at 60 Hz, six at 120). The further the longer,
  not in proportion: a row's 64 points 250, a phone's page width 350, across a 1000-point window 450 (to whole frames); a page on
  a wide window slides a little longer than on a phone.
- How far is the furthest anything of it goes for its cause: a box's place, its height, its ground's corners (a
  composer's ground, its words, ＋ and send are one motion, on the furthest one's clock: @motion.layout's `by`); a
  picture's corners as it flies or zooms; a page across its room or up it. A row's height in a list still takes a
  near Move's 300 ms (`row_size_ms`): its way's length comes with the list's rows by key (list_size.mbt).
- Told again on its way (another target, the hand), it goes on from where it is, as fast as it went, as long as what
  is left of its way is far (`@ui.move_path`; @motion.move takes the velocity an Anim has).
- What the hand lets go of on its way somewhere sets out as fast as the hand went.
- What is not a move keeps a length of its own: what comes and goes by fading, a few points' rise or a 0.97 scale
  (kind 2), a control answering (kind 7), what waits and what is lit (kinds 8, 9). Words sent flying (kind 4) keep
  their own curve, their length as a Move's of their way scales (`flight_way_ms`); a message's avatar going home to
  its activity likewise (emit.mbt `return_ms`), its hop a hop's (its time its height's, over the higher of its ends).
  detlint's `motion-length` stops a tween on Move.
- A test waits for a move's end by `@ui.move_most_ms` (any move is over by then), or by `move_ms` of the way it set.

Why a move is a spring's way and not an ease-out. A curve fast from its start puts much of a long way there in its
first frame: on the web's ease-out the tape, 700 points over 380 ms, was 54 points on in the first frame at 120 Hz
and 110 at 60, half way there in a seventh of its time, then crept for the last third (the composer 「一帧动老远」, the
sidebar a jump and a crawl). The speed at its start is also what a frame drawn a little late or early turns into a
step: 3.5 times the mean speed on the ease-out, under twice it at most on a spring from rest, so the same 2 ms off
the display's beat is 13 points off on the tape there and 4 here. A spring's way has no step at its start, is at
its fastest a tenth of the way in, and lands without a crawl one can see. What comes or goes over a few points (a
fade, a 0.97 scale, 6 points up) is not a move: its fast start is what makes it feel at once.

## Presets

Each kind has a few, each named once: the app's in `src/sf/motion.mbt`, the framework's in mbui where it makes that
motion (kit's panels and controls, `@motion`'s springs, ui's pages pushed), as the table says; every motion uses one
of them. Their numbers are the web's at the same place (paths from the repository's root), not made up here, but for
the curves: a move's length and curve are a Move's (Curves, above), what goes goes on `Leave`.

| Kind | Preset | Value | The web's |
|---|---|---|---|
| 1 | let go, small: a row, a card | spring 0.28 s, no bounce | `MOVE`, web/ui/src/motion.ts:26 |
| 1 | let go, large: a sheet, the pictures' strip | spring 0.32 s, no bounce | web/src/mobile/app.tsx:526 (a sheet), web/src/FilePreview.tsx:743 (`SLIDE`) |
| 2 | by its trigger: a menu, a popover, a picker, a select, the `@` menu, the switcher | in 140 ms ease-out, from 0.97 and clear, growing out of its trigger's side; out at once (`@kit.pop_in`, `pop_out`) | web/ui/src/styles/controls.css.ts:71 (`popKeyframes`) |
| 2 | a hover's card: the pointer rested on, left | in 160 ms ease-out from 0.96 and clear; out 90 ms on `Leave` to 0.97 and clear | web/src/Hover.css.ts:10-22 |
| 2 | a tip | in 120 ms ease-out, a fade; out at once (`@kit.tip_in`) | web/ui/src/parts.css.ts:336 |
| 2 | a sheet | up and down a Move as long as it is tall, let go as fast as the finger went; its scrim to 0.28 over 300 ms | web/src/mobile/app.css.ts:82-97 |
| 2 | a dialog | in 200 ms ease-out from 0.98, a little low, and clear; its ground's fade 180 ms; out at once (`@kit.dialog_in`, `ground_in`) | web/ui/src/parts.css.ts:180, 193 |
| 2 | a message | in 220 ms ease-out, up from 6 below (`@sf.enter_ms`, `enter_rise`) | `ENTER`, web/ui/src/motion.ts:19-20 |
| 2 | a row new to a list | grown in from 0.9 and clear over 240 ms ease-out, 100 ms after (`@sf.row_grown_in`) | web/src/listMotion.ts:54 |
| 2 | what goes from a list: a row, the agent's line, what leaves the outbox | out 200 ms on `Leave`, a copy shrinking to 0.9 as it fades (`@sf.leave`) | `LEAVE`, web/ui/src/motion.ts:21-22, web/src/listMotion.ts:116 |
| 2 | a bar | in a Move of its 120 points' drop, out 250 ms on `Leave` | web/src/mobile/Bar.css.ts:17 |
| 2 | a toast | in 200 ms ease-out, out 150 ms | web/ui/src/toast.css.ts:16-18 |
| 2 | what is put in the composer: a file's card, a picture's tile, a quote's card; a notice over a chat's composer (archived, its cache over, its station down) | in 180 ms ease-out, up from 6 below (`@sf.waiting_in`); what a draft or a chat opens with is there at once; a notice no longer said leaves as a row does (`@sf.leave`), drawn as it was | web/src/Chat.css.ts:286, 449; web/src/Jobs.css.ts:217 |
| 2 | a page over the whole window: a chat shared as a picture | in 140 ms ease-out, a fade (`@sf.window_page_in`); out as a dialog (`@kit.pop_out`) | web/src/FilePreview.css.ts:29 |
| 2 | ⌘K | its scrim faded in over 120 ms, its panel grown out of 0.97 from its top over 140 ms ease-out; out at once | web/src/Switcher.css.ts:19, 25 |
| 2 | a chat's find bar, in place of its buttons | in 120 ms ease-out, a fade (`@kit.tip_in`); out at once | web/src/ChatFind.css.ts:10 |
| 2 | woken over a picture or a film: the viewer's bars, the player's controls | in 120 ms, resting out 320 ms, ease-out (`@sf.wake_ms`, `sleep_ms`: kit's media's) | web/src/FilePreview.css.ts:37, 54; web/ui/src/viewer/media.css.ts:23-25 |
| 3 | a shape: the composer, a card | a Move as long as it goes (`@motion.move`) | web/src/morph.ts `useMorph` |
| 3 | the composer to another page | a Move as long as it goes | web/src/dock.tsx, web/src/styles/global.css.ts:257 (the view transition) |
| 3 | a layout switched: the sidebar, the tape, a side panel | a Move as long as the furthest of it goes (`Ctx::move_state`) | `moveState`, web/ui/src/motion.ts:287 |
| 3 | rows making way, the agent's line among them | spring 0.28 s (`@sf.move_spring`) | `MOVE`, web/src/listMotion.ts |
| 4 | words sent | 520 ms (a phone's 600) over their usual way, as long as their way is far once their row is laid out (from where they were typed to where their message has them, the furthest of across and up; a new chat's first words as long as their page's change), on the flight's curve (0.6, 0, 0.2, 1), set alike and broken into lines alike in the field and in the message (the theme's `words`, the composer's width), so moved, in pieces: what is on one line in both, each from where it was typed to where the message has it | web/src/madeChat.ts:329-331 (sfbase/flight.mbt); ChatHost.kt `pieces`, SendText.kt |
| 4 | the composer under words sent: as tall as it was till they are a quarter of the way, then down as a shape | `@sf.shape_ms` from then | ChatHost.kt `hold` (the web keeps only the list's foot, dock.tsx) |
| 4 | the composer's hint under words sent: gone at once, back once they are out of its field | 200 ms on the arrival's curve (`@sf.hint_back_ms`) | web/src/madeChat.css.ts:19-20 |
| 4 | a picture into the viewer and back | a Move as long as its corners go, each way | none on the web, which fades it in over 140 ms (web/src/FilePreview.css.ts); Android's FilePreview.kt (sfbase/viewer.mbt) |
| 5 | pushed, popped | a Move across its room; swiped back and let go, on (or back) as fast as the finger went | web/src/mobile/app.css.ts:16, 22-30 |
| 5 | risen | a Move up its room | web/src/mobile/app.css.ts:32 |
| 5 | another place on the bar | a page's Move from its side; in place, faded in on `Out` | web/src/mobile/app.css.ts:34 |
| 6 | the glide | a share of what is left, τ 100 ms | `GLIDE_TAU`, web/ui/src/motion.ts:33 |
| 7 | pressed, pointed at; a switch turned | 140 ms ease-out (`@sf.dur_ms`, `@kit.switch_ms`) | `--dur`, web/src/styles/global.css.ts:104; web/ui/src/parts.css.ts:85, 94 |
| 7 | a segmented thumb | 240 ms ease-out | web/ui/src/parts.css.ts:64 |
| 7 | a known progress | to a part told anew over 200 ms ease-out (`@kit.progress_ms`) | web/ui/src/waiting.css.ts:61 |
| 7 | a picture's zoom told where | a Move as long as its corners go | Android's Zoom.kt |
| 7 | a finger's ripple | in 450 ms, out 375 ms | none on the web (Android's RippleDrawable) |
| 8 | breath (to 0.5, a restarting service's dot to 0.35), spinner, band | 1400 ms ease-in-out each way (`@sf.breath`); 800 ms a turn; 1400 ms | web/ui/src/waiting.css.ts, web/src/Jobs.css.ts:18, web/ui/src/styles/spinner.css.ts |
| 9 | a message gone to | in 160 ms, held to 900 ms, gone by 1700 ms | web/src/Jobs.css.ts:199 |
| 9 | a passage gone to | 2400 ms | web/src/styles/global.css.ts:299 |
| 9 | a search's strokes | 520 ms each, 180 ms apart | web/src/styles/global.css.ts:278, 290 |
| 9 | copied: a copy button's check, 已复制 | 1600 ms (`@sf.copied_ms`) | web/ui/src/parts.tsx:361 |

### Settled where the web differed from itself

- A new message: the library's `ENTER` (220 ms, up from 6) on every screen. The phone's web rises it over 320 ms on
  `--m-standard`, up from 14 (web/src/mobile/styles/root.css.ts:124); one app on every device takes the library's.
- Words sent: the web's 520 ms on every screen, since the phone took the shared composer (#1646). Android's 600 (its
  flight over 80%, settling from 24%) is left only on sfapp's old composer, which sends nothing of its own now.
- A new chat's first words: words sent like any (520 ms on the flight's curve, the list coming up with them on their
  way up), not the web's 480 ms on `--m-ease` (madeChat.ts toMadeChat), which lands three quarters of the way in its
  first tenth: beside every other send it read as a jump (the user, 2026-10-27: 「非 new chat 的发消息比 new chat 流畅很多」).
  The composer going down to its chat's foot as they set out goes on their way too, not a page's 340 ms ease-out, which
  went a fifth of 200 in its first frame, ahead of words still setting off (the user: 「composer 好像还是会一帧动老远」).
- A card answered from here (and anything answered or let go under a post: 忽略, a vault's or a phone's request, the
  chat's need at its end): on screen it moves nothing. Picked, none is pressed any more, the one picked as it was,
  the rest faded, the line over them saying who decides saying how it went in its place; the answer's row comes in, in a turn kept for it as it is picked (list_turns.mbt `keep_turn`), the
  one change of the list's height. The card does not close: it becomes how it went only out of sight (scrolled away
  and back, the chat left and opened again), at once (`Turns::in_turn`'s `seen`, `Reading::sees`); 忽略 fades where it
  is, its room kept; a card with buttons says how it went in its buttons' room, as high as they were, and the chat's need at its end says it was let go, each fading out, then in (`said_in_place`, settings' `answered_in_place`). Closing the options after the answer (#2245) still moved the list three or four times (the
  user, 2026-10-29: 「后续动效有点太多了而且全是消息列表高度变化」「统一设计一下」); closing them with it (#2222) read
  as the list jumping about.
- Words sent keep the shape they were typed in, so that sending them only moves them (Android's SendText.kt, the
  user 2026-10-26: 「从第一性原理出发」): the composer sets them as a message does (the theme's `words`, a phone's 15 on
  24.75, not the web's 16 on 21, which is there so that iOS's browser does not zoom into a field), and the viewer's
  bubble is as wide as the composer sets them, not the web's 78% of the column and 560 at most; the web flies a copy
  of the message from the size they were typed at instead, their lines jumping as it takes them.
- The same for what goes with them: the viewer's message has its files over its words, as the composer holds them
  (the web has them under), so that each goes straight up to its place, a picture never across the words; and a new
  chat's composer is held as a chat's is while its first words and files are in it (the web lets it go at once).

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
   on its ground until that is there (`@motion.reshape` `carry`, morph.ts `morph`); nothing for the window, the
   sidebar, a keyboard or the tier. Words sent: it is held as tall as it was, its box and its room, while they are in
   it, and comes down for their letting go of it, a quarter of their way, not from under them as they set out
   (ChatHost.kt hold, which sfapp's composer had; its box gone down at once since the phone took the shared one,
   #1646, the words left hanging over it, the user 2026-10-26: 「发消息好像会瞬间把 composer 高度重置」).
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
7. **Presets.** Done: each preset in the table named once (the app's in `src/sf/motion.mbt`, the framework's in mbui),
   each motion of its kind using it. The copies in sfapp that nothing calls are gone (#1714). One curve enum, `@ui.Ease`, played as Compose plays a cubic-bezier, for a page
   pushed, a state moved, a scrollbar and every tween, a curve said by its name wherever it is one (a card's, the
   bar's); one sheet spring, kit's sheet's taken from `@motion.sheet_spring` (#1718). What comes by its trigger is
   kit's, by the presets above: a popover, a menu, a select, a context menu growing out of its trigger's side, a tip
   fading in, a dialog and its ground; each gone at once as it is put away, not faded out (a hover's card, which the
   pointer leaves, excepted). Each comes in the first time it is shown too (`@motion.presence`'s `initial`): the
   presenters' menus, made anew each time they open, had come in at once (#1725). A control answering the hand on
   --dur, a button's ground pointed at and a switch's knob on a tween where they were on springs; a known progress going
   to a part told anew over 200 ms where it jumped; the player's controls woken and resting as the viewer's bars are;
   the agent's line making way on the rows' spring; zoom's glide, copied and the breath one each, not two or three
   (#1733). What goes from the chat's list (the agent's line, what leaves the outbox) goes as from any list (`@sf.leave`:
   it faded on its own curve, not shrinking); the sidebar's rows come and go by the same presets; the sidebar's move,
   the composer's shape and its page move take their numbers from the presets.
8. **The page crossfade** between a new chat and a chat on a computer (sfdesk/switch.mbt). Done: the new chat's scene
   leaves by its own way up (as one become its chat does), what comes in is there at once, the composer moves between
   their places.

The inventory's list, site by site, is in the chat that made this (still.fail chat c-70f465c94a, 动效盘点.md); it is
not kept here, as it goes out of date with each step.
