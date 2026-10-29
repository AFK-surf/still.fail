// Rarely changed network controls, kept collapsed on the station's settings page.
import { useState } from "react";
import type { StationNetwork } from "./core/shapes.ts";
import { useCall } from "./core/react.ts";
import { useDoing } from "./doing.ts";
import { useAct } from "@stillfail/ui/toast.tsx";
import { Button, Select, Section } from "./ui.tsx";
import { t } from "./i18n.ts";

export function NetworkSection({ station, network, manager }: { station: string; network: StationNetwork; manager: boolean }) {
  const [open, setOpen] = useState(false);
  const call = useCall();
  const act = useAct();
  const busy = useDoing("network.setCongestion", { station });
  return <Section title={<Button variant="ghost" aria-expanded={open} onClick={() => setOpen(!open)}>{t("web-pages.stations.network.advanced")}</Button>}>
    {open && <Section title={t("web-pages.stations.network.algorithm")} description={t("web-pages.stations.network.note")}>
      <Select disabled={!manager || busy} label={t("web-pages.stations.network.algorithm")} value={network.congestion}
        options={["cubic", "bbr"].map((value) => ({ value, label: t(`web-pages.stations.network.${value}`) }))}
        onChange={(congestion) => { void act(call("network.setCongestion", { station, congestion }), t("web-pages.stations.network.what"), t("web-pages.stations.network.saved")); }} />
    </Section>}
  </Section>;
}
