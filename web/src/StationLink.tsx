// How this device reaches a station, said after its name or icon where a chat names it (the bar's agent tile, its
// station tag): away, coming back, else the way its connection goes (直连, 北京中继, 正在选路), its round trip only
// while that is slow. Followed alone, a word at a time, not the station's whole view (its load changes much more often).
import { useTopicSelect } from "./core/react.ts";
import type { Level, StationView } from "./core/shapes.ts";
import { t } from "./i18n.ts";
import { scopeOf } from "./station.tsx";
import * as css from "./StationLink.css.ts";

export type StationLink = { text: string; level: Level };

export function useStationLink(address: string): StationLink | null {
  return useTopicSelect<StationView[], StationLink | null>({ topic: "stations", scope: scopeOf(address) }, (st) => {
    const s = st.value?.find((x) => x.station === address);
    if (!s) return null;
    if (!s.online) return { text: t("web-pages.stations.offline"), level: "red" };
    if (s.reconnecting) return { text: t("web-pages.stations.connecting"), level: "ok" };
    if (!s.net) return null;
    const slow = s.net.rtt && s.net.rtt.level !== "ok" ? s.net.rtt : null;
    return { text: slow ? `${s.net.path} · ${slow.text}` : s.net.path, level: slow?.level ?? "ok" };
  }, (a, b) => a === b || (!!a && !!b && a.text === b.text && a.level === b.level));
}

/** The words, grey while all is well, in their level's colour while not. */
export function StationLinkText({ link }: { link: StationLink }) {
  return <span className={css.link} data-level={link.level}>{link.text}</span>;
}
