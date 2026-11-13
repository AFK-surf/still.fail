// What a process has used so far on Linux, read from /proc (resources/linux.ts): the files' text as the kernel writes
// it, and on Linux this process's own.
import assert from "node:assert/strict";
import { test } from "node:test";
import { diskOfIo, footprintOfStatus, linuxUsage, ticksOfStat } from "../src/resources/linux.ts";

// A name with a space and a parenthesis of its own; utime 1234, stime 56.
const STAT = "4242 (node (x) y) S 1 4242 4242 0 -1 4194304 1000 0 0 0 1234 56 0 0 20 0 11 0 100 1000000 5000 18446744073709551615";
const STATUS = "Name:\tnode\nVmRSS:\t  204800 kB\nRssAnon:\t  102400 kB\nRssFile:\t  100000 kB\nRssShmem:\t    2400 kB\nVmSwap:\t    1024 kB\n";
const IO = "rchar: 999\nwchar: 888\nsyscr: 1\nsyscw: 2\nread_bytes: 4096\nwrite_bytes: 8192\ncancelled_write_bytes: 0\n";

test("the CPU ticks are counted after the name's last parenthesis", () => {
  assert.equal(ticksOfStat(STAT), 1290);
  assert.equal(ticksOfStat("garbage"), null);
});

test("the footprint is its own memory, resident or swapped, not the files it maps", () => {
  assert.equal(footprintOfStatus(STATUS), (102400 + 2400 + 1024) * 1024);
  // A kernel before 4.5 does not split it: the resident set.
  assert.equal(footprintOfStatus("VmRSS:\t 10 kB\n"), 10 * 1024);
  assert.equal(footprintOfStatus("Name:\tzombie\n"), null);
});

test("the disk's bytes are what reached the disk, not the page cache's", () => {
  assert.deepEqual(diskOfIo(IO), { diskRead: 4096, diskWritten: 8192 });
  assert.equal(diskOfIo("rchar: 1\n"), null);
});

test("a process gone is none; one whose io is not readable has no disk", async () => {
  const files: Record<string, string> = { "/proc/1/stat": STAT, "/proc/1/status": STATUS, "/proc/1/io": IO, "/proc/2/stat": STAT, "/proc/2/status": STATUS };
  const read = async (path: string) => {
    const text = files[path];
    if (text === undefined) throw new Error("ENOENT");
    return text;
  };
  const [one, two, gone] = await linuxUsage([1, 2, 3], read);
  assert.deepEqual(one, { cpuNs: 1290 * 1e7, footprint: (102400 + 2400 + 1024) * 1024, diskRead: 4096, diskWritten: 8192 });
  assert.deepEqual(two, { cpuNs: 1290 * 1e7, footprint: (102400 + 2400 + 1024) * 1024 });
  assert.equal(gone, null);
});

test("on Linux, this process's own is read", { skip: process.platform !== "linux" && "reads /proc, which only Linux has" }, async () => {
  const [self] = await linuxUsage([process.pid]);
  assert.ok(self);
  assert.ok(self.cpuNs > 0);
  assert.ok(self.footprint > 1 << 20);
  assert.equal(typeof self.diskRead, "number");
});
