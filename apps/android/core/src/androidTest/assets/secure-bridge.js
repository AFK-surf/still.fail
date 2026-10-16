// The bridge's `secure.*` calls alone (SecureStoreTest.kt): a call `secure {op, key, user, reason, value}` asks
// __native.call("secure.<op>") as client/core-ts hosts/bridge.ts does (the value's bytes beside the JSON, base64 here)
// and answers `{json, value}` (the answer's bytes in base64, null for none), or fails with the error the app gave.
var B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

function encode(bytes) {
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

function decode(text) {
  var out = [];
  var bits = 0;
  var acc = 0;
  for (var i = 0; i < text.length; i++) {
    var v = B64.indexOf(text[i]);
    if (v < 0) continue;
    acc = (acc << 6) | v;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      out.push((acc >> bits) & 255);
    }
  }
  return new Uint8Array(out);
}

var waiting = {};
var next = 1;

globalThis.__stillfail = {
  start: function () {},
  connect: function () {},
  complete: function (id, json, error, bytes) {
    var w = waiting[id];
    delete waiting[id];
    if (!w) return;
    if (error !== null) __native.emit(w.client, JSON.stringify({ id: w.id, error: { code: "host", message: error } }));
    else __native.emit(w.client, JSON.stringify({ id: w.id, ok: { json: json === "" ? null : JSON.parse(json), value: bytes === undefined ? null : encode(new Uint8Array(bytes)) } }));
  },
  receive: function (client, json) {
    var m = JSON.parse(json);
    if (m.call !== "secure") {
      if (m.call !== undefined) __native.emit(client, JSON.stringify({ id: m.id, ok: null }));
      return;
    }
    var p = m.params;
    var id = next++;
    waiting[id] = { client: client, id: m.id };
    var args = { key: p.key, user: p.user === true, reason: p.reason || "" };
    if (typeof p.value === "string") __native.call(id, "secure." + p.op, JSON.stringify(args), decode(p.value).buffer);
    else __native.call(id, "secure." + p.op, JSON.stringify(args));
  },
};
