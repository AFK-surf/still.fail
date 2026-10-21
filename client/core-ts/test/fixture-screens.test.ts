// The screens both of still.fail's Android apps are drawn from to be compared (client/fixtures/screens: Android's
// ScreensRefTest, the mbui app's MBUI_FIXTURE=json): what each topic says is what this core would say of it, its shape
// as present.ts conforms it, so neither app is shown what no core sends.
import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import { conformTopic } from "../src/present.ts";

const dir = join(import.meta.dirname, "../../fixtures/screens");

for (const file of readdirSync(dir).filter((f) => f.endsWith(".json") && f !== "allowed.json")) {
  test(`screens/${file}: every topic's value in the core's shape`, () => {
    const screen = JSON.parse(readFileSync(join(dir, file), "utf8"));
    const wrong = [];
    for (const { topic, value } of screen.topics) {
      const shaped = conformTopic(topic, value);
      if ("error" in shaped) wrong.push(`${JSON.stringify(topic)}: ${shaped.error}`);
    }
    assert.deepEqual(wrong, []);
  });
}
