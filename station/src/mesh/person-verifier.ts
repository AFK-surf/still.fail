// Personal chains can contain 1024 signed entries. Check them on one reusable worker, not on the station's event loop.
import { Worker } from "node:worker_threads";
import type { Entry, Person, Role } from "../cloud/lock.ts";
import { wall } from "../ops/fibers.ts";

export type PersonWho = { sub: string; endpoint: string; base?: string; proof?: string };
export type PersonRequest =
  | { kind: "snapshot"; sub: string; entries: unknown[]; bindings: string[] }
  | { kind: "admit"; entries: unknown[]; workspace: Entry[]; who: PersonWho };
type Answer = { id: number; person?: Person; role?: Role; error?: string };

export class PersonVerifier {
  readonly #data: string;
  #worker: Worker | null = null;
  #idle: (() => void) | null = null;
  #next = 0;
  #closed = false;
  readonly #waiting = new Map<number, { resolve: (answer: Answer) => void; reject: (error: Error) => void; timer: () => void }>();

  constructor(data: string) { this.#data = data; }

  #start(): Worker {
    if (this.#closed) throw new Error("the personal lock verifier is stopped");
    if (this.#idle) { this.#idle(); this.#idle = null; }
    if (this.#worker) return this.#worker;
    const file = new URL(import.meta.url.endsWith(".ts") ? "./person-verifier-worker.ts" : "./mesh/person-verifier-worker.js", import.meta.url);
    const worker = new Worker(file, { workerData: { data: this.#data }, resourceLimits: { maxOldGenerationSizeMb: 128, maxYoungGenerationSizeMb: 8 } });
    this.#worker = worker;
    worker.on("message", (answer: Answer) => {
      const waiter = this.#waiting.get(answer.id);
      if (!waiter) return;
      this.#waiting.delete(answer.id);
      waiter.timer();
      if (answer.error !== undefined) waiter.reject(new Error(answer.error));
      else waiter.resolve(answer);
      this.#rest(worker);
    });
    worker.on("error", () => this.#stop(worker));
    worker.on("exit", () => this.#stop(worker));
    return worker;
  }

  #stop(worker: Worker): void {
    if (this.#worker !== worker) return;
    this.#worker = null;
    if (this.#idle) { this.#idle(); this.#idle = null; }
    for (const waiter of this.#waiting.values()) {
      waiter.timer();
      waiter.reject(new Error("the personal lock verifier stopped"));
    }
    this.#waiting.clear();
    void worker.terminate();
  }

  #rest(worker: Worker): void {
    if (this.#worker !== worker || this.#waiting.size !== 0 || this.#idle) return;
    this.#idle = wall.after(60_000, () => this.#stop(worker));
  }

  #ask(request: PersonRequest): Promise<Answer> {
    // Bound the memory held by untrusted connections while a long chain is being checked.
    if (this.#waiting.size >= 32) return Promise.reject(new Error("the personal lock verifier is busy"));
    let worker: Worker;
    try { worker = this.#start(); } catch (error) { return Promise.reject(error); }
    const id = this.#next++;
    return new Promise((resolve, reject) => {
      const timer = wall.after(30_000, () => this.#stop(worker));
      this.#waiting.set(id, { resolve, reject, timer });
      try { worker.postMessage({ id, ...request }); }
      catch (error) { timer(); this.#waiting.delete(id); reject(error); this.#rest(worker); }
    });
  }

  async snapshot(sub: string, entries: unknown[], bindings: string[]): Promise<Person> {
    const answer = await this.#ask({ kind: "snapshot", sub, entries, bindings });
    if (!answer.person) throw new Error("the personal lock verifier returned no state");
    return answer.person;
  }

  async admit(workspace: Entry[], who: PersonWho, entries: unknown[]): Promise<Role> {
    const answer = await this.#ask({ kind: "admit", workspace, who, entries });
    if (!answer.role) throw new Error("the personal lock verifier returned no role");
    return answer.role;
  }

  close(): void {
    this.#closed = true;
    if (this.#worker) this.#stop(this.#worker);
  }
}
