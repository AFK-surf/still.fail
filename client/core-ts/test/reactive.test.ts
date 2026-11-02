import { test } from "node:test";

test("dependency_switching_batches_errors_and_releases_follow_the_oracle", async () => {
  await import("../bench/reactive-property-probe.ts");
});
