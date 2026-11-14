# Working in the base (for agents)

The first of the base in MoonBit: what a client's core stands on where the core is MoonBit, written once and shared
(the user, 2026-11-14: still.fail's own core is to move to MoonBit, 「以后 still fail 也会切 mb」, and a module is
written once for both sides, 「这样两边共用」). A moon module of its own, `base`, which takes mbui's `effect` as a member
of its workspace (`moon.work`); `effect` stays in mbui.

## Its parts

- `src/shell`: the binding of the Rust shell (`client/shell`, through its C interface) for a program on `@effect`:
  a call that answers later as a fiber's wait, one that answers at once, a clock, random bytes. `shell.mbt` is the
  surface, the same over two shells, one a target (`moon.pkg`'s `targets`): `shell_native.mbt` with `shell.c`
  natively, `shell_js.mbt` in a page, which answers the same ops by their names with the same JSON from
  `client/iroh-wasm` and what a browser has.
- `src/wire`: what goes on a stream and how it is read, with no stream: lines, a request's head and a reply's, an
  event stream's text. Pure, with its tests.
- `src/mesh`: the device side of the mesh on those two: the endpoint and its key, a link to a peer (hello, pings,
  renewal), a request a stream, replies as they come, a link opened again. `mesh.mbt`'s head says what of the
  TypeScript mesh (`client/core-ts/src/mesh.ts`) it leaves out.

## It knows no program

- Not still.fail's app, station or cloud, and not the program it was written for first: an instant messenger outside
  this repository, which is all that uses it today. Nothing in this repository imports it yet. What a program needs
  of it the program gives: its protocol, its credential and what its hello says (`Options`, `Mesh::link`), where its
  shell keeps files, where its page serves iroh from (`Shell::start`), and what it links: the shell's static library
  and iroh's wasm are still.fail's by name, and no file here names either.
- `scripts/mb-base.ts` holds it (`scripts/check.sh`): what the packages import, in every import block of a
  `moon.pkg` (their own, `mbui/effect`, MoonBit's core), and that no line under `src/` says still.fail's name or a
  program's of it, nor, as a word of its own, what that messenger is about or is called (`member`, `conversation`,
  `im`; `token` is let be: a mesh may honestly call a credential one).
- What is there today and not this library's to rename is let be by name and by count in the script's `NAMED`: the
  shell's C interface (`sf_shell_start`…), three keys of the device base's words and one reason on the wire that say
  `station`, one path in a comment. The table only falls, and the script cannot hold that (it counts what is there,
  not what was): so the rule is this file's. A count is raised or an entry added only for a name that is another
  part's to change and that honest work here must say (one more function of the shell's C interface bound, a key
  the device base's words have), in the change that needs it, its entry saying what takes it away. For a name this
  library chooses, never; for anything else, the owner is asked first.
- The station's programs bind the shell themselves (`station/mb/src/host`: with their parent's lines on stdin and
  their own loop): two bindings for now. That one is left as it is until the station is moved onto this one, whole.

## What is checked here, and what is not

- On a commit and a push (the git hooks: `scripts/check.sh`'s quick part) and in CI (its `ts` part, check-linux),
  for a change here: `scripts/mb-base.ts`; and `scripts/mb-base-words.ts --check`, for a change to the device base's
  two files of words too: `src/mesh/words_made.mbt` is what they make, and every key `src/mesh` says (the first
  argument of `say`, `failed`, `under`, written out as a string) is one they have, since `say` gives a key with no
  words back as the key. And `scripts/mb-base-sse.ts --check`, for a change to `src/wire`, to the core's reader of
  an event stream in TypeScript (`client/core-ts/src/sse.ts`) or to the script: `src/wire/sse_made_test.mbt` is
  what that reader gives for the script's streams.
- In CI and a full check only, for a change here or to what it is built with of mbui (`effect`, and `halt`, which
  `effect` imports: `mb-base.ts` holds that list to `effect`'s `moon.pkg`): every package under `src/` type-checked
  for native and for js, and every package's tests run on both. Today only `src/wire` has tests.
- No Rust shell is linked there. A native test that reaches the shell's C (`shell.c`, through `src/shell` or
  `src/mesh`) fails to link, naming `sf_shell_start`: it is not skipped. Until the check has a shell to link, such a
  test is js's alone (`moon.pkg`'s `targets`) or stays out of what calls the shell; one that only reads constants
  or pure functions of `src/mesh` runs on both.
- So nothing here tests the mesh or either shell: no test in this repository opens a link, `shell.c` is compiled by
  no check, and the JavaScript in `shell_js.mbt` (`extern "js"`, written out in MoonBit) is read by no compiler at
  all. What holds them is outside: the messenger's end-to-end suites, a real server and relay, a page in a browser.
  A mesh's test on a simulated network, as the TypeScript one has, is not written yet. After a change to
  `src/mesh` or `src/shell`, say what ran it; a green check here says only that it still types.
- `src/mesh/words_made.mbt` is made, and committed: `node scripts/mb-base-words.ts` writes it from the device
  base's own words (`client/core-ts/src/lang.zh.json`, `lang.en.json`: the keys `core-logic.mesh.*`), so a word is
  changed there, never here.
- `src/wire/sse_made_test.mbt` is made, and committed, too: `node scripts/mb-base-sse.ts`. The core in TypeScript
  keeps its own reader of an event stream and is not switched to this one (the user, 2026-11-14: 「不切 TS core，只留
  读取器的修正」; the core moves to MoonBit a layer at a time), so the two are two that read alike, to the byte, and
  these cases are all that holds them so: what a reader gives for some bytes is changed in both, a stream is added
  in the script, never a case here.

## What a program on it gets with it

- Natively, starting the shell sets the process's umask to 077 for good (`shell.c` `bsh_start`): every file the
  program makes after it is its user's alone, its own too. It is there because the Rust shell writes a value it
  keeps (the device's key) as the umask leaves it (`client/shell/src/lib.rs`, `storage.set`); the mend is the
  shell's, and this goes then.
- `shell.c` is POSIX's (pthread, `arc4random_buf`): no MSVC, and on Linux glibc 2.36 or later. It has been compiled
  and run on macOS on arm64 alone.

## Known, to be mended next

Moved as they were written (2026-11-14), with these in them; each is mended here with the messenger's suites run on
it, and its line goes then. Read from the code, none of them run:

- A fiber waiting in `Mesh::link` (`mesh.mbt:185,231`), `Link::admitted` (`link.mbt:179`) or `Link::closed`
  (`link.mbt:322`) as another calls `Mesh::close` can wait for good: what it waits on is completed only by fibers
  of the mesh's scope (`mesh.mbt:211-229,349-371`), which the close interrupts (`mesh.mbt:483`).
- In a page a stream's handle goes only once it is reset, or read to its end and finished
  (`shell_js.mbt:107,116,120`): a link's control stream (`mesh.mbt:305-307`; `Link::close`, `link.mbt:327-329`,
  closes the connection alone) and a reply's stream after a read of it failed (`link.mbt:229-234`) stay for the
  page's life, with one entry a connection that ended and one an endpoint closed (`shell_js.mbt:82,92`). Natively
  the Rust shell lets a connection's streams go as it closes and keeps one entry a connection.
- A peer's bytes are kept without a bound: an event stream's text with no blank line (`src/wire/sse.mbt`,
  `Sse::append`, as the TypeScript reader; past 1 GiB held its doubling, `room * 2`, wraps, where that reader's
  does not), and `Reply::rest`, which also copies all it has for each piece that comes (`link.mbt:244-250`).
- An event's `data:` lines are joined by MoonBit's `join` (`src/wire/sse.mbt`, `event_of`), which on js makes the
  string again at each line: in an engine that copies it each time, an event of very many lines costs their number
  squared (Hermes, run in the review of #6100, 2026-11-14; no program runs this reader there).
- In a page a timer of the runtime's more than 2^31-1 ms away (24.8 days) is given to `setTimeout` as it is, which
  fires at once, and again (`shell_js.mbt:176-179,230-235`).

## Working here

- Never `moon check` or `moon info` the whole workspace: mbui is a member of it, and moon writes every member's
  `pkg.generated.mbti` beside its packages, mbui's too. By package, here: `moon check --target native
  src/mesh` (and `--target js`), `moon test --target native src/wire`. The three `pkg.generated.mbti` are committed,
  as mbui's are, and are native's (on js `shell` starts with the address of iroh and has no `pump` or `run`): a check
  by package of a changed surface writes its own again, to commit; the check passes `--no-mbti` and writes none.
- `wire` and `mesh` are one source for both targets, but for one thing: what an event stream's reader does to many
  bytes at once is a file a target (`src/wire/moon.pkg`'s `targets`: `sse_js.mbt`, `sse_native.mbt`; `sse.mbt`'s
  head says why), each small enough to read against the other, and the package's tests run both. Nothing else in
  them asks which it is built for: what differs is under `shell.mbt`'s surface, and an op the mesh comes to ask is
  answered by both shells, under the Rust shell's name and with its JSON.
- A fiber's wait on the shell given up is not the shell's call given up: of its calls only a dial is
  (`Shell::give_up`), in a page too. A read let go of goes on, holding the stream's receiving half, and what it
  takes is lost to the next read. So a stream is never read again after a read of it was interrupted: it is reset
  (`Reply::cancel`, `Link::ask`); and what must not be interrupted half way (an exchange on the control stream) is a
  fiber of the mesh's own scope that the others wait for with a `Deferred` (`Mesh::ping`).
- `catch` does not catch a fiber's interruption: what must be undone then is in a `defer`.
- The times and the bytes are the TypeScript mesh's (`mesh.mbt`'s constants; `src/wire/wire_test.mbt`, line for
  line), since the peer is the same door: a change to one is a change to what that peer is sent.
- A compiler warning is an error or off (`moon.mod`'s `warnings`, mbui's line).
