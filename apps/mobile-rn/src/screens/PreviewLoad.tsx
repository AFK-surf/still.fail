// How far a web service's page has loaded in the preview (the core's `previewLoad` topic): a ring in its bar, and,
// tapped, each of the page's requests, how it went and how long it took.
import { Pressable, ScrollView, View } from "react-native";
import Svg, { Circle } from "react-native-svg";
import type { Topic } from "../../../../web/src/core/client.ts";
import { useTopic } from "../../../../web/src/core/react.ts";
import { app, SheetSpec } from "../AppState";
import { t } from "../i18n";
import { SheetHead } from "../ui/Sheet";
import { T } from "../ui/Text";
import { useC, withAlpha } from "../ui/Theme";

export interface PreviewLoading { percent: number; total: number; finished: number; failed: number; resources: PreviewResource[] }
export interface PreviewResource { id: number; method: string; path: string; since: number; ended?: number | null; status?: number | null; error?: string | null }

const loadTopic = (station: string, port: number): Topic => ({ topic: "previewLoad", station, port });
const label = (l: PreviewLoading) =>
  l.failed > 0 ? t("android-chat.load.label.failed", { percent: l.percent, finished: l.finished, total: l.total, failed: l.failed })
    : t("android-chat.load.label", { percent: l.percent, finished: l.finished, total: l.total });

/** The ring: how much of the page has come (red once any of it failed). */
export function PreviewLoad({ station, port }: { station: string; port: number }) {
  const C = useC();
  const state = useTopic<PreviewLoading>(loadTopic(station, port));
  const value = state.value;
  if (!value) return null;
  const color = value.failed > 0 ? C.red : C.muted;
  const round = 2 * Math.PI * 8;
  return (
    <Pressable
      accessibilityLabel={label(value)}
      onPress={() => { app.sheet = new SheetSpec(0.62, false, null, null, false, () => <PreviewLoadDetails station={station} port={port} />); }}
      style={{ width: 28, height: 28, alignItems: "center", justifyContent: "center" }}
    >
      <Svg width={20} height={20}>
        <Circle cx={10} cy={10} r={8} stroke={withAlpha(color, 0.18)} strokeWidth={2} fill="none" />
        <Circle cx={10} cy={10} r={8} stroke={color} strokeWidth={2} fill="none" strokeDasharray={`${(round * value.percent) / 100} ${round}`} transform="rotate(-90 10 10)" />
      </Svg>
    </Pressable>
  );
}

function PreviewLoadDetails({ station, port }: { station: string; port: number }) {
  const C = useC();
  const state = useTopic<PreviewLoading>(loadTopic(station, port));
  const value = state.value;
  if (!value) return null;
  return (
    <View style={{ flex: 1, paddingHorizontal: 20 }}>
      <SheetHead title={label(value)} />
      <T size={12} color={C.muted}>{t("android-chat.load.note")}</T>
      <ScrollView contentContainerStyle={{ paddingTop: 12 }}>
        {value.total === 0 ? <T size={13} color={C.muted}>{t("android-chat.load.waiting")}</T> : null}
        {value.resources.map((r) => {
          const color = r.error != null || (r.status ?? 0) >= 400 ? C.red : C.muted;
          return (
            <View key={r.id} style={{ width: "100%", paddingVertical: 6 }}>
              <View style={{ flexDirection: "row", gap: 10, alignItems: "center" }}>
                <T size={13} color={color} numberOfLines={1} style={{ flex: 1, minWidth: 0 }}>{r.path}</T>
                <T size={12} color={color}>{r.ended == null ? t("common.reading") : r.error != null ? t("android-chat.load.failed") : `${r.status}`}</T>
                {r.ended != null ? <T size={12} color={color}>{`${Math.max(0, Math.trunc(r.ended - r.since))} ms`}</T> : null}
              </View>
              {r.error != null ? <T size={12} color={color}>{r.error}</T> : null}
            </View>
          );
        })}
      </ScrollView>
    </View>
  );
}
