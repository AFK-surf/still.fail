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
//   conn.openBi, conn.close, conn.closed, conn.closeReason, conn.paths
//                      the connection's `openBi`, `close(code, reason)`, `closedInfo`, `closeReason`, `paths` (each
//                      path a relay's: no `ip`)
//   istream.read/write/finish/reset                    the stream's own; a read answers its end as `{end: true}`
//
// A handle is a number, as the Rust shell's (`{"id": n}`): an endpoint, a connection (kept as why it ended once it
// has: asked after, it answers that), a stream (let go of once reset, or read to its end and finished). As natively,
// a wait given up is not a call given up but for a dial: a read let go of goes on (iroh-wasm's `read` holds the
// stream's receiving half), so a stream is not read again after that, but reset.
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
  #|  // by handle: {endpoint} or, closed, {unbound: its id}; {conn} or, ended, {gone: why}; {stream, finished, ended}
  #|  const handles = new Map();
  #|  let last = 0;
  #|  const keep = (handle) => (handles.set(++last, handle), last);
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
  #|        if (h?.unbound !== undefined) throw new Error("the endpoint is closed");
  #|        if (h?.endpoint === undefined) throw new Error("not an endpoint");
  #|        let giveUp = () => {};
  #|        let gave = false;
  #|        const given = new Promise((resolve) => (giveUp = resolve));
  #|        dials.set(id, () => { gave = true; giveUp(); });
  #|        try {
  #|          const conn = await h.endpoint.connect(a.addr, bytes ?? none, [], given);
  #|          const kept = keep({ conn });
  #|          conn.closedInfo().then((why) => handles.set(kept, { gone: why }), () => {});
  #|          return [{ id: kept }];
  #|        } catch (e) {
  #|          throw gave ? new Error("cancelled") : e;
  #|        } finally {
  #|          dials.delete(id);
  #|        }
  #|      }
  #|      case "iroh.close":
  #|        if (h?.endpoint !== undefined) {
  #|          handles.set(a.id, { unbound: h.endpoint.id() });
  #|          await h.endpoint.close();
  #|        }
  #|        return [{}];
  #|      case "conn.openBi":
  #|        return [{ id: keep({ stream: await connection(h).openBi(), finished: false, ended: false }) }];
  #|      case "conn.closed":
  #|        return [h?.gone !== undefined ? h.gone : await connection(h).closedInfo()];
  #|      case "conn.close":
  #|        if (h?.gone === undefined) connection(h).close(a.code ?? 0, a.reason ?? "");
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
  #|        if (h?.unbound !== undefined) return h.unbound;
  #|        break;
  #|      case "iroh.relayStatus":
  #|        if (h?.endpoint !== undefined) return h.endpoint.relayStatus();
  #|        if (h?.unbound !== undefined) return [];
  #|        break;
  #|      case "conn.closeReason":
  #|        if (h?.conn !== undefined) return h.conn.closeReason() ?? null;
  #|        if (h?.gone !== undefined) return h.gone;
  #|        break;
  #|      case "conn.paths":
  #|        if (h?.conn !== undefined) return h.conn.paths();
  #|        if (h?.gone !== undefined) return [];
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
  #|    wake: (ms, turn) => {
  #|      clearTimeout(timer);
  #|      timer = ms < 0 ? 0 : setTimeout(turn, ms);
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
/// `turn` run `ms` from now, in the place of the one asked before (the page's one timer); negative: none.
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
/// as its next timer comes due. So `rt` is a runtime on this clock (`Runtime::live(now)`), and nothing else ticks it.
pub fn Shell::start(rt : @effect.Runtime, dir : String, iroh~ : String) -> Shell {
  let shell : Shell = { rt, waiting: Map([]), next: 0L }
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
        let left = at - now()
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
