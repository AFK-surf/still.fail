// One Linux desktop source: select the current user's active X11 or Wayland session when it is asked for.
import { hostname } from "node:os";
import { wall } from "../ops/fibers.ts";
import { desktopEnvironment } from "./linux-session.ts";
import { LinuxScreenTools } from "./linux-tools.ts";
import { LinuxGstDesktop } from "./linux-portal.ts";
import type { ScreenAccess, ScreenSource, ScreenView, ViewOptions } from "./source.ts";
import { X11Desktop, type X11DesktopOptions } from "./x11-desktop.ts";

type LinuxOptions = { data: string; changed: () => void; title?: () => string; env?: NodeJS.ProcessEnv; discover?: (env: NodeJS.ProcessEnv) => Promise<NodeJS.ProcessEnv> };

export class LinuxDesktop implements ScreenSource {
  readonly id = "desktop";
  readonly kind = "desktop" as const;
  readonly #o: LinuxOptions;
  readonly #x11Options: X11DesktopOptions;
  readonly #waylandOptions: { changed: () => void; title?: () => string; env: NodeJS.ProcessEnv };
  readonly #fallbackOptions: { changed: () => void; title?: () => string; env: NodeJS.ProcessEnv; mode: "x11" };
  readonly #tools: LinuxScreenTools;
  readonly #x11: X11Desktop;
  readonly #wayland: LinuxGstDesktop;
  readonly #fallback: LinuxGstDesktop;
  #current: X11Desktop | LinuxGstDesktop;
  #refreshing: Promise<void> | null = null;
  #looked = 0;

  constructor(options: LinuxOptions) {
    this.#o = options;
    const env = { ...(options.env ?? process.env) };
    this.#tools = new LinuxScreenTools(options.data);
    this.#x11Options = { changed: options.changed, title: options.title, env, tools: this.#tools };
    this.#waylandOptions = { changed: options.changed, title: options.title, env };
    this.#fallbackOptions = { changed: options.changed, title: options.title, env, mode: "x11" };
    this.#x11 = new X11Desktop(this.#x11Options);
    this.#wayland = new LinuxGstDesktop(this.#waylandOptions);
    this.#fallback = new LinuxGstDesktop(this.#fallbackOptions);
    this.#current = env.XDG_SESSION_TYPE?.toLowerCase() === "wayland" || env.WAYLAND_DISPLAY ? this.#wayland : this.#x11;
  }
  title(): string { return this.#o.title?.() ?? hostname(); }
  size(): { width: number; height: number } { return this.#current.size(); }
  access(): ScreenAccess { return this.#current.access(); }
  async refresh(force = false): Promise<void> {
    if (!force && wall.now() - this.#looked < 2_000) return;
    this.#refreshing ??= (async () => {
      const env = await (this.#o.discover ?? desktopEnvironment)(this.#o.env ?? process.env);
      this.#x11Options.env = env;
      this.#waylandOptions.env = env;
      this.#fallbackOptions.env = env;
      let next: X11Desktop | LinuxGstDesktop;
      if (env.XDG_SESSION_TYPE?.toLowerCase() === "wayland" || env.WAYLAND_DISPLAY) {
        next = this.#wayland;
      } else {
        await this.#x11.refresh(force);
        // CentOS's standard repositories do not provide both X11 commands. Its installed desktop's GStreamer and
        // XTest libraries can capture and control the same session without adding system repositories.
        next = this.#x11.access().reason === "linuxTools" && !this.#tools.canPrepare(env) ? this.#fallback : this.#x11;
      }
      if (next !== this.#current) { this.#current = next; this.#o.changed(); }
      if (next !== this.#x11) await next.refresh(force);
    })().finally(() => { this.#looked = wall.now(); this.#refreshing = null; });
    await this.#refreshing;
  }
  async open(options: ViewOptions): Promise<ScreenView> {
    await this.refresh(true);
    return this.#current.open(options);
  }
  async close(): Promise<void> { await Promise.all([this.#x11.close(), this.#wayland.close(), this.#fallback.close()]); }
}
