// The iroh a Node host gives the core (iroh.ts): the native addon the station in TypeScript ships (station/native/mesh,
// `mesh.node`), which the client's endpoint shares, loaded by the base's hosts/node-addon.ts. Where it is:
// STILLFAIL_MESH_NATIVE, beside the core's bundle (mesh.node), or where cargo built it in a checkout.
import { fileURLToPath } from "node:url";
import type { Iroh } from "../iroh.ts";
import { type Addon, addonAt, addonIroh } from "./node-addon.ts";

let loaded: Addon | null | undefined;

/// The addon, if it is there.
export function loadAddon(): Addon | null {
  if (loaded !== undefined) return loaded;
  // In a CommonJS bundle (the desktop app's) there is no import.meta: there STILLFAIL_MESH_NATIVE says where it is.
  const here = typeof import.meta.url === "string" ? import.meta.url : null;
  const near = (path: string) => (here ? fileURLToPath(new URL(path, here)) : undefined);
  loaded = addonAt([
    process.env.STILLFAIL_MESH_NATIVE,
    near("./mesh.node"),
    near("../../../../station/native/mesh/target/release/libstillfail_mesh.dylib"),
    near("../../../../station/native/mesh/target/release/libstillfail_mesh.so"),
  ]);
  return loaded;
}

/// The iroh of the addon (`addon`: a test's, to see what is bound); null where there is none.
export function nodeIroh(addon: Addon | null = loadAddon()): Iroh | null {
  return addon === null ? null : addonIroh(addon);
}

/// A station-side endpoint for tests: accepts the client's ALPNs.
export function testStation(addon: Addon, secretKey: Uint8Array, alpns: Uint8Array[]) {
  return addon.bind({ secretKey: Buffer.from(secretKey), alpns: alpns.map((a) => Buffer.from(a)), relayUrls: [], discovery: false });
}
