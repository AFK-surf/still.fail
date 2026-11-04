// `operate` of data outflow (docs/data-outflow.md, 「操作」): a program granted it makes admin API requests as a member.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { request as http } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";
import { type Identity, OutflowGrants } from "../src/outflow/grants.ts";
import { peerOperate } from "../src/outflow/peer.ts";
import { type OperateCall, OutflowServer } from "../src/outflow/server.ts";

const PROGRAM: Identity = { path: "/p", valid: false, teamId: null, identifier: null, signer: null, app: null, sha256: "aa" };
const HERE = { id: "st-here", name: "Office", here: true };
const THERE = { id: "st-there", name: "Ann's Mac", here: false };

async function rig(scopes: ("usage" | "operate")[], asked: string[] = scopes) {
  const data = mkdtempSync(join(tmpdir(), "outflow-operate-"));
  after(() => rmSync(data, { recursive: true, force: true }));
  const path = join(data, "o.sock");
  const grants = new OutflowGrants(data, () => 1);
  const calls: OperateCall[] = [];
  const server = new OutflowServer({
    path, grants, lang: () => "en", identify: async () => PROGRAM, reads: async () => "{}",
    workspace: { here: () => HERE, stations: async () => [HERE, THERE], read: async () => "{}" },
    operate: async (call) => (calls.push(call), { status: 201, headers: { "content-type": "application/json" }, body: Buffer.from('{"made":true}') }),
  });
  await server.listen();
  after(() => server.close());
  const send = (method: string, url: string, body: unknown, token?: string) =>
    new Promise<{ status: number; body: any }>((resolve, reject) => {
      const req = http({ socketPath: path, method, path: url, headers: token ? { authorization: `Bearer ${token}` } : {} }, (res) => {
        let text = "";
        res.setEncoding("utf8");
        res.on("data", (c) => (text += c));
        res.on("end", () => resolve({ status: res.statusCode!, body: text ? JSON.parse(text) : null }));
      });
      req.on("error", reject);
      req.end(JSON.stringify(body));
    });
  const answer = send("POST", "/v1/request", { name: "Comma", scopes: asked, workspace: true });
  while (grants.asking().length === 0) await new Promise((resolve) => setImmediate(resolve));
  grants.answer(grants.asking()[0]!.id, "lin@example.com", { allow: true, scopes, reach: "workspace" }, "owner");
  const { body } = await answer;
  const operate = (call: object, token = body.token as string) => send("POST", "/v1/operate", call, token);
  return { calls, grants, operate };
}

test("a request is made as the member the program names, and the API's answer comes back", async () => {
  const { calls, operate, grants } = await rig(["operate"]);
  const got = await operate({ actor: "Ann@Example.com", method: "post", path: "/sessions", body: Buffer.from('{"runtime":"codex"}').toString("base64") });
  assert.equal(got.status, 200);
  assert.equal(got.body.status, 201);
  assert.equal(Buffer.from(got.body.body, "base64").toString(), '{"made":true}');
  const [call] = calls;
  assert.deepEqual([call!.actor, call!.role, call!.method, call!.path, call!.station], ["ann@example.com", "member", "POST", "/sessions", null]);
  assert.equal(call!.body.toString(), '{"runtime":"codex"}');
  assert.equal(grants.list()[0]!.reads.at(-1)!.scope, "operate");
});

test("the person who allowed the grant keeps their role; nobody else has it", async () => {
  const { calls, operate } = await rig(["operate"]);
  await operate({ actor: "lin@example.com", method: "GET", path: "/overview" });
  assert.equal(calls[0]!.role, "owner");
});

test("only a grant of `operate` operates; an admin leaving it out leaves it out", async () => {
  const { calls, operate } = await rig(["usage"], ["usage", "operate"]);
  const got = await operate({ actor: "ann@example.com", method: "GET", path: "/overview" });
  assert.deepEqual([got.status, got.body.error], [403, "not granted: operate"]);
  assert.equal(calls.length, 0);
});

test("grants and the vault are not given to a program, whoever it acts as", async () => {
  const { calls, operate } = await rig(["operate"]);
  for (const path of ["/outflow/requests/x", "/outflow/grants", "/vault/items", "/vault-requests", "//outflow/grants", "/%6futflow/grants", "/x/../outflow/grants", "/vault?x=1"]) {
    const got = await operate({ actor: "lin@example.com", method: "POST", path });
    assert.deepEqual([got.status, got.body.error], [403, "not given to a program"], path);
  }
  assert.equal(calls.length, 0);
});

test("another station is named, within the workspace", async () => {
  const { calls, operate } = await rig(["operate"]);
  await operate({ actor: "ann@example.com", method: "GET", path: "/overview", station: THERE.id });
  assert.equal(calls[0]!.station, THERE.id);
  const got = await operate({ actor: "ann@example.com", method: "GET", path: "/overview", station: "st-other" });
  assert.equal(got.status, 404);
});

test("an actor is a member's email; a token is a token", async () => {
  const { operate } = await rig(["operate"]);
  assert.equal((await operate({ actor: "", method: "GET", path: "/overview" })).status, 400);
  assert.equal((await operate({ actor: "ann@example.com", method: "GET", path: "/overview" }, "sfo_wrong")).status, 401);
});

test("another station asking does it as a member at most, and is refused what a program is refused", async () => {
  const calls: OperateCall[] = [];
  const answer = peerOperate(async (call) => (calls.push(call), { status: 200, headers: {}, body: Buffer.from("{}") }));
  await answer("peer", { call: { actor: "lin@example.com", role: "owner", method: "GET", path: "/overview", query: [], headers: {} } }, "ws");
  assert.equal(calls[0]!.role, "member");
  await assert.rejects(answer("peer", { call: { actor: "a@b", role: "member", method: "GET", path: "/vault/items" } }, "ws"), /not given to a program/);
});
