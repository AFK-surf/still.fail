import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

test("the monoid API keeps the repository that signs release notifications", () => {
  const program = String.raw`
import importlib.util, json

spec = importlib.util.spec_from_file_location("deploy", "cloud/deploy.py")
deploy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(deploy)
original = deploy.read_template()
monoid = deploy.for_cloud(original, "monoid")
print(json.dumps({"original": original["vars"], "monoid": monoid["vars"]}))
`;
  const result = spawnSync("python3", ["-c", program], {
    cwd: fileURLToPath(new URL("..", import.meta.url)),
    env: { ...process.env, STILLFAIL_CLOUD: "" },
    encoding: "utf8",
  });
  assert.ifError(result.error);
  assert.equal(result.status, 0, result.stderr);
  const { original, monoid } = JSON.parse(result.stdout);
  assert.equal(monoid.PUBLIC_ORIGIN, "https://app.monoid.build");
  assert.equal(monoid.BETA_ORIGIN, "https://app.monoid.zone");
  assert.equal(monoid.STATUS_REPO_ID, original.STATUS_REPO_ID);
});
