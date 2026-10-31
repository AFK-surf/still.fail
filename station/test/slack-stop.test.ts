import assert from "node:assert/strict";
import { test } from "node:test";
import { Rig, message, reply, settle, testClock } from "./hub-fakes.ts";

const slackTs = (ms: number) => (ms / 1000).toFixed(6);

test("Slack's stop targets its bot in the thread, and retries cannot stop a later turn", async () => {
  const time = testClock();
  await time.adjust(1_700_000_000_000);
  const r = new Rig({ clock: time.clock });
  try {
    const m = message();
    await r.accept(m);
    await settle();
    await r.accept(reply(m, "1700000000.000200", "<@UGPT> help", { addressed: true }), "gpt");
    await settle();
    const claude = r.claude.last();
    const codex = r.codex.last();
    await time.adjust(1_000);
    const stop = { type: "stop" as const, channel: m.channel, threadTs: m.threadTs, ts: slackTs(time.clock.currentTimeMillisUnsafe()) };
    await r.hub.receive("cl", stop);
    await r.hub.receive("cl", stop);
    assert.equal(claude.aborts, 1);
    assert.equal(codex.aborts, 0, "the other bot is not stopped");
    assert.notEqual(r.chat.lastText(), "已停止当前任务", "the interrupt is not yet a completed stop");
    claude.end({ kind: "aborted" });
    await settle();
    assert.equal(r.chat.lastText(), "已停止当前任务");

    // Another request starts after the click. Both a duplicate and an event first delivered late leave it running.
    const delayed = { ...stop, ts: slackTs(time.clock.currentTimeMillisUnsafe() + 500) };
    await time.adjust(1_000);
    await r.accept(reply(m, "1700000002.000100", "<@UBOT> go on", { addressed: true }));
    await settle();
    const next = r.claude.last();
    assert.notEqual(next, claude);
    await r.hub.receive("cl", stop);
    await r.hub.receive("cl", delayed);
    assert.equal(next.aborts, 0);
    await time.adjust(1_000);
    await r.hub.receive("cl", { ...stop, ts: slackTs(time.clock.currentTimeMillisUnsafe()) });
    assert.equal(next.aborts, 1);
  } finally {
    await r.close();
  }
});

test("a failed interrupt is not acknowledged; Slack's retry still targets the same turn", async () => {
  const time = testClock();
  await time.adjust(1_700_000_000_000);
  const r = new Rig({ clock: time.clock });
  try {
    const m = message();
    await r.accept(m);
    await settle();
    const session = r.claude.last();
    let attempts = 0;
    session.abort = async () => {
      attempts++;
      if (attempts === 1) throw new Error("interrupt failed");
    };
    await time.adjust(1_000);
    const stop = { type: "stop" as const, channel: m.channel, threadTs: m.threadTs, ts: slackTs(time.clock.currentTimeMillisUnsafe()) };
    await assert.rejects(r.hub.receive("cl", stop), /interrupt failed/);
    await r.hub.receive("cl", stop);
    await r.hub.receive("cl", stop);
    assert.equal(attempts, 2);
  } finally {
    await r.close();
  }
});

test("a late stop cannot reach a new turn within the same Slack clock second", async () => {
  const time = testClock();
  await time.adjust(1_700_000_000_000);
  const r = new Rig({ clock: time.clock });
  try {
    const m = message({ ts: "1700000000.000100", threadTs: "1700000000.000100" });
    await r.accept(m);
    await settle();
    await r.hub.actor(r.store.getSession(`cl:${m.channel}:${m.threadTs}`)!).declare({ kind: "all_done" });
    r.claude.last().end({ kind: "completed" });
    await settle();
    await time.adjust(200);
    await r.accept(reply(m, "1700000000.200000", "<@UBOT> new turn", { addressed: true }));
    await settle();
    const next = r.claude.last();
    assert.equal(next.busy(), true);
    // The HTTP Date is only accurate to a second, so the latest possible local time is after this new turn started.
    await r.hub.receive("cl", { type: "stop", channel: m.channel, threadTs: m.threadTs, ts: "1700000000.100000", localAt: time.clock.currentTimeMillisUnsafe() + 800 });
    assert.equal(next.aborts, 0);
    await time.adjust(100);
    await r.hub.receive("cl", { type: "stop", channel: m.channel, threadTs: m.threadTs, ts: "1700000000.300000", localAt: time.clock.currentTimeMillisUnsafe() });
    assert.equal(next.aborts, 1);
  } finally {
    await r.close();
  }
});

test("a stop is not rejected because a later message steered the same turn", async () => {
  const time = testClock();
  await time.adjust(1_700_000_000_000);
  const r = new Rig({ clock: time.clock });
  try {
    const m = message({ ts: "1700000000.000100", threadTs: "1700000000.000100" });
    await r.accept(m);
    await settle();
    const session = r.claude.last();
    await time.adjust(200);
    await r.accept(reply(m, "1700000000.200000", "<@UBOT> another detail", { addressed: true }));
    await settle();
    assert.equal(session.steers.length, 1);
    await r.hub.receive("cl", { type: "stop", channel: m.channel, threadTs: m.threadTs, ts: "1700000000.100000", localAt: null });
    assert.equal(session.aborts, 1);
  } finally {
    await r.close();
  }
});

test("a stop clicked while the runtime is starting interrupts the turn once it is ready", async () => {
  const time = testClock();
  await time.adjust(1_700_000_000_000);
  const r = new Rig({ clock: time.clock });
  let release!: () => void;
  let opened!: () => void;
  const gate = new Promise<void>((resolve) => (release = resolve));
  const starting = new Promise<void>((resolve) => (opened = resolve));
  const open = r.claude.open.bind(r.claude);
  r.claude.open = async (...args) => {
    opened();
    await gate;
    return open(...args);
  };
  try {
    const m = message();
    await r.accept(m);
    await starting;
    await time.adjust(1_000);
    const stopping = r.hub.receive("cl", { type: "stop", channel: m.channel, threadTs: m.threadTs, ts: slackTs(time.clock.currentTimeMillisUnsafe()) });
    release();
    await stopping;
    assert.equal(r.claude.last().aborts, 1);
  } finally {
    release();
    await r.close();
  }
});

test("a stop uses Slack's clock, including when the station's clock is ahead", async () => {
  const time = testClock();
  await time.adjust(1_700_000_600_000);
  const r = new Rig({ clock: time.clock });
  try {
    const m = message({ ts: "1700000000.000100", threadTs: "1700000000.000100" });
    await r.accept(m);
    await settle();
    const session = r.claude.last();
    await time.adjust(1_000);
    await r.hub.receive("cl", { type: "stop", channel: m.channel, threadTs: m.threadTs, ts: "1700000001.000000", localAt: time.clock.currentTimeMillisUnsafe() });
    assert.equal(session.aborts, 1);
  } finally {
    await r.close();
  }
});

test("without a Slack Date header, a stop is compared to the Slack message time", async () => {
  const time = testClock();
  await time.adjust(1_700_000_600_000);
  const r = new Rig({ clock: time.clock });
  try {
    const m = message({ ts: "1700000000.000100", threadTs: "1700000000.000100" });
    await r.accept(m);
    await settle();
    await r.hub.receive("cl", { type: "stop", channel: m.channel, threadTs: m.threadTs, ts: "1700000001.000000", localAt: null });
    assert.equal(r.claude.last().aborts, 1);
  } finally {
    await r.close();
  }
});
