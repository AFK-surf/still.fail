// A cold prompt cache: the same decision in the station that starts the agent and the core that shows its choice.
// Costs are estimates in USD at the model's API list price; an unpriced model must never be assumed expensive.

export const DEFAULT_AFRESH_ABOVE = 1;
const COLD_FROM = 50_000;

/** Is the cold context worth offering a choice for? An explicit fresh choice remains in effect even for a small one. */
export function coldWorth(context: number, cost: number | undefined, threshold: number | undefined, chosen?: unknown): boolean {
  return chosen === true || context >= COLD_FROM || (threshold !== undefined && cost !== undefined && cost >= threshold);
}

/** The chat's explicit choice wins; an old station with no threshold keeps its former on/off behaviour. */
export function coldAfresh(chosen: unknown, enabled: boolean, threshold: number | undefined, cost: number | undefined): boolean {
  if (typeof chosen === "boolean") return chosen;
  if (!enabled) return false;
  return threshold === undefined || (cost !== undefined && cost >= threshold);
}

/** A threshold from config, falling back to the default when it is absent or invalid. */
export function afreshThreshold(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) && value >= 0 ? value : DEFAULT_AFRESH_ABOVE;
}
