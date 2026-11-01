import assert from "node:assert/strict";
import { test } from "node:test";
import { AdbActivity } from "../src/adb/activity.ts";

function packet(name: string, id = 0, payload = ""): Buffer {
  const data = Buffer.from(payload);
  const head = Buffer.alloc(24);
  const command = Buffer.from(name).readUInt32LE();
  head.writeUInt32LE(command, 0);
  head.writeUInt32LE(id, 4);
  head.writeUInt32LE(data.length, 12);
  head.writeUInt32LE(~command >>> 0, 20);
  return Buffer.concat([head, data]);
}

test("adb use is service activity, not reconnects or the station's maintenance", () => {
  const used: boolean[] = [];
  const activity = new AdbActivity("fail.still.android", (force) => used.push(force));
  const bytes = Buffer.concat([
    packet("CNXN", 0, "host::features=shell_v2\0"),
    packet("OPEN", 1, "shell,v2,raw:STILLFAIL_ADB_KEEP=1 pm grant fail.still.android android.permission.WRITE_SECURE_SETTINGS\0"),
    packet("WRTE", 1, "background"),
    packet("CLSE", 1),
    packet("OPEN", 2, "shell,v2,raw:STILLFAIL_ADB_KEEP=1 cmd deviceidle whitelist +fail.still.android\0"),
    packet("OPEN", 3, "shell,v2,raw:input tap 50 50\0"),
    packet("WRTE", 3, "a command"),
    packet("OKAY", 3),
    packet("CLSE", 3),
    packet("WRTE", 3, "after close"),
  ]);
  // Headers and service names can be split at any byte; several packets can also come in one chunk.
  for (let at = 0; at < bytes.length; at += 7) activity.take(bytes.subarray(at, at + 7));
  assert.deepEqual(used, [true, false, false, true]);
});

test("an older phone's encrypted transport is not guessed to be activity", () => {
  const used: boolean[] = [];
  const activity = new AdbActivity("fail.still.android", (force) => used.push(force));
  activity.take(Buffer.concat([packet("CNXN"), packet("STLS"), packet("OPEN", 1, "shell:id\0")]));
  assert.deepEqual(used, []);
});

test("an agent running the same command as background maintenance is still use", () => {
  const used: boolean[] = [];
  const activity = new AdbActivity("fail.still.android", (force) => used.push(force));
  activity.take(packet("OPEN", 1, "shell,v2,raw:pm grant fail.still.android android.permission.WRITE_SECURE_SETTINGS\0"));
  assert.deepEqual(used, [true]);
});
