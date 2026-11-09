// The host keeps sending input from within each input callback. The timer is
// due before that stream starts, so it must run while input is still arriving.
globalThis.__stillfail_timer = function (id) {
  __native.emit(1, id === 1 ? "timer" : "later");
};

globalThis.__stillfail = {
  start() {},
  connect: () => 1,
  receive(_client, message) {
    if (message === "start") __native.emit(1, "ready");
    else if (message === "begin") {
      __native.setTimer(1, 0);
      __native.emit(1, "armed");
    } else if (message === "input") __native.emit(1, "input");
    else if (message === "order") {
      // The host posts input before this task schedules its continuation.
      __native.emit(1, "queue-earlier");
      __native.setTimer(2, 0);
    } else if (message === "earlier") __native.emit(1, "earlier");
  },
  complete() {},
};
