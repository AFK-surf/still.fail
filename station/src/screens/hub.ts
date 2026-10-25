// The station's screens (docs/remote-screens.md): the registry its parts add their sources to (source.ts
// `makeScreens`), and who is on each now. What members are told of them (GET /admin/api/screens, `screens` on the
// event stream, the agents' `screen` tool) is said here; the views themselves go over the member link (mesh/screens.ts).
import { type Lang, tr } from "../ops/i18n.ts";
import { type ScreenAccess, type ScreenSource, type ScreenView, type Screens, type ViewOptions, makeScreens } from "./source.ts";

/// One view open now: whose, whether its input is taken, and how it is told its people changed.
export type Watcher = { name: string; control: boolean; tell(state: Record<string, unknown>): void };

/// What a person is told of a source's access when something is missing: whether it can be seen and driven, why not,
/// in their language, and what to turn on.
export type AccessShown = { capture: boolean; control: boolean; message: string; app?: string; path?: string; asking?: boolean };

/// A source that cannot be opened now, and why, in words a person reads (`key` of client/i18n's station part).
export class ScreenRefused extends Error {
  readonly status: number;
  readonly key: string;
  readonly args: Record<string, unknown>;
  readonly access?: ScreenAccess;
  constructor(status: number, key: string, args: Record<string, unknown> = {}, access?: ScreenAccess) {
    super(tr("en", key, args));
    this.status = status;
    this.key = key;
    this.args = args;
    this.access = access;
  }
}

/// The message for what is missing; none when nothing is.
export function accessShown(access: ScreenAccess | undefined, lang: Lang): AccessShown | undefined {
  if (access === undefined || (access.capture && access.control && access.unsupported === undefined)) return undefined;
  const named = { app: access.app || "still.fail Helper" };
  const message =
    access.unsupported === "platform" ? tr(lang, "station.screen.unsupported")
    : access.unsupported === "helper" ? tr(lang, "station.screen.noHelper")
    : [
        // Neither: it cannot be viewed either, so not "viewed but not controlled".
        !access.capture && !access.control ? tr(lang, "station.screen.bothOff", named)
        : !access.capture ? tr(lang, "station.screen.captureOff", named)
        : tr(lang, "station.screen.controlOff", named),
        // Where it is granted: the window on the machine, up now or once the screen is opened.
        tr(lang, access.asking ? "station.screen.asking" : "station.screen.toAsk", named),
      ].join(" ");
  return { capture: access.capture, control: access.control, message, ...(access.app ? { app: access.app } : {}), ...(access.path ? { path: access.path } : {}), ...(access.asking ? { asking: true } : {}) };
}

export type HubOptions = {
  /// Where a file a person drops into a view is put on this machine (docs/remote-screens.md `drop`, the drive's
  /// `dropFolder`); none: files are not taken.
  drop?: () => string | null;
};

export class ScreenHub implements Screens {
  readonly #sources = makeScreens();
  readonly #o: HubOptions;
  readonly #views = new Map<string, Set<Watcher>>();
  readonly #listeners = new Set<() => void>();
  readonly #refreshers = new Set<() => Promise<void>>();
  readonly #stopping = new Set<() => void>();

  constructor(options: HubOptions = {}) {
    this.#o = options;
    this.#sources.watch(() => this.#changed());
  }

  add(source: ScreenSource): () => void {
    return this.#sources.add(source);
  }
  list(): ScreenSource[] {
    return this.#sources.list();
  }
  get(id: string): ScreenSource | undefined {
    return this.#sources.get(id);
  }
  watch(listener: (sources: ScreenSource[]) => void): () => void {
    return this.#sources.watch(listener);
  }
  /// A source's title, size or access changed.
  changed() {
    this.#sources.changed();
  }

  /// How a source's state is looked at again before it is told (the desktop's grants: asked of macOS, not followed).
  refresher(refresh: () => Promise<void>): () => void {
    this.#refreshers.add(refresh);
    return () => this.#refreshers.delete(refresh);
  }
  async refresh(): Promise<void> {
    await Promise.all([...this.#refreshers].map((f) => f().catch(() => {})));
  }

  /// What members are told changed: a source came, went or changed, or someone opened or left a view.
  onChange(listener: () => void): () => void {
    this.#listeners.add(listener);
    return () => this.#listeners.delete(listener);
  }
  #changed() {
    for (const f of [...this.#listeners]) f();
  }

  /// Who is on a source now: everyone viewing, and those of them whose input is taken.
  people(id: string): { viewers: string[]; controlledBy: string[] } {
    const on = [...(this.#views.get(id) ?? [])];
    return { viewers: on.map((w) => w.name), controlledBy: on.filter((w) => w.control).map((w) => w.name) };
  }

  /// A view opened on `id`: everyone on it is told who is, and members are; the returned function leaves.
  join(id: string, watcher: Watcher): () => void {
    const on = this.#views.get(id) ?? new Set<Watcher>();
    this.#views.set(id, on);
    on.add(watcher);
    this.#tellPeople(id);
    let left = false;
    return () => {
      if (left) return;
      left = true;
      on.delete(watcher);
      if (on.size === 0 && this.#views.get(id) === on) this.#views.delete(id);
      this.#tellPeople(id);
    };
  }

  #tellPeople(id: string) {
    const people = this.people(id);
    for (const w of [...(this.#views.get(id) ?? [])]) w.tell(people);
    this.#changed();
  }

  /// A view opened by the station itself (the agents' computer-use tool), shown as `who` while it is open: in
  /// `viewers`, and with `control` in `controlledBy` (a name such as "agent: <chat title>"). Closing it leaves.
  async openAs(id: string, options: ViewOptions, who: { name: string; control: boolean }): Promise<ScreenView> {
    const source = this.get(id);
    if (source === undefined) throw new ScreenRefused(404, "station.screen.notFound");
    const view = await source.open(options);
    const leave = this.join(id, { name: who.name, control: who.control, tell: () => {} });
    return {
      next: () => view.next(),
      keyframe: () => view.keyframe(),
      input: (event) => view.input(event),
      close: () => {
        leave();
        view.close();
      },
    };
  }

  /// What ends a view as the station stops.
  whenStopping(stop: () => void): () => void {
    this.#stopping.add(stop);
    return () => this.#stopping.delete(stop);
  }

  /// The station stopping: every view ends, said so (`ended: "stopping"`).
  close() {
    for (const stop of [...this.#stopping]) stop();
  }

  /// POST /admin/api/screens/<id>/close: a screen closed from a person's app (a tab of the browser).
  async closeScreen(id: string): Promise<void> {
    const source = this.get(id);
    if (source === undefined) throw new ScreenRefused(404, "station.screen.notFound");
    if (source.discard === undefined) throw new ScreenRefused(405, "station.screen.notClosed");
    await source.discard();
  }

  /// GET /admin/api/screens, in `lang`: `{screens: [{id, kind, title, width, height, viewers, controlledBy, access?,
  /// clipboard?, peek?, drop?, closable?, openedBy?}]}`: `clipboard`, the types a view that drives it carries both ways;
  /// `peek`, it can be previewed (ViewOptions.peek); `drop`, where a file
  /// dropped into a view is put (`folder`) and whether the view can show it in the machine's file manager (`reveal`);
  /// `closable`, a person may close it (POST …/close); `openedBy`, the session that opened it (an agent's tab).
  listed(lang: Lang): { screens: Record<string, unknown>[] } {
    const folder = this.#o.drop?.() ?? null;
    return {
      screens: this.list().map((s) => {
        const { width, height } = s.size();
        const access = accessShown(s.access?.(), lang);
        const clipboard = s.clipboard?.() ?? [];
        const by = s.openedBy?.();
        return {
          id: s.id, kind: s.kind, title: s.title(), width, height, ...this.people(s.id), ...(access ? { access } : {}),
          ...(clipboard.length > 0 ? { clipboard } : {}),
          ...(s.peek ? { peek: true } : {}),
          ...(s.discard ? { closable: true } : {}),
          ...(by ? { openedBy: by } : {}),
          ...(folder !== null ? { drop: { folder, reveal: s.reveal === true } } : {}),
        };
      }),
    };
  }
}
