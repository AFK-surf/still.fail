// What stations of 0.1.9133 to 0.1.9168 left of the memory, mended by those after (src/share/memory.ts `#mend`): the
// state each wrote to its disk made as they wrote it, the stations started again on this one.
import assert from "node:assert/strict";
import { chmodSync, existsSync, mkdirSync, renameSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import { asideSkill } from "../src/share/memory.ts";
import { keepRecord, memoryWorld, readAt, writeAt } from "./memory-world.ts";

const CCVM = "a".repeat(64);
const MINI1 = "c".repeat(64);
const MBA = "d".repeat(64);
const STATIONS = [{ id: CCVM, name: "ccvm" }, { id: MINI1, name: "Mini1" }, { id: MBA, name: "MBA" }];
const PROJECT = `---\nname: stillfail\ndescription: 项目记忆：still.fail\n---\n${"- 项目的事。\n".repeat(50)}`;
const MINIS = "---\nname: stillfail\ndescription: 发布机\n---\n本机的发布配置在同目录 host。\n";

/// Three stations brought level as these do, Mini1's own stillfail kept apart as stillfail-Mini1, its host beside it.
async function levelled() {
  const w = memoryWorld(STATIONS);
  writeAt(w.at(CCVM), "skills/stillfail/SKILL.md", PROJECT);
  writeAt(w.at(MINI1), "skills/stillfail/SKILL.md", MINIS);
  writeAt(w.at(MINI1), "skills/stillfail/host", "mini\n");
  chmodSync(join(w.at(MINI1).home, "skills/stillfail/host"), 0o600);
  await w.level(MBA, MINI1, CCVM, MBA, MINI1, CCVM);
  return w;
}

test("a skill kept apart twice by 0.1.9133 (stillfail-MBA beside stillfail-Mini1) comes to one on every station", async () => {
  const w = await levelled();
  try {
    // What 0.1.9133 made on MBA, which took Mini1's first, and every station then took: the same skill under MBA's name,
    // its records Mini1's.
    const twice = asideSkill(Buffer.from(MINIS), "stillfail-MBA", "MBA").toString("utf8");
    for (const s of STATIONS) {
      await w.restart(s.id, (st) => {
        writeAt(st, "skills/stillfail-MBA/SKILL.md", twice);
        keepRecord(st, "skills/stillfail-MBA/SKILL.md", twice, { at: 1, by: MINI1, origin: true });
      });
    }
    await w.level(CCVM, MINI1, MBA, CCVM, MINI1, MBA);
    for (const s of STATIONS) {
      assert.equal(existsSync(join(w.at(s.id).home, "skills/stillfail-MBA/SKILL.md")), false, `${s.name} still has stillfail-MBA`);
      assert.match(readAt(w.at(s.id), "skills/stillfail-Mini1/SKILL.md")!, /本机的发布配置/, `${s.name} lost stillfail-Mini1`);
      assert.match(readAt(w.at(s.id), "skills/stillfail/SKILL.md")!, /项目记忆/);
    }
    // And it does not come back from a station that was off then.
    await w.level(MBA, CCVM, MINI1);
    for (const s of STATIONS) assert.equal(existsSync(join(w.at(s.id).home, "skills/stillfail-MBA/SKILL.md")), false);
  } finally {
    await w.done();
  }
});

test("a file only its owner reads that 0.1.9162 moved into the skill kept apart is put back where it was", async () => {
  const w = await levelled();
  try {
    await w.restart(MINI1, (st) => {
      const from = join(st.home, "skills/stillfail/host");
      const to = join(st.home, "skills/stillfail-Mini1/host");
      mkdirSync(join(to, ".."), { recursive: true });
      if (existsSync(to)) renameSync(to, `${to}.x`);
      renameSync(from, to);
    });
    await w.level(MINI1);
    assert.equal(readAt(w.at(MINI1), "skills/stillfail/host"), "mini\n");
    assert.equal(readAt(w.at(MINI1), "skills/stillfail-Mini1/host"), "mini\n");
    assert.equal(readAt(w.at(CCVM), "skills/stillfail/host"), null);
  } finally {
    await w.done();
  }
});
