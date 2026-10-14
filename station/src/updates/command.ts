// `stillfail-station update [--beta|--stable] --app DIR [--data DIR]`, what `stillfail update` (bin/stillfail,
// bin/stillfail.ps1) asks before it runs the installer: the channel set first when one is named (as `channel` does),
// then the channel's latest release verified as the pages' update does it (release.ts), and what to run said on stdout,
// a line each: `script=<the installer this release carries>` and the variables to give it (`STILLFAIL_…=…`). The shell
// runs it, not this process: on Windows the installer ends what runs from the release, this Node included.
// A refusal on stderr, exit code 1; a usage error, exit code 2.
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { providerOf, specOf } from "../cloud/provider.ts";
import { flag } from "../ops/files.ts";
import { stationLang, tr } from "../ops/i18n.ts";
import { setChannel } from "./channel.ts";
import { planUpdate } from "./release.ts";
import { type Channel, channelOf, releaseChannel } from "./versions.ts";

const configPath = (data: string) => process.env.STILLFAIL_CONFIG || process.env.EMBER_CONFIG || join(data, "config.json");

/// Where the releases of the control plane the station is in are (cloud.json: its origin, and Comma's under
/// /stations); none before it joined one. Before the station first ran, its data may still be at the old place.
export function releaseBaseIn(data: string): string | null {
  for (const file of [join(data, "mesh", "cloud.json"), join(homedir(), ".ember", "mesh", "cloud.json")]) {
    let said: any;
    try {
      said = JSON.parse(readFileSync(file, "utf8"));
    } catch {
      continue;
    }
    if (typeof said?.origin === "string" && said.origin) return specOf(providerOf(said.provider)).releaseBase(said.origin.replace(/\/+$/, ""));
  }
  return null;
}

export async function updateCommand(args: string[], data: string, trusted?: Map<string, string>): Promise<number> {
  const app = flag(args, "--app");
  const asked = args.filter((a) => a === "--beta" || a === "--stable");
  const positional = args.filter((a, i) => !a.startsWith("--") && !(i > 0 && ["--app", "--data"].includes(args[i - 1]!)));
  if (!app || asked.length > 1 || positional.length !== 1) return 2;
  const lang = stationLang();
  try {
    const base = releaseBaseIn(data);
    if (base === null) throw new Error(tr(lang, "station.updates.notJoined"));
    const named: Channel | null = asked[0] === "--beta" ? "beta" : asked[0] === "--stable" ? "stable" : null;
    if (named !== null) await setChannel(data, named, 10_000);
    let raw: any = {};
    if (existsSync(configPath(data))) raw = JSON.parse(readFileSync(configPath(data), "utf8"));
    const channel = channelOf(raw, app);
    const installed = releaseChannel(app) ?? channel;
    const plan = await planUpdate({ base, channel, app, installed, lang, trusted });
    const lines = [`script=${plan.script}`, ...Object.entries(plan.env).map(([k, v]) => `${k}=${v}`)];
    if (lines.some((l) => /[\r\n]/.test(l))) throw new Error(`a line break in ${JSON.stringify(lines)}`);
    console.log(lines.join("\n"));
    return 0;
  } catch (e) {
    console.error(`Error: ${(e as Error).message}`);
    return 1;
  }
}
