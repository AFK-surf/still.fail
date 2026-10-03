// Words of the station module others match by (station.rs).

/// What a write waits on while its station is asked again whether it was done (a status wait's `what`).
export function RECHECKING(): string {
  return "等它回来确认";
}
