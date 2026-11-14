// Names the frames of the Android app's native crashes (a tombstone as text: PostHog's `$exception`, logcat's DEBUG
// lines): each `#NN pc <hex> … libmbui.so` frame gets `<function>+0x<offset>` appended, from the release's symbols,
// what scripts/release.sh keeps for 30 days as symbols/android/<the APK's name without .apk>.syms.xz (`<address>
// <name>` a line, sorted by address: llvm-nm of the library as linked, mbui's scripts/android.sh MBUI_SYMBOLS). A
// frame's pc is its address in the library's own address space, the space llvm-nm prints, so the release's symbols
// need no shift. Other lines as they are. A function's size is not kept: a pc past the last one's end is named by it.
//   node scripts/crash-symbols.ts <symbols (.syms.xz or plain)> [tombstone file]
//   node scripts/crash-symbols.ts --fetch <apk name, e.g. stillfail-beta-8300> [tombstone file]
// The tombstone from stdin when no file is named. --fetch gets the symbols from the releases bucket first, as
// scripts/release.sh's `r2 get` does (wrangler in cloud/: a machine signed in to Cloudflare, `pnpm exec wrangler login`).
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

export interface Symbols { addresses: bigint[]; names: string[] }

/** A symbols file's text: `<hex address> <name>` lines (others passed over), sorted by address as they are kept. */
export function parseSymbols(text: string): Symbols {
  const rows: [bigint, string][] = [];
  for (const line of text.split("\n")) {
    const m = /^([0-9a-fA-F]+) (\S+)/.exec(line);
    if (m) rows.push([BigInt(`0x${m[1]}`), m[2]!]);
  }
  rows.sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0));
  return { addresses: rows.map((r) => r[0]), names: rows.map((r) => r[1]) };
}

/** The function `pc` is in (the last one starting at or before it) and how far into it; null before the first. */
export function lookup(symbols: Symbols, pc: bigint): { name: string; offset: bigint } | null {
  let lo = 0, hi = symbols.addresses.length - 1, at = -1;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1;
    if (symbols.addresses[mid]! <= pc) { at = mid; lo = mid + 1; } else hi = mid - 1;
  }
  return at < 0 ? null : { name: symbols.names[at]!, offset: pc - symbols.addresses[at]! };
}

/** The tombstone's text with each libmbui.so frame named. */
export function symbolize(tombstone: string, symbols: Symbols): string {
  return tombstone.split("\n").map((line) => {
    const m = /#\d+\s+pc\s+([0-9a-fA-F]+)\s.*libmbui\.so/.exec(line);
    const found = m ? lookup(symbols, BigInt(`0x${m[1]}`)) : null;
    return found ? `${line.replace(/\s+$/, "")} ${found.name}+0x${found.offset.toString(16)}` : line;
  }).join("\n");
}

/** A symbols file's text: xz's (its magic bytes) through `xz -dc`, else as it is. */
export function readSymbols(file: string): string {
  const bytes = readFileSync(file);
  const xz = bytes.subarray(0, 6).equals(Buffer.from([0xfd, 0x37, 0x7a, 0x58, 0x5a, 0x00]));
  return xz ? execFileSync("xz", ["-dc", file], { encoding: "utf8", maxBuffer: 1 << 30 }) : bytes.toString("utf8");
}

if (import.meta.main) {
  const args = process.argv.slice(2);
  const usage = "usage: node scripts/crash-symbols.ts <symbols file> | --fetch <apk name> [tombstone file]";
  let symbolsFile: string, tmp: string | null = null;
  if (args[0] === "--fetch") {
    if (!args[1]) throw new Error(usage);
    const name = args[1].replace(/^.*\//, "").replace(/\.apk$/, "");
    tmp = mkdtempSync(join(tmpdir(), "crash-symbols-"));
    symbolsFile = join(tmp, `${name}.syms.xz`);
    const cloud = join(import.meta.dirname, "..", "cloud");
    try {
      execFileSync("pnpm", ["exec", "wrangler", "r2", "object", "get", `stillfail-releases/symbols/android/${name}.syms.xz`, "--file", symbolsFile, "--remote"],
        { cwd: cloud, stdio: ["ignore", "ignore", "inherit"] });
    } catch {
      rmSync(tmp, { recursive: true, force: true });
      console.error(`crash-symbols: no symbols/android/${name}.syms.xz got from the bucket (kept 30 days; still.fail's own app's alone)`);
      process.exit(1);
    }
    args.splice(0, 2);
  } else {
    if (!args[0]) throw new Error(usage);
    symbolsFile = args.shift()!;
  }
  try {
    const symbols = parseSymbols(readSymbols(symbolsFile));
    const tombstone = readFileSync(args[0] ?? 0, "utf8");
    process.stdout.write(symbolize(tombstone, symbols));
  } finally {
    if (tmp) rmSync(tmp, { recursive: true, force: true });
  }
}
