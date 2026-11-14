// Every write to still.fail cloud a person makes answers once the cloud took it, however slow the reads around it are
// (src/core/execute.ts `REREAD_WAIT_MS`). 2026-11-11 a member added turned its button for 3 min 40 s, the POST itself
// under a second: what was read after it, on a link where little came back, was waited on. The test of that (core.test.ts
// `a_write_answers_once...`) held one read after one write; here every cloud write the UIs can make is made with every
// read (a GET, of the cloud or of a station) left unanswered, the write's own request answered at once, and each must
// answer within `REREAD_WAIT_MS`. A write that does not is in `KNOWN` with why, and `KNOWN` only falls.
import assert from "node:assert/strict";
import { test } from "node:test";
import { STORAGE_KEY } from "../src/accounts.ts";
import { Core } from "../src/core.ts";
import { REREAD_WAIT_MS } from "../src/core/execute.ts";
import { PARAMS, request } from "../src/ops.ts";
import { FakeHost, jsonResponse } from "../src/testing.ts";
import { account, answers, call, nowS } from "./helpers.ts";

/// Writes that do not answer while the reads hang, each with why. Only falls: one that answers now fails the test until
/// it is taken out.
const KNOWN: Record<string, string> = {};

/// The services ops.ts sends to the cloud (`CLOUD_SERVICES`).
const CLOUD = ["workspace", "invitation", "loginSession", "account", "admin"];

/// The cloud's operations (ops.ts `cloudOp`) that write: what a person waits on.
function cloudWrites(): string[] {
  return Object.keys(PARAMS).filter((name) => {
    if (!CLOUD.includes(name.slice(0, name.indexOf(".")))) return false;
    const r = request(name, paramsOf(name));
    return r !== null && "cloud" in r.target && r.method !== "GET";
  });
}

/// Params that fill every field `name` takes, as PARAMS declares them.
function paramsOf(name: string): Record<string, unknown> {
  const out: Record<string, unknown> = { account: "s1" };
  for (const field of PARAMS[name]!.split(" ").filter((f) => f !== "")) {
    const [key, type] = field.replace("?", "").split(":") as [string, string];
    out[key] = key === "workspace" ? "ws" : key === "role" ? "admin" : type === "number" ? 1 : type === "boolean" ? true : type === "strings" ? ["b@x.com"] : type === "json" ? {} : key === "email" ? "b@x.com" : `${key}-1`;
  }
  return out;
}

/// A core signed in as s1, owner of workspace `ws` with one station; once `hang()` is called every GET is left without
/// an answer and every other request answered 200 at once.
async function slowCore(): Promise<{ host: FakeHost; core: Core; hang: () => void }> {
  const host = new FakeHost();
  host.store(STORAGE_KEY, [account("s1", "a@x.com", "阿一", "tok", "r0", nowS(host) + 3600)]);
  let hanging = false;
  host.onFetch((req) => {
    const path = req.url.replace("https://stillfail.test", "");
    if (hanging) return req.method === "GET" ? new Promise(() => {}) : jsonResponse(200, {});
    switch (path) {
      case "/v1/me":
        return jsonResponse(200, { workspaces: [{ id: "ws", name: "W", role: "owner" }], invitations: [], relay_url: "https://relay.test" });
      case "/v1/workspaces/ws":
        return jsonResponse(200, { id: "ws", role: "owner", stations: [{ id: "st", name: "studio", online: true, last_seen: 1 }], members: [{ sub: "s1", email: "a@x.com", role: "owner" }] });
      default:
        return jsonResponse(404, { error: "not_found" });
    }
  });
  const core = await Core.create(host, { clock: host.time.clock });
  return { host, core, hang: () => (hanging = true) };
}

test("every_cloud_write_answers_within_the_reread_wait_while_every_read_hangs", async () => {
  const writes = cloudWrites();
  assert.ok(writes.includes("workspace.addMembers") && writes.includes("workspace.setRole"), String(writes));
  const late: string[] = [];
  for (const name of writes) {
    const { host, core, hang } = await slowCore();
    const ui = core.connect();
    await host.settle();
    hang();
    host.takeEmitted();
    call(core, ui, 2, name, paramsOf(name));
    await host.settle();
    await host.time.pass(REREAD_WAIT_MS);
    if (answers(host.takeEmitted(), 2) === undefined) late.push(name);
    core.close();
  }
  console.log(`writes measured: ${writes.length}; unanswered: ${JSON.stringify(late)}`);
  assert.deepEqual(late.filter((n) => !(n in KNOWN)), [], "a write waits on a read: answer once the cloud took it (execute.ts rereadAfterWrite)");
  assert.deepEqual(Object.keys(KNOWN).filter((n) => !late.includes(n)), [], "answers now: take it out of KNOWN");
});
