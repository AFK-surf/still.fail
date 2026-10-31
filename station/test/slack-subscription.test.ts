import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { ConfigFile } from "../src/ops/config.ts";
import { makeConnections } from "../src/slack/index.ts";
import { slackManifest } from "../src/slack/apps.ts";
import { SlackClient } from "../src/slack/web.ts";
import { Store } from "../src/store/store.ts";
import { FakeSlack, bot } from "./slack-fake.ts";

test("an existing connected Slack app gets the stop event when a configuration token becomes available", async () => {
  const data = mkdtempSync(join(tmpdir(), "stop-sub-"));
  writeFileSync(join(data, "config.json"), JSON.stringify({ connects: [{ id: "cl", createdBy: { id: "owner@example.test", name: "Owner" }, slack: { appToken: "xapp-test", botToken: "xoxb-test" } }] }));
  const fake = await FakeSlack.start();
  bot(fake);
  fake.answer("bots.info", { ok: true, bot: { app_id: "A1" } });
  let manifest = slackManifest("old");
  manifest.settings.event_subscriptions.bot_events = ["app_mention", "custom_event"];
  let exports = 0;
  fake.answer("apps.manifest.export", () => (++exports === 1 ? { ok: false, error: "temporarily_unavailable" } : { ok: true, manifest }));
  fake.answer("apps.manifest.update", (s) => {
    manifest = JSON.parse(s.params.manifest!);
    return { ok: true };
  });
  const config = new ConfigFile(data);
  const store = Store.open(":memory:");
  const slack = makeConnections({ data, config, store, receive: async () => {}, bound: () => true, client: new SlackClient(fake.base) });
  try {
    await slack.reconcile();
    await fake.until("connected", () => slack.state("cl")?.state === "connected");
    assert.equal(fake.calls("apps.manifest.export").length, 0, "there is no configuration token yet");
    config.update((raw) => {
      raw.slackConfigTokens = [{ by: "another@example.test", teamId: "T1", accessToken: "test", refreshToken: "refresh", expiresAt: Date.now() + 3_600_000 }];
    });
    await slack.reconcile();
    assert.equal(fake.calls("apps.manifest.export").length, 0, "another person's token is not used");
    config.update((raw) => { raw.slackConfigTokens.push({ by: "owner@example.test", teamId: "T1", accessToken: "test", refreshToken: "refresh", expiresAt: Date.now() + 3_600_000 }); });
    await fake.until("the first attempt", () => exports === 1);
    // No timer keeps asking Slack: the next real turn tries the failed setup again.
    slack.chat("cl")!.working!({ channel: "C1", threadTs: "1.1" }, "1.1", "working");
    await fake.until("the app's manifest updated", () => fake.calls("apps.manifest.update").length === 1);
    assert.deepEqual(manifest.settings.event_subscriptions.bot_events, ["app_mention", "custom_event", "agent_session_stopped"]);
    assert.equal(manifest.display_information.name, "old");
    assert.equal(fake.calls("apps.manifest.update")[0]!.params.app_id, "A1");
    await slack.reconcile();
    assert.equal(fake.calls("apps.manifest.update").length, 1, "reconciling does not write it again");
  } finally {
    await slack.close();
    store.close();
    await fake.close();
    rmSync(data, { recursive: true, force: true });
  }
});

test("an app is not changed after its connect is handed to another owner", async () => {
  const data = mkdtempSync(join(tmpdir(), "stop-owner-"));
  writeFileSync(join(data, "config.json"), JSON.stringify({
    connects: [{ id: "cl", createdBy: { id: "old@example.test" }, slack: { appToken: "xapp-test", botToken: "xoxb-test", appId: "A1" } }],
    slackConfigTokens: [{ by: "old@example.test", teamId: "T1", accessToken: "test", refreshToken: "refresh", expiresAt: Date.now() + 3_600_000 }],
  }));
  const fake = await FakeSlack.start();
  bot(fake);
  let release!: () => void;
  const held = new Promise<void>((resolve) => (release = resolve));
  const manifest = slackManifest("old");
  manifest.settings.event_subscriptions.bot_events = ["app_mention"];
  fake.answer("apps.manifest.export", async () => { await held; return { ok: true, manifest }; });
  const config = new ConfigFile(data);
  const store = Store.open(":memory:");
  const slack = makeConnections({ data, config, store, receive: async () => {}, bound: () => true, client: new SlackClient(fake.base) });
  try {
    await slack.reconcile();
    await fake.until("the manifest is being read", () => fake.calls("apps.manifest.export").length === 1);
    config.update((raw) => { raw.connects[0].createdBy = { id: "new@example.test" }; });
    release();
    await slack.close();
    assert.equal(fake.calls("apps.manifest.update").length, 0);
  } finally {
    release();
    await slack.close();
    store.close();
    await fake.close();
    rmSync(data, { recursive: true, force: true });
  }
});
