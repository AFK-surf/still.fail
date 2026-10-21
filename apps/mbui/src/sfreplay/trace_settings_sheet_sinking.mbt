// e2e/traces/settings-sheet-sinking.trace, made by scripts/trace.py from 02-settings_sheet_sinking.log: not edited by hand.

///|
/// What the app and its core said in the run, a line each.
pub let trace_settings_sheet_sinking : String =
  #|{"env":{"MBUI_CLOUD":"http://127.0.0.1:18787","MBUI_CORE_ACCOUNT":"{\"sub\":\"alice\",\"email\":\"alice@example.test\",\"name\":\"Name of alice\",\"picture\":\"\",\"access\":\"-\",\"refresh\":\"-\",\"accessExpires\":1792551401}"}}
  #|{"out":{"id":1,"call":"client.device","params":{"client":"still.fail mbui","app":"desktop","userAgent":"Macintosh; Mac OS X"}},"w":1792551103924.058}
  #|{"in":{"id":1,"ok":null},"w":1792551104009.766}
  #|{"out":{"id":2,"subscribe":{"topic":"accounts"},"keyed":true},"w":1792551104009.792}
  #|{"out":{"id":3,"subscribe":{"topic":"prefs"},"keyed":true},"w":1792551104009.802}
  #|{"step":"# written by scripts/rerecord.sh from its test (src/sfreplay/emit.mbt): not edited by hand","w":1792551104011.185}
  #|{"step":"timeout 90000","w":1792551104011.191}
  #|{"step":"answered client.device","w":1792551104011.193}
  #|{"step":"answered client.focus","w":1792551104036.507}
  #|{"in":{"id":2,"value":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""}]},"w":1792551104102.855}
  #|{"in":{"id":3,"value":{"onlyMine":false,"onlyWatching":false,"onlyDecisions":false,"listFilter":{},"appearance":"system","rowPicture":"auto","absoluteTime":false,"lang":"zh","keys":{},"lastChat":{},"openChat":{"01M5E5Y4HC3WQXMJPK0WSETJHC":{"station":"01M5E5Y4HC3WQXMJPK0WSETJHC/1696e83c4f5fdc08a7928a36719e589a2ff2d83aaa4f0858a8e37bf88aa2ad7f","key":"ember:c-6e6e44657d"}},"chatTabs":{},"dropFiles":{},"driveViews":{},"resume":{},"stationUpdatesDismissed":{},"device":{"app":"desktop","phone":false,"handoff":false},"reader":{"size":18,"line":1.7,"margin":22,"face":"sans","indent":true,"paper":"follow"},"rails":{},"bars":{"sets":[["chats","files","profiles","stations"],["decisions","usage","connects","archive"]],"current":0},"barsBy":{},"fonts":{},"faces":{"ui":{"id":"","name":"","mono":false,"family":"","files":[],"bytes":0},"text":{"id":"","name":"","mono":false,"family":"","files":[],"bytes":0},"code":{"id":"","name":"","mono":true,"family":"","files":[],"bytes":0},"list":[{"id":"inter","name":"Inter","mono":false,"family":"SF Inter","css":"http://127.0.0.1:18787/releases/fonts/inter/4.001/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/inter/4.001/var.ttf.gz","bytes":457818,"sha256":"29160a80ff49ddcab2c97711247e08b1fab27a484a329ce8b813d820dc559031"}],"preview":"http://127.0.0.1:18787/releases/fonts/inter/4.001/preview-194fa287.ttf","bytes":457818},{"id":"noto-sans-sc","name":"思源黑体","mono":false,"family":"SF Noto Sans SC","css":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/var.ttf.gz","bytes":11276563,"sha256":"a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da"}],"preview":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/preview-f0494178.ttf","bytes":11276563},{"id":"noto-serif-sc","name":"思源宋体","mono":false,"family":"SF Noto Serif SC","css":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/var.ttf.gz","bytes":15454579,"sha256":"050080d9255a86808f2945bffac582b31ef32bc36411ce29563b4961670c66f9"}],"preview":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/preview-001bbedf.ttf","bytes":15454579},{"id":"lxgw-wenkai","name":"霞鹜文楷","mono":false,"family":"SF LXGW WenKai","css":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/font.css","files":[{"weight":400,"url":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/400.ttf.gz","bytes":12904482,"sha256":"2d73eea94ad808999d90c0000c239a84a33b09d4bc6ab6c5b8bbf1eda8a7fc8b"},{"weight":500,"url":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/500.ttf.gz","bytes":13272430,"sha256":"f4b8a34d1f838fe411540cb7c97b1c384ac9738a876c4104500bc42508b2312a"}],"preview":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/preview-d3505af4.ttf","bytes":26176912},{"id":"jetbrains-mono","name":"JetBrains Mono","mono":true,"family":"SF JetBrains Mono","css":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/var.ttf.gz","bytes":90579,"sha256":"48715a42ec242c21e9f02692891e147d022299a52e48d5e413e1a942193ffeda"}],"preview":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/preview-ee73078f.ttf","bytes":90579},{"id":"fira-code","name":"Fira Code","mono":true,"family":"SF Fira Code","css":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/var.ttf.gz","bytes":137151,"sha256":"9335b082b3c7850d98a64b584f3417f65355f3471278bb5eeb8c6c0e8657aeeb"}],"preview":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/preview-555be27a.ttf","bytes":137151},{"id":"maple-mono","name":"Maple Mono","mono":true,"family":"SF Maple Mono CN","css":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/font.css","files":[{"weight":400,"url":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/400.ttf.gz","bytes":8352545,"sha256":"0fcc5139bfd5ab14ff989bb7dfd5236d0cafc10e60b9828569e6883613ab4085"},{"weight":600,"url":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/600.ttf.gz","bytes":8438132,"sha256":"96ed7ae26ee7c50b02b2d2b2bc0f1a0cbabe45ae5d6e6abf6678e2177c415677"}],"preview":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/preview-cffdf246.ttf","bytes":16790677}]}}},"w":1792551104102.897}
  #|{"out":{"id":4,"subscribe":{"topic":"workspaces"},"keyed":true},"w":1792551104102.946}
  #|{"out":{"id":5,"subscribe":{"topic":"status"},"keyed":true},"w":1792551104102.959}
  #|{"in":{"id":4,"value":[{"account":{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""},"workspaces":[{"id":"01M5E5Y4HC3WQXMJPK0WSETJHC","name":"Dev","role":"owner","created_at":1792551096,"stations":1,"members":1,"relays":[],"time":{"created_at":{"past":true,"at":1792551096000,"ago":"刚刚","full":"10/21 10:51:36","until":"1 分钟内"}}}],"invitations":[],"relay_url":"http://127.0.0.1:18740","loaded":true,"beta":true}]},"w":1792551104122.445}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792551104122.459}
  #|{"out":{"id":6,"subscribe":{"topic":"lock","workspace":"01M5E5Y4HC3WQXMJPK0WSETJHC"},"keyed":true},"w":1792551104122.492}
  #|{"out":{"id":7,"subscribe":{"topic":"chats","scope":"01M5E5Y4HC3WQXMJPK0WSETJHC","mine":false},"keyed":true},"w":1792551104122.508}
  #|{"out":{"id":8,"subscribe":{"topic":"changelog"},"keyed":true},"w":1792551104122.516}
  #|{"out":{"id":9,"subscribe":{"topic":"workspaceMarks","workspace":"01M5E5Y4HC3WQXMJPK0WSETJHC"},"keyed":true},"w":1792551104122.643}
  #|{"out":{"id":10,"subscribe":{"topic":"status","workspace":"01M5E5Y4HC3WQXMJPK0WSETJHC"},"keyed":true},"w":1792551104122.678}
  #|{"out":{"id":11,"call":"client.focus","params":{"visible":true,"focused":true,"workspace":"01M5E5Y4HC3WQXMJPK0WSETJHC"}},"w":1792551104129.722}
  #|{"out":{"id":12,"subscribe":{"topic":"notify"},"keyed":true},"w":1792551104129.734}
  #|{"out":{"id":13,"subscribe":{"topic":"notify","workspace":"01M5E5Y4HC3WQXMJPK0WSETJHC"},"keyed":true},"w":1792551104129.743}
  #|{"in":{"id":6,"value":{"available":true,"locked":false,"notice":true,"role":"owner","manages":true,"owner":true,"canSign":true,"signs":false,"me":{"device":"f21c6a811b2c34d95d0238d9d6c5c19ab50e201b740f6ef95300d85dc242c51e","code":"BRR-UUF","kind":"app","confirmed":false,"waiting":false,"asked":false},"signers":0,"members":[],"stations":[{"id":"1696e83c4f5fdc08a7928a36719e589a2ff2d83aaa4f0858a8e37bf88aa2ad7f","name":"studio","version":"0.1.0","online":true,"protected":false}],"protected":0,"requests":[],"renew":[],"attention":0}},"w":1792551104136.196}
  #|{"in":{"id":7,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"stations":[{"station":"01M5E5Y4HC3WQXMJPK0WSETJHC/1696e83c4f5fdc08a7928a36719e589a2ff2d83aaa4f0858a8e37bf88aa2ad7f","id":"1696e83c4f5fdc08a7928a36719e589a2ff2d83aaa4f0858a8e37bf88aa2ad7f","name":"studio","state":"online"}],"loading":false,"days":[{"daysAgo":0,"at":1792551103147,"label":"今天","items":[{"id":"ember:c-6e6e44657d","session":"ember:c-6e6e44657d","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","agents":[{"key":"ember:c-6e6e44657d","runtime":"claude","process":"warm","pending":0,"lastTurn":{"id":"36256e3e-c73e-48b8-bdce-70d223d9a6fd","kind":"nudge","outcome":"completed","startedAt":1792551103143,"endedAt":1792551103146},"agentText":"默认模型","mark":"failed","statusText":"出错：意外停止","badgeText":"失败，需要处理"}],"last":{"seq":4,"authorKind":"ember","author":"ember","authorName":"still.fail","text":"⚠️ 本轮 agent 未在对话中回复，以下是它最后输出的文字，由 station 代为转发（并非它发布的消息）；回复即可继续：\n\n> Your turn ended without a state, so nobody knows where the chat stands. Only a real unresolved need requires need_human. A factual a","createdAt":1792551103147,"by":{"kind":"ember","name":"still.fail","mine":false,"label":"still.fail"},"preview":"⚠️ 本轮 agent 未在对话中回复，以下是它最后输出的文字，由 station 代为转发（并非它发布的消息）；回复即可继续： Your turn ended without a state, so nobody knows where the chat stands. Only a real unresolved need requires need_human. A factual a","time":{"createdAt":{"at":1792551103147,"ago":"刚刚","full":"10/21 10:51:43","until":"1 分钟内","past":true}}},"unread":false,"mine":true,"lastActiveAt":1792551103147,"station":"01M5E5Y4HC3WQXMJPK0WSETJHC/1696e83c4f5fdc08a7928a36719e589a2ff2d83aaa4f0858a8e37bf88aa2ad7f","stationName":"studio","state":"failed","time":{"lastActiveAt":{"at":1792551103147,"ago":"刚刚","full":"10/21 10:51:43","until":"1 分钟内","past":true}},"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"peopleText":"你 发起","clientKey":"new:chat-2d8a8c87afd522469d","pinned":false,"stateText":"出错：意外停止","tone":"alert"}]}],"trouble":null,"members":1,"leading":"agents","glyph":{"online":1,"dim":0,"connecting":0,"failing":0,"working":0,"summary":"studio","label":"1 台 station，1 台在线"},"note":{"reading":false,"text":null,"failing":[],"empty":false}}},"w":1792551104136.229}
  #|{"in":{"id":8,"value":{"app":"desktop","tabs":[{"part":"desktop","label":"桌面","days":[]},{"part":"web","label":"网页","days":[]},{"part":"android","label":"安卓","days":[]},{"part":"station","label":"Station","days":[]},{"part":"cloud","label":"云端","days":[]}],"loading":false}},"w":1792551104136.249}
  #|{"in":{"id":9,"value":{"workspaces":{"01M5E5Y4HC3WQXMJPK0WSETJHC":{"alert":1,"unread":0,"tone":"alert","label":"1 个出错","chat":{"station":"01M5E5Y4HC3WQXMJPK0WSETJHC/1696e83c4f5fdc08a7928a36719e589a2ff2d83aaa4f0858a8e37bf88aa2ad7f","key":"ember:c-6e6e44657d"},"badge":0,"items":[{"kind":"alert","workspace":"01M5E5Y4HC3WQXMJPK0WSETJHC","workspaceName":"Dev","station":"01M5E5Y4HC3WQXMJPK0WSETJHC/1696e83c4f5fdc08a7928a36719e589a2ff2d83aaa4f0858a8e37bf88aa2ad7f","stationName":"studio","session":"ember:c-6e6e44657d","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","text":"出错：意外停止","seen":true,"at":1792551103147}],"mineTone":"alert"}},"badge":0,"badgeCounts":"attention","badgeKinds":{"on":true,"wait":true,"failed":true,"done":false,"message":false}}},"w":1792551104136.26}
  #|{"in":{"id":10,"value":{"items":[]}},"w":1792551104136.269}
  #|{"in":{"id":11,"ok":null},"w":1792551104136.271}
  #|{"in":{"id":12,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792551104136.282}
  #|{"in":{"id":13,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792551104136.287}
  #|{"out":{"id":14,"subscribe":{"topic":"longJobs","scope":"01M5E5Y4HC3WQXMJPK0WSETJHC"},"keyed":true},"w":1792551104136.318}
  #|{"out":{"id":15,"call":"notify.permission","params":{"state":"unknown"}},"w":1792551104138.508}
  #|{"in":{"id":14,"value":{"groups":[]}},"w":1792551104152.858}
  #|{"in":{"id":15,"ok":null},"w":1792551104152.865}
  #|{"step":"answered notify.permission","w":1792551104153.113}
  #|{"step":"tap icon:settings","w":1792551104169.75}
  #|{"step":"tap icon:settings","acted":true,"w":1792551104169.763}
  #|{"out":{"id":16,"subscribe":{"topic":"workspace","workspace":"01M5E5Y4HC3WQXMJPK0WSETJHC"},"keyed":true},"w":1792551104186.316}
  #|{"out":{"id":17,"subscribe":{"topic":"stations","scope":"01M5E5Y4HC3WQXMJPK0WSETJHC"},"keyed":true},"w":1792551104186.331}
  #|{"out":{"id":18,"subscribe":{"topic":"connects","scope":"01M5E5Y4HC3WQXMJPK0WSETJHC","mine":false},"keyed":true},"w":1792551104186.337}
  #|{"out":{"id":19,"subscribe":{"topic":"vaults","workspace":"01M5E5Y4HC3WQXMJPK0WSETJHC"},"keyed":true},"w":1792551104186.343}
  #|{"out":{"id":20,"subscribe":{"topic":"doing"},"keyed":true},"w":1792551104188.984}
  #|{"step":"wait 300","w":1792551104189.899}
  #|{"in":{"id":16,"value":{"id":"01M5E5Y4HC3WQXMJPK0WSETJHC","name":"Dev","role":"owner","created_at":1792551096,"members":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":"https://example.test/p.png","role":"owner","added_at":1792551096}],"stations":[{"id":"1696e83c4f5fdc08a7928a36719e589a2ff2d83aaa4f0858a8e37bf88aa2ad7f","name":"studio","emoji":null,"icon":null,"enrolled_at":1792551097,"enrolled_by":"alice","last_seen":1792551100,"version":"0.1.0","time":{"last_seen":{"past":true,"at":1792551100000,"ago":"刚刚","full":"10/21 10:51:40","until":"1 分钟内"}}}],"invitations":[],"added":[],"relays":[],"lock":null,"lock_requests":0,"time":{"created_at":{"past":true,"at":1792551096000,"ago":"刚刚","full":"10/21 10:51:36","until":"1 分钟内"}}}},"w":1792551104202.858}
  #|{"in":{"id":17,"value":[{"station":"01M5E5Y4HC3WQXMJPK0WSETJHC/1696e83c4f5fdc08a7928a36719e589a2ff2d83aaa4f0858a8e37bf88aa2ad7f","id":"1696e83c4f5fdc08a7928a36719e589a2ff2d83aaa4f0858a8e37bf88aa2ad7f","name":"studio","summary":"空闲 · Apple M4 · 16 GB · macOS 27.0.1","face":"idle","line":"Apple M4","online":true,"reconnecting":false,"lastSeen":1792551100,"version":"0.1.0","link":{"state":"online"},"runtimes":[{"runtime":"claude","models":["claude-sonnet-5-5"]}],"models":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792551100879,"time":{"checkedAt":{"at":1792551100879,"ago":"刚刚","full":"10/21 10:51:40","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"overview":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null,"summaryText":"最近 7 天检查了 0 个 chat","changeText":null}},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","email":"alice@example.test","name":"Name of alice","sub":"alice","role":"owner","workspace":"01M5E5Y4HC3WQXMJPK0WSETJHC","device":"f21c6a811b2c34d95d0238d9d6c5c19ab50e201b740f6ef95300d85dc242c51e"},"connects":[],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792551100756,"time":{"checkedAt":{"at":1792551100756,"ago":"刚刚","full":"10/21 10:51:40","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792551100879,"time":{"checkedAt":{"at":1792551100879,"ago":"刚刚","full":"10/21 10:51:40","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]}],"processes":[],"counts":{"sessions":1,"running":0,"warm":1},"mesh":{"state":"running","origin":"http://127.0.0.1:18787","station":"1696e83c4f5fdc08a7928a36719e589a2ff2d83aaa4f0858a8e37bf88aa2ad7f","workspace":"Dev","workspaceId":"01M5E5Y4HC3WQXMJPK0WSETJHC","name":"studio"},"slackUsers":[],"slackTeams":[],"slackApps":[],"feishuRegistrations":[],"disk":{"freeBytes":44857667584,"totalBytes":245107195904},"logins":[],"machineLogins":[],"sharing":true,"consoleSignIn":true,"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"google","name":"Google Gemini","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xai","name":"xAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"mistral","name":"Mistral","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"deepseek","name":"DeepSeek","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen","name":"Qwen","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai","name":"Kimi","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai","name":"Z.ai","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax","name":"MiniMax","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ant-ling","name":"Ant Ling","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"jev","name":"Jev","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen-cn","name":"Qwen (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"openrouter","name":"OpenRouter","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"opencode","name":"OpenCode Zen","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"groq","name":"Groq","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"together","name":"Together AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"fireworks","name":"Fireworks","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cerebras","name":"Cerebras","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"huggingface","name":"Hugging Face","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"nvidia","name":"NVIDIA","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"baseten","name":"Baseten","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ollama","name":"Ollama","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"custom","name":"Custom","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""}],"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792551098325},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.305","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792551098325},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-news/apps/e2e-local/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792551098325},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-news/apps/e2e-local/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792551098325},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","latest":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-news/apps/e2e-local/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792551098325},{"id":"cursor","name":"Cursor","installed":false,"latest":"1.0.40","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792551098325},{"id":"devin","name":"Devin","installed":true,"version":"3000.11.92","latest":"3000.11.92","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-news/apps/e2e-local/ember/station/test/fake/devin，不是用 Devin 的安装脚本装的，需在该机器上手动更新","state":"idle","checkedAt":1792551098325}],"processesText":"没有运行中的 agent 进程","agentEnv":[],"drive":{"roots":[],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false}},"betaOffered":false,"host":{"hostname":"3720-Mac-mini-1","os":"macOS 27.0.1","arch":"arm64","cpus":10,"cpuModel":"Apple M4","load":0.16,"cpuBusy":0.11,"uptimeSec":30464,"memory":{"totalBytes":17179869184,"usedBytes":9499770880,"swapUsedBytes":300742083},"disk":{"path":"/tmp/mbe2e-C/data","totalBytes":245107195904,"freeBytes":44859523072},"emberRssBytes":159840080,"checkedAt":1792551102530,"summary":"10 核 · 16 GB","line":"macOS 27.0.1 · 10 核 · 16 GB · 已运行 0 天","facts":["3720-Mac-mini-1","macOS 27.0.1","arm64 · 10 核","已运行 8 小时"],"meters":[{"label":"CPU","short":"CPU","percent":11,"left":89,"level":"ok","value":"11%","remaining":"空闲 89%","big":"89","unit":"%","title":"CPU 空闲","total":"负载 1.6","note":"负载 1.6 · Apple M4"},{"label":"内存","short":"内存","percent":55,"left":45,"level":"ok","value":"8.8 GB / 16.0 GB","remaining":"剩 7.2 G","big":"7.2","unit":"GB","title":"内存剩","total":"共 16 GB","note":"swap 0.3 GB"},{"label":"磁盘","short":"磁盘","percent":82,"left":18,"level":"amber","value":"剩余 41.8 GB / 228 GB","remaining":"剩 41.8 G","big":"41.8","unit":"GB","title":"磁盘剩","total":"共 228 GB"}],"identity":"Apple M4 · 16 GB · macOS 27.0.1","details":[{"label":"主机名","value":"3720-Mac-mini-1"},{"label":"芯片","value":"Apple M4 · 10 核 · arm64"},{"label":"已运行","value":"8 小时"},{"label":"still.fail","value":"进程占用 152 MB"}],"usage":"内存 8.8 GB / 16.0 GB · 磁盘 剩余 41.8 GB / 228 GB","emberText":"still.fail 152 MB"},"way":{"path":"直连","via":"direct"},"time":{"lastSeen":{"at":1792551100000,"ago":"刚刚","full":"10/21 10:51:40","until":"1 分钟内","past":true}},"joined":false}]},"w":1792551104202.972}
  #|{"in":{"id":18,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"items":[],"wait":{"reading":false,"text":null,"failing":[],"empty":true}}},"w":1792551104203.048}
  #|{"in":{"id":19,"value":{"available":true,"locked":false,"canSign":false,"setUp":false,"vaults":[{"id":"plain","name":"个人","owner":"alice","ownerName":"Name of alice","mine":true,"members":[{"sub":"alice","name":"Name of alice"}],"station":"1696e83c4f5fdc08a7928a36719e589a2ff2d83aaa4f0858a8e37bf88aa2ad7f","stationName":"studio","items":0,"devices":0,"open":true,"keyed":true,"missing":0,"recoverable":false}],"requests":[],"refused":[{"station":"1696e83c4f5fdc08a7928a36719e589a2ff2d83aaa4f0858a8e37bf88aa2ad7f","name":"studio","code":"vault_needs_lock"}],"plain":true}},"w":1792551104203.057}
  #|{"in":{"id":20,"value":{"doing":[]}},"w":1792551104203.062}
  #|{"in":{"id":17,"delta":[{"path":[0,"overview","disk","freeBytes"],"set":44857602048}]},"w":1792551104319.518}
  #|{"step":"now tap =Station","w":1792551104503.877}
  #|{"step":"now tap =Station","acted":true,"w":1792551104503.944}
  #|{"step":"wait 300","w":1792551104533.521}
  #|{"step":"now tap =studio","w":1792551104837.193}
  #|{"step":"now tap =studio","acted":true,"w":1792551104837.255}
  #|{"out":{"id":21,"subscribe":{"topic":"screens","station":"01M5E5Y4HC3WQXMJPK0WSETJHC/1696e83c4f5fdc08a7928a36719e589a2ff2d83aaa4f0858a8e37bf88aa2ad7f"},"keyed":true},"w":1792551104855.267}
  #|{"out":{"id":22,"subscribe":{"topic":"memberships","station":"01M5E5Y4HC3WQXMJPK0WSETJHC/1696e83c4f5fdc08a7928a36719e589a2ff2d83aaa4f0858a8e37bf88aa2ad7f"},"keyed":true},"w":1792551104855.371}
  #|{"out":{"id":23,"subscribe":{"topic":"adbShare"},"keyed":true},"w":1792551104865.944}
  #|{"step":"wait 300","w":1792551104868.24}
  #|{"in":{"id":21,"value":{"screens":[{"id":"desktop","kind":"desktop","title":"3720-Mac-mini-1","width":0,"height":0,"viewers":[],"controlledBy":[],"access":{"capture":false,"control":false,"message":"此 station 版本不含屏幕助手（stillfail-screen），请更新 station"},"clipboard":[],"drop":{"folder":"/tmp/mbe2e-C/home","reveal":true},"peek":false,"line":"此 station 版本不含屏幕助手（stillfail-screen），请更新 station","link":"/w/01M5E5Y4HC3WQXMJPK0WSETJHC/s/1696e83c4f5fdc08a7928a36719e589a2ff2d83aaa4f0858a8e37bf88aa2ad7f/screen/desktop"}],"outdated":false,"control":true,"known":true}},"w":1792551104869.547}
  #|{"in":{"id":22,"value":{"manages":true,"loading":true,"canJoin":false,"workspaces":[]}},"w":1792551104869.592}
  #|{"in":{"id":22,"value":{"manages":true,"loading":false,"canJoin":true,"workspaces":[{"workspace":"01M5E5Y4HC3WQXMJPK0WSETJHC","name":"Dev","stationName":"studio","home":true,"here":true,"line":"主 workspace"}]}},"w":1792551104869.605}
  #|{"in":{"id":23,"value":{"sharing":false,"phase":"off","tunnels":0}},"w":1792551104869.618}
  #|{"step":"now tap icon:more","w":1792551105187.238}
  #|{"step":"now tap icon:more","acted":true,"w":1792551105187.31}
  #|{"step":"tap 重命名","w":1792551105210.073}
  #|{"step":"tap 重命名","acted":true,"w":1792551105287.592}
  #|{"step":"clear","w":1792551105304.178}
  #|{"step":"clear","acted":true,"w":1792551105304.31}
  #|{"step":"type e2e-not-082939","w":1792551105333.643}
  #|{"step":"type e2e-not-082939","acted":true,"w":1792551105333.685}
  #|{"step":"tapxy 195 60","w":1792551105346.731}
  #|{"step":"tapxy 195 60","acted":true,"w":1792551105346.786}
  #|{"step":"tapxy -60 -330","w":1792551105354.807}
  #|{"step":"tapxy -60 -330","acted":true,"w":1792551105354.842}
  #|{"step":"tapxy -60 -300","w":1792551105375.57}
  #|{"step":"tapxy -60 -300","acted":true,"w":1792551105375.609}
  #|{"step":"tapxy -60 -270","w":1792551105393.892}
  #|{"step":"tapxy -60 -270","acted":true,"w":1792551105393.932}
  #|{"step":"tapxy -60 -240","w":1792551105403.769}
  #|{"step":"tapxy -60 -240","acted":true,"w":1792551105403.807}
  #|{"step":"gone station 名称","w":1792551105420.692}
  #|{"step":"until =studio","w":1792551105420.749}
  #|{"step":"","w":1792551105420.769}
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
  #|{"textrec":{"s":[14,400,0,"出错：意外停止"],"r":[0,1,13.891050583657588,48,1,1,13.891050583657588,49,2,1,14.081712062256813,50,3,1,13.891050583657588,51,4,1,13.891050583657588,52,5,1,13.891050583657588,53,6,1,13.891050583657588,54]}}
  #|{"textrec":{"m":[14,400,0],"r":[13.53515625,2.953125,20,13.53515625,2.953125,0]}}
  #|{"textrec":{"s":[16,400,0,"…"],"r":[0,1,12.5625,55]}}
  #|{"textrec":{"s":[16,400,0,"端到端测试的对话 post:你好，我是测试用的…"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,26,3,1,15.875486381322958,28,4,1,15.875486381322958,29,5,1,15.875486381322958,30,6,1,15.875486381322958,31,7,1,15.875486381322958,32,8,1,4.1875,-1,9,1,9.453125,33,10,1,9.140625,34,11,1,8.0234375,35,12,1,5.4609375,36,13,1,4.4375,37,14,1,15.875486381322958,38,15,1,15.875486381322958,39,16,1,16.09338521400778,40,17,1,15.875486381322958,41,18,1,15.875486381322958,42,19,1,15.87548638132293,28,20,1,15.875486381322958,29,21,1,15.875486381322958,43,22,1,15.875486381322958,30,23,1,12.5625,55]}}
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
  #|{"textrec":{"g":55,"r":[462,0,13,5,0,-3,0]}}
  #|{"textrec":{"g":48,"r":[476,0,14,16,0,-13,0]}}
  #|{"textrec":{"g":49,"r":[491,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":50,"r":[508,0,5,10,1,-10,0]}}
  #|{"textrec":{"g":51,"r":[514,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":52,"r":[531,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":53,"r":[548,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":54,"r":[564,0,15,15,-1,-13,0]}}
  #|{"textrec":{"ib":["33d1dfbf90932d3b",1241,64],"r":[17,17,17,17]}}
  #|{"textrec":{"ib":["182b7158e0c0cae1",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["d61ec6305f7d8c8b",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["8bf9607b651cec61",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"s":[17,400,0,"会话"],"r":[0,1,16.851167315175097,56,1,1,16.851167315175097,57]}}
  #|{"textrec":{"m":[17,400,0],"r":[16.435546875,3.5859375,24,16.435546875,3.5859375,0]}}
  #|{"textrec":{"s":[32,700,8,"设置"],"r":[0,1,30.345864661654133,58,1,1,30.345864661654133,59]}}
  #|{"textrec":{"m":[32,700,0],"r":[30.9375,6.75,45,27.5185546875,4.4814453125,0]}}
  #|{"textrec":{"s":[16,700,0,"Name of alice"],"r":[0,1,11.9765625,60,1,1,9.12109375,61,2,1,14.6015625,62,3,1,9.30078125,63,4,1,3.8125,-1,5,1,9.6015625,64,6,1,6.21484375,65,7,1,3.8125,-1,8,1,9.12109375,61,9,1,4.40625,66,10,1,4.28125,67,11,1,9.0859375,68,12,1,9.30078125,63]}}
  #|{"textrec":{"m":[16,700,0],"r":[15.46875,3.375,23,15.46875,3.375,0]}}
  #|{"textrec":{"s":[13,400,0,"alice@example.test"],"r":[0,1,7.0966796875,12,1,1,3.2119140625,69,2,1,3.1357421875,70,3,1,7.1982421875,13,4,1,7.3505859375,14,5,1,11.857421875,71,6,1,7.2236328125,14,7,1,6.6142578125,72,8,1,7.0966796875,12,9,1,11.2353515625,73,10,1,7.8583984375,11,11,1,3.2119140625,69,12,1,7.3505859375,14,13,1,3.65625,74,14,1,4.471923828125,75,15,1,7.302978515625,14,16,1,6.69677734375,10,17,1,4.61474609375,75]}}
  #|{"textrec":{"s":[23,600,0,"N"],"r":[0,1,16.576080499507952,76]}}
  #|{"textrec":{"m":[23,600,0],"r":[22.236328125,4.8515625,33,19.778961181640625,3.221038818359375,0]}}
  #|{"textrec":{"s":[15,600,0,"Dev"],"r":[0,1,10.861195921897888,77,1,1,8.51915180683136,78,2,1,8.18638265132904,79]}}
  #|{"textrec":{"s":[15,400,0,"Workspace"],"r":[0,1,13.916015625,80,1,1,8.26171875,81,2,1,5.478515625,82,3,1,7.763671875,83,4,1,7.470703125,84,5,1,8.9208984375,85,6,1,8.0419921875,86,7,1,8.1591796875,87,8,1,8.3349609375,88]}}
  #|{"textrec":{"s":[14,400,0,"未开启"],"r":[0,1,13.891050583657588,89,1,1,13.891050583657588,90,2,1,13.891050583657588,91]}}
  #|{"textrec":{"s":[15,400,0,"安全"],"r":[0,1,14.883268482490273,92,1,1,14.883268482490273,20]}}
  #|{"textrec":{"s":[15,400,0,"Station"],"r":[0,1,9.32373046875,93,1,1,5.21484375,94,2,1,8.0419921875,86,3,1,5.21484375,94,4,1,3.4716796875,95,5,1,8.6279296875,81,6,1,8.51806640625,96]}}
  #|{"textrec":{"s":[15,400,0,"连接"],"r":[0,1,14.883268482490273,97,1,1,14.883268482490273,98]}}
  #|{"textrec":{"s":[15,400,0,"Profile"],"r":[0,1,9.29443359375,99,1,1,5.36865234375,82,2,1,8.51806640625,81,3,1,5.19287109375,100,4,1,3.4716796875,95,5,1,3.5595703125,101,6,1,8.3349609375,88]}}
  #|{"textrec":{"s":[15,400,0,"自动决策"],"r":[0,1,14.883268482490273,102,1,1,14.883268482490273,103,2,1,14.883268482490273,104,3,1,14.883268482490273,105]}}
  #|{"textrec":{"s":[15,400,0,"记忆"],"r":[0,1,14.883268482490273,106,1,1,14.883268482490273,107]}}
  #|{"textrec":{"s":[15,400,0,"用量"],"r":[0,1,14.883268482490273,108,1,1,14.883268482490273,109]}}
  #|{"textrec":{"s":[15,600,0,"此设备"],"r":[0,1,14.883268482490273,110,1,1,14.883268482490273,111,2,1,14.883268482490273,112]}}
  #|{"textrec":{"s":[14,400,0,"跟随系统"],"r":[0,1,13.891050583657588,113,1,1,13.891050583657588,114,2,1,13.891050583657588,115,3,1,13.891050583657588,116]}}
  #|{"textrec":{"s":[15,400,0,"外观"],"r":[0,1,14.883268482490273,117,1,1,14.883268482490273,118]}}
  #|{"textrec":{"s":[14,400,0,"2 栏"],"r":[0,1,8.298828125,119,1,1,3.787109375,-1,2,1,13.891050583657588,120]}}
  #|{"textrec":{"s":[15,400,0,"下方栏"],"r":[0,1,14.883268482490273,121,1,1,14.883268482490273,122,2,1,14.883268482490273,123]}}
  #|{"textrec":{"s":[15,400,0,"本机缓存"],"r":[0,1,14.883268482490273,124,1,1,14.883268482490273,125,2,1,14.883268482490273,126,3,1,14.883268482490273,127]}}
  #|{"textrec":{"s":[15,400,0,"通知"],"r":[0,1,14.883268482490273,128,1,1,14.883268482490273,129]}}
  #|{"textrec":{"s":[13,400,0,"任务完成、需要处理、出错或有新消息时通知你"],"r":[0,1,12.898832684824903,130,1,1,12.898832684824903,131,2,1,12.898832684824903,132,3,1,12.898832684824903,133,4,1,13.075875486381321,134,5,1,12.89883268482491,135,6,1,12.898832684824896,136,7,1,12.898832684824896,137,8,1,12.898832684824896,138,9,1,13.075875486381335,134,10,1,12.898832684824896,139,11,1,12.898832684824896,140,12,1,12.898832684824896,141,13,1,12.898832684824896,142,14,1,12.898832684824896,143,15,1,12.898832684824896,144,16,1,12.898832684824896,145,17,1,12.898832684824896,146,18,1,12.898832684824896,147,19,1,12.898832684824924,148,20,1,12.898832684824924,4]}}
  #|{"textrec":{"s":[15,400,0,"检查更新"],"r":[0,1,14.883268482490273,149,1,1,14.883268482490273,150,2,1,14.883268482490273,151,3,1,14.883268482490273,152]}}
  #|{"textrec":{"s":[15,400,0,"still.fail mbui 0.1"],"r":[0,1,7.58056640625,84,1,1,5.17822265625,94,2,1,3.4716796875,95,3,1,3.5595703125,101,4,1,3.5595703125,101,5,1,3.9990234375,153,6,1,4.86328125,100,7,1,7.93212890625,86,8,1,3.4716796875,95,9,1,3.5595703125,101,10,1,3.984375,-1,11,1,12.8173828125,154,12,1,8.9794921875,155,13,1,8.51806640625,156,14,1,3.4716796875,95,15,1,3.984375,-1,16,1,8.9208984375,157,17,1,3.7060546875,153,18,1,6.50390625,158]}}
  #|{"textrec":{"s":[15,400,0,"更新日志"],"r":[0,1,14.883268482490273,151,1,1,14.883268482490273,152,2,1,14.883268482490273,159,3,1,14.883268482490273,160]}}
  #|{"textrec":{"s":[15,600,0,"Dev · 你是Owner"],"r":[0,1,10.861195921897888,77,1,1,8.51915180683136,78,2,1,8.18638265132904,79,3,1,3.761730194091797,-1,4,1,7.186782927948599,161,5,1,3.761730194091797,-1,6,1,14.883268482490273,162,7,1,14.883268482490273,163,8,1,13.354362845420837,164,9,1,12.072962522506714,165,10,1,8.93320620059967,166,11,1,8.615586161613464,78,12,1,5.99338173866272,167]}}
  #|{"textrec":{"s":[14,400,0,"1 人"],"r":[0,1,6.34375,168,1,1,3.787109375,-1,2,1,13.891050583657588,169]}}
  #|{"textrec":{"s":[14,400,0,"0 条"],"r":[0,1,8.66796875,170,1,1,3.787109375,-1,2,1,13.891050583657588,171]}}
  #|{"textrec":{"s":[15,400,0,"密钥"],"r":[0,1,14.883268482490273,172,1,1,14.883268482490273,173]}}
  #|{"textrec":{"s":[14,400,0,"1/1 在线"],"r":[0,1,6.34375,168,1,1,4.115234375,174,2,1,6.34375,168,3,1,3.787109375,-1,4,1,13.891050583657588,175,5,1,13.891050583657588,176]}}
  #|{"textrec":{"s":[14,400,0,"0 个"],"r":[0,1,8.66796875,170,1,1,3.787109375,-1,2,1,13.891050583657588,177]}}
  #|{"textrec":{"s":[14,400,0,"1 个"],"r":[0,1,6.34375,168,1,1,3.787109375,-1,2,1,13.891050583657588,177]}}
  #|{"textrec":{"ib":["504a4df6beac534a",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["a1e7be43eb966606",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"g":56,"r":[580,0,18,18,-1,-15,0]}}
  #|{"textrec":{"g":57,"r":[599,0,19,18,-1,-15,0]}}
  #|{"textrec":{"g":58,"r":[619,0,31,31,0,-26,0]}}
  #|{"textrec":{"g":59,"r":[651,0,30,29,0,-25,0]}}
  #|{"textrec":{"g":77,"r":[682,0,12,13,0,-12,0]}}
  #|{"textrec":{"g":78,"r":[695,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":79,"r":[707,0,11,11,-1,-10,0]}}
  #|{"textrec":{"g":161,"r":[719,0,5,5,1,-8,0]}}
  #|{"textrec":{"g":162,"r":[725,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":163,"r":[742,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":164,"r":[759,0,13,14,-1,-12,0]}}
  #|{"textrec":{"g":165,"r":[773,0,14,11,-1,-10,0]}}
  #|{"textrec":{"g":166,"r":[788,0,10,11,0,-10,0]}}
  #|{"textrec":{"g":167,"r":[799,0,7,11,0,-10,0]}}
  #|{"textrec":{"g":80,"r":[807,0,16,13,-1,-12,0]}}
  #|{"textrec":{"g":81,"r":[824,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":82,"r":[836,0,7,11,0,-10,0]}}
  #|{"textrec":{"g":83,"r":[844,0,9,14,0,-13,0]}}
  #|{"textrec":{"g":84,"r":[854,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":85,"r":[865,0,10,14,0,-10,0]}}
  #|{"textrec":{"g":86,"r":[876,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":87,"r":[887,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":88,"r":[898,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":92,"r":[909,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":172,"r":[926,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":173,"r":[943,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":93,"r":[960,0,11,14,-1,-12,0]}}
  #|{"textrec":{"g":94,"r":[972,0,7,13,-1,-11,0]}}
  #|{"textrec":{"g":95,"r":[980,0,5,14,-1,-13,0]}}
  #|{"textrec":{"g":96,"r":[986,0,9,11,0,-10,0]}}
  #|{"textrec":{"g":97,"r":[996,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":98,"r":[1013,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":99,"r":[1030,0,10,13,0,-12,0]}}
  #|{"textrec":{"g":100,"r":[1041,0,7,14,-1,-13,0]}}
  #|{"textrec":{"g":101,"r":[1049,0,4,14,0,-13,0]}}
  #|{"textrec":{"g":102,"r":[1054,0,13,16,1,-13,0]}}
  #|{"textrec":{"g":103,"r":[1068,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":104,"r":[1085,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":105,"r":[1103,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":106,"r":[1120,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":107,"r":[1138,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":108,"r":[1155,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":109,"r":[1171,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":110,"r":[1188,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":111,"r":[1206,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":112,"r":[1224,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":117,"r":[1242,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":118,"r":[1260,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":121,"r":[1278,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":122,"r":[1295,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":123,"r":[1312,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":124,"r":[1329,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":125,"r":[1347,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":126,"r":[1365,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":127,"r":[1383,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":76,"r":[1400,0,17,19,0,-18,0]}}
  #|{"textrec":{"g":60,"r":[1418,0,12,14,0,-13,0]}}
  #|{"textrec":{"g":61,"r":[1431,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":62,"r":[1443,0,15,11,0,-10,0]}}
  #|{"textrec":{"g":63,"r":[1459,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":64,"r":[1471,0,12,12,-1,-10,0]}}
  #|{"textrec":{"g":65,"r":[1484,0,8,14,-1,-13,0]}}
  #|{"textrec":{"g":66,"r":[1493,0,5,14,0,-13,0]}}
  #|{"textrec":{"g":67,"r":[1499,0,5,15,0,-14,0]}}
  #|{"textrec":{"g":68,"r":[1505,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":12,"r":[1517,0,9,10,-1,-8,0]}}
  #|{"textrec":{"g":69,"r":[1527,0,4,12,0,-11,0]}}
  #|{"textrec":{"g":70,"r":[1532,0,5,12,-1,-11,0]}}
  #|{"textrec":{"g":13,"r":[1538,0,9,10,-1,-8,0]}}
  #|{"textrec":{"g":14,"r":[1548,0,9,10,-1,-8,0]}}
  #|{"textrec":{"g":71,"r":[1558,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":72,"r":[1573,0,9,9,-1,-8,0]}}
  #|{"textrec":{"g":73,"r":[1583,0,12,9,0,-8,0]}}
  #|{"textrec":{"g":11,"r":[1596,0,9,12,0,-8,0]}}
  #|{"textrec":{"g":74,"r":[1606,0,4,5,0,-3,0]}}
  #|{"textrec":{"g":75,"r":[1611,0,7,12,-1,-10,0]}}
  #|{"textrec":{"g":10,"r":[1619,0,9,10,-1,-8,0]}}
  #|{"textrec":{"g":89,"r":[1629,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":90,"r":[1645,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":91,"r":[1661,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":168,"r":[1677,0,7,12,-1,-11,0]}}
  #|{"textrec":{"g":174,"r":[1685,0,7,16,-1,-12,0]}}
  #|{"textrec":{"g":175,"r":[1693,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":176,"r":[1709,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":113,"r":[1726,0,16,15,-1,-12,0]}}
  #|{"textrec":{"g":114,"r":[1743,0,15,16,0,-13,0]}}
  #|{"textrec":{"g":115,"r":[1759,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":116,"r":[1775,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":169,"r":[1792,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":170,"r":[1809,0,10,14,-1,-12,0]}}
  #|{"textrec":{"g":171,"r":[1820,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":177,"r":[1837,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":119,"r":[1854,0,9,13,0,-12,0]}}
  #|{"textrec":{"g":120,"r":[1864,0,16,16,-1,-13,0]}}
  #|{"textrec":{"ib":["b3685975cd23abc3",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"s":[16,600,0,"Station"],"r":[0,1,10.266256332397461,178,1,1,5.999713897705078,179,2,1,8.899068832397461,180,3,1,5.999713897705078,179,4,1,4.046333312988281,181,5,1,9.432537078857422,182,6,1,9.466253280639648,183]}}
  #|{"textrec":{"m":[16,600,0],"r":[15.46875,3.375,23,15.46875,3.375,0]}}
  #|{"textrec":{"s":[17,400,0,"设置"],"r":[0,1,16.851167315175097,184,1,1,16.851167315175097,185]}}
  #|{"textrec":{"s":[16,700,0,"studio"],"r":[0,1,8.73046875,186,1,1,6.26953125,187,2,1,9.72265625,188,3,1,10.109375,189,4,1,4.28125,67,5,1,9.6015625,64]}}
  #|{"textrec":{"s":[13,400,0,"空闲 · Apple M4 · 16 GB · macOS 27.0.1"],"r":[0,1,12.898832684824903,190,1,1,12.898832684824903,191,2,1,3.580078125,-1,3,1,6.228545204222122,192,4,1,3.580078125,-1,5,1,8.68359375,193,6,1,7.8583984375,11,7,1,7.8583984375,11,8,1,3.211914062500007,69,9,1,7.3505859375,14,10,1,3.580078125,-1,11,1,11.2861328125,194,12,1,8.2900390625,195,13,1,3.580078125,-1,14,1,6.228545204222115,192,15,1,3.580078125,-1,16,1,5.9541015625,196,17,1,8.201171875,197,18,1,3.580078125,-1,19,1,9.62939453125,198,20,1,8.4677734375,199,21,1,3.580078125,-1,22,1,6.228545204222115,192,23,1,3.580078125,-1,24,1,11.2353515625,73,25,1,7.0966796875,12,26,1,7.1982421875,13,27,1,9.953125,200,28,1,8.20751953125,201,29,1,3.580078125,-1,30,1,7.76953125,202,31,1,6.626953125,203,32,1,2.8310546875,74,33,1,7.6044921875,204,34,1,3.3388671875,74,35,1,5.763671875,196]}}
  #|{"textrec":{"s":[13,400,0,"↑"],"r":[0,1,10.080078125,205]}}
  #|{"textrec":{"s":[13,500,0," "],"r":[0,1,3.4683494567871094,-1]}}
  #|{"textrec":{"m":[13,500,0],"r":[12.568359375,2.7421875,18,12.568359375,2.7421875,0]}}
  #|{"textrec":{"s":[13,400,0,"↓"],"r":[0,1,10.080078125,206]}}
  #|{"textrec":{"s":[13,400,0,"直连"],"r":[0,1,12.898832684824903,207,1,1,12.898832684824903,208]}}
  #|{"textrec":{"s":[13,400,0,"当前延迟 "],"r":[0,1,12.898832684824903,209,1,1,12.898832684824903,210,2,1,12.898832684824903,211,3,1,12.898832684824903,212,4,1,3.580078125,-1]}}
  #|{"textrec":{"s":[13,500,0,"0 ms"],"r":[0,1,8.373004913330078,213,1,1,3.4683494567871094,-1,2,1,11.530966997146606,214,3,1,6.933351516723633,215]}}
  #|{"textrec":{"s":[11,600,0,"磁盘"],"r":[0,1,10.93579766536965,216,1,1,10.93579766536965,217]}}
  #|{"textrec":{"m":[11,600,0],"r":[10.634765625,2.3203125,16,10.634765625,2.3203125,0]}}
  #|{"textrec":{"s":[11,600,0,"剩 41.8 G"],"r":[0,1,10.93579766536965,218,1,1,2.9949302673339844,-1,2,1,7.3840750455856305,219,3,1,5.295345067977905,220,4,1,3.3275551795959473,221,5,1,7.26071560382843,222,6,1,2.9949302673339844,-1,7,1,8.372097969055176,223]}}
  #|{"textrec":{"g":184,"r":[1881,0,19,18,-1,-15,0]}}
  #|{"textrec":{"g":185,"r":[1901,0,18,17,-1,-14,0]}}
  #|{"textrec":{"ib":["b7b1dc2c98725280",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"g":216,"r":[1920,0,13,12,-1,-10,0]}}
  #|{"textrec":{"g":217,"r":[1934,0,13,12,-1,-10,0]}}
  #|{"textrec":{"g":218,"r":[1948,0,13,13,-1,-10,0]}}
  #|{"textrec":{"g":219,"r":[1962,0,9,10,-1,-9,0]}}
  #|{"textrec":{"g":220,"r":[1972,0,7,10,-1,-9,0]}}
  #|{"textrec":{"g":221,"r":[1980,0,5,5,-1,-3,0]}}
  #|{"textrec":{"g":222,"r":[1986,0,9,11,-1,-9,0]}}
  #|{"textrec":{"g":223,"r":[1996,0,10,11,-1,-9,0]}}
  #|{"textrec":{"g":186,"r":[2007,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":187,"r":[2019,0,8,14,-1,-12,0]}}
  #|{"textrec":{"g":188,"r":[2028,0,10,12,0,-10,0]}}
  #|{"textrec":{"g":189,"r":[0,32,12,15,-1,-13,0]}}
  #|{"textrec":{"g":190,"r":[13,32,14,14,-1,-12,0]}}
  #|{"textrec":{"g":191,"r":[28,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":192,"r":[42,32,4,5,1,-7,0]}}
  #|{"textrec":{"g":193,"r":[47,32,11,12,-1,-11,0]}}
  #|{"textrec":{"g":194,"r":[59,32,12,12,0,-11,0]}}
  #|{"textrec":{"g":195,"r":[72,32,10,12,-1,-11,0]}}
  #|{"textrec":{"g":196,"r":[83,32,7,12,-1,-11,0]}}
  #|{"textrec":{"g":197,"r":[91,32,10,13,-1,-11,0]}}
  #|{"textrec":{"g":198,"r":[102,32,11,13,-1,-11,0]}}
  #|{"textrec":{"g":199,"r":[114,32,9,12,0,-11,0]}}
  #|{"textrec":{"g":200,"r":[124,32,12,13,-1,-11,0]}}
  #|{"textrec":{"g":201,"r":[137,32,10,13,-1,-11,0]}}
  #|{"textrec":{"g":202,"r":[148,32,9,12,-1,-11,0]}}
  #|{"textrec":{"g":203,"r":[158,32,9,12,-1,-11,0]}}
  #|{"textrec":{"g":204,"r":[168,32,10,13,-1,-11,0]}}
  #|{"textrec":{"g":178,"r":[179,32,12,15,-1,-13,0]}}
  #|{"textrec":{"g":179,"r":[192,32,8,14,-1,-12,0]}}
  #|{"textrec":{"g":180,"r":[201,32,11,12,-1,-10,0]}}
  #|{"textrec":{"g":181,"r":[213,32,5,15,0,-14,0]}}
  #|{"textrec":{"g":182,"r":[219,32,11,12,-1,-10,0]}}
  #|{"textrec":{"g":183,"r":[231,32,10,11,0,-10,0]}}
  #|{"textrec":{"ib":["2bb63fc1d380f765",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"s":[11,400,0,"Apple M4 · 16 GB · macOS 27.0.1"],"r":[0,1,7.4765625,224,1,1,6.7783203125,225,2,1,6.7783203125,225,3,1,2.8466796875,226,4,1,6.3486328125,227,5,1,3.158203125,-1,6,1,9.6787109375,228,7,1,7.1435546875,229,8,1,3.158203125,-1,9,1,5.2804038549793475,230,10,1,3.158203125,-1,11,1,5.166992187499993,231,12,1,7.068359375,232,13,1,3.158203125,-1,14,1,8.27685546875,233,15,1,7.2939453125,234,16,1,3.158203125,-1,17,1,5.28040385497934,230,18,1,3.158203125,-1,19,1,9.6357421875,235,20,1,6.1337890625,236,21,1,6.2197265625,237,22,1,8.55078125,238,23,1,7.07373046875,239,24,1,3.158203125,-1,25,1,6.703125,240,26,1,5.736328125,241,27,1,2.5244140625,242,28,1,6.5634765625,243,29,1,2.9541015625,242,30,1,5.005859375,231]}}
  #|{"textrec":{"m":[11,400,0],"r":[10.634765625,2.3203125,16,10.634765625,2.3203125,0]}}
  #|{"textrec":{"s":[16,600,0,"studio"],"r":[0,1,8.471200942993164,244,1,1,5.973020553588867,179,2,1,9.466253280639648,245,3,1,9.891647338867188,246,4,1,4.046333312988281,181,5,1,9.432537078857422,182]}}
  #|{"textrec":{"s":[17,400,0,"Station"],"r":[0,1,10.40087890625,247,1,1,5.744140625,248,2,1,8.9482421875,249,3,1,5.744140625,248,4,1,3.7685546875,250,5,1,9.6123046875,251,6,1,9.48779296875,252]}}
  #|{"textrec":{"s":[28,600,0,"89"],"r":[0,1,18.046374320983887,253,1,1,18.283138751983643,254]}}
  #|{"textrec":{"m":[28,600,0],"r":[27.0703125,5.90625,40,24.0787353515625,3.9212646484375,0]}}
  #|{"textrec":{"s":[15,500,0,"%"],"r":[0,1,14.252007007598877,255]}}
  #|{"textrec":{"m":[15,500,0],"r":[14.501953125,3.1640625,21,14.501953125,3.1640625,0]}}
  #|{"textrec":{"s":[13,500,0,"CPU 空闲"],"r":[0,1,9.350531578063965,256,1,1,8.364851832389832,257,2,1,9.618190050125122,258,3,1,3.4683494567871094,-1,4,1,12.898832684824903,259,5,1,12.898832684824903,260]}}
  #|{"textrec":{"s":[12,400,0,"负载 1.6"],"r":[0,1,11.918287937743191,261,1,1,11.918287937743191,262,2,1,3.375,-1,3,1,5.419921875,263,4,1,3.181640625,264,5,1,7.40625,265]}}
  #|{"textrec":{"m":[12,400,0],"r":[11.6015625,2.53125,17,11.6015625,2.53125,0]}}
  #|{"textrec":{"s":[28,600,0,"7.2"],"r":[0,1,14.867459774017334,266,1,1,5.5835723876953125,267,2,1,16.886554718017578,268]}}
  #|{"textrec":{"s":[15,500,0,"GB"],"r":[0,1,11.039557456970215,269,1,1,9.822771549224854,270]}}
  #|{"textrec":{"s":[13,500,0,"内存剩"],"r":[0,1,12.898832684824903,271,1,1,12.898832684824903,272,2,1,12.898832684824903,273]}}
  #|{"textrec":{"s":[12,400,0,"共 16 GB"],"r":[0,1,11.918287937743191,274,1,1,3.375,-1,2,1,5.56640625,263,3,1,7.640625,265,4,1,3.375,-1,5,1,8.958984374999996,275,6,1,7.88671875,276]}}
  #|{"textrec":{"s":[28,600,0,"41.8"],"r":[0,1,18.027241706848145,277,1,1,13.169396877288818,278,2,1,6.6237664222717285,267,3,1,18.046374320983887,253]}}
  #|{"textrec":{"s":[13,500,0,"磁盘剩"],"r":[0,1,12.898832684824903,279,1,1,12.898832684824903,280,2,1,12.898832684824903,273]}}
  #|{"textrec":{"s":[12,400,0,"共 228 GB"],"r":[0,1,11.918287937743191,274,1,1,3.375,-1,2,1,7.2421875,281,3,1,7.2421875,281,4,1,7.6640624999999964,282,5,1,3.375,-1,6,1,8.958984375,275,7,1,7.88671875,276]}}
  #|{"textrec":{"s":[13,400,0,"主机名"],"r":[0,1,12.898832684824903,283,1,1,12.898832684824903,284,2,1,12.898832684824903,285]}}
  #|{"textrec":{"s":[13,400,0,"3720-Mac-mini-1"],"r":[0,1,8.07421875,286,1,1,7.3251953125,203,2,1,7.76953125,202,3,1,8.1123046875,204,4,1,6.0556640625,287,5,1,11.2861328125,194,6,1,7.0966796875,12,7,1,7.1982421875,13,8,1,6.0556640625,287,9,1,11.2353515625,73,10,1,3.1357421875,70,11,1,7.50927734375,288,12,1,3.1357421875,70,13,1,6.0556640625,287,14,1,5.9541015625,196]}}
  #|{"textrec":{"s":[13,400,0,"芯片"],"r":[0,1,12.898832684824903,289,1,1,12.898832684824903,290]}}
  #|{"textrec":{"s":[13,400,0,"Apple M4 · 10 核 · arm64"],"r":[0,1,8.68359375,193,1,1,7.8583984375,11,2,1,7.8583984375,11,3,1,3.2119140625,69,4,1,7.3505859375,14,5,1,3.580078125,-1,6,1,11.2861328125,194,7,1,8.2900390625,195,8,1,3.580078125,-1,9,1,6.228545204222115,192,10,1,3.580078125,-1,11,1,5.9541015625,196,12,1,8.1123046875,204,13,1,3.580078125,-1,14,1,12.898832684824896,291,15,1,3.580078125,-1,16,1,6.228545204222115,192,17,1,3.580078125,-1,18,1,7.0966796875,12,19,1,4.9384765625,8,20,1,11.298828125,73,21,1,8.201171875,197,22,1,8.2900390625,195]}}
  #|{"textrec":{"s":[13,400,0,"已运行"],"r":[0,1,12.898832684824903,292,1,1,12.898832684824903,293,2,1,12.898832684824903,294]}}
  #|{"textrec":{"s":[13,400,0,"8 小时"],"r":[0,1,8.2265625,295,1,1,3.580078125,-1,2,1,12.898832684824903,296,3,1,12.898832684824903,146]}}
  #|{"textrec":{"s":[13,400,0,"still.fail"],"r":[0,1,6.69677734375,10,1,1,4.61474609375,75,2,1,3.1357421875,70,3,1,3.2119140625,69,4,1,3.2119140625,69,5,1,3.5927734375,74,6,1,4.341796875,297,7,1,7.00146484375,12,8,1,3.1357421875,70,9,1,3.2119140625,69]}}
  #|{"textrec":{"s":[13,400,0,"进程占用 152 MB"],"r":[0,1,12.898832684824903,298,1,1,12.898832684824903,299,2,1,12.898832684824903,300,3,1,12.898832684824903,301,4,1,3.580078125,-1,5,1,5.9541015625,196,6,1,7.9599609375,302,7,1,7.76953125,202,8,1,3.580078125,-1,9,1,11.2861328125,194,10,1,8.4677734375,199]}}
  #|{"textrec":{"s":[13,400,0,"没有运行中的 agent 进程"],"r":[0,1,12.898832684824903,303,1,1,12.898832684824903,142,2,1,12.898832684824903,293,3,1,12.898832684824903,294,4,1,12.898832684824896,304,5,1,12.898832684824896,5,6,1,3.580078125,-1,7,1,7.0966796875,12,8,1,7.845703125,305,9,1,7.3505859375,14,10,1,7.50927734375,288,11,1,4.646484375,75,12,1,3.580078125,-1,13,1,12.898832684824896,298,14,1,12.898832684824896,299]}}
  #|{"textrec":{"s":[15,600,0,"在此 station 上"],"r":[0,1,14.883268482490273,306,1,1,14.883268482490273,110,2,1,3.761730194091797,-1,3,1,8.000344634056091,307,4,1,5.658300518989563,308,5,1,8.40147078037262,309,6,1,5.683325529098511,308,7,1,3.8520312309265137,310,8,1,8.901597261428833,311,9,1,8.93320620059967,166,10,1,3.761730194091797,-1,11,1,14.883268482490266,312]}}
  #|{"textrec":{"s":[15,400,0,"共享调试"],"r":[0,1,14.883268482490273,313,1,1,14.883268482490273,314,2,1,14.883268482490273,315,3,1,14.883268482490273,316]}}
  #|{"textrec":{"s":[14,400,0,"未开放"],"r":[0,1,13.891050583657588,89,1,1,13.891050583657588,90,2,1,13.891050583657588,317]}}
  #|{"textrec":{"s":[15,400,0,"文件"],"r":[0,1,14.883268482490273,318,1,1,14.883268482490273,319]}}
  #|{"textrec":{"s":[15,600,0,"Agent 环境变量"],"r":[0,1,10.209932327270508,320,1,1,9.027448296546936,321,2,1,8.615586161613464,78,3,1,8.93320620059967,166,4,1,5.683325529098511,308,5,1,3.761730194091797,-1,6,1,14.883268482490273,322,7,1,14.883268482490273,323,8,1,14.883268482490266,324,9,1,14.88326848249028,325]}}
  #|{"textrec":{"s":[15,400,0,"暂无变量"],"r":[0,1,14.883268482490273,326,1,1,14.883268482490273,327,2,1,14.883268482490273,328,3,1,14.883268482490273,109]}}
  #|{"textrec":{"s":[15,400,0,"编辑变量"],"r":[0,1,14.883268482490273,329,1,1,14.883268482490273,330,2,1,14.883268482490273,328,3,1,14.883268482490273,109]}}
  #|{"textrec":{"s":[15,600,0,"屏幕"],"r":[0,1,14.883268482490273,331,1,1,14.883268482490273,332]}}
  #|{"textrec":{"s":[15,400,0,"3720-Mac-mini-1"],"r":[0,1,9.169921875,333,1,1,8.3056640625,334,2,1,8.818359375,335,3,1,9.2138671875,157,4,1,6.8408203125,336,5,1,12.8759765625,337,6,1,8.0419921875,86,7,1,8.1591796875,87,8,1,6.8408203125,336,9,1,12.8173828125,154,10,1,3.4716796875,95,11,1,8.51806640625,96,12,1,3.4716796875,95,13,1,6.8408203125,336,14,1,6.7236328125,158]}}
  #|{"textrec":{"s":[13,400,0,"此 station 版本不含屏幕助手（stillfail-screen），请更新 station"],"r":[0,1,12.898832684824903,338,1,1,3.580078125,-1,2,1,6.69677734375,10,3,1,4.61474609375,75,4,1,7.0966796875,12,5,1,4.646484375,75,6,1,3.1357421875,70,7,1,7.6044921875,7,8,1,7.50927734375,288,9,1,3.580078125,-1,10,1,12.898832684824903,339,11,1,12.89883268482491,340,12,1,12.898832684824896,341,13,1,12.898832684824896,342,14,1,12.898832684824896,343,15,1,12.898832684824896,344,16,1,12.898832684824896,345,17,1,19.398832684824896,346,18,1,4.071984435797674,347,19,1,6.69677734375,10,20,1,4.61474609375,75,21,1,3.1357421875,70,22,1,3.2119140625,69,23,1,3.2119140625,69,24,1,4.5322265625,297,25,1,7.00146484375,12,26,1,3.1357421875,70,27,1,3.2119140625,69,28,1,6.0556640625,287,29,1,6.728515625,10,30,1,7.1982421875,13,31,1,4.77978515625,8,32,1,7.25537109375,14,33,1,7.3505859375,14,34,1,7.50927734375,288,35,1,5.456712062256827,348,36,1,13.075875486381335,349,37,1,12.898832684824924,350,38,1,12.898832684824924,351,39,1,12.898832684824924,143,40,1,3.580078125,-1,41,1,6.69677734375,10,42,1,4.61474609375,75,43,1,7.0966796875,12,44,1,4.646484375,75,45,1,3.1357421875,70,46,1,7.6044921875,7,47,1,7.50927734375,288]}}
  #|{"textrec":{"g":247,"r":[242,32,12,16,-1,-14,0]}}
  #|{"textrec":{"g":248,"r":[255,32,8,15,-1,-13,0]}}
  #|{"textrec":{"g":249,"r":[264,32,11,13,-1,-11,0]}}
  #|{"textrec":{"g":250,"r":[276,32,5,15,0,-14,0]}}
  #|{"textrec":{"g":251,"r":[282,32,12,13,-1,-11,0]}}
  #|{"textrec":{"g":252,"r":[295,32,10,12,0,-11,0]}}
  #|{"textrec":{"g":253,"r":[306,32,18,24,0,-22,0]}}
  #|{"textrec":{"g":254,"r":[325,32,18,24,0,-22,0]}}
  #|{"textrec":{"g":256,"r":[344,32,11,13,-1,-11,0]}}
  #|{"textrec":{"g":257,"r":[356,32,9,12,0,-11,0]}}
  #|{"textrec":{"g":258,"r":[366,32,10,13,0,-11,0]}}
  #|{"textrec":{"g":259,"r":[377,32,14,14,-1,-12,0]}}
  #|{"textrec":{"g":260,"r":[392,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":261,"r":[406,32,13,14,-1,-11,0]}}
  #|{"textrec":{"g":262,"r":[420,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":263,"r":[435,32,7,11,-1,-10,0]}}
  #|{"textrec":{"g":264,"r":[443,32,4,5,0,-3,0]}}
  #|{"textrec":{"g":265,"r":[448,32,9,12,-1,-10,0]}}
  #|{"textrec":{"g":283,"r":[458,32,14,14,-1,-12,0]}}
  #|{"textrec":{"g":284,"r":[473,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":285,"r":[489,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":289,"r":[504,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":290,"r":[520,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":292,"r":[535,32,13,13,0,-11,0]}}
  #|{"textrec":{"g":293,"r":[549,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":294,"r":[565,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":297,"r":[581,32,7,12,-1,-11,0]}}
  #|{"textrec":{"g":303,"r":[589,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":142,"r":[605,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":304,"r":[620,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":5,"r":[634,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":305,"r":[648,32,9,12,-1,-8,0]}}
  #|{"textrec":{"g":288,"r":[658,32,8,9,0,-8,0]}}
  #|{"textrec":{"g":298,"r":[667,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":299,"r":[683,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":306,"r":[699,32,16,17,-1,-14,0]}}
  #|{"textrec":{"g":307,"r":[716,32,10,12,-1,-10,0]}}
  #|{"textrec":{"g":308,"r":[727,32,8,13,-1,-11,0]}}
  #|{"textrec":{"g":309,"r":[736,32,10,12,-1,-10,0]}}
  #|{"textrec":{"g":310,"r":[747,32,6,14,-1,-13,0]}}
  #|{"textrec":{"g":311,"r":[754,32,11,12,-1,-10,0]}}
  #|{"textrec":{"g":312,"r":[766,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":313,"r":[783,32,16,17,-1,-14,0]}}
  #|{"textrec":{"g":314,"r":[800,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":315,"r":[817,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":316,"r":[834,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":318,"r":[852,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":319,"r":[870,32,16,17,-1,-14,0]}}
  #|{"textrec":{"g":331,"r":[887,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":332,"r":[904,32,17,17,-1,-14,0]}}
  #|{"textrec":{"ib":["dfa0b3408acf8bc7",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"g":333,"r":[922,32,10,14,0,-12,0]}}
  #|{"textrec":{"g":334,"r":[933,32,10,13,-1,-12,0]}}
  #|{"textrec":{"g":335,"r":[944,32,10,13,0,-12,0]}}
  #|{"textrec":{"g":157,"r":[955,32,11,14,-1,-12,0]}}
  #|{"textrec":{"g":336,"r":[967,32,7,4,0,-6,0]}}
  #|{"textrec":{"g":337,"r":[975,32,13,13,0,-12,0]}}
  #|{"textrec":{"g":154,"r":[989,32,13,11,0,-10,0]}}
  #|{"textrec":{"g":158,"r":[1003,32,8,13,-1,-12,0]}}
  #|{"textrec":{"g":338,"r":[1012,32,15,14,-1,-12,0]}}
  #|{"textrec":{"g":7,"r":[1028,32,9,10,-1,-8,0]}}
  #|{"textrec":{"g":339,"r":[1038,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":340,"r":[1054,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":341,"r":[1070,32,15,14,-1,-11,0]}}
  #|{"textrec":{"g":342,"r":[1086,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":343,"r":[1102,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":344,"r":[1117,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":345,"r":[1133,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":346,"r":[1148,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":347,"r":[1164,32,5,15,-1.16666666666667,-12,0]}}
  #|{"textrec":{"g":287,"r":[1170,32,8,4,-1,-6,0]}}
  #|{"textrec":{"g":8,"r":[1179,32,6,9,0,-8,0]}}
  #|{"textrec":{"g":348,"r":[1186,32,6,15,-1,-12,0]}}
  #|{"textrec":{"g":349,"r":[1193,32,5,7,0,-3,0]}}
  #|{"textrec":{"g":350,"r":[1199,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":351,"r":[1215,32,15,14,-1,-11,0]}}
  #|{"textrec":{"g":143,"r":[1231,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":224,"r":[1247,32,10,10,-1,-9,0]}}
  #|{"textrec":{"g":225,"r":[1258,32,9,10,-1,-7,0]}}
  #|{"textrec":{"g":226,"r":[1268,32,4,11,-1,-10,0]}}
  #|{"textrec":{"g":227,"r":[1273,32,8,9,-1,-7,0]}}
  #|{"textrec":{"g":228,"r":[1282,32,11,10,-1,-9,0]}}
  #|{"textrec":{"g":229,"r":[1294,32,9,10,-1,-9,0]}}
  #|{"textrec":{"g":230,"r":[1304,32,5,4,0,-6,0]}}
  #|{"textrec":{"g":231,"r":[1310,32,6,10,-1,-9,0]}}
  #|{"textrec":{"g":232,"r":[1317,32,9,11,-1,-9,0]}}
  #|{"textrec":{"g":233,"r":[1327,32,10,11,-1,-9,0]}}
  #|{"textrec":{"g":234,"r":[1338,32,9,10,-1,-9,0]}}
  #|{"textrec":{"g":235,"r":[1348,32,11,8,-1,-7,0]}}
  #|{"textrec":{"g":236,"r":[1360,32,8,9,-1,-7,0]}}
  #|{"textrec":{"g":237,"r":[1369,32,8,9,-1,-7,0]}}
  #|{"textrec":{"g":238,"r":[1378,32,10,11,-1,-9,0]}}
  #|{"textrec":{"g":239,"r":[1389,32,9,11,-1,-9,0]}}
  #|{"textrec":{"g":240,"r":[1399,32,8,10,-1,-9,0]}}
  #|{"textrec":{"g":241,"r":[1408,32,8,10,-1,-9,0]}}
  #|{"textrec":{"g":242,"r":[1417,32,5,5,-1,-3,0]}}
  #|{"textrec":{"g":243,"r":[1423,32,9,11,-1,-9,0]}}
  #|{"textrec":{"g":255,"r":[1433,32,16,14,-1,-12,0]}}
  #|{"textrec":{"g":286,"r":[1450,32,10,13,-1,-11,0]}}
  #|{"textrec":{"g":291,"r":[1461,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":295,"r":[1477,32,10,13,-1,-11,0]}}
  #|{"textrec":{"g":296,"r":[1488,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":146,"r":[1504,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":300,"r":[1520,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":301,"r":[1534,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":302,"r":[1549,32,10,13,-1,-11,0]}}
  #|{"textrec":{"g":244,"r":[1560,32,11,12,-1,-10,0]}}
  #|{"textrec":{"g":245,"r":[1572,32,10,12,0,-10,0]}}
  #|{"textrec":{"g":246,"r":[1583,32,11,15,-1,-13,0]}}
  #|{"textrec":{"g":266,"r":[1595,32,17,22,-1,-21,0]}}
  #|{"textrec":{"g":267,"r":[1613,32,7,7,0,-5,0]}}
  #|{"textrec":{"g":268,"r":[1621,32,17,23,0,-22,0]}}
  #|{"textrec":{"g":271,"r":[1639,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":272,"r":[1653,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":273,"r":[1669,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":274,"r":[1684,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":275,"r":[1699,32,11,12,-1,-10,0]}}
  #|{"textrec":{"g":276,"r":[1711,32,9,11,0,-10,0]}}
  #|{"textrec":{"g":269,"r":[1721,32,13,14,-1,-12,0]}}
  #|{"textrec":{"g":270,"r":[1735,32,11,13,0,-12,0]}}
  #|{"textrec":{"g":277,"r":[1747,32,18,22,0,-21,0]}}
  #|{"textrec":{"g":278,"r":[1766,32,11,22,0,-21,0]}}
  #|{"textrec":{"g":279,"r":[1778,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":280,"r":[1794,32,15,14,-1,-12,0]}}
  #|{"textrec":{"g":281,"r":[1810,32,9,11,-1,-10,0]}}
  #|{"textrec":{"g":282,"r":[1820,32,9,12,-1,-10,0]}}
  #|{"textrec":{"g":317,"r":[1830,32,16,16,-1,-13,0]}}
  #|{"textrec":{"ib":["ddfdc2820df8a676",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"s":[17,700,0,"studio"],"r":[0,1,9.176513671875,352,1,1,6.561767578125,353,2,1,10.230712890625,354,3,1,10.6416015625,355,4,1,4.44921875,356,5,1,10.10205078125,357]}}
  #|{"textrec":{"m":[17,700,0],"r":[16.435546875,3.5859375,24,16.435546875,3.5859375,0]}}
  #|{"textrec":{"s":[15,400,0,"重命名"],"r":[0,1,14.883268482490273,358,1,1,14.883268482490273,359,2,1,14.883268482490273,360]}}
  #|{"textrec":{"s":[15,400,0,"图标"],"r":[0,1,14.883268482490273,361,1,1,14.883268482490273,362]}}
  #|{"textrec":{"s":[15,400,0,"从 workspace 移除"],"r":[0,1,14.883268482490273,363,1,1,3.984375,-1,2,1,11.2353515625,364,3,1,8.4814453125,81,4,1,5.478515625,82,5,1,7.763671875,83,6,1,7.470703125,84,7,1,8.920898437500007,85,8,1,8.0419921875,86,9,1,8.1591796875,87,10,1,8.3349609375,88,11,1,3.984375,-1,12,1,14.88326848249028,365,13,1,14.88326848249028,366]}}
  #|{"textrec":{"g":352,"r":[1847,32,11,13,-1,-11,0]}}
  #|{"textrec":{"g":353,"r":[1859,32,9,15,-1,-13,0]}}
  #|{"textrec":{"g":354,"r":[1869,32,11,13,0,-11,0]}}
  #|{"textrec":{"g":355,"r":[1881,32,12,16,-1,-14,0]}}
  #|{"textrec":{"g":356,"r":[1894,32,5,16,0,-15,0]}}
  #|{"textrec":{"g":357,"r":[1900,32,12,13,-1,-11,0]}}
  #|{"textrec":{"g":358,"r":[1913,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":359,"r":[1930,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":360,"r":[1947,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":361,"r":[1963,32,15,16,0,-13,0]}}
  #|{"textrec":{"g":362,"r":[1979,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":363,"r":[1996,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":364,"r":[2014,32,14,10,-1,-9,0]}}
  #|{"textrec":{"g":365,"r":[2029,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":366,"r":[0,57,16,16,0,-13,0]}}
  #|{"textrec":{"s":[17,700,0,"station 名称"],"r":[0,1,9.176513671875,352,1,1,6.561767578125,353,2,1,9.591552734375,367,3,1,6.58251953125,353,4,1,4.44921875,356,5,1,10.10205078125,357,6,1,10.230712890625,368,7,1,3.951171875,-1,8,1,16.851167315175104,369,9,1,16.851167315175104,370]}}
  #|{"textrec":{"s":[14,600,0,"取消"],"r":[0,1,13.891050583657588,371,1,1,13.891050583657588,372]}}
  #|{"textrec":{"m":[14,600,0],"r":[13.53515625,2.953125,20,13.53515625,2.953125,0]}}
  #|{"textrec":{"s":[14,600,0,"保存"],"r":[0,1,13.891050583657588,373,1,1,13.891050583657588,374]}}
  #|{"textrec":{"s":[15,400,0,"studio"],"r":[0,1,7.58056640625,84,1,1,5.17822265625,94,2,1,8.51806640625,156,3,1,8.9794921875,375,4,1,3.4716796875,95,5,1,8.6279296875,81]}}
  #|{"textrec":{"g":367,"r":[17,57,11,13,-1,-11,0]}}
  #|{"textrec":{"g":368,"r":[29,57,11,12,0,-11,0]}}
  #|{"textrec":{"g":369,"r":[41,57,17,18,-1,-15,0]}}
  #|{"textrec":{"g":370,"r":[59,57,19,18,-1,-15,0]}}
  #|{"textrec":{"g":156,"r":[79,57,9,11,0,-9,0]}}
  #|{"textrec":{"g":375,"r":[89,57,10,15,-1,-13,0]}}
  #|{"textrec":{"g":371,"r":[100,57,16,15,-1,-12,0]}}
  #|{"textrec":{"g":372,"r":[117,57,15,16,-1,-13,0]}}
  #|{"textrec":{"g":373,"r":[133,57,16,16,-1,-13,0]}}
  #|{"textrec":{"g":374,"r":[150,57,16,16,-1,-13,0]}}
  #|{"textrec":{"s":[15,400,0,"studioe2e-not-082939"],"r":[0,1,7.58056640625,84,1,1,5.17822265625,94,2,1,8.51806640625,156,3,1,8.9794921875,375,4,1,3.4716796875,95,5,1,8.6279296875,81,6,1,8.3349609375,88,7,1,8.78173828125,335,8,1,8.29833984375,88,9,1,6.8408203125,336,10,1,8.51806640625,96,11,1,8.6279296875,81,12,1,5.068359375,94,13,1,6.6943359375,336,14,1,9.2138671875,157,15,1,9.345703125,376,16,1,8.818359375,335,17,1,9.31640625,377,18,1,9.169921875,333,19,1,9.31640625,377]}}
  #|{"textrec":{"g":376,"r":[167,57,11,14,-1,-12,0]}}
  #|{"textrec":{"g":377,"r":[179,57,11,14,-1,-12,0]}}
  #|{"textrec":{"s":[16,600,0,"连接"],"r":[0,1,15.875486381322958,378,1,1,15.875486381322958,379]}}
  #|{"textrec":{"s":[17,400,0,"studio"],"r":[0,1,8.42529296875,380,1,1,5.70263671875,248,2,1,9.48779296875,381,3,1,10.0107421875,382,4,1,3.7685546875,250,5,1,9.6123046875,251]}}
  #|{"textrec":{"s":[15,400,0,"此机器上暂无连接"],"r":[0,1,14.883268482490273,383,1,1,14.883268482490273,125,2,1,14.883268482490273,384,3,1,14.883268482490273,385,4,1,14.88326848249028,326,5,1,14.88326848249028,327,6,1,14.88326848249028,97,7,1,14.88326848249028,98]}}
  #|{"textrec":{"s":[16,600,0,"Profile"],"r":[0,1,10.239953994750977,386,1,1,6.225622177124023,387,2,1,9.327718734741211,182,3,1,5.944116592407227,388,4,1,4.046333312988281,181,5,1,4.159873962402344,389,6,1,9.127458572387695,390]}}
  #|{"textrec":{"s":[15,600,0,"API Key"],"r":[0,1,10.429658889770508,320,1,1,9.65855062007904,391,2,1,4.261693954467773,392,3,1,3.761730194091797,-1,4,1,9.82150912284851,393,5,1,8.214586973190308,78,6,1,8.328588008880615,394]}}
  #|{"textrec":{"s":[15,400,0,"cc"],"r":[0,1,8.1591796875,87,1,1,8.1591796875,87]}}
  #|{"textrec":{"s":[13,400,0,"无法检查 · 自定义环境变量 · 已启用 1 / 1 个模型"],"r":[0,1,12.898832684824903,395,1,1,12.898832684824903,396,2,1,12.898832684824903,397,3,1,12.898832684824903,398,4,1,3.580078125,-1,5,1,6.228545204222122,192,6,1,3.580078124999993,-1,7,1,12.898832684824896,399,8,1,12.898832684824896,400,9,1,12.898832684824896,401,10,1,12.898832684824896,402,11,1,12.898832684824896,403,12,1,12.898832684824896,404,13,1,12.898832684824896,405,14,1,3.580078125,-1,15,1,6.228545204222115,192,16,1,3.580078125,-1,17,1,12.898832684824896,292,18,1,12.898832684824896,406,19,1,12.898832684824896,301,20,1,3.580078125,-1,21,1,5.9541015625,196,22,1,3.580078125,-1,23,1,3.884765625,407,24,1,3.580078125,-1,25,1,5.9541015625,196,26,1,3.580078125,-1,27,1,12.898832684824896,408,28,1,12.898832684824924,409,29,1,12.898832684824924,410]}}
  #|{"textrec":{"g":378,"r":[191,57,17,17,-1,-14,0]}}
  #|{"textrec":{"g":379,"r":[209,57,17,17,-1,-14,0]}}
  #|{"textrec":{"g":380,"r":[227,57,11,13,-1,-11,0]}}
  #|{"textrec":{"g":381,"r":[239,57,10,12,0,-10,0]}}
  #|{"textrec":{"g":382,"r":[250,57,12,16,-1,-14,0]}}
  #|{"textrec":{"g":383,"r":[263,57,16,15,-1,-13,0]}}
  #|{"textrec":{"g":384,"r":[280,57,17,16,-1,-13,0]}}
  #|{"textrec":{"g":385,"r":[298,57,16,15,-1,-13,0]}}
  #|{"textrec":{"g":326,"r":[315,57,15,17,0,-14,0]}}
  #|{"textrec":{"g":327,"r":[331,57,16,16,-1,-13,0]}}
