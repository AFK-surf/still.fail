import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

for (const scenario of ["public", "api", "api-anonymous", "api-redirect", "invalid-token", "broken-body", "wrong-digest", "json-body", "missing", "public-404", "rate-limited"] as const) test(`a native release download handles ${scenario}`, (t) => {
  const root = fileURLToPath(new URL("..", import.meta.url));
  const dir = mkdtempSync(join(tmpdir(), "native-release-fallback-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const bin = join(dir, "bin"), cache = join(dir, "cache"), files = join(dir, "files"), archive = join(dir, "asset.tar.gz");
  mkdirSync(bin); mkdirSync(files);
  // A stable key and a real tarball: the command must unpack the requested files into its normal cache.
  writeFileSync(join(bin, "git"), "#!/bin/sh\nexit 0\n");
  chmodSync(join(bin, "git"), 0o755);
  writeFileSync(join(files, "libstillfail_shell.a"), "archive");
  writeFileSync(join(files, "libstillfail_shell.libs"), "libs");
  const packed = spawnSync("tar", ["-czf", archive, "-C", files, "."], { encoding: "utf8" });
  assert.equal(packed.status, 0, packed.stderr);
  const preload = join(dir, "preload.mjs");
  writeFileSync(preload, `
    import { readFileSync } from 'node:fs';
    import { createHash } from 'node:crypto';
    let name;
    const scenario = ${JSON.stringify(scenario)};
    globalThis.fetch = async (at, init = {}) => {
      const url = new URL(at);
      if (url.hostname === 'app.still.fail') return new Response('', { status: 404 });
      if (url.hostname === 'github.com') {
        name = url.pathname.split('/').at(-1);
        if (scenario === 'public') return new Response(readFileSync(process.env.NATIVE_TEST_ARCHIVE));
        if (scenario === 'public-404') return new Response('', { status: 404 });
        if (scenario === 'broken-body') return new Response(new ReadableStream({ start(c) { c.error(new Error('cut short')); } }));
        return new Response('', { status: 504 });
      }
      if (url.hostname === 'api.github.com' && url.pathname.endsWith('/releases/tags/native-artifacts')) {
        const auth = new Headers(init.headers).get('authorization');
        if (scenario === 'rate-limited') {
          if (auth !== null && auth !== 'Bearer native-test-token') throw new Error('wrong metadata authorization');
          return new Response('', { status: 403 });
        }
        if (scenario === 'invalid-token' && auth) return new Response('', { status: 401 });
        if ((scenario === 'api-anonymous' || scenario === 'invalid-token') ? auth !== null : auth !== 'Bearer native-test-token') throw new Error('wrong metadata authorization');
        if (scenario === 'missing') return Response.json({ assets: [] });
        const digest = scenario === 'wrong-digest' ? '0'.repeat(64) : createHash('sha256').update(readFileSync(process.env.NATIVE_TEST_ARCHIVE)).digest('hex');
        return Response.json({ assets: [{ id: 123, name, digest: 'sha256:' + digest }] });
      }
      if (url.hostname === 'api.github.com' && url.pathname.endsWith('/releases/assets/123') &&
          new Headers(init.headers).get('accept') === 'application/octet-stream') {
        const auth = new Headers(init.headers).get('authorization');
        if (scenario === 'invalid-token' && auth) return new Response('', { status: 401 });
        if ((scenario === 'api-anonymous' || scenario === 'invalid-token') ? auth !== null : auth !== 'Bearer native-test-token') throw new Error('wrong asset authorization');
        if (scenario === 'api-redirect') {
          if (init.redirect !== 'manual') throw new Error('asset redirect did not keep authorization at the API');
          return new Response(null, { status: 302, headers: { location: 'https://assets.example.test/asset' } });
        }
        if (scenario === 'json-body') return Response.json({ id: 123, name });
        return new Response(readFileSync(process.env.NATIVE_TEST_ARCHIVE), { headers: { 'content-type': 'application/octet-stream' } });
      }
      if (url.hostname === 'assets.example.test' && scenario === 'api-redirect') {
        if (new Headers(init.headers).has('authorization')) throw new Error('authorization went to the asset host');
        return new Response(readFileSync(process.env.NATIVE_TEST_ARCHIVE));
      }
      throw new Error('unexpected native request');
    };
  `);
  const run = spawnSync(process.execPath, ["--import", preload, join(root, "scripts/native.ts"), "fetch", "shell-apple", "darwin-arm64"], {
    cwd: root, encoding: "utf8", env: { ...process.env, PATH: `${bin}:${process.env.PATH}`, NATIVE_TEST_ARCHIVE: archive,
      STILLFAIL_NATIVE_CACHE: cache, STILLFAIL_NATIVE: "", STILLFAIL_NATIVE_INBOX: "", STILLFAIL_DIRECT_DNS: "",
      STILLFAIL_NATIVE_STORE: "https://app.still.fail/releases/natives", STILLFAIL_NATIVE_REPO: "AFK-surf/monoid",
      STILLFAIL_NATIVE_RELEASE: "native-artifacts", STILLFAIL_NATIVE_CACHE_MAX_BYTES: "0",
      GH_TOKEN: scenario === "api-anonymous" ? "" : "native-test-token", GITHUB_TOKEN: "" },
  });
  if (["public", "api", "api-anonymous", "api-redirect", "invalid-token", "broken-body"].includes(scenario)) {
    assert.equal(run.status, 0, run.stderr);
    const cached = run.stdout.trim();
    assert.equal(readFileSync(join(cached, "libstillfail_shell.a"), "utf8"), "archive");
    assert.equal(existsSync(join(cached, "manifest.json")), true);
  } else {
    assert.notEqual(run.status, 0, "a missing or corrupt artifact cannot become a cache entry");
    if (scenario === "wrong-digest") assert.match(run.stderr, /different digest/);
    if (scenario === "json-body") assert.match(run.stderr, /did not give a gzip archive/);
    if (scenario === "rate-limited") assert.match(run.stderr, /release API answered 403/);
  }
});
