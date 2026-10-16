// What the core does with a screen view's frame, alone (FramePathBench.kt): a call `bench {size, count, mode, every}`
// answers `count` values `{frame: {key, ts, at}}`, each a frame of `size` random bytes as the core would have it (its
// own buffer, sliced out of what the link read), said either beside the JSON (`mode: "bytes"`, __native.emitBytes) or
// in it as base64 (`mode: "base64"`, __native.emit, the core's own base64 as client/core-ts/src/util.ts has it), then
// `{ok: {ms}}`: how long the engine's thread spent on them. `every` (ms): one frame each so often (on the engine's
// timers), else all at once.
var B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

function base64(bytes) {
  var out = "";
  var i = 0;
  for (; i + 2 < bytes.length; i += 3) {
    var n = (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2];
    out += B64[(n >> 18) & 63] + B64[(n >> 12) & 63] + B64[(n >> 6) & 63] + B64[n & 63];
  }
  var rest = bytes.length - i;
  if (rest === 1) {
    var a = bytes[i] << 16;
    out += B64[(a >> 18) & 63] + B64[(a >> 12) & 63] + "==";
  } else if (rest === 2) {
    var b = (bytes[i] << 16) | (bytes[i + 1] << 8);
    out += B64[(b >> 18) & 63] + B64[(b >> 12) & 63] + B64[(b >> 6) & 63] + "=";
  }
  return out;
}

function noise(size) {
  var b = new Uint8Array(size);
  var x = 12345;
  for (var i = 0; i < size; i++) {
    x = (Math.imul(x, 1103515245) + 12345) | 0;
    b[i] = (x >>> 16) & 255;
  }
  return b;
}

var timers = {};
var nextTimer = 1;
globalThis.__stillfail_timer = function (id) {
  var f = timers[id];
  delete timers[id];
  if (f) f();
};
function later(ms, f) {
  var id = nextTimer++;
  timers[id] = f;
  __native.setTimer(id, ms);
}

function bench(client, id, p) {
  var source = noise(p.size);
  var spent = 0;
  var i = 0;
  function one() {
    var t0 = __native.monotonic();
    // The frame as it comes: a buffer of its own.
    var frame = source.slice();
    var head = { frame: { key: i === 0, ts: i, at: t0 } };
    if (p.mode === "bytes") __native.emitBytes(client, JSON.stringify({ id: id, value: head }), frame.buffer);
    else {
      head.bytes = base64(frame);
      __native.emit(client, JSON.stringify({ id: id, value: head }));
    }
    spent += __native.monotonic() - t0;
    i++;
  }
  function done() {
    __native.emit(client, JSON.stringify({ id: id, ok: { ms: spent } }));
  }
  if (!p.every) {
    while (i < p.count) one();
    done();
    return;
  }
  function tick() {
    one();
    if (i < p.count) later(p.every, tick);
    else done();
  }
  tick();
}

globalThis.__stillfail = {
  start: function () {},
  connect: function () {},
  complete: function () {},
  receive: function (client, json) {
    var m = JSON.parse(json);
    if (m.call === "bench") bench(client, m.id, m.params);
    else if (m.call !== undefined) __native.emit(client, JSON.stringify({ id: m.id, ok: null }));
  },
};
