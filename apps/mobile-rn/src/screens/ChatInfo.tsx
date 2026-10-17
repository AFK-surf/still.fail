// A chat's own sheet, from its bar's "…" (split from Chat.kt).
import { useState, type ReactNode } from "react";
import { Linking, Pressable, ScrollView, View } from "react-native";
import type { ChatAgent, ChatShare, ChatThread, ChatView } from "../../../../web/src/core/shapes.ts";
import { SheetSpec, useApp, type AppState, type ChatOf } from "../AppState";
import { rememberTopic, Topics } from "../data/Topics";
import { chatAgentState } from "../data/Chats";
import { t } from "../i18n";
import { Button, DoingMark, Field, PickRow } from "../ui/Controls";
import { Icon, Icons } from "../ui/Icon";
import { ModelMark, PeopleStack, QuotaRings, SlackMark } from "../ui/Parts";
import { SheetGrab, SheetHead } from "../ui/Sheet";
import { Smooth } from "../ui/Smooth";
import { T } from "../ui/Text";
import { dp, useC, withAlpha } from "../ui/Theme";
import { Spinner } from "../ui/Waiting";
import { agentSince, openAgent } from "./AgentSheet";
import { chatLink, copyChatLink } from "./ChatLink";
import { Switch } from "./Connects";
import { PublishList, shownPublish } from "./Publish";
import { confirm } from "./Settings";

/**
 * The chat itself, from "…": its name (with a way to change it) over who started it, how many take part and when it was
 * last written in, in a line; its agents, each where it stands (a tap opens its card, AgentSheet.tsx); then what can be
 * done with it, within reach: pin it, copy its link, open it in Slack, archive it. As tall as what it shows.
 */
export function openChatInfo(app: AppState, station: string, of: ChatOf, thread: ChatThread, first: ChatView | null = null) {
  const publish = shownPublish(first?.publish);
  const rows = (first?.agents?.length ?? 1) * 56 + ((first?.pinned != null ? 1 : 0) + (first?.slackUrl != null ? 1 : 0) + (first?.xshare != null ? 1 : 0) + 2) * 40 +
    (publish != null ? ((publish.may ? 1 : 0) + publish.links.length) * 40 + 10 : 0);
  app.sheet = new SheetSpec(0.55, false, 22 + 84 + rows + 10 + 30, null, false, () => <ChatInfoSheet app={app} station={station} of={of} thread={thread} />);
}

function ChatInfoSheet({ app, station, of, thread }: { app: AppState; station: string; of: ChatOf; thread: ChatThread }) {
  const C = useC();
  const chat = rememberTopic<ChatView>(Topics.chat(station, of));
  useApp((s) => s.doing);
  const view = chat.value;
  // Archived or offline, it is only read: no name to change, nothing to archive.
  const open = view != null && view.archived !== true && !view.offline;
  const session = ("session" in of ? of.session : undefined) ?? view?.agents?.[0]?.session?.key ?? "";
  const about = view?.thread ?? thread;
  // Archived or offline it is still read, and pasted elsewhere still read there: its link is there whenever it has one.
  const link = view != null ? chatLink(app.cloudOrigin, station, session) : null;
  // Under way: a spinner on the pin's row, not tapped again.
  const pinning = app.isDoing("chat.pin", { station, session });
  // Who started it and when, how many take part, when it was last written in: what there is of them, in a line.
  const creator = about.creator?.shown?.display;
  const created = about.time?.["createdAt"]?.ago;
  const people = view?.people?.length;
  const latest = about.lastMessage?.time?.["createdAt"]?.ago;
  const facts = [
    view?.place != null ? t("android-chat.info.from.slack", { place: view.place }) : null,
    creator != null && created != null ? t("android-chat.info.startedAt", { name: creator, ago: created }) : (creator ?? created),
    people != null && people > 1 ? t("android-chat.info.people.count", { n: people }) : null,
    latest != null ? t("android-chat.info.latestAt", { ago: latest }) : null,
  ].filter((f): f is string => f != null).join(" · ");
  const faces = view?.people?.length ? view.people.slice(0, 5) : null;
  const shown = shownPublish(view?.publish);
  return (
    <>
      <SheetGrab />
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingLeft: 18, paddingRight: 18, paddingBottom: 30 }}>
        <View style={{ flexDirection: "row", paddingTop: 4, gap: 12 }}>
          <T size={18} line={24} weight="700" numberOfLines={2} style={{ flex: 1, minWidth: 0 }}>{view?.title ?? ""}</T>
          {open && (
            <View style={{ width: 32, height: 32, borderRadius: 16, overflow: "hidden", backgroundColor: withAlpha(C.ink, 0.05) }}>
              <Pressable
                onPress={() => askTitle(app, station, view.thread?.id, session, view.title)}
                android_ripple={{ color: withAlpha(C.ink, 0.1) }}
                accessibilityLabel={t("android-chat.rename")}
                style={{ flex: 1, alignItems: "center", justifyContent: "center" }}
              >
                <Icon icon={Icons.Edit} size={16} color={C.ink} />
              </Pressable>
            </View>
          )}
        </View>
        <View style={{ flexDirection: "row", paddingTop: 6, paddingBottom: 16, alignItems: "center", gap: 8 }}>
          {faces && (
            // The stack draws each face 5dp over the one before: as wide as what it draws.
            <View style={{ width: 19 + (faces.length - 1) * 14, flexDirection: "row", overflow: "visible" }}>
              <View style={{ flexShrink: 0 }}><PeopleStack people={faces} size={16} ring={C.surface} /></View>
            </View>
          )}
          <T size={13} color={C.muted} numberOfLines={1} style={{ flex: 1, minWidth: 0 }}>{facts}</T>
        </View>
        {view != null && view.agents.length > 0 && (
          <>
            <InfoList>
              {view.agents.map((a) => <AgentInfoRow key={a.session.key} app={app} station={station} of={of} a={a} />)}
            </InfoList>
            <View style={{ height: 10 }} />
          </>
        )}
        {(open || link != null || view?.slackUrl != null || view?.xshare != null) && (
          <InfoList>
            {/* A station from before pins says nothing of them: its chats are not pinned from here. */}
            {open && view.pinned != null && (() => {
              const pinned = view.pinned;
              return (
                <InfoRow onClick={pinning ? null : () => app.act(pinned ? t("android-chat.unpin.verb") : t("android-chat.pin.verb"), () => app.api(station).setPinned(session, !pinned))}>
                  <Icon icon={Icons.Pin} size={16} color={C.ink} />
                  <T size={14} style={{ flex: 1 }}>{pinned ? t("android-chat.unpin") : t("android-chat.info.pinTop")}</T>
                  {pinning && <Spinner inline />}
                </InfoRow>
              );
            })()}
            {link != null && (
              <InfoRow onClick={() => copyChatLink(app, view?.title ?? "", link)}>
                <Icon icon={Icons.Copy} size={16} color={C.ink} />
                <T size={14} style={{ flex: 1 }}>{t("web-main.chat.copyLink")}</T>
              </InfoRow>
            )}
            {view?.xshare != null && <ShareRow app={app} station={station} thread={about.id} share={view.xshare} />}
            {view?.slackUrl != null && (() => {
              const url = view.slackUrl;
              return (
                <InfoRow onClick={() => void Linking.openURL(url)}>
                  <SlackMark size={16} />
                  <T size={14} style={{ flex: 1 }}>{t("android-chat.info.slack.open")}</T>
                  <Icon icon={Icons.ChevronRight} size={14} color={C.subtle} />
                </InfoRow>
              );
            })()}
            {/* Into the archive (its first agent's session with it when it is that session's own), back to the list at once. */}
            {open && (
              <InfoRow
                onClick={() => {
                  const own = view.agents[0]?.session?.key ?? ("session" in of ? of.session : undefined) ?? "";
                  const archive = async () => {
                    await app.api(station).setArchived(thread.id, own, true);
                    app.toast = t("android-chat.archived");
                  };
                  // A chat keeping watch is archived only once asked: its watch runs on in the archive (the core's words).
                  // Either way the sheet closes and the page goes at once; a toast says if it could not.
                  const watch = view.watch;
                  if (watch != null) confirm(app, t("android-chat.archive.ask", { title: view.title }), watch.ask, t("android-chat.archive"), false, t("android-chat.archive.verb"), () => app.pop(), archive);
                  else { app.sheet = null; app.pop(); app.act(t("android-chat.archive.verb"), archive); }
                }}
              >
                <Icon icon={Icons.Archive} size={16} color={C.ink} />
                <T size={14} style={{ flex: 1 }}>{t("android-chat.info.archive")}</T>
              </InfoRow>
            )}
          </InfoList>
        )}
        {/* Making it public, a card of its own (Publish.tsx). */}
        {shown != null && (
          <>
            <View style={{ height: 10 }} />
            <PublishList app={app} station={station} thread={about.id} publish={shown} />
          </>
        )}
      </ScrollView>
    </>
  );
}

/** One of the chat's agents in its sheet: where it stands and for how long (its clock runs, so a row of its own). */
function AgentInfoRow({ app, station, of, a }: { app: AppState; station: string; of: ChatOf; a: ChatAgent }) {
  const C = useC();
  const s = a.session;
  // The account it runs on now, with what is left of it (so a glance here saves the trip to settings).
  const quota = a.account?.quota ?? a.profile?.quota;
  const since = agentSince(a);
  return (
    <InfoRow onClick={() => openAgent(app, station, of, a)}>
      <ModelMark maker={s.maker} runtime={s.runtime} size={36} state={chatAgentState(a)} around={C.surface2} />
      <View style={{ flex: 1, minWidth: 0 }}>
        <T size={15} weight="600" numberOfLines={1}>{s.agentText}</T>
        {/* Where it stands and for how long, in a line: it gives way with an ellipsis rather than wrapping. */}
        <T size={12} color={C.muted} numberOfLines={1}>{[s.statusText, since].filter((x) => x != null).join(" · ")}</T>
      </View>
      <QuotaRings quota={quota} />
      <Icon icon={Icons.ChevronRight} size={14} color={C.subtle} />
    </InfoRow>
  );
}

/**
 * The chat's sharing with the viewer's other workspaces (docs/chat-share.md; web mobile/Chat.tsx ShareRow): where it is
 * shared at the row's end, under way a spinner there; a tap opens the sheet that changes it, for those who may (its
 * starter, an owner or admin).
 */
function ShareRow({ app, station, thread, share }: { app: AppState; station: string; thread: number; share: ChatShare }) {
  const C = useC();
  const session = share.session;
  useApp((s) => s.doing);
  const busy = app.isDoing("chat.xshare", { station, session });
  const failed = app.failedOf("chat.xshare", { station, session });
  return (
    <InfoRow onClick={!share.may || busy ? null : () => openShare(app, station, thread, session, share)}>
      <Icon icon={Icons.Users} size={16} color={C.ink} />
      {/* Its name whole; where it is shared after it, at the row's end, cut short rather than wrapped. */}
      <T size={14} numberOfLines={1} style={{ flexShrink: 0 }}>{t("web-pages.chat.xshare")}</T>
      <T size={13} color={C.muted} numberOfLines={1} align="right" style={{ flex: 1, minWidth: 0 }}>{share.text}</T>
      {busy || failed != null ? <DoingMark running={busy} failed={failed} /> : share.may ? <Icon icon={Icons.ChevronRight} size={14} color={C.subtle} /> : null}
    </InfoRow>
  );
}

/** Which of the viewer's other workspaces it is shared with, ticked, and whether their agents may send: done, the sheet goes at once. */
function openShare(app: AppState, station: string, thread: number, session: string, share: ChatShare) {
  app.sheet = new SheetSpec(0.6, false, 22 + 48 + 44 + share.places.length * 48 + 12 + 66 + 70, null, false, () => <ShareSheet app={app} station={station} thread={thread} session={session} share={share} />);
}

function ShareSheet({ app, station, thread, session, share }: { app: AppState; station: string; thread: number; session: string; share: ChatShare }) {
  const C = useC();
  const [ticked, setTicked] = useState<ReadonlySet<string>>(() => new Set(share.places.filter((p) => p.on).map((p) => p.workspace)));
  const [write, setWrite] = useState(share.write);
  const none = ticked.size === 0;
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("web-pages.chat.xshare")} />
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: 24 }}>
        <T size={13} color={C.muted} style={{ paddingHorizontal: 20, paddingVertical: 6 }}>{t("web-pages.chat.xshare.lead")}</T>
        {share.places.map((p) => (
          <PickRow
            key={p.workspace}
            label={p.name}
            checked={ticked.has(p.workspace)}
            onClick={() => setTicked((was) => { const next = new Set(was); if (next.has(p.workspace)) next.delete(p.workspace); else next.add(p.workspace); return next; })}
          />
        ))}
        <View style={{ paddingLeft: 20, paddingRight: 20, paddingTop: 12, paddingBottom: 16 }}>
          <Smooth radius={14} style={{ backgroundColor: withAlpha(C.ink, 0.05) }}>
            <Pressable disabled={none} onPress={() => setWrite((w) => !w)} android_ripple={{ color: withAlpha(C.ink, 0.1) }} style={{ paddingHorizontal: 14, paddingVertical: 10 }}>
              <View style={{ flexDirection: "row", alignItems: "center", gap: 12, opacity: none ? 0.5 : 1 }}>
                <View style={{ flex: 1, minWidth: 0 }}>
                  <T size={15} weight="600">{t("web-pages.chat.xshare.write")}</T>
                  <T size={13} color={C.muted}>{t("web-pages.chat.xshare.writeNote")}</T>
                </View>
                <Switch on={write && !none} />
              </View>
            </Pressable>
          </Smooth>
        </View>
        <View style={{ flexDirection: "row", paddingHorizontal: 20, justifyContent: "flex-end" }}>
          <Button
            label={t("common.done")}
            primary
            onClick={() => {
              app.sheet = null;
              const to = share.places.filter((p) => ticked.has(p.workspace)).map((p) => p.workspace);
              app.act(t("web-pages.chat.xshare.verb"), () => app.api(station).share(thread, session, to, write));
            }}
          />
        </View>
      </ScrollView>
    </>
  );
}

/**
 * Renames the chat (web mobile/sheets.tsx → ask, with `empty`): an empty name gives it back its first message. The core
 * shows the new name at once (views/local.ts), so the sheet goes as it is given, not waiting on the station; a
 * failure is said by a toast, the name as it was again.
 */
export function askTitle(app: AppState, station: string, thread: number | null | undefined, session: string, first: string): void {
  app.sheet = new SheetSpec(0.42, false, null, null, false, () => <AskTitleSheet app={app} station={station} thread={thread} session={session} first={first} />);
}

function AskTitleSheet({ app, station, thread, session, first }: { app: AppState; station: string; thread: number | null | undefined; session: string; first: string }) {
  const C = useC();
  const [text, setText] = useState(first);
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("android-chat.rename.title")} />
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingHorizontal: 20, gap: 10 }} keyboardShouldPersistTaps="handled">
        <Field value={text} onChange={setText} placeholder={t("android-chat.rename.field")} />
        <T size={12} color={C.muted}>{t("android-chat.rename.note")}</T>
        <View style={{ flexDirection: "row", paddingTop: 6, paddingBottom: 24, gap: 8, justifyContent: "flex-end" }}>
          <Button label={t("common.cancel")} primary={false} onClick={() => { app.sheet = null; }} />
          <Button
            label={t("common.save")}
            primary
            enabled={text.trim() !== first}
            onClick={() => {
              const title = text.trim();
              app.sheet = null;
              app.act(t("android-chat.rename.verb"), () => app.api(station).rename(thread ?? null, session, title));
            }}
          />
        </View>
      </ScrollView>
    </>
  );
}

export function InfoList({ children }: { children?: ReactNode }) {
  const C = useC();
  return <Smooth radius={14} style={{ alignSelf: "stretch", backgroundColor: withAlpha(C.ink, 0.05) }}>{children}</Smooth>;
}

export function InfoRow({ onClick = null, children }: { onClick?: (() => void) | null; children?: ReactNode }) {
  const C = useC();
  const row = { flexDirection: "row", alignItems: "center", gap: dp(12), paddingHorizontal: dp(12), paddingVertical: dp(10) } as const;
  if (onClick == null) return <View style={row}>{children}</View>;
  return <Pressable onPress={onClick} android_ripple={{ color: withAlpha(C.ink, 0.1) }} style={row}>{children}</Pressable>;
}
