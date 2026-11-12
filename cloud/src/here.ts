// The product of the origin a request is answered on (guests.ts: one cloud answering as the other product too), for
// the words made while answering it (i18n.ts). Kept for each request's own work, as requests interleave in a Worker.
import { AsyncLocalStorage } from "node:async_hooks";
import { productOf, type Product } from "../../client/i18n/brand.ts";

const product = new AsyncLocalStorage<Product>();

/** `run` with the words it makes naming the product whose origin `origin` is (i18n.ts reads `productHere`). */
export function asProductOf<T>(origin: string, run: () => T): T {
  return product.run(productOf(origin), run);
}

/** The product of the origin being answered, where one is (`asProductOf`). */
export function productHere(): Product | undefined {
  return product.getStore();
}
