// One Linux desktop source: select the current user's active X11 or Wayland session when it is asked for.
import { hostname } from "node:os";
import { desktopEnvironment } from "./linux-session.ts";
import { LinuxScreenTools } from "./linux-tools.ts";
import { WaylandDesktop } from "./linux-portal.ts";
import type { ScreenAccess, ScreenSource, ScreenView, ViewOptions } from "./source.ts";
import { X11Desktop, type X11DesktopOptions } from "./x11-desktop.ts";

type LinuxOptions = { data: string; changed: () => void; env?: NodeJS.ProcessEnv; discover?: (env: NodeJS.ProcessEnv) => Promise<NodeJS.ProcessEnv> };

export class LinuxDesktop implements ScreenSource {
  readonly id = "desktop";
  readonly kind = "desktop" as const;
  readonly #o: LinuxOptions;
  readonly #x11Options: X11DesktopOptions;
  readonly #waylandOptions: { changed: () => void; env: NodeJS.ProcessEnv };
  readonly #x11: X11Desktop;
  readonly #wayland: WaylandDesktop;
  #current: X11Desktop | WaylandDesktop;
  #refreshing: Promise<void> | null = null;
  #looked = 0;

  constructor(options: LinuxOptions) {
    this.#o = options;
    const env = { ...(options.env ?? process.env) };
    this.#x11Options = { changed: options.changed, env, tools: new LinuxScreenTools(options.data) };
    this.#waylandOptions = { changed: options.changed, env };
    this.#x11 = new X11Desktop(this.#x11Options);
    this.#wayland = new WaylandDesktop(this.#waylandOptions);
    this.#current = env.XDG_SESSION_TYPE?.toLowerCase() === "wayland" || env.WAYLAND_DISPLAY ? this.#wayland : this.#x11;
  }
  title(): string { return hostname(); }
  size(): { width: number; height: number } { return this.#current.size(); }
  access(): ScreenAccess { return this.#current.access(); }
  async refresh(force = false): Promise<void> {
    if (!force && Date.now() - this.#looked < 2_000) return;
    this.#refreshing ??= (async () => {
      const env = await (this.#o.discover ?? desktopEnvironment)(this.#o.env ?? process.env);
      this.#x11Options.env = env;
      this.#waylandOptions.env = env;
      const next = env.XDG_SESSION_TYPE?.toLowerCase() === "wayland" || env.WAYLAND_DISPLAY ? this.#wayland : this.#x11;
      if (next !== this.#current) { this.#current = next; this.#o.changed(); }
      await next.refresh(force);
    })().finally(() => { this.#looked = Date.now(); this.#refreshing = null; });
    await this.#refreshing;
  }
  async open(options: ViewOptions): Promise<ScreenView> {
    await this.refresh(true);
    return this.#current.open(options);
  }
  async close(): Promise<void> { await Promise.all([this.#x11.close(), this.#wayland.close()]); }
}
