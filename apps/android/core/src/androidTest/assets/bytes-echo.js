// A call's bytes there and back through the real engine (BytesBesideTest.kt): `echo` answers `{ok: {size}}` with the
// bytes it was given beside it (__stillfail.receiveBytes, __native.emitBytes), each one turned (255 - b) so what comes
// back is not what was sent by mistake; a call with none answers `{ok: {size: null}}` and nothing beside it.
globalThis.__stillfail = {
  start: function () {},
  connect: function () {},
  complete: function () {},
  receive: function (client, json) {
    var m = JSON.parse(json);
    if (m.call !== undefined) __native.emit(client, JSON.stringify({ id: m.id, ok: { size: null } }));
  },
  receiveBytes: function (client, json, bytes) {
    var m = JSON.parse(json);
    var given = new Uint8Array(bytes);
    var back = new Uint8Array(given.length);
    for (var i = 0; i < given.length; i++) back[i] = 255 - given[i];
    __native.emitBytes(client, JSON.stringify({ id: m.id, ok: { size: given.length } }), back.buffer);
  },
};
