// wake.rs's tests, ported (same names, same checks): fibers in place of polled futures.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect, Exit, Queue, type Fiber } from "effect";
import { HostError } from "../src/error.ts";
import type { HttpRequest, HttpResponse, Pull } from "../src/host.ts";
import { FakeHost, flush, jsonResponse } from "../src/testing.ts";
import { DROPPED, GONE, HEDGE, NETWORK, QUIET_MS, STREAM_AWAY_MS, Wake, Wakes, hedgeable, hedged, quietEnds, unlessDropped } from "../src/wake.ts";

const wake = (at: number, away: number) => new Wake(at, away, false, false);

/// A fiber's outcome, once it has one.
function watch<A, E>(effect: Effect.Effect<A, E>) {
  const fiber: Fiber.Fiber<A, E> = Effect.runFork(effect);
  let exit: Exit.Exit<A, E> | null = null;
  fiber.addObserver((e) => (exit = e));
  return {
    pending: async () => {
      await flush();
      return exit === null;
    },
    done: async () => {
      await flush();
      return exit as Exit.Exit<A, E> | null;
    },
  };
}
const errorOf = (exit: Exit.Exit<unknown, HostError> | null) => {
  if (!exit || !Exit.isFailure(exit)) return null;
  const r = Effect.runSync(Effect.result(exit as Effect.Effect<unknown, HostError>));
  return r._tag === "Failure" ? r.failure.message : null;
};

test("a_request_long_unanswered_fails_when_the_page_is_back", async () => {
  const wakes = new Wakes();
  const request = watch(unlessDropped(wakes, 1_000, Effect.never as Effect.Effect<void, HostError>));
  // Back after a short while: it may still come.
  wakes.wake(wake(3_000, 1_500));
  assert.ok(await request.pending());
  // Away long enough, but it was only just sent (the page asking again as it came back): left alone.
  wakes.wake(wake(1_000 + QUIET_MS - 1, 60_000));
  assert.ok(await request.pending());
  // Sent while the page was away (an app in the background still runs a while), unanswered since: given up.
  wakes.wake(wake(60_000, 59_500));
  assert.equal(errorOf(await request.done()), DROPPED);
});

const get: HttpRequest = { method: "GET", url: "https://x/y", headers: [], body: null };

test("a_read_under_way_is_asked_again_beside_itself_and_the_first_answer_is_its", async () => {
  const host = new FakeHost();
  let asked = 0;
  host.onFetch(() => {
    asked++;
    return { status: 200, headers: [], body: new TextEncoder().encode("second") };
  });
  const wakes = new Wakes();
  // The first is on a connection that is gone: it never answers.
  let firstGone = true;
  const ask = Effect.suspend(() => {
    if (firstGone) {
      firstGone = false;
      return Effect.never as Effect.Effect<HttpResponse, HostError>;
    }
    return host.fetch(get);
  });
  const answer = watch(hedged(wakes, host, ask));
  assert.ok(await answer.pending());
  wakes.wake(new Wake(host.nowMs(), 0, true, false));
  const exit = await answer.done();
  assert.ok(exit && Exit.isSuccess(exit));
  assert.equal(new TextDecoder().decode((exit as Exit.Success<HttpResponse, HostError>).value.body), "second");
  assert.equal(asked, 1);
});

test("only_reads_and_what_says_so_are_asked_twice", () => {
  const request = (method: string, headers: [string, string][]): HttpRequest => ({ method, url: "", headers, body: null });
  assert.ok(hedgeable(request("GET", [])));
  assert.ok(!hedgeable(request("POST", [])));
  assert.ok(hedgeable(request("POST", [[HEDGE, "1"]])));
});

test("the_network_changing_fails_every_request_under_way", async () => {
  const wakes = new Wakes();
  const request = watch(unlessDropped(wakes, 1_000, Effect.never as Effect.Effect<void, HostError>));
  assert.ok(await request.pending());
  wakes.wake(new Wake(1_001, 0, true, false));
  assert.equal(errorOf(await request.done()), NETWORK);
});

test("a_retry_fails_nothing_under_way_and_asks_a_read_again_beside_itself", async () => {
  const wakes = new Wakes();
  const retry = (at: number) => new Wake(at, 0, false, true);
  // A write under way: left to answer.
  const write = watch(unlessDropped(wakes, 1_000, Effect.never as Effect.Effect<void, HostError>));
  assert.ok(await write.pending());
  wakes.wake(retry(60_000));
  assert.ok(await write.pending());
  // A read under way: asked again beside it, the first answer its.
  const host = new FakeHost();
  host.onFetch(() => jsonResponse(200, "again"));
  let first = true;
  const ask = Effect.suspend(() => {
    if (first) {
      first = false;
      return Effect.never as Effect.Effect<HttpResponse, HostError>;
    }
    return host.fetch(get);
  });
  const answer = watch(hedged(wakes, host, ask));
  assert.ok(await answer.pending());
  wakes.wake(retry(host.nowMs()));
  const exit = await answer.done();
  assert.ok(exit && Exit.isSuccess(exit));
  assert.equal(new TextDecoder().decode((exit as Exit.Success<HttpResponse, HostError>).value.body), '"again"');
  // And the connections are suspect: the links are tried against new ones.
  assert.ok(retry(0).suspectsConnections());
  assert.ok(!retry(0).dropsStream(0));
});

test("a_stream_quiet_while_away_ends_and_one_that_spoke_goes_on", async () => {
  const host = new FakeHost();
  const wakes = new Wakes();
  const queue = Effect.runSync(Queue.unbounded<string>());
  const pull: Pull<string> = { take: Queue.take(queue) };
  const frames = quietEnds(host, wakes, pull);
  Queue.offerUnsafe(queue, "hello");
  assert.equal(await Effect.runPromise(frames.take), "hello");
  const heard = host.nowMs();
  const next = watch(frames.take);
  assert.ok(await next.pending());
  // It said something while the page was away: it is there.
  wakes.wake(wake(heard + 1_000, STREAM_AWAY_MS + 5_000));
  assert.ok(await next.pending());
  // Away not long enough to tell.
  wakes.wake(wake(heard + 20_000, 10_000));
  assert.ok(await next.pending());
  // Nothing since before the page went away: it ends.
  wakes.wake(wake(heard + STREAM_AWAY_MS + 10_000, STREAM_AWAY_MS));
  assert.equal(errorOf(await next.done()), GONE);
});

test("a_stream_opened_while_away_and_quiet_since_ends", async () => {
  const host = new FakeHost();
  const wakes = new Wakes();
  const queue = Effect.runSync(Queue.unbounded<string>());
  const opened = host.nowMs();
  const frames = quietEnds(host, wakes, { take: Queue.take(queue) });
  const next = watch(frames.take);
  assert.ok(await next.pending());
  // The page went away before it opened (it was opened in the background), and nothing came since.
  wakes.wake(wake(opened + STREAM_AWAY_MS, STREAM_AWAY_MS + 60_000));
  assert.equal(errorOf(await next.done()), GONE);
});
