// A cold prompt cache: the same decision in the station that starts the agent and the core that shows its choice.
// Costs are estimates in USD at the model's API list price; zero means every expired cache, priced or not.

export const DEFAULT_AFRESH_ABOVE = 1;
const COLD_FROM = 50_000;

/** Is the cold context worth offering a choice for? An explicit or unconditional fresh choice is always worth showing. */
export function coldWorth(context: number, cost: number | undefined, threshold: number | undefined, chosen?: unknown, enabled = false): boolean {
  return chosen === true || (enabled && threshold === 0) || context >= COLD_FROM || (threshold !== undefined && cost !== undefined && cost >= threshold);
}

/** The chat's explicit choice wins; an old station with no threshold keeps its former on/off behaviour. */
export function coldAfresh(chosen: unknown, enabled: boolean, threshold: number | undefined, cost: number | undefined): boolean {
  if (typeof chosen === "boolean") return chosen;
  if (!enabled) return false;
  return threshold === undefined || threshold === 0 || (cost !== undefined && cost >= threshold);
}

/** A threshold from config, falling back to the default when it is absent or invalid. */
export function afreshThreshold(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) && value >= 0 ? value : DEFAULT_AFRESH_ABOVE;
}
