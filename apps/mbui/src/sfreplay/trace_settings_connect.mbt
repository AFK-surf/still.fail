// e2e/traces/settings-connect.trace, made by scripts/trace.py from 01-settings_connect.log: not edited by hand.

///|
/// What the app and its core said in the run, a line each.
pub let trace_settings_connect : String =
  #|{"step":"peer connect-put e2e-080726"}
  #|{"env":{"MBUI_CLOUD":"http://127.0.0.1:18787","MBUI_CORE_ACCOUNT":"{\"sub\":\"alice\",\"email\":\"alice@example.test\",\"name\":\"Name of alice\",\"picture\":\"\",\"access\":\"-\",\"refresh\":\"-\",\"accessExpires\":1792593799}"}}
  #|{"out":{"id":1,"call":"client.device","params":{"client":"still.fail mbui","app":"desktop","userAgent":"Macintosh; Mac OS X"}},"w":1792593503970.627}
  #|{"in":{"id":1,"ok":null},"w":1792593504062.552}
  #|{"out":{"id":2,"subscribe":{"topic":"accounts"},"keyed":true},"w":1792593504062.578}
  #|{"out":{"id":3,"subscribe":{"topic":"prefs"},"keyed":true},"w":1792593504062.588}
  #|{"step":"# written by scripts/rerecord.sh from its test (src/sfreplay/emit.mbt): not edited by hand","w":1792593504064.039}
  #|{"step":"timeout 90000","w":1792593504064.045}
  #|{"step":"answered client.device","w":1792593504064.048}
  #|{"step":"answered client.focus","w":1792593504089.481}
  #|{"in":{"id":2,"value":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""}]},"w":1792593504139.072}
  #|{"in":{"id":3,"value":{"onlyMine":false,"onlyWatching":false,"onlyDecisions":false,"listFilter":{},"appearance":"system","rowPicture":"auto","absoluteTime":false,"lang":"zh","keys":{},"lastChat":{},"openChat":{},"chatTabs":{},"dropFiles":{},"driveViews":{},"resume":{},"stationUpdatesDismissed":{},"device":{"app":"desktop","phone":false,"handoff":false},"reader":{"size":18,"line":1.7,"margin":22,"face":"sans","indent":true,"paper":"follow"},"rails":{},"bars":{"sets":[["chats","files","profiles","stations"],["decisions","usage","connects","archive"]],"current":0},"barsBy":{},"fonts":{},"faces":{"ui":{"id":"","name":"","mono":false,"family":"","files":[],"bytes":0},"text":{"id":"","name":"","mono":false,"family":"","files":[],"bytes":0},"code":{"id":"","name":"","mono":true,"family":"","files":[],"bytes":0},"list":[{"id":"inter","name":"Inter","mono":false,"family":"SF Inter","css":"http://127.0.0.1:18787/releases/fonts/inter/4.001/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/inter/4.001/var.ttf.gz","bytes":457818,"sha256":"29160a80ff49ddcab2c97711247e08b1fab27a484a329ce8b813d820dc559031"}],"preview":"http://127.0.0.1:18787/releases/fonts/inter/4.001/preview-194fa287.ttf","bytes":457818},{"id":"noto-sans-sc","name":"思源黑体","mono":false,"family":"SF Noto Sans SC","css":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/var.ttf.gz","bytes":11276563,"sha256":"a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da"}],"preview":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/preview-f0494178.ttf","bytes":11276563},{"id":"noto-serif-sc","name":"思源宋体","mono":false,"family":"SF Noto Serif SC","css":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/var.ttf.gz","bytes":15454579,"sha256":"050080d9255a86808f2945bffac582b31ef32bc36411ce29563b4961670c66f9"}],"preview":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/preview-001bbedf.ttf","bytes":15454579},{"id":"lxgw-wenkai","name":"霞鹜文楷","mono":false,"family":"SF LXGW WenKai","css":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/font.css","files":[{"weight":400,"url":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/400.ttf.gz","bytes":12904482,"sha256":"2d73eea94ad808999d90c0000c239a84a33b09d4bc6ab6c5b8bbf1eda8a7fc8b"},{"weight":500,"url":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/500.ttf.gz","bytes":13272430,"sha256":"f4b8a34d1f838fe411540cb7c97b1c384ac9738a876c4104500bc42508b2312a"}],"preview":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/preview-d3505af4.ttf","bytes":26176912},{"id":"jetbrains-mono","name":"JetBrains Mono","mono":true,"family":"SF JetBrains Mono","css":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/var.ttf.gz","bytes":90579,"sha256":"48715a42ec242c21e9f02692891e147d022299a52e48d5e413e1a942193ffeda"}],"preview":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/preview-ee73078f.ttf","bytes":90579},{"id":"fira-code","name":"Fira Code","mono":true,"family":"SF Fira Code","css":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/var.ttf.gz","bytes":137151,"sha256":"9335b082b3c7850d98a64b584f3417f65355f3471278bb5eeb8c6c0e8657aeeb"}],"preview":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/preview-555be27a.ttf","bytes":137151},{"id":"maple-mono","name":"Maple Mono","mono":true,"family":"SF Maple Mono CN","css":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/font.css","files":[{"weight":400,"url":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/400.ttf.gz","bytes":8352545,"sha256":"0fcc5139bfd5ab14ff989bb7dfd5236d0cafc10e60b9828569e6883613ab4085"},{"weight":600,"url":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/600.ttf.gz","bytes":8438132,"sha256":"96ed7ae26ee7c50b02b2d2b2bc0f1a0cbabe45ae5d6e6abf6678e2177c415677"}],"preview":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/preview-cffdf246.ttf","bytes":16790677}]}}},"w":1792593504139.113}
  #|{"out":{"id":4,"subscribe":{"topic":"workspaces"},"keyed":true},"w":1792593504139.157}
  #|{"out":{"id":5,"subscribe":{"topic":"status"},"keyed":true},"w":1792593504139.166}
  #|{"in":{"id":4,"value":[{"account":{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""},"workspaces":[{"id":"01M5FEC1A8SXWCJ2CJR4NZWW4A","name":"Dev","role":"owner","created_at":1792593495,"stations":1,"members":1,"relays":[],"time":{"created_at":{"past":true,"at":1792593495000,"ago":"刚刚","full":"10/21 22:38:15","until":"1 分钟内"}}}],"invitations":[],"relay_url":"http://127.0.0.1:18740","loaded":true,"beta":true}]},"w":1792593504155.764}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792593504155.858}
  #|{"out":{"id":6,"subscribe":{"topic":"lock","workspace":"01M5FEC1A8SXWCJ2CJR4NZWW4A"},"keyed":true},"w":1792593504155.9}
  #|{"out":{"id":7,"subscribe":{"topic":"chats","scope":"01M5FEC1A8SXWCJ2CJR4NZWW4A","mine":false},"keyed":true},"w":1792593504155.913}
  #|{"out":{"id":8,"subscribe":{"topic":"changelog"},"keyed":true},"w":1792593504155.918}
  #|{"out":{"id":9,"subscribe":{"topic":"workspaceMarks","workspace":"01M5FEC1A8SXWCJ2CJR4NZWW4A"},"keyed":true},"w":1792593504156.039}
  #|{"out":{"id":10,"subscribe":{"topic":"status","workspace":"01M5FEC1A8SXWCJ2CJR4NZWW4A"},"keyed":true},"w":1792593504156.071}
  #|{"out":{"id":11,"subscribe":{"topic":"lockPrompts"},"keyed":true},"w":1792593504161.125}
  #|{"out":{"id":12,"call":"client.focus","params":{"visible":true,"focused":true,"workspace":"01M5FEC1A8SXWCJ2CJR4NZWW4A"}},"w":1792593504163.733}
  #|{"out":{"id":13,"subscribe":{"topic":"notify"},"keyed":true},"w":1792593504163.744}
  #|{"out":{"id":14,"subscribe":{"topic":"notify","workspace":"01M5FEC1A8SXWCJ2CJR4NZWW4A"},"keyed":true},"w":1792593504163.751}
  #|{"in":{"id":6,"value":{"available":true,"locked":false,"notice":true,"role":"owner","manages":true,"owner":true,"canSign":true,"signs":false,"me":{"device":"52d0e57782843b8a08448a0cb74446830deae97fbcc5ebb884032d4b3087633c","code":"CBR-BQR","kind":"app","confirmed":false,"waiting":false,"asked":false},"signers":0,"members":[],"stations":[{"id":"54e0965173aed663957a02cd87d2b07d8a95702891abadf91e52f5dc52bcd8e5","name":"studio","version":"0.1.0","online":true,"protected":false}],"protected":0,"requests":[],"renew":[],"attention":0}},"w":1792593504176.289}
  #|{"in":{"id":7,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"stations":[{"station":"01M5FEC1A8SXWCJ2CJR4NZWW4A/54e0965173aed663957a02cd87d2b07d8a95702891abadf91e52f5dc52bcd8e5","id":"54e0965173aed663957a02cd87d2b07d8a95702891abadf91e52f5dc52bcd8e5","name":"studio","state":"online"}],"loading":false,"days":[{"daysAgo":0,"at":1792593499332,"label":"今天","items":[{"id":"ember:c-3aac41200d","session":"ember:c-3aac41200d","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","agents":[{"key":"ember:c-3aac41200d","runtime":"claude","process":"warm","pending":0,"lastTurn":{"id":"6df3e2d4-c3a1-4904-9866-095d7b55a115","kind":"input","outcome":"completed","declared":"final","ending":"all_done","need":"answered the question that was asked","startedAt":1792593499264,"endedAt":1792593499334},"agentText":"默认模型","statusText":"已完成：answered the question that was asked"}],"last":{"seq":2,"authorKind":"agent","author":"ember:c-3aac41200d","text":"你好，我是测试用的 agent","createdAt":1792593499332,"by":{"kind":"agent","name":"agent","mine":false,"runtime":"claude","label":"agent"},"preview":"你好，我是测试用的 agent","time":{"createdAt":{"at":1792593499332,"ago":"刚刚","full":"10/21 22:38:19","until":"1 分钟内","past":true}}},"unread":true,"mine":true,"lastActiveAt":1792593499332,"station":"01M5FEC1A8SXWCJ2CJR4NZWW4A/54e0965173aed663957a02cd87d2b07d8a95702891abadf91e52f5dc52bcd8e5","stationName":"studio","time":{"lastActiveAt":{"at":1792593499332,"ago":"刚刚","full":"10/21 22:38:19","until":"1 分钟内","past":true}},"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"peopleText":"你 发起","clientKey":"new:chat-64c6778bb8ad8bb4bb","pinned":false,"tone":"done"}]}],"trouble":null,"members":1,"leading":"agents","glyph":{"online":1,"dim":0,"connecting":0,"failing":0,"working":0,"summary":"studio","label":"1 台 station，1 台在线"},"note":{"reading":false,"text":null,"failing":[],"empty":false}}},"w":1792593504176.32}
  #|{"in":{"id":8,"value":{"app":"desktop","tabs":[{"part":"desktop","label":"桌面","days":[]},{"part":"web","label":"网页","days":[]},{"part":"android","label":"安卓","days":[]},{"part":"station","label":"Station","days":[]},{"part":"cloud","label":"云端","days":[]}],"loading":false}},"w":1792593504176.341}
  #|{"in":{"id":9,"value":{"workspaces":{"01M5FEC1A8SXWCJ2CJR4NZWW4A":{"alert":0,"unread":1,"tone":"done","label":"1 个有新消息","badge":0,"items":[],"mineTone":"done"}},"badge":0,"badgeCounts":"attention","badgeKinds":{"on":true,"wait":true,"failed":true,"done":false,"message":false}}},"w":1792593504176.349}
  #|{"in":{"id":10,"value":{"items":[]}},"w":1792593504176.354}
  #|{"in":{"id":11,"value":{"pairing":[]}},"w":1792593504176.357}
  #|{"in":{"id":12,"ok":null},"w":1792593504176.359}
  #|{"in":{"id":13,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792593504176.369}
  #|{"in":{"id":14,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792593504176.374}
  #|{"out":{"id":15,"subscribe":{"topic":"longJobs","scope":"01M5FEC1A8SXWCJ2CJR4NZWW4A"},"keyed":true},"w":1792593504176.414}
  #|{"out":{"id":16,"call":"notify.permission","params":{"state":"unknown"}},"w":1792593504179.258}
  #|{"in":{"id":15,"value":{"groups":[]}},"w":1792593504189.076}
  #|{"in":{"id":16,"ok":null},"w":1792593504189.082}
  #|{"step":"answered notify.permission","w":1792593504198.379}
  #|{"step":"#before peer connect-put e2e-080726","w":1792593504205.969}
  #|{"step":"tap icon:settings","w":1792593504205.971}
  #|{"step":"tap icon:settings","acted":true,"w":1792593504205.983}
  #|{"out":{"id":17,"subscribe":{"topic":"workspace","workspace":"01M5FEC1A8SXWCJ2CJR4NZWW4A"},"keyed":true},"w":1792593504225.897}
  #|{"out":{"id":18,"subscribe":{"topic":"stations","scope":"01M5FEC1A8SXWCJ2CJR4NZWW4A"},"keyed":true},"w":1792593504225.936}
  #|{"out":{"id":19,"subscribe":{"topic":"connects","scope":"01M5FEC1A8SXWCJ2CJR4NZWW4A","mine":false},"keyed":true},"w":1792593504225.947}
  #|{"out":{"id":20,"subscribe":{"topic":"vaults","workspace":"01M5FEC1A8SXWCJ2CJR4NZWW4A"},"keyed":true},"w":1792593504225.958}
  #|{"out":{"id":21,"subscribe":{"topic":"doing"},"keyed":true},"w":1792593504232.944}
  #|{"step":"wait 299","w":1792593504234.165}
  #|{"in":{"id":17,"value":{"id":"01M5FEC1A8SXWCJ2CJR4NZWW4A","name":"Dev","role":"owner","created_at":1792593495,"members":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":"https://example.test/p.png","role":"owner","added_at":1792593495}],"stations":[{"id":"54e0965173aed663957a02cd87d2b07d8a95702891abadf91e52f5dc52bcd8e5","name":"studio","emoji":null,"icon":null,"enrolled_at":1792593495,"enrolled_by":"alice","last_seen":1792593499,"version":"0.1.0","time":{"last_seen":{"past":true,"at":1792593499000,"ago":"刚刚","full":"10/21 22:38:19","until":"1 分钟内"}}}],"invitations":[],"added":[],"relays":[],"lock":null,"lock_requests":0,"time":{"created_at":{"past":true,"at":1792593495000,"ago":"刚刚","full":"10/21 22:38:15","until":"1 分钟内"}}}},"w":1792593504239.092}
  #|{"in":{"id":18,"value":[{"station":"01M5FEC1A8SXWCJ2CJR4NZWW4A/54e0965173aed663957a02cd87d2b07d8a95702891abadf91e52f5dc52bcd8e5","id":"54e0965173aed663957a02cd87d2b07d8a95702891abadf91e52f5dc52bcd8e5","name":"studio","summary":"正在连接","face":"idle","line":"在线","online":true,"reconnecting":false,"lastSeen":1792593499,"version":"0.1.0","link":{"state":"online"},"runtimes":[{"runtime":"claude","models":["claude-sonnet-5-5"]}],"models":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792593499241,"time":{"checkedAt":{"at":1792593499241,"ago":"刚刚","full":"10/21 22:38:19","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"overview":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null,"summaryText":"最近 7 天检查了 0 个 chat","changeText":null}},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","email":"alice@example.test","name":"Name of alice","sub":"alice","role":"owner","workspace":"01M5FEC1A8SXWCJ2CJR4NZWW4A","device":"52d0e57782843b8a08448a0cb74446830deae97fbcc5ebb884032d4b3087633c"},"connects":[{"id":"e2e-080726","name":"e2e-080726","enabled":true,"kind":"slack","mode":"multi-session","requireMention":true,"bind":{"runtime":"claude","model":"claude-sonnet-5-5"},"slack":{"appToken":"","botToken":""},"connection":{"state":"no_tokens"},"createdBy":{"id":"alice@example.test","name":"Name of alice"},"sessions":0,"statusText":"未连接 Slack","presence":"offline","modeText":"多会话","modeShort":"多会话","runtimeText":"Claude Code","runText":"Claude Code · Sonnet 5.5","modelName":"Sonnet 5.5"}],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":["e2e-080726"],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792593499119,"time":{"checkedAt":{"at":1792593499119,"ago":"刚刚","full":"10/21 22:38:19","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792593499241,"time":{"checkedAt":{"at":1792593499241,"ago":"刚刚","full":"10/21 22:38:19","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"modelsReading":false,"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]}],"processes":[],"counts":{"sessions":1,"running":0,"warm":1},"mesh":{"state":"running","origin":"http://127.0.0.1:18787","station":"54e0965173aed663957a02cd87d2b07d8a95702891abadf91e52f5dc52bcd8e5","workspace":"Dev","workspaceId":"01M5FEC1A8SXWCJ2CJR4NZWW4A","name":"studio"},"slackUsers":[],"slackTeams":[],"slackApps":[],"feishuRegistrations":[],"disk":{"freeBytes":31506513920,"totalBytes":245107195904},"logins":[],"machineLogins":[],"sharing":true,"consoleSignIn":true,"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"google","name":"Google Gemini","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xai","name":"xAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"mistral","name":"Mistral","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"deepseek","name":"DeepSeek","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen","name":"Qwen","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai","name":"Kimi","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai","name":"Z.ai","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax","name":"MiniMax","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ant-ling","name":"Ant Ling","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"jev","name":"Jev","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen-cn","name":"Qwen (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"openrouter","name":"OpenRouter","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"opencode","name":"OpenCode Zen","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"groq","name":"Groq","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"together","name":"Together AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"fireworks","name":"Fireworks","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cerebras","name":"Cerebras","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"huggingface","name":"Hugging Face","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"nvidia","name":"NVIDIA","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"baseten","name":"Baseten","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ollama","name":"Ollama","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"custom","name":"Custom","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""}],"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792593498619},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.306","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792593498619},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-lockp/apps/e2e-local/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792593498619},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-lockp/apps/e2e-local/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792593498619},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","latest":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-lockp/apps/e2e-local/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792593498619},{"id":"cursor","name":"Cursor","installed":false,"latest":"1.0.40","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792593498619},{"id":"devin","name":"Devin","installed":true,"version":"3000.11.92","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-lockp/apps/e2e-local/ember/station/test/fake/devin，不是用 Devin 的安装脚本装的，需在该机器上手动更新","state":"idle","checkedAt":1792593498619}],"processesText":"没有运行中的 agent 进程","agentEnv":[],"drive":{"roots":[],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false}},"betaOffered":false,"way":{"path":"直连","via":"direct"},"time":{"lastSeen":{"at":1792593499000,"ago":"刚刚","full":"10/21 22:38:19","until":"1 分钟内","past":true}},"joined":false}]},"w":1792593504239.224}
  #|{"in":{"id":19,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"items":[{"station":"01M5FEC1A8SXWCJ2CJR4NZWW4A/54e0965173aed663957a02cd87d2b07d8a95702891abadf91e52f5dc52bcd8e5","stationName":"studio","connect":{"id":"e2e-080726","name":"e2e-080726","enabled":true,"kind":"slack","mode":"multi-session","requireMention":true,"bind":{"runtime":"claude","model":"claude-sonnet-5-5"},"slack":{"appToken":"","botToken":""},"connection":{"state":"no_tokens"},"createdBy":{"id":"alice@example.test","name":"Name of alice","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"sessions":0,"statusText":"未连接 Slack","presence":"offline","modeText":"多会话","modeShort":"多会话","runtimeText":"Claude Code","runText":"Claude Code · Sonnet 5.5","modelName":"Sonnet 5.5"},"sessions":[],"candidates":[{"key":"ember:c-3aac41200d","connect":"ember","scope":"all","createdBy":"alice@example.test","boundTo":[],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"},"participants":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"}],"runtime":"claude","profile":"cc","profilePinned":false,"runtimeSessionId":"a7dabb72-2f8d-45f2-9ef7-a575704656f6","workspace":"/tmp/mbe2e-C/data/sessions/ember/c-3aac41200d/workspace","running":false,"createdAt":1792593499182,"lastActiveAt":1792593499334,"process":"warm","turns":1,"pending":0,"firstText":"端到端测试的对话 post:你好，我是测试用的 agent","lastTurn":{"id":"6df3e2d4-c3a1-4904-9866-095d7b55a115","kind":"input","outcome":"completed","declared":"final","ending":"all_done","need":"answered the question that was asked","startedAt":1792593499264,"endedAt":1792593499334},"statusText":"已完成：answered the question that was asked","tone":"green","titleText":"端到端测试的对话 post:你好，我是测试用的 agent","agentText":"默认模型","runtimeText":"Claude Code","processText":"保温中","efforts":["low","medium","high","xhigh","max"],"time":{"createdAt":{"at":1792593499182,"ago":"刚刚","full":"10/21 22:38:19","until":"1 分钟内","past":true},"lastActiveAt":{"at":1792593499334,"ago":"刚刚","full":"10/21 22:38:19","until":"1 分钟内","past":true}},"chat":1,"description":"单会话 · ember · 1 轮 · 刚刚","current":false}],"running":0}],"wait":{"reading":false,"text":null,"failing":[],"empty":false}}},"w":1792593504239.315}
  #|{"in":{"id":20,"value":{"available":true,"locked":false,"canSign":false,"setUp":false,"vaults":[{"id":"plain","name":"个人","owner":"alice","ownerName":"Name of alice","mine":true,"members":[{"sub":"alice","name":"Name of alice"}],"station":"54e0965173aed663957a02cd87d2b07d8a95702891abadf91e52f5dc52bcd8e5","stationName":"studio","items":0,"devices":0,"open":true,"keyed":true,"missing":0,"recoverable":false}],"requests":[],"refused":[{"station":"54e0965173aed663957a02cd87d2b07d8a95702891abadf91e52f5dc52bcd8e5","name":"studio","code":"vault_needs_lock"}],"plain":true}},"w":1792593504239.346}
  #|{"in":{"id":21,"value":{"doing":[]}},"w":1792593504239.353}
  #|{"in":{"id":18,"delta":[{"path":[0,"host"],"set":{"hostname":"3720-Mac-mini-1","os":"macOS 27.0.1","arch":"arm64","cpus":10,"cpuModel":"Apple M4","load":1.05,"cpuBusy":0.76,"uptimeSec":72866,"memory":{"totalBytes":17179869184,"usedBytes":9122562048,"swapUsedBytes":250347520},"disk":{"path":"/tmp/mbe2e-C/data","totalBytes":245107195904,"freeBytes":31506391040},"emberRssBytes":158856944,"checkedAt":1792593504350,"summary":"10 核 · 16 GB","line":"macOS 27.0.1 · 10 核 · 16 GB · 已运行 0 天","facts":["3720-Mac-mini-1","macOS 27.0.1","arm64 · 10 核","已运行 20 小时"],"meters":[{"label":"CPU","short":"CPU","percent":76,"left":24,"level":"amber","value":"76%","remaining":"空闲 24%","big":"24","unit":"%","title":"CPU 空闲","total":"负载 10.5","note":"负载 10.5 · Apple M4"},{"label":"内存","short":"内存","percent":53,"left":47,"level":"ok","value":"8.5 GB / 16.0 GB","remaining":"剩 7.5 G","big":"7.5","unit":"GB","title":"内存剩","total":"共 16 GB","note":"swap 0.2 GB"},{"label":"磁盘","short":"磁盘","percent":87,"left":13,"level":"amber","value":"剩余 29.3 GB / 228 GB","remaining":"剩 29.3 G","big":"29.3","unit":"GB","title":"磁盘剩","total":"共 228 GB"}],"identity":"Apple M4 · 16 GB · macOS 27.0.1","details":[{"label":"主机名","value":"3720-Mac-mini-1"},{"label":"芯片","value":"Apple M4 · 10 核 · arm64"},{"label":"已运行","value":"20 小时"},{"label":"still.fail","value":"进程占用 151 MB"}],"usage":"内存 8.5 GB / 16.0 GB · 磁盘 剩余 29.3 GB / 228 GB","emberText":"still.fail 151 MB"}},{"path":[0,"line"],"set":"Apple M4"},{"path":[0,"summary"],"set":"空闲 · Apple M4 · 16 GB · macOS 27.0.1"}]},"w":1792593504355.767}
  #|{"step":"now tap =连接","w":1792593504539.626}
  #|{"step":"now tap =连接","acted":true,"w":1792593504539.661}
  #|{"step":"wait 300","w":1792593504560.349}
  #|{"step":"now tap =e2e-080726","w":1792593504872.86}
  #|{"step":"now tap =e2e-080726","acted":true,"w":1792593504872.889}
  #|{"step":"wait 300","w":1792593504898.141}
  #|{"step":"now until 此连接尚未接入 Slack","w":1792593505223.284}
  #|{"step":"tap icon:more","w":1792593505223.333}
  #|{"step":"tap icon:more","acted":true,"w":1792593505223.364}
  #|{"step":"wait 1438","w":1792593505246.854}
  #|{"step":"now tap =停用","w":1792593506690.607}
  #|{"step":"now tap =停用","acted":true,"w":1792593506690.687}
  #|{"out":{"id":22,"call":"connect.put","params":{"station":"01M5FEC1A8SXWCJ2CJR4NZWW4A/54e0965173aed663957a02cd87d2b07d8a95702891abadf91e52f5dc52bcd8e5","id":"e2e-080726","input":{"enabled":false}}},"w":1792593506706.696}
  #|{"step":"answered connect.put","w":1792593506707.841}
  #|{"in":{"id":21,"value":{"doing":[{"call":"connect.put","params":{"station":"01M5FEC1A8SXWCJ2CJR4NZWW4A/54e0965173aed663957a02cd87d2b07d8a95702891abadf91e52f5dc52bcd8e5","id":"e2e-080726"},"since":1792593506707,"stage":"running"}]}},"w":1792593506772.435}
  #|{"in":{"id":18,"delta":[{"path":[0,"overview","connects",0,"connection","state"],"set":"disabled"},{"path":[0,"overview","connects",0,"enabled"],"set":false},{"path":[0,"overview","connects",0,"statusText"],"set":"已停用"},{"path":[0,"overview","disk","freeBytes"],"set":31501832192}]},"w":1792593506772.466}
  #|{"in":{"id":19,"delta":[{"path":["items",0,"connect","connection","state"],"set":"disabled"},{"path":["items",0,"connect","enabled"],"set":false},{"path":["items",0,"connect","statusText"],"set":"已停用"}]},"w":1792593506772.514}
  #|{"in":{"id":22,"ok":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null},"canEditPolicy":true},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","sub":"alice","email":"alice@example.test","name":"Name of alice","role":"owner","workspace":"01M5FEC1A8SXWCJ2CJR4NZWW4A","device":"52d0e57782843b8a08448a0cb74446830deae97fbcc5ebb884032d4b3087633c","lockDevice":{"base":"52d0e57782843b8a08448a0cb74446830deae97fbcc5ebb884032d4b3087633c","proof":"eb09a405cb928ec574563b05a0d1b19706214d21e015ad53c23e0c77a3ea4e06cc275b695aa02ada9b2958a560d636edf823de402fc61561df07aab93f17a304"},"home":true},"mesh":{"state":"running","origin":"http://127.0.0.1:18787","station":"54e0965173aed663957a02cd87d2b07d8a95702891abadf91e52f5dc52bcd8e5","workspace":"Dev","workspaceId":"01M5FEC1A8SXWCJ2CJR4NZWW4A","name":"studio"},"connects":[{"id":"e2e-080726","name":"e2e-080726","team":null,"botImage":null,"enabled":false,"kind":"slack","mode":"multi-session","requireMention":true,"bind":{"runtime":"claude","model":"claude-sonnet-5-5","effort":null,"profile":null},"slack":{"appToken":"","botToken":""},"connection":{"state":"disabled"},"createdBy":{"id":"alice@example.test","name":"Name of alice"},"sessions":0,"session":null}],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"email":null,"access":{"kind":"env","key":"","provider":null,"endpoint":null,"protocol":null,"login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"model":null,"models":["claude-sonnet-5-5"],"env":[],"usedBy":["e2e-080726"],"loginCommand":"","machine":false,"backgroundOnMessage":true,"fast":null,"check":{"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","models":null,"checkedAt":1792593499119,"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口","reason":"no_probabilities","model":null,"provider":null,"models":[]}},"login":null,"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792593499241},"share":null,"workspaces":[]}],"footprint":null,"processes":[],"counts":{"sessions":1,"running":0,"warm":1},"slackUsers":[],"slackTeams":[],"disk":{"freeBytes":31501832192,"totalBytes":245107195904},"logins":[],"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs"},{"id":"google","name":"Google Gemini","group":"labs"},{"id":"xai","name":"xAI","group":"labs"},{"id":"mistral","name":"Mistral","group":"labs"},{"id":"deepseek","name":"DeepSeek","group":"labs"},{"id":"qwen","name":"Qwen","group":"labs"},{"id":"moonshotai","name":"Kimi","group":"labs"},{"id":"zai","name":"Z.ai","group":"labs"},{"id":"minimax","name":"MiniMax","group":"labs"},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs"},{"id":"ant-ling","name":"Ant Ling","group":"labs"},{"id":"jev","name":"Jev","group":"labs"},{"id":"qwen-cn","name":"Qwen (China)","group":"labs"},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs"},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs"},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs"},{"id":"openrouter","name":"OpenRouter","group":"gateways"},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways"},{"id":"opencode","name":"OpenCode Zen","group":"gateways"},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways"},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted"},{"id":"groq","name":"Groq","group":"hosted"},{"id":"together","name":"Together AI","group":"hosted"},{"id":"fireworks","name":"Fireworks","group":"hosted"},{"id":"cerebras","name":"Cerebras","group":"hosted"},{"id":"huggingface","name":"Hugging Face","group":"hosted"},{"id":"nvidia","name":"NVIDIA","group":"hosted"},{"id":"baseten","name":"Baseten","group":"hosted"},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted"},{"id":"ollama","name":"Ollama","group":"local"},{"id":"custom","name":"Custom","group":"local"}],"machineLogins":[],"consoleSignIn":true,"sharing":true,"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792593498619},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.306","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792593498619},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-lockp/apps/e2e-local/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792593498619},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-lockp/apps/e2e-local/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792593498619},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","latest":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-lockp/apps/e2e-local/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792593498619},{"id":"cursor","name":"Cursor","installed":false,"latest":"1.0.40","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792593498619},{"id":"devin","name":"Devin","installed":true,"version":"3000.11.92","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-lockp/apps/e2e-local/ember/station/test/fake/devin，不是用 Devin 的安装脚本装的，需在该机器上手动更新","state":"idle","checkedAt":1792593498619}],"slackApps":[],"agentEnv":[],"drive":{"roots":[],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false},"feedback":true,"feishuRegistrations":[]}},"w":1792593506772.675}
  #|{"step":"until 已停用","w":1792593506789.945}
  #|{"step":"wait 1438","w":1792593506789.958}
  #|{"in":{"id":21,"value":{"doing":[]}},"w":1792593506839.105}
  #|{"step":"now tap 每个 thread 一个会话","w":1792593508239.825}
  #|{"step":"now tap 每个 thread 一个会话","acted":true,"w":1792593508239.878}
  #|{"step":"wait 1455","w":1792593508256.622}
  #|{"step":"now tap 所有 thread 共用一个会话","w":1792593509723.685}
  #|{"step":"now tap 所有 thread 共用一个会话","acted":true,"w":1792593509723.757}
  #|{"step":"until 改为单会话","w":1792593509740.603}
  #|{"step":"tap 改为单会话","w":1792593509773.344}
  #|{"step":"tap 改为单会话","acted":true,"w":1792593509773.376}
  #|{"out":{"id":23,"call":"connect.put","params":{"station":"01M5FEC1A8SXWCJ2CJR4NZWW4A/54e0965173aed663957a02cd87d2b07d8a95702891abadf91e52f5dc52bcd8e5","id":"e2e-080726","input":{"mode":"single-session","requireMention":true}}},"w":1792593509773.907}
  #|{"step":"answered connect.put","w":1792593509784.542}
  #|{"in":{"id":23,"ok":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null},"canEditPolicy":true},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","sub":"alice","email":"alice@example.test","name":"Name of alice","role":"owner","workspace":"01M5FEC1A8SXWCJ2CJR4NZWW4A","device":"52d0e57782843b8a08448a0cb74446830deae97fbcc5ebb884032d4b3087633c","lockDevice":{"base":"52d0e57782843b8a08448a0cb74446830deae97fbcc5ebb884032d4b3087633c","proof":"eb09a405cb928ec574563b05a0d1b19706214d21e015ad53c23e0c77a3ea4e06cc275b695aa02ada9b2958a560d636edf823de402fc61561df07aab93f17a304"},"home":true},"mesh":{"state":"running","origin":"http://127.0.0.1:18787","station":"54e0965173aed663957a02cd87d2b07d8a95702891abadf91e52f5dc52bcd8e5","workspace":"Dev","workspaceId":"01M5FEC1A8SXWCJ2CJR4NZWW4A","name":"studio"},"connects":[{"id":"e2e-080726","name":"e2e-080726","team":null,"botImage":null,"enabled":false,"kind":"slack","mode":"single-session","requireMention":true,"bind":{"runtime":"claude","model":"claude-sonnet-5-5","effort":null,"profile":null},"slack":{"appToken":"","botToken":""},"connection":{"state":"disabled"},"createdBy":{"id":"alice@example.test","name":"Name of alice"},"sessions":0,"session":null}],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"email":null,"access":{"kind":"env","key":"","provider":null,"endpoint":null,"protocol":null,"login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"model":null,"models":["claude-sonnet-5-5"],"env":[],"usedBy":["e2e-080726"],"loginCommand":"","machine":false,"backgroundOnMessage":true,"fast":null,"check":{"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","models":null,"checkedAt":1792593499119,"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口","reason":"no_probabilities","model":null,"provider":null,"models":[]}},"login":null,"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792593499241},"share":null,"workspaces":[]}],"footprint":null,"processes":[],"counts":{"sessions":1,"running":0,"warm":1},"slackUsers":[],"slackTeams":[],"disk":{"freeBytes":31501500416,"totalBytes":245107195904},"logins":[],"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs"},{"id":"google","name":"Google Gemini","group":"labs"},{"id":"xai","name":"xAI","group":"labs"},{"id":"mistral","name":"Mistral","group":"labs"},{"id":"deepseek","name":"DeepSeek","group":"labs"},{"id":"qwen","name":"Qwen","group":"labs"},{"id":"moonshotai","name":"Kimi","group":"labs"},{"id":"zai","name":"Z.ai","group":"labs"},{"id":"minimax","name":"MiniMax","group":"labs"},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs"},{"id":"ant-ling","name":"Ant Ling","group":"labs"},{"id":"jev","name":"Jev","group":"labs"},{"id":"qwen-cn","name":"Qwen (China)","group":"labs"},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs"},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs"},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs"},{"id":"openrouter","name":"OpenRouter","group":"gateways"},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways"},{"id":"opencode","name":"OpenCode Zen","group":"gateways"},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways"},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted"},{"id":"groq","name":"Groq","group":"hosted"},{"id":"together","name":"Together AI","group":"hosted"},{"id":"fireworks","name":"Fireworks","group":"hosted"},{"id":"cerebras","name":"Cerebras","group":"hosted"},{"id":"huggingface","name":"Hugging Face","group":"hosted"},{"id":"nvidia","name":"NVIDIA","group":"hosted"},{"id":"baseten","name":"Baseten","group":"hosted"},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted"},{"id":"ollama","name":"Ollama","group":"local"},{"id":"custom","name":"Custom","group":"local"}],"machineLogins":[],"consoleSignIn":true,"sharing":true,"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792593498619},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.306","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792593498619},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-lockp/apps/e2e-local/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792593498619},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-lockp/apps/e2e-local/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792593498619},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","latest":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-lockp/apps/e2e-local/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792593498619},{"id":"cursor","name":"Cursor","installed":false,"latest":"1.0.40","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792593498619},{"id":"devin","name":"Devin","installed":true,"version":"3000.11.92","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-lockp/apps/e2e-local/ember/station/test/fake/devin，不是用 Devin 的安装脚本装的，需在该机器上手动更新","state":"idle","checkedAt":1792593498619}],"slackApps":[],"agentEnv":[],"drive":{"roots":[],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false},"feedback":true,"feishuRegistrations":[]}},"w":1792593509822.522}
  #|{"step":"until 已更改会话方式","w":1792593509840.035}
  #|{"step":"wait 1455","w":1792593509840.049}
  #|{"in":{"id":18,"delta":[{"path":[0,"overview","connects",0,"mode"],"set":"single-session"},{"path":[0,"overview","connects",0,"modeShort"],"set":"单会话"},{"path":[0,"overview","connects",0,"modeText"],"set":"单会话 · @ 唤醒"},{"path":[0,"overview","disk","freeBytes"],"set":31501500416}]},"w":1792593509855.746}
  #|{"in":{"id":19,"delta":[{"path":["items",0,"connect","mode"],"set":"single-session"},{"path":["items",0,"connect","modeShort"],"set":"单会话"},{"path":["items",0,"connect","modeText"],"set":"单会话 · @ 唤醒"}]},"w":1792593509855.793}
  #|{"step":"now tap icon:more","w":1792593511323.593}
  #|{"step":"now tap icon:more","acted":true,"w":1792593511323.671}
  #|{"step":"wait 1438","w":1792593511342.25}
  #|{"step":"now tap 更换 token","w":1792593512790.4}
  #|{"step":"now tap 更换 token","acted":true,"w":1792593512790.489}
  #|{"out":{"id":24,"call":"slack.tokens.edit","params":{"station":"01M5FEC1A8SXWCJ2CJR4NZWW4A/54e0965173aed663957a02cd87d2b07d8a95702891abadf91e52f5dc52bcd8e5","form":"mbui-tokens-1","input":{"connect":"e2e-080726"}}},"w":1792593512806.304}
  #|{"step":"answered slack.tokens.edit","w":1792593512807.405}
  #|{"in":{"id":24,"ok":{"appToken":"","botToken":"","verified":null,"errors":[],"ready":true}},"w":1792593512822.451}
  #|{"out":{"id":25,"subscribe":{"topic":"slackTokens","station":"01M5FEC1A8SXWCJ2CJR4NZWW4A/54e0965173aed663957a02cd87d2b07d8a95702891abadf91e52f5dc52bcd8e5","form":"mbui-tokens-1"},"keyed":true},"w":1792593512822.922}
  #|{"in":{"id":25,"value":{"appToken":"","botToken":"","verified":null,"errors":[],"ready":true}},"w":1792593512839.098}
  #|{"step":"wait 1339","w":1792593512849.423}
  #|{"step":"now until App-Level Token","w":1792593514324.111}
  #|{"step":"tap xapp-","w":1792593514324.166}
  #|{"step":"tap xapp-","acted":true,"w":1792593514324.243}
  #|{"step":"type xapp-1-madeup-080726","w":1792593514350.112}
  #|{"step":"type xapp-1-madeup-080726","acted":true,"w":1792593514350.192}
  #|{"out":{"id":26,"call":"slack.tokens.edit","params":{"station":"01M5FEC1A8SXWCJ2CJR4NZWW4A/54e0965173aed663957a02cd87d2b07d8a95702891abadf91e52f5dc52bcd8e5","form":"mbui-tokens-1","input":{"appToken":"xapp-1-madeup-080726"}}},"w":1792593514357.148}
  #|{"step":"answered slack.tokens.edit","w":1792593514359.433}
  #|{"in":{"id":26,"ok":{"appToken":"xapp-1-madeup-080726","botToken":"","verified":null,"errors":[],"ready":true}},"w":1792593514372.475}
  #|{"step":"tap xoxb-","w":1792593514390.579}
  #|{"step":"tap xoxb-","acted":true,"w":1792593514390.64}
  #|{"step":"type xoxb-madeup-080726","w":1792593514407.363}
  #|{"step":"type xoxb-madeup-080726","acted":true,"w":1792593514407.409}
  #|{"out":{"id":27,"call":"slack.tokens.edit","params":{"station":"01M5FEC1A8SXWCJ2CJR4NZWW4A/54e0965173aed663957a02cd87d2b07d8a95702891abadf91e52f5dc52bcd8e5","form":"mbui-tokens-1","input":{"botToken":"xoxb-madeup-080726"}}},"w":1792593514423.785}
  #|{"step":"answered slack.tokens.edit","w":1792593514424.668}
  #|{"in":{"id":27,"ok":{"appToken":"xapp-1-madeup-080726","botToken":"xoxb-madeup-080726","verified":null,"errors":[],"ready":true}},"w":1792593514439.142}
  #|{"in":{"id":25,"delta":[{"path":["appToken"],"set":"xapp-1-madeup-080726"},{"path":["botToken"],"set":"xoxb-madeup-080726"}]},"w":1792593514439.242}
  #|{"step":"tap 保存并连接","w":1792593514457.231}
  #|{"step":"tap 保存并连接","acted":true,"w":1792593514457.287}
  #|{"out":{"id":28,"call":"slack.tokens.verify","params":{"station":"01M5FEC1A8SXWCJ2CJR4NZWW4A/54e0965173aed663957a02cd87d2b07d8a95702891abadf91e52f5dc52bcd8e5","form":"mbui-tokens-1"}},"w":1792593514475.891}
  #|{"step":"answered slack.tokens.verify","w":1792593514476.992}
  #|{"in":{"id":21,"value":{"doing":[{"call":"slack.tokens.verify","params":{"station":"01M5FEC1A8SXWCJ2CJR4NZWW4A/54e0965173aed663957a02cd87d2b07d8a95702891abadf91e52f5dc52bcd8e5","form":"mbui-tokens-1"},"since":1792593514476,"stage":"running"}]}},"w":1792593514639.167}
  #|{"in":{"id":28,"ok":false},"w":1792593515455.81}
  #|{"step":"tap 取消","w":1792593515473.903}
  #|{"step":"tap 取消","acted":true,"w":1792593515473.966}
  #|{"out":{"id":29,"call":"slack.tokens.drop","params":{"station":"01M5FEC1A8SXWCJ2CJR4NZWW4A/54e0965173aed663957a02cd87d2b07d8a95702891abadf91e52f5dc52bcd8e5","form":"mbui-tokens-1"}},"w":1792593515489.632}
  #|{"step":"answered slack.tokens.drop","w":1792593515491.052}
  #|{"in":{"id":29,"ok":{"appToken":"","botToken":"","verified":null,"errors":[],"ready":false}},"w":1792593515505.808}
  #|{"in":{"id":25,"value":{"appToken":"","botToken":"","verified":null,"errors":[],"ready":false}},"w":1792593515505.905}
  #|{"in":{"id":21,"value":{"doing":[]}},"w":1792593515505.931}
  #|{"step":"wait 1449","w":1792593515523.918}
  #|{"in":{"id":18,"delta":[{"path":[0,"overview","disk","freeBytes"],"set":31501459456},{"path":[0,"overview","machineLogins"],"append":[{"runtime":"claude","installed":true,"loggedIn":false,"usable":false,"text":"无法读取 Claude Code 的登录信息","offered":false},{"runtime":"codex","installed":true,"loggedIn":false,"usable":false,"text":"Codex 未登录","offered":false}]}]},"w":1792593516355.777}
  #|{"step":"now tap icon:more","w":1792593517107.01}
  #|{"step":"now tap icon:more","acted":true,"w":1792593517107.08}
  #|{"step":"wait 1438","w":1792593517124.473}
  #|{"step":"now tap 删除连接","w":1792593518573.764}
  #|{"step":"now tap 删除连接","acted":true,"w":1792593518573.85}
  #|{"step":"wait 1382","w":1792593518590.339}
  #|{"step":"now until 删除「e2e-080726」","w":1792593519973.698}
  #|{"step":"tap =删除连接","w":1792593519973.764}
  #|{"step":"tap =删除连接","acted":true,"w":1792593519973.827}
  #|{"out":{"id":30,"call":"connect.delete","params":{"station":"01M5FEC1A8SXWCJ2CJR4NZWW4A/54e0965173aed663957a02cd87d2b07d8a95702891abadf91e52f5dc52bcd8e5","id":"e2e-080726"}},"w":1792593519989.553}
  #|{"step":"answered connect.delete","w":1792593519993.659}
  #|{"in":{"id":21,"value":{"doing":[{"call":"connect.delete","params":{"station":"01M5FEC1A8SXWCJ2CJR4NZWW4A/54e0965173aed663957a02cd87d2b07d8a95702891abadf91e52f5dc52bcd8e5","id":"e2e-080726"},"since":1792593519989,"stage":"running"}]}},"w":1792593520055.78}
  #|{"in":{"id":18,"delta":[{"path":[0,"overview","connects"],"set":[]},{"path":[0,"overview","disk","freeBytes"],"set":31501688832},{"path":[0,"overview","profiles",0,"usedBy"],"set":[]}]},"w":1792593520055.807}
  #|{"in":{"id":19,"delta":[{"path":["items"],"set":[]},{"path":["wait","empty"],"set":true}]},"w":1792593520055.836}
  #|{"in":{"id":30,"ok":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null},"canEditPolicy":true},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","sub":"alice","email":"alice@example.test","name":"Name of alice","role":"owner","workspace":"01M5FEC1A8SXWCJ2CJR4NZWW4A","device":"52d0e57782843b8a08448a0cb74446830deae97fbcc5ebb884032d4b3087633c","lockDevice":{"base":"52d0e57782843b8a08448a0cb74446830deae97fbcc5ebb884032d4b3087633c","proof":"eb09a405cb928ec574563b05a0d1b19706214d21e015ad53c23e0c77a3ea4e06cc275b695aa02ada9b2958a560d636edf823de402fc61561df07aab93f17a304"},"home":true},"mesh":{"state":"running","origin":"http://127.0.0.1:18787","station":"54e0965173aed663957a02cd87d2b07d8a95702891abadf91e52f5dc52bcd8e5","workspace":"Dev","workspaceId":"01M5FEC1A8SXWCJ2CJR4NZWW4A","name":"studio"},"connects":[],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"email":null,"access":{"kind":"env","key":"","provider":null,"endpoint":null,"protocol":null,"login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"model":null,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"fast":null,"check":{"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","models":null,"checkedAt":1792593499119,"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口","reason":"no_probabilities","model":null,"provider":null,"models":[]}},"login":null,"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792593499241},"share":null,"workspaces":[]}],"footprint":null,"processes":[],"counts":{"sessions":1,"running":0,"warm":1},"slackUsers":[],"slackTeams":[],"disk":{"freeBytes":31501688832,"totalBytes":245107195904},"logins":[],"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs"},{"id":"google","name":"Google Gemini","group":"labs"},{"id":"xai","name":"xAI","group":"labs"},{"id":"mistral","name":"Mistral","group":"labs"},{"id":"deepseek","name":"DeepSeek","group":"labs"},{"id":"qwen","name":"Qwen","group":"labs"},{"id":"moonshotai","name":"Kimi","group":"labs"},{"id":"zai","name":"Z.ai","group":"labs"},{"id":"minimax","name":"MiniMax","group":"labs"},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs"},{"id":"ant-ling","name":"Ant Ling","group":"labs"},{"id":"jev","name":"Jev","group":"labs"},{"id":"qwen-cn","name":"Qwen (China)","group":"labs"},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs"},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs"},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs"},{"id":"openrouter","name":"OpenRouter","group":"gateways"},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways"},{"id":"opencode","name":"OpenCode Zen","group":"gateways"},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways"},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted"},{"id":"groq","name":"Groq","group":"hosted"},{"id":"together","name":"Together AI","group":"hosted"},{"id":"fireworks","name":"Fireworks","group":"hosted"},{"id":"cerebras","name":"Cerebras","group":"hosted"},{"id":"huggingface","name":"Hugging Face","group":"hosted"},{"id":"nvidia","name":"NVIDIA","group":"hosted"},{"id":"baseten","name":"Baseten","group":"hosted"},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted"},{"id":"ollama","name":"Ollama","group":"local"},{"id":"custom","name":"Custom","group":"local"}],"machineLogins":[{"runtime":"claude","installed":true,"loggedIn":false,"email":null,"plan":null,"usable":false,"quota":null,"text":"无法读取 Claude Code 的登录信息"},{"runtime":"codex","installed":true,"loggedIn":false,"email":null,"plan":null,"usable":false,"quota":null,"text":"Codex 未登录"}],"consoleSignIn":true,"sharing":true,"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792593498619},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.306","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792593498619},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-lockp/apps/e2e-local/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792593498619},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-lockp/apps/e2e-local/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792593498619},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","latest":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-lockp/apps/e2e-local/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792593498619},{"id":"cursor","name":"Cursor","installed":false,"latest":"1.0.40","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792593498619},{"id":"devin","name":"Devin","installed":true,"version":"3000.11.92","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-lockp/apps/e2e-local/ember/station/test/fake/devin，不是用 Devin 的安装脚本装的，需在该机器上手动更新","state":"idle","checkedAt":1792593498619}],"slackApps":[],"agentEnv":[],"drive":{"roots":[],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false},"feedback":true,"feishuRegistrations":[]}},"w":1792593520055.948}
  #|{"step":"until 已删除连接","w":1792593520072.689}
  #|{"step":"hover =连接","w":1792593520072.701}
  #|{"step":"hover =连接","acted":true,"w":1792593520072.716}
  #|{"step":"wait 2600","w":1792593520089.425}
  #|{"in":{"id":21,"value":{"doing":[]}},"w":1792593520239.136}
  #|{"step":"wait 100","w":1792593522806.933}
  #|{"step":"now tap icon:plus","w":1792593522923.308}
  #|{"step":"now tap icon:plus","acted":true,"w":1792593522923.386}
  #|{"out":{"id":31,"subscribe":{"topic":"connectFlow","station":"01M5FEC1A8SXWCJ2CJR4NZWW4A/54e0965173aed663957a02cd87d2b07d8a95702891abadf91e52f5dc52bcd8e5","form":"mbui-connect-1"},"keyed":true},"w":1792593522939.784}
  #|{"out":{"id":32,"call":"connect.flow.open","params":{"station":"01M5FEC1A8SXWCJ2CJR4NZWW4A/54e0965173aed663957a02cd87d2b07d8a95702891abadf91e52f5dc52bcd8e5","form":"mbui-connect-1","input":{"mobile":true,"resume":null}}},"w":1792593522941.493}
  #|{"step":"answered connect.flow.open","w":1792593522941.92}
  #|{"in":{"id":31,"error":{"code":"invalid_params","message":"连接草稿已关闭"}},"w":1792593522955.813}
  #|{"in":{"id":32,"ok":{"step":"platform","platform":null,"feishu":{"way":"scan","appId":"","appSecret":"","lark":false,"canVerify":false,"verified":false,"errors":[],"failed":false,"creating":false,"error":null,"connect":null},"resume":null,"mobile":true,"team":null,"adding":false,"settings":{"name":"still.fail","displayName":"still.fail","description":"Coding agent in your threads (still.fail)","longDescription":"","backgroundColor":"#F3E3D3","groups":{"base":true,"public":true,"dm":true,"customize":true,"files":true,"reactions":true,"channels":true,"people":true,"extras":true,"canvases":true,"lists":true,"topics":true,"usergroups":true,"search":true,"connect":true,"more":true}},"icon":null,"iconError":null,"madeId":null,"config":"","mode":"multi-session","requireMention":true,"platforms":["slack","feishu"],"title":"选择平台","back":"close","number":1,"total":5,"gettingToken":false,"noProfile":false,"configReady":false,"configError":null,"canMake":false,"canCreate":true,"teams":[],"chosen":null,"made":null,"pick":{"fastAvailable":false,"fastText":null,"options":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"runtimes":["claude"],"maker":{"id":"anthropic","name":"Anthropic"},"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"id":"cc","name":"cc","current":false,"spent":null,"efforts":["low","medium","high","xhigh","max"],"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792593499241},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]},"spent":null,"availability":"here"}],"runtimeFixed":false,"value":{"model":"claude-sonnet-5-5","runtime":"claude","effort":null,"fast":null,"profile":null},"valueOption":{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"runtimes":["claude"],"maker":{"id":"anthropic","name":"Anthropic"},"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"id":"cc","name":"cc","current":false,"spent":null,"efforts":["low","medium","high","xhigh","max"],"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792593499241},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]},"spent":null,"availability":"here"},"account":{"text":"自动分配","auto":true,"level":null,"profile":null},"draft":{"model":"claude-sonnet-5-5","runtime":"claude","effort":null,"profile":null,"fast":null},"option":"claude-sonnet-5-5","runtimes":[],"efforts":["low","medium","high","xhigh","max"],"accounts":[{"id":"cc","name":"cc","current":false,"spent":null,"efforts":["low","medium","high","xhigh","max"],"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792593499241},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}],"dropped":null,"who":"账号","whoLevel":null,"autoNote":"额度用完或登录失效时自动切换","changed":false,"was":["Sonnet 5.5","默认深度","自动 · "],"becomes":["Sonnet 5.5","默认深度","自动分配"],"force":null,"modelText":"Sonnet 5.5","maker":{"id":"anthropic","name":"Anthropic"},"accountText":"自动分配","accountNote":"额度用完或登录失效时自动切换","accountWarn":false,"saveText":"无变更","next":{"model":"claude-sonnet-5-5","runtime":"claude","effort":null,"profile":null,"fast":null},"borrow":null}}},"w":1792593522956.065}
  #|{"step":"wait 300","w":1792593522972.757}
  #|{"in":{"id":31,"value":{"step":"platform","title":"选择平台","back":"close","number":1,"total":5,"mobile":true,"adding":false,"settings":{"name":"still.fail","displayName":"still.fail","description":"Coding agent in your threads (still.fail)","longDescription":"","backgroundColor":"#F3E3D3","groups":{"base":true,"public":true,"dm":true,"customize":true,"files":true,"reactions":true,"channels":true,"people":true,"extras":true,"canvases":true,"lists":true,"topics":true,"usergroups":true,"search":true,"connect":true,"more":true}},"config":"","configReady":false,"mode":"multi-session","requireMention":true,"gettingToken":false,"noProfile":false,"canMake":false,"canCreate":true,"teams":[],"pick":{"fastAvailable":false,"options":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792593499241,"time":{"checkedAt":{"at":1792593499241,"ago":"刚刚","full":"10/21 22:38:19","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]},"availability":"here"}],"runtimeFixed":false,"value":{"model":"claude-sonnet-5-5","runtime":"claude"},"valueOption":{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792593499241,"time":{"checkedAt":{"at":1792593499241,"ago":"刚刚","full":"10/21 22:38:19","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]},"availability":"here"},"account":{"text":"自动分配","auto":true},"draft":{"model":"claude-sonnet-5-5","runtime":"claude"},"option":"claude-sonnet-5-5","runtimes":[],"efforts":["low","medium","high","xhigh","max"],"accounts":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792593499241,"time":{"checkedAt":{"at":1792593499241,"ago":"刚刚","full":"10/21 22:38:19","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}],"who":"账号","autoNote":"额度用完或登录失效时自动切换","changed":false,"was":["Sonnet 5.5","默认深度","自动 · "],"becomes":["Sonnet 5.5","默认深度","自动分配"],"modelText":"Sonnet 5.5","maker":{"id":"anthropic","name":"Anthropic"},"accountText":"自动分配","accountNote":"额度用完或登录失效时自动切换","accountWarn":false,"saveText":"无变更"},"platforms":["slack","feishu"],"feishu":{"way":"scan","appId":"","appSecret":"","lark":false,"canVerify":false,"verified":false,"errors":[],"failed":false,"creating":false}}},"w":1792593523055.842}
  #|{"in":{"id":18,"delta":[{"path":[0,"host","checkedAt"],"set":1792593523037},{"path":[0,"host","cpuBusy"],"set":0.2},{"path":[0,"host","details",3,"value"],"set":"进程占用 138 MB"},{"path":[0,"host","disk","freeBytes"],"set":31501672448},{"path":[0,"host","emberRssBytes"],"set":144554240},{"path":[0,"host","emberText"],"set":"still.fail 138 MB"},{"path":[0,"host","load"],"set":0.83},{"path":[0,"host","memory","usedBytes"],"set":8772452352},{"path":[0,"host","meters",0,"big"],"set":"80"},{"path":[0,"host","meters",0,"left"],"set":80},{"path":[0,"host","meters",0,"level"],"set":"ok"},{"path":[0,"host","meters",0,"note"],"set":"负载 8.3 · Apple M4"},{"path":[0,"host","meters",0,"percent"],"set":20},{"path":[0,"host","meters",0,"remaining"],"set":"空闲 80%"},{"path":[0,"host","meters",0,"total"],"set":"负载 8.3"},{"path":[0,"host","meters",0,"value"],"set":"20%"},{"path":[0,"host","meters",1,"big"],"set":"7.8"},{"path":[0,"host","meters",1,"left"],"set":49},{"path":[0,"host","meters",1,"percent"],"set":51},{"path":[0,"host","meters",1,"remaining"],"set":"剩 7.8 G"},{"path":[0,"host","meters",1,"value"],"set":"8.2 GB / 16.0 GB"},{"path":[0,"host","uptimeSec"],"set":72885},{"path":[0,"host","usage"],"set":"内存 8.2 GB / 16.0 GB · 磁盘 剩余 29.3 GB / 228 GB"}]},"w":1792593523172.482}
  #|{"step":"now until 选择平台","w":1792593523373.407}
  #|{"step":"tap =Slack","w":1792593523373.464}
  #|{"step":"tap =Slack","acted":true,"w":1792593523373.51}
  #|{"out":{"id":33,"call":"connect.flow.edit","params":{"station":"01M5FEC1A8SXWCJ2CJR4NZWW4A/54e0965173aed663957a02cd87d2b07d8a95702891abadf91e52f5dc52bcd8e5","form":"mbui-connect-1","input":{"platform":"slack"}}},"w":1792593523389.345}
  #|{"step":"answered connect.flow.edit","w":1792593523389.689}
  #|{"in":{"id":33,"ok":{"step":"platform","platform":"slack","feishu":{"way":"scan","appId":"","appSecret":"","lark":false,"canVerify":false,"verified":false,"errors":[],"failed":false,"creating":false,"error":null,"connect":null},"resume":null,"mobile":true,"team":null,"adding":false,"settings":{"name":"still.fail","displayName":"still.fail","description":"Coding agent in your threads (still.fail)","longDescription":"","backgroundColor":"#F3E3D3","groups":{"base":true,"public":true,"dm":true,"customize":true,"files":true,"reactions":true,"channels":true,"people":true,"extras":true,"canvases":true,"lists":true,"topics":true,"usergroups":true,"search":true,"connect":true,"more":true}},"icon":null,"iconError":null,"madeId":null,"config":"","mode":"multi-session","requireMention":true,"platforms":["slack","feishu"],"title":"选择平台","back":"close","number":1,"total":5,"gettingToken":false,"noProfile":false,"configReady":false,"configError":null,"canMake":false,"canCreate":true,"teams":[],"chosen":null,"made":null,"pick":{"fastAvailable":false,"fastText":null,"options":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"runtimes":["claude"],"maker":{"id":"anthropic","name":"Anthropic"},"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"id":"cc","name":"cc","current":false,"spent":null,"efforts":["low","medium","high","xhigh","max"],"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792593499241},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]},"spent":null,"availability":"here"}],"runtimeFixed":false,"value":{"model":"claude-sonnet-5-5","runtime":"claude","effort":null,"fast":null,"profile":null},"valueOption":{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"runtimes":["claude"],"maker":{"id":"anthropic","name":"Anthropic"},"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"id":"cc","name":"cc","current":false,"spent":null,"efforts":["low","medium","high","xhigh","max"],"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792593499241},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]},"spent":null,"availability":"here"},"account":{"text":"自动分配","auto":true,"level":null,"profile":null},"draft":{"model":"claude-sonnet-5-5","runtime":"claude","effort":null,"profile":null,"fast":null},"option":"claude-sonnet-5-5","runtimes":[],"efforts":["low","medium","high","xhigh","max"],"accounts":[{"id":"cc","name":"cc","current":false,"spent":null,"efforts":["low","medium","high","xhigh","max"],"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792593499241},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}],"dropped":null,"who":"账号","whoLevel":null,"autoNote":"额度用完或登录失效时自动切换","changed":false,"was":["Sonnet 5.5","默认深度","自动 · "],"becomes":["Sonnet 5.5","默认深度","自动分配"],"force":null,"modelText":"Sonnet 5.5","maker":{"id":"anthropic","name":"Anthropic"},"accountText":"自动分配","accountNote":"额度用完或登录失效时自动切换","accountWarn":false,"saveText":"无变更","next":{"model":"claude-sonnet-5-5","runtime":"claude","effort":null,"profile":null,"fast":null},"borrow":null}}},"w":1792593523405.991}
  #|{"step":"tap =下一步","w":1792593523423.315}
  #|{"step":"tap =下一步","acted":true,"w":1792593523423.366}
  #|{"out":{"id":34,"call":"connect.flow.go","params":{"station":"01M5FEC1A8SXWCJ2CJR4NZWW4A/54e0965173aed663957a02cd87d2b07d8a95702891abadf91e52f5dc52bcd8e5","form":"mbui-connect-1","input":{"to":"team"}}},"w":1792593523439.577}
  #|{"step":"answered connect.flow.go","w":1792593523440.037}
  #|{"in":{"id":34,"ok":{}},"w":1792593523455.822}
  #|{"in":{"id":31,"delta":[{"path":["back"],"set":"platform"},{"path":["number"],"set":2},{"path":["platform"],"set":"slack"},{"path":["step"],"set":"team"},{"path":["title"],"set":"选择 Slack 工作区"}]},"w":1792593523455.908}
  #|{"step":"tap 添加配置 token","w":1792593523481.96}
  #|{"step":"tap 添加配置 token","acted":true,"w":1792593523482.008}
  #|{"out":{"id":35,"call":"connect.flow.go","params":{"station":"01M5FEC1A8SXWCJ2CJR4NZWW4A/54e0965173aed663957a02cd87d2b07d8a95702891abadf91e52f5dc52bcd8e5","form":"mbui-connect-1","input":{"to":"token"}}},"w":1792593523489.32}
  #|{"step":"answered connect.flow.go","w":1792593523489.619}
  #|{"in":{"id":35,"ok":{}},"w":1792593523505.806}
  #|{"step":"tap =打开","w":1792593523523.282}
  #|{"in":{"id":31,"delta":[{"path":["back"],"set":"team"},{"path":["number"],"set":1},{"path":["step"],"set":"token"},{"path":["title"],"set":"添加配置 token"}]},"w":1792593523589.165}
  #|{"step":"tap =打开","acted":true,"w":1792593523602.835}
  #|{"step":"","w":1792593523615.383}
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
  #|{"textrec":{"ib":["bef2954d97ce1d9f",6508,64],"r":[40,40,40,40]}}
  #|{"textrec":{"ib":["1d51432b25a425eb",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"ib":["c8ac90bf691295f0",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["31d8ec32aedeae00",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["a7ccae3554fe46cf",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"s":[15,400,0,"搜索全部内容"],"r":[0,1,14.883268482490273,18,1,1,14.883268482490273,19,2,1,14.883268482490273,20,3,1,14.883268482490273,21,4,1,14.88326848249028,22,5,1,14.88326848249028,23]}}
  #|{"textrec":{"m":[15,400,0],"r":[14.501953125,3.1640625,21,14.501953125,3.1640625,0]}}
  #|{"textrec":{"s":[15,600,0,"今天"],"r":[0,1,14.883268482490273,24,1,1,14.883268482490273,25]}}
  #|{"textrec":{"m":[15,600,0],"r":[14.501953125,3.1640625,21,14.501953125,3.1640625,0]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 post:你好，我是测试用的 agent"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,26,3,1,15.875486381322958,28,4,1,15.875486381322958,29,5,1,15.875486381322958,30,6,1,15.875486381322958,31,7,1,15.875486381322958,32,8,1,3.95001220703125,-1,9,1,9.824199676513672,33,10,1,9.432537078857422,34,11,1,8.471200942993164,35,12,1,5.973020553588867,36,13,1,4.952056884765625,37,14,1,15.875486381322958,38,15,1,15.875486381322958,39,16,1,16.09338521400778,40,17,1,15.875486381322958,41,18,1,15.875486381322958,42,19,1,15.87548638132293,28,20,1,15.875486381322958,29,21,1,15.875486381322958,43,22,1,15.875486381322958,30,23,1,3.95001220703125,-1,24,1,8.899068832397461,44,25,1,9.801153182983398,45,26,1,9.127458572387695,46,27,1,9.466253280639648,47,28,1,5.999713897705078,36]}}
  #|{"textrec":{"m":[16,600,0],"r":[15.46875,3.375,23,15.46875,3.375,0]}}
  #|{"textrec":{"s":[14,400,0,"你好，我是测试用的 agent"],"r":[0,1,13.891050583657588,48,1,1,13.891050583657588,49,2,1,14.081712062256813,50,3,1,13.891050583657588,51,4,1,13.891050583657588,52,5,1,13.891050583657588,53,6,1,13.891050583657588,54,7,1,13.891050583657588,55,8,1,13.891050583657588,56,9,1,3.787109375000014,-1,10,1,7.57421875,57,11,1,8.380859375,58,12,1,7.84765625,59,13,1,8.0185546875,60,14,1,4.935546875,61]}}
  #|{"textrec":{"m":[14,400,0],"r":[13.53515625,2.953125,20,13.53515625,2.953125,0]}}
  #|{"textrec":{"s":[16,600,0,"…"],"r":[0,1,14.076484680175781,62]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 post:你好，我是测试用的…"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,26,3,1,15.875486381322958,28,4,1,15.875486381322958,29,5,1,15.875486381322958,30,6,1,15.875486381322958,31,7,1,15.875486381322958,32,8,1,3.95001220703125,-1,9,1,9.824199676513672,33,10,1,9.432537078857422,34,11,1,8.471200942993164,35,12,1,5.973020553588867,36,13,1,4.952056884765625,37,14,1,15.875486381322958,38,15,1,15.875486381322958,39,16,1,16.09338521400778,40,17,1,15.875486381322958,41,18,1,15.875486381322958,42,19,1,15.87548638132293,28,20,1,15.875486381322958,29,21,1,15.875486381322958,43,22,1,15.875486381322958,30,23,1,14.076484680175781,62]}}
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
  #|{"textrec":{"g":33,"r":[317,0,11,14,0,-10,0]}}
  #|{"textrec":{"g":34,"r":[329,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":35,"r":[341,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":36,"r":[353,0,8,14,-1,-12,0]}}
  #|{"textrec":{"g":37,"r":[362,0,5,12,0,-10,0]}}
  #|{"textrec":{"g":38,"r":[368,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":39,"r":[386,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":40,"r":[404,0,6,8,0,-4,0]}}
  #|{"textrec":{"g":41,"r":[411,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":42,"r":[430,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":43,"r":[448,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":62,"r":[465,0,14,6,0,-4,0]}}
  #|{"textrec":{"g":48,"r":[480,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":49,"r":[496,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":50,"r":[513,0,5,7,0,-3,0]}}
  #|{"textrec":{"g":51,"r":[519,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":52,"r":[536,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":53,"r":[552,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":54,"r":[568,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":55,"r":[585,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":56,"r":[601,0,14,16,0,-13,0]}}
  #|{"textrec":{"g":57,"r":[616,0,9,11,-1,-9,0]}}
  #|{"textrec":{"g":58,"r":[626,0,10,13,-1,-9,0]}}
  #|{"textrec":{"g":59,"r":[637,0,10,11,-1,-9,0]}}
  #|{"textrec":{"g":60,"r":[648,0,9,10,0,-9,0]}}
  #|{"textrec":{"g":61,"r":[658,0,7,13,-1,-11,0]}}
  #|{"textrec":{"ib":["33d1dfbf90932d3b",1241,64],"r":[17,17,17,17]}}
  #|{"textrec":{"ib":["182b7158e0c0cae1",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["d61ec6305f7d8c8b",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["8bf9607b651cec61",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"s":[17,400,0,"会话"],"r":[0,1,16.851167315175097,63,1,1,16.851167315175097,64]}}
  #|{"textrec":{"m":[17,400,0],"r":[16.435546875,3.5859375,24,16.435546875,3.5859375,0]}}
  #|{"textrec":{"s":[32,700,8,"设置"],"r":[0,1,30.345864661654133,65,1,1,30.345864661654133,66]}}
  #|{"textrec":{"m":[32,700,0],"r":[30.9375,6.75,45,27.5185546875,4.4814453125,0]}}
  #|{"textrec":{"s":[16,700,0,"Name of alice"],"r":[0,1,11.9765625,67,1,1,9.12109375,68,2,1,14.6015625,69,3,1,9.30078125,70,4,1,3.8125,-1,5,1,9.6015625,71,6,1,6.21484375,72,7,1,3.8125,-1,8,1,9.12109375,68,9,1,4.40625,73,10,1,4.28125,74,11,1,9.0859375,75,12,1,9.30078125,70]}}
  #|{"textrec":{"m":[16,700,0],"r":[15.46875,3.375,23,15.46875,3.375,0]}}
  #|{"textrec":{"s":[13,400,0,"alice@example.test"],"r":[0,1,7.0966796875,12,1,1,3.2119140625,76,2,1,3.1357421875,77,3,1,7.1982421875,13,4,1,7.3505859375,14,5,1,11.857421875,78,6,1,7.2236328125,14,7,1,6.6142578125,79,8,1,7.0966796875,12,9,1,11.2353515625,80,10,1,7.8583984375,11,11,1,3.2119140625,76,12,1,7.3505859375,14,13,1,3.65625,81,14,1,4.471923828125,82,15,1,7.302978515625,14,16,1,6.69677734375,10,17,1,4.61474609375,82]}}
  #|{"textrec":{"s":[23,600,0,"N"],"r":[0,1,16.576080499507952,83]}}
  #|{"textrec":{"m":[23,600,0],"r":[22.236328125,4.8515625,33,19.778961181640625,3.221038818359375,0]}}
  #|{"textrec":{"s":[15,600,0,"Dev"],"r":[0,1,10.861195921897888,84,1,1,8.51915180683136,85,2,1,8.18638265132904,86]}}
  #|{"textrec":{"s":[15,400,0,"Workspace"],"r":[0,1,13.916015625,87,1,1,8.26171875,88,2,1,5.478515625,89,3,1,7.763671875,90,4,1,7.470703125,91,5,1,8.9208984375,92,6,1,8.0419921875,93,7,1,8.1591796875,94,8,1,8.3349609375,95]}}
  #|{"textrec":{"s":[14,400,0,"未开启"],"r":[0,1,13.891050583657588,96,1,1,13.891050583657588,97,2,1,13.891050583657588,98]}}
  #|{"textrec":{"s":[15,400,0,"安全"],"r":[0,1,14.883268482490273,99,1,1,14.883268482490273,20]}}
  #|{"textrec":{"s":[15,400,0,"Station"],"r":[0,1,9.32373046875,100,1,1,5.21484375,101,2,1,8.0419921875,93,3,1,5.21484375,101,4,1,3.4716796875,102,5,1,8.6279296875,88,6,1,8.51806640625,103]}}
  #|{"textrec":{"s":[15,400,0,"连接"],"r":[0,1,14.883268482490273,104,1,1,14.883268482490273,105]}}
  #|{"textrec":{"s":[15,400,0,"Profile"],"r":[0,1,9.29443359375,106,1,1,5.36865234375,89,2,1,8.51806640625,88,3,1,5.19287109375,107,4,1,3.4716796875,102,5,1,3.5595703125,108,6,1,8.3349609375,95]}}
  #|{"textrec":{"s":[15,400,0,"自动决策"],"r":[0,1,14.883268482490273,109,1,1,14.883268482490273,110,2,1,14.883268482490273,111,3,1,14.883268482490273,112]}}
  #|{"textrec":{"s":[15,400,0,"记忆"],"r":[0,1,14.883268482490273,113,1,1,14.883268482490273,114]}}
  #|{"textrec":{"s":[15,400,0,"用量"],"r":[0,1,14.883268482490273,115,1,1,14.883268482490273,116]}}
  #|{"textrec":{"s":[15,600,0,"此设备"],"r":[0,1,14.883268482490273,117,1,1,14.883268482490273,118,2,1,14.883268482490273,119]}}
  #|{"textrec":{"s":[14,400,0,"跟随系统"],"r":[0,1,13.891050583657588,120,1,1,13.891050583657588,121,2,1,13.891050583657588,122,3,1,13.891050583657588,123]}}
  #|{"textrec":{"s":[15,400,0,"外观"],"r":[0,1,14.883268482490273,124,1,1,14.883268482490273,125]}}
  #|{"textrec":{"s":[14,400,0,"2 栏"],"r":[0,1,8.298828125,126,1,1,3.787109375,-1,2,1,13.891050583657588,127]}}
  #|{"textrec":{"s":[15,400,0,"下方栏"],"r":[0,1,14.883268482490273,128,1,1,14.883268482490273,129,2,1,14.883268482490273,130]}}
  #|{"textrec":{"s":[15,400,0,"本机缓存"],"r":[0,1,14.883268482490273,131,1,1,14.883268482490273,132,2,1,14.883268482490273,133,3,1,14.883268482490273,134]}}
  #|{"textrec":{"s":[15,400,0,"通知"],"r":[0,1,14.883268482490273,135,1,1,14.883268482490273,136]}}
  #|{"textrec":{"s":[13,400,0,"任务完成、需要处理、出错或有新消息时通知你"],"r":[0,1,12.898832684824903,137,1,1,12.898832684824903,138,2,1,12.898832684824903,139,3,1,12.898832684824903,140,4,1,13.075875486381321,141,5,1,12.89883268482491,142,6,1,12.898832684824896,143,7,1,12.898832684824896,144,8,1,12.898832684824896,145,9,1,13.075875486381335,141,10,1,12.898832684824896,146,11,1,12.898832684824896,147,12,1,12.898832684824896,148,13,1,12.898832684824896,149,14,1,12.898832684824896,150,15,1,12.898832684824896,151,16,1,12.898832684824896,152,17,1,12.898832684824896,153,18,1,12.898832684824896,154,19,1,12.898832684824924,155,20,1,12.898832684824924,4]}}
  #|{"textrec":{"s":[15,400,0,"检查更新"],"r":[0,1,14.883268482490273,156,1,1,14.883268482490273,157,2,1,14.883268482490273,158,3,1,14.883268482490273,159]}}
  #|{"textrec":{"s":[15,400,0,"still.fail mbui 0.1"],"r":[0,1,7.58056640625,91,1,1,5.17822265625,101,2,1,3.4716796875,102,3,1,3.5595703125,108,4,1,3.5595703125,108,5,1,3.9990234375,160,6,1,4.86328125,107,7,1,7.93212890625,93,8,1,3.4716796875,102,9,1,3.5595703125,108,10,1,3.984375,-1,11,1,12.8173828125,161,12,1,8.9794921875,162,13,1,8.51806640625,163,14,1,3.4716796875,102,15,1,3.984375,-1,16,1,8.9208984375,164,17,1,3.7060546875,160,18,1,6.50390625,165]}}
  #|{"textrec":{"s":[15,400,0,"更新日志"],"r":[0,1,14.883268482490273,158,1,1,14.883268482490273,159,2,1,14.883268482490273,166,3,1,14.883268482490273,167]}}
  #|{"textrec":{"s":[15,400,0,"服务条款"],"r":[0,1,14.883268482490273,168,1,1,14.883268482490273,169,2,1,14.883268482490273,170,3,1,14.883268482490273,171]}}
  #|{"textrec":{"s":[15,400,0,"隐私政策"],"r":[0,1,14.883268482490273,172,1,1,14.883268482490273,173,2,1,14.883268482490273,174,3,1,14.883268482490273,112]}}
  #|{"textrec":{"s":[15,600,0,"Dev · 你是Owner"],"r":[0,1,10.861195921897888,84,1,1,8.51915180683136,85,2,1,8.18638265132904,86,3,1,3.761730194091797,-1,4,1,7.186782927948599,175,5,1,3.761730194091797,-1,6,1,14.883268482490273,176,7,1,14.883268482490273,177,8,1,13.354362845420837,178,9,1,12.072962522506714,179,10,1,8.93320620059967,180,11,1,8.615586161613464,85,12,1,5.99338173866272,181]}}
  #|{"textrec":{"s":[14,400,0,"1 人"],"r":[0,1,6.34375,182,1,1,3.787109375,-1,2,1,13.891050583657588,183]}}
  #|{"textrec":{"s":[14,400,0,"0 条"],"r":[0,1,8.66796875,184,1,1,3.787109375,-1,2,1,13.891050583657588,185]}}
  #|{"textrec":{"s":[15,400,0,"密钥"],"r":[0,1,14.883268482490273,186,1,1,14.883268482490273,187]}}
  #|{"textrec":{"s":[14,400,0,"1/1 在线"],"r":[0,1,6.34375,182,1,1,4.115234375,188,2,1,6.34375,182,3,1,3.787109375,-1,4,1,13.891050583657588,189,5,1,13.891050583657588,190]}}
  #|{"textrec":{"s":[14,400,0,"1 个"],"r":[0,1,6.34375,182,1,1,3.787109375,-1,2,1,13.891050583657588,191]}}
  #|{"textrec":{"ib":["504a4df6beac534a",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["a1e7be43eb966606",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"g":65,"r":[666,0,31,31,0,-26,0]}}
  #|{"textrec":{"g":66,"r":[698,0,30,29,0,-25,0]}}
  #|{"textrec":{"g":84,"r":[729,0,12,13,0,-12,0]}}
  #|{"textrec":{"g":85,"r":[742,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":86,"r":[754,0,11,11,-1,-10,0]}}
  #|{"textrec":{"g":175,"r":[766,0,5,5,1,-8,0]}}
  #|{"textrec":{"g":176,"r":[772,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":177,"r":[789,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":178,"r":[806,0,13,14,-1,-12,0]}}
  #|{"textrec":{"g":179,"r":[820,0,14,11,-1,-10,0]}}
  #|{"textrec":{"g":180,"r":[835,0,10,11,0,-10,0]}}
  #|{"textrec":{"g":181,"r":[846,0,7,11,0,-10,0]}}
  #|{"textrec":{"g":117,"r":[854,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":118,"r":[872,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":119,"r":[890,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":63,"r":[908,0,18,18,-1,-15,0]}}
  #|{"textrec":{"g":64,"r":[927,0,19,18,-1,-15,0]}}
  #|{"textrec":{"g":83,"r":[947,0,17,19,0,-18,0]}}
  #|{"textrec":{"g":67,"r":[965,0,12,14,0,-13,0]}}
  #|{"textrec":{"g":68,"r":[978,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":69,"r":[990,0,15,11,0,-10,0]}}
  #|{"textrec":{"g":70,"r":[1006,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":71,"r":[1018,0,12,12,-1,-10,0]}}
  #|{"textrec":{"g":72,"r":[1031,0,8,14,-1,-13,0]}}
  #|{"textrec":{"g":73,"r":[1040,0,5,14,0,-13,0]}}
  #|{"textrec":{"g":74,"r":[1046,0,5,15,0,-14,0]}}
  #|{"textrec":{"g":75,"r":[1052,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":12,"r":[1064,0,9,10,-1,-8,0]}}
  #|{"textrec":{"g":76,"r":[1074,0,4,12,0,-11,0]}}
  #|{"textrec":{"g":77,"r":[1079,0,5,12,-1,-11,0]}}
  #|{"textrec":{"g":13,"r":[1085,0,9,10,-1,-8,0]}}
  #|{"textrec":{"g":14,"r":[1095,0,9,10,-1,-8,0]}}
  #|{"textrec":{"g":78,"r":[1105,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":79,"r":[1120,0,9,9,-1,-8,0]}}
  #|{"textrec":{"g":80,"r":[1130,0,12,9,0,-8,0]}}
  #|{"textrec":{"g":11,"r":[1143,0,9,12,0,-8,0]}}
  #|{"textrec":{"g":81,"r":[1153,0,4,5,0,-3,0]}}
  #|{"textrec":{"g":82,"r":[1158,0,7,12,-1,-10,0]}}
  #|{"textrec":{"g":10,"r":[1166,0,9,10,-1,-8,0]}}
  #|{"textrec":{"g":87,"r":[1176,0,16,13,-1,-12,0]}}
  #|{"textrec":{"g":88,"r":[1193,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":89,"r":[1205,0,7,11,0,-10,0]}}
  #|{"textrec":{"g":90,"r":[1213,0,9,14,0,-13,0]}}
  #|{"textrec":{"g":91,"r":[1223,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":92,"r":[1234,0,10,14,0,-10,0]}}
  #|{"textrec":{"g":93,"r":[1245,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":94,"r":[1256,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":95,"r":[1267,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":99,"r":[1278,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":186,"r":[1295,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":187,"r":[1312,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":100,"r":[1329,0,11,14,-1,-12,0]}}
  #|{"textrec":{"g":101,"r":[1341,0,7,13,-1,-11,0]}}
  #|{"textrec":{"g":102,"r":[1349,0,5,14,-1,-13,0]}}
  #|{"textrec":{"g":103,"r":[1355,0,9,11,0,-10,0]}}
  #|{"textrec":{"g":104,"r":[1365,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":105,"r":[1382,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":106,"r":[1399,0,10,13,0,-12,0]}}
  #|{"textrec":{"g":107,"r":[1410,0,7,14,-1,-13,0]}}
  #|{"textrec":{"g":108,"r":[1418,0,4,14,0,-13,0]}}
  #|{"textrec":{"g":109,"r":[1423,0,13,16,1,-13,0]}}
  #|{"textrec":{"g":110,"r":[1437,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":111,"r":[1454,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":112,"r":[1472,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":113,"r":[1489,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":114,"r":[1507,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":115,"r":[1524,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":116,"r":[1540,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":124,"r":[1557,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":125,"r":[1575,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":128,"r":[1593,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":129,"r":[1610,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":130,"r":[1627,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":131,"r":[1644,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":132,"r":[1662,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":133,"r":[1680,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":134,"r":[1698,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":96,"r":[1715,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":97,"r":[1731,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":98,"r":[1747,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":182,"r":[1763,0,7,12,-1,-11,0]}}
  #|{"textrec":{"g":188,"r":[1771,0,7,16,-1,-12,0]}}
  #|{"textrec":{"g":189,"r":[1779,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":190,"r":[1795,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":120,"r":[1812,0,16,15,-1,-12,0]}}
  #|{"textrec":{"g":121,"r":[1829,0,15,16,0,-13,0]}}
  #|{"textrec":{"g":122,"r":[1845,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":123,"r":[1861,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":183,"r":[1878,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":184,"r":[1895,0,10,14,-1,-12,0]}}
  #|{"textrec":{"g":185,"r":[1906,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":191,"r":[1923,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":126,"r":[1940,0,9,13,0,-12,0]}}
  #|{"textrec":{"g":127,"r":[1950,0,16,16,-1,-13,0]}}
  #|{"textrec":{"ib":["b3685975cd23abc3",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"s":[16,600,0,"连接"],"r":[0,1,15.875486381322958,192,1,1,15.875486381322958,193]}}
  #|{"textrec":{"s":[17,400,0,"设置"],"r":[0,1,16.851167315175097,194,1,1,16.851167315175097,195]}}
  #|{"textrec":{"s":[15,600,0,"studio"],"r":[0,1,8.000344634056091,196,1,1,5.658300518989563,197,2,1,8.93320620059967,198,3,1,9.332013130187988,199,4,1,3.8520312309265137,200,5,1,8.901597261428833,201]}}
  #|{"textrec":{"s":[12,400,0,"未连接 Slack"],"r":[0,1,11.918287937743191,202,1,1,11.918287937743191,203,2,1,11.918287937743195,204,3,1,3.375,-1,4,1,7.646484375,205,5,1,3.03515625,206,6,1,6.62109375,207,7,1,6.71484375,208,8,1,6.515625,209]}}
  #|{"textrec":{"m":[12,400,0],"r":[11.6015625,2.53125,17,11.6015625,2.53125,0]}}
  #|{"textrec":{"s":[15,400,0,"e2e-080726"],"r":[0,1,8.3349609375,95,1,1,8.78173828125,210,2,1,8.29833984375,95,3,1,6.8408203125,211,4,1,9.2138671875,164,5,1,9.345703125,212,6,1,9.0673828125,164,7,1,8.1591796875,213,8,1,8.818359375,210,9,1,9.31640625,214]}}
  #|{"textrec":{"s":[13,400,0,"多会话 · Claude Code · Sonnet 5.5"],"r":[0,1,12.898832684824903,215,1,1,12.898832684824903,216,2,1,12.898832684824903,217,3,1,3.580078125,-1,4,1,6.228545204222122,218,5,1,3.580078125,-1,6,1,9.2294921875,219,7,1,3.2119140625,76,8,1,7.0966796875,12,9,1,7.50927734375,220,10,1,7.9091796875,221,11,1,7.3505859375,14,12,1,3.580078125,-1,13,1,9.2294921875,219,14,1,7.6044921875,7,15,1,7.9091796875,221,16,1,7.3505859375,14,17,1,3.580078125,-1,18,1,6.228545204222115,218,19,1,3.580078125,-1,20,1,8.20751953125,222,21,1,7.6044921875,7,22,1,7.50927734375,223,23,1,7.50927734375,223,24,1,7.3505859375,14,25,1,4.646484375,82,26,1,3.580078125,-1,27,1,7.73779296875,224,28,1,3.354736328125,81,29,1,7.753662109375,224]}}
  #|{"textrec":{"s":[13,400,0,"…"],"r":[0,1,10.384765625,225]}}
  #|{"textrec":{"s":[13,400,0,"多会话 · Claude Code · Sonn…"],"r":[0,1,12.898832684824903,215,1,1,12.898832684824903,216,2,1,12.898832684824903,217,3,1,3.580078125,-1,4,1,6.228545204222122,218,5,1,3.580078125,-1,6,1,9.2294921875,219,7,1,3.2119140625,76,8,1,7.0966796875,12,9,1,7.50927734375,220,10,1,7.9091796875,221,11,1,7.3505859375,14,12,1,3.580078125,-1,13,1,9.2294921875,219,14,1,7.6044921875,7,15,1,7.9091796875,221,16,1,7.3505859375,14,17,1,3.580078125,-1,18,1,6.228545204222115,218,19,1,3.580078125,-1,20,1,8.20751953125,222,21,1,7.6044921875,7,22,1,7.50927734375,223,23,1,7.50927734375,223,24,1,10.384765625,225]}}
  #|{"textrec":{"g":194,"r":[1967,0,19,18,-1,-15,0]}}
  #|{"textrec":{"g":195,"r":[1987,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":196,"r":[2006,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":197,"r":[2017,0,8,13,-1,-11,0]}}
  #|{"textrec":{"g":198,"r":[2026,0,10,12,0,-10,0]}}
  #|{"textrec":{"g":199,"r":[0,32,11,15,-1,-13,0]}}
  #|{"textrec":{"g":200,"r":[12,32,6,14,-1,-13,0]}}
  #|{"textrec":{"g":201,"r":[19,32,11,12,-1,-10,0]}}
  #|{"textrec":{"ib":["ae2e80af250a0610",1241,64],"r":[17,17,17,17]}}
  #|{"textrec":{"g":210,"r":[31,32,10,13,0,-12,0]}}
  #|{"textrec":{"g":211,"r":[42,32,7,4,0,-6,0]}}
  #|{"textrec":{"g":164,"r":[50,32,11,14,-1,-12,0]}}
  #|{"textrec":{"g":212,"r":[62,32,11,14,-1,-12,0]}}
  #|{"textrec":{"g":213,"r":[74,32,10,13,-1,-12,0]}}
  #|{"textrec":{"g":214,"r":[85,32,11,14,-1,-12,0]}}
  #|{"textrec":{"g":215,"r":[97,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":216,"r":[111,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":217,"r":[127,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":218,"r":[143,32,4,5,1,-7,0]}}
  #|{"textrec":{"g":219,"r":[148,32,11,13,-1,-11,0]}}
  #|{"textrec":{"g":220,"r":[160,32,9,10,-1,-8,0]}}
  #|{"textrec":{"g":221,"r":[170,32,9,13,-1,-11,0]}}
  #|{"textrec":{"g":7,"r":[180,32,9,10,-1,-8,0]}}
  #|{"textrec":{"g":222,"r":[190,32,10,13,-1,-11,0]}}
  #|{"textrec":{"g":223,"r":[201,32,8,9,0,-8,0]}}
  #|{"textrec":{"g":225,"r":[210,32,11,5,0,-3,0]}}
  #|{"textrec":{"g":192,"r":[222,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":193,"r":[240,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":202,"r":[258,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":203,"r":[273,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":204,"r":[288,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":205,"r":[303,32,9,12,-1,-10,0]}}
  #|{"textrec":{"g":206,"r":[313,32,4,11,0,-10,0]}}
  #|{"textrec":{"g":207,"r":[318,32,8,10,-1,-8,0]}}
  #|{"textrec":{"g":208,"r":[327,32,9,10,-1,-8,0]}}
  #|{"textrec":{"g":209,"r":[337,32,8,11,0,-10,0]}}
  #|{"textrec":{"ib":["2bb63fc1d380f765",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"s":[11,400,0,"未连接 Slack"],"r":[0,1,10.93579766536965,226,1,1,10.93579766536965,227,2,1,10.935797665369652,228,3,1,3.158203125,-1,4,1,7.07373046875,229,5,1,2.8466796875,230,6,1,6.1337890625,231,7,1,6.2197265625,232,8,1,6.037109374999993,233]}}
  #|{"textrec":{"m":[11,400,0],"r":[10.634765625,2.3203125,16,10.634765625,2.3203125,0]}}
  #|{"textrec":{"s":[16,600,0,"e2e-080726"],"r":[0,1,9.127458572387695,46,1,1,9.717817306518555,234,2,1,9.100765228271484,46,3,1,7.363014221191406,235,4,1,10.31976318359375,236,5,1,10.440597534179688,237,6,1,10.138774871826172,236,7,1,8.996856689453125,238,8,1,9.744510650634766,234,9,1,10.3499755859375,239]}}
  #|{"textrec":{"s":[17,400,0,"连接"],"r":[0,1,16.851167315175097,240,1,1,16.851167315175097,241]}}
  #|{"textrec":{"s":[15,400,0,"Slack"],"r":[0,1,9.32373046875,100,1,1,3.5595703125,108,2,1,8.0419921875,93,3,1,8.1591796875,94,4,1,7.91015625,90]}}
  #|{"textrec":{"s":[13,400,0,"studio · 所属 你"],"r":[0,1,6.69677734375,10,1,1,4.61474609375,82,2,1,7.50927734375,220,3,1,7.9091796875,221,4,1,3.1357421875,77,5,1,7.6044921875,7,6,1,3.580078125,-1,7,1,6.228545204222122,218,8,1,3.580078125,-1,9,1,12.898832684824903,242,10,1,12.89883268482491,243,11,1,3.580078125,-1,12,1,12.898832684824896,4]}}
  #|{"textrec":{"s":[13,400,0,"此连接尚未接入 Slack。"],"r":[0,1,12.898832684824903,244,1,1,12.898832684824903,245,2,1,12.898832684824903,246,3,1,12.898832684824903,247,4,1,12.898832684824896,248,5,1,12.898832684824896,246,6,1,12.898832684824896,249,7,1,3.580078125,-1,8,1,8.20751953125,222,9,1,3.2119140625,76,10,1,7.0966796875,12,11,1,7.1982421875,13,12,1,6.982421875,9,13,1,6.575875486381335,250]}}
  #|{"textrec":{"s":[13,400,0,"填写 token"],"r":[0,1,12.898832684824903,251,1,1,12.898832684824903,252,2,1,3.580078125,-1,3,1,4.598876953125,82,4,1,7.556884765625,7,5,1,6.82373046875,9,6,1,7.19189453125,14,7,1,7.50927734375,223]}}
  #|{"textrec":{"s":[15,600,0,"运行方式"],"r":[0,1,14.883268482490273,253,1,1,14.883268482490273,254,2,1,14.883268482490273,255,3,1,14.883268482490273,256]}}
  #|{"textrec":{"s":[13,400,0,"模型"],"r":[0,1,12.898832684824903,257,1,1,12.898832684824903,258]}}
  #|{"textrec":{"s":[15,400,0,"Sonnet 5.5 · 默认深度 · 自动分配"],"r":[0,1,9.32373046875,100,1,1,8.6279296875,88,2,1,8.51806640625,103,3,1,8.51806640625,103,4,1,8.3349609375,95,5,1,5.21484375,101,6,1,3.984375,-1,7,1,8.78173828125,259,8,1,3.724365234375,160,9,1,8.800048828125,259,10,1,3.984375,-1,11,1,7.186782927948599,260,12,1,3.984375,-1,13,1,14.88326848249028,261,14,1,14.88326848249028,262,15,1,14.88326848249028,263,16,1,14.88326848249028,264,17,1,3.984375,-1,18,1,7.186782927948599,260,19,1,3.984375,-1,20,1,14.88326848249028,109,21,1,14.88326848249028,110,22,1,14.88326848249028,265,23,1,14.88326848249028,266]}}
  #|{"textrec":{"s":[13,400,0,"会话"],"r":[0,1,12.898832684824903,216,1,1,12.898832684824903,217]}}
  #|{"textrec":{"s":[15,400,0,"每个 thread 一个会话"],"r":[0,1,14.883268482490273,267,1,1,14.883268482490273,268,2,1,3.984375,-1,3,1,5.21484375,101,4,1,8.59130859375,269,5,1,5.36865234375,89,6,1,8.22509765625,95,7,1,8.0419921875,93,8,1,8.9794921875,270,9,1,3.984375,-1,10,1,14.883268482490266,271,11,1,14.88326848249028,268,12,1,14.88326848249028,272,13,1,14.88326848249028,273]}}
  #|{"textrec":{"s":[13,400,0,"在 thread 中 @ 它即开启一个新会话，该 thread 的后续消息都进入此会话"],"r":[0,1,12.898832684824903,1,1,1,3.580078125,-1,2,1,4.646484375,82,3,1,7.57275390625,274,4,1,4.77978515625,8,5,1,7.25537109375,14,6,1,7.0966796875,12,7,1,7.9091796875,221,8,1,3.580078125,-1,9,1,12.898832684824903,275,10,1,3.580078125,-1,11,1,11.857421875,78,12,1,3.580078125,-1,13,1,12.89883268482491,276,14,1,12.898832684824896,277,15,1,12.898832684824896,278,16,1,12.898832684824896,279,17,1,12.898832684824896,280,18,1,12.898832684824896,281,19,1,12.898832684824896,150,20,1,12.898832684824896,216,21,1,12.898832684824896,217,22,1,13.075875486381335,282,23,1,12.898832684824896,283,24,1,3.580078125,-1,25,1,4.646484375,82,26,1,7.57275390625,274,27,1,4.77978515625,8,28,1,7.255371093750028,14,29,1,7.0966796875,12,30,1,7.9091796875,221,31,1,3.580078125,-1,32,1,12.898832684824924,5,33,1,12.898832684824924,284,34,1,12.898832684824924,285,35,1,12.898832684824924,151,36,1,12.898832684824924,152,37,1,12.898832684824924,286,38,1,12.898832684824924,287,39,1,12.898832684824924,249,40,1,12.898832684824924,244,41,1,12.898832684824924,216,42,1,12.898832684824924,217]}}
  #|{"textrec":{"s":[13,400,0,"运行于 Claude Code，创建后无法更改；如需使用其他运行时，请新建连接。进行中的会话继续使用开始时的设置。"],"r":[0,1,12.898832684824903,288,1,1,12.898832684824903,289,2,1,12.898832684824903,290,3,1,3.580078125,-1,4,1,9.2294921875,219,5,1,3.2119140625,76,6,1,7.0966796875,12,7,1,7.509277343750007,220,8,1,7.9091796875,221,9,1,7.3505859375,14,10,1,3.580078125,-1,11,1,9.2294921875,219,12,1,7.6044921875,7,13,1,7.9091796875,221,14,1,7.3505859375,14,15,1,13.075875486381335,282,16,1,12.898832684824896,291,17,1,12.898832684824896,292,18,1,12.898832684824896,284,19,1,12.898832684824896,293,20,1,12.898832684824896,294,21,1,12.898832684824896,295,22,1,12.898832684824896,296,23,1,13.075875486381335,297,24,1,12.898832684824896,298,25,1,12.898832684824924,142,26,1,12.898832684824924,299,27,1,12.898832684824924,300,28,1,12.898832684824924,301,29,1,12.898832684824924,302,30,1,12.898832684824924,288,31,1,12.898832684824924,289,32,1,12.898832684824924,153,33,1,13.075875486381335,282,34,1,12.898832684824924,303,35,1,12.898832684824924,150,36,1,12.898832684824924,292,37,1,12.898832684824924,245,38,1,12.898832684824924,246,39,1,13.075875486381335,250,40,1,12.898832684824924,287,41,1,12.898832684824924,289,42,1,12.898832684824924,275,43,1,12.898832684824924,5,44,1,12.898832684824924,216,45,1,12.898832684824868,217,46,1,12.898832684824924,304,47,1,12.898832684824924,285,48,1,12.898832684824924,299,49,1,12.898832684824924,300,50,1,12.898832684824924,278,51,1,12.898832684824924,305,52,1,12.898832684824924,153,53,1,12.898832684824924,5,54,1,12.898832684824924,306,55,1,12.898832684824924,307,56,1,6.575875486381278,250]}}
  #|{"textrec":{"s":[15,600,0,"Slack app"],"r":[0,1,9.68320906162262,308,1,1,3.9584755897521973,309,2,1,8.40147078037262,310,3,1,8.423570394515991,311,4,1,8.464449048042297,312,5,1,3.761730194091797,-1,6,1,8.40147078037262,310,7,1,9.268780946731567,313,8,1,9.268780946731567,313]}}
  #|{"textrec":{"s":[15,400,0,"名字、头像和权限"],"r":[0,1,14.883268482490273,314,1,1,14.883268482490273,315,2,1,15.087548638132297,316,3,1,14.883268482490273,317,4,1,14.883268482490266,318,5,1,14.88326848249028,319,6,1,14.88326848249028,320,7,1,14.88326848249028,321]}}
  #|{"textrec":{"s":[13,400,0,"修改会写入 Slack 中的此 app"],"r":[0,1,12.898832684824903,322,1,1,12.898832684824903,296,2,1,12.898832684824903,216,3,1,12.898832684824903,252,4,1,12.898832684824896,249,5,1,3.580078125,-1,6,1,8.20751953125,222,7,1,3.2119140625,76,8,1,7.0966796875,12,9,1,7.1982421875,13,10,1,6.982421875,9,11,1,3.580078125,-1,12,1,12.898832684824896,275,13,1,12.898832684824896,5,14,1,12.898832684824896,244,15,1,3.580078125,-1,16,1,7.0966796875,12,17,1,7.8583984375,11,18,1,7.8583984375,11]}}
  #|{"textrec":{"s":[15,600,0,"最近会话"],"r":[0,1,14.883268482490273,323,1,1,14.883268482490273,324,2,1,14.883268482490273,325,3,1,14.883268482490273,326]}}
  #|{"textrec":{"s":[15,400,0,"暂无会话。在 Slack 中 @e2e-080726 即可开始。"],"r":[0,1,14.883268482490273,327,1,1,14.883268482490273,328,2,1,14.883268482490273,272,3,1,14.883268482490273,273,4,1,15.08754863813229,329,5,1,14.88326848249028,330,6,1,3.984375,-1,7,1,9.32373046875,100,8,1,3.5595703125,108,9,1,8.0419921875,93,10,1,8.1591796875,94,11,1,7.91015625,90,12,1,3.984375,-1,13,1,14.88326848249028,331,14,1,3.984375,-1,15,1,13.53515625,332,16,1,8.3349609375,95,17,1,8.78173828125,210,18,1,8.29833984375,95,19,1,6.8408203125,211,20,1,9.2138671875,164,21,1,9.345703125,212,22,1,9.0673828125,164,23,1,8.1591796875,213,24,1,8.818359375,210,25,1,9.31640625,214,26,1,3.984375,-1,27,1,14.88326848249028,333,28,1,14.88326848249028,334,29,1,14.88326848249028,335,30,1,14.88326848249028,336,31,1,7.5875486381323185,329]}}
  #|{"textrec":{"g":240,"r":[346,32,18,18,-1,-15,0]}}
  #|{"textrec":{"g":241,"r":[365,32,18,18,-1,-15,0]}}
  #|{"textrec":{"g":244,"r":[384,32,15,14,-1,-12,0]}}
  #|{"textrec":{"g":245,"r":[400,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":246,"r":[416,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":247,"r":[432,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":248,"r":[446,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":249,"r":[462,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":9,"r":[478,32,8,12,0,-11,0]}}
  #|{"textrec":{"g":250,"r":[487,32,6,6,0,-3,0]}}
  #|{"textrec":{"g":253,"r":[494,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":254,"r":[512,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":255,"r":[529,32,16,17,-1,-14,0]}}
  #|{"textrec":{"g":256,"r":[546,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":257,"r":[563,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":258,"r":[579,32,14,14,-1,-12,0]}}
  #|{"textrec":{"g":288,"r":[594,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":289,"r":[610,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":290,"r":[626,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":282,"r":[641,32,5,7,0,-3,0]}}
  #|{"textrec":{"g":291,"r":[647,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":292,"r":[662,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":284,"r":[678,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":293,"r":[693,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":294,"r":[708,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":295,"r":[724,32,15,14,-1,-11,0]}}
  #|{"textrec":{"g":296,"r":[740,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":297,"r":[756,32,5,11,1,-9,0]}}
  #|{"textrec":{"g":298,"r":[762,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":142,"r":[777,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":299,"r":[792,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":300,"r":[808,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":301,"r":[823,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":302,"r":[839,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":153,"r":[855,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":303,"r":[871,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":150,"r":[887,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":287,"r":[903,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":275,"r":[919,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":5,"r":[933,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":304,"r":[947,32,15,14,-1,-12,0]}}
  #|{"textrec":{"g":285,"r":[963,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":278,"r":[979,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":305,"r":[994,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":306,"r":[1010,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":307,"r":[1026,32,15,13,-1,-11,0]}}
  #|{"textrec":{"g":308,"r":[1042,32,12,14,-1,-12,0]}}
  #|{"textrec":{"g":309,"r":[1055,32,5,14,0,-13,0]}}
  #|{"textrec":{"g":310,"r":[1061,32,10,12,-1,-10,0]}}
  #|{"textrec":{"g":311,"r":[1072,32,11,12,-1,-10,0]}}
  #|{"textrec":{"g":312,"r":[1084,32,10,14,0,-13,0]}}
  #|{"textrec":{"g":313,"r":[1095,32,10,14,0,-10,0]}}
  #|{"textrec":{"g":323,"r":[1106,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":324,"r":[1123,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":325,"r":[1141,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":326,"r":[1159,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":327,"r":[1177,32,15,17,0,-14,0]}}
  #|{"textrec":{"g":328,"r":[1193,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":272,"r":[1210,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":273,"r":[1228,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":329,"r":[1246,32,7,7,0,-4,0]}}
  #|{"textrec":{"g":330,"r":[1254,32,16,17,-1,-14,0]}}
  #|{"textrec":{"g":331,"r":[1271,32,15,16,0,-13,0]}}
  #|{"textrec":{"g":332,"r":[1287,32,14,15,0,-12,0]}}
  #|{"textrec":{"g":333,"r":[1302,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":334,"r":[1319,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":335,"r":[1336,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":336,"r":[1353,32,16,16,-1,-13,0]}}
  #|{"textrec":{"ib":["76961adfc9864d7d",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"g":314,"r":[1370,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":315,"r":[1386,32,16,17,-1,-14,0]}}
  #|{"textrec":{"g":316,"r":[1403,32,7,7,0,-4,0]}}
  #|{"textrec":{"g":317,"r":[1411,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":318,"r":[1428,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":319,"r":[1446,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":320,"r":[1463,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":321,"r":[1481,32,16,16,0,-13,0]}}
  #|{"textrec":{"g":322,"r":[1498,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":252,"r":[1514,32,14,14,-1,-11,0]}}
  #|{"textrec":{"ib":["78b0ba5fc1dd19af",2593,64],"r":[25,25,25,25]}}
  #|{"textrec":{"g":242,"r":[1529,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":243,"r":[1545,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":4,"r":[1560,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":259,"r":[1575,32,10,14,0,-12,0]}}
  #|{"textrec":{"g":160,"r":[1586,32,5,5,0,-3,0]}}
  #|{"textrec":{"g":260,"r":[1592,32,5,5,1,-8,0]}}
  #|{"textrec":{"g":261,"r":[1598,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":262,"r":[1616,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":263,"r":[1634,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":264,"r":[1652,32,16,17,-1,-14,0]}}
  #|{"textrec":{"g":265,"r":[1669,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":266,"r":[1686,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":267,"r":[1703,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":268,"r":[1721,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":269,"r":[1739,32,9,14,0,-13,0]}}
  #|{"textrec":{"g":270,"r":[1749,32,10,15,-1,-13,0]}}
  #|{"textrec":{"g":271,"r":[1760,32,16,4,-1,-7,0]}}
  #|{"textrec":{"g":1,"r":[1777,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":274,"r":[1792,32,8,12,0,-11,0]}}
  #|{"textrec":{"g":8,"r":[1801,32,6,9,0,-8,0]}}
  #|{"textrec":{"g":276,"r":[1808,32,14,14,-1,-12,0]}}
  #|{"textrec":{"g":277,"r":[1823,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":279,"r":[1838,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":280,"r":[1853,32,15,4,-1,-7,0]}}
  #|{"textrec":{"g":281,"r":[1869,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":283,"r":[1885,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":151,"r":[1901,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":152,"r":[1916,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":286,"r":[1932,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":46,"r":[1947,32,11,12,-1,-10,0]}}
  #|{"textrec":{"g":234,"r":[1959,32,11,14,0,-13,0]}}
  #|{"textrec":{"g":235,"r":[1971,32,8,5,0,-7,0]}}
  #|{"textrec":{"g":236,"r":[1980,32,11,15,0,-13,0]}}
  #|{"textrec":{"g":237,"r":[1992,32,12,15,-1,-13,0]}}
  #|{"textrec":{"g":238,"r":[2005,32,11,14,-1,-13,0]}}
  #|{"textrec":{"g":239,"r":[2017,32,12,15,-1,-13,0]}}
  #|{"textrec":{"g":226,"r":[2030,32,13,13,-1,-10,0]}}
  #|{"textrec":{"g":227,"r":[0,51,13,13,-1,-10,0]}}
  #|{"textrec":{"g":228,"r":[14,51,13,13,-1,-10,0]}}
  #|{"textrec":{"g":229,"r":[28,51,9,11,-1,-9,0]}}
  #|{"textrec":{"g":230,"r":[38,51,4,11,-1,-10,0]}}
  #|{"textrec":{"g":231,"r":[43,51,8,9,-1,-7,0]}}
  #|{"textrec":{"g":232,"r":[52,51,8,9,-1,-7,0]}}
  #|{"textrec":{"g":233,"r":[61,51,8,11,-1,-10,0]}}
  #|{"textrec":{"g":251,"r":[70,51,15,15,-1,-12,0]}}
  #|{"textrec":{"ib":["ddfdc2820df8a676",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"s":[17,700,0,"e2e-080726"],"r":[0,1,9.782470703125,337,1,1,10.479736328125,338,2,1,9.76171875,337,3,1,7.802734375,339,4,1,11.2060546875,340,5,1,11.322265625,341,6,1,10.99853515625,340,7,1,9.6787109375,342,8,1,10.50048828125,338,9,1,11.189453125,343]}}
  #|{"textrec":{"m":[17,700,0],"r":[16.435546875,3.5859375,24,16.435546875,3.5859375,0]}}
  #|{"textrec":{"s":[15,400,0,"重新连接"],"r":[0,1,14.883268482490273,344,1,1,14.883268482490273,159,2,1,14.883268482490273,104,3,1,14.883268482490273,105]}}
  #|{"textrec":{"s":[15,400,0,"更换 token"],"r":[0,1,14.883268482490273,158,1,1,14.883268482490273,345,2,1,3.984375,-1,3,1,5.159912109375,101,4,1,8.572998046875,88,5,1,7.72705078125,90,6,1,8.15185546875,95,7,1,8.51806640625,103]}}
  #|{"textrec":{"s":[15,400,0,"停用"],"r":[0,1,14.883268482490273,346,1,1,14.883268482490273,115]}}
  #|{"textrec":{"s":[12,400,0,"Slack 连接将断开"],"r":[0,1,7.646484375,205,1,1,3.03515625,206,2,1,6.62109375,207,3,1,6.71484375,208,4,1,6.515625,209,5,1,3.375,-1,6,1,11.918287937743187,203,7,1,11.918287937743187,204,8,1,11.918287937743187,347,9,1,11.918287937743187,348,10,1,11.918287937743187,349]}}
  #|{"textrec":{"s":[15,400,0,"更改所属用户"],"r":[0,1,14.883268482490273,158,1,1,14.883268482490273,350,2,1,14.883268482490273,351,3,1,14.883268482490273,352,4,1,14.88326848249028,115,5,1,14.88326848249028,353]}}
  #|{"textrec":{"s":[12,400,0,"你"],"r":[0,1,11.918287937743191,354]}}
  #|{"textrec":{"s":[15,400,0,"删除连接"],"r":[0,1,14.883268482490273,355,1,1,14.883268482490273,356,2,1,14.883268482490273,104,3,1,14.883268482490273,105]}}
  #|{"textrec":{"g":337,"r":[86,51,12,13,-1,-11,0]}}
  #|{"textrec":{"g":338,"r":[99,51,11,15,0,-14,0]}}
  #|{"textrec":{"g":339,"r":[111,51,8,5,0,-7,0]}}
  #|{"textrec":{"g":340,"r":[120,51,12,16,0,-14,0]}}
  #|{"textrec":{"g":341,"r":[133,51,12,16,0,-14,0]}}
  #|{"textrec":{"g":342,"r":[146,51,12,14,-1,-13,0]}}
  #|{"textrec":{"g":343,"r":[159,51,12,16,0,-14,0]}}
  #|{"textrec":{"g":344,"r":[172,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":159,"r":[189,51,17,17,-1,-14,0]}}
  #|{"textrec":{"g":158,"r":[207,51,17,16,-1,-13,0]}}
  #|{"textrec":{"g":345,"r":[225,51,17,17,-1,-14,0]}}
  #|{"textrec":{"g":346,"r":[243,51,16,17,-1,-14,0]}}
  #|{"textrec":{"g":347,"r":[260,51,14,14,-1,-11,0]}}
  #|{"textrec":{"g":348,"r":[275,51,14,14,-1,-11,0]}}
  #|{"textrec":{"g":349,"r":[290,51,14,13,-1,-10,0]}}
  #|{"textrec":{"g":350,"r":[305,51,17,16,-1,-13,0]}}
  #|{"textrec":{"g":351,"r":[323,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":352,"r":[340,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":353,"r":[357,51,15,17,-1,-14,0]}}
  #|{"textrec":{"g":354,"r":[373,51,14,14,-1,-11,0]}}
  #|{"textrec":{"g":355,"r":[388,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":356,"r":[405,51,16,16,0,-13,0]}}
  #|{"textrec":{"s":[11,400,0,"已停用"],"r":[0,1,10.93579766536965,357,1,1,10.93579766536965,358,2,1,10.935797665369652,359]}}
  #|{"textrec":{"s":[14,400,0,"已停用，Slack 连接已断开"],"r":[0,1,13.891050583657588,360,1,1,13.891050583657588,361,2,1,13.891050583657588,55,3,1,12.681712062256807,50,4,1,8.7705078125,362,5,1,3.390625,363,6,1,7.57421875,57,7,1,7.68359375,364,8,1,7.451171875,365,9,1,3.787109375,-1,10,1,13.891050583657588,366,11,1,13.891050583657588,367,12,1,13.891050583657602,360,13,1,13.891050583657602,368,14,1,13.891050583657602,97]}}
  #|{"textrec":{"g":357,"r":[422,51,13,12,-1,-10,0]}}
  #|{"textrec":{"g":358,"r":[436,51,12,13,-1,-10,0]}}
  #|{"textrec":{"g":359,"r":[449,51,12,12,-1,-10,0]}}
  #|{"textrec":{"g":360,"r":[462,51,14,14,0,-12,0]}}
  #|{"textrec":{"g":361,"r":[477,51,15,16,-1,-13,0]}}
  #|{"textrec":{"g":362,"r":[493,51,11,14,-1,-12,0]}}
  #|{"textrec":{"g":363,"r":[505,51,4,13,0,-12,0]}}
  #|{"textrec":{"g":364,"r":[510,51,10,11,-1,-9,0]}}
  #|{"textrec":{"g":365,"r":[521,51,9,13,0,-12,0]}}
  #|{"textrec":{"g":366,"r":[531,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":367,"r":[548,51,15,16,-1,-13,0]}}
  #|{"textrec":{"g":368,"r":[564,51,16,16,-1,-13,0]}}
  #|{"textrec":{"s":[17,700,0,"会话方式"],"r":[0,1,16.851167315175097,369,1,1,16.851167315175097,370,2,1,16.851167315175097,371,3,1,16.851167315175097,372]}}
  #|{"textrec":{"s":[15,600,0,"每个 thread 一个会话"],"r":[0,1,14.883268482490273,373,1,1,14.883268482490273,374,2,1,3.761730194091797,-1,3,1,5.683325529098511,197,4,1,9.00644838809967,375,5,1,5.895114541053772,181,6,1,8.517318964004517,85,7,1,8.40147078037262,310,8,1,9.332013130187988,199,9,1,3.761730194091797,-1,10,1,14.883268482490266,376,11,1,14.88326848249028,374,12,1,14.88326848249028,325,13,1,14.88326848249028,326]}}
  #|{"textrec":{"s":[15,600,0,"所有 thread 共用一个会话"],"r":[0,1,14.883268482490273,377,1,1,14.883268482490273,378,2,1,3.761730194091797,-1,3,1,5.683325529098511,197,4,1,9.00644838809967,375,5,1,5.895114541053772,181,6,1,8.517318964004517,85,7,1,8.40147078037262,310,8,1,9.332013130187988,199,9,1,3.761730194091797,-1,10,1,14.883268482490266,379,11,1,14.88326848249028,380,12,1,14.88326848249028,376,13,1,14.88326848249028,374,14,1,14.88326848249028,325,15,1,14.88326848249028,326]}}
  #|{"textrec":{"s":[13,400,0,"它看到的所有 thread 都进入同一个会话，适合长期值守的助手"],"r":[0,1,12.898832684824903,276,1,1,12.898832684824903,381,2,1,12.898832684824903,382,3,1,12.898832684824903,5,4,1,12.898832684824896,242,5,1,12.898832684824896,149,6,1,3.580078125,-1,7,1,4.646484375,82,8,1,7.57275390625,274,9,1,4.77978515625,8,10,1,7.25537109375,14,11,1,7.0966796875,12,12,1,7.9091796875,221,13,1,3.580078125,-1,14,1,12.898832684824896,286,15,1,12.898832684824896,287,16,1,12.898832684824896,249,17,1,12.898832684824896,383,18,1,12.898832684824896,280,19,1,12.898832684824896,281,20,1,12.898832684824896,216,21,1,12.898832684824896,217,22,1,13.075875486381335,282,23,1,12.898832684824896,384,24,1,12.898832684824924,385,25,1,12.898832684824924,386,26,1,12.898832684824924,387,27,1,12.898832684824924,388,28,1,12.898832684824924,389,29,1,12.898832684824924,5,30,1,12.898832684824924,390,31,1,12.898832684824924,391]}}
  #|{"textrec":{"s":[14,600,0,"取消"],"r":[0,1,13.891050583657588,392,1,1,13.891050583657588,393]}}
  #|{"textrec":{"m":[14,600,0],"r":[13.53515625,2.953125,20,13.53515625,2.953125,0]}}
  #|{"textrec":{"s":[14,600,0,"确认更改"],"r":[0,1,13.891050583657588,394,1,1,13.891050583657588,395,2,1,13.891050583657588,396,3,1,13.891050583657588,397]}}
  #|{"textrec":{"g":369,"r":[581,51,19,18,-1,-15,0]}}
  #|{"textrec":{"g":370,"r":[601,51,19,18,-1,-15,0]}}
  #|{"textrec":{"g":371,"r":[621,51,18,18,-1,-15,0]}}
  #|{"textrec":{"g":372,"r":[640,51,18,18,-1,-15,0]}}
  #|{"textrec":{"g":373,"r":[659,51,17,17,-1,-14,0]}}
  #|{"textrec":{"g":374,"r":[677,51,17,16,-1,-13,0]}}
  #|{"textrec":{"g":375,"r":[695,51,10,14,0,-13,0]}}
  #|{"textrec":{"g":376,"r":[706,51,16,5,-1,-8,0]}}
  #|{"textrec":{"g":377,"r":[723,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":378,"r":[740,51,16,17,-1,-14,0]}}
  #|{"textrec":{"g":379,"r":[757,51,16,17,-1,-14,0]}}
  #|{"textrec":{"g":380,"r":[774,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":381,"r":[791,51,14,15,-1,-12,0]}}
  #|{"textrec":{"g":382,"r":[806,51,14,15,-1,-12,0]}}
  #|{"textrec":{"g":149,"r":[821,51,14,15,-1,-12,0]}}
  #|{"textrec":{"g":383,"r":[836,51,13,14,0,-11,0]}}
  #|{"textrec":{"g":384,"r":[850,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":385,"r":[866,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":386,"r":[882,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":387,"r":[898,51,14,15,-1,-12,0]}}
  #|{"textrec":{"g":388,"r":[913,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":389,"r":[929,51,14,15,-1,-12,0]}}
  #|{"textrec":{"g":390,"r":[944,51,14,15,-1,-12,0]}}
  #|{"textrec":{"g":391,"r":[959,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":392,"r":[975,51,16,15,-1,-12,0]}}
  #|{"textrec":{"g":393,"r":[992,51,15,16,-1,-13,0]}}
  #|{"textrec":{"g":394,"r":[1008,51,15,16,-1,-13,0]}}
  #|{"textrec":{"g":395,"r":[1024,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":396,"r":[1041,51,16,15,-1,-12,0]}}
  #|{"textrec":{"g":397,"r":[1058,51,16,16,-1,-13,0]}}
  #|{"textrec":{"s":[14,600,0,"仅在被 @ 时唤醒"],"r":[0,1,13.891050583657588,398,1,1,13.891050583657588,399,2,1,13.891050583657588,400,3,1,3.5793075561523438,-1,4,1,12.781262159347534,401,5,1,3.5793075561523438,-1,6,1,13.891050583657588,402,7,1,13.891050583657588,403,8,1,13.891050583657588,404]}}
  #|{"textrec":{"s":[13,400,0,"被 @ 的 thread 中，后续回复无需再 @。"],"r":[0,1,12.898832684824903,405,1,1,3.580078125,-1,2,1,11.857421875,78,3,1,3.580078125,-1,4,1,12.898832684824903,5,5,1,3.580078125,-1,6,1,4.646484375,82,7,1,7.57275390625,274,8,1,4.77978515625,8,9,1,7.25537109375,14,10,1,7.0966796875,12,11,1,7.9091796875,221,12,1,3.580078125,-1,13,1,12.89883268482491,275,14,1,13.075875486381321,282,15,1,12.89883268482491,284,16,1,12.898832684824896,285,17,1,12.898832684824896,406,18,1,12.898832684824896,407,19,1,12.898832684824896,293,20,1,12.898832684824896,142,21,1,12.898832684824896,408,22,1,3.580078125,-1,23,1,11.857421875,78,24,1,6.575875486381335,250]}}
  #|{"textrec":{"s":[13,600,0,"更改后"],"r":[0,1,12.898832684824903,409,1,1,12.898832684824903,410,2,1,12.898832684824903,411]}}
  #|{"textrec":{"m":[13,600,0],"r":[12.568359375,2.7421875,18,12.568359375,2.7421875,0]}}
  #|{"textrec":{"s":[13,400,0,"· 此后它收到的消息都将进入同一个会话；现有各 thread 的会话不再接收新消息，包括这些 thread 中的回复。记录会保留。"],"r":[0,1,6.22854520422212,218,1,1,3.580078124999999,-1,2,1,12.898832684824903,244,3,1,12.8988326848249,284,4,1,12.898832684824903,276,5,1,12.898832684824903,412,6,1,12.898832684824896,382,7,1,12.898832684824896,5,8,1,12.898832684824896,151,9,1,12.898832684824896,152,10,1,12.898832684824896,286,11,1,12.898832684824896,413,12,1,12.898832684824896,287,13,1,12.898832684824896,249,14,1,12.898832684824896,383,15,1,12.898832684824896,280,16,1,12.898832684824896,281,17,1,12.898832684824896,216,18,1,12.898832684824896,217,19,1,13.075875486381335,297,20,1,12.898832684824896,414,21,1,12.898832684824924,149,22,1,12.898832684824924,415,23,1,3.580078125,-1,24,1,4.646484375,82,25,1,7.57275390625,274,26,1,4.77978515625,8,27,1,7.25537109375,14,28,1,7.0966796875,12,29,1,7.9091796875,221,30,1,3.580078125,-1,31,1,12.898832684824924,5,32,1,12.898832684824924,216,33,1,12.898832684824924,217,34,1,12.898832684824924,416,35,1,12.898832684824924,408,36,1,12.898832684824924,246,37,1,12.898832684824924,412,38,1,12.898832684824924,150,39,1,12.898832684824924,151,40,1,12.898832684824924,152,41,1,13.075875486381335,282,42,1,12.898832684824924,417,43,1,12.898832684824924,418,44,1,12.898832684824924,419,45,1,12.898832684824924,420,46,1,3.580078125,-1,47,1,4.646484375,82,48,1,7.57275390625,274,49,1,4.77978515625,8,50,1,7.25537109375,14,51,1,7.0966796875,12,52,1,7.9091796875,221,53,1,3.580078125,-1,54,1,12.898832684824924,275,55,1,12.898832684824924,5,56,1,12.898832684824924,406,57,1,12.898832684824924,407,58,1,13.075875486381278,250,59,1,12.898832684824924,421,60,1,12.898832684824924,422,61,1,12.898832684824924,216,62,1,12.898832684824924,423,63,1,12.898832684824924,424,64,1,6.575875486381278,250]}}
  #|{"textrec":{"s":[13,400,0,"· 下一条消息将开始新的单会话；也可在切换后选择已有会话。"],"r":[0,1,6.22854520422212,218,1,1,3.580078124999999,-1,2,1,12.898832684824903,425,3,1,12.8988326848249,280,4,1,12.898832684824903,426,5,1,12.898832684824903,151,6,1,12.898832684824896,152,7,1,12.898832684824896,413,8,1,12.898832684824896,278,9,1,12.898832684824896,305,10,1,12.898832684824896,150,11,1,12.898832684824896,5,12,1,12.898832684824896,427,13,1,12.898832684824896,216,14,1,12.898832684824896,217,15,1,13.075875486381335,297,16,1,12.898832684824896,428,17,1,12.898832684824896,429,18,1,12.898832684824896,1,19,1,12.898832684824896,430,20,1,12.898832684824896,431,21,1,12.898832684824924,284,22,1,12.898832684824924,432,23,1,12.898832684824924,433,24,1,12.898832684824924,434,25,1,12.898832684824924,149,26,1,12.898832684824924,216,27,1,12.898832684824924,217,28,1,6.575875486381335,250]}}
  #|{"textrec":{"s":[14,600,0,"改为单会话"],"r":[0,1,13.891050583657588,397,1,1,13.891050583657588,435,2,1,13.891050583657588,436,3,1,13.891050583657588,437,4,1,13.891050583657588,438]}}
  #|{"textrec":{"g":398,"r":[1075,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":399,"r":[1092,51,15,16,-1,-13,0]}}
  #|{"textrec":{"g":400,"r":[1108,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":401,"r":[1125,51,15,14,-1,-11,0]}}
  #|{"textrec":{"g":402,"r":[1141,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":403,"r":[1158,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":404,"r":[1175,51,16,15,-1,-12,0]}}
  #|{"textrec":{"g":405,"r":[1192,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":406,"r":[1208,51,13,14,0,-11,0]}}
  #|{"textrec":{"g":407,"r":[1222,51,14,15,-1,-12,0]}}
  #|{"textrec":{"g":408,"r":[1237,51,15,14,-1,-11,0]}}
  #|{"textrec":{"g":409,"r":[1253,51,15,14,-1,-11,0]}}
  #|{"textrec":{"g":410,"r":[1269,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":411,"r":[1285,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":412,"r":[1301,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":413,"r":[1317,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":414,"r":[1333,51,15,14,-1,-11,0]}}
  #|{"textrec":{"g":415,"r":[1349,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":416,"r":[1365,51,15,14,-1,-11,0]}}
  #|{"textrec":{"g":417,"r":[1381,51,14,15,-1,-12,0]}}
  #|{"textrec":{"g":418,"r":[1396,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":419,"r":[1412,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":420,"r":[1428,51,14,14,-1,-12,0]}}
  #|{"textrec":{"g":421,"r":[1443,51,15,14,-1,-12,0]}}
  #|{"textrec":{"g":422,"r":[1459,51,14,14,-1,-11,0]}}
  #|{"textrec":{"g":423,"r":[1474,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":424,"r":[1490,51,14,15,-1,-12,0]}}
  #|{"textrec":{"g":425,"r":[1505,51,14,14,-1,-11,0]}}
  #|{"textrec":{"g":426,"r":[1520,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":427,"r":[1536,51,14,15,-1,-12,0]}}
  #|{"textrec":{"g":428,"r":[1551,51,15,14,-1,-12,0]}}
  #|{"textrec":{"g":429,"r":[1567,51,14,14,-1,-11,0]}}
  #|{"textrec":{"g":430,"r":[1582,51,14,15,-1,-12,0]}}
  #|{"textrec":{"g":431,"r":[1597,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":432,"r":[1613,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":433,"r":[1629,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":434,"r":[1645,51,13,13,0,-11,0]}}
  #|{"textrec":{"g":435,"r":[1659,51,15,16,-1,-13,0]}}
  #|{"textrec":{"g":436,"r":[1675,51,15,16,-1,-13,0]}}
  #|{"textrec":{"g":437,"r":[1691,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":438,"r":[1708,51,16,16,-1,-13,0]}}
  #|{"textrec":{"s":[14,400,0,"已更改会话方式"],"r":[0,1,13.891050583657588,360,1,1,13.891050583657588,439,2,1,13.891050583657588,440,3,1,13.891050583657588,441,4,1,13.891050583657588,442,5,1,13.891050583657588,443,6,1,13.891050583657588,444]}}
  #|{"textrec":{"g":439,"r":[1725,51,16,15,-1,-12,0]}}
  #|{"textrec":{"g":440,"r":[1742,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":441,"r":[1759,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":442,"r":[1776,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":443,"r":[1793,51,15,16,-1,-13,0]}}
  #|{"textrec":{"g":444,"r":[1809,51,15,16,-1,-13,0]}}
  #|{"textrec":{"s":[15,400,0,"所有 thread 共用一个会话"],"r":[0,1,14.883268482490273,351,1,1,14.883268482490273,445,2,1,3.984375,-1,3,1,5.21484375,101,4,1,8.59130859375,269,5,1,5.36865234375,89,6,1,8.22509765625,95,7,1,8.0419921875,93,8,1,8.9794921875,270,9,1,3.984375,-1,10,1,14.883268482490266,446,11,1,14.88326848249028,115,12,1,14.88326848249028,271,13,1,14.88326848249028,268,14,1,14.88326848249028,272,15,1,14.88326848249028,273]}}
  #|{"textrec":{"s":[13,400,0,"它看到的所有 thread 都进入同一个会话，适合长期值守的助手仅在被 @ 时唤醒。"],"r":[0,1,12.898832684824903,276,1,1,12.898832684824903,381,2,1,12.898832684824903,382,3,1,12.898832684824903,5,4,1,12.898832684824896,242,5,1,12.898832684824896,149,6,1,3.580078125,-1,7,1,4.646484375,82,8,1,7.57275390625,274,9,1,4.77978515625,8,10,1,7.25537109375,14,11,1,7.0966796875,12,12,1,7.9091796875,221,13,1,3.580078125,-1,14,1,12.898832684824896,286,15,1,12.898832684824896,287,16,1,12.898832684824896,249,17,1,12.898832684824896,383,18,1,12.898832684824896,280,19,1,12.898832684824896,281,20,1,12.898832684824896,216,21,1,12.898832684824896,217,22,1,13.075875486381335,282,23,1,12.898832684824896,384,24,1,12.898832684824924,385,25,1,12.898832684824924,386,26,1,12.898832684824924,387,27,1,12.898832684824924,388,28,1,12.898832684824924,389,29,1,12.898832684824924,5,30,1,12.898832684824924,390,31,1,12.898832684824924,391,32,1,12.898832684824924,447,33,1,12.898832684824924,1,34,1,12.898832684824924,405,35,1,3.580078125,-1,36,1,11.857421875,78,37,1,3.580078125,-1,38,1,12.898832684824924,153,39,1,12.898832684824924,448,40,1,12.898832684824924,449,41,1,6.575875486381335,250]}}
  #|{"textrec":{"s":[13,400,0,"当前"],"r":[0,1,12.898832684824903,450,1,1,12.898832684824903,451]}}
  #|{"textrec":{"s":[15,400,0,"暂无会话；下一条消息将开始新会话。"],"r":[0,1,14.883268482490273,327,1,1,14.883268482490273,328,2,1,14.883268482490273,272,3,1,14.883268482490273,273,4,1,15.08754863813229,452,5,1,14.88326848249028,128,6,1,14.88326848249028,271,7,1,14.88326848249028,170,8,1,14.88326848249028,453,9,1,14.88326848249028,454,10,1,14.88326848249028,455,11,1,14.88326848249028,335,12,1,14.88326848249028,336,13,1,14.88326848249028,159,14,1,14.88326848249028,272,15,1,14.88326848249028,273,16,1,7.58754863813229,329]}}
  #|{"textrec":{"g":445,"r":[1825,51,16,17,-1,-14,0]}}
  #|{"textrec":{"g":446,"r":[1842,51,16,17,-1,-14,0]}}
  #|{"textrec":{"g":447,"r":[1859,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":448,"r":[1875,51,14,15,0,-12,0]}}
  #|{"textrec":{"g":449,"r":[1890,51,15,14,-1,-11,0]}}
  #|{"textrec":{"g":450,"r":[1906,51,13,15,0,-12,0]}}
  #|{"textrec":{"g":451,"r":[1920,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":452,"r":[1936,51,5,12,1,-10,0]}}
  #|{"textrec":{"g":170,"r":[1942,51,16,17,-1,-14,0]}}
  #|{"textrec":{"g":453,"r":[1959,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":454,"r":[1976,51,16,17,-1,-14,0]}}
  #|{"textrec":{"g":455,"r":[1993,51,16,16,-1,-13,0]}}
  #|{"textrec":{"s":[15,400,0,"启用"],"r":[0,1,14.883268482490273,456,1,1,14.883268482490273,115]}}
  #|{"textrec":{"g":456,"r":[2010,51,15,17,-1,-14,0]}}
  #|{"textrec":{"s":[17,700,0,"Slack token"],"r":[0,1,11.044189453125,457,1,1,4.58203125,458,2,1,9.591552734375,459,3,1,9.55419921875,460,4,1,9.790771484375,461,5,1,3.951171875,-1,6,1,6.5513916015625,462,7,1,10.0709228515625,463,8,1,9.52099609375,461,9,1,9.5126953125,337,10,1,10.230712890625,464]}}
  #|{"textrec":{"s":[12,400,0,"可仅更换其中一个，留空的一项将沿用已保存的值。"],"r":[0,1,11.918287937743191,465,1,1,11.918287937743191,466,2,1,11.918287937743195,467,3,1,11.918287937743187,468,4,1,11.918287937743187,469,5,1,11.918287937743187,470,6,1,11.918287937743187,471,7,1,11.918287937743187,472,8,1,12.081712062256813,473,9,1,11.918287937743187,474,10,1,11.918287937743187,475,11,1,11.918287937743202,476,12,1,11.918287937743202,471,13,1,11.918287937743202,477,14,1,11.918287937743202,347,15,1,11.918287937743202,478,16,1,11.918287937743202,479,17,1,11.918287937743202,480,18,1,11.918287937743202,481,19,1,11.918287937743202,482,20,1,11.918287937743202,476,21,1,11.918287937743202,483,22,1,6.081712062256827,484]}}
  #|{"textrec":{"s":[13,600,0,"App-Level Token"],"r":[0,1,9.165990829467773,485,1,1,8.159896612167358,486,2,1,8.159896612167358,486,3,1,6.160183429718018,487,4,1,7.3685595989227295,488,5,1,7.351526618003845,489,6,1,7.08481502532959,490,7,1,7.456791400909424,489,8,1,3.5576319694519043,491,9,1,3.3871192932128906,-1,10,1,7.765498876571655,492,11,1,7.2270050048828125,493,12,1,7.273967742919922,494,13,1,7.404953241348267,489,14,1,7.869065165519714,495]}}
  #|{"textrec":{"s":[13,600,0,"Bot Token"],"r":[0,1,8.765251636505127,496,1,1,7.841670751571655,493,2,1,5.052501916885376,497,3,1,3.3871192932128906,-1,4,1,7.765498876571655,492,5,1,7.2270050048828125,493,6,1,7.273967742919922,494,7,1,7.404953241348267,489,8,1,7.869065165519714,495]}}
  #|{"textrec":{"s":[14,600,0,"保存并连接"],"r":[0,1,13.891050583657588,498,1,1,13.891050583657588,499,2,1,13.891050583657588,500,3,1,13.891050583657588,501,4,1,13.891050583657588,502]}}
  #|{"textrec":{"g":457,"r":[2026,51,13,16,-1,-14,0]}}
  #|{"textrec":{"g":458,"r":[2040,51,5,15,0,-14,0]}}
  #|{"textrec":{"g":459,"r":[0,70,11,13,-1,-11,0]}}
  #|{"textrec":{"g":460,"r":[12,70,12,13,-1,-11,0]}}
  #|{"textrec":{"g":461,"r":[25,70,11,15,0,-14,0]}}
  #|{"textrec":{"g":462,"r":[37,70,9,15,-1,-13,0]}}
  #|{"textrec":{"g":463,"r":[47,70,12,13,-1,-11,0]}}
  #|{"textrec":{"g":464,"r":[60,70,11,12,0,-11,0]}}
  #|{"textrec":{"g":465,"r":[72,70,14,13,-1,-10,0]}}
  #|{"textrec":{"g":466,"r":[87,70,14,14,-1,-11,0]}}
  #|{"textrec":{"g":467,"r":[102,70,14,14,-1,-11,0]}}
  #|{"textrec":{"g":468,"r":[117,70,14,14,-1,-11,0]}}
  #|{"textrec":{"g":469,"r":[132,70,14,14,-1,-11,0]}}
  #|{"textrec":{"g":470,"r":[147,70,12,14,0,-11,0]}}
  #|{"textrec":{"g":471,"r":[160,70,14,4,-1,-6,0]}}
  #|{"textrec":{"g":472,"r":[175,70,14,14,-1,-11,0]}}
  #|{"textrec":{"g":473,"r":[190,70,5,6,0,-3,0]}}
  #|{"textrec":{"g":474,"r":[196,70,13,14,-1,-11,0]}}
  #|{"textrec":{"g":475,"r":[210,70,13,13,-1,-11,0]}}
  #|{"textrec":{"g":476,"r":[224,70,13,14,-1,-11,0]}}
  #|{"textrec":{"g":477,"r":[238,70,14,14,-1,-11,0]}}
  #|{"textrec":{"g":478,"r":[253,70,14,14,-1,-11,0]}}
  #|{"textrec":{"g":479,"r":[268,70,13,14,-1,-11,0]}}
  #|{"textrec":{"g":480,"r":[282,70,13,12,0,-10,0]}}
  #|{"textrec":{"g":481,"r":[296,70,14,14,-1,-11,0]}}
  #|{"textrec":{"g":482,"r":[311,70,14,14,-1,-11,0]}}
  #|{"textrec":{"g":483,"r":[326,70,14,14,-1,-11,0]}}
  #|{"textrec":{"g":484,"r":[341,70,6,6,0,-3,0]}}
  #|{"textrec":{"g":485,"r":[348,70,11,12,-1,-11,0]}}
  #|{"textrec":{"g":486,"r":[360,70,10,13,-1,-9,0]}}
  #|{"textrec":{"g":487,"r":[371,70,8,5,-1,-6,0]}}
  #|{"textrec":{"g":488,"r":[380,70,8,12,0,-11,0]}}
  #|{"textrec":{"g":489,"r":[389,70,10,11,-1,-9,0]}}
  #|{"textrec":{"g":490,"r":[400,70,10,9,-1,-8,0]}}
  #|{"textrec":{"g":491,"r":[411,70,4,12,0,-11,0]}}
  #|{"textrec":{"g":492,"r":[416,70,10,12,-1,-11,0]}}
  #|{"textrec":{"g":493,"r":[427,70,10,11,-1,-9,0]}}
  #|{"textrec":{"g":494,"r":[438,70,9,12,0,-11,0]}}
  #|{"textrec":{"g":495,"r":[448,70,10,10,-1,-9,0]}}
  #|{"textrec":{"s":[15,400,0,"xapp-…"],"r":[0,1,7.6318359375,503,1,1,8.0419921875,93,2,1,8.9208984375,92,3,1,8.9208984375,92,4,1,6.8408203125,211,5,1,11.8359375,504]}}
  #|{"textrec":{"g":503,"r":[459,70,10,10,-1,-9,0]}}
  #|{"textrec":{"g":504,"r":[470,70,12,5,0,-3,0]}}
  #|{"textrec":{"g":496,"r":[483,70,10,12,0,-11,0]}}
  #|{"textrec":{"g":497,"r":[494,70,7,12,-1,-10,0]}}
  #|{"textrec":{"s":[15,400,0,"xoxb-…"],"r":[0,1,7.44873046875,503,1,1,8.26171875,88,2,1,7.44873046875,503,3,1,8.9794921875,162,4,1,6.8408203125,211,5,1,11.8359375,504]}}
  #|{"textrec":{"g":162,"r":[502,70,10,15,0,-13,0]}}
  #|{"textrec":{"g":498,"r":[513,70,16,16,-1,-13,0]}}
  #|{"textrec":{"g":499,"r":[530,70,16,16,-1,-13,0]}}
  #|{"textrec":{"g":500,"r":[547,70,15,16,-1,-13,0]}}
  #|{"textrec":{"g":501,"r":[563,70,16,16,-1,-13,0]}}
  #|{"textrec":{"g":502,"r":[580,70,16,16,-1,-13,0]}}
  #|{"textrec":{"s":[15,400,0,"••••••••••••••••••••"],"r":[0,1,6.8408203125,505,1,1,6.8408203125,505,2,1,6.8408203125,505,3,1,6.8408203125,505,4,1,6.8408203125,505,5,1,6.8408203125,505,6,1,6.8408203125,505,7,1,6.8408203125,505,8,1,6.8408203125,505,9,1,6.8408203125,505,10,1,6.8408203125,505,11,1,6.8408203125,505,12,1,6.8408203125,505,13,1,6.8408203125,505,14,1,6.8408203125,505,15,1,6.8408203125,505,16,1,6.8408203125,505,17,1,6.8408203125,505,18,1,6.8408203125,505,19,1,6.8408203125,505]}}
  #|{"textrec":{"g":505,"r":[597,70,6,6,1,-7,0]}}
  #|{"textrec":{"s":[15,400,0,"••••••••••••••••••"],"r":[0,1,6.8408203125,505,1,1,6.8408203125,505,2,1,6.8408203125,505,3,1,6.8408203125,505,4,1,6.8408203125,505,5,1,6.8408203125,505,6,1,6.8408203125,505,7,1,6.8408203125,505,8,1,6.8408203125,505,9,1,6.8408203125,505,10,1,6.8408203125,505,11,1,6.8408203125,505,12,1,6.8408203125,505,13,1,6.8408203125,505,14,1,6.8408203125,505,15,1,6.8408203125,505,16,1,6.8408203125,505,17,1,6.8408203125,505]}}
  #|{"textrec":{"s":[17,700,0,"删除「e2e-080726」？"],"r":[0,1,16.851167315175097,506,1,1,25.351167315175097,507,2,1,6.366731517509727,508,3,1,9.782470703125,337,4,1,10.479736328125007,338,5,1,9.76171875,337,6,1,7.802734375,339,7,1,11.2060546875,340,8,1,11.322265625,341,9,1,10.99853515625,340,10,1,9.6787109375,342,11,1,10.50048828125,338,12,1,11.189453125,343,13,1,8.194066147859928,509,14,1,8.582684824902714,510]}}
  #|{"textrec":{"s":[14,400,0,"Slack 连接将断开。Slack 中的 app 需要你手动删除。"],"r":[0,1,8.7705078125,362,1,1,3.390625,363,2,1,7.57421875,57,3,1,7.68359375,364,4,1,7.451171875,365,5,1,3.787109375,-1,6,1,13.891050583657588,366,7,1,13.891050583657588,367,8,1,13.891050583657588,511,9,1,13.891050583657588,368,10,1,13.891050583657588,97,11,1,14.081712062256813,512,12,1,8.7705078125,362,13,1,3.390625,363,14,1,7.57421875,57,15,1,7.68359375,364,16,1,7.451171875,365,17,1,3.787109375,-1,18,1,13.891050583657574,513,19,1,13.891050583657602,56,20,1,3.787109375,-1,21,1,7.57421875,57,22,1,8.39453125,514,23,1,8.39453125,514,24,1,3.787109375,-1,25,1,13.891050583657602,515,26,1,13.891050583657602,516,27,1,13.891050583657602,48,28,1,13.891050583657602,517,29,1,13.891050583657602,518,30,1,13.891050583657602,519,31,1,13.891050583657602,520,32,1,7.081712062256827,512]}}
  #|{"textrec":{"s":[14,600,0,"删除连接"],"r":[0,1,13.891050583657588,521,1,1,13.891050583657588,522,2,1,13.891050583657588,501,3,1,13.891050583657588,502]}}
  #|{"textrec":{"g":506,"r":[604,70,18,18,-1,-15,0]}}
  #|{"textrec":{"g":507,"r":[623,70,18,18,0,-15,0]}}
  #|{"textrec":{"g":508,"r":[642,70,9,13,-1.8333333333333304,-15,0]}}
  #|{"textrec":{"g":509,"r":[652,70,9,13,-1,-10,0]}}
  #|{"textrec":{"g":510,"r":[662,70,10,16,-1,-14,0]}}
  #|{"textrec":{"g":511,"r":[673,70,16,16,-1,-13,0]}}
  #|{"textrec":{"g":512,"r":[690,70,6,6,0,-3,0]}}
  #|{"textrec":{"g":513,"r":[697,70,14,16,0,-13,0]}}
  #|{"textrec":{"g":514,"r":[712,70,9,13,0,-9,0]}}
  #|{"textrec":{"g":515,"r":[722,70,15,15,-1,-12,0]}}
  #|{"textrec":{"g":516,"r":[738,70,16,15,-1,-12,0]}}
  #|{"textrec":{"g":517,"r":[755,70,15,16,-1,-13,0]}}
  #|{"textrec":{"g":518,"r":[771,70,15,16,-1,-13,0]}}
  #|{"textrec":{"g":519,"r":[787,70,15,16,-1,-13,0]}}
  #|{"textrec":{"g":520,"r":[803,70,15,15,0,-12,0]}}
  #|{"textrec":{"g":521,"r":[819,70,15,16,-1,-13,0]}}
  #|{"textrec":{"g":522,"r":[835,70,16,15,-1,-12,0]}}
  #|{"textrec":{"s":[12,400,0,"已停用"],"r":[0,1,11.918287937743191,480,1,1,11.918287937743191,523,2,1,11.918287937743195,479]}}
  #|{"textrec":{"s":[13,400,0,"单会话 · @ 唤醒 · Claude Code · Sonnet 5.5"],"r":[0,1,12.898832684824903,427,1,1,12.898832684824903,216,2,1,12.898832684824903,217,3,1,3.580078125,-1,4,1,6.228545204222122,218,5,1,3.580078125,-1,6,1,11.857421875,78,7,1,3.580078125,-1,8,1,12.898832684824896,448,9,1,12.898832684824896,449,10,1,3.580078125,-1,11,1,6.228545204222115,218,12,1,3.580078125,-1,13,1,9.2294921875,219,14,1,3.2119140625,76,15,1,7.0966796875,12,16,1,7.50927734375,220,17,1,7.9091796875,221,18,1,7.3505859375,14,19,1,3.580078125,-1,20,1,9.2294921875,219,21,1,7.6044921875,7,22,1,7.9091796875,221,23,1,7.3505859375,14,24,1,3.580078125,-1,25,1,6.228545204222115,218,26,1,3.580078125,-1,27,1,8.20751953125,222,28,1,7.6044921875,7,29,1,7.50927734375,223,30,1,7.50927734375,223,31,1,7.3505859375,14,32,1,4.646484375,82,33,1,3.580078125,-1,34,1,7.73779296875,224,35,1,3.354736328125,81,36,1,7.753662109375028,224]}}
  #|{"textrec":{"s":[13,400,0,"单会话 · @ 唤醒 · Claude Code · S…"],"r":[0,1,12.898832684824903,427,1,1,12.898832684824903,216,2,1,12.898832684824903,217,3,1,3.580078125,-1,4,1,6.228545204222122,218,5,1,3.580078125,-1,6,1,11.857421875,78,7,1,3.580078125,-1,8,1,12.898832684824896,448,9,1,12.898832684824896,449,10,1,3.580078125,-1,11,1,6.228545204222115,218,12,1,3.580078125,-1,13,1,9.2294921875,219,14,1,3.2119140625,76,15,1,7.0966796875,12,16,1,7.50927734375,220,17,1,7.9091796875,221,18,1,7.3505859375,14,19,1,3.580078125,-1,20,1,9.2294921875,219,21,1,7.6044921875,7,22,1,7.9091796875,221,23,1,7.3505859375,14,24,1,3.580078125,-1,25,1,6.228545204222115,218,26,1,3.580078125,-1,27,1,8.20751953125,222,28,1,10.384765625,225]}}
  #|{"textrec":{"g":523,"r":[852,70,13,14,-1,-11,0]}}
  #|{"textrec":{"s":[14,400,0,"连接不存在"],"r":[0,1,13.891050583657588,366,1,1,13.891050583657588,367,2,1,13.891050583657588,524,3,1,13.891050583657588,525,4,1,13.891050583657588,189]}}
  #|{"textrec":{"s":[14,400,0,"已删除连接"],"r":[0,1,13.891050583657588,360,1,1,13.891050583657588,519,2,1,13.891050583657588,520,3,1,13.891050583657588,366,4,1,13.891050583657588,367]}}
  #|{"textrec":{"s":[15,400,0,"此机器上暂无连接"],"r":[0,1,14.883268482490273,526,1,1,14.883268482490273,132,2,1,14.883268482490273,527,3,1,14.883268482490273,528,4,1,14.88326848249028,327,5,1,14.88326848249028,328,6,1,14.88326848249028,104,7,1,14.88326848249028,105]}}
  #|{"textrec":{"s":[14,400,0,"连接是用户访问 still.fail 的入口，例如一个 Slack app。每个连接运行在一台 station 上，并绑定一个模型。"],"r":[0,1,13.891050583657588,366,1,1,13.891050583657588,367,2,1,13.891050583657588,52,3,1,13.891050583657588,55,4,1,13.891050583657588,529,5,1,13.891050583657588,530,6,1,13.891050583657588,531,7,1,3.787109375,-1,8,1,7.1435546875,532,9,1,4.9013671875,61,10,1,3.30859375,533,11,1,3.390625,363,12,1,3.390625,363,13,1,3.80078125,534,14,1,4.607421874999986,535,15,1,7.4716796875,57,16,1,3.30859375,533,17,1,3.390625,363,18,1,3.787109375,-1,19,1,13.891050583657602,56,20,1,13.891050583657602,536,21,1,13.891050583657602,537,22,1,14.081712062256798,50,23,1,13.891050583657574,538,24,1,13.891050583657602,539,25,1,13.891050583657602,540,26,1,13.891050583657602,191,27,1,3.787109375,-1,28,1,8.7705078125,362,29,1,3.390625,363,30,1,7.57421875,57,31,1,7.68359375,364,32,1,7.451171875,365,33,1,3.787109375,-1,34,1,7.57421875,57,35,1,8.39453125,514,36,1,8.39453125,514,37,1,14.081712062256827,512,38,1,13.891050583657602,541,39,1,13.891050583657602,191,40,1,13.891050583657602,366,41,1,13.891050583657602,367,42,1,13.891050583657602,542,43,1,13.891050583657602,543,44,1,13.891050583657602,189,45,1,13.891050583657602,540,46,1,13.891050583657602,544,47,1,3.787109375,-1,48,1,7.1435546875,532,49,1,4.9013671875,61,50,1,7.57421875,57,51,1,4.935546875,61,52,1,3.30859375,533,53,1,8.12109375,545,54,1,8.018554687499943,60,55,1,3.787109375,-1,56,1,13.891050583657602,546,57,1,14.08171206225677,50,58,1,13.891050583657602,547,59,1,13.891050583657602,548,60,1,13.891050583657602,549,61,1,13.891050583657602,540,62,1,13.891050583657602,191,63,1,13.891050583657602,550,64,1,13.891050583657602,551,65,1,7.08171206225677,512]}}
  #|{"textrec":{"g":526,"r":[866,70,16,15,-1,-13,0]}}
  #|{"textrec":{"g":527,"r":[883,70,17,16,-1,-13,0]}}
  #|{"textrec":{"g":528,"r":[901,70,16,15,-1,-13,0]}}
  #|{"textrec":{"g":529,"r":[918,70,14,16,-1,-13,0]}}
  #|{"textrec":{"g":530,"r":[933,70,16,16,-1,-13,0]}}
  #|{"textrec":{"g":531,"r":[950,70,14,16,0,-13,0]}}
  #|{"textrec":{"g":532,"r":[965,70,9,11,-1,-9,0]}}
  #|{"textrec":{"g":533,"r":[975,70,5,13,-1,-12,0]}}
  #|{"textrec":{"g":534,"r":[981,70,4,5,0,-3,0]}}
  #|{"textrec":{"g":535,"r":[986,70,7,13,-1,-12,0]}}
  #|{"textrec":{"g":536,"r":[994,70,16,16,-1,-13,0]}}
  #|{"textrec":{"g":537,"r":[1011,70,13,13,0,-11,0]}}
  #|{"textrec":{"g":538,"r":[1025,70,15,16,-1,-13,0]}}
  #|{"textrec":{"g":539,"r":[1041,70,15,16,-1,-13,0]}}
  #|{"textrec":{"g":540,"r":[1057,70,15,4,-1,-7,0]}}
  #|{"textrec":{"g":541,"r":[1073,70,16,16,-1,-13,0]}}
  #|{"textrec":{"g":542,"r":[1090,70,16,15,-1,-12,0]}}
  #|{"textrec":{"g":543,"r":[1107,70,15,16,-1,-13,0]}}
  #|{"textrec":{"g":544,"r":[1123,70,14,16,0,-13,0]}}
  #|{"textrec":{"g":545,"r":[1138,70,10,11,-1,-9,0]}}
  #|{"textrec":{"g":546,"r":[1149,70,15,15,-1,-13,0]}}
  #|{"textrec":{"g":547,"r":[1165,70,15,16,-1,-13,0]}}
  #|{"textrec":{"g":548,"r":[1181,70,15,16,-1,-13,0]}}
  #|{"textrec":{"g":549,"r":[1197,70,15,16,-1,-13,0]}}
  #|{"textrec":{"g":550,"r":[1213,70,16,16,-1,-13,0]}}
  #|{"textrec":{"g":551,"r":[1230,70,15,15,-1,-12,0]}}
  #|{"textrec":{"g":524,"r":[1246,70,15,15,-1,-12,0]}}
  #|{"textrec":{"g":525,"r":[1262,70,15,16,-1,-13,0]}}
  #|{"textrec":{"s":[16,600,0,"添加连接"],"r":[0,1,15.875486381322958,552,1,1,15.875486381322958,553,2,1,15.875486381322958,192,3,1,15.875486381322958,193]}}
  #|{"textrec":{"s":[17,400,0,"取消"],"r":[0,1,16.851167315175097,554,1,1,16.851167315175097,555]}}
  #|{"textrec":{"g":554,"r":[1278,70,18,17,-1,-14,0]}}
  #|{"textrec":{"g":555,"r":[1297,70,18,18,-1,-15,0]}}
  #|{"textrec":{"g":552,"r":[1316,70,18,17,-1,-14,0]}}
  #|{"textrec":{"g":553,"r":[1335,70,17,17,-1,-14,0]}}
  #|{"textrec":{"s":[17,600,0,"添加连接"],"r":[0,1,16.851167315175097,556,1,1,16.851167315175097,557,2,1,16.851167315175097,558,3,1,16.851167315175097,559]}}
  #|{"textrec":{"m":[17,600,0],"r":[16.435546875,3.5859375,24,16.435546875,3.5859375,0]}}
  #|{"textrec":{"s":[11,400,0,"选择平台 · 1 / 5"],"r":[0,1,10.93579766536965,560,1,1,10.93579766536965,561,2,1,10.935797665369652,562,3,1,10.935797665369648,563,4,1,3.158203125,-1,5,1,5.2804038549793475,564,6,1,3.158203125,-1,7,1,5.1669921875,565,8,1,3.158203125,-1,9,1,3.416015625,566,10,1,3.158203125,-1,11,1,6.8642578125,567]}}
  #|{"textrec":{"s":[12,400,0,"在 Slack 的频道和私信中使用"],"r":[0,1,11.918287937743191,568,1,1,3.375,-1,2,1,7.646484375,205,3,1,3.03515625,206,4,1,6.6210937499999964,207,5,1,6.71484375,208,6,1,6.515625,209,7,1,3.375,-1,8,1,11.918287937743187,476,9,1,11.918287937743187,569,10,1,11.918287937743187,570,11,1,11.918287937743187,571,12,1,11.918287937743187,572,13,1,11.918287937743187,573,14,1,11.918287937743187,470,15,1,11.918287937743202,574,16,1,11.918287937743202,479]}}
  #|{"textrec":{"s":[15,400,0,"飞书"],"r":[0,1,14.883268482490273,575,1,1,14.883268482490273,576]}}
  #|{"textrec":{"s":[12,400,0,"在飞书的群和私聊中使用，含国际版 Lark"],"r":[0,1,11.918287937743191,568,1,1,11.918287937743191,577,2,1,11.918287937743195,578,3,1,11.918287937743187,476,4,1,11.918287937743187,579,5,1,11.918287937743187,571,6,1,11.918287937743187,572,7,1,11.918287937743187,580,8,1,11.918287937743187,470,9,1,11.918287937743187,574,10,1,11.918287937743187,479,11,1,12.081712062256798,473,12,1,11.918287937743202,581,13,1,11.918287937743202,582,14,1,11.918287937743202,583,15,1,11.918287937743202,584,16,1,3.375,-1,17,1,6.814453125,585,18,1,6.62109375,207,19,1,4.5703125,586,20,1,6.515625,209]}}
  #|{"textrec":{"s":[14,600,0,"下一步"],"r":[0,1,13.891050583657588,587,1,1,13.891050583657588,588,2,1,13.891050583657588,589]}}
  #|{"textrec":{"g":556,"r":[1353,70,19,18,-1,-15,0]}}
  #|{"textrec":{"g":557,"r":[1373,70,18,18,-1,-15,0]}}
  #|{"textrec":{"g":558,"r":[1392,70,18,18,-1,-15,0]}}
  #|{"textrec":{"g":559,"r":[1411,70,18,18,-1,-15,0]}}
  #|{"textrec":{"g":560,"r":[1430,70,13,13,-1,-10,0]}}
  #|{"textrec":{"g":561,"r":[1444,70,13,12,-1,-10,0]}}
  #|{"textrec":{"g":562,"r":[1458,70,13,13,-1,-10,0]}}
  #|{"textrec":{"g":563,"r":[1472,70,13,13,-1,-10,0]}}
  #|{"textrec":{"g":564,"r":[1486,70,5,4,0,-6,0]}}
  #|{"textrec":{"g":565,"r":[1492,70,6,10,-1,-9,0]}}
  #|{"textrec":{"g":566,"r":[1499,70,6,13,-1,-10,0]}}
  #|{"textrec":{"g":567,"r":[1506,70,9,11,-1,-9,0]}}
  #|{"textrec":{"g":568,"r":[1516,70,14,14,-1,-11,0]}}
  #|{"textrec":{"g":569,"r":[1531,70,14,14,-1,-11,0]}}
  #|{"textrec":{"g":570,"r":[1546,70,14,14,-1,-11,0]}}
  #|{"textrec":{"g":571,"r":[1561,70,13,14,-1,-11,0]}}
  #|{"textrec":{"g":572,"r":[1575,70,14,14,-1,-11,0]}}
  #|{"textrec":{"g":573,"r":[1590,70,14,14,-1,-11,0]}}
  #|{"textrec":{"g":574,"r":[1605,70,14,14,-1,-11,0]}}
  #|{"textrec":{"g":575,"r":[1620,70,16,16,-1,-13,0]}}
  #|{"textrec":{"g":576,"r":[1637,70,16,16,-1,-13,0]}}
  #|{"textrec":{"g":577,"r":[1654,70,14,12,-1,-10,0]}}
  #|{"textrec":{"g":578,"r":[1669,70,13,14,-1,-11,0]}}
  #|{"textrec":{"g":579,"r":[1683,70,14,14,-1,-11,0]}}
  #|{"textrec":{"g":580,"r":[1698,70,13,14,-1,-11,0]}}
  #|{"textrec":{"g":581,"r":[1712,70,14,14,-1,-11,0]}}
  #|{"textrec":{"g":582,"r":[1727,70,12,14,0,-11,0]}}
  #|{"textrec":{"g":583,"r":[1740,70,14,14,-1,-11,0]}}
  #|{"textrec":{"g":584,"r":[1755,70,14,14,-1,-11,0]}}
  #|{"textrec":{"g":585,"r":[1770,70,8,11,0,-10,0]}}
  #|{"textrec":{"g":586,"r":[1779,70,7,9,-1,-8,0]}}
  #|{"textrec":{"ib":["2a1e0543c4d4f8c0",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["ca3c0dc6df833a30",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"g":587,"r":[1787,70,15,15,-1,-12,0]}}
  #|{"textrec":{"g":588,"r":[1803,70,15,4,-1,-7,0]}}
  #|{"textrec":{"g":589,"r":[1819,70,15,16,-1,-13,0]}}
  #|{"textrec":{"ib":["e13e77444a4987cd",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"s":[17,400,0,"上一步"],"r":[0,1,16.851167315175097,590,1,1,16.851167315175097,591,2,1,16.851167315175097,592]}}
  #|{"textrec":{"s":[11,400,0,"选择 Slack 工作区 · 2 / 5"],"r":[0,1,10.93579766536965,560,1,1,10.93579766536965,561,2,1,3.158203125,-1,3,1,7.0737304687499964,229,4,1,2.8466796875,230,5,1,6.1337890625,231,6,1,6.2197265625,232,7,1,6.037109375,233,8,1,3.158203125,-1,9,1,10.935797665369648,593,10,1,10.935797665369648,594,11,1,10.935797665369648,595,12,1,3.158203125,-1,13,1,5.28040385497934,564,14,1,3.158203125,-1,15,1,6.703125,596,16,1,3.158203125,-1,17,1,3.416015625,566,18,1,3.158203125,-1,19,1,6.8642578125,567]}}
  #|{"textrec":{"s":[14,400,0,"有了 Slack 配置 token，still.fail 会替你在 Slack 中创建 app：名称、头像和权限都在这里填写，无需在 Slack 后台逐项配置。该 token 仅供你使用。"],"r":[0,1,13.891050583657588,597,1,1,13.891050583657588,598,2,1,3.787109375,-1,3,1,8.7705078125,362,4,1,3.390625,363,5,1,7.57421875,57,6,1,7.68359375,364,7,1,7.451171875,365,8,1,3.787109375,-1,9,1,13.891050583657588,599,10,1,13.891050583657588,600,11,1,3.787109375,-1,12,1,4.88427734375,61,13,1,8.06982421875,545,14,1,7.2802734375,365,15,1,7.6767578125,59,16,1,8.0185546875,60,17,1,12.681712062256821,50,18,1,7.1435546875,532,19,1,4.9013671875,61,20,1,3.30859375,533,21,1,3.390625,363,22,1,3.390625,363,23,1,3.80078125,534,24,1,4.607421875,535,25,1,7.4716796875,57,26,1,3.30859375,533,27,1,3.390625,363,28,1,3.787109375,-1,29,1,13.891050583657574,441,30,1,13.891050583657602,601,31,1,13.891050583657602,48,32,1,13.891050583657602,189,33,1,3.787109375,-1,34,1,8.7705078125,362,35,1,3.390625,363,36,1,7.57421875,57,37,1,7.68359375,364,38,1,7.451171875,365,39,1,3.787109375,-1,40,1,13.891050583657602,513,41,1,13.891050583657602,602,42,1,13.891050583657602,603,43,1,3.787109375,-1,44,1,7.57421875,57,45,1,8.39453125,514,46,1,8.39453125,514,47,1,14.081712062256827,604,48,1,13.891050583657602,605,49,1,13.891050583657602,606,50,1,14.081712062256827,607,51,1,13.891050583657602,608,52,1,13.891050583657602,609,53,1,13.891050583657602,610,54,1,13.891050583657602,611,55,1,13.891050583657602,612,56,1,13.891050583657602,613,57,1,13.891050583657545,189,58,1,13.891050583657602,614,59,1,13.891050583657602,615,60,1,13.891050583657602,616,61,1,13.891050583657602,617,62,1,14.08171206225677,50,63,1,13.891050583657602,618,64,1,13.891050583657602,515,65,1,13.891050583657602,189,66,1,3.787109375,-1,67,1,8.7705078125,362,68,1,3.390625,363,69,1,7.57421875,57,70,1,7.68359375,364,71,1,7.451171875,365,72,1,3.787109375,-1,73,1,13.891050583657602,619,74,1,13.891050583657602,544,75,1,13.891050583657602,620,76,1,13.891050583657602,621,77,1,13.891050583657602,599,78,1,13.891050583657602,600,79,1,14.08171206225677,512,80,1,13.891050583657602,622,81,1,3.787109375,-1,82,1,4.88427734375,61,83,1,8.06982421875,545,84,1,7.2802734375,365,85,1,7.6767578125,59,86,1,8.0185546875,60,87,1,3.787109375,-1,88,1,13.891050583657602,623,89,1,13.891050583657602,624,90,1,13.891050583657602,48,91,1,13.891050583657602,625,92,1,13.891050583657602,55,93,1,7.08171206225677,512]}}
  #|{"textrec":{"s":[14,600,0,"添加配置 token"],"r":[0,1,13.891050583657588,626,1,1,13.891050583657588,627,2,1,13.891050583657588,628,3,1,13.891050583657588,629,4,1,3.5793075561523438,-1,5,1,5.3377615213394165,630,6,1,8.341481804847717,631,7,1,7.765144348144531,632,8,1,7.906205654144287,633,9,1,8.406018495559692,634]}}
  #|{"textrec":{"s":[14,400,0,"不使用配置 token，在 Slack 中手动创建 app"],"r":[0,1,13.891050583657588,524,1,1,13.891050583657588,625,2,1,13.891050583657588,55,3,1,13.891050583657588,599,4,1,13.891050583657588,600,5,1,3.787109375,-1,6,1,4.88427734375,61,7,1,8.06982421875,545,8,1,7.2802734375,365,9,1,7.6767578125,59,10,1,8.0185546875,60,11,1,14.081712062256813,50,12,1,13.891050583657574,189,13,1,3.787109375,-1,14,1,8.7705078125,362,15,1,3.390625,363,16,1,7.57421875,57,17,1,7.68359375,364,18,1,7.451171875,365,19,1,3.787109375,-1,20,1,13.891050583657602,513,21,1,13.891050583657602,517,22,1,13.891050583657602,518,23,1,13.891050583657602,602,24,1,13.891050583657602,603,25,1,3.787109375,-1,26,1,7.57421875,57,27,1,8.39453125,514,28,1,8.39453125,514]}}
  #|{"textrec":{"g":590,"r":[1835,70,18,18,-1,-15,0]}}
  #|{"textrec":{"g":591,"r":[1854,70,18,4,-1,-8,0]}}
  #|{"textrec":{"g":592,"r":[1873,70,18,18,-1,-15,0]}}
  #|{"textrec":{"g":593,"r":[1892,70,13,11,-1,-9,0]}}
  #|{"textrec":{"g":594,"r":[1906,70,13,13,-1,-10,0]}}
  #|{"textrec":{"g":595,"r":[1920,70,12,12,0,-10,0]}}
  #|{"textrec":{"g":596,"r":[1933,70,8,10,-1,-9,0]}}
  #|{"textrec":{"g":597,"r":[1942,70,15,16,-1,-13,0]}}
  #|{"textrec":{"g":598,"r":[1958,70,13,15,0,-12,0]}}
  #|{"textrec":{"g":599,"r":[1972,70,16,15,-1,-12,0]}}
  #|{"textrec":{"g":600,"r":[1989,70,15,15,-1,-12,0]}}
  #|{"textrec":{"g":601,"r":[2005,70,16,16,-1,-13,0]}}
  #|{"textrec":{"g":602,"r":[2022,70,15,16,-1,-13,0]}}
  #|{"textrec":{"g":603,"r":[0,89,15,16,-1,-13,0]}}
  #|{"textrec":{"g":604,"r":[16,89,5,10,1,-10,0]}}
  #|{"textrec":{"g":605,"r":[22,89,14,16,-1,-13,0]}}
  #|{"textrec":{"g":606,"r":[37,89,16,16,-1,-13,0]}}
  #|{"textrec":{"g":607,"r":[54,89,6,6,0,-3,0]}}
  #|{"textrec":{"g":608,"r":[61,89,15,16,-1,-13,0]}}
  #|{"textrec":{"g":609,"r":[77,89,16,16,-1,-13,0]}}
  #|{"textrec":{"g":610,"r":[94,89,15,16,-1,-13,0]}}
  #|{"textrec":{"g":611,"r":[110,89,16,16,-1,-13,0]}}
  #|{"textrec":{"g":612,"r":[127,89,15,15,0,-12,0]}}
  #|{"textrec":{"g":613,"r":[143,89,15,16,-1,-13,0]}}
  #|{"textrec":{"g":614,"r":[159,89,16,16,-1,-13,0]}}
  #|{"textrec":{"g":615,"r":[176,89,15,14,-1,-12,0]}}
  #|{"textrec":{"g":616,"r":[192,89,16,16,-1,-13,0]}}
  #|{"textrec":{"g":617,"r":[209,89,15,15,-1,-12,0]}}
  #|{"textrec":{"g":618,"r":[225,89,15,15,-1,-12,0]}}
  #|{"textrec":{"g":619,"r":[241,89,15,16,-1,-13,0]}}
  #|{"textrec":{"g":620,"r":[257,89,16,15,-1,-12,0]}}
  #|{"textrec":{"g":621,"r":[274,89,16,15,-1,-12,0]}}
  #|{"textrec":{"g":622,"r":[291,89,16,16,-1,-13,0]}}
  #|{"textrec":{"g":623,"r":[308,89,16,16,-1,-13,0]}}
  #|{"textrec":{"g":624,"r":[325,89,16,16,-1,-13,0]}}
  #|{"textrec":{"g":625,"r":[342,89,16,16,-1,-13,0]}}
  #|{"textrec":{"g":626,"r":[359,89,16,16,-1,-13,0]}}
  #|{"textrec":{"g":627,"r":[376,89,15,16,-1,-13,0]}}
  #|{"textrec":{"g":628,"r":[392,89,16,15,-1,-12,0]}}
  #|{"textrec":{"g":629,"r":[409,89,15,15,-1,-12,0]}}
  #|{"textrec":{"g":630,"r":[425,89,7,13,-1,-11,0]}}
  #|{"textrec":{"g":631,"r":[433,89,10,11,-1,-9,0]}}
  #|{"textrec":{"g":632,"r":[444,89,9,13,0,-12,0]}}
  #|{"textrec":{"g":633,"r":[454,89,10,11,-1,-9,0]}}
  #|{"textrec":{"g":634,"r":[465,89,9,10,0,-9,0]}}
  #|{"textrec":{"s":[11,400,0,"添加配置 token · 1 / 5"],"r":[0,1,10.93579766536965,635,1,1,10.93579766536965,636,2,1,10.935797665369652,637,3,1,10.935797665369648,638,4,1,3.158203125,-1,5,1,4.020263671875,639,6,1,6.523193359375,640,7,1,5.90283203125,233,8,1,6.214355468749993,641,9,1,6.48291015625,642,10,1,3.158203125,-1,11,1,5.28040385497934,564,12,1,3.158203125,-1,13,1,5.1669921875,565,14,1,3.158203125,-1,15,1,3.416015625,566,16,1,3.158203125,-1,17,1,6.8642578125,567]}}
  #|{"textrec":{"s":[14,400,0,"1."],"r":[0,1,6.1728515625,182,1,1,3.8349609375,534]}}
  #|{"textrec":{"s":[14,400,0,"打开 api.slack.com/apps，用 bot 所在 Slack 工作区的账号登录。"],"r":[0,1,13.891050583657588,643,1,1,13.891050583657588,97,2,1,3.787109375,-1,3,1,7.57421875,57,4,1,8.39453125,514,5,1,3.30859375,533,6,1,4.005859375,534,7,1,7.177734375,532,8,1,3.390625,363,9,1,7.57421875,57,10,1,7.68359375,364,11,1,7.451171875,365,12,1,3.869140625,534,13,1,7.546875,364,14,1,8.12109375,545,15,1,12.03125,644,16,1,4.115234375,188,17,1,7.57421875,57,18,1,8.39453125,514,19,1,8.39453125,514,20,1,7.177734375,532,21,1,14.081712062256798,50,22,1,13.891050583657602,55,23,1,3.787109375,-1,24,1,8.44921875,645,25,1,8.12109375,545,26,1,4.935546875,61,27,1,3.787109375,-1,28,1,13.891050583657602,646,29,1,13.891050583657602,189,30,1,3.787109375,-1,31,1,8.7705078125,362,32,1,3.390625,363,33,1,7.57421875,57,34,1,7.68359375,364,35,1,7.451171875,365,36,1,3.787109375,-1,37,1,13.891050583657602,647,38,1,13.891050583657602,648,39,1,13.891050583657602,649,40,1,13.891050583657602,56,41,1,13.891050583657602,650,42,1,13.891050583657602,651,43,1,13.891050583657602,652,44,1,13.891050583657602,653,45,1,7.081712062256827,512]}}
  #|{"textrec":{"s":[14,400,0,"打开"],"r":[0,1,13.891050583657588,643,1,1,13.891050583657588,97]}}
  #|{"textrec":{"s":[14,400,0,"2."],"r":[0,1,8.1962890625,126,1,1,3.9033203125,534]}}
  #|{"textrec":{"s":[14,400,0,"滚动到页面底部的「Your App Configuration Tokens」，点击 Generate Token，选择此工作区。"],"r":[0,1,13.891050583657588,654,1,1,13.891050583657588,518,2,1,13.891050583657588,655,3,1,13.891050583657588,656,4,1,13.891050583657588,657,5,1,13.891050583657588,658,6,1,13.891050583657588,659,7,1,20.891050583657588,56,8,1,5.066147859922182,660,9,1,8.4423828125,661,10,1,7.5400390625,545,11,1,8.0185546875,662,12,1,5.181640625,663,13,1,3.787109375,-1,14,1,9.283203125,664,15,1,8.39453125,514,16,1,8.39453125,514,17,1,3.787109375,-1,18,1,9.87109375,665,19,1,8.12109375,545,20,1,8.0185546875,60,21,1,4.9150390625,535,22,1,3.30859375,533,23,1,8.380859375,58,24,1,8.0185546875,662,25,1,5.181640625,663,26,1,7.57421875,57,27,1,4.935546875,61,28,1,3.30859375,533,29,1,8.12109375,545,30,1,8.0185546875,60,31,1,3.787109375,-1,32,1,8.0390625,666,33,1,7.4375,545,34,1,7.2802734375,365,35,1,7.6767578125,59,36,1,8.0185546875,60,37,1,7.177734375,532,38,1,6.543774319066131,667,39,1,14.081712062256827,50,40,1,13.891050583657602,668,41,1,13.891050583657602,669,42,1,3.787109375,-1,43,1,10.3017578125,670,44,1,7.84765625,59,45,1,8.0185546875,60,46,1,7.84765625,59,47,1,5.181640625,663,48,1,7.57421875,57,49,1,4.88427734375,61,50,1,7.79638671875,59,51,1,3.787109375,-1,52,1,8.0390625,666,53,1,7.4375,545,54,1,7.2802734375,365,55,1,7.6767578125,59,56,1,8.0185546875,60,57,1,14.081712062256827,50,58,1,13.891050583657602,671,59,1,13.891050583657602,672,60,1,13.891050583657602,673,61,1,13.891050583657602,647,62,1,13.891050583657602,648,63,1,13.891050583657602,649,64,1,7.08171206225677,512]}}
  #|{"textrec":{"s":[14,400,0,"3."],"r":[0,1,8.3876953125,674,1,1,3.7666015625,534]}}
  #|{"textrec":{"s":[14,400,0,"将以 xoxe-1- 开头的 Refresh Token 粘贴到下方。still.fail 会自动续期，无需再手动处理。"],"r":[0,1,13.891050583657588,511,1,1,13.891050583657588,675,2,1,3.787109375,-1,3,1,7.0205078125,676,4,1,7.779296875,545,5,1,6.849609375,676,6,1,7.6767578125,59,7,1,6.453125,677,8,1,6.34375,182,9,1,6.453125,677,10,1,3.787109375,-1,11,1,13.891050583657588,97,12,1,13.891050583657588,608,13,1,13.891050583657588,56,14,1,3.787109375000014,-1,15,1,8.8935546875,678,16,1,7.7451171875,59,17,1,4.9150390625,535,18,1,5.0791015625,663,19,1,7.7451171875,59,20,1,7.177734375,532,21,1,8.0869140625,679,22,1,3.787109375,-1,23,1,8.0390625,666,24,1,7.4375,545,25,1,7.2802734375,365,26,1,7.6767578125,59,27,1,8.0185546875,60,28,1,3.787109375,-1,29,1,13.891050583657602,680,30,1,13.891050583657602,681,31,1,13.891050583657602,655,32,1,13.891050583657602,682,33,1,13.891050583657602,443,34,1,14.081712062256827,512,35,1,7.1435546875,532,36,1,4.9013671875,61,37,1,3.30859375,533,38,1,3.390625,363,39,1,3.390625,363,40,1,3.80078125,534,41,1,4.607421875,535,42,1,7.4716796875,57,43,1,3.30859375,533,44,1,3.390625,363,45,1,3.787109375,-1,46,1,13.891050583657602,441,47,1,13.891050583657602,683,48,1,13.891050583657602,518,49,1,13.891050583657602,684,50,1,13.891050583657602,685,51,1,14.081712062256827,50,52,1,13.891050583657602,618,53,1,13.891050583657602,515,54,1,13.891050583657602,686,55,1,13.891050583657602,517,56,1,13.891050583657602,518,57,1,13.891050583657545,687,58,1,13.891050583657602,688,59,1,7.08171206225677,512]}}
  #|{"textrec":{"s":[14,600,0,"添加"],"r":[0,1,13.891050583657588,626,1,1,13.891050583657588,627]}}
  #|{"textrec":{"g":635,"r":[475,89,13,13,-1,-10,0]}}
  #|{"textrec":{"g":636,"r":[489,89,12,13,-1,-10,0]}}
  #|{"textrec":{"g":637,"r":[502,89,13,13,-1,-10,0]}}
  #|{"textrec":{"g":638,"r":[516,89,13,12,-1,-10,0]}}
  #|{"textrec":{"g":639,"r":[530,89,6,11,-1,-9,0]}}
  #|{"textrec":{"g":640,"r":[537,89,8,9,-1,-7,0]}}
  #|{"textrec":{"g":641,"r":[546,89,8,9,-1,-7,0]}}
  #|{"textrec":{"g":642,"r":[555,89,8,8,-1,-7,0]}}
  #|{"textrec":{"g":643,"r":[564,89,15,16,-1,-13,0]}}
  #|{"textrec":{"g":644,"r":[580,89,13,10,0,-9,0]}}
  #|{"textrec":{"g":645,"r":[594,89,9,14,0,-12,0]}}
  #|{"textrec":{"g":646,"r":[604,89,16,16,-1,-13,0]}}
  #|{"textrec":{"g":647,"r":[621,89,15,14,-1,-12,0]}}
  #|{"textrec":{"g":648,"r":[637,89,15,16,-1,-13,0]}}
  #|{"textrec":{"g":649,"r":[653,89,14,14,0,-12,0]}}
  #|{"textrec":{"g":650,"r":[668,89,16,16,-1,-13,0]}}
  #|{"textrec":{"g":651,"r":[685,89,15,15,-1,-12,0]}}
  #|{"textrec":{"g":652,"r":[701,89,16,15,-1,-13,0]}}
  #|{"textrec":{"g":653,"r":[718,89,15,15,-1,-12,0]}}
  #|{"textrec":{"g":654,"r":[734,89,16,16,-1,-13,0]}}
  #|{"textrec":{"g":655,"r":[751,89,15,16,-1,-13,0]}}
  #|{"textrec":{"g":656,"r":[767,89,15,15,-1,-12,0]}}
  #|{"textrec":{"g":657,"r":[783,89,15,15,-1,-12,0]}}
  #|{"textrec":{"g":658,"r":[799,89,15,16,-1,-13,0]}}
  #|{"textrec":{"g":659,"r":[815,89,15,16,-1,-13,0]}}
  #|{"textrec":{"g":660,"r":[831,89,7,12,-1.333333333333333,-13,0]}}
  #|{"textrec":{"g":661,"r":[839,89,11,12,-1,-11,0]}}
  #|{"textrec":{"g":662,"r":[851,89,9,11,0,-9,0]}}
  #|{"textrec":{"g":663,"r":[861,89,6,10,0,-9,0]}}
  #|{"textrec":{"g":664,"r":[868,89,11,12,-1,-11,0]}}
  #|{"textrec":{"g":665,"r":[880,89,12,14,-1,-12,0]}}
  #|{"textrec":{"g":666,"r":[893,89,11,12,-1,-11,0]}}
  #|{"textrec":{"g":667,"r":[905,89,7,11,-1,-8,0]}}
  #|{"textrec":{"g":668,"r":[913,89,15,16,-1,-13,0]}}
  #|{"textrec":{"g":669,"r":[929,89,15,16,-1,-13,0]}}
  #|{"textrec":{"g":670,"r":[945,89,12,14,-1,-12,0]}}
  #|{"textrec":{"g":671,"r":[958,89,16,16,-1,-13,0]}}
  #|{"textrec":{"g":672,"r":[975,89,16,16,-1,-13,0]}}
  #|{"textrec":{"g":673,"r":[992,89,16,14,-1,-12,0]}}
  #|{"textrec":{"g":674,"r":[1009,89,10,14,-1,-12,0]}}
  #|{"textrec":{"g":675,"r":[1020,89,15,16,0,-13,0]}}
  #|{"textrec":{"g":676,"r":[1036,89,9,10,-1,-9,0]}}
  #|{"textrec":{"g":677,"r":[1046,89,7,4,0,-6,0]}}
  #|{"textrec":{"g":678,"r":[1054,89,10,12,0,-11,0]}}
  #|{"textrec":{"g":679,"r":[1065,89,9,13,0,-12,0]}}
  #|{"textrec":{"g":680,"r":[1075,89,15,16,-1,-13,0]}}
  #|{"textrec":{"g":681,"r":[1091,89,15,16,-1,-13,0]}}
  #|{"textrec":{"g":682,"r":[1107,89,15,15,-1,-12,0]}}
  #|{"textrec":{"g":683,"r":[1123,89,12,16,1,-13,0]}}
  #|{"textrec":{"g":684,"r":[1136,89,16,16,-1,-13,0]}}
  #|{"textrec":{"g":685,"r":[1153,89,15,16,-1,-13,0]}}
  #|{"textrec":{"g":686,"r":[1169,89,15,15,-1,-12,0]}}
  #|{"textrec":{"g":687,"r":[1185,89,16,16,-1,-13,0]}}
  #|{"textrec":{"g":688,"r":[1202,89,16,14,-1,-12,0]}}
  #|{"textrec":{"s":[15,400,0,"xoxe-1-…"],"r":[0,1,7.44873046875,503,1,1,8.26171875,88,2,1,7.265625,503,3,1,8.15185546875,95,4,1,6.8408203125,211,5,1,6.7236328125,165,6,1,6.8408203125,211,7,1,11.8359375,504]}}
  #|{"textrec":{"g":165,"r":[1219,89,8,13,-1,-12,0]}}
