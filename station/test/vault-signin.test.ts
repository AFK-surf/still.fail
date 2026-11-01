// Signing in to a site from a card (vault/signin.ts, docs/vault.md 登录态 "Signing in from a card"): one call of the
// agent's, the vault's sign-in asked for where it keeps one; else a card the person answers from their app, what their
// password manager gave typed in by the station step by step, a code asked on the card, a person given the tab where
// only they can go on, the agent told when the page left its sign-in and kept in the vault, with no card of its own,
// once it says it is signed in. Nothing waits on time: the browser and the vault are the test's.
import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import type { Driven, FormField, FormValues } from "../src/browser/signin-form.ts";
import type { Request } from "../src/vault/crypto.ts";
import { SignIns, siteOf } from "../src/vault/signin.ts";
import { STILLFAIL_SURFACE } from "../src/store/store.ts";

const tick = () => new Promise((r) => setImmediate(r));

function world(o: { listed?: string; held?: string; surface?: string } = {}) {
  const cards: { ts: string; card: any; text: string }[] = [];
  const withdrawn: string[] = [];
  const told: string[] = [];
  const driven: { values: FormValues; used: FormField[] }[] = [];
  const kept: { site: string; made: (r: string) => void }[] = [];
  const used: string[] = [];
  const answers: Driven[] = [];
  const subscribers: ((c: { type: string; key?: string }) => void)[] = [];
  const sessions = new Map<string, { archivedAt?: number | null }>([["s1", {}]]);
  let n = 0;
  let tabs = [{ id: "T1", url: "https://github.com/login" }];
  let form = { username: true, password: true, code: false, blocked: false };
  const hub = {
    store: {
      getSession: (k: string) => sessions.get(k) ?? null,
      starter: () => "pat@example.com",
      latestThread: () => ({ connect: "c", thread: { id: 1, channel: "EMBER", threadTs: "1.0", surface: o.surface ?? STILLFAIL_SURFACE } }) as any,
      insertMessage: (m: any) => {
        cards.push({ ts: m.ts, card: m.card, text: m.text });
        return [++n];
      },
      withdrawCard: (_a: string, _t: number, ts: string) => (withdrawn.push(ts), true),
      restateCard: (_a: string, _t: number, ts: string, f: (was: any) => any) => {
        const c = cards.find((x) => x.ts === ts)!;
        c.card = f(c.card);
        return true;
      },
      subscribe: (f: (c: { type: string; key?: string }) => void) => void subscribers.push(f),
    },
    chat: () => ({ post: async () => `t${n + 1}` }),
    shared: () => {},
    notify: (_s: string, text: string) => void told.push(text),
  };
  const timers: (() => void)[] = [];
  const signIns = new SignIns({
    db: new DatabaseSync(":memory:"), hub, now: () => 1_800_000_000_000, after: (_ms, f) => (timers.push(f), () => {}),
    workspace: () => "ws", screenLink: (tab) => `https://app/w/ws/s/st/screen/browser%3A${tab}`, id: () => "g1",
    browser: {
      tabs: () => tabs,
      look: async () => form,
      drive: async (_s, _t, _site, values, usedFields) => {
        driven.push({ values: { ...values }, used: [...usedFields] });
        const a = answers.shift() ?? { state: "left" };
        for (const k of ["username", "password", "code"] as const) if (values[k] !== undefined && a.state !== "person") usedFields.add(k);
        return a;
      },
    },
    vault: {
      listed: () => o.listed ?? null,
      held: () => o.held ?? null,
      use: async (_s, item) => (used.push(item), `Asked for ${item}.`),
      keep: async (_s, site, _reason, made) => {
        kept.push({ site, made });
        made("r_save");
        return `Asked to keep ${site}.`;
      },
    },
  });
  return {
    signIns, cards, withdrawn, told, driven, kept, used, answers, timers,
    setTabs: (t: typeof tabs) => void (tabs = t), setForm: (f: typeof form) => void (form = f),
    archive: (s: string) => {
      sessions.set(s, { archivedAt: 1 });
      for (const f of subscribers) f({ type: "session", key: s });
    },
  };
}

test("a site as asked: its host, without scheme, path, port or www.", () => {
  assert.equal(siteOf("https://www.GitHub.com/login?x=1"), "github.com");
  assert.equal(siteOf("accounts.google.com:443"), "accounts.google.com");
});

test("a sign-in the vault keeps (or grants already) is asked for as any secret: no card of the sign-in's", async () => {
  const w = world({ listed: "i_gh" });
  assert.match(await w.signIns.ask("s1", { site: "github.com", reason: "看 PR" }), /Asked for i_gh/);
  assert.deepEqual(w.used, ["i_gh"]);
  assert.equal(w.cards.length, 0);
  const held = world({ held: "Granted already." });
  assert.match(await held.signIns.ask("s1", { site: "github.com", reason: "看 PR" }), /Granted already/);
  // ran out: asked anew
  const again = world({ listed: "i_gh" });
  await again.signIns.ask("s1", { site: "github.com", reason: "看 PR", again: true });
  assert.equal(again.used.length, 0);
  assert.equal(again.cards.length, 1);
});

test("none kept: a card on the chat's tab on the site, refused without one or without a sign-in form there", async () => {
  const w = world();
  w.setTabs([]);
  await assert.rejects(w.signIns.ask("s1", { site: "github.com", reason: "看 PR" }), /no tab on github.com/);
  w.setTabs([{ id: "T1", url: "https://github.com/" }]);
  w.setForm({ username: false, password: false, code: false, blocked: false });
  await assert.rejects(w.signIns.ask("s1", { site: "github.com", reason: "看 PR" }), /no sign-in form/);
  await assert.rejects(w.signIns.ask("s1", { site: "github.com" }), /reason is required/);
  w.setForm({ username: true, password: true, code: false, blocked: false });
  const said = await w.signIns.ask("s1", { site: "https://github.com/login", reason: "看 PR" });
  assert.match(said, /card in your chat/);
  assert.equal(w.cards.length, 1);
  assert.equal(w.cards[0]!.text, "要登录 github.com：看 PR");
  assert.equal(w.cards[0]!.card.assignee, "pat@example.com");
  assert.deepEqual(w.cards[0]!.card.signin, { id: "g1", site: "github.com", reason: "看 PR", screen: "browser:T1" });
  // asked again meanwhile: the same one
  assert.match(await w.signIns.ask("s1", { site: "github.com", reason: "again" }), /waits for pat@example.com/);
  assert.equal(w.cards.length, 1);
});

test("in Slack there is no card: the words give the tab's screen", async () => {
  const w = world({ surface: "slack" });
  await w.signIns.ask("s1", { site: "github.com", reason: "看 PR" });
  assert.equal(w.cards[0]!.card, null);
  assert.match(w.cards[0]!.text, /screen\/browser%3AT1/);
});

test("filled from the person's app: typed in step by step, a code asked on the card, the agent told once the page left its sign-in, kept with no card of its own once it says so", async () => {
  const w = world();
  await w.signIns.ask("s1", { site: "github.com", reason: "看 PR" });
  // only the person the agent works for, in its workspace
  assert.match(w.signIns.fill("eve@x.com", "ws", "g1", { password: "pw" })!, /only the person/);
  assert.match(w.signIns.fill("pat@example.com", "other", "g1", { password: "pw" })!, /no such sign-in/);
  assert.match(w.signIns.fill("pat@example.com", "ws", "g1", {})!, /nothing to fill/);
  w.answers.push({ state: "code" });
  assert.equal(w.signIns.fill("Pat@Example.com", "ws", "g1", { username: "pat", password: "pw", keep: true }), null);
  assert.equal(w.cards[0]!.card.signin.outcome.status, "filling");
  await tick();
  assert.deepEqual(w.cards[0]!.card.signin.outcome, { status: "code", keep: true });
  assert.equal(w.told.length, 0);
  // the code: typed with what was given before, the account and password not again
  w.answers.push({ state: "left" });
  assert.equal(w.signIns.fill("pat@example.com", "ws", "g1", { code: "123456" }), null);
  await tick();
  assert.deepEqual(w.driven[1], { values: { username: "pat", password: "pw", code: "123456" }, used: ["username", "password"] });
  assert.equal(w.cards[0]!.card.signin.outcome.status, "left");
  assert.match(w.told[0]!, /left its sign-in.*done: true.*keeps the sign-in in their vault/s);
  assert.doesNotMatch(w.told[0]!, /pw|123456/, "nothing typed told");
  // the agent looked: kept, the request on the card for the app to approve in place; its card waits for that
  assert.match(await w.signIns.ask("s1", { site: "github.com", done: true }), /Signed in to github.com. Asked to keep github.com/);
  assert.equal(w.kept[0]!.site, "github.com");
  assert.deepEqual(w.cards[0]!.card.signin.outcome, { status: "done", keep: true, save: "r_save" });
  assert.deepEqual(w.withdrawn, []);
  w.signIns.heard({ id: "r_save", session: "s1", status: "granted", save: { kind: "browser" } } as unknown as Request);
  assert.equal(w.cards[0]!.card.signin.outcome.kept, "granted");
  assert.deepEqual(w.withdrawn, ["t1"]);
  // done: answered no more
  assert.match(w.signIns.fill("pat@example.com", "ws", "g1", { password: "pw" })!, /done already/);
});

test("where only the person can go on, the card gives them the tab; they say when they are done, or the agent says what is left", async () => {
  const w = world();
  await w.signIns.ask("s1", { site: "github.com", reason: "看 PR" });
  w.answers.push({ state: "person", why: "blocked" });
  w.signIns.fill("pat@example.com", "ws", "g1", { username: "pat", password: "pw", keep: false });
  await tick();
  assert.deepEqual(w.cards[0]!.card.signin.outcome, { status: "person", why: "blocked", keep: false });
  assert.equal(w.signIns.self("pat@example.com", "ws", "g1", true), null);
  assert.match(w.told[0]!, /signed in to github.com themselves/);
  assert.doesNotMatch(w.told[0]!, /keeps the sign-in/, "they chose not to keep it");
  assert.match(await w.signIns.ask("s1", { site: "github.com", stuck: "去邮箱点确认链接" }), /screen/);
  assert.deepEqual(w.cards[0]!.card.signin.outcome, { status: "person", why: "agent", said: "去邮箱点确认链接", keep: false });
  assert.match(await w.signIns.ask("s1", { site: "github.com", done: true }), /chose not to keep it/);
  assert.equal(w.kept.length, 0);
  assert.deepEqual(w.withdrawn, ["t1"]);
});

test("refused on the card, or its chat archived: let go, the card withdrawn, what was given forgotten", async () => {
  const w = world();
  await w.signIns.ask("s1", { site: "github.com", reason: "看 PR" });
  assert.equal(w.signIns.deny("pat@example.com", "ws", "g1"), null);
  assert.match(w.told[0]!, /chose not to sign in/);
  assert.deepEqual(w.withdrawn, ["t1"]);
  assert.equal(w.signIns.get("g1")!.status, "denied");
  const a = world();
  await a.signIns.ask("s1", { site: "github.com", reason: "看 PR" });
  a.archive("s1");
  assert.equal(a.signIns.get("g1")!.status, "ended");
});
