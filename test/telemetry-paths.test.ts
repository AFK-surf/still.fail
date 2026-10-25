import assert from "node:assert/strict";
import { test } from "node:test";
import { pathTemplate } from "../web/src/telemetry.ts";

test("paths sent to telemetry hold the routes' words and no ids, names or keys", () => {
  const cases: [string, string][] = [
    ["/w/ws1/s/st1/chats/12", "/w/:workspace/s/:station/chats/:thread"],
    ["/w/ws1/new", "/w/:workspace/new"],
    ["/w/ws1/settings/stations", "/w/:workspace/settings/stations"],
    ["/w/ws1/settings/stations/st1/footprint", "/w/:workspace/settings/stations/:station/footprint"],
    ["/w/ws1/s/st1/settings/accounts/p1", "/w/:workspace/s/:station/settings/accounts/:profile"],
    // A profile's key holds its account's email.
    ["/w/ws1/settings/profiles/account/sub%3Acodex%3Ame%40example.com", "/w/:workspace/settings/profiles/account/:profile"],
    ["/w/ws1/settings/profiles/add/anthropic", "/w/:workspace/settings/profiles/add/:id"],
    // A skill's name may be a customer's.
    ["/w/ws1/settings/memory/st1/skill/acme-brand", "/w/:workspace/settings/memory/:id/skill/:id"],
    ["/w/ws1/settings/vault/v1/item1", "/w/:workspace/settings/vault/:id/:id"],
    ["/w/ws1/settings/vault/all", "/w/:workspace/settings/vault/all"],
    ["/w/ws1/s/st1/services/job_9226a560", "/w/:workspace/s/:station/services/:id"],
    ["/w/ws1/s/st1/chats/12/history/ember%3Ac-1", "/w/:workspace/s/:station/chats/:thread/history/:id"],
    ["/o/ws1/st1/slack%3AC1", "/o/:id/:id/:id"],
    ["/Users/someone/notes.md", "/:id/:id/:id"],
    ["/", "/"],
  ];
  for (const [path, template] of cases) assert.equal(pathTemplate(path), template, path);
});
