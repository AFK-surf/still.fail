// Someone added to a workspace (POST /v1/workspaces/:id/members) is told so by mail (mail.ts `sendAdded`): in it at
// once, or once they first sign in with that email; once a day at most, what could not be sent said to the app.
import assert from "node:assert/strict";
import test from "node:test";
import type { MailMessage } from "../src/mail.ts";
import { harness } from "./harness.ts";

type H = Awaited<ReturnType<typeof harness>>;
type As = ReturnType<H["as"]>;

const create = async (owner: As, name: string) => ((await (await owner("POST", "/v1/workspaces", { name })).json()) as { id: string }).id;
const add = async (owner: As, workspace: string, emails: string[], lang?: string) => {
  const answer = await owner("POST", `/v1/workspaces/${workspace}/members`, { role: "member", emails, ...(lang ? { lang } : {}) });
  assert.equal(answer.status, 200);
  return (await answer.json()) as { joined: string[]; added: string[]; already: string[]; unmailed: string[]; mail?: unknown };
};
const to = (h: H, email: string) => h.mails.filter((m) => m.to === email);

test("each one added is mailed: who added them, to what, and how they get in; one already a member is not", async () => {
  const h = await harness({ mail: true });
  try {
    const alice = h.as(await h.login("alice"));
    await h.login("bob");
    const team = await create(alice, "Team");
    const made = await add(alice, team, ["bob@example.test", "carol@example.test", "alice@example.test"]);
    assert.deepEqual([made.joined, made.added, made.already, made.unmailed], [["bob@example.test"], ["carol@example.test"], ["alice@example.test"], []]);
    assert.equal(made.mail, undefined, "what the Directory handed the API to send stays there");

    const [bob] = to(h, "bob@example.test") as [MailMessage];
    const [carol] = to(h, "carol@example.test") as [MailMessage];
    assert.equal(to(h, "alice@example.test").length, 0);
    assert.equal(h.mails.length, 2);
    assert.match(bob.subject, /alice.*「Team」/);
    assert.match(bob.text, /打开 still\.fail 就能看到/, "in it already: open the app");
    assert.match(carol.text, /用 carol@example\.test 登录 still\.fail，就会自动加入/, "not signed up: sign in with that email");
    assert.match(carol.html, new RegExp(`href="${h.origin.replace(/[.]/g, "\\.")}"`), "a link to this cloud, no token");
    assert.deepEqual(carol.from, { email: "noreply@relay.example", name: "still.fail" });

    // In the language the app asked in.
    await add(alice, team, ["dave@example.test"], "en");
    assert.match(to(h, "dave@example.test")[0]!.subject, /alice invited you to “Team”/);
  } finally {
    await h.close();
  }
});

test("on monoid's cloud the mail says monoid and links there", async () => {
  const h = await harness({ mail: true, origin: "https://app.monoid.build" });
  try {
    const alice = h.as(await h.login("alice"));
    await add(alice, await create(alice, "Team"), ["carol@example.test"]);
    const [carol] = to(h, "carol@example.test") as [MailMessage];
    assert.match(carol.text, /登录 monoid，就会自动加入/);
    assert.doesNotMatch(carol.text + carol.subject + carol.html, /still\.fail/);
    assert.match(carol.html, /href="https:\/\/app\.monoid\.build"/);
    assert.equal((carol.from as { name: string }).name, "monoid");
  } finally {
    await h.close();
  }
});

test("taken out and added again the same day, nobody is mailed twice; a mail that could not go is said and tried again", async () => {
  let refuse = "frank@example.test";
  const h = await harness({ mail: (m) => (m.to === refuse ? "E_RATE_LIMIT_EXCEEDED" : true) });
  try {
    const alice = h.as(await h.login("alice"));
    const team = await create(alice, "Team");
    await add(alice, team, ["carol@example.test"]);
    assert.equal((await alice("DELETE", `/v1/workspaces/${team}/added/carol@example.test`)).status, 200);
    assert.deepEqual((await add(alice, team, ["carol@example.test"])).unmailed, []);
    assert.equal(to(h, "carol@example.test").length, 1, "once a day");
    // Another workspace is another mail.
    await add(alice, await create(alice, "Lab"), ["carol@example.test"]);
    assert.equal(to(h, "carol@example.test").length, 2);

    const first = await add(alice, team, ["frank@example.test"]);
    assert.deepEqual([first.added, first.unmailed], [["frank@example.test"], ["frank@example.test"]], "added all the same, the mail said not sent");
    refuse = "";
    assert.deepEqual((await add(alice, team, ["frank@example.test"])).unmailed, []);
    assert.equal(to(h, "frank@example.test").length, 1, "added again, it is sent");
  } finally {
    await h.close();
  }
});

test("a cloud with no mail adds as before and says nothing unsent", async () => {
  const h = await harness();
  try {
    const alice = h.as(await h.login("alice"));
    const made = await add(alice, await create(alice, "Team"), ["carol@example.test"]);
    assert.deepEqual([made.added, made.unmailed], [["carol@example.test"], []]);
    assert.equal(h.mails.length, 0);
  } finally {
    await h.close();
  }
});

