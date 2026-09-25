import assert from "node:assert/strict";
import { test } from "node:test";
import { slackManifest } from "../src/admin/slack-manifest.ts";
import { applySettings, SLACK_GROUPS, settingsOf } from "../src/chat/slack-apps.ts";

test("a new app has every permission group on", () => {
  const settings = settingsOf(slackManifest("ember"));
  assert.equal(settings.name, "ember");
  assert.ok(Object.values(settings.groups).every(Boolean));
});

test("turning a group off removes its scopes and events but keeps unknown ones", () => {
  const manifest = slackManifest("ember") as any;
  manifest.oauth_config.scopes.bot.push("commands");
  const next = applySettings(manifest, { groups: { files: false } as never, description: "", backgroundColor: "#112233" });
  const scopes: string[] = next.oauth_config.scopes.bot;
  for (const s of SLACK_GROUPS.files.scopes) assert.ok(!scopes.includes(s), s);
  assert.ok(scopes.includes("commands"));
  assert.ok(!next.settings.event_subscriptions.bot_events.includes("file_shared"));
  assert.equal(next.display_information.description, undefined);
  assert.equal(next.display_information.background_color, "#112233");
  assert.equal(settingsOf(next).groups.files, false);
  assert.equal(settingsOf(next).groups.reactions, true);
  const back = applySettings(next, { groups: { files: true } as never });
  assert.equal(settingsOf(back).groups.files, true);
});

test("the base group cannot be turned off", () => {
  const next = applySettings(slackManifest("ember"), { groups: { base: false } as never });
  assert.equal(settingsOf(next).groups.base, true);
});
