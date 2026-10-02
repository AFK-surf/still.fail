import type { useConnectFlow } from "../connect-flow.ts";
// A connect's Slack app, edited from ember: name, description, colour, icon and
// permissions are written into the app's manifest with the workspace's app
// configuration token. When permissions change, Slack asks a person to approve
// them; that is the only step left in Slack.
import { useStation } from "../station.tsx";
import { Check, External, ImageUpload, ShieldCheck } from "../icons.tsx";
import { useEffect, useRef, useState } from "react";
import { core, useTopic } from "../core/react.ts";
import { useAction, useApi, type Buddy, type Connect, type SlackAppLinks, type SlackAppSettings, type SlackAppView, type SlackGroup } from "../api.ts";
import { useToast } from "../toast.tsx";
import { Button, Dialog, Field, ICON, Section, Tip } from "../ui.tsx";
import * as css from "./SlackApp.css.ts";
import * as shellCss from "../styles/shell.css.ts";
import * as controlsCss from "../styles/controls.css.ts";
import * as pagesCss from "../styles/pages.css.ts";
import * as chatCss from "../styles/chat.css.ts";
import * as modelCss from "../ModelTriple.css.ts";
import * as additionsCss from "../styles/additions.css.ts";

import { NAME } from "../channel.ts";
import { t } from "../i18n.ts";
/** Permission groups in plain words; mirrors SLACK_GROUPS on the server. */
/** A group's words, read in the language at the time. */
const group = (key: string) => ({
  get label() { return t(`web-pages.slackApp.group.${key}`); },
  get description() { return t(`web-pages.slackApp.group.${key}.description`); },
});
const GROUPS: Record<SlackGroup, { label: string; description: string }> = {
  base: group("base"),
  public: group("public"),
  dm: group("dm"),
  customize: group("customize"),
  files: group("files"),
  reactions: group("reactions"),
  channels: group("channels"),
  people: group("people"),
  extras: group("extras"),
  canvases: group("canvases"),
  lists: group("lists"),
  topics: group("topics"),
  usergroups: group("usergroups"),
  search: group("search"),
  connect: group("connect"),
  more: group("more"),
};

/** The groups in sections, as the form shows them. */
const SECTIONS: { title: string; groups: SlackGroup[] }[] = [
  { get title() { return t("web-pages.slackApp.section.messages"); }, groups: ["base", "public", "dm", "customize", "reactions"] },
  { get title() { return t("web-pages.slackApp.section.channels"); }, groups: ["channels", "topics", "connect"] },
  { get title() { return t("web-pages.slackApp.section.files"); }, groups: ["files", "canvases", "lists"] },
  { get title() { return t("web-pages.slackApp.section.people"); }, groups: ["people", "usergroups", "search"] },
  { get title() { return t("web-pages.slackApp.section.other"); }, groups: ["extras", "more"] },
];

/**
 * The connect's Slack app, folded (it is changed now and then): its name, icon and permissions, edited here and written
 * into the app's manifest with the viewer's configuration token; without one, a way to add it, in a dialog.
 */
export function SlackAppSection({ connect }: { connect: Connect }) {
  const station = useStation();
  // Read from Slack through the station; the core reads it again after a write to the connect.
  const app = useTopic<SlackAppView>({ topic: "slackApp", station: station.address, connect: connect.id });
  const [adding, setAdding] = useState(false);
  const saved = () => {};
  const links = app.value?.links;
  return (
    <details className={css.appFold}>
      <summary>
        <span className={css.appFoldTitle}>Slack app</span>
        <span className={shellCss.muted}>{t("web-pages.slackApp.foldNote")}</span>
      </summary>
      <div className={css.appFoldBody}>
        {app.error ? <p className={controlsCss.fieldError}>{app.error.message}</p>
          : !app.value ? <p className={shellCss.muted}>{t("web-pages.slackApp.loading")}</p>
          : app.value.state === "no_app" ? <p className={shellCss.muted}>{app.value.error ? t("web-pages.slackApp.noApp", { error: app.value.error }) : t("web-pages.slackApp.notConnected")}</p>
          : app.value.state === "no_config_token" ? (
            <div className={`${pagesCss.card} ${pagesCss.cardRow}`}>
              <span className={pagesCss.cardRowText}><span>{t("web-pages.slackApp.needsToken")}</span><span className={shellCss.muted}>{t("web-pages.slackApp.needsTokenNote")}</span></span>
              <Button onClick={() => setAdding(true)}>{t("web-pages.slackApp.addToken")}</Button>
            </div>
          )
          : app.value.state === "error" ? (
            <div className={`${pagesCss.card} ${pagesCss.cardRow}`}>
              <span className={`${pagesCss.cardRowText} ${controlsCss.fieldError}`}>{t("web-pages.slackApp.readFailed", { error: app.value.error ?? "" })}</span>
              <Button onClick={() => setAdding(true)}>{t("web-pages.slackApp.replaceToken")}</Button>
            </div>
          )
          : <AppForm key={JSON.stringify(app.value.settings)} connect={connect} settings={app.value.settings} links={app.value.links} onSaved={saved} />}
        {links && <a className={`${chatCss.textButton} ${css.appFoldLink}`} href={links.settings} target="_blank" rel="noopener">{t("web-pages.slackApp.openInSlack")}</a>}
      </div>
      <Dialog open={adding} onClose={() => setAdding(false)} wide title={t("web-pages.slackApp.addTokenTitle")}>
        <ConfigTokenForm onSaved={() => setAdding(false)} />
      </Dialog>
    </details>
  );
}

/**
 * Adds a Slack workspace's app configuration token (by its refresh token); `onSaved` gets the workspace. Pasting the
 * refresh token saves it at once; pasting the access token Slack shows above it says which one is wanted.
 */
export function ConfigTokenForm({ replacing, onSaved, flow }: { replacing?: boolean; onSaved(teamId: string): void; flow?: ReturnType<typeof useConnectFlow> }) {
  const api = useApi();
  const toast = useToast();
  const [token, echo] = useState("");
  const legacySave = useAction((value: string) => api.addConfigToken(value), ({ teamId }) => { setToken(""); toast(t("web-pages.slackApp.tokenAdded")); onSaved(teamId); });
  const setToken = (config: string) => { echo(config); flow?.edit({ config }); };
  const save = flow ? { busy: flow.busy, error: flow.error ? new Error(flow.error) : null, run: (_value: string) => flow.act("config") } : legacySave;
  const wrong = flow ? flow.view?.configError : token.startsWith("xoxe.xoxp-") ? t("web-pages.slackApp.accessToken")
    : token && !token.startsWith("xoxe-") ? t("web-pages.slackApp.refreshPrefix") : null;
  const ready = flow ? flow.view?.configReady : token.startsWith("xoxe-1-") && token.length > 20;
  return (
    <ol className={css.tokenGuide}>
      <li>
        <strong>{t("web-pages.slackApp.step1")}</strong>
        <span className={shellCss.muted}>{t("web-pages.slackApp.step1Note")}</span>
        <a className={`${controlsCss.btn} ${controlsCss.btnPrimary}`} href="https://api.slack.com/apps" target="_blank" rel="noopener"><External {...ICON} />{t("web-pages.slackApp.openApps")}</a>
      </li>
      <li>
        <strong>{t("web-pages.slackApp.step2")}</strong>
        <span className={shellCss.muted}>{t("web-pages.slackApp.step2Note")}</span>
      </li>
      <li>
        <strong>{t("web-pages.slackApp.step3")}</strong>
        <span className={shellCss.muted}>{t("web-pages.slackApp.step3Note", { name: NAME })}</span>
        <div className={additionsCss.inputRow}>
          <input className={`${controlsCss.input} ${shellCss.mono}`} type="password" autoComplete="off" spellCheck={false} value={token} aria-label="Refresh Token"
            onChange={(e) => setToken(e.target.value.trim())}
            onPaste={(e) => {
              const pasted = e.clipboardData.getData("text").trim();
              if (pasted.startsWith("xoxe-1-") && pasted.length > 20) { e.preventDefault(); setToken(pasted); void save.run(pasted); }
            }}
            placeholder="xoxe-1-…" />
          <Button variant="primary" disabled={!ready} busy={save.busy} onClick={() => void save.run(token)}>{replacing ? t("web-pages.slackApp.useThis") : t("web-pages.slackApp.add")}</Button>
        </div>
        {(wrong || save.error) && <p className={controlsCss.fieldError} role="alert">{wrong ?? save.error?.message}</p>}
      </li>
    </ol>
  );
}

/**
 * Crops an image to a centred square and scales it to 1024 px, the size Slack wants (512–2000), as a JPEG: small enough
 * to send (a PNG of a rich picture is megabytes).
 */
export async function toIcon(file: File): Promise<string> {
  const url = URL.createObjectURL(file);
  try {
    const image = new Image();
    image.src = url;
    await image.decode();
    const side = Math.min(image.naturalWidth, image.naturalHeight);
    const canvas = document.createElement("canvas");
    canvas.width = canvas.height = 1024;
    const g = canvas.getContext("2d")!;
    // A JPEG has no transparency: what was clear is white, not black.
    g.fillStyle = "#FFFFFF";
    g.fillRect(0, 0, 1024, 1024);
    g.drawImage(image, (image.naturalWidth - side) / 2, (image.naturalHeight - side) / 2, side, side, 0, 0, 1024, 1024);
    return canvas.toDataURL("image/jpeg", 0.9);
  } finally {
    URL.revokeObjectURL(url);
  }
}

/**
 * An avatar to start from: a drawing on a background colour of its own (a mono mark is drawn white). `thumb`: a small
 * copy for the picker, when the drawing is a large picture.
 */
export interface Avatar { id: string; label: string; src: string; thumb?: string; bg: string; mono?: boolean }

const BASE = import.meta.env.BASE_URL;

/** The model makers' marks, each on its own colour. */
export const MAKERS: Avatar[] = [
  { id: "anthropic", label: "Anthropic", src: `${BASE}models/anthropic.svg`, bg: "#D97757", mono: true },
  { id: "openai", label: "OpenAI", src: `${BASE}models/openai.svg`, bg: "#0D0D0D", mono: true },
  { id: "gemini", label: "Gemini", src: `${BASE}models/gemini.svg`, bg: "#FFFFFF" },
  { id: "deepseek", label: "DeepSeek", src: `${BASE}models/deepseek.svg`, bg: "#FFFFFF" },
  { id: "qwen", label: "Qwen", src: `${BASE}models/qwen.svg`, bg: "#FFFFFF" },
  { id: "zhipu", get label() { return t("web-pages.slackApp.maker.zhipu"); }, src: `${BASE}models/zhipu.svg`, bg: "#FFFFFF" },
  { id: "kimi", label: "Kimi", src: `${BASE}models/kimi.svg`, bg: "#0D0D0D", mono: true },
  { id: "minimax", label: "MiniMax", src: `${BASE}models/minimax.svg`, bg: "#FFFFFF" },
  { id: "xai", label: "xAI", src: `${BASE}models/xai.svg`, bg: "#0D0D0D", mono: true },
];

/**
 * still.fail's buddy at the jobs a bot is made for, so people tell bots apart by what they do: the list is the core's
 * (`buddies`, from web/public/avatars/index.json), each drawn from <id>.webp (1024 px, for the icon) with a small
 * <id>.thumb.webp (128 px, for the list). A core from before it has none to offer.
 */
let buddies: Promise<Avatar[]> | null = null;
function loadBuddies(): Promise<Avatar[]> {
  buddies ??= core().call("buddies").then((list) => (list as Buddy[]).map((a) => ({ ...a, src: `${BASE}avatars/${a.id}.webp`, thumb: `${BASE}avatars/${a.id}.thumb.webp` })), () => []);
  return buddies;
}
export function useBuddies(): Avatar[] | null {
  const [list, setList] = useState<Avatar[] | null>(null);
  useEffect(() => { void loadBuddies().then(setList); }, []);
  return list;
}

/** An avatar as the app's icon (a JPEG, its colour filling it): 1024 px, its colour behind it, the drawing centred (a maker's mark smaller, in white when mono). */
export async function renderAvatar(avatar: Avatar, bg: string, maker: boolean): Promise<string> {
  const image = new Image();
  image.src = avatar.src;
  await image.decode();
  const canvas = document.createElement("canvas");
  canvas.width = canvas.height = 1024;
  const g = canvas.getContext("2d")!;
  g.fillStyle = bg;
  g.fillRect(0, 0, 1024, 1024);
  if (maker) {
    // A maker's mark: smaller, centred, and white when mono.
    const size = 560;
    const at = (1024 - size) / 2;
    if (avatar.mono) {
      const mark = document.createElement("canvas");
      mark.width = mark.height = size;
      const m = mark.getContext("2d")!;
      m.drawImage(image, 0, 0, size, size);
      m.globalCompositeOperation = "source-in";
      m.fillStyle = "#FFFFFF";
      m.fillRect(0, 0, size, size);
      g.drawImage(mark, at, at);
    } else {
      g.drawImage(image, at, at, size, size);
    }
  } else {
    // A buddy: what is drawn (its margins trimmed) as large as fits, 92% of the icon.
    const [x, y, w, h] = drawnBox(image);
    const scale = (1024 * 0.92) / Math.max(w, h);
    g.drawImage(image, x, y, w, h, (1024 - w * scale) / 2, (1024 - h * scale) / 2, w * scale, h * scale);
  }
  return canvas.toDataURL("image/jpeg", 0.9);
}

/** Where a picture has anything drawn (not transparent): x, y, width, height in its own pixels. */
function drawnBox(image: HTMLImageElement): [number, number, number, number] {
  const size = 256;
  const canvas = document.createElement("canvas");
  canvas.width = canvas.height = size;
  const g = canvas.getContext("2d")!;
  g.drawImage(image, 0, 0, size, size);
  const { data } = g.getImageData(0, 0, size, size);
  let left = size, top = size, right = -1, bottom = -1;
  for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
    if (data[(y * size + x) * 4 + 3]! > 16) { left = Math.min(left, x); right = Math.max(right, x); top = Math.min(top, y); bottom = Math.max(bottom, y); }
  }
  if (right < 0) return [0, 0, image.naturalWidth, image.naturalHeight];
  const k = image.naturalWidth / size;
  return [left * k, top * k, (right - left + 1) * k, (bottom - top + 1) * k];
}

/** The colour an uploaded picture sits on best: the average of its edge. */
export function edgeColour(dataUrl: string): Promise<string> {
  return new Promise((resolve) => {
    const image = new Image();
    image.onload = () => {
      const canvas = document.createElement("canvas");
      canvas.width = canvas.height = 32;
      const g = canvas.getContext("2d")!;
      g.drawImage(image, 0, 0, 32, 32);
      const { data } = g.getImageData(0, 0, 32, 32);
      let r = 0, gr = 0, b = 0, n = 0;
      for (let i = 0; i < 32; i++) for (const [x, y] of [[i, 0], [i, 31], [0, i], [31, i]] as const) {
        const at = (y * 32 + x) * 4;
        r += data[at]!; gr += data[at + 1]!; b += data[at + 2]!; n++;
      }
      const hex = (v: number) => Math.round(v / n).toString(16).padStart(2, "0");
      resolve(`#${hex(r)}${hex(gr)}${hex(b)}`.toUpperCase());
    };
    image.onerror = () => resolve("#7A2E0E");
    image.src = dataUrl;
  });
}

/** What a new app starts as: every permission on; its colour and icon come from its first avatar. */
export const NEW_APP: SlackAppSettings = {
  name: NAME, displayName: NAME, description: `Coding agent in your threads (${NAME})`, longDescription: "", backgroundColor: "#F3E3D3",
  groups: Object.fromEntries((Object.keys(GROUPS) as SlackGroup[]).map((g) => [g, true])) as Record<SlackGroup, boolean>,
};

/**
 * An app's look and permissions, by how often each is changed: its avatar and name up front (an avatar picked from
 * still.fail's buddies or the model makers, or uploaded), then its colour, which follows the avatar until it is set by
 * hand (and can go back); the description on a line; permissions folded. One name, which is the name in messages too.
 * `fresh`: a new app, which starts as the general helper.
 */
export function AppFields({ settings, onChange, icon, onIcon, fresh }: {
  settings: SlackAppSettings; onChange(settings: SlackAppSettings): void; icon: string | null; onIcon(icon: string | null, error: string | null): void; fresh?: boolean;
}) {
  const file = useRef<HTMLInputElement>(null);
  const buddyList = useBuddies();
  const [picked, setPicked] = useState<{ avatar: Avatar; maker: boolean } | { upload: true; bg: string } | null>(null);
  // The colour follows the avatar picked, until it is set by hand here (an app's colour so far is no such choice).
  const [colourSet, setColourSet] = useState(false);
  const set = <K extends keyof SlackAppSettings>(key: K, value: SlackAppSettings[K]) => onChange({ ...settings, [key]: value });
  // The name in messages is the app's name (setting it apart is for Slack's own settings).
  const setName = (name: string) => onChange({ ...settings, name, displayName: name });
  const recommended = picked ? ("upload" in picked ? picked.bg : picked.avatar.bg) : null;
  const draw = (p: typeof picked, bg: string) => {
    if (p && !("upload" in p)) void renderAvatar(p.avatar, bg, p.maker).then((i) => onIcon(i, null), () => onIcon(null, t("web-pages.slackApp.drawFailed")));
  };
  const pick = (avatar: Avatar, maker: boolean, next = settings) => {
    const p = { avatar, maker };
    setPicked(p);
    const bg = colourSet ? next.backgroundColor : avatar.bg;
    if (bg !== next.backgroundColor) onChange({ ...next, backgroundColor: bg });
    draw(p, bg);
  };
  const colour = (bg: string, byHand: boolean) => {
    setColourSet(byHand);
    set("backgroundColor", bg);
    if (/^#[0-9a-fA-F]{6}$/.test(bg)) draw(picked, bg);
  };
  // A new app starts as the general helper (else the first avatar), on its colour.
  const started = useRef(false);
  useEffect(() => {
    if (!fresh || started.current || icon || !buddyList?.length) return;
    started.current = true;
    pick(buddyList.find((a) => a.id === "general-helper") ?? buddyList[0]!, false);
  });
  const on = (Object.keys(GROUPS) as SlackGroup[]).filter((g) => settings.groups[g]).length;
  const isPicked = (a: Avatar) => picked !== null && !("upload" in picked) && picked.avatar.id === a.id;
  const tile = (a: Avatar, maker: boolean) => (
    <Tip key={a.id} label={a.label}><button type="button" className={css.avatarTile} data-picked={isPicked(a) || undefined} aria-label={a.label}
      style={{ background: a.bg }} onClick={() => pick(a, maker)}>
      <img src={a.thumb ?? a.src} alt="" loading="lazy" data-mono={a.mono || undefined} data-maker={maker || undefined} />
    </button></Tip>
  );
  return (
    <>
      <div className={css.appLook}>
        <Tip label={t("web-pages.slackApp.upload")}><button type="button" className={css.appAvatar} onClick={() => file.current?.click()} style={{ background: settings.backgroundColor || undefined }}>
          {icon ? <img src={icon} alt={t("web-pages.slackApp.avatar")} /> : <span className={css.appAvatarEmpty}><ImageUpload {...ICON} size={20} />{fresh ? t("web-pages.slackApp.uploadShort") : t("web-pages.slackApp.keep")}</span>}
        </button></Tip>
        <input ref={file} type="file" accept="image/png,image/jpeg,image/webp" hidden onChange={(e) => {
          const f = e.target.files?.[0];
          e.target.value = "";
          if (f) void toIcon(f).then(async (i) => {
            const bg = await edgeColour(i);
            setPicked({ upload: true, bg });
            onIcon(i, null);
            if (!colourSet) set("backgroundColor", bg);
          }, () => onIcon(null, t("web-pages.slackApp.readImageFailed")));
        }} />
        <div className={css.appLookMain}>
          <input id="app-name" className={`${controlsCss.input} ${css.appNameInput}`} aria-label={t("web-pages.settings.workspace.name")} placeholder={t("web-pages.settings.workspace.name")} value={settings.name} onChange={(e) => setName(e.target.value)} />
          <input id="app-desc" className={`${controlsCss.input} ${css.appDesc}`} aria-label={t("web-pages.slackApp.description")} maxLength={140} placeholder={t("web-pages.slackApp.descriptionPlaceholder")} value={settings.description} onChange={(e) => set("description", e.target.value)} />
          <div className={css.appColour}>
            <input type="color" className={css.colorSwatch} aria-label={t("web-pages.slackApp.colour")} value={/^#[0-9a-fA-F]{6}$/.test(settings.backgroundColor) ? settings.backgroundColor : "#7a2e0e"}
              onChange={(e) => colour(e.target.value.toUpperCase(), true)} />
            <input className={`${controlsCss.input} ${shellCss.mono} ${css.appColourHex}`} aria-label={t("web-pages.slackApp.colourHex")} spellCheck={false} value={settings.backgroundColor} onChange={(e) => colour(e.target.value, true)} />
            {recommended && colourSet && recommended.toLowerCase() !== settings.backgroundColor.toLowerCase() && (
              <button type="button" className={chatCss.textButton} onClick={() => colour(recommended, false)}>{t("web-pages.slackApp.recommended")}</button>
            )}
          </div>
        </div>
      </div>
      <div className={css.avatarPicker} aria-label={t("web-pages.slackApp.avatar")}>
        {(buddyList ?? []).map((a) => tile(a, false))}
        {MAKERS.map((a) => tile(a, true))}
      </div>
      <details className={css.appPerms}>
        <summary>
          {t("web-pages.slackApp.permissions", { on, all: Object.keys(GROUPS).length })}
          {on < Object.keys(GROUPS).length && (
            <button type="button" className={`${controlsCss.textToggle} ${css.permAll}`}
              onClick={(e) => { e.preventDefault(); set("groups", Object.fromEntries(Object.keys(GROUPS).map((g) => [g, true])) as Record<SlackGroup, boolean>); }}>
              {t("web-pages.slackApp.allOn")}
            </button>
          )}
        </summary>
        <div className={css.permSections}>
          {SECTIONS.map(({ title, groups }) => {
            const all = groups.every((g) => settings.groups[g]);
            return (
              <div key={title} className={modelCss.poolSeries}>
                <div className={modelCss.poolSeriesHead}>
                  <h4>{title}</h4>
                  <button type="button" className={controlsCss.textToggle}
                    onClick={() => set("groups", { ...settings.groups, ...Object.fromEntries(groups.map((g) => [g, g === "base" || !all])) })}>
                    {all ? t("web-pages.settings.members.none") : t("web-pages.settings.members.all")}
                  </button>
                </div>
                <ul className={css.permGrid}>
                  {groups.map((g) => (
                    <li key={g}>
                      {g === "base" ? (
                        // Always on, no choice: a tick without a box.
                        <Tip label={GROUPS[g].description}><span className={`${chatCss.modelPoolItem} ${css.permFixed}`} data-on>
                          <Check size={13} strokeWidth={2.4} />
                          <span>{GROUPS[g].label}</span>
                        </span></Tip>
                      ) : (
                        <Tip label={GROUPS[g].description}><label className={chatCss.modelPoolItem} data-on={settings.groups[g] || undefined}>
                          <input type="checkbox" checked={settings.groups[g] ?? false}
                            onChange={(e) => set("groups", { ...settings.groups, [g]: e.target.checked })} />
                          <span>{GROUPS[g].label}</span>
                        </label></Tip>
                      )}
                    </li>
                  ))}
                </ul>
              </div>
            );
          })}
        </div>
      </details>
    </>
  );
}

function AppForm({ connect, settings, links, onSaved }: { connect: Connect; settings: SlackAppSettings; links: SlackAppLinks; onSaved(): void }) {
  const api = useApi();
  const toast = useToast();
  const [draft, setDraft] = useState(settings);
  const [icon, setIcon] = useState<string | null>(null);
  const [iconError, setIconError] = useState<string | null>(null);
  const [approve, setApprove] = useState(false);
  useEffect(() => setDraft(settings), [settings]);

  const changed = (Object.keys(settings) as (keyof SlackAppSettings)[]).filter((k) => JSON.stringify(settings[k]) !== JSON.stringify(draft[k]));
  const dirty = changed.length > 0 || icon !== null;
  // Changed permissions are approved in Slack. The browser lets a tab open only while the click is being handled, and
  // the station's answer comes later: a tab is opened on the click, when the permissions change, and sent to Slack's
  // page once the app is written (closed if it went wrong). The desktop app opens pages in the system browser, from
  // any time.
  const approval = useRef<Window | null>(null);
  const apply = useAction(() => api.putSlackApp(connect.id, {
    ...Object.fromEntries(changed.map((k) => [k, draft[k]])),
    ...(icon ? { icon } : {}),
  }), (result) => {
    setIcon(null);
    setIconError(result.iconError);
    setApprove(result.permissionsUpdated);
    const tab = approval.current;
    approval.current = null;
    if (result.permissionsUpdated && tab) tab.location.href = links.install;
    else if (result.permissionsUpdated && window.stillfailDesktop) window.open(links.install, "_blank");
    else tab?.close();
    toast(result.permissionsUpdated ? t("web-pages.slackApp.updatedApprove") : t("web-pages.slackApp.updated"));
    onSaved();
  });
  const save = () => {
    if (changed.includes("groups") && !window.stillfailDesktop) {
      const tab = window.open("", "_blank");
      if (tab) {
        tab.opener = null;
        tab.document.title = t("web-pages.slackApp.updatingTitle");
        tab.document.body.style.cssText = "font: 15px system-ui, sans-serif; color: #666; display: grid; place-items: center; height: 100vh; margin: 0";
        tab.document.body.textContent = t("web-pages.slackApp.updating");
      }
      approval.current = tab;
    }
    void apply.run().then((done) => { if (done === undefined) { approval.current?.close(); approval.current = null; } });
  };

  return (
    <div className={`${pagesCss.card} slack-app`}>
      {approve && (
        <div className={additionsCss.callout} data-tone="blue" role="status">
          <ShieldCheck {...ICON} />
          <span>{t("web-pages.slackApp.approveNote")}</span>
          <a className={`${controlsCss.btn} ${controlsCss.btnPrimary}`} href={links.install} target="_blank" rel="noopener" onClick={() => setApprove(false)}>{t("web-pages.slackApp.approve")}</a>
        </div>
      )}
      <AppFields settings={draft} onChange={setDraft} icon={icon} onIcon={(i, e) => { setIcon(i); setIconError(e); }} />
      {iconError && <p className={controlsCss.fieldError} role="alert">{iconError}</p>}
      {apply.error && <p className={controlsCss.fieldError} role="alert">{apply.error.message}</p>}
      <div className={pagesCss.cardActions}>
        {dirty && <Button variant="ghost" onClick={() => { setDraft(settings); setIcon(null); }}>{t("web-pages.slackApp.revert")}</Button>}
        <Button variant="primary" disabled={!dirty} busy={apply.busy} onClick={save}>{t("web-pages.slackApp.apply")}</Button>
      </div>
    </div>
  );
}
