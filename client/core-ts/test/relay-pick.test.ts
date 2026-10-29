// What a chat's relay picker shows (src/relay-pick.ts, `chat.relayView`): the bot gone on through, the places offered
// and in what order, a Slack message's link typed instead.
import assert from "node:assert/strict";
import { test } from "node:test";
import { MENTIONS, arrange, mentionQuery, mentionView, readConnects, readPeople, relayBot, relayView, slackLink, type RelayConnect, type RelayPlace } from "../src/relay-pick.ts";
import { parseCall } from "../src/core/calls.ts";
import { tr } from "../src/i18n.ts";
import { answers, call, cloudCore } from "./helpers.ts";

// deno-lint-ignore no-explicit-any
type J = any;

const zh = (k: string, a?: Record<string, string | number>) => tr("zh", k, a);
const channel = (name: string, used?: number): RelayPlace => (used === undefined ? { id: name, name, kind: "channel" } : { id: name, name, kind: "channel", used });
const bot = (id: string, places: RelayPlace[], more: Partial<RelayConnect> = {}): RelayConnect => ({ id, kind: "slack", name: id, team: "AFK", places, ...more });

test("the_bot_gone_on_through_is_the_one_picked_else_the_chats_own_else_the_first", () => {
  const cs = [bot("a", []), bot("b", [], { preferred: true })];
  assert.equal(relayBot(cs, null)?.id, "b");
  assert.equal(relayBot(cs, "a")?.id, "a");
  assert.equal(relayBot([bot("a", []), bot("c", [])], null)?.id, "a");
  assert.equal(relayBot([], null), null);
});

test("places_relayed_to_before_come_first_then_by_name_and_of_many_only_the_recent_ones", () => {
  const few = [channel("ops"), channel("dev", 5), channel("art")];
  assert.deepEqual(arrange([bot("a", few)], "", false).rows.map((r) => r.place.name), ["dev", "art", "ops"]);
  const many = [...Array(9).keys()].map((i) => channel(`c${i}`, i < 6 ? i : undefined));
  const shown = arrange([bot("a", many)], "", false);
  assert.equal(shown.recent, true);
  assert.equal(shown.total, 9);
  assert.deepEqual(shown.rows.map((r) => r.place.name), ["c5", "c4", "c3", "c2", "c1"]);
  assert.equal(arrange([bot("a", many)], "", true).rows.length, 9, "all asked for");
  // Typed: those starting with it first, out of all of them.
  assert.deepEqual(arrange([bot("a", [channel("release"), channel("pre-release", 3), channel("ops")])], "rel", false).rows.map((r) => r.place.name), ["release", "pre-release"]);
});

test("a_slack_messages_link_typed_is_its_thread", () => {
  const link = "https://afk.slack.com/archives/C0123ABC/p1792828521435000";
  assert.equal(slackLink(` ${link} `), link);
  assert.equal(slackLink("https://afk.slack.com/archives/C0123ABC"), null);
  assert.equal(slackLink("release"), null);
});

test("the_view_names_the_places_and_the_bots_among_several", () => {
  const cs = [bot("a", [channel("dev"), { id: "g", name: "设计组", kind: "group" }, { id: "p", name: "core", kind: "channel", private: true }]), bot("b", [], { team: "Cue", error: "token revoked" })];
  const v = relayView(cs, "", false, null, zh);
  assert.equal(v.bot, "a");
  assert.deepEqual(v.bots, [{ id: "a", label: "a · AFK" }, { id: "b", label: "b · Cue" }]);
  assert.deepEqual(v.rows.map((r) => [r.name, r.aside]), [["🔒 #core", null], ["#dev", null], ["设计组", zh("web-main.relay.kind.group")]]);
  assert.equal(v.rows[1]!.note, zh("web-main.relay.kind.channel"), "what relaying there does, said once it is picked");
  assert.equal(v.empty, null);
  const other = relayView(cs, "", false, "b", zh);
  assert.deepEqual([other.empty, other.unread], ["noPlaces", ["token revoked"]]);
  assert.equal(relayView(cs, "zzz", false, null, zh).empty, "noMatch");
  assert.deepEqual(relayView([bot("a", [])], "", false, null, zh).bots, [], "one bot: none to pick from");
});

test("a_client_asks_the_core_what_the_picker_shows", async () => {
  const connects = [bot("a", [channel("dev")])];
  assert.deepEqual(parseCall("chat.relayView", { connects, query: "d" }), { kind: "relayView", connects: readConnects(connects), query: "d", all: false, bot: null });
  const { host, core } = await cloudCore();
  const ui = core.connect();
  call(core, ui, 1, "chat.relayView", { connects, query: "", all: false });
  await host.settle();
  const v = (answers(host.takeEmitted(), 1) as J).ok;
  assert.deepEqual(v.rows.map((r: J) => r.name), ["#dev"]);
  assert.equal(v.bot, "a");
});

test("an_at_in_the_note_offers_the_people_there_and_picking_one_writes_their_name", () => {
  const people = [{ id: "U1", name: "pengxiao", aka: "Peng Xiao" }, { id: "U2", name: "ann" }, { id: "U3", name: "张三" }, { id: "U4", name: "xiaoming" }];
  assert.deepEqual(mentionQuery("hi @pe"), { at: 3, query: "pe" });
  assert.equal(mentionQuery("mail a@b"), null, "an @ in a word is not one");
  assert.equal(mentionQuery("@ann\nlook"), null, "nor one on a line before");
  assert.equal(mentionView(people, "look").query, null);
  // Their name or other name has it, those starting with it first, then by name.
  assert.deepEqual(mentionView(people, "@xiao").rows.map((p) => p.id), ["U4", "U1"]);
  assert.deepEqual(mentionView(people, "@Peng X").rows.map((p) => p.id), ["U1"]);
  assert.deepEqual(mentionView(people, "@").rows.map((p) => p.id), ["U2", "U1", "U4", "U3"]);
  assert.equal(mentionView(Array.from({ length: 9 }, (_, i) => ({ id: `U${i}`, name: `p${i}` })), "@p").rows.length, MENTIONS);
  // Picked: the note with their name in place of what was typed, and nothing is offered for it any more.
  const picked = mentionView(people, "请 @张").rows[0]!;
  assert.equal(picked.note, "请 @张三 ");
  assert.deepEqual(mentionView(people, picked.note).rows, []);
  assert.deepEqual(readPeople([{ id: "U1", name: "a", aka: "", picture: "p" }, { id: "", name: "b" }, "x"]), [{ id: "U1", name: "a", picture: "p" }]);
});

test("a_client_asks_the_core_whom_the_note_can_mention", async () => {
  const people = [{ id: "U1", name: "ann" }];
  assert.deepEqual(parseCall("chat.relayMentions", { people, note: "@a" }), { kind: "relayMentions", people, note: "@a" });
  const { host, core } = await cloudCore();
  const ui = core.connect();
  call(core, ui, 1, "chat.relayMentions", { people, note: "hi @a" });
  await host.settle();
  assert.deepEqual((answers(host.takeEmitted(), 1) as J).ok, { query: "a", rows: [{ id: "U1", name: "ann", note: "hi @ann " }] });
});
