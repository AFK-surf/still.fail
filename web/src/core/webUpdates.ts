// The browser host's update state. Kept outside the views: both web layouts show the same notice, and neither
// requests deployment metadata. This belongs to the web host, not the shared Rust core or the desktop updater.
declare const __WEB_REVISION__: string | null;

type Release = { revision: string; version: string };
const EVERY = 60_000;

export class WebUpdates {
  #available: Release | null = null;
  #dismissed: string | null = null;
  #listeners = new Set<() => void>();
  #checking = false;
  #last = -Infinity;
  #started = false;
  private readonly revision: string | null;
  private readonly read: () => Promise<unknown>;
  constructor(revision: string | null, read: () => Promise<unknown>) {
    this.revision = revision;
    this.read = read;
  }

  snapshot = (): Release | null => this.#available;
  subscribe = (listener: () => void): (() => void) => {
    this.#listeners.add(listener);
    return () => { this.#listeners.delete(listener); };
  };
  #publish(value: Release | null): void {
    if (this.#available?.revision === value?.revision) return;
    this.#available = value;
    for (const listener of this.#listeners) listener();
  }
  dismiss = (): void => {
    this.#dismissed = this.#available?.revision ?? null;
    this.#publish(null);
  };
  refresh = (): void => { window.location.reload(); };

  async check(now = Date.now()): Promise<void> {
    if (!this.revision || this.#checking || now - this.#last < EVERY) return;
    this.#checking = true;
    this.#last = now;
    try {
      const value = await this.read();
      if (!value || typeof value !== "object") return;
      const { revision, version } = value as Partial<Release>;
      // An old host, SPA fallback, failed request or incomplete deploy is not an update.
      if (typeof revision !== "string" || !/^[a-f0-9]{40}$/.test(revision) || typeof version !== "string" || !/^\d+\.\d+\.\d+$/.test(version)) return;
      this.#publish(revision === this.revision || revision === this.#dismissed ? null : { revision, version });
    } catch { /* Offline or an older host: try again next minute, without interrupting the page. */ }
    finally { this.#checking = false; }
  }

  start(): void {
    if (this.#started || !this.revision || window.stillfailDesktop) return;
    this.#started = true;
    const check = () => { if (document.visibilityState === "visible") void this.check(); };
    check();
    setInterval(check, EVERY);
    document.addEventListener("visibilitychange", check);
    window.addEventListener("online", check);
  }
}

export const webUpdates = new WebUpdates(typeof __WEB_REVISION__ === "string" ? __WEB_REVISION__ : null, async () => {
  const response = await fetch(`/build.json?t=${Date.now()}`, { cache: "no-store", signal: AbortSignal.timeout(10_000) });
  if (!response.ok) throw new Error("Build metadata unavailable");
  return response.json();
});
