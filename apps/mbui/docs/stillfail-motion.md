# still.fail's motion, as its Android app has it, and mbui's

Every animation of the Android app (ember `apps/android`, at 69be4b7bf), where it is, what sets it off, what moves,
and how (duration and curve, or spring), with its place in the Kotlin; then what mbui has of it (the motion package src/motion,
ui's drawing over layout src/ui/draw.mbt, the screens in src/sfapp). Compose's own numbers: `tween(ms, delay, easing)`; `spring(dampingRatio, stiffness,
visibilityThreshold)` at mass 1; Motion.kt's `motionSpring(visualDuration, bounce)` is stiffness (2π / 1.2·duration)²
and damping ratio clamp(1 − bounce, .05, 1). Curves are CSS's cubic-bezier (Compose's CubicBezierEasing).
`Animatable` and `animate*AsState` start a frame after they are asked (their first frame drawn at their start), go on
from where they are when told anew (a spring with its velocity, a tween from its value), and end at their duration
(a spring's: until it stays within its threshold, Compose's SpringEstimation). mbui's Anim does all of that
(src/motion/anim.mbt) and src/motion/motion_test.mbt checks its springs and tweens against values printed by Compose's
own classes (animation-core 1.10.1, `scripts/compose_ref.sh`): equal to the float (2e-6 of the way) at every frame,
and the same durations to the millisecond.

Paths: `chat/` is `apps/android/chat/src/main/kotlin/fail/still/android/screens/`, `ui/` is
`apps/android/shared/src/main/kotlin/fail/still/android/ui/`, `app/` is `apps/android/app/src/main/kotlin/fail/still/android/`.

## The shared pieces (ui/Motion.kt, ui/Follow.kt)

| What | Spec | Where | mbui |
|---|---|---|---|
| Reduced motion | One clock for every window (MotionDurationScale 0): every animation at its end at once; the prefs' `motion` (`reduce` / `full`) or the system's animator duration scale 0 | ui/Motion.kt:43-80 | `@ui.reduced_motion()`: the host's (macOS/iOS Reduce Motion, Android's animator scale 0, Windows' client-area animations off; `@hostapi.reduce_motion`, read once a second) or MBUI_REDUCE_MOTION=1; every Anim, presence, FLIP, flight at its end at once. Screenshots (`Ctx::stable`) likewise. The prefs' own setting: not yet (Settings is another slice) |
| Loops reduced | A loop holds its rest pose (`still`), a spinner turns slowly (`slowMs`) | ui/Motion.kt:82-97 | spinners and breathing exist (src/sf); not slowed when reduced |
| Flash reduced | Shown at its peak as long, then gone | ui/Motion.kt:99-112 | — (no quote jumps yet) |
| Ease.Out | (.2, .7, .2, 1) | ui/Motion.kt:115 | `Curve::Out` |
| Ease.Arrive | (.2, .8, .2, 1) | :117 | `Arrive` |
| Ease.Flight | (.6, 0, .2, 1) | :119 | `Flight` |
| Ease.Standard | FastOutSlowIn (.4, 0, .2, 1) | :121 | `Standard` |
| Ease.CssOut | (0, 0, .58, 1) | :123 | `CssOut` |
| Ease.Decel | (0, 0, .2, 1) | :125 | `Decel` |
| Ease.LeaveFade | (.3, 0, .5, 1) | :127 | `LeaveFade` |
| Ease.Css | (.25, .1, .25, 1) | :129 | `Css` |
| ArchiveEase | (.16, 1, .3, 1) | chat/Chat.kt:273 | `Soft` |
| MoveSpring | motionSpring(.28): stiffness 349.7, ratio 1, threshold .5 | ui/Motion.kt:144-145 | `@ui.move_spring` |
| SheetSpring | motionSpring(.32): stiffness 267.7, ratio 1, threshold .5 | :146-147 | `@ui.sheet_spring` |
| MenuSpring | motionSpring(.24, bounce .08): stiffness 476.0, ratio .92, threshold .001 | ui/Sheet.kt:249-251 | `@ui.menu_spring` |
| Follower | a spring retargeted mid-way goes on from where it is and its speed; the same target changes nothing | ui/Motion.kt:149-169 | `Anim::follow` |
| A list following its end | each frame 1 − e^(−dt/100 ms) of what is left, at least 1 px; more than 12 rows away most of the way at once; slowed by the motion scale | ui/Follow.kt:125-154 | `Ctx::list_to_end` glide (src/ui/list.mbt, before this work) |

## Pages (app/App.kt)

| Motion | Trigger | Property | Spec | Where | mbui |
|---|---|---|---|---|---|
| Push / pop | a page opened or closed | both pages side by side, x ± width | tween(300, FastOutSlowIn) | app/App.kt:538-549 | `Ctx::nav` (src/ui/nav.mbt, before this work) |
| Swipe back | the left edge or predictive back | follows the finger; let go: on, or back | linear in the seek, 300 | app/App.kt:520-531 | `Ctx::nav` |
| Settings from the left | the gear | x from −width | tween(300, FastOutSlowIn) | app/App.kt:545-546 | not yet (Settings is a placeholder) |
| A new chat rises | 令 | y from height; the page under fades out | tween(380, (.2, .8, .2, 1)) | app/App.kt:122, 542-544 | not yet (new chat is another agent's slice) |
| A place switched (bottom bar) | a place tapped | new page slides 30 toward the ball's way and fades in, old out | slide tween(220, Arrive), fade in 220 Arrive, out 90 linear; same place fade 180 Arrive | app/App.kt:492-501 | not yet (bottom bar) |
| Opening waits | a page pushed | waits for what the core has on the device | up to LOCAL_MS 100 | app/App.kt:221-222, 353-362 | — |

## Home: the chats list (chat/Home.kt, chat/ListMotion.kt)

| Motion | Trigger | Property | Spec | Where | mbui |
|---|---|---|---|---|---|
| Rows move to their new places (FLIP) | the list's keys change (a chat with news to the top, one in, one out; a chat asked for here keeps its row by its `clientKey` as its station makes it) | a row's placement (y) from where it was, going on from where it had got to | spring(1, 350, threshold 1 px); taken at once unless the rows changed within 150 ms (CHANGED_MS: a width or something over the rows is the list's own layout) | chat/ListMotion.kt:32-33, 121-134; chat/Home.kt:331-335 | `list_keys` + `layout` (`@ui.row_spring`), Home's rows and day headings (src/sfapp/home.mbt `moving`); measured below |
| Closing over a row gone | a row gone | the rows after it wait | 100 ms (CLOSE_DELAY_MS) while within 50 ms of the change, not for one lifted | chat/ListMotion.kt:28-30, 102, 114-116 | same (the spring's delay) |
| A row new to the list grows in | its key new since the last change, drawn within 400 ms | alpha 0 → 1, scale .9 → 1 (centre) | tween(240, delay 100, (.2, .7, .2, 1)) | chat/Home.kt:321-322, 336; chat/ListMotion.kt:90, 108-112 | `layout(enter=…)` |
| A row gone leaves | its key gone while it showed (not swiped away) | a copy where it was: alpha 1 → 0, scale 1 → .9, under the rows closing over it | tween(200, CSS ease-out) | chat/Home.kt:286, 348-358; chat/ListMotion.kt:96-101 | `layout(exit=…)`: the copy is the row's last frame's instances (src/motion ghosts, `Drawing`), painted under the rows |
| A row that went ahead passes over the others | kept rows' order: one now ahead of others it was behind (not a day heading) | drawn over its siblings; a ground of its own (ink 6% over the page) held to 60%, then fading | 480 ms linear | chat/ListMotion.kt:91-95, 118-119; chat/Home.kt:323-345 | `Ctx::lifted`, `Ctx::put_over`; the ground in `chat_row` |
| Come back to | the list drawn again after frames it was not (its page come back to from a chat, its pane slid to) | nothing moves: drawn as it is, as Android composes the list anew (a new ListMotion) | — | app/App.kt AnimatedContent; chat/Home.kt:266 | `list_keys` (a list not built the frame before is new again) |
| Held order | a finger on the list or it scrolling | rows keep their places and days; new ones come in where they would be; let go, the list as it is | — | chat/ListMotion.kt:159-189; chat/Home.kt:269-284 | yes (`held_order`; `Ctx::list_moving`) |
| A chat's mark comes | its tone changes while the list shows (within 300 ms) | scale 0 → 1.3 (at 60%) → 1 | tween(320, CSS ease-out) | chat/Home.kt:654-664; chat/ListMotion.kt:191-210 | yes (`chat_mark` `pop`, `marks_seen`) |
| The busy mark turns | at work | rotation | 1200 ms linear, repeating | chat/Home.kt:662 | `@sf.spinner` (before this work) |
| Swipe to archive | a finger across a done row | x follows; 归档 under it fills in ink past 35%; gone off, archived, leaving no copy as it leaves the list | fill tween(140); back MoveSpring with the finger's speed; off tween(200, Standard), then the call; a fling past 500 dp/s | chat/Home.kt:427-520 | yes (home_menu.mbt `swipe_to_archive`; `list_unghost`) |
| The filter's lists switch | 全部 / 我参与的 / 监控中 | the three panes side by side, x | tween(240, FastOutSlowIn) | chat/Home.kt:163, 192-194 | yes (`home_page`) |
| Search opens | the field at the list's top | the lists up 56 dp and out; the bars fade | open tween(280, Arrive), close tween(240, Standard) | chat/Home.kt:181-199; chat/Search.kt:149-157 | yes (search.mbt) |

Android's recordings of these (HomeMotionTest: e2e/tapes/home-*.trace) are replayed over the app (src/sfreplay/tapes_wbtest.mbt), each frame's words held to where Android drew them.

## A chat's list (chat/Chat.kt)

| Motion | Trigger | Property | Spec | Where | mbui |
|---|---|---|---|---|---|
| New rows rise in | a row new to the list while it follows its end, said while the chat shows (a message `said`, an agent `started`), not flown in nor out of an avatar | y +14 dp → 0, alpha 0 → 1 | tween(320, FastOutSlowIn) | chat/Chat.kt:336-343, 552-561, 828-834 | yes (`row_keys`, `entering`; the model now reads `said`, `started`) |
| The list glides after them | something new at the end while followed (from half a second after it is put in place) | scroll | 1 − e^(−dt/100) per frame | ui/Follow.kt | yes: `Ctx::list(glide_on_growth=true)` keeps where it was and glides (before, a list stuck to its end jumped); the jump button's glide was there before |
| A sent message keeps its row | the outbox entry becomes the chat's message | its key stays `o:<outbox id>` (no row leaving, none coming) | — | chat/Chat.kt:351-354, 485-489 | yes (`Reading.sent`; the model reads `outgoing`, the outbox's `seq`) |
| What leaves the chat fades | an outbox row dropped, an activity gone | alpha 1 → 0 (a copy) | tween(200) | chat/Chat.kt:838-844 | outbox rows yes (`keyed(exit=…)`), activities by their own fade |
| An activity comes in | an agent starting while the chat shows, each turn (the core's `started`; in a chat made here, an agent first seen at work in it) | its room opens (height 0 → its own), alpha 0 → 1, scale .5 → 1 from its avatar (9 dp, middle) | tween(220, Ease.Out) | chat/Chat.kt:1529-1556 | yes (`reveal` + look; the room is laid out, as the app's, see below). Its key is its agent's, the same each turn: gone from the chat's end, it is new to the list again (`row_keys`), so a later turn comes in as the first did (Android's app keeps it known: there its later turns are there at once) |
| An activity stays, then goes | its agent stops | stays 600 ms (HOLD_MS), then alpha → 0 over 220 (FADE_MS), its ring out over 160 | tween(220), tween(160) | chat/Chat.kt:396-398, 437-462, 1537, 1603 | yes (`with_lingering`) |
| An activity pushed down glides | something said above it | placement | spring(1, 300, 1 px) (web useActivityGlide) | chat/Chat.kt:393-394, 844 | yes (`layout` in content places; not while words fly, nor as the page before comes in) |
| The floor | an activity folded away | the room it leaves kept so nothing above drops | — | chat/Chat.kt:465-479 | not yet |
| What an activity says changes | another thing to say, after 700 ms | crossfade: new in from 1/4 below, old out 1/4 up | tween(240) fade + slide | chat/Chat.kt:1575-1578, 1630 | not yet |
| The work ring | at work | arc 5° → 235° and back each 1.5 s (ease-in-out (.42, 0, .58, 1) each half), turning every 2 s; one 6 s clock | infinite | chat/Chat.kt:1592-1628 | a turning arc (`@sf.spinner`, before this work), not the stretch |
| The way to the newest (↓) | away from the end by more than 120 dp, or short of the chat's end | alpha; y +18 → 0 and scale .6 → 1 | in: alpha tween(180, Css), the rest tween(220, Standard); out: 150 and 180; turned back from where it is | chat/Chat.kt:869-878, 921-954 | yes (`presence` in `jump_to_latest`) |
| The bell over it lifts | both show | y 0 → −44 dp | tween(200, Standard) | chat/Chat.kt:881 | not yet (no bell) |
| The bell | what waits to be decided is not in view | as the way to the newest | as above | chat/Chat.kt:972-990 | not yet |
| 归档 in the bar comes and goes | nothing left in the chat | alpha, scale .85 → 1, width from its end | tween(280, ArchiveEase) each | chat/Chat.kt:281-285 | yes (`chat_bar`: presence and its width) |
| 忽略 goes | dismissed | alpha, scale → .85 (top left), height → 0 | tween(280, ArchiveEase) | chat/Chat.kt:956-961 | yes (`ask_dismiss` over decide.mbt `under_post`) |
| A quoted message flashes | a quote tapped (a jump) | the accent's ground: 0 → 1 in 160 ms (Ease.Out), held to 900, → 0 by 1700 (Standard); a passage marked to .24 by 160, held to 1400, gone by 2400 | keyframes | chat/ChatMotion.kt:254-335 | not yet (no quote jumps) |
| A passage picked (long press) | a hold on a message's words | the picked ground (accent 26%), the handles and the bar (引用 / 复制) | none: there at once, gone at once | chat/MessagePick.kt; ui/Pick.kt:143 | the same (no motion, as the app; src/sfapp/pick.mbt) |
| Quotes in the composer | a quote taken into the draft, or dropped | the composer's capsule changes shape round it | the morph (below) | chat/Composer.kt | yes (the morph) |
| A search's words drawn in | opened from a search | strokes under the words | 520 ms each, 180 apart, Standard | chat/ChatMotion.kt:289-295; ui/TextMark.kt:47-48, 108 | not yet |

## Sending (chat/ChatHost.kt)

| Motion | Trigger | Property | Spec | Where | mbui |
|---|---|---|---|---|---|
| Words wait as typed | sent, until their row is in the list | the field's words drawn over the field | ≤ 2 s, then given up | chat/ChatHost.kt:520-534, 629-635 | yes (`flight_waiting`) |
| Words fly into their bubble (open chat) | their row laid out | x on Ease.Flight over the first 80% of 600 ms; y the same 12% late (a curve); their size as typed until they settle; the bubble's ground coming in round them from 24% to 80%; the row's time and the rest coming in as they settle (Ease.Arrive from 24%) | 600 ms linear clock (FLIGHT_MS, FLY .8, SETTLE .24) | chat/ChatHost.kt:112-211, 508-648, 685-693 | yes: the bubble flown over the composer by `fly` (flight.mbt); the words go as one block (the field and the bubble wrap alike), not cut into pieces by line |
| A new chat's first words | a new chat made | where typed from the frame sent until their row is laid out; then across and up together, Ease.Arrive, 480 ms after 90; the list rises from the composer's top, cut there | ARRIVE_MS 480 | chat/ChatHost.kt:145-167, 645 | yes (`flight_carry_*`, flight.mbt: the list's box drawn off its place, the bubble across over the composer) |
| The rows above go up with them | the new row puts them up at once | their offset from where they were, on the words' way up | the flight's `up` | chat/ChatHost.kt:407-420 | yes (`layout(screen=true, drive=up)`) |
| Files fly from their tiles | sent with files | each from its tile to its place, its crop opening, corners from the composer's to 10 dp | the flight's across/up | chat/ChatHost.kt:650-683 | not yet |
| The composer is held | words sent | its content as tall as when sent until they are 24% of the way | — | chat/ChatHost.kt:324-333, 644 | yes (the morph's target) |
| The hint comes back | the words out of the composer's top | the placeholder's alpha | gone at once, back tween(200, Arrive) | chat/ChatHost.kt:470-472, 612-614 | yes, once the words are half way up (not by their bottom against the composer's edge) |
| A new chat's scene leaves | its chat made | up and out, scale .96, alpha; its choices fade where they are | 140 ms Arrive; choices 80 ms LeaveFade | chat/ChatHost.kt:451-460; chat/NewChat.kt:165-215 | yes (`new_chat_leaving`, newchat.mbt) |

## The composer (chat/Composer.kt)

| Motion | Trigger | Property | Spec | Where | mbui |
|---|---|---|---|---|---|
| The capsule changes shape | its content's height changes (a line, a file, a quote, opened, sent) | its height (and so its corners), standing on its bottom edge; ＋, the field, send carried from where they were drawn to their places | one timeline: 260 ms linear clock, Ease.Out | chat/Composer.kt:985-1083 | yes (`composer`: only drawn — the capsule laid out as tall as its content at once, its ground drawn only, as tall as an Anim says on its bottom edge, its content drawn cut to it (`cut_to_bottom`) while it grows, the parts drawn by `layout` in a `scope` from the content's bottom) |

## Over the pages (ui/Sheet.kt)

| Motion | Trigger | Property | Spec | Where | mbui |
|---|---|---|---|---|---|
| A sheet opens | asked | from below (offset → 0) | SheetSpring | ui/Sheet.kt:138-153 | the newchat-bar agent's sheet (src/sfapp/sheet.mbt) is built on it; `@ui.sheet_spring` and `Anim` are its exact form |
| Another sheet in its place | asked while one shows | height → the new one's | SheetSpring | ui/Sheet.kt:147-148 | same |
| A sheet closes | scrim, back, dragged down | offset → its height | SheetSpring | ui/Sheet.kt:150-152 | same; drawn only as it goes (every sheet: the host's, the chat's, the drive's, the settings' (now on SheetSpring both ways), ＋'s) |
| Let go | the grabber's drag ends | height to 55% / 94% / closed (under 30%), from the finger's speed | SheetSpring with velocity | ui/Sheet.kt:158-182 | same |
| The scrim | a sheet asked or gone | black 28% | tween(300, Css) | ui/Sheet.kt:130, 187 | same; fading out, drawn only (a tap is what is under it's) |
| The menu opens | a long press, the filter | alpha in 160 Ease.Out; scale .9 → 1 from its corner by the anchor | MenuSpring | ui/Sheet.kt:276-283 | the filter's menu (src/sfapp/pages.mbt, `presence`) |
| The menu closes | a tap outside, back, an item | alpha out 120 CssOut; scale → .9 | MenuSpring | ui/Sheet.kt:282 | the filter's menu, drawn until it has gone |
| The menu's scrim | | black 28% | tween(200) | ui/Sheet.kt:261 | the filter's menu |
| A toast | said | alpha in and out | tween(200, Css) each; 2600 ms | ui/Sheet.kt:303-322 | yes (`toast`) |
| The reader | a history entry opened in full | x from the right | tween(300, Standard) | ui/Sheet.kt:331-337 | not yet |

## Pressing

| Motion | Trigger | Property | Spec | Where | mbui |
|---|---|---|---|---|---|
| Ripple | `clickable` with Material 3's ripple (Theme.kt), on buttons and rows | a disc from the touch, the pressed state layer | Android's RippleDrawable (≈ 225 ms grow, 75 in, 150 out; pressed alpha .1) | ui/Theme.kt | the pressed grounds come and go on the ripple's timing (`pressing`: in 75 ms, out 150, a short tap shown whole); no disc spreading from the finger |
| A row held | a long press on a Home row | ink 5% ground; its time shows | at once | chat/Home.kt:572, 615 | yes (before this work) |
| An option pressed | a decision's option | scale .97 | tween(80) in, tween(180) out, Ease.Out | chat/Decisions.kt:141-150 | yes (`option_button`) |
| An activity pressed | its line | ink 10% ground round it | at once | chat/Chat.kt:1538-1554 | — |

## Agents' messages out of their avatar (chat/ChatMotion.kt)

| Motion | Trigger | Property | Spec | Where | mbui |
|---|---|---|---|---|---|
| Fold | an agent posts while its activity shows (watched: in front, at the end) | its line folds to its avatar: width → 0 (200, Ease.Out), alpha (160, Ease.Out) | Fold 170 ms | chat/ChatMotion.kt:58, 131-137; chat/Chat.kt:1524-1528 | yes (src/sfapp/emit.mbt; the line cut to its share of its width and faded in `activity`) |
| Float | after the fold | the avatar's copy hops: up to 34 dp over the higher end in 42% of the time ((1 − (1 − u)^2.5)), then drops ever faster (u^2.5), across ease-in-out cubic; stretched (7% up, 14% down) | 440 ms; on to the same agent's next: a drop only, 280 ms | chat/ChatMotion.kt:58, 198-236, 354-358 | yes (`emit_flight`, `emit_flyer`: drawn only, over the list, from where the two ends were last laid out: `@motion.measured_rect`) |
| Spit | landed | the message comes out: scale .35 → 1 from 12 dp, unrolling from its top (Ease.Out), alpha by 35%; the avatar flattened (116% × 80%) springing back (stiffness 520, damping 14) with a 12% swell | 380 ms | chat/ChatMotion.kt:237-246, 360-393 | yes (`emit_out`: a look and mbui's `Ctx::cut_to_top`; the message's own avatar hidden meanwhile) |
| Return | after | the copy goes home, cubic out | 320 ms | chat/ChatMotion.kt:247-250 | yes; one turn after another (not in ListTurns' queue with what else changes the list's height) |

## Waiting and loops (ui/Waiting.kt, ui/Parts.kt, others)

| Motion | Spec | Where | mbui |
|---|---|---|---|
| Words about a wait come after a moment | 400 ms (LATER_MS) | ui/Waiting.kt:66-76 | yes (before this work) |
| A spinner | 800 ms linear; reduced: 2400 | ui/Waiting.kt:89 | `@sf.spinner` |
| The rows to come breathe | alpha 1 ↔ .5, 700 ms EaseInOut, reversing | ui/Waiting.kt:143-148 | yes (before this work) |
| A progress bar fills | tween(200, Ease.Out); indeterminate 1400 EaseInOut | ui/Waiting.kt:220-228 | — |
| A running chat state turns | 1200 linear | ui/Parts.kt:147 | `@sf.spinner` |
| A segmented control's thumb | tween(240, (0, 0, .2, 1)) | ui/Parts.kt:399-408 | — |
| The splash mark floats | 900 FastOutSlowIn, reversing | ui/Parts.kt:577-582 | yes (before this work) |
| A station's eye blinks; its arcs pulse | 2600 keyframes; 700 FastOutSlowIn reversing | ui/StationGlyph.kt:88-93 | — |
| A job breathes | 700, 1 ↔ .35 | chat/Jobs.kt:110 | — |
| A picture's ThumbHash blot; fade when loaded | 1100 EaseOut; 300 after 800 | chat/ChatFiles.kt:404-462 | — |
| History's line marked | colour, tween(900) | chat/History.kt:278 | — |
| A note pinned / popping in | scale 1.12, 160 Arrive; pop .97 → 1 and alpha, 140 Arrive | ui/../screens/Notes.kt:73, 137-146 | — |
| Decisions' deck | a card in 260 Ease.Out; answered: up, 360 (.55, 0, .85, .35); set aside: 1.25 widths, 260 Standard; back MoveSpring | chat/Decisions.kt:380-425, 477 | — |
| A decision's options go, its outcome comes | out: 200 CSS ease-out, scale .9, height by the delayed MOVE spring (100 ms); outcome: fade after 200, height on the same | chat/Decisions.kt:192-222; chat/ListMotion.kt:39-41 | yes in a chat (`decision_under`; no turns: it starts at once, not after what else changes the list's height) |
| The viewer from a thumbnail | open 320 Arrive, close 280 Arrive, fade 140 Out | chat/FilePreview.kt:207-210, 359-388 | — |
| The latest chats' button (wide) | in: fade 180, scale .6 from (8%, 110%) 280; out 160 / 200 | chat/Wide.kt:128-131 | — |
| The keyboard's room | follows the system's insets | ui/Keyboard.kt:82 | the host's insets (before this work) |

## The bottom bar (ui/Bar.kt)

Springs as react-spring's (tension, friction, mass 1) stepped a frame at a time by one loop, retargeted by the finger:
the panel 260/17, the notch 300/30, the held ball 420/16; the ball's spring as stiff as its way is short (300 × 90 /
distance, 90 to 700), stretched by its speed (up to 36 dp); the bar in and out 380 / 300 Arrive; the ball's alpha 200
Css and scale .6 → 1 250 Css; an action's icon swapped (out 120 Css to .5, in after 60: 180 Css, scale .5 → 1 240
Arrive); a place's tint 300 Css; a bar chosen in the panel sliding down into the bar's place as the panel closes
(200/28 from where it was) (ui/Bar.kt:296-400, 460-520, 700-780, 950-970, 1110-1150). mbui (src/sfapp/bar.mbt, the
newchat-bar and glass-bars branches): all of it, the springs stepped as Bar.kt steps them (4 ms at most a step); the
bar going and coming, the action growing and shrinking, its icon swapping and the chosen bar coming down are looks
over where they are laid out (`Ctx::look`), what leaves only drawn (`leaving`: the bar going down, the icon going
out, the bars not chosen and the bar left); the icon's swap is an `Anim` (300 ms linear); `log_frame` puts
`bar/vis`, `bar/panel` and `bar/icon-swap` in the motion log.

## What the Android tests pin down (app/src/androidTest/…/motion)

Harness.kt records every frame on a stopped clock and the share of pixels unlike the settled page; a motion that snaps
at its end shows as a drop. ChatMotionTest: a message sent into a short chat must not snap into place (largest drop
< 2.5%), lines keep their breaks and baselines between the field and the bubble, a row sent under a long reply is in
sight above the composer a second on with no ink left in the field; the composer's shape change; files flying.
RowsMotionTest: an agent's reply out of its avatar (one, a stream, two agents), an activity pushed down, the list
gliding after a message (positions probed), the jump to the latest, quotes flashing. MenuMotionTest: first mount,
dismissal, an interrupted dismissal. OverMotionTest: predictive back, a sheet flung up and pulled down, the viewer
from its thumbnail.

## mbui's primitives: the motion package (src/motion) over ui's drawing (src/ui/draw.mbt)

The rule, kept by how the two are split: motion only changes what is drawn. ui gives a node built this frame a look
(`Ctx::look`, `set_look`: opacity, offset, scale about a point; `put_over`: over its siblings or over everything;
`draw_only`: never tapped nor found by the drive) and paints it so, while its tap rects stay where its
layout puts it, under the clips as laid out: a node drawn moved, faded to nothing or scaled is tapped where it is laid
out, at once (the drive finds it there too). Nothing in src/motion takes a tap, a focus or words, holds a send or waits
for anything: the send goes through its own path at once, and the words flying to their bubble are a picture of them
over the composer and the row's own bubble drawn flown. What has been let go of and is drawn only while it goes (＋'s
sheet going down and its scrim, the filter's menu, the way to the newest, a toast) is built under `leaving`: drawn only,
so a tap meanwhile is what is under it's (the field, the rows). The package plugs into ui through three hooks (`on_after_layout`: its looks from where things are
laid out; `on_list_underlay`: copies of rows gone drawn under a list's rows, `Drawing`; `on_reset`) and reads a frame
through ui's accessors (`node_rect`, `list_above`, `list_scrolled`, …): ui does not know it.

- `spec.mbt`: `Ease` (every curve above; `bezier_at`, Compose's CubicBezierEasing), `Spec` (`spring`, `tween`,
  `motion_spring`, `Snap`; `move_spring`, `row_spring`, `sheet_spring`, `menu_spring`; `Motion`: one of Motion's
  transitions), `spring_at` (SpringSimulation), `spring_duration` (SpringEstimation), `Spec::value_at` (as Compose
  plays it: whole milliseconds, at its end at its duration).
- Motion's API, after Motion (motion.dev, MIT; ported with its copyright): `easing.mbt` (`cubic_bezier` by Motion's
  own solver, `ease_in`/`ease_out`/`ease_in_out`, `circ_*`, `back_*`, `anticipate`, `steps`, `mirror_easing`,
  `reverse_easing`, `easing_named`); `utils.mbt` (`clamp`, `progress`, `wrap`, `velocity_per_second`, `mix`,
  `interpolate`, `pipe`); `generators.mbt` (`spring_generator`: by stiffness, damping and mass or by duration /
  visual duration and bounce, `find_spring` and `bounce_to_damping_ratio` the conversion, a negative bounce
  overdamping it, rest by `rest_speed` / `rest_delta`, `retarget`; `inertia_generator`: power, time constant,
  `modify_target`, sprung back at `min` / `max`; `keyframes_generator`: values at times, eased piece by piece;
  `calc_generator_duration`, `pregenerate_keyframes`, `generator_easing`, `linear_easing`, `Generator::to_css`);
  `transition.mbt` (`spring_to`, `tween_to`, `keyframes_to`, `inertia_to` as a `Spec` for `animate` and `Anim`, which
  play a generator frame by frame; `compose_to_motion`, `motion_to_compose`, `visual_to_compose`: Compose's springs
  and Motion's, both damped harmonic oscillators); `projection.mbt` (Motion's layout projection geometry: `Axis`, `Box`,
  `calc_axis_delta` / `calc_box_delta`, `apply_*_delta`, `calc_relative_*`, `transform_box`: the arithmetic `layout`
  does on laid-out rects). `motion_port_test.mbt` and `projection_port_test.mbt` are Motion's own unit tests for
  those, with their inputs and expected numbers, and the two kinds of spring checked against each other.
- `anim.mbt`: `Anim` (Animatable: `animate`, `follow`, `snap`, `get`, `moving`), `anim`, `animate`
  (animateFloatAsState), `pressing` (the ripple's timing).
- `layer.mbt`: layout animation by key, `layout` (FLIP, Motion's `layout`; in a list by the list's content so scrolling
  moves nothing; `screen` by the view; `drive` by a progress the app gives); `list_keys` (ListMotion: arrived, gone by
  a copy, lifted, closing late, moves only as the rows change); `keyed`, `entering`; `presence` (AnimatePresence,
  AnimatedVisibility); `fly` (shared elements, Motion's `layoutId`); `scope` (places taken from a box's bottom);
  `measure` / `measured`; `reveal` (a height the app animates: the one helper that lays out). MBUI_MOTION_LOG=1 logs
  every moving frame (`MOTION <ms> <key> …`).
- ui (draw.mbt): `Look`, the hooks, `Drawing`, `reduced_motion`, `Ctx::still`, `field_words` (where an editor's words
  are). A subtree drawn moved is painted under its clip moved back by its look (what is drawn inside a box once moved
  is what the box cuts), and what holds it is not left out for being laid out outside a clip.
- The composer's change of shape is only drawn: the capsule is laid out as tall as its content at once, so ＋, the
  field, send and a quote's line are laid out (and tapped) where they end up from the first frame; its ground is drawn
  only (`draw_only`), as tall as the morph says, on its bottom edge, its content drawn cut to it (`cut_to_bottom`)
  while it grows, the parts' places drawn carried. (Laid out at the morph's height and cut there, it had left send and
  a quote's line outside the capsule while it grew: a tap on them was lost, the words stayed in the field.)
- At rest nothing of it paints: every screenshot is as before (0 px on every golden).
- The rule on main's own scrims and sheets (branch glass-bars): the chat's sheets (decide.mbt `sheet_frame`), the
  drive's (`dv_sheet_frame`), the settings' and the sheet host's are built under `leaving` as they go down, their
  scrims too (`scrim(open=)`), so a tap meanwhile is what is under them's (src/sfapp/motion_wbtest.mbt,
  settings_wbtest.mbt; e2e 51–53); the settings' sheet, which went at once, goes down on SheetSpring and lets go of
  its field's keyboard as it goes.
- `reveal` stays the one helper that lays out, on purpose: the Android app opens an activity's room by its layout
  (Chat.kt Activity: `layout { … height * open }`), so in a chat that follows its end what moves is everything above
  it, carried up as the room opens while the list glides after its end (Follow.kt). Drawn only (laid out whole at once,
  its ground drawn growing), the list's end would jump by the whole row and the rows above would go up on the glide
  alone (1 − e^(−t/100 ms) of the row) instead of on the opening's Ease.Out under that glide, a different motion of
  every row in view; and nothing in the room is tapped out of place meanwhile (it is the last row, nothing is laid
  out under it, the row's own tap is where it is drawn but for its scale). The composer's morph is different: there
  what is laid out at the morph's height (send, a quote's line) was outside where it was drawn and lost its taps.
