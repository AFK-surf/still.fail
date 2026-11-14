// The shell of a page: the ops the mesh asks of the Rust shell (shell.mbt lists the two), by the same names
// with the same JSON and bytes, done with what a browser has. iroh is iroh for the browser
// (client/iroh-wasm, a module made by wasm-bindgen with its wasm beside it; its calls are those the TypeScript core
// wraps, client/core-ts/src/iroh-bindings.ts), loaded from where the page serves it the first time an endpoint is
// bound; what is kept is kept in the page's localStorage; the clock is the page's, the random bytes its crypto's.
//
//   op                 on a page
//   storage.get/set    localStorage, the key `<dir>:<key>`, the value in hex (a file a key natively)
//   iroh.bind          the module's `bind({secretKey, relayUrls})`: through relays alone whatever is asked (a browser
//                      has no UDP: `relayOnly` is always so), and nothing looked up (`lookup` never)
//   iroh.connect       `endpoint.connect(addr, alpn, [], givenUp)`; `fetch.cancel` of its call resolves `givenUp`,
//                      which drops the handshake, and it is answered "cancelled" as natively
//   iroh.endpointId, iroh.relayStatus, iroh.close      the endpoint's `id`, `relayStatus`, `close`
//   conn.openBi, conn.close, conn.closed, conn.closeReason, conn.paths, conn.stats
//                      the connection's `openBi`, `close(code, reason)`, `closedInfo`, `closeReason`, `paths` (each
//                      path a relay's: no `ip`), `stats` (`{rxBytes, txBytes}` alone of what the Rust shell says,
//                      and of a connection not ended alone: one that ended is "not its handle", which the mesh
//                      takes as nothing more having come)
//   conn.acceptBi      the connection's `acceptBi`: the next stream its peer opens, a handle as one opened here; of
//                      a connection that ended, or ends meanwhile, `{end: true}`, never a failure
//   istream.read/write/finish/reset                    the stream's own; a read answers its end as `{end: true}`
//   istream.stopped    the stream's `stopped`: `{code}`, what its peer stopped it with, else null: once what was
//                      written is taken, and of a stream reset here. iroh-wasm says null of a failure too, so
//                      where it does and the stream's connection has ended this fails, as the Rust shell does;
//                      a failure with its connection up cannot be told from null
//
// A handle is a number, as the Rust shell's (`{"id": n}`), and a page lives long: each is let go of, none kept for
// the page's life.
//   a stream       once reset, or read to its end and finished; and with its connection, as that ends (its control
//                  stream, which is neither; a reply's left unread): as the Rust shell lets a connection's go;
//   a connection   kept as why it ended once it has (asked after, it answers that), until it is closed with
//                  `forget` (`conn.close {id, forget: true}`: the mesh's, once it was told the end and keeps why
//                  itself, or at once of one an opening gave up, ended or not) or its endpoint closes. The Rust
//                  shell reads no `forget` and keeps that of every connection it had: there it is that shell's to
//                  let go;
//   an endpoint    as it is closed, with every connection of it and their streams. Nothing is answered of it after
//                  (the Rust shell still says a closed one's id: the mesh keeps it and asks none).
// As natively, a wait given up is not a call given up but for a dial: a read let go of goes on (iroh-wasm's `read`
// holds the stream's receiving half), so a stream is not read again after that, but reset.
//
// There is no loop to pump from: every answer is an event of the page's (a promise's), given to its fiber and then
// followed by a turn of the runtime, and so is a timer of the runtime's come due (`Shell::start`).

///|
/// The page's side, made once (`page_start`): the handles, iroh's module once loaded, the one timer.
#external
priv type Page

///|
/// `answered(id, kind, text, bytes)` is called as a call is answered (`Shell::settle`'s kinds), never while it is
/// asked.
extern "js" fn page_start(prefix : String, iroh : String, answered : (Int, Int, String, Bytes) -> Unit) -> Page =
  #|(prefix, irohAt, answered) => {
  #|  const none = new Uint8Array(0);
  #|  // by handle: {endpoint}; {conn, of: its endpoint, closed: why it ended, once it has} or, ended, {gone: why, of};
  #|  // {stream, on: its connection, finished, ended}
  #|  const handles = new Map();
  #|  let last = 0;
  #|  const keep = (handle) => (handles.set(++last, handle), last);
  #|  // a connection's streams let go of (as it ends, or is let go of itself)
  #|  const streamsGo = (conn) => {
  #|    for (const [id, h] of handles) if (h.on === conn) handles.delete(id);
  #|  };
  #|  // by the call of a dial under way: what gives it up
  #|  const dials = new Map();
  #|  let iroh = null;
  #|  const load = () => (iroh ??= import(irohAt).then((module) => module.default().then(() => module)).catch((e) => { iroh = null; throw e; }));
  #|  const hex = (bytes) => Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
  #|  const unhex = (text) => Uint8Array.from(text.match(/../g) ?? [], (b) => Number.parseInt(b, 16));
  #|  const connection = (h) => {
  #|    if (h?.gone !== undefined) throw new Error("connection closed: " + (h.gone.reason ?? ""));
  #|    if (h?.conn === undefined) throw new Error("not a connection");
  #|    return h.conn;
  #|  };
  #|  const stream = (h) => {
  #|    if (h?.stream === undefined) throw new Error("not a stream");
  #|    return h.stream;
  #|  };
  #|  // what a call is answered later: [its JSON] or [its JSON, its bytes]
  #|  const run = async (id, op, a, bytes) => {
  #|    const h = handles.get(a.id);
  #|    switch (op) {
  #|      case "storage.get": {
  #|        const kept = localStorage.getItem(prefix + ":" + a.key);
  #|        return kept === null ? [{ none: true }] : [{}, unhex(kept)];
  #|      }
  #|      case "storage.set":
  #|        localStorage.setItem(prefix + ":" + a.key, hex(bytes ?? none));
  #|        return [{}];
  #|      case "iroh.bind": {
  #|        const module = await load();
  #|        return [{ id: keep({ endpoint: await module.bind({ secretKey: bytes ?? none, relayUrls: a.relayUrls ?? [] }) }) }];
  #|      }
  #|      case "iroh.connect": {
  #|        if (h?.endpoint === undefined) throw new Error("not an endpoint");
  #|        let giveUp = () => {};
  #|        let gave = false;
  #|        const given = new Promise((resolve) => (giveUp = resolve));
  #|        dials.set(id, () => { gave = true; giveUp(); });
  #|        try {
  #|          const conn = await h.endpoint.connect(a.addr, bytes ?? none, [], given);
  #|          // (its endpoint closed meanwhile: nothing would let go of a connection kept now)
  #|          if (handles.get(a.id) !== h) {
  #|            conn.close(0, "closed");
  #|            throw new Error("the endpoint is closed");
  #|          }
  #|          const entry = { conn, of: a.id, closed: conn.closedInfo().catch((e) => ({ kind: "other", reason: said(e) })) };
  #|          const kept = keep(entry);
  #|          // Ended, however it did: its streams go, and what is kept of it is why (unless it was let go of first).
  #|          entry.closed.then((why) => {
  #|            if (handles.get(kept) !== entry) return;
  #|            handles.set(kept, { gone: why, of: a.id });
  #|            streamsGo(kept);
  #|          });
  #|          return [{ id: kept }];
  #|        } catch (e) {
  #|          throw gave ? new Error("cancelled") : e;
  #|        } finally {
  #|          dials.delete(id);
  #|        }
  #|      }
  #|      case "iroh.close":
  #|        if (h?.endpoint !== undefined) {
  #|          // let go of with all that was its: its connections, ended or not, and their streams
  #|          handles.delete(a.id);
  #|          for (const [id, one] of handles) {
  #|            if (one.of !== a.id) continue;
  #|            handles.delete(id);
  #|            streamsGo(id);
  #|          }
  #|          await h.endpoint.close();
  #|        }
  #|        return [{}];
  #|      case "conn.openBi": {
  #|        const opened = await connection(h).openBi();
  #|        // (ended, or let go of, meanwhile: its streams went then, and this one would stay)
  #|        if (handles.get(a.id) !== h) throw new Error("connection closed");
  #|        return [{ id: keep({ stream: opened, on: a.id, finished: false, ended: false }) }];
  #|      }
  #|      case "conn.acceptBi": {
  #|        if (h?.gone !== undefined) return [{ end: true }];
  #|        const accepted = await connection(h).acceptBi();
  #|        // (ended, or let go of, meanwhile: its streams went then, and this one would stay)
  #|        if (accepted === null || accepted === undefined || handles.get(a.id) !== h) return [{ end: true }];
  #|        return [{ id: keep({ stream: accepted, on: a.id, finished: false, ended: false }) }];
  #|      }
  #|      case "conn.closed":
  #|        if (h?.gone !== undefined) return [h.gone];
  #|        connection(h);
  #|        return [await h.closed];
  #|      case "conn.close":
  #|        if (h?.gone === undefined) connection(h).close(a.code ?? 0, a.reason ?? "");
  #|        // `forget`: nothing is asked of it after (the mesh was told its end, or gave it up with its opening, where
  #|        // it is closed just above): let go of, its streams with it
  #|        if (a.forget === true) {
  #|          handles.delete(a.id);
  #|          streamsGo(a.id);
  #|        }
  #|        return [{}];
  #|      case "istream.read": {
  #|        const came = await stream(h).read();
  #|        if (came !== null && came !== undefined) return [{}, came];
  #|        h.ended = true;
  #|        if (h.finished) handles.delete(a.id);
  #|        return [{ end: true }];
  #|      }
  #|      case "istream.write":
  #|        await stream(h).write(bytes ?? none);
  #|        return [{}];
  #|      case "istream.finish":
  #|        await stream(h).finish();
  #|        h.finished = true;
  #|        if (h.ended) handles.delete(a.id);
  #|        return [{}];
  #|      case "istream.stopped": {
  #|        const code = (await stream(h).stopped()) ?? null;
  #|        if (code === null) {
  #|          // (null is a failure's answer too: its connection ended, or let go of, that is what it was)
  #|          const on = handles.get(h.on);
  #|          if (on?.conn === undefined || (on.conn.closeReason() ?? null) !== null) throw new Error("connection closed");
  #|        }
  #|        return [{ code }];
  #|      }
  #|      case "istream.reset":
  #|        if (h?.stream !== undefined) {
  #|          handles.delete(a.id);
  #|          await h.stream.reset(a.code ?? 0);
  #|        }
  #|        return [{}];
  #|      default:
  #|        throw new Error("a page's shell has no " + op);
  #|    }
  #|  };
  #|  // what a call is answered at once
  #|  const now = (op, a) => {
  #|    if (op === "fetch.cancel") {
  #|      const give = dials.get(a.id);
  #|      if (give === undefined) return false;
  #|      give();
  #|      return true;
  #|    }
  #|    const h = handles.get(a.id);
  #|    switch (op) {
  #|      case "iroh.endpointId":
  #|        if (h?.endpoint !== undefined) return h.endpoint.id();
  #|        break;
  #|      case "iroh.relayStatus":
  #|        if (h?.endpoint !== undefined) return h.endpoint.relayStatus();
  #|        break;
  #|      case "conn.closeReason":
  #|        if (h?.conn !== undefined) return h.conn.closeReason() ?? null;
  #|        if (h?.gone !== undefined) return h.gone;
  #|        break;
  #|      case "conn.paths":
  #|        if (h?.conn !== undefined) return h.conn.paths();
  #|        if (h?.gone !== undefined) return [];
  #|        break;
  #|      case "conn.stats":
  #|        // ({rxBytes, txBytes}: of one that ended a page keeps none, and the mesh asks it of none)
  #|        if (h?.conn !== undefined) return h.conn.stats();
  #|        break;
  #|      default:
  #|        throw new Error("a page's shell has no " + op);
  #|    }
  #|    throw new Error(op + ": not its handle");
  #|  };
  #|  const said = (e) => String(e?.message ?? e);
  #|  let timer = 0;
  #|  return {
  #|    call: (id, op, json, bytes, has) => {
  #|      run(id, op, JSON.parse(json), has ? bytes : null).then(
  #|        (answer) => answered(id, answer.length > 1 ? 1 : 0, JSON.stringify(answer[0]), answer.length > 1 ? answer[1] : none),
  #|        (e) => answered(id, 2, said(e), none),
  #|      );
  #|    },
  #|    ask: (op, json) => {
  #|      try {
  #|        return JSON.stringify({ value: now(op, JSON.parse(json)) ?? null });
  #|      } catch (e) {
  #|        return JSON.stringify({ error: said(e) });
  #|      }
  #|    },
  #|    soon: (turn) => queueMicrotask(turn),
  #|    // (a delay past 2^31-1 ms a browser takes for none and fires at once: the most it takes is asked instead, and
  #|    // the turn that comes of it, finding nothing due, asks again for what is left)
  #|    wake: (ms, turn) => {
  #|      clearTimeout(timer);
  #|      timer = ms < 0 ? 0 : setTimeout(turn, Math.min(ms, 2147483647));
  #|    },
  #|  };
  #|}

///|
extern "js" fn page_call(page : Page, id : Int, op : String, json : String, bytes : Bytes, has : Bool) -> Unit =
  #|(page, id, op, json, bytes, has) => page.call(id, op, json, bytes, has)

///|
extern "js" fn page_ask(page : Page, op : String, json : String) -> String =
  #|(page, op, json) => page.ask(op, json)

///|
/// `turn` run once what runs now is over (a microtask).
extern "js" fn page_soon(page : Page, turn : () -> Unit) -> Unit =
  #|(page, turn) => page.soon(turn)

///|
/// `turn` run `ms` from now, in the place of the one asked before (the page's one timer); negative: none. It may
/// come early (after 2^31-1 ms where `ms` is more): whoever asks looks at the clock when it does.
extern "js" fn page_wake(page : Page, ms : Double, turn : () -> Unit) -> Unit =
  #|(page, ms, turn) => page.wake(ms, turn)

///|
extern "js" fn page_now() -> Double =
  #|() => performance.now()

///|
extern "js" fn page_random(n : Int) -> Bytes =
  #|(n) => crypto.getRandomValues(new Uint8Array(n))

///|
/// The page's side, once the shell is started.
let page : Ref[Page?] = Ref(None)

///|
/// Starts the shell of this page for the fibers of `rt`: what it keeps (`storage.*`) is in the page's localStorage
/// under `dir` (the key `<dir>:<key>`, in hex), and iroh is the module at `iroh` (an address of the page's server:
/// iroh-wasm's JavaScript, its wasm beside it), loaded as the first endpoint is bound. From now on `rt` is turned by
/// the page's events: once what woke a fiber is over (an answer of the shell's, a fork from the page's own code), and
/// as its next timer comes due, by `rt`'s own clock. So `rt` is a runtime on a clock of the page's
/// (`Runtime::live(now)`), and nothing else ticks it.
pub fn Shell::start(rt : @effect.Runtime, dir : String, iroh~ : String) -> Shell {
  let shell = Shell::of_target(rt)
  let made = page_start(dir, iroh, (id, kind, text, bytes) => shell.settle(id.to_int64(), kind, text, bytes))
  page.val = Some(made)
  // (one turn for all that woke since the last: asked once, run as a microtask; then the page's timer set for the
  // runtime's next, which asks a turn as it comes due)
  let asked = Ref(false)
  let wake : Ref[() -> Unit] = Ref(() => ())
  let turn = () => {
    asked.val = false
    rt.tick()
    match rt.next_timer() {
      Some(at) => {
        let left = at - rt.now()
        page_wake(made, if left < 0L { 0.0 } else { left.to_double() }, () => (wake.val)())
      }
      None => page_wake(made, -1.0, () => ())
    }
  }
  wake.val = () => {
    if !asked.val {
      asked.val = true
      page_soon(made, turn)
    }
  }
  rt.on_wake(() => (wake.val)())
  rt.on_timer(_ => (wake.val)())
  shell
}

///|
/// A call out: `op` with its JSON and, where it carries any, its bytes, answered later as `id`.
fn send(id : Int64, op : String, json : String, bytes : Bytes?) -> Unit {
  guard page.val is Some(page) else { return }
  match bytes {
    Some(b) => page_call(page, id.to_int(), op, json, b, true)
    None => page_call(page, id.to_int(), op, json, b"", false)
  }
}

///|
/// What the shell answers `op` at once: `{"value": …}` or `{"error": …}`.
fn asked(op : String, json : String) -> String {
  match page.val {
    Some(page) => page_ask(page, op, json)
    None => "{\"error\":\"the shell is not started\"}"
  }
}

///|
/// A clock that never goes back, in ms: what a runtime of the shell's programs goes by.
pub fn now() -> Int64 {
  page_now().to_int64()
}

///|
/// `n` bytes of the system's randomness (a key).
pub fn random(n : Int) -> Bytes {
  page_random(n)
}
