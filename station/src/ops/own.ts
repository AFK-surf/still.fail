// What is the station's own on this machine, never reached through what it lends its members or its control plane
// (the device tools, the drive): its data directory (its key, cloud.json, the profiles' homes under it), its config,
// the profiles' homes elsewhere, the machine's runtime logins.
import { claudeCredentialsFile, codexAuthFile } from "../agents/machine-logins.ts";

export const ownPaths = (data: string, config: string, profileHomes: string[]): string[] => [
  data,
  config,
  ...profileHomes,
  claudeCredentialsFile(process.env),
  codexAuthFile(process.env),
];
