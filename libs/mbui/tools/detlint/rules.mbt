// The rules (RULES' words) and what finds each in a MoonBit file

///|
let rule_names : Array[String] = [
  "frame-request", "settle", "flow-wait", "script-wait", "page-settle", "device-shot",
  "host-import", "frame-wait", "at-rest-wait", "frame-count", "literal-time", "stable-mode",
  "retired-api", "app-clock", "wall-clock", "engine-math", "poll", "host-read", "builtin-hash",
  "hash-order", "globals", "style-literal", "box-loose", "style-exact", "style-text", "build-effect",
  "after-build-input", "unsettled-ok", "host-delay", "library-import", "reset-wire", "page-hand", "page-screen", "page-look", "follow-layout",
  "motion-read", "page-old-part", "page-old-sheet", "corners-each", "cursor-hand", "tier-outside-shell", "fixture-import",
  "motion-spring", "built-by-hand", "layout-read-back", "motion-length", "tester-branch", "frame-number", "ui-current",
  "build-clock", "build-motion", "old-list", "list-comes-off", "old-island", "old-panel",
  "click-read", "key-read", "part-place", "button-by-hand", "layout-told", "abort-unsaid", "empty-on-done", "panic-test", "read-before-run", "reset-by-hand",
  "app-word",
]

///|
let rule_words : Map[String, String] = {
  "app-word": "the code names an app built on it (detlint.json `app_words`: a word, a path of its): a framework knows no app; what an app needs of it is asked of the app, its own native calls (@hostapi.app_said, app_tell), a name it says (@hostapi.set_site_name), its config",
  "frame-request": "the app asks for a frame itself: the framework knows when one is due (an input, an event, an animation's deadline, a layout read)",
  "settle": "waits for, or asks whether, the app is settled: stability is an end-of-test assertion (assert_idle), never what a step waits for",
  "flow-wait": "an end-to-end flow waits a fixed time: wait for the named thing (until, answered, ready, decoded)",
  "script-wait": "a test or screenshot script waits a fixed time or frame count: wait for the event, or take the picture at a time the animations declare",
  "page-settle": "a script waits on a web page until the app is settled (__mbhost.settled): take it at a declared time, or wait for the named thing",
  "device-shot": "a script takes a picture of the app off a device, an emulator or a simulator: what it shows is compared in the Tester (its draw list at a declared moment), pixels by the hosts' offscreen render of that list; a device runs the host's contracts and a few smoke flows only",
  "host-import": "a package that is not an app's main imports mbui/host: ask the host through mbui/hostapi (a Tester answers it); the platforms' hosts are an app's main's alone, so a test links none",
  "frame-wait": "a fiber waits for the next frame: wait until the moment (an animation's declared end, a timer) or the event, not a frame: how many frames come is the display's",
  "at-rest-wait": "goes on until the app is at rest (settled by another name): at_rest is asserted (assert_true(t.at_rest())), never waited on, nor run on in a loop while something moves or is still to come; a step waits for its own named thing, an end runs a declared time and asserts idle, a picture is of a declared moment",
  "frame-count": "a test runs a fixed number of frames: give the inputs and run_for a declared time",
  "literal-time": "a time given as a bare number: name what it is (an animation's or a timer's declared length)",
  "stable-mode": "the app draws otherwise when it is screenshotted (Ctx::stable): the picture is taken at a time its animations declare, of the app as it runs",
  "retired-api": "an interface given up (an animation is data, declared once with its start and end): frames_until, animating, animating_until, run_animations; take_drop, files_held (a drop asked for each frame: Ctx::on_files is told it); motion_end run to, or read by the app",
  "app-clock": "the app reads the clock to work out an animation or a time passed: motion / wake_at do it from what they declared",
  "wall-clock": "the machine's own clock or randomness, outside the host that provides them",
  "engine-math": "a sine, an exponential, a power from @math: on js the engine's Math.*, whose last bits are the machine's; @dmath's (mbui/dmath) are the same on every machine",
  "poll": "a frame or a wake asked for under a condition that reads the host or the layout: that answer is an event",
  "host-read": "the app reads where it runs from @hostapi: through @ui, which a Tester answers",
  "builtin-hash": "a value made from MoonBit's own hash (seeded anew in each process, not the same on js and native): @ui.stable_hash",
  "hash-order": "a @hashmap / @hashset, its order the process's hash's: a Map (in the order put), or sort it",
  "globals": "a mutable global its package's reset does not put back, nor says `// kept across runs: why`",
  "page-hand": "a page reads the current input (@ui.pointing()): what it shows, where and how big is the native input's and the screen's (@sf.native_input(), the tier, its own width); how it answers the hand is the library's primitives' (c.lit, c.menu_asked, the app's own library's)",
  "page-screen": "a page reads the native input (@sf.native_input(): touch, or keyboard and mouse, as the app was started): what differs by it is the theme's, the library's parts', the presenters' and the shell's; a page that needs it asks the library for a part that holds it for every page",
  "tier-outside-shell": "a page reads the tier (@sf.layout) or the shell's own state (is_wide, the tape's, the stack's): what is laid out by the tier is the shell's (its files, detlint.json `shell.files`); a page is drawn into the box it is given, laid out by its own width, and what it needs of the frame it is given (PageFrame)",
  "frame-number": "what is built knows which frame or build it is (Ctx::frame_number, Ctx::build_number): what it is for is said by its cause, recorded where the cause is taken, or by the moment (Ctx::moment); a frame or a build counted is no cause, and the frames between two moments do not matter",
  "click-read": "what is built reads whether a press came (Ctx::clicked, clicked_on, double_clicked: true the frame after it) to do what the press does: that is done in the build, or told after the frame's builds, not at the press; say it as the press's handler (Ctx::on_press; a part's on_press, on_pick, on_change, on_submit: done as the press is let go, at its moment, outside any build). Counted so what is left only falls; the Bool goes from mbui's API once none is",
  "key-read": "what is built reads whether a key came (Ctx::key_pressed, keys_came, the app's action_pressed: true the frame after it) to do what the key does: say it as an action of a node (View::on_action, its keys the window's keymap's: View::keymap), done at the key's moment, or a node's own key (View::on_key). Counted so what is left only falls; the Bool goes from mbui's API once none is",
  "ui-current": "what is built reaches the frame's context from anywhere (@ui.current()): what is built gets its Ctx passed (an old view's build, a test's Tester), a node of the window's tree what its View gives (View::words_scale, pixel_scale, glass_solid, keyboard_inset, image_ready, cause_at, window; Field::focus, View::focus_let_go), an event's handler its event; never a global one",
  "build-clock": "the frames' clock read where it is followed (Ctx::now, now_before, now_of, cycle, shows_motion; ui's clock_read, clock_read_here, frame_clock): read as a frame is built, the frame's one watch is told by the clock and the whole frame is built again each frame while it is read (a spinner on a page: every frame of its turn). What moves by the clock is read where it is drawn, given its moment there (Ctx::cycle_look's phase; a look's, a move's closure, Ctx::look_by, moved_by); a stamp or a moment woken at is the moment (Ctx::moment, wake_in, every); what changes when a motion ends is said by that end, a moment declared. Counted where they are called, built or painted alike (a lexer cannot tell which: mbui's old parts read it as they paint too), and only fall",
  "old-panel": "a panel presented with what it holds drawn by the old immediate-mode view (@sf.panel's body and foot, Ctx's): what a panel holds is the window's tree's (@sf.panel_nodes: its body and foot made once as nodes, drawn by the tree on every screen); counted so the ones left only go, and the old body's path goes from the presenters once none is",
  "build-motion": "an animated value read as a frame is built (@motion.animate's value, Anim::get, Way::get, outside what a frame's paint is given): what is built from it is built again each frame it moves, the whole frame with it. Tell it as it is built (@motion.told, Anim::follow) and read it where it is drawn, given to a paint taker (Ctx::look_by, moved_by, bg_by, ink_by, notch_by, cut_across_by, glyphs_by, cycle_look); what is built while it comes or goes follows its declared end (Anim::over, ends). Counted where it is read, so the ones left (a size laid out by it, a colour or a shape no paint taker draws) only fall",
  "list-comes-off": "a page's list said at once (View::scrolls_window's at_once=true: its keys there and gone at once, what its blocks hold each its own way): what comes or goes by data down a column, and what a block holds, makes its way in the list's one way, the framework's (the owner's 方案 A, 2026-11-09); each list said so as its rows were given their way is switched on one at a time, before and after shown to the owner, so the ones left only go",
  "old-list": "a long list laid out by the old immediate-mode view (Ctx::list, the library's rows_list, desk_lanes, panel_list over it): a list is the window's tree's (a page made once, page_node; View::each in what scrolls, View::scrolls_window); counted so the ones left only go, and Ctx::list goes from mbui with its fast paths once none is",
  "old-island": "an old immediate-mode view hosted in a node of the window's tree (@ui.old: its Ctx built again as its frame is, inside a page made once): what is left of the old view where its part has no node yet (a code's boxes, a panel's body, a lock's gate), counted so the ones left only go, and @ui.old goes from mbui with Ctx once none is",
  "tester-branch": "what runs in the app asks whether a Tester runs it (its fake host, `fake.val`; a switch only a Tester sets, detlint.json `tester.names`): what differs under a Tester is its fake host's answer (@hostapi.Host, mbui's ui/fake_host.mbt) or what the Tester does itself after a frame (its own files, `tester.files`), never a path of the app's of its own",
  "fixture-import": "the app says the made-up core (detlint.json `fixture.package`: its fake topics, calls and data) outside the file that opens a mode over the app (`fixture.openers`) and outside its tests: the made-up core is the tests' and the tools' (sffix, sffilm, sflayout, sfreplay), never what a page reads",
  "page-look": "a page draws one arrangement's piece itself (narrow_*, desk_*, its own branch on Narrow or Wide): its parts are the library's (a page's parts, src/sf page.mbt), which the page's frame lays out by its width, the same page on every screen",
  "page-old-part": "a page takes a part from an older copy of it (@settings.button, pick_row, provider_mark, wide_head, quota_chips, meter_chip): the library has the one, after the web's (@sf.button, choice_row, provider_logo, page_head, quota_chips, meter_chip)",
  "page-old-sheet": "a page puts a sheet up in an older host of its own (the settings' open_sheet, a chat's): a menu, a pick, a panel, a confirm or a question is the library's presenters' (@sf.menu, @sf.pick, @sf.panel, @sf.confirm, @sf.ask), which show it as the screen and the native input have it (a sheet from the foot with touch short of Large; else beside what opened it, or a dialog)",
  "reset-wire": "a global its package's reset sets to something other than its `let`'s value: a wire (a hook given what does the work), which reset sets only as a Tester starts, never in the app; set it once in the package's `fn init`, and keep it across runs",
  "style-literal": "a number where a style is said (a box's or words' look, @ui.style…), or an Exact(…) outside the token files: name it with a token (mbui's ui/style.mbt)",
  "box-loose": "a box or words said by their loose look (pad=, bg=, size=…): say it as a named style (style=)",
  "style-exact": "a value off the theme's scale (Exact(…)), in a token file too: only goes down",
  "style-text": "a named style (a top-level let, a .then(…) of one) said as a call whose properties are all tokens and numbers: moonc makes each @ui.style(…) call ~5-10 KB of C run as the app starts; write it as its text, @ui.css(\"…\") (printed after `write:`). @ui.style(…) is for a style naming a variable or worked out, and inside functions (mbui's ui/style.mbt)",
  "build-effect": "a view tells outside while it builds (a core's call, a host's effect): a frame is built again while what it read changes, and a build let go of tells all the same; say what every build works out alike in Ctx::after_build (once the frame's builds are over, as the last says it), what an input took in Ctx::tell (once, whichever build took it), or in the event's own handler",
  "after-build-input": "what an input took (a click, a row or a switch used, a choice made) told by Ctx::after_build: that is the frame's last build's alone, and a build after the one that took the input sees it not, so a frame built again (a layout read back, what it read changed) loses it; do it in the input's handler (Ctx::on_press; a part's on_press, on_pick, on_change, on_submit: at the input's moment, outside any build)",
  "unsettled-ok": "a test leaves out its end's idle check (unsettled_ok=…: what still moves or asks, until it says its end): counted so the ones left only go",
  "library-import": "a package of the app's component library (detlint.json `library`) imports what is not the framework's nor said to be its own (the app's pages, its core, a station's, the cloud's): what it needs of the app, the app gives it as it starts (a function it sets: @sf.set_shortcuts)",
  "button-by-hand": "a part of the app's component library (detlint.json `library`) says it is a button itself (`@view.said(Button, …)`, with a press and a focus of its own) where mbui has the headless one (@headless.button): what a control is to the hand, the keyboard and a screen reader is its component's, the library's part a look over it (AGENTS.md, Components); counted so the ones left only go: a plain one moved over @headless.button, one that says pressed, expanded or selected over the component that carries that once it is made",
  "part-place": "a part of the app's component library (detlint.json `library`) made in the node it is given takes no place of its caller's (`#callsite(autofill(loc))`, `loc~ : SourceLoc`, its outside made as `box(made_for=loc, …)` or as a headless component's node, `@headless.button(made_for=loc, …)`): what a test finds in it is not traced back to the app's line that asked for it (view's source.mbt), only to the library's inside it",
  "follow-layout": "a motion follows what the layout measured (a node's size or place, the window's, the keyboard's): what changed it is not its cause; tell the motion at its cause, with what it moves for (@motion.layout's `by`), and what its container does to it is no motion of its own (the app's sf/motion.mbt)",
  "built-by-hand": "the app says by hand that what was built is to be built again (Ctx::forget_parts, built_from_changed): what changed is a signal (same= by its value), read where it is used, and what read it is built again by itself, nothing else; a kept build that differs from one built whole is a read not followed, made followed, never covered by building more",
  "layout-read-back": "the app reads back where or how large something was laid out (Ctx::rect_of, laid_size, laid_rect) for what it builds: the first frame has none and draws it wrong, a change lays the frame out again; say it as layout (a box's own rules, by the width it is given, Ctx::place_by_size, cover), a press by what took it (c.hovered, press_within); a flight's ends by @motion.measure",
  "layout-told": "what is made reads back what the layout came to, told as a change once all is laid out (View::laid_size_told, went_told, pointer_here_told): it is made again by it and laid out again, the layout's result flowing back into what this layout made; make it by the room it is given as that layout comes to it (View::by_room: Room::width, Room::tall), say it as layout (min_width/max_width `within`), or as the framework's own (a scroll's reach, a beside's side); counted, so those left only go. What a page's list has in sight, told to handlers (ListPlace::on_sight, ListPlace::sight_now) at the moments the hand is found again, for the accounts they keep and tell the core of, is let through by name: never read as a frame is built, nor bound to what is made",
  "motion-spring": "the app makes a spring of its own (@motion.spring, motion_spring, Ctx::spring): a spring is one of @motion's (move_spring, sheet_spring, lift_spring), as a timed motion's curve is one of @ui.Ease's (the app's sf/motion.mbt, Curves)",
  "motion-length": "a move given a length of its own (a tween on Move): a thing moved takes as long as its way is far, from where it is as it is told (@motion.moved, @ui.move_ms; the app's sf/motion.mbt, Curves: the user, 2026-10-30, 「有些动效不应该固定播放时间，因为它的距离是不固定的」)",
  "motion-read": "the app reads whether a motion runs (moving()): what is shown, what takes a press, when state is let go follow from the cause and the motion's declared end (ends()); what only draws by it says so on its line (det-ok)",
  "corners-each": "a box's corners said not all alike (Corners, LinkedEach): only a design's, each looked at and kept, never what came by the way (the user, 2026-10-26: 每个四边圆角不一致的都应该手动确认是否 by design); say why where it is said and list it in the app's sf/align.mbt (四角不一致的), then raise its count: mbui itself never works corners out unlike each other",
  "cursor-hand": "the pointer's hand said over something (Ctx::cursor(…, Hand)): what takes presses shows it by itself (its click read: Ctx::clicked, a part's Response; its press taken without it said, Ctx::takes_presses: a slider), and nothing else does; what takes presses as a ground (a stage, the room round a list's rows) says Arrow",
  "abort-unsaid": "an abort of its own (abort(…)): on wasm-gc, where the tests run off CI, it prints nothing of its words, the test only `failed: Error` with no place; stop with @halt.saying(…) (mbui/halt), which prints the words and the line that said them first",
  "empty-on-done": "an empty on_done (or a source's call's `done`, `fn(_) {  }`): to the core it reads the answer, awaited and the frame after it built whole for nothing; a call whose answer nobody reads gives none (@core.call with no on_done), or the app's answer_unread for a source's call; a native call's empty on_got the same (give none)",
  "panic-test": "a test that passes by stopping its program (`test \"panic …\"`): stopped in the middle of what it asked (a change, a layout, a frame), it leaves the process there, and on wasm-gc the tests after it in the same program run on from it (view's shared_test's left the signals' batch open: 185 of view's 435 failed after it, 2026-11-11). Ask it as an app's run on a host does, its fault told and not stopping the run (`@view.faults_stop` false, `@view.fault_told` given: view's boundary_test faults_kept), and assert the words it said (a check that stops: the step saying what is wrong asserted, ui css_read, Tester::idle_said, flex reuse_refused); none is left",
  "read-before-run": "a test reads the app's words or language (detlint.json `run_first.reads`: @sf.t, tr) before it starts its own run of the app (`run_first.starts`: new_run, fresh_app; Tester::new, or a function that starts one first): what it reads then is the app as the test before it in the process left it. gate_wbtest's last test leaves the core's prefs saying English; landing_node_wbtest's first, reading its titles' words before its new_run, looked for English ones in the Chinese its run drew, and failed only where the two files ran in one process, which CI's grouping changes with the rate and the files' seconds (#5433, 2026-11-11). Start the run first, then read what it shows",
  "reset-by-hand": "a test puts the app back by hand (new_run) and makes no Tester after it: the app's reset is then left marked as done for a Tester to come (sfapp's reset_by_hand), and that Tester is the next test's, which starts from the app as this one left it, not as at the start (2026-11-11); a test that makes no Tester puts it back with fresh_app(), which leaves nothing marked",
  "host-delay": "a host does something a fixed time later (postDelayed, dispatch_after, SetTimer, setTimeout): do it on the event it waits for (a callback, a listener, the system's word); a time the app asked for (its wake) says so on its line (det-ok)",
}

///|
/// what the app may not call to have what was built built again (built-by-hand)
let built_by_hand : Array[String] = ["forget_parts", "built_from_changed"]

///|
/// a Ctx's reads of where or how large a node was laid out (layout-read-back)
let layout_read_back : Array[String] = ["rect_of", "laid_size", "laid_rect"]

///|
/// what the layout came to, told back as a change to make things by (layout-told)
let layout_told : Array[String] = ["laid_size_told", "went_told", "pointer_here_told"]

///|
/// what a page's list has in sight, told to handlers at the hand's moments (list_sight.mbt): let through layout-told by
/// name, read by a handler for its accounts, never by what is made
let layout_told_handlers : Array[String] = ["on_sight", "sight_now"]

///|
/// what @math works out by the engine on js (implementation-approximated in ECMAScript): @dmath's in their place
let engine_math : Array[String] = [
  "sin", "cos", "tan", "asin", "acos", "atan", "atan2", "exp", "expm1", "ln", "ln_1p",
  "log2", "log10", "pow", "sinh", "cosh", "tanh", "asinh", "acosh", "atanh", "cbrt",
  "hypot",
]

///|
let frame_ask : Array[String] = [
  "request_frame", "wake_in", "wake_after", "wake_at", "wake_at_time", "frames_until",
]

///|
let retired : Array[String] = [
  "frames_until", "animating", "animating_until", "run_animations", "take_drop", "files_held",
]

///|
/// kept inside the framework, given up for tests and apps: run_for(motion_end() - time()) is run_animations again
let retired_outside : Array[String] = ["motion_end"]

///|
let settle_names : Array[String] = ["settle", "settled"]

///|
/// a target's place waited on until it holds still from frame to frame: settling by another name
let hold_still : Array[String] = [
  "held_still", "holds_still", "hold_still", "steady", "still_at",
]

///|
/// what still moves or is still to come, read in a loop that runs the clock on: settling by another name
let move_reads : Array[String] = [
  "rest_of", "moving", "moving_now", "next_wake", "motion_end", "rest_why", "list_moving",
]

///|
let clock_runs : Array[String] = [
  "run_for", "run_to", "run_to_rest", "frame", "frame_at", "draw", "draw_owed", "advance",
]

///|
/// what may hold at_rest(): an assertion's arguments (a test's end), nothing that goes on until it is
let asserts : Array[String] = [
  "assert_true", "assert_false", "assert_eq", "assert_not_eq", "inspect", "debug_inspect",
]

///|
let settle_types : Array[String] = ["Tester", "Ctx", "Runtime"]

///|
let settle_defs : Array[String] = [
  "settle", "settled", "unsettled", "stable", "assert_idle",
]

///|
let time_fns : Array[String] = [
  "run_for", "wake_in", "wake_after", "wake_at", "advance", "frames_until", "wake_at_time",
]

///|
let host_reads : Array[String] = [
  "now", "wake_after", "platform", "system_dark", "window_inset", "env",
]

///|
let query_default : Array[String] = [
  "pressed", "list_row_height", "list_place", "rect_of", "row_height", "image_info", "view_info",
  "view_site_state", "update_state", "shared_in", "made", "grabbed", "photos", "kept", "files",
]

///|
fn rx(p : String) -> @re.Regex {
  @re.Regex::new(p) catch {
    _ => panic()
  }
}

///|
let wall_words : @re.Regex = rx(
  "\\b(Date\\.now|performance\\.now|Math\\.random|crypto\\.getRandomValues|clock_gettime|gettimeofday|mach_absolute_time|CFAbsoluteTimeGetCurrent|arc4random|crypto\\.randomUUID|randomUUID|NSUUID|uuid_generate|SecRandomCopyBytes|getrandom|BCryptGenRandom|SecureRandom|rand|srand|random)\\b(?=\\s*\\()|\\b(Date\\.now|performance\\.now|Math\\.random|NSUUID|SecureRandom|randomUUID)\\b|/dev/u?random",
)

///|
/// the time of day read as a source's `now`, the one place it may be (@ui.wall_ms)
let wall_as_now : @re.Regex = rx(
  "\\bnow\\s*:\\s*fn\\s*\\(\\s*\\)\\s*\\{\\s*@ui\\.wall_ms\\(\\s*\\)\\s*\\}",
)

///|
/// a function that makes a random id when called with nothing
let random_ids : Array[String] = [
  "uuid", "uuid4", "uuid_v4", "new_uuid", "random_uuid", "random_id", "rand_id", "random_hex",
  "random_string", "random_bytes",
]

///|
let plain_types : Array[String] = [
  "Int", "Int64", "UInt", "UInt64", "Int16", "UInt16", "Double", "Float", "String", "Bool",
  "Char", "Byte", "Bytes", "Json", "Unit",
]

///|
let host_import : @re.Regex = rx("\"mbui/host\"")

///|
let build_effect_calls : Array[String] = [
  "@hostapi.share", "@hostapi.open_url", "@hostapi.notice_show", "@hostapi.set_sideways",
  "@hostapi.set_turnable",
  "@hostapi.set_dark", "@hostapi.update_fetch", "@hostapi.update_apply", "@hostapi.push_token", "@hostapi.gallery_ask",
  "@hostapi.exit", "@hostapi.keep", "@hostapi.save_file", "@hostapi.clipboard_set", "@ui.share",
  "@ui.open_url", "@ui.notice_show", "@ui.notice_ask", "@ui.notice_settings", "@hostapi.notice_settings", "@ui.keep", "@ui.keep_bytes", "@ui.clipboard_set",
  "@ui.save_file", "@ui.pick", "@ui.set_sideways", "@ui.exit", "@ui.clipboard_set_png", "@ui.clipboard_read",
  "@ui.keep_awake", "@ui.haptic", "@hostapi.clip_set_text", "@hostapi.clip_set_png", "@hostapi.clip_read",
  "@hostapi.keep_awake", "@hostapi.haptic", "@ui.native_call", "@hostapi.native_call",
]

///|
let build_effect_methods : Array[String] = [
  "go_back", "go_forward", "reload", "load", "set_scale", "close", "play", "pause", "seek",
  "rate", "grab_frame",
]

///|
/// a closure given to one of these runs later than the build: a fiber, a timer, a host's answer, a page's leaving
let later_calls : Array[String] = [
  "fork", "effect", "spawn", "after", "later", "video", "site", "subscribe", "each_later",
  "watch", "take_back",
]

///|
/// the Ctx's own handlers: what is given to one runs as its input comes, not as the frame builds
let handler_methods : Array[String] = ["on_press", "follow_press", "on_key"]

///|
let later_labels : Array[String] = [
  "done", "answer", "then", "leave", "serve", "read", "back", "cancel", "fail", "ok", "shown",
  "broken",
]

///|
/// called with the Ctx in a condition, not a widget's use: a time, a hold, a layout's read
let not_input_calls : Array[String] = [
  "after", "held", "within", "mark", "list_info", "rect_of", "words_of", "is_wide", "presence",
  "animate", "theme", "window_size", "list_place",
]

///|
/// a widget whose answer is what the finger or the keys chose this frame
let input_value_calls : Array[String] = [
  "segmented", "code_field", "toggle", "switch", "slider", "stepper",
]

///|
let input_words : Array[String] = [
  "clicked", "tapped", "take_end", "take_tap", "take_key", "key_pressed", "chosen", "dismissed",
  "acted", "submitted", "right_clicked", "shortcut", "take_move", "pasted", "took",
]

///|
let exc_re : @re.Regex = rx("det-ok\\(([a-z-]+(?:\\s*,\\s*[a-z-]+)*)\\)\\s*:?\\s*(.*)")

///|
priv struct Finding {
  rule : String
  file : String
  line : Int
  mut what : String
  mut excused : String? // its det-ok's reason
}

///|
fn finding(rule : String, file : String, line : Int, what : String) -> Finding {
  { rule, file, line, what, excused: None }
}

///|
fn under(rel : String, prefixes : Array[String]) -> Bool {
  prefixes.iter().any(fn(p) {
    let q = if p.has_suffix("/") {
      p.exact_view(end=p.length() - 1).to_owned()
    } else {
      p
    }
    rel == p || rel.has_prefix(q + "/")
  })
}

///|
fn matches(rel : String, globs : Array[String]) -> Bool {
  globs.iter().any(fn(g) { @sys.fnmatch(rel, g) })
}
