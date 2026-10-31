// One Codex account can be signed in here and borrowed from another station at the same time.
import assert from "node:assert/strict";
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import { Accounts } from "../src/accounts/index.ts";
import { ConfigFile } from "../src/ops/config.ts";
import { sessionKey } from "../src/sessions/hub.ts";
import { Rig, message, settle } from "./hub-fakes.ts";

async function withSharedAccount(run: (r: Rig, key: string) => Promise<void>) {
  const r = new Rig();
  try {
    r.edit((raw) => {
      const local = raw.profiles.find((p: any) => p.id === "cx");
      local.models = ["gpt-6.1-terra"];
      raw.profiles.push({ ...local, id: "borrowed" }, { ...local, id: "other" });
      raw.connects.find((c: any) => c.id === "gpt").bind = { runtime: "codex", model: "gpt-6.1-terra", profile: "borrowed" };
    });
    r.hub.accounts.setHealth((id) => ({ account: id === "other" ? "account-b" : "account-a" }));
    const m = message();
    await r.accept(m, "gpt");
    await settle();
    const key = sessionKey("gpt", m.channel, m.threadTs);
    assert.equal(r.session(key).profile, "borrowed");
    await run(r, key);
  } finally {
    await r.close();
  }
}

test("an account's running chats count together across its local and borrowed profiles", async () => {
  await withSharedAccount(async (r) => {
    const profiles = r.config.profiles.filter((p) => p.runtime === "codex");
    assert.equal(r.hub.accounts.pick(profiles, "gpt-6.1-terra", true).id, "other");
  });
});

test("when an account hits its allowance, its other profile cannot take over the chat", async () => {
  await withSharedAccount(async (r, key) => {
    r.store.setSessionProfile(key, "borrowed", false);
    r.hub.accounts.spend(key, "borrowed");
    assert.equal(r.session(key).profile, "other");
  });
});

test("the newest successful allowance belongs to the account, even if another profile's reading is older", async () => {
  await withSharedAccount(async (r) => {
    r.hub.accounts.setHealth((id) => ({
      account: id === "other" ? "account-b" : "account-a",
      quota: { state: "ok", checkedAt: id === "cx" ? 1 : 2, windows: [{ usedPercent: id === "cx" ? 10 : id === "borrowed" ? 90 : 60 }] },
    }));
    const profiles = r.config.profiles.filter((p) => p.runtime === "codex");
    assert.equal(r.hub.accounts.pick(profiles, "gpt-6.1-terra", true).id, "other");
  });
});

test("two profiles on the same account do not win two successive picks while neither has started", async () => {
  const r = new Rig();
  try {
    r.edit((raw) => {
      const local = raw.profiles.find((p: any) => p.id === "cx");
      local.models = ["gpt-6.1-terra"];
      raw.profiles.push({ ...local, id: "borrowed" }, { ...local, id: "other" });
    });
    r.hub.accounts.setHealth((id) => ({ account: id === "other" ? "account-b" : "account-a" }));
    const profiles = r.config.profiles.filter((p) => p.runtime === "codex");
    assert.equal(r.hub.accounts.pick(profiles, "gpt-6.1-terra", true).id, "cx");
    assert.equal(r.hub.accounts.pick(profiles, "gpt-6.1-terra", true).id, "other");
  } finally {
    await r.close();
  }
});

test("Codex subscription profiles identify the actual account, including a borrowed login", async () => {
  const r = new Rig();
  try {
    r.edit((raw) => {
      const local = raw.profiles.find((p: any) => p.id === "cx");
      local.access = { kind: "subscription" };
      raw.profiles.push({ ...local, id: "borrowed", home: "homes/borrowed", share: { borrowed: true } });
      raw.profiles.push({ ...local, id: "other", home: "homes/other" });
      raw.profiles.push({ ...local, id: "workspace", home: "homes/workspace" });
      raw.profiles.push({ ...local, id: "api", home: "homes/api", access: { kind: "env" } });
    });
    const writeLogin = (home: string, account: string, user: string) => {
      const path = join(r.dir, "homes", home);
      mkdirSync(path, { recursive: true });
      const claims = Buffer.from(JSON.stringify({ sub: user, email: "same@example.test" })).toString("base64url");
      writeFileSync(join(path, "auth.json"), JSON.stringify({ tokens: { account_id: account, id_token: `header.${claims}.signature` } }));
    };
    writeLogin("cx", "first", "user-a");
    writeLogin("borrowed", "first", "user-a");
    writeLogin("other", "first", "user-b");
    writeLogin("workspace", "second", "user-a");
    writeLogin("api", "first", "user-a");
    const config = new ConfigFile(r.dir);
    config.update((raw) => Object.assign(raw, r.raw));
    const accounts = new Accounts({ data: r.dir, store: r.store, config, machine: null });
    assert.ok(accounts.health("cx").account);
    assert.equal(accounts.health("cx").account, accounts.health("borrowed").account);
    assert.notEqual(accounts.health("cx").account, accounts.health("other").account, "different users in the same workspace");
    assert.notEqual(accounts.health("cx").account, accounts.health("workspace").account, "the same user in different workspaces");
    assert.equal(accounts.health("api").account, undefined, "a gateway is not a Codex subscription");
    r.hub.accounts.setHealth((id) => accounts.health(id));
    const profiles = r.config.profiles.filter((p) => ["cx", "borrowed", "other"].includes(p.id));
    const [first, second] = [r.hub.accounts.pick(profiles, null, true), r.hub.accounts.pick(profiles, null, true)];
    assert.notEqual(accounts.health(first.id).account, accounts.health(second.id).account);
    writeLogin("borrowed", "new-account", "user-a");
    assert.notEqual(accounts.health("cx").account, accounts.health("borrowed").account, "a changed login is read again");
  } finally {
    await r.close();
  }
});
