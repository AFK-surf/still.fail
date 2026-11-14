// A program that says its last line and ends at once is told in that order (read/mb-reader.ts MbProcess): its line, then
// its end. Told on the child's `exit`, its end could come before the line was read, and the restore that waited for it
// took the answer for none ("the restore ended saying nothing (0)", once in a full run on a loaded machine).
import assert from "node:assert/strict";
import { test } from "node:test";
import { MbProcess } from "../src/read/mb-reader.ts";

test("a program's last line is told before its end", { skip: process.platform === "win32" ? "no /bin/sh" : false }, async () => {
  // (many at once, a line of 64 KB each: the end's notice and the line's bytes race on a busy machine)
  const line = JSON.stringify({ ready: "x".repeat(65536) });
  const runs = await Promise.all(Array.from({ length: 64 }, () => new Promise<string[]>((resolve) => {
    const said: string[] = [];
    const p = new MbProcess("/bin/sh", ["-c", `printf '%s\\n' '${line}'`]);
    p.on("message", () => said.push("line"));
    p.on("exit", () => { said.push("end"); resolve(said); });
  })));
  for (const said of runs) assert.deepEqual(said, ["line", "end"]);
});
