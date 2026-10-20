// The words, as the Android app says them in Chinese (ember client/i18n/catalog/zh: android-chat.json,
// android-settings.json, android-misc.json, common.json); `{name}` is put in by `fill`.

///|
let zh : Map[String, String] = {
  "common.link.open": "打开链接",
  "common.link.copy": "复制链接",
  "common.link.copied": "已复制链接",
  "android-misc.link.cantOpen": "无法打开此链接",
  "android-misc.screen.title": "屏幕",
  "android-misc.adb.title": "共享调试",
  "android-chat.annotate.copied": "已复制",
  "android-chat.annotate.selectAll": "全选",
  "android-chat.archive": "归档",
  "android-chat.archived": "已归档",
  "android-chat.asks.dismiss": "忽略",
  "android-chat.attach.camera": "拍照",
  "android-chat.attach.files": "文件",
  "android-chat.attach.photos": "照片",
  "android-chat.attach.recent.allow": "显示最近照片",
  "android-chat.attach.recent.more": "选择更多照片",
  "android-chat.attach.title": "添加到消息",
  "android-chat.ref.failed": "无法引用此对话：{error}",
  "android-chat.ref.none": "此 station 上没有其他对话",
  "android-chat.ref.none.match": "没有标题匹配的对话",
  "android-chat.ref.title": "引用对话",
  "android-chat.ref.update": "更新 {app} 后才能引用对话",
  "android-chat.chat.archiveThis": "归档此对话",
  "android-chat.chat.delete.verb": "删除",
  "android-chat.chat.empty": "在此发送消息，此对话中的 agent 会在这里回复",
  "android-chat.chat.latest": "跳到最新",
  "android-chat.chat.loadingFrom": "正在从 {name} 读取对话",
  "android-chat.chat.newBelow": "以下是新消息",
  "android-chat.chat.newMessages": "{n} 条新消息",
  "android-chat.chat.placeholder": "发消息",
  "android-chat.chat.retry.verb": "重新发送",
  "android-chat.chat.sending": "正在发送",
  "android-chat.chat.slack.from": "来自 {name}",
  "android-chat.chat.unreadable": "无法读取此对话：{error}",
  "android-chat.chat.unsent": "未发送",
  "android-chat.chat.unsent.toast": "未发送",
  "android-chat.chat.unsent.why": "发送失败：{error}",
  "android-chat.chat.waiting": "等待中",
  "android-chat.chat.waitingAgent": "等待 agent 接收",
  "android-chat.chat.working": "处理中",
  "android-chat.composer.archived": "已归档，还原后才能发送消息。 ",
  "android-chat.composer.archived.placeholder": "还原对话后才能发送",
  "android-chat.composer.offline": "此 station 已离线：当前显示的是之前读取的内容，暂时无法发送消息",
  "android-chat.composer.restore": "还原对话",
  "android-chat.composer.restoring": "正在还原",
  "android-chat.composer.send": "发送",
  "android-chat.composer.send.failed": "无法发送：{error}",
  "android-chat.file.failed": "失败",
  "android-chat.file.noPreview": "暂时无法预览",
  "android-chat.file.tooBig": "超过 1 GB",
  "android-chat.file.uploadFailed": "上传失败",
  "android-chat.file.uploading.part": "正在上传 {percent}% · {size}",
  "android-chat.history.send.failed": "发送失败",
  "android-chat.history.sent.to": "发送到 {name}",
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
  "android-chat.info.title": "对话信息",
  "android-chat.new.account": "账号",
  "android-chat.new.auto": "自动",
  "android-chat.new.confirm": "确定",
  "android-chat.new.effort": "思考深度",
  "android-chat.new.fast.note": "消耗更多额度或积分",
  "android-chat.new.frequent": "常用",
  "android-chat.new.heading": "想让 agent 做什么？",
  "android-chat.new.model": "模型",
  "android-chat.new.noModels": "没有可用模型 · 前往勾选",
  "android-chat.new.offline.text": "在任一机器上打开 {app}，即可连接到此 workspace。",
  "android-chat.new.offline.title": "没有在线的 station",
  "android-chat.new.placeholder": "做任何事",
  "android-chat.new.profile.add": "添加 Profile",
  "android-chat.new.profile.text": "为 {station} 添加 Profile。agent 通过它运行模型：可以是订阅（Claude、ChatGPT），或模型服务的 key。",
  "android-chat.new.runtime": "运行时",
  "android-chat.new.speed": "速度",
  "android-chat.new.station.pick": "选择运行的 station",
  "android-chat.new.sub": "描述要做的事。它会在 {station} 上使用所选模型新建会话。",
  "android-chat.new.title": "新对话",
  "android-chat.new.unchanged": "无变更",
  "android-chat.newChat": "新建对话",
  "android-chat.pick.default": "默认",
  "android-chat.pick.effort.default": "默认深度",
  "android-chat.pick.failed": "无法选择：{error}",
  "android-chat.pick.family.other": "其他",
  "android-chat.pick.model": "选择模型",
  "android-chat.pick.quote": "引用",
  "android-chat.pick.speed.follow": "跟随订阅",
  "android-chat.pick.speed.standard": "标准",
  "android-chat.quote.comment": "添加说明（可选）",
  "android-chat.quote.who": "{name}：",
  "android-chat.save.failed": "无法保存：{error}",
  "android-chat.search.field": "搜索全部内容",
  "android-chat.search.cancel": "取消",
  "android-chat.search.chats": "对话",
  "android-chat.search.messages": "消息",
  "android-chat.search.archived": "已归档",
  "android-chat.search.none": "未找到结果",
  "android-chat.search.update": "更新后才能搜索",
  "android-chat.search.more": "查看更多",
  "android-chat.search.all": "全部结果",
  "android-misc.bar.place.archive": "已归档",
  "android-misc.notify.allowInSettings": "在系统设置里允许 {app} 发通知",
  "android-misc.notify.channel": "消息",
  "android-misc.bar.place.chats": "对话",
  "android-misc.bar.place.connects": "连接",
  "android-misc.bar.place.decisions": "奏",
  "android-misc.bar.place.files": "文件",
  "android-misc.bar.place.profiles": "Profile",
  "android-misc.bar.place.stations": "Station",
  "android-misc.bar.place.usage": "用量",
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
  "android-settings.station.first": "添加第一台 station",
  "android-settings.station.firstNote": "agent 在你的机器上运行。首先添加一台 Mac 或 Linux 机器。",
  "common.cancel": "取消",
  "common.copy": "复制",
  "common.delete": "删除",
  "common.opening": "正在打开",
  "common.reading": "正在读取",
  "common.retry": "重试",
  "common.uploading": "正在上传",
  "web-main.composer.expandPaste": "展开到输入框",
  "web-main.composer.pasteAttachment": "{count} 字符",
  "web-main.composer.pasteUploading": "正在上传",
  "web-main.composer.pastedText": "粘贴的文字",
  "web-main.composer.removePaste": "删除粘贴片段",
  "web-main.composer.retryPaste": "重试上传",
  "web-pages.chat.files": "Station 文件",
  "web-main.outside.title": "分享对话",
  "web-main.outside.lead": "发送后，此 workspace 中的 agent 可读取以下内容（连续 6 小时未使用即失效）：",
  "web-main.outside.from": "来自 {name}",
  "web-main.outside.cannot": "你没有分享权限，需由发起人或管理员分享",
  "web-main.outside.share": "分享并发送",
  "web-main.outside.anyway": "仍然发送",
  "web-main.outside.failed": "分享失败：{error}",
}

///|
/// The words for `key`.
pub fn tr(key : String) -> String {
  match zh.get(key) {
    Some(s) => s
    None =>
      match drive_zh.get(key) {
        Some(s) => s
        None =>
          match zh_decide.get(key) {
            Some(s) => s
            None =>
              match zh_wide.get(key) {
                Some(s) => s
                None =>
                  match zh_links.get(key) {
                    Some(s) => s
                    None => zh_screen.get(key).unwrap_or(key)
                  }
              }
          }
      }
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
