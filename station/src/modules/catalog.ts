// The modules still.fail makes, which any station may install as a package (modules/packages.ts) when its owners or
// admins turn one on (api/routes/modules.ts): no one writes config.json for them.
export type Offered = { id: string; package: string };

export const CATALOG: readonly Offered[] = [];
