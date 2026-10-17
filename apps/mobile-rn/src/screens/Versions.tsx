// A station's software and whether newer versions are out (the station's updates.rs), as the web's Versions.tsx says
// it: the station itself, Claude Code and Codex, each updated (or a runtime installed) from here by whoever may (a
// workspace's owner or admin). Grey but for what wants doing: a newer version out, an update going on, one that failed.
import { useState } from "react";
import { Pressable, View } from "react-native";
import { CoreError } from "../../../../web/src/core/client.ts";
import type { SoftwareVersion } from "../../../../web/src/core/shapes.ts";
import { app as theApp } from "../AppState";
import { deviceLocale, lang, langOf, t } from "../i18n";
import { Icons } from "../ui/Icon";
import { DownloadChip, IconIn, ListCard, ListRow, ripple, SectionHeader } from "../ui/Parts";
import { T } from "../ui/Text";
import { useC } from "../ui/Theme";
import { Spinner } from "../ui/Waiting";
import { Switch } from "./Connects";

/**
 * The station's versions as a section of its page: one to a row, then the check (with when it last looked). `updates`:
 * its overview's (none from a station older than them: nothing shows); `manager`: may update; `beta`: the 测试版 switch
 * is offered (the core's `betaOffered`).
 */
export function Versions({ station, updates, manager, beta = false }: { station: string; updates: SoftwareVersion[] | null | undefined; manager: boolean; beta?: boolean }) {
  const app = theApp;
  const C = useC();
  const [updating, setUpdating] = useState<string | null>(null);
  const [checking, setChecking] = useState(false);
  const [failed, setFailed] = useState<string | null>(null);
  // The channel asked for, while it is being set: the switch shows it at once.
  const [switching, setSwitching] = useState<string | null>(null);
  // Updating by itself as asked, while it is being turned on or off.
  const [turning, setTurning] = useState<boolean | null>(null);
  if (updates == null || updates.length === 0) return null;
  const api = app.api(station);
  /** A call of this section: what went wrong said under it, `after` once it is over either way. */
  const go = (run: () => Promise<void>, after: () => void) => {
    void run().catch((e: unknown) => { if (e instanceof CoreError) setFailed(e.message); else throw e; }).finally(after);
  };
  const checked = updates[0]!.checkedAt;
  const own = updates.find((v) => v.id === "station");
  const channel = own?.channel;
  const auto = own?.auto;
  const on = (switching ?? channel) === "beta";
  const autoOn = turning ?? auto;
  return (
    <>
      <SectionHeader title={t("android-misc.versions.title")} trailing={checked != null ? t("android-misc.versions.lastChecked", { time: new Intl.DateTimeFormat(appLocale(), { dateStyle: "short", timeStyle: "short" }).format(new Date(checked)) }) : null} start={24} />
      <ListCard>
        {updates.map((v) => (
          <VersionRow key={v.id} v={v} manager={manager} busy={updating === v.id} onUpdate={() => {
            setUpdating(v.id); setFailed(null);
            go(() => api.updateSoftware(v.id), () => setUpdating(null));
          }} />
        ))}
        {beta && manager && channel != null && (
          <ListRow onClick={switching != null ? null : () => {
            const to = on ? "stable" : "beta";
            setSwitching(to); setFailed(null);
            go(() => api.setSoftwareChannel(to), () => setSwitching(null));
          }}>
            <View style={{ flex: 1, minWidth: 0 }}>
              <T size={15} color={C.ink}>{t("android-misc.versions.beta")}</T>
              <T size={13} color={C.muted}>{t("android-misc.versions.beta.text")}</T>
            </View>
            <Switch on={on} />
          </ListRow>
        )}
        {manager && auto != null && (
          <ListRow onClick={turning != null ? null : () => {
            const to = !autoOn;
            setTurning(to); setFailed(null);
            go(() => api.setSoftwareAuto(to), () => setTurning(null));
          }}>
            <View style={{ flex: 1, minWidth: 0 }}>
              <T size={15} color={C.ink}>{t("android-misc.versions.auto")}</T>
              <T size={13} color={C.muted}>{own?.idleOnly === true ? t("android-misc.versions.auto.idle") : t("android-misc.versions.auto.text")}</T>
            </View>
            <Switch on={autoOn === true} />
          </ListRow>
        )}
        <ListRow onClick={checked == null || checking ? null : () => {
          setChecking(true); setFailed(null);
          go(() => api.checkSoftware(), () => setChecking(false));
        }}>
          <T size={15} color={C.muted} style={{ flex: 1, minWidth: 0 }}>{checked == null ? t("android-misc.versions.checkingVersions") : checking ? t("android-misc.versions.checking") : t("android-misc.versions.check")}</T>
          {(checking || checked == null) && <Spinner />}
        </ListRow>
      </ListCard>
      {failed != null && <T size={13} color={C.red} style={{ paddingHorizontal: 24, paddingBottom: 10 }}>{failed}</T>}
    </>
  );
}

/** One piece of software: its name and version, what is out, and what may be done with it. */
function VersionRow({ v, manager, busy, onUpdate }: { v: SoftwareVersion; manager: boolean; busy: boolean; onUpdate: () => void }) {
  const C = useC();
  const shown = v.installed ? v.version ?? (v.id === "station" ? t("android-misc.versions.dev") : t("android-misc.versions.unknown")) : t("android-misc.versions.notInstalled");
  // What the web says on hover, said under the name.
  const note = [
    v.state === "idle" ? v.done : null,
    v.note,
    v.installed && !v.newer && v.downgrade !== true && v.latest != null ? t("android-misc.updates.latest") : null,
    v.installed && v.latest == null && v.checkedAt != null ? t("android-misc.versions.checkFailed") : null,
    v.state === "failed" ? v.message : null,
  ].filter((x): x is string => x != null && x.trim() !== "").join(t("android-misc.versions.sep"));
  const action = (label: string) => {
    if (!(manager && v.updatable)) return null;
    if (busy) return <Spinner inline />;
    return (
      <Pressable onPress={onUpdate} android_ripple={ripple(C.ink)}>
        <T size={13} weight="500" color={C.accent}>{label}</T>
      </Pressable>
    );
  };
  const latest = v.latest;
  const end = (() => {
    if (v.state === "updating") {
      const percent = v.percent;
      return (
        <View style={{ flexDirection: "row", alignItems: "center", gap: 6 }}>
          {percent != null ? <DownloadChip percent={percent} /> : <Spinner inline />}
          {/* Where it is, as the station says (one older than that: nothing more than 正在更新). */}
          <T size={13} weight="500" color={C.accentInk}>{v.progress ?? (v.installed ? t("android-misc.versions.updating") : t("android-misc.versions.installing"))}</T>
        </View>
      );
    }
    if (v.state === "failed") return (
      <>
        <T size={13} weight="500" color={C.red}>{v.installed ? t("android-misc.versions.updateFailed") : t("android-misc.versions.installFailed")}</T>
        {action(t("common.retry"))}
      </>
    );
    if (!v.installed) return action(t("android-misc.versions.install"));
    if (v.newer && latest != null) return <><Latest version={latest} />{action(t("android-misc.versions.update"))}</>;
    if (v.downgrade === true && latest != null) return <><Latest version={latest} />{action(t("android-misc.versions.backToStable"))}</>;
    return null;
  })();
  return (
    <ListRow>
      <View style={{ flex: 1, minWidth: 0 }}>
        {/* The name's line, with what is out and what may be done at its end: all its words on one baseline. */}
        <View style={{ flexDirection: "row", alignItems: "center" }}>
          <View style={{ flex: 1, minWidth: 0, flexDirection: "row", alignItems: "baseline", gap: 6 }}>
            <T size={15} color={C.ink} numberOfLines={1}>{v.name}</T>
            <T size={13} color={C.muted} numberOfLines={1} ellipsizeMode="tail" style={{ flexShrink: 1 }}>{shown}</T>
            {v.channel === "beta" && (
              <View style={{ borderRadius: 999, overflow: "hidden", backgroundColor: C.accentBg, paddingHorizontal: 6, paddingVertical: 1 }}>
                <T size={11} weight="500" color={C.accentInk} numberOfLines={1}>{t("android-misc.versions.beta")}</T>
              </View>
            )}
          </View>
          <View style={{ paddingLeft: 12, flexDirection: "row", alignItems: "center", gap: 10 }}>{end}</View>
        </View>
        {/* Its line kept while there is nothing to say: the rows stay put as checks and updates come and go. */}
        <T size={13} color={v.state === "failed" ? C.red : C.muted}>{note || " "}</T>
      </View>
    </ListRow>
  );
}

/** What it would go to: an arrow drawn as tall as the figures, at their stroke, centred on them, then the version. */
function Latest({ version }: { version: string }) {
  const C = useC();
  return (
    <View style={{ flexDirection: "row", alignItems: "center", gap: 3 }}>
      <IconIn icon={Icons.ArrowRight} size={18} tint={C.accentInk} />
      <T size={13} weight="500" color={C.accentInk}>{version}</T>
    </View>
  );
}

/** The phone's locale when it is in the app's language, else that language's: dates as the words around them are. */
function appLocale(): string {
  const device = deviceLocale();
  return langOf(device) === lang() ? device : lang() === "zh" ? "zh-CN" : "en";
}
