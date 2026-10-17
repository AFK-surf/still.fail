// The workspace's models in a station's model control (docs/station-share.md 借用): its own, those borrowed from
// another station, those another station could lend it, and borrowing one (a manager's, confirmed first).
import assert from "node:assert/strict";
import { test } from "node:test";
import { Choose } from "../src/choose.ts";
import { holdLanguage } from "../src/i18n.ts";
import type { Topic } from "../src/protocol.ts";
import { borrowable, models, sourced } from "../src/views/models.ts";

holdLanguage();
// deno-lint-ignore no-explicit-any
type J = any;

const profile = (id: string, ms: string[], more: J = {}): J => ({ id, name: `${id}@x.com`, runtime: "claude", runtimes: ["claude"], access: { kind: "subscription" }, models: ms, ...more });
const station = (id: string, name: string, profiles: J[], more: J = {}): J => ({ station: `ws/${id}`, id, name, online: true, joined: false, overview: { sharing: true, profiles }, ...more });

const HERE = "a".repeat(64);
const STUDIO = "b".repeat(64);
const MINI = "c".repeat(64);

function workspace(): J[] {
  return [
    station(HERE, "ccvm", [
      profile("mine", ["claude-opus-5-5"]),
      // A copy Studio shares with it.
      profile("go", ["kimi-k3"], { runtimes: ["claude", "codex", "dsh"], access: { kind: "opencode-go", key: "st_1…" }, share: { id: "sh-go", role: "user", host: STUDIO } }),
    ]),
    station(STUDIO, "Studio", [
      profile("go", ["kimi-k3"], { runtimes: ["claude", "codex", "dsh"], access: { kind: "opencode-go", key: "st_1…" }, share: { id: "sh-go", role: "host", host: STUDIO, allow: [HERE] } }),
      profile("cx", ["gpt-6-astra"], { runtime: "codex", runtimes: ["codex"] }),
      profile("ds", ["deepseek-v4-pro", "claude-opus-5-5"], { runtimes: ["dsh"], access: { kind: "api-provider", key: "sk…" }, share: { id: "sh-ds", role: "host", host: STUDIO, allow: [MINI] } }),
    ]),
    // Down: what it has is not known.
    station(MINI, "Mini1", [profile("m", ["glm-5.2"])], { online: false }),
  ];
}

test("a_station_offers_its_own_models_says_which_are_borrowed_and_lists_what_others_could_lend", () => {
  const ws = workspace();
  const here = ws[0].overview;
  const own = sourced(models(here, 0), here, ws);
  assert.deepEqual(own.map((o: J) => [o.model, o.availability, o.fromText ?? null]), [["claude-opus-5-5", "here", null], ["kimi-k3", "borrowed", "借自 Studio"]]);
  const lend = borrowable(ws, `ws/${HERE}`, own, null, 0);
  // Opus is here already; Kimi is borrowed; Mini1 is down.
  assert.deepEqual(lend.map((o: J) => [o.model, o.availability, o.fromText, o.runtimes]), [["gpt-6-astra", "borrowable", "在 Studio 上", ["codex"]], ["deepseek-v4-pro", "borrowable", "在 Studio 上", ["dsh"]]]);
  const ds = lend.find((o: J) => o.model === "deepseek-v4-pro");
  assert.deepEqual(ds.borrow, { station: `ws/${STUDIO}`, stationName: "Studio", profile: "ds", profileName: "ds@x.com", subscription: false, pending: false, allow: [MINI] });
  assert.deepEqual(ds.accounts, { dsh: [] }, "not run here till borrowed");
  assert.equal(lend.find((o: J) => o.model === "gpt-6-astra").borrow.subscription, true);
  // A control whose runtime cannot change: only what runs on it.
  assert.deepEqual(borrowable(ws, `ws/${HERE}`, own, "codex", 0).map((o: J) => o.model), ["gpt-6-astra"]);
  // Shared with every station already: on its way, nothing to ask.
  ws[1].overview.profiles[1].share = { id: "sh-cx", role: "host", host: STUDIO, allow: null };
  assert.equal(borrowable(ws, `ws/${HERE}`, own, "codex", 0)[0].borrow.pending, true);
  // A station this workspace joined neither lends nor borrows; one that cannot share lends nothing.
  assert.deepEqual(borrowable(ws.map((s) => (s.id === HERE ? { ...s, joined: true } : s)), `ws/${HERE}`, own, null, 0), []);
  assert.deepEqual(borrowable(ws.map((s) => (s.id === STUDIO ? { ...s, overview: { ...s.overview, sharing: false } } : s)), `ws/${HERE}`, own, null, 0), []);
});

/// A model control on the first station of `ws`, its core's store and records stood in for.
function control(ws: J[], role: string) {
  const values = new Map<string, unknown>([[`overview ws/${HERE}`, ws[0].overview], ["stations", ws]]);
  const keyOf = (t: Topic) => (t.topic === "overview" ? `overview ${t.station}` : String(t.topic));
  const store: J = { get: (t: Topic) => values.get(keyOf(t)), watch: () => ({ drop() {} }), invalidate() {} };
  const data: J = { record: () => undefined, put() {}, shared: (t: Topic) => (t.topic === "workspace" ? { role } : undefined), mes: () => [] };
  return new Choose({ store, data, now: () => 0, agent: () => null });
}

test("picking_another_stations_model_asks_to_borrow_it_and_borrowing_shares_it_with_this_station", () => {
  const of = "connect-new:f";
  const at = `ws/${HERE}`;
  const choose = control(workspace(), "admin");
  choose.set(at, of, { model: "deepseek-v4-pro" });
  const v: J = (choose.compute({ topic: "pick", station: at, of }) as J).ok;
  assert.equal(v.option, "deepseek-v4-pro");
  assert.deepEqual([v.borrow.note, v.borrow.title, v.borrow.action, v.borrow.allowed], ["此 station 还不能用 DeepSeek V4 Pro", "向 Studio 借用 ds@x.com", "借用账号", true]);
  assert.equal(v.borrow.lines.length, 3);
  assert.ok(v.borrow.lines[1].includes("副本"), v.borrow.lines[1]);
  assert.ok(v.borrow.lines[2].includes("环境"), v.borrow.lines[2]);
  // Not saved till borrowed.
  assert.throws(() => choose.save(at, of), /请先借用/);
  // Borrowed: Studio is asked to share the profile with this station too, as a manager may.
  const op: J = choose.borrow(at, of);
  assert.equal(op.target.station, `ws/${STUDIO}`);
  assert.equal(op.path, "/profiles/ds/share");
  assert.deepEqual(op.body, { on: true, allow: [MINI, HERE] });
  // A member may not; a model of this station's own needs nothing.
  const member = control(workspace(), "member");
  member.set(at, of, { model: "deepseek-v4-pro" });
  const m: J = (member.compute({ topic: "pick", station: at, of }) as J).ok;
  assert.deepEqual([m.borrow.allowed, m.borrow.why], [false, "只有 owner 或 admin 可以借用"]);
  assert.throws(() => member.borrow(at, of), /owner 或 admin/);
  choose.set(at, of, { model: "claude-opus-5-5" });
  assert.equal((choose.compute({ topic: "pick", station: at, of }) as J).ok.borrow, null);
  assert.throws(() => choose.borrow(at, of), /无需借用/);
});
