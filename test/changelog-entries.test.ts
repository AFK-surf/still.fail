import assert from "node:assert/strict";
import { test } from "node:test";
import { partsOf, readMessage, refused, saysNothing } from "../scripts/changelog.ts";

test("a commit's lines and fixes come from each paragraph of trailers, not only git's last one", () => {
  // As 4ae91923 and 36 others were written: the trailers git reads are only Co-Authored-By.
  const above = "Mobile station list: what runs low\n\nWhy, at length.\n\nSession: ember:c-1\nChangelog: 修复：手机上 station 列表写出剩多少\nFixes: FB-12\n\nCo-Authored-By: Claude <noreply@anthropic.com>\n";
  assert.deepEqual(readMessage(above), { text: ["修复：手机上 station 列表写出剩多少"], fixes: [12], parts: [] });
  const last = "Pin chats\n\nChangelog: 新功能：会话可以置顶\nChangelog: 修复：置顶后顺序不变\nFixes: FB-3 FB-4\nSession: ember:c-2\n";
  assert.deepEqual(readMessage(last), { text: ["新功能：会话可以置顶", "修复：置顶后顺序不变"], fixes: [3, 4], parts: [] });
  // A line folded onto the next, indented.
  assert.deepEqual(readMessage("Subject\n\nChangelog: 修复：很长的一行\n  接着写\nSession: ember:c-3\n").text, ["修复：很长的一行 接着写"]);
});

test("a subject, or prose that only mentions a trailer, says nothing", () => {
  // 43d5a869's subject.
  assert.deepEqual(readMessage("Changelog: the stable channel's is written once a release\n\nSession: ember:c-4\n"), { text: [], fixes: [], parts: [] });
  const prose = "Subject\n\nThe line to write is\nChangelog: 修复：……\nin the trailers.\n\nCo-Authored-By: Claude <noreply@anthropic.com>\n";
  assert.deepEqual(readMessage(prose), { text: [], fixes: [], parts: [] });
});

test("a Changelog trailer saying there is nothing to tell is refused", () => {
  for (const nothing of ["none", "None.", "n/a", "无", "-"]) {
    assert.deepEqual(saysNothing(`Subject\n\nSession: ember:c-5\nChangelog: ${nothing}\nFixes: FB-7\n`), [nothing]);
  }
  assert.deepEqual(saysNothing("Subject\n\nChangelog: 修复：none 不再出现在更新提示里\n"), []);
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
  const shapes = ["client/core-ts/src/shapes/schema.ts", "apps/android/shared/src/main/kotlin/fail/still/android/data/Shapes.kt", "web/src/core/shapes.ts"];
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

test("the mbui app reaches Android and the desktop; its desktop's own pages and each host's code, the one they are for", () => {
  // The desktop's ⌘K (3605d692) and its side panel's tabs (54186c3a), with their tapes, kept answers and the script that
  // makes them: the desktop alone, where they had been on Android's tab.
  const desk = ["apps/mbui/src/sfdesk/switcher.mbt", "apps/mbui/src/sfapp/wide_switcher.mbt", "apps/mbui/src/sfapp/settings/web_vault.mbt"];
  const nothing = ["apps/mbui/e2e/traces/wide-new-chat.trace", "apps/mbui/src/sfkept/kept.mbt", "apps/mbui/src/sffilm/main.mbt", "apps/mbui/src/sfapp/search_fixture.mbt", "apps/mbui/src/sfapp/wide_panel_wbtest.mbt", "apps/mbui/scripts/motion/wide-switcher.drive", "apps/mbui/detlint.json", "client/core-ts/scripts/kept-answers.ts"];
  assert.deepEqual(partsOf([...desk, ...nothing]), ["desktop"]);
  assert.deepEqual(partsOf(["apps/mbui/src/sfapp/chat.mbt", ...nothing]), ["android", "desktop"]);
  assert.deepEqual(partsOf(["apps/mbui/mbui/src/ui/text.mbt"]), ["android", "desktop"]);
  assert.deepEqual(partsOf(["apps/mbui/android/app/src/main/java/dev/mbui/Crashes.java", "apps/mbui/mbui/src/host/android_host.c"]), ["android"]);
  assert.deepEqual(partsOf(["apps/mbui/mbui/src/host/mac_app.m", "apps/mbui/src/host/win_core.c"]), ["desktop"]);
  assert.deepEqual(partsOf(["apps/mbui/mbui/src/host/ios_app.m", "apps/mbui/ios/Info.plist"]), []);
});

test("a commit's agent says the parts people see it in; one that does not, or names none of them, is refused", () => {
  // The desktop's side panel's tabs (54186c3a), in code the Android app builds too: the agent says it is the desktop's.
  const desk = "mbui desktop: the chat's side panel's tabs\n\nChangelog: 桌面版（mbui）聊天侧栏的标签页改由 core 保存\nChangelog-parts: desktop\n\nCo-Authored-By: Claude <noreply@anthropic.com>\n";
  assert.deepEqual(readMessage(desk).parts, ["desktop"]);
  assert.deepEqual(refused(desk), []);
  assert.deepEqual(readMessage("Subject\n\nChangelog: 修复：……\nChangelog-parts: Android, web\n").parts, ["android", "web"]);
  // The site's: no release.
  assert.deepEqual(refused("Site: plainly\n\nChangelog: 官网首屏只留一句\nChangelog-parts: none\n"), []);
  // Nothing to tell, nothing to say.
  assert.deepEqual(refused("Refactor\n\nSession: ember:c-6\n"), []);
  const unsaid = (m: string) => refused(m).filter((why) => why.startsWith("no Changelog-parts")).length;
  assert.equal(unsaid("Subject\n\nChangelog: 修复：……\nSession: ember:c-7\n"), 1);
  assert.equal(unsaid("Subject\n\nFixes: FB-9\n"), 1);
  assert.equal(refused("Subject\n\nChangelog: 修复：……\nChangelog-parts: mac, desktop\n").length, 1);
  assert.equal(refused("Subject\n\nChangelog: none\nChangelog-parts: web\n").length, 1);
});
