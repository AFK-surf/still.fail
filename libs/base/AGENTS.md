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
  `client/iroh-wasm` and what a browser has. And one that is no target's, a test's (`Shell::stood_in`): its calls are
  given to the test, which answers them.
- `src/wire`: what goes on a stream and how it is read, with no stream: lines, a request's head and a reply's, an
  event stream's text. Pure, with its tests.
- `src/mesh`: the device side of the mesh on those two: the endpoint and its key, a link to a peer (hello, pings,
  renewal), one for each scope its program names there, a request a stream (its head with what its kind says, its
  body whole or a step at a time and told of, its reply whole or as it comes, or the stream open both ways after
  its head), the streams its peer opens, a link opened
  again, let go of by its program, its holder told as another takes its place; its pings measured, how its place
  is by them told as it changes, and a link that stops answering raced against a new one (`health.mbt`); what its
  program's word that its connections are suspect does, and the endpoint bound anew where stuck (`wake.mbt`); what
  the endpoint is bound with beside its relays, the relays told again, and a connection a peer dials to it, which
  is never a link (`bind.mbt`).
  `mesh.mbt`'s head says what of the TypeScript mesh (`client/core-ts/src/mesh.ts`) it leaves out.

## It knows no program

- Not still.fail's app, station or cloud, and not the program it was written for first: an instant messenger
  outside this repository, which is all that uses it today. Nothing in this repository imports it yet. What a
  program needs of it the program gives: its protocol, its credential and what its hello says (`Options`,
  `Mesh::link`), what it tells its links to one peer apart by (`Mesh::link`'s `scope`: a string of the program's
  own, which the base never reads; a program with one scope says none), what a peer is told a link was let go for
  (`Mesh::drop_link`'s `reason`), what its endpoint is bound with beside its relays (`Binding`: whether peers are
  looked up, the protocols it takes connections on, which entry leads to which of its relays, worked out by the
  program), where its shell keeps files, where its page serves iroh from (`Shell::start`),
  and what it links: the shell's static library and iroh's wasm are still.fail's by name, and no file here names
  either.
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
  for native and for js, and every package's tests run on both: `src/wire`'s, `src/mesh`'s, and on js `src/shell`'s.
- No Rust shell is linked there. A native test that reaches the shell's C (`shell.c`: through `Shell::start`, or
  the package's `random` and `now`) fails to link, naming `sf_shell_start`: it is not skipped. So a test of what
  stands on the shell is given a stood-in one (`Shell::stood_in`), which reaches none of it and runs on both
  targets: the mesh's are (`src/mesh/stood_wbtest.mbt` is the peer they share, and its head says how a test uses
  it: it answers what the mesh asks of iroh by the shells' names and JSON, and either holds back a dial, a read and
  a connection's end for the test to answer by hand, or is a peer that answers by itself as the test scripts it:
  the hello, the control stream's exchanges, a request, a connection's end, each at once, some time later on the
  test's clock, never, or when the test gives it), on a runtime of the test's own clock. What depends on which of
  two fibers comes first in one turn is set up without running and then run at once (its `start`, `answered`,
  `run`): a test that runs to rest after every step never sees a fiber cut before its first. A test of the page's
  shell itself is js's alone (`moon.pkg`'s `targets`: `shell_js_wbtest.mbt`, the page's timers in its hands).
- That is all that is tested here of the mesh and the shells: what the mesh asks of a shell and does with its
  answers (as it is closed, what it lets go of, how much of a reply it keeps: `src/mesh/mesh_wbtest.mbt`; a link's
  life against the scripted peer, at the TypeScript mesh's times: its hello and each refusal of it, its pings and
  three of them missed, its credential's renewal and a refusal of one, its end by the peer, its peer dialled again:
  `src/mesh/peer_wbtest.mbt`; links by scope and peer on that peer: one peer in two scopes, the link there is now,
  one let go of by its program, its holder told as it is replaced, and what each looks at again after it waited:
  `src/mesh/scope_wbtest.mbt`; its pings' round trips against numbers worked out by hand, how a place is and each
  change of it told once, and the race of a link suspect: won by the new link, by the old one's answer, by
  neither, by what came on the old one meanwhile, its probe never sent or answered late, two scopes at once, a
  link its peer ended while its ping was out (not raced, not dialled for), and the place let go of or the mesh
  closed at each of forty turns from the ping missed on and at each of twelve from the answer of the race's dial
  on: `src/mesh/health_wbtest.mbt`; what a link carries
  beside the one whole request, and how each fails: a head with further fields, a body in steps, a reply read a
  piece a call, a duplex, the streams the peer opens, the peer stopping a stream, a head too long, a wait given
  up, the link let go of, ended or the mesh closed under them: `src/mesh/requests_wbtest.mbt`; a wake: the shell
  told, the links it races and those it does not, an opening's second dial winning, losing, both failing, both
  answered at once, the place let go of or the mesh closed at each turn; and the endpoint bound anew: when it is
  taken for stuck, never while anything is on it nor twice in 5 s; nothing dialled on one found stuck with no
  connection open, which is bound as what is under way ends, two places asked for in turn for ten minutes;
  whoever waits to dial told as its place is let go of, as the mesh closes, as an opening, a link's answer or a
  race leaves the endpoint; three askers of one place and one dial; the mesh closed at each of its waits, and
  what of the shell's answers it waits for: `src/mesh/wake_wbtest.mbt`; what an endpoint is bound with, said or
  not; its relays told again: the same, their entries alone (one telling at a time, a refusal of ones told
  over), others with nothing on the endpoint, with links and a connection taken on it, with a link that waits to
  dial, while the shell binds, a bind that fails, the mesh closed meanwhile; and a connection a peer dials:
  handed to one asker, its first line held to a time and a length, an asker gone, the endpoint bound anew with
  the wait out or as one comes, in either order, the mesh closed at each turn: `src/mesh/bind_wbtest.mbt`), and
  how the page's shell turns its runtime. The peer has no network under it: when it answers is the test's to say,
  a connection is lost by the test saying so, and what the transport counted (`conn.stats`), whether the
  endpoint is on a relay, and a peer dialling the endpoint (the answer to `iroh.accept`) are the test's words
  too. That peer is the test's script, not a
  door: no test in this repository opens a link to a real peer; `shell.c` is compiled by the native step (moon
  makes a package's stub with its tests, into an archive nothing there calls) and run by none; and the rest of the
  JavaScript in `shell_js.mbt` (`extern "js"`, written out in MoonBit: what it does with iroh and its handles) is
  read by no compiler and run by no test here. What holds those is outside: the messenger's end-to-end suites, a
  real server and relay, a page in a browser (which reads the page's handles from outside). Two meshes on a
  simulated network, as the TypeScript one has, are not written yet. After a change to `src/shell`, or to what
  `src/mesh` asks of a shell, say what ran it there.
- `src/mesh/words_made.mbt` is made, and committed: `node scripts/mb-base-words.ts` writes it from the device
  base's own words (`client/core-ts/src/lang.zh.json`, `lang.en.json`: the keys `core-logic.mesh.*`), so a word is
  changed there, never here.
- `src/wire/sse_made_test.mbt` is made, and committed, too: `node scripts/mb-base-sse.ts`. The core in TypeScript
  keeps its own reader of an event stream and is not switched to this one (the user, 2026-11-14: 「不切 TS core，只留
  读取器的修正」; the core moves to MoonBit a layer at a time), so the two are two that read alike, to the byte, and
  these cases are all that holds them so: what a reader gives for some bytes is changed in both, a stream is added
  in the script, never a case here.

## What a program on it gets with it

- Natively, what the shell keeps (the device's key) is a file of its user's alone whatever the process's umask: the
  Rust shell makes it so as it writes one (`client/shell/src/lib.rs`, `create_private`), for every program linked
  to it. The umask is the program's and is not touched; the directory the shell is started with is its user's
  alone where it was not there (`shell.c` `bsh_start`). A value kept before that stays as it was made until it is
  written again: nothing goes through what is there. And it is the shell's doing alone: a program linked to a
  shell from before it keeps its key as its umask has it, and nothing at run time says which shell is linked (its
  build's key does: `scripts/native.ts`).
- A peer's bytes are kept up to a bound, the caller's to say: a reply read whole (`Reply::rest`, `max_body`) and
  one block of an event stream (`Sse::new`, `max_event`), 16 MiB each unless said, past which each fails
  (`too_long`, `TooLong`) and is let go of. What is longer is read as it comes (`Reply::take`, a duplex's reply,
  `Inbound::take`), and that has no bound of bytes because it keeps none: a call is one read of the shell's (64 KiB
  at most natively), nothing is read of the peer before it is asked for, and a reader that stops asking holds its
  peer back by the transport's own window. What goes out waits the same way: a write ends once the stream took it,
  and a body told of (`Link::request`'s `wrote`) has one step of 64 KiB waiting at most.
- A connection a peer dials to the endpoint (`Mesh::incoming`, only on an endpoint bound to take a protocol:
  `Binding.takes`) is the one thing here that a peer nobody knows starts, and is never a link: nothing of `links`,
  `current`, the pings or a credential knows it. What is kept for such a peer: by the mesh, one connection the
  shell brought that no asker took yet, and each one taken (its handle, its place in `incomings`) until its end is
  told, the endpoint is bound on other relays (`Mesh::retune`) or the mesh closes; of what it sends, `most` bytes
  and one read of the shell's while its first line is waited for (`Incoming::first`: 64 KiB unless said), and it
  has 30 s (`first_ms`, unless said) from that being asked to open its first stream and end that line, or is
  closed. After that line the stream is its program's, read a piece a call as any (`Inbound`). Not bounded here,
  and its program's to bound: how long a connection taken stays (one never asked its first line, or kept after
  it: `Incoming::close`; while one is there an endpoint taken for stuck is not bound anew), and how many it holds
  at once. And the shell's: see "Known, and left".
- `shell.c` is POSIX's (pthread, `arc4random_buf`): no MSVC, and on Linux glibc 2.36 or later. It has been compiled
  and run on macOS on arm64 alone.

## Known, and left

What was known as the library was moved here (2026-11-14) is mended, each with a test that failed before; what is
left is another part's:

- Natively the Rust shell keeps one entry for every connection that ended and every endpoint closed, for its
  process's life (`client/shell/src/lib.rs`: `Handle::Gone`, `Handle::Unbound`), and has no op that lets one go. The
  mesh says when it is done with a connection (`conn.close` with `forget`, `Mesh::open`), which a page's shell goes
  by; the Rust shell reads no such field. Letting them go there is that shell's to do, for the device base in
  TypeScript too, which holds them the same. An endpoint bound anew (`Mesh::rebind`) leaves one such entry each
  time, and that is no rare time: every dial that runs out of time unconnected leaves the endpoint taken for
  stuck, so a peer that does not answer, asked for again and again, binds it anew at each try (5 s apart at the
  soonest), as in the device base in TypeScript. The same each time its relays are told again as others
  (`Mesh::retune`).
- Natively the Rust shell takes every connection dialled to an endpoint that takes a protocol, from the first
  time one is asked for (`iroh.accept`): each handshake is done by itself, and those nobody asked for yet wait in
  a queue with no bound (`client/shell/src/lib.rs`, `Accepted`). The mesh asks for one at a time, the next only
  as its program asks (`Mesh::incoming`), so a program that stops asking leaves what peers dial open there until
  the endpoint closes. The device base in TypeScript takes each as it comes and hands it to its program at once,
  which bounds nothing either. That shell's to bound.
- A write given up lets go of its stream: that is the mesh's intent (`Out::write` resets it), and both shells' only
  once that write moves. `istream.write` holds the sending half while it writes, and `istream.reset` waits for it
  (`client/shell/src/lib.rs`, `client/iroh-wasm/src/lib.rs`): given up because the peer is not reading, the write
  stays, and the reset behind it, until the peer reads, stops the stream or the connection ends. The Rust shell's
  and iroh-wasm's to mend, for the device base in TypeScript too.
- A read that waits as its connection ends can be answered the stream's end by the Rust shell, not a failure (it
  wakes the read as it lets go of the connection's streams). The mesh is told an end and has no length of its own
  to hold a body to, so a reply cut so passes for whole (`requests_wbtest.mbt` scripts it): what a reply's head
  says of its length is its program's to hold it to, until that shell answers a failure there. As in the device
  base in TypeScript.
- On js under Hermes, MoonBit's own `Array` costs the square of its length as it grows: a full one is copied into a
  `new Array(n)` from its last place down, which that engine takes badly (40,000 pushes 0.6 s, 80,000 2.7 s, where
  the engine's own `push` takes 3 and 6 ms; the hermes of React Native 0.81.4, 2026-11-14), and its `StringBuilder`
  and `join` make their string again at each piece. The reader of an event stream keeps one event's lines out of
  both (`sse_js.mbt`); what `Sse::feed` gives is still an `Array`, so a chunk that ends tens of thousands of events
  at once pays it there, as does anything else here that grows one. MoonBit's core's to mend; no program runs
  this library under Hermes.

## Working here

- Never `moon check` or `moon info` the whole workspace: mbui is a member of it, and moon writes every member's
  `pkg.generated.mbti` beside its packages, mbui's too. By package, here: `moon check --target native
  src/mesh` (and `--target js`), `moon test --target native src/wire`. The three `pkg.generated.mbti` are committed,
  as mbui's are, and are native's (on js `shell` starts with the address of iroh and has no `pump` or `run`): a check
  by package of a changed surface writes its own again, to commit; the check passes `--no-mbti` and writes none.
- `wire` and `mesh` are one source for both targets, but for one thing: what an event stream's reader does to many
  bytes at once, and to an event's many lines, is a file a target (`src/wire/moon.pkg`'s `targets`: `sse_js.mbt`,
  `sse_native.mbt`; `sse.mbt`'s head says why), each small enough to read against the other, and the package's
  tests run both. On js a timing in Node says nothing of it: what is slow there is slow under Hermes, and was
  found by running the built reader under its command line. Nothing else in
  them asks which it is built for: what differs is under `shell.mbt`'s surface, and an op the mesh comes to ask is
  answered by both shells, under the Rust shell's name and with its JSON.
- A fiber's wait on the shell given up is not the shell's call given up: of its calls only a dial is
  (`Shell::give_up`), in a page too. A read let go of goes on, holding the stream's receiving half, and what it
  takes is lost to the next read. So a stream is never read again after a read of it was interrupted: it is reset
  (`Reply::cancel`, `Link::sent`); and what must not be interrupted half way (an exchange on the control stream) is a
  fiber of the mesh's own scope that the others wait for with a `Deferred` (`Mesh::ping`; the probe of a link
  suspect, `Mesh::race`: what has a time is the wait, never the exchange, and an exchange whose wait is over
  before its turn on the stream came is not begun). A write let go of goes on too, and what of it went is not
  known: the stream is let go of, both ways, by the write itself (`Out::write`), as a request given up before its
  reply's head is (`Link::sent`). The wait for a stream to be opened (`conn.openBi`), let go of, would leave the
  stream the shell then opens open for nobody: it is the mesh's own fiber, which resets the one that comes for an
  asker gone (`Link::stream`). And the wait for a stream the peer opens (`conn.acceptBi`), let go of, would
  take the next stream and keep it from everyone: it is the mesh's own fiber, one under way a link at most, whose
  answer is kept on the link for whoever asks next (`Link::accept`); whoever waits for it waits for the link's end
  beside it, which the close says of every link, since that fiber cut before its first step says nothing. A wait
  that holds nothing is simply let go (`Out::stopped`, `Out::finish`). The wait for a connection a peer dials
  (`iroh.accept`), let go of, would take the next connection for nobody: it is the mesh's own fiber, one under
  way at most, whose answer is kept on the mesh for whoever asks next (`Mesh::await_coming`); whoever waits for
  it is told by the close, which lets go of the wait (`Mesh::forget_coming`), since that fiber cut says nothing.
  And a connection's first line (`Incoming::first`) is read in its asker's own fiber, which may be cut: then, and
  whenever it fails, the connection is closed, so the read that goes on is of nothing anyone reads again. A new wait on the shell says which of these
  it is, where it is written.
- `catch` does not catch a fiber's interruption: what must be undone then is in a `defer`. And a fiber interrupted
  before its first step runs nothing, no `defer` either. So what others wait for from a fiber of the mesh's scope
  (an opening's end, a link's answer, its end) is not left to that fiber as the mesh closes: `Mesh::close` says it
  itself, of every opening in `links`, every link in `live` and whoever waits to dial (`held`), in the step it is
  called in, and then cuts them all (a fiber not cut in time says nothing over what was said), or whoever waits on
  one cut before it began waits for good. That holds only while an opening not ended is in `links`: one is taken out, or
  put over, only once it ended (`Mesh::drop_link` ends one being opened itself, telling whoever waits and cutting
  its fiber, before it takes it out; that fiber, were it not cut in time, says nothing over an opening ended), and
  what waited on anything before it takes one out looks again whether it is still the one there (`Mesh::steer`,
  after its ping: the peer may have been asked for again meanwhile, or its program may have let go of the link, and
  one let go of is not dialled for). And where the mesh takes one out to dial anew itself, that dial's opening is
  put there in the same step (`Mesh::dial`, the half of `link` that waits for nothing): whoever is told `links`
  changed runs before a fiber forked there takes its first step, and a program that lets go of the place then must
  find the opening to end it, or the mesh dials on for a link nobody has (a review found it, 2026-11-14:
  `scope_wbtest.mbt`'s last case). What waits to be told `links` changed looks again as it is told
  (`Mesh::replaced`: the change may be another place's), and the close tells it too; it is not told which, so a
  holder that asks for the link again as it is told dials anew after its program's `drop_link` as well: a program
  rid of a link stops its holders first. A race (`racing`, health.mbt) is held to the same: it is its place's from
  the step its link is found suspect, before its fiber took a step; while it is there its old link is the one at
  its place, since whatever puts another there or takes it out ends the race in that step (`Mesh::end_race`:
  `drop_link`, `Mesh::dial`) or is its own verdict; a new link it opened has a place in the step it wins
  (`Mesh::switch`) or is closed; and the pings' own verdict leaves a link that is raced to the race. A link that
  ended while its ping was out (its peer closed it) is neither raced nor dialled for: its end is told
  (`Link::closed`), and its program asks again or does not, as in that mesh, whose ways are its usable links. A `Deferred` a
  new fiber of the scope is to complete for others is kept where the close finds it. And the close is whole once
  begun: its telling first, which needs nothing of the shell; then its fibers' ends, all at once but an endpoint
  being bound anew, which waits for the shell's answer to `iroh.bind` (and to the close of the endpoint of
  before); then what it asks of the shell itself, where an interruption of its caller waits too
  (`@effect.uninterruptible`). What the close waits on at the shell only the close waits on, for as long as the
  shell takes: that is the shell's to bound (a review found everyone it tells waiting there too, 2026-11-14).
- The endpoint's handle changes as it is bound anew (`Mesh::rebind`, wake.mbt), so nothing may hold the one of
  before across that. What is on an endpoint is counted in one place, `Mesh::idle`: a link whose connection has
  not ended (`live`; a stream of its peer's waited for is on a link), an opening under way with the dial tried
  beside it, a race; whatever comes to be on an endpoint otherwise is added there. It is bound anew only while that
  says nothing is, and nothing comes to be meanwhile: every dial is a `link`'s, which waits to be told the bind
  ended (`Mesh::hold`) and then looks at its place again (three askers of a place make one dial), or the mesh's
  own for a link, of which there is none. The bind is a fiber of
  the mesh's that nothing cuts short once begun (the shell binds whoever waits, and an endpoint bound for nobody
  would stay): `Mesh::close` waits for it with the others, it looks again as the shell answers (the mesh closed:
  the new endpoint is closed there and the close closes the one of before; else the new one is the mesh's from
  that step, whoever waited goes on, and the one of before is closed there after), so each is closed once; cut
  before its first step, it asked nothing and the close told whoever waited. What reads `endpoint` reads it as it
  asks (`Mesh::on_a_relay`, a dial), never kept from before a wait. And an endpoint taken for stuck has to come
  to have nothing on it, however it is asked: from the first `link` that finds it so with no connection open on
  it, and 5 s gone since the last bind, nothing new is dialled on it (`Mesh::settling`: what is left on it ends
  by itself, an opening in 10 s on a relay and 40 s on none), so it is bound as the last of that ends. Whoever
  asks meanwhile waits in `held`, at no place in `links`: told to look again wherever something leaves the
  endpoint (`Mesh::eased`: an opening ended, a link no more `live`, a race over, a bind ended; a place that
  forgets to say it parks an asker for good), failed as closed where its place is let go of (`drop_link`) and
  as the mesh closes. A review found the endpoint never bound while two places were asked for in turn, each
  one's dial keeping it from the other's (2026-11-14). With a connection open on it, it is dialled on as it
  is, as in that mesh.
- A connection a peer dialled that its program took is on the endpoint too (`incomings`, counted in `idle`, and
  as a connection open in `settling`). The one wait that is asked of an endpoint and outlives it is the wait for
  such a connection (`iroh.accept`): it is let go of in the step the endpoint is changed (`Mesh::forget_coming`:
  no more the one the mesh keeps, whoever waits on it told to look again, a connection it brought and nobody
  took closed), and both that wait's fiber, as the shell answers it, and its asker, as it wakes, look whether it
  is still the one kept before they take what it brought; an asker woken while the endpoint is being bound anew
  waits to be told that ended first (`held`, at no place), since a connection taken then would be on an endpoint
  that goes for having nothing on it. Where its relays are told again as others (`Mesh::retune`) the mesh makes
  the endpoint idle itself: everything on it is let go of in that one step (`Mesh::rehome`), the bind begun in
  the same step, which waits for their ends to be told first; told yet others while the shell binds, it binds
  once more before anyone goes on. What was told and the endpoint is not on yet is kept (`retuned`), and is as
  an endpoint taken for stuck to whoever asks for a link: bound by the next that finds nothing on it, nothing
  new dialled on it while what is on it ends by itself. The entries alone are told the endpoint as it is, one
  telling at a time, each looking again, as its turn comes and as the shell answers, whether those are still
  the ones wanted and that still the endpoint.
- What the mesh takes at a shell it lets go of there, for a page lives long: a stream by resetting it, or by
  reading it to its end and finishing it, which is when both shells let go of one (one whose read failed is reset:
  `Reply::take`; a request's is finished as it is sent, so reading its reply to its end is all it takes; one open
  both ways, a duplex's or one its peer opened, is its program's to finish or cancel, and read to its end alone it
  stays until its connection ends), a connection by closing it with `forget`, once its end
  is kept (`Link::ended` answers from that, and nothing is asked of it after) or at once where an opening gave it
  up, an endpoint by closing it. A new op that takes a handle says when it goes, in both shells.
- The times and the bytes are the TypeScript mesh's (`mesh.mbt`'s constants; `src/wire/wire_test.mbt`, line for
  line; `src/mesh/peer_wbtest.mbt`, a link's lines and when each goes), since the peer is the same door: a change to
  one is a change to what that peer is sent. One byte the peer sees differs, known: a link let go for its pings is
  closed here saying `closed`, where that mesh says `woke` of every link it drops (its `dropLink`), its program's
  and its pings' alike. The base takes no word of a program's for its own: what it closes itself says its own
  (`closed`, `credential refused`, `opening ended`), and a link its program lets go of says what the program gives
  (`Mesh::drop_link`), `closed` where it gives none.
- Where the race of a link suspect is not that mesh's (`Mesh::race`; numbers and conditions are: a ping missed
  after one answered in under 1.5 s, a probe of 5 s, the old link closed 10 s after another took its place):
  - Its probe is never given up half way. That mesh interrupts the exchange as its 5 s run out, its line sent or
    not, and may keep the link (something came on it meanwhile), whose control stream is then one answer behind:
    each line after reads the answer to the one before. Here the exchange is the mesh's own fiber: its time run out
    while it waited its turn behind the ping, nothing is sent (as there); run out with its line sent, its answer is
    read when it comes, so a link kept reads its answers in their order. The lines a peer is sent are the same, and
    their order; when one goes is not: the ping due while such a probe is still out waits its turn behind it, and
    goes as the probe's answer comes (there it goes at its tick, and reads that answer for its own).
  - A link whose third ping is missed while it is raced is the race's to decide. That mesh lets it go and dials
    anew then, a second dial beside the race's, whose link is closed as it opens. Here one dial is made: the
    race's; where neither answers the link is let go and nothing is dialled until it is asked for, as there
    where the race ends before the third miss.
  - Something having come on the old link keeps it only while it has not ended: there the bytes of the peer's own
    close count as the link being there after all, and the new link is closed for one that is gone.
  - Where the old link is kept, the new one's dial is given up at once (there it is left to finish, and closed).
  - A place's health is told only as it changes, and as the mesh closes (whoever waits fails as closed): there a
    place nothing was told of yet tells whoever waits what it already was, and nothing tells them at the close.
  - The race asks `conn.stats` of both shells (`rxBytes`). The page's shell answers it since this, in JavaScript no
    compiler reads and no test here runs; where a shell does not answer, nothing is taken to have come.
- Where a link's requests are not that mesh's (`link.mbt`; the head lines are, byte for byte: `wire_test.mbt` has
  what Node printed for that mesh's own expressions): one call takes what its `request` and `ask` take
  (`Link::request`'s `body`, `more`, `wrote`), and its `socket` is a `duplex` whose `more` says `socket`: what a
  head says after its headers is its program's. `more` may not name `method`, `path` or `headers` (there it writes
  over them unsaid). A link's refusal is said of every request on it (there of `request` alone). A write that
  failed or was given up lets go of its stream (there the stream is its caller's to reset). `Out::finish` is
  waited for (there it is sent off and its failure dropped), and asked once where it went. `Out::stopped` of a
  stream let go of here is the mesh's own answer, asked then or waiting as it happens (the shells answer a wait on
  a stream reset here only as its connection ends, so there it waits that long): none of one its program
  cancelled, cut of one let go of for a read or a write that failed, where a stop the peer sent may be what failed
  it. And it is asked before the stream is both read to its end and finished, after which the shells have none to
  ask (there the shell's failure is the caller's): where the reply may already be read to its end, before
  `finish`. A stream being opened for an asker gone is reset as it comes (there it stays). A number that is none
  is written `null`, as JavaScript writes it. `Link::accept` is one wait at the shell at a time,
  kept across askers (there each call is its own, and one given up takes the next stream with it). Not here: `tap`
  (a screen's frames read by the shell and said to the app itself; the Rust shell's `istream.tap`, no page's): a
  duplex's reply is read by its program. The page's shell answers `conn.acceptBi` and `istream.stopped` since
  this, in JavaScript no compiler reads; no test here, and no flow of the messenger's, runs either.
- Where a wake and the endpoint bound anew are not that mesh's (`wake.mbt`; `#watch`, `#hedge`, `#rebind` there):
  - **When an endpoint is bound anew.** There, twice: before a dial where a dial ran out of time unconnected and no
    link is open, and by the second dial of an opening at a wake where no link is open; both while openings may be
    under way on it (the one tried beside, too), whose dials end with the endpoint closed under them. Here only the
    first, and only while nothing at all is on it: an opening's second dial is on the same endpoint (the shell told
    of the network first), and an endpoint with another place's opening still under way waits for that to end,
    nothing new dialled on it meanwhile. What a peer can see of it: after a wake with no link open, the second
    dial comes from the same endpoint; and where that endpoint is in truth stuck a new one dials later than
    there by what is left of the openings under way: up to 10 s with the endpoint on a relay, up to 40 s with
    it on none (an opening waits 30 s to be on one before its 10 s count), and as long again from a wake that
    tried one a second time meanwhile. There, as here, a link open keeps the endpoint; here one whose
    connection is open and that is no more usable (its credential refused at a renewal) keeps it too, until it
    ends.
  - The second dial's link, come after the first's took the opening, is closed (there it is kept open by nobody);
    one that fails before the first leaves the first to end (there the first is given up and dialled again).
  - The second dial asks for its credential as the first did: a new one where the last was refused (there always
    the one its source has).
  - What the program says is that its connections are suspect, nothing more (`Mesh::wake()`): there a wake says how
    long away, whether the network changed and whether a person asked, and the mesh acts on any of the three alike
    but for speeds forgotten on a changed network, which are not kept here yet.
  - A race begun at a wake goes by the two answers alone, as there.
  - The page's shell answers `iroh.networkChange` since this, in JavaScript no compiler reads; no test here, and no
    flow of the messenger's, runs it. An endpoint bound a second time in a page (`iroh.bind` again, then
    `iroh.close` of the first) is run by no test here either, and is no rare path: any page that asks again for
    a peer that did not answer takes it.
- Where what the endpoint is bound with, its relays told again and the connections it takes are not that mesh's
  (`bind.mbt`; `make`, `#bind`, `retune`, `#accepting` there; what a bind is asked is, key for key):
  - **Relays told again as others, with links on the endpoint.** There the endpoint is bound anew at once and the
    one before closed with its links on it: their peers are told what the transport says of an endpoint closed,
    the links stay in its table until asked for again, and where the bind fails they are kept. Here every link is
    let go of first, as `drop_link` does (its peer told the reason its program gives, `closed` unless said; its
    holders told), then, as their ends are told, the endpoint is bound; where that bind fails the links are gone
    all the same, and the endpoint stays on the relays of before until a link finds nothing on it, 5 s later at
    the soonest (there it is never tried again). The same where the shell cannot be told the entries.
  - Told what it has is by the strings (there as URLs: one written two ways is one). A relay written another
    way is another here, and binds anew.
  - Which entry leads to which relay is its program's to say (`RelayEntry`): there the mesh is given the entries
    and a table of their relays and works it out, dropping an entry that is among the relays or whose relay is
    not the endpoint's. The entries as ways of their own to dial through are the ways', not here yet.
  - The entries are told one telling at a time, and ones told over before their turn are never asked (there each
    telling is sent off as it is told, in no order the shell holds to).
  - A connection a peer dials is asked for by its program, one at a time (`Mesh::incoming`), and its first stream
    and first line are held to 30 s and 64 KiB (`Incoming::first`): there every connection is handed to its
    program as it comes, which waits for its first stream with no time. One taken counts as on the endpoint:
    an endpoint taken for stuck is not bound anew under it (there it is, no link being open, and the connection
    ends with the endpoint). Of a connection taken, only its first stream is given: further streams of its
    peer's, streams opened on it from here, its paths, are not here; nor is a peer dialled on another protocol
    with no credential (that mesh's `endpoint()`, the other side of what its program takes).
  - The page's shell binds with `relayEntries` where any are said and answers `iroh.setRelayEntries` since this,
    in JavaScript no compiler reads and no test here runs; `iroh.accept` it has not (iroh-wasm takes no
    connection), and `Mesh::incoming` on a page fails saying so (`host`). No flow of the messenger's runs any of
    the three, nor a second bind in a page.
- A compiler warning is an error or off (`moon.mod`'s `warnings`, mbui's line).
