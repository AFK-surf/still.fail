// What the app's Kotlin side does, for the measurement in Hermes (main.cpp): start the core offline, subscribe the chat
// list of the bench's workspace (bench/first-view.ts seeds it), note when its first rows and its last change came and
// the memory then; once nothing changed for 5 s, read the list once more to count it, print, end.
(function () {
  var t0 = __bench.now();
  var first = null;
  var lastAt = null;
  var emits = 0;
  var rowsOf = function (v) {
    var n = 0;
    var days = (v && v.days) || [];
    for (var i = 0; i < days.length; i++) n += days[i].items.length;
    return n;
  };
  var memory = function () {
    __bench.gc();
    return { rssMB: Math.round(__bench.rss() / 104857.6) / 10, heapMB: Math.round(__bench.heap() / 104857.6) / 10 };
  };
  var counted = null;
  __native.emit = function (client, json) {
    if (json.indexOf('{"id":1,') !== 0 && json.indexOf('{"id":2,') !== 0) return;
    var m = JSON.parse(json);
    if (m.id === 2) {
      if (m.value && counted === null) counted = rowsOf(m.value);
      return;
    }
    emits++;
    lastAt = __bench.now() - t0;
    if (first === null && m.value && rowsOf(m.value) > 0) first = { ms: Math.round(lastAt), rows: rowsOf(m.value), memory: memory() };
  };
  __stillfail.start("http://127.0.0.1:9", false);
  var ui = __stillfail.connect();
  __stillfail.receive(ui, JSON.stringify({ id: 1, subscribe: { topic: "chats", scope: "w", mine: false }, keyed: true }));
  var check = function () {
    var now = __bench.now() - t0;
    if (first !== null && counted === null && now - lastAt > 5000) {
      __stillfail.receive(ui, JSON.stringify({ id: 2, subscribe: { topic: "chats", scope: "w", mine: false }, keyed: true }));
    }
    if (counted !== null || now > 180000) {
      __bench.print(JSON.stringify({ first: first, whole: { ms: Math.round(lastAt), rows: counted, emits: emits }, settled: memory() }));
      __bench.exit();
      return;
    }
    setTimeout(check, 500);
  };
  setTimeout(check, 500);
})();
