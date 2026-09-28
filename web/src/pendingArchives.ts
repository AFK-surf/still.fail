/** Hide an archive immediately, until both sidebar views have caught up with the successful write. */
export class PendingArchives {
  private pending = new Map<string, boolean>();
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
    this.reconcile(this.visible);
  }

  fail(key: string): void {
    this.pending.delete(key);
    this.emit();
  }

  reconcile(visible: Set<string>): void {
    this.visible = visible;
    let changed = false;
    for (const [key, done] of this.pending) {
      if (done && !visible.has(key)) {
        this.pending.delete(key);
        changed = true;
      }
    }
    if (changed) this.emit();
  }

  private emit(): void {
    this.snapshot = new Set(this.pending.keys());
    for (const listener of this.listeners) listener();
  }
}

export const archiveKey = (item: { station: string; id: string }): string => JSON.stringify([item.station, item.id]);
