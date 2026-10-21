// e2e/traces/open-link.trace, made by scripts/trace.py from 08-open_link.log: not edited by hand.

///|
/// What the app and its core said in the run, a line each.
pub let trace_open_link : String =
  #|{"env":{"MBUI_CLOUD":"http://127.0.0.1:18787","MBUI_CORE_ACCOUNT":"{\"sub\":\"alice\",\"email\":\"alice@example.test\",\"name\":\"Name of alice\",\"picture\":\"\",\"access\":\"-\",\"refresh\":\"-\",\"accessExpires\":1792549733}"}}
  #|{"out":{"id":1,"call":"client.device","params":{"client":"still.fail mbui","app":"desktop","userAgent":"Macintosh; Mac OS X"}},"w":1792549612709.566}
  #|{"in":{"id":1,"ok":null},"w":1792549612797.558}
  #|{"out":{"id":2,"subscribe":{"topic":"accounts"},"keyed":true},"w":1792549612797.583}
  #|{"out":{"id":3,"subscribe":{"topic":"prefs"},"keyed":true},"w":1792549612797.592}
  #|{"step":"# written by scripts/rerecord.sh from its test (src/sfreplay/emit.mbt): not edited by hand","w":1792549612799.054}
  #|{"step":"timeout 90000","w":1792549612799.06}
  #|{"step":"answered client.device","w":1792549612799.062}
  #|{"step":"answered client.focus","w":1792549612825.065}
  #|{"in":{"id":2,"value":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""}]},"w":1792549612891.384}
  #|{"in":{"id":3,"value":{"onlyMine":false,"onlyWatching":false,"onlyDecisions":false,"listFilter":{},"appearance":"system","rowPicture":"auto","absoluteTime":false,"lang":"zh","keys":{},"lastChat":{},"openChat":{"01M5E4B7SMW6BHBY7R148X785R":{"station":"01M5E4B7SMW6BHBY7R148X785R/b6f15a112e33296e79bfd2f7537d5f4313c7392ce6deea2cc95addb6aee947af","key":"ember:c-ce38477477"}},"chatTabs":{},"dropFiles":{},"driveViews":{},"resume":{},"stationUpdatesDismissed":{},"device":{"app":"desktop","phone":false,"handoff":false},"reader":{"size":18,"line":1.7,"margin":22,"face":"sans","indent":true,"paper":"follow"},"rails":{},"bars":{"sets":[["chats","files","profiles","stations"],["decisions","usage","connects","archive"]],"current":0},"barsBy":{},"fonts":{},"faces":{"ui":{"id":"","name":"","mono":false,"family":"","files":[],"bytes":0},"text":{"id":"","name":"","mono":false,"family":"","files":[],"bytes":0},"code":{"id":"","name":"","mono":true,"family":"","files":[],"bytes":0},"list":[{"id":"inter","name":"Inter","mono":false,"family":"SF Inter","css":"http://127.0.0.1:18787/releases/fonts/inter/4.001/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/inter/4.001/var.ttf.gz","bytes":457818,"sha256":"29160a80ff49ddcab2c97711247e08b1fab27a484a329ce8b813d820dc559031"}],"preview":"http://127.0.0.1:18787/releases/fonts/inter/4.001/preview-194fa287.ttf","bytes":457818},{"id":"noto-sans-sc","name":"思源黑体","mono":false,"family":"SF Noto Sans SC","css":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/var.ttf.gz","bytes":11276563,"sha256":"a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da"}],"preview":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/preview-f0494178.ttf","bytes":11276563},{"id":"noto-serif-sc","name":"思源宋体","mono":false,"family":"SF Noto Serif SC","css":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/var.ttf.gz","bytes":15454579,"sha256":"050080d9255a86808f2945bffac582b31ef32bc36411ce29563b4961670c66f9"}],"preview":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/preview-001bbedf.ttf","bytes":15454579},{"id":"lxgw-wenkai","name":"霞鹜文楷","mono":false,"family":"SF LXGW WenKai","css":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/font.css","files":[{"weight":400,"url":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/400.ttf.gz","bytes":12904482,"sha256":"2d73eea94ad808999d90c0000c239a84a33b09d4bc6ab6c5b8bbf1eda8a7fc8b"},{"weight":500,"url":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/500.ttf.gz","bytes":13272430,"sha256":"f4b8a34d1f838fe411540cb7c97b1c384ac9738a876c4104500bc42508b2312a"}],"preview":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/preview-d3505af4.ttf","bytes":26176912},{"id":"jetbrains-mono","name":"JetBrains Mono","mono":true,"family":"SF JetBrains Mono","css":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/var.ttf.gz","bytes":90579,"sha256":"48715a42ec242c21e9f02692891e147d022299a52e48d5e413e1a942193ffeda"}],"preview":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/preview-ee73078f.ttf","bytes":90579},{"id":"fira-code","name":"Fira Code","mono":true,"family":"SF Fira Code","css":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/var.ttf.gz","bytes":137151,"sha256":"9335b082b3c7850d98a64b584f3417f65355f3471278bb5eeb8c6c0e8657aeeb"}],"preview":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/preview-555be27a.ttf","bytes":137151},{"id":"maple-mono","name":"Maple Mono","mono":true,"family":"SF Maple Mono CN","css":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/font.css","files":[{"weight":400,"url":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/400.ttf.gz","bytes":8352545,"sha256":"0fcc5139bfd5ab14ff989bb7dfd5236d0cafc10e60b9828569e6883613ab4085"},{"weight":600,"url":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/600.ttf.gz","bytes":8438132,"sha256":"96ed7ae26ee7c50b02b2d2b2bc0f1a0cbabe45ae5d6e6abf6678e2177c415677"}],"preview":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/preview-cffdf246.ttf","bytes":16790677}]}}},"w":1792549612891.428}
  #|{"out":{"id":4,"subscribe":{"topic":"workspaces"},"keyed":true},"w":1792549612891.477}
  #|{"out":{"id":5,"subscribe":{"topic":"status"},"keyed":true},"w":1792549612891.489}
  #|{"in":{"id":4,"value":[{"account":{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""},"workspaces":[{"id":"01M5E4B7SMW6BHBY7R148X785R","name":"Dev","role":"owner","created_at":1792549429,"stations":1,"members":1,"relays":[],"time":{"created_at":{"past":true,"at":1792549429000,"ago":"3 分钟前","full":"10/21 10:23:49","until":"1 分钟内"}}}],"invitations":[],"relay_url":"http://127.0.0.1:18740","loaded":true,"beta":true}]},"w":1792549612910.308}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792549612910.323}
  #|{"out":{"id":6,"subscribe":{"topic":"lock","workspace":"01M5E4B7SMW6BHBY7R148X785R"},"keyed":true},"w":1792549612910.356}
  #|{"out":{"id":7,"subscribe":{"topic":"chats","scope":"01M5E4B7SMW6BHBY7R148X785R","mine":false},"keyed":true},"w":1792549612910.37}
  #|{"out":{"id":8,"subscribe":{"topic":"changelog"},"keyed":true},"w":1792549612910.378}
  #|{"out":{"id":9,"subscribe":{"topic":"workspaceMarks","workspace":"01M5E4B7SMW6BHBY7R148X785R"},"keyed":true},"w":1792549612910.498}
  #|{"out":{"id":10,"subscribe":{"topic":"status","workspace":"01M5E4B7SMW6BHBY7R148X785R"},"keyed":true},"w":1792549612910.541}
  #|{"out":{"id":11,"call":"client.focus","params":{"visible":true,"focused":true,"workspace":"01M5E4B7SMW6BHBY7R148X785R"}},"w":1792549612917.453}
  #|{"out":{"id":12,"subscribe":{"topic":"notify"},"keyed":true},"w":1792549612917.466}
  #|{"out":{"id":13,"subscribe":{"topic":"notify","workspace":"01M5E4B7SMW6BHBY7R148X785R"},"keyed":true},"w":1792549612917.476}
  #|{"in":{"id":6,"value":{"available":true,"locked":false,"notice":true,"role":"owner","manages":true,"owner":true,"canSign":true,"signs":false,"me":{"device":"3a57bbf1171f1168ccb6950b318d7b053a40bc2ef1dec65aeba6d4bc4d04e66d","code":"2XF-J5Y","kind":"app","confirmed":false,"waiting":false,"asked":false},"signers":0,"members":[],"stations":[{"id":"b6f15a112e33296e79bfd2f7537d5f4313c7392ce6deea2cc95addb6aee947af","name":"studio","version":"0.1.0","online":true,"protected":false}],"protected":0,"requests":[],"renew":[],"attention":0}},"w":1792549612924.724}
  #|{"in":{"id":7,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"stations":[{"station":"01M5E4B7SMW6BHBY7R148X785R/b6f15a112e33296e79bfd2f7537d5f4313c7392ce6deea2cc95addb6aee947af","id":"b6f15a112e33296e79bfd2f7537d5f4313c7392ce6deea2cc95addb6aee947af","name":"studio","state":"online"}],"loading":false,"days":[{"daysAgo":0,"at":1792549612395,"label":"今天","items":[{"id":"ember:c-ce38477477","session":"ember:c-ce38477477","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","agents":[{"key":"ember:c-ce38477477","runtime":"claude","process":"warm","pending":0,"lastTurn":{"id":"013db861-546c-42db-8b6c-a2ea01b58e4b","kind":"nudge","outcome":"completed","startedAt":1792549612393,"endedAt":1792549612394},"agentText":"默认模型","mark":"failed","statusText":"出错：意外停止","badgeText":"失败，需要处理"}],"last":{"seq":8,"authorKind":"ember","author":"ember","authorName":"still.fail","text":"⚠️ 本轮 agent 未在对话中回复，以下是它最后输出的文字，由 station 代为转发（并非它发布的消息）；回复即可继续：\n\n> Your turn ended without a state, so nobody knows where the chat stands. Only a real unresolved need requires need_human. A factual a","createdAt":1792549612395,"by":{"kind":"ember","name":"still.fail","mine":false,"label":"still.fail"},"preview":"⚠️ 本轮 agent 未在对话中回复，以下是它最后输出的文字，由 station 代为转发（并非它发布的消息）；回复即可继续： Your turn ended without a state, so nobody knows where the chat stands. Only a real unresolved need requires need_human. A factual a","time":{"createdAt":{"at":1792549612395,"ago":"刚刚","full":"10/21 10:26:52","until":"1 分钟内","past":true}}},"unread":false,"mine":true,"lastActiveAt":1792549612395,"station":"01M5E4B7SMW6BHBY7R148X785R/b6f15a112e33296e79bfd2f7537d5f4313c7392ce6deea2cc95addb6aee947af","stationName":"studio","state":"failed","time":{"lastActiveAt":{"at":1792549612395,"ago":"刚刚","full":"10/21 10:26:52","until":"1 分钟内","past":true}},"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"peopleText":"你 发起","pinned":false,"stateText":"出错：意外停止","tone":"alert"},{"id":"ember:c-929cb60322","session":"ember:c-929cb60322","thread":2,"title":"另一台设备新建的对话 082947 post:新对话里的回复 082947","agents":[{"key":"ember:c-929cb60322","runtime":"claude","process":"cold","pending":0,"lastTurn":{"id":"fee5fb0a-dc3d-4e31-9ed4-657fd9506dfa","kind":"input","outcome":"completed","declared":"final","ending":"all_done","need":"answered the question that was asked","startedAt":1792549567334,"endedAt":1792549567403},"agentText":"默认模型","statusText":"已完成：answered the question that was asked"}],"last":{"seq":2,"authorKind":"agent","author":"ember:c-929cb60322","text":"新对话里的回复 082947","createdAt":1792549567401,"by":{"kind":"agent","name":"agent","mine":false,"runtime":"claude","label":"agent"},"preview":"新对话里的回复 082947","time":{"createdAt":{"at":1792549567401,"ago":"1 分钟前","full":"10/21 10:26:07","until":"1 分钟内","past":true}}},"unread":true,"mine":true,"lastActiveAt":1792549567401,"station":"01M5E4B7SMW6BHBY7R148X785R/b6f15a112e33296e79bfd2f7537d5f4313c7392ce6deea2cc95addb6aee947af","stationName":"studio","time":{"lastActiveAt":{"at":1792549567401,"ago":"1 分钟前","full":"10/21 10:26:07","until":"1 分钟内","past":true}},"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"peopleText":"你 发起","pinned":false,"tone":"done"}]}],"trouble":null,"members":1,"leading":"agents","glyph":{"online":1,"dim":0,"connecting":0,"failing":0,"working":0,"summary":"studio","label":"1 台 station，1 台在线"},"note":{"reading":false,"text":null,"failing":[],"empty":false}}},"w":1792549612924.762}
  #|{"in":{"id":8,"value":{"app":"desktop","tabs":[{"part":"desktop","label":"桌面","days":[]},{"part":"web","label":"网页","days":[]},{"part":"android","label":"安卓","days":[]},{"part":"station","label":"Station","days":[]},{"part":"cloud","label":"云端","days":[]}],"loading":false}},"w":1792549612924.791}
  #|{"in":{"id":9,"value":{"workspaces":{"01M5E4B7SMW6BHBY7R148X785R":{"alert":1,"unread":1,"tone":"alert","label":"1 个出错 · 1 个有新消息","chat":{"station":"01M5E4B7SMW6BHBY7R148X785R/b6f15a112e33296e79bfd2f7537d5f4313c7392ce6deea2cc95addb6aee947af","key":"ember:c-ce38477477"},"badge":0,"items":[{"kind":"alert","workspace":"01M5E4B7SMW6BHBY7R148X785R","workspaceName":"Dev","station":"01M5E4B7SMW6BHBY7R148X785R/b6f15a112e33296e79bfd2f7537d5f4313c7392ce6deea2cc95addb6aee947af","stationName":"studio","session":"ember:c-ce38477477","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","text":"出错：意外停止","seen":true,"at":1792549612395}],"mineTone":"alert"}},"badge":0,"badgeCounts":"attention","badgeKinds":{"on":true,"wait":true,"failed":true,"done":false,"message":false}}},"w":1792549612924.802}
  #|{"in":{"id":10,"value":{"items":[]}},"w":1792549612924.808}
  #|{"in":{"id":11,"ok":null},"w":1792549612924.811}
  #|{"in":{"id":12,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792549612924.818}
  #|{"in":{"id":13,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792549612924.821}
  #|{"out":{"id":14,"subscribe":{"topic":"longJobs","scope":"01M5E4B7SMW6BHBY7R148X785R"},"keyed":true},"w":1792549612924.852}
  #|{"out":{"id":15,"call":"notify.permission","params":{"state":"unknown"}},"w":1792549612927.582}
  #|{"in":{"id":14,"value":{"groups":[]}},"w":1792549612941.387}
  #|{"in":{"id":15,"ok":null},"w":1792549612941.404}
  #|{"step":"answered notify.permission","w":1792549612941.687}
  #|{"step":"tap 端到端测试","w":1792549612958.29}
  #|{"step":"tap 端到端测试","acted":true,"w":1792549612958.303}
  #|{"out":{"id":16,"subscribe":{"topic":"chat","station":"01M5E4B7SMW6BHBY7R148X785R/b6f15a112e33296e79bfd2f7537d5f4313c7392ce6deea2cc95addb6aee947af","session":"ember:c-ce38477477"},"keyed":true},"w":1792549612974.824}
  #|{"out":{"id":17,"call":"draft.get","params":{"key":"01M5E4B7SMW6BHBY7R148X785R/b6f15a112e33296e79bfd2f7537d5f4313c7392ce6deea2cc95addb6aee947af:ember:c-ce38477477"}},"w":1792549612975.15}
  #|{"step":"answered draft.get","w":1792549612975.301}
  #|{"in":{"id":17,"ok":{"text":"","quotes":[],"files":[],"id":"draft-728f75574b4e053c2d"}},"w":1792549612991.377}
  #|{"in":{"id":16,"value":{"archived":false,"pinned":false,"me":{"id":"alice@example.test","email":"alice@example.test"},"thread":{"id":1,"surface":"ember","channel":"EMBER","threadTs":"1792549433.269000","createdBy":"alice@example.test","creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"createdAt":1792549433269,"sessions":[{"thread":1,"session":"ember:c-ce38477477","connect":"ember","joinedAt":1792549433269}],"last":8,"lastMessage":{"seq":8,"thread":1,"ts":"1792549612.395000","authorKind":"ember","author":"ember","authorName":"still.fail","text":"⚠️ 本轮 agent 未在对话中回复，以下是它最后输出的文字，由 station 代为转发（并非它发布的消息）；回复即可继续：\n\n> Your turn ended without a state, so nobody knows where the chat stands. Only a real unresolved need requires need_human. A factual answer alone does not need a follow-up question; do not invent one. If you still need something after answering a clarification, visibly ask for it; need alone is only a status summary. Cards are optional. Do not reopen a decision the user already made. Decide whether anything in it is still unfinished, then end the turn with exactly one:\n> - all_done: nothing in the chat is left unfinished at all. Post the result with chat_post kind \"all_done\" (or chat_state \"all_done\" if you already posted it), with done: why nothing is left, naming the evidence (a commit, a release, a person's confirmation, the answer given).\n> - need_human: a person has to give, do, decide, confirm or verify something (a card you posted included), or answer a question you asked: kind \"need_human\" with need, what they have to give, do or decide (to verify: where, how and what to look at). If work you started is pending too, mention it after the ask in need.\n> - waiting: only work you started that will bring you back on its own (a background command or agent, a job, a loop watching CI), with nothing asked of anyone, and nothing else you can do meanwhile: chat_state \"waiting\" with seconds, your estimate of how long until it does, and for, what you wait for. Waiting on a person is need_human.\n> - Otherwise: continue the work.","attachments":[],"quotes":[],"createdAt":1792549612395,"time":{"createdAt":{"at":1792549612395,"ago":"刚刚","full":"10/21 10:26:52","until":"1 分钟内","past":true}}},"read":8,"unread":0,"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"firstText":"端到端测试的对话 post:你好，我是测试用的 agent","time":{"createdAt":{"at":1792549433269,"ago":"3 分钟前","full":"10/21 10:23:53","until":"1 分钟内","past":true}}},"title":"端到端测试的对话 post:你好，我是测试用的 agent","people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"agents":[{"session":{"key":"ember:c-ce38477477","connect":"ember","scope":"all","createdBy":"alice@example.test","boundTo":[],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"},"participants":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"}],"runtime":"claude","profile":"cc","profilePinned":false,"runtimeSessionId":"1ecb3f53-8733-4536-8ed7-9b1e9da6987e","workspace":"/tmp/mbe2e-C/data/sessions/ember/c-ce38477477/workspace","running":false,"createdAt":1792549433267,"lastActiveAt":1792549612394,"process":"warm","turns":6,"pending":0,"firstText":"端到端测试的对话 post:你好，我是测试用的 agent","lastTurn":{"id":"013db861-546c-42db-8b6c-a2ea01b58e4b","kind":"nudge","outcome":"completed","startedAt":1792549612393,"endedAt":1792549612394},"statusText":"出错：意外停止","tone":"red","mark":"failed","badgeText":"失败，需要处理","titleText":"端到端测试的对话 post:你好，我是测试用的 agent","agentText":"默认模型","runtimeText":"Claude Code","processText":"保温中","efforts":["low","medium","high","xhigh","max"],"time":{"createdAt":{"at":1792549433267,"ago":"3 分钟前","full":"10/21 10:23:53","until":"1 分钟内","past":true},"lastActiveAt":{"at":1792549612394,"ago":"刚刚","full":"10/21 10:26:52","until":"1 分钟内","past":true}}},"status":"unexpected","badge":"failed","profile":{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792549612239,"time":{"checkedAt":{"at":1792549612239,"ago":"刚刚","full":"10/21 10:26:52","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792549433312,"time":{"checkedAt":{"at":1792549433312,"ago":"3 分钟前","full":"10/21 10:23:53","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]},"profiles":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":true,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792549433312,"time":{"checkedAt":{"at":1792549433312,"ago":"3 分钟前","full":"10/21 10:23:53","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}],"choices":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":true,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792549433312,"time":{"checkedAt":{"at":1792549433312,"ago":"3 分钟前","full":"10/21 10:23:53","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"account":{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":true,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792549433312,"time":{"checkedAt":{"at":1792549433312,"ago":"3 分钟前","full":"10/21 10:23:53","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}},"attention":[],"turns":[{"id":"4fc5c1fd-b0e1-4661-801f-e18b0fe112a1","kind":"input","outcome":"completed","declared":"final","ending":"all_done","startedAt":1792549433334,"endedAt":1792549433406},{"id":"99be7f09-8655-4352-b05d-e733f1b11d12","kind":"input","outcome":"completed","declared":"final","ending":"all_done","startedAt":1792549568368,"endedAt":1792549568393},{"id":"c7416a78-8321-4fdb-9c94-d8631f0ee1f6","kind":"input","outcome":"completed","declared":"final","ending":"all_done","startedAt":1792549570453,"endedAt":1792549570500},{"id":"08e13d20-df74-4c24-a9e8-102cbef36f1d","kind":"input","outcome":"completed","startedAt":1792549612347,"endedAt":1792549612391},{"id":"4677ae14-9a17-4c96-aeac-c9550e5c643a","kind":"nudge","outcome":"completed","startedAt":1792549612392,"endedAt":1792549612393},{"id":"013db861-546c-42db-8b6c-a2ea01b58e4b","kind":"nudge","outcome":"completed","startedAt":1792549612393,"endedAt":1792549612394}],"threads":[{"id":1,"surface":"ember","channel":"EMBER","threadTs":"1792549433.269000","createdBy":"alice@example.test","creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"},"createdAt":1792549433269,"sessions":[{"thread":1,"session":"ember:c-ce38477477","connect":"ember","joinedAt":1792549433269}],"last":8,"lastMessage":{"seq":8,"thread":1,"ts":"1792549612.395000","authorKind":"ember","author":"ember","authorName":"still.fail","text":"⚠️ 本轮 agent 未在对话中回复，以下是它最后输出的文字，由 station 代为转发（并非它发布的消息）；回复即可继续：\n\n> Your turn ended without a state, so nobody knows where the chat stands. Only a real unresolved need requires need_human. A factual answer alone does not need a follow-up question; do not invent one. If you still need something after answering a clarification, visibly ask for it; need alone is only a status summary. Cards are optional. Do not reopen a decision the user already made. Decide whether anything in it is still unfinished, then end the turn with exactly one:\n> - all_done: nothing in the chat is left unfinished at all. Post the result with chat_post kind \"all_done\" (or chat_state \"all_done\" if you already posted it), with done: why nothing is left, naming the evidence (a commit, a release, a person's confirmation, the answer given).\n> - need_human: a person has to give, do, decide, confirm or verify something (a card you posted included), or answer a question you asked: kind \"need_human\" with need, what they have to give, do or decide (to verify: where, how and what to look at). If work you started is pending too, mention it after the ask in need.\n> - waiting: only work you started that will bring you back on its own (a background command or agent, a job, a loop watching CI), with nothing asked of anyone, and nothing else you can do meanwhile: chat_state \"waiting\" with seconds, your estimate of how long until it does, and for, what you wait for. Waiting on a person is need_human.\n> - Otherwise: continue the work.","attachments":[],"quotes":[],"createdAt":1792549612395,"time":{"createdAt":{"at":1792549612395,"ago":"刚刚","full":"10/21 10:26:52","until":"1 分钟内","past":true}}},"read":8,"unread":0,"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"}],"firstText":"端到端测试的对话 post:你好，我是测试用的 agent","time":{"createdAt":{"at":1792549433269,"ago":"3 分钟前","full":"10/21 10:23:53","until":"1 分钟内","past":true}}}],"jobs":[]}],"messages":[{"seq":1,"thread":1,"ts":"1792549433.322000","authorKind":"person","author":"alice@example.test","authorName":"Name of alice","text":"端到端测试的对话 post:你好，我是测试用的 agent","attachments":[],"quotes":[],"createdAt":1792549433322,"mine":true,"system":false,"by":{"name":"Name of alice","picture":"https://example.test/p.png"},"waiting":false,"time":{"createdAt":{"at":1792549433322,"ago":"3 分钟前","full":"10/21 10:23:53","until":"1 分钟内","past":true}}},{"seq":2,"thread":1,"ts":"1792549433.404000","authorKind":"agent","author":"ember:c-ce38477477","text":"你好，我是测试用的 agent","attachments":[],"quotes":[],"declared":"final","ending":"all_done","createdAt":1792549433404,"mine":false,"system":false,"by":{"name":"默认模型","agent":"ember:c-ce38477477","runtime":"claude","here":true},"waiting":false,"time":{"createdAt":{"at":1792549433404,"ago":"3 分钟前","full":"10/21 10:23:53","until":"1 分钟内","past":true}}},{"seq":3,"thread":1,"ts":"1792549568.368000","authorKind":"person","author":"alice@example.test","authorName":"Name of alice","text":"再问一次 post:这一条应当显示为未读 082947","attachments":[],"quotes":[],"createdAt":1792549568368,"mine":true,"system":false,"by":{"name":"Name of alice","picture":"https://example.test/p.png"},"waiting":false,"time":{"createdAt":{"at":1792549568368,"ago":"1 分钟前","full":"10/21 10:26:08","until":"1 分钟内","past":true}}},{"seq":4,"thread":1,"ts":"1792549568.391000","authorKind":"agent","author":"ember:c-ce38477477","text":"这一条应当显示为未读 082947","attachments":[],"quotes":[],"declared":"final","ending":"all_done","createdAt":1792549568391,"mine":false,"system":false,"by":{"name":"默认模型","agent":"ember:c-ce38477477","runtime":"claude","here":true},"waiting":false,"time":{"createdAt":{"at":1792549568391,"ago":"1 分钟前","full":"10/21 10:26:08","until":"1 分钟内","past":true}}},{"seq":5,"thread":1,"ts":"1792549570.450000","authorKind":"person","author":"alice@example.test","authorName":"Name of alice","text":"还没发出去的草稿 082给个表格 082947 md:表格和代码 082947947","attachments":[],"quotes":[],"createdAt":1792549570450,"mine":true,"system":false,"by":{"name":"Name of alice","picture":"https://example.test/p.png"},"waiting":false,"time":{"createdAt":{"at":1792549570450,"ago":"刚刚","full":"10/21 10:26:10","until":"1 分钟内","past":true}}},{"seq":6,"thread":1,"ts":"1792549570.498000","authorKind":"agent","author":"ember:c-ce38477477","text":"表格和代码 082947947\n\n| 页面 | 状态 | 耗时 |\n|:--|:-:|--:|\n| 首页 | 完成 | 1.2 s |\n| 聊天页的列表和输入框 | 进行中 | 3.4 s |\n\n```ts\nexport function placeRows(rows: Row[], from: number): number {\n  const visible = rows.filter((r) => r.top >= from && r.top < from + window.innerHeight * 2) // only the rows near the screen\n  return visible.length\n}\n```\n\n详见 https://example.com/e2e/082947947","attachments":[],"quotes":[],"declared":"final","ending":"all_done","createdAt":1792549570498,"mine":false,"system":false,"by":{"name":"默认模型","agent":"ember:c-ce38477477","runtime":"claude","here":true},"waiting":false,"time":{"createdAt":{"at":1792549570498,"ago":"刚刚","full":"10/21 10:26:10","until":"1 分钟内","past":true}}},{"seq":7,"thread":1,"ts":"1792549612.308000","authorKind":"person","author":"alice@example.test","authorName":"Name of alice","text":"断网时发出的消息 082947","attachments":[],"quotes":[],"createdAt":1792549612308,"mine":true,"system":false,"by":{"name":"Name of alice","picture":"https://example.test/p.png"},"waiting":false,"time":{"createdAt":{"at":1792549612308,"ago":"刚刚","full":"10/21 10:26:52","until":"1 分钟内","past":true}}},{"seq":8,"thread":1,"ts":"1792549612.395000","authorKind":"ember","author":"ember","authorName":"still.fail","text":"⚠️ 本轮 agent 未在对话中回复，以下是它最后输出的文字，由 station 代为转发（并非它发布的消息）；回复即可继续：\n\n> Your turn ended without a state, so nobody knows where the chat stands. Only a real unresolved need requires need_human. A factual answer alone does not need a follow-up question; do not invent one. If you still need something after answering a clarification, visibly ask for it; need alone is only a status summary. Cards are optional. Do not reopen a decision the user already made. Decide whether anything in it is still unfinished, then end the turn with exactly one:\n> - all_done: nothing in the chat is left unfinished at all. Post the result with chat_post kind \"all_done\" (or chat_state \"all_done\" if you already posted it), with done: why nothing is left, naming the evidence (a commit, a release, a person's confirmation, the answer given).\n> - need_human: a person has to give, do, decide, confirm or verify something (a card you posted included), or answer a question you asked: kind \"need_human\" with need, what they have to give, do or decide (to verify: where, how and what to look at). If work you started is pending too, mention it after the ask in need.\n> - waiting: only work you started that will bring you back on its own (a background command or agent, a job, a loop watching CI), with nothing asked of anyone, and nothing else you can do meanwhile: chat_state \"waiting\" with seconds, your estimate of how long until it does, and for, what you wait for. Waiting on a person is need_human.\n> - Otherwise: continue the work.","attachments":[],"quotes":[],"createdAt":1792549612395,"mine":false,"system":true,"reportable":true,"by":{"name":"still.fail"},"waiting":false,"time":{"createdAt":{"at":1792549612395,"ago":"刚刚","full":"10/21 10:26:52","until":"1 分钟内","past":true}}}],"elsewhere":[],"more":false,"newer":false,"caught":8,"unreadAbove":false,"outbox":[],"link":{"state":"online"},"offline":false,"pending":false,"asks":[],"publish":{"may":true,"links":[]}}},"w":1792549612991.502}
  #|{"out":{"id":18,"subscribe":{"topic":"stations","scope":"01M5E4B7SMW6BHBY7R148X785R"},"keyed":true},"w":1792549612991.667}
  #|{"out":{"id":19,"subscribe":{"topic":"chatJobs","station":"01M5E4B7SMW6BHBY7R148X785R/b6f15a112e33296e79bfd2f7537d5f4313c7392ce6deea2cc95addb6aee947af","session":"ember:c-ce38477477"},"keyed":true},"w":1792549612991.676}
  #|{"out":{"id":20,"call":"picture","params":{"url":"https://example.test/p.png"}},"w":1792549612991.687}
  #|{"out":{"id":21,"call":"client.focus","params":{"chat":{"station":"01M5E4B7SMW6BHBY7R148X785R/b6f15a112e33296e79bfd2f7537d5f4313c7392ce6deea2cc95addb6aee947af","session":"ember:c-ce38477477","thread":1,"end":true}}},"w":1792549613003.968}
  #|{"in":{"id":18,"value":[{"station":"01M5E4B7SMW6BHBY7R148X785R/b6f15a112e33296e79bfd2f7537d5f4313c7392ce6deea2cc95addb6aee947af","id":"b6f15a112e33296e79bfd2f7537d5f4313c7392ce6deea2cc95addb6aee947af","name":"studio","summary":"空闲 · Apple M4 · 16 GB · macOS 27.0.1","face":"idle","line":"Apple M4","online":true,"reconnecting":false,"lastSeen":1792549612,"version":"0.1.0","link":{"state":"online"},"runtimes":[{"runtime":"claude","models":["claude-sonnet-5-5"]}],"models":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792549433312,"time":{"checkedAt":{"at":1792549433312,"ago":"3 分钟前","full":"10/21 10:23:53","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"overview":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null,"summaryText":"最近 7 天检查了 0 个 chat","changeText":null}},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","email":"alice@example.test","name":"Name of alice","sub":"alice","role":"owner","workspace":"01M5E4B7SMW6BHBY7R148X785R","device":"3a57bbf1171f1168ccb6950b318d7b053a40bc2ef1dec65aeba6d4bc4d04e66d"},"connects":[],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792549612239,"time":{"checkedAt":{"at":1792549612239,"ago":"刚刚","full":"10/21 10:26:52","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792549433312,"time":{"checkedAt":{"at":1792549433312,"ago":"3 分钟前","full":"10/21 10:23:53","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]}],"processes":[],"counts":{"sessions":2,"running":0,"warm":1},"mesh":{"state":"running","origin":"http://127.0.0.1:18787","station":"b6f15a112e33296e79bfd2f7537d5f4313c7392ce6deea2cc95addb6aee947af","workspace":"Dev","workspaceId":"01M5E4B7SMW6BHBY7R148X785R","name":"studio"},"slackUsers":[],"slackTeams":[],"slackApps":[],"feishuRegistrations":[],"disk":{"freeBytes":45802393600,"totalBytes":245107195904},"logins":[],"machineLogins":[],"sharing":true,"consoleSignIn":true,"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"google","name":"Google Gemini","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xai","name":"xAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"mistral","name":"Mistral","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"deepseek","name":"DeepSeek","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen","name":"Qwen","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai","name":"Kimi","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai","name":"Z.ai","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax","name":"MiniMax","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ant-ling","name":"Ant Ling","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"jev","name":"Jev","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen-cn","name":"Qwen (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"openrouter","name":"OpenRouter","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"opencode","name":"OpenCode Zen","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"groq","name":"Groq","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"together","name":"Together AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"fireworks","name":"Fireworks","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cerebras","name":"Cerebras","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"huggingface","name":"Hugging Face","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"nvidia","name":"NVIDIA","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"baseten","name":"Baseten","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ollama","name":"Ollama","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"custom","name":"Custom","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""}],"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792549609834},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.305","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792549609834},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-news/apps/e2e-local/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792549609834},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-news/apps/e2e-local/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792549609834},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","latest":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-news/apps/e2e-local/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792549609834},{"id":"cursor","name":"Cursor","installed":false,"latest":"1.0.40","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792549609834},{"id":"devin","name":"Devin","installed":true,"version":"3000.11.92","latest":"3000.11.92","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-news/apps/e2e-local/ember/station/test/fake/devin，不是用 Devin 的安装脚本装的，需在该机器上手动更新","state":"idle","checkedAt":1792549609834}],"processesText":"没有运行中的 agent 进程","agentEnv":[],"drive":{"roots":[],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false}},"betaOffered":false,"host":{"hostname":"3720-Mac-mini-1","os":"macOS 27.0.1","arch":"arm64","cpus":10,"cpuModel":"Apple M4","load":0.33,"cpuBusy":0.08,"uptimeSec":28930,"memory":{"totalBytes":17179869184,"usedBytes":9360801792,"swapUsedBytes":300742083},"disk":{"path":"/tmp/mbe2e-C/data","totalBytes":245107195904,"freeBytes":45805400064},"emberRssBytes":131512432,"checkedAt":1792549568532,"summary":"10 核 · 16 GB","line":"macOS 27.0.1 · 10 核 · 16 GB · 已运行 0 天","facts":["3720-Mac-mini-1","macOS 27.0.1","arm64 · 10 核","已运行 8 小时"],"meters":[{"label":"CPU","short":"CPU","percent":8,"left":92,"level":"ok","value":"8%","remaining":"空闲 92%","big":"92","unit":"%","title":"CPU 空闲","total":"负载 3.3","note":"负载 3.3 · Apple M4"},{"label":"内存","short":"内存","percent":54,"left":46,"level":"ok","value":"8.7 GB / 16.0 GB","remaining":"剩 7.3 G","big":"7.3","unit":"GB","title":"内存剩","total":"共 16 GB","note":"swap 0.3 GB"},{"label":"磁盘","short":"磁盘","percent":81,"left":19,"level":"amber","value":"剩余 42.7 GB / 228 GB","remaining":"剩 42.7 G","big":"42.7","unit":"GB","title":"磁盘剩","total":"共 228 GB"}],"identity":"Apple M4 · 16 GB · macOS 27.0.1","details":[{"label":"主机名","value":"3720-Mac-mini-1"},{"label":"芯片","value":"Apple M4 · 10 核 · arm64"},{"label":"已运行","value":"8 小时"},{"label":"still.fail","value":"进程占用 125 MB"}],"usage":"内存 8.7 GB / 16.0 GB · 磁盘 剩余 42.7 GB / 228 GB","emberText":"still.fail 125 MB"},"way":{"path":"直连","via":"direct"},"time":{"lastSeen":{"at":1792549612000,"ago":"刚刚","full":"10/21 10:26:52","until":"1 分钟内","past":true}},"joined":false}]},"w":1792549613008.138}
  #|{"in":{"id":19,"value":{"jobs":[],"servicesNote":"","jobsNote":"","current":0,"ended":0,"clear":[],"allText":"全部 0 个","clearText":"清除 0 个已结束的","hiddenText":"另有 0 个已停止或结束"}},"w":1792549613008.219}
  #|{"in":{"id":21,"ok":null},"w":1792549613008.223}
  #|{"step":"answered picture","w":1792549613015.152}
  #|{"in":{"id":18,"delta":[{"path":[0,"host","checkedAt"],"set":1792549612399},{"path":[0,"host","details",3,"value"],"set":"进程占用 136 MB"},{"path":[0,"host","disk","freeBytes"],"set":45802786816},{"path":[0,"host","emberRssBytes"],"set":142849800},{"path":[0,"host","emberText"],"set":"still.fail 136 MB"},{"path":[0,"host","load"],"set":0.21},{"path":[0,"host","memory","usedBytes"],"set":9306095616},{"path":[0,"host","meters",0,"note"],"set":"负载 2.1 · Apple M4"},{"path":[0,"host","meters",0,"total"],"set":"负载 2.1"},{"path":[0,"host","uptimeSec"],"set":28974},{"path":[0,"overview","disk","freeBytes"],"set":45802364928}]},"w":1792549613108.055}
  #|{"in":{"id":20,"error":{"code":"picture","message":"无法加载图片：error sending request for url (https://example.test/p.png): client error (Connect): tls handshake eof"}},"w":1792549613191.405}
  #|{"step":"answered client.focus","w":1792549613210.594}
  #|{"step":"wait 300","w":1792549613226.978}
  #|{"step":"now until =studio","w":1792549613543.215}
  #|{"step":"tap 发消息","w":1792549613543.274}
  #|{"step":"tap 发消息","acted":true,"w":1792549613543.324}
  #|{"step":"type 给个链接 082947 md:链接 082947","w":1792549613570.093}
  #|{"step":"type 给个链接 082947 md:链接 082947","acted":true,"w":1792549613570.148}
  #|{"out":{"id":22,"call":"session.warm","params":{"station":"01M5E4B7SMW6BHBY7R148X785R/b6f15a112e33296e79bfd2f7537d5f4313c7392ce6deea2cc95addb6aee947af","key":"ember:c-ce38477477"}},"w":1792549613575.139}
  #|{"step":"answered session.warm","w":1792549613578.828}
  #|{"in":{"id":22,"ok":{"ok":true}},"w":1792549613591.417}
  #|{"step":"tap icon:arrow-up","w":1792549613610.325}
  #|{"step":"tap icon:arrow-up","acted":true,"w":1792549613610.375}
  #|{"out":{"id":23,"call":"chat.send","params":{"station":"01M5E4B7SMW6BHBY7R148X785R/b6f15a112e33296e79bfd2f7537d5f4313c7392ce6deea2cc95addb6aee947af","text":"给个链接 082947 md:链接 082947","attachments":[],"quotes":[],"thread":1}},"w":1792549613625.218}
  #|{"step":"answered chat.send","w":1792549613628.757}
  #|{"in":{"id":23,"ok":{"seq":9}},"w":1792549613658.053}
  #|{"step":"wait 600","w":1792549613675.444}
  #|{"in":{"id":16,"delta":[{"path":["agents",0,"session","lastActiveAt"],"set":1792549613686},{"path":["agents",0,"session","lastTurn","declared"],"set":"final"},{"path":["agents",0,"session","lastTurn","endedAt"],"set":1792549613686},{"path":["agents",0,"session","lastTurn","ending"],"set":"all_done"},{"path":["agents",0,"session","lastTurn","id"],"set":"952b35a4-df80-4e7c-b247-e024b3dfc8c8"},{"path":["agents",0,"session","lastTurn","kind"],"set":"input"},{"path":["agents",0,"session","lastTurn","need"],"set":"answered the question that was asked"},{"path":["agents",0,"session","lastTurn","startedAt"],"set":1792549613634},{"path":["agents",0,"session","statusText"],"set":"已完成：answered the question that was asked"},{"path":["agents",0,"session","time","lastActiveAt","at"],"set":1792549613686},{"path":["agents",0,"session","time","lastActiveAt","full"],"set":"10/21 10:26:53"},{"path":["agents",0,"session","tone"],"set":"green"},{"path":["agents",0,"session","turns"],"set":7},{"path":["agents",0,"session","badgeText"],"remove":true},{"path":["agents",0,"session","mark"],"remove":true},{"path":["agents",0,"status"],"set":"final"},{"path":["agents",0,"threads",0,"last"],"set":10},{"path":["agents",0,"threads",0,"lastMessage","author"],"set":"ember:c-ce38477477"},{"path":["agents",0,"threads",0,"lastMessage","authorKind"],"set":"agent"},{"path":["agents",0,"threads",0,"lastMessage","createdAt"],"set":1792549613684},{"path":["agents",0,"threads",0,"lastMessage","declared"],"set":"final"},{"path":["agents",0,"threads",0,"lastMessage","ending"],"set":"all_done"},{"path":["agents",0,"threads",0,"lastMessage","seq"],"set":10},{"path":["agents",0,"threads",0,"lastMessage","text"],"set":"链接 082947\n\n| 页面 | 状态 | 耗时 |\n|:--|:-:|--:|\n| 首页 | 完成 | 1.2 s |\n| 聊天页的列表和输入框 | 进行中 | 3.4 s |\n\n```ts\nexport function placeRows(rows: Row[], from: number): number {\n  const visible = rows.filter((r) => r.top >= from && r.top < from + window.innerHeight * 2) // only the rows near the screen\n  return visible.length\n}\n```\n\n详见 https://example.com/e2e/082947"},{"path":["agents",0,"threads",0,"lastMessage","time","createdAt","at"],"set":1792549613684},{"path":["agents",0,"threads",0,"lastMessage","time","createdAt","full"],"set":"10/21 10:26:53"},{"path":["agents",0,"threads",0,"lastMessage","ts"],"set":"1792549613.684000"},{"path":["agents",0,"threads",0,"lastMessage","authorName"],"remove":true},{"path":["agents",0,"threads",0,"unread"],"set":1},{"path":["agents",0,"turns"],"append":[{"id":"952b35a4-df80-4e7c-b247-e024b3dfc8c8","kind":"input","outcome":"completed","declared":"final","ending":"all_done","startedAt":1792549613634,"endedAt":1792549613686}]},{"path":["agents",0,"badge"],"remove":true},{"path":["outbox"],"key":["id"],"put":{"id":"out-18c959ed6b3daf3ae8","text":"给个链接 082947 md:链接 082947","attachments":[],"quotes":[],"createdAt":1792549613626,"state":"sending","seq":9,"time":{"createdAt":{"at":1792549613626,"ago":"刚刚","full":"10/21 10:26:53","until":"1 分钟内","past":true}}},"before":null},{"path":["thread","last"],"set":10},{"path":["thread","lastMessage","author"],"set":"ember:c-ce38477477"},{"path":["thread","lastMessage","authorKind"],"set":"agent"},{"path":["thread","lastMessage","createdAt"],"set":1792549613684},{"path":["thread","lastMessage","declared"],"set":"final"},{"path":["thread","lastMessage","ending"],"set":"all_done"},{"path":["thread","lastMessage","seq"],"set":10},{"path":["thread","lastMessage","text"],"set":"链接 082947\n\n| 页面 | 状态 | 耗时 |\n|:--|:-:|--:|\n| 首页 | 完成 | 1.2 s |\n| 聊天页的列表和输入框 | 进行中 | 3.4 s |\n\n```ts\nexport function placeRows(rows: Row[], from: number): number {\n  const visible = rows.filter((r) => r.top >= from && r.top < from + window.innerHeight * 2) // only the rows near the screen\n  return visible.length\n}\n```\n\n详见 https://example.com/e2e/082947"},{"path":["thread","lastMessage","time","createdAt","at"],"set":1792549613684},{"path":["thread","lastMessage","time","createdAt","full"],"set":"10/21 10:26:53"},{"path":["thread","lastMessage","ts"],"set":"1792549613.684000"},{"path":["thread","lastMessage","authorName"],"remove":true},{"path":["thread","unread"],"set":1}]},"w":1792549613724.802}
  #|{"in":{"id":9,"value":{"workspaces":{"01M5E4B7SMW6BHBY7R148X785R":{"alert":0,"unread":2,"tone":"done","label":"2 个有新消息","chat":{"station":"01M5E4B7SMW6BHBY7R148X785R/b6f15a112e33296e79bfd2f7537d5f4313c7392ce6deea2cc95addb6aee947af","key":"ember:c-ce38477477"},"badge":0,"items":[],"mineTone":"done"}},"badge":0,"badgeCounts":"attention","badgeKinds":{"on":true,"wait":true,"failed":true,"done":false,"message":false}}},"w":1792549613724.957}
  #|{"in":{"id":7,"delta":[{"path":["days"],"key":["daysAgo"],"patch":0,"ops":[{"path":["at"],"set":1792549613684},{"path":["items"],"key":["station","id"],"patch":["01M5E4B7SMW6BHBY7R148X785R/b6f15a112e33296e79bfd2f7537d5f4313c7392ce6deea2cc95addb6aee947af","ember:c-ce38477477"],"ops":[{"path":["agents",0,"lastTurn","declared"],"set":"final"},{"path":["agents",0,"lastTurn","endedAt"],"set":1792549613686},{"path":["agents",0,"lastTurn","ending"],"set":"all_done"},{"path":["agents",0,"lastTurn","id"],"set":"952b35a4-df80-4e7c-b247-e024b3dfc8c8"},{"path":["agents",0,"lastTurn","kind"],"set":"input"},{"path":["agents",0,"lastTurn","need"],"set":"answered the question that was asked"},{"path":["agents",0,"lastTurn","startedAt"],"set":1792549613634},{"path":["agents",0,"statusText"],"set":"已完成：answered the question that was asked"},{"path":["agents",0,"badgeText"],"remove":true},{"path":["agents",0,"mark"],"remove":true},{"path":["last","author"],"set":"ember:c-ce38477477"},{"path":["last","authorKind"],"set":"agent"},{"path":["last","by","kind"],"set":"agent"},{"path":["last","by","label"],"set":"agent"},{"path":["last","by","name"],"set":"agent"},{"path":["last","by","runtime"],"set":"claude"},{"path":["last","createdAt"],"set":1792549613684},{"path":["last","preview"],"set":"链接 082947 页面 状态 耗时 :-- :-: --: 首页 完成 1.2 s 聊天页的列表和输入框 进行中 3.4 s export function placeRows(rows: Row[], from: number): number { const visible = rows.filter((r) => r."},{"path":["last","seq"],"set":10},{"path":["last","text"],"set":"链接 082947\n\n| 页面 | 状态 | 耗时 |\n|:--|:-:|--:|\n| 首页 | 完成 | 1.2 s |\n| 聊天页的列表和输入框 | 进行中 | 3.4 s |\n\n```ts\nexport function placeRows(rows: Row[], from: number): number {\n  const visible = rows.filter((r) => r."},{"path":["last","time","createdAt","at"],"set":1792549613684},{"path":["last","time","createdAt","full"],"set":"10/21 10:26:53"},{"path":["last","authorName"],"remove":true},{"path":["lastActiveAt"],"set":1792549613684},{"path":["time","lastActiveAt","at"],"set":1792549613684},{"path":["time","lastActiveAt","full"],"set":"10/21 10:26:53"},{"path":["tone"],"set":"done"},{"path":["unread"],"set":true},{"path":["state"],"remove":true},{"path":["stateText"],"remove":true}]}]}]},"w":1792549613724.978}
  #|{"in":{"id":18,"delta":[{"path":[0,"overview","disk","freeBytes"],"set":45802405888}]},"w":1792549613725.029}
  #|{"in":{"id":16,"delta":[{"path":["messages"],"key":["seq","outgoing"],"put":{"seq":10,"thread":1,"ts":"1792549613.684000","authorKind":"agent","author":"ember:c-ce38477477","text":"链接 082947\n\n| 页面 | 状态 | 耗时 |\n|:--|:-:|--:|\n| 首页 | 完成 | 1.2 s |\n| 聊天页的列表和输入框 | 进行中 | 3.4 s |\n\n```ts\nexport function placeRows(rows: Row[], from: number): number {\n  const visible = rows.filter((r) => r.top >= from && r.top < from + window.innerHeight * 2) // only the rows near the screen\n  return visible.length\n}\n```\n\n详见 https://example.com/e2e/082947","attachments":[],"quotes":[],"declared":"final","ending":"all_done","createdAt":1792549613684,"mine":false,"system":false,"by":{"name":"默认模型","agent":"ember:c-ce38477477","runtime":"claude","here":true},"waiting":false,"said":true,"time":{"createdAt":{"at":1792549613684,"ago":"刚刚","full":"10/21 10:26:53","until":"1 分钟内","past":true}}},"before":null},{"path":["messages"],"key":["seq","outgoing"],"put":{"outgoing":"out-18c959ed6b3daf3ae8","seq":9,"thread":1,"ts":"1792549613.631000","authorKind":"person","author":"alice@example.test","authorName":"Name of alice","text":"给个链接 082947 md:链接 082947","attachments":[],"quotes":[],"createdAt":1792549613631,"mine":true,"system":false,"by":{"name":"Name of alice","picture":"https://example.test/p.png"},"waiting":false,"said":true,"time":{"createdAt":{"at":1792549613631,"ago":"刚刚","full":"10/21 10:26:53","until":"1 分钟内","past":true}}},"before":[10,null]},{"path":["outbox"],"key":["id"],"drop":"out-18c959ed6b3daf3ae8"}]},"w":1792549613841.409}
  #|{"in":{"id":16,"delta":[{"path":["agents",0,"threads",0,"read"],"set":10},{"path":["agents",0,"threads",0,"unread"],"set":0},{"path":["archivable"],"set":true},{"path":["thread","read"],"set":10},{"path":["thread","unread"],"set":0}]},"w":1792549613908.065}
  #|{"in":{"id":7,"delta":[{"path":["days"],"key":["daysAgo"],"patch":0,"ops":[{"path":["at"],"set":1792549567401},{"path":["items"],"key":["station","id"],"patch":["01M5E4B7SMW6BHBY7R148X785R/b6f15a112e33296e79bfd2f7537d5f4313c7392ce6deea2cc95addb6aee947af","ember:c-ce38477477"],"ops":[{"path":["archivable"],"set":true},{"path":["settled"],"set":true},{"path":["stateText"],"set":"已完成：answered the question that was asked"},{"path":["unread"],"set":false},{"path":["tone"],"remove":true}]},{"path":["items"],"key":["station","id"],"move":["01M5E4B7SMW6BHBY7R148X785R/b6f15a112e33296e79bfd2f7537d5f4313c7392ce6deea2cc95addb6aee947af","ember:c-929cb60322"],"before":["01M5E4B7SMW6BHBY7R148X785R/b6f15a112e33296e79bfd2f7537d5f4313c7392ce6deea2cc95addb6aee947af","ember:c-ce38477477"]}]}]},"w":1792549613908.129}
  #|{"in":{"id":9,"delta":[{"path":["workspaces","01M5E4B7SMW6BHBY7R148X785R","label"],"set":"1 个有新消息"},{"path":["workspaces","01M5E4B7SMW6BHBY7R148X785R","unread"],"set":1}]},"w":1792549613908.188}
  #|{"step":"now gone 正在发送","w":1792549614292.172}
  #|{"step":"until example.com/e2e","w":1792549614292.196}
  #|{"step":"tap example.com/e2e","w":1792549614292.211}
  #|{"step":"tap example.com/e2e","acted":true,"w":1792549614292.23}
  #|{"out":{"id":24,"call":"link.parse","params":{"url":"https://example.com/e2e/082947"}},"w":1792549614308.535}
  #|{"step":"answered link.parse","w":1792549614309.544}
  #|{"in":{"id":24,"ok":null},"w":1792549614324.738}
  #|{"step":"","w":1792549614343.044}
  #|{"textrec":{"ib":["bfd9b0d6dc602826",12668,64],"r":[56,56,56,56]}}
  #|{"textrec":{"s":[13,400,0,"正在读取你的 workspace"],"r":[0,1,12.898832684824903,0,1,1,12.898832684824903,1,2,1,12.898832684824903,2,3,1,12.898832684824903,3,4,1,12.898832684824896,4,5,1,12.898832684824896,5,6,1,3.580078125,-1,7,1,9.8642578125,6,8,1,7.4775390625,7,9,1,4.875,8,10,1,6.85546875,9,11,1,6.6015625,10,12,1,7.8583984375,11,13,1,7.0966796875,12,14,1,7.1982421875,13,15,1,7.3505859375,14]}}
  #|{"textrec":{"m":[13,400,0],"r":[12.568359375,2.7421875,18,12.568359375,2.7421875,0]}}
  #|{"textrec":{"s":[24,700,0,"Dev"],"r":[0,1,17.075823068618774,15,1,1,13.365240812301636,16,2,1,12.759063005447388,17]}}
  #|{"textrec":{"m":[24,700,0],"r":[23.203125,5.0625,34,20.638916015625,3.361083984375,0]}}
  #|{"textrec":{"g":15,"r":[0,0,18,19,0,-18,0]}}
  #|{"textrec":{"g":16,"r":[19,0,15,16,-1,-14,0]}}
  #|{"textrec":{"g":17,"r":[35,0,15,15,-1,-14,0]}}
  #|{"textrec":{"ib":["02698e60df92657e",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"ib":["1d51432b25a425eb",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"ib":["fdb526ba00f881f4",3232,64],"r":[28,28,28,28]}}
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
  #|{"textrec":{"s":[16,600,0,"另一台设备新建的对话 082947 post:新对话里的回复 082947"],"r":[0,1,15.875486381322958,56,1,1,15.875486381322958,57,2,1,15.875486381322958,58,3,1,15.875486381322958,59,4,1,15.875486381322958,60,5,1,15.875486381322958,61,6,1,15.875486381322958,62,7,1,15.875486381322958,63,8,1,15.875486381322958,64,9,1,15.875486381322958,65,10,1,3.95001220703125,-1,11,1,10.31976318359375,66,12,1,10.465335845947266,67,13,1,9.744510650634766,68,14,1,10.3499755859375,69,15,1,10.42471694946289,70,16,1,9.153106689453125,71,17,1,3.95001220703125,-1,18,1,9.824199676513672,72,19,1,9.432537078857422,73,20,1,8.471200942993164,74,21,1,5.973020553588867,75,22,1,4.952056884765625,76,23,1,15.875486381322958,61,24,1,15.875486381322958,64,25,1,15.875486381322958,65,26,1,15.875486381322958,77,27,1,15.875486381322958,63,28,1,15.875486381322958,78,29,1,15.875486381322958,79,30,1,3.95001220703125,-1,31,1,10.31976318359375,66,32,1,10.465335845947266,67,33,1,9.744510650634766,68,34,1,10.3499755859375,69,35,1,10.42471694946289,70,36,1,9.153106689453125,71]}}
  #|{"textrec":{"m":[16,600,0],"r":[15.46875,3.375,23,15.46875,3.375,0]}}
  #|{"textrec":{"s":[14,400,0,"新对话里的回复 082947"],"r":[0,1,13.891050583657588,80,1,1,13.891050583657588,81,2,1,13.891050583657588,82,3,1,13.891050583657588,83,4,1,13.891050583657588,84,5,1,13.891050583657588,85,6,1,13.891050583657588,86,7,1,3.787109375,-1,8,1,8.66796875,87,9,1,8.791015625,88,10,1,8.298828125,89,11,1,8.763671874999986,90,12,1,8.859375,91,13,1,7.8203125,92]}}
  #|{"textrec":{"s":[16,600,0,"…"],"r":[0,1,14.076484680175781,93]}}
  #|{"textrec":{"s":[16,600,0,"另一台设备新建的对话 082947 post:新对话…"],"r":[0,1,15.875486381322958,56,1,1,15.875486381322958,57,2,1,15.875486381322958,58,3,1,15.875486381322958,59,4,1,15.875486381322958,60,5,1,15.875486381322958,61,6,1,15.875486381322958,62,7,1,15.875486381322958,63,8,1,15.875486381322958,64,9,1,15.875486381322958,65,10,1,3.95001220703125,-1,11,1,10.31976318359375,66,12,1,10.465335845947266,67,13,1,9.744510650634766,68,14,1,10.3499755859375,69,15,1,10.42471694946289,70,16,1,9.153106689453125,71,17,1,3.95001220703125,-1,18,1,9.824199676513672,72,19,1,9.432537078857422,73,20,1,8.471200942993164,74,21,1,5.973020553588867,75,22,1,4.952056884765625,76,23,1,15.875486381322958,61,24,1,15.875486381322958,64,25,1,15.875486381322958,65,26,1,14.076484680175781,93]}}
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
  #|{"textrec":{"g":56,"r":[580,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":57,"r":[598,0,17,5,-1,-8,0]}}
  #|{"textrec":{"g":58,"r":[616,0,16,17,0,-14,0]}}
  #|{"textrec":{"g":59,"r":[633,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":60,"r":[652,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":61,"r":[670,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":62,"r":[689,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":63,"r":[707,0,16,17,0,-14,0]}}
  #|{"textrec":{"g":64,"r":[724,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":65,"r":[742,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":66,"r":[761,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":67,"r":[773,0,12,15,-1,-13,0]}}
  #|{"textrec":{"g":68,"r":[786,0,11,14,0,-13,0]}}
  #|{"textrec":{"g":69,"r":[798,0,12,15,-1,-13,0]}}
  #|{"textrec":{"g":70,"r":[811,0,12,14,-1,-13,0]}}
  #|{"textrec":{"g":71,"r":[824,0,11,14,-1,-13,0]}}
  #|{"textrec":{"g":72,"r":[836,0,11,14,0,-10,0]}}
  #|{"textrec":{"g":73,"r":[848,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":74,"r":[860,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":75,"r":[872,0,8,14,-1,-12,0]}}
  #|{"textrec":{"g":76,"r":[881,0,5,12,0,-10,0]}}
  #|{"textrec":{"g":93,"r":[887,0,14,6,0,-4,0]}}
  #|{"textrec":{"g":80,"r":[902,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":81,"r":[919,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":82,"r":[935,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":83,"r":[952,0,15,14,-1,-12,0]}}
  #|{"textrec":{"g":84,"r":[968,0,14,16,0,-13,0]}}
  #|{"textrec":{"g":85,"r":[983,0,14,15,0,-12,0]}}
  #|{"textrec":{"g":86,"r":[998,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":87,"r":[1014,0,10,14,-1,-12,0]}}
  #|{"textrec":{"g":88,"r":[1025,0,11,14,-1,-12,0]}}
  #|{"textrec":{"g":89,"r":[1037,0,9,13,0,-12,0]}}
  #|{"textrec":{"g":90,"r":[1047,0,11,14,-1,-12,0]}}
  #|{"textrec":{"g":91,"r":[1059,0,11,12,-1,-11,0]}}
  #|{"textrec":{"g":92,"r":[1071,0,10,12,-1,-11,0]}}
  #|{"textrec":{"ib":["33d1dfbf90932d3b",1241,64],"r":[17,17,17,17]}}
  #|{"textrec":{"ib":["182b7158e0c0cae1",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["d61ec6305f7d8c8b",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["8bf9607b651cec61",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 post:你好，我是测试用的 agent"],"r":[0,1,15.875486381322958,94,1,1,15.875486381322958,95,2,1,15.875486381322958,94,3,1,15.875486381322958,96,4,1,15.875486381322958,97,5,1,15.875486381322958,63,6,1,15.875486381322958,64,7,1,15.875486381322958,65,8,1,3.95001220703125,-1,9,1,9.824199676513672,72,10,1,9.432537078857422,73,11,1,8.471200942993164,74,12,1,5.973020553588867,75,13,1,4.952056884765625,76,14,1,15.875486381322958,98,15,1,15.875486381322958,99,16,1,16.09338521400778,100,17,1,15.875486381322958,101,18,1,15.875486381322958,102,19,1,15.87548638132293,96,20,1,15.875486381322958,97,21,1,15.875486381322958,103,22,1,15.875486381322958,63,23,1,3.95001220703125,-1,24,1,8.899068832397461,104,25,1,9.801153182983398,105,26,1,9.127458572387695,106,27,1,9.466253280639648,107,28,1,5.999713897705078,75]}}
  #|{"textrec":{"s":[8,600,0,"N"],"r":[0,1,6.271738052368164,108]}}
  #|{"textrec":{"m":[8,600,0],"r":[7.734375,1.6875,11,7.734375,1.6875,0]}}
  #|{"textrec":{"s":[15,400,0,"本轮 agent 未在对话中回复，以下是它最后输出的文字，由 station 代为转发（并非它发布的消息）；回复即可继续："],"r":[0,1,14.883268482490273,109,1,1,14.883268482490273,110,2,1,3.984375,-1,3,1,8.0419921875,111,4,1,8.90625,112,5,1,8.3349609375,113,6,1,8.51806640625,114,7,1,5.21484375,115,8,1,3.984375,-1,9,1,14.883268482490266,116,10,1,14.88326848249028,117,11,1,14.88326848249028,118,12,1,14.88326848249028,119,13,1,14.88326848249028,120,14,1,14.88326848249028,121,15,1,14.88326848249028,122,16,1,15.08754863813229,123,17,1,14.88326848249028,124,18,1,14.88326848249028,125,19,1,14.88326848249028,126,20,1,14.88326848249028,127,21,1,14.88326848249028,128,22,1,14.88326848249028,129,23,1,14.88326848249028,130,24,1,14.88326848249028,131,25,1,14.88326848249028,132,26,1,14.88326848249028,133,27,1,14.88326848249028,134,28,1,15.087548638132319,123,29,1,14.88326848249028,135,30,1,3.984375,-1,31,1,7.58056640625,136,32,1,5.17822265625,115,33,1,8.0419921875,111,34,1,5.21484375,115,35,1,3.4716796875,137,36,1,8.6279296875,138,37,1,8.51806640625,114,38,1,3.984375,-1,39,1,14.88326848249028,139,40,1,14.88326848249028,140,41,1,14.88326848249028,141,42,1,22.38326848249028,142,43,1,4.698443579766547,143,44,1,14.88326848249028,144,45,1,14.88326848249028,145,46,1,14.88326848249028,127,47,1,14.88326848249028,142,48,1,14.88326848249028,146,49,1,14.88326848249028,132,50,1,14.88326848249028,147,51,1,14.88326848249028,148,52,1,6.296206225680976,149,53,1,15.087548638132262,150,54,1,14.88326848249028,121,55,1,14.88326848249028,122,56,1,14.88326848249028,151,57,1,14.88326848249028,152,58,1,14.88326848249028,153,59,1,14.88326848249028,154,60,1,7.587548638132262,155]}}
  #|{"textrec":{"s":[15,400,0," · "],"r":[0,1,3.984375,-1,1,1,7.186782927948601,156,2,1,3.984375,-1]}}
  #|{"textrec":{"s":[15,600,0,"上报"],"r":[0,1,14.883268482490273,157,1,1,14.883268482490273,158]}}
  #|{"textrec":{"s":[15,400,0,"…"],"r":[0,1,11.8359375,159]}}
  #|{"textrec":{"s":[15,400,0,"本轮 agent 未在对话中回复，以下是它最后…"],"r":[0,1,14.883268482490273,109,1,1,14.883268482490273,110,2,1,3.984375,-1,3,1,8.0419921875,111,4,1,8.90625,112,5,1,8.3349609375,113,6,1,8.51806640625,114,7,1,5.21484375,115,8,1,3.984375,-1,9,1,14.883268482490266,116,10,1,14.88326848249028,117,11,1,14.88326848249028,118,12,1,14.88326848249028,119,13,1,14.88326848249028,120,14,1,14.88326848249028,121,15,1,14.88326848249028,122,16,1,15.08754863813229,123,17,1,14.88326848249028,124,18,1,14.88326848249028,125,19,1,14.88326848249028,126,20,1,14.88326848249028,127,21,1,14.88326848249028,128,22,1,14.88326848249028,129,23,1,11.8359375,159]}}
  #|{"textrec":{"s":[16,400,0,"断网时发出的消息 082947"],"r":[0,1,15.875486381322958,160,1,1,15.875486381322958,161,2,1,15.875486381322958,162,3,1,15.875486381322958,163,4,1,15.875486381322958,164,5,1,15.875486381322958,30,6,1,15.875486381322958,165,7,1,15.875486381322958,166,8,1,4.1875,-1,9,1,9.765625,167,10,1,9.90625,168,11,1,9.34375,169,12,1,9.875,170,13,1,9.984375,171,14,1,8.796875,172]}}
  #|{"textrec":{"s":[10,400,0,"刚刚"],"r":[0,1,9.941634241245136,173,1,1,9.941634241245136,173]}}
  #|{"textrec":{"m":[10,400,0],"r":[9.66796875,2.109375,14,9.66796875,2.109375,0]}}
  #|{"textrec":{"s":[12,500,0,"页面"],"r":[0,1,11.918287937743191,174,1,1,11.918287937743191,175]}}
  #|{"textrec":{"s":[12,500,0,"页"],"r":[0,1,11.918287937743191,174]}}
  #|{"textrec":{"s":[12,500,0,"面"],"r":[0,1,11.918287937743191,175]}}
  #|{"textrec":{"s":[12,500,0,"状态"],"r":[0,1,11.918287937743191,176,1,1,11.918287937743191,177]}}
  #|{"textrec":{"s":[12,500,0,"状"],"r":[0,1,11.918287937743191,176]}}
  #|{"textrec":{"s":[12,500,0,"态"],"r":[0,1,11.918287937743191,177]}}
  #|{"textrec":{"s":[12,500,0,"耗时"],"r":[0,1,11.918287937743191,178,1,1,11.918287937743191,179]}}
  #|{"textrec":{"s":[12,500,0,"耗"],"r":[0,1,11.918287937743191,178]}}
  #|{"textrec":{"s":[12,500,0,"时"],"r":[0,1,11.918287937743191,179]}}
  #|{"textrec":{"s":[13,400,0,"首页"],"r":[0,1,12.898832684824903,180,1,1,12.898832684824903,181]}}
  #|{"textrec":{"s":[13,400,0,"首"],"r":[0,1,12.898832684824903,180]}}
  #|{"textrec":{"s":[13,400,0,"页"],"r":[0,1,12.898832684824903,181]}}
  #|{"textrec":{"s":[13,400,0,"完成"],"r":[0,1,12.898832684824903,182,1,1,12.898832684824903,183]}}
  #|{"textrec":{"s":[13,400,0,"完"],"r":[0,1,12.898832684824903,182]}}
  #|{"textrec":{"s":[13,400,0,"成"],"r":[0,1,12.898832684824903,183]}}
  #|{"textrec":{"s":[13,400,0,"1.2 s"],"r":[0,1,5.79541015625,184,1,1,3.49755859375,185,2,1,7.642578125,186,3,1,3.580078125,-1,4,1,6.728515625,10]}}
  #|{"textrec":{"s":[13,400,0,"1.2"],"r":[0,1,5.79541015625,184,1,1,3.49755859375,185,2,1,7.642578125,186]}}
  #|{"textrec":{"s":[13,400,0,"s"],"r":[0,1,6.728515625,10]}}
  #|{"textrec":{"s":[13,400,0,"聊天页的列表和输入框"],"r":[0,1,12.898832684824903,187,1,1,12.898832684824903,188,2,1,12.898832684824903,181,3,1,12.898832684824903,5,4,1,12.898832684824896,189,5,1,12.898832684824896,190,6,1,12.898832684824896,191,7,1,12.898832684824896,192,8,1,12.898832684824896,193,9,1,12.898832684824896,194]}}
  #|{"textrec":{"s":[13,400,0,"聊"],"r":[0,1,12.898832684824903,187]}}
  #|{"textrec":{"s":[13,400,0,"天"],"r":[0,1,12.898832684824903,188]}}
  #|{"textrec":{"s":[13,400,0,"的"],"r":[0,1,12.898832684824903,5]}}
  #|{"textrec":{"s":[13,400,0,"列"],"r":[0,1,12.898832684824903,189]}}
  #|{"textrec":{"s":[13,400,0,"表"],"r":[0,1,12.898832684824903,190]}}
  #|{"textrec":{"s":[13,400,0,"和"],"r":[0,1,12.898832684824903,191]}}
  #|{"textrec":{"s":[13,400,0,"输"],"r":[0,1,12.898832684824903,192]}}
  #|{"textrec":{"s":[13,400,0,"入"],"r":[0,1,12.898832684824903,193]}}
  #|{"textrec":{"s":[13,400,0,"框"],"r":[0,1,12.898832684824903,194]}}
  #|{"textrec":{"s":[13,400,0,"进行中"],"r":[0,1,12.898832684824903,195,1,1,12.898832684824903,196,2,1,12.898832684824903,197]}}
  #|{"textrec":{"s":[13,400,0,"进"],"r":[0,1,12.898832684824903,195]}}
  #|{"textrec":{"s":[13,400,0,"行"],"r":[0,1,12.898832684824903,196]}}
  #|{"textrec":{"s":[13,400,0,"中"],"r":[0,1,12.898832684824903,197]}}
  #|{"textrec":{"s":[13,400,0,"3.4 s"],"r":[0,1,7.85205078125,198,1,1,3.37060546875,185,2,1,8.099609375,199,3,1,3.580078125,-1,4,1,6.728515625,10]}}
  #|{"textrec":{"s":[13,400,0,"3.4"],"r":[0,1,7.85205078125,198,1,1,3.37060546875,185,2,1,8.099609375,199]}}
  #|{"textrec":{"s":[15,650,0,"默认模型"],"r":[0,1,14.883268482490273,200,1,1,14.883268482490273,201,2,1,14.883268482490273,202,3,1,14.883268482490273,203]}}
  #|{"textrec":{"m":[15,650,0],"r":[14.501953125,3.1640625,21,14.501953125,3.1640625,0]}}
  #|{"textrec":{"s":[15,400,0,"表格和代码 082947947"],"r":[0,1,14.883268482490273,204,1,1,14.883268482490273,205,2,1,14.883268482490273,206,3,1,14.883268482490273,139,4,1,14.88326848249028,207,5,1,3.984375,-1,6,1,9.2138671875,208,7,1,9.345703125,209,8,1,8.818359375,210,9,1,9.31640625,211,10,1,9.4189453125,212,11,1,8.232421875,213,12,1,9.2431640625,211,13,1,9.4189453125,212,14,1,8.3056640625,213]}}
  #|{"textrec":{"m":[12,500,0],"r":[11.6015625,2.53125,17,11.6015625,2.53125,0]}}
  #|{"textrec":{"m":[12,400,0],"r":[11.6015625,2.53125,17,11.6015625,2.53125,0]}}
  #|{"textrec":{"s":[12,400,2,"export"],"r":[0,1,7.2,214,1,1,7.2,215,2,1,7.2,216,3,1,7.2,217,4,1,7.2,218,5,1,7.2,219]}}
  #|{"textrec":{"m":[12,400,2],"r":[12.24005126953125,3.60003662109375,17,12.720025777816772,4.080008268356323,0]}}
  #|{"textrec":{"s":[12,400,2," "],"r":[0,1,7.2,-1]}}
  #|{"textrec":{"s":[12,400,2,"function"],"r":[0,1,7.2,220,1,1,7.2,221,2,1,7.2,222,3,1,7.2,223,4,1,7.2,219,5,1,7.2,224,6,1,7.2,217,7,1,7.2,222]}}
  #|{"textrec":{"s":[12,400,2,"placeRows"],"r":[0,1,7.2,216,1,1,7.2,225,2,1,7.2,226,3,1,7.2,223,4,1,7.2,214,5,1,7.2,227,6,1,7.2,217,7,1,7.2,228,8,1,7.2,229]}}
  #|{"textrec":{"s":[12,400,2,"("],"r":[0,1,7.2,230]}}
  #|{"textrec":{"s":[12,400,2,"rows"],"r":[0,1,7.2,218,1,1,7.2,217,2,1,7.2,228,3,1,7.2,229]}}
  #|{"textrec":{"s":[12,400,2,":"],"r":[0,1,7.2,231]}}
  #|{"textrec":{"s":[12,400,2,"Row"],"r":[0,1,7.2,227,1,1,7.2,217,2,1,7.2,228]}}
  #|{"textrec":{"s":[12,400,2,"[],"],"r":[0,1,7.2,232,1,1,7.2,233,2,1,7.2,234]}}
  #|{"textrec":{"s":[12,400,2,"from"],"r":[0,1,7.2,220,1,1,7.2,218,2,1,7.2,217,3,1,7.2,235]}}
  #|{"textrec":{"s":[12,400,2,"number"],"r":[0,1,7.2,222,1,1,7.2,221,2,1,7.2,235,3,1,7.2,236,4,1,7.2,214,5,1,7.2,218]}}
  #|{"textrec":{"s":[12,400,2,"):"],"r":[0,1,7.2,237,1,1,7.2,231]}}
  #|{"textrec":{"s":[12,400,2,"{"],"r":[0,1,7.2,238]}}
  #|{"textrec":{"s":[12,400,2,"\n  "],"r":[0,1,0,-1,1,1,7.2,-1,2,1,7.2,-1]}}
  #|{"textrec":{"s":[12,400,2,"const"],"r":[0,1,7.2,223,1,1,7.2,217,2,1,7.2,222,3,1,7.2,229,4,1,7.2,219]}}
  #|{"textrec":{"s":[12,400,2,"visible"],"r":[0,1,7.2,239,1,1,7.2,224,2,1,7.2,229,3,1,7.2,224,4,1,7.2,236,5,1,7.2,225,6,1,7.2,214]}}
  #|{"textrec":{"s":[12,400,2,"="],"r":[0,1,7.2,240]}}
  #|{"textrec":{"s":[12,400,2,"."],"r":[0,1,7.2,241]}}
  #|{"textrec":{"s":[12,400,2,"filter"],"r":[0,1,7.2,220,1,1,7.2,224,2,1,7.2,225,3,1,7.2,219,4,1,7.2,214,5,1,7.2,218]}}
  #|{"textrec":{"s":[12,400,2,"(("],"r":[0,1,7.2,230,1,1,7.2,230]}}
  #|{"textrec":{"s":[12,400,2,"r"],"r":[0,1,7.2,218]}}
  #|{"textrec":{"s":[12,400,2,")"],"r":[0,1,7.2,237]}}
  #|{"textrec":{"s":[12,400,2,"=>"],"r":[0,1,7.2,240,1,1,7.2,242]}}
  #|{"textrec":{"s":[12,400,2,"top"],"r":[0,1,7.2,219,1,1,7.2,217,2,1,7.2,216]}}
  #|{"textrec":{"s":[12,400,2,">="],"r":[0,1,7.2,242,1,1,7.2,240]}}
  #|{"textrec":{"s":[12,400,2,"&&"],"r":[0,1,7.2,243,1,1,7.2,243]}}
  #|{"textrec":{"s":[12,400,2,"<"],"r":[0,1,7.2,244]}}
  #|{"textrec":{"s":[12,400,2,"+"],"r":[0,1,7.2,245]}}
  #|{"textrec":{"s":[12,400,2,"window"],"r":[0,1,7.2,228,1,1,7.2,224,2,1,7.2,222,3,1,7.2,246,4,1,7.2,217,5,1,7.2,228]}}
  #|{"textrec":{"s":[12,400,2,"innerHeight"],"r":[0,1,7.2,224,1,1,7.2,222,2,1,7.2,222,3,1,7.2,214,4,1,7.2,218,5,1,7.2,247,6,1,7.2,214,7,1,7.2,224,8,1,7.2,248,9,1,7.2,249,10,1,7.2,219]}}
  #|{"textrec":{"s":[12,400,2,"*"],"r":[0,1,7.2,250]}}
  #|{"textrec":{"s":[12,400,2,"2"],"r":[0,1,7.2,251]}}
  #|{"textrec":{"s":[12,400,2,"// only the rows near the screen"],"r":[0,1,7.2,252,1,1,7.2,252,2,1,7.2,-1,3,1,7.2,217,4,1,7.2,222,5,1,7.2,225,6,1,7.2,253,7,1,7.2,-1,8,1,7.2,219,9,1,7.2,249,10,1,7.2,214,11,1,7.2,-1,12,1,7.2,218,13,1,7.2,217,14,1,7.2,228,15,1,7.2,229,16,1,7.2,-1,17,1,7.2,222,18,1,7.2,214,19,1,7.2,226,20,1,7.2,218,21,1,7.2,-1,22,1,7.2,219,23,1,7.2,249,24,1,7.2,214,25,1,7.2,-1,26,1,7.2,229,27,1,7.2,223,28,1,7.2,218,29,1,7.2,214,30,1,7.2,214,31,1,7.2,222]}}
  #|{"textrec":{"s":[12,400,2,"return"],"r":[0,1,7.2,218,1,1,7.2,214,2,1,7.2,219,3,1,7.2,221,4,1,7.2,218,5,1,7.2,222]}}
  #|{"textrec":{"s":[12,400,2,"length"],"r":[0,1,7.2,225,1,1,7.2,214,2,1,7.2,222,3,1,7.2,248,4,1,7.2,219,5,1,7.2,249]}}
  #|{"textrec":{"s":[12,400,2,"\n"],"r":[0,1,0,-1]}}
  #|{"textrec":{"s":[12,400,2,"}"],"r":[0,1,7.2,254]}}
  #|{"textrec":{"s":[15,400,0,"详见 "],"r":[0,1,14.883268482490273,255,1,1,14.883268482490273,256,2,1,3.984375,-1]}}
  #|{"textrec":{"s":[15,400,0,"https://example.com/e2e/082947947"],"r":[0,1,8.59130859375,257,1,1,5.21484375,115,2,1,5.21484375,115,3,1,8.9208984375,258,4,1,7.6171875,136,5,1,4.21875,259,6,1,4.3359375,260,7,1,4.3359375,260,8,1,8.1884765625,113,9,1,7.4853515625,261,10,1,8.0419921875,111,11,1,12.8173828125,262,12,1,8.9208984375,258,13,1,3.5595703125,263,14,1,8.3349609375,113,15,1,4.072265625,264,16,1,8.0126953125,265,17,1,8.6279296875,138,18,1,12.8173828125,262,19,1,4.3359375,260,20,1,8.3349609375,113,21,1,8.78173828125,210,22,1,8.29833984375,113,23,1,4.3359375,260,24,1,9.2138671875,208,25,1,9.345703125,209,26,1,8.818359375,210,27,1,9.31640625,211,28,1,9.4189453125,212,29,1,8.232421875,213,30,1,9.2431640625,211,31,1,9.4189453125,212,32,1,8.3056640625,213]}}
  #|{"textrec":{"s":[10,400,0,"ts"],"r":[0,1,3.701171875,266,1,1,5.302734375,267]}}
  #|{"textrec":{"s":[11,400,0,"复制"],"r":[0,1,10.93579766536965,268,1,1,10.93579766536965,269]}}
  #|{"textrec":{"m":[11,400,0],"r":[10.634765625,2.3203125,16,10.634765625,2.3203125,0]}}
  #|{"textrec":{"s":[16,400,0,"还没发出去的草稿 082给个表格 082947 md:表格和代码 082947947"],"r":[0,1,15.875486381322958,270,1,1,15.875486381322958,271,2,1,15.875486381322958,163,3,1,15.875486381322958,164,4,1,15.875486381322958,272,5,1,15.875486381322958,30,6,1,15.875486381322958,273,7,1,15.875486381322958,274,8,1,4.1875,-1,9,1,9.765625,167,10,1,9.90625,168,11,1,11.34375,169,12,1,15.875486381322958,275,13,1,15.875486381322958,276,14,1,15.875486381322958,277,15,1,15.875486381322958,278,16,1,4.1875,-1,17,1,9.765625,167,18,1,9.90625,168,19,1,9.34375,169,20,1,9.875,170,21,1,9.984375,171,22,1,8.796875,172,23,1,4.1875,-1,24,1,13.609375,279,25,1,9.515625,280,26,1,4.4375,37,27,1,15.875486381322958,277,28,1,15.875486381322958,278,29,1,15.875486381322958,281,30,1,15.875486381322958,282,31,1,15.875486381322958,283,32,1,4.1875,-1,33,1,9.765625,167,34,1,9.90625,168,35,1,9.34375,169,36,1,9.875,170,37,1,9.984375,171,38,1,8.71875,172,39,1,9.796875,170,40,1,9.984375,171,41,1,8.796875,172]}}
  #|{"textrec":{"s":[10,400,0,"1 分钟前"],"r":[0,1,4.755859375,284,1,1,2.9296875,-1,2,1,9.941634241245136,285,3,1,9.941634241245136,286,4,1,9.941634241245133,287]}}
  #|{"textrec":{"s":[15,400,0,"这一条应当显示为未读 082947"],"r":[0,1,14.883268482490273,288,1,1,14.883268482490273,289,2,1,14.883268482490273,290,3,1,14.883268482490273,291,4,1,14.88326848249028,292,5,1,14.88326848249028,293,6,1,14.88326848249028,294,7,1,14.88326848249028,140,8,1,14.88326848249028,116,9,1,14.88326848249028,295,10,1,3.984375,-1,11,1,9.2138671875,208,12,1,9.345703125,209,13,1,8.818359375,210,14,1,9.31640625,211,15,1,9.4189453125,212,16,1,8.3056640625,213]}}
  #|{"textrec":{"s":[16,400,0,"再问一次 post:这一条应当显示为未读 082947"],"r":[0,1,15.875486381322958,296,1,1,15.875486381322958,297,2,1,15.875486381322958,298,3,1,15.875486381322958,299,4,1,4.1875,-1,5,1,9.453125,33,6,1,9.140625,34,7,1,8.0234375,35,8,1,5.4609375,36,9,1,4.4375,37,10,1,15.875486381322958,300,11,1,15.875486381322958,298,12,1,15.875486381322958,301,13,1,15.875486381322958,302,14,1,15.875486381322958,303,15,1,15.875486381322958,304,16,1,15.875486381322958,305,17,1,15.875486381322958,306,18,1,15.875486381322958,307,19,1,15.875486381322958,308,20,1,4.1875,-1,21,1,9.765625,167,22,1,9.90625,168,23,1,9.34375,169,24,1,9.875,170,25,1,9.984375,171,26,1,8.796875,172]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 post:你好…"],"r":[0,1,15.875486381322958,94,1,1,15.875486381322958,95,2,1,15.875486381322958,94,3,1,15.875486381322958,96,4,1,15.875486381322958,97,5,1,15.875486381322958,63,6,1,15.875486381322958,64,7,1,15.875486381322958,65,8,1,3.95001220703125,-1,9,1,9.824199676513672,72,10,1,9.432537078857422,73,11,1,8.471200942993164,74,12,1,5.973020553588867,75,13,1,4.952056884765625,76,14,1,15.875486381322958,98,15,1,15.875486381322958,99,16,1,14.076484680175781,93]}}
  #|{"textrec":{"ib":["504a4df6beac534a",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"s":[12,400,0,"studio"],"r":[0,1,6.251953125,309,1,1,4.330078125,310,2,1,7.001953125,311,3,1,7.37109375,312,4,1,2.96484375,313,5,1,7.08984375,314]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 post:…"],"r":[0,1,15.875486381322958,94,1,1,15.875486381322958,95,2,1,15.875486381322958,94,3,1,15.875486381322958,96,4,1,15.875486381322958,97,5,1,15.875486381322958,63,6,1,15.875486381322958,64,7,1,15.875486381322958,65,8,1,3.95001220703125,-1,9,1,9.824199676513672,72,10,1,9.432537078857422,73,11,1,8.471200942993164,74,12,1,5.973020553588867,75,13,1,4.952056884765625,76,14,1,14.076484680175781,93]}}
  #|{"textrec":{"g":288,"r":[1082,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":289,"r":[1099,0,16,4,-1,-7,0]}}
  #|{"textrec":{"g":290,"r":[1116,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":291,"r":[1133,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":292,"r":[1150,0,14,16,0,-13,0]}}
  #|{"textrec":{"g":293,"r":[1165,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":294,"r":[1182,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":140,"r":[1199,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":116,"r":[1215,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":295,"r":[1232,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":208,"r":[1250,0,11,14,-1,-12,0]}}
  #|{"textrec":{"g":209,"r":[1262,0,11,14,-1,-12,0]}}
  #|{"textrec":{"g":210,"r":[1274,0,10,13,0,-12,0]}}
  #|{"textrec":{"g":211,"r":[1285,0,11,14,-1,-12,0]}}
  #|{"textrec":{"g":212,"r":[1297,0,11,13,-1,-12,0]}}
  #|{"textrec":{"g":213,"r":[1309,0,10,13,-1,-12,0]}}
  #|{"textrec":{"g":204,"r":[1320,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":205,"r":[1337,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":206,"r":[1355,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":139,"r":[1372,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":207,"r":[1389,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":174,"r":[1406,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":175,"r":[1421,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":180,"r":[1436,0,14,15,-1,-12,0]}}
  #|{"textrec":{"g":181,"r":[1451,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":187,"r":[1466,0,14,15,-1,-12,0]}}
  #|{"textrec":{"g":188,"r":[1481,0,15,14,-1,-11,0]}}
  #|{"textrec":{"g":5,"r":[1497,0,13,15,0,-12,0]}}
  #|{"textrec":{"g":189,"r":[1511,0,14,15,-1,-12,0]}}
  #|{"textrec":{"g":190,"r":[1526,0,14,15,-1,-12,0]}}
  #|{"textrec":{"g":191,"r":[1541,0,14,15,-1,-12,0]}}
  #|{"textrec":{"g":192,"r":[1556,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":193,"r":[1572,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":194,"r":[1588,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":214,"r":[1604,0,8,10,0,-8,0]}}
  #|{"textrec":{"g":215,"r":[1613,0,9,9,-1,-8,0]}}
  #|{"textrec":{"g":216,"r":[1623,0,8,12,0,-8,0]}}
  #|{"textrec":{"g":217,"r":[1632,0,8,10,0,-8,0]}}
  #|{"textrec":{"g":218,"r":[1641,0,8,9,0,-8,0]}}
  #|{"textrec":{"g":219,"r":[1650,0,9,11,-1,-10,0]}}
  #|{"textrec":{"g":220,"r":[1660,0,9,11,-1,-10,0]}}
  #|{"textrec":{"g":221,"r":[1670,0,8,10,0,-8,0]}}
  #|{"textrec":{"g":222,"r":[1679,0,8,9,0,-8,0]}}
  #|{"textrec":{"g":223,"r":[1688,0,8,10,0,-8,0]}}
  #|{"textrec":{"g":224,"r":[1697,0,8,12,0,-11,0]}}
  #|{"textrec":{"g":225,"r":[1706,0,9,11,-1,-10,0]}}
  #|{"textrec":{"g":226,"r":[1716,0,9,10,-1,-8,0]}}
  #|{"textrec":{"g":227,"r":[1726,0,8,11,0,-10,0]}}
  #|{"textrec":{"g":228,"r":[1735,0,9,9,-1,-8,0]}}
  #|{"textrec":{"g":229,"r":[1745,0,8,10,0,-8,0]}}
  #|{"textrec":{"g":230,"r":[1754,0,6,15,1,-12,0]}}
  #|{"textrec":{"g":231,"r":[1761,0,5,10,1,-8,0]}}
  #|{"textrec":{"g":232,"r":[1767,0,6,14,1,-11,0]}}
  #|{"textrec":{"g":233,"r":[1774,0,6,14,0,-11,0]}}
  #|{"textrec":{"g":234,"r":[1781,0,5,6,1,-3,0]}}
  #|{"textrec":{"g":235,"r":[1787,0,9,9,-1,-8,0]}}
  #|{"textrec":{"g":236,"r":[1797,0,8,12,0,-10,0]}}
  #|{"textrec":{"g":237,"r":[1806,0,6,15,0,-12,0]}}
  #|{"textrec":{"g":238,"r":[1813,0,9,14,-1,-11,0]}}
  #|{"textrec":{"g":239,"r":[1823,0,9,9,-1,-8,0]}}
  #|{"textrec":{"g":240,"r":[1833,0,8,6,0,-7,0]}}
  #|{"textrec":{"g":241,"r":[1842,0,5,5,1,-3,0]}}
  #|{"textrec":{"g":242,"r":[1848,0,8,10,0,-9,0]}}
  #|{"textrec":{"g":243,"r":[1857,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":244,"r":[1868,0,8,10,0,-9,0]}}
  #|{"textrec":{"g":245,"r":[1877,0,9,8,-1,-8,0]}}
  #|{"textrec":{"g":246,"r":[1887,0,8,12,0,-10,0]}}
  #|{"textrec":{"g":247,"r":[1896,0,8,11,0,-10,0]}}
  #|{"textrec":{"g":248,"r":[1905,0,8,12,0,-8,0]}}
  #|{"textrec":{"g":249,"r":[1914,0,8,11,0,-10,0]}}
  #|{"textrec":{"g":250,"r":[1923,0,9,9,-1,-9,0]}}
  #|{"textrec":{"g":251,"r":[1933,0,9,11,-1,-10,0]}}
  #|{"textrec":{"g":252,"r":[1943,0,9,14,-1,-11,0]}}
  #|{"textrec":{"g":253,"r":[1953,0,9,12,-1,-8,0]}}
  #|{"textrec":{"g":254,"r":[1963,0,8,14,0,-11,0]}}
  #|{"textrec":{"g":255,"r":[1972,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":256,"r":[1989,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":257,"r":[2006,0,9,14,0,-13,0]}}
  #|{"textrec":{"g":115,"r":[2016,0,7,13,-1,-11,0]}}
  #|{"textrec":{"g":258,"r":[2024,0,10,14,0,-10,0]}}
  #|{"textrec":{"g":136,"r":[2035,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":259,"r":[0,20,5,11,0,-9,0]}}
  #|{"textrec":{"g":260,"r":[6,20,7,17,-1,-13,0]}}
  #|{"textrec":{"g":113,"r":[14,20,10,12,-1,-10,0]}}
  #|{"textrec":{"g":261,"r":[25,20,10,10,-1,-9,0]}}
  #|{"textrec":{"g":111,"r":[36,20,10,12,-1,-10,0]}}
  #|{"textrec":{"g":262,"r":[47,20,13,11,0,-10,0]}}
  #|{"textrec":{"g":263,"r":[61,20,4,14,0,-13,0]}}
  #|{"textrec":{"g":264,"r":[66,20,5,5,0,-3,0]}}
  #|{"textrec":{"g":265,"r":[72,20,10,12,-1,-10,0]}}
  #|{"textrec":{"g":138,"r":[83,20,11,12,-1,-10,0]}}
  #|{"textrec":{"g":109,"r":[95,20,17,16,-1,-13,0]}}
  #|{"textrec":{"g":110,"r":[113,20,17,16,-1,-13,0]}}
  #|{"textrec":{"g":112,"r":[131,20,10,14,-1,-10,0]}}
  #|{"textrec":{"g":114,"r":[142,20,9,11,0,-10,0]}}
  #|{"textrec":{"g":117,"r":[152,20,16,17,-1,-14,0]}}
  #|{"textrec":{"g":118,"r":[169,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":119,"r":[186,20,17,16,-1,-13,0]}}
  #|{"textrec":{"g":120,"r":[204,20,15,16,0,-13,0]}}
  #|{"textrec":{"g":121,"r":[220,20,15,16,0,-13,0]}}
  #|{"textrec":{"g":122,"r":[236,20,16,17,-1,-14,0]}}
  #|{"textrec":{"g":123,"r":[253,20,5,7,0,-3,0]}}
  #|{"textrec":{"g":124,"r":[259,20,16,16,0,-13,0]}}
  #|{"textrec":{"g":125,"r":[276,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":126,"r":[293,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":127,"r":[310,20,15,17,0,-14,0]}}
  #|{"textrec":{"g":128,"r":[326,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":129,"r":[343,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":159,"r":[360,20,12,5,0,-3,0]}}
  #|{"textrec":{"ib":["11ba9484460f477d",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["a1e7be43eb966606",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"ib":["c7a6d30e254a5910",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"g":200,"r":[373,20,17,16,-1,-13,0]}}
  #|{"textrec":{"g":201,"r":[391,20,17,16,-1,-13,0]}}
  #|{"textrec":{"g":202,"r":[409,20,17,16,-1,-13,0]}}
  #|{"textrec":{"g":203,"r":[427,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":270,"r":[444,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":271,"r":[462,20,18,17,-1,-14,0]}}
  #|{"textrec":{"g":163,"r":[481,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":164,"r":[499,20,15,17,0,-14,0]}}
  #|{"textrec":{"g":272,"r":[515,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":273,"r":[533,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":274,"r":[551,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":167,"r":[569,20,11,15,0,-13,0]}}
  #|{"textrec":{"g":168,"r":[581,20,11,15,0,-13,0]}}
  #|{"textrec":{"g":169,"r":[593,20,10,14,0,-13,0]}}
  #|{"textrec":{"g":275,"r":[604,20,18,17,-1,-14,0]}}
  #|{"textrec":{"g":276,"r":[623,20,18,17,-1,-14,0]}}
  #|{"textrec":{"g":277,"r":[642,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":278,"r":[660,20,18,17,-1,-14,0]}}
  #|{"textrec":{"g":170,"r":[679,20,11,15,0,-13,0]}}
  #|{"textrec":{"g":171,"r":[691,20,12,14,-1,-13,0]}}
  #|{"textrec":{"g":172,"r":[704,20,11,14,-1,-13,0]}}
  #|{"textrec":{"g":279,"r":[716,20,14,11,0,-10,0]}}
  #|{"textrec":{"g":280,"r":[731,20,11,15,-1,-13,0]}}
  #|{"textrec":{"g":281,"r":[743,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":282,"r":[761,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":283,"r":[779,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":94,"r":[797,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":95,"r":[815,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":96,"r":[833,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":97,"r":[851,20,18,17,-1,-14,0]}}
  #|{"textrec":{"s":[16,400,0,"发消息"],"r":[0,1,15.875486381322958,163,1,1,15.875486381322958,165,2,1,15.875486381322958,166]}}
  #|{"textrec":{"g":165,"r":[870,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":166,"r":[888,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":284,"r":[906,20,6,10,-1,-9,0]}}
  #|{"textrec":{"g":285,"r":[913,20,12,12,-1,-9,0]}}
  #|{"textrec":{"g":286,"r":[926,20,11,12,-1,-9,0]}}
  #|{"textrec":{"g":287,"r":[938,20,12,13,-1,-10,0]}}
  #|{"textrec":{"g":173,"r":[951,20,11,11,-1,-9,0]}}
  #|{"textrec":{"g":176,"r":[963,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":177,"r":[978,20,14,13,-1,-11,0]}}
  #|{"textrec":{"g":182,"r":[993,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":183,"r":[1009,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":195,"r":[1025,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":196,"r":[1041,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":197,"r":[1057,20,13,15,0,-12,0]}}
  #|{"textrec":{"g":160,"r":[1071,20,16,17,0,-14,0]}}
  #|{"textrec":{"g":161,"r":[1088,20,16,17,0,-14,0]}}
  #|{"textrec":{"g":162,"r":[1105,20,16,17,0,-14,0]}}
  #|{"textrec":{"g":178,"r":[1122,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":179,"r":[1137,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":184,"r":[1152,20,7,12,-1,-11,0]}}
  #|{"textrec":{"g":185,"r":[1160,20,4,5,0,-3,0]}}
  #|{"textrec":{"g":186,"r":[1165,20,9,12,-1,-11,0]}}
  #|{"textrec":{"g":10,"r":[1175,20,9,10,-1,-8,0]}}
  #|{"textrec":{"g":198,"r":[1185,20,10,13,-1,-11,0]}}
  #|{"textrec":{"g":199,"r":[1196,20,10,12,-1,-11,0]}}
  #|{"textrec":{"g":108,"r":[1207,20,8,8,-1,-7,0]}}
  #|{"textrec":{"g":309,"r":[1216,20,8,10,-1,-8,0]}}
  #|{"textrec":{"g":310,"r":[1225,20,6,11,-1,-9,0]}}
  #|{"textrec":{"g":311,"r":[1232,20,9,10,-1,-8,0]}}
  #|{"textrec":{"g":312,"r":[1242,20,9,12,-1,-10,0]}}
  #|{"textrec":{"g":313,"r":[1252,20,5,11,-1,-10,0]}}
  #|{"textrec":{"g":314,"r":[1258,20,9,10,-1,-8,0]}}
  #|{"textrec":{"g":266,"r":[1268,20,6,10,-1,-8,0]}}
  #|{"textrec":{"g":267,"r":[1275,20,7,9,-1,-7,0]}}
  #|{"textrec":{"g":296,"r":[1283,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":297,"r":[1301,20,16,17,0,-14,0]}}
  #|{"textrec":{"g":298,"r":[1318,20,17,4,-1,-8,0]}}
  #|{"textrec":{"g":299,"r":[1336,20,18,17,-1,-14,0]}}
  #|{"textrec":{"g":300,"r":[1355,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":301,"r":[1373,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":302,"r":[1391,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":303,"r":[1409,20,15,17,0,-14,0]}}
  #|{"textrec":{"g":304,"r":[1425,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":305,"r":[1443,20,17,16,-1,-13,0]}}
  #|{"textrec":{"g":306,"r":[1461,20,16,17,-1,-14,0]}}
  #|{"textrec":{"g":307,"r":[1478,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":308,"r":[1496,20,18,17,-1,-14,0]}}
  #|{"textrec":{"g":268,"r":[1515,20,13,13,-1,-10,0]}}
  #|{"textrec":{"g":269,"r":[1529,20,12,13,-1,-10,0]}}
  #|{"textrec":{"g":156,"r":[1542,20,5,5,1,-8,0]}}
  #|{"textrec":{"ib":["252b41f603f509d8",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"g":157,"r":[1548,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":158,"r":[1565,20,17,16,-1,-13,0]}}
  #|{"textrec":{"ib":["b277602c41d156e7",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"ib":["ddfdc2820df8a676",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"s":[16,400,0,"给个链接 082947 md:链接 082947"],"r":[0,1,15.875486381322958,275,1,1,15.875486381322958,276,2,1,15.875486381322958,315,3,1,15.875486381322958,316,4,1,4.1875,-1,5,1,9.765625,167,6,1,9.90625,168,7,1,9.34375,169,8,1,9.875,170,9,1,9.984375,171,10,1,8.796875,172,11,1,4.1875,-1,12,1,13.609375,279,13,1,9.515625,280,14,1,4.4375,37,15,1,15.875486381322958,315,16,1,15.875486381322958,316,17,1,4.1875,-1,18,1,9.765625,167,19,1,9.90625,168,20,1,9.34375,169,21,1,9.875,170,22,1,9.984375,171,23,1,8.796875,172]}}
  #|{"textrec":{"g":315,"r":[1583,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":316,"r":[1601,20,17,17,-1,-14,0]}}
  #|{"textrec":{"ib":["9699dbc96b0fdfd9",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"s":[10,400,0,"正在发送"],"r":[0,1,9.941634241245136,317,1,1,9.941634241245136,318,2,1,9.941634241245136,319,3,1,9.941634241245136,320]}}
  #|{"textrec":{"g":317,"r":[1619,20,12,11,-1,-9,0]}}
  #|{"textrec":{"g":318,"r":[1632,20,12,13,-1,-10,0]}}
  #|{"textrec":{"g":319,"r":[1645,20,12,13,-1,-10,0]}}
  #|{"textrec":{"g":320,"r":[1658,20,12,13,-1,-10,0]}}
  #|{"textrec":{"s":[15,400,0,"链接 082947"],"r":[0,1,14.883268482490273,321,1,1,14.883268482490273,322,2,1,3.984375,-1,3,1,9.2138671875,208,4,1,9.345703125,209,5,1,8.818359375,210,6,1,9.31640625,211,7,1,9.4189453125,212,8,1,8.3056640625,213]}}
  #|{"textrec":{"s":[15,400,0,"https://example.com/e2e/082947"],"r":[0,1,8.59130859375,257,1,1,5.21484375,115,2,1,5.21484375,115,3,1,8.9208984375,258,4,1,7.6171875,136,5,1,4.21875,259,6,1,4.3359375,260,7,1,4.3359375,260,8,1,8.1884765625,113,9,1,7.4853515625,261,10,1,8.0419921875,111,11,1,12.8173828125,262,12,1,8.9208984375,258,13,1,3.5595703125,263,14,1,8.3349609375,113,15,1,4.072265625,264,16,1,8.0126953125,265,17,1,8.6279296875,138,18,1,12.8173828125,262,19,1,4.3359375,260,20,1,8.3349609375,113,21,1,8.78173828125,210,22,1,8.29833984375,113,23,1,4.3359375,260,24,1,9.2138671875,208,25,1,9.345703125,209,26,1,8.818359375,210,27,1,9.31640625,211,28,1,9.4189453125,212,29,1,8.3056640625,213]}}
  #|{"textrec":{"g":321,"r":[1671,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":322,"r":[1688,20,16,17,-1,-14,0]}}
  #|{"textrec":{"ib":["5011346a34665c45",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 post…"],"r":[0,1,15.875486381322958,94,1,1,15.875486381322958,95,2,1,15.875486381322958,94,3,1,15.875486381322958,96,4,1,15.875486381322958,97,5,1,15.875486381322958,63,6,1,15.875486381322958,64,7,1,15.875486381322958,65,8,1,3.95001220703125,-1,9,1,9.824199676513672,72,10,1,9.432537078857422,73,11,1,8.471200942993164,74,12,1,5.973020553588867,75,13,1,14.076484680175781,93]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 pos…"],"r":[0,1,15.875486381322958,94,1,1,15.875486381322958,95,2,1,15.875486381322958,94,3,1,15.875486381322958,96,4,1,15.875486381322958,97,5,1,15.875486381322958,63,6,1,15.875486381322958,64,7,1,15.875486381322958,65,8,1,3.95001220703125,-1,9,1,9.824199676513672,72,10,1,9.432537078857422,73,11,1,8.497894287109375,74,12,1,14.076484680175781,93]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 po…"],"r":[0,1,15.875486381322958,94,1,1,15.875486381322958,95,2,1,15.875486381322958,94,3,1,15.875486381322958,96,4,1,15.875486381322958,97,5,1,15.875486381322958,63,6,1,15.875486381322958,64,7,1,15.875486381322958,65,8,1,3.95001220703125,-1,9,1,9.824199676513672,72,10,1,9.329673767089844,73,11,1,13.973621368408203,323]}}
  #|{"textrec":{"g":323,"r":[1705,20,14,6,-0.10286331176757812,-4,0]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 p…"],"r":[0,1,15.875486381322958,94,1,1,15.875486381322958,95,2,1,15.875486381322958,94,3,1,15.875486381322958,96,4,1,15.875486381322958,97,5,1,15.875486381322958,63,6,1,15.875486381322958,64,7,1,15.875486381322958,65,8,1,3.95001220703125,-1,9,1,9.721336364746094,72,10,1,13.973621368408203,323]}}
