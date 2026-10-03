// After an agent ends a turn all_done (or final), whether the chat has nothing left to do (the Rust station's hub.rs
// `suggest_archive`). As main has it since migration note 21: all_done is not reviewed before it is posted or recorded;
// the review runs on its own afterwards, asked of the decision model with the latest messages that fit, newest first.
// A chat it finds finished is recommended for the archive (until anyone says anything in it again); one it finds
// unfinished, or cannot tell, is not. It never holds an agent back.
import { Effect } from "effect";
import type { MessageRow } from "../store/store.ts";
import { type Capability, type ChoiceResult, acceptsCompletion, archiveQuestion, decide, type DecisionConfig, resolvedModel } from "./decision.ts";
import type { Hub } from "./hub.ts";
import { usable } from "./pool.ts";

type Json = any;

/// The decision reads the latest messages of a chat that fit these: how many it is given, and how many bytes of them.
const ARCHIVE_REVIEW_MESSAGES = 400;
const ARCHIVE_REVIEW_BYTES = 80_000;

/// Starts the review in the background (a fiber of the hub's).
export function suggestArchive(hub: Hub, key: string) {
  hub.fork(Effect.promise(() => review(hub, key).catch(() => {})));
}

/// The review itself; resolves once its result is recorded.
export async function review(hub: Hub, key: string): Promise<void> {
  const rule = hub.config().automaticDecisions.completion;
  if (!rule.enabled) return;
  const candidates: [string, DecisionConfig][] = [];
  for (const profile of hub.config().profiles) {
    const health = hub.accounts.healthOf(profile.id);
    if (!usable(health)) continue;
    const capability = health.check?.decision as Capability | undefined;
    const config = capability ? resolvedModel(profile, capability, rule.model) : undefined;
    if (config) candidates.push([profile.id, config]);
  }
  const record = (detail: Json) => {
    try {
      hub.store.recordDecision(key, detail);
    } catch {}
  };
  if (candidates.length === 0) {
    record({ purpose: "archive", version: 2, model: rule.model ?? "", accepted: false, elapsedMs: 0, error: "配置的模型在现有 Profile 中暂不可用" });
    return;
  }
  const started = Date.now();
  const versions: [number, number][] = [];
  let selected = 0;
  let reviewed: { ok: ChoiceResult } | { error: string };
  try {
    // The chat as it is now: each thread this agent closes, its latest messages while they fit.
    const conversations: Json[] = [];
    for (const thread of hub.store.sessionThreads(key)) {
      const id = thread.thread.id;
      const version = hub.store.lastEntry(id);
      const messages = hub.store.messagesBefore(id, null, ARCHIVE_REVIEW_MESSAGES + 1);
      const omitted = messages.length > ARCHIVE_REVIEW_MESSAGES;
      if (omitted) messages.shift();
      const shown = (m: MessageRow) => ({ authorKind: m.authorKind, author: m.author, text: m.text, ts: m.ts, hasAttachments: m.attachments.length > 0 });
      // Newest first, as many as fit; the ones that did not are older, and said so.
      const kept: Json[] = [];
      let size = 0;
      for (const m of [...messages].reverse()) {
        const view = shown(m);
        size += Buffer.byteLength(JSON.stringify(view));
        if (size > ARCHIVE_REVIEW_BYTES && kept.length > 0) break;
        kept.push(view);
      }
      const older = messages.length - kept.length;
      kept.reverse();
      const pending = hub.store.pendingCard(id);
      conversations.push({ thread: id, messages: kept, olderMessagesLeftOut: older > 0 || omitted, pendingCard: pending ? { ts: pending[0].ts, text: pending[0].text } : null });
      versions.push([id, version]);
    }
    if (conversations.length === 0) throw new Error("archive review has no conversation evidence");
    const state = { agent: key, conversations, attachmentContentsAvailable: false };
    let answer: { ok: ChoiceResult } | { error: string } = { error: "no decision profile available" };
    for (let i = 0; i < candidates.length; i++) {
      selected = i;
      try {
        answer = { ok: await decide(candidates[i]![1], archiveQuestion(), state) };
        break;
      } catch (error) {
        answer = { error: (error as Error).message };
      }
    }
    reviewed = answer;
  } catch (error) {
    reviewed = { error: (error as Error).message };
  }
  const config = candidates[selected]![1];
  const accepted = "ok" in reviewed && acceptsCompletion(reviewed.ok, config.threshold);
  // Said while the chat stood still: anything said since makes it a question for another review.
  const now = hub.config().automaticDecisions.completion;
  const unchanged = versions.every(([id, version]) => hub.store.lastEntry(id) === version) && now.enabled === rule.enabled && now.model === rule.model;
  record({
    purpose: "archive",
    version: 2,
    profile: candidates[selected]![0],
    provider: config.provider,
    model: config.model,
    threshold: config.threshold,
    elapsedMs: Date.now() - started,
    threads: versions,
    accepted: accepted && unchanged,
    result: "ok" in reviewed ? reviewed.ok : null,
    error: "error" in reviewed ? reviewed.error : null,
  });
  if (!unchanged) return;
  for (const [id, version] of versions) {
    try {
      if (accepted) hub.store.suggestArchive(key, id, version);
      else hub.store.clearArchiveSuggestion(key, id);
    } catch {}
  }
}
