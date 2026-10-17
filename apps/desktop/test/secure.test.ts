// What the desktop keeps sealed (src/secure.ts), with a stand-in for safeStorage and for Touch ID: the file's form, the
// prompt only for a value kept with `user`, and a file changed to skip the prompt not opening.
// Run: node --test apps/desktop/test/secure.test.ts
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";
import { SealedFiles, blobUser, fileName, openBlob, sealBlob, type Seal } from "../src/secure.ts";

const dir = mkdtempSync(join(tmpdir(), "stillfail-sealed-"));
after(() => rmSync(dir, { recursive: true, force: true }));

/// Not a cipher: the text reversed behind a mark, so a test sees it was sealed and opened by this.
const seal: Seal = {
  encryptString: (text) => Buffer.concat([Buffer.from("sealed:"), Buffer.from(text).reverse()]),
  decryptString: (sealed) => {
    if (!sealed.subarray(0, 7).equals(Buffer.from("sealed:"))) throw new Error("not sealed by this");
    return Buffer.from(sealed.subarray(7)).reverse().toString();
  },
};

test("a file: SFS1, the user byte, then the sealing of both", () => {
  const blob = sealBlob(seal, new Uint8Array([1, 2, 255]), true);
  assert.equal(blob.subarray(0, 5).toString("hex"), Buffer.from("SFS1\x01", "latin1").toString("hex"));
  assert.equal(seal.decryptString(blob.subarray(5)), "1:AQL_");
  assert.equal(blobUser(blob), true);
  assert.deepEqual(openBlob(seal, blob), { value: new Uint8Array([1, 2, 255]), user: true });
  assert.equal(blobUser(sealBlob(seal, new Uint8Array(0), false)), false);
  assert.equal(blobUser(Buffer.from("SFS2\x00")), null);
  // The outer byte changed so as not to be asked: it does not open.
  const changed = Buffer.from(blob);
  changed[4] = 0;
  assert.throws(() => openBlob(seal, changed), /was changed/);
  assert.equal(fileName("lock-signer"), "lock-signer");
  assert.equal(fileName("../a b"), "%2E%2E%2Fa%20b");
});

test("kept, read back, asked for only when kept with user, and gone", async () => {
  const asked: string[] = [];
  let say: "yes" | "no" = "yes";
  const files = new SealedFiles(join(dir, "a"), seal, async (reason) => {
    asked.push(reason);
    if (say === "no") throw new Error("user_cancelled");
  });
  assert.equal(await files.get("lock-signer", false, ""), null);
  await files.set("lock-signer", new Uint8Array([7, 7]), false);
  await files.set("vault-box", new Uint8Array([9]), true);
  assert.deepEqual(readdirSync(join(dir, "a")).sort(), ["lock-signer", "vault-box"]);
  if (process.platform !== "win32") assert.equal(statSync(join(dir, "a", "vault-box")).mode & 0o777, 0o600);
  assert.ok(!readFileSync(join(dir, "a", "vault-box")).includes(Buffer.from("CQ")), "the value is not in the file as it is");

  assert.deepEqual(await files.get("lock-signer", false, ""), new Uint8Array([7, 7]));
  assert.deepEqual(asked, [], "a value kept without user is read without asking");
  assert.deepEqual(await files.get("vault-box", true, "approve a request"), new Uint8Array([9]));
  assert.deepEqual(asked, ["approve a request"]);
  say = "no";
  await assert.rejects(files.get("vault-box", true, "open an item"), /^Error: user_cancelled$/);
  say = "yes";
  // Asked with the other `user`: neither way reads it.
  await assert.rejects(files.get("vault-box", false, ""), /kept with user: true/);
  await assert.rejects(files.get("lock-signer", true, "x"), /kept with user: false/);

  // The outer byte changed on the disk: no prompt is skipped, nothing opens.
  const path = join(dir, "a", "vault-box");
  const blob = readFileSync(path);
  blob[4] = 0;
  writeFileSync(path, blob);
  await assert.rejects(files.get("vault-box", false, ""), /was changed/);

  await files.delete("vault-box");
  await files.delete("vault-box");
  assert.equal(await files.get("vault-box", true, "x"), null);

  // Asked by itself, with no value (turning the workspace lock off).
  await files.ask("turn off security mode");
  assert.deepEqual(asked.at(-1), "turn off security mode");
  say = "no";
  await assert.rejects(files.ask("turn off security mode"), /^Error: user_cancelled$/);
});

test("where nothing can ask, a value kept with user is read as the login allows", async () => {
  const files = new SealedFiles(join(dir, "b"), seal, null);
  await files.set("vault-box", new Uint8Array([1]), true);
  assert.deepEqual(await files.get("vault-box", true, "x"), new Uint8Array([1]));
  await files.ask("x");
});
