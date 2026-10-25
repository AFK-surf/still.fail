/** A gesture may report several points between paints. Draw its latest point once, and flush before handing it
 * to a release animation so that animation starts exactly where the finger ended. */
export function latestFrame<T>(draw: (value: T) => void) {
  let frame = 0;
  let pending: { value: T } | null = null;
  const flush = () => {
    if (frame) cancelAnimationFrame(frame);
    frame = 0;
    const next = pending;
    pending = null;
    if (next) draw(next.value);
  };
  return {
    set(value: T) { pending = { value }; if (!frame) frame = requestAnimationFrame(flush); },
    flush,
    cancel() { if (frame) cancelAnimationFrame(frame); frame = 0; pending = null; },
  };
}

/** Release velocity from the last 100 ms, not from the beginning of a possibly long-held gesture. */
export class GestureVelocity {
  private samples: { value: number; at: number }[] = [];
  reset(value: number, at: number): void { this.samples = [{ value, at }]; }
  push(value: number, at: number): void {
    this.samples = this.samples.filter(sample => at - sample.at <= 100);
    if (this.samples.at(-1)?.at === at) this.samples.pop();
    this.samples.push({ value, at });
  }
  speed(at: number): number {
    const samples = this.samples.filter(sample => at - sample.at <= 100);
    const first = samples[0], last = samples.at(-1);
    return first && last && last.at > first.at ? (last.value - first.value) * 1000 / (last.at - first.at) : 0;
  }
}
