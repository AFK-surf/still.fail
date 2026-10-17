// The automatic decisions (settings → 自动决策, as the narrow web's mobile/AutomaticDecisions.tsx): what can be decided
// without a person, each station's rule for completing chats (on or off, the model that judges), and its archive policy.
import { useEffect, useMemo } from "react";
import { Pressable, ScrollView, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { core, useTopic } from "../../../../web/src/core/react.ts";
import type { ArchiveOptionView, ArchivePolicyDraft, ArchivePolicyView, AutomaticDecisionDraft, AutomaticDecisionView, StationView } from "../../../../web/src/core/shapes.ts";
import { useDoing, useDoingFailed } from "../../../../web/src/doing.ts";
import { app, SheetSpec } from "../AppState";
import type { WorkspaceEntry } from "../data/Accounts";
import { Topics } from "../data/Topics";
import { t } from "../i18n";
import { Button, DoingMark, Field } from "../ui/Controls";
import { Icon, Icons } from "../ui/Icon";
import { LargeTitle, ListCard, ListRow, NavButton, SectionHeader, Seg } from "../ui/Parts";
import { SheetGrab, SheetHead } from "../ui/Sheet";
import { T } from "../ui/Text";
import { useC, withAlpha } from "../ui/Theme";
import { Spinner, WaitLine, WaitShape, Waiting } from "../ui/Waiting";
import { GoRow, ModelList, PageNote } from "./SettingParts";
import { Switch } from "./Connects";
import { TopBack } from "./Stations";

export function AutomaticDecisionsScreen() {
  const C = useC();
  const insets = useSafeAreaInsets();
  return (
    <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: insets.bottom }}>
      <TopBack label={t("android-settings.title")} onBack={() => app.pop()} />
      <LargeTitle small="" big={t("web-pages.automaticDecisions.title")} />
      <ListCard>
        <ListRow onClick={() => app.push({ kind: "AutomaticDecisionCompletion" })}>
          <View style={{ flex: 1, minWidth: 0, gap: 5 }}>
            <T color={C.ink} size={15}>{t("web-pages.automaticDecisions.completion")}</T>
            <T size={13} color={C.muted}>{t("web-pages.automaticDecisions.completionShort")}</T>
          </View>
          <Icon icon={Icons.ChevronRight} size={14} color={C.subtle} />
        </ListRow>
      </ListCard>
    </ScrollView>
  );
}

/** Where a wait says itself in a line on these pages: a PageNote's place. */
const NoteRoom = { paddingLeft: 24, paddingRight: 24, paddingBottom: 10 } as const;

export function AutomaticDecisionCompletionScreen({ current }: { current: WorkspaceEntry }) {
  const insets = useSafeAreaInsets();
  const topic = useTopic<StationView[]>(Topics.stations(current.workspace.id));
  return (
    <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: insets.bottom }}>
      <TopBack label={t("web-pages.automaticDecisions.title")} onBack={() => app.pop()} />
      <LargeTitle small="" big={t("web-pages.automaticDecisions.completion")} />
      {topic.value?.map((station) => {
        const view = station.overview?.automaticDecisions;
        if (station.online && view != null) return <AutomaticDecisionPanel key={station.station} station={station.station} name={station.name} view={view} />;
        return (
          <View key={station.station}>
            <SectionHeader title={station.name} start={24} />
            {station.online && station.overview == null
              ? <View style={NoteRoom}><WaitLine text={t("common.connecting")} /></View>
              : <PageNote text={t(!station.online ? "web-pages.automaticDecisions.offlineNote" : "web-pages.automaticDecisions.upgrade")} />}
          </View>
        );
      }) ?? <Waiting shape={WaitShape.Cards} count={2} text={t("common.readingStations")} error={topic.error?.message} />}
      {topic.value?.length === 0 && <PageNote text={t("web-pages.automaticDecisions.addStation")} />}
      <View style={{ height: 30 }} />
    </ScrollView>
  );
}

function AutomaticDecisionPanel({ station, name, view }: { station: string; name: string; view: AutomaticDecisionView }) {
  if (!view.canEdit) return (<><SectionHeader title={name} start={24} /><PageNote text={t("web-pages.automaticDecisions.adminOnly")} /></>);
  return <AutomaticDecisionForm station={station} name={name} view={view} />;
}

/** The station's rule, edited through the core's draft (`decisionForm`, a form of its own each time the panel opens). */
function AutomaticDecisionForm({ station, name, view }: { station: string; name: string; view: AutomaticDecisionView }) {
  const C = useC();
  const form = useMemo(() => crypto.randomUUID(), [station]);
  const topic = useTopic<AutomaticDecisionDraft>({ topic: "decisionForm", station, form });
  const act = (action: string, input: Record<string, unknown> = {}) => {
    app.act(
      t("web-pages.automaticDecisions.configAction"),
      () => core().call(`automaticDecisions.form.${action}`, { station, form, input }),
      action === "save" ? t("web-pages.automaticDecisions.saved") : undefined,
    );
  };
  const edit = (key: string, value: unknown) => act("edit", { [key]: value });
  useEffect(() => {
    act("open");
    return () => act("drop");
  }, [station, form]);
  const saving = useDoing("automaticDecisions.form.save", { station, form });
  const refreshing = useDoing("automaticDecisions.refresh", { station });
  const refreshFailed = useDoingFailed("automaticDecisions.refresh", { station });
  const reviewing = useDoing("automaticDecisions.review", { station });
  const reviewFailed = useDoingFailed("automaticDecisions.review", { station });
  const saveFailed = useDoingFailed("automaticDecisions.form.save", { station, form });
  const d = topic.value;
  if (d == null) return <View style={NoteRoom}><WaitLine text={topic.error?.message ?? t("web-pages.automaticDecisions.readingConfig")} error={topic.error != null} /></View>;
  const busy = d.pending || saving;
  const model = view.models.find((m) => m.id === d.model);
  const policy = view.policy;
  return (
    <>
      <View style={{ alignSelf: "stretch", paddingRight: 20, flexDirection: "row", alignItems: "center" }}>
        <View style={{ flex: 1, minWidth: 0 }}><SectionHeader title={name} start={24} /></View>
        {/* In the button's place, as big as it, so the head does not move. */}
        {refreshing
          ? <View style={{ width: 34, height: 34, alignItems: "center", justifyContent: "center" }}><Spinner /></View>
          : <NavButton icon={Icons.Refresh} onClick={() => {
              app.act(t("web-pages.automaticDecisions.refreshAction"), () => core().call("automaticDecisions.refresh", { station }), t("web-pages.automaticDecisions.refreshed"));
            }} />}
      </View>
      {refreshFailed != null && <PageNote text={refreshFailed} />}
      <ListCard>
        <ListRow onClick={busy ? undefined : () => edit("enabled", !d.enabled)}>
          <View style={{ flex: 1, minWidth: 0, gap: 5 }}>
            <T color={C.ink} size={15}>{t("web-pages.automaticDecisions.enabled")}</T>
          </View>
          <Switch on={d.enabled} />
        </ListRow>
        <GoRow
          title={t("web-pages.automaticDecisions.model")}
          value={model?.name ?? (d.model.length === 0 ? t("web-pages.automaticDecisions.pickModel") : t("web-pages.automaticDecisions.unavailable", { model: d.model }))}
          onClick={() => {
            if (!busy) app.sheet = new SheetSpec(0.5, false, null, null, false, () => (
                <>
                  <SheetGrab />
                  <SheetHead title={t("web-pages.automaticDecisions.model")} />
                  {d.pick != null && <ModelList models={d.pick.options} runtime="codex" picked={d.model} onPick={(m: string) => { app.sheet = null; edit("model", m); }} />}
                </>
            ));
          }}
        />
        {/* Asked of the station as saved: only once the rule is on there, and nothing unsaved. */}
        {view.canReview === true && view.settings.completion?.enabled === true && !d.dirty && (
          <ListRow onClick={busy || reviewing ? undefined : () => {
            app.act(t("web-pages.automaticDecisions.reviewAction"), () => core().call("automaticDecisions.review", { station }), t("web-pages.automaticDecisions.reviewStarted"));
          }}>
            <T color={C.ink} size={15} style={{ flex: 1, minWidth: 0 }}>{t("web-pages.automaticDecisions.review")}</T>
            <DoingMark running={reviewing} failed={reviewFailed ?? null} inline />
          </ListRow>
        )}
        {policy != null && (
          <ListRow onClick={() => app.push({ kind: "AutomaticDecisionPolicy", station })}>
            <View style={{ flex: 1, minWidth: 0, gap: 5 }}>
              <T color={C.ink} size={15}>{t("web-pages.archivePolicy.title")}</T>
              <T size={13} color={policy.failed > 0 ? C.red : C.muted}>
                {[t("web-pages.archivePolicy.optionCount", { n: policy.options.length }), policy.summaryText || null].filter((x): x is string => x != null).join(" · ")}
              </T>
            </View>
            <Icon icon={Icons.ChevronRight} size={14} color={C.subtle} />
          </ListRow>
        )}
      </ListCard>
      {d.dirty && (
        <View style={{ paddingHorizontal: 12, flexDirection: "row", gap: 12, alignItems: "center" }}>
          <Button label={t("web-pages.automaticDecisions.save")} primary busy={saving} enabled={!busy} onClick={() => act("save")} />
          <DoingMark running={false} failed={saveFailed ?? null} />
        </View>
      )}
    </>
  );
}

/** A station's archive policy, on a screen of its own (from its row under the station's rule). */
export function AutomaticDecisionPolicyScreen({ current, station }: { current: WorkspaceEntry; station: string }) {
  const insets = useSafeAreaInsets();
  const topic = useTopic<StationView[]>(Topics.stations(current.workspace.id));
  const s = topic.value?.find((x) => x.station === station);
  const view = s?.online === true ? s.overview?.automaticDecisions : undefined;
  const policy = view?.policy;
  return (
    <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: insets.bottom }}>
      <TopBack label={t("web-pages.automaticDecisions.completion")} onBack={() => app.pop()} />
      <LargeTitle small={s?.name ?? ""} big={t("web-pages.archivePolicy.title")} />
      {policy != null && view?.canEdit
        ? <ArchivePolicySection station={station} policy={policy} />
        : topic.value == null
          ? <Waiting shape={WaitShape.Cards} count={2} text={t("common.readingStations")} error={topic.error?.message} />
          : s?.online === true && s.overview == null
            ? <View style={NoteRoom}><WaitLine text={t("common.connecting")} /></View>
            : <PageNote text={topic.error?.message ?? t(
                s?.online !== true ? "web-pages.automaticDecisions.offlineNote"
                  : view != null && !view.canEdit ? "web-pages.automaticDecisions.adminOnly"
                  : "web-pages.automaticDecisions.upgrade",
              )} />}
      <View style={{ height: 30 }} />
    </ScrollView>
  );
}

/** The calls on a policy's draft (`automaticDecisions.policy.*`), by its station and form. */
type PolicyCall = (action: string, input?: Record<string, unknown>) => Promise<unknown>;

/** The station's archive policy (web mobile/AutomaticDecisions.tsx PolicySection): its words and its options in two groups,
 *  each with how many chats the checks put there. A tap edits what it is on, in a sheet (the core's draft, policyForm):
 *  the words, an option (with the chats it got), a new option. */
function ArchivePolicySection({ station, policy }: { station: string; policy: ArchivePolicyView }) {
  const C = useC();
  const form = useMemo(() => crypto.randomUUID(), [station]);
  const topic = useTopic<ArchivePolicyDraft>({ topic: "policyForm", station, form });
  const call: PolicyCall = (action, input = {}) => core().call(`automaticDecisions.policy.${action}`, { station, form, input });
  const edit = (input: Record<string, unknown>) => app.act(t("web-pages.archivePolicy.editAction"), () => call("edit", input));
  useEffect(() => {
    app.act(t("web-pages.archivePolicy.readAction"), () => call("open"));
    return () => app.act(t("web-pages.archivePolicy.closeAction"), () => call("drop"));
  }, [station, form]);
  const busy = topic.value?.pending !== false;
  const saving = useDoing("automaticDecisions.policy.save", { station, form });
  const saveFailed = useDoingFailed("automaticDecisions.policy.save", { station, form });
  // Closed at once; the save goes on beside the policy's title (a spinner, or what went wrong).
  const save = () => { app.sheet = null; app.act(t("web-pages.archivePolicy.saveAction"), () => call("save"), t("web-pages.archivePolicy.saved")); };
  const cancel = () => { app.sheet = null; app.act(t("web-pages.archivePolicy.editAction"), () => call("edit", { reset: true })); };
  // An option of the station's (by its id), else a new one (by its draft key).
  const sheet = (id: string | null, key: string | null, view: ArchiveOptionView | null) => {
    app.sheet = new SheetSpec(0.85, false, null, null, false, () => <PolicySheet station={station} form={form} policy={policy} id={id} draftKey={key} view={view} edit={edit} call={call} cancel={cancel} save={save} />);
  };
  // Back to the station's first: what an earlier sheet left unsaved is gone.
  const open = (id: string | null, view: ArchiveOptionView | null) => app.act(t("web-pages.archivePolicy.editAction"), async () => { await call("edit", { reset: true }); sheet(id, null, view); });
  const add = (archive: boolean) => app.act(t("web-pages.archivePolicy.editAction"), async () => {
    await call("edit", { reset: true });
    const made = await call("edit", { add: archive }) as { options?: { key?: string }[] } | null;
    const key = made?.options?.[made.options.length - 1]?.key;
    if (key == null) return;
    sheet(null, key, null);
  });
  const group = (archive: boolean) => t(archive ? "web-pages.archivePolicy.archive" : "web-pages.archivePolicy.keep");
  const line = [policy.changeText ?? null, policy.summaryText || null].filter((x): x is string => x != null).join(" · ");
  return (
    <>
      <View style={{ alignSelf: "stretch", paddingRight: 20, flexDirection: "row", alignItems: "center" }}>
        <View style={{ flex: 1, minWidth: 0 }}><PageNote text={t("web-pages.archivePolicy.textLead")} /></View>
        <DoingMark running={saving} failed={saveFailed ?? null} inline />
      </View>
      <ListCard>
        <ListRow onClick={busy ? undefined : () => open(null, null)}>
          <T size={14} color={C.ink} line={22} style={{ flex: 1, minWidth: 0 }}>{policy.text}</T>
        </ListRow>
      </ListCard>
      {[true, false].map((archive) => (
        <View key={String(archive)}>
          <SectionHeader title={group(archive)} start={24} />
          <ListCard>
            {policy.options.filter((o) => o.archive === archive).map((o) => (
              <ListRow key={o.id} onClick={busy ? undefined : () => open(o.id, o)}>
                <View style={{ flex: 1, minWidth: 0, gap: 3 }}>
                  <T color={C.ink} size={15}>{o.name}</T>
                  <T size={13} color={C.muted}>{o.rubric}</T>
                </View>
                <T size={13} color={C.muted}>{`${o.count}`}</T>
              </ListRow>
            ))}
            <ListRow onClick={busy ? undefined : () => add(archive)}><T size={15} color={C.accent}>{t("web-pages.archivePolicy.add")}</T></ListRow>
          </ListCard>
        </View>
      ))}
      <T size={13} color={policy.failed > 0 ? C.red : C.muted} style={{ paddingLeft: 24, paddingRight: 24, paddingTop: 4, paddingBottom: 10 }}>{line}</T>
    </>
  );
}

/** A policy sheet: the policy's words (neither `id` nor `draftKey`), or an option (with the chats it got), as the draft has it now. */
function PolicySheet({ station, form, policy, id, draftKey, view, edit, call, cancel, save }: {
  station: string; form: string; policy: ArchivePolicyView; id: string | null;
  /** Kotlin's `key`: React keeps that name for itself. */
  draftKey: string | null;
  view: ArchiveOptionView | null;
  edit: (input: Record<string, unknown>) => void; call: PolicyCall; cancel: () => void; save: () => void;
}) {
  const C = useC();
  const topic = useTopic<ArchivePolicyDraft>({ topic: "policyForm", station, form });
  const d = topic.value;
  if (d == null) return null;
  if (id == null && draftKey == null) {
    return (
      <>
        <SheetGrab />
        <SheetHead title={t("web-pages.archivePolicy.title")} />
        <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingHorizontal: 20, gap: 12 }}>
          <T size={13} color={C.muted}>{t("web-pages.archivePolicy.textLead")}</T>
          <Field value={d.policy} onChange={(it: string) => edit({ policy: it })} placeholder={t("web-pages.archivePolicy.title")} lines={8} />
          <SheetTools dirty={d.dirty === true} remove={null} cancel={cancel} save={save} />
        </ScrollView>
      </>
    );
  }
  const o = d.options.find((x) => (draftKey != null ? x.key === draftKey : x.id === id));
  if (o == null) return null;
  return (
    <>
      <SheetGrab />
      <SheetHead title={view?.name ?? t("web-pages.archivePolicy.newOption")} />
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingHorizontal: 20, gap: 12 }}>
        <Field value={o.name} onChange={(it: string) => edit({ option: o.key, name: it })} placeholder={t("web-pages.archivePolicy.name")} />
        <Field value={o.rubric} onChange={(it: string) => edit({ option: o.key, rubric: it })} placeholder={t("web-pages.archivePolicy.rubric")} lines={3} />
        <Seg options={[t("web-pages.archivePolicy.archive"), t("web-pages.archivePolicy.keep")]} selected={o.archive ? 0 : 1} onSelect={(it: number) => edit({ option: o.key, archive: it === 0 })} fill />
        {view != null && view.count > 0 && (
          <>
            <T size={13} color={C.muted}>{t("web-pages.archivePolicy.chats", { days: policy.days })}</T>
            <ListCard>
              {view.chats.map((c) => (
                <ListRow key={c.session} onClick={() => { cancel(); app.push({ kind: "Chat", station, of: { session: c.session } }); }}>
                  <T size={14} color={C.ink} numberOfLines={1} style={{ flex: 1, minWidth: 0 }}>{c.title}</T>
                  <Icon icon={Icons.ChevronRight} size={14} color={C.subtle} />
                </ListRow>
              ))}
            </ListCard>
          </>
        )}
        <SheetTools
          dirty={d.dirty === true}
          remove={draftKey == null ? () => {
            app.sheet = null;
            app.act(t("web-pages.archivePolicy.saveAction"), async () => { await call("edit", { remove: o.key }); await call("save"); }, t("web-pages.archivePolicy.saved"));
          } : null}
          cancel={cancel}
          save={save}
        />
      </ScrollView>
    </>
  );
}

/** The foot of a policy sheet: removing what it edits (an option of the station's), cancelling, saving. */
function SheetTools({ dirty, remove, cancel, save }: { dirty: boolean; remove: (() => void) | null; cancel: () => void; save: () => void }) {
  const C = useC();
  return (
    <View style={{ alignSelf: "stretch", paddingTop: 4, paddingBottom: 24, flexDirection: "row", gap: 8, alignItems: "center" }}>
      {remove != null && <TextAction label={t("web-pages.archivePolicy.remove")} color={C.red} enabled onClick={remove} />}
      <View style={{ flex: 1 }} />
      <Button label={t("web-pages.archivePolicy.cancel")} primary={false} onClick={() => cancel()} />
      <Button label={t("web-pages.archivePolicy.save")} primary enabled={dirty} onClick={() => save()} />
    </View>
  );
}

/** A word that does something (no frame), as the web's LinkButton. */
function TextAction({ label, color, enabled, onClick }: { label: string; color: string; enabled: boolean; onClick: () => void }) {
  const C = useC();
  return (
    <Pressable disabled={!enabled} onPress={onClick} android_ripple={{ color: withAlpha(C.ink, 0.1) }} style={{ paddingVertical: 4 }}>
      <T size={14} color={enabled ? color : C.subtle}>{label}</T>
    </Pressable>
  );
}
