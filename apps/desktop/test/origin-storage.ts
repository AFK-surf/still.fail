// Run with Electron against a temporary userData directory; never against an installed app's data.
import { app, BrowserWindow, protocol } from "electron";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { exportOriginStorage, importOriginStorage } from "../src/origin-storage";
const dir = mkdtempSync(join(tmpdir(), "stillfail-origin-test-"));
app.setPath("userData", dir);
protocol.registerSchemesAsPrivileged([{ scheme: "app", privileges: { standard: true, secure: true } }]);
void app.whenReady().then(async () => {
  protocol.handle("app", () => new Response("<!doctype html>"));
  const old = new BrowserWindow({ show: false, webPreferences: { sandbox: true } });
  const next = new BrowserWindow({ show: false, webPreferences: { sandbox: true } });
  try {
    await old.loadURL("app://ember/");
    await next.loadURL("app://stillfail/");
    await old.webContents.executeJavaScript(`(async () => {
      localStorage.setItem('ember.theme', 'dark');
      localStorage.setItem('stillfail.draft', 'unsent text');
      const db = await new Promise((resolve, reject) => {
        const r = indexedDB.open('stillfail-core', 2);
        r.onupgradeneeded = () => { r.result.createObjectStore('values'); r.result.createObjectStore('records'); };
        r.onsuccess = () => resolve(r.result); r.onerror = () => reject(r.error);
      });
      await new Promise((resolve, reject) => {
        const tx = db.transaction(['values', 'records'], 'readwrite');
        tx.objectStore('values').put(new Uint8Array([0, 255, 12]), 'credentials');
        tx.objectStore('records').put(new Uint8Array([3, 4]), ['chats', 'one']);
        tx.oncomplete = resolve; tx.onabort = () => reject(tx.error);
      }); db.close();
    })()`);
    const snapshot = await old.webContents.executeJavaScript(`(${exportOriginStorage.toString()})()`);
    assert.equal(snapshot.databases.length, 1);
    await next.webContents.executeJavaScript(`localStorage.setItem('ember.theme', 'light')`);
    const copy = () => next.webContents.executeJavaScript(`(${importOriginStorage.toString()})(${JSON.stringify(snapshot)})`);
    await copy();
    const moved = await next.webContents.executeJavaScript(`(${exportOriginStorage.toString()})()`);
    assert.deepEqual(moved.databases, snapshot.databases);
    assert.equal(new Map(moved.local).get('stillfail.draft'), 'unsent text');
    assert.equal(new Map(moved.local).get('ember.theme'), 'light', 'existing target wins');
    assert.deepEqual(await old.webContents.executeJavaScript(`(${exportOriginStorage.toString()})()`), snapshot, 'source remains a rollback copy');
    await next.webContents.executeJavaScript(`localStorage.removeItem('stillfail.draft')`);
    await copy();
    assert.equal(await next.webContents.executeJavaScript(`localStorage.getItem('stillfail.draft')`), null, 'retry must not resurrect deleted data');
    console.log('PASS: real Electron origin migration, binary DB rows, settings, rollback source and idempotency');
  } catch (error) { console.error(error); process.exitCode = 1; }
  finally { old.destroy(); next.destroy(); app.quit(); }
});
app.on("will-quit", () => { rmSync(dir, { recursive: true, force: true }); });
