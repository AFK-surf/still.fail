// What the station says names the product of the cloud it is enrolled in (client/i18n/brand.ts): monoid's says monoid.
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { CloudState } from "../src/cloud/state.ts";
import { tr } from "../src/ops/i18n.ts";

test("a station enrolled in monoid's cloud says monoid", () => {
  const key = "station.cli.held";
  const data = mkdtempSync(join(tmpdir(), "brand-"));
  mkdirSync(join(data, "mesh"), { recursive: true });
  const state = new CloudState(data, false);
  try {
    assert.match(tr("zh", key), /still\.fail/);
    writeFileSync(join(data, "mesh", "cloud.json"), JSON.stringify({ origin: "https://app.monoid.build", station: "s", workspace: "w", name: "n", key: "k" }));
    state.reload();
    const said = tr("zh", key);
    assert.match(said, /monoid/);
    assert.doesNotMatch(said, /(?<![\w./@-])still\.fail/);
  } finally {
    state.close();
  }
});
