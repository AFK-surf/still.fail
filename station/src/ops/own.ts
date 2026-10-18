// What is the station's own on this machine, never reached through what it lends its members or its control plane
// (the device tools, the drive, a search of the machine's files): its data directory (its key, cloud.json, the profiles'
// homes under it), its config, and what its parts add as they are made (the agents: the profiles' homes elsewhere, the
// machine's runtime logins).
export class Own {
  readonly data: string;
  readonly config: string;
  readonly #more: (() => string[])[] = [];

  constructor(data: string, config: string) {
    this.data = data;
    this.config = config;
  }

  /// What a part keeps that is the station's own too, asked anew each time (a profile may be added meanwhile).
  add(more: () => string[]): void {
    this.#more.push(more);
  }

  /// What the parts add, without the data directory and the config.
  more(): string[] {
    return this.#more.flatMap((more) => more());
  }

  paths(): string[] {
    return [this.data, this.config, ...this.more()];
  }
}

/// The loopback ports this station's own servers listen on (the agents' door, the loopback port; behind a launcher's
/// entrance, its ports too): never reached by other stations' programs (mesh/peer-http.ts), as the door would carry
/// them on further and the rest is the station's own.
export const ownPorts = new Set<number>();
