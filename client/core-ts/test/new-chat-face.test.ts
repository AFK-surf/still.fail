// A new chat's page (`newChat`) carries what it draws: its model control as it is drawn closed (NewChatPick), worked out
// of the one station it starts on. The control's panel is the `pick` topic, asked as it opens. In Hermes on a Mac Studio
// (5 stations up, the first open of a workspace landing on a new chat, 2026-11-11) `newChat` made the whole panel for
// the page: every station's models (`stationsWhole`, 5.06 ms), every option annotated with how it runs picked, the
// configurations used most, the starred, the makers (5.7 ms more), 10.7 ms of its value; and made it again on every
// change of any station's overview. Counted here, never timed (src/work.ts).
import assert from "node:assert/strict";
import { test } from "node:test";
import { Choose } from "../src/choose.ts";
import { holdLanguage } from "../src/i18n.ts";
import { EVICT_AFTER_MS } from "../src/store.ts";
import { work, workSince } from "../src/work.ts";
import { CHAT, UP, fixture, more, OPENS, records } from "./real-size.ts";
import { setup } from "./views-rig.ts";

holdLanguage();

// deno-lint-ignore no-explicit-any
type J = any;

const NEW = { topic: "newChat", scope: "ws" };

/// The workspace of real size (real-size.ts: 5 stations, 4 up, each with its profiles and dozens of models) on a rig
/// with a new chat's and a model control's topics, the device's data written as a device's sync writes it.
async function workspace() {
  const t = setup({ all: true, owners: ({ host, store, data, views }) => [new Choose({ store, data, now: () => host.nowMs(), agent: (s, k) => views.agent(s, k) })] });
  const base = t.host.nowMs();
  for (const [table, k, value] of records(base)) t.data.put(table, k, value);
  t.store.subscribe(1, 1, NEW, true);
  for (let round = 0; round < 2; round++) {
    for (const [topic, value] of [...fixture(base, OPENS), ...more(base)]) t.set(topic, value);
    await t.host.time.pass(100);
  }
  t.host.takeEmitted();
  return t;
}

/// The value the subscription `id` was last sent whole.
const sent = (t: ReturnType<typeof setup>, id: number): J => {
  let v: J = undefined;
  for (const [, m] of t.host.takeEmitted()) if ((m as J).id === id && "value" in (m as J)) v = (m as J).value;
  return v;
};

test("a_new_chats_page_asked_anew_makes_the_models_of_the_station_it_starts_on_alone_and_annotates_no_option", async () => {
  const t = await workspace();
  // Let go of and asked again once its topic is gone: made anew, as at a workspace's first open in a run.
  t.store.unsubscribe(1, 1);
  await t.host.time.pass((EVICT_AFTER_MS * 5) / 4, 1000);
  assert.ok(!t.store.liveTopics().some((topic) => topic.topic === "newChat"), "let go");
  // (each time the page is made, counted: made as it is first asked and again as what it reads comes in)
  let makes = 0;
  const compute = t.router.compute.bind(t.router);
  t.router.compute = (topic) => {
    if (topic.topic === "newChat") makes++;
    return compute(topic);
  };
  const from = { ...work };
  t.store.subscribe(1, 2, NEW, true);
  await t.host.time.pass(100);
  const page = sent(t, 2);
  const made = workSince(from);
  assert.ok(makes > 0);
  // (the real path: a station up it starts on, its control drawn)
  assert.equal(page.station.station, CHAT.station);
  assert.equal(typeof page.pick.valueOption.name, "string");
  // Each time, its station's models once (every profile enabled there serves the workspace: what its page serves and
  // its control runs on are one list; main: every station's up besides, `stationsWhole`'s, and every option annotated).
  assert.equal(made.models, makes, "one station's models");
  assert.equal(made.annotated, 0, "no option annotated");
  assert.ok(!t.store.liveTopics().some((topic) => topic.topic === "stationsWhole" || topic.topic === "pick"), "no station whole, no panel");
});

test("another_stations_overview_changing_makes_the_new_chats_page_of_its_one_stations_models_alone", async () => {
  // (a station the page does not start on: its accounts' allowance read anew. Its row is made again, and the page with
  // it; main made every station's models again for it, `stationsWhole`'s, and the whole panel)
  const t = await workspace();
  const from = { ...work };
  const other = UP.find((s) => s !== CHAT.station)!;
  const ov = t.data.shared({ topic: "overview", station: other }) as J;
  t.set({ topic: "overview", station: other }, { ...ov, profiles: ov.profiles.map((p: J) => ({ ...p, quota: { ...p.quota, readAt: (p.quota?.readAt ?? 0) + 1 } })) });
  await t.host.time.pass(100);
  const made = workSince(from);
  assert.equal(made.models, 1, "its one station's models");
  assert.equal(made.annotated, 0, "no option annotated");
});

test("a_new_chats_control_says_of_what_it_runs_on_what_its_panel_says", async () => {
  // The page's control closed and the panel it opens say one thing: what it runs on, its model's name, maker and
  // runtimes, how hard it can think, Fast, the account named (`pick`'s, as the panel has them).
  const t = await workspace();
  t.store.subscribe(1, 3, { topic: "pick", station: CHAT.station, of: "new" }, true);
  await t.host.time.pass(100);
  const pick = t.store.get({ topic: "pick", station: CHAT.station, of: "new" }) as J;
  const face = (t.store.get(NEW) as J).pick;
  assert.deepEqual(face.value, pick.value);
  const named = (o: J) => ({ name: o.name, maker: o.maker, runtimes: o.runtimes });
  assert.deepEqual(named(face.valueOption), named(pick.valueOption));
  assert.deepEqual(face.efforts, pick.efforts);
  assert.equal(face.fastText, pick.fastText);
  assert.deepEqual(face.account, pick.account);
  assert.ok(pick.options.length > 20, "the panel's models");
});

/// A new chat on station `ws/st` of a workspace whose only station it is (`joined` or its own), of `profiles`: its
/// page's value and what its making listed, over a store and records stood in for.
function pageOf(profiles: J[], joined = false): { page: J; pick: J; made: ReturnType<typeof workSince> } {
  const overview = { sharing: true, profiles };
  const row = { station: "ws/st", id: "st", name: "Willow", online: true, ...(joined ? { joined: true, home: "Home" } : {}), overview: { counts: { running: 0 } } };
  const value = (t: J): unknown => (t.topic === "overview" ? overview : t.topic === "station" ? { ...row, overview } : t.topic === "stations" ? [row] : t.topic === "stationsWhole" ? [{ ...row, overview }] : undefined);
  const store: J = { get: value, value: (t: J) => (value(t) === undefined ? undefined : { ok: value(t) }), watch: () => ({ drop() {} }), invalidate() {} };
  const data: J = { record: () => undefined, put() {}, shared: () => undefined, mes: () => [] };
  const choose = new Choose({ store, data, now: () => 0, agent: () => null });
  const from = { ...work };
  const page = (choose.compute({ topic: "newChat", scope: "ws" }) as J).ok;
  const made = workSince(from);
  return { page, pick: (choose.compute({ topic: "pick", station: "ws/st", of: "new" }) as J).ok, made };
}

const runs = (id: string, ms: string[], more: J = {}): J => ({ id, name: `${id}@x.com`, runtime: "claude", runtimes: ["claude"], access: { kind: "subscription" }, models: ms, ...more });

test("a_new_chats_page_lists_its_stations_models_once_where_every_profile_enabled_there_serves_its_workspace_and_twice_where_one_does_not", () => {
  // Every profile enabled there serving it (one disabled, which neither lists): one list, the page's and the control's.
  const all = pageOf([runs("a", ["claude-opus-5-5"]), runs("b", ["claude-sonnet-5"], { serves: true }), runs("c", ["claude-fable-1"], { enabled: false })]);
  assert.equal(all.made.models, 1);
  assert.deepEqual(all.page.pick.value, all.pick.value);
  // One enabled there that does not serve this workspace (`serves` false): the page's models leave it out, the
  // control's do not (`pick` of `new`, as it always made them), each made apart, the face as its panel's.
  const not = pageOf([runs("a", ["claude-sonnet-5"]), runs("b", ["claude-opus-5-5"], { serves: false })]);
  assert.equal(not.made.models, 2);
  assert.deepEqual(not.page.model.model, "claude-sonnet-5", "the page: what serves it");
  assert.deepEqual(not.page.pick.value, not.pick.value, "the control: as its panel");
  assert.ok(not.pick.options.some((o: J) => o.model === "claude-opus-5-5"), "the control's: the one not serving it too");
  // A station this workspace joined, of before `serves`: its profiles whose `workspaces` do not name it serve it not.
  const joined = pageOf([runs("a", ["claude-sonnet-5"], { workspaces: ["ws"] }), runs("b", ["claude-opus-5-5"], { workspaces: ["home"] })], true);
  assert.equal(joined.made.models, 2);
  assert.deepEqual(joined.page.pick.value, joined.pick.value);
});
