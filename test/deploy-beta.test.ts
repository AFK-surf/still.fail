import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

// Exercise the deployment entry point with fake credentials and no network or deployment commands.
const program = String.raw`
import importlib.util, io, json, os, subprocess, sys, urllib.error
from pathlib import Path

scenario = json.loads(sys.argv[1])
os.environ.clear()
os.environ["STILLFAIL_DEPLOY_DIR"] = str(Path.cwd() / "unused-deploy-test")
if "override" in scenario:
    os.environ["STILLFAIL_BETA"] = scenario["override"]
spec = importlib.util.spec_from_file_location("deploy", "cloud/deploy.py")
deploy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(deploy)
deploy.read_template = lambda *args: {"vars": {
    "PUBLIC_ORIGIN": "https://app.example.test",
    "BETA_ORIGIN": "https://beta.example.test",
    "ADMIN_ORIGIN": "https://admin.example.test",
}}
deploy.account_id = lambda: "test-account"

def wrangler(*args, **kwargs):
    assert args == ("auth", "token", "--json"), "deployment must not start after a failed lookup"
    assert "override" not in scenario, "an explicit override must not read credentials"
    if scenario.get("error") == "auth":
        raise subprocess.CalledProcessError(1, ["wrangler", "auth", "token"])
    return json.dumps({"type": "api_token", "token": "test-only"})

def urlopen(*args, **kwargs):
    assert "override" not in scenario, "an explicit override must not query the zone"
    if scenario.get("error") == "network":
        raise urllib.error.URLError("SSL: UNEXPECTED_EOF_WHILE_READING")
    return io.BytesIO(scenario.get("body", "").encode())

deploy.wrangler = wrangler
deploy.urllib.request.urlopen = urlopen
if scenario.get("probe"):
    print(json.dumps(deploy.beta_ready("test-account")))
else:
    sys.argv = ["deploy.py", "web-beta", "--skip-build"]
    deploy.main()
`;

function run(scenario: Record<string, unknown>) {
  const result = spawnSync("python3", ["-c", program, JSON.stringify(scenario)], {
    cwd: fileURLToPath(new URL("..", import.meta.url)),
    encoding: "utf8",
  });
  assert.ifError(result.error);
  return result;
}

test("a failed zone lookup stops deployment instead of silently skipping the test channel", () => {
  for (const scenario of [
    { error: "network" },
    { error: "auth" },
    { body: "not JSON" },
    { body: JSON.stringify({ success: false, errors: [{ code: 10000 }], result: [] }) },
    { body: JSON.stringify({ success: true, result: null }) },
  ]) {
    const result = run(scenario);
    assert.notEqual(result.status, 0, JSON.stringify(scenario));
    assert.match(result.stderr, /could not check Cloudflare zone example.test; deployment stopped/);
    assert.doesNotMatch(result.stdout, /taking it for missing|skipping web-beta|deployed/);
  }
});

test("successful zone lookups and explicit overrides keep their deployment policy", () => {
  for (const [zones, expected] of [
    [[{ status: "active" }], true],
    [[{ status: "pending" }], false],
    [[], false],
  ] as const) {
    const result = run({ probe: true, body: JSON.stringify({ success: true, result: zones }) });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(JSON.parse(result.stdout), expected);
  }
  for (const override of ["on", "off"]) {
    const result = run({ probe: true, override });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(JSON.parse(result.stdout), override === "on");
  }
});
