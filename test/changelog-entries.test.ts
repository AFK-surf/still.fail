import assert from "node:assert/strict";
import { test } from "node:test";
import { partsOf, readMessage } from "../scripts/changelog.ts";

test("a commit's lines and fixes come from each paragraph of trailers, not only git's last one", () => {
  // As 4ae91923 and 36 others were written: the trailers git reads are only Co-Authored-By.
  const above = "Mobile station list: what runs low\n\nWhy, at length.\n\nSession: ember:c-1\nChangelog: 修复：手机上 station 列表写出剩多少\nFixes: FB-12\n\nCo-Authored-By: Claude <noreply@anthropic.com>\n";
  assert.deepEqual(readMessage(above), { text: ["修复：手机上 station 列表写出剩多少"], fixes: [12] });
  const last = "Pin chats\n\nChangelog: 新功能：会话可以置顶\nChangelog: 修复：置顶后顺序不变\nFixes: FB-3 FB-4\nSession: ember:c-2\n";
  assert.deepEqual(readMessage(last), { text: ["新功能：会话可以置顶", "修复：置顶后顺序不变"], fixes: [3, 4] });
  // A line folded onto the next, indented.
  assert.deepEqual(readMessage("Subject\n\nChangelog: 修复：很长的一行\n  接着写\nSession: ember:c-3\n").text, ["修复：很长的一行 接着写"]);
});

test("a subject, or prose that only mentions a trailer, says nothing", () => {
  // 43d5a869's subject.
  assert.deepEqual(readMessage("Changelog: the stable channel's is written once a release\n\nSession: ember:c-4\n"), { text: [], fixes: [] });
  const prose = "Subject\n\nThe line to write is\nChangelog: 修复：……\nin the trailers.\n\nCo-Authored-By: Claude <noreply@anthropic.com>\n";
  assert.deepEqual(readMessage(prose), { text: [], fixes: [] });
});

test("the words for other parts do not make a commit reach Android", () => {
  const words = (part: string) => [`client/i18n/catalog/en/${part}.json`, `client/i18n/catalog/zh/${part}.json`];
  // The desktop's dock (4fcde680), Slack's files on the station (3f92c1bf): their words are in the core.
  assert.deepEqual(partsOf(["apps/desktop/src/dock.ts", "scripts/native.ts", ...words("desktop")]), ["desktop"]);
  assert.deepEqual(partsOf(["station/src/slack/files.ts", ...words("station")]), ["station"]);
  assert.deepEqual(partsOf(["web/src/pages/Notifications.tsx", ...words("web-pages")]), ["web"]);
  // The core's logic and its words: every app.
  assert.deepEqual(partsOf(["client/core-ts/src/history.ts", ...words("core-logic")]), ["android", "web"]);
  // Words alone: the parts they are named for.
  assert.deepEqual(partsOf(words("android-settings")), ["android"]);
  assert.deepEqual(partsOf(words("web-main")), ["web"]);
  assert.deepEqual(partsOf(words("station")), ["station"]);
  assert.deepEqual(partsOf(words("common")), ["android", "web"]);
});

test("tests, the clients' types and what Android does not carry reach no app by themselves", () => {
  const notCarried = /^client\/iroh-wasm\/|^client\/core-ts\/(test|bench|harness|side)\/|^client\/core-ts\/src\/hosts\/(web|node|node-iroh|node-sql)\.ts$/;
  // A web fix whose schema change regenerated Android's types (31f155ec).
  const shapes = ["client/core-ts/src/shapes/schema.ts", "apps/android/app/src/main/kotlin/fail/still/android/data/Shapes.kt", "web/src/core/shapes.ts"];
  assert.deepEqual(partsOf([...shapes, "web/src/cloud/CloudApp.tsx"], notCarried), ["web"]);
  assert.deepEqual(partsOf(["apps/android/app/src/androidTest/kotlin/A.kt", "station/src/x.ts"], notCarried), ["station"]);
  assert.deepEqual(partsOf(["client/core-ts/src/hosts/web.ts"], notCarried), ["web"]);
  assert.deepEqual(partsOf(["client/shell/src/lib.rs"], notCarried), ["android"]);
  // Only those: a commit carrying the line for the ones before it reaches where its files are (10f9b815).
  assert.deepEqual(partsOf(["client/core-ts/test/views.test.ts"], notCarried), ["android", "web"]);
  assert.deepEqual(partsOf(["apps/android/app/src/androidTest/kotlin/A.kt"], notCarried), ["android"]);
  // The site and the docs need no release.
  assert.deepEqual(partsOf(["docs/changelog.md", ".github/workflows/pipeline.yml"], notCarried), []);
});
