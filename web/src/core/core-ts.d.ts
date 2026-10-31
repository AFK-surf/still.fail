// The TypeScript core's web host (client/core-ts/src/hosts/web.ts), as the worker uses it. Vite resolves the module
// to that file (vite.config.ts); its types are said here, so the web's stricter tsconfig checks the worker against
// this and the core is checked by its own (client/core-ts/tsconfig.json).
declare module "@stillfail/core-ts/web" {
  /** What client/iroh-wasm's module gives. */
  export type IrohModule = { bind(options: { secretKey: Uint8Array; relayUrls: string[] }): Promise<unknown> };
  /** What the core uses of SQLite's WASM build (`@sqlite.org/sqlite-wasm`), as the worker loads it. */
  export type WasmSqlite = {
    open(path: string): never;
    memory(): never;
    unlink(path: string): boolean;
    reserve(files: number): Promise<void>;
  };
  /** A core in this worker: one client per port; `bytes`, those a page handed over beside a message (src/mbui/core.ts). */
  export interface WebCore {
    connect(): number;
    disconnect(client: number): void;
    receive(client: number, message: unknown, bytes?: Uint8Array): void;
  }
  /** Whether what the core shares is frozen where it is shared (on in development: a write on it throws there). */
  export function checkShared(on: boolean): void;
  /** `emit(client, message)`: what the core says to each client; `onFatal`: a bug ended the core; `loadSqlite`: its databases;
   *  `onReport`: an error it goes on after, for error tracking. */
  export function startWeb(emit: (client: number, message: unknown) => void, testChannel: boolean, loadIroh: () => Promise<IrohModule>, onFatal: (reason: string, error: unknown) => void, loadSqlite: () => Promise<WasmSqlite>, modules?: readonly unknown[], onReport?: (error: Error) => void): Promise<WebCore>;
}
