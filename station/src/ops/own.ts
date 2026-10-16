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

/// The loopback ports this station's own servers listen on (the agents' door, the loopback port; behind a launcher's
/// entrance, its ports too): never reached by other stations' programs (mesh/peer-http.ts), as the door would carry
/// them on further and the rest is the station's own.
export const ownPorts = new Set<number>();
