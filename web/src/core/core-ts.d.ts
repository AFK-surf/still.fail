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
  /** A core in this worker: one client per port. */
  export interface WebCore {
    connect(): number;
    disconnect(client: number): void;
    receive(client: number, message: unknown): void;
  }
  /** `emit(client, message)`: what the core says to each client; `onFatal`: a bug ended the core; `loadSqlite`: its databases. */
  export function startWeb(emit: (client: number, message: unknown) => void, testChannel: boolean, loadIroh: () => Promise<IrohModule>, onFatal: (reason: string, error: unknown) => void, loadSqlite: () => Promise<WasmSqlite>): Promise<WebCore>;
}
