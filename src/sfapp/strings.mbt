// The words, as the Android app says them in Chinese (ember client/i18n/catalog/zh: android-chat.json,
// android-settings.json, android-misc.json, common.json); `{name}` is put in by `fill`.

///|
let zh : Map[String, String] = {
  "android-chat.annotate.copied": "已复制",
  "android-chat.annotate.selectAll": "全选",
  "android-chat.attach.camera": "拍照",
  "android-chat.attach.files": "文件",
  "android-chat.attach.photos": "照片",
  "android-chat.attach.recent.allow": "显示最近照片",
  "android-chat.attach.recent.more": "选择更多照片",
  "android-chat.attach.title": "添加到消息",
  "android-chat.chat.delete.verb": "删除",
  "android-chat.chat.retry.verb": "重新发送",
  "android-chat.chat.unsent.toast": "未发送",
  "android-chat.chat.unsent.why": "发送失败：{error}",
  "android-chat.composer.archived": "已归档，还原后才能发送消息。 ",
  "android-chat.composer.archived.placeholder": "还原对话后才能发送",
  "android-chat.composer.offline": "此 station 已离线：当前显示的是之前读取的内容，暂时无法发送消息",
  "android-chat.composer.restore": "还原对话",
  "android-chat.composer.restoring": "正在还原",
  "android-chat.composer.send": "发送",
  "android-chat.composer.send.failed": "无法发送：{error}",
  "android-chat.file.failed": "失败",
  "android-chat.file.tooBig": "超过 1 GB",
  "android-chat.file.uploadFailed": "上传失败",
  "android-chat.file.uploading.part": "正在上传 {percent}% · {size}",
  "android-chat.pick.quote": "引用",
  "android-chat.quote.comment": "添加说明（可选）",
  "common.copy": "复制",
  "common.delete": "删除",
  "common.retry": "重试",
  "common.uploading": "正在上传",
  "web-main.composer.expandPaste": "展开到输入框",
  "web-main.composer.pasteAttachment": "{count} 字符",
  "web-main.composer.pasteUploading": "正在上传",
  "web-main.composer.pastedText": "粘贴的文字",
  "web-main.composer.removePaste": "删除粘贴片段",
  "web-main.composer.retryPaste": "重试上传",
  "web-pages.chat.files": "Station 文件",
  "android-chat.asks.dismiss": "忽略",
  "android-chat.chat.archiveThis": "归档此对话",
  "android-chat.chat.empty": "在此发送消息，此对话中的 agent 会在这里回复",
  "android-chat.chat.keep": "保留",
  "android-chat.chat.latest": "跳到最新",
  "android-chat.chat.loadingFrom": "正在从 {name} 读取对话",
  "android-chat.chat.newBelow": "以下是新消息",
  "android-chat.chat.newMessages": "{n} 条新消息",
  "android-chat.chat.placeholder": "发消息",
  "android-chat.chat.sending": "正在发送",
  "android-chat.chat.slack.from": "来自 {name}",
  "android-chat.chat.unreadable": "无法读取此对话：{error}",
  "android-chat.chat.unsent": "未发送",
  "android-chat.chat.waiting": "等待中",
  "android-chat.chat.waitingAgent": "等待 agent 接收",
  "android-chat.chat.working": "处理中",
  "android-chat.file.noPreview": "暂时无法预览",
  "android-chat.history.send.failed": "发送失败",
  "android-chat.history.sent.to": "发送到 {name}",
  "android-chat.quote.who": "{name}：",
  "android-chat.archive": "归档",
  "android-chat.archived": "已归档",
  "android-chat.info.title": "对话信息",
  "android-settings.station.first": "添加第一台 station",
  "android-settings.station.firstNote": "agent 在你的机器上运行。首先添加一台 Mac 或 Linux 机器。",
  "android-chat.home.empty.many": "暂无会话。在 Slack 中 @ 它们，或",
  "android-chat.home.empty.mine": "暂无你参与的会话",
  "android-chat.home.empty.one": "暂无会话。在 Slack 中 @ 它，或",
  "android-chat.home.empty.watching": "暂无监控中的会话",
  "android-chat.home.filter.all": "全部",
  "android-chat.home.filter.archived": "已归档",
  "android-chat.home.filter.label": "筛选会话：{filter}",
  "android-chat.home.filter.mine": "我参与的",
  "android-chat.home.filter.watching": "监控中",
  "android-chat.home.invited": "有邀请",
  "android-chat.home.loading": "正在读取会话",
  "android-chat.home.mark.alert": "需要处理",
  "android-chat.home.mark.busy": "工作中",
  "android-chat.home.mark.done": "已完成，有新消息",
  "android-chat.home.mark.other": "等待他人",
  "android-chat.home.mark.wait": "等待你处理",
  "android-chat.home.settings": "设置",
  "android-chat.newChat": "新建对话",
  "android-chat.search.field": "搜索全部内容",
  "android-misc.bar.place.chats": "对话",
  "android-misc.workspace.addAccount": "登录其他账号",
  "android-misc.workspace.addAccount.sub": "保留已登录账号，添加另一个账号",
  "android-misc.workspace.current": "当前使用",
  "android-misc.workspace.new": "新建 workspace",
  "android-misc.workspace.none": "尚未加入任何 workspace",
  "android-misc.workspace.none.lead": "可以请正在使用 {app} 的人将 {email} 邀请进他们的 workspace，也可以自行创建",
  "android-misc.workspace.others": "其他 workspace",
  "android-misc.workspace.sheet.title": "切换 workspace",
  "android-misc.workspaces.loadFailed": "无法读取你的 workspace",
  "android-misc.workspaces.loading": "正在读取你的 workspace",
  "android-settings.signIn.google": "登录或注册",
  "android-settings.signIn.many": "可同时登录多个账号，随时切换 workspace。",
  "android-settings.signIn.note": "登录后，你所在 workspace 的所有 station 和会话都会显示在这里。",
  "android-settings.signIn.title": "让 agent 持续工作",
  "common.opening": "正在打开",
  "common.reading": "正在读取",
}

///|
/// The words for `key`.
pub fn tr(key : String) -> String {
  match zh.get(key) {
    Some(s) => s
    None => drive_zh.get(key).unwrap_or(key)
  }
}

///|
/// The words for `key` with `{name}`s put in.
pub fn fill(key : String, args : Array[(String, String)]) -> String {
  let mut s = tr(key)
  for a in args {
    s = s.replace_all(old="{" + a.0 + "}", new=a.1)
  }
  s
}
