import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { Store } from "../src/store/store.ts";

test("an incomplete detail index keeps the existing summary writers", () => {
  const store = Store.open(":memory:");
  try {
    store.db.exec("UPDATE usage_detail_all SET done = 0 WHERE id = 1");
    assert.equal(store.retireDuplicateUsage(), false);
    assert.ok(store.db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'trigger' AND name = 'usage_minute_add'").get());
  } finally { store.close(); }
});

test("incomplete daily quarters keep the existing summary writers", () => {
  const store = Store.open(":memory:");
  try {
    store.db.exec("UPDATE usage_minute_all SET done = 0 WHERE id = 1");
    assert.equal(store.retireDuplicateUsage(), false);
    assert.ok(store.db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'trigger' AND name = 'usage_minute_add'").get());
  } finally { store.close(); }
});

test("reopening does not restore retired summary writers", () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-unified-"));
  const path = join(dir, "stillfail.db");
  let store = Store.open(path);
  try {
    assert.equal(store.retireDuplicateUsage(), true);
    store.close();
    store = Store.open(path);
    const triggers = store.db.prepare("SELECT name FROM sqlite_master WHERE type = 'trigger' AND name IN ('usage_quarters_add','usage_quarters_drop','usage_minute_add','usage_minute_drop')").all();
    assert.deepEqual(triggers, []);
    assert.equal(store.retireDuplicateUsage(), true);
  } finally { store.close(); rmSync(dir, { recursive: true, force: true }); }
});
