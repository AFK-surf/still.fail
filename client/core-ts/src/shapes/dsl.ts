// How the shapes are written (schema.ts): a struct's fields as they go on the wire, the words of a closed set, a
// union told apart by a tag. conform.ts walks them; scripts/shapes.ts makes the clients' types of them.

export type Ty = string | { opt: Ty } | { vec: Ty } | { map: Ty } | { tuple: Ty[] };
/// `client`: the type the clients see where it is not the wire's (`I54`: a whole number a JS number holds).
export type Field = { name: string; ty: Ty; default: boolean; skipNone: boolean; client?: Ty; doc?: string };
/// `client: false`: a shape only the core uses (the clients get no type for it).
type Common = { doc?: string; client: boolean };
export type Shape =
  | ({ kind: "struct"; fields: Field[]; default: boolean } & Common)
  | ({ kind: "enum"; values: string[]; default: string | null } & Common)
  | ({ kind: "tagged"; tag: string; content: string; variants: Record<string, Ty>; names: Record<string, string> } & Common);

type FieldOptions = { default?: true; skipNone?: true; client?: Ty; doc?: string };
type Options = { doc?: string; client?: false };

export const opt = (ty: Ty): Ty => ({ opt: ty });
export const vec = (ty: Ty): Ty => ({ vec: ty });
export const map = (ty: Ty): Ty => ({ map: ty });
export const tuple = (...tys: Ty[]): Ty => ({ tuple: tys });

const isOpt = (ty: Ty) => typeof ty === "object" && "opt" in ty;

/// A struct: each field `[wire name, type, options]`. An absent option is left out unless `keepNone`; `default`: a field
/// missing from what is read takes its type's default (for the whole struct, or one field).
export function struct(fields: [string, Ty, FieldOptions?][], o: Options & { default?: true; keepNone?: true } = {}): Shape {
  return {
    kind: "struct",
    default: o.default === true,
    client: o.client !== false,
    doc: o.doc,
    fields: fields.map(([name, ty, f = {}]) => ({ name, ty, default: f.default === true, skipNone: isOpt(ty) && (o.keepNone !== true || f.skipNone === true), client: f.client, doc: f.doc })),
  };
}

/// A closed set of words; `default`: the one a missing value reads as.
export function words(values: string[], o: Options & { default?: string } = {}): Shape {
  return { kind: "enum", values, default: o.default ?? null, client: o.client !== false, doc: o.doc };
}

/// A union, `{ <tag>: <word>, <content>: … }`: each variant `[word, its name in Kotlin, its content's type]`.
export function tagged(tag: string, content: string, variants: [string, string, Ty][], o: Options = {}): Shape {
  return {
    kind: "tagged",
    tag,
    content,
    variants: Object.fromEntries(variants.map(([w, , ty]) => [w, ty])),
    names: Object.fromEntries(variants.map(([w, n]) => [w, n])),
    client: o.client !== false,
    doc: o.doc,
  };
}
