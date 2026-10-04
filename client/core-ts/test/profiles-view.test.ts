// The workspace's profiles in one list (src/views/profiles.ts): a shared one once, from its host while that one is read;
// one on a station only with that station; a shared subscription whose host is away, unusable and first.
import assert from "node:assert/strict";
import { test } from "node:test";
import { holdLanguage } from "../src/i18n.ts";
import { workspaceProfiles } from "../src/views/profiles.ts";

holdLanguage();

const A = "a".repeat(64);
const B = "b".repeat(64);
const profile = (id: string, extra: Record<string, unknown> = {}) => ({ id, name: id, access: { kind: "subscription" }, checkTone: "green", ...extra });
const station = (id: string, name: string, online: boolean, profiles: unknown[] | null) => ({ id, station: `w/${id}`, name, online, overview: profiles === null ? undefined : { sharing: true, profiles } });

test("a shared profile is listed once, from its host, with where it is signed in and who may use it", () => {
  const share = { id: "sh-1", host: A, allow: [A, B] };
  const view = workspaceProfiles([
    station(A, "studio", true, [profile("max", { share: { ...share, role: "host" } }), profile("local", { access: { kind: "env" } })]),
    station(B, "mini", true, [profile("sh-1", { share: { ...share, role: "user", reachable: true } })]),
  ]);
  assert.equal(view.items.length, 2);
  const shared = view.items.find((e: any) => e.shared);
  assert.equal(shared.key, "sh-1");
  assert.equal(shared.station, `w/${A}`, "its page is on its host");
  assert.equal(shared.profile.id, "max");
  assert.equal(shared.where, "登录在 studio · 只给 studio、mini");
  assert.equal(shared.usable, true);
  assert.deepEqual(shared.stations.map((s: any) => [s.name, s.allowed]), [["studio", true], ["mini", true]]);
  const local = view.items.find((e: any) => !e.shared);
  assert.equal(local.where, "只在 studio");
  assert.equal(local.canShare, true);
});

test("a shared subscription whose host is away comes from a copy, unusable, first", () => {
  const share = { id: "sh-1", host: A, allow: null };
  const view = workspaceProfiles([
    station(A, "studio", false, null),
    station(B, "mini", true, [profile("b-own", { access: { kind: "env" } }), profile("sh-1", { name: "Max", share: { ...share, role: "user", reachable: true } })]),
  ]);
  assert.equal(view.items[0].key, "sh-1");
  assert.equal(view.items[0].usable, false);
  assert.equal(view.items[0].editable, false);
  // Still listed as up by the cloud, but not answering the station borrowing it: away all the same.
  const late = workspaceProfiles([
    station(A, "studio", true, null),
    station(B, "mini", true, [profile("sh-1", { share: { ...share, role: "user", reachable: false } })]),
  ]);
  assert.equal(late.items[0].usable, false);
  assert.equal(late.loading, true, "studio is up and not read yet");
});
