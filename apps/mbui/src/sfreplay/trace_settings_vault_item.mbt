// e2e/traces/settings-vault-item.trace, made by scripts/trace.py from 01-settings_vault_item.log: not edited by hand.

///|
/// What the app and its core said in the run, a line each.
pub let trace_settings_vault_item : String =
  #|{"env":{"MBUI_CLOUD":"http://127.0.0.1:18787","MBUI_CORE_ACCOUNT":"{\"sub\":\"alice\",\"email\":\"alice@example.test\",\"name\":\"Name of alice\",\"picture\":\"\",\"access\":\"-\",\"refresh\":\"-\",\"accessExpires\":1792610338}"}}
  #|{"out":{"id":1,"call":"client.device","params":{"client":"still.fail mbui","app":"desktop","userAgent":"Macintosh; Mac OS X"}},"w":1792610039938.498}
  #|{"in":{"id":1,"ok":null},"w":1792610040018.084}
  #|{"out":{"id":2,"subscribe":{"topic":"accounts"},"keyed":true},"w":1792610040018.108}
  #|{"out":{"id":3,"subscribe":{"topic":"prefs"},"keyed":true},"w":1792610040018.117}
  #|{"step":"# written by scripts/rerecord.sh from its test (src/sfreplay/emit.mbt): not edited by hand","w":1792610040019.593}
  #|{"step":"timeout 90000","w":1792610040019.601}
  #|{"step":"answered client.device","w":1792610040019.604}
  #|{"step":"answered client.focus","w":1792610040037.633}
  #|{"in":{"id":2,"value":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""}]},"w":1792610040133.537}
  #|{"in":{"id":3,"value":{"onlyMine":false,"onlyWatching":false,"onlyDecisions":false,"listFilter":{},"appearance":"system","rowPicture":"auto","absoluteTime":false,"lang":"zh","keys":{},"lastChat":{},"openChat":{},"chatTabs":{},"dropFiles":{},"driveViews":{},"filesTabs":{},"driveFavorites":{},"resume":{},"stationUpdatesDismissed":{},"device":{"app":"desktop","phone":false,"handoff":false},"reader":{"size":18,"line":1.7,"margin":22,"face":"sans","indent":true,"paper":"follow"},"rails":{},"bars":{"sets":[["chats","files","profiles","stations"],["decisions","usage","connects","archive"]],"current":0},"barsBy":{},"fonts":{},"faces":{"ui":{"id":"","name":"","mono":false,"family":"","files":[],"bytes":0},"text":{"id":"","name":"","mono":false,"family":"","files":[],"bytes":0},"code":{"id":"","name":"","mono":true,"family":"","files":[],"bytes":0},"list":[{"id":"inter","name":"Inter","mono":false,"family":"SF Inter","css":"http://127.0.0.1:18787/releases/fonts/inter/4.001/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/inter/4.001/var.ttf.gz","bytes":457818,"sha256":"29160a80ff49ddcab2c97711247e08b1fab27a484a329ce8b813d820dc559031"}],"preview":"http://127.0.0.1:18787/releases/fonts/inter/4.001/preview-194fa287.ttf","bytes":457818},{"id":"noto-sans-sc","name":"思源黑体","mono":false,"family":"SF Noto Sans SC","css":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/var.ttf.gz","bytes":11276563,"sha256":"a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da"}],"preview":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/preview-f0494178.ttf","bytes":11276563},{"id":"noto-serif-sc","name":"思源宋体","mono":false,"family":"SF Noto Serif SC","css":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/var.ttf.gz","bytes":15454579,"sha256":"050080d9255a86808f2945bffac582b31ef32bc36411ce29563b4961670c66f9"}],"preview":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/preview-001bbedf.ttf","bytes":15454579},{"id":"lxgw-wenkai","name":"霞鹜文楷","mono":false,"family":"SF LXGW WenKai","css":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/font.css","files":[{"weight":400,"url":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/400.ttf.gz","bytes":12904482,"sha256":"2d73eea94ad808999d90c0000c239a84a33b09d4bc6ab6c5b8bbf1eda8a7fc8b"},{"weight":500,"url":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/500.ttf.gz","bytes":13272430,"sha256":"f4b8a34d1f838fe411540cb7c97b1c384ac9738a876c4104500bc42508b2312a"}],"preview":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/preview-d3505af4.ttf","bytes":26176912},{"id":"jetbrains-mono","name":"JetBrains Mono","mono":true,"family":"SF JetBrains Mono","css":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/var.ttf.gz","bytes":90579,"sha256":"48715a42ec242c21e9f02692891e147d022299a52e48d5e413e1a942193ffeda"}],"preview":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/preview-ee73078f.ttf","bytes":90579},{"id":"fira-code","name":"Fira Code","mono":true,"family":"SF Fira Code","css":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/var.ttf.gz","bytes":137151,"sha256":"9335b082b3c7850d98a64b584f3417f65355f3471278bb5eeb8c6c0e8657aeeb"}],"preview":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/preview-555be27a.ttf","bytes":137151},{"id":"maple-mono","name":"Maple Mono","mono":true,"family":"SF Maple Mono CN","css":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/font.css","files":[{"weight":400,"url":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/400.ttf.gz","bytes":8352545,"sha256":"0fcc5139bfd5ab14ff989bb7dfd5236d0cafc10e60b9828569e6883613ab4085"},{"weight":600,"url":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/600.ttf.gz","bytes":8438132,"sha256":"96ed7ae26ee7c50b02b2d2b2bc0f1a0cbabe45ae5d6e6abf6678e2177c415677"}],"preview":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/preview-cffdf246.ttf","bytes":16790677}]}}},"w":1792610040133.596}
  #|{"out":{"id":4,"subscribe":{"topic":"workspaces"},"keyed":true},"w":1792610040133.661}
  #|{"out":{"id":5,"subscribe":{"topic":"status"},"keyed":true},"w":1792610040133.675}
  #|{"in":{"id":4,"value":[{"account":{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""},"workspaces":[{"id":"01M5FY4RZM755X3GCF020J3Y5K","name":"Dev","role":"owner","created_at":1792610034,"stations":1,"members":1,"relays":[],"time":{"created_at":{"past":true,"at":1792610034000,"ago":"刚刚","full":"10/22 03:13:54","until":"1 分钟内"}}}],"invitations":[],"relay_url":"http://127.0.0.1:18740","loaded":true,"beta":true}]},"w":1792610040150.19}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792610040150.219}
  #|{"out":{"id":6,"subscribe":{"topic":"lock","workspace":"01M5FY4RZM755X3GCF020J3Y5K"},"keyed":true},"w":1792610040150.261}
  #|{"out":{"id":7,"subscribe":{"topic":"chats","scope":"01M5FY4RZM755X3GCF020J3Y5K","mine":false},"keyed":true},"w":1792610040150.276}
  #|{"out":{"id":8,"subscribe":{"topic":"changelog"},"keyed":true},"w":1792610040150.285}
  #|{"out":{"id":9,"subscribe":{"topic":"workspaceMarks","workspace":"01M5FY4RZM755X3GCF020J3Y5K"},"keyed":true},"w":1792610040150.411}
  #|{"out":{"id":10,"subscribe":{"topic":"status","workspace":"01M5FY4RZM755X3GCF020J3Y5K"},"keyed":true},"w":1792610040150.446}
  #|{"out":{"id":11,"subscribe":{"topic":"lockPrompts"},"keyed":true},"w":1792610040155.352}
  #|{"out":{"id":12,"call":"client.focus","params":{"visible":true,"focused":true,"workspace":"01M5FY4RZM755X3GCF020J3Y5K"}},"w":1792610040157.784}
  #|{"out":{"id":13,"subscribe":{"topic":"notify"},"keyed":true},"w":1792610040157.793}
  #|{"out":{"id":14,"subscribe":{"topic":"notify","workspace":"01M5FY4RZM755X3GCF020J3Y5K"},"keyed":true},"w":1792610040157.801}
  #|{"in":{"id":6,"value":{"available":true,"locked":false,"notice":true,"role":"owner","manages":true,"owner":true,"canSign":true,"signs":false,"me":{"device":"966060e8e5f92c860671d3f2e9e1b64d480603ad694799cb5914ee1c7d2784f4","code":"LEA-9CF","kind":"app","confirmed":false,"waiting":false,"asked":false},"signers":0,"members":[],"stations":[{"id":"83b1ac03cf03902875979b4beb59f41adb688c93c1fe68fdfc4a66caecb8a4b6","name":"studio","version":"0.1.0","online":true,"protected":false}],"protected":0,"requests":[],"renew":[],"attention":0}},"w":1792610040166.843}
  #|{"in":{"id":7,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"stations":[{"station":"01M5FY4RZM755X3GCF020J3Y5K/83b1ac03cf03902875979b4beb59f41adb688c93c1fe68fdfc4a66caecb8a4b6","id":"83b1ac03cf03902875979b4beb59f41adb688c93c1fe68fdfc4a66caecb8a4b6","name":"studio","state":"online"}],"loading":false,"days":[{"daysAgo":0,"at":1792610038701,"label":"今天","items":[{"id":"ember:c-4b34cd57b3","session":"ember:c-4b34cd57b3","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","agents":[{"key":"ember:c-4b34cd57b3","runtime":"claude","process":"warm","pending":0,"lastTurn":{"id":"ac4550f4-4f5e-40e2-afb6-464a8bc37c14","kind":"input","outcome":"completed","declared":"final","ending":"all_done","need":"answered the question that was asked","startedAt":1792610038631,"endedAt":1792610038703},"agentText":"默认模型","statusText":"已完成：answered the question that was asked"}],"last":{"seq":2,"authorKind":"agent","author":"ember:c-4b34cd57b3","text":"你好，我是测试用的 agent","createdAt":1792610038701,"by":{"kind":"agent","name":"agent","mine":false,"runtime":"claude","label":"agent"},"preview":"你好，我是测试用的 agent","time":{"createdAt":{"at":1792610038701,"ago":"刚刚","full":"10/22 03:13:58","until":"1 分钟内","past":true}}},"unread":true,"mine":true,"lastActiveAt":1792610038701,"station":"01M5FY4RZM755X3GCF020J3Y5K/83b1ac03cf03902875979b4beb59f41adb688c93c1fe68fdfc4a66caecb8a4b6","stationName":"studio","time":{"lastActiveAt":{"at":1792610038701,"ago":"刚刚","full":"10/22 03:13:58","until":"1 分钟内","past":true}},"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"peopleText":"你 发起","clientKey":"new:chat-d2c26cab114b11a3df","pinned":false,"tone":"done"}]}],"trouble":null,"members":1,"leading":"agents","glyph":{"online":1,"dim":0,"connecting":0,"failing":0,"working":0,"summary":"studio","label":"1 台 station，1 台在线"},"note":{"reading":false,"text":null,"failing":[],"empty":false}}},"w":1792610040166.92}
  #|{"in":{"id":8,"value":{"app":"desktop","tabs":[{"part":"desktop","label":"桌面","days":[]},{"part":"web","label":"网页","days":[]},{"part":"android","label":"安卓","days":[]},{"part":"station","label":"Station","days":[]},{"part":"cloud","label":"云端","days":[]}],"loading":false}},"w":1792610040166.943}
  #|{"in":{"id":9,"value":{"workspaces":{"01M5FY4RZM755X3GCF020J3Y5K":{"alert":0,"unread":1,"tone":"done","label":"1 个有新消息","badge":0,"items":[],"mineTone":"done"}},"badge":0,"badgeCounts":"attention","badgeKinds":{"on":true,"wait":true,"failed":true,"done":false,"message":false}}},"w":1792610040166.954}
  #|{"in":{"id":10,"value":{"items":[]}},"w":1792610040166.959}
  #|{"in":{"id":11,"value":{"pairing":[]}},"w":1792610040166.962}
  #|{"in":{"id":12,"ok":null},"w":1792610040166.964}
  #|{"in":{"id":13,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792610040166.97}
  #|{"in":{"id":14,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792610040166.974}
  #|{"out":{"id":15,"subscribe":{"topic":"longJobs","scope":"01M5FY4RZM755X3GCF020J3Y5K"},"keyed":true},"w":1792610040167.006}
  #|{"out":{"id":16,"call":"notify.permission","params":{"state":"unknown"}},"w":1792610040169.45}
  #|{"in":{"id":15,"value":{"groups":[]}},"w":1792610040183.488}
  #|{"in":{"id":16,"ok":null},"w":1792610040183.515}
  #|{"step":"answered notify.permission","w":1792610040183.805}
  #|{"step":"tap icon:settings","w":1792610040200.385}
  #|{"step":"tap icon:settings","acted":true,"w":1792610040200.396}
  #|{"out":{"id":17,"subscribe":{"topic":"workspace","workspace":"01M5FY4RZM755X3GCF020J3Y5K"},"keyed":true},"w":1792610040216.941}
  #|{"out":{"id":18,"subscribe":{"topic":"stations","scope":"01M5FY4RZM755X3GCF020J3Y5K"},"keyed":true},"w":1792610040216.952}
  #|{"out":{"id":19,"subscribe":{"topic":"connects","scope":"01M5FY4RZM755X3GCF020J3Y5K","mine":false},"keyed":true},"w":1792610040216.957}
  #|{"out":{"id":20,"subscribe":{"topic":"vaults","workspace":"01M5FY4RZM755X3GCF020J3Y5K"},"keyed":true},"w":1792610040216.963}
  #|{"out":{"id":21,"subscribe":{"topic":"doing"},"keyed":true},"w":1792610040219.604}
  #|{"out":{"id":22,"call":"cache.usage","params":{}},"w":1792610040220.457}
  #|{"step":"answered cache.usage","w":1792610040220.616}
  #|{"in":{"id":17,"value":{"id":"01M5FY4RZM755X3GCF020J3Y5K","name":"Dev","role":"owner","created_at":1792610034,"members":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":"https://example.test/p.png","role":"owner","added_at":1792610034}],"stations":[{"id":"83b1ac03cf03902875979b4beb59f41adb688c93c1fe68fdfc4a66caecb8a4b6","name":"studio","emoji":null,"icon":null,"enrolled_at":1792610035,"enrolled_by":"alice","last_seen":1792610038,"version":"0.1.0","time":{"last_seen":{"past":true,"at":1792610038000,"ago":"刚刚","full":"10/22 03:13:58","until":"1 分钟内"}}}],"invitations":[],"added":[],"relays":[],"lock":null,"lock_requests":0,"time":{"created_at":{"past":true,"at":1792610034000,"ago":"刚刚","full":"10/22 03:13:54","until":"1 分钟内"}}}},"w":1792610040233.462}
  #|{"in":{"id":18,"value":[{"station":"01M5FY4RZM755X3GCF020J3Y5K/83b1ac03cf03902875979b4beb59f41adb688c93c1fe68fdfc4a66caecb8a4b6","id":"83b1ac03cf03902875979b4beb59f41adb688c93c1fe68fdfc4a66caecb8a4b6","name":"studio","summary":"正在连接","face":"idle","line":"在线","online":true,"reconnecting":false,"lastSeen":1792610038,"version":"0.1.0","link":{"state":"online"},"runtimes":[{"runtime":"claude","models":["claude-sonnet-5-5"]}],"models":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792610038612,"time":{"checkedAt":{"at":1792610038612,"ago":"刚刚","full":"10/22 03:13:58","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"overview":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null,"summaryText":"最近 7 天检查了 0 个 chat","changeText":null}},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","email":"alice@example.test","name":"Name of alice","sub":"alice","role":"owner","workspace":"01M5FY4RZM755X3GCF020J3Y5K","device":"966060e8e5f92c860671d3f2e9e1b64d480603ad694799cb5914ee1c7d2784f4"},"connects":[],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792610038486,"time":{"checkedAt":{"at":1792610038486,"ago":"刚刚","full":"10/22 03:13:58","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792610038612,"time":{"checkedAt":{"at":1792610038612,"ago":"刚刚","full":"10/22 03:13:58","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"modelsReading":false,"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]}],"processes":[],"counts":{"sessions":1,"running":0,"warm":1},"mesh":{"state":"running","origin":"http://127.0.0.1:18787","station":"83b1ac03cf03902875979b4beb59f41adb688c93c1fe68fdfc4a66caecb8a4b6","workspace":"Dev","workspaceId":"01M5FY4RZM755X3GCF020J3Y5K","name":"studio"},"slackUsers":[],"slackTeams":[],"slackApps":[],"feishuRegistrations":[],"disk":{"freeBytes":28382961664,"totalBytes":245107195904},"logins":[],"machineLogins":[],"sharing":true,"consoleSignIn":true,"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"google","name":"Google Gemini","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xai","name":"xAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"mistral","name":"Mistral","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"deepseek","name":"DeepSeek","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen","name":"Qwen","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai","name":"Kimi","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"kimi-code","name":"Kimi Code","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai","name":"Z.ai","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax","name":"MiniMax","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ant-ling","name":"Ant Ling","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"jev","name":"Jev","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen-cn","name":"Qwen (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"openrouter","name":"OpenRouter","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"opencode","name":"OpenCode Zen","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"groq","name":"Groq","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"together","name":"Together AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"fireworks","name":"Fireworks","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cerebras","name":"Cerebras","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"huggingface","name":"Hugging Face","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"nvidia","name":"NVIDIA","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"baseten","name":"Baseten","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ollama","name":"Ollama","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"custom","name":"Custom","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""}],"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792610036233},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.306","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792610036233},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-icon/apps/e2e-local/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792610036233},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-icon/apps/e2e-local/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792610036233},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","latest":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-icon/apps/e2e-local/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792610036233},{"id":"cursor","name":"Cursor","installed":false,"latest":"1.0.40","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792610036233},{"id":"devin","name":"Devin","installed":true,"version":"3000.11.92","latest":"3000.11.92","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-icon/apps/e2e-local/ember/station/test/fake/devin，不是用 Devin 的安装脚本装的，需在该机器上手动更新","state":"idle","checkedAt":1792610036233}],"processesText":"没有运行中的 agent 进程","agentEnv":[],"drive":{"roots":[],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false}},"betaOffered":false,"way":{"path":"直连","via":"direct"},"time":{"lastSeen":{"at":1792610038000,"ago":"刚刚","full":"10/22 03:13:58","until":"1 分钟内","past":true}},"joined":false}]},"w":1792610040233.572}
  #|{"in":{"id":19,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"items":[],"wait":{"reading":false,"text":null,"failing":[],"empty":true}}},"w":1792610040233.645}
  #|{"in":{"id":20,"value":{"available":true,"locked":false,"canSign":false,"setUp":false,"vaults":[{"id":"plain","name":"个人","owner":"alice","ownerName":"Name of alice","mine":true,"members":[{"sub":"alice","name":"Name of alice"}],"station":"83b1ac03cf03902875979b4beb59f41adb688c93c1fe68fdfc4a66caecb8a4b6","stationName":"studio","items":0,"devices":0,"open":true,"keyed":true,"missing":0,"recoverable":false}],"requests":[],"refused":[{"station":"83b1ac03cf03902875979b4beb59f41adb688c93c1fe68fdfc4a66caecb8a4b6","name":"studio","code":"vault_needs_lock"}],"plain":true}},"w":1792610040233.653}
  #|{"in":{"id":21,"value":{"doing":[]}},"w":1792610040233.659}
  #|{"in":{"id":22,"ok":{"chats":[{"station":"01M5FY4RZM755X3GCF020J3Y5K/83b1ac03cf03902875979b4beb59f41adb688c93c1fe68fdfc4a66caecb8a4b6","thread":1,"title":null,"sessions":["ember:c-4b34cd57b3"],"bytes":558}]}},"w":1792610040233.663}
  #|{"step":"wait 299","w":1792610040250.613}
  #|{"in":{"id":18,"delta":[{"path":[0,"host"],"set":{"hostname":"3720-Mac-mini-1","os":"macOS 27.0.1","arch":"arm64","cpus":10,"cpuModel":"Apple M4","load":0.19,"cpuBusy":0.12,"uptimeSec":89402,"memory":{"totalBytes":17179869184,"usedBytes":10366189568,"swapUsedBytes":216793088},"disk":{"path":"/tmp/mbe2e-C/data","totalBytes":245107195904,"freeBytes":28382834688},"emberRssBytes":162004136,"checkedAt":1792610040256,"summary":"10 核 · 16 GB","line":"macOS 27.0.1 · 10 核 · 16 GB · 已运行 1 天","facts":["3720-Mac-mini-1","macOS 27.0.1","arm64 · 10 核","已运行 1 天 0 小时"],"meters":[{"label":"CPU","short":"CPU","percent":12,"left":88,"level":"ok","value":"12%","remaining":"空闲 88%","big":"88","unit":"%","title":"CPU 空闲","total":"负载 1.9","note":"负载 1.9 · Apple M4"},{"label":"内存","short":"内存","percent":60,"left":40,"level":"ok","value":"9.7 GB / 16.0 GB","remaining":"剩 6.3 G","big":"6.3","unit":"GB","title":"内存剩","total":"共 16 GB","note":"swap 0.2 GB"},{"label":"磁盘","short":"磁盘","percent":88,"left":12,"level":"amber","value":"剩余 26.4 GB / 228 GB","remaining":"剩 26.4 G","big":"26.4","unit":"GB","title":"磁盘剩","total":"共 228 GB"}],"identity":"Apple M4 · 16 GB · macOS 27.0.1","details":[{"label":"主机名","value":"3720-Mac-mini-1"},{"label":"芯片","value":"Apple M4 · 10 核 · arm64"},{"label":"已运行","value":"1 天 0 小时"},{"label":"still.fail","value":"进程占用 154 MB"}],"usage":"内存 9.7 GB / 16.0 GB · 磁盘 剩余 26.4 GB / 228 GB","emberText":"still.fail 154 MB"}},{"path":[0,"line"],"set":"Apple M4"},{"path":[0,"summary"],"set":"空闲 · Apple M4 · 16 GB · macOS 27.0.1"}]},"w":1792610040283.586}
  #|{"step":"now tap 密钥","w":1792610040551.17}
  #|{"step":"now tap 密钥","acted":true,"w":1792610040551.256}
  #|{"out":{"id":23,"subscribe":{"topic":"profiles","scope":"01M5FY4RZM755X3GCF020J3Y5K"},"keyed":true},"w":1792610040567.54}
  #|{"out":{"id":24,"subscribe":{"topic":"vaultItems","workspace":"01M5FY4RZM755X3GCF020J3Y5K","vault":"plain"},"keyed":true},"w":1792610040567.609}
  #|{"step":"wait 300","w":1792610040574.39}
  #|{"in":{"id":23,"value":{"items":[{"key":"01M5FY4RZM755X3GCF020J3Y5K/83b1ac03cf03902875979b4beb59f41adb688c93c1fe68fdfc4a66caecb8a4b6/cc","group":"key","groupTitle":"API Key","station":"01M5FY4RZM755X3GCF020J3Y5K/83b1ac03cf03902875979b4beb59f41adb688c93c1fe68fdfc4a66caecb8a4b6","stationId":"83b1ac03cf03902875979b4beb59f41adb688c93c1fe68fdfc4a66caecb8a4b6","stationName":"studio","profile":{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792610038486,"time":{"checkedAt":{"at":1792610038486,"ago":"刚刚","full":"10/22 03:13:58","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792610038612,"time":{"checkedAt":{"at":1792610038612,"ago":"刚刚","full":"10/22 03:13:58","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"modelsReading":false,"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]},"shared":false,"host":"83b1ac03cf03902875979b4beb59f41adb688c93c1fe68fdfc4a66caecb8a4b6","hostName":"studio","hostOnline":true,"usable":true,"where":"仅在 studio","stations":[{"id":"83b1ac03cf03902875979b4beb59f41adb688c93c1fe68fdfc4a66caecb8a4b6","station":"01M5FY4RZM755X3GCF020J3Y5K/83b1ac03cf03902875979b4beb59f41adb688c93c1fe68fdfc4a66caecb8a4b6","name":"studio","online":true,"allowed":true}],"editable":true,"canShare":true,"members":[{"station":"01M5FY4RZM755X3GCF020J3Y5K/83b1ac03cf03902875979b4beb59f41adb688c93c1fe68fdfc4a66caecb8a4b6","stationId":"83b1ac03cf03902875979b4beb59f41adb688c93c1fe68fdfc4a66caecb8a4b6","stationName":"studio","online":true,"profileId":"cc","role":"own","about":"此 station 自有的 key","usable":true,"checkText":"无法检查","checkTone":"neutral","usedBy":0}]}],"wait":{"reading":false,"text":null,"failing":[],"empty":false}}},"w":1792610040583.613}
  #|{"in":{"id":24,"value":{"vault":"plain","name":"个人","open":true,"items":[]}},"w":1792610040583.732}
  #|{"step":"now until 未加锁","w":1792610040884.24}
  #|{"step":"tap icon:plus","w":1792610040884.287}
  #|{"step":"tap icon:plus","acted":true,"w":1792610040884.318}
  #|{"step":"wait 1432","w":1792610040900.826}
  #|{"step":"now tap =Token","w":1792610042334.398}
  #|{"step":"now tap =Token","acted":true,"w":1792610042334.463}
  #|{"step":"until 添加密钥","w":1792610042351.306}
  #|{"step":"tap 例如 GitHub","w":1792610042378.142}
  #|{"step":"tap 例如 GitHub","acted":true,"w":1792610042378.179}
  #|{"step":"type e2e-080726","w":1792610042392.543}
  #|{"step":"type e2e-080726","acted":true,"w":1792610042392.58}
  #|{"step":"tap ghp_","w":1792610042402.673}
  #|{"step":"tap ghp_","acted":true,"w":1792610042402.71}
  #|{"step":"type ghp_madeup_080726_value","w":1792610042418.746}
  #|{"step":"type ghp_madeup_080726_value","acted":true,"w":1792610042418.789}
  #|{"step":"tap =允许 agent 申请","w":1792610042435.847}
  #|{"step":"tap =允许 agent 申请","acted":true,"w":1792610042435.892}
  #|{"step":"wheelat 300 限定域名","w":1792610042467.87}
  #|{"step":"wheelat 300 限定域名","acted":true,"w":1792610042467.908}
  #|{"step":"wait 900","w":1792610042476.225}
  #|{"step":"now tap api.github.com, uploads.github.com","w":1792610043384.852}
  #|{"step":"now tap api.github.com, uploads.github.com","acted":true,"w":1792610043384.916}
  #|{"step":"type api.example.test","w":1792610043401.825}
  #|{"step":"type api.example.test","acted":true,"w":1792610043401.862}
  #|{"step":"tap =保存","w":1792610043419.272}
  #|{"step":"tap =保存","acted":true,"w":1792610043419.323}
  #|{"out":{"id":25,"call":"vault.putItem","params":{"workspace":"01M5FY4RZM755X3GCF020J3Y5K","vault":"plain","plain":{"kind":"token","name":"e2e-080726","fields":{"value":"ghp_madeup_080726_value"},"domains":[],"notes":""},"listing":{"name":"e2e-080726","kind":"token","modes":["proxy"],"hosts":["api.example.test"]}}},"w":1792610043433.782}
  #|{"step":"answered vault.putItem","w":1792610043435.706}
  #|{"in":{"id":25,"ok":{"id":"i_01M5FY51HAKAM709PVFK1F6WE2","version":0}},"w":1792610043450.187}
  #|{"step":"wait 1464","w":1792610043467.865}
  #|{"in":{"id":20,"delta":[{"path":["vaults"],"key":["id"],"patch":"plain","ops":[{"path":["items"],"set":1}]}]},"w":1792610043650.229}
  #|{"in":{"id":24,"delta":[{"path":["items"],"key":["id"],"put":{"id":"i_01M5FY51HAKAM709PVFK1F6WE2","version":0,"at":1792610043,"name":"e2e-080726","kind":"token","listed":true,"modes":["proxy"],"hosts":["api.example.test"]},"before":null}]},"w":1792610043650.319}
  #|{"step":"now until =e2e-080726","w":1792610044951.001}
  #|{"step":"tap =e2e-080726","w":1792610044951.061}
  #|{"step":"tap =e2e-080726","acted":true,"w":1792610044951.094}
  #|{"out":{"id":26,"subscribe":{"topic":"vaultUses","workspace":"01M5FY4RZM755X3GCF020J3Y5K","vault":"plain","item":"i_01M5FY51HAKAM709PVFK1F6WE2"},"keyed":true},"w":1792610044967.207}
  #|{"step":"wait 300","w":1792610044993.307}
  #|{"in":{"id":26,"value":{"item":"i_01M5FY51HAKAM709PVFK1F6WE2","uses":[]}},"w":1792610044993.481}
  #|{"step":"now tap =显示","w":1792610045304.718}
  #|{"step":"now tap =显示","acted":true,"w":1792610045304.794}
  #|{"out":{"id":27,"call":"vault.open","params":{"workspace":"01M5FY4RZM755X3GCF020J3Y5K","item":"i_01M5FY51HAKAM709PVFK1F6WE2"}},"w":1792610045321.079}
  #|{"step":"answered vault.open","w":1792610045321.581}
  #|{"in":{"id":27,"ok":{"vault":"plain","id":"i_01M5FY51HAKAM709PVFK1F6WE2","version":0,"plain":{"kind":"token","name":"e2e-080726","fields":{"value":"ghp_madeup_080726_value"},"domains":[],"notes":""}}},"w":1792610045337.286}
  #|{"step":"tap icon:edit","w":1792610045354.653}
  #|{"step":"tap icon:edit","acted":true,"w":1792610045354.692}
  #|{"step":"wait 1464","w":1792610045377.618}
  #|{"step":"now until 限定域名","w":1792610046872.087}
  #|{"step":"tap =删除","w":1792610046872.165}
  #|{"step":"tap =删除","acted":true,"w":1792610046872.209}
  #|{"step":"wait 1433","w":1792610046889.033}
  #|{"step":"now until 删除「e2e-080726」","w":1792610048338.038}
  #|{"step":"tap =删除","w":1792610048338.117}
  #|{"step":"tap =删除","acted":true,"w":1792610048338.176}
  #|{"out":{"id":28,"call":"vault.deleteItem","params":{"workspace":"01M5FY4RZM755X3GCF020J3Y5K","vault":"plain","item":"i_01M5FY51HAKAM709PVFK1F6WE2"}},"w":1792610048354.372}
  #|{"step":"answered vault.deleteItem","w":1792610048355.416}
  #|{"in":{"id":28,"ok":{"id":"i_01M5FY51HAKAM709PVFK1F6WE2","version":1}},"w":1792610048370.614}
  #|{"step":"wait 300","w":1792610048388.786}
  #|{"in":{"id":20,"delta":[{"path":["vaults"],"key":["id"],"patch":"plain","ops":[{"path":["items"],"set":0}]}]},"w":1792610048437.278}
  #|{"in":{"id":24,"delta":[{"path":["items"],"key":["id"],"drop":"i_01M5FY51HAKAM709PVFK1F6WE2"}]},"w":1792610048437.349}
  #|{"step":"now gone =e2e-080726","w":1792610048704.756}
  #|{"step":"wait 1106","w":1792610048704.807}
  #|{"step":"","w":1792610049821.381}
  #|{"textrec":{"m":[15,400,0],"r":[14.501953125,3.1640625,21,14.501953125,3.1640625,0]}}
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
  #|{"textrec":{"ib":["d61ec6305f7d8c8b",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["182b7158e0c0cae1",866,64],"r":[14,14,14,14]}}
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
  #|{"textrec":{"s":[14,400,0,"0 个"],"r":[0,1,8.66796875,184,1,1,3.787109375,-1,2,1,13.891050583657588,191]}}
  #|{"textrec":{"s":[14,400,0,"1 个"],"r":[0,1,6.34375,182,1,1,3.787109375,-1,2,1,13.891050583657588,191]}}
  #|{"textrec":{"s":[14,400,0,"558 B"],"r":[0,1,8.50390625,192,1,1,8.50390625,192,2,1,8.791015625,193,3,1,3.787109375,-1,4,1,9.05078125,194]}}
  #|{"textrec":{"ib":["504a4df6beac534a",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["a1e7be43eb966606",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"g":63,"r":[666,0,18,18,-1,-15,0]}}
  #|{"textrec":{"g":64,"r":[685,0,19,18,-1,-15,0]}}
  #|{"textrec":{"g":65,"r":[705,0,31,31,0,-26,0]}}
  #|{"textrec":{"g":66,"r":[737,0,30,29,0,-25,0]}}
  #|{"textrec":{"g":84,"r":[768,0,12,13,0,-12,0]}}
  #|{"textrec":{"g":85,"r":[781,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":86,"r":[793,0,11,11,-1,-10,0]}}
  #|{"textrec":{"g":175,"r":[805,0,5,5,1,-8,0]}}
  #|{"textrec":{"g":176,"r":[811,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":177,"r":[828,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":178,"r":[845,0,13,14,-1,-12,0]}}
  #|{"textrec":{"g":179,"r":[859,0,14,11,-1,-10,0]}}
  #|{"textrec":{"g":180,"r":[874,0,10,11,0,-10,0]}}
  #|{"textrec":{"g":181,"r":[885,0,7,11,0,-10,0]}}
  #|{"textrec":{"g":87,"r":[893,0,16,13,-1,-12,0]}}
  #|{"textrec":{"g":88,"r":[910,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":89,"r":[922,0,7,11,0,-10,0]}}
  #|{"textrec":{"g":90,"r":[930,0,9,14,0,-13,0]}}
  #|{"textrec":{"g":91,"r":[940,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":92,"r":[951,0,10,14,0,-10,0]}}
  #|{"textrec":{"g":93,"r":[962,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":94,"r":[973,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":95,"r":[984,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":99,"r":[995,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":186,"r":[1012,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":187,"r":[1029,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":100,"r":[1046,0,11,14,-1,-12,0]}}
  #|{"textrec":{"g":101,"r":[1058,0,7,13,-1,-11,0]}}
  #|{"textrec":{"g":102,"r":[1066,0,5,14,-1,-13,0]}}
  #|{"textrec":{"g":103,"r":[1072,0,9,11,0,-10,0]}}
  #|{"textrec":{"g":104,"r":[1082,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":105,"r":[1099,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":106,"r":[1116,0,10,13,0,-12,0]}}
  #|{"textrec":{"g":107,"r":[1127,0,7,14,-1,-13,0]}}
  #|{"textrec":{"g":108,"r":[1135,0,4,14,0,-13,0]}}
  #|{"textrec":{"g":109,"r":[1140,0,13,16,1,-13,0]}}
  #|{"textrec":{"g":110,"r":[1154,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":111,"r":[1171,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":112,"r":[1189,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":113,"r":[1206,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":114,"r":[1224,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":115,"r":[1241,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":116,"r":[1257,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":117,"r":[1274,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":118,"r":[1292,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":119,"r":[1310,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":124,"r":[1328,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":125,"r":[1346,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":128,"r":[1364,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":129,"r":[1381,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":130,"r":[1398,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":131,"r":[1415,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":132,"r":[1433,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":133,"r":[1451,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":134,"r":[1469,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":83,"r":[1486,0,17,19,0,-18,0]}}
  #|{"textrec":{"g":67,"r":[1504,0,12,14,0,-13,0]}}
  #|{"textrec":{"g":68,"r":[1517,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":69,"r":[1529,0,15,11,0,-10,0]}}
  #|{"textrec":{"g":70,"r":[1545,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":71,"r":[1557,0,12,12,-1,-10,0]}}
  #|{"textrec":{"g":72,"r":[1570,0,8,14,-1,-13,0]}}
  #|{"textrec":{"g":73,"r":[1579,0,5,14,0,-13,0]}}
  #|{"textrec":{"g":74,"r":[1585,0,5,15,0,-14,0]}}
  #|{"textrec":{"g":75,"r":[1591,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":12,"r":[1603,0,9,10,-1,-8,0]}}
  #|{"textrec":{"g":76,"r":[1613,0,4,12,0,-11,0]}}
  #|{"textrec":{"g":77,"r":[1618,0,5,12,-1,-11,0]}}
  #|{"textrec":{"g":13,"r":[1624,0,9,10,-1,-8,0]}}
  #|{"textrec":{"g":14,"r":[1634,0,9,10,-1,-8,0]}}
  #|{"textrec":{"g":78,"r":[1644,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":79,"r":[1659,0,9,9,-1,-8,0]}}
  #|{"textrec":{"g":80,"r":[1669,0,12,9,0,-8,0]}}
  #|{"textrec":{"g":11,"r":[1682,0,9,12,0,-8,0]}}
  #|{"textrec":{"g":81,"r":[1692,0,4,5,0,-3,0]}}
  #|{"textrec":{"g":82,"r":[1697,0,7,12,-1,-10,0]}}
  #|{"textrec":{"g":10,"r":[1705,0,9,10,-1,-8,0]}}
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
  #|{"textrec":{"g":192,"r":[1878,0,9,13,0,-11,0]}}
  #|{"textrec":{"g":193,"r":[1888,0,11,14,-1,-12,0]}}
  #|{"textrec":{"g":194,"r":[1900,0,10,12,0,-11,0]}}
  #|{"textrec":{"g":183,"r":[1911,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":184,"r":[1928,0,10,14,-1,-12,0]}}
  #|{"textrec":{"g":185,"r":[1939,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":191,"r":[1956,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":126,"r":[1973,0,9,13,0,-12,0]}}
  #|{"textrec":{"g":127,"r":[1983,0,16,16,-1,-13,0]}}
  #|{"textrec":{"ib":["b3685975cd23abc3",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"s":[17,400,0,"设置"],"r":[0,1,16.851167315175097,195,1,1,16.851167315175097,196]}}
  #|{"textrec":{"s":[32,700,8,"密钥"],"r":[0,1,30.345864661654133,197,1,1,30.345864661654133,198]}}
  #|{"textrec":{"s":[15,400,0,"开启安全模式"],"r":[0,1,14.883268482490273,199,1,1,14.883268482490273,200,2,1,14.883268482490273,99,3,1,14.883268482490273,20,4,1,14.88326848249028,201,5,1,14.88326848249028,202]}}
  #|{"textrec":{"s":[15,400,0,"未加锁"],"r":[0,1,14.883268482490273,203,1,1,14.883268482490273,204,2,1,14.883268482490273,205]}}
  #|{"textrec":{"s":[13,400,0,"以明文保存在 station 上"],"r":[0,1,12.898832684824903,206,1,1,12.898832684824903,207,2,1,12.898832684824903,208,3,1,12.898832684824903,209,4,1,12.898832684824896,210,5,1,12.898832684824896,1,6,1,3.580078125,-1,7,1,6.69677734375,10,8,1,4.61474609375,82,9,1,7.0966796875,12,10,1,4.646484375,82,11,1,3.1357421875,77,12,1,7.6044921875,7,13,1,7.50927734375,211,14,1,3.580078125,-1,15,1,12.898832684824896,212]}}
  #|{"textrec":{"s":[13,400,0,"studio 未加入安全模式，无法存放密钥库"],"r":[0,1,6.69677734375,10,1,1,4.61474609375,82,2,1,7.50927734375,213,3,1,7.9091796875,214,4,1,3.1357421875,77,5,1,7.6044921875,7,6,1,3.580078125,-1,7,1,12.898832684824903,215,8,1,12.898832684824903,216,9,1,12.89883268482491,217,10,1,12.898832684824896,218,11,1,12.898832684824896,219,12,1,12.898832684824896,220,13,1,12.898832684824896,221,14,1,13.075875486381335,222,15,1,12.898832684824896,223,16,1,12.898832684824896,224,17,1,12.898832684824896,210,18,1,12.898832684824896,225,19,1,12.898832684824896,226,20,1,12.898832684824896,227,21,1,12.898832684824896,228]}}
  #|{"textrec":{"s":[15,600,0,"API Key"],"r":[0,1,10.429658889770508,229,1,1,9.65855062007904,230,2,1,4.261693954467773,231,3,1,3.761730194091797,-1,4,1,9.82150912284851,232,5,1,8.214586973190308,85,6,1,8.328588008880615,233]}}
  #|{"textrec":{"s":[15,400,0,"cc"],"r":[0,1,8.1591796875,94,1,1,8.1591796875,94]}}
  #|{"textrec":{"s":[13,400,0,"Profile · 仅在 studio"],"r":[0,1,8.18212890625,234,1,1,4.77978515625,8,2,1,7.50927734375,7,3,1,4.62744140625,235,4,1,3.1357421875,77,5,1,3.2119140625,76,6,1,7.3505859375,14,7,1,3.580078125,-1,8,1,6.228545204222122,236,9,1,3.580078125,-1,10,1,12.898832684824903,237,11,1,12.89883268482491,1,12,1,3.580078125,-1,13,1,6.69677734375,10,14,1,4.61474609375,82,15,1,7.50927734375,213,16,1,7.9091796875,214,17,1,3.1357421875,77,18,1,7.6044921875,7]}}
  #|{"textrec":{"g":195,"r":[2000,0,19,18,-1,-15,0]}}
  #|{"textrec":{"g":196,"r":[2020,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":197,"r":[0,32,30,32,0,-27,0]}}
  #|{"textrec":{"g":198,"r":[31,32,31,31,-1,-26,0]}}
  #|{"textrec":{"g":229,"r":[63,32,13,13,-1,-12,0]}}
  #|{"textrec":{"g":230,"r":[77,32,11,13,0,-12,0]}}
  #|{"textrec":{"g":231,"r":[89,32,5,13,0,-12,0]}}
  #|{"textrec":{"g":232,"r":[95,32,11,13,0,-12,0]}}
  #|{"textrec":{"g":233,"r":[107,32,11,14,-1,-10,0]}}
  #|{"textrec":{"g":213,"r":[119,32,9,10,-1,-8,0]}}
  #|{"textrec":{"g":214,"r":[129,32,9,13,-1,-11,0]}}
  #|{"textrec":{"g":7,"r":[139,32,9,10,-1,-8,0]}}
  #|{"textrec":{"g":215,"r":[149,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":216,"r":[165,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":217,"r":[180,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":218,"r":[196,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":219,"r":[211,32,15,14,-1,-12,0]}}
  #|{"textrec":{"g":220,"r":[227,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":221,"r":[243,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":222,"r":[259,32,5,7,0,-3,0]}}
  #|{"textrec":{"g":223,"r":[265,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":224,"r":[280,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":210,"r":[296,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":225,"r":[312,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":226,"r":[328,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":227,"r":[343,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":228,"r":[358,32,15,15,-1,-12,0]}}
  #|{"textrec":{"ib":["46d0db0d8467a80d",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"ib":["7e9322e1e57d8f14",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"g":203,"r":[374,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":204,"r":[391,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":205,"r":[408,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":206,"r":[426,32,14,15,0,-12,0]}}
  #|{"textrec":{"g":207,"r":[441,32,13,14,0,-11,0]}}
  #|{"textrec":{"g":208,"r":[455,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":209,"r":[471,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":1,"r":[487,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":211,"r":[502,32,8,9,0,-8,0]}}
  #|{"textrec":{"g":212,"r":[511,32,14,14,-1,-12,0]}}
  #|{"textrec":{"g":234,"r":[526,32,9,12,0,-11,0]}}
  #|{"textrec":{"g":8,"r":[536,32,6,9,0,-8,0]}}
  #|{"textrec":{"g":235,"r":[543,32,7,12,-1,-11,0]}}
  #|{"textrec":{"g":236,"r":[551,32,4,5,1,-7,0]}}
  #|{"textrec":{"g":237,"r":[556,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":199,"r":[572,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":200,"r":[589,32,15,17,-1,-14,0]}}
  #|{"textrec":{"g":201,"r":[605,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":202,"r":[623,32,16,16,-1,-13,0]}}
  #|{"textrec":{"ib":["c7a6d30e254a5910",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"s":[17,700,0,"添加"],"r":[0,1,16.851167315175097,238,1,1,16.851167315175097,239]}}
  #|{"textrec":{"m":[17,700,0],"r":[16.435546875,3.5859375,24,16.435546875,3.5859375,0]}}
  #|{"textrec":{"s":[15,400,0,"订阅或模型 API Key"],"r":[0,1,14.883268482490273,240,1,1,14.883268482490273,241,2,1,14.883268482490273,242,3,1,14.883268482490273,201,4,1,14.88326848249028,243,5,1,3.984375,-1,6,1,9.873046875,244,7,1,9.29443359375,106,8,1,3.779296875,245,9,1,3.984375,-1,10,1,9.35302734375,246,11,1,7.96875,95,12,1,7.8369140625,247]}}
  #|{"textrec":{"s":[13,400,0,"供 agent 运行模型"],"r":[0,1,12.898832684824903,248,1,1,3.580078125,-1,2,1,7.0966796875,12,3,1,7.845703125,249,4,1,7.3505859375,14,5,1,7.50927734375,211,6,1,4.646484375,82,7,1,3.580078125,-1,8,1,12.898832684824903,250,9,1,12.89883268482491,251,10,1,12.898832684824896,220,11,1,12.898832684824896,252]}}
  #|{"textrec":{"s":[15,400,0,"Token"],"r":[0,1,8.5400390625,253,1,1,7.8955078125,88,2,1,7.72705078125,90,3,1,8.15185546875,95,4,1,8.51806640625,103]}}
  #|{"textrec":{"s":[13,400,0,"GitHub、Cloudflare 等服务的 API token"],"r":[0,1,9.62939453125,254,1,1,3.1357421875,77,2,1,4.646484375,82,3,1,9.572265625,255,4,1,7.50927734375,213,5,1,7.9091796875,256,6,1,11.775875486381324,141,7,1,9.2294921875,257,8,1,3.2119140625,76,9,1,7.6044921875,7,10,1,7.50927734375,213,11,1,7.9091796875,214,12,1,4.62744140625,235,13,1,3.2119140625,76,14,1,7.0966796875,12,15,1,4.77978515625,8,16,1,7.25537109375,14,17,1,3.580078125,-1,18,1,12.898832684824896,258,19,1,12.898832684824896,259,20,1,12.898832684824896,138,21,1,12.898832684824896,5,22,1,3.580078125,-1,23,1,8.68359375,260,24,1,8.18212890625,234,25,1,3.40234375,261,26,1,3.580078125,-1,27,1,4.598876953125,82,28,1,7.556884765625,7,29,1,6.82373046875,9,30,1,7.19189453125,14,31,1,7.50927734375,211]}}
  #|{"textrec":{"s":[15,400,0,"SSH 密钥"],"r":[0,1,9.32373046875,100,1,1,9.32373046875,100,2,1,10.8984375,262,3,1,3.984375,-1,4,1,14.883268482490273,186,5,1,14.883268482490273,187]}}
  #|{"textrec":{"s":[13,400,0,"推送代码、登录服务器"],"r":[0,1,12.898832684824903,263,1,1,12.898832684824903,264,2,1,12.898832684824903,265,3,1,12.898832684824903,266,4,1,13.075875486381321,141,5,1,12.89883268482491,267,6,1,12.898832684824896,268,7,1,12.898832684824896,259,8,1,12.898832684824896,138,9,1,12.898832684824896,269]}}
  #|{"textrec":{"s":[15,400,0,"登录"],"r":[0,1,14.883268482490273,270,1,1,14.883268482490273,271]}}
  #|{"textrec":{"s":[13,400,0,"网站的用户名和密码"],"r":[0,1,12.898832684824903,272,1,1,12.898832684824903,273,2,1,12.898832684824903,5,3,1,12.898832684824903,274,4,1,12.898832684824896,275,5,1,12.898832684824896,276,6,1,12.898832684824896,277,7,1,12.898832684824896,226,8,1,12.898832684824896,266]}}
  #|{"textrec":{"s":[13,400,0,"未开启安全模式时，此类密钥以明文保存在 station 上，agent 可绕过批准直接读取"],"r":[0,1,12.898832684824903,215,1,1,12.898832684824903,278,2,1,12.898832684824903,279,3,1,12.898832684824903,218,4,1,12.898832684824896,219,5,1,12.898832684824896,220,6,1,12.898832684824896,221,7,1,12.898832684824896,153,8,1,13.075875486381321,222,9,1,12.89883268482491,280,10,1,12.898832684824896,281,11,1,12.898832684824896,226,12,1,12.898832684824896,227,13,1,12.898832684824896,206,14,1,12.898832684824896,207,15,1,12.898832684824896,208,16,1,12.898832684824896,209,17,1,12.898832684824896,210,18,1,12.898832684824896,1,19,1,3.580078125,-1,20,1,6.69677734375,10,21,1,4.614746093749972,82,22,1,7.0966796875,12,23,1,4.646484375,82,24,1,3.1357421875,77,25,1,7.6044921875,7,26,1,7.50927734375,211,27,1,3.580078125,-1,28,1,12.898832684824924,212,29,1,11.775875486381324,222,30,1,7.0966796875,12,31,1,7.845703125,249,32,1,7.3505859375,14,33,1,7.50927734375,211,34,1,4.646484375,82,35,1,3.580078125,-1,36,1,12.898832684824924,282,37,1,12.898832684824924,283,38,1,12.898832684824924,284,39,1,12.898832684824924,285,40,1,12.898832684824924,286,41,1,12.898832684824924,287,42,1,12.898832684824924,288,43,1,12.898832684824924,2,44,1,12.898832684824924,3]}}
  #|{"textrec":{"g":238,"r":[640,32,19,18,-1,-15,0]}}
  #|{"textrec":{"g":239,"r":[660,32,18,18,-1,-15,0]}}
  #|{"textrec":{"g":240,"r":[679,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":241,"r":[697,32,15,17,0,-14,0]}}
  #|{"textrec":{"g":242,"r":[713,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":243,"r":[730,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":244,"r":[747,32,12,13,-1,-12,0]}}
  #|{"textrec":{"g":245,"r":[760,32,4,13,0,-12,0]}}
  #|{"textrec":{"g":246,"r":[765,32,11,13,0,-12,0]}}
  #|{"textrec":{"g":247,"r":[777,32,10,13,-1,-9,0]}}
  #|{"textrec":{"g":248,"r":[788,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":249,"r":[804,32,9,12,-1,-8,0]}}
  #|{"textrec":{"g":250,"r":[814,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":251,"r":[830,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":252,"r":[846,32,14,14,-1,-12,0]}}
  #|{"textrec":{"g":253,"r":[861,32,11,13,-1,-12,0]}}
  #|{"textrec":{"g":254,"r":[873,32,11,13,-1,-11,0]}}
  #|{"textrec":{"g":255,"r":[885,32,10,12,0,-11,0]}}
  #|{"textrec":{"g":256,"r":[896,32,9,13,0,-11,0]}}
  #|{"textrec":{"g":141,"r":[906,32,6,6,0,-3,0]}}
  #|{"textrec":{"g":257,"r":[913,32,11,13,-1,-11,0]}}
  #|{"textrec":{"g":258,"r":[925,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":259,"r":[940,32,15,14,-1,-11,0]}}
  #|{"textrec":{"g":138,"r":[956,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":5,"r":[972,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":260,"r":[986,32,11,12,-1,-11,0]}}
  #|{"textrec":{"g":261,"r":[998,32,4,12,0,-11,0]}}
  #|{"textrec":{"g":9,"r":[1003,32,8,12,0,-11,0]}}
  #|{"textrec":{"g":262,"r":[1012,32,11,13,0,-12,0]}}
  #|{"textrec":{"g":263,"r":[1024,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":264,"r":[1039,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":265,"r":[1055,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":266,"r":[1071,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":267,"r":[1086,32,15,14,-1,-12,0]}}
  #|{"textrec":{"g":268,"r":[1102,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":269,"r":[1117,32,15,14,-1,-11,0]}}
  #|{"textrec":{"g":270,"r":[1133,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":271,"r":[1151,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":272,"r":[1168,32,13,14,0,-11,0]}}
  #|{"textrec":{"g":273,"r":[1182,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":274,"r":[1198,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":275,"r":[1213,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":276,"r":[1228,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":277,"r":[1243,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":278,"r":[1258,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":279,"r":[1273,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":153,"r":[1288,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":280,"r":[1304,32,15,14,-1,-12,0]}}
  #|{"textrec":{"g":281,"r":[1320,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":282,"r":[1336,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":283,"r":[1351,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":284,"r":[1367,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":285,"r":[1383,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":286,"r":[1398,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":287,"r":[1414,32,14,14,-1,-12,0]}}
  #|{"textrec":{"g":288,"r":[1429,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":2,"r":[1445,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":3,"r":[1461,32,15,14,-1,-11,0]}}
  #|{"textrec":{"ib":["5ae5cd42ddaa84d8",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"ib":["1f0afe4af62fcd94",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"ib":["2834b04de0fd6a28",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"ib":["4e9816fd8acef556",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"s":[14,600,0,"保存"],"r":[0,1,13.891050583657588,289,1,1,13.891050583657588,290]}}
  #|{"textrec":{"m":[14,600,0],"r":[13.53515625,2.953125,20,13.53515625,2.953125,0]}}
  #|{"textrec":{"s":[17,700,0,"添加密钥"],"r":[0,1,16.851167315175097,238,1,1,16.851167315175097,239,2,1,16.851167315175097,291,3,1,16.851167315175097,292]}}
  #|{"textrec":{"s":[13,400,0,"名称"],"r":[0,1,12.898832684824903,276,1,1,12.898832684824903,293]}}
  #|{"textrec":{"s":[13,400,0,"值"],"r":[0,1,12.898832684824903,294]}}
  #|{"textrec":{"s":[15,400,0,"允许 agent 申请"],"r":[0,1,14.883268482490273,295,1,1,14.883268482490273,296,2,1,3.984375,-1,3,1,8.0419921875,93,4,1,8.90625,297,5,1,8.3349609375,95,6,1,8.51806640625,103,7,1,5.21484375,101,8,1,3.984375,-1,9,1,14.883268482490266,298,10,1,14.88326848249028,299]}}
  #|{"textrec":{"s":[13,400,0,"每次使用需经你批准"],"r":[0,1,12.898832684824903,300,1,1,12.898832684824903,301,2,1,12.898832684824903,302,3,1,12.898832684824903,274,4,1,12.898832684824896,142,5,1,12.898832684824896,303,6,1,12.898832684824896,4,7,1,12.898832684824896,285,8,1,12.898832684824896,286]}}
  #|{"textrec":{"g":291,"r":[1477,32,18,18,-1,-15,0]}}
  #|{"textrec":{"g":292,"r":[1496,32,18,18,-1,-15,0]}}
  #|{"textrec":{"g":289,"r":[1515,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":290,"r":[1532,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":293,"r":[1549,32,15,15,-1,-12,0]}}
  #|{"textrec":{"s":[15,400,0,"例如 GitHub token"],"r":[0,1,14.883268482490273,304,1,1,14.883268482490273,305,2,1,3.984375,-1,3,1,10.96435546875,306,4,1,3.4716796875,102,5,1,5.21484375,101,6,1,10.8984375,262,7,1,8.51806640625,163,8,1,8.9794921875,162,9,1,3.984375,-1,10,1,5.159912109375,101,11,1,8.572998046875,88,12,1,7.72705078125,90,13,1,8.15185546875,95,14,1,8.51806640625,103]}}
  #|{"textrec":{"g":304,"r":[1565,32,16,17,-1,-14,0]}}
  #|{"textrec":{"g":305,"r":[1582,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":306,"r":[1599,32,13,14,-1,-12,0]}}
  #|{"textrec":{"g":163,"r":[1613,32,9,11,0,-9,0]}}
  #|{"textrec":{"g":162,"r":[1623,32,10,15,0,-13,0]}}
  #|{"textrec":{"g":294,"r":[1634,32,15,15,-1,-12,0]}}
  #|{"textrec":{"s":[15,400,0,"ghp_…"],"r":[0,1,8.90625,297,1,1,8.59130859375,307,2,1,8.701171875,92,3,1,8.29833984375,308,4,1,11.8359375,309]}}
  #|{"textrec":{"g":297,"r":[1650,32,10,14,-1,-10,0]}}
  #|{"textrec":{"g":307,"r":[1661,32,9,14,0,-13,0]}}
  #|{"textrec":{"g":308,"r":[1671,32,11,4,-1,-1,0]}}
  #|{"textrec":{"g":309,"r":[1683,32,12,5,0,-3,0]}}
  #|{"textrec":{"g":295,"r":[1696,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":296,"r":[1713,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":298,"r":[1731,32,13,16,1,-13,0]}}
  #|{"textrec":{"g":299,"r":[1745,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":300,"r":[1762,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":301,"r":[1778,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":302,"r":[1794,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":142,"r":[1810,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":303,"r":[1825,32,15,14,-1,-12,0]}}
  #|{"textrec":{"g":4,"r":[1841,32,14,15,-1,-12,0]}}
  #|{"textrec":{"ib":["899ec1ee57bf0709",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"s":[15,400,0,"e2e-080726"],"r":[0,1,8.3349609375,95,1,1,8.78173828125,310,2,1,8.29833984375,95,3,1,6.8408203125,311,4,1,9.2138671875,164,5,1,9.345703125,312,6,1,9.0673828125,164,7,1,8.1591796875,313,8,1,8.818359375,310,9,1,9.31640625,314]}}
  #|{"textrec":{"g":310,"r":[1856,32,10,13,0,-12,0]}}
  #|{"textrec":{"g":311,"r":[1867,32,7,4,0,-6,0]}}
  #|{"textrec":{"g":164,"r":[1875,32,11,14,-1,-12,0]}}
  #|{"textrec":{"g":312,"r":[1887,32,11,14,-1,-12,0]}}
  #|{"textrec":{"g":313,"r":[1899,32,10,13,-1,-12,0]}}
  #|{"textrec":{"g":314,"r":[1910,32,11,14,-1,-12,0]}}
  #|{"textrec":{"s":[15,400,0,"•••••••••••••••••••••••"],"r":[0,1,6.8408203125,315,1,1,6.8408203125,315,2,1,6.8408203125,315,3,1,6.8408203125,315,4,1,6.8408203125,315,5,1,6.8408203125,315,6,1,6.8408203125,315,7,1,6.8408203125,315,8,1,6.8408203125,315,9,1,6.8408203125,315,10,1,6.8408203125,315,11,1,6.8408203125,315,12,1,6.8408203125,315,13,1,6.8408203125,315,14,1,6.8408203125,315,15,1,6.8408203125,315,16,1,6.8408203125,315,17,1,6.8408203125,315,18,1,6.8408203125,315,19,1,6.8408203125,315,20,1,6.8408203125,315,21,1,6.8408203125,315,22,1,6.8408203125,315]}}
  #|{"textrec":{"g":315,"r":[1922,32,6,6,1,-7,0]}}
  #|{"textrec":{"s":[13,400,0,"提供方式"],"r":[0,1,12.898832684824903,316,1,1,12.898832684824903,248,2,1,12.898832684824903,317,3,1,12.898832684824903,221]}}
  #|{"textrec":{"s":[12,400,0,"代理：agent 仅获得占位符，请求发往限定域名时替换为真实值。环境变量：命令可读取明文，有泄露给 agent 的风险"],"r":[0,1,11.918287937743191,318,1,1,11.918287937743191,319,2,1,12.081712062256805,320,3,1,6.62109375,321,4,1,7.3125,322,5,1,6.85546875,323,6,1,7.001953125,324,7,1,4.359375,325,8,1,3.375,-1,9,1,11.918287937743187,326,10,1,11.918287937743187,327,11,1,11.918287937743187,328,12,1,11.918287937743187,329,13,1,11.918287937743187,330,14,1,11.918287937743202,331,15,1,12.081712062256798,332,16,1,11.918287937743202,333,17,1,11.918287937743202,334,18,1,11.918287937743202,335,19,1,11.918287937743202,336,20,1,11.918287937743202,337,21,1,11.918287937743202,338,22,1,11.918287937743202,339,23,1,11.918287937743202,340,24,1,11.918287937743202,341,25,1,11.918287937743173,342,26,1,11.918287937743173,343,27,1,11.918287937743173,344,28,1,11.918287937743173,345,29,1,11.918287937743173,346,30,1,11.918287937743173,347,31,1,12.081712062256827,348,32,1,11.918287937743173,349,33,1,11.918287937743173,350,34,1,11.918287937743173,351,35,1,11.918287937743173,352,36,1,12.081712062256827,320,37,1,11.918287937743173,353,38,1,11.918287937743173,354,39,1,11.918287937743173,355,40,1,11.918287937743173,356,41,1,11.918287937743173,357,42,1,11.918287937743173,358,43,1,11.918287937743173,359,44,1,12.081712062256827,332,45,1,11.918287937743173,360,46,1,11.91828793774323,361,47,1,11.91828793774323,362,48,1,11.91828793774323,363,49,1,3.375,-1,50,1,6.62109375,321,51,1,7.3125,322,52,1,6.85546875,323,53,1,7.001953125,324,54,1,4.359375,325,55,1,3.375,-1,56,1,11.91828793774323,364,57,1,11.91828793774323,365,58,1,11.91828793774323,366]}}
  #|{"textrec":{"m":[12,400,0],"r":[11.6015625,2.53125,17,11.6015625,2.53125,0]}}
  #|{"textrec":{"s":[13,400,0,"限定域名"],"r":[0,1,12.898832684824903,367,1,1,12.898832684824903,368,2,1,12.898832684824903,369,3,1,12.898832684824903,276]}}
  #|{"textrec":{"s":[13,400,0,"变量名"],"r":[0,1,12.898832684824903,370,1,1,12.898832684824903,371,2,1,12.898832684824903,276]}}
  #|{"textrec":{"s":[14,400,0,"代理"],"r":[0,1,13.891050583657588,372,1,1,13.891050583657588,373]}}
  #|{"textrec":{"s":[14,400,0,"环境变量"],"r":[0,1,13.891050583657588,374,1,1,13.891050583657588,375,2,1,13.891050583657588,376,3,1,13.891050583657588,377]}}
  #|{"textrec":{"g":316,"r":[1929,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":317,"r":[1945,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":372,"r":[1960,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":373,"r":[1976,32,16,14,-1,-12,0]}}
  #|{"textrec":{"g":374,"r":[1993,32,16,15,-1,-12,0]}}
  #|{"textrec":{"g":375,"r":[2010,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":376,"r":[2027,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":377,"r":[0,65,15,15,-1,-12,0]}}
  #|{"textrec":{"g":318,"r":[16,65,14,14,-1,-11,0]}}
  #|{"textrec":{"g":319,"r":[31,65,14,13,-1,-11,0]}}
  #|{"textrec":{"g":320,"r":[46,65,4,9,1,-9,0]}}
  #|{"textrec":{"g":321,"r":[51,65,8,10,-1,-8,0]}}
  #|{"textrec":{"g":322,"r":[60,65,9,12,-1,-8,0]}}
  #|{"textrec":{"g":323,"r":[70,65,9,10,-1,-8,0]}}
  #|{"textrec":{"g":324,"r":[80,65,9,9,-1,-8,0]}}
  #|{"textrec":{"g":325,"r":[90,65,6,11,-1,-9,0]}}
  #|{"textrec":{"g":326,"r":[97,65,14,14,-1,-11,0]}}
  #|{"textrec":{"g":327,"r":[112,65,14,14,-1,-11,0]}}
  #|{"textrec":{"g":328,"r":[127,65,14,14,-1,-11,0]}}
  #|{"textrec":{"g":329,"r":[142,65,12,14,0,-11,0]}}
  #|{"textrec":{"g":330,"r":[155,65,14,14,-1,-11,0]}}
  #|{"textrec":{"g":331,"r":[170,65,14,14,-1,-11,0]}}
  #|{"textrec":{"g":332,"r":[185,65,5,6,0,-3,0]}}
  #|{"textrec":{"g":333,"r":[191,65,14,14,-1,-11,0]}}
  #|{"textrec":{"g":334,"r":[206,65,14,14,-1,-11,0]}}
  #|{"textrec":{"g":335,"r":[221,65,14,14,-1,-11,0]}}
  #|{"textrec":{"g":336,"r":[236,65,14,14,-1,-11,0]}}
  #|{"textrec":{"g":337,"r":[251,65,14,14,-1,-11,0]}}
  #|{"textrec":{"g":338,"r":[266,65,14,14,-1,-11,0]}}
  #|{"textrec":{"g":339,"r":[281,65,14,14,-1,-11,0]}}
  #|{"textrec":{"g":340,"r":[296,65,13,14,-1,-11,0]}}
  #|{"textrec":{"g":341,"r":[310,65,14,14,-1,-11,0]}}
  #|{"textrec":{"g":342,"r":[325,65,14,14,-1,-11,0]}}
  #|{"textrec":{"g":343,"r":[340,65,14,14,-1,-11,0]}}
  #|{"textrec":{"g":344,"r":[355,65,13,14,-1,-11,0]}}
  #|{"textrec":{"g":345,"r":[369,65,14,14,-1,-11,0]}}
  #|{"textrec":{"g":346,"r":[384,65,13,14,-1,-11,0]}}
  #|{"textrec":{"g":347,"r":[398,65,14,14,-1,-11,0]}}
  #|{"textrec":{"g":348,"r":[413,65,6,6,0,-3,0]}}
  #|{"textrec":{"g":349,"r":[420,65,14,13,-1,-10,0]}}
  #|{"textrec":{"g":350,"r":[435,65,14,14,-1,-11,0]}}
  #|{"textrec":{"g":351,"r":[450,65,14,14,-1,-11,0]}}
  #|{"textrec":{"g":352,"r":[465,65,14,13,-1,-11,0]}}
  #|{"textrec":{"g":353,"r":[480,65,14,14,-1,-11,0]}}
  #|{"textrec":{"g":354,"r":[495,65,14,14,-1,-11,0]}}
  #|{"textrec":{"g":355,"r":[510,65,14,13,-1,-10,0]}}
  #|{"textrec":{"g":356,"r":[525,65,14,14,-1,-11,0]}}
  #|{"textrec":{"g":357,"r":[540,65,14,14,-1,-11,0]}}
  #|{"textrec":{"g":358,"r":[555,65,13,14,-1,-11,0]}}
  #|{"textrec":{"g":359,"r":[569,65,14,14,-1,-11,0]}}
  #|{"textrec":{"g":360,"r":[584,65,14,14,-1,-11,0]}}
  #|{"textrec":{"g":361,"r":[599,65,14,14,-1,-11,0]}}
  #|{"textrec":{"g":362,"r":[614,65,14,14,-1,-11,0]}}
  #|{"textrec":{"g":363,"r":[629,65,14,14,-1,-11,0]}}
  #|{"textrec":{"g":364,"r":[644,65,13,14,-1,-11,0]}}
  #|{"textrec":{"g":365,"r":[658,65,14,14,-1,-11,0]}}
  #|{"textrec":{"g":366,"r":[673,65,14,14,-1,-11,0]}}
  #|{"textrec":{"g":367,"r":[688,65,14,14,0,-11,0]}}
  #|{"textrec":{"g":368,"r":[703,65,15,15,-1,-12,0]}}
  #|{"textrec":{"g":369,"r":[719,65,15,15,-1,-12,0]}}
  #|{"textrec":{"s":[15,400,0,"api.github.com, uploads.github.com"],"r":[0,1,8.0419921875,93,1,1,8.9208984375,92,2,1,3.4716796875,102,3,1,4.072265625,160,4,1,8.759765625,297,5,1,3.4716796875,102,6,1,5.21484375,101,7,1,8.59130859375,307,8,1,8.51806640625,163,9,1,8.90625,162,10,1,3.9990234375,160,11,1,8.0126953125,94,12,1,8.6279296875,88,13,1,12.8173828125,161,14,1,4.21875,378,15,1,3.984375,-1,16,1,8.51806640625,163,17,1,8.9208984375,92,18,1,3.5595703125,108,19,1,8.6279296875,88,20,1,8.0419921875,93,21,1,8.9794921875,379,22,1,7.6171875,91,23,1,4.072265625,160,24,1,8.759765625,297,25,1,3.4716796875,102,26,1,5.21484375,101,27,1,8.59130859375,307,28,1,8.51806640625,163,29,1,8.90625,162,30,1,3.9990234375,160,31,1,8.0126953125,94,32,1,8.6279296875,88,33,1,12.8173828125,161]}}
  #|{"textrec":{"g":160,"r":[735,65,5,5,0,-3,0]}}
  #|{"textrec":{"g":161,"r":[741,65,13,11,0,-10,0]}}
  #|{"textrec":{"g":378,"r":[755,65,5,7,-1,-3,0]}}
  #|{"textrec":{"g":379,"r":[761,65,10,15,-1,-13,0]}}
  #|{"textrec":{"g":370,"r":[772,65,15,15,-1,-12,0]}}
  #|{"textrec":{"g":371,"r":[788,65,14,14,-1,-12,0]}}
  #|{"textrec":{"s":[15,400,0,"例如 GH_TOKEN"],"r":[0,1,14.883268482490273,304,1,1,14.883268482490273,305,2,1,3.984375,-1,3,1,10.96435546875,306,4,1,10.8984375,262,5,1,8.07861328125,308,6,1,8.61328125,253,7,1,11.1181640625,380,8,1,9.64599609375,246,9,1,8.701171875,381,10,1,10.8984375,382]}}
  #|{"textrec":{"g":380,"r":[803,65,13,14,-1,-12,0]}}
  #|{"textrec":{"g":381,"r":[817,65,9,13,0,-12,0]}}
  #|{"textrec":{"g":382,"r":[827,65,11,13,0,-12,0]}}
  #|{"textrec":{"s":[15,400,0,"api.example.test"],"r":[0,1,8.0419921875,93,1,1,8.9208984375,92,2,1,3.4716796875,102,3,1,4.072265625,160,4,1,8.0419921875,95,5,1,7.4853515625,383,6,1,8.0419921875,93,7,1,12.8173828125,161,8,1,8.9208984375,92,9,1,3.5595703125,108,10,1,8.3349609375,95,11,1,4.072265625,160,12,1,5.013427734375,101,13,1,8.280029296875,95,14,1,7.58056640625,91,15,1,5.17822265625,101]}}
  #|{"textrec":{"g":383,"r":[839,65,10,10,-1,-9,0]}}
  #|{"textrec":{"s":[15,600,0,"Token"],"r":[0,1,8.813706636428833,384,1,1,8.192367553710938,385,2,1,8.24655532836914,386,3,1,8.397692441940308,85,4,1,8.93320620059967,180]}}
  #|{"textrec":{"s":[13,400,0,"未加密 · "],"r":[0,1,12.898832684824903,215,1,1,12.898832684824903,216,2,1,12.898832684824903,226,3,1,3.580078125,-1,4,1,6.228545204222122,236,5,1,3.580078125,-1]}}
  #|{"textrec":{"s":[13,400,0,"允许 agent 申请 · 代理 · api.example.test"],"r":[0,1,12.898832684824903,387,1,1,12.898832684824903,388,2,1,3.580078125,-1,3,1,7.0966796875,12,4,1,7.845703125,249,5,1,7.3505859375,14,6,1,7.50927734375,211,7,1,4.646484375,82,8,1,3.580078125,-1,9,1,12.89883268482491,389,10,1,12.898832684824896,390,11,1,3.580078125,-1,12,1,6.228545204222115,236,13,1,3.580078125,-1,14,1,12.898832684824896,265,15,1,12.898832684824896,145,16,1,3.580078125,-1,17,1,6.228545204222115,236,18,1,3.580078125,-1,19,1,7.0966796875,12,20,1,7.8583984375,11,21,1,3.1357421875,77,22,1,3.65625,81,23,1,7.0966796875,14,24,1,6.6142578125,79,25,1,7.0966796875,12,26,1,11.2353515625,80,27,1,7.8583984375,11,28,1,3.2119140625,76,29,1,7.3505859375,14,30,1,3.65625,81,31,1,4.471923828125,82,32,1,7.302978515625,14,33,1,6.69677734375,10,34,1,4.61474609375,82]}}
  #|{"textrec":{"s":[13,400,0,"…"],"r":[0,1,10.384765625,391]}}
  #|{"textrec":{"s":[13,400,0,"允许 agent 申请 · 代理 · api.exampl…"],"r":[0,1,12.898832684824903,387,1,1,12.898832684824903,388,2,1,3.580078125,-1,3,1,7.0966796875,12,4,1,7.845703125,249,5,1,7.3505859375,14,6,1,7.50927734375,211,7,1,4.646484375,82,8,1,3.580078125,-1,9,1,12.89883268482491,389,10,1,12.898832684824896,390,11,1,3.580078125,-1,12,1,6.228545204222115,236,13,1,3.580078125,-1,14,1,12.898832684824896,265,15,1,12.898832684824896,145,16,1,3.580078125,-1,17,1,6.228545204222115,236,18,1,3.580078125,-1,19,1,7.0966796875,12,20,1,7.8583984375,11,21,1,3.1357421875,77,22,1,3.65625,81,23,1,7.0966796875,14,24,1,6.6142578125,79,25,1,7.0966796875,12,26,1,11.2353515625,80,27,1,7.8583984375,11,28,1,3.2119140625,76,29,1,10.384765625,391]}}
  #|{"textrec":{"g":384,"r":[850,65,12,13,-1,-12,0]}}
  #|{"textrec":{"g":385,"r":[863,65,11,12,-1,-10,0]}}
  #|{"textrec":{"g":386,"r":[875,65,10,14,0,-13,0]}}
  #|{"textrec":{"g":387,"r":[886,65,15,15,-1,-12,0]}}
  #|{"textrec":{"g":388,"r":[902,65,15,15,-1,-12,0]}}
  #|{"textrec":{"g":389,"r":[918,65,12,15,0,-12,0]}}
  #|{"textrec":{"g":390,"r":[931,65,15,15,-1,-12,0]}}
  #|{"textrec":{"g":145,"r":[947,65,15,13,-1,-11,0]}}
  #|{"textrec":{"g":391,"r":[963,65,11,5,0,-3,0]}}
  #|{"textrec":{"s":[11,400,0,"Token · 保存在 studio"],"r":[0,1,6.4990234375,392,1,1,6.0263671875,393,2,1,5.90283203125,394,3,1,6.21435546875,395,4,1,6.48291015625,396,5,1,3.158203125,-1,6,1,5.2804038549793475,397,7,1,3.158203125,-1,8,1,10.935797665369648,398,9,1,10.935797665369655,399,10,1,10.935797665369648,400,11,1,3.158203125,-1,12,1,5.79541015625,401,13,1,4.03369140625,402,14,1,6.48291015625,403,15,1,6.8212890625,404,16,1,2.7822265625,405,17,1,6.5634765625,393]}}
  #|{"textrec":{"m":[11,400,0],"r":[10.634765625,2.3203125,16,10.634765625,2.3203125,0]}}
  #|{"textrec":{"s":[16,600,0,"e2e-080726"],"r":[0,1,9.127458572387695,46,1,1,9.717817306518555,406,2,1,9.100765228271484,46,3,1,7.363014221191406,407,4,1,10.31976318359375,408,5,1,10.440597534179688,409,6,1,10.138774871826172,408,7,1,8.996856689453125,410,8,1,9.744510650634766,406,9,1,10.3499755859375,411]}}
  #|{"textrec":{"s":[17,400,0,"密钥"],"r":[0,1,16.851167315175097,412,1,1,16.851167315175097,413]}}
  #|{"textrec":{"s":[15,600,0,"此密钥未加密"],"r":[0,1,14.883268482490273,117,1,1,14.883268482490273,414,2,1,14.883268482490273,415,3,1,14.883268482490273,416,4,1,14.88326848249028,417,5,1,14.88326848249028,414]}}
  #|{"textrec":{"s":[14,400,0,"它以明文保存在 studio 上，agent 可绕过批准直接读取。开启安全模式后，仅你的设备能解密，agent 每次使用都需经你批准。"],"r":[0,1,13.891050583657588,418,1,1,13.891050583657588,419,2,1,13.891050583657588,420,3,1,13.891050583657588,421,4,1,13.891050583657588,422,5,1,13.891050583657588,423,6,1,13.891050583657588,189,7,1,3.787109375,-1,8,1,7.1435546875,424,9,1,4.9013671875,61,10,1,8.0185546875,425,11,1,8.449218749999986,426,12,1,3.30859375,427,13,1,8.12109375,428,14,1,3.787109375,-1,15,1,13.891050583657602,429,16,1,12.681712062256821,50,17,1,7.57421875,57,18,1,8.380859375,58,19,1,7.84765625,59,20,1,8.0185546875,60,21,1,4.935546875,61,22,1,3.787109375,-1,23,1,13.891050583657574,430,24,1,13.891050583657602,431,25,1,13.891050583657602,432,26,1,13.891050583657602,433,27,1,13.891050583657602,434,28,1,13.891050583657602,435,29,1,13.891050583657602,436,30,1,13.891050583657602,437,31,1,13.891050583657602,438,32,1,14.081712062256827,439,33,1,13.891050583657602,97,34,1,13.891050583657602,98,35,1,13.891050583657602,440,36,1,13.891050583657602,441,37,1,13.891050583657602,442,38,1,13.891050583657602,443,39,1,13.891050583657602,444,40,1,14.081712062256827,50,41,1,13.891050583657602,445,42,1,13.891050583657602,48,43,1,13.891050583657602,56,44,1,13.891050583657602,446,45,1,13.891050583657602,447,46,1,13.891050583657602,448,47,1,13.891050583657602,449,48,1,13.891050583657602,450,49,1,12.681712062256793,50,50,1,7.57421875,57,51,1,8.380859375,58,52,1,7.84765625,59,53,1,8.0185546875,60,54,1,4.935546875,61,55,1,3.787109375,-1,56,1,13.891050583657602,451,57,1,13.891050583657602,452,58,1,13.891050583657602,453,59,1,13.891050583657602,55,60,1,13.891050583657602,454,61,1,13.891050583657602,455,62,1,13.891050583657602,456,63,1,13.891050583657602,48,64,1,13.891050583657602,433,65,1,13.891050583657602,434,66,1,7.08171206225677,439]}}
  #|{"textrec":{"s":[15,600,0,"内容"],"r":[0,1,14.883268482490273,457,1,1,14.883268482490273,458]}}
  #|{"textrec":{"s":[15,400,0,"显示"],"r":[0,1,14.883268482490273,459,1,1,14.883268482490273,460]}}
  #|{"textrec":{"s":[14,400,2,"••••••••••••••••••••"],"r":[0,1,8.4,461,1,1,8.4,461,2,1,8.400000000000002,461,3,1,8.399999999999999,461,4,1,8.399999999999999,461,5,1,8.399999999999999,461,6,1,8.399999999999999,461,7,1,8.400000000000006,461,8,1,8.400000000000006,461,9,1,8.400000000000006,461,10,1,8.400000000000006,461,11,1,8.400000000000006,461,12,1,8.400000000000006,461,13,1,8.400000000000006,461,14,1,8.400000000000006,461,15,1,8.399999999999991,461,16,1,8.400000000000006,461,17,1,8.400000000000006,461,18,1,8.400000000000006,461,19,1,8.400000000000006,461]}}
  #|{"textrec":{"m":[14,400,2],"r":[14.280059814453125,4.200042724609375,20,14.840030074119568,4.7600096464157104,0]}}
  #|{"textrec":{"s":[15,600,0,"agent 可用"],"r":[0,1,8.40147078037262,462,1,1,9.247174859046936,463,2,1,8.615586161613464,85,3,1,8.93320620059967,180,4,1,5.683325529098511,464,5,1,3.761730194091797,-1,6,1,14.883268482490273,465,7,1,14.883268482490273,466]}}
  #|{"textrec":{"s":[14,400,0,"方式"],"r":[0,1,13.891050583657588,467,1,1,13.891050583657588,443]}}
  #|{"textrec":{"s":[15,400,0,"代理 · 限 api.example.test"],"r":[0,1,14.883268482490273,468,1,1,14.883268482490273,469,2,1,3.984375,-1,3,1,7.186782927948599,470,4,1,3.984375,-1,5,1,14.883268482490273,471,6,1,3.984375,-1,7,1,8.041992187499993,93,8,1,8.9208984375,92,9,1,3.4716796875,102,10,1,4.072265625,160,11,1,8.0419921875,95,12,1,7.4853515625,383,13,1,8.0419921875,93,14,1,12.8173828125,161,15,1,8.9208984375,92,16,1,3.5595703125,108,17,1,8.3349609375,95,18,1,4.072265625,160,19,1,5.013427734375,101,20,1,8.280029296875,95,21,1,7.58056640625,91,22,1,5.17822265625,101]}}
  #|{"textrec":{"s":[15,600,0,"使用记录"],"r":[0,1,14.883268482490273,472,1,1,14.883268482490273,466,2,1,14.883268482490273,473,3,1,14.883268482490273,474]}}
  #|{"textrec":{"s":[15,400,0,"正在读取"],"r":[0,1,14.883268482490273,475,1,1,14.883268482490273,476,2,1,14.883268482490273,477,3,1,14.883268482490273,478]}}
  #|{"textrec":{"s":[15,400,0,"暂无使用记录"],"r":[0,1,14.883268482490273,479,1,1,14.883268482490273,480,2,1,14.883268482490273,481,3,1,14.883268482490273,115,4,1,14.88326848249028,113,5,1,14.88326848249028,271]}}
  #|{"textrec":{"g":412,"r":[975,65,18,18,-1,-15,0]}}
  #|{"textrec":{"g":413,"r":[994,65,18,18,-1,-15,0]}}
  #|{"textrec":{"g":418,"r":[1013,65,14,15,0,-13,0]}}
  #|{"textrec":{"g":419,"r":[1028,65,15,16,0,-13,0]}}
  #|{"textrec":{"g":420,"r":[1044,65,14,15,0,-12,0]}}
  #|{"textrec":{"g":421,"r":[1059,65,16,16,-1,-13,0]}}
  #|{"textrec":{"g":422,"r":[1076,65,16,16,-1,-13,0]}}
  #|{"textrec":{"g":423,"r":[1093,65,15,16,-1,-13,0]}}
  #|{"textrec":{"g":424,"r":[1109,65,9,11,-1,-9,0]}}
  #|{"textrec":{"g":425,"r":[1119,65,9,11,0,-9,0]}}
  #|{"textrec":{"g":426,"r":[1129,65,10,14,-1,-12,0]}}
  #|{"textrec":{"g":427,"r":[1140,65,5,13,-1,-12,0]}}
  #|{"textrec":{"g":428,"r":[1146,65,10,11,-1,-9,0]}}
  #|{"textrec":{"g":429,"r":[1157,65,15,15,-1,-13,0]}}
  #|{"textrec":{"g":430,"r":[1173,65,15,15,-1,-12,0]}}
  #|{"textrec":{"g":431,"r":[1189,65,15,16,-1,-13,0]}}
  #|{"textrec":{"g":432,"r":[1205,65,16,16,-1,-13,0]}}
  #|{"textrec":{"g":433,"r":[1222,65,15,16,-1,-13,0]}}
  #|{"textrec":{"g":434,"r":[1238,65,15,16,-1,-13,0]}}
  #|{"textrec":{"g":435,"r":[1254,65,15,16,-1,-13,0]}}
  #|{"textrec":{"g":436,"r":[1270,65,15,16,-1,-13,0]}}
  #|{"textrec":{"g":437,"r":[1286,65,16,16,-1,-13,0]}}
  #|{"textrec":{"g":438,"r":[1303,65,16,15,-1,-12,0]}}
  #|{"textrec":{"g":439,"r":[1320,65,6,6,0,-3,0]}}
  #|{"textrec":{"g":440,"r":[1327,65,15,16,-1,-13,0]}}
  #|{"textrec":{"g":441,"r":[1343,65,16,15,-1,-13,0]}}
  #|{"textrec":{"g":442,"r":[1360,65,16,16,-1,-13,0]}}
  #|{"textrec":{"g":443,"r":[1377,65,15,16,-1,-13,0]}}
  #|{"textrec":{"g":444,"r":[1393,65,15,16,-1,-13,0]}}
  #|{"textrec":{"g":445,"r":[1409,65,16,16,-1,-13,0]}}
  #|{"textrec":{"g":446,"r":[1426,65,16,15,-1,-12,0]}}
  #|{"textrec":{"g":447,"r":[1443,65,16,16,-1,-13,0]}}
  #|{"textrec":{"g":448,"r":[1460,65,15,16,-1,-13,0]}}
  #|{"textrec":{"g":449,"r":[1476,65,15,16,-1,-13,0]}}
  #|{"textrec":{"g":450,"r":[1492,65,15,16,-1,-13,0]}}
  #|{"textrec":{"g":451,"r":[1508,65,16,16,-1,-13,0]}}
  #|{"textrec":{"g":452,"r":[1525,65,16,16,-1,-13,0]}}
  #|{"textrec":{"g":453,"r":[1542,65,16,16,-1,-13,0]}}
  #|{"textrec":{"g":454,"r":[1559,65,15,16,-1,-13,0]}}
  #|{"textrec":{"g":455,"r":[1575,65,15,15,-1,-12,0]}}
  #|{"textrec":{"g":456,"r":[1591,65,16,15,-1,-13,0]}}
  #|{"textrec":{"g":457,"r":[1608,65,15,17,0,-14,0]}}
  #|{"textrec":{"g":458,"r":[1624,65,16,17,-1,-14,0]}}
  #|{"textrec":{"g":461,"r":[1641,65,6,6,1,-8,0]}}
  #|{"textrec":{"g":462,"r":[1648,65,10,12,-1,-10,0]}}
  #|{"textrec":{"g":463,"r":[1659,65,11,14,-1,-10,0]}}
  #|{"textrec":{"g":464,"r":[1671,65,8,13,-1,-11,0]}}
  #|{"textrec":{"g":465,"r":[1680,65,16,16,-1,-13,0]}}
  #|{"textrec":{"g":466,"r":[1697,65,16,16,-1,-13,0]}}
  #|{"textrec":{"g":467,"r":[1714,65,15,16,-1,-13,0]}}
  #|{"textrec":{"g":472,"r":[1730,65,17,17,-1,-14,0]}}
  #|{"textrec":{"g":473,"r":[1748,65,17,16,-1,-13,0]}}
  #|{"textrec":{"g":474,"r":[1766,65,16,16,-1,-13,0]}}
  #|{"textrec":{"g":479,"r":[1783,65,15,17,0,-14,0]}}
  #|{"textrec":{"g":480,"r":[1799,65,16,16,-1,-13,0]}}
  #|{"textrec":{"g":481,"r":[1816,65,17,17,-1,-14,0]}}
  #|{"textrec":{"g":414,"r":[1834,65,16,17,-1,-14,0]}}
  #|{"textrec":{"g":415,"r":[1851,65,16,16,-1,-13,0]}}
  #|{"textrec":{"g":416,"r":[1868,65,16,16,-1,-13,0]}}
  #|{"textrec":{"g":417,"r":[1885,65,16,16,-1,-13,0]}}
  #|{"textrec":{"g":468,"r":[1902,65,16,16,-1,-13,0]}}
  #|{"textrec":{"g":469,"r":[1919,65,17,16,-1,-13,0]}}
  #|{"textrec":{"g":470,"r":[1937,65,5,5,1,-8,0]}}
  #|{"textrec":{"g":471,"r":[1943,65,16,16,0,-13,0]}}
  #|{"textrec":{"g":46,"r":[1960,65,11,12,-1,-10,0]}}
  #|{"textrec":{"g":406,"r":[1972,65,11,14,0,-13,0]}}
  #|{"textrec":{"g":407,"r":[1984,65,8,5,0,-7,0]}}
  #|{"textrec":{"g":408,"r":[1993,65,11,15,0,-13,0]}}
  #|{"textrec":{"g":409,"r":[2005,65,12,15,-1,-13,0]}}
  #|{"textrec":{"g":410,"r":[2018,65,11,14,-1,-13,0]}}
  #|{"textrec":{"g":411,"r":[2030,65,12,15,-1,-13,0]}}
  #|{"textrec":{"g":392,"r":[0,84,9,10,-1,-9,0]}}
  #|{"textrec":{"g":393,"r":[10,84,8,9,-1,-7,0]}}
  #|{"textrec":{"g":394,"r":[19,84,8,11,-1,-10,0]}}
  #|{"textrec":{"g":395,"r":[28,84,8,9,-1,-7,0]}}
  #|{"textrec":{"g":396,"r":[37,84,8,8,-1,-7,0]}}
  #|{"textrec":{"g":397,"r":[46,84,5,4,0,-6,0]}}
  #|{"textrec":{"g":398,"r":[52,84,13,13,-1,-10,0]}}
  #|{"textrec":{"g":399,"r":[66,84,13,13,-1,-10,0]}}
  #|{"textrec":{"g":400,"r":[80,84,13,13,-1,-10,0]}}
  #|{"textrec":{"g":401,"r":[94,84,8,9,-1,-7,0]}}
  #|{"textrec":{"g":402,"r":[103,84,6,11,-1,-9,0]}}
  #|{"textrec":{"g":403,"r":[110,84,8,9,-1,-7,0]}}
  #|{"textrec":{"g":404,"r":[119,84,8,12,-1,-10,0]}}
  #|{"textrec":{"g":405,"r":[128,84,5,11,-1,-10,0]}}
  #|{"textrec":{"g":459,"r":[134,84,16,16,-1,-13,0]}}
  #|{"textrec":{"g":460,"r":[151,84,16,16,-1,-13,0]}}
  #|{"textrec":{"ib":["6ee372740187b96d",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"s":[12,400,0,"值"],"r":[0,1,11.918287937743191,347]}}
  #|{"textrec":{"s":[14,400,2,"••••••••••••"],"r":[0,1,8.4,461,1,1,8.4,461,2,1,8.400000000000002,461,3,1,8.399999999999999,461,4,1,8.399999999999999,461,5,1,8.399999999999999,461,6,1,8.399999999999999,461,7,1,8.400000000000006,461,8,1,8.400000000000006,461,9,1,8.400000000000006,461,10,1,8.400000000000006,461,11,1,8.400000000000006,461]}}
  #|{"textrec":{"ib":["3ce9bbde28f6ac44",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"ib":["f2d2cfcd33247ceb",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"s":[17,700,0,"编辑「e2e-080726」"],"r":[0,1,16.851167315175097,482,1,1,25.351167315175097,483,2,1,6.366731517509727,484,3,1,9.782470703125,485,4,1,10.479736328125007,486,5,1,9.76171875,485,6,1,7.802734375,487,7,1,11.2060546875,488,8,1,11.322265625,489,9,1,10.99853515625,488,10,1,9.6787109375,490,11,1,10.50048828125,486,12,1,11.189453125,491,13,1,8.902399481193243,492]}}
  #|{"textrec":{"s":[14,400,0,"删除"],"r":[0,1,13.891050583657588,493,1,1,13.891050583657588,494]}}
  #|{"textrec":{"g":482,"r":[168,84,18,18,-1,-15,0]}}
  #|{"textrec":{"g":483,"r":[187,84,19,18,-1,-15,0]}}
  #|{"textrec":{"g":484,"r":[207,84,9,13,-1.8333333333333304,-15,0]}}
  #|{"textrec":{"g":485,"r":[217,84,12,13,-1,-11,0]}}
  #|{"textrec":{"g":486,"r":[230,84,11,15,0,-14,0]}}
  #|{"textrec":{"g":487,"r":[242,84,8,5,0,-7,0]}}
  #|{"textrec":{"g":488,"r":[251,84,12,16,0,-14,0]}}
  #|{"textrec":{"g":489,"r":[264,84,12,16,0,-14,0]}}
  #|{"textrec":{"g":490,"r":[277,84,12,14,-1,-13,0]}}
  #|{"textrec":{"g":491,"r":[290,84,12,16,0,-14,0]}}
  #|{"textrec":{"g":492,"r":[303,84,9,13,-1,-10,0]}}
  #|{"textrec":{"g":493,"r":[313,84,15,16,-1,-13,0]}}
  #|{"textrec":{"g":494,"r":[329,84,15,15,0,-12,0]}}
  #|{"textrec":{"s":[17,700,0,"删除「e2e-080726」？"],"r":[0,1,16.851167315175097,495,1,1,25.351167315175097,496,2,1,6.366731517509727,484,3,1,9.782470703125,485,4,1,10.479736328125007,486,5,1,9.76171875,485,6,1,7.802734375,487,7,1,11.2060546875,488,8,1,11.322265625,489,9,1,10.99853515625,488,10,1,9.6787109375,490,11,1,10.50048828125,486,12,1,11.189453125,491,13,1,8.194066147859928,492,14,1,8.582684824902714,497]}}
  #|{"textrec":{"s":[14,400,0,"删除后不可恢复，agent 也无法再申请"],"r":[0,1,13.891050583657588,493,1,1,13.891050583657588,494,2,1,13.891050583657588,444,3,1,13.891050583657588,498,4,1,13.891050583657588,430,5,1,13.891050583657588,499,6,1,13.891050583657588,500,7,1,12.681712062256807,50,8,1,7.57421875,57,9,1,8.380859375,58,10,1,7.84765625,59,11,1,8.0185546875,60,12,1,4.935546875,61,13,1,3.787109375,-1,14,1,13.891050583657574,501,15,1,13.891050583657602,502,16,1,13.891050583657602,503,17,1,13.891050583657602,504,18,1,13.891050583657602,505,19,1,13.891050583657602,506]}}
  #|{"textrec":{"s":[14,600,0,"取消"],"r":[0,1,13.891050583657588,507,1,1,13.891050583657588,508]}}
  #|{"textrec":{"s":[14,600,0,"删除"],"r":[0,1,13.891050583657588,509,1,1,13.891050583657588,510]}}
  #|{"textrec":{"g":495,"r":[345,84,18,18,-1,-15,0]}}
  #|{"textrec":{"g":496,"r":[364,84,18,18,0,-15,0]}}
  #|{"textrec":{"g":497,"r":[383,84,10,16,-1,-14,0]}}
  #|{"textrec":{"g":498,"r":[394,84,15,15,-1,-12,0]}}
  #|{"textrec":{"g":499,"r":[410,84,16,16,-1,-13,0]}}
  #|{"textrec":{"g":500,"r":[427,84,15,16,-1,-13,0]}}
  #|{"textrec":{"g":501,"r":[443,84,16,15,-1,-13,0]}}
  #|{"textrec":{"g":502,"r":[460,84,15,15,-1,-12,0]}}
  #|{"textrec":{"g":503,"r":[476,84,16,16,-1,-13,0]}}
  #|{"textrec":{"g":504,"r":[493,84,15,15,-1,-12,0]}}
  #|{"textrec":{"g":505,"r":[509,84,13,16,0,-13,0]}}
  #|{"textrec":{"g":506,"r":[523,84,16,16,-1,-13,0]}}
  #|{"textrec":{"g":507,"r":[540,84,16,15,-1,-12,0]}}
  #|{"textrec":{"g":508,"r":[557,84,15,16,-1,-13,0]}}
  #|{"textrec":{"g":509,"r":[573,84,15,16,-1,-13,0]}}
  #|{"textrec":{"g":510,"r":[589,84,16,15,-1,-12,0]}}
  #|{"textrec":{"s":[16,600,0,"密钥"],"r":[0,1,15.875486381322958,511,1,1,15.875486381322958,512]}}
  #|{"textrec":{"g":511,"r":[606,84,17,17,-1,-14,0]}}
  #|{"textrec":{"g":512,"r":[624,84,17,17,-1,-14,0]}}
