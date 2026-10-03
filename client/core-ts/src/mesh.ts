// This device's iroh endpoint and its links to stations (mesh.rs), over the iroh surface each host gives (`Iroh`,
// mesh-native.ts). Until a host gives one, stations are not reached.
import { Effect } from "effect";
import type { Inner } from "./core.ts";
import { CoreError } from "./error.ts";
import type { StationWire } from "./station/wire.ts";

/// The wire over mesh links (filled in by the mesh module once an iroh is given).
export function meshWire(_inner: Inner): StationWire {
  return {
    request: () => Effect.fail(new CoreError("mesh", "no mesh on this host yet")),
  };
}
