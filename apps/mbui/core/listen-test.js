// The core's stand-in for core/listen_test.m: what client/core-ts's bridge host asks of `listen.*` (hosts/bridge.ts),
// straight on apple_core.mm's __native, and what it got, told to the test as messages. Plain ES2017, not bundled.
var pending = {};
var nextCall = 1;
var client = 0;

function call(op, args, bytes) {
  return new Promise(function (resolve, reject) {
    var id = nextCall++;
    pending[id] = { resolve: resolve, reject: reject };
    __native.call(id, op, JSON.stringify(args), bytes);
  });
}

function say(o) {
  __native.emit(client, JSON.stringify(o));
}

function text(buffer) {
  return buffer ? String.fromCharCode.apply(null, new Uint8Array(buffer)) : "";
}

function bytes(s) {
  var out = new Uint8Array(s.length);
  for (var i = 0; i < s.length; i++) out[i] = s.charCodeAt(i);
  return out.buffer;
}

async function run() {
  try {
    var opened = (await call("listen.open", { port: 0, host: "127.0.0.1" })).json;
    var taken = null;
    try {
      await call("listen.open", { port: opened.port, host: "127.0.0.1" });
    } catch (e) {
      taken = String(e);
    }
    var outside = null;
    try {
      await call("listen.open", { port: 0, host: "0.0.0.0" });
    } catch (e) {
      outside = String(e);
    }
    say({ opened: opened.port, taken: taken, outside: outside });
    var asked = await call("listen.next", { id: opened.id });
    say({ asked: asked.json, body: text(asked.bytes) });
    await call(
      "listen.respond",
      { id: opened.id, request: asked.json.request, status: 200, headers: [["Content-Type", "text/plain"], ["X-Test", "yes"], ["Content-Length", "1"]] },
      bytes("answered " + asked.json.path),
    );
    var waiting = call("listen.next", { id: opened.id });
    await call("listen.close", { id: opened.id });
    say({ ended: (await waiting).json, after: (await call("listen.next", { id: opened.id })).json });
  } catch (e) {
    say({ failed: String(e) });
  }
}

globalThis.__stillfail = {
  start: function () {},
  connect: function () {
    client = 1;
    run();
    return client;
  },
  complete: function (id, json, error, buffer) {
    var p = pending[id];
    delete pending[id];
    if (!p) return;
    if (error !== null && error !== undefined) p.reject(error);
    else p.resolve({ json: JSON.parse(json), bytes: buffer });
  },
  receive: function () {},
  receiveBytes: function () {},
};
