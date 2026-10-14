import { style } from "@vanilla-extract/css";
import { name as stationName } from "../cloud/StationCards.css.ts";

// This machine's station (LocalStation.tsx) is a workspace's station card (cloud/StationCards.css.ts); its name is
// only said here, not a button to its details.
export const name = style([stationName, { cursor: "default", selectors: { "&:hover": { textDecoration: "none" } } }]);
