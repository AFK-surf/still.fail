// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `presets` whole on a
// workspace of real size.
///|
fn init {
  let asked =
    #|{"topic":"presets","station":"ws/maple"}
  let value =
    #|{"presets":[{"id":"p-app","name":"still.fail App","dirs":[{"path":"/Users/maple/src/app","repo":"github.com/acme/app"},{"path":"/Users/maple/src/design-system","repo":"github.com/acme/design-system"}],"instructions":"改 UI 前先在 Pixel 8 和 iPhone 16 上各录一段前后对比；提交前跑 `pnpm test` 和 `pnpm exec tsgo --noEmit`。","createdBy":"me@x.com","createdAt":1789549200000,"updatedAt":1791104400000},{"id":"p-infra","name":"Infra","dirs":[{"path":"/Users/maple/src/infra","repo":"github.com/acme/infra"}],"instructions":"生产环境的改动先在 staging 跑一遍，改动前在 #infra 说一声。","createdBy":"lina@acme.dev","createdAt":1787734800000,"updatedAt":1790499600000}],"candidates":[{"path":"/Users/maple/src/app","name":"app","repo":"github.com/acme/app","chats":40,"lastAt":1791259200000,"where":"~/src/app"},{"path":"/Users/maple/src/station","name":"station","repo":"github.com/acme/station","chats":34,"lastAt":1791241200000,"where":"~/src/station"},{"path":"/Users/maple/src/website","name":"website","repo":"github.com/acme/website","chats":28,"lastAt":1791223200000,"where":"~/src/website"},{"path":"/Users/maple/src/infra","name":"infra","repo":"github.com/acme/infra","chats":22,"lastAt":1791205200000,"where":"~/src/infra"},{"path":"/Users/maple/src/design-system","name":"design-system","repo":"github.com/acme/design-system","chats":16,"lastAt":1791187200000,"where":"~/src/design-system"},{"path":"/Users/maple/src/mobile","name":"mobile","repo":"github.com/acme/mobile","chats":10,"lastAt":1791169200000,"where":"~/src/mobile"}]}
  put(asked, value)
}
