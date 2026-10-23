// The core's stand-in for core/exit_test.m: what the UI says starts a task that tells the test it runs (a message,
// on the core's thread, which the test holds there). Plain ES2017, not bundled.
var client = 0;

globalThis.__stillfail = {
  start: function () {},
  connect: function () {
    client = 1;
    return client;
  },
  complete: function () {},
  receive: function (c, json) {
    __native.emit(client, JSON.stringify({ running: JSON.parse(json).n }));
  },
  receiveBytes: function () {},
};
