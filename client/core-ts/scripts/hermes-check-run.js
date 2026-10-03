;(function () {
  var t0 = Date.now();
  globalThis.__stillfail.start("http://127.0.0.1:1", false);
  var c = globalThis.__stillfail.connect();
  globalThis.__stillfail.receive(c, JSON.stringify({ id: 1, subscribe: { topic: "accounts" } }));
  globalThis.__stillfail.receive(c, JSON.stringify({ id: 2, subscribe: { topic: "prefs" }, keyed: true }));
  globalThis.__stillfail.receive(c, JSON.stringify({ id: 3, call: "prefs.set", params: { appearance: "dark" } }));
  globalThis.__stillfail.receive(c, JSON.stringify({ id: 4, call: "draft.put", params: { station: "w/s", chat: "new", text: "你好 hermes 😀", quotes: [], files: [] } }));
  globalThis.__stillfail.receive(c, JSON.stringify({ id: 5, subscribe: { topic: "chats", scope: "w" }, keyed: true }));
  // The CLI runs timers at once, in order (no clock): later is after so many turns.
  var after = function (turns, fn) { if (turns === 0) fn(); else setTimeout(function () { after(turns - 1, fn); }, 0); };
  after(300, function () {
    globalThis.__stillfail.receive(c, JSON.stringify({ id: 6, call: "draft.get", params: { station: "w/s", chat: "new" } }));
  });
  after(1500, function () {
    print("started and answered in " + (Date.now() - t0) + " ms");
    emitted.forEach(function (m) { print(m.slice(0, 220)); });
    print("records: " + Object.keys(records).join(","));
  });
})();
