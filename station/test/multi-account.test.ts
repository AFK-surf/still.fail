// Multi-account selection (`sessions.profiles`, `connect.bind.profiles`): a session kept to a chosen subset of accounts
// picks, repicks, fails over and waits for refills strictly within that subset without leaking to unselected accounts;
// a single account behaves as pinned, and null gives the choice back to all eligible accounts.
import assert from "node:assert/strict";
import { test } from "node:test";
import { sessionKey } from "../src/sessions/hub.ts";
import { configure, newSession } from "../src/sessions/lifecycle.ts";
import { Rig, say, settle } from "./hub-fakes.ts";

const chat = (runtime: "claude" | "codex" = "claude") => ({ runtime, createdBy: "local" });

test("a session kept to a subset of accounts rotates, repicks and fails over only within that subset", async () => {
  const r = new Rig();
  try {
    r.edit((raw) => {
      raw.profiles[0].models = ["opus", "sonnet"];
      raw.profiles.push(
        { ...raw.profiles[0], id: "cc2", name: "second", models: ["opus", "sonnet"] },
        { ...raw.profiles[0], id: "cc3", name: "third", models: ["opus", "sonnet"] },
      );
    });
    // Created with two of the three accounts: unpinned, restricted to [cc, cc2].
    const [key] = newSession(r.hub, { ...chat(), model: "opus", profiles: ["cc", "cc2"] });
    let row = r.session(key);
    assert.equal(row.profilePinned, false);
    assert.deepEqual(row.profiles, ["cc", "cc2"]);
    assert.ok(["cc", "cc2"].includes(row.profile));

    // When the first account hits its allowance, spend moves to the other checked account (never cc3) and keeps [cc, cc2].
    const first = row.profile;
    const other = first === "cc" ? "cc2" : "cc";
    const moved = r.hub.accounts.spend(key, first);
    assert.ok(moved !== null);
    row = r.session(key);
    assert.equal(row.profile, other);
    assert.deepEqual(row.profiles, ["cc", "cc2"]);

    // When both checked accounts are spent, it does NOT leak to cc3 (which is healthy): it stays and waits for their refill.
    assert.equal(r.hub.accounts.spend(key, other), null);
    assert.equal(r.hub.accounts.goesOnWith(r.session(key), "cc3"), false);
    assert.equal(r.hub.accounts.goesOnWith(r.session(key), first), true);
    assert.equal(r.hub.accounts.runOn(key).id, other);
    assert.ok(r.hub.accounts.refillsAt(key) > r.hub.now());

    // Resetting first's allowance allows repick within [cc, cc2] without clearing the subset.
    r.hub.accounts.resetAllowance(first);
    await configure(r.hub, key, { profiles: ["cc", "cc2"], repick: true });
    row = r.session(key);
    assert.equal(row.profile, first);
    assert.deepEqual(row.profiles, ["cc", "cc2"]);

    // Unchecking the active account (keeping [cc2, cc3] when on cc) moves immediately into [cc2, cc3].
    r.hub.accounts.resetAllowance(other);
    await configure(r.hub, key, { profiles: ["cc2", "cc3"] });
    row = r.session(key);
    assert.ok(["cc2", "cc3"].includes(row.profile));
    assert.deepEqual(row.profiles, ["cc2", "cc3"]);

    // Narrowing to one account pins it; null gives the choice back to all accounts (全选).
    await configure(r.hub, key, { profiles: ["cc3"] });
    row = r.session(key);
    assert.deepEqual([row.profile, row.profilePinned, row.profiles], ["cc3", true, ["cc3"]]);

    await configure(r.hub, key, { profiles: null });
    row = r.session(key);
    assert.deepEqual([row.profilePinned, row.profiles], [false, null]);
    assert.equal(r.hub.accounts.goesOnWith(row, "cc"), true);
  } finally {
    await r.close();
  }
});

test("a connect bound to multiple accounts starts its sessions on that subset", async () => {
  const r = new Rig();
  try {
    r.edit((raw) => {
      raw.profiles[0].models = ["opus"];
      raw.profiles.push(
        { ...raw.profiles[0], id: "cc2", name: "second", models: ["opus"] },
        { ...raw.profiles[0], id: "cc3", name: "third", models: ["opus"] },
      );
      delete raw.connects.find((c: any) => c.id === "cl").bind.profile;
      raw.connects.find((c: any) => c.id === "cl").bind.profiles = ["cc2", "cc3"];
    });
    const m = say("<@UBOT> hi");
    await r.accept(m);
    await settle();
    const row = r.session(sessionKey("cl", "C1", m.threadTs));
    assert.equal(row.profilePinned, false);
    assert.deepEqual(row.profiles, ["cc2", "cc3"]);
    assert.ok(["cc2", "cc3"].includes(row.profile));
  } finally {
    await r.close();
  }
});
