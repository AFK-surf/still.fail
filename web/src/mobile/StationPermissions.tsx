// A Mac station's grants on its page on a phone (./Stations.tsx), as the Android app has them (screens/Stations.kt): the
// wide screen's (../StationPermissions.tsx), a row each on a card, what wants doing at its end as words in the accent
// (asking for one, opening the screen to grant it there); what is unavailable now under the card.
import type { StationGrant, StationPermissions } from "../core/shapes.ts";
import { useDoing } from "../doing.ts";
import { grantEnd, grantMark, useGrantRequest, type GrantEnd } from "../StationPermissions.tsx";
import { t } from "../i18n.ts";
import { useApp } from "./app.tsx";
import { Spinner } from "@stillfail/ui/waiting.tsx";
import { ListCard, ListRow, SectionHeader } from "./parts.tsx";
import * as partsCss from "./styles/parts.css.ts";
import * as listsCss from "./styles/lists.css.ts";
import * as css from "./StationPermissions.css.ts";

export function PermissionsCard({ station, permissions: p }: { station: string; permissions: StationPermissions }) {
  const app = useApp();
  const request = useGrantRequest(station, (link) => app.push(link));
  return (
    <>
      <SectionHeader title={t("web-pages.stations.permissions.section")} start={24} />
      <ListCard>
        {p.grants.map((g) => <Row key={g.id} station={station} g={g} end={grantEnd(g, p)} onRequest={() => request(g, p)} onOpen={() => p.screen && app.push(p.screen)} />)}
      </ListCard>
      {p.note && <p className={css.mNote}>{p.note}</p>}
    </>
  );
}

function Row({ station, g, end, onRequest, onOpen }: { station: string; g: StationGrant; end: GrantEnd; onRequest(): void; onOpen(): void }) {
  const busy = useDoing("permissions.request", { station, grant: g.id });
  const Mark = grantMark(g.id);
  return (
    <ListRow>
      <Mark size={18} className={partsCss.mSubtle} />
      <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
        <span className={listsCss.mRowTitle}>{g.name}</span>
        <span className={css.mLine} data-asking={g.asking || undefined}>{g.line}</span>
      </span>
      {end === "request" ? (busy ? <Spinner inline /> : <button type="button" className={css.mAction} aria-label={t("web-pages.stations.permissions.requestLabel", { name: g.name })} onClick={onRequest}>{t("web-pages.stations.permissions.request")}</button>)
        : end === "open" ? <button type="button" className={css.mAction} onClick={onOpen}>{t("web-pages.stations.permissions.openScreen")}</button>
        : <span className={css.mState} data-end={end}>{t(end === "granted" ? "web-pages.stations.permissions.granted" : end === "waiting" ? "web-pages.stations.permissions.waiting" : "web-pages.stations.permissions.missing")}</span>}
    </ListRow>
  );
}
