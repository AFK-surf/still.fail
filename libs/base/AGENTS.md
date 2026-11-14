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
- `src/js`: the base as JavaScript calls it, and `js/`, what `build.sh` builds of it (below, Built for JavaScript).
- `src/mesh`: the device side of the mesh on those two: the endpoint and its key, a link to a peer (hello, pings,
  renewal), a request a stream, replies as they come, a link opened again. `mesh.mbt`'s head says what of the
  TypeScript mesh (`client/core-ts/src/mesh.ts`) it leaves out.

## It knows no program

- Not still.fail's app, station or cloud, and not the program it was written for first: an instant messenger outside
  this repository. As MoonBit nothing in this repository imports it yet; the core in TypeScript takes one part of it
  built for JavaScript (below), which is of no program either. What a program needs
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
  words back as the key.
- In CI and a full check only, for a change here or to what it is built with of mbui (`effect`, and `halt`, which
  `effect` imports: `mb-base.ts` holds that list to `effect`'s `moon.pkg`): every package under `src/` type-checked
  for native and for js, and every package's tests run on both. Today only `src/wire` has tests. And, for a change
  here alone, `js/` held to what the source builds to (`build.sh --check`).
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

## Built for JavaScript

- A part of the base written once here is taken by a core in TypeScript as it is built for JavaScript (the user,
  2026-11-14: 「固定下来做成 mb 的…这样两边共用」): `build.sh` builds the package `src/js` and what it reaches to
  `js/base.js`, with the types moon writes for it (`js/base.d.ts`, `js/moonbit.d.ts`), committed as the rules' is
  (`rules/build.sh`), so that nothing which takes it needs MoonBit. A change to `src/` runs `sh libs/base/build.sh`
  and commits what it made; never edited by hand. It is its own artefact, apart from the rules': each carries its
  own copy of what it uses of MoonBit's core (of `base.js`'s 9.4 KB minified, 4.0 KB is in `rules.js` too). One
  build of both would carry it once, and moon can make one (a package of a third module importing both), which
  this library, knowing no program, cannot be.
- The first part so taken is the reader of an event stream (`src/wire/sse.mbt`; `client/core-ts/src/sse.ts` is all
  that is left of the one in TypeScript, and that core's check lets a base file of its own import `js/base.js`:
  `client/core-ts/scripts/base.ts`, `MADE`). It reads as that one read, to the byte: a change to what it gives for
  some bytes is a change to still.fail's core on every platform, and is held by that core's tests
  (`client/core-ts/test/sse.test.ts`) as by `wire_test.mbt`.
- What crosses to JavaScript is what both sides hold the same way, so nothing is converted at a call: `Bytes` is a
  `Uint8Array`, `String` a string, `FixedArray` an array (never `Array`, an object of MoonBit's own there; nor a
  struct or an enum, whose fields moon names as it likes), `T?` of those the value or `undefined`. A value of the
  base's own is handed back as it was got and never read there. Bytes given are read during the call and not kept
  (their caller writes them again).
- A function of `src/js` never says `raise`: built for JavaScript one that does throws nothing, and gives back an
  object its caller would have to look into. What cannot go on is an `abort` with words: it reaches the caller as an
  `Error` with those words. One with none (an index out of bounds, an `unwrap` of nothing) is an `Error` whose
  message is empty, told apart only by its stack, where moon's names say the package and the function
  (`_M0MP24base4wire3Sse6append`) and no line of a `.mbt` file. An integer divided by zero is 0 there, with no
  error.
- MoonBit's core reads UTF-8 on js with the engine's `TextDecoder`, two of them made as `base.js` is loaded: where
  the engine has none (Hermes 0.81), the program's own must be there before this is loaded (still.fail's core:
  `client/core-ts/src/hosts/hermes-globals.ts`, which its entry imports first).

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
  `Sse::append`, as the reader in TypeScript before it), and `Reply::rest`, which also copies all it has for each piece that comes
  (`link.mbt:244-250`).
- In a page a timer of the runtime's more than 2^31-1 ms away (24.8 days) is given to `setTimeout` as it is, which
  fires at once, and again (`shell_js.mbt:176-179,230-235`).

## Working here

- Never `moon check` or `moon info` the whole workspace: mbui is a member of it, and moon writes every member's
  `pkg.generated.mbti` beside its packages, mbui's too. By package, here: `moon check --target native
  src/mesh` (and `--target js`), `moon test --target native src/wire`. The three `pkg.generated.mbti` are committed,
  as mbui's are, and are native's (on js `shell` starts with the address of iroh and has no `pump` or `run`): a check
  by package of a changed surface writes its own again, to commit; the check passes `--no-mbti` and writes none.
- `wire` and `mesh` are one source for both targets: nothing in them asks which it is built for. What differs is
  under `shell.mbt`'s surface, and an op the mesh comes to ask is answered by both shells, under the Rust shell's
  name and with its JSON; and, in `wire`, the three things an event stream's reader does to many bytes at once
  (`sse_js.mbt`: a typed array's `set`, `copyWithin`, `indexOf`; `sse_native.mbt`: MoonBit's own loops), since
  MoonBit's loop a byte is 2.3 to 2.6 times slower in Hermes, which compiles nothing (measured, 2026-11-14). A
  part that goes through many bytes or characters on js asks the engine for it so, in a file of its target, small
  enough to read against the other; the package's tests run both.
- A fiber's wait on the shell given up is not the shell's call given up: of its calls only a dial is
  (`Shell::give_up`), in a page too. A read let go of goes on, holding the stream's receiving half, and what it
  takes is lost to the next read. So a stream is never read again after a read of it was interrupted: it is reset
  (`Reply::cancel`, `Link::ask`); and what must not be interrupted half way (an exchange on the control stream) is a
  fiber of the mesh's own scope that the others wait for with a `Deferred` (`Mesh::ping`).
- `catch` does not catch a fiber's interruption: what must be undone then is in a `defer`.
- The times and the bytes are the TypeScript mesh's (`mesh.mbt`'s constants; `src/wire/wire_test.mbt`, line for
  line), since the peer is the same door: a change to one is a change to what that peer is sent.
- A compiler warning is an error or off (`moon.mod`'s `warnings`, mbui's line).
