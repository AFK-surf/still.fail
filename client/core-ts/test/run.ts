// Runs an effect for a test: its success, or its failure thrown as it is.
import { Effect } from "effect";

export async function run<A, E>(effect: Effect.Effect<A, E>): Promise<A> {
  const result = await Effect.runPromise(Effect.result(effect));
  if (result._tag === "Failure") throw result.failure;
  return result.success;
}
