// The workspace's profiles (views.ts #profilesView) made of what they read of each station's overview, kept beside it
// (schema.ts overviewProfiledOf, `station_part.profiled`), never of a decorated copy of the whole overview: on the
// workspace of real size (real-size.ts) the value is the one the whole overviews made, in Chinese and in English, and a
// core opened anew on the database reads no overview whole to make it, nor decorates one.
import assert from "node:assert/strict";
import { test } from "node:test";
import { conformTy } from "../src/conform.ts";
import { holdLanguage, setCurrent } from "../src/i18n.ts";
import { Output } from "../src/output.ts";
import * as present from "../src/present.ts";
import type { Topic } from "../src/protocol.ts";
import { workspaceProfiles } from "../src/views/profiles.ts";
import { work, workSince } from "../src/work.ts";
import { held, topicOf } from "./real-size-asked.ts";
import { setup } from "./views-rig.ts";

holdLanguage();
// deno-lint-ignore no-explicit-any
type J = any;

/// The profiles as they were made before: every station's whole overview decorated (present.ts) and put through its
/// shape (views.ts asShaped), its profiles and the machines' logins offered taken of that.
function madeOfWholes(t: Awaited<ReturnType<typeof held>>["t"], scope: string, c: present.Clock): J {
  const stations = t.views.stations(scope) as J[];
  const whole = new Map<string, J>();
  for (const s of stations) {
    const o = t.data.shared({ topic: "overview", station: s.address });
    const shaped = o === undefined ? null : conformTy("Overview", present.decorate({ topic: "overview", station: s.address }, structuredClone(o), c));
    whole.set(s.address, shaped !== null && "ok" in shaped ? shaped.ok : null);
  }
  const listed = workspaceProfiles(stations.map((s) => ({ station: s.address, id: s.id, name: s.name, online: s.online, joined: s.joined, overview: whole.get(s.address) })));
  const machineLogins = stations.flatMap((s) => {
    const logins = s.online ? ((whole.get(s.address)?.machineLogins ?? []) as J[]).filter((l) => l?.offered === true) : [];
    return logins.length > 0 ? [{ station: s.address, stationName: s.name, logins }] : [];
  });
  return { ...listed, machineLogins };
}

for (const lang of ["zh", "en"] as const) {
  test(`the workspace's profiles made of each station's kept part are the ones its whole overview made, in ${lang}`, async () => {
    setCurrent(lang);
    try {
      const { t: was } = await held(false);
      const topic = topicOf("profiles");
      // (the accounts whole, as an account's page and usage read them, `profilesWhole`, made by a core of its own on the
      // same database, at the moment this one makes them)
      was.store.runner.shutdown();
      const t = setup({ all: true, host: was.host });
      const wholeTopic: Topic = { topic: "profilesWhole", scope: topic.scope };
      t.store.subscribe(9, 9, wholeTopic, true);
      t.store.subscribe(8, 8, topic, true);
      await t.host.time.pass(100);
      const now = t.host.nowMs();
      const c: present.Clock = { now, offsetMin: t.host.utcOffsetMin(now) };
      const kept = t.store.value(wholeTopic);
      assert.ok(kept !== undefined && "ok" in kept, "the store holds the profiles whole");
      const before = madeOfWholes(t, String(topic.scope), c);
      assert.ok((before.items as J[]).length > 0);
      assert.deepEqual(kept.ok, before);
      // (and what the list sends, its rows, byte for byte what the whole went out as)
      const out = (v: J) => {
        const o = new Output().shape(topic, v, c, true);
        assert.ok("ok" in o);
        return JSON.stringify(o.ok);
      };
      const listed = t.store.value(topic);
      assert.ok(listed !== undefined && "ok" in listed);
      assert.equal(out(listed.ok), out(before));
    } finally {
      setCurrent("zh");
    }
  });
}

test("a core opened anew on a written database makes the workspace's profiles of the stations' kept rows, no overview read whole nor a part decorated", async () => {
  const { t } = await held(false);
  // (the same database, a core of its own: nothing parsed or made of it yet)
  const fresh = setup({ all: true, host: t.host });
  const profiles: Topic = { topic: "profiles", scope: "ws" };
  const before = { ...work };
  fresh.store.subscribe(1, 1, profiles, true);
  await fresh.host.time.pass(100);
  const v = fresh.store.value(profiles);
  assert.ok(v !== undefined && "ok" in v && ((v.ok as J).items as J[]).length > 0, "its profiles made");
  const spent = workSince(before);
  assert.equal(spent.overviewsRead, 0, "no station's whole overview read");
  assert.equal(spent.overviews, 0, "no station's whole overview decorated");
  // (each station's accounts' rows kept beside its part as the core before read the list: none decorated)
  assert.equal(spent.profiledParts, 0, "no station's part decorated");
  assert.equal(spent.profileRows, 0, "no station's rows made");
  assert.equal(spent.profileRowKept, (fresh.views.stations("ws") as J[]).length, "each station's rows taken as kept");
});
