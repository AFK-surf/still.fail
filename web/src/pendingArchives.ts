/** Hide an archive immediately, allowing the successful write's coalesced sidebar updates to catch up. */
export class PendingArchives {
  private pending = new Map<string, boolean>();
  private timers = new Map<string, ReturnType<typeof setTimeout>>();
  private visible = new Set<string>();
  private listeners = new Set<() => void>();
  private snapshot: ReadonlySet<string> = new Set();

  subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener);
    return () => { this.listeners.delete(listener); };
  };
  getSnapshot = (): ReadonlySet<string> => this.snapshot;

  begin(key: string): boolean {
    if (this.pending.has(key)) return false;
    this.pending.set(key, false);
    this.emit();
    return true;
  }

  finish(key: string): void {
    this.pending.set(key, true);
    // A new message can restore the chat before either view ever shows it absent. Do not mask that row forever:
    // allow a second for the core's coalesced updates, then trust the latest list even if it still contains the row.
    this.timers.set(key, setTimeout(() => this.fail(key), 1000));
    this.reconcile(this.visible);
  }

  fail(key: string): void {
    this.remove(key);
    this.emit();
  }

  reconcile(visible: Set<string>): void {
    this.visible = visible;
    let changed = false;
    for (const [key, done] of this.pending) {
      if (done && !visible.has(key)) {
        this.remove(key);
        changed = true;
      }
    }
    if (changed) this.emit();
  }

  private remove(key: string): void {
    clearTimeout(this.timers.get(key));
    this.timers.delete(key);
    this.pending.delete(key);
  }

  private emit(): void {
    this.snapshot = new Set(this.pending.keys());
    for (const listener of this.listeners) listener();
  }
}

export const archiveKey = (item: { station: string; id: string }): string => JSON.stringify([item.station, item.id]);
