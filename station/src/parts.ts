// The station's parts that are modules of it, in its own process (docs/station-modules.md, 「进程内的模块」): each a
// layer the composition root (main.ts) lists, made after the platform and the agents' side, saying here what it adds to
// what the station answers: its routes of the admin API, the writes a read-only member may make of them, its fields of
// the overview and its tools for the agents. Nothing registers itself: a part is in the station because main.ts names
// it, and says what it adds as it is made. What is said here is read as it is asked for (a request, an agent's tool
// list), so the admin API and the agents, made before the parts, take what they add.
import type { Route } from "./api/admin.ts";
import type { Lang } from "./ops/i18n.ts";
import type { Viewer } from "./mesh/credential.ts";
import type { Tool } from "./tools/mcp.ts";

export class StationParts {
  readonly #routes: Route[] = [];
  readonly #viewerMay: ((r: { method: string; path: string }) => boolean)[] = [];
  readonly #overview = new Map<string, (viewer: Viewer, lang: Lang) => unknown>();
  readonly #tools: Tool[] = [];

  /// A part's routes of the admin API (after the platform's own).
  routes(routes: Route[]): void {
    this.#routes.push(...routes);
  }

  /// Which of a part's requests besides reads a read-only member may make (their own marks, say).
  viewerMay(may: (r: { method: string; path: string }) => boolean): void {
    this.#viewerMay.push(may);
  }

  /// A field of the overview (GET /overview), as `viewer` sees it; none of the platform's or another part's.
  overview(field: string, view: (viewer: Viewer, lang: Lang) => unknown): void {
    if (this.#overview.has(field)) throw new Error(`the overview's ${field} is said twice`);
    this.#overview.set(field, view);
  }

  /// A part's tools for the agents (their MCP door, tools/mcp.ts).
  tools(tools: Tool[]): void {
    this.#tools.push(...tools);
  }

  // ── what is asked of them ──

  allRoutes(): readonly Route[] {
    return this.#routes;
  }

  mayView(r: { method: string; path: string }): boolean {
    return this.#viewerMay.some((may) => may(r));
  }

  async overviewOf(viewer: Viewer, lang: Lang): Promise<Record<string, unknown>> {
    const out: Record<string, unknown> = {};
    for (const [field, view] of this.#overview) out[field] = await view(viewer, lang);
    return out;
  }

  allTools(): readonly Tool[] {
    return this.#tools;
  }
}
