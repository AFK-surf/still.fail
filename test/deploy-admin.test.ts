import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

test("an API deployment reads its administrator from private configuration", () => {
  const program = String.raw`
import importlib.util, json, os, sys, tempfile
from pathlib import Path

with tempfile.TemporaryDirectory() as directory:
    os.environ.pop("STILLFAIL_ADMIN_EMAIL", None)
    os.environ.pop("EMBER_ADMIN_EMAIL", None)
    os.environ["STILLFAIL_DEPLOY_DIR"] = directory
    spec = importlib.util.spec_from_file_location("deploy", "cloud/deploy.py")
    deploy = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(deploy)
    try:
        deploy.admin_email(False)
        raise AssertionError("a real deployment accepted missing configuration")
    except SystemExit:
        pass
    assert deploy.admin_email(True) == "admin@example.test"
    Path(directory, "admin-email").write_text("file@example.test\n")
    assert deploy.admin_email(False) == "file@example.test"
    os.environ["STILLFAIL_ADMIN_EMAIL"] = "env@example.test"
    assert deploy.admin_email(False) == "env@example.test"
    assert deploy.admin_email(True) == "admin@example.test"
    deploy.ROOT = Path(directory)
    deploy.read_template = lambda *args: {"name": "api-test", "vars": {"PUBLIC_ORIGIN": "https://example.test"}}
    deploy.account_id = lambda: "account-test"
    deploy.beta_ready = lambda account: True
    google = Path(directory, "google.json")
    google.write_text(json.dumps({"web": {"client_id": "test", "client_secret": "test", "redirect_uris": []}}))
    def wrangler(*args, **kwargs):
        config = json.loads(Path(args[args.index("--config") + 1]).read_text())
        assert config["vars"]["ADMIN_EMAIL"] == "env@example.test"
        raise RuntimeError("stopped before deployment")
    deploy.wrangler = wrangler
    sys.argv = ["deploy.py", "api", "--skip-build", "--google", str(google)]
    try:
        deploy.main()
        raise AssertionError("deployment should have been intercepted")
    except RuntimeError as error:
        assert str(error) == "stopped before deployment"
`;
  const result = spawnSync("python3", ["-c", program], {
    cwd: fileURLToPath(new URL("..", import.meta.url)), encoding: "utf8",
  });
  assert.ifError(result.error);
  assert.equal(result.status, 0, result.stderr);
});
