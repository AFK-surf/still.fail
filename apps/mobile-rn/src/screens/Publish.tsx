// A chat made public (docs/public-share.md; the core's views/publish.ts), from its sheet (ChatInfo.tsx): its links, and
// the sheet that publishes it (web mobile/Chat.tsx PublishList / PublishSheet).
import * as Clipboard from "expo-clipboard";
import { useEffect, useState, type ReactNode } from "react";
import { Pressable, ScrollView, View } from "react-native";
import { CoreError } from "../../../../web/src/core/client.ts";
import type { ChatPublish, ChatPublished, PublishFile, PublishMessage, PublishPreview } from "../../../../web/src/core/shapes.ts";
import { useDoing } from "../../../../web/src/doing.ts";
import type { AppState } from "../AppState";
import { errorText } from "../data/Calls";
import { t } from "../i18n";
import { Button } from "../ui/Controls";
import { Icon, Icons } from "../ui/Icon";
import { Markdown, withRefs } from "../ui/Markdown";
import { Avatar } from "../ui/Parts";
import { SheetGrab, SheetHead } from "../ui/Sheet";
import { Smooth } from "../ui/Smooth";
import { T } from "../ui/Text";
import { useC, withAlpha } from "../ui/Theme";
import { WaitLine } from "../ui/Waiting";
import { chatInk } from "../ui/ChatInk";
import { AgentAvatar, MessageTime } from "./Chat";
import { FileCard, imageBox, kindOf, PreviewKind, StationImage } from "./ChatFiles";
import { InfoList, InfoRow } from "./ChatInfo";
import { confirm } from "./Settings";

/** A chat's public links as its sheet shows them: to those who may publish it, or when it has some (a read-only member sees them). */
export function shownPublish(publish: ChatPublish | null | undefined): ChatPublish | null {
  return publish && (publish.may || publish.links.length > 0) ? publish : null;
}

/**
 * Making the chat public, a card of its own in its sheet: 「公开分享」 opens the sheet that publishes it, for those who
 * may (not a read-only member); each of its links under it, when and by whom, 复制, and 撤销 for who published it or an
 * owner or admin (asked first; gone from here at once).
 */
export function PublishList({ app, station, thread, publish }: { app: AppState; station: string; thread: number; publish: ChatPublish }) {
  const C = useC();
  return (
    <InfoList>
      {publish.may && (
        <InfoRow onClick={() => openPublish(app, station, thread)}>
          <Icon icon={Icons.Web} size={16} color={C.ink} />
          <T size={14} color={C.ink} style={{ flex: 1 }}>{t("web-pages.chat.publish")}</T>
          <Icon icon={Icons.ChevronRight} size={14} color={C.subtle} />
        </InfoRow>
      )}
      {publish.links.map((l) => <PublishedRow key={l.id} app={app} station={station} thread={thread} link={l} />)}
    </InfoList>
  );
}

function PublishedRow({ app, station, thread, link }: { app: AppState; station: string; thread: number; link: ChatPublished }) {
  const C = useC();
  return (
    <InfoRow>
      <T size={13} color={C.muted} numberOfLines={1} ellipsizeMode="tail" style={{ flex: 1, minWidth: 0 }}>
        {[link.time?.["createdAt"]?.ago, link.byName].filter((x): x is string => x != null).join(" · ")}
      </T>
      <TextAction label={t("common.copy")} onClick={() => copyLink(app, link.link)} />
      {link.mayRevoke && (
        <TextAction
          label={t("web-pages.chat.publish.revoke")}
          onClick={() =>
            confirm(app, t("web-pages.chat.publish.revokeAsk"), t("web-pages.chat.publish.revokeNote"), t("web-pages.chat.publish.revoke"), true, t("web-pages.chat.publish.revokeVerb"), () => {}, async () => {
              await app.api(station).unpublish(thread, link.id);
            })
          }
        />
      )}
    </InfoRow>
  );
}

/** A link's words as a button (in the accent, no frame), as the phone's web draws one (parts.tsx LinkButton). */
function TextAction({ label, onClick }: { label: string; onClick: () => void }) {
  const C = useC();
  return (
    <Smooth radius={6}>
      <Pressable onPress={onClick} android_ripple={{ color: withAlpha(C.ink, 0.12), borderless: false }} style={{ paddingHorizontal: 4, paddingVertical: 2 }}>
        <T size={14} color={C.accent}>{label}</T>
      </Pressable>
    </Smooth>
  );
}

/** Puts a link on the clipboard, saying so. */
function copyLink(app: AppState, link: string) {
  Clipboard.setStringAsync(link).then(
    () => { app.toast = t("common.link.copied"); },
    (e: unknown) => { app.toast = t("common.link.copyFailed", { error: e instanceof Error ? e.message : String(e) }); },
  );
}

/** A preview as asked (`chat.publishPreview`): being read, read, or why not. */
type Previewed = { kind: "Reading" } | { kind: "Ok"; preview: PublishPreview } | { kind: "Failed"; error: string };

/**
 * Publishes the chat (web mobile/Chat.tsx PublishSheet): what it would hold, asked as the sheet opens; the attachments
 * to tick (all at first; one too big is shown, never ticked), who can read it, 「发布」. Published, its link with a way
 * to copy it; the chat's sheet lists it from then on.
 */
export function openPublish(app: AppState, station: string, thread: number) {
  app.sheet = { height: 0.9, content: () => <PublishSheet app={app} station={station} thread={thread} /> };
}

function PublishSheet({ app, station, thread }: { app: AppState; station: string; thread: number }) {
  const C = useC();
  const [shown, setShown] = useState<Previewed>({ kind: "Reading" });
  const [off, setOff] = useState<ReadonlySet<string>>(new Set());
  const [made, setMade] = useState<ChatPublished | null>(null);
  useEffect(() => {
    let live = true;
    app.api(station).publishPreview(thread).then(
      (preview) => { if (live) setShown({ kind: "Ok", preview }); },
      (e: unknown) => { if (live) setShown({ kind: "Failed", error: e instanceof CoreError ? errorText(e) : String(e) }); },
    );
    return () => { live = false; };
  }, [thread]); // eslint-disable-line react-hooks/exhaustive-deps
  const publishing = useDoing("chat.publish", { station, thread });
  // Its words 20dp in from the edges; the attachments' rows run to them, as a list to tick does.
  const inset = { marginHorizontal: 20 } as const;
  const done = made;
  const now = shown;
  let body: ReactNode;
  if (done != null) {
    body = (
      <>
        <Smooth radius={22} style={[inset, { backgroundColor: withAlpha(C.ink, 0.04) }]}>
          <T size={14} color={C.ink} numberOfLines={1} ellipsizeMode="tail" style={{ paddingHorizontal: 14, paddingVertical: 10 }}>{done.link}</T>
        </Smooth>
        <View style={[inset, { flexDirection: "row", justifyContent: "flex-end", gap: 8 }]}>
          <Button label={t("common.done")} primary={false} onClick={() => { app.sheet = null; }} />
          <Button label={t("common.link.copy")} primary onClick={() => copyLink(app, done.link)} />
        </View>
      </>
    );
  } else if (now.kind === "Reading") {
    body = <View style={inset}><WaitLine text={t("web-pages.chat.publish.reading")} /></View>;
  } else if (now.kind === "Failed") {
    body = <T size={13} color={C.red} style={inset}>{now.error}</T>;
  } else if (now.preview.messages.length === 0) {
    body = <T size={14} color={C.muted} style={inset}>{t("web-pages.chat.publish.empty")}</T>;
  } else {
    const p = now.preview;
    const ticked = p.files.filter((f) => !off.has(f.k));
    body = (
      <>
        {/* As the chat draws others' messages, on a card. */}
        <Smooth radius={22} style={[inset, { backgroundColor: withAlpha(C.ink, 0.04) }]}>
          <View style={{ paddingHorizontal: 16, paddingVertical: 14, gap: 16 }}>
            {p.messages.map((m) => (
              <PreviewMessage key={m.n} station={station} m={m} off={off} toggle={(k) => setOff((o) => { const n = new Set(o); if (n.has(k)) n.delete(k); else n.add(k); return n; })} />
            ))}
          </View>
        </Smooth>
        {p.hiddenText != null && <T size={12} color={C.muted} style={inset}>{p.hiddenText}</T>}
        <View style={[inset, { flexDirection: "row", justifyContent: "flex-end" }]}>
          <Button
            label={t("web-pages.chat.publish.go")} primary busy={publishing}
            onClick={() => app.act(t("web-pages.chat.publish.verb"), async () => {
              setMade(await app.api(station).publish(thread, p.upto, ticked.map((f) => f.k)));
            })}
          />
        </View>
      </>
    );
  }
  return (
    <>
      <SheetGrab />
      <SheetHead title={made != null ? t("web-pages.chat.publish.made") : t("web-pages.chat.publish")} />
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingTop: 4, paddingBottom: 30, gap: 12 }}>
        <T size={12} color={C.muted} style={inset}>{t("web-pages.chat.publish.lead")}</T>
        {body}
      </ScrollView>
    </>
  );
}

/**
 * A message as the snapshot would hold it, drawn as the chat draws someone else's (Chat.tsx SaidRow): its avatar and
 * name in line over what it says, an agent's in Markdown; under it its attachments as the chat shows them, each ticked
 * to go with it or not (`off`: those left out), and with something hidden, how many.
 */
function PreviewMessage({ station, m, off, toggle }: { station: string; m: PublishMessage; off: ReadonlySet<string>; toggle: (k: string) => void }) {
  const C = useC();
  const ink = chatInk();
  return (
    <View style={{ width: "100%" }}>
      {/* As the chat draws them (Chat.tsx SaidRow): an agent by its maker's mark, a person by their picture. */}
      <View style={{ position: "absolute", left: 0, top: 3 }}>
        {m.agent ? <AgentAvatar maker={m.maker ?? null} runtime={m.runtime ?? null} /> : <Avatar id={m.author} name={m.author} size={18} picture={m.picture ?? null} />}
      </View>
      <View style={{ width: "100%", gap: 4 }}>
        <View style={{ marginLeft: 25, minHeight: 24, flexDirection: "row", alignItems: "center", gap: 6 }}>
          {/* FontWeight(650) there: React Native takes weights by the hundred, the nearest below. */}
          <T size={15} weight="600" color={ink.name} numberOfLines={1} ellipsizeMode="tail" style={{ maxWidth: 240 }}>{m.author}</T>
          <MessageTime stamp={m.time?.["createdAt"] ?? null} />
        </View>
        {m.agent ? <Markdown text={m.text} /> : m.text.length > 0 ? <T size={15} line={23} color={ink.text}>{withRefs(m.text)}</T> : null}
        {m.files.length > 0 && (
          <View style={{ marginTop: 2, flexDirection: "row", flexWrap: "wrap", gap: 6 }}>
            {m.files.map((f) => <FileToggle key={f.k} station={station} f={f} on={!off.has(f.k)} toggle={() => toggle(f.k)} />)}
          </View>
        )}
        {m.hiddenText != null && (
          <View style={{ flexDirection: "row", alignItems: "center", gap: 6 }}>
            <Icon icon={Icons.ShieldCheck} size={13} color={C.muted} />
            <T size={12} color={C.muted}>{m.hiddenText}</T>
          </View>
        )}
      </View>
    </View>
  );
}

/**
 * An attachment in the preview as the chat shows it (web Publish.tsx FileToggle): an image's box, else its card, with
 * the app's checkbox in its top right corner; a tap anywhere on it ticks or unticks it (nothing opens), unticked it fades.
 */
function FileToggle({ station, f, on, toggle }: { station: string; f: PublishFile; on: boolean; toggle: () => void }) {
  const C = useC();
  const owner = f.file.owner;
  const box = imageBox(f.file);
  return (
    <View style={{ opacity: on ? 1 : 0.45 }}>
      {owner != null && kindOf(f.name).kind === PreviewKind.Image
        ? <View style={{ width: 160, aspectRatio: box.width / box.height }}><StationImage station={station} session={owner} file={f.file} /></View>
        : <FileCard name={f.name} size={f.size} onClick={null} />}
      {/* Over it all: a tap ticks, rather than opening the file. */}
      <Pressable onPress={toggle} style={{ position: "absolute", left: 0, top: 0, right: 0, bottom: 0 }} />
      {/* The app's checkbox (web global.css.ts): a soft square, ink with a check when ticked. */}
      <View pointerEvents="none" style={{ position: "absolute", top: 8, right: 8 }}>
        <Smooth radius={6} stroke={{ width: 1, color: on ? C.ink : C.line }} style={{ width: 18, height: 18, backgroundColor: on ? C.ink : C.bg, alignItems: "center", justifyContent: "center" }}>
          {on && <Icon icon={Icons.Check} size={12} color={C.bg} />}
        </Smooth>
      </View>
    </View>
  );
}
