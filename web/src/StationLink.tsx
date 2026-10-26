// How this device reaches a station, as a dot where a chat names it (the bar's agent tile, its station tag): straight
// there (green), through a relay (amber), away (red), else coming back or a way still being chosen (grey). Its
// words (直连, 北京中继, 离线) are its label. Followed alone, not the station's whole view (its load changes much more often);
// how it is reached only (`way`), not its round trip, which would have it sampled wherever a chat names it.
import { useTopicSelect } from "./core/react.ts";
import type { StationView } from "./core/shapes.ts";
import { t } from "./i18n.ts";
import { scopeOf } from "./station.tsx";
import * as css from "./StationLink.css.ts";

export type StationLink = { via: "direct" | "relay" | "waiting" | "offline"; text: string };

export function useStationLink(address: string): StationLink | null {
  return useTopicSelect<StationView[], StationLink | null>({ topic: "stations", scope: scopeOf(address) }, (st) => {
    const s = st.value?.find((x) => x.station === address);
    if (!s) return null;
    if (!s.online) return { via: "offline", text: t("web-pages.stations.offline") };
    if (s.reconnecting) return { via: "waiting", text: t("common.connecting") };
    if (!s.way) return null;
    const via = s.way.via === "direct" ? "direct" : s.way.via === "relay" ? "relay" : s.way.via === "choosing" ? "waiting" : null;
    return via && { via, text: s.way.path };
  }, (a, b) => a === b || (!!a && !!b && a.via === b.via && a.text === b.text));
}

/** The dot in a line, before the station's name. */
export function StationDot({ link }: { link: StationLink }) {
  return <span className={css.dot} data-via={link.via} role="img" aria-label={link.text} />;
}

/** The dot on the bottom-right corner of what it is put in (which is `css.corner`). */
export function StationCornerDot({ link }: { link: StationLink | null }) {
  return link && <span className={css.cornerDot} data-via={link.via} aria-hidden="true" />;
}
