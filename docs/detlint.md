# detlint: what determinism must not rest on

A run is deterministic because every input is given by the test: inputs, the core's messages, the host's results,
the clock. Not because anything waits for the app to "settle". `scripts/detlint.py` stops what goes the other way:
a guessed time, a wait for stability, a frame the app asks for itself, the machine's own clock. Being settled stays
one assertion, at a test's end (no input, no animation: no frame).

    python3 scripts/detlint.py                 the report; fails above or below the bar
    python3 scripts/detlint.py . --list RULE   every finding of RULE, file:line
    python3 scripts/detlint.py . --update      the counts found become the bar (never raised: --update=raise)
    python3 scripts/detlint_test.py            each rule's failing and passing example

It runs first in `scripts/check.sh` and in CI's test job. still.fail's `apps/mbui` runs this file, of the mbui its
`mbui.rev` pins (`python3 "$MBUI_DIR/scripts/detlint.py" apps/mbui`), with its own `apps/mbui/detlint.json`, from
`apps/mbui/scripts/check.sh` and still.fail's `scripts/check.sh`: a change to the rules reaches it with a bump.

## The bar

`detlint.json` keeps each rule's findings by file (`counts`), and its exceptions the same way (`excused`). Each file
is held to its own bar, not the rule's total: one more finding in any file fails, a finding moved into another file
too (that file is above its bar), naming the file and its lines; the totals are printed. Fewer fails too, until
`--update` lowers the bar in the same commit: what a migration moved off cannot come back. `--update` never raises
a file's bar (a file renamed or split: `--update=raise`, and the commit says why). A rule at 0 is forbidden outright;
once a migration reaches 0 nothing else is needed.

## Exceptions

On the line, or the line over it, with the reason:

    c.request_frame() // det-ok(frame-request): the bench draws every frame on purpose
    # det-ok(script-wait): the emulator's boot has nothing to wait for but its property

Several rules: `det-ok(poll, frame-request): …`. One without a reason is not taken. The report prints every
exception with its reason. They are counted too (`excused`, by rule and file) and only go down, apart from the
findings: marking a finding `det-ok` does not make it go away (`wait 800  # det-ok(flow-wait): …` fails). The one
rule where an exception may take the place of a finding there was is `app-clock` (a time shown is right, below):
there a file's findings and exceptions together stay under their bar, so marking one and running `--update` passes.

## The rules

| rule | stops | instead |
|---|---|---|
| `frame-request` | anything but the scheduler itself calls `Ctx::request_frame`, `@host.request_frame`, `@ui.request_frame`, `h_request_frame`: the app, and the framework's components, lists, scrolling, pages, overlays, nav, fx and motion too. The scheduler (`mbt.frame_core`): in mbui `src/ui/app.mbt` (the frame loop, the dispatch of inputs and events), `src/ui/ctx.mbt` (`request_frame`, `wake_*` themselves), `src/ui/hostcall.mbt`, `src/ui/hostread.mbt` (the host's bridge), `src/host`; in still.fail `src/host` | nothing: the framework frames inputs and events; an animation is data, declared once with its start and end |
| `settle` | `Tester::settle` / `settled`, `Ctx::settled`, `Runtime::settle` / `settled`, anywhere (tests, the Tester's own `tap`…, the driver), but in their own definitions | `run_for(<a declared time>)`, `finish(<that ticket>)`; `assert_idle()` at the end |
| `unsettled-ok` | a test that leaves out its end's idle check, `unsettled_ok=…` (`Tester::settle`'s, still.fail's `Flow::end`'s), counted where it is used, its why given there | the motion or the wake said, then its end run to and `assert_idle()` |
| `build-effect` | a view (a function given the `Ctx`) telling outside while it builds: a call to its core (`(src.call)(…)`, `build_effect.fields`), a host's effect (`@host.share`, `@ui.keep`…: `build_effect.calls`), a native view's own (`reload`, `set_scale`, `seek`, `close`…: `build_effect.methods`, by name), or an app's function doing one (found to a fixed point). Not in `Ctx::after_build`, a callback or handler (`fn(r) { … }`, `on_*=`, `take_back`, an answer), or under an input the frame takes (`clicked`, a widget's `button(c, …)`). A frame is built again while what it read changes: what a build let go of told outside is told all the same, and from the state it saw | `c.after_build(key, fn() { … })`: told once, as the frame's last build says it; where the value is the same in every build (the core's, the host's, a key), `det-ok(build-effect): why` |
| `flow-wait` | `wait N`, `linger N` in an end-to-end flow | `until`, and the named events (`answered`, `ready`, `decoded`) |
| `script-wait` | `sleep N`, `MBUI_SHOT_AT=N`, `setTimeout(…, N)`, `waitForTimeout(…)`, `time.sleep(…)` in test and screenshot scripts. At 0 in mbui | wait for the file, the log line (`scripts/logwait.py`; on a device `adb logcat -m 1 -e …`), the process's end, the event; a picture at a time its animations declare |
| `page-settle` | a script waits on a web page until the app is settled (`__mbhost.settled()`, `unsettled()`). Forbidden (at 0 in mbui and still.fail) | take the picture at a declared time (web/host.js `shot_at`: the run's own clock, `window.__shot`; Android's `--ei shot_at`, "SHOT n t" on the log); wait for the named thing (an input taken and drawn: the tape's INPUT and DRAWHASH lines, `?MBUI_DRAW_LOG=1`) |
| `frame-count` | a test's `for _ in 0..<N { … t.frame() … }` | the inputs, then `run_for` a declared time |
| `literal-time` | a bare number as a time: `run_for`, `wake_in`, `wake_after`, `wake_at`, `advance`, `frames_until`, `frame(ms=)` (`c.now() + 500.0` too; `0` is no time and passes) | a named length: `run_for(toast_life)`, `wake_at(at + hold_ms)` |
| `stable-mode` | the app reads `Ctx::stable()` (drawn otherwise when screenshotted) | the picture taken at a declared time, of the app as it runs |
| `retired-api` | `frames_until`, `animating`, `animating_until`, `run_animations`, defined or called, anywhere: given up (an animation is data, declared once with its start and end). `motion_end` run to (an argument of `run_for`, `advance`, `frame`, `wake_*`: `t.run_for(t.motion_end() - t.time())` is `run_animations` again) or read by the app; the framework keeps it, and its own tests may read it. Forbidden from the start (mbui's three runs to it, in `kit/controls_test.mbt`, `ui/motion_data_wbtest.mbt`, `ui/reader_test.mbt`, counted until they go) | motion's declared animations |
| `app-clock` (an exception may replace a finding) | the app reads the clock: `.now()`, `@ui.now()`, `@host.now()` (`(c.now() - at) / 180.0`, `at = c.now()`) | motion, `wake_at` from a declared length. Showing a time is right (`3 分钟前`: under a Tester the clock is the test's; its next change a `wake_at`): such a read is marked `det-ok(app-clock): shown as …`, in place of its finding |
| `wall-clock` | `Date.now`, `performance.now`, `Math.random`, `crypto.getRandomValues`… (also inside externs' JS), an unseeded `@random`, `wall_ms()` outside the host / core that provides them | the host's clock through `@ui`, a seed |
| `poll` | a frame or a wake asked for under a condition (if, while, match, an arm's guard, an else's if) that reads the host (`@host.*`), the layout or a host handle (`list_row_height`, `list_place`, `rect_of`, `made`, `grabbed`, `photos`, `pressed`…), or calls a function of the package that does | the host's answer, the layout's, as an event; a deadline while a finger is down is a deadline and passes |
| `host-read` | the app calls `@host.now / wake_after / platform / system_dark / window_inset / env` (still.fail #738) | `@ui`'s, which a Tester answers |
| `builtin-hash` | a value made from MoonBit's own hash: `x.hash()`, `Hash::hash(x)`, an `impl Hash for T` of one's own (seeded anew in each process, not the same on js and native: `"abc".hash()` was 979870683 in one process, 1111343748 in another); a `Map`'s own keys are not this | `@ui.stable_hash` / `stable_hash_bytes` (FNV-1a 64, the same everywhere) |
| `hash-order` | a `@hashmap` / `@hashset`: gone through, its order is its hash's, the process's | a `Map` (in the order put), or a sorted list |
| `globals` | a top-level `let` of a Ref, Map, Array or struct in `globals.roots` that its package's `reset` / `reset_globals` / what `on_reset` is given (and what they call) does not name, nor says `// kept across runs: why` over it (still.fail's check of `mbui-reader-rest`) | put it back in reset |
| `style-literal` | a number in a box's or words' look (`c.box(pad=12.0)`, `c.text(size=13.0)`, `c.row(gap=8.0)`), in `@ui.style(…)`, `patch`, `text_style`, `text_patch`, or an `Exact(…)` made outside the token files (`style.tokens` in detlint.json); not in tests | a token by name; an off-scale value named in the token file (docs/style.md) |
| `box-loose` | a call to `box`, `row`, `column`, `layer`, `text`, `rich` that says its look loosely (`pad=`, `bg=`, `size=`, `color=`…); not in tests | `style=` a named style |
| `style-exact` | every `Exact(…)` made (not the enums' declarations, nor a match's patterns), the token files' too; not in tests | a token on the theme's scale |

## How it reads MoonBit, and its limits

A lexer of its own (comments, strings and their `\{…}`, `#|` lines, chars, numbers: `0..<60` is a range), a call
being `NAME(…)` with what is before it (`x.`, `@pkg.`, `T::`) and its arguments split at the top level, top-level
items (a `test` block, a `fn T::f`), blocks and their headers. No types from the compiler: a receiver's type is
inferred where it is written (`self` in `fn T::…`; `x : T`; `let x = T::new(…)`; `let x = f(…)` with `f` declared
`-> T`), and a receiver it cannot tell is counted (over, not under).

Checked against the compiler (`moon ide find-references`, mbui main of 2026-10-20): `Tester::settle` 159 of 159,
`Tester::settled` 4 of 4, `Ctx::settled` 3 of 3, `Ctx::stable` 2 of 2, `Ctx::request_frame` 62 of 62, `Ctx::now` 27
of 27 (of those, 1, 4 and 7 through a receiver it could not type, counted as such); none that the compiler does not
find.

What it does not see:
- `poll` follows reads through the package's functions, not through state: `if update_busy() { c.request_frame() }`
  where `update_busy` reads a field another function filled from `@host.update_state()` is not a poll to it, nor a
  time polled every frame (`if waited(c, k) < later_ms { c.request_frame() }`). In the app both are still
  `frame-request`. Of the 17 polls the frame audit (2026-10-20) lists in still.fail's app, it finds 11.
- `app-clock` counts reads of the clock, not what is done with them: `(now - sent) / 60000.0` for "3 分钟前" and
  `(now - at) / 180.0` for an animation are the same expression. Decided: it counts them all, and a read that shows a
  time is marked, once, as the migration reaches it (an exception in place of a finding, so the bar only goes down).
- `Ctx::still()` is motion reduced alone (the person's setting: `Ctx::reduced_motion`), not `stable-mode`. Reading
  whether a run is stable (`Ctx::stable`, gone from mbui; an app's own flag for it) is `stable-mode` anywhere, the
  framework's code too: a screenshot's run draws and moves as any run.
- Hosts (Objective-C, C, Java, JS outside MoonBit externs) are not read.
- `script-wait` reads lines: a `sleep` in a heredoc counts, one in a comment line does not.
