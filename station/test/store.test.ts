// the Rust station's store/tests.rs ported (same names, same checks), and what else the write side promises: cards closed
// and withdrawn, turns, jobs, bindings and usage.
import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { constants, DatabaseSync } from "node:sqlite";
import { after, test } from "node:test";
import { zstdDecompressSync } from "node:zlib";
import {
  ANY_RUNNING, AUTO, type AuthorKind, CARD_BEFORE, CLOSED_CARD_AFTER_POSTS, CLOSED_THREAD_SINCE, DELIVERY_INSERT_IF_ABSENT, DELIVERY_INSERT_IF_MEMBER, type EntryRow, HEARD_IN, JOBS_RUNNING, JOBS_UP, JOB_AT_PORT, type JobRow, LATEST_DECISIONS, LATEST_DECISIONS_SCOPED_NO_TIME, LEGACY_LATEST_DECISIONS, LEGACY_LATEST_DECISIONS_SCOPED, LEGACY_LATEST_DECISIONS_SCOPED_FALLBACK, LIVE_SESSIONS, LOGIN_CARDS, MODELS_USED_BY,
  MANUAL, MEMBER_JOIN_IF_NEEDED, type NewMessage, OPTIONS_BEFORE, PEOPLE_SAID_AFTER, POST_AFTER_FIRST, POST_AFTER_INDEXED, POST_BLOCKS_READY, ROUTER_WORKSPACE_MISMATCH, RUNNING_SESSIONS, SAID_SINCE, SCHEMA_VERSION, SESSION_JOBS, SESSION_OF_RUNTIME, SESSION_THREAD_BY_ID, STATS_OF, Store, type StoreChange, THREAD_INSERT_IF_ABSENT, decisionScopedWithSession, newMessage,
} from "../src/store/store.ts";
import { addClientColumn, addListState, firstDelivery, MERGED, SCHEMA } from "../src/store/schema.ts";
import { ARCHIVE_POLICY, LEGACY_ARCHIVE_POLICY, installArchivePolicyIndex } from "../src/store/archive-policy-index.ts";
import { installDecisionTimeIndex } from "../src/store/legacy-decision-time.ts";
import { LEGACY_LAST_DECISION_REPAIR, installDecisionSessionIndex } from "../src/store/legacy-decision-session.ts";
import { installLegacyEdits, legacyEditStep } from "../src/store/legacy-edits-build.ts";
import { installLegacySaid, LEGACY_SAID_BOUNDARY_TAIL, LEGACY_SAID_DRAIN, LEGACY_SAID_DRAIN_THREAD,
  LEGACY_SAID_HEAD_FIRST, LEGACY_SAID_HEAD_TAIL, LEGACY_SAID_NEEDS_DRAIN } from "../src/store/legacy-said-build.ts";
import { ARCHIVE_LAST_FIRST, ARCHIVE_LAST_GUARD, ARCHIVE_LAST_LETTER_AFTER, ARCHIVE_LAST_LETTER_ANY,
  ARCHIVE_LAST_SAID_KEY, ARCHIVE_LAST_SLICE_BEFORE, ARCHIVE_LAST_SLICE_FIRST, ARCHIVE_LAST_TAIL } from "../src/store/archive-last.ts";
import { CC_THREADS_SQL } from "../src/store/rows.ts";
import { LATEST_THREAD_ATTEMPT, LATEST_THREAD_SCOPE } from "../src/store/latest-thread-index.ts";
import { CARD_POST_AFTER, CARD_POST_BEFORE, CARD_POST_LATEST, CARD_POST_NEXT, CARD_POST_SAMPLE } from "../src/store/card-post-index.ts";
import { SESSION_COUNT_FIRST, SESSION_COUNT_NEXT, SESSION_COUNT_TOTAL, SESSION_COUNT_CONNECT, SESSION_COUNT_DISPLACED } from "../src/store/session-counts.ts";
import { SESSION_LIST_CONNECT, SESSION_LIST_DISPLACED, SESSION_LIST_FIRST, SESSION_LIST_NEXT, SESSION_LIST_SCOPE,
  SESSION_LIST_SCOPE_CONNECT } from "../src/store/session-list-index.ts";
import { SESSION_BINDINGS_DELETE, SESSION_BINDINGS_DISPLACED, SESSION_BINDINGS_EXISTS, SESSION_BINDINGS_FIRST, SESSION_BINDINGS_NEXT, SESSION_BINDINGS_SELECTED } from "../src/store/session-bindings-index.ts";
import { ARCHIVE_KEEP_EXISTS, ARCHIVE_PIN_EXISTS } from "../src/store/archive-mark-index.ts";
import { WIDGET_SOURCE, WIDGET_SOURCE_MISSING, WIDGET_SOURCE_POSITIONS_FIRST, WIDGET_SOURCE_POSITIONS_NEXT,
  WIDGET_SOURCE_UNUSUAL, widgetSourcesStep } from "../src/store/widget-sources.ts";
import { SESSION_UP_JOB, SESSION_UP_JOBS, SESSION_UP_JOBS_CONFLICT, SESSION_UP_JOBS_DISPLACED, SESSION_UP_JOBS_END, SESSION_UP_JOBS_FIRST, SESSION_UP_JOBS_NEXT } from "../src/store/session-up-jobs.ts";
import { ACTIVE_SESSIONS, TAKEN_SINCE, TURNS_BETWEEN, TURNS_FROM } from "../src/store/usage.ts";
import { detailQuery } from "../src/store/usage-detail.ts";
import { installCompactUsage } from "../src/store/usage-compact.ts";
import { installUsageSummaryBlocks, usageSummaryBlocksRangeScan, usageSummaryBlocksScan } from "../src/store/usage-summary-blocks.ts";
import { REMOTE_RUNS_ALL, REMOTE_RUNS_OF } from "../src/store/remote-runs.ts";
import { AWAKE_JOBS, REMOTE_QUEUE_JOBS, RUNNING_JOB_SESSIONS, RUNNING_WAIT_JOBS } from "../src/store/active-jobs.ts";
import { activeJobUpgradeStep, ACTIVE_JOB_CONFLICT, ACTIVE_JOB_END, ACTIVE_JOB_FIRST, ACTIVE_JOB_NEXT, ACTIVE_JOB_NULL_ID,
  ACTIVE_REMOTE_FIRST, ACTIVE_REMOTE_NEXT, REMOTE_QUEUE_PREPARED } from "../src/store/active-jobs-upgrade.ts";
import { HAS_SESSION_ACTIVE_WATCH } from "../src/store/watch-jobs.ts";
import { RECOVER_AWAKE_WAITS, RECOVER_BACKFILL_FIRST, RECOVER_BACKFILL_NEXT, RECOVER_WAITS } from "../src/store/recover-waits.ts";
import { AWAKE_BACKFILL_FIRST, AWAKE_BACKFILL_NEXT, AWAKE_WAIT_STATUS, reconcileAwakeWaits, syncAwakeWait } from "../src/store/awake-waits.ts";
import * as read from "../src/read/store.ts";
import { usageSummaryEdgeQuery } from "../src/read/usage-batched.ts";
import { usageSummaryBlockOverlayQuery, usageSummaryBlockPendingQuery, usageSummaryBlockQueries } from "../src/read/usage-summary-blocks.ts";
import { recentChatDisplacedEntry } from "../src/store/chat-list-entry-rowid.ts";
import { HISTORY_AFTER, HISTORY_DAYS, HISTORY_SCOPES, HISTORY_SEED_CALLS, HISTORY_TOTAL } from "../src/store/usage-history.ts";
import { installRecentChatIndex, RECENT_GLOBAL_PAGE } from "../src/store/chat-list-index.ts";
import { RECENT_DEFAULT_HOME_PAGE } from "../src/store/chat-list-home-index.ts";
import { installRecentHomeOverlap, RECENT_HOME_ORDER_PAGE, RECENT_HOME_WORKSPACE_ORDER_PAGE } from "../src/store/chat-list-home-overlap.ts";
import { RECENT_SCOPE_ORDER_PENDING, RECENT_SCOPE_ORDER_SMALL, RECENT_SCOPE_VISIBILITY_AMBIGUOUS, RECENT_SCOPE_VISIBILITY_HOME,
  RECENT_SCOPE_VISIBILITY_MEMBERS_SMALL, RECENT_SCOPE_VISIBILITY_PENDING, RECENT_SCOPE_VISIBILITY_ROWS_SMALL,
  RECENT_WORKSPACE_PAGE } from "../src/store/chat-list-scope-rows.ts";
import { recentScopeHomeMemberQueries } from "../src/store/chat-list-scope-journal.ts";
import { FIRST_SCOPE_CANDIDATE_SESSION, NEXT_SCOPE_CANDIDATE_SESSION, PUT_SCOPE_CANDIDATE, RECENT_SCOPE_MEMBER_EXISTS,
  REMOVE_SCOPE_CANDIDATE } from "../src/store/chat-list-scope-build.ts";
import { RECENT_CHAT_SCHEMA_VERSION } from "../src/store/chat-list-schema.ts";
import { FIRST_SCOPE_CONNECT, FIRST_SCOPE_HOME_THREADS, FIRST_SCOPE_MEMBER_THREADS, FIRST_SCOPE_OLD_SESSION, FIRST_SCOPE_SESSIONS,
  FIRST_SCOPE_SESSIONS_THROUGH, NEXT_SCOPE_CONNECT, NEXT_SCOPE_OLD_SESSION, SCOPE_HOME_THREADS, SCOPE_MEMBER_THREADS,
  SCOPE_MEMBER_WITHOUT_HOME, SCOPE_SESSIONS, SCOPE_SESSIONS_THROUGH } from "../src/store/chat-list-scope-source.ts";
import { FIRST_HOME_CHAT_MEMBERS, NEXT_HOME_CHAT_MEMBERS } from "../src/store/chat-list-home-source.ts";
import { type CardEnd, cardsEnded } from "../src/connects/card-ends.ts";
import { fileAway } from "./archived-before.ts";
import { referenceAnswersSince } from "./card-answer-reference.ts";
import { testClock } from "./hub-fakes.ts";
import type { Viewer } from "../src/mesh/credential.ts";
import { PENDING_BACKFILL_AFTER, PENDING_BODIES, PENDING_DUE, PENDING_MEMBER, PENDING_NO_TIME, PENDING_OTHER_TIME, PENDING_OWN, PENDING_SEED, PENDING_SEED_FIRST } from "../src/vault/pending-index.ts";
import { REBOX_BACKFILL_FIRST, REBOX_BACKFILL_NEXT, REBOX_READY } from "../src/vault/rebox-index.ts";
import { CARRIED_SAVE_PENDING, Secrets } from "../src/vault/secrets.ts";
import { VaultStore } from "../src/vault/store.ts";
import { enableSandboxIndex, runnerChoiceFromKeys, RUNNER_SESSION_CANDIDATES, RUNNER_TAKEUP_NAMES, RUNNER_TAKEUP_SESSIONS, SANDBOX_DIRTY_BATCH, SANDBOX_PRUNE_FIRST, SANDBOX_PRUNE_NEXT, SANDBOX_SCAN_FIRST,
  SANDBOX_SCAN_NEXT, SANDBOX_SESSION } from "../src/store/sandbox-index.ts";
import { installSessionDirectories, sessionDirectoryCandidate, sessionDirectoryChoice, SESSION_DIR_ARGUMENTS, SESSION_DIR_DIRTY, SESSION_DIR_FIRST, SESSION_DIR_INITIAL, SESSION_DIR_LIVE_FEW, SESSION_DIR_LIVE_MANY, SESSION_DIR_NEXT } from "../src/store/session-directory.ts";
import { installChatShareIndex, SHARE_DIRTY, SHARE_DUE, SHARE_FIRST, SHARE_LAPSED_WORKSPACE, SHARE_LIVE, SHARE_NEXT, SHARE_NEXT_TIME } from "../src/store/chat-share-index.ts";
import { installProcessJobs, PROCESS_JOBS, PROCESS_JOB_CONFLICT, PROCESS_JOB_END, PROCESS_JOB_FIRST, PROCESS_JOB_NEXT, PROCESS_JOB_NULL_ID } from "../src/store/process-jobs.ts";

const dirs: string[] = [];
const stores: Store[] = [];
after(() => {
  for (const s of stores) {
    try {
      s.close();
    } catch {}
  }
  for (const d of dirs) rmSync(d, { recursive: true, force: true });
});

function tempdir(): string {
  const d = mkdtempSync(join(tmpdir(), "store-test-"));
  dirs.push(d);
  return d;
}

function open(path: string, archive: string | null = null): Store {
  const s = Store.open(path, archive);
  stores.push(s);
  return s;
}

const memory = () => open(":memory:");

function assertSessionJobPlans() {
  const db = memory().db;
  const work = (db.prepare(`EXPLAIN QUERY PLAN ${RUNNING_JOB_SESSIONS}`).all('["a"]') as { detail: string }[]).map((r) => r.detail).join(" | ");
  assert.match(work, /SEARCH active_watch_jobs USING COVERING INDEX active_watch_jobs_session .*session=\?/);
  assert.match(work, /SEARCH active_other_jobs USING PRIMARY KEY .*session=\?/);
  assert.doesNotMatch(work, /SCAN (active_watch_jobs|active_other_jobs|jobs)\b/);
  const up = (db.prepare(`EXPLAIN QUERY PLAN ${read.PREPARED_UP_JOBS_OF}`).all("a") as { detail: string }[]).map((r) => r.detail);
  const upDetail = up.join(" | ");
  assert.ok(up.some((s) => s.startsWith("SEARCH i USING PRIMARY KEY") && s.includes("session=?")), upDetail);
  assert.ok(up.some((s) => s.startsWith("SEARCH j USING INTEGER PRIMARY KEY") && s.includes("rowid=?")), upDetail);
  assert.ok(up.every((s) => !/^SCAN (i|j|jobs)\b/.test(s)), upDetail);

  const watches = (db.prepare(`EXPLAIN QUERY PLAN ${read.WATCHING_ALL}`).all() as { detail: string }[]).map((r) => r.detail);
  const watchDetail = watches.join(" | ");
  assert.ok(watches.some((s) => /^SCAN w\b/.test(s)), watchDetail); // Only running watches are in this lookup.
  assert.ok(watches.some((s) => s.startsWith("SEARCH j ") && s.includes("id=?")), watchDetail);
  assert.ok(watches.every((s) => !/^SCAN (j|jobs)\b/.test(s)), watchDetail);
}

function assertProcessJobPlans() {
  const db = memory().db;
  installProcessJobs(db);
  const plan = (sql: string, ...args: (string | number)[]) =>
    (db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(...args) as { detail: string }[]).map((row) => row.detail).join(" | ");
  const groups = plan(PROCESS_JOBS);
  assert.match(groups, /SCAN p\b/); // This table contains only running process groups.
  assert.match(groups, /SEARCH j USING INDEX sqlite_autoindex_jobs_1 .*id=\?/);
  assert.doesNotMatch(groups, /SCAN (j|jobs)\b/);
  assert.match(plan(PROCESS_JOB_END), /SEARCH jobs USING COVERING INDEX jobs_state .*state=\?/);
  assert.match(plan(PROCESS_JOB_FIRST, "100", 64), /SEARCH jobs USING COVERING INDEX jobs_state .*rowid</);
  assert.match(plan(PROCESS_JOB_NEXT, "1", "100", 64), /SEARCH jobs USING COVERING INDEX jobs_state .*rowid>/);
  assert.match(plan(PROCESS_JOB_NULL_ID), /SEARCH jobs USING INDEX sqlite_autoindex_jobs_1 .*id=\?/);
  const conflicts = plan(PROCESS_JOB_CONFLICT, "a", "token", 1);
  assert.equal((conflicts.match(/SEARCH jobs USING/g) ?? []).length, 3, conflicts);
  assert.match(conflicts, /SEARCH j USING INTEGER PRIMARY KEY .*rowid=\?/);
  assert.doesNotMatch(conflicts, /jobs_up \(state=\?\)/);
}

function assertActiveJobUpgradePlans() {
  const db = memory().db;
  db.exec("DROP INDEX active_other_remote_jobs");
  activeJobUpgradeStep(db);
  const plan = (sql: string, ...args: (string | number)[]) =>
    (db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(...args) as { detail: string }[]).map((row) => row.detail).join(" | ");
  assert.match(plan(ACTIVE_JOB_END), /SEARCH jobs USING COVERING INDEX jobs_state .*state=\?/);
  assert.match(plan(ACTIVE_JOB_FIRST, "100", 64), /SEARCH jobs USING COVERING INDEX jobs_state .*rowid</);
  assert.match(plan(ACTIVE_JOB_NEXT, "1", "100", 64), /SEARCH jobs USING COVERING INDEX jobs_state .*rowid>/);
  assert.match(plan(ACTIVE_JOB_NULL_ID), /SEARCH jobs USING INDEX sqlite_autoindex_jobs_1 .*id=\?/);
  const conflicts = plan(ACTIVE_JOB_CONFLICT, "a", "token", 1);
  assert.equal((conflicts.match(/SEARCH jobs USING/g) ?? []).length, 3, conflicts);
  assert.match(conflicts, /SEARCH j USING INTEGER PRIMARY KEY .*rowid=\?/);
  assert.doesNotMatch(conflicts, /jobs_up \(state=\?\)/);
  assert.match(plan(ACTIVE_REMOTE_FIRST, "s", "j", 64), /SEARCH active_other_jobs USING PRIMARY KEY/);
  assert.match(plan(ACTIVE_REMOTE_NEXT, "a", "j", "z", "j", 64), /SEARCH active_other_jobs USING PRIMARY KEY/);
  const remote = plan(REMOTE_QUEUE_PREPARED);
  assert.match(remote, /SEARCH w USING PRIMARY KEY .*job>\?/);
  assert.match(remote, /SEARCH a USING PRIMARY KEY .*job>\?/);
  assert.equal(remote.split(" | ").filter((s) => /SEARCH j USING INDEX sqlite_autoindex_jobs_1 .*id=\?/.test(s)).length, 2, remote);
  assert.doesNotMatch(remote, /SCAN (a|w|j|jobs)\b/);
}

function assertSandboxPlans() {
  const db = memory().db;
  enableSandboxIndex(db);
  const plan = (sql: string, ...args: (string | number)[]) =>
    (db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(...args) as { detail: string }[]).map((row) => row.detail).join(" | ");
  for (const sql of [SANDBOX_SESSION, RUNNER_SESSION_CANDIDATES]) {
    const lookup = plan(sql, "s");
    assert.match(lookup, /SEARCH n USING (?:COVERING )?INDEX sandbox_name_lookup .*name=\?/);
    assert.match(lookup, /SEARCH s USING INDEX sqlite_autoindex_sessions_1 .*key=\?/);
    assert.doesNotMatch(lookup, /SCAN (n|s|sessions)\b/);
  }
  assert.match(plan(runnerChoiceFromKeys(2), "a", "b"), /SEARCH s USING INDEX sqlite_autoindex_sessions_1 .*key=\?/);
  assert.match(plan(RUNNER_TAKEUP_NAMES, "s"), /SEARCH sandbox_name_rows USING COVERING INDEX sandbox_name_lookup .*name=\?/);
  const takeup = plan(RUNNER_TAKEUP_SESSIONS, '["a","b"]');
  assert.match(takeup, /SCAN sessions USING INDEX sessions_running/);
  assert.match(takeup, /SEARCH s USING INDEX sqlite_autoindex_sessions_1 .*key=\?/);
  assert.doesNotMatch(takeup, /SCAN s\b/);
  for (const sql of [SANDBOX_SCAN_FIRST, SANDBOX_SCAN_NEXT, SANDBOX_PRUNE_FIRST, SANDBOX_PRUNE_NEXT, SANDBOX_DIRTY_BATCH])
    assert.match(sql, /LIMIT \?$/);
  assert.match(plan(SANDBOX_SCAN_NEXT, "s", "z", 64), /SEARCH sessions USING COVERING INDEX sqlite_autoindex_sessions_1 .*key>\?/);
  assert.match(plan(SANDBOX_PRUNE_NEXT, "s", "z", 64), /SEARCH sandbox_name_rows USING PRIMARY KEY .*session>\?/);
}

function assertChatSharePlans() {
  const db = memory().db;
  installChatShareIndex(db);
  const plan = (sql: string, ...args: (string | number)[]) =>
    (db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(...args) as { detail: string }[]).map((row) => row.detail).join(" | ");
  for (const [sql, args] of [[SHARE_LIVE, [0]], [SHARE_DUE, [0, 1]]] as const) {
    const p = plan(sql, ...args);
    assert.match(p, /SEARCH t USING COVERING INDEX chat_share_target_time .*used>\?/);
    assert.match(p, /SEARCH c USING INDEX sqlite_autoindex_chat_shares_1 .*session=\?/);
    assert.doesNotMatch(p, /SCAN (?:t|c|chat_shares)\b/);
  }
  assert.match(plan(SHARE_NEXT_TIME, 0), /SEARCH t USING COVERING INDEX chat_share_target_time .*used>\?/);
  assert.match(plan(SHARE_LAPSED_WORKSPACE, "w", 0), /SEARCH t USING COVERING INDEX chat_share_target_workspace .*workspace=\? AND used<\?/);
  assert.match(plan(SHARE_NEXT, "s", "z", 64), /SEARCH chat_shares USING COVERING INDEX sqlite_autoindex_chat_shares_1 .*session>\?/);
  for (const sql of [SHARE_FIRST, SHARE_NEXT, SHARE_DIRTY]) assert.match(sql, /LIMIT \?$/);
}

function assertSessionDirectoryPlans() {
  const db = memory().db;
  installSessionDirectories(db);
  const plan = (sql: string, ...args: (string | number)[]) =>
    (db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(...args) as { detail: string }[]).map((row) => row.detail).join(" | ");
  for (const live of [true, false]) {
    const candidate = plan(sessionDirectoryCandidate(live), "/a");
    assert.match(candidate, /SEARCH d USING COVERING INDEX session_dir_root .*root=\?/);
    assert.match(candidate, /SEARCH s USING INDEX sqlite_autoindex_sessions_1 .*key=\?/);
    assert.doesNotMatch(candidate, /SCAN (d|s|sessions)\b/);
    assert.match(plan(sessionDirectoryChoice(2, live), "a", "b", "/a", "/a"), /SEARCH s USING INDEX sqlite_autoindex_sessions_1 .*key=\?/);
  }
  for (const sql of [SESSION_DIR_FIRST, SESSION_DIR_NEXT, SESSION_DIR_DIRTY]) assert.match(sql, /LIMIT \?$/);
  assert.match(plan(SESSION_DIR_NEXT, "a", "z", 64), /SEARCH sessions USING COVERING INDEX sqlite_autoindex_sessions_1 .*key>\?/);
  assert.match(plan(SESSION_DIR_LIVE_MANY), /SCAN sessions USING (?:COVERING )?INDEX sessions_live/);
  assert.match(SESSION_DIR_LIVE_MANY, /LIMIT 1 OFFSET 32$/);
  assert.match(plan(SESSION_DIR_LIVE_FEW), /SCAN sessions USING INDEX sessions_live/);
  assert.match(SESSION_DIR_LIVE_FEW, /LIMIT 32$/);
  assert.match(plan(SESSION_DIR_INITIAL, "/", "0"), /SEARCH session_dir_rows USING COVERING INDEX session_dir_root .*root>\?/);
  const argumentsPlan = plan(SESSION_DIR_ARGUMENTS, '["/a"]', "/home", '["a"]');
  assert.match(argumentsPlan, /SEARCH d USING COVERING INDEX session_dir_root .*root=\?/);
  assert.match(argumentsPlan, /SEARCH s USING INDEX sqlite_autoindex_sessions_1 .*key=\?/);
  assert.doesNotMatch(argumentsPlan, /SCAN (d|s|sessions)\b/);
}

function assertAwakeJobPlan() {
  const steps = (memory().db.prepare(`EXPLAIN QUERY PLAN ${AWAKE_JOBS}`).all() as { detail: string }[]).map((r) => r.detail);
  const detail = steps.join(" | ");
  assert.ok(steps.some((s) => /^SCAN w\b/.test(s)), detail); // The watch lookup contains only running watches.
  assert.ok(steps.some((s) => s.startsWith("SEARCH j ") && s.includes("id=?")), detail);
  assert.ok(steps.some((s) => s.includes("jobs_up") && s.includes("state=?") && s.includes("port=?")), detail);
  assert.ok(steps.every((s) => !/^SCAN (j|jobs)\b/.test(s)), detail);
}

function assertRemoteQueuePlan() {
  const steps = (memory().db.prepare(`EXPLAIN QUERY PLAN ${REMOTE_QUEUE_JOBS}`).all() as { detail: string }[]).map((r) => r.detail);
  const detail = steps.join(" | ");
  assert.ok(steps.some((s) => s.startsWith("SEARCH w ") && s.includes("job>?") && s.includes("job<?")), detail);
  assert.ok(steps.some((s) => s.startsWith("SEARCH a ") && s.includes("active_other_remote_jobs") && s.includes("job>?") && s.includes("job<?")), detail);
  assert.ok(steps.filter((s) => s.startsWith("SEARCH j ") && s.includes("id=?")).length >= 2, detail);
  assert.ok(steps.every((s) => !/^SCAN (a|w|j|jobs)\b/.test(s)), detail);
}

function assertRecoveryWaitPlans() {
  const db = memory().db;
  const plan = (sql: string, args: unknown[]) =>
    (db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(...(args as never[])) as { detail: string }[]).map((r) => r.detail);
  for (const sql of [RECOVER_WAITS, RECOVER_AWAKE_WAITS]) {
    const steps = plan(sql, []), detail = steps.join(" | ");
    assert.ok(steps.some((s) => /^SCAN w\b/.test(s)), detail); // Only the maintained waiting keys are enumerated.
    assert.ok(steps.some((s) => s.startsWith("SEARCH s ") && s.includes("key=?")), detail);
    assert.ok(steps.some((s) => s.includes("turns_by_session") && s.includes("session_key=?")), detail);
    assert.ok(steps.every((s) => !/^SCAN (s|t|turns)\b/.test(s)), detail);
  }
  for (const sql of [RECOVER_BACKFILL_FIRST, RECOVER_BACKFILL_NEXT]) assert.match(sql, /LIMIT \?$/);
  assert.ok(plan(RECOVER_BACKFILL_NEXT, ["a", 64]).some((s) => s.startsWith("SEARCH sessions ")), "backfill must seek after its cursor");
  const awake = plan(AWAKE_WAIT_STATUS, [0]).join(" | ");
  assert.match(awake, /SEARCH session_awake_deadlines USING PRIMARY KEY.*deadline>\?/);
  assert.match(awake, /SEARCH session_awake_deadlines USING PRIMARY KEY.*deadline=\?/);
  for (const sql of [AWAKE_BACKFILL_FIRST, AWAKE_BACKFILL_NEXT]) assert.match(sql, /LIMIT \?$/);
  assert.ok(plan(AWAKE_BACKFILL_NEXT, ["a", 64]).some((s) => s.startsWith("SEARCH session_recover_waits ")));
  for (const sql of syncAwakeWait("?1").split(";").filter((s) => s.trim())) {
    const steps = plan(sql, ["a"]), detail = steps.join(" | ");
    assert.ok(steps.every((s) => !/^SCAN (s|t|turns|session_recover_waits|session_awake_deadlines)\b/.test(s)), detail);
  }
  const staged = plan(reconcileAwakeWaits("session_recover_turn_stage"), []).join(" | ");
  assert.match(staged, /SEARCH session_recover_waits USING PRIMARY KEY/);
  assert.doesNotMatch(staged, /SCAN (sessions|turns|session_recover_waits|session_awake_deadlines)\b/);
}

function assertPendingVaultPlans() {
  const db = memory().db;
  const vaults = new VaultStore(db);
  new Secrets({ db, vaults, data: ".", now: () => 0, home: () => null, lock: () => null,
    hub: { store: { subscribe() {}, getSession() { return null; } } } as never, proxy: {} as never, plain: {} as never });
  const queries: [string, unknown[], string[]][] = [
    [PENDING_OWN, ["w", "alice"], ["vault_pending_decider", "SEARCH r USING INDEX"]],
    [PENDING_MEMBER, ["w", "alice"], ["SEARCH m USING PRIMARY KEY", "vault_pending_decider", "SEARCH r USING INDEX"]],
    [PENDING_DUE, ["w", 0], ["vault_pending_at", "SEARCH r USING INDEX"]],
    [PENDING_NO_TIME, ["w"], ["vault_pending_at", "SEARCH r USING INDEX"]],
    [PENDING_OTHER_TIME, ["w"], ["vault_pending_at", "SEARCH r USING INDEX"]],
    [PENDING_BODIES, ["w"], ["SEARCH p USING PRIMARY KEY", "SEARCH r USING INDEX"]],
    [PENDING_SEED_FIRST, ["w", 32], ["SEARCH p USING PRIMARY KEY", "SEARCH r USING INDEX"]],
    [PENDING_SEED, ["w", "r", 32], ["SEARCH p USING PRIMARY KEY", "SEARCH r USING INDEX"]],
    [PENDING_BACKFILL_AFTER, ["w", "r", 32], ["SEARCH vault_requests USING COVERING INDEX"]],
    [REBOX_BACKFILL_NEXT, ["w", "r", 32], ["SEARCH vault_requests USING COVERING INDEX"]],
    [CARRIED_SAVE_PENDING, ["w", "r"], ["SEARCH vault_requests USING INDEX"]],
  ];
  for (const [sql, args, expected] of queries) {
    const steps = (db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(...(args as never[])) as { detail: string }[]).map((row) => row.detail);
    const detail = `${sql}\n  ${steps.join(" | ")}`;
    assert.ok(steps.every((step) => !step.startsWith("SCAN ") && !step.includes("TEMP B-TREE")), detail);
    for (const part of expected) assert.ok(steps.some((step) => step.includes(part)), detail);
  }
  assert.match(REBOX_BACKFILL_FIRST, /LIMIT \?$/);
  assert.match(REBOX_BACKFILL_NEXT, /LIMIT \?$/);
  const firstPlan = (db.prepare(`EXPLAIN QUERY PLAN ${REBOX_BACKFILL_FIRST}`).all(32) as { detail: string }[]).map((row) => row.detail);
  assert.ok(firstPlan.some((step) => step.includes("SCAN vault_requests USING COVERING INDEX")), firstPlan.join(" | "));
  const reboxPlan = (db.prepare(`EXPLAIN QUERY PLAN ${REBOX_READY}`).all() as { detail: string }[]).map((row) => row.detail);
  assert.ok(reboxPlan.some((step) => step.startsWith("SCAN p")), reboxPlan.join(" | "));
  assert.ok(reboxPlan.some((step) => step.startsWith("SEARCH r USING") && step.includes("(ws=? AND id=?)")), reboxPlan.join(" | "));
  assert.ok(reboxPlan.every((step) => !step.startsWith("SCAN r")), reboxPlan.join(" | "));
}

function assertRecentChatPlans() {
  const db = memory().db;
  installRecentChatIndex(db);
  installRecentHomeOverlap(db);
  const plan = (sql: string, args: unknown[]) =>
    (db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(...(args as never[])) as { detail: string }[]).map((r) => r.detail);
  const versionSteps = plan(RECENT_CHAT_SCHEMA_VERSION, ["global", "recent_chat_meta"]);
  assert.ok(versionSteps.some((s) => s.startsWith("SEARCH ") && s.includes("PRIMARY KEY (part=?)")), versionSteps.join(" | "));
  const displacedSteps = plan(recentChatDisplacedEntry("?"), [1]);
  assert.ok(displacedSteps.some((s) => s.startsWith("SEARCH e ") && s.includes("INTEGER PRIMARY KEY (rowid=?)")), displacedSteps.join(" | "));
  assert.ok(displacedSteps.some((s) => s.startsWith("SEARCH s ") && s.includes("INTEGER PRIMARY KEY (rowid=?)")), displacedSteps.join(" | "));
  // An ordered scan is safe here only because the query stops at the requested page size.
  for (const [sql, args, index, seek] of [
    [RECENT_GLOBAL_PAGE, [5], "recent_chat_order", false],
    [RECENT_DEFAULT_HOME_PAGE, [5], "recent_home_order", false],
    [RECENT_HOME_ORDER_PAGE, [5], "recent_home_order", false],
    [RECENT_WORKSPACE_PAGE, ["ws", 5], "recent_scope_order", true],
    [RECENT_HOME_WORKSPACE_ORDER_PAGE, ["ws", 5], "recent_scope_order", true],
  ] as [string, unknown[], string, boolean][]) {
    const steps = plan(sql, args), detail = `${sql}\n  ${steps.join(" | ")}`;
    assert.match(sql, /LIMIT \?\s*$/);
    assert.ok(steps.some((s) => s.includes(index) && (seek ? s.startsWith("SEARCH ") && s.includes("ws=?") : s.startsWith("SCAN "))), detail);
    assert.ok(steps.every((s) => !s.includes("TEMP B-TREE")), detail);
  }
  // The pending-job input is limited before each primary-key lookup into the requested workspace.
  for (const sql of [RECENT_SCOPE_ORDER_PENDING, RECENT_SCOPE_VISIBILITY_PENDING]) {
    const steps = plan(sql, ["ws"]), detail = `${sql}\n  ${steps.join(" | ")}`;
    assert.match(sql, /ORDER BY thread LIMIT 65/);
    assert.ok(steps.some((s) => s.includes("SEARCH r USING PRIMARY KEY (ws=? AND thread=?)")), detail);
    assert.ok(steps.every((s) => !s.includes("TEMP B-TREE")), detail);
  }
  const visibilitySteps = plan(RECENT_SCOPE_VISIBILITY_AMBIGUOUS, ["ws"]);
  assert.match(RECENT_SCOPE_VISIBILITY_AMBIGUOUS, /ORDER BY thread LIMIT 65/);
  assert.ok(visibilitySteps.some((s) => s.startsWith("SEARCH c ") && s.includes("PRIMARY KEY (ws=? AND thread=?)")), visibilitySteps.join(" | "));
  for (const sql of [RECENT_SCOPE_ORDER_SMALL, RECENT_SCOPE_VISIBILITY_ROWS_SMALL, RECENT_SCOPE_VISIBILITY_MEMBERS_SMALL]) {
    const steps = plan(sql, ["ws"]), detail = `${sql}\n  ${steps.join(" | ")}`;
    assert.match(sql, /WHERE ws = \?1 ORDER BY thread(?:, session)? LIMIT 65/);
    assert.ok(steps.some((s) => s.startsWith("SEARCH ") && s.includes("PRIMARY KEY (ws=?)")), detail);
    assert.ok(steps.some((s) => s.startsWith("SEARCH d ") && s.includes("INTEGER PRIMARY KEY (rowid=?)")), detail);
    assert.ok(steps.every((s) => !s.includes("TEMP B-TREE")), detail);
  }
  const homeSteps = plan(RECENT_SCOPE_VISIBILITY_HOME, ["ws"]);
  assert.ok(homeSteps.some((s) => s.startsWith("SEARCH ") && s.includes("recent_scope_visibility_home") && s.includes("home_ws=?")),
    homeSteps.join(" | "));
  for (const sql of [PUT_SCOPE_CANDIDATE, REMOVE_SCOPE_CANDIDATE]) {
    const steps = plan(sql, ["ws", 1, "a"]);
    assert.ok(steps.some((s) => s.startsWith("SEARCH recent_scope_candidates ") && s.includes("PRIMARY KEY (ws=? AND thread=? AND session=?)")),
      `${sql}\n  ${steps.join(" | ")}`);
  }
  const memberSteps = plan(RECENT_SCOPE_MEMBER_EXISTS, [1, "a", "ws"]);
  assert.ok(memberSteps.some((s) => s.startsWith("SEARCH m ") && s.includes("thread=? AND session=?")), memberSteps.join(" | "));
  assert.ok(memberSteps.some((s) => s.startsWith("SEARCH s ") && s.includes("key=?")), memberSteps.join(" | "));
  const memberWrites = recentScopeHomeMemberQueries("?1");
  for (const sql of [memberWrites.update, memberWrites.insert]) {
    const steps = plan(sql, [1]), detail = `${sql}\n  ${steps.join(" | ")}`;
    assert.match(sql, /WHERE thread = \?1 ORDER BY session LIMIT 64/);
    assert.ok(steps.some((s) => s.startsWith("SEARCH ") && s.includes("thread_sessions") && s.includes("thread=?")), detail);
    assert.ok(steps.some((s) => s.startsWith("SEARCH ") && s.includes("PRIMARY KEY")), detail);
    assert.ok(steps.every((s) => !s.startsWith("SCAN recent_scope_member_dirty") && !s.includes("TEMP B-TREE")), detail);
  }
  // Old source scans seek each connection, workspace, session or chat before applying their batch limits.
  for (const [sql, args, index, seek] of [
    [FIRST_SCOPE_CONNECT, [], "sessions_by_connect", false], [NEXT_SCOPE_CONNECT, ["a"], "sessions_by_connect", true],
    [FIRST_SCOPE_SESSIONS, ["a", "ws", 5], "sessions_by_connect", true], [SCOPE_SESSIONS, ["a", "ws", 0n, 5], "sessions_by_connect", true],
    [FIRST_SCOPE_SESSIONS_THROUGH, ["a", "ws", 10n, 5], "sessions_by_connect", true],
    [SCOPE_SESSIONS_THROUGH, ["a", "ws", 0n, 10n, 5], "sessions_by_connect", true],
    [FIRST_SCOPE_OLD_SESSION, [10n], "INTEGER PRIMARY KEY", true], [NEXT_SCOPE_OLD_SESSION, [0n, 10n], "INTEGER PRIMARY KEY", true],
    [FIRST_SCOPE_CANDIDATE_SESSION, ["ws", "a", 5], "recent_scope_candidates_session", true],
    [NEXT_SCOPE_CANDIDATE_SESSION, ["ws", "a", 0n, 5], "recent_scope_candidates_session", true],
    [FIRST_SCOPE_HOME_THREADS, ["a", 5], "threads_home", true], [SCOPE_HOME_THREADS, ["a", 0n, 5], "threads_home", true],
    [FIRST_SCOPE_MEMBER_THREADS, ["a", 5], "thread_sessions_session", true], [SCOPE_MEMBER_THREADS, ["a", 0n, 5], "thread_sessions_session", true],
    [SCOPE_MEMBER_WITHOUT_HOME, [1], "INTEGER PRIMARY KEY", true],
    [FIRST_HOME_CHAT_MEMBERS, [1, 5], "thread_sessions", true], [NEXT_HOME_CHAT_MEMBERS, [1, "a", 5], "thread_sessions", true],
  ] as [string, unknown[], string, boolean][]) {
    const steps = plan(sql, args), detail = `${sql}\n  ${steps.join(" | ")}`;
    assert.ok(steps.some((s) => s.includes(index) && (seek ? s.startsWith("SEARCH ") : s.startsWith("SCAN "))), detail);
    assert.ok(steps.every((s) => !s.includes("TEMP B-TREE")), detail);
  }
}

function session(store: Store, key: string) {
  store.insertSession({ key, connect: "ds", runtime: "claude", profile: "cc", workspace: `/w/${key}`, token: key, createdAt: 1, lastActiveAt: 1 });
}

const say = (store: Store, thread: number, ts: string, kind: AuthorKind, author: string, text: string) =>
  store.insertMessage(newMessage(thread, ts, kind, author, text));

function heard(store: Store): { changes: StoreChange[]; stop: () => void } {
  const changes: StoreChange[] = [];
  return { changes, stop: store.subscribe((c) => changes.push(c)) };
}

const archiveFile = (store: Store, thread: number) => join(store.archiveDir(), "threads", `${thread}.jsonl.zst`);

test("a write waits its turn while another of the station's writers writes, not refused at once", () => {
  // Begun deferred, a transaction that read first was refused at its first write (SQLITE_BUSY_SNAPSHOT, "database is
  // locked", no wait) where another connection wrote meanwhile: the usage worker filling its statistics, and a person's
  // message was not sent (a station, 2026-11-03).
  const path = join(tempdir(), "s.db");
  const store = open(path);
  const other = new DatabaseSync(path, { timeout: 0 });
  // SQLite as it is: read, another writes, then write.
  const raw = new DatabaseSync(path, { timeout: 0 });
  raw.exec("BEGIN");
  raw.prepare("SELECT count(*) FROM sessions").get();
  other.exec("INSERT INTO kept_chats (viewer, thread) VALUES ('x', 1)");
  assert.throws(() => raw.exec("INSERT INTO kept_chats (viewer, thread) VALUES ('y', 2)"), /locked/);
  raw.exec("ROLLBACK");
  // The store's: the writing taken as it begins, so another writer waits for it (or is refused itself) instead.
  const begun: string[] = [];
  // (the connection itself's: the store's is a proxy that times what it runs, store/timed.ts)
  store.db.exec = function (this: DatabaseSync, sql: string) {
    begun.push(sql);
    return DatabaseSync.prototype.exec.call(this, sql);
  };
  session(store, "k");
  const thread = store.openThread("ember", "CHAT", "1.0", null, null).id;
  say(store, thread, "1.1", "person", "a@x", "hi");
  assert.ok(begun.length > 0 && begun.every((sql) => sql !== "BEGIN"), `every transaction takes the writing as it begins: ${begun.filter((s) => s.startsWith("BEGIN"))}`);
  assert.ok(begun.includes("BEGIN IMMEDIATE"));
  raw.close();
  other.close();
});

test("a database of another schema version is refused", () => {
  const path = join(tempdir(), "ember.db");
  const db = new DatabaseSync(path);
  db.exec("CREATE TABLE sessions (key TEXT); PRAGMA user_version = 8;");
  db.close();
  assert.throws(() => Store.open(path), /schema version 8; this station uses 13/);
});

test("a new database is made at version 13", () => {
  const path = join(tempdir(), "new.db");
  open(path).close();
  const db = new DatabaseSync(path, { readOnly: true });
  assert.equal((db.prepare("PRAGMA user_version").get() as any).user_version, SCHEMA_VERSION);
  assert.equal((db.prepare("PRAGMA journal_mode").get() as any).journal_mode, "wal");
  db.close();
});

test("a database from before the index on turns gets it as it is opened", () => {
  const path = join(tempdir(), "turns.db");
  open(path).close();
  const before = new DatabaseSync(path);
  before.exec("DROP INDEX turns_by_session");
  before.close();
  open(path).close();
  const db = new DatabaseSync(path, { readOnly: true });
  assert.ok(db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'index' AND name = 'turns_by_session'").get() !== undefined);
  // Each session's turns are found by it (sessionStats), not by reading every turn.
  const plan = db.prepare("EXPLAIN QUERY PLAN SELECT COUNT(*) FROM turns WHERE session_key = ?").all("k") as { detail: string }[];
  assert.ok(plan.some((p) => p.detail.includes("turns_by_session")), JSON.stringify(plan));
  db.close();
});

test("counting people for a title stops at the threshold even in a long conversation", () => {
  const store = memory();
  const thread = store.openThread("ember", "CHAT", "many", null, null).id;
  const insert = store.db.prepare("INSERT INTO entries (thread, n, kind, author_kind, author, text, at) VALUES (?, ?, 'message', 'person', 'p', 'hello', ?)");
  store.db.exec("BEGIN");
  for (let n = 1; n <= 2_000; n++) insert.run(thread, n, n);
  store.db.exec("COMMIT");
  const count = store.peopleSaidAfter.bind(store);
  assert.equal(count(thread, 0, 5), 5);
  assert.equal(count(thread, 1_998, 5), 2);
  assert.equal(count(thread, 2_000, 5), 0);
  assert.equal(count(thread, 0, 2), 2);
  assert.equal(count(thread, 0, 0), 0);
  const plan = store.db.prepare(`EXPLAIN QUERY PLAN ${PEOPLE_SAID_AFTER}`).all(thread, 0, 5) as { detail: string }[];
  assert.match(plan.map((p) => p.detail).join(" | "), /SEARCH entries USING (?:COVERING )?INDEX entries_people_by_n \(thread=\? AND n>\?\)/);
  let examined = 0;
  store.db.function("count_examined", (n) => { examined++; return n; });
  const probed = PEOPLE_SAID_AFTER.replace("n > ?", "n > ? AND count_examined(n) IS NOT NULL");
  const query = store.db.prepare(probed);
  assert.equal((query.get(thread, 0, 5) as { c: number }).c, 5);
  assert.equal(examined, 5, "only the messages needed for the decision are visited");
  examined = 0;
  assert.equal((query.get(thread, 1_000, 5) as { c: number }).c, 5);
  assert.equal(examined, 5, "more matching history does not increase the work");
});

test("a message is recorded once and delivered to every session in its thread", () => {
  const store = memory();
  session(store, "a");
  session(store, "b");
  const thread = store.openThread("slack:T1", "C1", "1.1", null, null);
  assert.equal(store.openThread("slack:T1", "C1", "1.1", null, null).id, thread.id);
  store.joinThread(thread.id, "a", "ds");
  assert.equal(store.joinThread(thread.id, "a", "ds"), false);
  store.joinThread(thread.id, "b", "gpt");
  const first = say(store, thread.id, "1.1", "person", "U1", "hi");
  assert.deepEqual(first, [1, true]);
  assert.deepEqual(say(store, thread.id, "1.1", "person", "U1", "hi"), [1, false]);
  assert.deepEqual(store.deliver(thread.id, first[0], ["a", "b"]), ["a", "b"]);
  assert.deepEqual(store.deliver(thread.id, first[0], ["a", "b"]), []);
  assert.deepEqual(store.pendingMessages("b").map((m) => [m.message.text, m.connect]), [["hi", "gpt"]]);
  const told = heard(store);
  store.markDelivered("a", [{ thread: thread.id, n: first[0], apart: false }]);
  told.stop();
  // How many it has yet to take, said with the change: devices are told it at once, not after its summary is read.
  assert.deepEqual(told.changes.filter((c) => c.type === "session"), [{ type: "session", key: "a", pending: 0 }]);
  assert.deepEqual(store.sessionsWithPending(), ["b"]);
  assert.equal(store.latestThread("a")!.thread.id, thread.id);
  assert.equal(store.sessionThread("b", "C1", "1.1")!.connect, "gpt");
  assert.equal(store.sessionThread("b", "C9", "1.1"), null);
});

const plain = (entries: EntryRow[]) => entries.map((e) => [e.n, e.kind, e.target !== null ? String(e.target) : (e.ts ?? ""), e.text ?? ""]);

test("a thread is a log, edits are entries of their own", () => {
  const store = memory();
  const thread = store.openThread("slack:T1", "C1", "1.1", null, null);
  const other = store.openThread("slack:T1", "C1", "2.1", null, null);
  for (const ts of ["1.1", "1.2", "1.3"]) say(store, thread.id, ts, "person", "U1", ts);
  say(store, other.id, "2.1", "person", "U1", "elsewhere");
  assert.equal(store.lastEntry(thread.id), 3);
  assert.deepEqual(store.entriesAfter(thread.id, 3), []);
  assert.equal(store.editMessage("slack:T1", "C1", "1.1", "1.1", "1.1 edited"), thread.id);
  assert.equal(store.editMessage("slack:T1", "C1", "1.1", "1.1", "1.1 edited"), null, "the same words are no change");
  assert.equal(store.editMessage("slack:T1", "C1", "1.1", "1.2", "1.2 edited"), thread.id);
  assert.equal(store.editMessage("slack:T1", "C1", "1.1", "9.9", "never seen"), null);
  store.insertMessage({ ...newMessage(thread.id, "1.4", "agent", "a", "new"), declared: "final" });
  assert.deepEqual(plain(store.entriesAfter(thread.id, 3)), [[4, "edit", "1", "1.1 edited"], [5, "edit", "2", "1.2 edited"], [6, "message", "1.4", "new"]]);
  // What was read stays true: the message entries are as they were said.
  assert.deepEqual(plain(store.entriesBetween(thread.id, 1, 2)), [[1, "message", "1.1", "1.1"], [2, "message", "1.2", "1.2"]]);
  assert.deepEqual(store.entriesBetween(thread.id, 5, 9).map((e) => e.n), [5, 6]);
  assert.deepEqual(store.entriesBefore(thread.id, 4, 2).map((e) => e.n), [2, 3]);
  assert.deepEqual(store.entriesBefore(thread.id, null, 2).map((e) => e.n), [5, 6]);
  assert.deepEqual(store.entriesAfter(other.id, 0).map((e) => e.n), [1], "each thread counts from 1");
  // Merged: the latest edit's words.
  const merged = store.messagesBefore(thread.id, null, 10).map((m) => [m.n, m.text, m.editedAt !== null]);
  assert.deepEqual(merged, [[1, "1.1 edited", true], [2, "1.2 edited", true], [3, "1.3", false], [6, "new", false]]);
  assert.deepEqual(store.messagesBefore(thread.id, 3, 1).map((m) => m.ts), ["1.2"]);
  assert.equal(store.lastMessage(thread.id)!.declared, "final");
  store.editMessage("slack:T1", "C1", "1.1", "1.1", "1.1 again");
  assert.equal(store.messagesBefore(thread.id, 2, 1)[0]!.text, "1.1 again", "the latest edit");
  // Each message's latest edit is found at once by the index of edits, as the station's SQLite (node's) plans it, not by
  // going back over the whole thread.
  const plan = (store.db.prepare("EXPLAIN QUERY PLAN SELECT * FROM merged WHERE thread = ? AND n = ?").all(thread.id, 1) as { detail: string }[]).map((r) => r.detail);
  assert.ok(plan.some((d) => d.includes("entries_edits (thread=? AND target=?)")), plan.join(" | "));
});

test("the prepared old edit lookup seeks one message's edits", () => {
  const store=memory(),thread=store.openThread("ember","CHAT","old-edit-plan",null,null).id;
  store.db.exec("CREATE INDEX entries_target ON entries(thread,target) WHERE target IS NOT NULL; DROP INDEX entries_edits");
  installLegacyEdits(store.db);
  while (!legacyEditStep(store.db).ready) { /* prepare */ }
  addClientColumn(store.db);
  const plan=store.db.prepare("EXPLAIN QUERY PLAN SELECT * FROM merged WHERE thread=? AND n=?").all(thread,1)
    .map((r) => String(r.detail)).join(" | ");
  assert.match(plan,/SEARCH s USING PRIMARY KEY \(thread=\? AND target=\?/,plan);
  assert.match(plan,/SEARCH t USING PRIMARY KEY \(thread=\? AND target=\?/,plan);
  assert.doesNotMatch(plan,/SCAN (?:s|t)\b/,plan);
});

test("a message still pending reaches the agent as it reads at delivery", () => {
  const store = memory();
  session(store, "a");
  const thread = store.openThread("slack:T1", "C1", "1.1", null, null);
  store.joinThread(thread.id, "a", "ds");
  for (const ts of ["1.1", "1.2"]) {
    const [n] = say(store, thread.id, ts, "person", "U1", ts);
    store.deliver(thread.id, n, ["a"]);
  }
  store.editMessage("slack:T1", "C1", "1.1", "1.1", "edited");
  assert.deepEqual(store.pendingMessages("a").map((m) => [m.message.n, m.message.text]), [[1, "edited"], [2, "1.2"]]);
  assert.equal(store.sessionStats("a").get("a")!.firstText, "edited");
});

test("reads move forward only and unread counts skip the viewer's own", () => {
  const store = memory();
  session(store, "a");
  const thread = store.openThread("slack:T1", "C1", "1.1", null, null);
  store.joinThread(thread.id, "a", "ds");
  const [mine] = say(store, thread.id, "1.2", "person", "me@x", "q");
  say(store, thread.id, "1.3", "agent", "a", "answer");
  say(store, thread.id, "1.4", "person", "you@x", "also");
  store.editMessage("slack:T1", "C1", "1.1", "1.3", "answer, edited");
  const view = (viewer: string) => store.listThreads(viewer, "a", null)[0]!;
  const me = view("me@x");
  assert.deepEqual([me.unread, me.read, me.last], [2, 0, 4]);
  assert.equal(store.unreadCount("me@x", thread.id), 2, "an edit is no message of its own");
  assert.equal(view("you@x").unread, 2);
  assert.equal(store.setRead("me@x", thread.id, mine + 1), mine + 1);
  assert.equal(store.setRead("me@x", thread.id, mine), mine + 1, "never back");
  const me2 = view("me@x");
  assert.deepEqual([me2.unread, me2.read], [1, mine + 1]);
  assert.equal(view("you@x").unread, 2, "each viewer reads for themselves");
  assert.deepEqual([view("me@x").lastMessage!.ts, view("you@x").lastMessage!.text], ["1.4", "also"]);
  // Its people, and the first thing one of them said.
  assert.deepEqual([view("me@x").people, view("me@x").firstText], [["slack:ds:me@x", "slack:ds:you@x"], "q"]);
  const slack = store.openThread("slack:T1", "C1", "2.1", null, null);
  store.joinThread(slack.id, "a", "ds");
  say(store, slack.id, "2.1", "agent", "a", "hello");
  say(store, slack.id, "2.2", "person", "U2", "<@UBOT> 看看");
  say(store, slack.id, "2.3", "person", "U1", "嗯");
  say(store, slack.id, "2.4", "person", "U2", "再看");
  const slackView = store.listThreads("me@x", null, slack.id)[0]!;
  assert.deepEqual([slackView.people, slackView.firstText], [["slack:ds:U2", "slack:ds:U1"], "<@UBOT> 看看"]);
  assert.deepEqual(store.listThreads("me@x", null, null).map((t) => t.thread.id), [slack.id, thread.id], "the latest said first");
});

test("an archived thread keeps its entries in the database", () => {
  const archive = tempdir();
  const store = open(":memory:", archive);
  session(store, "a");
  const own = store.openThread("ember", "CHAT", "2.1", null, null);
  store.joinThread(own.id, "a", "ember");
  say(store, own.id, "2.2", "person", "local", "看看");
  say(store, own.id, "2.3", "agent", "a", "好");
  const before = store.listThreads("local", null, own.id)[0];
  const entries = store.entriesAfter(own.id, 0);
  store.setArchived("a", true, MANUAL);
  assert.ok(!existsSync(join(archive, "threads", `${own.id}.jsonl.zst`)), "archived, its entries stay where they are");
  assert.deepEqual(store.entriesAfter(own.id, 0), entries);
  assert.deepEqual(store.listThreads("local", null, own.id)[0], before);
});

test("a database of version 12 has the threads a station before wrote out to files brought back, and goes to 13", () => {
  const data = tempdir();
  const path = join(data, "stillfail.db");
  const archive = join(data, "archive");
  const store = open(path, archive);
  session(store, "a");
  session(store, "b");
  const shared = store.openThread("slack:T1", "C1", "1.1", null, null);
  const own = store.openThread("ember", "CHAT", "2.1", null, null);
  store.joinThread(shared.id, "a", "ds");
  store.joinThread(shared.id, "b", "ds");
  store.joinThread(own.id, "a", "ember");
  const at = (m: NewMessage, at: number): NewMessage => ({ ...m, at });
  store.insertMessage(at(newMessage(own.id, "2.2", "person", "local", "看看"), 1));
  store.insertMessage(at(newMessage(own.id, "2.3", "agent", "a", "好"), 2));
  store.insertMessage(at(newMessage(shared.id, "1.1", "person", "U1", "hi"), 3));
  const before = store.listThreads("local", null, null);
  const entries = [store.entriesAfter(own.id, 0), store.entriesAfter(shared.id, 0)];
  store.setArchived("a", true, MANUAL);
  store.setArchived("b", true, MANUAL);
  const files = [fileAway(store, own.id), fileAway(store, shared.id)];
  // The shape the Rust station wrote (serde's EntryRow).
  const text = zstdDecompressSync(readFileSync(files[0]!)).toString("utf8");
  assert.ok(text.split("\n")[0]!.startsWith(`{"thread":${own.id},"n":1,"kind":"message","target":null,"ts":"2.2","authorKind":"person"`), text);
  store.db.exec("CREATE TABLE IF NOT EXISTS items (thread INTEGER)");
  store.close();

  const again = open(path, archive);
  assert.deepEqual([again.entriesAfter(own.id, 0), again.entriesAfter(shared.id, 0)], entries);
  assert.deepEqual(again.listThreads("local", null, null), before);
  assert.deepEqual(again.participants("a").get("a"), ["local", "slack:ds:U1"]);
  assert.ok(files.every((f) => !existsSync(f)), "the files go once their entries are back");
  const has = (type: string, name: string) => again.db.prepare("SELECT 1 FROM sqlite_master WHERE type = ? AND name = ?").get(type, name) !== undefined;
  assert.ok(!has("table", "items") && !has("index", "threads_archived"));
  assert.equal((again.db.prepare("PRAGMA user_version").get() as any).user_version, SCHEMA_VERSION);
  // Said in again, numbered on.
  assert.deepEqual(say(again, own.id, "2.4", "person", "local", "还在吗"), [3, true]);
});

test("what lists say of a thread and a session is kept as its messages are written, and goes with them", () => {
  const store = memory();
  session(store, "a");
  const thread = store.openThread("ember", "CHAT", "1.1", null, null);
  store.joinThread(thread.id, "a", "ember");
  const state = () => store.db.prepare("SELECT last_n, said_n, person_n, letters FROM thread_state WHERE thread = ?").get(thread.id);
  const people = () => store.db.prepare("SELECT author, first_n FROM thread_people WHERE thread = ? ORDER BY first_n").all(thread.id).map((r: any) => [r.author, r.first_n]);
  assert.equal(state(), undefined);
  const [first] = say(store, thread.id, "1.2", "person", "x@a", "先看看日志");
  store.deliver(thread.id, first, ["a"]);
  say(store, thread.id, "1.3", "agent", "a", "在看");
  store.insertMessage({ ...newMessage(thread.id, "1.4", "agent", "b", "来自 [备份](https://x/o/w/s/b)：\n\n好了"), letter: { way: "in", title: "备份", link: "https://x/o/w/s/b" } });
  const [second] = say(store, thread.id, "1.5", "person", "y@a", "我也看");
  store.deliver(thread.id, second, ["a"]);
  say(store, thread.id, "1.6", "person", "x@a", "好");
  assert.deepEqual({ ...(state() as object) }, { last_n: 5, said_n: 5, person_n: 1, letters: 1 });
  assert.deepEqual(people(), [["x@a", 1], ["y@a", 4]]);
  // An edit is an entry of its own: the last, nothing else; what is said of the message as merged is its new words.
  store.editMessage("ember", "CHAT", "1.1", "1.2", "先看看今天的日志");
  assert.deepEqual({ ...(state() as object) }, { last_n: 6, said_n: 5, person_n: 1, letters: 1 });
  const [listed] = store.listThreads("x@a", null, thread.id);
  assert.deepEqual([listed!.firstText, listed!.lastMessage?.text, listed!.letters, listed!.people], ["先看看今天的日志", "好", 1, ["x@a", "y@a"]]);
  assert.equal(store.sessionStats("a").get("a")!.firstText, "先看看今天的日志");
  // The first message given goes: the next given is the first.
  store.db.prepare("DELETE FROM deliveries WHERE thread = ? AND n = ?").run(thread.id, first);
  assert.equal(store.sessionStats("a").get("a")!.firstText, "我也看");
  // The thread goes: what was kept of it with it.
  store.db.prepare("DELETE FROM entries WHERE thread = ?").run(thread.id);
  assert.equal(state(), undefined);
  assert.deepEqual(people(), []);
});

test("deleting a session removes its first-message summary once, not once per delivery", () => {
  const store = memory();
  session(store, "a");
  session(store, "b");
  const thread = store.openThread("ember", "CHAT", "1.1", null, null);
  store.joinThread(thread.id, "a", "ember");
  store.joinThread(thread.id, "b", "ember");
  for (let i = 0; i < 32; i++) {
    const [n] = say(store, thread.id, `1.${i + 2}`, "person", "x@a", `message ${i}`);
    store.deliver(thread.id, n, i === 0 ? ["a", "b"] : ["a"]);
  }
  store.db.exec(`
    CREATE TEMP TABLE first_removed (session TEXT);
    CREATE TEMP TRIGGER count_first_removed AFTER DELETE ON main.session_first BEGIN
      INSERT INTO first_removed VALUES (OLD.session);
    END;
  `);
  store.deleteSession("a");
  assert.deepEqual(store.db.prepare("SELECT session FROM first_removed").all().map((r) => r.session), ["a"]);
  assert.equal(store.sessionStats("b").get("b")!.firstText, "message 0", "the other participant keeps its summary");
});

for (const mode of ["ABORT", "REPLACE"] as const) for (const recursive of [false, true]) {
  test(`a delivery written with ${mode} keeps the session's first message (recursive triggers ${recursive})`, () => {
    const store = memory();
    const db = store.db;
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    session(store, "first");
    db.prepare("INSERT INTO deliveries (thread,n,session) VALUES (1,1,'first')").run();
    db.prepare(`INSERT OR ${mode} INTO deliveries (thread,n,session) VALUES (1,2,'first')`).run();
    assert.deepEqual({ ...db.prepare("SELECT thread,n FROM session_first WHERE session='first'").get() }, { thread: 1, n: 1 });
  });
}

for (const recursive of [false, true]) {
  test(`replacing the first delivery keeps the earliest remaining delivery (recursive triggers ${recursive})`, () => {
    const store = memory();
    const db = store.db;
    try {
      db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
      session(store, "first");
      db.prepare("INSERT INTO deliveries (thread,n,session) VALUES (1,1,'first'), (1,2,'first')").run();
      db.prepare("INSERT OR IGNORE INTO deliveries (thread,n,session) VALUES (1,1,'first')").run();
      assert.deepEqual({ ...db.prepare("SELECT thread,n FROM session_first WHERE session='first'").get() }, {thread:1,n:1});
      db.prepare("INSERT OR REPLACE INTO deliveries (thread,n,session) VALUES (1,1,'first')").run();
      assert.deepEqual({ ...db.prepare("SELECT thread,n FROM session_first WHERE session='first'").get() }, {thread:1,n:2});
    } finally { store.close(); }
  });
}

test("replacing a sole delivery does not rewrite the unchanged first-message summary", () => {
  const store = memory();
  const db = store.db;
  try {
    db.exec(`PRAGMA recursive_triggers = OFF;
      CREATE TEMP TABLE first_changed (session TEXT);
      CREATE TEMP TRIGGER watch_first AFTER UPDATE ON main.session_first BEGIN INSERT INTO first_changed VALUES (NEW.session); END;`);
    session(store, "first");
    db.prepare("INSERT INTO deliveries (thread,n,session) VALUES (1,1,'first')").run();
    db.prepare("INSERT OR REPLACE INTO deliveries (thread,n,session) VALUES (1,1,'first')").run();
    assert.deepEqual(db.prepare("SELECT session FROM first_changed").all(), []);
  } finally { store.close(); }
});

test("deleting a first delivery finds the earliest remaining one across its threads", () => {
  const store = memory();
  const db = store.db;
  try {
    session(store, "first");
    db.prepare("INSERT INTO deliveries (thread,n,session) VALUES (9,1,'first'), (2,1,'first'), (9,2,'first')").run();
    db.prepare("DELETE FROM deliveries WHERE thread=9 AND n=1 AND session='first'").run();
    assert.deepEqual({ ...db.prepare("SELECT thread,n FROM session_first WHERE session='first'").get() }, {thread:2,n:1});
    db.prepare("DELETE FROM deliveries WHERE thread=2 AND n=1 AND session='first'").run();
    assert.deepEqual({ ...db.prepare("SELECT thread,n FROM session_first WHERE session='first'").get() }, {thread:9,n:2});
    db.prepare("DELETE FROM deliveries WHERE thread=9 AND n=2 AND session='first'").run();
    assert.equal(db.prepare("SELECT 1 FROM session_first WHERE session='first'").get(), undefined);
  } finally { store.close(); }
});

test("finding the first delivery seeks each thread without walking its messages", () => {
  const store = memory();
  const db = store.db;
  try {
    const put = db.prepare("INSERT INTO deliveries (thread,n,session,delivered_at) VALUES (?,?,?,1)");
    db.exec("BEGIN");
    for (let n=0; n<5_000; n++) { put.run(9,n,"target"); put.run(10,n,"other"); }
    put.run(2,0,"target");
    db.exec("COMMIT");
    let visited = 0;
    db.function("visit_first_delivery", (_row) => { visited++; return 1; });
    const sql = firstDelivery("?1");
    const traced = sql.replaceAll("WHERE session = ?1", "WHERE visit_first_delivery(rowid) AND session = ?1");
    assert.deepEqual({ ...db.prepare(traced).get("target") }, {thread:9,n:0});
    assert.ok(visited <= 4, `one seek per thread plus its first row (visited ${visited})`);
    const plan = (db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all("target") as {detail:string}[]).map((r) => r.detail).join(" | ");
    assert.match(plan, /SEARCH deliveries USING COVERING INDEX deliveries_session \(session=\? AND thread=\?\)/);
    assert.doesNotMatch(plan, /USE TEMP B-TREE/);
    db.exec("BEGIN");
    for (let n=0; n<1_200; n++) put.run(1000+n,0,"target");
    db.exec("COMMIT");
    visited = 0;
    assert.deepEqual({ ...db.prepare(traced).get("target") }, {thread:9,n:0});
    assert.ok(visited <= 2 * 1_202, `many threads still seek their first rows (visited ${visited})`);
  } finally { store.close(); }
});

test("an older database replaces the first-delivery trigger without rebuilding its summary", () => {
  const path = join(tempdir(), "first-delivery.db");
  const before = open(path);
  session(before, "first");
  before.db.prepare("INSERT INTO deliveries (thread,n,session) VALUES (1,1,'first')").run();
  before.db.exec(`DROP TRIGGER session_first_add; DROP TRIGGER session_first_drop;
    CREATE TRIGGER session_first_add AFTER INSERT ON deliveries BEGIN
      INSERT OR IGNORE INTO session_first VALUES (NEW.session, NEW.thread, NEW.n);
    END;
    CREATE TRIGGER session_first_drop AFTER DELETE ON deliveries
      WHEN EXISTS (SELECT 1 FROM session_first WHERE session=OLD.session AND thread=OLD.thread AND n=OLD.n) BEGIN
      DELETE FROM session_first WHERE session=OLD.session;
      INSERT OR IGNORE INTO session_first SELECT session,thread,n FROM deliveries WHERE session=OLD.session ORDER BY rowid LIMIT 1;
    END`);
  before.close();
  const after = open(path);
  after.db.prepare("INSERT OR REPLACE INTO deliveries (thread,n,session) VALUES (1,2,'first')").run();
  assert.deepEqual({ ...after.db.prepare("SELECT thread,n FROM session_first WHERE session='first'").get() }, { thread: 1, n: 1 });
  after.db.prepare("DELETE FROM deliveries WHERE thread=1 AND n=1 AND session='first'").run();
  assert.deepEqual({ ...after.db.prepare("SELECT thread,n FROM session_first WHERE session='first'").get() }, { thread: 1, n: 2 });
  assert.match((after.db.prepare("SELECT sql FROM sqlite_master WHERE type='trigger' AND name='session_first_drop'").get() as {sql:string}).sql, /WITH RECURSIVE first_threads/);
});

test("updating the first-delivery trigger does not read or rewrite old deliveries and summaries", () => {
  const store = memory();
  const db = store.db;
  db.exec(`DROP TRIGGER session_first_add; DROP TRIGGER session_first_drop;
    CREATE TRIGGER session_first_add AFTER INSERT ON deliveries BEGIN
      INSERT OR IGNORE INTO session_first VALUES (NEW.session, NEW.thread, NEW.n);
    END;
    CREATE TRIGGER session_first_drop AFTER DELETE ON deliveries BEGIN
      DELETE FROM session_first WHERE session=OLD.session;
      INSERT OR IGNORE INTO session_first SELECT session,thread,n FROM deliveries WHERE session=OLD.session ORDER BY rowid LIMIT 1;
    END`);
  const tables = new Set(["deliveries", "entries", "session_first", "thread_state", "thread_people"]);
  db.setAuthorizer((action, table) => tables.has(table ?? "") && [constants.SQLITE_READ, constants.SQLITE_INSERT, constants.SQLITE_UPDATE, constants.SQLITE_DELETE].includes(action)
    ? constants.SQLITE_DENY : constants.SQLITE_OK);
  try { addListState(db); } finally { db.setAuthorizer(null); }
  db.setAuthorizer((action) => action === constants.SQLITE_CREATE_TRIGGER || action === constants.SQLITE_DROP_TRIGGER
    ? constants.SQLITE_DENY : constants.SQLITE_OK);
  try { addListState(db); } finally { db.setAuthorizer(null); }
});

test("what two chats' agents wrote each other is neither a chat's unread nor what lists show of it, archived or not", () => {
  const data = tempdir();
  const store = open(join(data, "stillfail.db"), join(data, "archive"));
  session(store, "a");
  const thread = store.openThread("ember", "CHAT", "1.1", null, null);
  store.joinThread(thread.id, "a", "ember");
  // Opened by another chat's agent: what it is about is the chat's first message, said as any other.
  say(store, thread.id, "1.2", "agent", "b", "由 [备份](https://x/o/w/s/b) 开的 chat：\n\n看看备份");
  say(store, thread.id, "1.3", "agent", "a", "好，在看");
  // Letters: from a session here and from one of another station, and one this chat's agent wrote another chat.
  const letter = (ts: string, author: string, text: string, way: "in" | "out") =>
    store.insertMessage({ ...newMessage(thread.id, ts, "agent", author, text), letter: { way, title: "备份", link: "https://x/o/w/s/b" } });
  letter("1.4", "b", "来自 [备份](https://x/o/w/s/b)：\n\n脚本放好了", "in");
  letter("1.5", "peer/chat:c-9", "From [Backups](https://x/o/w/t/c):\n\nDone", "in");
  letter("1.6", "a", "发给 [备份](https://x/o/w/s/b)：\n\n收到", "out");
  const reader = read.openStore(data);
  const lists = () => [store.listThreads("local", null, null), read.listThreads(reader, "local", null, null)];
  for (const threads of lists()) assert.deepEqual(threads.map((t) => [t.lastMessage?.ts, t.unread, t.letters]), [["1.3", 2, 3]]);
  assert.equal(store.unreadCount("local", thread.id), 2);
  // This chat's own agent quoting one in the chat says it in the chat.
  say(store, thread.id, "1.7", "agent", "a", "来自 [备份](https://x/o/w/s/b)：\n\n照它说的改了");
  for (const threads of lists()) assert.deepEqual(threads.map((t) => [t.lastMessage?.ts, t.unread, t.letters]), [["1.7", 3, 3]]);
  // Archived: the same.
  store.setArchived("a", true, MANUAL);
  for (const threads of lists()) assert.deepEqual(threads.map((t) => [t.lastMessage?.ts, t.unread, t.letters]), [["1.7", 3, 3]]);
  reader.db.close();
});

test("letters from before they were marked are marked as the column comes, by the chat their heading names", () => {
  const data = tempdir();
  const path = join(data, "stillfail.db");
  const store = open(path);
  session(store, "a");
  const thread = store.openThread("ember", "CHAT", "1.1", null, null);
  store.joinThread(thread.id, "a", "ember");
  say(store, thread.id, "1.2", "agent", "b", "来自 [备份](https://x/o/w/s/b)：\n\n脚本放好了");
  say(store, thread.id, "1.3", "agent", "peer/chat:c-9", "From <https://x/o/w/t/c|Backups>:\n\nDone");
  say(store, thread.id, "1.4", "agent", "a", "来自 [备份](https://x/o/w/s/b)：\n\n照它说的改了");
  say(store, thread.id, "1.5", "agent", "b", "由 [备份](https://x/o/w/s/b) 开的 chat：\n\n看看备份");
  store.close();
  // As a station from before letters left it (from before the lists' kept state too, whose trigger reads the column).
  const db = new DatabaseSync(path);
  db.exec("DROP TRIGGER said_state_before_insert; DROP TRIGGER said_state_before_delete; DROP TRIGGER said_state_before_update; DROP TABLE said_state_guard");
  db.exec("DROP TRIGGER thread_state_add; DROP TRIGGER thread_state_drop; DROP TRIGGER session_first_add; DROP TRIGGER session_first_drop");
  db.exec("DROP TABLE thread_state; DROP TABLE thread_people; DROP TABLE session_first");
  db.exec(`DROP TRIGGER widget_source_before_add; DROP TRIGGER widget_source_add; DROP TRIGGER widget_source_fast_add;
    DROP TRIGGER widget_source_before_change; DROP TRIGGER widget_source_change; DROP TRIGGER widget_source_drop;
    DROP TRIGGER widget_source_drop_thread; DROP TABLE widget_source_rows; DROP TABLE widget_source_invalid;
    DROP TABLE widget_source_changed; DROP TABLE widget_source_scopes; DROP TABLE widget_source_meta`);
  db.exec("DROP VIEW merged; DROP INDEX entries_letters; DROP INDEX entries_said; ALTER TABLE entries DROP COLUMN letter");
  db.close();
  const again = open(path);
  assert.deepEqual(
    again.entriesAfter(thread.id, 0).map((e) => [e.ts, e.letter ?? null]),
    [
      ["1.2", { way: "in", title: "备份", link: "https://x/o/w/s/b" }],
      ["1.3", { way: "in", title: "Backups", link: "https://x/o/w/t/c" }],
      ["1.4", null],
      ["1.5", null],
    ],
  );
  assert.equal(again.listThreads("local", null, null)[0]?.letters, 2);
});

test("an archived thread whose file is lost comes back empty, and is counted on from what was read of it", () => {
  const data = tempdir();
  const path = join(data, "stillfail.db");
  const before = open(path, join(data, "archive"));
  session(before, "a");
  session(before, "b");
  const lost = before.openThread("ember", "CHAT", "1.1", null, null);
  const kept = before.openThread("ember", "CHAT", "2.1", null, null);
  before.joinThread(lost.id, "a", "ember");
  before.joinThread(kept.id, "b", "ember");
  say(before, lost.id, "1.2", "person", "local", "看看");
  say(before, lost.id, "1.3", "agent", "a", "好");
  say(before, lost.id, "1.4", "agent", "a", "做完了");
  say(before, kept.id, "2.2", "person", "local", "还有这个");
  before.setRead("local", lost.id, 3);
  before.setArchived("a", true, MANUAL);
  rmSync(fileAway(before, lost.id));
  before.close();
  const store = open(path, join(data, "archive"));

  // Every list it is in is still read, by the station and by its readers (another connection over the same file).
  const reader = read.openStore(data);
  for (const threads of [store.listThreads("local", null, null), read.listThreads(reader, "local", null, null)]) {
    assert.deepEqual(threads.map((t) => [t.thread.id, t.lastMessage?.text ?? null, t.unread]), [[kept.id, "还有这个", 0], [lost.id, null, 0]]);
  }
  assert.deepEqual(store.entriesAfter(lost.id, 0), []);
  assert.deepEqual(read.entriesAfter(reader, lost.id, 0n), []);
  assert.equal(store.lastEntry(lost.id), 0);
  reader.db.close();

  // Said in again, it comes back with that alone, numbered after what was read of it: what a client keeps of the
  // thread (1 to 3) is not numbered again.
  assert.deepEqual(say(store, lost.id, "1.5", "person", "local", "还在吗"), [4, true]);
  assert.deepEqual(store.entriesAfter(lost.id, 0).map((e) => [e.n, e.text]), [[4, "还在吗"]]);
  // A thread nothing was said in starts at 1 as before.
  const fresh = store.openThread("ember", "CHAT", "3.1", null, null);
  assert.deepEqual(say(store, fresh.id, "3.2", "person", "local", "新的"), [1, true]);
});

test("thread ids are never used again", () => {
  const store = memory();
  session(store, "a");
  const thread = store.openThread("ember", "CHAT", "1.1", null, null);
  store.joinThread(thread.id, "a", "ember");
  store.deleteSession("a");
  assert.ok(store.openThread("ember", "CHAT", "2.1", null, null).id > thread.id);
});

test("deleting removes the session's rows and the threads only it was in", () => {
  const store = memory();
  session(store, "a");
  session(store, "b");
  const shared = store.openThread("slack:T1", "C1", "1.1", null, null);
  const own = store.openThread("ember", "CHAT", "2.1", null, null);
  store.joinThread(shared.id, "a", "ds");
  store.joinThread(shared.id, "b", "ds");
  store.joinThread(own.id, "a", "ember");
  const [said] = say(store, shared.id, "1.1", "person", "U1", "hi");
  store.deliver(shared.id, said, ["a", "b"]);
  say(store, own.id, "2.2", "person", "local", "mine");
  store.setRead("local", own.id, 99);
  store.startTurn("t", "a", "input");
  store.setBinding("team", "a");
  store.setArchived("a", true, MANUAL);
  assert.ok(store.getSession("a")!.archivedAt! > 0);
  store.setArchived("a", false, MANUAL);
  assert.equal(store.getSession("a")!.archivedAt, null);
  const h = heard(store);
  store.deleteSession("a");
  const told = h.changes.flatMap((c) =>
    c.type === "sessionRemoved" ? [`removed ${c.key}`] : c.type === "threadRemoved" ? [`thread removed ${c.id}`] : c.type === "thread" ? [`thread ${c.id}`] : [],
  );
  assert.deepEqual(told, ["removed a", `thread removed ${own.id}`, `thread ${shared.id}`]);
  assert.equal(store.getSession("a"), null);
  assert.equal(store.getThread(own.id), null);
  assert.deepEqual(store.entriesAfter(own.id, 0), []);
  assert.deepEqual(store.threadSessions(shared.id).map((m) => m.session), ["b"]);
  assert.equal(store.pendingMessages("b").length, 1, "the other session keeps its delivery");
  assert.deepEqual(store.listTurns("a"), []);
  assert.equal(store.binding("team"), null);
});

test("the store announces what changed", () => {
  const store = memory();
  const h = heard(store);
  session(store, "a");
  const thread = store.openThread("ember", "CHAT", "1.1", null, null);
  store.joinThread(thread.id, "a", "ember");
  const [n] = say(store, thread.id, "1.2", "person", "local", "hi");
  store.deliver(thread.id, n, ["a"]);
  store.setRead("local", thread.id, n);
  store.recordProcess(42, 1, "claude", "x");
  store.forgetProcess(42);
  store.forgetProcess(42);
  const kinds = h.changes.map((c) => (["session", "thread", "read", "processes"].includes(c.type) ? c.type : "other"));
  assert.deepEqual(kinds, ["session", "session", "thread", "thread", "session", "read", "processes", "processes"]);
  assert.deepEqual(h.changes[2], { type: "thread", id: thread.id, entries: [] });
  const appended = h.changes[3]!;
  assert.ok(appended.type === "thread");
  assert.deepEqual([appended.id, appended.entries.map((e) => [e.n, e.text])], [thread.id, [[1, "hi"]]]);
  assert.deepEqual(h.changes[5], { type: "read", viewer: "local", thread: thread.id, n });
  h.stop();
  store.notify("a");
  assert.equal(h.changes.length, 8, "unsubscribed");
});

test("a session's chat is named by the thread said in last, as the lists have it, read by its rows alone", async () => {
  const time = testClock();
  await time.adjust(Date.parse("2026-10-25T00:00:00Z"));
  const store = Store.open(":memory:", null, time.clock);
  stores.push(store);
  session(store, "a");
  assert.equal(store.sessionChat("a"), null);
  const slack = store.openThread("slack", "C1", "1.1", null, null);
  const own = store.openThreadOf("ember", "CHAT", "2.1", null, null, "a");
  store.joinThread(slack.id, "a", "slack");
  store.joinThread(own.id, "a", "ember");
  say(store, slack.id, "1.2", "person", "u1", "看一下构建");
  await time.adjust(1000);
  say(store, own.id, "2.2", "person", "local", "hi");
  const named = () => [store.sessionChat("a")!.thread.id, store.sessionChat("a")!.firstText];
  // The still.fail chat said in last: its words are not asked (its title is its own, or 新对话).
  assert.deepEqual(named(), [own.id, null]);
  assert.equal(store.listThreads("", "a", null)[0]!.thread.id, own.id);
  await time.adjust(1000);
  say(store, slack.id, "1.3", "agent", "a", "好");
  assert.deepEqual(named(), [slack.id, "看一下构建"]);
  assert.equal(store.listThreads("", "a", null)[0]!.thread.id, slack.id);
});

test("a session's own chat is archived with it, a chat of its own alone; anything new said brings them back", () => {
  const store = memory();
  session(store, "a");
  const own = store.openThreadOf("ember", "CHAT", "1.1", null, null, "a");
  const other = store.openThread("ember", "CHAT", "2.1", null, null);
  store.joinThread(own.id, "a", "ember");
  store.joinThread(other.id, "a", "ember");
  say(store, other.id, "2.2", "person", "local", "hi");
  assert.equal(store.homeChat("a")!.id, own.id);
  assert.deepEqual(store.chatsOfTheirOwn().map((t) => t.id), [other.id]);
  const thread = (id: number) => store.getThread(id)!;
  const row = () => store.getSession("a")!;

  store.setArchived("a", true, AUTO);
  assert.deepEqual([row().archivedBy, thread(own.id).hiddenBy], [AUTO, AUTO]);
  assert.equal(thread(other.id).hiddenAt, null, "a chat of its own stays");
  // Its agent says something there: the session comes back, with its own chat.
  say(store, other.id, "2.3", "agent", "a", "done");
  assert.equal(row().archivedAt, null);
  assert.equal(row().shownAt, null, "brought back by what was said, not by hand");
  assert.equal(thread(own.id).hiddenAt, null);

  store.setThreadHidden(other.id, true, AUTO);
  assert.ok(thread(other.id).hiddenAt !== null);
  assert.equal(row().archivedAt, null, "its sessions stay");
  assert.ok(!existsSync(archiveFile(store, other.id)), "out of lists, its entries stay in the database");
  assert.deepEqual(store.entriesAfter(other.id, 0).map((e) => e.text), ["hi", "done"]);
  // Someone writes in it: shown again.
  say(store, other.id, "2.4", "person", "local", "again");
  assert.equal(thread(other.id).hiddenAt, null);
  // Hidden by hand, it stays hidden.
  store.setThreadHidden(other.id, true, MANUAL);
  assert.ok(store.manuallyArchived(other.id));
  say(store, other.id, "2.41", "agent", "a", "late");
  assert.ok(thread(other.id).hiddenAt !== null);
  store.setThreadHidden(other.id, false, MANUAL);

  // Archived by hand, nothing said brings it back: it takes no messages.
  store.setArchived("a", true, MANUAL);
  assert.ok(store.manuallyArchived(own.id));
  say(store, own.id, "1.2", "agent", "a", "late");
  assert.equal(row().archivedBy, MANUAL);
  assert.ok(thread(own.id).hiddenAt !== null);
  // Shown again by hand: the idle clock starts over.
  store.setArchived("a", false, MANUAL);
  assert.ok(row().shownAt !== null);
  assert.equal(store.manuallyArchived(own.id), false);

  // Archived by the station, an agent's word in its chat brings back every session that hears it.
  session(store, "b");
  store.joinThread(other.id, "b", "ember");
  store.setArchived("a", true, AUTO);
  store.setArchived("b", true, AUTO);
  say(store, other.id, "2.5", "agent", "b", "news");
  assert.deepEqual([row().archivedAt, store.getSession("b")!.archivedAt], [null, null]);
});

test("a database made before archiving gains its columns and each session's first chat is its own", () => {
  const path = join(tempdir(), "ember.db");
  const db = new DatabaseSync(path);
  const old = SCHEMA.replace("  archived_at INTEGER,\n  archived_by TEXT,\n  shown_at INTEGER,\n  cwd TEXT\n", "  archived_at INTEGER\n").replace(
    "  home TEXT,\n  hidden_at INTEGER,\n  hidden_by TEXT,\n  shown_at INTEGER,\n",
    "",
  );
  assert.ok(!old.includes("hidden_at"));
  db.exec(old);
  db.exec(`PRAGMA user_version = ${SCHEMA_VERSION}`);
  db.exec(`INSERT INTO sessions (key, connect, scope, runtime, profile, workspace, token, created_at, last_active_at, archived_at)
             VALUES ('a', 'ember', 'all', 'claude', 'cc', '/w/a', 'a', 1, 1, 5);
           INSERT INTO threads (id, surface, channel, thread_ts, created_at) VALUES (1, 'ember', 'CHAT', '1.1', 1), (2, 'ember', 'CHAT', '2.1', 2);
           INSERT INTO thread_sessions (thread, session, connect, joined_at) VALUES (1, 'a', 'ember', 1), (2, 'a', 'ember', 2);`);
  db.close();
  const store = open(path);
  const first = store.getThread(1)!;
  assert.deepEqual([first.home, first.hiddenAt, first.hiddenBy], ["a", 5, MANUAL]);
  assert.equal(store.getThread(2)!.home, null);
  assert.equal(store.getSession("a")!.archivedBy, MANUAL);
  store.close();
  // Opened again: nothing more to add.
  open(path);
});

test("a database made before clients gains the column and a message keeps its app through archiving", () => {
  const dir = tempdir();
  const path = join(dir, "ember.db");
  const db = new DatabaseSync(path);
  const old = SCHEMA.replace("  client TEXT,\n", "");
  assert.ok(!old.includes("client"));
  db.exec(old);
  // The view as it was made before.
  db.exec(MERGED.replace("m.declared, m.client, m.agent_identity,", "m.declared,"));
  db.exec(`PRAGMA user_version = ${SCHEMA_VERSION}`);
  db.close();
  const store = open(path, join(dir, "archive"));
  session(store, "a");
  const thread = store.openThread("ember", "CHAT", "1.1", null, null);
  store.joinThread(thread.id, "a", "ember");
  say(store, thread.id, "1.2", "person", "local", "旧的");
  const [n] = store.insertMessage({ ...newMessage(thread.id, "1.3", "person", "local", "新的"), client: "android 0.1.1123" });
  store.deliver(thread.id, n, ["a"]);
  const clients = () => store.messagesBefore(thread.id, null, 10).map((m) => m.client);
  assert.deepEqual(clients(), [null, "android 0.1.1123"]);
  assert.equal(store.pendingMessages("a")[0]!.message.client, "android 0.1.1123");
  store.setArchived("a", true, MANUAL);
  assert.deepEqual(clients(), [null, "android 0.1.1123"]);
  store.setArchived("a", false, MANUAL);
  assert.deepEqual(clients(), [null, "android 0.1.1123"]);
  store.close();
  open(path);
});

test("a widget's state is kept by session and path, its model told once until it changes", () => {
  const store = memory();
  session(store, "a");
  session(store, "b");
  const thread = store.openThread("ember", "CHAT", "3.1", null, null);
  assert.equal(widgetSourcesStep(store.db, thread.id).done, true);
  store.joinThread(thread.id, "a", "ember");
  const path = "/w/a/uploads/pick.html";
  store.insertMessage({ ...newMessage(thread.id, "3.2", "agent", "a", "![](pick.html)"), attachments: [{ name: "pick.html", path, size: 9 }] });
  assert.equal(store.widgetState("a", path), null);
  store.putWidgetState("a", path, `{"modelContent":"red"}`, "red");
  store.putWidgetState("a", "/w/a/uploads/quiet.html", `{"privateContent":1}`, null);
  assert.equal(store.widgetState("a", path), `{"modelContent":"red"}`);
  assert.equal(store.widgetState("b", path), null, "kept per session");
  assert.deepEqual(store.untoldWidgetModels("a"), [{ path, name: "pick.html", thread: ["CHAT", "3.1"], model: "red" }]);
  store.markWidgetModelsTold("a", [[path, "red"]]);
  assert.deepEqual(store.untoldWidgetModels("a"), []);
  // The same model again is not news; another is, and one changed after it was read is not marked told.
  store.putWidgetState("a", path, `{"modelContent":"red","privateContent":2}`, "red");
  assert.deepEqual(store.untoldWidgetModels("a"), []);
  store.putWidgetState("a", path, `{"modelContent":"blue"}`, "blue");
  store.markWidgetModelsTold("a", [[path, "red"]]);
  assert.deepEqual(store.untoldWidgetModels("a").map((w) => w.model), ["blue"]);
  // A file no message of the session's threads carries: its path's name, no thread.
  store.putWidgetState("a", "/elsewhere/x.html", "{}", "x");
  const elsewhere = store.untoldWidgetModels("a").find((w) => w.path === "/elsewhere/x.html")!;
  assert.deepEqual([elsewhere.name, elsewhere.thread], ["x.html", null]);
  store.deleteSession("a");
  assert.equal(store.widgetState("a", path), null);
});

test("old transcript records keep their runtime when a chat changes runtime", () => {
  const path = join(tempdir(), "ember.db");
  let store = open(path);
  session(store, "old");
  store.setRuntimeSessionId("old", "earlier");
  store.ranIn("old", "earlier", "cc");
  store.close();
  const db = new DatabaseSync(path);
  db.exec("ALTER TABLE runtime_sessions DROP COLUMN runtime");
  db.close();
  store = open(path);
  store.setSessionRuntime("old", "codex", "cx", false, null, null, null, null);
  assert.deepEqual(store.runtimeSessionSources("old"), [{ id: "earlier", runtime: "claude", profile: "cc" }]);
  assert.equal(store.sessionOfRuntime("claude", "earlier")?.key, "old");
  assert.equal(store.sessionOfRuntime("codex", "earlier"), null);
  store.close();
  store = open(path);
  assert.equal(store.runtimeSessionSources("old")[0]!.runtime, "claude");
});

test("session fast migrates old databases and survives restart", () => {
  const path = join(tempdir(), "ember.db");
  let store = open(path);
  session(store, "old");
  store.close();
  const db = new DatabaseSync(path);
  db.exec("ALTER TABLE sessions DROP COLUMN fast");
  db.close();
  store = open(path);
  assert.equal(store.getSession("old")!.fast, null);
  store.setSessionFast("old", false);
  store.close();
  store = open(path);
  assert.equal(store.getSession("old")!.fast, false);
});

test("the sessions that wait are those whose latest turn said so, found together", () => {
  const store = memory();
  for (const key of ["waits", "waited", "done", "none"]) session(store, key);
  store.startTurn("w1", "waits", "input");
  store.endTurn("w1", "completed", null, "waiting", 60);
  store.startTurn("d1", "waited", "input");
  store.endTurn("d1", "completed", null, "waiting", 60);
  store.startTurn("d2", "waited", "job");
  store.endTurn("d2", "completed", null, null, null);
  store.startTurn("x1", "done", "input");
  store.endTurn("x1", "completed", null, null, null);
});

test("the latest turn is the last inserted when start times tie", () => {
  const store = memory();
  session(store, "same-ms");
  store.startTurn("first", "same-ms", "input");
  store.endTurn("first", "failed", "rate_limit: quota", null, null);
  store.startTurn("second", "same-ms", "resume");
  store.endTurn("second", "completed", null, null, null);
  store.db.exec("UPDATE turns SET started_at = 123 WHERE session_key = 'same-ms'");
  const latest = store.lastTurn("same-ms")!;
  assert.equal(latest.kind, "resume");
  assert.equal(latest.outcome, "completed");
  assert.equal(latest.detail, null);
  assert.equal(store.statsOf(["same-ms"]).get("same-ms")!.lastTurn!.outcome, "completed");
  assert.equal(store.stopWait("same-ms", true), false, "stopping an allowance wait does not change an older turn");
  store.startTurn("third", "same-ms", "resume");
  store.endTurn("third", "failed", "rate_limit: quota", null, null);
  store.db.exec("UPDATE turns SET started_at = 123 WHERE session_key = 'same-ms'");
  assert.equal(store.stopWait("same-ms", true), true);
  assert.equal(store.lastTurn("same-ms")!.outcome, "aborted");
});

test("a message keeps its model after switching, editing and archiving", () => {
  const dir = tempdir();
  const store = open(join(dir, "ember.db"), join(dir, "archive"));
  session(store, "a");
  const thread = store.openThread("ember", "CHAT", "1.1", null, null);
  store.joinThread(thread.id, "a", "ember");
  store.setSessionModel("a", "gpt-6-sol", "high");
  say(store, thread.id, "1.2", "agent", "a", "first");
  store.setSessionModel("a", "gpt-6-astra", "medium");
  say(store, thread.id, "1.3", "agent", "a", "second");
  store.editMessage("ember", "CHAT", "1.1", "1.2", "edited");
  const check = () => {
    const messages = store.messagesBefore(thread.id, null, 10);
    assert.equal(messages[0]!.agentIdentity.model, "gpt-6-sol");
    assert.equal(messages[0]!.agentIdentity.effort, "high");
    assert.equal(messages[0]!.agentIdentity.runtime, "claude");
    assert.equal(messages[1]!.agentIdentity.model, "gpt-6-astra");
    assert.equal(messages[0]!.text, "edited");
  };
  check();
  store.setArchived("a", true, MANUAL);
  check();
  store.setArchived("a", false, MANUAL);
  check();
});

test("an existing client view gains model identity even after a partial upgrade", () => {
  for (const alreadyAdded of [false, true]) {
    const path = join(tempdir(), "ember.db");
    const db = new DatabaseSync(path);
    db.exec(SCHEMA);
    // The immediately previous release already had client, but no model snapshot.
    db.exec(MERGED.replace("m.agent_identity, ", ""));
    // The broken upgrade added the column while leaving this old view in place.
    if (alreadyAdded) db.exec("ALTER TABLE entries ADD COLUMN agent_identity TEXT");
    db.exec(`PRAGMA user_version = ${SCHEMA_VERSION}`);
    db.exec(`INSERT INTO entries (thread, n, kind, ts, author_kind, author, text, client, at) VALUES (1, 1, 'message', '1.1', 'person', 'local', 'kept', 'android old', 100)`);
    db.exec(`INSERT INTO entries (thread, n, kind, target, author_kind, author, text, at) VALUES (1, 2, 'edit', 1, 'person', 'local', 'edited', 200)`);
    db.close();
    // Both the first upgrade and subsequent opens must keep existing data readable.
    for (let i = 0; i < 2; i++) {
      const store = open(path);
      const message = store.messageAt(1, "1.1")!;
      assert.equal(message.text, "edited");
      assert.equal(message.client, "android old");
      assert.equal(message.editedAt, 200);
      assert.equal(message.agentIdentity, null, "do not backfill old messages");
      assert.deepEqual(store.messagesBefore(1, null, 10), [message]);
      assert.deepEqual(store.lastMessage(1), message);
      store.close();
    }
  }
});

test("canonical and legacy system authors are read as the same kind", () => {
  const store = memory();
  const thread = store.openThread("ember", "CHAT", "1.1", null, null);
  store.db.exec(`INSERT INTO entries (thread, n, kind, ts, author_kind, author, text, at) VALUES (${thread.id}, 1, 'message', '1.1', 'stillfail', 'stillfail', 'x', 1)`);
  say(store, thread.id, "1.2", "ember", "ember", "y");
  assert.deepEqual(store.entriesAfter(thread.id, 0).map((e) => e.authorKind), ["ember", "ember"]);
  // Writes keep the legacy spelling.
  assert.equal((store.db.prepare("SELECT author_kind FROM entries WHERE n = 2").get() as any).author_kind, "ember");
});

// ── beyond tests.rs ──

test("an options card is kept as options too, and a choice that closes it ends the need", () => {
  const store = memory();
  session(store, "a");
  const thread = store.openThread("ember", "CHAT", "1.1", null, null);
  store.joinThread(thread.id, "a", "ember");
  const card = { type: "options", options: [{ label: "合并", action: "close" }, { label: "再看" }] };
  store.startTurnFor("t1", "a", "input", { profile: "cc", person: "local", thread: thread.id });
  const [n] = store.insertMessage({ ...newMessage(thread.id, "1.2", "agent", "a", "合并吗？"), card });
  const row = store.db.prepare("SELECT card, options FROM entries WHERE n = ?").get(n) as any;
  assert.deepEqual([JSON.parse(row.card), JSON.parse(row.options)], [card, card.options]);
  assert.deepEqual(store.pendingCard(thread.id)![1], card);
  // Old style: options alone become an options card.
  const [m] = store.insertMessage({ ...newMessage(thread.id, "1.3", "agent", "a", "选一个"), options: [{ label: "x" }] });
  assert.deepEqual(store.entriesBetween(thread.id, m, m)[0]!.card, { type: "options", options: [{ label: "x" }] });
  assert.equal(store.closeCard("local", thread.id, n, "合并"), false, "not the latest card");
  // Back to one card: a fresh thread.
  const t2 = store.openThread("ember", "CHAT", "2.1", null, null);
  store.joinThread(t2.id, "a", "ember");
  const [k] = store.insertMessage({ ...newMessage(t2.id, "2.2", "agent", "a", "合并吗？"), card });
  store.setAbout("t1", [t2.id, k, "2.2"]);
  store.endTurn("t1", "completed", null, "need_help", null);
  assert.equal(store.closeCard("local", t2.id, k, "再看"), false, "a reply option does not close");
  const h = heard(store);
  assert.equal(store.closeCard("local", t2.id, k, "合并", "en"), true);
  assert.deepEqual(h.changes, [{ type: "session", key: "a" }, { type: "thread", id: t2.id, entries: [], closed: k }]);
  const last = store.lastTurn("a")!;
  assert.deepEqual([last.declared, last.ending, last.need], ["final", "all_done", "Chose “合并”"]);
  assert.equal(store.pendingCard(t2.id), null);
  assert.equal(store.closeCard("local", t2.id, k, "合并"), true, "closing again is no change");
  assert.equal(h.changes.length, 2);
  const answers = referenceAnswersSince(store, 0);
  assert.deepEqual(answers.map((a) => [a.question.n, a.by, a.answer]), [[k, "local", null]]);
  h.stop();
});

test("a card closes while the agent that asked is still in its turn, and that turn ends final", () => {
  const store = memory();
  session(store, "a");
  const thread = store.openThread("ember", "CHAT", "1.1", null, null);
  store.joinThread(thread.id, "a", "ember");
  const card = { type: "options", options: [{ label: "合并", action: "close" }, { label: "再看" }] };
  store.startTurnFor("t1", "a", "input", { profile: "cc", person: "local", thread: thread.id });
  const [k] = store.insertMessage({ ...newMessage(thread.id, "1.2", "agent", "a", "合并吗？"), card });
  store.setNeed("t1", "选一个");
  store.setAbout("t1", [thread.id, k, "1.2"]);
  store.declareTurn("t1", "need_human", null);
  assert.equal(store.closeCard("local", thread.id, k, "合并", "en"), true, "its turn still runs");
  assert.equal(store.pendingCard(thread.id), null);
  store.endTurn("t1", "completed", null, "need_human", null);
  const last = store.lastTurn("a")!;
  assert.deepEqual([last.declared, last.ending, last.need], ["final", "all_done", "Chose “合并”"]);
  // A later turn needing a person about another card is left as it ends.
  store.startTurnFor("t2", "a", "input", { profile: "cc", person: "local", thread: thread.id });
  const [j] = store.insertMessage({ ...newMessage(thread.id, "1.3", "agent", "a", "再来？"), card });
  store.setAbout("t2", [thread.id, j, "1.3"]);
  store.endTurn("t2", "completed", null, "need_human", null);
  assert.equal(store.lastTurn("a")!.declared, "need_human");
});

test("the cards answered lately of some threads alone are those the whole station's has in them", () => {
  const data = tempdir();
  const store = open(join(data, "stillfail.db"));
  session(store, "a");
  const card = { type: "options", options: [{ label: "x" }] };
  const threads = ["1", "2"].map((ts) => {
    const t = store.openThread("ember", "CHAT", `${ts}.0`, null, null);
    store.joinThread(t.id, "a", "ember");
    store.insertMessage({ ...newMessage(t.id, `${ts}.1`, "agent", "a", "?"), card });
    say(store, t.id, `${ts}.2`, "person", "me@x", "x");
    return t.id;
  });
  const reader = read.openStore(data);
  const whole = read.answersSince(reader, 0, threads);
  assert.deepEqual(whole.map((a) => a.question.thread).sort(), [...threads].sort());
  assert.deepEqual(read.answersSince(reader, 0, [threads[1]!]), whole.filter((a) => a.question.thread === threads[1]));
  assert.deepEqual(read.answersSince(reader, 0, [threads[1]!, threads[1]!]), whole.filter((a) => a.question.thread === threads[1]));
  assert.deepEqual(read.answersSince(reader, 0, []), []);
});

test("an agent withdraws its own card only", () => {
  const store = memory();
  session(store, "a");
  const thread = store.openThread("ember", "CHAT", "1.1", null, null);
  const [n] = store.insertMessage({ ...newMessage(thread.id, "1.2", "agent", "a", "?"), card: { type: "text" } });
  assert.equal(store.withdrawCard("b", thread.id, "1.2"), false);
  assert.equal(store.withdrawCard("a", thread.id, "1.2"), true);
  assert.equal(store.pendingCard(thread.id), null);
  assert.deepEqual(referenceAnswersSince(store, 0), [], "withdrawn is not answered");
  assert.ok(n > 0);
});

test("a card stops waiting as a person writes, a newer card comes, its agent withdraws it or someone closes it: each said once", () => {
  const store = memory();
  session(store, "a");
  const thread = store.openThread("slack", "C1", "1.1", null, null);
  const h = heard(store);
  const ended = () => h.changes.splice(0).flatMap((c) => cardsEnded(store, c)).map((e) => [e.message.ts, e.end]);
  const options = { type: "options", options: [{ label: "合并", action: "close" }, { label: "先不" }] };
  store.insertMessage({ ...newMessage(thread.id, "1.2", "agent", "a", "合并吗？"), card: options });
  assert.deepEqual(ended(), [], "a first card replaces nothing");
  say(store, thread.id, "1.3", "person", "U1", "再想想");
  assert.deepEqual(ended(), [["1.2", { why: "message", by: "U1", byTs: "1.3" }]]);
  say(store, thread.id, "1.4", "person", "U2", "还有");
  assert.deepEqual(ended(), [], "only the first message after it closes it");
  store.insertMessage({ ...newMessage(thread.id, "1.5", "agent", "a", "那这样？"), card: options });
  store.insertMessage({ ...newMessage(thread.id, "1.6", "agent", "a", "还是这样？"), card: { type: "text" } });
  assert.deepEqual(ended(), [["1.5", { why: "replaced" }]]);
  assert.equal(store.withdrawCard("a", thread.id, "1.6"), true);
  assert.deepEqual(ended(), [["1.6", { why: "withdrawn" }]]);
  store.insertMessage({ ...newMessage(thread.id, "1.7", "agent", "a", "那就？"), card: options });
  assert.deepEqual(ended(), [], "one withdrawn before it is not replaced again");
  assert.equal(store.closeCard("local", thread.id, store.messageAt(thread.id, "1.7")!.n, "合并"), true);
  assert.deepEqual(ended(), [["1.7", { why: "closed" }]]);
  say(store, thread.id, "1.8", "person", "U1", "好");
  assert.deepEqual(ended(), [], "one closed is not closed again by a message");
  store.insertMessage({ ...newMessage(thread.id, "1.9", "agent", "a", "最后？"), card: options });
  say(store, thread.id, "1.10", "person", "U1", "嗯");
  assert.deepEqual(ended().map(([, e]) => (e as CardEnd).why), ["message"]);
  assert.equal(store.withdrawCard("a", thread.id, "1.9"), true);
  assert.equal(store.withdrawCard("a", thread.id, "1.9"), true);
  assert.deepEqual(ended(), [], "one answered and withdrawn after keeps its answer");
  h.stop();
});

test("an agent restates its card on its post: an edit with the same words and the new card, its latest the base of the next", () => {
  const store = memory();
  session(store, "a");
  const thread = store.openThread("ember", "CHAT", "1.1", null, null);
  const card = { type: "options", options: [{ label: "仅本次" }], vault: { request: "r_1", name: "GitHub" } };
  const [n] = store.insertMessage({ ...newMessage(thread.id, "1.2", "agent", "a", "申请使用「GitHub」"), card });
  assert.equal(store.restateCard("b", thread.id, "1.2", (c) => c), false, "not another's");
  assert.equal(store.restateCard("a", thread.id, "1.2", (c) => ({ ...c, vault: { ...c.vault, outcome: { status: "granted" } } })), true);
  assert.equal(store.restateCard("a", thread.id, "1.2", (c) => ({ ...c, seen: c.vault.outcome.status })), true);
  const edits = store.entriesAfter(thread.id, n).filter((e) => e.kind === "edit");
  assert.deepEqual(edits.map((e) => [e.target, e.text]), [[n, "申请使用「GitHub」"], [n, "申请使用「GitHub」"]]);
  assert.deepEqual(edits[1]!.card, { ...card, vault: { ...card.vault, outcome: { status: "granted" } }, seen: "granted" });
  assert.equal(store.pendingCard(thread.id)?.[1].vault.request, "r_1", "the post's card still asks: restating it decides nothing");
});

test("a turn nobody's message started goes on with the work of the one before; a wait stopped is aborted", () => {
  const store = memory();
  session(store, "a");
  assert.equal(store.hasTurns("a"), false);
  store.startTurnFor("t1", "a", "input", { profile: "cc", person: "me@x", thread: 7 });
  store.endTurn("t1", "completed", null, "waiting", 60);
  store.setWaitFor("t1", "CI", false);
  // Turns started in the same ms tie in ORDER BY started_at (as in the Rust): keep them apart.
  store.db.exec("UPDATE turns SET started_at = started_at - 1000 WHERE id = 't1'");
  store.startTurn("t2", "a", "nudge");
  const t2 = store.db.prepare("SELECT profile, person, thread FROM turns WHERE id = 't2'").get() as any;
  assert.deepEqual({ ...t2 }, { profile: null, person: "me@x", thread: 7 });
  assert.equal(store.stopWait("a"), false, "the latest turn is not waiting");
  store.endTurn("t2", "completed", null, "waiting", 30);
  assert.equal(store.stopWait("a"), true);
  const last = store.lastTurn("a")!;
  assert.deepEqual([last.outcome, last.declared, last.waitSeconds, last.detail], ["aborted", null, null, "other: stopped while waiting"]);
  assert.deepEqual([store.listTurns("a")[0]!.summary.waitFor, store.listTurns("a")[0]!.summary.waitWatch], ["CI", false]);
  assert.equal(store.toldNotes("a") > 0, true, "a new session was told every note");
  store.setToldNotes("a", 3);
  assert.equal(store.toldNotes("a"), 3);
  const stats = store.sessionStats(null).get("a")!;
  assert.deepEqual([stats.turns, stats.lastTurn!.outcome], [2, "aborted"]);
});

test("bindings tell both sessions; delivered can be taken back", () => {
  const store = memory();
  session(store, "a");
  session(store, "b");
  const h = heard(store);
  store.setBinding("team", "b");
  store.setBinding("team", "a");
  assert.deepEqual(h.changes, [{ type: "session", key: "b" }, { type: "session", key: "a" }, { type: "session", key: "b" }]);
  assert.deepEqual([...store.listBindings()], [["a", ["team"]]]);
  h.stop();
  const thread = store.openThread("ember", "CHAT", "1.1", null, null);
  store.joinThread(thread.id, "a", "ember");
  const [n] = say(store, thread.id, "1.2", "person", "local", "hi");
  store.deliver(thread.id, n, ["a"]);
  store.markDelivered("a", [{ thread: thread.id, n, apart: false }]);
  assert.deepEqual([...store.heardThreads("a", [thread.id, 999])], [thread.id]);
  store.markUndelivered("a", [{ thread: thread.id, n, apart: false }]);
  assert.equal(store.pendingMessages("a").length, 1);
  assert.deepEqual([...store.heardThreads("a", [thread.id])], []);
});

// On a station (2026-11-03) a session's detail read its 378 jobs, each with its notices and its log looked at.
test("jobs: a session's detail as a device asks it lists its latest and those still up, by indexes", async () => {
  const store = memory();
  session(store, "a");
  const job = (i: number, over: Partial<JobRow> = {}): JobRow => ({
    id: `j${i}`, sessionKey: "a", name: `job ${i}`, command: "make", cwd: "/w/a", port: null, token: `t${i}`, state: "exited", pgid: null,
    exitCode: 0, startedAt: 10 + i, endedAt: 20 + i, restarts: 0, log: `/w/a/j${i}.log`, watch: false, ...over,
  });
  // The first a service still up, the second running: both from long ago; then 60 over.
  store.insertJob(job(0, { port: 4000 }));
  store.insertJob(job(1, { state: "running", endedAt: null, exitCode: null }));
  for (let i = 2; i < 62; i++) store.insertJob(job(i));
  const { session: detail } = await import("../src/read/sessions.ts");
  const viewer: Viewer = { sub: "u", email: "a@x", name: "A", role: "owner", workspace: "ws", device: "d", home: true };
  const r = read.makeStore(store.db, tempdir());
  const ids = (now: boolean) => detail(r, "a", viewer, "en", 0, now).jobs.map((j: any) => j.id);
  const latest = Array.from({ length: read.JOBS_NOW }, (_, k) => `j${61 - k}`);
  assert.deepEqual(ids(true), [...latest, "j1", "j0"], "the latest, newest first, then the old ones still up");
  assert.equal(ids(false).length, 62, "all of them, as a device from before asks");
  for (const [sql, args] of [[read.LATEST_JOBS, ["a", 5]], [read.UP_JOBS_OF, ["a"]]] as const) {
    const plan = (store.db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(...args) as { detail: string }[]).map((p) => p.detail);
    assert.ok(plan.every((d) => !/^SCAN jobs/.test(d)) && !plan.some((d) => d.includes("TEMP B-TREE")), plan.join(" | "));
  }
});

test("what is written of a chat beside what is said in it is told as written: archive review, shares, chats opened from it", () => {
  const store = memory();
  session(store, "a");
  const h = heard(store);
  store.suggestArchive("a", 7, 12);
  store.setArchiveVerdict("a", 7, 12, { picked: "archive" });
  store.clearArchiveSuggestion("a", 7);
  store.setChatShare("a", [{ workspace: "w2", name: "Two" }], true, "a@x");
  store.insertOpened({ childStation: "", child: "b", parentStation: "", parent: "a", key: "k", title: "子对话", link: null, openerTitle: null });
  h.stop();
  const marks = h.changes.filter((c) => c.type === "chatMark").map(({ type: _, ...m }: any) => m);
  assert.deepEqual(marks.map((m: any) => m.opened ? { ...m, opened: { ...m.opened, createdAt: 0 } } : m), [
    { thread: 7, session: "a", archive: { suggested: 12 } },
    { thread: 7, session: "a", archive: { verdict: { picked: "archive" } } },
    { thread: 7, session: "a", archive: { suggested: null } },
    { thread: null, session: "a", share: { to: [{ workspace: "w2", name: "Two" }], write: true } },
    { thread: null, session: "a", opened: { childStation: "", child: "b", parent: "a", title: "子对话", openerTitle: null, createdAt: 0 } },
  ]);
});

// On a station (2026-11-03) the archive was made whole at once: its many chats in 60 s, every other read of devices waiting.
test("the archive a page at a time, the latest archived first, each by the index of those archived; the sidebar by those shown", async () => {
  const time = testClock();
  await time.adjust(Date.parse("2026-11-03T00:00:00Z"));
  const store = Store.open(":memory:", null, time.clock);
  stores.push(store);
  for (const key of ["a", "b", "c", "d", "e"]) session(store, key);
  for (const key of ["b", "d", "a", "e"]) {
    await time.adjust(1000);
    store.setArchived(key, true, MANUAL);
  }
  const r = read.makeStore(store.db, tempdir());
  const pages: string[][] = [];
  let before: [number, string] = [Number.MAX_SAFE_INTEGER, "\uffff"];
  for (;;) {
    const page = read.archivedPage(r, before, 3);
    pages.push(page.map((i) => i.id));
    if (page.length < 3) break;
    before = [page.at(-1)!.at, page.at(-1)!.id];
  }
  assert.deepEqual(pages.flat().filter((id) => !/^\d+$/.test(id)), ["e", "a", "d", "b"], "each once, the latest archived first");
  assert.deepEqual(read.shownSessions(r).map((x) => x.key), ["c"]);
  for (const [sql, args] of [[read.ARCHIVED_PAGE, [Number.MAX_SAFE_INTEGER, "\uffff", 3]], [read.SHOWN_SESSIONS, []]] as const) {
    const plan = (store.db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(...args) as { detail: string }[]).map((p) => p.detail);
    assert.ok(!plan.some((d) => /^SCAN (sessions|threads)\b/.test(d) && !d.includes("INDEX sessions_live")), plan.join(" | "));
  }
});

test("the archived sessions by the index of those archived, the longest archived first; the log's file kept small", async () => {
  // Every session read whole on the main thread to find the archived held the station 8 to 13 s on a station (2026-11-03);
  // and the log's file stayed at the 520 MB it once grew to, with 1 GB of the disk left.
  const time = testClock();
  await time.adjust(Date.parse("2026-11-03T00:00:00Z"));
  const store = Store.open(join(tempdir(), "s.db"), null, time.clock);
  stores.push(store);
  for (const key of ["a", "b", "c"]) session(store, key);
  for (const key of ["c", "a"]) {
    await time.adjust(1000);
    store.setArchived(key, true, MANUAL);
  }
  assert.deepEqual(store.archivedSessions().map((s) => s.key), ["c", "a"]);
  const plan = (store.db.prepare("EXPLAIN QUERY PLAN SELECT key, archived_at FROM sessions INDEXED BY sessions_put_away WHERE archived_at IS NOT NULL ORDER BY archived_at, key").all() as { detail: string }[]).map((p) => p.detail).join(" | ");
  assert.match(plan, /sessions_put_away/);
  assert.ok(!/TEMP B-TREE/.test(plan), plan);
  assert.equal((store.db.prepare("PRAGMA journal_size_limit").get() as { journal_size_limit: number }).journal_size_limit, 64 << 20);
});

test("the card each chat waits on is kept as it is posted, answered and closed; one from before is worked out as it was", () => {
  // Worked out at each read of the sidebar's marks, a dozen lookups a chat, 26 s for 68 chats on a station (2026-11-03).
  const path = join(tempdir(), "s.db");
  const before = Store.open(path, null);
  session(before, "a");
  const old = before.openThread("ember", "CHAT", "old", null, null).id;
  before.insertMessage({ ...newMessage(old, "1.1", "agent", "a", "选一个"), card: { type: "options", options: [{ label: "好" }] } } as any);
  // As a database from before the cards were kept: made again on what is there.
  before.db.exec("DROP TABLE pending_cards; DROP TABLE pending_cards_from; DROP TRIGGER IF EXISTS pending_cards_post; DROP TRIGGER IF EXISTS pending_cards_answered; DROP TRIGGER IF EXISTS pending_cards_closed; DROP TRIGGER IF EXISTS pending_cards_gone");
  before.close();
  const store = open(path);
  const r = read.makeStore(store.db, tempdir());
  const chat = store.openThread("ember", "CHAT", "new", null, null).id;
  const card = { ...newMessage(chat, "2.1", "agent", "a", "选一个"), card: { type: "options", options: [{ label: "好" }] } } as any;
  const [n] = store.insertMessage(card);
  let kept = read.pendingCards(r, [old, chat])!;
  assert.deepEqual([[...kept.at], [...kept.before]], [[[chat, n]], [old]]);
  assert.equal(read.cardAt(r, chat, n)?.[0].n, n);
  // A person writes: it waits no more.
  say(store, chat, "2.2", "person", "a@x", "好");
  assert.deepEqual([...read.pendingCards(r, [chat])!.at], []);
  // Posted again, then closed: none.
  const [m] = store.insertMessage({ ...card, ts: "2.3" });
  assert.deepEqual([...read.pendingCards(r, [chat])!.at], [[chat, m]]);
  store.db.prepare("INSERT INTO closed_cards VALUES (?, ?, 'a@x', 1)").run(chat, m);
  kept = read.pendingCards(r, [chat])!;
  assert.deepEqual([...kept.at], []);
});

test("jobs: started, said, ended and cleared", () => {
  const store = memory();
  session(store, "a");
  const job: JobRow = {
    id: "j1", sessionKey: "a", name: "build", command: "make", cwd: "/w/a", port: null, token: "tok", state: "running", pgid: 10,
    exitCode: null, startedAt: 1, endedAt: null, restarts: 0, log: "/w/a/j1.log", watch: true,
  };
  const h = heard(store);
  store.insertJob(job);
  assert.deepEqual(store.getJob("j1"), job);
  assert.equal(store.jobByToken("tok")!.id, "j1");
  for (let i = 0; i < 55; i++) store.addJobNotice("j1", `n${i}`);
  assert.equal(store.jobNotices("j1", 100).length, 50);
  assert.equal(store.jobNotices("j1", 1)[0]!.text, "n54");
  store.jobStarted("j1", 11, true);
  assert.deepEqual([store.getJob("j1")!.pgid, store.getJob("j1")!.restarts], [11, 1]);
  store.jobEnded("j1", "exited", 0);
  assert.deepEqual(store.clearEndedJobs("a"), [["j1", "/w/a/j1.log"]]);
  assert.deepEqual(store.listJobs(null), []);
  assert.deepEqual(h.changes.slice(-2), [{ type: "session", key: "a" }, { type: "jobRemoved", id: "j1", session: "a" }]);
  h.stop();
});

test("usage: the sessions at work are found by when their turns ended, once each, not by reading every turn", () => {
  const store = memory();
  for (const key of ["a", "b", "c"]) session(store, key);
  store.startTurn("t1", "a", "input");
  store.startTurn("t2", "b", "input");
  store.endTurn("t2", "completed", null, null, null);
  store.startTurn("t3", "b", "input");
  store.endTurn("t3", "completed", null, null, null);
  store.startTurn("t4", "b", "job");
  assert.deepEqual(store.usageActiveSessions(0).sort(), ["a", "b"]);
  assert.deepEqual(store.usageActiveSessions(Number.MAX_SAFE_INTEGER).sort(), ["a", "b"], "running ones whenever");
});

test("what the station asks again and again is planned by an index, never a scan of what grows with time", () => {
  assertRecentChatPlans();
  assertPendingVaultPlans();
  assertRecoveryWaitPlans();
  assertAwakeJobPlan();
  assertSessionJobPlans();
  assertProcessJobPlans();
  assertActiveJobUpgradePlans();
  assertSandboxPlans();
  assertChatSharePlans();
  assertSessionDirectoryPlans();
  assertRemoteQueuePlan();
  const oldSaid = memory();
  installLegacySaid(oldSaid.db);
  const oldSaidPlan = (sql: string, ...args: (number | string)[]) =>
    (oldSaid.db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(...args) as { detail: string }[]).map((r) => r.detail);
  const needsDrain = oldSaidPlan(LEGACY_SAID_NEEDS_DRAIN,1);
  assert.ok(needsDrain.some((line) => line.includes("legacy_said_dirty USING PRIMARY KEY (thread=?)")), needsDrain.join(" | "));
  for (const [sql,args] of [
    [LEGACY_SAID_HEAD_FIRST,[1]], [LEGACY_SAID_HEAD_TAIL,[1]], [LEGACY_SAID_BOUNDARY_TAIL,[1,100,"alice"]],
  ] as [string,(number | string)[]][]) {
    const plan = oldSaidPlan(sql,...args);
    assert.ok(plan.some((line) => line.startsWith("SEARCH ") && line.includes("(thread=?")), plan.join(" | "));
    assert.ok(!plan.some((line) => /^SCAN (e|entries)\b/.test(line)), plan.join(" | "));
  }
  for (const [sql,args] of [[LEGACY_SAID_DRAIN,[64]], [LEGACY_SAID_DRAIN_THREAD,[1,64]]] as [string,number[]][]) {
    const plan = oldSaidPlan(sql,...args);
    assert.ok(plan.every((line) => !line.includes("TEMP B-TREE")), plan.join(" | "));
    if (sql === LEGACY_SAID_DRAIN_THREAD)
      assert.ok(plan.some((line) => line.includes("SEARCH d USING PRIMARY KEY (thread=?)")), plan.join(" | "));
  }
  const pageTail = oldSaidPlan(read.LEGACY_SAID_PAGE_TAIL,1,100,65);
  assert.ok(pageTail.some((line) => line.startsWith("SEARCH e ") && line.includes("thread=?") && line.includes("n<?")), pageTail.join(" | "));
  assert.ok(!pageTail.some((line) => line.includes("TEMP B-TREE")), pageTail.join(" | "));
  const store = memory();
  for (const [sql,args] of [
    [ARCHIVE_LAST_FIRST,[1]], [ARCHIVE_LAST_TAIL,[1]], [ARCHIVE_LAST_SLICE_FIRST,[1,64]],
    [ARCHIVE_LAST_SLICE_BEFORE,[1,"100",64]],
  ] as [string,(number | string)[]][]) {
    const plan = (store.db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(...args) as { detail: string }[]).map((r) => r.detail);
    assert.ok(plan.some((line) => line.startsWith("SEARCH e ") && line.includes("thread=?")), plan.join(" | "));
    assert.ok(!plan.some((line) => /^SCAN e\b/.test(line)), plan.join(" | "));
    if (sql === ARCHIVE_LAST_SLICE_FIRST || sql === ARCHIVE_LAST_SLICE_BEFORE)
      assert.ok(!plan.some((line) => line.includes("TEMP B-TREE")), plan.join(" | "));
    if (sql === ARCHIVE_LAST_SLICE_BEFORE)
      assert.ok(plan.some((line) => line.startsWith("SEARCH e ") && line.includes("n<?")), plan.join(" | "));
  }
  const archiveLastGuard = (store.db.prepare(`EXPLAIN QUERY PLAN ${ARCHIVE_LAST_GUARD}`).all(1) as { detail: string }[])
    .map((r) => r.detail);
  assert.ok(archiveLastGuard.some((line) => line.includes("SEARCH g USING PRIMARY KEY (thread=?)")), archiveLastGuard.join(" | "));
  for (const [sql, args, index] of [
    [ARCHIVE_LAST_SAID_KEY, [1], "entries_said"],
    [ARCHIVE_LAST_LETTER_ANY, [1], "entries_letters"],
    [ARCHIVE_LAST_LETTER_AFTER, [1, "100"], "entries_letters"],
  ] as [string, (number | string)[], string][]) {
    const plan = (store.db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(...args) as { detail: string }[]).map((r) => r.detail);
    assert.ok(plan.some((line) => line.startsWith("SEARCH e ") && line.includes(index) && line.includes("thread=?")), plan.join(" | "));
    assert.ok(!plan.some((line) => line.includes("TEMP B-TREE")), plan.join(" | "));
    if (sql === ARCHIVE_LAST_LETTER_AFTER)
      assert.ok(plan.some((line) => line.includes("n>?")), plan.join(" | "));
  }
  const lastMessage = (store.db.prepare(`EXPLAIN QUERY PLAN ${read.LAST_MESSAGE_KEYED}`).all(1, "100") as { detail: string }[])
    .map((r) => r.detail);
  assert.ok(lastMessage.some((line) => line.startsWith("SEARCH m ") && line.includes("thread=?") && line.includes("n=?")), lastMessage.join(" | "));
  const pageKeys = (store.db.prepare(`EXPLAIN QUERY PLAN ${read.MESSAGES_FROM_KEYS}`).all(1, '["1","2"]') as { detail: string }[])
    .map((r) => r.detail);
  assert.ok(pageKeys.some((line) => line.startsWith("SEARCH m ") && line.includes("thread=?") && line.includes("n=?")), pageKeys.join(" | "));
  const recentEdit = (store.db.prepare(`EXPLAIN QUERY PLAN ${read.LAST_MESSAGE_RECENT_EDIT}`).all(1, "100") as { detail: string }[])
    .map((r) => r.detail);
  assert.ok(recentEdit.some((line) => line.startsWith("SEARCH entries ") && line.includes("thread=?")), recentEdit.join(" | "));
  assert.ok(!recentEdit.some((line) => /^SCAN entries\b/.test(line)), recentEdit.join(" | "));
  const selectedEdit = (store.db.prepare(`EXPLAIN QUERY PLAN ${read.LAST_MESSAGE_WITH_EDIT}`).all(1, "100", "101") as { detail: string }[])
    .map((r) => r.detail);
  assert.ok(selectedEdit.some((line) => line.startsWith("SEARCH m ") && line.includes("thread=?") && line.includes("n=?")), selectedEdit.join(" | "));
  assert.ok(selectedEdit.some((line) => line.startsWith("SEARCH e ") && line.includes("thread=?") && line.includes("n=?")), selectedEdit.join(" | "));
  store.db.exec("CREATE INDEX entries_target ON entries(thread,target) WHERE target IS NOT NULL");
  const oldEdits = (store.db.prepare(`EXPLAIN QUERY PLAN ${read.LAST_MESSAGE_OLD_EDITS}`).all(1, "100") as { detail: string }[])
    .map((r) => r.detail);
  assert.ok(oldEdits.some((line) => line.startsWith("SEARCH x ") && line.includes("entries_target") && line.includes("target=?")), oldEdits.join(" | "));
  for (const [sql, value, table, key] of [[ARCHIVE_PIN_EXISTS, "s", "archive_pin_rows", "session"], [ARCHIVE_KEEP_EXISTS, 1, "archive_keep_rows", "thread"]] as const) {
    const plan = (store.db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(value) as { detail: string }[]).map((r) => r.detail);
    assert.ok(plan.some((s) => s.includes(`SEARCH ${table} USING PRIMARY KEY (${key}=?)`)), plan.join(" | "));
  }
  const bindingPlan = (store.db.prepare(`EXPLAIN QUERY PLAN ${SESSION_BINDINGS_SELECTED}`).all('["a"]') as { detail: string }[]).map((r) => r.detail);
  assert.ok(bindingPlan.some((line) => line.startsWith("SEARCH i ") && line.includes("session=?")), bindingPlan.join(" | "));
  assert.ok(!bindingPlan.some((line) => /^SCAN i\b/.test(line)), bindingPlan.join(" | "));
  for (const [sql, args, keys] of [
    [SESSION_LIST_SCOPE, ["ws", 1, 0], ["kind=?", "ws=?", "archived=?"]],
    [SESSION_LIST_SCOPE_CONNECT, ["ws", 1, 0, "a"], ["kind=?", "ws=?", "archived=?", "connect=?"]],
    [SESSION_LIST_CONNECT, [0, "a"], ["archived=?", "connect=?"]],
  ] as [string, unknown[], string[]][]) {
    const plan = (store.db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(...(args as never[])) as { detail: string }[]).map((r) => r.detail);
    assert.ok(plan.some((line) => line.startsWith("SEARCH i ") && keys.every((key) => line.includes(key))), `${sql}\n  ${plan.join(" | ")}`);
    assert.ok(plan.some((line) => line.startsWith("SEARCH s ") && line.includes("key=?")), plan.join(" | "));
    assert.ok(!plan.some((line) => /^SCAN (i|s)\b/.test(line)), plan.join(" | "));
  }
  const detail = detailQuery(1n, 1_000_001n, 1n, { workspace: "ws", home: false })!;
  const compact = memory();
  installCompactUsage(compact.db, () => 0);
  const usageBatch = read.batchedUsageQueries({ workspace: "ws", home: false });
  const usagePlans = [
    [usageBatch.selected, [0n, 100n, "Wws"]], [usageBatch.owner, ["a"]],
    [usageBatch.buckets, [0n, "a", 0n, 100n, "Wws"]], [usageBatch.anyPending, ["Wws"]], [usageBatch.pending, ["Wws"]],
    [usageBatch.pendingRange, [0n, 100n, "Wws"]],
  ] as [string, unknown[]][];
  for (const [sql, args] of usagePlans) {
    const plan = (compact.db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(...(args as never[])) as { detail: string }[]).map((r) => r.detail);
    assert.ok(plan.every((d) => !d.startsWith("SCAN ")), `${sql}\n  ${plan.join(" | ")}`);
  }
  installUsageSummaryBlocks(compact.db);
  const groups: [string, unknown[], string][] = [];
  for (const scoped of [false, true]) {
    for (const size of [1, 15, 60] as const) {
      const q = usageSummaryBlockQueries(scoped, size);
      const index = size === 1 ? (scoped ? "usage_summary_blocks_shadow_scope_time" : "usage_summary_blocks_shadow_time")
        : scoped ? "PRIMARY KEY" : "usage_summary_blocks_time";
      groups.push([q.selected, scoped ? [0, 100, "Wws"] : [0, 100], index]);
    }
    const q = usageSummaryBlockQueries(scoped, 60);
    const index = scoped ? "PRIMARY KEY" : "usage_summary_blocks_time";
    groups.push([q.next, scoped ? [0, 100, "Wws"] : [0, 100], index], [q.last, scoped ? ["Wws"] : [], index]);
  }
  for (const side of ["time", "old", "new"] as const) {
    groups.push([usageSummaryBlockPendingQuery(side), side === "time" ? [0, 100] : [0, 100, "Wws"], `usage_summary_blocks_dirty_${side}`]);
  }
  const rowKey = ["a", 0, 0, "p", "cc", "claude", "m", 0];
  for (const current of [false, true]) groups.push([usageSummaryBlockOverlayQuery(current), rowKey, "PRIMARY KEY"]);
  groups.push([usageSummaryBlocksScan(true, false), ["Wws", 32], "usage_compact_scope_time"]);
  groups.push([usageSummaryBlocksScan(true, true), ["Wws", 0, "a", 0, "p", "cc", "claude", "m", 0, 32], "usage_compact_scope_time"]);
  groups.push([usageSummaryBlocksScan(false, true), [...rowKey, 32], "PRIMARY KEY"]);
  groups.push([usageSummaryBlocksRangeScan(true, false), ["Wws", 0, 100, 32], "usage_compact_scope_time"]);
  groups.push([usageSummaryBlocksRangeScan(true, true), ["Wws", 0, 100, 0, "a", 0, "p", "cc", "claude", "m", 0, 32], "usage_compact_scope_time"]);
  groups.push([usageSummaryBlocksRangeScan(false, false), [0, 100, 32], "usage_compact_time"]);
  groups.push([usageSummaryBlocksRangeScan(false, true), [0, 100, 0, "a", 0, "p", "cc", "claude", "m", 0, 32], "usage_compact_time"]);
  for (const [sql, args, index] of groups) {
    const plan = (compact.db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(...(args as never[])) as { detail: string }[]).map((r) => r.detail);
    assert.ok(plan.some((d) => d.startsWith("SEARCH ") && d.includes(index)), `${sql}\n  ${plan.join(" | ")}`);
    assert.ok(plan.every((d) => !d.includes("TEMP B-TREE")), `${sql}\n  ${plan.join(" | ")}`);
  }
  for (const scope of ["all", "workspace", "home"] as const) {
    const sql = usageSummaryEdgeQuery(scope);
    const args = scope === "workspace" ? [0, 0, "Wws", 1, 2, "ws"] : [0, 0, scope === "home" ? "H" : null, 1, 2];
    const plan = (compact.db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(...args) as { detail: string }[]).map((r) => r.detail);
    const index = scope === "all" ? "usage_compact_time" : "usage_compact_scope_time";
    assert.ok(plan.some((d) => d.startsWith("SEARCH ") && d.includes(index)), `${sql}\n  ${plan.join(" | ")}`);
    assert.ok(plan.some((d) => d.startsWith("SEARCH ") && d.includes("usage_session")), `${sql}\n  ${plan.join(" | ")}`);
    assert.ok(plan.every((d) => !d.includes("TEMP B-TREE")), `${sql}\n  ${plan.join(" | ")}`);
  }
  // As the station's SQLite (node's) plans each: a scan only of an index that holds the sessions shown or running, the
  // login cards, or of the small one that counts sessions (or of what a subquery found); a table, or an index of every
  // turn, job or entry, never.
  const planned: [string, unknown[]][] = [
    [read.ORIGINAL_RUNTIME, ["a"]],
    [ACTIVE_SESSIONS, [0]], [LIVE_SESSIONS, []], [ANY_RUNNING, []], [RUNNING_SESSIONS, []], [JOBS_RUNNING, []], [JOBS_UP, []], [JOB_AT_PORT, [5100]], [SESSION_JOBS, ["a"]],
    [HAS_SESSION_ACTIVE_WATCH, ["a"]], [RUNNING_WAIT_JOBS, ["a"]], [SESSION_THREAD_BY_ID, [1, "a"]],
    [LATEST_THREAD_ATTEMPT, ["a"]], [LATEST_THREAD_SCOPE, ["a"]],
    [THREAD_INSERT_IF_ABSENT, ["slack", "C", "1", null, null, 1, null]],
    [MEMBER_JOIN_IF_NEEDED, [1, "a", "slack", 1]], [DELIVERY_INSERT_IF_ABSENT, [1, 1, "a"]], [DELIVERY_INSERT_IF_MEMBER, [1, 1, "a", MANUAL]], [ROUTER_WORKSPACE_MISMATCH, [1, "home", "home"]],
    [STATS_OF, ["a"]], [SESSION_COUNT_TOTAL, [1, "ws"]], [SESSION_COUNT_CONNECT, [1, "ws", "a"]],
    [SESSION_COUNT_FIRST, ["100", 64]], [SESSION_COUNT_NEXT, ["1", "100", 64]],
    [SESSION_LIST_FIRST, ["100", 64]], [SESSION_LIST_NEXT, ["1", "100", 64]],
    [SESSION_BINDINGS_FIRST, ["100", 64]], [SESSION_BINDINGS_NEXT, ["1", "100", 64]],
    [SESSION_BINDINGS_EXISTS, ["a"]],
    [SESSION_UP_JOB, ["a"]], [SESSION_UP_JOBS, ["a"]],
    [SESSION_UP_JOBS_END, ["a"]],
    [SESSION_UP_JOBS_FIRST, ["a", "100", 64]], [SESSION_UP_JOBS_NEXT, ["a", "1", "100", 64]],
    [WIDGET_SOURCE_POSITIONS_FIRST, [1, "100", 64]], [WIDGET_SOURCE_POSITIONS_NEXT, [1, "1", "100", 64]],
    [LATEST_DECISIONS, [0]], [ARCHIVE_POLICY, ["ws"]], [CLOSED_THREAD_SINCE, [1, 0]], [LOGIN_CARDS, ["%l1%"]], [CARD_BEFORE, [1, 9]], [OPTIONS_BEFORE, [1, 9]],
    [TURNS_FROM, ["a", 0]], [TURNS_BETWEEN, ["a", 0, 9]], [TAKEN_SINCE, ["a", "ember", 0]], [SESSION_OF_RUNTIME, ["claude", "r1"]], [SAID_SINCE, [1, 0]],
    [HEARD_IN, ["a", 1]], [MODELS_USED_BY, ["a@x", 0]], [REMOTE_RUNS_OF, ["ws", 0]], [REMOTE_RUNS_ALL, [0]],
    [detail.sql, detail.args], [HISTORY_DAYS, ["ws", 0n, 100n, 480n]], [HISTORY_AFTER, ["ws", 100n]], [HISTORY_TOTAL, ["ws"]],
    [HISTORY_SCOPES, []], [HISTORY_SEED_CALLS, [0]], [read.SAID_LATEST, [1]], [read.SAID_SCAN, [1, 100, 64]], [read.SAID_STATE, [1]],
    [CARD_POST_BEFORE, [1, 9]], [CARD_POST_NEXT, [1, 0]], [CARD_POST_AFTER, [1, 0]], [CARD_POST_LATEST, [1]], [CARD_POST_SAMPLE, [1]],
    [CLOSED_CARD_AFTER_POSTS, [1, 0]],
    [read.HAS_ANSWER_PEOPLE_SINCE, [1, 0]],
    [read.FIRST_ANSWER_PERSON_SINCE, [1, 0]], [read.ANSWER_PEOPLE_AFTER, [1, 0, 1]],
    [read.ANSWER_NEXT_PERSON, [1, 0]],
    [POST_BLOCKS_READY, [1, 0]], [POST_AFTER_FIRST, [1, 0]], [POST_AFTER_INDEXED, [1, "a", 0, 0]],
  ];
  const scans = /^SCAN (?!CONSTANT ROW$|parts$|\(subquery-\d+\)$|\w+ USING (?:COVERING )?INDEX (?:sessions_live|sessions_running|sessions_by_connect|entries_login_cards)\b)/;
  const plans = new Map<string, string[]>();
  for (const [sql, args] of planned) {
    const plan = (store.db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(...(args as never[])) as { detail: string }[]).map((r) => r.detail);
    // The detail query materializes only keys sought inside the requested range, then scans those keys in session
    // order. It must still seek the underlying lookup below (asserted separately), not scan the historical table.
    assert.ok(!plan.some((d) => scans.test(d)
      && !(sql === detail.sql && d === "SCAN target" && plan.includes("MATERIALIZE targets"))
      && !(sql === RUNNING_WAIT_JOBS && d === "SCAN active" && plan.includes("CO-ROUTINE active"))
      // `small` contains at most two memberships; `choice` is its one-row sentinel.
      && !(sql === LATEST_THREAD_ATTEMPT && (d === "SCAN small" || d === "SCAN p"))
      && !(sql === POST_AFTER_INDEXED && (d === "SCAN first" || d === "SCAN second"))
      // One row a workspace.
      && !(sql === HISTORY_SCOPES && d === "SCAN usage_history_total")), `${sql}\n  ${plan.join(" | ")}`);
    plans.set(sql, plan);
  }
  assert.equal(plans.get(JOB_AT_PORT)!.filter((d) => d.includes("jobs_up (state=? AND port=?)")).length, 2,
    "a port is sought among running and restarting services");
  assert.ok(plans.get(SESSION_THREAD_BY_ID)!.some((d) => d.includes("(thread=? AND session=?)")));
  assert.ok(plans.get(SESSION_THREAD_BY_ID)!.some((d) => d.includes("INTEGER PRIMARY KEY (rowid=?)")));
  assert.match(LATEST_THREAD_ATTEMPT, /session=\?1 LIMIT 2/);
  assert.ok(plans.get(LATEST_THREAD_ATTEMPT)!.some((d) => d.includes("thread_sessions_session (session=?)")));
  assert.ok(plans.get(LATEST_THREAD_ATTEMPT)!.some((d) => d.includes("SEARCH r USING PRIMARY KEY (session=?)")));
  assert.ok(!plans.get(LATEST_THREAD_ATTEMPT)!.some((d) => d.includes("TEMP B-TREE")));
  assert.ok(plans.get(LATEST_THREAD_SCOPE)!.some((d) => d.includes("PRIMARY KEY (session=?)")));
  assert.ok(plans.get(THREAD_INSERT_IF_ABSENT)!.some((d) => d.includes("(surface=? AND channel=? AND thread_ts=?)")));
  assert.ok(plans.get(MEMBER_JOIN_IF_NEEDED)!.some((d) => d.includes("(thread=? AND session=?)")));
  assert.ok(plans.get(DELIVERY_INSERT_IF_ABSENT)!.some((d) => d.includes("(thread=? AND n=? AND session=?)")));
  assert.ok(plans.get(DELIVERY_INSERT_IF_MEMBER)!.some((d) => d.includes("(thread=? AND session=?)")));
  assert.ok(plans.get(DELIVERY_INSERT_IF_MEMBER)!.some((d) => d.includes("(thread=? AND n=?)")));
  assert.ok(plans.get(DELIVERY_INSERT_IF_MEMBER)!.some((d) => d.includes("(thread=? AND n=? AND session=?)")));
  assert.ok(plans.get(ROUTER_WORKSPACE_MISMATCH)!.some((d) => d.includes("(thread=?)")));
  assert.ok(plans.get(ROUTER_WORKSPACE_MISMATCH)!.some((d) => d.includes("(key=?)")));
  assert.ok(plans.get(SESSION_COUNT_TOTAL)!.some((d) => d.includes("PRIMARY KEY (kind=? AND ws=?)")));
  assert.ok(plans.get(SESSION_COUNT_CONNECT)!.some((d) => d.includes("PRIMARY KEY (kind=? AND ws=? AND connect=?)")));
  assert.ok(plans.get(SESSION_COUNT_FIRST)!.some((d) => d.includes("INTEGER PRIMARY KEY (rowid<?)")));
  assert.ok(plans.get(SESSION_COUNT_NEXT)!.some((d) => d.includes("INTEGER PRIMARY KEY (rowid>? AND rowid<?)")));
  assert.ok(plans.get(SESSION_LIST_FIRST)!.some((d) => d.includes("INTEGER PRIMARY KEY (rowid<?)")));
  assert.ok(plans.get(SESSION_LIST_NEXT)!.some((d) => d.includes("INTEGER PRIMARY KEY (rowid>? AND rowid<?)")));
  assert.ok(plans.get(SESSION_BINDINGS_FIRST)!.some((d) => d.includes("INTEGER PRIMARY KEY (rowid<?)")));
  assert.ok(plans.get(SESSION_BINDINGS_NEXT)!.some((d) => d.includes("INTEGER PRIMARY KEY (rowid>? AND rowid<?)")));
  assert.ok(plans.get(SESSION_BINDINGS_EXISTS)!.some((d) => d.includes("session_binding_rows USING PRIMARY KEY (session=?)")));
  assert.ok(plans.get(SESSION_UP_JOB)!.some((d) => d.includes("session_up_job_rows USING PRIMARY KEY (session=?)")));
  assert.ok(plans.get(SESSION_UP_JOBS)!.some((d) => d.includes("SEARCH i USING PRIMARY KEY (session=?)")));
  assert.ok(plans.get(SESSION_UP_JOBS_END)!.some((d) => d.includes("jobs_by_session (session_key=?)")));
  assert.ok(plans.get(SESSION_UP_JOBS_FIRST)!.some((d) => d.includes("jobs_by_session (session_key=? AND rowid<?)")));
  assert.ok(plans.get(SESSION_UP_JOBS_NEXT)!.some((d) => d.includes("jobs_by_session (session_key=? AND rowid>? AND rowid<?)")));
  for (const sql of [WIDGET_SOURCE_POSITIONS_FIRST, WIDGET_SOURCE_POSITIONS_NEXT]) {
    assert.ok(plans.get(sql)!.some((d) => d.includes("MERGE (UNION ALL)")));
    assert.ok(plans.get(sql)!.some((d) => d.includes("entries_said (thread=?")));
    assert.ok(plans.get(sql)!.some((d) => d.includes("entries_letters (thread=?")));
    assert.ok(!plans.get(sql)!.some((d) => d.includes("TEMP B-TREE")));
  }
  // A session's messages not delivered yet: by the index of those alone, not every message it was ever given; and its
  // turns not counted (auto-archiving read each shown session's every delivery and turn so: 13 s and 22 s on a station).
  assert.ok(plans.get(STATS_OF)!.some((d) => d.includes("deliveries_pending (session=?)")), plans.get(STATS_OF)!.join(" | "));
  assert.ok(!plans.get(STATS_OF)!.some((d) => d.includes("COVERING INDEX turns_by_session")), plans.get(STATS_OF)!.join(" | "));
  // Whether a session heard from a thread: by its deliveries there alone, not every message it was ever given (3.3 s on
  // the main thread on a station); the models someone's chats ran on from the index alone.
  assert.ok(plans.get(HEARD_IN)!.some((d) => d.includes("deliveries_session (session=? AND thread=?)")), plans.get(HEARD_IN)!.join(" | "));
  assert.ok(plans.get(POST_AFTER_FIRST)!.some((d) => d.includes("(thread=? AND n>?)")), plans.get(POST_AFTER_FIRST)!.join(" | "));
  assert.ok(plans.get(POST_AFTER_INDEXED)!.some((d) => d.includes("PRIMARY KEY (thread=? AND author=? AND bucket>?)")), plans.get(POST_AFTER_INDEXED)!.join(" | "));
  assert.ok(plans.get(POST_AFTER_INDEXED)!.some((d) => d.includes("(thread=? AND n>? AND n<?)")), plans.get(POST_AFTER_INDEXED)!.join(" | "));
  assert.ok(plans.get(MODELS_USED_BY)!.some((d) => d.includes("COVERING INDEX sessions_models (created_by=? AND created_at>?)")), plans.get(MODELS_USED_BY)!.join(" | "));
  assert.ok(plans.get(REMOTE_RUNS_OF)!.some((d) => d.includes("PRIMARY KEY (ws=? AND at>?)")), plans.get(REMOTE_RUNS_OF)!.join(" | "));
  assert.ok(plans.get(REMOTE_RUNS_ALL)!.some((d) => d.includes("PRIMARY KEY (at>?)")), plans.get(REMOTE_RUNS_ALL)!.join(" | "));
  assert.ok(plans.get(detail.sql)!.some((d) => d.includes("usage_detail_lookup_scope (scope=? AND level=? AND bucket>? AND bucket<?)")), plans.get(detail.sql)!.join(" | "));
  // The usage page's year: its own workspace's quarters of those days alone; installing it, the calls from a time on.
  assert.ok(plans.get(HISTORY_DAYS)!.some((d) => d.includes("PRIMARY KEY (scope=? AND quarter>? AND quarter<?)")), plans.get(HISTORY_DAYS)!.join(" | "));
  assert.ok(plans.get(HISTORY_AFTER)!.some((d) => d.includes("PRIMARY KEY (scope=? AND quarter>?)")), plans.get(HISTORY_AFTER)!.join(" | "));
  assert.ok(plans.get(HISTORY_SEED_CALLS)!.some((d) => d.includes("INDEX usage_at (at>?)")), plans.get(HISTORY_SEED_CALLS)!.join(" | "));
  // The latest card before a message: by the index of cards, not by going back over the thread to it.
  assert.ok(plans.get(CARD_BEFORE)!.some((d) => d.includes("entries_cards")), plans.get(CARD_BEFORE)!.join(" | "));
  assert.ok(plans.get(OPTIONS_BEFORE)!.some((d) => d.includes("entries_options")), plans.get(OPTIONS_BEFORE)!.join(" | "));
  assert.ok(plans.get(SAID_SINCE)!.some((d) => d.includes("entries_people_since (thread=? AND at>?)")), plans.get(SAID_SINCE)!.join(" | "));
  assert.ok(plans.get(CLOSED_THREAD_SINCE)!.some((d) => d.includes("closed_cards_thread_at (thread=? AND at>?)")), plans.get(CLOSED_THREAD_SINCE)!.join(" | "));
  // Each session's latest check of the last days: from the index of their times alone.
  assert.ok(plans.get(LATEST_DECISIONS)!.some((d) => d.includes("COVERING INDEX decision_checks_lately")), plans.get(LATEST_DECISIONS)!.join(" | "));
  // An old store's ready branch also reads times and sessions from a covering index; the small workspace path seeks
  // its sessions and their checks. The no-time fallback uses those same seeks if a time index disappears.
  const decisionOld = memory();
  decisionOld.db.exec("CREATE INDEX decision_checks_at ON decision_checks(created_at)");
  const putDecision = decisionOld.db.prepare("INSERT INTO decision_checks(session,created_at,result) VALUES('old',1,'{}')");
  for (let n = 0; n < 64; n++) putDecision.run();
  decisionOld.db.exec("DROP INDEX decision_checks_lately");
  installDecisionTimeIndex(decisionOld.db);
  for (const [sql, args] of [[LEGACY_LATEST_DECISIONS, [0]], [LEGACY_LATEST_DECISIONS_SCOPED, [0, "ws", 0]],
    [LEGACY_LATEST_DECISIONS_SCOPED_FALLBACK, [0, "ws", 1]]] as [string, unknown[]][]) {
    const oldPlan = (decisionOld.db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(...(args as never[])) as { detail: string }[]).map((r) => r.detail);
    assert.ok(oldPlan.some((d) => d.includes("COVERING INDEX legacy_decision_time_at (created_at>?)")), oldPlan.join(" | "));
    if (sql === LEGACY_LATEST_DECISIONS_SCOPED) {
      assert.ok(oldPlan.some((d) => d.includes("sessions_by_connect") && d.includes("connect=?") && d.includes("ws=?")), oldPlan.join(" | "));
      assert.ok(oldPlan.some((d) => d.includes("decision_checks_session") && d.includes("session=?")), oldPlan.join(" | "));
    }
  }
  const noTimePlan = (decisionOld.db.prepare(`EXPLAIN QUERY PLAN ${LATEST_DECISIONS_SCOPED_NO_TIME}`).all(0, "ws", 0) as { detail: string }[]).map((r) => r.detail);
  assert.ok(noTimePlan.some((d) => d.includes("sessions_by_connect") && d.includes("connect=?") && d.includes("ws=?")), noTimePlan.join(" | "));
  assert.ok(noTimePlan.some((d) => d.includes("decision_checks_session") && d.includes("session=?")), noTimePlan.join(" | "));
  const decisionRepair = memory();
  const putRepair = decisionRepair.db.prepare("INSERT INTO decision_checks(session,created_at,result) VALUES('old',1,'{}')");
  for (let n = 0; n < 64; n++) putRepair.run();
  decisionRepair.db.exec("DROP INDEX decision_checks_session");
  installDecisionSessionIndex(decisionRepair.db);
  decisionRepair.db.exec("DROP INDEX legacy_decision_session_by_session");
  installDecisionSessionIndex(decisionRepair.db);
  const repairLast = (decisionRepair.db.prepare(`EXPLAIN QUERY PLAN ${LEGACY_LAST_DECISION_REPAIR}`).all("old") as { detail: string }[]).map((r) => r.detail);
  assert.ok(repairLast.some((d) => d.includes("legacy_decision_session_repair_by_session") && d.includes("session=?")), repairLast.join(" | "));
  assert.ok(repairLast.some((d) => d.includes("INTEGER PRIMARY KEY (rowid=?)")), repairLast.join(" | "));
  const repairScope = (decisionRepair.db.prepare(`EXPLAIN QUERY PLAN ${decisionScopedWithSession(false, false, "repair")}`)
    .all(0, "ws", 0) as { detail: string }[]).map((r) => r.detail);
  assert.ok(repairScope.some((d) => d.includes("legacy_decision_session_repair_by_session") && d.includes("session=?")), repairScope.join(" | "));
  // Current policy: seek this workspace's most recent change. An old store keeps the original scan only until its
  // background lookup is prepared; its ready branch must seek the workspace, then the chosen row by primary key.
  assert.ok(plans.get(ARCHIVE_POLICY)!.some((d) => d.includes("archive_policy_by_ws (ws=?)")), plans.get(ARCHIVE_POLICY)!.join(" | "));
  const policyOld = memory();
  policyOld.db.exec("DROP INDEX archive_policy_by_ws");
  const putPolicy = policyOld.db.prepare("INSERT INTO archive_policy(at,policy,author,summary,ws) VALUES(0,'{}','{}','','ws')");
  for (let n=0;n<64;n++) putPolicy.run();
  installArchivePolicyIndex(policyOld.db);
  const oldPolicyPlan = (policyOld.db.prepare(`EXPLAIN QUERY PLAN ${LEGACY_ARCHIVE_POLICY}`).all("ws") as { detail: string }[]).map((r) => r.detail);
  assert.ok(oldPolicyPlan.some((d) => d.includes("archive_policy_lookup_ws (ws=?)")), oldPolicyPlan.join(" | "));
  assert.ok(oldPolicyPlan.some((d) => d.includes("INTEGER PRIMARY KEY (rowid=?)")), oldPolicyPlan.join(" | "));
  // The turns the usage counter reads at each part of a transcript: those of its calls' time alone.
  assert.ok(plans.get(TURNS_BETWEEN)!.some((d) => d.includes("turns_by_session (session_key=? AND started_at>? AND started_at<?)")), plans.get(TURNS_BETWEEN)!.join(" | "));
  assert.ok(plans.get(TAKEN_SINCE)!.some((d) => d.includes("deliveries_taken (session=? AND delivered_at>?)")), plans.get(TAKEN_SINCE)!.join(" | "));
  // What each says.
  session(store, "a");
  session(store, "b");
  store.setArchived("b", true, MANUAL);
  assert.deepEqual(store.liveSessions().map((s) => s.key), ["a"]);
  assert.deepEqual(store.sessionCounts(), [{ connect: "ds", ws: null, n: 2 }]);
  assert.equal(store.anyRunning(), false);
  store.startTurn("t1", "a", "input");
  const stats = store.statsOf(["a", "missing"]);
  assert.deepEqual([...stats.keys()], ["a"]);
  assert.deepEqual(stats.get("a"), { pending: 0, lastTurn: stats.get("a")!.lastTurn });
  assert.equal(stats.get("a")!.lastTurn?.kind, "input");
  // In use: shown, or at work though archived.
  assert.deepEqual(store.sessionsInUse().map((s) => s.key), ["a"]);
  store.setRunning("b", true);
  assert.deepEqual(store.runningSessions().map((s) => s.key), ["b"]);
  assert.deepEqual(store.sessionsInUse().map((s) => s.key), ["a", "b"]);
  store.setRunning("a", true);
  assert.deepEqual(store.sessionsInUse().map((s) => s.key).sort(), ["a", "b"], "each once");
  // The session that went on with a runtime's session: by its current one, or one it ran in before.
  store.setRuntimeSessionId("a", "r2");
  store.ranIn("b", "r1", null);
  assert.equal(store.sessionOfRuntime("claude", "r2")?.key, "a");
  assert.equal(store.sessionOfRuntime("claude", "r1")?.key, "b");
  assert.equal(store.sessionOfRuntime("codex", "r1"), null, "another runtime's");
  assert.equal(store.sessionOfRuntime("claude", "r9"), null);
});

test("what is told as chats change is planned by the size of what it finds, not by a chat's or a session's history", () => {
  assertRecentChatPlans();
  assertPendingVaultPlans();
  assertRecoveryWaitPlans();
  assertAwakeJobPlan();
  assertSessionJobPlans();
  assertProcessJobPlans();
  assertActiveJobUpgradePlans();
  assertSandboxPlans();
  assertChatSharePlans();
  assertSessionDirectoryPlans();
  assertRemoteQueuePlan();
  const store = memory();
  // As node's SQLite plans each, over the file the readers read: a chat's unread messages counted from the index of its
  // messages alone; an agent's message during a turn by the index of theirs by time; a session's turns as counted, its
  // undelivered messages by the index of those alone, its latest turn by its index; the Slack threads a chat copies to,
  // by their last entry; and of the items a change touched, or of a chat, their own shares and openers. Each
  // as it was read every message of a chat, every turn or delivery of a session, or every row of its table: a notice of
  // a chat of many messages read many pages, 3 to 16 s on a station short of memory (2026-11-02), every telling after it waiting.
  const planned: [string, unknown[]][] = [
    [read.UNREAD, [1, 0, "[]"]], [read.ASKED_DURING, [1, 0, 9]], [`${read.SESSION_STATS} WHERE s.key = ?`, ["a"]], [`${read.SESSION_ACTIVITY} WHERE s.key = ?`, ["a"]], [read.LAST_TURN, ["a"]], [read.LATEST_TURNS, ["a", 1]], [CC_THREADS_SQL, [1]],
    [read.SHARES_OF, ['["a"]']], [read.OPENERS_OF, ['["a"]']], [read.OPENED_OF, ['["a"]']], [read.PINS_OF, ["a@x", '["a"]']],
    [`${read.SEEN_OF} WHERE key IN (SELECT value FROM json_each(?))`, ['["a"]']], [read.TOLD_BLOCKED, ["a", 0, 9]], [read.RUNNING_OF, ['["a"]']],
    [SESSION_COUNT_DISPLACED, ["a", "token", 1]],
    [SESSION_LIST_DISPLACED, ["a", "token", 1]],
    [SESSION_BINDINGS_DISPLACED, ["a", 1]],
    [SESSION_BINDINGS_DELETE, ["a"]],
    [SESSION_UP_JOBS_DISPLACED, ["a", "token", 1]],
    [SESSION_UP_JOBS_CONFLICT, ["a", "token", 1]],
    [SESSION_THREAD_BY_ID, [1, "a"]],
    [LATEST_THREAD_ATTEMPT, ["a"]], [LATEST_THREAD_SCOPE, ["a"]],
    [THREAD_INSERT_IF_ABSENT, ["slack", "C", "1", null, null, 1, null]],
    [MEMBER_JOIN_IF_NEEDED, [1, "a", "slack", 1]], [DELIVERY_INSERT_IF_ABSENT, [1, 1, "a"]], [DELIVERY_INSERT_IF_MEMBER, [1, 1, "a", MANUAL]], [ROUTER_WORKSPACE_MISMATCH, [1, "home", "home"]],
    [WIDGET_SOURCE, ["a", "/w/item.html"]], [WIDGET_SOURCE_MISSING, ["a"]], [WIDGET_SOURCE_UNUSUAL, ["a"]],
  ];
  const scans = /^SCAN (?!CONSTANT ROW$|\(subquery-\d+\)$|json_each VIRTUAL TABLE\b)/;
  const plans = new Map<string, string[]>();
  for (const [sql, args] of planned) {
    const plan = (store.db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(...(args as never[])) as { detail: string }[]).map((r) => r.detail);
    assert.ok(!plan.some((d) => scans.test(d)
      && !(sql === LATEST_THREAD_ATTEMPT && (d === "SCAN small" || d === "SCAN p"))), `${sql}\n  ${plan.join(" | ")}`);
    plans.set(sql, plan);
  }
  const has = (sql: string, step: string) => assert.ok(plans.get(sql)!.some((d) => d.includes(step)), `${step}\n  ${plans.get(sql)!.join(" | ")}`);
  const lacks = (sql: string, step: string) => assert.ok(!plans.get(sql)!.some((d) => d.includes(step)), `${step}\n  ${plans.get(sql)!.join(" | ")}`);
  assert.equal(plans.get(SESSION_COUNT_DISPLACED)!.filter((d) => d.startsWith("SEARCH sessions")).length, 3,
    "a replacing session finds at most one row by each unique identity");
  assert.equal(plans.get(SESSION_LIST_DISPLACED)!.filter((d) => d.startsWith("SEARCH s ")).length, 3,
    "session list updates find displaced rows by unique identity");
  assert.equal(plans.get(SESSION_BINDINGS_DISPLACED)!.filter((d) => d.startsWith("SEARCH b ")).length, 2,
    "binding updates find displaced rows by connection or rowid");
  assert.equal(plans.get(SESSION_UP_JOBS_DISPLACED)!.filter((d) => d.startsWith("SEARCH j ")).length, 3,
    "job updates find displaced rows by id, token or rowid");
  assert.equal(plans.get(SESSION_UP_JOBS_CONFLICT)!.filter((d) => d.startsWith("SEARCH jobs ")).length, 3,
    "job inserts check each conflicting identity by an index");
  has(SESSION_BINDINGS_DELETE, "session_binding_rows USING PRIMARY KEY (session=?)");
  has(SESSION_BINDINGS_DELETE, "bindings USING INTEGER PRIMARY KEY (rowid=?)");
  has(SESSION_THREAD_BY_ID, "(thread=? AND session=?)");
  has(SESSION_THREAD_BY_ID, "INTEGER PRIMARY KEY (rowid=?)");
  has(LATEST_THREAD_ATTEMPT, "thread_sessions_session (session=?)");
  has(LATEST_THREAD_ATTEMPT, "SEARCH r USING PRIMARY KEY (session=?)");
  lacks(LATEST_THREAD_ATTEMPT, "TEMP B-TREE");
  has(LATEST_THREAD_SCOPE, "PRIMARY KEY (session=?)");
  has(THREAD_INSERT_IF_ABSENT, "(surface=? AND channel=? AND thread_ts=?)");
  has(MEMBER_JOIN_IF_NEEDED, "(thread=? AND session=?)");
  has(DELIVERY_INSERT_IF_ABSENT, "(thread=? AND n=? AND session=?)");
  has(DELIVERY_INSERT_IF_MEMBER, "(thread=? AND session=?)");
  has(DELIVERY_INSERT_IF_MEMBER, "(thread=? AND n=?)");
  has(DELIVERY_INSERT_IF_MEMBER, "(thread=? AND n=? AND session=?)");
  has(ROUTER_WORKSPACE_MISMATCH, "(thread=?)");
  has(ROUTER_WORKSPACE_MISMATCH, "(key=?)");
  has(read.UNREAD, "COVERING INDEX entries_said (thread=? AND n>?)");
  has(read.ASKED_DURING, "entries_agent_at (thread=? AND at>? AND at<?)");
  const stats = `${read.SESSION_STATS} WHERE s.key = ?`;
  has(stats, "c USING PRIMARY KEY (session=?)");
  has(stats, "w USING PRIMARY KEY (session=?)");
  // Whether a turn of it ended before its work was kept: its first by its end, from the index alone.
  has(stats, "o USING COVERING INDEX turns_by_end (session_key=?");
  has(stats, "deliveries_pending (session=?)");
  // An uncounted old session checks at most 65 of its own turns before asking for bounded preparation.
  has(stats, "old USING COVERING INDEX turns_by_session (session_key=?)");
  lacks(`${read.SESSION_ACTIVITY} WHERE s.key = ?`, "session_turns");
  lacks(stats, "deliveries_session");
  has(read.LAST_TURN, "turns_by_session (session_key=?)");
  // A session's latest turns by the index of its turns, from its end: not every turn read and sorted.
  has(read.LATEST_TURNS, "turns_by_session (session_key=?)");
  lacks(read.LATEST_TURNS, "TEMP B-TREE");
  has(CC_THREADS_SQL, "e USING INDEX sqlite_autoindex_entries_1 (thread=? AND n=?)");
  lacks(CC_THREADS_SQL, "e USING INDEX sqlite_autoindex_entries_1 (thread=?)");
  // The original lookup remains only for noncanonical attachment JSON, which older SQLite writers cannot validate.
  has(WIDGET_SOURCE, "thread_sessions_session (session=?)");
  has(WIDGET_SOURCE, "widget_source_by_path (thread=? AND path=?)");
  for (const sql of [WIDGET_SOURCE_MISSING, WIDGET_SOURCE_UNUSUAL]) has(sql, "thread_sessions_session (session=?)");
  has(WIDGET_SOURCE_MISSING, "s USING PRIMARY KEY (thread=?)");
  has(WIDGET_SOURCE_UNUSUAL, "i USING PRIMARY KEY (thread=?)");
  has(read.SHARES_OF, "chat_shares USING INDEX sqlite_autoindex_chat_shares_1 (session=?)");
  has(read.OPENERS_OF, "o USING INDEX sqlite_autoindex_opened_chats_1 (child_station=? AND child=?)");
  has(read.OPENED_OF, "o USING INDEX opened_chats_by_key (parent_station=? AND parent=?)");
  has(read.PINS_OF, "pins USING INDEX sqlite_autoindex_pins_1 (viewer=? AND session=?)");
  has(read.TOLD_BLOCKED, "turns_by_end (session_key=? AND ended_at>? AND ended_at<?)");
  // The jobs running of some sessions: by an index (of those running, or of their sessions' jobs), never every job.
  has(read.RUNNING_OF, "SEARCH jobs USING INDEX");
  // Which workspace each session is in (each usage read's, for every session it names, and for every one there is):
  // from the index of them alone, not the sessions themselves.
  has(`${read.SEEN_OF} WHERE key IN (SELECT value FROM json_each(?))`, "SEARCH sessions USING COVERING INDEX sessions_ws (key=?)");
  assert.deepEqual((store.db.prepare(`EXPLAIN QUERY PLAN ${read.SEEN_OF}`).all() as { detail: string }[]).map((r) => r.detail), ["SCAN sessions USING COVERING INDEX sessions_ws"]);
});

test("a session's turns are counted as they are written and removed, and once from those before", () => {
  const path = join(tempdir(), "stillfail.db");
  let store = open(path);
  session(store, "a");
  session(store, "b");
  store.startTurn("t1", "a", "input");
  store.startTurn("t2", "a", "input");
  store.startTurn("t3", "b", "input");
  const turns = (s: Store) => {
    const r = read.makeStore(s.db, tempdir());
    return Object.fromEntries([...read.sessionStats(r, null)].map(([key, stats]) => [key, stats.turns]));
  };
  assert.deepEqual(turns(store), { a: 2, b: 1 });
  store.deleteSession("b");
  assert.deepEqual(turns(store), { a: 2 });
  assert.deepEqual(store.db.prepare("SELECT session, n FROM session_turns").all().map((r: any) => [r.session, r.n]), [["a", 2]]);
  // A database from before the count: a short old session answers from its turns without writing a summary.
  store.db.exec("DROP TRIGGER session_turns_add; DROP TRIGGER session_turns_drop; DROP TRIGGER session_turns_before_insert; DROP TRIGGER session_turns_move; DROP TABLE session_turns_guard; DROP TABLE session_turns;");
  store.startTurn("t4", "a", "input");
  store.close();
  store = open(path);
  assert.deepEqual(turns(store), { a: 3 });
});

// On a station (2026-11-03) a device read a session with its every turn (many of them, 25 s) to add up how long they ran.
test("a session's work is kept as its turns end and go, from when it began to be kept; one with turns ended before says none", async () => {
  const time = testClock();
  await time.adjust(Date.parse("2026-11-03T00:00:00Z"));
  const path = join(tempdir(), "stillfail.db");
  const opened = () => {
    const s = Store.open(path, null, time.clock);
    stores.push(s);
    return s;
  };
  let store = opened();
  session(store, "a");
  session(store, "b");
  const MIN = 60_000;
  const work = (s: Store) => Object.fromEntries([...read.sessionStats(read.makeStore(s.db, tempdir()), null)].map(([key, stats]) => [key, stats.workMs]));
  await time.adjust(MIN);
  store.startTurn("t1", "a", "input");
  await time.adjust(5 * MIN);
  store.endTurn("t1", "completed", null, null, null);
  store.startTurn("t2", "a", "input");
  await time.adjust(2 * MIN);
  store.startTurn("t3", "b", "input");
  assert.deepEqual(work(store), { a: 5 * MIN, b: 0 }, "a turn running is not counted yet");
  store.endTurn("t2", "completed", null, null, null);
  assert.deepEqual(work(store), { a: 7 * MIN, b: 0 });
  // Its detail without its turns, as a device asks it (`?turns=0`); all of them as one from before does.
  const { session: detail } = await import("../src/read/sessions.ts");
  const viewer: Viewer = { sub: "u", email: "a@x", name: "A", role: "owner", workspace: "ws", device: "d", home: true };
  const r = read.makeStore(store.db, tempdir());
  assert.deepEqual(detail(r, "a", viewer, "en", 0).turns, []);
  assert.deepEqual(detail(r, "a", viewer, "en").turns.map((t: any) => t.id), ["t1", "t2"]);
  assert.deepEqual([detail(r, "a", viewer, "en", 0).session.turns, detail(r, "a", viewer, "en", 0).session.workMs], [2, 7 * MIN]);
  // A database from before the work was kept: nothing added up from its turns as it opens, and a session with a turn
  // ended by then says none; one whose turns all end after, its work.
  store.db.exec("DROP TRIGGER session_work_add; DROP TRIGGER session_work_end; DROP TRIGGER session_work_drop; DROP TABLE session_work; DROP TABLE session_work_from;");
  await time.adjust(MIN);
  store.endTurn("t3", "completed", null, null, null);
  store.close();
  await time.adjust(MIN);
  store = opened();
  assert.equal((store.db.prepare("SELECT COUNT(*) AS n FROM session_work").get() as { n: number }).n, 0, "none read from the turns before");
  session(store, "c");
  store.startTurn("t4", "c", "input");
  await time.adjust(3 * MIN);
  store.endTurn("t4", "completed", null, null, null);
  store.startTurn("t5", "a", "input");
  await time.adjust(MIN);
  store.endTurn("t5", "completed", null, null, null);
  assert.deepEqual(work(store), { a: null, b: null, c: 3 * MIN });
  // Gone with the session's turns.
  store.deleteSession("c");
  assert.deepEqual(store.db.prepare("SELECT session, ms FROM session_work ORDER BY session").all().map((x: any) => [x.session, x.ms]), [["a", MIN]]);
});

test("usage: where a model's context was compacted is kept as calls are recorded, and made once from those before", () => {
  const path = join(tempdir(), "stillfail.db");
  let store = open(path);
  session(store, "a");
  const call = (id: string, at: number, sent: number, model = "m", subagent = false) =>
    [{ id, at, model, subagent, fast: false, input: sent, cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: subagent ? null : sent, window: null }, { turn: null, person: null, thread: null, profile: "cc" }] as const;
  store.recordUsage("/t.jsonl", { session: "a", offset: 1, model: "m" }, "claude", [
    call("c1", 1000, 120_000),
    call("s1", 1500, 5_000, "m", true), // a sub-agent's: not the session's context
    call("c2", 2000, 30_000), // compacted from 120 000
    call("c3", 3000, 40_000), // not compacted: up
    call("c4", 4000, 90_000, "other"), // another model: not compared
    call("c5", 5000, 20_000, "other"), // compacted from 90 000
    call("c6", 6000, 10_000, "other"), // under COMPACTED_FROM before: not
  ] as never);
  assert.deepEqual([...store.compactionPoints(0)].sort(), [["m", 120_000], ["other", 90_000]]);
  assert.deepEqual([...store.compactionPoints(4500)], [["other", 90_000]], "those since");
  // A database from before them: made from the calls it has, as it opens.
  store.db.exec("DROP TRIGGER usage_compactions_add; DROP TABLE usage_compactions;");
  store.close();
  store = open(path);
  assert.deepEqual([...store.compactionPoints(0)].sort(), [["m", 120_000], ["other", 90_000]]);
});

test("usage: a call is recorded once, its output grown; turns tell whom they were for", () => {
  const store = memory();
  session(store, "a");
  store.startTurnFor("t1", "a", "input", { profile: "cc", person: "me@x", thread: 3 });
  const call = { id: "c1", at: 1000, model: "m", subagent: false, fast: true, input: 1, cacheRead: 2, cacheWrite: 3, cacheWriteLong: 4, output: 5, calls: 1, context: 10, window: null };
  const of = { turn: "t1", person: "me@x", thread: 3, profile: "cc" };
  assert.equal(store.recordUsage("/t.jsonl", { session: "a", offset: 10, model: "m" }, "claude", [[call, of]]), 1);
  assert.equal(store.recordUsage("/t.jsonl", { session: "a", offset: 20, model: "m" }, "claude", [[{ ...call, output: 9 }, of]]), 0);
  assert.deepEqual(store.usageFiles().get("/t.jsonl"), { session: "a", offset: 20, model: "m" });
  const [g] = store.usageGroups(0, 2000, 0);
  assert.deepEqual([g!.calls, g!.output, g!.fast, g!.day], [1, 9, true, "1970-01-01"]);
  assert.equal(store.usageSince(), 1000);
  assert.deepEqual(store.usageTurns("a", 0, 2000).map((t) => [t.id, t.of.person, t.of.thread, t.of.profile]), [["t1", "me@x", 3, "cc"]]);
  assert.deepEqual(store.usageActiveSessions(0), ["a"]);
  const h = heard(store);
  store.usageChanged(["a"]);
  store.usageChanged(["a"], 1000);
  assert.deepEqual(h.changes, [{ type: "usage", sessions: ["a"] }, { type: "usage", sessions: ["a"], from: 1000 }]);
  h.stop();
});

test("usage: a missing old session total does not reconstruct calls and new writes are kept apart", () => {
  const path = join(tempdir(), "usage.db");
  const of = { turn: null, person: null, thread: null, profile: null };
  const call = (id: string, model: string | null, output: number) => ({ id, at: 1000, model, subagent: false, fast: false, input: 1, cacheRead: 2, cacheWrite: 3, cacheWriteLong: 4, output, calls: 1, context: 10, window: null });
  const first = open(path);
  session(first, "a");
  first.recordUsage("/a.jsonl", { session: "a", offset: 1, model: "m" }, "claude", [[call("c1", "m", 5), of], [call("c2", null, 1), of]]);
  first.close();
  // A database from before the totals: old calls remain untouched as it is opened.
  const before = new DatabaseSync(path);
  before.exec("DROP TRIGGER usage_totals_add; DROP TRIGGER usage_totals_grow; DROP TRIGGER usage_totals_drop; DROP TABLE usage_totals;");
  before.close();
  const store = open(path);
  // A call's output grown, a new call, and one recorded by a station process from before the totals.
  store.recordUsage("/a.jsonl", { session: "a", offset: 2, model: "m" }, "claude", [[call("c1", "m", 9), of], [call("c3", "m", 2), of]]);
  const older = new DatabaseSync(path);
  older.exec("INSERT INTO usage (id, at, session, runtime, model, input, cache_read, cache_write, cache_write_long, output) VALUES ('c4', 1000, 'a', 'claude', 'm', 1, 2, 3, 4, 7)");
  older.close();
  assert.deepEqual(store.usageOfSession("a"), [], "a partial session total is not shown as a lifetime total");
  assert.deepEqual(store.db.prepare("SELECT runtime, model, calls, input, cache_read, cache_write, cache_write_long, output FROM usage_totals WHERE session = 'a'")
    .all().map((r) => [r.runtime, r.model, r.calls, r.input, r.cache_read, r.cache_write, r.cache_write_long, r.output]),
  [["claude", "m", 2, 2, 4, 6, 8, 9]], "only new calls contribute to the incremental total");
  assert.deepEqual(store.usageOfSession("b"), []);
});

test("usage: the page's days are the calls added up from statistics, whatever the range and time zone", () => {
  const path = join(tempdir(), "usage.db");
  let store = open(path);
  session(store, "a");
  session(store, "b");
  // Calls over three days, a few in each quarter, for two sessions, threads, people and models (some none).
  let seed = 7;
  const next = (n: number) => ((seed = (seed * 48271) % 2147483647), seed % n);
  const day = 86_400_000;
  const calls = Array.from({ length: 600 }, (_, i) => {
    const of = { turn: null, person: [null, "p@x", "q@x"][next(3)]!, thread: [null, 1, 2][next(3)]!, profile: [null, "cc"][next(2)]! };
    const c = { id: `c${i}`, at: day + next(3 * day), model: [null, "m", "n"][next(3)]!, subagent: false, fast: next(2) === 0, input: next(100), cacheRead: next(100), cacheWrite: next(100), cacheWriteLong: next(100), output: next(100), calls: 1 + next(3), context: null, window: null };
    return [next(2) === 0 ? "a" : "b", c, of] as const;
  });
  const record = (only: readonly (typeof calls)[number][]) => {
    for (const [key, c, of] of only) store.recordUsage(`/${key}.jsonl`, { session: key, offset: 1, model: null }, "claude", [[c, of]] as never);
  };
  record(calls.slice(0, 400));
  store.close();
  // The current detail index remains usable if the obsolete quarter table is absent on an older database.
  const before = new DatabaseSync(path);
  before.exec("DROP TRIGGER usage_quarters_add; DROP TRIGGER usage_quarters_drop; DROP TRIGGER usage_quarters_grow; DROP TABLE usage_quarters;");
  before.close();
  store = open(path);
  record(calls.slice(400));
  // Outputs grown, and calls taken away.
  for (const [key, c, of] of calls.slice(0, 50)) store.recordUsage(`/${key}.jsonl`, { session: key, offset: 2, model: null }, "claude", [[{ ...c, output: c.output + 1000 }, of]] as never);
  store.db.exec("DELETE FROM usage WHERE id IN ('c3', 'c77', 'c450')");
  const one = `SELECT strftime('%Y-%m-%d', (at + ?3 * 60000) / 1000, 'unixepoch') AS day, session, thread, person, profile, runtime, model, fast,
      SUM(calls) AS calls, SUM(input) AS input, SUM(cache_read) AS cache_read, SUM(cache_write) AS cache_write, SUM(cache_write_long) AS cache_write_long, SUM(output) AS output
    FROM usage WHERE at >= ?1 AND at < ?2 GROUP BY day, session, thread, person, profile, runtime, model, fast`;
  const sorted = (rows: unknown[]) => rows.map((r) => JSON.stringify(r)).sort();
  const fromStats = (from: number, to: number, tz: number) => {
    const query = detailQuery(BigInt(from), BigInt(to), BigInt(tz), null);
    return query === null ? [] : store.db.prepare(query.sql).all(...query.args);
  };
  const some = fromStats(day + 5 * 900_000 + 7, day * 3 - 11, 480).length;
  assert.ok(some > 100, `${some} groups`);
  const q = 900_000;
  const ranges = [[0, 2 ** 62], [day + 5 * q, day * 3], [day + 5 * q + 7, day * 3 - 11], [day * 2 + 3, day * 2 + 400], [day * 2, day * 2 + q], [day * 3 + 1, day * 2], [-5, day + q + 1]];
  for (const [from, to] of ranges) {
    for (const tz of [0, 480, -300, 330, 345, 7, -1]) {
      const kept = fromStats(from!, to!, tz);
      const a = sorted(kept), b = sorted(store.db.prepare(one).all(from!, to!, tz));
      assert.deepEqual(a, b, `${from}..${to} at ${tz}: ${JSON.stringify([a.filter((x) => !b.includes(x)).slice(0, 3), b.filter((x) => !a.includes(x)).slice(0, 3)])}`);
    }
  }
  store.close();
});

test("usage: a row is the calls it says, and a database from before says each was one, with the context it sent", () => {
  const path = join(tempdir(), "usage.db");
  const of = { turn: null, person: null, thread: null, profile: "cc" };
  const call = (id: string, at: number, input: number, more: object = {}) =>
    [{ id, at, model: "m", subagent: false, fast: false, input, cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: input, window: null, ...more }, of] as const;
  let store = open(path);
  session(store, "a");
  store.recordUsage("/a.jsonl", { session: "a", offset: 1, model: "m" }, "claude", [call("c1", 1000, 120_000), call("s1", 1500, 7, { subagent: true, context: null })] as never);
  store.close();
  // As a station from before the columns kept it: its triggers too.
  const before = new DatabaseSync(path);
  const detailObjects = before.prepare("SELECT type, name FROM sqlite_master WHERE (name LIKE 'usage_detail_%' OR name = 'usage_detail') AND type IN ('trigger', 'table') ORDER BY type DESC").all() as { type: string; name: string }[];
  for (const object of detailObjects) before.exec(`DROP ${object.type.toUpperCase()} "${object.name}"`);
  before.exec(`DROP TRIGGER usage_totals_add; DROP TRIGGER usage_totals_drop; DROP TRIGGER usage_compactions_add;
    DROP TRIGGER usage_main_calls_usage_drop; DROP TRIGGER usage_main_calls_usage_change; DROP TRIGGER usage_main_calls_add; DROP TRIGGER usage_main_calls_drop;
    DROP TABLE usage_main_calls; DROP TABLE usage_compaction_events; DROP TABLE usage_compaction_backfill;
    DROP TRIGGER usage_quarters_add; DROP TRIGGER usage_quarters_drop; DROP TRIGGER usage_quarters_grow; DROP TABLE usage_quarters;
    DROP TRIGGER usage_minute_add; DROP TRIGGER usage_minute_drop; DROP TRIGGER usage_minute_grow;
    DROP TRIGGER usage_minute_session_add; DROP TRIGGER usage_minute_session_move; DROP TRIGGER usage_minute_session_drop;
    DROP TABLE usage_minute; DROP TABLE usage_day_quarters; DROP TABLE usage_minute_scope; DROP TABLE usage_minute_sessions; DROP TABLE usage_minute_seen; DROP TABLE usage_minute_all;
    DROP TRIGGER usage_history_add; DROP TRIGGER usage_history_grow; DROP TRIGGER usage_history_move; DROP TRIGGER usage_history_drop;
    DROP TABLE usage_history; DROP TABLE usage_history_total; DROP TABLE usage_history_since;
    ALTER TABLE usage DROP COLUMN calls; ALTER TABLE usage DROP COLUMN context; ALTER TABLE usage DROP COLUMN context_window;
    CREATE TRIGGER usage_totals_add AFTER INSERT ON usage BEGIN
      INSERT INTO usage_totals VALUES (NEW.session, NEW.runtime, COALESCE(NEW.model, ''), NEW.fast, 1, NEW.input, NEW.cache_read, NEW.cache_write, NEW.cache_write_long, NEW.output)
      ON CONFLICT (session, runtime, model, fast) DO UPDATE SET calls = calls + 1, input = input + excluded.input;
    END;
    CREATE TRIGGER usage_totals_drop AFTER DELETE ON usage BEGIN UPDATE usage_totals SET calls = calls - 1 WHERE session = OLD.session; END;
    CREATE TRIGGER usage_compactions_add AFTER INSERT ON usage BEGIN SELECT 1; END;`);
  before.close();
  store = open(path);
  // The old call remains intact; an unfinished context index does not claim it is complete.
  assert.deepEqual(store.db.prepare("SELECT context, context_window FROM usage WHERE id = 'c1'").get(),
    Object.assign(Object.create(null), { context: null, context_window: null }));
  assert.deepEqual(store.lastContexts("a", 5), []);
  // A turn told at once is its calls; the context it ended with is what it says, compacted from the one before.
  store.recordUsage("/a.jsonl", { session: "a", offset: 2, model: "m" }, "claude", [call("c2", 2000, 300_000, { calls: 3, context: 20_000, window: 200_000 })] as never);
  assert.deepEqual(store.usageOfSession("a").map((g) => [g.calls, g.input]), [[5, 420_007]]);
  assert.deepEqual(store.usageGroups(0, 3000, 0).map((g) => [g.calls, g.input]), [[3, 300_000]],
    "the new detail starts with the call recorded after the upgrade");
  assert.deepEqual(store.lastContexts("a", 1), []);
  assert.deepEqual([...store.compactionPoints(0)], []);
  store.close();
});

test("a session's usage as its summary says it: kept as told, a change told as the session's only once it rests", () => {
  const data = tempdir();
  const store = open(join(data, "stillfail.db"));
  session(store, "a");
  const h = heard(store);
  const usage = { modelCalls: 2, inputTokens: 30, cachedTokens: 20, outputTokens: 4, model: "m", contextTokens: 15, contextWindow: null };
  store.setRunning("a", true);
  h.changes.length = 0;
  store.setSessionUsage("a", usage);
  assert.deepEqual(h.changes, [], "at work: its stream tells it");
  assert.deepEqual(store.sessionUsage("a"), usage);
  store.setRunning("a", false);
  h.changes.length = 0;
  store.setSessionUsage("a", usage);
  assert.deepEqual(h.changes, [], "the same: nothing");
  store.setSessionUsage("a", { ...usage, modelCalls: 3, cost: 0.5 });
  assert.deepEqual(h.changes, [{ type: "session", key: "a" }], "at rest: told as the session's");
  store.setSessionUsage("a", { ...usage, modelCalls: 4 }, true);
  assert.deepEqual(h.changes.length, 1, "quiet: not told");
  store.setSessionUsage("gone", usage);
  assert.equal(store.sessionUsage("gone"), null, "no session: none kept");
  session(store, "b");
  assert.deepEqual(store.sessionKeys().sort(), ["a", "b"]);
  const reader = read.openStore(data);
  assert.deepEqual([...read.sessionUsages(reader, null)], [["a", { ...usage, modelCalls: 4 }]]);
  assert.deepEqual([...read.sessionUsages(reader, "b")], []);
  h.stop();
});

test("a session's starter: whom its chat was started for, before anyone wrote in it (a chat an agent opened)", () => {
  const store = memory();
  store.insertSession({ key: "opened", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w/opened", token: "opened", createdAt: 1, lastActiveAt: 1, createdBy: "Pat@Example.com" });
  const thread = store.openThread("ember", "CHAT", "3.1", null, "Pat@Example.com");
  store.joinThread(thread.id, "opened", "ember");
  say(store, thread.id, "3.2", "agent", "opened", "开始");
  assert.equal(store.starter("opened"), "pat@example.com", "started for Pat, though only its agent has written");
  // A session of before createdBy was kept: the first person who wrote in it.
  session(store, "older");
  const older = store.openThread("ember", "CHAT", "4.1", null, null);
  store.joinThread(older.id, "older", "ember");
  say(store, older.id, "4.2", "person", "Bob@x.com", "hi");
  assert.equal(store.starter("older"), "bob@x.com");
  session(store, "nobody");
  assert.equal(store.starter("nobody"), null);
});
