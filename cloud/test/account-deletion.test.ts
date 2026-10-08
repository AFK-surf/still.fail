import assert from "node:assert/strict";
import test from "node:test";
import { harness } from "./harness.ts";
import { deletionCoverage } from "../src/deletion.ts";

test("deletion coverage is a blocked proposal, includes authored content and controlled-node copies, and leaves actual retention unknown", () => {
  assert.equal(deletionCoverage.coverageIncomplete, true);
  assert.equal(deletionCoverage.canDelete, false);
  assert.ok(deletionCoverage.categories.every(category => ["planned", "unverified", "unimplemented"].includes(category.status)));
  const authored = deletionCoverage.categories.find(category => category.id === "cloud_shared_attribution")!;
  assert.equal(authored.action, "delete");
  assert.equal(authored.status, "unimplemented");
  assert.match(authored.detail, /消息、上传内容及其中的个人信息/);
  assert.match(authored.detail, /不会仅移除署名而保留你的内容/);
  const node = deletionCoverage.categories.find(category => category.id === "node_copies")!;
  assert.equal(node.action, "delete_then_acknowledge");
  assert.equal(node.status, "unimplemented");
  assert.match(node.detail, /服务管理的电脑会话、上传内容及其中的个人信息/);
  assert.match(node.detail, /清理结果仍需电脑确认/);
  assert.match(node.detail, /这不会清空电脑，也不会删除与这个账号无关的文件。/);
  assert.match(node.detail, /独立保存、导出且不受服务管理/);
  assert.doesNotMatch(node.detail, /仅存于节点的共享历史|不远程卸载或擦盘/);
  assert.match(deletionCoverage.sharedPreservation, /其他成员的内容和共享工作区/);
  assert.doesNotMatch(deletionCoverage.sharedPreservation, /共享正文与资源|本地副本不承诺远程擦除/);
  for (const id of ["logs_telemetry", "backups"]) {
    const category = deletionCoverage.categories.find(category => category.id === id)!;
    assert.equal(category.status, "unverified");
    assert.match(category.detail, /实际.*保留期限尚未核实/);
  }
  assert.equal(deletionCoverage.offlineAccess.status, "proposed_unverified");
  assert.equal(deletionCoverage.offlineAccess.maximumGrantSeconds, 30 * 86400);
  assert.equal(deletionCoverage.offlineAccess.grantLifetimeStart, "original_grant_issuance");
  assert.equal(deletionCoverage.offlineAccess.instantRevocationGuaranteed, false);
  assert.match(deletionCoverage.offlineAccess.detail, /不代表电脑上的相关内容会在30天内自动清除/);
  assert.equal(deletionCoverage.securityRetention.status, "proposed_unverified");
  assert.equal(deletionCoverage.securityRetention.receiptRetentionSeconds, null);
  assert.equal(deletionCoverage.securityRetention.proposedReceiptRetentionSeconds, 32 * 86400);
  assert.match(deletionCoverage.securityRetention.purpose, /尚未实现或验证/);
  assert.match(deletionCoverage.securityRetention.purpose, /不是实际保留期限、全部日志的保留规则或 Apple 审核结论/);
});

test("deletion summary lists resolvable last-owner impact and deletion fails closed without losing sessions/shared members", async () => {
  const h = await harness();
  try {
    const aliceTokens = await h.login("alice");
    const alice = h.as(aliceTokens);
    const bob = h.as(await h.login("bob"));
    const workspace = await (await alice("POST", "/v1/workspaces", { name: "Preserved shared workspace" })).json() as any;
    await alice("POST", `/v1/workspaces/${workspace.id}/members`, { role: "member", emails: ["bob@example.test"] });
    const before = await (await alice("POST", "/v1/auth/deletion-summary", {})).json() as any;
    assert.equal(before.coverageIncomplete, true);
    assert.equal(before.canDelete, false);
    assert.equal(before.reauthNeeded, false);
    assert.equal(before.lastOwnerWorkspaces[0].id, workspace.id);
    assert.ok(before.lastOwnerWorkspaces[0].actions.includes("workspace.setRole"));
    assert.equal(before.offlineAccess.instantRevocationGuaranteed, false);
    assert.equal(before.offlineAccess.existingRevocationReplaySeconds, 31 * 86400);
    for (let retry = 0; retry < 2; retry++) {
      const response = await alice("POST", "/v1/auth/delete-account", {});
      assert.equal(response.status, 409);
      const result = await response.json() as any;
      assert.equal(result.deleted, false);
      assert.equal(result.state, "blocked");
      assert.equal(result.error, "deletion_coverage_incomplete");
    }
    assert.equal((await alice("GET", "/v1/auth/session")).status, 200, "blocked deletion retains session");
    assert.equal((await bob("GET", `/v1/workspaces/${workspace.id}`)).status, 200, "other members preserved");
    const view = await (await alice("GET", `/v1/workspaces/${workspace.id}`)).json() as any;
    const bobSub = view.members.find((m: any) => m.email === "bob@example.test").sub;
    await alice("PATCH", `/v1/workspaces/${workspace.id}/members/${bobSub}`, { role: "owner" });
    const resolved = await (await alice("POST", "/v1/auth/deletion-summary", {})).json() as any;
    assert.deepEqual(resolved.lastOwnerWorkspaces, [], "transfer resolves owner blocker; not a permanent prohibition");
    assert.ok(resolved.blockers.some((b: any) => b.code === "coverage_incomplete"), "owner resolution does not invent cloud erasure coverage");
    assert.equal(resolved.canDelete, false);
    assert.equal(resolved.coverageIncomplete, true);
    const stillBlocked = await alice("POST", "/v1/auth/delete-account", {});
    assert.equal(stillBlocked.status, 409, "resolving ownership must not unlock deletion");
    const blockedResult = await stillBlocked.json() as any;
    assert.equal(blockedResult.deleted, false);
    assert.equal(blockedResult.state, "blocked");
    assert.equal(blockedResult.error, "deletion_coverage_incomplete");
    const appleUnavailable = await h.fetch("/v1/auth/apple/challenge", { method: "POST" });
    assert.equal(appleUnavailable.status, 503);
    assert.equal((await appleUnavailable.json() as any).error, "apple_not_configured");
    assert.equal((await alice("GET", "/v1/auth/session")).status, 200, "Apple config does not gate Google sessions");
    const refresh = await h.fetch("/v1/auth/refresh", { method: "POST", headers: { authorization: `Bearer ${aliceTokens.refresh_token}`, "content-type": "application/json" }, body: JSON.stringify({ request_id: "01ARZ3NDEKTSV4RRFFQ69G5FAV" }) });
    assert.equal(refresh.status, 200, "Google refresh remains compatible");
  } finally { await h.close(); }
});
