/** Exact solution of a damped spring over elapsed seconds. Unlike Euler integration, the same elapsed time gives
 * the same position and velocity at 60 Hz, 120 Hz, or after a missed frame. Mass is one. */
export function springStep(value: number, velocity: number, target: number, tension: number, damping: number, dt: number): { value: number; velocity: number } {
  if (dt <= 0) return { value, velocity };
  const x = value - target;
  const a = damping / 2;
  const discriminant = tension - a * a;
  if (Math.abs(discriminant) < 1e-8) {
    const b = velocity + a * x, decay = Math.exp(-a * dt);
    return { value: target + (x + b * dt) * decay, velocity: (velocity - a * b * dt) * decay };
  }
  if (discriminant > 0) {
    const w = Math.sqrt(discriminant), decay = Math.exp(-a * dt), sin = Math.sin(w * dt), cos = Math.cos(w * dt);
    return { value: target + decay * (x * cos + (velocity + a * x) / w * sin), velocity: decay * (velocity * cos - (a * velocity + tension * x) / w * sin) };
  }
  const w = Math.sqrt(-discriminant), r1 = -a + w, r2 = -a - w;
  const c1 = (velocity - r2 * x) / (r1 - r2), c2 = x - c1;
  const e1 = Math.exp(r1 * dt), e2 = Math.exp(r2 * dt);
  return { value: target + c1 * e1 + c2 * e2, velocity: c1 * r1 * e1 + c2 * r2 * e2 };
}
