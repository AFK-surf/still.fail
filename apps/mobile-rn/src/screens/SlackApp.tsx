// A connect's Slack app, edited from here (the desktop's web/src/pages/SlackApp.tsx): its name, description, colour,
// icon and permissions are written into the app's manifest with the viewer's app configuration token for its Slack
// workspace. When permissions change, Slack asks a person to approve them; that is the only step left in Slack. A new
// app's look (a picture picked from still.fail's buddies or the model makers, or uploaded, on its colour) is set the same
// way when it is made (Connects.tsx → NewConnectScreen, as web/src/mobile/Connects.tsx → AppLook).
// (The Android app's screens/SlackApp.kt.)
import { useEffect, useState, useSyncExternalStore } from "react";
import { BackHandler, Image, Linking, Pressable, ScrollView, View, type ImageSourcePropType } from "react-native";
import { SvgXml } from "react-native-svg";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { core, useTopic } from "../../../../web/src/core/react.ts";
import type { Buddy } from "../../../../web/src/core/shapes.ts";
import { useDoing } from "../../../../web/src/doing.ts";
import { app } from "../AppState";
import { APP_NAME } from "../build";
import { t } from "../i18n";
import { Button, Field } from "../ui/Controls";
import { Drawables, type DrawableName } from "../ui/Drawables";
import { Drawing } from "../ui/Drawing";
import { Icon, Icons } from "../ui/Icon";
import { NavBar } from "../ui/Parts";
import { Smooth } from "../ui/Smooth";
import { T } from "../ui/Text";
import { useC, withAlpha } from "../ui/Theme";
import { WaitShape, Waiting } from "../ui/Waiting";
import type { ConnectFlow } from "./ConnectFlow";
import { SecretField, Steps } from "./Connects";

// ── what Slack has ─────────────────────────────────────────────────────

export interface SlackAppLinksView { settings: string; install: string; appToken: string; oauth: string }

export interface SlackAppSettings {
  name: string; displayName: string; description: string; longDescription: string;
  backgroundColor: string; groups: Record<string, boolean>;
}

/** A connect's Slack app as the `slackApp` topic has it: no_app | no_config_token | ok | error. */
export interface SlackAppView { state: string; appId: string | null; links: SlackAppLinksView | null; settings: SlackAppSettings | null; error: string | null }

const str = (v: unknown) => (typeof v === "string" ? v : "");
const obj = (v: unknown) => (v != null && typeof v === "object" ? (v as Record<string, unknown>) : null);

/** The settings as Kotlin's serializer reads them: what the station left out is its default. */
function settingsOf(v: unknown): SlackAppSettings | null {
  const o = obj(v);
  if (o == null) return null;
  const groups: Record<string, boolean> = {};
  for (const [g, on] of Object.entries(obj(o.groups) ?? {})) if (typeof on === "boolean") groups[g] = on;
  return { name: str(o.name), displayName: str(o.displayName), description: str(o.description), longDescription: str(o.longDescription), backgroundColor: str(o.backgroundColor), groups };
}

/** The topic's value as Kotlin's serializer reads it (the station's own JSON, with its defaults). */
function slackAppView(v: unknown): SlackAppView | null {
  const o = obj(v);
  if (o == null) return null;
  const l = obj(o.links);
  return {
    state: str(o.state),
    appId: typeof o.appId === "string" ? o.appId : null,
    links: l != null ? { settings: str(l.settings), install: str(l.install), appToken: str(l.appToken), oauth: str(l.oauth) } : null,
    settings: settingsOf(o.settings),
    error: typeof o.error === "string" ? o.error : null,
  };
}

/** The permission groups' ids, in their order (SLACK_GROUP_WORDS', apart so NEW_APP needs no words at load). */
const SLACK_GROUPS = ["base", "public", "dm", "customize", "files", "reactions", "channels", "people", "extras", "canvases", "lists", "topics", "usergroups", "search", "connect", "more"];

/** Permission groups in plain words (web/src/pages/SlackApp.tsx → GROUPS; the station's SLACK_GROUPS), in their order. */
export function SLACK_GROUP_WORDS(): [string, [string, string]][] {
  return SLACK_GROUPS.map((it) => [it, [t(`android-settings.slack.group.${it}`), t(`android-settings.slack.group.${it}.note`)]]);
}

/** Groups that only work as Slack's admins allow, marked so (web/src/pages/SlackApp.tsx → ADMIN, which says why). */
export const SLACK_ADMIN_GROUPS: ReadonlySet<string> = new Set(["connect", "usergroups"]);

/** The groups in sections, as the form shows them (web/src/pages/SlackApp.tsx → SECTIONS). */
export function SLACK_SECTIONS(): [string, string[]][] {
  return [
    [t("android-settings.slack.section.messages"), ["base", "public", "dm", "customize", "reactions"]],
    [t("android-settings.slack.section.channels"), ["channels", "topics", "connect"]],
    [t("android-settings.slack.section.files"), ["files", "canvases", "lists"]],
    [t("android-settings.slack.section.people"), ["people", "usergroups", "search"]],
    [t("android-settings.slack.section.other"), ["extras", "more"]],
  ];
}

/**
 * A Slack app's settings being edited: what its form shows, and what it started as. Kotlin's echoes are Compose state;
 * here they are observed: what shows them reads `version` with useSyncExternalStore (`subscribe`), drawn again when
 * one is set.
 */
export class AppDraft {
  readonly start: SlackAppSettings;
  readonly #onEdit: (settings: Record<string, unknown>) => void;
  #nameEcho: string;
  #descriptionEcho: string;
  #colorEcho: string;
  #groupsEcho: Record<string, boolean>;
  readonly #listeners = new Set<() => void>();
  #version = 0;

  constructor(start: SlackAppSettings, onEdit: (settings: Record<string, unknown>) => void = () => {}) {
    this.start = start;
    this.#onEdit = onEdit;
    this.#nameEcho = start.name;
    this.#descriptionEcho = start.description;
    this.#colorEcho = start.backgroundColor;
    this.#groupsEcho = Object.fromEntries(SLACK_GROUPS.map((g) => [g, start.groups[g] ?? false]));
  }

  subscribe = (l: () => void) => { this.#listeners.add(l); return () => { this.#listeners.delete(l); }; };
  get version() { return this.#version; }
  #changed() { this.#version++; for (const l of this.#listeners) l(); this.#onEdit(this.settings()); }

  get name() { return this.#nameEcho; }
  set name(value: string) { this.#nameEcho = value; this.#changed(); }
  get description() { return this.#descriptionEcho; }
  set description(value: string) { this.#descriptionEcho = value; this.#changed(); }
  get color() { return this.#colorEcho; }
  set color(value: string) { this.#colorEcho = value; this.#changed(); }
  get groups(): Record<string, boolean> { return this.#groupsEcho; }
  set groups(value: Record<string, boolean>) { this.#groupsEcho = value; this.#changed(); }

  /** The settings as the station takes them (the name in messages is the app's name). */
  settings(): Record<string, unknown> {
    return {
      name: this.name.trim(), displayName: this.name.trim(), description: this.description.trim(), longDescription: this.start.longDescription,
      backgroundColor: this.color, groups: { ...this.groups },
    };
  }

  /** Only what changed, for a write to an app that exists. */
  changes(): Record<string, unknown> {
    const out: Record<string, unknown> = {};
    if (this.name.trim() !== this.start.name) { out.name = this.name.trim(); out.displayName = this.name.trim(); }
    if (this.description.trim() !== this.start.description) out.description = this.description.trim();
    if (this.color !== this.start.backgroundColor) out.backgroundColor = this.color;
    if (SLACK_GROUPS.some((g) => this.groups[g] !== (this.start.groups[g] ?? false))) out.groups = { ...this.groups };
    return out;
  }
}

/** What a new app starts as: every permission on; its colour and icon come from its first avatar. */
export const NEW_APP: SlackAppSettings = {
  name: APP_NAME, displayName: APP_NAME, description: `Coding agent in your threads (${APP_NAME})`, longDescription: "", backgroundColor: "#F3E3D3",
  groups: Object.fromEntries(SLACK_GROUPS.map((g) => [g, true])),
};

// ── avatars ────────────────────────────────────────────────────────────

/** A picture to start from: a buddy (assets/avatars/<id>.webp, the web's) or a model maker's mark, on a colour of its own. */
export class AppAvatar {
  constructor(readonly id: string, readonly label: string, readonly bg: string, readonly mark: DrawableName | null = null, readonly mono: boolean = false) {}
}

/** still.fail's buddy at the jobs a bot is made for, so people tell bots apart by what they do (the core's list, `buddies`). */
async function buddies(): Promise<AppAvatar[]> {
  try {
    return ((await core().call("buddies", {})) as Buddy[]).map((it) => new AppAvatar(it.id, it.label, it.bg));
  } catch {
    return [];
  }
}

/** The model makers' marks, each on its own colour (Kotlin's is a getter, for its words). */
function MAKER_AVATARS(): AppAvatar[] {
  return [
    new AppAvatar("anthropic", "Anthropic", "#D97757", "maker_anthropic", true),
    new AppAvatar("openai", "OpenAI", "#0D0D0D", "maker_openai", true),
    new AppAvatar("gemini", "Gemini", "#FFFFFF", "maker_gemini"),
    new AppAvatar("deepseek", "DeepSeek", "#FFFFFF", "maker_deepseek"),
    new AppAvatar("qwen", "Qwen", "#FFFFFF", "maker_qwen"),
    new AppAvatar("zhipu", t("android-settings.slack.zhipu"), "#FFFFFF", "maker_zhipu"),
    new AppAvatar("kimi", "Kimi", "#0D0D0D", "maker_kimi", true),
    new AppAvatar("minimax", "MiniMax", "#FFFFFF", "maker_minimax"),
    new AppAvatar("xai", "xAI", "#0D0D0D", "maker_xai", true),
  ];
}

const HEX = /^#[0-9a-fA-F]{6}$/;

/** A colour as drawn: `hex` when it is one, else `fallback` (Kotlin's 0xFF7A2E0E). */
function parseColor(hex: string, fallback: string = "#7A2E0E"): string {
  return HEX.test(hex) ? hex : fallback;
}

/** A picture drawn here, as the native side would hand it over: where it is (a file, or a data URL) and its size in px. */
interface Bitmap { uri: string; width: number; height: number }
interface Rect { left: number; top: number; right: number; bottom: number }

function native(what: string): never {
  throw new Error(`not in this app yet: ${what}`);
}

/** A picture as Slack takes an icon: a JPEG, as a data URL. */
function dataUrl(bitmap: Bitmap): string {
  // NATIVE: encoding a bitmap as JPEG (quality 90) into "data:image/jpeg;base64,…" (Bitmap.compress) is not in the app.
  return native(`JPEG of ${bitmap.uri}`);
}

/** Where a picture has anything drawn (not transparent), in its own pixels. */
function drawnBox(image: Bitmap): Rect {
  // NATIVE: reading pixels (scaled to 256 × 256, alpha > 16 is drawn, the box scaled back by width / 256; nothing drawn:
  // the whole picture) is not in the app.
  return native(`pixels of ${image.uri}`);
}

/** An avatar as the app's icon: 1024 px, its colour behind it, a buddy as large as fits (92%), a maker's mark smaller (white when mono). */
async function renderAvatar(avatar: AppAvatar, bg: string): Promise<Bitmap> {
  // NATIVE: drawing a 1024 px bitmap is not in the app: filled with parseColor(bg, parseColor(avatar.bg)); a maker's mark
  // (tinted white when mono) at (1024 - 560) / 2, 560 square; else assets/avatars/<id>.webp (not in this app either),
  // its drawnBox scaled by 1024 × 0.92 / max(box's width, height), centred, filtered.
  void drawnBox;
  return native(`icon of ${avatar.id} on ${parseColor(bg, parseColor(avatar.bg))}`);
}

/** A picked picture cropped to a centred square and scaled to 1024 px (Slack wants 512–2000); what was clear is white. */
async function toIcon(uri: string): Promise<Bitmap | null> {
  // NATIVE: decoding the picked picture (sampled down by 2s while its short side / (sample × 2) ≥ 1024), its centred square
  // drawn onto 1024 px of white, is not in the app.
  return native(`icon from ${uri}`);
}

/** The colour a picture sits on best: the average of its edge. */
function edgeColour(bitmap: Bitmap): string {
  // NATIVE: reading pixels (scaled to 32 × 32, the average of its four edges' pixels as #RRGGBB) is not in the app.
  return native(`edge of ${bitmap.uri}`);
}

/** The phone's picture picker, pictures only (Kotlin's PickVisualMedia(ImageOnly)): the one picked, or null. */
async function pickImage(): Promise<string | null> {
  // NATIVE: no picture picker in the app (expo-image-picker or the Photo Picker); nothing is picked meanwhile.
  return null;
}

/** A buddy's small picture (assets/avatars/<id>.thumb.webp), or null when there is none. */
function avatarThumb(id: string): ImageSourcePropType | null {
  // NATIVE: the buddies' pictures (assets/avatars/<id>.webp and .thumb.webp) are not in the RN app; its tile shows its colour.
  void id;
  return null;
}

/** The icon picked for an app: the picture as shown (its uri), and as it goes to Slack. */
export class IconPick {
  constructor(readonly bitmap: string, readonly data: string) {}
}

/**
 * An app's look, as the web's AppLook / AppFields have it: an avatar picked from still.fail's buddies or the model makers,
 * or uploaded, on its colour; the colour follows the avatar until it is set by hand (and can go back). `fresh`: a new
 * app, which starts as the general helper.
 */
export function AppLook({ draft, icon, onIcon, fresh }: { draft: AppDraft; icon: IconPick | null; onIcon: (icon: IconPick | null, error: string | null) => void; fresh: boolean }) {
  const C = useC();
  useSyncExternalStore(draft.subscribe, () => draft.version);
  const [buddyList, setBuddyList] = useState<AppAvatar[]>([]);
  useEffect(() => {
    let live = true;
    void buddies().then((it) => { if (live) setBuddyList(it); });
    return () => { live = false; };
  }, []);
  // What was picked: an avatar (its id), or an upload (its edge's colour).
  const [picked, setPicked] = useState<AppAvatar | null>(null);
  const [uploadBg, setUploadBg] = useState<string | null>(null);
  const [colourSet, setColourSet] = useState(false);
  const recommended = picked?.bg ?? uploadBg;
  const draw = (a: AppAvatar | null, bg: string) => {
    if (a != null) void (async () => {
      try { const b = await renderAvatar(a, bg); onIcon(new IconPick(b.uri, dataUrl(b)), null); } catch { onIcon(null, t("android-settings.slack.drawFailed")); }
    })();
  };
  const pick = (a: AppAvatar) => {
    setPicked(a); setUploadBg(null);
    const bg = colourSet ? draft.color : a.bg;
    draft.color = bg;
    draw(a, bg);
  };
  const colour = (bg: string, byHand: boolean) => {
    setColourSet(byHand);
    draft.color = bg;
    if (HEX.test(bg)) draw(picked, bg);
  };
  // A new app starts as the general helper (else the first avatar), on its colour.
  useEffect(() => {
    if (fresh && icon == null && picked == null) {
      const first = buddyList.find((it) => it.id === "general-helper") ?? buddyList[0];
      if (first != null) pick(first);
    }
  }, [buddyList]);
  const upload = (uri: string | null) => {
    if (uri != null) void (async () => {
      let b: Bitmap | null;
      try { b = await toIcon(uri); } catch { b = null; }
      if (b == null) onIcon(null, t("android-settings.slack.imageFailed"));
      else {
        const bg = edgeColour(b);
        setPicked(null); setUploadBg(bg);
        onIcon(new IconPick(b.uri, dataUrl(b)), null);
        if (!colourSet) draft.color = bg;
      }
    })();
  };
  const openPicker = () => { void pickImage().then(upload); };
  const ripple = { color: withAlpha(C.ink, 0.1) };
  return (
    <View style={{ gap: 10 }}>
      <FormLabel text={t("android-settings.slack.icon")} />
      <View style={{ flexDirection: "row", alignItems: "center", gap: 14 }}>
        <Smooth radius={18} style={{ width: 72, height: 72, backgroundColor: parseColor(draft.color, C.chip) }}>
          <Pressable onPress={openPicker} android_ripple={ripple} style={{ flex: 1, alignItems: "center", justifyContent: "center" }}>
            {icon != null ? (
              <Image source={{ uri: icon.bitmap }} accessibilityLabel={t("android-settings.slack.icon")} resizeMode="cover" style={{ width: "100%", height: "100%" }} />
            ) : (
              <View style={{ alignItems: "center" }}>
                <Icon icon={Icons.ImageUpload} size={20} color={C.muted} />
                <T size={11} color={C.muted}>{fresh ? t("android-settings.slack.upload") : t("android-settings.slack.keep")}</T>
              </View>
            )}
          </Pressable>
        </Smooth>
        <View style={{ flex: 1, minWidth: 0, gap: 4 }}>
          <T size={13} color={C.muted}>{t("android-settings.slack.iconNote")}</T>
          <Pressable onPress={openPicker} android_ripple={ripple} style={{ alignSelf: "flex-start" }}>
            <T size={14} color={C.accent}>{t("android-settings.slack.uploadImage")}</T>
          </Pressable>
        </View>
      </View>
      <AvatarGrid list={[...buddyList, ...MAKER_AVATARS()]} picked={picked?.id ?? null} onPick={pick} />
      <FormLabel text={t("android-settings.slack.background")} />
      <View style={{ flexDirection: "row", alignItems: "center", gap: 10 }}>
        <Smooth radius={12} style={{ width: 44, height: 44, backgroundColor: parseColor(draft.color) }} />
        <View style={{ flex: 1, minWidth: 0 }}>
          <Field value={draft.color} onChange={(it: string) => colour(it.trim().toUpperCase(), true)} placeholder="#RRGGBB" mono />
        </View>
        {recommended != null && colourSet && recommended.toLowerCase() !== draft.color.toLowerCase() && (
          <Pressable onPress={() => colour(recommended, false)} android_ripple={ripple}>
            <T size={14} color={C.accent}>{t("android-settings.slack.recommended")}</T>
          </Pressable>
        )}
      </View>
    </View>
  );
}

/** A mark tinted white (Compose's ColorFilter.tint(White)): Drawing cannot tint, so its own drawing with every fill and line white. */
function WhiteMark({ name, size }: { name: DrawableName; size: number }) {
  const d = Drawables[name];
  const xml = d.svg.replace(/(fill|stroke)="(?!none)[^"]*"/g, '$1="#FFFFFF"');
  return <SvgXml xml={xml} width={size} height={(size * d.height) / d.width} />;
}

/** The avatars in a full grid, tiles at least 48 across, 10 apart; the picked one ringed in the accent. */
function AvatarGrid({ list, picked, onPick }: { list: AppAvatar[]; picked: string | null; onPick: (a: AppAvatar) => void }) {
  const C = useC();
  // BoxWithConstraints: the grid's width, once it is laid out.
  const [maxWidth, setMaxWidth] = useState(0);
  const gap = 10;
  const columns = Math.max(1, Math.floor((maxWidth + gap) / (48 + gap)));
  const side = (maxWidth - gap * (columns - 1)) / columns;
  const rows: AppAvatar[][] = [];
  for (let i = 0; i < list.length; i += columns) rows.push(list.slice(i, i + columns));
  const tile = (a: AppAvatar, inner: number) => {
    const thumb = a.mark == null ? avatarThumb(a.id) : null;
    return (
      <Pressable onPress={() => onPick(a)} android_ripple={{ color: withAlpha(C.ink, 0.1) }} style={{ flex: 1, alignItems: "center", justifyContent: "center" }}>
        {a.mark != null ? (
          a.mono ? <WhiteMark name={a.mark} size={inner * 0.55} /> : <Drawing name={a.mark} width={inner * 0.55} />
        ) : thumb != null ? (
          <Image source={thumb} accessibilityLabel={a.label} resizeMode="cover" style={{ width: "100%", height: "100%", transform: [{ scale: 1.18 }] }} />
        ) : null}
      </Pressable>
    );
  };
  return (
    <View style={{ alignSelf: "stretch" }} onLayout={(e) => setMaxWidth(e.nativeEvent.layout.width)}>
      {maxWidth > 0 && (
        <View style={{ gap }}>
          {rows.map((row, r) => (
            <View key={r} style={{ flexDirection: "row", gap }}>
              {row.map((a) => {
                const on = a.id === picked;
                return on ? (
                  <Smooth key={a.id} radius={14} stroke={{ width: 2, color: C.accent }} style={{ width: side, height: side, padding: 4 }}>
                    <Smooth radius={9} style={{ flex: 1, backgroundColor: parseColor(a.bg) }}>{tile(a, side - 8)}</Smooth>
                  </Smooth>
                ) : (
                  <Smooth key={a.id} radius={12} style={{ width: side, height: side, backgroundColor: parseColor(a.bg) }}>{tile(a, side)}</Smooth>
                );
              })}
            </View>
          ))}
        </View>
      )}
    </View>
  );
}

export function FormLabel({ text }: { text: string }) {
  const C = useC();
  return <T size={13} weight="600" color={C.ink}>{text}</T>;
}

// ── the page ───────────────────────────────────────────────────────────

/**
 * A connect's Slack app: read from Slack through the station (the `slackApp` topic); without the viewer's configuration
 * token for its Slack workspace, a way to add one; otherwise its look and permissions, applied to Slack at once.
 */
export function SlackAppScreen({ station, connect }: { station: string; connect: string }) {
  const C = useC();
  const insets = useSafeAreaInsets();
  const topic = useTopic<unknown>({ topic: "slackApp", station, connect });
  const view = slackAppView(topic.value);
  const open = (url: string) => { void Linking.openURL(url); };
  const [adding, setAdding] = useState(false);
  // What the last write said (Slack wants the new permissions approved; the icon did not take): kept here, as the
  // form below is made again from what Slack has after a write. (Kept for this station and connect: set back for others.)
  const [approve, setApprove] = useState(false);
  const [iconError, setIconError] = useState<string | null>(null);
  useEffect(() => { setApprove(false); setIconError(null); }, [station, connect]);
  useEffect(() => {
    if (!adding) return;
    const s = BackHandler.addEventListener("hardwareBackPress", () => { setAdding(false); return true; });
    return () => s.remove();
  }, [adding]);
  const ripple = { color: withAlpha(C.ink, 0.1) };
  const body = () => {
    if (adding) return <ConfigTokenSteps station={station} onSaved={() => setAdding(false)} />;
    const settings = view!.settings;
    const url = view!.links?.settings;
    return (
      <>
        {view!.state === "no_app" ? (
          <T size={14} color={C.muted}>{view!.error != null ? t("android-settings.slack.noApp", { error: view!.error }) : t("android-settings.slack.notConnected")}</T>
        ) : view!.state === "no_config_token" ? (
          <>
            <T size={14} color={C.muted}>{t("android-settings.slack.needToken")}</T>
            <View style={{ flexDirection: "row", justifyContent: "flex-end" }}><Button label={t("android-settings.slack.addToken")} primary onClick={() => setAdding(true)} /></View>
          </>
        ) : view!.state === "error" || settings == null ? (
          <>
            <T size={14} color={C.red}>{t("android-settings.slack.readFailed", { error: view!.error ?? "" })}</T>
            <View style={{ flexDirection: "row", justifyContent: "flex-end" }}><Button label={t("android-settings.slack.changeToken")} primary={false} onClick={() => setAdding(true)} /></View>
          </>
        ) : (
          // Keyed by what Slack has: a change there (or a write from here) starts the form again from it.
          <AppForm key={JSON.stringify(settings)} station={station} connect={connect} settings={settings} links={view!.links} open={open}
            approveState={[approve, setApprove]} iconErrorState={[iconError, setIconError]} />
        )}
        {url != null && url !== "" && (
          <Pressable onPress={() => open(url)} android_ripple={ripple} style={{ alignSelf: "flex-start", paddingVertical: 4 }}>
            <T size={14} color={C.accent}>{t("android-settings.slack.open")}</T>
          </Pressable>
        )}
      </>
    );
  };
  return (
    <View style={{ flex: 1 }}>
      <NavBar
        back={adding ? "Slack app" : t("android-settings.connects.title")}
        onBack={() => { if (adding) setAdding(false); else app.pop(); }}
        title={adding ? t("android-settings.slack.addToken") : "Slack app"}
        sub={<T size={11} color={C.muted}>{t("android-settings.slack.sub")}</T>}
      />
      {view == null ? (
        <Waiting shape={WaitShape.Cards} text={t("android-settings.slack.reading")} error={topic.error?.message} />
      ) : (
        <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: insets.bottom + 30, paddingHorizontal: 18, paddingTop: 8, gap: 12 }}>
          {body()}
        </ScrollView>
      )}
    </View>
  );
}

function AppForm({ station, connect, settings, links, open, approveState, iconErrorState }: {
  station: string;
  connect: string;
  settings: SlackAppSettings;
  links: SlackAppLinksView | null;
  open: (url: string) => void;
  approveState: [boolean, (v: boolean) => void];
  iconErrorState: [string | null, (v: string | null) => void];
}) {
  const C = useC();
  const [draft] = useState(() => new AppDraft(settings));
  useSyncExternalStore(draft.subscribe, () => draft.version);
  const [icon, setIcon] = useState<IconPick | null>(null);
  const [iconError, setIconError] = iconErrorState;
  const [approve, setApprove] = approveState;
  const busy = useDoing("connect.putSlackApp", { station, connect });
  const [error, setError] = useState<string | null>(null);
  const [perms, setPerms] = useState(false);
  const changes = draft.changes();
  const dirty = Object.keys(changes).length > 0 || icon != null;
  const groupWords = SLACK_GROUP_WORDS();
  const ripple = { color: withAlpha(C.ink, 0.1) };
  // Permissions, folded: changed now and then.
  const on = Object.values(draft.groups).filter((it) => it).length;
  const words = Object.fromEntries(groupWords);
  return (
    <>
      {approve && links != null && (
        <Smooth radius={12} style={{ backgroundColor: withAlpha(C.blue, 0.10), paddingHorizontal: 12, paddingVertical: 10, gap: 8 }}>
          <View style={{ flexDirection: "row", alignItems: "center", gap: 8 }}>
            <Icon icon={Icons.ShieldCheck} size={16} color={C.blue} />
            <T size={13} color={C.ink} style={{ flex: 1, minWidth: 0 }}>{t("android-settings.slack.approveNote")}</T>
          </View>
          <View style={{ flexDirection: "row", justifyContent: "flex-end" }}>
            <Button label={t("android-settings.slack.approve")} primary onClick={() => { setApprove(false); open(links.install); }} />
          </View>
        </Smooth>
      )}
      <FormLabel text={t("android-settings.slack.name")} />
      <Field value={draft.name} onChange={(it: string) => { draft.name = it; }} placeholder={t("android-settings.slack.name")} />
      <FormLabel text={t("android-settings.slack.description")} />
      <Field value={draft.description} onChange={(it: string) => { draft.description = it.slice(0, 140); }} placeholder={t("android-settings.slack.descriptionPlaceholder")} />
      <AppLook draft={draft} icon={icon} onIcon={(i, e) => { setIcon(i); setIconError(e); }} fresh={false} />
      {iconError != null && <T size={13} color={C.red}>{iconError}</T>}
      <Pressable onPress={() => setPerms(!perms)} android_ripple={ripple} style={{ alignSelf: "stretch", paddingVertical: 6, flexDirection: "row", alignItems: "center", gap: 6 }}>
        <Icon icon={perms ? Icons.ChevronDown : Icons.ChevronRight} size={14} color={C.muted} />
        <T size={14} color={C.muted} style={{ flex: 1, minWidth: 0 }}>{t("android-settings.slack.perms", { on, n: groupWords.length })}</T>
        {on < groupWords.length && (
          <Pressable onPress={() => { draft.groups = Object.fromEntries(SLACK_GROUPS.map((g) => [g, true])); }} android_ripple={ripple}>
            <T size={14} color={C.accent}>{t("android-settings.slack.allOn")}</T>
          </Pressable>
        )}
      </Pressable>
      {/* Names only, as the models of a profile are picked (Profiles.tsx ModelsSection): what each allows is on the web's hover. */}
      {perms && SLACK_SECTIONS().map(([title, groups]) => {
        const all = groups.every((it) => draft.groups[it] === true);
        return (
          <View key={title}>
            <View style={{ paddingTop: 12, paddingBottom: 2, flexDirection: "row", alignItems: "center", gap: 12 }}>
              <T size={13} color={C.muted}>{title}</T>
              <Pressable onPress={() => { draft.groups = { ...draft.groups, ...Object.fromEntries(groups.map((it) => [it, it === "base" || !all])) }; }} android_ripple={ripple}>
                <T size={13} color={C.accent}>{all ? t("android-settings.none") : t("android-settings.all")}</T>
              </Pressable>
            </View>
            {groups.map((g) => {
              const checked = draft.groups[g] ?? false;
              const fixed = g === "base";
              return (
                <Pressable key={g} disabled={fixed} onPress={() => { draft.groups = { ...draft.groups, [g]: !checked }; }} android_ripple={ripple}
                  style={{ alignSelf: "stretch", paddingVertical: 9, flexDirection: "row", alignItems: "center", gap: 12 }}>
                  {/* Always on, no choice: a tick without a box. */}
                  {fixed ? (
                    <View style={{ width: 20, height: 20, alignItems: "center", justifyContent: "center" }}><Icon icon={Icons.Check} size={16} color={C.accent} /></View>
                  ) : (
                    <Smooth radius={6} style={{ width: 20, height: 20, backgroundColor: checked ? C.accent : C.chip, alignItems: "center", justifyContent: "center" }}>
                      {checked && <Icon icon={Icons.Check} size={13} color={C.bg} />}
                    </Smooth>
                  )}
                  <T size={14} color={checked ? C.ink : C.muted} numberOfLines={1} style={{ flexShrink: 1, minWidth: 0 }}>{words[g]![0]}</T>
                  {SLACK_ADMIN_GROUPS.has(g) && <T size={12} color={C.muted}>{t("android-settings.slack.admin")}</T>}
                </Pressable>
              );
            })}
          </View>
        );
      })}
      {error != null && <T size={13} color={C.red}>{error}</T>}
      <View style={{ flexDirection: "row", gap: 8, justifyContent: "flex-end" }}>
        {dirty && (
          <Button label={t("android-settings.slack.revert")} primary={false} onClick={() => {
            draft.name = settings.name; draft.description = settings.description; draft.color = settings.backgroundColor;
            draft.groups = Object.fromEntries(SLACK_GROUPS.map((g) => [g, settings.groups[g] ?? false])); setIcon(null);
          }} />
        )}
        <Button label={t("android-settings.slack.apply")} primary busy={busy} enabled={dirty} onClick={() => {
          setError(null);
          const body: Record<string, unknown> = { ...changes, ...(icon != null ? { icon: icon.data } : {}) };
          void (async () => {
            try {
              const r = await app.api(station).putSlackApp(connect, body);
              setIcon(null);
              const ie = r["iconError"];
              setIconError(ie != null && typeof ie !== "object" ? String(ie) : null);
              const updated = r["permissionsUpdated"] === true;
              setApprove(updated);
              // Changed permissions are approved in Slack: its page opens at once (the notice stays, to go back to it).
              if (updated && links != null) open(links.install);
              app.toast = updated ? t("android-settings.slack.updatedApprove") : t("android-settings.slack.updated");
            } catch (e) { setError(e instanceof Error ? e.message : String(e)); }
          })();
        }} />
      </View>
    </>
  );
}

/**
 * Adds a Slack workspace's app configuration token (by its refresh token); `onSaved` gets the workspace. The access
 * token Slack shows above it is told apart from the one wanted.
 */
export function ConfigTokenSteps({ station, flow = null, onSaved }: { station: string; flow?: ConnectFlow | null; onSaved: (team: string) => void }) {
  const C = useC();
  const [config, setConfig] = useState("");
  const addingToken = useDoing("slack.addConfigToken", { station });
  const busy = flow != null ? flow.busy : addingToken;
  const [error, setError] = useState<string | null>(null);
  const configError = flow?.view?.configError;
  return (
    <>
      <Steps steps={[
        [t("android-settings.slack.step1"), () => { void Linking.openURL("https://api.slack.com/apps"); }],
        [t("android-settings.slack.step2"), null],
        [t("android-settings.slack.step3", { app: APP_NAME }), null],
      ]} />
      <SecretField value={config} onChange={(it) => { setConfig(it); flow?.edit({ config: it }); }} placeholder="xoxe-1-…" />
      {flow != null ? (
        configError != null && <T size={13} color={C.red}>{configError}</T>
      ) : config.startsWith("xoxe.xoxp-") ? (
        <T size={13} color={C.red}>{t("android-settings.slack.accessToken")}</T>
      ) : config !== "" && !config.startsWith("xoxe-") ? (
        <T size={13} color={C.red}>{t("android-settings.slack.refreshToken")}</T>
      ) : null}
      {error != null && <T size={13} color={C.red}>{error}</T>}
      <View style={{ flexDirection: "row", justifyContent: "flex-end" }}>
        <Button label={t("android-settings.slack.add")} primary busy={busy} enabled={flow?.view?.configReady ?? (config.startsWith("xoxe-1-") && config.length > 20)} onClick={() => {
          if (flow != null) { flow.act("config"); return; }
          setError(null);
          void (async () => {
            try { const team = await app.api(station).addConfigToken(config); setConfig(""); app.toast = t("android-settings.slack.added"); onSaved(team); }
            catch (e) { setError(e instanceof Error ? e.message : String(e)); }
          })();
        }} />
      </View>
    </>
  );
}
