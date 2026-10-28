// The programs granted a station's data (the `outflowGrants` topic, docs/data-outflow.md): read as a page shows it,
// told as the station says, revoked with `outflow.revoke`; a station from before has none.
import assert from "node:assert/strict";
import { test } from "node:test";
import { apply, call, readsOf, subscribe, v } from "./helpers.ts";
import { base, started } from "./station-fixture.ts";

const S = "ws/st";
const grant = (scopes: string[], reads: { at: number; scope: string; rows: number }[] = []) => ({
  id: "g1",
  identity: { path: "/Applications/Comma.app/Contents/Resources/station/node", valid: true, teamId: "D9AAN3VJK8", identifier: "surf.comma.station", signer: "Developer ID Application: AFK Inc. (D9AAN3VJK8)", app: "Comma", sha256: null },
  said: { name: "Comma", purpose: "ROI" },
  scopes,
  grantedAt: 1_000,
  reads,
  lastReadAt: reads.at(-1)?.at ?? null,
});

test("the_grants_are_read_as_shown_and_revoking_one_reads_them_again", async () => {
  const said: Record<string, unknown> = { ...base(), "GET /outflow/grants": { grants: [grant(["usage", "chats"], [{ at: 2_000, scope: "usage", rows: 3 }, { at: 3_000, scope: "chats", rows: 1 }])] }, "DELETE /outflow/grants/g1": { revoked: true } };
  const { host, core } = await started(said);
  const reads = () => host.requests.flatMap(readsOf).filter((u) => u.endsWith("/admin/api/outflow/grants")).length;
  assert.equal(reads(), 0, "not read until a page shows it");
  const ui = core.connect();
  const values = new Map<number, unknown>();
  subscribe(core, ui, 1, { topic: "outflowGrants", station: S });
  await host.time.pass(500, 10);
  apply(host, values);
  assert.equal(reads(), 1);
  const shown = v(values, 1);
  assert.equal(shown.supported, true);
  const [g] = shown.grants;
  assert.equal(g.program, "Comma");
  assert.equal(g.signed, true);
  assert.equal(g.said, "Comma — ROI");
  assert.deepEqual(g.scopes.map((s: { id: string }) => s.id), ["usage", "chats"]);
  assert.deepEqual(g.reads.map((r: { scope: string; rows: number }) => [r.scope, r.rows]), [["chats", 1], ["usage", 3]], "the newest first");
  assert.equal(g.lastReadAt, 3_000);
  assert.ok(g.grantedText.length > 0 && g.lastReadText.length > 0);

  said["GET /outflow/grants"] = { grants: [] };
  call(core, ui, 2, "outflow.revoke", { station: S, id: "g1" });
  await host.time.pass(500, 10);
  apply(host, values);
  assert.ok(host.requests.some((r) => JSON.stringify(r).includes("/admin/api/outflow/grants/g1")), "revoked on the station");
  assert.equal(reads(), 2);
  assert.deepEqual(v(values, 1).grants, []);
  core.close();
});

test("an_unsigned_program_is_shown_as_unsigned", async () => {
  const unsigned = { ...grant(["usage"]), identity: { path: "/tmp/x/node", valid: true, teamId: null, identifier: "node", signer: null, app: null, sha256: "ab" } };
  const first = await started({ ...base(), "GET /outflow/grants": { grants: [unsigned] } });
  const ui = first.core.connect();
  const values = new Map<number, unknown>();
  subscribe(first.core, ui, 1, { topic: "outflowGrants", station: S });
  await first.host.time.pass(500, 10);
  apply(first.host, values);
  const [g] = v(values, 1).grants;
  assert.equal(g.signed, false);
  assert.equal(g.signer, null);
  assert.equal(g.program, "node");
  first.core.close();
});
