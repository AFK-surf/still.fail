// A new chat's page says whether another station would lend its station a model (choose.ts `#lends`: its
// `borrow_only` words, no `blocked`), as a yes or no walked of the stations' overviews (views/models.ts `lends`), where it
// made every station's models and every model another could lend (`borrowable` of `stationsWhole`) to count them. The
// two say the same, arrangement by arrangement: borrow.test.ts's, and the page's own.
import assert from "node:assert/strict";
import { test } from "node:test";
import { holdLanguage } from "../src/i18n.ts";
import { borrowable, lends } from "../src/views/models.ts";

holdLanguage();
// deno-lint-ignore no-explicit-any
type J = any;

const profile = (id: string, ms: string[], more: J = {}): J => ({ id, name: `${id}@x.com`, runtime: "claude", runtimes: ["claude"], access: { kind: "subscription" }, models: ms, ...more });
const station = (id: string, name: string, profiles: J[], more: J = {}): J => ({ station: `ws/${id}`, id, name, online: true, joined: false, overview: { sharing: true, profiles }, ...more });

const HERE = "a".repeat(64);
const STUDIO = "b".repeat(64);
const MINI = "c".repeat(64);
const AT = `ws/${HERE}`;

/// borrow.test.ts's workspace: this station with its own and a copy Office shares with it, Office lending two models
/// (one shared with TestStation), TestStation down.
function workspace(): J[] {
  return [
    station(HERE, "lab-node", [
      profile("mine", ["claude-opus-5-5"]),
      profile("go", ["kimi-k3"], { runtimes: ["claude", "codex", "dsh"], access: { kind: "opencode-go", key: "st_1…" }, share: { id: "sh-go", role: "user", host: STUDIO } }),
    ]),
    station(STUDIO, "Office", [
      profile("go", ["kimi-k3"], { runtimes: ["claude", "codex", "dsh"], access: { kind: "opencode-go", key: "st_1…" }, share: { id: "sh-go", role: "host", host: STUDIO, allow: [HERE] } }),
      profile("cx", ["gpt-6-astra"], { runtime: "codex", runtimes: ["codex"] }),
      profile("ds", ["deepseek-v4-pro", "claude-opus-5-5"], { runtimes: ["dsh"], access: { kind: "api-provider", key: "sk…" }, share: { id: "sh-ds", role: "host", host: STUDIO, allow: [MINI] } }),
    ], { emoji: "🖥️" }),
    station(MINI, "TestStation", [profile("m", ["glm-5.2"])], { online: false }),
  ];
}

/// `ws` with station `id` changed by `f`.
const with_ = (ws: J[], id: string, f: (s: J) => J): J[] => ws.map((s) => (s.id === id ? f(s) : s));
/// `ws` with station `id`'s profiles `ps`.
const profiles = (ws: J[], id: string, ps: J[]): J[] => with_(ws, id, (s) => ({ ...s, overview: { ...s.overview, profiles: ps } }));

/// Each arrangement, by what it is.
function arrangements(): [string, J[]][] {
  const base = workspace();
  const bare = profiles(base, HERE, []);
  const only = (ps: J[]) => profiles(bare, STUDIO, ps);
  return [
    ["borrow.test.ts's workspace", base],
    ["shared with every station already", with_(base, STUDIO, (s) => ({ ...s, overview: { ...s.overview, profiles: s.overview.profiles.map((p: J) => (p.id === "cx" ? { ...p, share: { id: "sh-cx", role: "host", host: STUDIO, allow: null } } : p)) } }))],
    ["this station joined", with_(base, HERE, (s) => ({ ...s, joined: true }))],
    ["Office cannot share", with_(base, STUDIO, (s) => ({ ...s, overview: { ...s.overview, sharing: false } }))],
    ["no profile here, another lends", bare],
    ["no profile here, none lends", only([])],
    ["no profile here, the lender joined", with_(bare, STUDIO, (s) => ({ ...s, joined: true }))],
    ["no profile here, the lender not sharing", with_(bare, STUDIO, (s) => ({ ...s, overview: { ...s.overview, sharing: false } }))],
    ["no profile here, the lender down", with_(bare, STUDIO, (s) => ({ ...s, online: false }))],
    ["no profile here, the lender unreadable", with_(bare, STUDIO, (s) => ({ ...s, overview: null }))],
    ["no profile here, the lender not read yet", with_(bare, STUDIO, (s) => ({ ...s, overview: undefined }))],
    ["no profile here, the lender's only profile a copy it borrows", only([profile("go", ["kimi-k3"], { share: { id: "sh-x", role: "user", host: MINI } })])],
    ["no profile here, the lender's only profile shared here already", profiles(only([profile("ds", ["deepseek-v4-pro"], { share: { id: "sh-ds", role: "host", host: STUDIO } })]), HERE, [profile("ds", ["deepseek-v4-pro"], { enabled: false, share: { id: "sh-ds", role: "user", host: STUDIO } })])],
    ["no profile here, the lender's only profile runs no model", only([profile("e", [])])],
    ["no profile here, the lender's only profile disabled", only([profile("cx", ["gpt-6-astra"], { enabled: false })])],
    ["no profile here, the lender's only profile shared with another", only([profile("ds", ["deepseek-v4-pro"], { share: { id: "sh-ds", role: "host", host: STUDIO, allow: [MINI] } })])],
    ["no profile here, only a down station lends", with_(only([]), MINI, (s) => ({ ...s, online: true }))],
    ["no profile here, this station not listed", bare.filter((s) => s.id !== HERE)],
  ];
}

test("whether_another_station_lends_a_new_chats_station_a_model_is_what_borrowable_of_every_station_said", () => {
  const says: string[] = [];
  for (const [what, ws] of arrangements()) {
    const before = borrowable(ws, AT, [], null, 0).length > 0;
    const now = lends(ws, AT, (at) => ws.find((s) => s.station === at)?.overview);
    assert.equal(now, before, what);
    says.push(`${what}: ${now}`);
  }
  // (both answers taken: not every arrangement says the same)
  assert.ok(says.some((s) => s.endsWith("true")) && says.some((s) => s.endsWith("false")), says.join("\n"));
});
