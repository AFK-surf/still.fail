// A Claude subscription's limit resets: read from its usage answer, and used as Claude Code uses them, against a local
// provider.
import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { claimOutcome, claudeClaim, claudeResets, claudeResetWith } from "../src/accounts/claude-reset.ts";
import { claudeUsage } from "../src/accounts/quota.ts";
import { provider } from "./accounts-fakes.ts";

// As Anthropic answered Claude Code 2.1.321 on 2026-11-10 (the fields this reads).
const grant = { id: "launch-2610-fable", resets_total: 1, resets_left: 1, starts_at: "2026-11-09T18:00:00+00:00", ends_at: "2027-03-09T07:59:00+00:00", paused: false, usable_now: true, use_requires_limit: false, type: "full" };
const notAtWall = { eligible: false, ineligible_reason: "not_at_wall", in_experiment: false, arm: null, available: false, resets_per_week: 1 };
const atWall = { eligible: true, ineligible_reason: null, in_experiment: true, arm: "reset", available: true, next_available_at: null };
const ember = (grants: unknown[], next: string | null = null) => ({ eligible: true, ineligible_reason: null, at_limit: false, exhausted: [], grants, next_grant_id: next });
const elsewhere = { juniper_tide: { ...notAtWall, ineligible_reason: "surface" }, cedar_ember: { eligible: false, ineligible_reason: "surface", grants: [] } };

describe("a Claude subscription's limit resets", { concurrency: true }, () => {
  test("are listed a kind each, as Claude Code names them: by what one gives back, with how many and till when", () => {
    const ends = Date.parse("2027-03-09T07:59:00Z");
    // Fable's launch reset: `full` as the provider says, but giving back to the week what Fable used: Fable's.
    const fable = { ...grant, gives_back_weekly: true, clears: ["seven_day_overage_included"] };
    assert.deepEqual(claudeResets({ juniper_tide: notAtWall, cedar_ember: ember([fable], grant.id) }, "Fable"), [{ id: "model", kind: "model", model: "Fable", left: 1, usable: true, expiries: [ends] }]);
    // The weekly 5-hour reset with a 5-hour grant usable only at a limit: one kind; a full one apart.
    const session = { ...grant, id: "s", type: null, clears: ["five_hour"], usable_now: false };
    const full = { ...grant, id: "f", resets_left: 2 };
    assert.deepEqual(claudeResets({ juniper_tide: atWall, cedar_ember: ember([full, session]) }), [
      { id: "session", kind: "session", left: 2, usable: true, expiries: [ends] },
      { id: "full", kind: "full", left: 2, usable: true, expiries: [ends, ends] },
    ]);
    assert.deepEqual(claudeResets({ juniper_tide: atWall, cedar_ember: ember([]) }), [{ id: "session", kind: "session", left: 1, usable: true }]);
    assert.deepEqual(claudeResets({ cedar_ember: ember([{ ...grant, type: null, clears: ["seven_day"] }]) }).map((r) => r.kind), ["weekly"]);
    // Paused or used up: not held; the control arm of the 5-hour reset: none.
    assert.deepEqual(claudeResets({ juniper_tide: { ...atWall, arm: "control" }, cedar_ember: ember([{ ...grant, paused: true }, { ...grant, id: "b", resets_left: 0 }]) }), []);
    // Offered to another surface (or an older Claude Code) only: nothing to show.
    assert.deepEqual(claudeResets(elsewhere), []);
    assert.deepEqual(claudeResets({}), []);
  });

  test("use the weekly 5-hour reset first, else the grant named next, else say why none", () => {
    const other = { ...grant, id: "other" };
    assert.deepEqual(claudeClaim({ juniper_tide: atWall, cedar_ember: ember([grant], grant.id) }, "k"), { program: "juniper_tide" });
    const claim = claudeClaim({ juniper_tide: notAtWall, cedar_ember: ember([other, grant], grant.id) }, "key-1");
    assert.equal(typeof claim, "object");
    const c = claim as { program: string; grant_id?: string; request_id?: string };
    assert.deepEqual([c.program, c.grant_id], ["cedar_ember", grant.id]);
    assert.match(c.request_id!, /^[A-Za-z0-9_-]{1,64}$/);
    assert.deepEqual(claudeClaim({ cedar_ember: ember([other, grant], grant.id) }, "key-1"), claim, "the same key, the same request");
    assert.equal((claudeClaim({ cedar_ember: ember([other, grant], null) }, "k") as { grant_id: string }).grant_id, "other");
    // By kind: the 5-hour one asks the weekly 5-hour reset; a full one, its grant even with the 5-hour one there; a kind
    // not held, none.
    const fullOne = { ...grant, id: "f", type: "full" };
    assert.deepEqual(claudeClaim({ juniper_tide: atWall, cedar_ember: ember([fullOne]) }, "k", "session"), { program: "juniper_tide" });
    assert.equal((claudeClaim({ juniper_tide: atWall, cedar_ember: ember([fullOne]) }, "k", "full") as { grant_id: string }).grant_id, "f");
    assert.equal(claudeClaim({ juniper_tide: atWall, cedar_ember: ember([fullOne]) }, "k", "weekly"), "noCredit");
        // Held but usable only at a limit: none now; none held: no credit.
    assert.equal(claudeClaim({ juniper_tide: notAtWall, cedar_ember: ember([{ ...grant, usable_now: false }]) }, "k"), "none");
    assert.equal(claudeClaim({ juniper_tide: notAtWall, cedar_ember: ember([]) }, "k"), "noCredit");
    assert.equal(claudeClaim(elsewhere, "k"), "noCredit");
    assert.deepEqual(["reset", "already_used", "not_limited", "cooldown", "ineligible", "unavailable", undefined].map(claimOutcome),
      ["reset", "alreadyRedeemed", "nothingToReset", "unavailable", "unavailable", "unconfirmed", "unconfirmed"]);
  });

  test("are asked as the installed Claude Code asks them, and shown with the allowance", async () => {
    const p = await provider(() => ({ status: 200, body: { seven_day: { utilization: 70, resets_at: null }, juniper_tide: notAtWall, cedar_ember: ember([grant], grant.id) } }));
    const q = await claudeUsage(p.base, "t", "zh", "2.1.321");
    assert.deepEqual([q.resetCount, q.resetExpiries, q.resets?.map((r) => r.kind)], [1, [Date.parse("2027-03-09T07:59:00Z")], ["full"]]);
    assert.equal(p.asked[0]!.url, "/api/oauth/usage?at_wall=1&skip_spend=1");
    assert.equal(p.asked[0]!.headers["user-agent"], "claude-cli/2.1.321 (external, cli)");
    // No Claude Code to ask as: the plain read, no resets.
    const plain = await claudeUsage(p.base, "t", "zh");
    assert.deepEqual(["resetCount" in plain, "resets" in plain], [false, false]);
    assert.equal(p.asked[1]!.url, "/api/oauth/usage");
    await p.close();
  });

  test("are used at the account's organization; a token not good is said, a refusal is the provider's", async () => {
    let usage = 200;
    let answer: { status: number; body: unknown } = { status: 200, body: { result: "reset", resets_left: 0 } };
    const p = await provider((asked) => {
      if (asked.url.startsWith("/api/oauth/usage")) return { status: usage, body: { juniper_tide: atWall, cedar_ember: ember([]) } };
      if (asked.url === "/api/oauth/profile") return { status: 200, body: { organization: { uuid: "9a8b-7c6d" } } };
      return answer;
    });
    assert.deepEqual(await claudeResetWith(p.base, "t", "2.1.321", "k"), { outcome: "reset" });
    const claim = p.asked.at(-1)!;
    assert.deepEqual([claim.method, claim.url, claim.body], ["POST", "/api/organizations/9a8b-7c6d/reset_rate_limits", { program: "juniper_tide" }]);
    answer = { status: 200, body: { result: "not_limited" } };
    assert.deepEqual(await claudeResetWith(p.base, "t", "2.1.321", "k"), { outcome: "nothingToReset" });
    answer = { status: 429, body: {} };
    assert.deepEqual(await claudeResetWith(p.base, "t", "2.1.321", "k"), { outcome: "unavailable" });
    answer = { status: 401, body: {} };
    assert.deepEqual(await claudeResetWith(p.base, "t", "2.1.321", "k"), { unauthorized: true });
    usage = 401;
    const asked = p.asked.length;
    assert.deepEqual(await claudeResetWith(p.base, "t", "2.1.321", "k"), { unauthorized: true });
    assert.equal(p.asked.length, asked + 1, "nothing claimed with a token not good");
    await p.close();
  });
});
