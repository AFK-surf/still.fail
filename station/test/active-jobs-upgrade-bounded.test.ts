import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { OTHER_JOBS_AT_INSTALL, installOtherActiveJobs } from "../src/store/active-jobs.ts";
import { ACTIVE_WATCHES_AT_INSTALL, installActiveWatches } from "../src/store/watch-jobs.ts";
import { ACTIVE_JOB_FIRST, ACTIVE_JOB_NEXT, activeJobUpgradeReady, activeJobUpgradeStep } from "../src/store/active-jobs-upgrade.ts";

for (const watched of [false, true]) test(`an old database prepares active ${watched ? "watches" : "jobs"} without an unbounded writer transaction`, () => {
  const largest: number[] = [];
  for (const n of [40, 400]) {
    const db = new DatabaseSync(":memory:");
    try {
      db.exec(`CREATE TABLE jobs(id TEXT PRIMARY KEY,session_key TEXT NOT NULL,state TEXT NOT NULL,watch INTEGER NOT NULL,token TEXT UNIQUE NOT NULL);
        CREATE INDEX jobs_state ON jobs(state);`);
      const add = db.prepare("INSERT INTO jobs VALUES(?, 'session', 'running', ?, ?)");
      for (let i = 0; i < n; i++) add.run(`job-${i}`, watched ? 1 : 0, `token-${i}`);
      if (!watched) installActiveWatches(db);
      let inWrite = false, inspected = 0, max = 0;
      db.function("upgrade_job_seen", (_id) => { if (inWrite) inspected++; return 1; });
      const observed = new Proxy(db, { get(target, property) {
        if (property === "exec") return (sql: string) => {
          if (sql === "BEGIN IMMEDIATE") { inWrite = true; inspected = 0; }
          const select = watched ? ACTIVE_WATCHES_AT_INSTALL : OTHER_JOBS_AT_INSTALL;
          const measured = sql.replace(select, `${select} AND upgrade_job_seen(id)`);
          const result = target.exec(measured);
          if (sql === "COMMIT" || sql === "ROLLBACK") { max = Math.max(max, inspected); inWrite = false; }
          return result;
        };
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      } });
      if (watched) installActiveWatches(observed);
      else installOtherActiveJobs(observed);
      largest.push(max);
    } finally { db.close(); }
  }
  assert.ok(largest.every((n) => n <= 64), `one writer transaction visited ${largest.join(" / ")} existing rows`);
});

test("each writer transaction visits a fixed number of old running jobs", () => {
  const largest: number[] = [];
  for (const n of [40, 400]) {
    const db = new DatabaseSync(":memory:");
    try {
      db.exec(`CREATE TABLE jobs(id TEXT PRIMARY KEY,session_key TEXT NOT NULL,state TEXT NOT NULL,watch INTEGER NOT NULL,token TEXT UNIQUE NOT NULL);
        CREATE INDEX jobs_state ON jobs(state);`);
      const add = db.prepare("INSERT INTO jobs VALUES(?, 'session', 'running', ?, ?)");
      for (let i = 0; i < n; i++) add.run(`job-${i}`, i % 2, `token-${i}`);
      let writing = false, visited = 0, max = 0;
      db.function("upgrade_row_seen", (_row) => { if (writing) visited++; return 1; });
      const observed = new Proxy(db, { get(target, property) {
        if (property === "exec") return (sql: string) => {
          if (sql === "BEGIN IMMEDIATE") { writing = true; visited = 0; }
          const measured = sql.replace(ACTIVE_WATCHES_AT_INSTALL, `${ACTIVE_WATCHES_AT_INSTALL} AND upgrade_row_seen(rowid)`)
            .replace(OTHER_JOBS_AT_INSTALL, `${OTHER_JOBS_AT_INSTALL} AND upgrade_row_seen(rowid)`);
          const result = target.exec(measured);
          if (sql === "COMMIT" || sql === "ROLLBACK") { max = Math.max(max, visited); writing = false; }
          return result;
        };
        if (property === "prepare") return (sql: string) => {
          if (sql === ACTIVE_JOB_FIRST || sql === ACTIVE_JOB_NEXT) {
            return target.prepare(sql.replace(" ORDER BY rowid LIMIT ?", " AND upgrade_row_seen(rowid) ORDER BY rowid LIMIT ?"));
          }
          if (sql === "SELECT 1 FROM jobs INDEXED BY jobs_state WHERE state = 'running' LIMIT 1 OFFSET 64") {
            return target.prepare(sql.replace(" LIMIT", " AND upgrade_row_seen(rowid) LIMIT"));
          }
          return target.prepare(sql);
        };
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      } });
      installActiveWatches(observed);
      installOtherActiveJobs(observed);
      while (!activeJobUpgradeReady(observed)) activeJobUpgradeStep(observed);
      largest.push(max);
    } finally { db.close(); }
  }
  // An immediate installation probes at most 65 rows and copies at most 64; subsequent batches read at most 64.
  assert.ok(largest.every((n) => n <= 129), `one writer transaction visited ${largest.join(" / ")} old rows`);
});
