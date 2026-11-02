// Coming back on a weak link: streams that end as soon as they open wait longer each time, a station read afresh is
// taken up from its last event only once all of it was read, and the cloud's socket is tried again after a replacement
// that failed (link.ts, cursor.ts, sync/cloud.ts).
import assert from "node:assert/strict";
import { test } from "node:test";
import { Deferred, Effect, Queue } from "effect";
import { Core } from "../src/core.ts";
import { t } from "../src/i18n.ts";
import { CoreError, HostError } from "../src/error.ts";
import { BRIEF_MAX_MS, OFFLINE_RETRY_MS, RECONNECT_MAX_MS, RECONNECT_MS, STREAM_HELD_MS, UPDATE_DOWN_MS } from "../src/station/link.ts";
import { StationAddr } from "../src/station/addr.ts";
import { SOCKET_RETRY_MAX_MS } from "../src/sync/cloud.ts";
import { apply, call, subscribe } from "./helpers.ts";
import { HostWire } from "../src/station/wire.ts";
import { Wake } from "../src/wake.ts";
import { run } from "./run.ts";
import { base, overview, started, stationLater, stationReplies, status, threadView } from "./station-fixture.ts";

const ST = "ws/st";

/// Ends the stream open now, and finds when the next one opens: after `wait` and not before.
async function opensAfter(s: Awaited<ReturnType<typeof started>>, wait: number): Promise<void> {
  const n = s.streams.length;
  s.end();
  await s.host.time.pass(wait - 50, 50);
  assert.equal(s.streams.length, n, `not before ${wait} ms`);
  await s.host.time.pass(100, 50);
  assert.equal(s.streams.length, n + 1, `after ${wait} ms`);
}

test("streams_that_end_as_they_open_wait_longer_each_time_and_one_held_waits_as_before", async () => {
  const s = await started();
  try {
    for (const wait of [2000, 4000, 8000, 16000, 32000, RECONNECT_MAX_MS, RECONNECT_MAX_MS]) await opensAfter(s, wait);
    // One that held past the station's keepalive shows the link holds a stream: those after it wait as the first again.
    await s.host.time.pass(STREAM_HELD_MS, 1000);
    await opensAfter(s, RECONNECT_MS);
    await opensAfter(s, RECONNECT_MS);
    await opensAfter(s, 2 * RECONNECT_MS);
  } finally {
    s.core.close();
  }
});

test("streams_that_hold_a_while_on_a_weak_link_are_opened_again_at_once_each_time", async () => {
  const s = await started();
  try {
    // Each brought what the station told, and went some half a minute later: never more than RECONNECT_MS between.
    for (let i = 0; i < 6; i++) {
      s.push("overview", {});
      await s.host.time.pass(STREAM_HELD_MS + 5000, 1000);
      await opensAfter(s, RECONNECT_MS);
    }
  } finally {
    s.core.close();
  }
});

test("the_ui_coming_back_opens_a_stream_at_once_and_it_waits_as_the_first_again", async () => {
  const s = await started();
  try {
    for (const wait of [2000, 4000, 8000, 16000]) await opensAfter(s, wait);
    const n = s.streams.length;
    s.end();
    await s.host.time.pass(1000, 50);
    assert.equal(s.streams.length, n);
    s.core.inner.wakes.wake(new Wake(s.host.nowMs(), 31_000, false, false));
    await s.host.time.pass(100, 50);
    assert.equal(s.streams.length, n + 1, "at once");
    await opensAfter(s, RECONNECT_MS);
  } finally {
    s.core.close();
  }
});

test("a_core_started_again_while_its_station_was_read_afresh_reads_it_again", async () => {
  const answers = base();
  const s = await started(answers);
  let again: Core | undefined;
  try {
    // Read afresh, the chats not yet answered, as the stream tells on: where it is is not written down meanwhile.
    answers["GET /chats"] = [{ id: "7", thread: 7, session: "k1", title: "UPDATED", agents: [], lastActiveAt: 2 }];
    const release = s.host.hold("/admin/api/changed/chats");
    s.core.inner.stations.snapshot(ST);
    await s.host.settle();
    Queue.offerUnsafe(s.streams.at(-1)!.queue, new TextEncoder().encode("id: abcdef.50\nevent: overview\ndata: {}\n\n"));
    await s.host.settle();
    await run(s.core.inner.data.written);
    assert.equal(s.core.inner.data.record("heard", ST), undefined);
    // The app's process let go before the chats came.
    s.core.close();
    await s.host.settle();
    release();
    s.gate.resumes = true;
    again = await Core.create(s.host, { clock: s.host.time.clock, sample: 0, wire: () => new HostWire(s.host) });
    await s.host.time.pass(1000, 50);
    assert.ok(!s.streams.at(-1)!.path.includes("since="), s.streams.at(-1)!.path);
    const rows = again.inner.data.get({ topic: "chatRows", station: ST }) as { title: string }[];
    assert.equal(rows[0].title, "UPDATED");
    // All of it read, where it is is written down with what came after.
    Queue.offerUnsafe(s.streams.at(-1)!.queue, new TextEncoder().encode("id: abcdef.51\nevent: overview\ndata: {}\n\n"));
    await s.host.settle();
    await run(again.inner.data.written);
    assert.equal(again.inner.data.record("heard", ST), "abcdef.51");
  } finally {
    again?.close();
    s.core.close();
  }
});

test("a_station_read_afresh_that_could_not_be_read_whole_is_not_taken_up_from_its_last_event", async () => {
  const s = await started();
  try {
    // The chats not answered (the station failing as they were asked): nothing is written down, though the stream tells on.
    let down = true;
    stationReplies(s.host, (req) => (down && /\/admin\/api\/(changed\/)?chats$/.test(req.url) ? status(503, { error: "down" }) : undefined));
    s.core.inner.stations.snapshot(ST);
    await s.host.time.pass(1000, 50);
    Queue.offerUnsafe(s.streams.at(-1)!.queue, new TextEncoder().encode("id: abcdef.60\nevent: overview\ndata: {}\n\n"));
    await s.host.settle();
    await run(s.core.inner.data.written);
    assert.equal(s.core.inner.data.record("heard", ST), undefined);
    // Read whole the next time: written down.
    down = false;
    s.core.inner.stations.snapshot(ST);
    await s.host.time.pass(1000, 50);
    await run(s.core.inner.data.written);
    assert.equal(s.core.inner.data.record("heard", ST), "abcdef.60");
  } finally {
    s.core.close();
  }
});

test("a_failed_cloud_replacement_lets_the_next_wake_reconnect", async () => {
  const s = await started();
  try {
    const original = s.host.websocket.bind(s.host);
    let attempts = 0;
    let fail = true;
    s.host.websocket = (url, protocols) => {
      attempts++;
      return fail ? Effect.fail(new HostError("temporary outage")) : original(url, protocols);
    };
    const wake = () => s.core.inner.wakes.wake(new Wake(s.host.nowMs(), 31000, false, false));
    wake();
    await s.host.settle();
    assert.equal(attempts, 1);
    fail = false;
    wake();
    await s.host.settle();
    assert.equal(attempts, 2);
    assert.equal(s.host.openSockets("/v1/events"), 1);
    await s.host.time.pass(61000, 1000);
    assert.equal(attempts, 3, "the first heartbeat also has a deadline");
  } finally {
    s.core.close();
  }
});

// ── a station that tells a stream read afresh where its log is (station/src/api/events.ts) ──

/// The stream open now ends, `streak` times in a row each after `lasted` ms; resolves as the last one has ended.
async function flap(s: Awaited<ReturnType<typeof started>>, streak: number, lasted = 10_000): Promise<void> {
  for (let i = 0; i < streak; i++) {
    await s.host.time.pass(lasted, 500);
    const n = s.streams.length;
    s.end();
    if (i < streak - 1) while (s.streams.length <= n) await s.host.time.pass(250, 250);
  }
}

/// How long until the next stream opens.
async function reopens(s: Awaited<ReturnType<typeof started>>, limit = 120_000): Promise<number> {
  const n = s.streams.length;
  const from = s.host.nowMs();
  while (s.streams.length <= n && s.host.nowMs() - from < limit) await s.host.time.pass(250, 250);
  return s.host.nowMs() - from;
}

test("brief_streams_that_go_on_from_where_they_were_wait_at_most_BRIEF_MAX_MS_and_read_no_lists_again", async () => {
  const s = await started();
  s.gate.resumes = true;
  s.gate.marks = true;
  try {
    await flap(s, 1);
    await reopens(s);
    const lists = () => s.host.requests.filter((r) => /\/admin\/api\/(changed\/)?(chats|sessions|threads)(\?|$)/.test(r.url) || r.url.endsWith("/admin/api/batch")).length;
    const before = lists();
    for (let i = 0; i < 8; i++) {
      await flap(s, 1);
      assert.ok((await reopens(s)) <= BRIEF_MAX_MS, `try ${i}`);
      assert.ok(s.streams.at(-1)!.path.includes("since=abcdef."), s.streams.at(-1)!.path);
    }
    assert.equal(lists(), before, "each went on from where it was: nothing read afresh");
  } finally {
    s.core.close();
  }
});

test("a_brief_stream_that_goes_on_opens_again_as_soon_as_the_station_answers", async () => {
  const s = await started();
  s.gate.resumes = true;
  s.gate.marks = true;
  try {
    await flap(s, 6);
    const n = s.streams.length;
    const ended = s.host.nowMs();
    await s.host.time.pass(1000, 250);
    s.core.inner.stations.requests.onAnswered?.(StationAddr.parse(ST));
    while (s.streams.length <= n) await s.host.time.pass(250, 250);
    assert.ok(s.host.nowMs() - ended <= 1250, `${s.host.nowMs() - ended} ms`);
  } finally {
    s.core.close();
  }
});

/// A wire whose pings the test says (mesh.ts `healthChange`).
function pinging(host: Parameters<typeof started>[2] extends ((h: infer H) => unknown) | undefined ? H : never) {
  const wire = new HostWire(host) as HostWire & { healthChange(station: StationAddr, was: boolean): Effect.Effect<boolean>; set(up: boolean): void };
  let up = true;
  let waiting: Deferred.Deferred<boolean>[] = [];
  wire.healthChange = (_station, was) => Effect.suspend(() => {
    if (up !== was) return Effect.succeed(up);
    const d = Deferred.makeUnsafe<boolean>();
    waiting.push(d);
    return Deferred.await(d);
  });
  wire.set = (now) => {
    up = now;
    const told = waiting;
    waiting = [];
    for (const d of told) Deferred.doneUnsafe(d, Effect.succeed(now));
  };
  return wire;
}

test("pings_unanswered_show_the_station_coming_back_at_once_and_answered_again_reached", async () => {
  let wire: ReturnType<typeof pinging> | undefined;
  const s = await started(base(), 0, (host) => (wire = pinging(host)));
  try {
    const state = () => (s.core.inner.stations.link(ST)?.state as { state: string }).state;
    assert.equal(state(), "online");
    wire!.set(false);
    await s.host.time.pass(100, 50);
    assert.equal(state(), "reconnecting", "not STREAM_IDLE_MS later");
    wire!.set(true);
    await s.host.time.pass(100, 50);
    assert.equal(state(), "online");
    // Something coming on the stream shows it reached too.
    wire!.set(false);
    await s.host.time.pass(100, 50);
    s.push("overview", {});
    await s.host.time.pass(100, 50);
    assert.equal(state(), "online");
  } finally {
    s.core.close();
  }
});

test("pings_answered_again_open_a_brief_stream_that_goes_on_at_once", async () => {
  let wire: ReturnType<typeof pinging> | undefined;
  const s = await started(base(), 0, (host) => (wire = pinging(host)));
  s.gate.resumes = true;
  s.gate.marks = true;
  try {
    await flap(s, 6);
    const n = s.streams.length;
    const ended = s.host.nowMs();
    wire!.set(false);
    await s.host.time.pass(1000, 250);
    wire!.set(true);
    while (s.streams.length <= n) await s.host.time.pass(250, 250);
    assert.ok(s.host.nowMs() - ended <= 1250, `${s.host.nowMs() - ended} ms`);
  } finally {
    s.core.close();
  }
});

test("a_station_tried_seldom_after_long_down_is_tried_as_still_fail_cloud_is_reached_again", async () => {
  const s = await started();
  let down = true;
  stationLater(s.host, (req) => (down && req.url.includes("/admin/api") ? Promise.reject(new HostError("连不上")) : undefined));
  try {
    s.host.refuseSockets = true;
    s.gate.stream = "fail";
    s.host.socketClose("/v1/events");
    s.end();
    // Some ten minutes of tries: it is tried every OFFLINE_RETRY_MS now.
    await s.host.time.pass(7.3 * 60_000, 1000);
    down = false;
    s.host.refuseSockets = false;
    s.gate.stream = "open";
    // The cloud's socket is tried within SOCKET_RETRY_MAX_MS, and the station with it.
    assert.ok((await reopens(s, OFFLINE_RETRY_MS)) <= SOCKET_RETRY_MAX_MS + 2_000);
  } finally {
    s.core.close();
  }
});

test("while_the_app_keeps_its_record_a_station_not_reached_says_each_miss_each_wait_and_what_ended_it", async () => {
  const s = await started();
  const lines: string[] = [];
  s.host.recorder = { on: () => true, line: (l) => lines.push(l) };
  let down = true;
  stationLater(s.host, (req) => (down && req.url.includes("/admin/api") ? Promise.reject(new HostError("连不上")) : undefined));
  try {
    s.gate.stream = "fail";
    s.end();
    await s.host.time.pass(20_000, 1000);
    assert.ok(lines.some((l) => /^link miss: \S+ misses=\d+\/12 cloud=(up|down) -> \w+: /.test(l)), lines.join("\n"));
    assert.ok(lines.some((l) => /^link wait: \S+ \d+s \(backoff\) misses=\d+ why=/.test(l)), lines.join("\n"));
    assert.ok(lines.some((l) => /^link woke: \S+ by its time after \d+s$/.test(l)), lines.join("\n"));
    // the station back: no more misses said after it is reached
    down = false;
    s.gate.stream = "open";
    await reopens(s, 120_000);
  } finally {
    s.host.recorder = undefined;
    s.core.close();
  }
});

test("a_station_refusing_this_device_for_a_security_mode_is_down_for_that_and_says_why_whatever_still_fail_cloud_says", async () => {
  const s = await started();
  try {
    const why = "此 station 尚未接入此 workspace 的安全模式，稍后会自动重试；如果一直如此，请将它更新到最新版本";
    s.gate.stream = new CoreError("lock_station", why);
    s.end();
    await s.host.time.pass(10_000, 1000);
    const link = () => s.core.inner.stations.link(ST)?.state as { state: string; cause?: string; message?: string };
    assert.deepEqual([link().state, link().cause, link().message], ["offline", "lock", why]);
    // still.fail cloud's word changing (it lists the station online) does not make it 连不上.
    s.core.inner.stations.recause();
    assert.equal(link().cause, "lock");
    // Taking members again: reached.
    s.gate.stream = "open";
    await s.host.time.pass(RECONNECT_MAX_MS + 1000, 1000);
    assert.equal(link().state, "online");
  } finally {
    s.core.close();
  }
});

/// Takes the station down (nothing reaches it, its stream not opened) until the returned function brings it back.
async function takenDown(s: Awaited<ReturnType<typeof started>>): Promise<(() => void) & { down: () => boolean }> {
  let down = true;
  stationLater(s.host, (req) => (down && req.url.includes("/admin/api") ? Promise.reject(new HostError("连不上")) : undefined));
  s.gate.stream = "fail";
  s.end();
  await s.host.time.pass(60_000, 1000);
  assert.equal((s.core.inner.stations.link(ST)?.state as { state: string }).state, "offline");
  return Object.assign(() => {
    down = false;
    s.gate.stream = "open";
  }, { down: () => down });
}

test("messages_that_failed_as_their_station_was_down_go_in_order_once_it_is_reached_and_refused_ones_do_not", async () => {
  const s = await started();
  const posted: string[] = [];
  let n = 3;
  stationReplies(s.host, (req) => {
    if (req.method !== "POST" || !req.url.endsWith("/threads/7/messages")) return undefined;
    const text = JSON.parse(new TextDecoder().decode(req.body!)).text as string;
    if (text === "refused") return status(400, { error: "no such file" });
    posted.push(text);
    return { n: ++n };
  });
  try {
    // Refused as it is: not sent again.
    call(s.core, 1, 900, "chat.send", { station: ST, thread: 7, text: "refused" });
    await s.host.time.pass(1000, 250);
    const back = await takenDown(s);
    for (const [i, text] of ["一", "二", "三"].entries()) {
      call(s.core, 1, 901 + i, "chat.send", { station: ST, thread: 7, text });
      await s.host.time.pass(1000, 250);
    }
    const states = () => s.core.inner.views.local.outbox(ST, 7).map((m: { text: string; state: string; seq?: number }) => [m.text, m.seq !== undefined ? "sent" : m.state]);
    assert.deepEqual(states(), [["refused", "failed"], ["一", "failed"], ["二", "failed"], ["三", "failed"]]);
    back();
    await reopens(s, 20 * 60_000);
    await s.host.time.pass(2000, 250);
    assert.deepEqual(posted, ["一", "二", "三"]);
    assert.deepEqual(states().filter(([text]) => text === "refused"), [["refused", "failed"]]);
  } finally {
    s.core.close();
  }
});

test("a_new_chat_whose_answer_was_lost_is_retried_with_its_first_message", async () => {
  const s = await started();
  let first = true;
  let created = 0;
  const messages: string[] = [];
  stationLater(s.host, (req) => {
    if (first && req.method === "POST" && req.url.endsWith("/admin/api/sessions")) {
      first = false;
      return Promise.reject(new HostError("connection lost after creation"));
    }
    return undefined;
  });
  stationReplies(s.host, (req) => {
    if (req.method === "POST" && req.url.endsWith("/admin/api/sessions")) {
      created++;
      return { key: "ember:c-9", thread: threadView(9, 0) };
    }
    if (req.method === "POST" && req.url.endsWith("/admin/api/threads/9/messages")) {
      messages.push(JSON.parse(new TextDecoder().decode(req.body!)).text);
      return { n: 1 };
    }
    return undefined;
  });
  try {
    const local = s.core.inner.views.local;
    const key = local.pendingNew(ST, { runtime: "claude" });
    local.pendingQueue(key, { text: "first message" });
    s.core.inner.viewCalls.makeChat(key);
    await s.host.time.pass(1000, 250);
    assert.equal(local.unreached(ST).chats.includes(key), true);
    s.core.inner.viewCalls.stationBack(ST);
    await s.host.time.pass(2000, 250);
    assert.equal(created, 1);
    assert.deepEqual(messages, ["first message"]);
  } finally {
    s.core.close();
  }
});

test("a_new_chat_whose_station_went_down_stays_said_down_and_is_asked_for_once_the_station_is_reached", async () => {
  const s = await started();
  const asked: string[] = [];
  stationReplies(s.host, (req) => {
    if (req.method === "POST" && req.url.endsWith("/admin/api/sessions")) {
      asked.push(req.url);
      return { key: "ember:c-9", thread: threadView(9, 0) };
    }
    return undefined;
  });
  try {
    call(s.core, 1, 1, "newChat.pick", { scope: "ws", station: "st" });
    subscribe(s.core, 1, 2, { topic: "newChat", scope: "ws" });
    await s.host.time.pass(1000, 250);
    const back = await takenDown(s);
    const values = new Map();
    subscribe(s.core, 1, 3, { topic: "newChat", scope: "ws" });
    await s.host.time.pass(500, 250);
    apply(s.host, values);
    const page = values.get(3) as { down: boolean; station: { id: string } | null };
    assert.deepEqual([page.down, page.station?.id], [true, "st"]);
    // Sent while down: not asked of the station (it might make it twice), asked once it is reached.
    call(s.core, 1, 4, "chat.create", { station: ST, runtime: "claude", model: "opus" });
    await s.host.time.pass(5000, 250);
    assert.equal(asked.length, 0);
    back();
    await reopens(s, 20 * 60_000);
    await s.host.time.pass(2000, 250);
    assert.equal(asked.length, 1);
  } finally {
    s.core.close();
  }
});

type Shown = { offline: boolean; offlineNote?: string; outbox: { text: string; state: string; waits?: string; error?: string }[] };
type Listed = { trouble: { text: string; state: string } | null; days: { items: { id: string; offline?: string }[] }[] };

test("a_station_down_says_why_as_the_device_can_tell_and_its_chat_takes_messages_that_go_once_it_is_reached", async () => {
  // A weak network took a phone's stations for down, said each 离线 while it was up, and its composer took nothing.
  const row7 = { id: "k1", session: "k1", thread: 7, title: "部署", agents: [], last: null, unread: false, mine: true, lastActiveAt: 1, connect: null, origin: null };
  const s = await started({ ...base(), "GET /chats": [row7] });
  const posted: string[] = [];
  let tried = 0;
  let n = 3;
  stationReplies(s.host, (req) => {
    if (req.method !== "POST" || !req.url.endsWith("/threads/7/messages")) return undefined;
    posted.push(JSON.parse(new TextDecoder().decode(req.body!)).text as string);
    return { n: ++n };
  });
  try {
    const values = new Map<number, unknown>();
    subscribe(s.core, 1, 1, { topic: "chat", station: ST, thread: 7 });
    subscribe(s.core, 1, 2, { topic: "chats", scope: "ws" });
    const back = await takenDown(s);
    stationLater(s.host, (req) => {
      if (req.url.endsWith("/threads/7/messages")) tried++;
      return back.down() && req.url.includes("/admin/api") ? Promise.reject(new HostError("连不上")) : undefined;
    });
    await s.host.time.pass(500, 250);
    apply(s.host, values);
    const chat = () => values.get(1) as Shown;
    const list = () => values.get(2) as Listed;
    const row = () => list().days.flatMap((d) => d.items).find((i) => i.id === "k1");
    // still.fail cloud is reached and lists it online: not said 离线, but not reached from here.
    assert.equal((s.core.inner.stations.link(ST)?.state as { cause?: string }).cause, "unreached");
    assert.equal(chat().offline, true);
    assert.equal(chat().offlineNote, t("core-logic.looks.offline.unreached", { name: "studio" }));
    assert.equal(row()?.offline, t("core-views.station.unreachable", { name: "studio" }));
    assert.equal(list().trouble?.text, t("core-views.station.unreachable", { name: "studio" }));
    // Sent while it is down: it waits in the outbox, said so, the station not tried for it.
    call(s.core, 1, 3, "chat.send", { station: ST, thread: 7, text: "一" });
    await s.host.time.pass(1000, 250);
    apply(s.host, values);
    assert.deepEqual(chat().outbox.map((o) => [o.text, o.state, o.waits, o.error]), [["一", "sending", t("core-logic.looks.outbox.held"), undefined]]);
    assert.equal(tried, 0, "not tried while it is down");
    // The device's network goes too: still.fail cloud is not reached either, and that is what is said.
    s.host.refuseSockets = true;
    s.host.socketClose("/v1/events");
    await s.host.time.pass(1000, 250);
    apply(s.host, values);
    assert.equal((s.core.inner.stations.link(ST)?.state as { cause?: string }).cause, "network");
    assert.equal(chat().offlineNote, t("core-logic.looks.offline.network", { name: "studio" }));
    assert.equal(row()?.offline, t("core-views.station.offline_network", { name: "studio" }));
    // Both back: the message goes, once.
    s.host.refuseSockets = false;
    back();
    await reopens(s, 20 * 60_000);
    await s.host.time.pass(2000, 250);
    apply(s.host, values);
    assert.deepEqual(posted, ["一"]);
    assert.equal(chat().offline, false);
    assert.equal(chat().offlineNote, undefined);
    assert.equal(row()?.offline, undefined);
  } finally {
    s.core.close();
  }
});

test("a_station_its_update_takes_down_is_said_updating_until_it_has_been_down_longer_than_an_update_takes", async () => {
  // Updating, a station goes down while the installer hands over or restarts it: it said only 离线 (2026-10-29).
  const row7 = { id: "k1", session: "k1", thread: 7, title: "部署", agents: [], last: null, unread: false, mine: true, lastActiveAt: 1, connect: null, origin: null };
  const updating = { ...overview, updates: [{ id: "station", name: "still.fail", installed: true, version: "0.1.1", latest: "0.1.2", newer: true, updatable: true, state: "updating" }] };
  const s = await started({ ...base(), "GET /overview": updating, "GET /chats": [row7] });
  try {
    const values = new Map<number, unknown>();
    subscribe(s.core, 1, 1, { topic: "chat", station: ST, thread: 7 });
    subscribe(s.core, 1, 2, { topic: "chats", scope: "ws" });
    await s.host.time.pass(1000, 250);
    const chat = () => values.get(1) as Shown;
    const row = () => (values.get(2) as Listed).days.flatMap((d) => d.items).find((i) => i.id === "k1") as { offline?: string; stateText?: string; updating?: boolean } | undefined;
    // Gone: said so at once, while its link is still coming back, not only once it is taken for offline.
    stationLater(s.host, (req) => (req.url.includes("/admin/api") ? Promise.reject(new HostError("连不上")) : undefined));
    s.gate.stream = "fail";
    s.end();
    await s.host.time.pass(500, 250);
    apply(s.host, values);
    assert.equal((s.core.inner.stations.link(ST)?.state as { state?: string }).state, "reconnecting");
    assert.equal((s.core.inner.stations.link(ST)?.state as { cause?: string }).cause, "updating");
    assert.equal(chat().offline, true);
    assert.equal(chat().offlineNote, t("core-logic.looks.offline.updating", { name: "studio" }));
    assert.equal(row()?.offline, t("core-views.station.updating", { name: "studio" }));
    // Its row says so on its second line; the row and the chat are marked with the update's mark.
    assert.equal(row()?.stateText, t("core-views.station.updating", { name: "studio" }));
    assert.equal(row()?.updating, true);
    assert.equal((chat() as Shown & { updating?: boolean }).updating, true);
    await s.host.time.pass(60_000, 1000);
    apply(s.host, values);
    assert.equal((s.core.inner.stations.link(ST)?.state as { state?: string }).state, "offline");
    assert.equal((s.core.inner.stations.link(ST)?.state as { cause?: string }).cause, "updating");
    assert.equal(chat().offlineNote, t("core-logic.looks.offline.updating", { name: "studio" }));
    // Down longer than an update takes: no longer taken for its update.
    await s.host.time.pass(UPDATE_DOWN_MS + OFFLINE_RETRY_MS, 60_000);
    apply(s.host, values);
    assert.equal((s.core.inner.stations.link(ST)?.state as { cause?: string }).cause, "unreached");
    assert.equal(chat().offlineNote, t("core-logic.looks.offline.unreached", { name: "studio" }));
  } finally {
    s.core.close();
  }
});

test("a_station_the_cloud_says_is_not_online_is_said_offline", async () => {
  const s = await started(undefined, 0, undefined, (st) => {
    st.cloud.online = false;
    st.gate.stream = "fail";
  });
  try {
    const values = new Map<number, unknown>();
    subscribe(s.core, 1, 2, { topic: "chats", scope: "ws" });
    await s.host.time.pass(1000, 250);
    apply(s.host, values);
    assert.equal((s.core.inner.stations.link(ST)?.state as { cause?: string }).cause, "station");
    assert.equal((values.get(2) as Listed).trouble?.text, t("core-views.station.offline", { name: "studio" }));
  } finally {
    s.core.close();
  }
});
