// The seeds simulated tests (sim-iroh.ts) run on: fixed, so a run is the same every time and a failure is the code's,
// replayed as it was anywhere. Each varies what a network leaves open (jitter, how writes are cut); SIM_SEED=<seed> runs
// only that one, as a failure names it.

export const SEEDS = [1, 2, 3, 4];

export function seeds(): number[] {
  return process.env.SIM_SEED ? [Number(process.env.SIM_SEED)] : SEEDS;
}
