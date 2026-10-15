// The measures' types, for the web app's development build (web/src/dev/offs.ts).
export function corners(mark?: boolean): { measured: number; wrong: string[] };
export function panels(mark?: boolean): { surfaces: number; corners: number; wrong: string[] };
