// What a failure under the core says to people (error.ts): their words for what kind of failure it was, with when it
// failed; what the host, the network or a library said in its own words kept as the cause, for telemetry only.
import assert from "node:assert/strict";
import { test } from "node:test";
import { CoreError, HostError, asCoreError } from "../src/error.ts";
import { holdLanguage } from "../src/i18n.ts";

holdLanguage();

test("a host's own words are not said to people; what kind of failure it was is", () => {
  const net = asCoreError(new HostError("error sending request for url (https://app.still.fail/v1/x): connection refused"));
  assert.deepEqual([net.code, net.message, net.cause], ["host", "网络连接失败", "error sending request for url (https://app.still.fail/v1/x): connection refused"]);
  const other = asCoreError(new HostError("SQLITE_FULL: database or disk is full"));
  assert.deepEqual([other.message, other.cause], ["此设备上的操作失败", "SQLITE_FULL: database or disk is full"]);
  assert.equal(asCoreError(new TypeError("Cannot read properties of undefined (reading 'x')")).message, "此设备上的操作失败");
  // What the core words itself is said as it is, as are the words of a wake.
  assert.equal(asCoreError(HostError.said("此浏览器不支持 IndexedDB")).message, "此浏览器不支持 IndexedDB");
  assert.equal(asCoreError(new HostError("网络变了，重新连接")).message, "网络变了，重新连接");
  // Said with when it failed, by which its spans are found.
  const plain = CoreError.plainly("fonts", new HostError("dns error: failed to lookup address"));
  plain.stamped(Date.UTC(2026, 10, 2, 6, 46, 33), 480);
  assert.deepEqual([plain.code, plain.message], ["fonts", "网络连接失败（11月2日 14:46:33）"]);
  // A caller's words for what failed, over the kind.
  assert.equal(CoreError.plainly("screen", new Error("bad frame"), "无法解析屏幕数据").message, "无法解析屏幕数据");
});
