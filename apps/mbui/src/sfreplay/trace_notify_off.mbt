// e2e/traces/notify-off.trace, made by scripts/trace.py from 10-notify_off.log: not edited by hand.

///|
/// What the app and its core said in the run, a line each.
pub let trace_notify_off : String =
  #|{"env":{"MBUI_CLOUD":"http://127.0.0.1:18787","MBUI_CORE_ACCOUNT":"{\"sub\":\"alice\",\"email\":\"alice@example.test\",\"name\":\"Name of alice\",\"picture\":\"\",\"access\":\"-\",\"refresh\":\"-\",\"accessExpires\":1792548983}"}}
  #|{"out":{"id":1,"call":"client.device","params":{"client":"still.fail mbui","app":"desktop","userAgent":"Macintosh; Mac OS X"}},"w":1792548793564.631}
  #|{"in":{"id":1,"ok":null},"w":1792548793661.914}
  #|{"out":{"id":2,"subscribe":{"topic":"accounts"},"keyed":true},"w":1792548793661.94}
  #|{"out":{"id":3,"subscribe":{"topic":"prefs"},"keyed":true},"w":1792548793661.95}
  #|{"step":"# written by scripts/rerecord.sh from its test (src/sfreplay/emit.mbt): not edited by hand","w":1792548793663.407}
  #|{"step":"timeout 90000","w":1792548793663.413}
  #|{"step":"answered client.device","w":1792548793663.415}
  #|{"step":"answered client.focus","w":1792548793679.052}
  #|{"in":{"id":2,"value":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""}]},"w":1792548793745.236}
  #|{"in":{"id":3,"value":{"onlyMine":false,"onlyWatching":false,"onlyDecisions":false,"listFilter":{},"appearance":"system","rowPicture":"auto","absoluteTime":false,"lang":"zh","keys":{},"lastChat":{},"openChat":{"01M5E3MC1B496BJETXKX7JNGSF":{"station":"01M5E3MC1B496BJETXKX7JNGSF/138ba6116d729e54bf1241baf74a72cecff00ecf0b23bff83d1345178b6cb111","key":"ember:c-4d25e6d2a3"}},"chatTabs":{},"dropFiles":{},"driveViews":{},"resume":{},"stationUpdatesDismissed":{},"device":{"app":"desktop","phone":false,"handoff":false},"reader":{"size":18,"line":1.7,"margin":22,"face":"sans","indent":true,"paper":"follow"},"rails":{},"bars":{"sets":[["chats","files","profiles","stations"],["decisions","usage","connects","archive"]],"current":0},"barsBy":{},"fonts":{},"faces":{"ui":{"id":"","name":"","mono":false,"family":"","files":[],"bytes":0},"text":{"id":"","name":"","mono":false,"family":"","files":[],"bytes":0},"code":{"id":"","name":"","mono":true,"family":"","files":[],"bytes":0},"list":[{"id":"inter","name":"Inter","mono":false,"family":"SF Inter","css":"http://127.0.0.1:18787/releases/fonts/inter/4.001/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/inter/4.001/var.ttf.gz","bytes":457818,"sha256":"29160a80ff49ddcab2c97711247e08b1fab27a484a329ce8b813d820dc559031"}],"preview":"http://127.0.0.1:18787/releases/fonts/inter/4.001/preview-194fa287.ttf","bytes":457818},{"id":"noto-sans-sc","name":"思源黑体","mono":false,"family":"SF Noto Sans SC","css":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/var.ttf.gz","bytes":11276563,"sha256":"a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da"}],"preview":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/preview-f0494178.ttf","bytes":11276563},{"id":"noto-serif-sc","name":"思源宋体","mono":false,"family":"SF Noto Serif SC","css":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/var.ttf.gz","bytes":15454579,"sha256":"050080d9255a86808f2945bffac582b31ef32bc36411ce29563b4961670c66f9"}],"preview":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/preview-001bbedf.ttf","bytes":15454579},{"id":"lxgw-wenkai","name":"霞鹜文楷","mono":false,"family":"SF LXGW WenKai","css":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/font.css","files":[{"weight":400,"url":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/400.ttf.gz","bytes":12904482,"sha256":"2d73eea94ad808999d90c0000c239a84a33b09d4bc6ab6c5b8bbf1eda8a7fc8b"},{"weight":500,"url":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/500.ttf.gz","bytes":13272430,"sha256":"f4b8a34d1f838fe411540cb7c97b1c384ac9738a876c4104500bc42508b2312a"}],"preview":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/preview-d3505af4.ttf","bytes":26176912},{"id":"jetbrains-mono","name":"JetBrains Mono","mono":true,"family":"SF JetBrains Mono","css":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/var.ttf.gz","bytes":90579,"sha256":"48715a42ec242c21e9f02692891e147d022299a52e48d5e413e1a942193ffeda"}],"preview":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/preview-ee73078f.ttf","bytes":90579},{"id":"fira-code","name":"Fira Code","mono":true,"family":"SF Fira Code","css":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/var.ttf.gz","bytes":137151,"sha256":"9335b082b3c7850d98a64b584f3417f65355f3471278bb5eeb8c6c0e8657aeeb"}],"preview":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/preview-555be27a.ttf","bytes":137151},{"id":"maple-mono","name":"Maple Mono","mono":true,"family":"SF Maple Mono CN","css":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/font.css","files":[{"weight":400,"url":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/400.ttf.gz","bytes":8352545,"sha256":"0fcc5139bfd5ab14ff989bb7dfd5236d0cafc10e60b9828569e6883613ab4085"},{"weight":600,"url":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/600.ttf.gz","bytes":8438132,"sha256":"96ed7ae26ee7c50b02b2d2b2bc0f1a0cbabe45ae5d6e6abf6678e2177c415677"}],"preview":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/preview-cffdf246.ttf","bytes":16790677}]}}},"w":1792548793745.279}
  #|{"out":{"id":4,"subscribe":{"topic":"workspaces"},"keyed":true},"w":1792548793745.327}
  #|{"out":{"id":5,"subscribe":{"topic":"status"},"keyed":true},"w":1792548793745.339}
  #|{"in":{"id":4,"value":[{"account":{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""},"workspaces":[{"id":"01M5E3MC1B496BJETXKX7JNGSF","name":"Dev","role":"owner","created_at":1792548679,"stations":1,"members":1,"relays":[],"time":{"created_at":{"past":true,"at":1792548679000,"ago":"2 分钟前","full":"10/21 10:11:19","until":"1 分钟内"}}}],"invitations":[],"relay_url":"http://127.0.0.1:18740","loaded":true,"beta":true}]},"w":1792548793763.466}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792548793763.481}
  #|{"out":{"id":6,"subscribe":{"topic":"lock","workspace":"01M5E3MC1B496BJETXKX7JNGSF"},"keyed":true},"w":1792548793763.513}
  #|{"out":{"id":7,"subscribe":{"topic":"chats","scope":"01M5E3MC1B496BJETXKX7JNGSF","mine":false},"keyed":true},"w":1792548793763.528}
  #|{"out":{"id":8,"subscribe":{"topic":"changelog"},"keyed":true},"w":1792548793763.542}
  #|{"out":{"id":9,"subscribe":{"topic":"workspaceMarks","workspace":"01M5E3MC1B496BJETXKX7JNGSF"},"keyed":true},"w":1792548793763.663}
  #|{"out":{"id":10,"subscribe":{"topic":"status","workspace":"01M5E3MC1B496BJETXKX7JNGSF"},"keyed":true},"w":1792548793763.701}
  #|{"out":{"id":11,"call":"client.focus","params":{"visible":true,"focused":true,"workspace":"01M5E3MC1B496BJETXKX7JNGSF"}},"w":1792548793770.968}
  #|{"out":{"id":12,"subscribe":{"topic":"notify"},"keyed":true},"w":1792548793770.983}
  #|{"out":{"id":13,"subscribe":{"topic":"notify","workspace":"01M5E3MC1B496BJETXKX7JNGSF"},"keyed":true},"w":1792548793770.991}
  #|{"in":{"id":6,"value":{"available":true,"locked":false,"notice":true,"role":"owner","manages":true,"owner":true,"canSign":true,"signs":false,"me":{"device":"a49b9649c51f7154da373b273e5d2ee5f2088787e8f26b3131fbb01f6eed23e8","code":"5SM-5FJ","kind":"app","confirmed":false,"waiting":false,"asked":false},"signers":0,"members":[],"stations":[{"id":"138ba6116d729e54bf1241baf74a72cecff00ecf0b23bff83d1345178b6cb111","name":"studio","version":"0.1.0","online":true,"protected":false}],"protected":0,"requests":[],"renew":[],"attention":0}},"w":1792548793778.565}
  #|{"in":{"id":7,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"stations":[{"station":"01M5E3MC1B496BJETXKX7JNGSF/138ba6116d729e54bf1241baf74a72cecff00ecf0b23bff83d1345178b6cb111","id":"138ba6116d729e54bf1241baf74a72cecff00ecf0b23bff83d1345178b6cb111","name":"studio","state":"online"}],"loading":false,"days":[{"daysAgo":0,"at":1792548792874,"label":"今天","items":[{"id":"ember:c-4d25e6d2a3","session":"ember:c-4d25e6d2a3","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","agents":[{"key":"ember:c-4d25e6d2a3","runtime":"claude","process":"warm","pending":0,"lastTurn":{"id":"a03039b9-37c2-4ea8-9db0-716f7251bdf7","kind":"input","outcome":"completed","declared":"block","ending":"need_help","need":"这个不该通知 083209","about":{"thread":1,"seq":20,"ts":"1792548792.873000"},"startedAt":1792548792870,"endedAt":1792548792875},"agentText":"默认模型","mark":"block","statusText":"需要你处理：这个不该通知 083209","badgeText":"agent 已暂停，等待处理"}],"last":{"seq":20,"authorKind":"agent","author":"ember:c-4d25e6d2a3","text":"这个不该通知 083209","createdAt":1792548792874,"by":{"kind":"agent","name":"agent","mine":false,"runtime":"claude","state":"block","label":"agent（agent 已暂停，等待处理）"},"preview":"这个不该通知 083209","time":{"createdAt":{"at":1792548792874,"ago":"刚刚","full":"10/21 10:13:12","until":"1 分钟内","past":true}}},"unread":false,"mine":true,"lastActiveAt":1792548792874,"station":"01M5E3MC1B496BJETXKX7JNGSF/138ba6116d729e54bf1241baf74a72cecff00ecf0b23bff83d1345178b6cb111","stationName":"studio","state":"block","time":{"lastActiveAt":{"at":1792548792874,"ago":"刚刚","full":"10/21 10:13:12","until":"1 分钟内","past":true}},"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"peopleText":"你 发起","clientKey":"new:chat-3cc8a26dbd3be52c94","pinned":false,"decision":{"seq":20,"options":[{"label":"好 083209"},{"label":"不好 083209"}],"card":{"type":"options","options":[{"label":"好 083209"},{"label":"不好 083209"}]},"text":"奏 · 这个不该通知 083209"},"stateText":"需要你处理：这个不该通知 083209","tone":"wait"},{"id":"ember:c-f77fef823b","session":"ember:c-f77fef823b","thread":2,"title":"要归档的对话 083209 post:归档前的回复 083209","agents":[{"key":"ember:c-f77fef823b","runtime":"claude","process":"cold","pending":0,"lastTurn":{"id":"d84f99f0-2bb3-4c00-8f4c-4769ac06f96e","kind":"input","outcome":"completed","startedAt":1792548777129,"endedAt":1792548777196},"agentText":"默认模型","mark":"failed","statusText":"出错：意外停止","badgeText":"失败，需要处理"}],"last":{"seq":1,"authorKind":"person","author":"alice@example.test","authorName":"Name of alice","text":"要归档的对话 083209 post:归档前的回复 083209","createdAt":1792548777117,"by":{"kind":"person","name":"你","mine":true,"id":"alice@example.test","picture":"https://example.test/p.png","label":"你"},"preview":"要归档的对话 083209 post:归档前的回复 083209","time":{"createdAt":{"at":1792548777117,"ago":"刚刚","full":"10/21 10:12:57","until":"1 分钟内","past":true}}},"unread":false,"mine":true,"lastActiveAt":1792548777117,"station":"01M5E3MC1B496BJETXKX7JNGSF/138ba6116d729e54bf1241baf74a72cecff00ecf0b23bff83d1345178b6cb111","stationName":"studio","state":"failed","time":{"lastActiveAt":{"at":1792548777117,"ago":"刚刚","full":"10/21 10:12:57","until":"1 分钟内","past":true}},"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"peopleText":"你 发起","clientKey":"new:chat-e5c10f1662b3338734","pinned":false,"stateText":"出错：意外停止","tone":"alert"}]}],"trouble":null,"members":1,"leading":"agents","glyph":{"online":1,"dim":0,"connecting":0,"failing":0,"working":0,"summary":"studio","label":"1 台 station，1 台在线"},"note":{"reading":false,"text":null,"failing":[],"empty":false}}},"w":1792548793778.605}
  #|{"in":{"id":8,"value":{"app":"desktop","tabs":[{"part":"desktop","label":"桌面","days":[]},{"part":"web","label":"网页","days":[]},{"part":"android","label":"安卓","days":[]},{"part":"station","label":"Station","days":[]},{"part":"cloud","label":"云端","days":[]}],"loading":false}},"w":1792548793778.635}
  #|{"in":{"id":9,"value":{"workspaces":{"01M5E3MC1B496BJETXKX7JNGSF":{"alert":1,"unread":0,"wait":1,"decisions":1,"tone":"alert","label":"1 个出错 · 1 个待你处理","chat":{"station":"01M5E3MC1B496BJETXKX7JNGSF/138ba6116d729e54bf1241baf74a72cecff00ecf0b23bff83d1345178b6cb111","key":"ember:c-4d25e6d2a3"},"badge":0,"items":[{"kind":"alert","workspace":"01M5E3MC1B496BJETXKX7JNGSF","workspaceName":"Dev","station":"01M5E3MC1B496BJETXKX7JNGSF/138ba6116d729e54bf1241baf74a72cecff00ecf0b23bff83d1345178b6cb111","stationName":"studio","session":"ember:c-f77fef823b","thread":2,"title":"要归档的对话 083209 post:归档前的回复 083209","text":"出错：意外停止","seen":true,"at":1792548777117},{"kind":"wait","workspace":"01M5E3MC1B496BJETXKX7JNGSF","workspaceName":"Dev","station":"01M5E3MC1B496BJETXKX7JNGSF/138ba6116d729e54bf1241baf74a72cecff00ecf0b23bff83d1345178b6cb111","stationName":"studio","session":"ember:c-4d25e6d2a3","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","text":"需要你处理：这个不该通知 083209","seq":20,"seen":true,"at":1792548792874}],"elsewhere":1,"mineTone":"alert"}},"badge":0,"badgeCounts":"attention","badgeKinds":{"on":true,"wait":true,"failed":true,"done":false,"message":false}}},"w":1792548793778.646}
  #|{"in":{"id":10,"value":{"items":[]}},"w":1792548793778.654}
  #|{"in":{"id":11,"ok":null},"w":1792548793778.656}
  #|{"in":{"id":12,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792548793778.663}
  #|{"in":{"id":13,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792548793778.666}
  #|{"out":{"id":14,"subscribe":{"topic":"longJobs","scope":"01M5E3MC1B496BJETXKX7JNGSF"},"keyed":true},"w":1792548793778.692}
  #|{"out":{"id":15,"call":"notify.permission","params":{"state":"unknown"}},"w":1792548793781.441}
  #|{"in":{"id":14,"value":{"groups":[]}},"w":1792548793795.229}
  #|{"in":{"id":15,"ok":null},"w":1792548793795.235}
  #|{"step":"answered notify.permission","w":1792548793795.466}
  #|{"step":"until 端到端测试","w":1792548793812.132}
  #|{"step":"tap icon:settings","w":1792548793812.142}
  #|{"step":"tap icon:settings","acted":true,"w":1792548793812.153}
  #|{"out":{"id":16,"subscribe":{"topic":"workspace","workspace":"01M5E3MC1B496BJETXKX7JNGSF"},"keyed":true},"w":1792548793828.677}
  #|{"out":{"id":17,"subscribe":{"topic":"stations","scope":"01M5E3MC1B496BJETXKX7JNGSF"},"keyed":true},"w":1792548793828.699}
  #|{"out":{"id":18,"subscribe":{"topic":"connects","scope":"01M5E3MC1B496BJETXKX7JNGSF","mine":false},"keyed":true},"w":1792548793828.705}
  #|{"out":{"id":19,"subscribe":{"topic":"vaults","workspace":"01M5E3MC1B496BJETXKX7JNGSF"},"keyed":true},"w":1792548793828.711}
  #|{"out":{"id":20,"subscribe":{"topic":"doing"},"keyed":true},"w":1792548793831.252}
  #|{"step":"wait 300","w":1792548793832.044}
  #|{"in":{"id":16,"value":{"id":"01M5E3MC1B496BJETXKX7JNGSF","name":"Dev","role":"owner","created_at":1792548679,"members":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":"https://example.test/p.png","role":"owner","added_at":1792548679}],"stations":[{"id":"138ba6116d729e54bf1241baf74a72cecff00ecf0b23bff83d1345178b6cb111","name":"studio","emoji":null,"icon":null,"enrolled_at":1792548680,"enrolled_by":"alice","last_seen":1792548683,"version":"0.1.0","time":{"last_seen":{"past":true,"at":1792548683000,"ago":"2 分钟前","full":"10/21 10:11:23","until":"1 分钟内"}}}],"invitations":[],"added":[],"relays":[],"lock":null,"lock_requests":0,"time":{"created_at":{"past":true,"at":1792548679000,"ago":"2 分钟前","full":"10/21 10:11:19","until":"1 分钟内"}}}},"w":1792548793845.24}
  #|{"in":{"id":17,"value":[{"station":"01M5E3MC1B496BJETXKX7JNGSF/138ba6116d729e54bf1241baf74a72cecff00ecf0b23bff83d1345178b6cb111","id":"138ba6116d729e54bf1241baf74a72cecff00ecf0b23bff83d1345178b6cb111","name":"studio","summary":"空闲 · Apple M4 · 16 GB · macOS 27.0.1","face":"idle","line":"Apple M4","online":true,"reconnecting":false,"lastSeen":1792548683,"version":"0.1.0","link":{"state":"online"},"runtimes":[{"runtime":"claude","models":["claude-sonnet-5-5"]}],"models":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792548683804,"time":{"checkedAt":{"at":1792548683804,"ago":"2 分钟前","full":"10/21 10:11:23","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"overview":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null,"summaryText":"最近 7 天检查了 0 个 chat","changeText":null}},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","email":"alice@example.test","name":"Name of alice","sub":"alice","role":"owner","workspace":"01M5E3MC1B496BJETXKX7JNGSF","device":"a49b9649c51f7154da373b273e5d2ee5f2088787e8f26b3131fbb01f6eed23e8"},"connects":[],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792548683670,"time":{"checkedAt":{"at":1792548683670,"ago":"2 分钟前","full":"10/21 10:11:23","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792548683804,"time":{"checkedAt":{"at":1792548683804,"ago":"2 分钟前","full":"10/21 10:11:23","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]}],"processes":[],"counts":{"sessions":2,"running":0,"warm":1},"mesh":{"state":"running","origin":"http://127.0.0.1:18787","station":"138ba6116d729e54bf1241baf74a72cecff00ecf0b23bff83d1345178b6cb111","workspace":"Dev","workspaceId":"01M5E3MC1B496BJETXKX7JNGSF","name":"studio"},"slackUsers":[],"slackTeams":[],"slackApps":[],"feishuRegistrations":[],"disk":{"freeBytes":46393667584,"totalBytes":245107195904},"logins":[],"machineLogins":[{"runtime":"claude","installed":true,"loggedIn":false,"usable":false,"text":"无法读取 Claude Code 的登录信息","offered":false},{"runtime":"codex","installed":true,"loggedIn":false,"usable":false,"text":"Codex 未登录","offered":false}],"sharing":true,"consoleSignIn":true,"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"google","name":"Google Gemini","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xai","name":"xAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"mistral","name":"Mistral","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"deepseek","name":"DeepSeek","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen","name":"Qwen","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai","name":"Kimi","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai","name":"Z.ai","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax","name":"MiniMax","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ant-ling","name":"Ant Ling","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"jev","name":"Jev","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen-cn","name":"Qwen (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"openrouter","name":"OpenRouter","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"opencode","name":"OpenCode Zen","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"groq","name":"Groq","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"together","name":"Together AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"fireworks","name":"Fireworks","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cerebras","name":"Cerebras","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"huggingface","name":"Hugging Face","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"nvidia","name":"NVIDIA","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"baseten","name":"Baseten","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ollama","name":"Ollama","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"custom","name":"Custom","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""}],"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792548681828},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.305","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792548681828},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-news/apps/e2e-local/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792548681828},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-news/apps/e2e-local/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792548681828},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","latest":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-news/apps/e2e-local/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792548681828},{"id":"cursor","name":"Cursor","installed":false,"latest":"1.0.40","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792548681828},{"id":"devin","name":"Devin","installed":true,"version":"3000.11.92","latest":"3000.11.92","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-news/apps/e2e-local/ember/station/test/fake/devin，不是用 Devin 的安装脚本装的，需在该机器上手动更新","state":"idle","checkedAt":1792548681828}],"processesText":"没有运行中的 agent 进程","agentEnv":[],"drive":{"roots":[],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false}},"betaOffered":false,"host":{"hostname":"3720-Mac-mini-1","os":"macOS 27.0.1","arch":"arm64","cpus":10,"cpuModel":"Apple M4","load":0.53,"cpuBusy":0.12,"uptimeSec":28146,"memory":{"totalBytes":17179869184,"usedBytes":9846374400,"swapUsedBytes":300742083},"disk":{"path":"/tmp/mbe2e-C/data","totalBytes":245107195904,"freeBytes":46397394944},"emberRssBytes":148439408,"checkedAt":1792548784729,"summary":"10 核 · 16 GB","line":"macOS 27.0.1 · 10 核 · 16 GB · 已运行 0 天","facts":["3720-Mac-mini-1","macOS 27.0.1","arm64 · 10 核","已运行 7 小时"],"meters":[{"label":"CPU","short":"CPU","percent":12,"left":88,"level":"ok","value":"12%","remaining":"空闲 88%","big":"88","unit":"%","title":"CPU 空闲","total":"负载 5.3","note":"负载 5.3 · Apple M4"},{"label":"内存","short":"内存","percent":57,"left":43,"level":"ok","value":"9.2 GB / 16.0 GB","remaining":"剩 6.8 G","big":"6.8","unit":"GB","title":"内存剩","total":"共 16 GB","note":"swap 0.3 GB"},{"label":"磁盘","short":"磁盘","percent":81,"left":19,"level":"amber","value":"剩余 43.2 GB / 228 GB","remaining":"剩 43.2 G","big":"43.2","unit":"GB","title":"磁盘剩","total":"共 228 GB"}],"identity":"Apple M4 · 16 GB · macOS 27.0.1","details":[{"label":"主机名","value":"3720-Mac-mini-1"},{"label":"芯片","value":"Apple M4 · 10 核 · arm64"},{"label":"已运行","value":"7 小时"},{"label":"still.fail","value":"进程占用 142 MB"}],"usage":"内存 9.2 GB / 16.0 GB · 磁盘 剩余 43.2 GB / 228 GB","emberText":"still.fail 142 MB"},"way":{"path":"直连","via":"direct"},"time":{"lastSeen":{"at":1792548683000,"ago":"2 分钟前","full":"10/21 10:11:23","until":"1 分钟内","past":true}},"joined":false}]},"w":1792548793845.359}
  #|{"in":{"id":18,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"items":[],"wait":{"reading":false,"text":null,"failing":[],"empty":true}}},"w":1792548793845.437}
  #|{"in":{"id":19,"value":{"available":true,"locked":false,"canSign":false,"setUp":false,"vaults":[{"id":"plain","name":"个人","owner":"alice","ownerName":"Name of alice","mine":true,"members":[{"sub":"alice","name":"Name of alice"}],"station":"138ba6116d729e54bf1241baf74a72cecff00ecf0b23bff83d1345178b6cb111","stationName":"studio","items":0,"devices":0,"open":true,"keyed":true,"missing":0,"recoverable":false}],"requests":[],"refused":[{"station":"138ba6116d729e54bf1241baf74a72cecff00ecf0b23bff83d1345178b6cb111","name":"studio","code":"vault_needs_lock"}],"plain":true}},"w":1792548793845.444}
  #|{"in":{"id":20,"value":{"doing":[]}},"w":1792548793845.449}
  #|{"in":{"id":17,"delta":[{"path":[0,"overview","disk","freeBytes"],"set":46393630720}]},"w":1792548793995.244}
  #|{"step":"now until Workspace","w":1792548794146.278}
  #|{"step":"drag 195 600 0 -400 160","w":1792548794146.331}
  #|{"step":"drag 195 600 0 -400 160","acted":true,"w":1792548794146.36}
  #|{"step":"until =通知","w":1792548794329.509}
  #|{"step":"tap =通知","w":1792548794329.568}
  #|{"step":"tap =通知","acted":true,"w":1792548794329.604}
  #|{"out":{"id":21,"call":"notify.set","params":{"on":false}},"w":1792548794345.785}
  #|{"step":"answered notify.set","w":1792548794346.273}
  #|{"in":{"id":21,"ok":{"on":false,"asked":true,"push":false,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792548794361.951}
  #|{"out":{"id":22,"call":"push.unregister","params":{}},"w":1792548794362.05}
  #|{"in":{"id":22,"ok":null},"w":1792548794378.62}
  #|{"step":"answered push.unregister","w":1792548794379.698}
  #|{"step":"until 不接收通知","w":1792548794396.218}
  #|{"in":{"id":12,"delta":[{"path":["on"],"set":false},{"path":["push"],"set":false}]},"w":1792548794428.604}
  #|{"in":{"id":13,"delta":[{"path":["on"],"set":false},{"path":["push"],"set":false}]},"w":1792548794428.671}
  #|{"step":"back","w":1792548794431.466}
  #|{"step":"back","acted":true,"w":1792548794431.487}
  #|{"step":"wait 300","w":1792548794446.993}
  #|{"step":"now until 端到端测试","w":1792548794747.311}
  #|{"step":"log do: peer send 关了通知 083209 card:关着的时候 083209|好 083209|不好 083209","w":1792548794747.369}
  #|{"step":"peer send 关了通知 083209 card:关着的时候 083209|好 083209|不好 083209"}
  #|{"step":"done 1-peer","w":1792548794747.386}
  #|{"step":"until 关着的时候 083209","w":1792548795212.233}
  #|{"in":{"id":7,"delta":[{"path":["days"],"key":["daysAgo"],"patch":0,"ops":[{"path":["at"],"set":1792548795187},{"path":["items"],"key":["station","id"],"patch":["01M5E3MC1B496BJETXKX7JNGSF/138ba6116d729e54bf1241baf74a72cecff00ecf0b23bff83d1345178b6cb111","ember:c-4d25e6d2a3"],"ops":[{"path":["agents",0,"lastTurn","about","seq"],"set":22},{"path":["agents",0,"lastTurn","about","ts"],"set":"1792548795.187000"},{"path":["agents",0,"lastTurn","endedAt"],"set":1792548795188},{"path":["agents",0,"lastTurn","id"],"set":"4838bc6e-13ee-4baf-9961-a2390988f797"},{"path":["agents",0,"lastTurn","need"],"set":"关着的时候 083209"},{"path":["agents",0,"lastTurn","startedAt"],"set":1792548795185},{"path":["agents",0,"statusText"],"set":"需要你处理：关着的时候 083209"},{"path":["decision","seq"],"set":22},{"path":["decision","text"],"set":"奏 · 关着的时候 083209"},{"path":["last","createdAt"],"set":1792548795187},{"path":["last","preview"],"set":"关着的时候 083209"},{"path":["last","seq"],"set":22},{"path":["last","text"],"set":"关着的时候 083209"},{"path":["last","time","createdAt","at"],"set":1792548795187},{"path":["last","time","createdAt","full"],"set":"10/21 10:13:15"},{"path":["lastActiveAt"],"set":1792548795187},{"path":["stateText"],"set":"需要你处理：关着的时候 083209"},{"path":["time","lastActiveAt","at"],"set":1792548795187},{"path":["time","lastActiveAt","full"],"set":"10/21 10:13:15"},{"path":["unread"],"set":true}]}]}]},"w":1792548795261.961}
  #|{"in":{"id":17,"delta":[{"path":[0,"overview","disk","freeBytes"],"set":46393692160},{"path":[0,"overview","viewer","device"],"set":"19150da8f1b4b8617e2e32d9b5e62809737ea31968c1a349b887b7e06967b506"}]},"w":1792548795262.047}
  #|{"in":{"id":9,"delta":[{"path":["badge"],"set":1},{"path":["workspaces","01M5E3MC1B496BJETXKX7JNGSF","badge"],"set":1},{"path":["workspaces","01M5E3MC1B496BJETXKX7JNGSF","items",1,"at"],"set":1792548795187},{"path":["workspaces","01M5E3MC1B496BJETXKX7JNGSF","items",1,"seen"],"set":false},{"path":["workspaces","01M5E3MC1B496BJETXKX7JNGSF","items",1,"seq"],"set":22},{"path":["workspaces","01M5E3MC1B496BJETXKX7JNGSF","items",1,"text"],"set":"需要你处理：关着的时候 083209"}]},"w":1792548795262.059}
  #|{"step":"nonotice 关着的时候 083209","w":1792548795264.078}
  #|{"in":{"id":17,"delta":[{"path":[0,"host","checkedAt"],"set":1792548795256},{"path":[0,"host","cpuBusy"],"set":0.16},{"path":[0,"host","details",3,"value"],"set":"进程占用 141 MB"},{"path":[0,"host","disk","freeBytes"],"set":46393659392},{"path":[0,"host","emberRssBytes"],"set":148242824},{"path":[0,"host","emberText"],"set":"still.fail 141 MB"},{"path":[0,"host","load"],"set":0.48},{"path":[0,"host","memory","usedBytes"],"set":9919283200},{"path":[0,"host","meters",0,"big"],"set":"84"},{"path":[0,"host","meters",0,"left"],"set":84},{"path":[0,"host","meters",0,"note"],"set":"负载 4.8 · Apple M4"},{"path":[0,"host","meters",0,"percent"],"set":16},{"path":[0,"host","meters",0,"remaining"],"set":"空闲 84%"},{"path":[0,"host","meters",0,"total"],"set":"负载 4.8"},{"path":[0,"host","meters",0,"value"],"set":"16%"},{"path":[0,"host","meters",1,"left"],"set":42},{"path":[0,"host","meters",1,"percent"],"set":58},{"path":[0,"host","uptimeSec"],"set":28157}]},"w":1792548795411.926}
  #|{"step":"tap icon:settings","w":1792548795412.571}
  #|{"step":"tap icon:settings","acted":true,"w":1792548795412.592}
  #|{"step":"wait 300","w":1792548795429.799}
  #|{"step":"now until Workspace","w":1792548795746.231}
  #|{"step":"drag 195 600 0 -400 160","w":1792548795746.284}
  #|{"step":"drag 195 600 0 -400 160","acted":true,"w":1792548795746.313}
  #|{"step":"until =通知","w":1792548795928.746}
  #|{"step":"tap =通知","w":1792548795928.768}
  #|{"step":"tap =通知","acted":true,"w":1792548795928.781}
  #|{"out":{"id":23,"call":"notify.set","params":{"on":true}},"w":1792548795945.305}
  #|{"step":"answered notify.set","w":1792548795945.424}
  #|{"in":{"id":23,"ok":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792548795961.885}
  #|{"step":"until 任务完成、需要处理","w":1792548795978.689}
  #|{"in":{"id":12,"delta":[{"path":["on"],"set":true},{"path":["push"],"set":true}]},"w":1792548796095.217}
  #|{"in":{"id":13,"delta":[{"path":["on"],"set":true},{"path":["push"],"set":true}]},"w":1792548796095.235}
  #|{"step":"","w":1792548796095.492}
  #|{"textrec":{"ib":["bfd9b0d6dc602826",12668,64],"r":[56,56,56,56]}}
  #|{"textrec":{"s":[13,400,0,"正在读取你的 workspace"],"r":[0,1,12.898832684824903,0,1,1,12.898832684824903,1,2,1,12.898832684824903,2,3,1,12.898832684824903,3,4,1,12.898832684824896,4,5,1,12.898832684824896,5,6,1,3.580078125,-1,7,1,9.8642578125,6,8,1,7.4775390625,7,9,1,4.875,8,10,1,6.85546875,9,11,1,6.6015625,10,12,1,7.8583984375,11,13,1,7.0966796875,12,14,1,7.1982421875,13,15,1,7.3505859375,14]}}
  #|{"textrec":{"m":[13,400,0],"r":[12.568359375,2.7421875,18,12.568359375,2.7421875,0]}}
  #|{"textrec":{"s":[24,700,0,"Dev"],"r":[0,1,17.075823068618774,15,1,1,13.365240812301636,16,2,1,12.759063005447388,17]}}
  #|{"textrec":{"m":[24,700,0],"r":[23.203125,5.0625,34,20.638916015625,3.361083984375,0]}}
  #|{"textrec":{"g":15,"r":[0,0,18,19,0,-18,0]}}
  #|{"textrec":{"g":16,"r":[19,0,15,16,-1,-14,0]}}
  #|{"textrec":{"g":17,"r":[35,0,15,15,-1,-14,0]}}
  #|{"textrec":{"ib":["02698e60df92657e",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"ib":["fdb526ba00f881f4",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["1d51432b25a425eb",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"ib":["bef2954d97ce1d9f",6508,64],"r":[40,40,40,40]}}
  #|{"textrec":{"ib":["a7ccae3554fe46cf",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["31d8ec32aedeae00",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["c8ac90bf691295f0",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"s":[15,400,0,"搜索全部内容"],"r":[0,1,14.883268482490273,18,1,1,14.883268482490273,19,2,1,14.883268482490273,20,3,1,14.883268482490273,21,4,1,14.88326848249028,22,5,1,14.88326848249028,23]}}
  #|{"textrec":{"m":[15,400,0],"r":[14.501953125,3.1640625,21,14.501953125,3.1640625,0]}}
  #|{"textrec":{"s":[15,600,0,"今天"],"r":[0,1,14.883268482490273,24,1,1,14.883268482490273,25]}}
  #|{"textrec":{"m":[15,600,0],"r":[14.501953125,3.1640625,21,14.501953125,3.1640625,0]}}
  #|{"textrec":{"s":[16,400,0,"端到端测试的对话 post:你好，我是测试用的 agent"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,26,3,1,15.875486381322958,28,4,1,15.875486381322958,29,5,1,15.875486381322958,30,6,1,15.875486381322958,31,7,1,15.875486381322958,32,8,1,4.1875,-1,9,1,9.453125,33,10,1,9.140625,34,11,1,8.0234375,35,12,1,5.4609375,36,13,1,4.4375,37,14,1,15.875486381322958,38,15,1,15.875486381322958,39,16,1,16.09338521400778,40,17,1,15.875486381322958,41,18,1,15.875486381322958,42,19,1,15.87548638132293,28,20,1,15.875486381322958,29,21,1,15.875486381322958,43,22,1,15.875486381322958,30,23,1,4.1875,-1,24,1,8.515625,44,25,1,9.4375,45,26,1,8.828125,46,27,1,9.0234375,47,28,1,5.5,36]}}
  #|{"textrec":{"m":[16,400,0],"r":[15.46875,3.375,23,15.46875,3.375,0]}}
  #|{"textrec":{"s":[14,400,0,"这个不该通知 083209"],"r":[0,1,13.891050583657588,48,1,1,13.891050583657588,49,2,1,13.891050583657588,50,3,1,13.891050583657588,51,4,1,13.891050583657588,52,5,1,13.891050583657588,53,6,1,3.787109375,-1,7,1,8.66796875,54,8,1,8.791015625,55,9,1,8.626953125,56,10,1,8.298828125,57,11,1,8.66796875,54,12,1,8.763671875,58]}}
  #|{"textrec":{"m":[14,400,0],"r":[13.53515625,2.953125,20,13.53515625,2.953125,0]}}
  #|{"textrec":{"s":[16,400,0,"…"],"r":[0,1,12.5625,59]}}
  #|{"textrec":{"s":[16,400,0,"端到端测试的对话 post:你好，我是测试用的…"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,26,3,1,15.875486381322958,28,4,1,15.875486381322958,29,5,1,15.875486381322958,30,6,1,15.875486381322958,31,7,1,15.875486381322958,32,8,1,4.1875,-1,9,1,9.453125,33,10,1,9.140625,34,11,1,8.0234375,35,12,1,5.4609375,36,13,1,4.4375,37,14,1,15.875486381322958,38,15,1,15.875486381322958,39,16,1,16.09338521400778,40,17,1,15.875486381322958,41,18,1,15.875486381322958,42,19,1,15.87548638132293,28,20,1,15.875486381322958,29,21,1,15.875486381322958,43,22,1,15.875486381322958,30,23,1,12.5625,59]}}
  #|{"textrec":{"s":[16,400,0,"要归档的对话 083209 post:归档前的回复 083209"],"r":[0,1,15.875486381322958,60,1,1,15.875486381322958,61,2,1,15.875486381322958,62,3,1,15.875486381322958,30,4,1,15.875486381322958,31,5,1,15.875486381322958,32,6,1,4.1875,-1,7,1,9.765625,63,8,1,9.90625,64,9,1,9.71875,65,10,1,9.34375,66,11,1,9.765625,63,12,1,9.875,67,13,1,4.1875,-1,14,1,9.453125,33,15,1,9.140625,34,16,1,8.0234375,35,17,1,5.4609375,36,18,1,4.4375,37,19,1,15.875486381322958,61,20,1,15.875486381322958,62,21,1,15.875486381322958,68,22,1,15.875486381322958,30,23,1,15.875486381322958,69,24,1,15.875486381322958,70,25,1,4.1875,-1,26,1,9.765625,63,27,1,9.90625,64,28,1,9.71875,65,29,1,9.34375,66,30,1,9.765625,63,31,1,9.875,67]}}
  #|{"textrec":{"s":[14,400,0,"出错：意外停止"],"r":[0,1,13.891050583657588,71,1,1,13.891050583657588,72,2,1,14.081712062256813,73,3,1,13.891050583657588,74,4,1,13.891050583657588,75,5,1,13.891050583657588,76,6,1,13.891050583657588,77]}}
  #|{"textrec":{"s":[16,400,0,"要归档的对话 083209 post:归档前的回复 08…"],"r":[0,1,15.875486381322958,60,1,1,15.875486381322958,61,2,1,15.875486381322958,62,3,1,15.875486381322958,30,4,1,15.875486381322958,31,5,1,15.875486381322958,32,6,1,4.1875,-1,7,1,9.765625,63,8,1,9.90625,64,9,1,9.71875,65,10,1,9.34375,66,11,1,9.765625,63,12,1,9.875,67,13,1,4.1875,-1,14,1,9.453125,33,15,1,9.140625,34,16,1,8.0234375,35,17,1,5.4609375,36,18,1,4.4375,37,19,1,15.875486381322958,61,20,1,15.875486381322958,62,21,1,15.875486381322958,68,22,1,15.875486381322958,30,23,1,15.875486381322958,69,24,1,15.875486381322958,70,25,1,4.1875,-1,26,1,9.765625,63,27,1,9.6328125,64,28,1,12.2890625,78]}}
  #|{"textrec":{"g":18,"r":[51,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":19,"r":[69,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":20,"r":[86,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":21,"r":[104,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":22,"r":[121,0,15,16,0,-13,0]}}
  #|{"textrec":{"g":23,"r":[137,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":24,"r":[154,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":25,"r":[172,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":26,"r":[190,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":27,"r":[208,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":28,"r":[226,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":29,"r":[244,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":30,"r":[263,0,16,17,0,-14,0]}}
  #|{"textrec":{"g":31,"r":[280,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":32,"r":[298,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":33,"r":[317,0,10,14,0,-10,0]}}
  #|{"textrec":{"g":34,"r":[328,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":35,"r":[340,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":36,"r":[351,0,8,14,-1,-12,0]}}
  #|{"textrec":{"g":37,"r":[360,0,5,11,0,-9,0]}}
  #|{"textrec":{"g":38,"r":[366,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":39,"r":[384,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":40,"r":[402,0,6,7,0,-3,0]}}
  #|{"textrec":{"g":41,"r":[409,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":42,"r":[427,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":43,"r":[445,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":59,"r":[462,0,13,5,0,-3,0]}}
  #|{"textrec":{"g":48,"r":[476,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":49,"r":[493,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":50,"r":[510,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":51,"r":[526,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":52,"r":[543,0,16,15,-1,-12,0]}}
  #|{"textrec":{"g":53,"r":[560,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":54,"r":[576,0,10,14,-1,-12,0]}}
  #|{"textrec":{"g":55,"r":[587,0,11,14,-1,-12,0]}}
  #|{"textrec":{"g":56,"r":[599,0,10,14,-1,-12,0]}}
  #|{"textrec":{"g":57,"r":[610,0,9,13,0,-12,0]}}
  #|{"textrec":{"g":58,"r":[620,0,11,14,-1,-12,0]}}
  #|{"textrec":{"g":60,"r":[632,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":61,"r":[650,0,16,17,0,-14,0]}}
  #|{"textrec":{"g":62,"r":[667,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":63,"r":[685,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":64,"r":[697,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":65,"r":[709,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":66,"r":[721,0,10,14,0,-13,0]}}
  #|{"textrec":{"g":67,"r":[732,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":68,"r":[744,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":69,"r":[762,0,16,16,0,-13,0]}}
  #|{"textrec":{"g":70,"r":[779,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":78,"r":[797,0,13,5,-0.2734375,-3,0]}}
  #|{"textrec":{"g":71,"r":[811,0,14,16,0,-13,0]}}
  #|{"textrec":{"g":72,"r":[826,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":73,"r":[843,0,5,10,1,-10,0]}}
  #|{"textrec":{"g":74,"r":[849,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":75,"r":[866,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":76,"r":[883,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":77,"r":[899,0,15,15,-1,-13,0]}}
  #|{"textrec":{"ib":["33d1dfbf90932d3b",1241,64],"r":[17,17,17,17]}}
  #|{"textrec":{"ib":["5945e93431220f31",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["182b7158e0c0cae1",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["d61ec6305f7d8c8b",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["8bf9607b651cec61",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"s":[17,400,0,"会话"],"r":[0,1,16.851167315175097,79,1,1,16.851167315175097,80]}}
  #|{"textrec":{"m":[17,400,0],"r":[16.435546875,3.5859375,24,16.435546875,3.5859375,0]}}
  #|{"textrec":{"s":[32,700,8,"设置"],"r":[0,1,30.345864661654133,81,1,1,30.345864661654133,82]}}
  #|{"textrec":{"m":[32,700,0],"r":[30.9375,6.75,45,27.5185546875,4.4814453125,0]}}
  #|{"textrec":{"s":[16,700,0,"Name of alice"],"r":[0,1,11.9765625,83,1,1,9.12109375,84,2,1,14.6015625,85,3,1,9.30078125,86,4,1,3.8125,-1,5,1,9.6015625,87,6,1,6.21484375,88,7,1,3.8125,-1,8,1,9.12109375,84,9,1,4.40625,89,10,1,4.28125,90,11,1,9.0859375,91,12,1,9.30078125,86]}}
  #|{"textrec":{"m":[16,700,0],"r":[15.46875,3.375,23,15.46875,3.375,0]}}
  #|{"textrec":{"s":[13,400,0,"alice@example.test"],"r":[0,1,7.0966796875,12,1,1,3.2119140625,92,2,1,3.1357421875,93,3,1,7.1982421875,13,4,1,7.3505859375,14,5,1,11.857421875,94,6,1,7.2236328125,14,7,1,6.6142578125,95,8,1,7.0966796875,12,9,1,11.2353515625,96,10,1,7.8583984375,11,11,1,3.2119140625,92,12,1,7.3505859375,14,13,1,3.65625,97,14,1,4.471923828125,98,15,1,7.302978515625,14,16,1,6.69677734375,10,17,1,4.61474609375,98]}}
  #|{"textrec":{"s":[23,600,0,"N"],"r":[0,1,16.576080499507952,99]}}
  #|{"textrec":{"m":[23,600,0],"r":[22.236328125,4.8515625,33,19.778961181640625,3.221038818359375,0]}}
  #|{"textrec":{"s":[15,600,0,"Dev"],"r":[0,1,10.861195921897888,100,1,1,8.51915180683136,101,2,1,8.18638265132904,102]}}
  #|{"textrec":{"s":[15,400,0,"Workspace"],"r":[0,1,13.916015625,103,1,1,8.26171875,104,2,1,5.478515625,105,3,1,7.763671875,106,4,1,7.470703125,107,5,1,8.9208984375,108,6,1,8.0419921875,109,7,1,8.1591796875,110,8,1,8.3349609375,111]}}
  #|{"textrec":{"s":[14,400,0,"未开启"],"r":[0,1,13.891050583657588,112,1,1,13.891050583657588,113,2,1,13.891050583657588,114]}}
  #|{"textrec":{"s":[15,400,0,"安全"],"r":[0,1,14.883268482490273,115,1,1,14.883268482490273,20]}}
  #|{"textrec":{"s":[15,400,0,"Station"],"r":[0,1,9.32373046875,116,1,1,5.21484375,117,2,1,8.0419921875,109,3,1,5.21484375,117,4,1,3.4716796875,118,5,1,8.6279296875,104,6,1,8.51806640625,119]}}
  #|{"textrec":{"s":[15,400,0,"连接"],"r":[0,1,14.883268482490273,120,1,1,14.883268482490273,121]}}
  #|{"textrec":{"s":[15,400,0,"Profile"],"r":[0,1,9.29443359375,122,1,1,5.36865234375,105,2,1,8.51806640625,104,3,1,5.19287109375,123,4,1,3.4716796875,118,5,1,3.5595703125,124,6,1,8.3349609375,111]}}
  #|{"textrec":{"s":[15,400,0,"自动决策"],"r":[0,1,14.883268482490273,125,1,1,14.883268482490273,126,2,1,14.883268482490273,127,3,1,14.883268482490273,128]}}
  #|{"textrec":{"s":[15,400,0,"记忆"],"r":[0,1,14.883268482490273,129,1,1,14.883268482490273,130]}}
  #|{"textrec":{"s":[15,400,0,"用量"],"r":[0,1,14.883268482490273,131,1,1,14.883268482490273,132]}}
  #|{"textrec":{"s":[15,600,0,"此设备"],"r":[0,1,14.883268482490273,133,1,1,14.883268482490273,134,2,1,14.883268482490273,135]}}
  #|{"textrec":{"s":[14,400,0,"跟随系统"],"r":[0,1,13.891050583657588,136,1,1,13.891050583657588,137,2,1,13.891050583657588,138,3,1,13.891050583657588,139]}}
  #|{"textrec":{"s":[15,400,0,"外观"],"r":[0,1,14.883268482490273,140,1,1,14.883268482490273,141]}}
  #|{"textrec":{"s":[14,400,0,"2 栏"],"r":[0,1,8.298828125,57,1,1,3.787109375,-1,2,1,13.891050583657588,142]}}
  #|{"textrec":{"s":[15,400,0,"下方栏"],"r":[0,1,14.883268482490273,143,1,1,14.883268482490273,144,2,1,14.883268482490273,145]}}
  #|{"textrec":{"s":[15,400,0,"本机缓存"],"r":[0,1,14.883268482490273,146,1,1,14.883268482490273,147,2,1,14.883268482490273,148,3,1,14.883268482490273,149]}}
  #|{"textrec":{"s":[15,400,0,"通知"],"r":[0,1,14.883268482490273,150,1,1,14.883268482490273,151]}}
  #|{"textrec":{"s":[13,400,0,"任务完成、需要处理、出错或有新消息时通知你"],"r":[0,1,12.898832684824903,152,1,1,12.898832684824903,153,2,1,12.898832684824903,154,3,1,12.898832684824903,155,4,1,13.075875486381321,156,5,1,12.89883268482491,157,6,1,12.898832684824896,158,7,1,12.898832684824896,159,8,1,12.898832684824896,160,9,1,13.075875486381335,156,10,1,12.898832684824896,161,11,1,12.898832684824896,162,12,1,12.898832684824896,163,13,1,12.898832684824896,164,14,1,12.898832684824896,165,15,1,12.898832684824896,166,16,1,12.898832684824896,167,17,1,12.898832684824896,168,18,1,12.898832684824896,169,19,1,12.898832684824924,170,20,1,12.898832684824924,4]}}
  #|{"textrec":{"s":[15,400,0,"检查更新"],"r":[0,1,14.883268482490273,171,1,1,14.883268482490273,172,2,1,14.883268482490273,173,3,1,14.883268482490273,174]}}
  #|{"textrec":{"s":[15,400,0,"still.fail mbui 0.1"],"r":[0,1,7.58056640625,107,1,1,5.17822265625,117,2,1,3.4716796875,118,3,1,3.5595703125,124,4,1,3.5595703125,124,5,1,3.9990234375,175,6,1,4.86328125,123,7,1,7.93212890625,109,8,1,3.4716796875,118,9,1,3.5595703125,124,10,1,3.984375,-1,11,1,12.8173828125,176,12,1,8.9794921875,177,13,1,8.51806640625,178,14,1,3.4716796875,118,15,1,3.984375,-1,16,1,8.9208984375,179,17,1,3.7060546875,175,18,1,6.50390625,180]}}
  #|{"textrec":{"s":[15,400,0,"更新日志"],"r":[0,1,14.883268482490273,173,1,1,14.883268482490273,174,2,1,14.883268482490273,181,3,1,14.883268482490273,182]}}
  #|{"textrec":{"s":[15,600,0,"Dev · 你是Owner"],"r":[0,1,10.861195921897888,100,1,1,8.51915180683136,101,2,1,8.18638265132904,102,3,1,3.761730194091797,-1,4,1,7.186782927948599,183,5,1,3.761730194091797,-1,6,1,14.883268482490273,184,7,1,14.883268482490273,185,8,1,13.354362845420837,186,9,1,12.072962522506714,187,10,1,8.93320620059967,188,11,1,8.615586161613464,101,12,1,5.99338173866272,189]}}
  #|{"textrec":{"s":[14,400,0,"1 人"],"r":[0,1,6.34375,190,1,1,3.787109375,-1,2,1,13.891050583657588,191]}}
  #|{"textrec":{"s":[14,400,0,"0 条"],"r":[0,1,8.66796875,54,1,1,3.787109375,-1,2,1,13.891050583657588,192]}}
  #|{"textrec":{"s":[15,400,0,"密钥"],"r":[0,1,14.883268482490273,193,1,1,14.883268482490273,194]}}
  #|{"textrec":{"s":[14,400,0,"1/1 在线"],"r":[0,1,6.34375,190,1,1,4.115234375,195,2,1,6.34375,190,3,1,3.787109375,-1,4,1,13.891050583657588,196,5,1,13.891050583657588,197]}}
  #|{"textrec":{"s":[14,400,0,"0 个"],"r":[0,1,8.66796875,54,1,1,3.787109375,-1,2,1,13.891050583657588,49]}}
  #|{"textrec":{"s":[14,400,0,"1 个"],"r":[0,1,6.34375,190,1,1,3.787109375,-1,2,1,13.891050583657588,49]}}
  #|{"textrec":{"ib":["504a4df6beac534a",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["a1e7be43eb966606",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"g":79,"r":[915,0,18,18,-1,-15,0]}}
  #|{"textrec":{"g":80,"r":[934,0,19,18,-1,-15,0]}}
  #|{"textrec":{"g":81,"r":[954,0,31,31,0,-26,0]}}
  #|{"textrec":{"g":82,"r":[986,0,30,29,0,-25,0]}}
  #|{"textrec":{"g":100,"r":[1017,0,12,13,0,-12,0]}}
  #|{"textrec":{"g":101,"r":[1030,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":102,"r":[1042,0,11,11,-1,-10,0]}}
  #|{"textrec":{"g":183,"r":[1054,0,5,5,1,-8,0]}}
  #|{"textrec":{"g":184,"r":[1060,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":185,"r":[1077,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":186,"r":[1094,0,13,14,-1,-12,0]}}
  #|{"textrec":{"g":187,"r":[1108,0,14,11,-1,-10,0]}}
  #|{"textrec":{"g":188,"r":[1123,0,10,11,0,-10,0]}}
  #|{"textrec":{"g":189,"r":[1134,0,7,11,0,-10,0]}}
  #|{"textrec":{"g":103,"r":[1142,0,16,13,-1,-12,0]}}
  #|{"textrec":{"g":104,"r":[1159,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":105,"r":[1171,0,7,11,0,-10,0]}}
  #|{"textrec":{"g":106,"r":[1179,0,9,14,0,-13,0]}}
  #|{"textrec":{"g":107,"r":[1189,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":108,"r":[1200,0,10,14,0,-10,0]}}
  #|{"textrec":{"g":109,"r":[1211,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":110,"r":[1222,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":111,"r":[1233,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":115,"r":[1244,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":193,"r":[1261,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":194,"r":[1278,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":116,"r":[1295,0,11,14,-1,-12,0]}}
  #|{"textrec":{"g":117,"r":[1307,0,7,13,-1,-11,0]}}
  #|{"textrec":{"g":118,"r":[1315,0,5,14,-1,-13,0]}}
  #|{"textrec":{"g":119,"r":[1321,0,9,11,0,-10,0]}}
  #|{"textrec":{"g":120,"r":[1331,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":121,"r":[1348,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":122,"r":[1365,0,10,13,0,-12,0]}}
  #|{"textrec":{"g":123,"r":[1376,0,7,14,-1,-13,0]}}
  #|{"textrec":{"g":124,"r":[1384,0,4,14,0,-13,0]}}
  #|{"textrec":{"g":125,"r":[1389,0,13,16,1,-13,0]}}
  #|{"textrec":{"g":126,"r":[1403,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":127,"r":[1420,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":128,"r":[1438,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":129,"r":[1455,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":130,"r":[1473,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":131,"r":[1490,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":132,"r":[1506,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":133,"r":[1523,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":134,"r":[1541,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":135,"r":[1559,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":140,"r":[1577,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":141,"r":[1595,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":143,"r":[1613,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":144,"r":[1630,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":145,"r":[1647,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":146,"r":[1664,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":147,"r":[1682,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":148,"r":[1700,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":149,"r":[1718,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":99,"r":[1735,0,17,19,0,-18,0]}}
  #|{"textrec":{"g":83,"r":[1753,0,12,14,0,-13,0]}}
  #|{"textrec":{"g":84,"r":[1766,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":85,"r":[1778,0,15,11,0,-10,0]}}
  #|{"textrec":{"g":86,"r":[1794,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":87,"r":[1806,0,12,12,-1,-10,0]}}
  #|{"textrec":{"g":88,"r":[1819,0,8,14,-1,-13,0]}}
  #|{"textrec":{"g":89,"r":[1828,0,5,14,0,-13,0]}}
  #|{"textrec":{"g":90,"r":[1834,0,5,15,0,-14,0]}}
  #|{"textrec":{"g":91,"r":[1840,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":12,"r":[1852,0,9,10,-1,-8,0]}}
  #|{"textrec":{"g":92,"r":[1862,0,4,12,0,-11,0]}}
  #|{"textrec":{"g":93,"r":[1867,0,5,12,-1,-11,0]}}
  #|{"textrec":{"g":13,"r":[1873,0,9,10,-1,-8,0]}}
  #|{"textrec":{"g":14,"r":[1883,0,9,10,-1,-8,0]}}
  #|{"textrec":{"g":94,"r":[1893,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":95,"r":[1908,0,9,9,-1,-8,0]}}
  #|{"textrec":{"g":96,"r":[1918,0,12,9,0,-8,0]}}
  #|{"textrec":{"g":11,"r":[1931,0,9,12,0,-8,0]}}
  #|{"textrec":{"g":97,"r":[1941,0,4,5,0,-3,0]}}
  #|{"textrec":{"g":98,"r":[1946,0,7,12,-1,-10,0]}}
  #|{"textrec":{"g":10,"r":[1954,0,9,10,-1,-8,0]}}
  #|{"textrec":{"g":112,"r":[1964,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":113,"r":[1980,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":114,"r":[1996,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":190,"r":[2012,0,7,12,-1,-11,0]}}
  #|{"textrec":{"g":195,"r":[2020,0,7,16,-1,-12,0]}}
  #|{"textrec":{"g":196,"r":[2028,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":197,"r":[0,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":136,"r":[17,32,16,15,-1,-12,0]}}
  #|{"textrec":{"g":137,"r":[34,32,15,16,0,-13,0]}}
  #|{"textrec":{"g":138,"r":[50,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":139,"r":[66,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":191,"r":[83,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":192,"r":[100,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":142,"r":[117,32,16,16,-1,-13,0]}}
  #|{"textrec":{"ib":["b3685975cd23abc3",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"g":150,"r":[134,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":151,"r":[151,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":152,"r":[168,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":153,"r":[184,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":154,"r":[200,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":155,"r":[216,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":156,"r":[232,32,6,6,0,-3,0]}}
  #|{"textrec":{"g":157,"r":[239,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":158,"r":[254,32,15,14,-1,-11,0]}}
  #|{"textrec":{"g":159,"r":[270,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":160,"r":[286,32,15,13,-1,-11,0]}}
  #|{"textrec":{"g":161,"r":[302,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":162,"r":[316,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":163,"r":[332,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":164,"r":[348,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":165,"r":[363,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":166,"r":[379,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":167,"r":[394,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":168,"r":[410,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":169,"r":[426,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":170,"r":[442,32,14,14,-1,-12,0]}}
  #|{"textrec":{"g":4,"r":[457,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":175,"r":[472,32,5,5,0,-3,0]}}
  #|{"textrec":{"g":176,"r":[478,32,13,11,0,-10,0]}}
  #|{"textrec":{"g":177,"r":[492,32,10,15,0,-13,0]}}
  #|{"textrec":{"g":178,"r":[503,32,9,11,0,-9,0]}}
  #|{"textrec":{"g":179,"r":[513,32,11,14,-1,-12,0]}}
  #|{"textrec":{"g":180,"r":[525,32,8,13,-1,-12,0]}}
  #|{"textrec":{"g":171,"r":[534,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":172,"r":[552,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":173,"r":[569,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":174,"r":[587,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":181,"r":[605,32,12,16,1,-13,0]}}
  #|{"textrec":{"g":182,"r":[618,32,16,16,-1,-13,0]}}
  #|{"textrec":{"s":[13,400,0,"不接收通知"],"r":[0,1,12.898832684824903,198,1,1,12.898832684824903,199,2,1,12.898832684824903,200,3,1,12.898832684824903,169,4,1,12.898832684824896,170]}}
  #|{"textrec":{"g":198,"r":[635,32,15,14,-1,-11,0]}}
  #|{"textrec":{"g":199,"r":[651,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":200,"r":[667,32,15,15,-1,-12,0]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 post:你好，我是测试用的 agent"],"r":[0,1,15.875486381322958,201,1,1,15.875486381322958,202,2,1,15.875486381322958,201,3,1,15.875486381322958,203,4,1,15.875486381322958,204,5,1,15.875486381322958,205,6,1,15.875486381322958,206,7,1,15.875486381322958,207,8,1,3.95001220703125,-1,9,1,9.824199676513672,208,10,1,9.432537078857422,209,11,1,8.471200942993164,210,12,1,5.973020553588867,211,13,1,4.952056884765625,212,14,1,15.875486381322958,213,15,1,15.875486381322958,214,16,1,16.09338521400778,215,17,1,15.875486381322958,216,18,1,15.875486381322958,217,19,1,15.87548638132293,203,20,1,15.875486381322958,204,21,1,15.875486381322958,218,22,1,15.875486381322958,205,23,1,3.95001220703125,-1,24,1,8.899068832397461,219,25,1,9.801153182983398,220,26,1,9.127458572387695,221,27,1,9.466253280639648,222,28,1,5.999713897705078,211]}}
  #|{"textrec":{"m":[16,600,0],"r":[15.46875,3.375,23,15.46875,3.375,0]}}
  #|{"textrec":{"s":[14,400,0,"关着的时候 083209"],"r":[0,1,13.891050583657588,223,1,1,13.891050583657588,224,2,1,13.891050583657588,225,3,1,13.891050583657588,226,4,1,13.891050583657588,227,5,1,3.787109375,-1,6,1,8.66796875,54,7,1,8.791015625,55,8,1,8.626953125,56,9,1,8.298828125,57,10,1,8.66796875,54,11,1,8.763671875,58]}}
  #|{"textrec":{"s":[16,600,0,"…"],"r":[0,1,14.076484680175781,228]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 post:你好，我是测试用的…"],"r":[0,1,15.875486381322958,201,1,1,15.875486381322958,202,2,1,15.875486381322958,201,3,1,15.875486381322958,203,4,1,15.875486381322958,204,5,1,15.875486381322958,205,6,1,15.875486381322958,206,7,1,15.875486381322958,207,8,1,3.95001220703125,-1,9,1,9.824199676513672,208,10,1,9.432537078857422,209,11,1,8.471200942993164,210,12,1,5.973020553588867,211,13,1,4.952056884765625,212,14,1,15.875486381322958,213,15,1,15.875486381322958,214,16,1,16.09338521400778,215,17,1,15.875486381322958,216,18,1,15.875486381322958,217,19,1,15.87548638132293,203,20,1,15.875486381322958,204,21,1,15.875486381322958,218,22,1,15.875486381322958,205,23,1,14.076484680175781,228]}}
  #|{"textrec":{"g":201,"r":[683,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":202,"r":[701,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":203,"r":[719,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":204,"r":[737,32,18,17,-1,-14,0]}}
  #|{"textrec":{"g":205,"r":[756,32,16,17,0,-14,0]}}
  #|{"textrec":{"g":206,"r":[773,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":207,"r":[791,32,18,17,-1,-14,0]}}
  #|{"textrec":{"g":208,"r":[810,32,11,14,0,-10,0]}}
  #|{"textrec":{"g":209,"r":[822,32,11,12,-1,-10,0]}}
  #|{"textrec":{"g":210,"r":[834,32,11,12,-1,-10,0]}}
  #|{"textrec":{"g":211,"r":[846,32,8,14,-1,-12,0]}}
  #|{"textrec":{"g":212,"r":[855,32,5,12,0,-10,0]}}
  #|{"textrec":{"g":213,"r":[861,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":214,"r":[879,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":215,"r":[897,32,6,8,0,-4,0]}}
  #|{"textrec":{"g":216,"r":[904,32,18,17,-1,-14,0]}}
  #|{"textrec":{"g":217,"r":[923,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":218,"r":[941,32,16,17,-1,-14,0]}}
  #|{"textrec":{"g":228,"r":[958,32,14,6,0,-4,0]}}
  #|{"textrec":{"g":223,"r":[973,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":224,"r":[989,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":225,"r":[1005,32,14,16,0,-13,0]}}
  #|{"textrec":{"g":226,"r":[1020,32,15,16,0,-13,0]}}
  #|{"textrec":{"g":227,"r":[1036,32,16,16,-1,-13,0]}}
