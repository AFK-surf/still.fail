// What the station keeps of the vaults it holds (docs/vault.md): each vault's and each item's latest version, as signed,
// and the box certificates the workspace's app devices published. Ciphertext and signatures only; who may write what is
// checked before (crypto.ts). Its tables beside the store's, in the same database (`CREATE TABLE IF NOT EXISTS`: a
// station from before has none, and one from before opens this one's database as it was).
import type { DatabaseSync } from "node:sqlite";
import type { BoxCert, Item, Vault } from "./crypto.ts";

const SCHEMA = `
CREATE TABLE IF NOT EXISTS vaults (
  ws TEXT NOT NULL,
  id TEXT NOT NULL,
  seq INTEGER NOT NULL,
  body TEXT NOT NULL,
  PRIMARY KEY (ws, id)
);
CREATE TABLE IF NOT EXISTS vault_items (
  ws TEXT NOT NULL,
  vault TEXT NOT NULL,
  id TEXT NOT NULL,
  version INTEGER NOT NULL,
  body TEXT NOT NULL,
  PRIMARY KEY (ws, vault, id)
);
CREATE TABLE IF NOT EXISTS vault_boxes (
  ws TEXT NOT NULL,
  device TEXT NOT NULL,
  body TEXT NOT NULL,
  PRIMARY KEY (ws, device)
);
`;

const parse = <T>(rows: unknown[]): T[] => rows.map((r) => JSON.parse((r as { body: string }).body) as T);

export class VaultStore {
  readonly #db: DatabaseSync;

  constructor(db: DatabaseSync) {
    this.#db = db;
    db.exec(SCHEMA);
  }

  /// Every vault of a workspace held here, latest versions.
  vaults(ws: string): Vault[] {
    return parse(this.#db.prepare("SELECT body FROM vaults WHERE ws = ? ORDER BY id").all(ws));
  }

  vault(ws: string, id: string): Vault | null {
    return parse<Vault>(this.#db.prepare("SELECT body FROM vaults WHERE ws = ? AND id = ?").all(ws, id))[0] ?? null;
  }

  /// A vault's new version, in place of the one before (checked to follow it). Deleted, its items go with it: sealed
  /// under a key no one holds any more.
  putVault(v: Vault): void {
    this.#db.prepare("INSERT INTO vaults (ws, id, seq, body) VALUES (?, ?, ?, ?) ON CONFLICT (ws, id) DO UPDATE SET seq = excluded.seq, body = excluded.body").run(v.ws, v.id, v.seq, JSON.stringify(v));
    if (v.deleted) this.#db.prepare("DELETE FROM vault_items WHERE ws = ? AND vault = ?").run(v.ws, v.id);
  }

  /// A vault's items, latest versions (deleted ones too: a version saying so).
  items(ws: string, vault: string): Item[] {
    return parse(this.#db.prepare("SELECT body FROM vault_items WHERE ws = ? AND vault = ? ORDER BY id").all(ws, vault));
  }

  item(ws: string, vault: string, id: string): Item | null {
    return parse<Item>(this.#db.prepare("SELECT body FROM vault_items WHERE ws = ? AND vault = ? AND id = ?").all(ws, vault, id))[0] ?? null;
  }

  putItem(i: Item): void {
    this.#db.prepare("INSERT INTO vault_items (ws, vault, id, version, body) VALUES (?, ?, ?, ?, ?) ON CONFLICT (ws, vault, id) DO UPDATE SET version = excluded.version, body = excluded.body").run(i.ws, i.vault, i.id, i.version, JSON.stringify(i));
  }

  /// The box certificates published in a workspace, one per device (its latest).
  boxes(ws: string): BoxCert[] {
    return parse(this.#db.prepare("SELECT body FROM vault_boxes WHERE ws = ? ORDER BY device").all(ws));
  }

  box(ws: string, device: string): BoxCert | null {
    return parse<BoxCert>(this.#db.prepare("SELECT body FROM vault_boxes WHERE ws = ? AND device = ?").all(ws, device))[0] ?? null;
  }

  putBox(cert: BoxCert): void {
    this.#db.prepare("INSERT INTO vault_boxes (ws, device, body) VALUES (?, ?, ?) ON CONFLICT (ws, device) DO UPDATE SET body = excluded.body").run(cert.ws, cert.device, JSON.stringify(cert));
  }
}

const made = new WeakMap<DatabaseSync, VaultStore>();

/// The vault store of a database: one per database, whoever asks (the vault's routes, the keeper's).
export function vaultStore(db: DatabaseSync): VaultStore {
  let s = made.get(db);
  if (!s) made.set(db, (s = new VaultStore(db)));
  return s;
}
