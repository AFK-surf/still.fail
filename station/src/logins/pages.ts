// A login's page in the station's own browser (docs/remote-login.md, 在 station 的浏览器中登录): a person who would
// rather not do a login's browser step on their own device (or whose device cannot: a web page takes no loopback
// callback) has the station open the page in a tab of its browser, and drives that tab from their app (a screen,
// docs/remote-screens.md). The page is the one the login command opened: one that comes back to a loopback port comes
// back to the command on this machine, with nothing to relay or paste. The tab is the login's, by a key of its own
// (`machine:<id>`, `profile:<id>`): kept while the login goes on (a person who went back finds it again), closed as it
// ends; a person closing it themselves is heard, and the login told again.
import { log } from "../ops/log.ts";

/// What of the station's browser the logins use (browser/browser.ts StationBrowser).
export type PagesBrowser = {
  available(): boolean;
  openTab(url: string): Promise<string>;
  hasTab(targetId: string): boolean;
  front(targetId: string): Promise<void>;
  closeTab(targetId: string): Promise<void>;
};

/// The screen a tab of the station's browser is (browser/tabs.ts).
export const tabScreen = (targetId: string) => `browser:${targetId}`;

export class LoginPages {
  readonly #browser: PagesBrowser;
  /// The tab open for each login, by its key.
  readonly #tabs = new Map<string, string>();
  readonly #listeners = new Set<(key: string) => void>();
  /// Tabs being opened, by key: asked again meanwhile, the same one.
  readonly #opening = new Map<string, Promise<string>>();

  /// `watch`: hears each time the station's screens change (a tab came or went).
  constructor(browser: PagesBrowser, watch: (changed: () => void) => () => void) {
    this.#browser = browser;
    watch(() => {
      for (const [key, id] of [...this.#tabs]) {
        if (this.#browser.hasTab(id)) continue;
        this.#tabs.delete(key);
        this.#tell(key);
      }
    });
  }

  /// Hears the key of each login whose tab came or went.
  changes(listener: (key: string) => void): () => void {
    this.#listeners.add(listener);
    return () => this.#listeners.delete(listener);
  }

  /// Whether a page can be opened here: the station has a browser.
  can(): boolean {
    return this.#browser.available();
  }

  /// The screen of the tab open for `key`, if one is.
  screenOf(key: string): string | null {
    const id = this.#tabs.get(key);
    return id !== undefined && this.#browser.hasTab(id) ? tabScreen(id) : null;
  }

  /// The tab for `key`: the one open, brought to the front, else a new one at `url`. Its screen.
  async open(key: string, url: string): Promise<string> {
    const had = this.#tabs.get(key);
    if (had !== undefined && this.#browser.hasTab(had)) {
      await this.#browser.front(had).catch(() => {});
      return tabScreen(had);
    }
    const pending = this.#opening.get(key);
    if (pending) return pending;
    const opening = (async () => {
      const id = await this.#browser.openTab(url);
      this.#tabs.set(key, id);
      log.info("logins", "a login's page opened in the station's browser", { login: key });
      this.#tell(key);
      return tabScreen(id);
    })().finally(() => this.#opening.delete(key));
    this.#opening.set(key, opening);
    return opening;
  }

  /// The login ended: its tab closed.
  close(key: string): void {
    const id = this.#tabs.get(key);
    if (id === undefined) return;
    this.#tabs.delete(key);
    void this.#browser.closeTab(id);
    this.#tell(key);
  }

  #tell(key: string) {
    for (const l of this.#listeners) {
      try {
        l(key);
      } catch (e) {
        log.warn("logins", "a listener failed", { error: (e as Error).message });
      }
    }
  }
}
