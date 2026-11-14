// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `linkPreview pull` whole on a
// workspace of real size.
///|
fn init {
  let asked =
    #|{"topic":"linkPreview","station":"ws/maple","url":"https://github.com/acme/app/pull/5244"}
  let value =
    #|{"kind":"github_pull_request","url":"https://github.com/acme/app/pull/5244","title":"Android：列表行高首帧算好，滚动不再重新测量","repository":"acme/app","number":5244,"state":"open","author":{"login":"lina-park"},"additions":412,"deletions":187,"changedFiles":14,"comments":6,"labels":["android","performance","needs-review"],"checks":{"passed":23,"failed":0,"pending":2},"updatedAt":1791273600000,"time":{"updatedAt":{"at":1791273600000,"ago":"1 小时前","full":"10/6 08:00:00","until":"1 分钟内","past":true}}}
  put(asked, value)
}
