// A database in a file given to the vault as one that has no file: the vault's use index then starts no reader of its
// own (its MoonBit program, or the worker) and does that work on this connection, step by step, as for one in memory.
// For tests that open the file on a second connection, where the file is what is tested and the reader is not: a
// reader's process beside them writes when it will, and their own writes found the database locked now and then
// (vault-save.test.ts: 2 of 36 runs with six going at once, and each run on Linux; 2026-11-10). Tests of the reader
// itself (vault-uses-index, mb-vault-uses) give the database as it is and wait for its answers.
import type { DatabaseSync } from "node:sqlite";

export function withoutUseReader(db: DatabaseSync): DatabaseSync {
  return new Proxy(db, { get(target, key) {
    if (key === "location") return () => null;
    const value = Reflect.get(target, key, target);
    return typeof value === "function" ? value.bind(target) : value;
  } });
}
