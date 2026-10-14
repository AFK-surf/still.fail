import { FileSource } from "../src/file-source.ts";
import assert from "node:assert/strict";
import { test } from "node:test";
import { CoreFiles, FILE_PART, PageFiles } from "../src/hosts/file-port.ts";

function bridge(blob: Blob) {
  const reads: unknown[] = [];
  const page = new PageFiles((message) => core.receive(structuredClone(message)));
  const core = new CoreFiles((message) => { reads.push(message); page.receive(structuredClone(message)); });
  // The real renderer -> Node port must carry no DOM objects. JSON cloning the metadata also demonstrates that
  // the old bridge would lose a Blob, while the file descriptor survives intact.
  const message = page.prepare({ id: 1, call: "composer.add", params: { key: "ws/st:k", station: "ws/st", files: [{ id: "f1", name: "image.png", size: blob.size, blob }] } });
  const prepared = core.prepare(JSON.parse(JSON.stringify(message))) as any;
  const file = prepared.params.files[0].blob as FileSource;
  assert.ok(file instanceof FileSource);
  return { page, core, file, reads, prepared };
}

test("a pasted image crosses the desktop port byte for byte, only in requested parts", async () => {
  const bytes = new Uint8Array(FILE_PART + 13).map((_, i) => i % 251);
  const b = bridge(new Blob([bytes], { type: "image/png" }));
  assert.equal(b.reads.length, 0);
  assert.equal(b.file.type, "image/png");
  assert.equal(b.file.size, bytes.length);
  assert.deepEqual(new Uint8Array(await b.file.slice(0, FILE_PART).arrayBuffer()), bytes.slice(0, FILE_PART));
  assert.deepEqual(new Uint8Array(await b.file.slice(FILE_PART, FILE_PART * 2).arrayBuffer()), bytes.slice(FILE_PART));
  b.file.close();
  await assert.rejects(b.file.slice(0, 1).arrayBuffer(), /no longer available/);
  b.core.close();
});

test("empty files, read errors, and a page closing settle the pending read", async () => {
  const empty = bridge(new Blob([]));
  assert.equal((await empty.file.slice(0, FILE_PART).arrayBuffer()).byteLength, 0);
  empty.file.close();
  const failed = bridge(new Blob(["x"]));
  failed.page.close();
  await assert.rejects(failed.file.slice(0, 1).arrayBuffer(), /no longer available/);
  const gone = bridge(new Blob(["x"]));
  const pending = gone.file.slice(0, 1).arrayBuffer();
  gone.core.close();
  await assert.rejects(pending, /page closed/);
  await assert.rejects(gone.file.slice(0, 1).arrayBuffer(), /page closed/);
});

test("file reads are bounded even when a peer asks for a whole large file", async () => {
  const b = bridge(new Blob([new Uint8Array(FILE_PART + 1)]));
  await assert.rejects(b.file.slice(0, FILE_PART + 1).arrayBuffer(), /Invalid file part/);
  b.core.close(); b.page.close();
});
