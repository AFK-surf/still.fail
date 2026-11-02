// The core's lazy dependency graph, built on alien-signals/system. A change queues its observers without computing
// their values until the store schedules them; a dependency that is no longer read releases its links.
import { createReactiveSystem, type ReactiveFlags as Flags, type Link, type ReactiveNode } from "alien-signals/system";

// The package declares its flags as an ambient const enum, which cannot be
// imported as a value with this project's verbatimModuleSyntax setting.
const F = { None: 0, Mutable: 1, Watching: 2, RecursedCheck: 4, Recursed: 8, Dirty: 16, Pending: 32 } as const satisfies typeof import("alien-signals/system").ReactiveFlags;

type Result<T> = { ok: true; value: T } | { ok: false; error: unknown };
let active: ReactiveNode | undefined;
let cycle = 0;
let depth = 0;
let batching = 0;
let dispatching = false;
const pending = new Set<Observer>();

const { link, unlink, propagate, checkDirty, shallowPropagate } = createReactiveSystem({
  update(node) { return (node as Source<unknown> | Derived<unknown>).update(); },
  notify(node) {
    const observer = node as Observer;
    if (!observer.alive || observer.queued) return;
    observer.queued = true;
    pending.add(observer);
  },
  unwatched(node) {
    if (node instanceof Derived) node.detach();
    else if (node instanceof Source) node.unwatched();
  },
});

function dispatch(): void {
  if (batching || depth || dispatching) return;
  dispatching = true;
  let failed = false;
  let failure: unknown;
  try {
    for (const observer of pending) {
      pending.delete(observer);
      if (!observer.alive) continue;
      try { observer.schedule(observer.job); }
      catch (error) {
        observer.queued = false;
        observer.flags |= F.Recursed;
        if (!failed) { failed = true; failure = error; }
      }
    }
  } finally {
    dispatching = false;
  }
  if (failed) throw failure;
}

function prune(node: ReactiveNode): void {
  let dep = node.depsTail !== undefined ? node.depsTail.nextDep : node.deps;
  while (dep !== undefined) dep = unlink(dep, node);
}

function shouldUpdate(node: ReactiveNode): boolean {
  const flags = node.flags;
  if (flags & F.Dirty) return true;
  if (flags & F.Pending) {
    if (node.deps !== undefined && checkDirty(node.deps, node)) return true;
    node.flags = flags & ~F.Pending;
  }
  return false;
}

function tracked(node: ReactiveNode): void {
  if (active !== undefined && active.flags !== F.None) link(node, active, cycle);
}

export class Source<T> implements ReactiveNode {
  subs: Link | undefined;
  subsTail: Link | undefined;
  flags: Flags = F.Mutable;
  #value: T;
  #next: T;
  readonly #unwatched: (() => void) | undefined;
  constructor(value: T, unwatched?: () => void) { this.#value = this.#next = value; this.#unwatched = unwatched; }

  get(): T {
    if (this.flags & F.Dirty && this.update() && this.subs !== undefined) shallowPropagate(this.subs);
    tracked(this);
    dispatch();
    return this.#value;
  }

  set(value: T): void {
    if (Object.is(this.#next, value)) return;
    this.#next = value;
    this.flags = F.Mutable | F.Dirty;
    if (this.subs !== undefined) propagate(this.subs, depth > 0);
    dispatch();
  }

  update(): boolean {
    this.flags = F.Mutable;
    const changed = !Object.is(this.#value, this.#next);
    this.#value = this.#next;
    return changed;
  }

  hasSubscribers(): boolean { return this.subs !== undefined; }

  subscriberCount(): number {
    let count = 0;
    for (let sub = this.subs; sub !== undefined; sub = sub.nextSub) count++;
    return count;
  }

  unwatched(): void { this.#unwatched?.(); }
}

export class Derived<T> implements ReactiveNode {
  subs: Link | undefined;
  subsTail: Link | undefined;
  deps: Link | undefined;
  depsTail: Link | undefined;
  flags: Flags = F.Mutable | F.Dirty;
  #result: Result<T> | undefined;
  readonly #getter: () => T;
  constructor(getter: () => T) { this.#getter = getter; }

  get(): T {
    const parent = active;
    try {
      if (shouldUpdate(this) && this.update() && this.subs !== undefined) shallowPropagate(this.subs);
      tracked(this);
      const result = this.#result!;
      if (!result.ok) throw result.error;
      return result.value;
    } finally {
      if (parent === undefined && this.subs === undefined) this.detach();
      dispatch();
    }
  }

  update(): boolean {
    ++cycle;
    this.depsTail = undefined;
    this.flags = F.Mutable | F.RecursedCheck;
    const previous = active;
    active = this;
    const old = this.#result;
    try {
      depth++;
      try { this.#result = { ok: true, value: this.#getter() }; }
      catch (error) { this.#result = { ok: false, error }; }
    } finally {
      depth--;
      active = previous;
      this.flags &= ~F.RecursedCheck;
      prune(this);
    }
    const current = this.#result!;
    return old === undefined || old.ok !== current.ok || (old.ok && current.ok
      ? !Object.is(old.value, current.value)
      : !old.ok && !current.ok && !Object.is(old.error, current.error));
  }

  detach(): void {
    this.flags = F.Mutable | F.Dirty;
    let dep = this.depsTail;
    while (dep !== undefined) {
      const previous = dep.prevDep;
      unlink(dep, this);
      dep = previous;
    }
  }
}

class Observer implements ReactiveNode {
  deps: Link | undefined;
  depsTail: Link | undefined;
  flags: Flags = F.Watching;
  alive = true;
  queued = false;
  readonly #fn: () => void;
  readonly schedule: (job: () => void) => void;
  readonly job = () => this.run(false);
  constructor(fn: () => void, schedule: (job: () => void) => void) { this.#fn = fn; this.schedule = schedule; }

  run(first: boolean): void {
    if (!this.alive) return;
    if (!first && !shouldUpdate(this)) {
      this.queued = false;
      this.flags = F.Watching;
      dispatch();
      return;
    }
    this.queued = false;
    ++cycle;
    this.depsTail = undefined;
    this.flags = F.Watching | F.RecursedCheck;
    const previous = active;
    active = this;
    try {
      depth++;
      this.#fn();
    } finally {
      depth--;
      active = previous;
      this.flags &= ~F.RecursedCheck;
      prune(this);
      if (this.alive && (this.flags & F.Recursed)) {
        this.flags = F.Watching | F.Dirty;
        if (!this.queued) { this.queued = true; pending.add(this); }
      }
      dispatch();
    }
  }

  stop(): void {
    if (!this.alive) return;
    this.alive = false;
    this.flags = F.None;
    pending.delete(this);
    let dep = this.deps;
    while (dep !== undefined) dep = unlink(dep, this);
  }
}

export function signal<T>(value: T, unwatched?: () => void): Source<T> { return new Source(value, unwatched); }
export function computed<T>(getter: () => T): Derived<T> { return new Derived(getter); }
export function tracking(): boolean { return active !== undefined && active.flags !== F.None; }
export function untracked<T>(fn: () => T): T {
  const previous = active;
  active = undefined;
  try { return fn(); }
  finally { active = previous; }
}
export function observe(fn: () => void, schedule: (job: () => void) => void): () => void {
  const observer = new Observer(fn, schedule);
  try { observer.run(true); }
  catch (error) { observer.stop(); throw error; }
  return () => observer.stop();
}
export function batch(fn: () => void): void {
  batching++;
  try { fn(); }
  finally { batching--; dispatch(); }
}
