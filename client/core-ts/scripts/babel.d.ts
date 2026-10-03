// What scripts/hermes-bundle.ts uses of Babel (its types are a package of their own).
declare module "@babel/core" {
  export function transformSync(code: string, options: Record<string, unknown>): { code?: string | null } | null;
}
