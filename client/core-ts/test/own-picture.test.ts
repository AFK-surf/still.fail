// An account's own picture (still.fail cloud's PUT and DELETE /v1/me/picture, ops.ts `account.setPicture`,
// `account.removePicture`): put up or taken away as that account, then its `/v1/me` read again, whose picture the
// account takes and whose `own_picture` its entry of the `workspaces` topic says (`ownPicture`).
import assert from "node:assert/strict";
import { test } from "node:test";
import { Core } from "../src/core.ts";
import { FakeHost, jsonResponse } from "../src/testing.ts";
import { apply, call, signIn, subscribe } from "./helpers.ts";

test("an_accounts_own_picture_put_up_is_the_one_it_shows_marked_its_own_until_taken_away", async () => {
  const host = new FakeHost();
  signIn(host);
  const google = "https://lh.test/p.png";
  const own = "https://stillfail.test/v1/icons/0123456789abcdef0123456789abcdef.jpeg";
  const data = "data:image/jpeg;base64,/9j/";
  let shown: string | null = null;
  const sent: [string, unknown][] = [];
  host.onFetch((req) => {
    const path = req.url.replace("https://stillfail.test", "");
    if (path === "/v1/me") {
      return jsonResponse(200, { user: { sub: "s1", email: "a@x.com", name: "阿一", picture: shown ?? google, ...(shown ? { own_picture: true } : {}) }, workspaces: [], invitations: [], relay_url: "https://relay.test" });
    }
    if (path === "/v1/me/picture") {
      sent.push([req.method, req.body ? JSON.parse(new TextDecoder().decode(req.body)) : null]);
      shown = req.method === "PUT" ? own : null;
      return jsonResponse(200, { picture: shown ?? google });
    }
    return jsonResponse(404, { error: "not_found" });
  });
  const core = await Core.create(host, { clock: host.time.clock });
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "workspaces" });
  await host.settle();
  apply(host, values);
  const entry = () => (values.get(1) as any[])[0];
  assert.deepEqual([entry().account.picture, "ownPicture" in entry()], [google, false]);

  call(core, ui, 2, "account.setPicture", { account: "s1", picture: data });
  await host.settle();
  apply(host, values);
  assert.deepEqual(sent, [["PUT", { picture: data }]]);
  assert.deepEqual([entry().account.picture, entry().ownPicture], [own, true]);

  call(core, ui, 3, "account.removePicture", { account: "s1" });
  await host.settle();
  apply(host, values);
  assert.deepEqual(sent.at(-1), ["DELETE", null]);
  assert.deepEqual([entry().account.picture, "ownPicture" in entry()], [google, false]);
  core.close();
});
