// A station's update notice where it is named (StationUpdate.kt): the same core-owned open/dismiss/update state as the
// web's StationUpdate, a dot and its words that open a popover under them, its arrow at the dot.
import { useEffect, useRef, useState } from "react";
import { Modal, Pressable, StyleSheet, View, useWindowDimensions } from "react-native";
import Svg, { Path } from "react-native-svg";
import { core } from "../../../../web/src/core/react.ts";
import type { StationUpdateNotice } from "../../../../web/src/core/shapes.ts";
import { useDoing, useDoingFailed } from "../../../../web/src/doing.ts";
import { app } from "../AppState";
import { t } from "../i18n";
import { DoingMark } from "../ui/Controls";
import { Icon, Icons } from "../ui/Icon";
import { Smooth } from "../ui/Smooth";
import { T } from "../ui/Text";
import { raised, useC, withAlpha } from "../ui/Theme";
import { Progress } from "../ui/Waiting";

/** Where the popover's top is, under its anchor: a little over it (Kotlin's -4dp gap). */
const GAP = -4;
/** How far the popover keeps from the window's right. */
const MARGIN = 12;
/** The dot's centre, from the anchor's start. */
const DOT_CENTER = 3;
/** Round the card, inside the popover (where its shadow goes). */
const PAD = 12;

/** The same core-owned open/dismiss/update state as the web's StationUpdate. */
export function StationUpdateControl({ station, notice }: { station: string; notice: StationUpdateNotice | null | undefined }) {
  const C = useC();
  const busy = useDoing("software.update", { station, id: "station" });
  const failed = useDoingFailed("software.update", { station, id: "station" });
  const window = useWindowDimensions();
  const anchor = useRef<View>(null);
  // The anchor's box in the window, measured as the popover opens.
  const [at, setAt] = useState<{ x: number; y: number; width: number; height: number } | null>(null);
  const open = notice?.open === true;
  useEffect(() => {
    if (!open) return;
    anchor.current?.measureInWindow((x, y, width, height) => setAt({ x, y, width, height }));
  }, [open, window.width, window.height]);
  if (notice == null) return null;
  const control = (action: string) => {
    app.act(t("android-misc.stationUpdate.noticeWhat"), () => core().call("station.updateNotice", { station, action, version: notice.version }));
  };
  const accent = notice.tone === "trouble" ? C.red : C.accentInk;
  const width = Math.min(284, window.width - 24);
  // The popover as Kotlin's PopupPositionProvider places it: its right MARGIN from the window's, its top under the
  // anchor; the arrow at the dot (left to right; a right-to-left layout is not this app's).
  const contentWidth = width + PAD * 2;
  const left = Math.max(0, window.width - contentWidth - MARGIN);
  const top = at ? at.y + at.height + GAP : 0;
  const arrowX = at ? at.x + DOT_CENTER - left : 0;
  const surface = raised(C);
  const half = 7;
  const edge = 12;
  const x = Math.min(Math.max(arrowX, 30), contentWidth - 30);
  const versions = [notice.from, notice.to].filter((v): v is string => v != null).join(" → ");
  return (
    <View>
      <Pressable
        ref={anchor}
        accessibilityRole="button"
        accessibilityLabel={notice.text}
        onPress={() => control(notice.open === true ? "close" : "open")}
        android_ripple={{ color: withAlpha(C.ink, 0.1) }}
        style={{ minHeight: 32, flexDirection: "row", alignItems: "center", gap: 5 }}
      >
        <View style={{ width: 6, height: 6, borderRadius: 3, backgroundColor: accent }} />
        <T size={12} line={18} color={accent} numberOfLines={1} ellipsizeMode="clip">{notice.label ?? notice.text}</T>
      </Pressable>
      {open && at != null && (
        <Modal transparent visible animationType="none" statusBarTranslucent navigationBarTranslucent onRequestClose={() => control("close")}>
          {/* A tap beside it closes it (the popup's dismissal). */}
          <Pressable style={StyleSheet.absoluteFill} onPress={() => control("close")} />
          <View style={{ position: "absolute", left, top, width: contentWidth, padding: PAD }}>
            {/* The arrow, behind the card, at the dot. */}
            <Svg width={contentWidth} height={edge + 1} style={{ position: "absolute", left: 0, top: 0 }}>
              <Path d={`M${x - half} ${edge + 1}L${x} ${edge - half}L${x + half} ${edge + 1}Z`} fill={surface} />
            </Svg>
            <Smooth
              radius={14}
              style={{ width, backgroundColor: surface, elevation: 12, shadowColor: withAlpha("#000000", 0.08), shadowOpacity: 1, shadowRadius: 12, shadowOffset: { width: 0, height: 4 }, paddingLeft: 14, paddingRight: 10, paddingTop: 12, paddingBottom: 12, gap: 8 }}
            >
              <View style={{ flexDirection: "row", alignItems: "flex-start", gap: 8 }}>
                <View style={{ flex: 1, minWidth: 0, gap: 2 }}>
                  {notice.station != null ? (
                    <View style={{ flexDirection: "row", alignItems: "center", gap: 8 }}>
                      <T size={13} line={19} weight="500" color={C.ink} numberOfLines={1} style={{ flexShrink: 1, minWidth: 0 }}>{notice.station}</T>
                      {notice.label != null && <T size={12} line={19} color={accent} numberOfLines={1} ellipsizeMode="clip">{notice.label}</T>}
                    </View>
                  ) : (
                    <T size={13} line={19} weight="500" color={C.ink}>{notice.text}</T>
                  )}
                  {notice.detail != null && <T size={12} line={17} color={C.muted}>{notice.detail}</T>}
                </View>
                <Pressable
                  accessibilityRole="button"
                  accessibilityLabel={notice.dismissible === true ? t("android-misc.stationUpdate.dismiss") : t("android-misc.stationUpdate.collapse")}
                  onPress={() => control(notice.dismissible === true ? "dismiss" : "close")}
                  android_ripple={{ color: withAlpha(C.ink, 0.1) }}
                  style={{ width: 32, height: 32, transform: [{ translateY: -6 }], alignItems: "center", justifyContent: "center" }}
                >
                  <Icon icon={Icons.Close} size={14} color={C.muted} />
                </Pressable>
              </View>
              {notice.tone === "busy" && notice.station != null && (
                <View style={{ paddingRight: 4 }}><Progress part={notice.percent != null ? notice.percent / 100 : null} /></View>
              )}
              {(versions.length > 0 || notice.canUpdate === true) && (
                <View style={{ alignSelf: "stretch", paddingRight: 4, flexDirection: "row", alignItems: "center", gap: 12 }}>
                  <T size={11} line={16} mono color={C.muted} numberOfLines={1} style={{ flex: 1, minWidth: 0 }}>{versions}</T>
                  {notice.canUpdate === true && (
                    <View style={{ borderRadius: 999, overflow: "hidden", backgroundColor: C.accentBg }}>
                      <Pressable
                        disabled={busy}
                        accessibilityRole="button"
                        onPress={() => app.act(t("android-misc.stationUpdate.updateWhat"), () => app.api(station).updateSoftware("station"))}
                        android_ripple={{ color: withAlpha(C.ink, 0.1) }}
                        style={{ paddingHorizontal: 12, paddingVertical: 6, flexDirection: "row", alignItems: "center", gap: 4 }}
                      >
                        <DoingMark running={busy} failed={failed ?? null} inline />
                        <T size={12} line={16} weight="500" color={C.accentInk}>
                          {busy ? t("android-misc.stationUpdate.updating") : notice.tone === "trouble" ? t("common.retry") : t("android-misc.stationUpdate.updateNow")}
                        </T>
                      </Pressable>
                    </View>
                  )}
                </View>
              )}
            </Smooth>
          </View>
        </Modal>
      )}
    </View>
  );
}
