// A check of the Hermes bundle in Hermes's own CLI (scripts/hermes-bundle.ts): a shell faked in JS (storage and the
// database in memory, no network), the core started, subscribed to and called; what it says is printed.
//   cat scripts/hermes-check.js <bundle.js> scripts/hermes-check-run.js > x.js && hermes -Xes6-class -block-scoping -Xmicrotask-queue x.js
var store = {}, records = {}, emitted = [], timers = {};
var enc = function (s) { var out = []; s = unescape(encodeURIComponent(s)); for (var i = 0; i < s.length; i++) out.push(s.charCodeAt(i)); return new Uint8Array(out).buffer; };
globalThis.__native = {
  call: function (id, op, json, bytes) {
    if (globalThis.TRACE) print("CALL " + op + " " + json.slice(0, 80));
    var a = JSON.parse(json), answer = function (j, b, e) { setTimeout(function () { globalThis.__stillfail.complete(id, e ? null : JSON.stringify(j || {}), e || null, b); }, 0); };
    if (op === "storage.get") return store[a.key] ? answer({}, store[a.key]) : answer({ none: true });
    if (op === "storage.set") { store[a.key] = bytes; return answer({}); }
    if (op === "storage.delete") { delete store[a.key]; return answer({}); }
    if (op === "db.read") { var keys = Object.keys(records[a.table] || {}).filter(function (k) { return k >= a.from && k < a.to; }).sort(); var parts = keys.map(function (k) { return new Uint8Array(records[a.table][k]); }); var size = parts.reduce(function (n, p) { return n + p.length; }, 0), all = new Uint8Array(size), at = 0; parts.forEach(function (p) { all.set(p, at); at += p.length; }); return answer({ keys: keys, sizes: parts.map(function (p) { return p.length; }) }, all.buffer); }
    if (op === "db.write") { var v = new Uint8Array(bytes || new ArrayBuffer(0)), at2 = 0; a.ops.forEach(function (o) { if (o.put) { (records[o.put.table] = records[o.put.table] || {})[o.put.key] = v.slice(at2, at2 + o.put.size).buffer; at2 += o.put.size; } else if (records[o["delete"].table]) delete records[o["delete"].table][o["delete"].key]; }); return answer({}); }
    return answer(null, undefined, "offline in the check: " + op);
  },
  callSync: function () { return JSON.stringify({ error: "none" }); },
  emit: function (client, json) { emitted.push(json); },
  fatal: function (reason) { print("FATAL " + reason); },
  now: function () { return Date.now(); },
  monotonic: function () { return Date.now(); },
  utcOffset: function (at) { return -new Date(at).getTimezoneOffset(); },
  random: function (n) { var b = new Uint8Array(n); for (var i = 0; i < n; i++) b[i] = Math.floor(Math.random() * 256); return b.buffer; },
  setTimer: function (id, ms) { timers[id] = setTimeout(function () { globalThis.__stillfail_timer(id); }, ms); },
  clearTimer: function (id) { clearTimeout(timers[id]); },
  log: function (level, m) { print("LOG" + level + " " + m); },
};
