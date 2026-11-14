// The base in MoonBit knows no program (libs/base/AGENTS.md): not still.fail's app, station or cloud, nor the program
// it was first written for outside this repository (an instant messenger). As mbui's own rule is held (libs/mbui's
// detlint, `app-word`), and here over comments too, since none of these files needs the names even there. Refused:
//   - a member of its workspace (moon.work) but itself and mbui, a module it imports (moon.mod) but mbui;
//   - a package of it importing anything but its own packages, mbui's `effect` and MoonBit's core (`moonbitlang/core`),
//     in any of its moon.pkg's import blocks (its tests' too: `import { … } for "test"`);
//   - mbui's `effect` taking more of mbui than OF_MBUI says, or scripts/check.sh not running the base's moon step for
//     a change to each of those: what the base is built with is checked again when it changes;
//   - a library named to link (a moon.pkg's link flags): what a program built on it links is that program's to say
//     (the Rust shell's `libstillfail_shell.a` natively), as where a page serves iroh for the browser from is
//     (`stillfail_iroh_wasm.js` and its wasm): the page's shell loads the address it is given, and no other file here
//     loads a script at all;
//   - C that includes anything but the system's headers and MoonBit's;
//   - still.fail's name, a name of one of its programs or of what is theirs (WORDS), on any line under src/, in
//     moon.mod or in moon.work: but where NAMED lets a text be, whole and as many times as it says. What NAMED lets
//     be is what is there today and not this library's to rename: the Rust shell's C interface, three keys of the
//     device base's words and a reason on the wire, one path in a comment;
//   - a word of that first program outside (ITS_WORDS), as a word, on any line under src/.
// It reads the files' text, not the program: a name put together as it runs passes. It is held against a slip.
// Prints each line that is not so, and fails then.
//   node scripts/mb-base.ts
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = fileURLToPath(new URL("../libs/base", import.meta.url));

/// What a package here may import: the library's own packages, mbui's effect, MoonBit's core.
const MAY = /^(base\/[a-z_]+|mbui\/effect|moonbitlang\/core\/.+)$/;
/// The workspace: the library and mbui, which it takes `effect` of.
const MEMBERS = [".", "../mbui"];
/// The packages of mbui the base is built with: `effect`, and what `effect` imports of mbui, through any number of
/// imports. scripts/check.sh type-checks and tests the base again for a change to any of them, and names them there.
const OF_MBUI = ["effect", "halt"];
const CHECK = "scripts/check.sh";

/// still.fail's name, its code's prefixes (`sf_`, `sfh_`, the app's `sf…` packages: mbui's own list), its programs and
/// what is theirs.
const WORDS = /still\.?fail|\bsfh?_\w*|\bsf(base|app|pages|desk|core|kit|fix)\b|station|cloud|workspace|\bapps\//gi;
/// The words of the program this was first written for (an instant messenger outside this repository): what it is
/// about (conversations, members) and its own name (`im`, `im/1`, `IM_ADDON`), each as a word of its own, in any
/// case: not inside a longer one (`trim_start`, `claim_`, `prim_`, "remember", "membership" are none), but as a part
/// of a name written with `_` (`member_id`, `im_link`). That program's own check held `token` too, while these
/// packages were its: not here, since a mesh may honestly call a credential, or a part of what it parses, a token.
const ITS_WORDS = /(?<![A-Za-z0-9])(conversations?|members?|im)(?![A-Za-z0-9])/gi;

/// Where a file still says one of WORDS: [file, the text it is said in, how many times the file says it, what takes
/// it away]. The text is let be only whole (not as part of a longer name), and as many times as said here: once more
/// is refused, once fewer lowers the count. This table only falls.
const C_INTERFACE = "the Rust shell's C interface named for no program (client/shell/src/lib.rs: what every program linked to it declares, station/mb/src/host/host.c too)";
const KEY = "the key renamed in the device base's words (client/core-ts/src/lang.zh.json, lang.en.json, whose texts say \"the server\" already)";
const REASON = "another reason on the wire: it is what a peer closes a connection with as it takes a device out (client/core-ts/src/mesh.ts reads the same), and the key of the words for it";
const NAMED: [file: string, text: string, times: number, until: string][] = [
  ["src/shell/shell.c", "sf_complete", 2, C_INTERFACE],
  ["src/shell/shell.c", "sf_shell_start", 2, C_INTERFACE],
  ["src/shell/shell.c", "sf_shell_call", 2, C_INTERFACE],
  ["src/shell/shell.c", "sf_shell_call_sync", 2, C_INTERFACE],
  ["src/shell/shell.c", "sf_free", 2, C_INTERFACE],
  ["src/mesh/link.mbt", "station_removed", 2, REASON],
  ["src/mesh/link.mbt", "closed_by_station", 1, KEY],
  ["src/mesh/mesh.mbt", "bad_station_id", 1, KEY],
  // (made from the device base's words by scripts/mb-base-words.ts: a key and its text in each language)
  ["src/mesh/words_made.mbt", "station_removed", 4, REASON],
  ["src/mesh/words_made.mbt", "closed_by_station", 2, KEY],
  ["src/mesh/words_made.mbt", "bad_station_id", 2, KEY],
  ["src/wire/wire.mbt", "station/src/mesh/wire.ts", 1, "the door whose lines these are read as (the server side's base: scripts/mesh-base.ts) having a home that names no program; a comment"],
];

/// The one file that loads a script: the page's shell, iroh for the browser, from the address it is given.
const LOADS = "src/shell/shell_js.mbt";

const wrong: string[] = [];

/// The files under `dir`, from the library's root (not what moon builds there).
function under(dir: string): string[] {
  return readdirSync(join(ROOT, dir), { withFileTypes: true }).flatMap((entry) => {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) return entry.name === "_build" || entry.name === ".mooncakes" ? [] : under(path);
    return [path];
  });
}

/// The strings of every block `<name> { "…", … }` or `<name> = [ "…", … ]` of a moon file (a moon.pkg has an import
/// block for its package and may have one more for its tests, `import { … } for "test"`), comments left out; none
/// where it has no such block.
function blocks(source: string, name: RegExp): string[] {
  const code = source.replace(/^\s*\/\/.*$/gm, "");
  return [...code.matchAll(new RegExp(name.source, "g"))].flatMap((start) => {
    const rest = code.slice(start.index + start[0].length);
    const end = rest.search(/[}\]]/);
    return [...rest.slice(0, end < 0 ? rest.length : end).matchAll(/"([^"]*)"/g)].map((match) => match[1]!);
  });
}

const text = (file: string) => readFileSync(join(ROOT, file), "utf8");
const escaped = (s: string) => s.replace(/[.*+?^${}()|[\]\\/]/g, "\\$&");

// ── the workspace and the module ──

const members = blocks(text("moon.work"), /\bmembers\s*=\s*\[/);
if (members.join() !== MEMBERS.join()) wrong.push(`moon.work: its members are ${members.join(", ")}: the library and mbui alone (${MEMBERS.join(", ")})`);
for (const imported of blocks(text("moon.mod"), /\bimport\s*\{/)) {
  if (imported.replace(/@.*$/, "") !== "mbui") wrong.push(`moon.mod: imports the module ${imported}: of other modules the base takes mbui alone (its effect)`);
}

// ── what it is built with of mbui ──

/// `effect` and every package of mbui it reaches, by their moon.pkg files.
const reached = new Set<string>();
for (let queue = ["effect"], taken = queue.pop(); taken !== undefined; taken = queue.pop()) {
  if (reached.has(taken)) continue;
  reached.add(taken);
  for (const imported of blocks(text(`../mbui/src/${taken}/moon.pkg`), /\bimport\s*\{/)) if (imported.startsWith("mbui/")) queue.push(imported.slice("mbui/".length));
}
if ([...reached].sort().join() !== [...OF_MBUI].sort().join()) wrong.push(`libs/mbui/src/effect reaches ${[...reached].sort().join(", ")} of mbui, and OF_MBUI (scripts/mb-base.ts) says ${OF_MBUI.join(", ")}: say there what it reaches now, and in ${CHECK} where the base's moon step is run for a change to them`);
const stepFor = `^libs/mbui/src/(${OF_MBUI.join("|")})/`;
if (!text(`../../${CHECK}`).includes(stepFor)) wrong.push(`${CHECK} does not run the base's moon step for ${stepFor}: the base is built with those packages of mbui (OF_MBUI, scripts/mb-base.ts), and is checked again as one changes`);

// ── the packages ──

const files = [...under("src"), "moon.mod", "moon.work"].sort();
for (const file of files) {
  const source = text(file);
  const lines = source.split("\n");
  if (file.endsWith("moon.pkg")) {
    for (const imported of blocks(source, /\bimport\s*\{/)) {
      if (!MAY.test(imported)) wrong.push(`${file}: imports ${imported}: a package of the base imports its own, mbui/effect and moonbitlang/core alone`);
    }
    lines.forEach((line, i) => {
      if (/cc-link-flags|cc-flags|\.(a|o|so|dylib|lib|dll)\b/.test(line.replace(/\/\/.*$/, ""))) wrong.push(`${file}:${i + 1}: names what is linked or how: that is the linking program's to say`);
    });
  }
  if (/\.(c|h)$/.test(file)) {
    for (const [, included] of source.matchAll(/^\s*#\s*include\s*"([^"]+)"/gm)) {
      if (included !== "moonbit.h") wrong.push(`${file}: includes ${included}: the base's C includes the system's headers and MoonBit's alone`);
    }
  }
  if (file.endsWith(".mbt")) {
    lines.forEach((line, i) => {
      if (/^\s*\/\//.test(line)) return;
      const loads = /\bimport\s*\(|\bimportScripts\b|\brequire\s*\(|createElement\(\s*["']script|\bnew\s+Worker\b|\beval\s*\(|\bnew\s+Function\b/.exec(line);
      if (loads === null) return;
      if (file !== LOADS) wrong.push(`${file}:${i + 1}: loads a script (${loads[0]}): of the base the page's shell alone does (${LOADS}: iroh for the browser)`);
      else if (/["'`]/.test(line.slice(loads.index + loads[0].length).split(")")[0] ?? "")) wrong.push(`${file}:${i + 1}: loads a script it names itself: the page's shell is told where iroh is, by the program built on it`);
    });
  }

  // The names: each text NAMED lets be in this file taken out of its lines first (the longest first, so that one
  // within another is not counted for it), then nothing of WORDS left.
  const let_be = NAMED.filter(([named]) => named === file).sort((a, b) => b[1].length - a[1].length);
  const counts = new Map(let_be.map(([, said]) => [said, 0]));
  lines.forEach((line, i) => {
    let rest = line;
    for (const [, said] of let_be) {
      rest = rest.replace(new RegExp(`(?<![A-Za-z0-9_])${escaped(said)}(?![A-Za-z0-9_])`, "g"), () => {
        counts.set(said, counts.get(said)! + 1);
        return " ";
      });
    }
    for (const found of rest.matchAll(WORDS)) wrong.push(`${file}:${i + 1}: says "${found[0]}": the base names no program of still.fail's, nor still.fail`);
    if (file.startsWith("src/")) for (const found of rest.matchAll(ITS_WORDS)) wrong.push(`${file}:${i + 1}: says "${found[0]}": a word of a program built on the base, not the base's: say what it is to the mesh (a peer, a credential, a request)`);
  });
  for (const [, said, times, until] of let_be) {
    const there = counts.get(said)!;
    if (there > times) wrong.push(`${file}: says "${said}" ${there} times, and NAMED (scripts/mb-base.ts) lets it be ${times}: it goes with ${until}, and is said no more often meanwhile`);
    else if (there < times) wrong.push(`${file}: says "${said}" ${there} times, and NAMED (scripts/mb-base.ts) says ${times}: lower its count there${there === 0 ? ", or take its entry out" : ""} (the table only falls)`);
  }
}
for (const [file] of NAMED) if (!files.includes(file)) wrong.push(`NAMED names a file that is not there: ${file}: take its entries out`);

if (wrong.length > 0) {
  console.log(wrong.join("\n"));
  console.log(`(the base in MoonBit stands without a program: what one needs of it is given it as a parameter, by the program; ${"libs/base/AGENTS.md"})`);
  process.exit(1);
}
