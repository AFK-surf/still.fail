function fail(message: string): never { throw new Error(message); }
export default {
  equal(actual: unknown, expected: unknown, message = "equal") {
    if (!Object.is(actual, expected)) fail(`${message}: ${String(actual)} != ${String(expected)}`);
  },
  deepEqual(actual: unknown, expected: unknown, message = "deepEqual") {
    if (JSON.stringify(actual) !== JSON.stringify(expected)) fail(`${message}: ${JSON.stringify(actual)} != ${JSON.stringify(expected)}`);
  },
  throws(fn: () => void, expected: RegExp | ((error: unknown) => boolean)) {
    let threw = false;
    try { fn(); } catch (error) {
      threw = true;
      if (expected instanceof RegExp ? !expected.test(String(error)) : !expected(error)) fail(`unexpected exception: ${String(error)}`);
    }
    if (!threw) fail("did not throw");
  },
};
