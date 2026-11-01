// A connect's Slack app (chat/slack_apps.rs and chat/slack_apps/tests.rs, ported): manifests and their permission
// groups, the create-app link, and Slack's app API with a person's configuration tokens against a stand-in for Slack.
import assert from "node:assert/strict";
import { test } from "node:test";
import {
  type ConfigToken,
  SLACK_GROUPS,
  SlackApps,
  applySettings,
  createAppUrl,
  settingsOf,
  shapeOf,
  slackError,
  slackManifest,
  upsertToken,
  withSocketMode,
  withStopEvent,
} from "../src/slack/apps.ts";
import { SlackApiError, SlackClient } from "../src/slack/web.ts";
import { FakeSlack } from "./slack-fake.ts";

type Json = any;
const strings = (v: Json): string[] => (Array.isArray(v) ? v : []);

test("a new app has every permission group on", () => {
  const manifest = slackManifest("ember");
  const settings = settingsOf(manifest);
  assert.equal(settings.name, "ember");
  assert.equal(Object.keys(settings.groups).length, SLACK_GROUPS.length);
  assert.ok(Object.values(settings.groups).every((on) => on));
  assert.ok(manifest.settings.event_subscriptions.bot_events.includes("agent_session_stopped"));
  assert.ok(manifest.features.agent_view.agent_description);
  const old = structuredClone(manifest);
  old.settings.event_subscriptions.bot_events = old.settings.event_subscriptions.bot_events.filter((e: string) => e !== "agent_session_stopped");
  assert.ok(applySettings(old, {}).settings.event_subscriptions.bot_events.includes("agent_session_stopped"), "an existing app gets it when saved");
});

test("turning a group off removes its scopes and events but keeps unknown ones", () => {
  const manifest = slackManifest("ember");
  manifest.oauth_config.scopes.bot.push("workflow.steps:execute");
  const next = applySettings(manifest, { groups: { files: false }, description: "", backgroundColor: "#112233" });
  const scopes = strings(next.oauth_config.scopes.bot);
  for (const s of SLACK_GROUPS.find((g) => g.id === "files")!.scopes) assert.ok(!scopes.includes(s), s);
  assert.ok(scopes.includes("workflow.steps:execute"));
  assert.ok(!strings(next.settings.event_subscriptions.bot_events).includes("file_shared"));
  assert.equal(next.display_information.description, undefined);
  assert.equal(next.display_information.background_color, "#112233");
  assert.equal(settingsOf(next).groups.files, false);
  assert.equal(settingsOf(next).groups.reactions, true);
  assert.equal(manifest.oauth_config.scopes.bot.includes("files:read"), true, "the manifest given stays as it was");
  const back = applySettings(next, { groups: { files: true } });
  assert.equal(settingsOf(back).groups.files, true);
});

test("the base group cannot be turned off", () => {
  assert.equal(settingsOf(applySettings(slackManifest("ember"), { groups: { base: false } })).groups.base, true);
});

test("an existing plain bot gets the agent feature and stop subscription without losing its settings", () => {
  const old = slackManifest("ember");
  delete old.features.agent_view;
  old.settings.event_subscriptions.bot_events = ["app_mention", "an_unknown_event"];
  const next = withStopEvent(old);
  assert.ok(next);
  assert.deepEqual(next.settings.event_subscriptions.bot_events, ["app_mention", "an_unknown_event", "agent_session_stopped"]);
  assert.deepEqual(next.oauth_config, old.oauth_config);
  assert.deepEqual(next.features.agent_view, { agent_description: old.display_information.description });
  assert.equal(old.features.agent_view, undefined);
  assert.deepEqual(old.settings.event_subscriptions.bot_events, ["app_mention", "an_unknown_event"]);
  assert.equal(withStopEvent(next), null);
  assert.equal(withStopEvent(withSocketMode(old, false)), null);
});

test("an already subscribed plain bot still gets an agent view; an existing assistant view is kept", () => {
  const old = slackManifest("ember");
  delete old.features.agent_view;
  const next = withStopEvent(old);
  assert.ok(next?.features.agent_view);
  assert.deepEqual(next.settings.event_subscriptions, old.settings.event_subscriptions);
  old.features.assistant_view = { assistant_description: "Existing assistant" };
  assert.equal(withStopEvent(old), null);
  old.settings.event_subscriptions.bot_events = ["app_mention"];
  const assistant = withStopEvent(old);
  assert.deepEqual(assistant.features.assistant_view, old.features.assistant_view);
  assert.equal(assistant.features.agent_view, undefined);
});

test("automatic and manual edits of the same app keep both changes", async () => {
  const fake = await FakeSlack.start();
  let manifest = slackManifest("before");
  manifest.settings.event_subscriptions.bot_events = ["app_mention"];
  fake.answer("apps.manifest.export", () => ({ ok: true, manifest }));
  fake.answer("apps.manifest.update", (s) => {
    manifest = JSON.parse(s.params.manifest!);
    return { ok: true };
  });
  const apps = new SlackApps({ client: new SlackClient(fake.base), load: () => [token("me", "T1", "test", Date.now() + 3_600_000)], save: () => {} });
  try {
    await Promise.all([
      apps.editManifest("me", "A1", withStopEvent),
      apps.editManifest("me", "A1", (m) => applySettings(m, { name: "after" })),
    ]);
    assert.equal(manifest.display_information.name, "after");
    assert.ok(manifest.settings.event_subscriptions.bot_events.includes("agent_session_stopped"));
    assert.equal(fake.calls("apps.manifest.update").length, 2);
  } finally {
    await fake.close();
  }
});

test("an old app gets a bot user and its messages tab on any change", () => {
  const next = applySettings({ display_information: { name: "old" }, features: { app_home: { home_tab_enabled: true } } }, { name: " new " });
  assert.equal(next.display_information.name, "new");
  assert.deepEqual(next.features.bot_user, { display_name: " new ", always_online: true });
  assert.deepEqual(next.features.app_home, { home_tab_enabled: true, messages_tab_enabled: true, messages_tab_read_only_enabled: false });
});

test("socket mode off drops the events, and on brings back those of the groups on", () => {
  const manifest = applySettings(slackManifest("ember"), { groups: { files: false } });
  manifest.settings.event_subscriptions.bot_events.unshift("custom_event");
  const off = withSocketMode(manifest, false);
  assert.equal(off.settings.socket_mode_enabled, false);
  assert.equal(off.settings.event_subscriptions, undefined);
  assert.deepEqual([off.settings.interactivity, withSocketMode(off, true).settings.interactivity], [{ is_enabled: false }, { is_enabled: true }]);
  // An app made before cards gets them on its next save; one without Socket Mode would need a URL, so it does not.
  const before = slackManifest("ember");
  before.settings.interactivity = { is_enabled: false };
  assert.deepEqual([applySettings(before, {}).settings.interactivity, applySettings(off, {}).settings.interactivity], [{ is_enabled: true }, { is_enabled: false }]);
  const on = withSocketMode(manifest, true);
  const events = strings(on.settings.event_subscriptions.bot_events);
  assert.equal(events[0], "custom_event", "events ember does not know stay");
  assert.ok(events.includes("app_mention") && events.includes("reaction_added"));
  assert.ok(!events.includes("file_shared"), "a group off has no events");
  // Off first (as an app is made), then on: the groups' events come back.
  assert.ok(strings(withSocketMode(off, true).settings.event_subscriptions.bot_events).includes("message.im"));
});

test("the create-app link carries the manifest", () => {
  const url = createAppUrl("ember 机器人");
  const prefix = "https://api.slack.com/apps?new_app=1&manifest_json=";
  assert.ok(url.startsWith(prefix));
  const encoded = url.slice(prefix.length);
  assert.ok(!encoded.includes(" ") && !encoded.includes("{") && !encoded.includes('"'));
  const manifest = JSON.parse(decodeURIComponent(encoded));
  assert.deepEqual(manifest, slackManifest("ember 机器人"));
  assert.equal(manifest.settings.socket_mode_enabled, true);
  assert.deepEqual(manifest.settings.interactivity, { is_enabled: true }, "cards' buttons come over the socket");
  assert.deepEqual(slackManifest("x", null, "https://e/cb").oauth_config.redirect_urls, ["https://e/cb"]);
  // Field order as the Rust station writes it (serde_json's preserve_order).
  assert.deepEqual(Object.keys(manifest), ["display_information", "features", "oauth_config", "settings"]);
});

test("shapes show token kinds and never values", () => {
  assert.deepEqual(shapeOf({ app_id: "A1", credentials: { client_secret: "s3cret", token: "xapp-1-abc" }, n: 1, on: true }), {
    app_id: "string",
    credentials: { client_secret: "string", token: "xapp-…" },
    n: "number",
    on: "boolean",
  });
});

test("a person's token for a workspace replaces their old one, keeping who it is", () => {
  const owner = { team: "Acme", teamDomain: null, teamIcon: null, user: "Ada", email: null, image: null };
  const t = (by: string, team: string, access: string, o?: typeof owner): ConfigToken => ({ accessToken: access, refreshToken: "r", expiresAt: 1, teamId: team, by, ...(o ? { owner: o } : {}) });
  const tokens = upsertToken([t("me", "T1", "a", owner), t("you", "T1", "b")], t("me", "T1", "c"));
  assert.deepEqual(tokens, [t("me", "T1", "c", owner), t("you", "T1", "b")]);
  assert.equal(upsertToken(tokens, t("me", "T2", "d")).length, 3);
});

const token = (by: string, team: string, access: string, expiresAt: number): ConfigToken => ({ accessToken: access, refreshToken: `refresh-${access}`, expiresAt, teamId: team, by });

test("apps are reached with the person's token that owns them, rotating one about to expire", async () => {
  const fake = await FakeSlack.start();
  fake.answer("tooling.tokens.rotate", { ok: true, token: "fake-t1-next", refresh_token: "fake-r1-next", exp: 2_000_000_000, team_id: "T1" });
  // The app is T2's: T1's token is refused.
  fake.answer("apps.manifest.export", (s) => (s.auth === "fake-t2" ? { ok: true, manifest: { display_information: { name: "bot" } } } : { ok: false, error: "app_not_found" }));
  fake.answer("apps.manifest.validate", { ok: false, error: "invalid_manifest", errors: [{ pointer: "/display_information/name", message: "too long" }] });
  fake.answer("apps.icon.set", { ok: true });
  fake.answer("apps.manifest.create", { ok: true, app_id: "A9", credentials: { client_id: "c1", client_secret: "fake-secret" } });
  let tokens = [token("me", "T1", "fake-t1", Date.now() + 60_000), token("me", "T2", "fake-t2", Date.now() + 3_600_000), token("someone", "T3", "fake-t3", Date.now() + 3_600_000)];
  const apps = new SlackApps({
    client: new SlackClient(fake.base),
    load: () => tokens,
    save: (next) => {
      tokens = [...tokens.filter((t) => !(t.by === next.by && t.teamId === next.teamId)), next];
    },
  });
  try {
    assert.ok(apps.configured("me") && !apps.configured("stranger"));

    const manifest = await apps.exportManifest("me", "A2");
    assert.equal(manifest.display_information.name, "bot");
    assert.deepEqual(
      fake.seen.map((s) => [s.method, s.auth]),
      [
        ["tooling.tokens.rotate", ""],
        ["apps.manifest.export", "fake-t1-next"],
        ["apps.manifest.export", "fake-t2"],
      ],
      "T1's token was about to expire: rotated first, then tried; T2's owns the app",
    );
    assert.equal(fake.seen[0]!.params.refresh_token, "refresh-fake-t1");
    const rotated = tokens.find((t) => t.teamId === "T1")!;
    assert.deepEqual([rotated.accessToken, rotated.refreshToken, rotated.expiresAt, rotated.by], ["fake-t1-next", "fake-r1-next", 2_000_000_000_000, "me"]);

    // Its owner is known now: one call.
    fake.seen = [];
    await apps.exportManifest("me", "A2");
    assert.deepEqual(fake.seen.map((s) => s.auth), ["fake-t2"]);

    // Slack's refusals come with their code and details, in words people can act on.
    const refused = await apps.updateManifest("me", "A2", {}).catch((e) => e);
    assert.ok(refused instanceof SlackApiError);
    assert.equal(refused.code, "invalid_manifest");
    assert.equal(slackError(refused, "zh"), "manifest 无效：/display_information/name too long");
    assert.equal(refused.message, 'apps.manifest.validate: invalid_manifest [{"pointer":"/display_information/name","message":"too long"}]');

    fake.seen = [];
    await apps.setIcon("me", "A2", new Uint8Array([0x89, 0x50, 0x4e, 0x47]), "image/png");
    const icon = fake.seen[0]!;
    assert.ok(icon.contentType.startsWith("multipart/form-data"), icon.contentType);
    assert.ok(icon.body.includes('filename="icon.png"') && icon.body.includes('name="app_id"'));
    assert.equal(icon.params.app_id, "A2");

    assert.deepEqual(await apps.createApp("me", "T2", slackManifest("ember")), { appId: "A9", clientId: "c1", clientSecret: "fake-secret" });

    const none = await apps.exportManifest("stranger", "A2").catch((e) => e);
    assert.equal(none.message, "尚未添加 Slack App 配置 token");
    assert.equal(slackError(none, "en") !== none.message, true, "said in whoever asked's language");
    assert.equal((await apps.createApp("me", "T9", {}).catch((e) => e)).message, "此 Slack 工作区没有配置 token");
  } finally {
    await fake.close();
  }
});

test("two calls needing a rotation at once rotate once: the refresh token works once", async () => {
  const fake = await FakeSlack.start();
  let rotations = 0;
  fake.answer("tooling.tokens.rotate", async () => {
    rotations++;
    await new Promise((r) => setTimeout(r, 30));
    return { ok: true, token: "next", refresh_token: "r-next", exp: 2_000_000_000, team_id: "T1" };
  });
  fake.answer("apps.manifest.export", { ok: true, manifest: {} });
  let tokens = [token("me", "T1", "old", Date.now())];
  const apps = new SlackApps({ client: new SlackClient(fake.base), load: () => tokens, save: (t) => (tokens = [t]) });
  try {
    await Promise.all([apps.exportManifest("me", "A1"), apps.exportManifest("me", "A2")]);
    assert.equal(rotations, 1);
    assert.deepEqual(fake.calls("apps.manifest.export").map((s) => s.auth), ["next", "next"]);
  } finally {
    await fake.close();
  }
});
