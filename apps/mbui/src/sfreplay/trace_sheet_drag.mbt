// e2e/traces/sheet-drag.trace, made by scripts/trace.py from 01-sheet_drag.log: not edited by hand.

///|
/// What the app and its core said in the run, a line each.
pub let trace_sheet_drag : String =
  #|{"env":{"MBUI_CLOUD":"http://127.0.0.1:18787","MBUI_CORE_ACCOUNT":"{\"sub\":\"alice\",\"email\":\"alice@example.test\",\"name\":\"Name of alice\",\"picture\":\"\",\"access\":\"-\",\"refresh\":\"-\",\"accessExpires\":1792594099}"}}
  #|{"out":{"id":1,"call":"client.device","params":{"client":"still.fail mbui","app":"desktop","userAgent":"Macintosh; Mac OS X"}},"w":1792593800814.796}
  #|{"in":{"id":1,"ok":null},"w":1792593800903.131}
  #|{"out":{"id":2,"subscribe":{"topic":"accounts"},"keyed":true},"w":1792593800903.159}
  #|{"out":{"id":3,"subscribe":{"topic":"prefs"},"keyed":true},"w":1792593800903.167}
  #|{"step":"# written by scripts/rerecord.sh from its test (src/sfreplay/emit.mbt): not edited by hand","w":1792593800904.573}
  #|{"step":"timeout 90000","w":1792593800904.579}
  #|{"step":"answered client.device","w":1792593800904.582}
  #|{"step":"answered client.focus","w":1792593800917.241}
  #|{"in":{"id":2,"value":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""}]},"w":1792593800983.361}
  #|{"in":{"id":3,"value":{"onlyMine":false,"onlyWatching":false,"onlyDecisions":false,"listFilter":{},"appearance":"system","rowPicture":"auto","absoluteTime":false,"lang":"zh","keys":{},"lastChat":{},"openChat":{},"chatTabs":{},"dropFiles":{},"driveViews":{},"resume":{},"stationUpdatesDismissed":{},"device":{"app":"desktop","phone":false,"handoff":false},"reader":{"size":18,"line":1.7,"margin":22,"face":"sans","indent":true,"paper":"follow"},"rails":{},"bars":{"sets":[["chats","files","profiles","stations"],["decisions","usage","connects","archive"]],"current":0},"barsBy":{},"fonts":{},"faces":{"ui":{"id":"","name":"","mono":false,"family":"","files":[],"bytes":0},"text":{"id":"","name":"","mono":false,"family":"","files":[],"bytes":0},"code":{"id":"","name":"","mono":true,"family":"","files":[],"bytes":0},"list":[{"id":"inter","name":"Inter","mono":false,"family":"SF Inter","css":"http://127.0.0.1:18787/releases/fonts/inter/4.001/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/inter/4.001/var.ttf.gz","bytes":457818,"sha256":"29160a80ff49ddcab2c97711247e08b1fab27a484a329ce8b813d820dc559031"}],"preview":"http://127.0.0.1:18787/releases/fonts/inter/4.001/preview-194fa287.ttf","bytes":457818},{"id":"noto-sans-sc","name":"思源黑体","mono":false,"family":"SF Noto Sans SC","css":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/var.ttf.gz","bytes":11276563,"sha256":"a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da"}],"preview":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/preview-f0494178.ttf","bytes":11276563},{"id":"noto-serif-sc","name":"思源宋体","mono":false,"family":"SF Noto Serif SC","css":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/var.ttf.gz","bytes":15454579,"sha256":"050080d9255a86808f2945bffac582b31ef32bc36411ce29563b4961670c66f9"}],"preview":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/preview-001bbedf.ttf","bytes":15454579},{"id":"lxgw-wenkai","name":"霞鹜文楷","mono":false,"family":"SF LXGW WenKai","css":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/font.css","files":[{"weight":400,"url":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/400.ttf.gz","bytes":12904482,"sha256":"2d73eea94ad808999d90c0000c239a84a33b09d4bc6ab6c5b8bbf1eda8a7fc8b"},{"weight":500,"url":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/500.ttf.gz","bytes":13272430,"sha256":"f4b8a34d1f838fe411540cb7c97b1c384ac9738a876c4104500bc42508b2312a"}],"preview":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/preview-d3505af4.ttf","bytes":26176912},{"id":"jetbrains-mono","name":"JetBrains Mono","mono":true,"family":"SF JetBrains Mono","css":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/var.ttf.gz","bytes":90579,"sha256":"48715a42ec242c21e9f02692891e147d022299a52e48d5e413e1a942193ffeda"}],"preview":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/preview-ee73078f.ttf","bytes":90579},{"id":"fira-code","name":"Fira Code","mono":true,"family":"SF Fira Code","css":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/var.ttf.gz","bytes":137151,"sha256":"9335b082b3c7850d98a64b584f3417f65355f3471278bb5eeb8c6c0e8657aeeb"}],"preview":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/preview-555be27a.ttf","bytes":137151},{"id":"maple-mono","name":"Maple Mono","mono":true,"family":"SF Maple Mono CN","css":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/font.css","files":[{"weight":400,"url":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/400.ttf.gz","bytes":8352545,"sha256":"0fcc5139bfd5ab14ff989bb7dfd5236d0cafc10e60b9828569e6883613ab4085"},{"weight":600,"url":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/600.ttf.gz","bytes":8438132,"sha256":"96ed7ae26ee7c50b02b2d2b2bc0f1a0cbabe45ae5d6e6abf6678e2177c415677"}],"preview":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/preview-cffdf246.ttf","bytes":16790677}]}}},"w":1792593800983.405}
  #|{"out":{"id":4,"subscribe":{"topic":"workspaces"},"keyed":true},"w":1792593800983.459}
  #|{"out":{"id":5,"subscribe":{"topic":"status"},"keyed":true},"w":1792593800983.471}
  #|{"in":{"id":4,"value":[{"account":{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""},"workspaces":[{"id":"01M5FEN6HHK7MGP4WS3RBV1K9V","name":"Dev","role":"owner","created_at":1792593795,"stations":1,"members":1,"relays":[],"time":{"created_at":{"past":true,"at":1792593795000,"ago":"刚刚","full":"10/21 22:43:15","until":"1 分钟内"}}}],"invitations":[],"relay_url":"http://127.0.0.1:18740","loaded":true,"beta":true}]},"w":1792593801000.041}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792593801000.061}
  #|{"out":{"id":6,"subscribe":{"topic":"lock","workspace":"01M5FEN6HHK7MGP4WS3RBV1K9V"},"keyed":true},"w":1792593801000.1}
  #|{"out":{"id":7,"subscribe":{"topic":"chats","scope":"01M5FEN6HHK7MGP4WS3RBV1K9V","mine":false},"keyed":true},"w":1792593801000.167}
  #|{"out":{"id":8,"subscribe":{"topic":"changelog"},"keyed":true},"w":1792593801000.175}
  #|{"out":{"id":9,"subscribe":{"topic":"workspaceMarks","workspace":"01M5FEN6HHK7MGP4WS3RBV1K9V"},"keyed":true},"w":1792593801000.296}
  #|{"out":{"id":10,"subscribe":{"topic":"status","workspace":"01M5FEN6HHK7MGP4WS3RBV1K9V"},"keyed":true},"w":1792593801000.331}
  #|{"out":{"id":11,"subscribe":{"topic":"lockPrompts"},"keyed":true},"w":1792593801005.409}
  #|{"out":{"id":12,"call":"client.focus","params":{"visible":true,"focused":true,"workspace":"01M5FEN6HHK7MGP4WS3RBV1K9V"}},"w":1792593801007.989}
  #|{"out":{"id":13,"subscribe":{"topic":"notify"},"keyed":true},"w":1792593801008.002}
  #|{"out":{"id":14,"subscribe":{"topic":"notify","workspace":"01M5FEN6HHK7MGP4WS3RBV1K9V"},"keyed":true},"w":1792593801008.011}
  #|{"in":{"id":6,"value":{"available":true,"locked":false,"notice":true,"role":"owner","manages":true,"owner":true,"canSign":true,"signs":false,"me":{"device":"442ce9ef9baad9ef67b63e558da5f3cad25cbeb4af32b8cfcabe3ed81228ac97","code":"US3-6F3","kind":"app","confirmed":false,"waiting":false,"asked":false},"signers":0,"members":[],"stations":[{"id":"fb6aaa4a96847d41730b2a450cbd0cfd961b19420f8ead7918a5fe53fd0503b9","name":"studio","version":"0.1.0","online":true,"protected":false}],"protected":0,"requests":[],"renew":[],"attention":0}},"w":1792593801017.559}
  #|{"in":{"id":7,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"stations":[{"station":"01M5FEN6HHK7MGP4WS3RBV1K9V/fb6aaa4a96847d41730b2a450cbd0cfd961b19420f8ead7918a5fe53fd0503b9","id":"fb6aaa4a96847d41730b2a450cbd0cfd961b19420f8ead7918a5fe53fd0503b9","name":"studio","state":"online"}],"loading":false,"days":[{"daysAgo":0,"at":1792593799569,"label":"今天","items":[{"id":"ember:c-306da2e65b","session":"ember:c-306da2e65b","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","agents":[{"key":"ember:c-306da2e65b","runtime":"claude","process":"warm","pending":0,"lastTurn":{"id":"5109aa32-52df-4ece-9206-d2900418b27a","kind":"input","outcome":"completed","declared":"final","ending":"all_done","need":"answered the question that was asked","startedAt":1792593799503,"endedAt":1792593799571},"agentText":"默认模型","statusText":"已完成：answered the question that was asked"}],"last":{"seq":2,"authorKind":"agent","author":"ember:c-306da2e65b","text":"你好，我是测试用的 agent","createdAt":1792593799569,"by":{"kind":"agent","name":"agent","mine":false,"runtime":"claude","label":"agent"},"preview":"你好，我是测试用的 agent","time":{"createdAt":{"at":1792593799569,"ago":"刚刚","full":"10/21 22:43:19","until":"1 分钟内","past":true}}},"unread":true,"mine":true,"lastActiveAt":1792593799569,"station":"01M5FEN6HHK7MGP4WS3RBV1K9V/fb6aaa4a96847d41730b2a450cbd0cfd961b19420f8ead7918a5fe53fd0503b9","stationName":"studio","time":{"lastActiveAt":{"at":1792593799569,"ago":"刚刚","full":"10/21 22:43:19","until":"1 分钟内","past":true}},"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"peopleText":"你 发起","clientKey":"new:chat-383c51c6c106569487","pinned":false,"tone":"done"}]}],"trouble":null,"members":1,"leading":"agents","glyph":{"online":1,"dim":0,"connecting":0,"failing":0,"working":0,"summary":"studio","label":"1 台 station，1 台在线"},"note":{"reading":false,"text":null,"failing":[],"empty":false}}},"w":1792593801017.591}
  #|{"in":{"id":8,"value":{"app":"desktop","tabs":[{"part":"desktop","label":"桌面","days":[]},{"part":"web","label":"网页","days":[]},{"part":"android","label":"安卓","days":[]},{"part":"station","label":"Station","days":[]},{"part":"cloud","label":"云端","days":[]}],"loading":false}},"w":1792593801017.612}
  #|{"in":{"id":9,"value":{"workspaces":{"01M5FEN6HHK7MGP4WS3RBV1K9V":{"alert":0,"unread":1,"tone":"done","label":"1 个有新消息","badge":0,"items":[],"mineTone":"done"}},"badge":0,"badgeCounts":"attention","badgeKinds":{"on":true,"wait":true,"failed":true,"done":false,"message":false}}},"w":1792593801017.618}
  #|{"in":{"id":10,"value":{"items":[]}},"w":1792593801017.622}
  #|{"in":{"id":11,"value":{"pairing":[]}},"w":1792593801017.624}
  #|{"in":{"id":12,"ok":null},"w":1792593801017.626}
  #|{"in":{"id":13,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792593801017.631}
  #|{"in":{"id":14,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792593801017.635}
  #|{"out":{"id":15,"subscribe":{"topic":"longJobs","scope":"01M5FEN6HHK7MGP4WS3RBV1K9V"},"keyed":true},"w":1792593801017.667}
  #|{"out":{"id":16,"call":"notify.permission","params":{"state":"unknown"}},"w":1792593801020.096}
  #|{"in":{"id":15,"value":{"groups":[]}},"w":1792593801033.361}
  #|{"in":{"id":16,"ok":null},"w":1792593801033.366}
  #|{"step":"answered notify.permission","w":1792593801033.615}
  #|{"step":"until 端到端测试","w":1792593801050.325}
  #|{"step":"tap =Dev","w":1792593801050.333}
  #|{"step":"tap =Dev","acted":true,"w":1792593801050.345}
  #|{"step":"wait 1447","w":1792593801070.614}
  #|{"step":"now until 切换 workspace","w":1792593802518.09}
  #|{"step":"dragon 0 -300 400 切换 workspace","w":1792593802518.152}
  #|{"step":"dragon 0 -300 400 切换 workspace","acted":true,"w":1792593802518.189}
  #|{"step":"wait 1288","w":1792593802934.839}
  #|{"step":"now dragon 0 640 400 切换 workspace","w":1792593804234.844}
  #|{"step":"now dragon 0 640 400 切换 workspace","acted":true,"w":1792593804234.919}
  #|{"step":"wait 1365","w":1792593804651.786}
  #|{"step":"now gone 切换 workspace","w":1792593806017.944}
  #|{"step":"tap icon:ling","w":1792593806018}
  #|{"step":"tap icon:ling","acted":true,"w":1792593806018.041}
  #|{"out":{"id":17,"subscribe":{"topic":"newChat","scope":"01M5FEN6HHK7MGP4WS3RBV1K9V"},"keyed":true},"w":1792593806034.641}
  #|{"step":"answered machineSessions.list","w":1792593806037.722}
  #|{"in":{"id":17,"value":{"kept":"","stations":[{"station":"01M5FEN6HHK7MGP4WS3RBV1K9V/fb6aaa4a96847d41730b2a450cbd0cfd961b19420f8ead7918a5fe53fd0503b9","id":"fb6aaa4a96847d41730b2a450cbd0cfd961b19420f8ead7918a5fe53fd0503b9","name":"studio","summary":"正在连接","face":"idle","line":"在线","online":true,"reconnecting":false,"lastSeen":1792593799,"version":"0.1.0","link":{"state":"online"},"runtimes":[{"runtime":"claude","models":["claude-sonnet-5-5"]}],"models":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792593799487,"time":{"checkedAt":{"at":1792593799487,"ago":"刚刚","full":"10/21 22:43:19","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"overview":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null,"summaryText":"最近 7 天检查了 0 个 chat","changeText":null}},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","email":"alice@example.test","name":"Name of alice","sub":"alice","role":"owner","workspace":"01M5FEN6HHK7MGP4WS3RBV1K9V","device":"442ce9ef9baad9ef67b63e558da5f3cad25cbeb4af32b8cfcabe3ed81228ac97"},"connects":[],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792593799370,"time":{"checkedAt":{"at":1792593799370,"ago":"刚刚","full":"10/21 22:43:19","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792593799487,"time":{"checkedAt":{"at":1792593799487,"ago":"刚刚","full":"10/21 22:43:19","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"modelsReading":false,"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]}],"processes":[],"counts":{"sessions":1,"running":0,"warm":1},"mesh":{"state":"running","origin":"http://127.0.0.1:18787","station":"fb6aaa4a96847d41730b2a450cbd0cfd961b19420f8ead7918a5fe53fd0503b9","workspace":"Dev","workspaceId":"01M5FEN6HHK7MGP4WS3RBV1K9V","name":"studio"},"slackUsers":[],"slackTeams":[],"slackApps":[],"feishuRegistrations":[],"disk":{"freeBytes":29422252032,"totalBytes":245107195904},"logins":[],"machineLogins":[],"sharing":true,"consoleSignIn":true,"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"google","name":"Google Gemini","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xai","name":"xAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"mistral","name":"Mistral","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"deepseek","name":"DeepSeek","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen","name":"Qwen","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai","name":"Kimi","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai","name":"Z.ai","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax","name":"MiniMax","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ant-ling","name":"Ant Ling","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"jev","name":"Jev","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen-cn","name":"Qwen (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"openrouter","name":"OpenRouter","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"opencode","name":"OpenCode Zen","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"groq","name":"Groq","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"together","name":"Together AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"fireworks","name":"Fireworks","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cerebras","name":"Cerebras","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"huggingface","name":"Hugging Face","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"nvidia","name":"NVIDIA","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"baseten","name":"Baseten","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ollama","name":"Ollama","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"custom","name":"Custom","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""}],"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792593797006},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.306","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792593797006},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-lockp/apps/e2e-local/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792593797006},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-lockp/apps/e2e-local/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792593797006},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","latest":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-lockp/apps/e2e-local/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792593797006},{"id":"cursor","name":"Cursor","installed":false,"latest":"1.0.40","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792593797006},{"id":"devin","name":"Devin","installed":true,"version":"3000.11.92","latest":"3000.11.92","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-lockp/apps/e2e-local/ember/station/test/fake/devin，不是用 Devin 的安装脚本装的，需在该机器上手动更新","state":"idle","checkedAt":1792593797006}],"processesText":"没有运行中的 agent 进程","agentEnv":[],"drive":{"roots":[],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false}},"betaOffered":false,"way":{"path":"直连","via":"direct"},"time":{"lastSeen":{"at":1792593799000,"ago":"刚刚","full":"10/21 22:43:19","until":"1 分钟内","past":true}},"joined":false}],"any":true,"station":{"station":"01M5FEN6HHK7MGP4WS3RBV1K9V/fb6aaa4a96847d41730b2a450cbd0cfd961b19420f8ead7918a5fe53fd0503b9","id":"fb6aaa4a96847d41730b2a450cbd0cfd961b19420f8ead7918a5fe53fd0503b9","name":"studio","summary":"正在连接","face":"idle","line":"在线","online":true,"reconnecting":false,"lastSeen":1792593799,"version":"0.1.0","link":{"state":"online"},"runtimes":[{"runtime":"claude","models":["claude-sonnet-5-5"]}],"models":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792593799487,"time":{"checkedAt":{"at":1792593799487,"ago":"刚刚","full":"10/21 22:43:19","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"overview":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null,"summaryText":"最近 7 天检查了 0 个 chat","changeText":null}},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","email":"alice@example.test","name":"Name of alice","sub":"alice","role":"owner","workspace":"01M5FEN6HHK7MGP4WS3RBV1K9V","device":"442ce9ef9baad9ef67b63e558da5f3cad25cbeb4af32b8cfcabe3ed81228ac97"},"connects":[],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792593799370,"time":{"checkedAt":{"at":1792593799370,"ago":"刚刚","full":"10/21 22:43:19","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792593799487,"time":{"checkedAt":{"at":1792593799487,"ago":"刚刚","full":"10/21 22:43:19","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"modelsReading":false,"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]}],"processes":[],"counts":{"sessions":1,"running":0,"warm":1},"mesh":{"state":"running","origin":"http://127.0.0.1:18787","station":"fb6aaa4a96847d41730b2a450cbd0cfd961b19420f8ead7918a5fe53fd0503b9","workspace":"Dev","workspaceId":"01M5FEN6HHK7MGP4WS3RBV1K9V","name":"studio"},"slackUsers":[],"slackTeams":[],"slackApps":[],"feishuRegistrations":[],"disk":{"freeBytes":29422252032,"totalBytes":245107195904},"logins":[],"machineLogins":[],"sharing":true,"consoleSignIn":true,"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"google","name":"Google Gemini","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xai","name":"xAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"mistral","name":"Mistral","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"deepseek","name":"DeepSeek","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen","name":"Qwen","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai","name":"Kimi","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai","name":"Z.ai","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax","name":"MiniMax","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ant-ling","name":"Ant Ling","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"jev","name":"Jev","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen-cn","name":"Qwen (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"openrouter","name":"OpenRouter","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"opencode","name":"OpenCode Zen","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"groq","name":"Groq","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"together","name":"Together AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"fireworks","name":"Fireworks","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cerebras","name":"Cerebras","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"huggingface","name":"Hugging Face","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"nvidia","name":"NVIDIA","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"baseten","name":"Baseten","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ollama","name":"Ollama","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"custom","name":"Custom","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""}],"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792593797006},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.306","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792593797006},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-lockp/apps/e2e-local/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792593797006},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-lockp/apps/e2e-local/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792593797006},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","latest":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-lockp/apps/e2e-local/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792593797006},{"id":"cursor","name":"Cursor","installed":false,"latest":"1.0.40","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792593797006},{"id":"devin","name":"Devin","installed":true,"version":"3000.11.92","latest":"3000.11.92","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-lockp/apps/e2e-local/ember/station/test/fake/devin，不是用 Devin 的安装脚本装的，需在该机器上手动更新","state":"idle","checkedAt":1792593797006}],"processesText":"没有运行中的 agent 进程","agentEnv":[],"drive":{"roots":[],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false}},"betaOffered":false,"way":{"path":"直连","via":"direct"},"time":{"lastSeen":{"at":1792593799000,"ago":"刚刚","full":"10/21 22:43:19","until":"1 分钟内","past":true}},"joined":false},"model":{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792593799487,"time":{"checkedAt":{"at":1792593799487,"ago":"刚刚","full":"10/21 22:43:19","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}},"runtime":"claude","efforts":["low","medium","high","xhigh","max"],"accounts":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792593799487,"time":{"checkedAt":{"at":1792593799487,"ago":"刚刚","full":"10/21 22:43:19","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}],"pickAccount":false,"waiting":false,"pick":{"fastAvailable":false,"options":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792593799487,"time":{"checkedAt":{"at":1792593799487,"ago":"刚刚","full":"10/21 22:43:19","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]},"availability":"here"}],"runtimeFixed":false,"value":{"model":"claude-sonnet-5-5","runtime":"claude"},"valueOption":{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792593799487,"time":{"checkedAt":{"at":1792593799487,"ago":"刚刚","full":"10/21 22:43:19","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]},"availability":"here"},"draft":{"model":"claude-sonnet-5-5","runtime":"claude"},"option":"claude-sonnet-5-5","runtimes":[],"efforts":["low","medium","high","xhigh","max"],"accounts":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792593799487,"time":{"checkedAt":{"at":1792593799487,"ago":"刚刚","full":"10/21 22:43:19","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}],"who":"账号","autoNote":"额度用完或登录失效时自动切换","changed":false,"was":["Sonnet 5.5","默认深度","自动 · "],"becomes":["Sonnet 5.5","默认深度","自动分配"],"modelText":"Sonnet 5.5","maker":{"id":"anthropic","name":"Anthropic"},"accountText":"自动分配","accountNote":"额度用完或登录失效时自动切换","accountWarn":false,"saveText":"无变更"},"frequent":[]}},"w":1792593806067.142}
  #|{"out":{"id":18,"call":"machineSessions.list","params":{"station":"01M5FEN6HHK7MGP4WS3RBV1K9V/fb6aaa4a96847d41730b2a450cbd0cfd961b19420f8ead7918a5fe53fd0503b9"}},"w":1792593806076.016}
  #|{"out":{"id":19,"call":"draft.get","params":{"key":"new:01M5FEN6HHK7MGP4WS3RBV1K9V/fb6aaa4a96847d41730b2a450cbd0cfd961b19420f8ead7918a5fe53fd0503b9"}},"w":1792593806076.037}
  #|{"in":{"id":19,"ok":{"text":"","quotes":[],"files":[],"id":"draft-33bc8fd07ba5e9f6d1"}},"w":1792593806083.352}
  #|{"in":{"id":18,"ok":{"sessions":[]}},"w":1792593806083.398}
  #|{"step":"answered draft.get","w":1792593806100.395}
  #|{"step":"wait 380","w":1792593806117.108}
  #|{"in":{"id":17,"delta":[{"path":["station","host"],"set":{"hostname":"3720-Mac-mini-1","os":"macOS 27.0.1","arch":"arm64","cpus":10,"cpuModel":"Apple M4","load":0.49,"cpuBusy":0.09,"uptimeSec":73168,"memory":{"totalBytes":17179869184,"usedBytes":8670838784,"swapUsedBytes":250347520},"disk":{"path":"/tmp/mbe2e-C/data","totalBytes":245107195904,"freeBytes":29422010368},"emberRssBytes":158693056,"checkedAt":1792593806112,"summary":"10 核 · 16 GB","line":"macOS 27.0.1 · 10 核 · 16 GB · 已运行 0 天","facts":["3720-Mac-mini-1","macOS 27.0.1","arm64 · 10 核","已运行 20 小时"],"meters":[{"label":"CPU","short":"CPU","percent":9,"left":91,"level":"ok","value":"9%","remaining":"空闲 91%","big":"91","unit":"%","title":"CPU 空闲","total":"负载 4.9","note":"负载 4.9 · Apple M4"},{"label":"内存","short":"内存","percent":50,"left":50,"level":"ok","value":"8.1 GB / 16.0 GB","remaining":"剩 7.9 G","big":"7.9","unit":"GB","title":"内存剩","total":"共 16 GB","note":"swap 0.2 GB"},{"label":"磁盘","short":"磁盘","percent":88,"left":12,"level":"amber","value":"剩余 27.4 GB / 228 GB","remaining":"剩 27.4 G","big":"27.4","unit":"GB","title":"磁盘剩","total":"共 228 GB"}],"identity":"Apple M4 · 16 GB · macOS 27.0.1","details":[{"label":"主机名","value":"3720-Mac-mini-1"},{"label":"芯片","value":"Apple M4 · 10 核 · arm64"},{"label":"已运行","value":"20 小时"},{"label":"still.fail","value":"进程占用 151 MB"}],"usage":"内存 8.1 GB / 16.0 GB · 磁盘 剩余 27.4 GB / 228 GB","emberText":"still.fail 151 MB"}},{"path":["station","line"],"set":"Apple M4"},{"path":["station","summary"],"set":"空闲 · Apple M4 · 16 GB · macOS 27.0.1"},{"path":["stations",0,"host"],"set":{"hostname":"3720-Mac-mini-1","os":"macOS 27.0.1","arch":"arm64","cpus":10,"cpuModel":"Apple M4","load":0.49,"cpuBusy":0.09,"uptimeSec":73168,"memory":{"totalBytes":17179869184,"usedBytes":8670838784,"swapUsedBytes":250347520},"disk":{"path":"/tmp/mbe2e-C/data","totalBytes":245107195904,"freeBytes":29422010368},"emberRssBytes":158693056,"checkedAt":1792593806112,"summary":"10 核 · 16 GB","line":"macOS 27.0.1 · 10 核 · 16 GB · 已运行 0 天","facts":["3720-Mac-mini-1","macOS 27.0.1","arm64 · 10 核","已运行 20 小时"],"meters":[{"label":"CPU","short":"CPU","percent":9,"left":91,"level":"ok","value":"9%","remaining":"空闲 91%","big":"91","unit":"%","title":"CPU 空闲","total":"负载 4.9","note":"负载 4.9 · Apple M4"},{"label":"内存","short":"内存","percent":50,"left":50,"level":"ok","value":"8.1 GB / 16.0 GB","remaining":"剩 7.9 G","big":"7.9","unit":"GB","title":"内存剩","total":"共 16 GB","note":"swap 0.2 GB"},{"label":"磁盘","short":"磁盘","percent":88,"left":12,"level":"amber","value":"剩余 27.4 GB / 228 GB","remaining":"剩 27.4 G","big":"27.4","unit":"GB","title":"磁盘剩","total":"共 228 GB"}],"identity":"Apple M4 · 16 GB · macOS 27.0.1","details":[{"label":"主机名","value":"3720-Mac-mini-1"},{"label":"芯片","value":"Apple M4 · 10 核 · arm64"},{"label":"已运行","value":"20 小时"},{"label":"still.fail","value":"进程占用 151 MB"}],"usage":"内存 8.1 GB / 16.0 GB · 磁盘 剩余 27.4 GB / 228 GB","emberText":"still.fail 151 MB"}},{"path":["stations",0,"line"],"set":"Apple M4"},{"path":["stations",0,"summary"],"set":"空闲 · Apple M4 · 16 GB · macOS 27.0.1"}]},"w":1792593806183.409}
  #|{"step":"now until 想让 agent 做什么？","w":1792593806500.286}
  #|{"step":"tap =studio","w":1792593806500.306}
  #|{"step":"tap =studio","acted":true,"w":1792593806500.321}
  #|{"step":"wait 1426","w":1792593806520.581}
  #|{"step":"now until 选择运行的 station","w":1792593807951.506}
  #|{"step":"dragon 0 40 304 选择运行的 station","w":1792593807951.571}
  #|{"step":"dragon 0 40 304 选择运行的 station","acted":true,"w":1792593807951.606}
  #|{"step":"wait 1288","w":1792593808284.017}
  #|{"step":"now until 选择运行的 station","w":1792593809600.782}
  #|{"step":"dragon 0 200 304 选择运行的 station","w":1792593809600.809}
  #|{"step":"dragon 0 200 304 选择运行的 station","acted":true,"w":1792593809600.829}
  #|{"step":"wait 1387","w":1792593809934.87}
  #|{"step":"now gone 选择运行的 station","w":1792593811334.538}
  #|{"step":"tap =studio","w":1792593811334.6}
  #|{"step":"tap =studio","acted":true,"w":1792593811334.639}
  #|{"step":"wait 1426","w":1792593811351.963}
  #|{"step":"now tap1 =studio","w":1792593812784.875}
  #|{"step":"now tap1 =studio","acted":true,"w":1792593812784.957}
  #|{"out":{"id":20,"call":"newChat.pick","params":{"station":"fb6aaa4a96847d41730b2a450cbd0cfd961b19420f8ead7918a5fe53fd0503b9","scope":"01M5FEN6HHK7MGP4WS3RBV1K9V"}},"w":1792593812800.442}
  #|{"step":"answered newChat.pick","w":1792593812801.716}
  #|{"in":{"id":20,"ok":null},"w":1792593812816.696}
  #|{"step":"wait 1426","w":1792593812834.858}
  #|{"in":{"id":17,"delta":[{"path":["kept"],"set":"fb6aaa4a96847d41730b2a450cbd0cfd961b19420f8ead7918a5fe53fd0503b9"}]},"w":1792593812966.693}
  #|{"step":"now gone 选择运行的 station","w":1792593814351.495}
  #|{"step":"tap =取消","w":1792593814351.552}
  #|{"step":"tap =取消","acted":true,"w":1792593814351.592}
  #|{"step":"wait 380","w":1792593814369.041}
  #|{"step":"now until 端到端测试","w":1792593814751.912}
  #|{"step":"wait 358","w":1792593814751.986}
  #|{"step":"","w":1792593815117.981}
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
  #|{"textrec":{"s":[17,700,0,"切换 workspace"],"r":[0,1,16.851167315175097,63,1,1,16.851167315175097,64,2,1,3.951171875,-1,3,1,13.783447265625,65,4,1,9.915283203125,66,5,1,6.96435546875,67,6,1,9.60400390625,68,7,1,9.010498046875,69,8,1,10.56689453125,70,9,1,9.591552734375,71,10,1,9.55419921875,72,11,1,9.782470703125,73]}}
  #|{"textrec":{"m":[17,700,0],"r":[16.435546875,3.5859375,24,16.435546875,3.5859375,0]}}
  #|{"textrec":{"s":[15,400,0,"登录其他账号"],"r":[0,1,14.883268482490273,74,1,1,14.883268482490273,75,2,1,14.883268482490273,76,3,1,14.883268482490273,77,4,1,14.88326848249028,78,5,1,14.88326848249028,79]}}
  #|{"textrec":{"s":[12,400,0,"保留已登录账号，添加另一个账号"],"r":[0,1,11.918287937743191,80,1,1,11.918287937743191,81,2,1,11.918287937743195,82,3,1,11.918287937743187,83,4,1,11.918287937743187,84,5,1,11.918287937743187,85,6,1,11.918287937743187,86,7,1,12.081712062256813,87,8,1,11.918287937743187,88,9,1,11.918287937743187,89,10,1,11.918287937743187,90,11,1,11.918287937743202,91,12,1,11.918287937743202,92,13,1,11.918287937743202,85,14,1,11.918287937743202,86]}}
  #|{"textrec":{"m":[12,400,0],"r":[11.6015625,2.53125,17,11.6015625,2.53125,0]}}
  #|{"textrec":{"s":[15,400,0,"新建 workspace"],"r":[0,1,14.883268482490273,93,1,1,14.883268482490273,94,2,1,3.984375,-1,3,1,11.2353515625,95,4,1,8.4814453125,96,5,1,5.478515625,97,6,1,7.763671875,98,7,1,7.470703125,99,8,1,8.9208984375,100,9,1,8.0419921875,101,10,1,8.1591796875,102,11,1,8.3349609375,103]}}
  #|{"textrec":{"s":[13,400,0,"当前使用"],"r":[0,1,12.898832684824903,104,1,1,12.898832684824903,105,2,1,12.898832684824903,106,3,1,12.898832684824903,107]}}
  #|{"textrec":{"s":[15,400,0,"Dev"],"r":[0,1,10.6640625,108,1,1,8.26171875,103,2,1,7.822265625,109]}}
  #|{"textrec":{"s":[12,400,0,"alice@example.test"],"r":[0,1,6.62109375,110,1,1,3.03515625,111,2,1,2.96484375,112,3,1,6.71484375,113,4,1,6.85546875,114,5,1,11.015625,115,6,1,6.73828125,114,7,1,6.17578125,116,8,1,6.62109375,110,9,1,10.44140625,117,10,1,7.32421875,118,11,1,3.03515625,111,12,1,6.85546875,114,13,1,3.4453125,119,14,1,4.1982421875,120,15,1,6.8115234375,114,16,1,6.251953125,121,17,1,4.330078125,120]}}
  #|{"textrec":{"g":63,"r":[666,0,18,18,-1,-15,0]}}
  #|{"textrec":{"g":64,"r":[685,0,19,18,-1,-15,0]}}
  #|{"textrec":{"g":65,"r":[705,0,16,12,-1,-11,0]}}
  #|{"textrec":{"g":66,"r":[722,0,12,13,-1,-11,0]}}
  #|{"textrec":{"g":67,"r":[735,0,8,12,0,-11,0]}}
  #|{"textrec":{"g":68,"r":[744,0,11,15,0,-14,0]}}
  #|{"textrec":{"g":69,"r":[756,0,11,13,-1,-11,0]}}
  #|{"textrec":{"g":70,"r":[768,0,12,16,0,-11,0]}}
  #|{"textrec":{"g":71,"r":[781,0,11,13,-1,-11,0]}}
  #|{"textrec":{"g":72,"r":[793,0,12,13,-1,-11,0]}}
  #|{"textrec":{"g":73,"r":[806,0,12,13,-1,-11,0]}}
  #|{"textrec":{"g":104,"r":[819,0,13,15,0,-12,0]}}
  #|{"textrec":{"g":105,"r":[833,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":106,"r":[849,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":107,"r":[865,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":108,"r":[880,0,11,13,0,-12,0]}}
  #|{"textrec":{"g":103,"r":[892,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":109,"r":[903,0,10,10,-1,-9,0]}}
  #|{"textrec":{"g":110,"r":[914,0,8,10,-1,-8,0]}}
  #|{"textrec":{"g":111,"r":[923,0,4,11,0,-10,0]}}
  #|{"textrec":{"g":112,"r":[928,0,5,11,-1,-10,0]}}
  #|{"textrec":{"g":113,"r":[934,0,9,10,-1,-8,0]}}
  #|{"textrec":{"g":114,"r":[944,0,9,10,-1,-8,0]}}
  #|{"textrec":{"g":115,"r":[954,0,13,13,-1,-10,0]}}
  #|{"textrec":{"g":116,"r":[968,0,8,9,-1,-8,0]}}
  #|{"textrec":{"g":117,"r":[977,0,12,9,-1,-8,0]}}
  #|{"textrec":{"g":118,"r":[990,0,9,12,-1,-8,0]}}
  #|{"textrec":{"g":119,"r":[1000,0,4,5,0,-3,0]}}
  #|{"textrec":{"g":120,"r":[1005,0,6,11,-1,-9,0]}}
  #|{"textrec":{"g":121,"r":[1012,0,8,10,-1,-8,0]}}
  #|{"textrec":{"g":74,"r":[1021,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":75,"r":[1039,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":76,"r":[1056,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":77,"r":[1073,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":78,"r":[1090,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":79,"r":[1108,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":80,"r":[1125,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":81,"r":[1140,0,13,14,-1,-11,0]}}
  #|{"textrec":{"g":82,"r":[1154,0,13,12,0,-10,0]}}
  #|{"textrec":{"g":83,"r":[1168,0,14,13,-1,-11,0]}}
  #|{"textrec":{"g":84,"r":[1183,0,13,14,-1,-11,0]}}
  #|{"textrec":{"g":85,"r":[1197,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":86,"r":[1212,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":87,"r":[1227,0,5,6,0,-3,0]}}
  #|{"textrec":{"g":88,"r":[1233,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":89,"r":[1248,0,13,14,-1,-11,0]}}
  #|{"textrec":{"g":90,"r":[1262,0,13,14,-1,-11,0]}}
  #|{"textrec":{"g":91,"r":[1276,0,14,4,-1,-6,0]}}
  #|{"textrec":{"g":92,"r":[1291,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":93,"r":[1306,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":94,"r":[1324,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":95,"r":[1341,0,14,10,-1,-9,0]}}
  #|{"textrec":{"g":96,"r":[1356,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":97,"r":[1368,0,7,11,0,-10,0]}}
  #|{"textrec":{"g":98,"r":[1376,0,9,14,0,-13,0]}}
  #|{"textrec":{"g":99,"r":[1386,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":100,"r":[1397,0,10,14,0,-10,0]}}
  #|{"textrec":{"g":101,"r":[1408,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":102,"r":[1419,0,10,12,-1,-10,0]}}
  #|{"textrec":{"ib":["e13e77444a4987cd",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["d87c77ac2dcb8d23",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["2bb63fc1d380f765",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"s":[16,600,0,"新对话"],"r":[0,1,15.875486381322958,122,1,1,15.875486381322958,31,2,1,15.875486381322958,32]}}
  #|{"textrec":{"s":[17,400,0,"取消"],"r":[0,1,16.851167315175097,123,1,1,16.851167315175097,124]}}
  #|{"textrec":{"m":[17,400,0],"r":[16.435546875,3.5859375,24,16.435546875,3.5859375,0]}}
  #|{"textrec":{"g":122,"r":[1430,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":123,"r":[1449,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":124,"r":[1468,0,18,18,-1,-15,0]}}
  #|{"textrec":{"ib":["a1e7be43eb966606",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"ib":["504a4df6beac534a",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"m":[16,400,0],"r":[15.46875,3.375,23,15.46875,3.375,0]}}
  #|{"textrec":{"s":[22,700,0,"想让 agent 做什么？"],"r":[0,1,20.94548872180451,125,1,1,20.94548872180451,126,2,1,4.717369616031647,-1,3,1,12.220596134662628,127,4,1,13.331922113895416,128,5,1,12.428017258644104,129,6,1,12.945789515972137,130,7,1,8.15379598736763,131,8,1,4.717369616031647,-1,9,1,20.94548872180451,132,10,1,20.94548872180451,133,11,1,20.94548872180451,134,12,1,10.607142857142861,135]}}
  #|{"textrec":{"m":[22,700,0],"r":[21.26953125,4.640625,31,18.91900634765625,3.08099365234375,0]}}
  #|{"textrec":{"s":[14,400,0,"描述要做的事。它会在 studio 上使用所选模型新建会话。"],"r":[0,1,13.891050583657588,136,1,1,13.891050583657588,137,2,1,13.891050583657588,138,3,1,13.891050583657588,139,4,1,13.891050583657588,56,5,1,13.891050583657588,140,6,1,14.081712062256813,141,7,1,13.891050583657588,142,8,1,13.891050583657588,143,9,1,13.891050583657588,144,10,1,3.787109375,-1,11,1,7.1435546875,145,12,1,4.9013671875,61,13,1,8.0185546875,146,14,1,8.44921875,147,15,1,3.30859375,148,16,1,8.12109375,149,17,1,3.787109375,-1,18,1,13.891050583657574,150,19,1,13.891050583657602,151,20,1,13.891050583657602,55,21,1,13.891050583657602,152,22,1,13.891050583657602,153,23,1,13.891050583657602,154,24,1,13.891050583657602,155,25,1,13.891050583657602,156,26,1,13.891050583657602,157,27,1,13.891050583657602,143,28,1,13.891050583657602,158,29,1,7.081712062256827,141]}}
  #|{"textrec":{"s":[13,400,0,"studio"],"r":[0,1,6.69677734375,10,1,1,4.61474609375,159,2,1,7.50927734375,160,3,1,7.9091796875,161,4,1,3.1357421875,162,5,1,7.6044921875,7]}}
  #|{"textrec":{"s":[13,400,0,"Sonnet 5.5 · 默认深度"],"r":[0,1,8.20751953125,163,1,1,7.6044921875,7,2,1,7.50927734375,164,3,1,7.50927734375,164,4,1,7.3505859375,14,5,1,4.646484375,159,6,1,3.580078125,-1,7,1,7.73779296875,165,8,1,3.354736328125,166,9,1,7.753662109375,165,10,1,3.580078125,-1,11,1,6.228545204222115,167,12,1,3.580078125,-1,13,1,12.898832684824896,168,14,1,12.898832684824896,169,15,1,12.898832684824896,170,16,1,12.898832684824896,171]}}
  #|{"textrec":{"g":125,"r":[1487,0,23,21,-1,-18,0]}}
  #|{"textrec":{"g":126,"r":[1511,0,23,21,-1,-18,0]}}
  #|{"textrec":{"g":127,"r":[1535,0,14,15,-1,-13,0]}}
  #|{"textrec":{"g":128,"r":[1550,0,15,19,-1,-13,0]}}
  #|{"textrec":{"g":129,"r":[1566,0,14,15,-1,-13,0]}}
  #|{"textrec":{"g":130,"r":[1581,0,14,14,0,-13,0]}}
  #|{"textrec":{"g":131,"r":[1596,0,10,18,-1,-16,0]}}
  #|{"textrec":{"g":132,"r":[1607,0,23,23,-1,-19,0]}}
  #|{"textrec":{"g":133,"r":[1631,0,22,23,-1,-19,0]}}
  #|{"textrec":{"g":134,"r":[1654,0,22,23,-1,-19,0]}}
  #|{"textrec":{"g":135,"r":[1677,0,12,19,-1,-17,0]}}
  #|{"textrec":{"g":136,"r":[1690,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":137,"r":[1706,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":138,"r":[1723,0,16,15,-1,-12,0]}}
  #|{"textrec":{"g":139,"r":[1740,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":140,"r":[1757,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":141,"r":[1774,0,6,6,0,-3,0]}}
  #|{"textrec":{"g":142,"r":[1781,0,14,15,0,-13,0]}}
  #|{"textrec":{"g":143,"r":[1796,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":144,"r":[1813,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":145,"r":[1829,0,9,11,-1,-9,0]}}
  #|{"textrec":{"g":146,"r":[1839,0,9,11,0,-9,0]}}
  #|{"textrec":{"g":147,"r":[1849,0,10,14,-1,-12,0]}}
  #|{"textrec":{"g":148,"r":[1860,0,5,13,-1,-12,0]}}
  #|{"textrec":{"g":149,"r":[1866,0,10,11,-1,-9,0]}}
  #|{"textrec":{"g":150,"r":[1877,0,15,15,-1,-13,0]}}
  #|{"textrec":{"g":151,"r":[1893,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":152,"r":[1910,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":153,"r":[1927,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":154,"r":[1944,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":155,"r":[1961,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":156,"r":[1977,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":157,"r":[1994,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":158,"r":[2010,0,16,16,-1,-13,0]}}
  #|{"textrec":{"ib":["c5e03166c48d7075",105988,256],"r":[230,115,230,115]}}
  #|{"textrec":{"g":10,"r":[2027,0,9,10,-1,-8,0]}}
  #|{"textrec":{"g":159,"r":[2037,0,7,12,-1,-10,0]}}
  #|{"textrec":{"g":160,"r":[0,24,9,10,-1,-8,0]}}
  #|{"textrec":{"g":161,"r":[10,24,9,13,-1,-11,0]}}
  #|{"textrec":{"g":162,"r":[20,24,5,12,-1,-11,0]}}
  #|{"textrec":{"g":7,"r":[26,24,9,10,-1,-8,0]}}
  #|{"textrec":{"g":163,"r":[36,24,10,13,-1,-11,0]}}
  #|{"textrec":{"g":164,"r":[47,24,8,9,0,-8,0]}}
  #|{"textrec":{"g":14,"r":[56,24,9,10,-1,-8,0]}}
  #|{"textrec":{"g":165,"r":[66,24,10,13,-1,-11,0]}}
  #|{"textrec":{"g":166,"r":[77,24,4,5,0,-3,0]}}
  #|{"textrec":{"g":167,"r":[82,24,4,5,1,-7,0]}}
  #|{"textrec":{"g":168,"r":[87,24,15,15,-1,-12,0]}}
  #|{"textrec":{"g":169,"r":[103,24,15,15,-1,-12,0]}}
  #|{"textrec":{"g":170,"r":[119,24,15,15,-1,-12,0]}}
  #|{"textrec":{"g":171,"r":[135,24,15,15,-1,-12,0]}}
  #|{"textrec":{"ib":["38d950bb96ef001f",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["67313e91c47b1daa",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"s":[16,400,0,"做任何事"],"r":[0,1,15.875486381322958,172,1,1,15.875486381322958,173,2,1,15.875486381322958,174,3,1,15.875486381322958,175]}}
  #|{"textrec":{"g":172,"r":[151,24,18,17,-1,-14,0]}}
  #|{"textrec":{"g":173,"r":[170,24,17,17,-1,-14,0]}}
  #|{"textrec":{"g":174,"r":[188,24,17,17,-1,-14,0]}}
  #|{"textrec":{"g":175,"r":[206,24,17,17,-1,-14,0]}}
  #|{"textrec":{"ib":["c7a6d30e254a5910",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"ib":["b277602c41d156e7",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"s":[17,700,0,"选择运行的 station"],"r":[0,1,16.851167315175097,176,1,1,16.851167315175097,177,2,1,16.851167315175097,178,3,1,16.851167315175097,179,4,1,16.851167315175104,180,5,1,3.951171875,-1,6,1,9.176513671875,69,7,1,6.561767578125,181,8,1,9.591552734375,71,9,1,6.58251953125,181,10,1,4.44921875,182,11,1,10.10205078125,66,12,1,10.230712890625,183]}}
  #|{"textrec":{"s":[15,400,0,"studio"],"r":[0,1,7.58056640625,99,1,1,5.17822265625,184,2,1,8.51806640625,185,3,1,8.9794921875,186,4,1,3.4716796875,187,5,1,8.6279296875,96]}}
  #|{"textrec":{"s":[12,400,0,"空闲 · Apple M4 · 16 GB · macOS 27.0.1"],"r":[0,1,11.918287937743191,188,1,1,11.918287937743191,189,2,1,3.375,-1,3,1,5.754933455713633,190,4,1,3.375,-1,5,1,8.0859375,191,6,1,7.32421875,118,7,1,7.32421875,118,8,1,3.03515625,111,9,1,6.85546875,114,10,1,3.375,-1,11,1,10.48828125,192,12,1,7.72265625,193,13,1,3.375,-1,14,1,5.754933455713626,190,15,1,3.375,-1,16,1,5.56640625,194,17,1,7.640625,195,18,1,3.375,-1,19,1,8.958984375000014,196,20,1,7.88671875,197,21,1,3.375,-1,22,1,5.754933455713626,190,23,1,3.375,-1,24,1,10.44140625,117,25,1,6.62109375,110,26,1,6.71484375,113,27,1,9.2578125,198,28,1,7.646484375,199,29,1,3.375,-1,30,1,7.2421875,200,31,1,6.1875,201,32,1,2.68359375,119,33,1,7.08984375,202,34,1,3.15234375,119,35,1,5.390625,194]}}
  #|{"textrec":{"g":176,"r":[224,24,18,18,-1,-15,0]}}
  #|{"textrec":{"g":177,"r":[243,24,19,18,-1,-15,0]}}
  #|{"textrec":{"g":178,"r":[263,24,18,18,-1,-15,0]}}
  #|{"textrec":{"g":179,"r":[282,24,18,18,-1,-15,0]}}
  #|{"textrec":{"g":180,"r":[301,24,17,18,0,-15,0]}}
  #|{"textrec":{"g":181,"r":[319,24,9,15,-1,-13,0]}}
  #|{"textrec":{"g":182,"r":[329,24,5,16,0,-15,0]}}
  #|{"textrec":{"g":183,"r":[335,24,11,12,0,-11,0]}}
  #|{"textrec":{"g":184,"r":[347,24,7,13,-1,-11,0]}}
  #|{"textrec":{"g":185,"r":[355,24,9,11,0,-9,0]}}
  #|{"textrec":{"g":186,"r":[365,24,10,15,-1,-13,0]}}
  #|{"textrec":{"g":187,"r":[376,24,5,14,-1,-13,0]}}
  #|{"textrec":{"g":188,"r":[382,24,13,13,-1,-11,0]}}
  #|{"textrec":{"g":189,"r":[396,24,12,14,0,-11,0]}}
  #|{"textrec":{"g":190,"r":[409,24,5,5,0,-7,0]}}
  #|{"textrec":{"g":191,"r":[415,24,10,11,-1,-10,0]}}
  #|{"textrec":{"g":192,"r":[426,24,11,11,0,-10,0]}}
  #|{"textrec":{"g":193,"r":[438,24,10,11,-1,-10,0]}}
  #|{"textrec":{"g":194,"r":[449,24,7,11,-1,-10,0]}}
  #|{"textrec":{"g":195,"r":[457,24,9,12,-1,-10,0]}}
  #|{"textrec":{"g":196,"r":[467,24,11,12,-1,-10,0]}}
  #|{"textrec":{"g":197,"r":[479,24,9,11,0,-10,0]}}
  #|{"textrec":{"g":198,"r":[489,24,11,12,-1,-10,0]}}
  #|{"textrec":{"g":199,"r":[501,24,9,12,-1,-10,0]}}
  #|{"textrec":{"g":200,"r":[511,24,9,11,-1,-10,0]}}
  #|{"textrec":{"g":201,"r":[521,24,9,11,-1,-10,0]}}
  #|{"textrec":{"g":202,"r":[531,24,9,12,-1,-10,0]}}
  #|{"textrec":{"ib":["f68dbe6aa56805aa",2026,64],"r":[22,22,22,22]}}
