// What the scripts use of Babel (its types are a package of their own): hermes-bundle.ts transforms, writes.ts reads
// the core's files and walks them.
declare module "@babel/core" {
  export function transformSync(code: string, options: Record<string, unknown>): { code?: string | null } | null;
  export function parseSync(code: string, options: Record<string, unknown>): object | null;
  /// A place in the tree, as Babel's traverse gives it; only what writes.ts uses, loosely.
  export interface NodePath {
    node: any;
    parent: any;
    parentPath: NodePath;
    scope: { getBinding(name: string): ({ kind: string } & object) | undefined };
    get(key: string): NodePath | NodePath[] | any;
    traverse(visitors: Record<string, (path: any) => void>): void;
    skip(): void;
    [is: `is${string}`]: (...args: any[]) => boolean;
  }
  export function traverse(ast: object, visitors: Record<string, (path: any) => void>): void;
  export const types: any;
}
