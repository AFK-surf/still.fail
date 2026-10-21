// e2e/traces/settings-add-station.trace, made by scripts/trace.py from 01-settings_add_station.log: not edited by hand.

///|
/// What the app and its core said in the run, a line each.
pub let trace_settings_add_station : String =
  #|{"env":{"MBUI_CLOUD":"http://127.0.0.1:18787","MBUI_CORE_ACCOUNT":"{\"sub\":\"alice\",\"email\":\"alice@example.test\",\"name\":\"Name of alice\",\"picture\":\"\",\"access\":\"-\",\"refresh\":\"-\",\"accessExpires\":1792610142}"}}
  #|{"out":{"id":1,"call":"client.device","params":{"client":"still.fail mbui","app":"desktop","userAgent":"Macintosh; Mac OS X"}},"w":1792609843637.528}
  #|{"in":{"id":1,"ok":null},"w":1792609843717.024}
  #|{"out":{"id":2,"subscribe":{"topic":"accounts"},"keyed":true},"w":1792609843717.044}
  #|{"out":{"id":3,"subscribe":{"topic":"prefs"},"keyed":true},"w":1792609843717.054}
  #|{"step":"# written by scripts/rerecord.sh from its test (src/sfreplay/emit.mbt): not edited by hand","w":1792609843718.541}
  #|{"step":"timeout 90000","w":1792609843718.548}
  #|{"step":"answered client.device","w":1792609843718.55}
  #|{"step":"answered client.focus","w":1792609843736.09}
  #|{"in":{"id":2,"value":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""}]},"w":1792609843802.46}
  #|{"in":{"id":3,"value":{"onlyMine":false,"onlyWatching":false,"onlyDecisions":false,"listFilter":{},"appearance":"system","rowPicture":"auto","absoluteTime":false,"lang":"zh","keys":{},"lastChat":{},"openChat":{},"chatTabs":{},"dropFiles":{},"driveViews":{},"filesTabs":{},"driveFavorites":{},"resume":{},"stationUpdatesDismissed":{},"device":{"app":"desktop","phone":false,"handoff":false},"reader":{"size":18,"line":1.7,"margin":22,"face":"sans","indent":true,"paper":"follow"},"rails":{},"bars":{"sets":[["chats","files","profiles","stations"],["decisions","usage","connects","archive"]],"current":0},"barsBy":{},"fonts":{},"faces":{"ui":{"id":"","name":"","mono":false,"family":"","files":[],"bytes":0},"text":{"id":"","name":"","mono":false,"family":"","files":[],"bytes":0},"code":{"id":"","name":"","mono":true,"family":"","files":[],"bytes":0},"list":[{"id":"inter","name":"Inter","mono":false,"family":"SF Inter","css":"http://127.0.0.1:18787/releases/fonts/inter/4.001/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/inter/4.001/var.ttf.gz","bytes":457818,"sha256":"29160a80ff49ddcab2c97711247e08b1fab27a484a329ce8b813d820dc559031"}],"preview":"http://127.0.0.1:18787/releases/fonts/inter/4.001/preview-194fa287.ttf","bytes":457818},{"id":"noto-sans-sc","name":"思源黑体","mono":false,"family":"SF Noto Sans SC","css":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/var.ttf.gz","bytes":11276563,"sha256":"a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da"}],"preview":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/preview-f0494178.ttf","bytes":11276563},{"id":"noto-serif-sc","name":"思源宋体","mono":false,"family":"SF Noto Serif SC","css":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/var.ttf.gz","bytes":15454579,"sha256":"050080d9255a86808f2945bffac582b31ef32bc36411ce29563b4961670c66f9"}],"preview":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/preview-001bbedf.ttf","bytes":15454579},{"id":"lxgw-wenkai","name":"霞鹜文楷","mono":false,"family":"SF LXGW WenKai","css":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/font.css","files":[{"weight":400,"url":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/400.ttf.gz","bytes":12904482,"sha256":"2d73eea94ad808999d90c0000c239a84a33b09d4bc6ab6c5b8bbf1eda8a7fc8b"},{"weight":500,"url":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/500.ttf.gz","bytes":13272430,"sha256":"f4b8a34d1f838fe411540cb7c97b1c384ac9738a876c4104500bc42508b2312a"}],"preview":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/preview-d3505af4.ttf","bytes":26176912},{"id":"jetbrains-mono","name":"JetBrains Mono","mono":true,"family":"SF JetBrains Mono","css":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/var.ttf.gz","bytes":90579,"sha256":"48715a42ec242c21e9f02692891e147d022299a52e48d5e413e1a942193ffeda"}],"preview":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/preview-ee73078f.ttf","bytes":90579},{"id":"fira-code","name":"Fira Code","mono":true,"family":"SF Fira Code","css":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/var.ttf.gz","bytes":137151,"sha256":"9335b082b3c7850d98a64b584f3417f65355f3471278bb5eeb8c6c0e8657aeeb"}],"preview":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/preview-555be27a.ttf","bytes":137151},{"id":"maple-mono","name":"Maple Mono","mono":true,"family":"SF Maple Mono CN","css":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/font.css","files":[{"weight":400,"url":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/400.ttf.gz","bytes":8352545,"sha256":"0fcc5139bfd5ab14ff989bb7dfd5236d0cafc10e60b9828569e6883613ab4085"},{"weight":600,"url":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/600.ttf.gz","bytes":8438132,"sha256":"96ed7ae26ee7c50b02b2d2b2bc0f1a0cbabe45ae5d6e6abf6678e2177c415677"}],"preview":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/preview-cffdf246.ttf","bytes":16790677}]}}},"w":1792609843802.494}
  #|{"out":{"id":4,"subscribe":{"topic":"workspaces"},"keyed":true},"w":1792609843802.538}
  #|{"out":{"id":5,"subscribe":{"topic":"status"},"keyed":true},"w":1792609843802.547}
  #|{"in":{"id":4,"value":[{"account":{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""},"workspaces":[{"id":"01M5FXYS94SYCJ0PB9XS4BKV1W","name":"Dev","role":"owner","created_at":1792609838,"stations":1,"members":1,"relays":[],"time":{"created_at":{"past":true,"at":1792609838000,"ago":"刚刚","full":"10/22 03:10:38","until":"1 分钟内"}}}],"invitations":[],"relay_url":"http://127.0.0.1:18740","loaded":true,"beta":true}]},"w":1792609843819.162}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792609843819.182}
  #|{"out":{"id":6,"subscribe":{"topic":"lock","workspace":"01M5FXYS94SYCJ0PB9XS4BKV1W"},"keyed":true},"w":1792609843819.223}
  #|{"out":{"id":7,"subscribe":{"topic":"chats","scope":"01M5FXYS94SYCJ0PB9XS4BKV1W","mine":false},"keyed":true},"w":1792609843819.234}
  #|{"out":{"id":8,"subscribe":{"topic":"changelog"},"keyed":true},"w":1792609843819.24}
  #|{"out":{"id":9,"subscribe":{"topic":"workspaceMarks","workspace":"01M5FXYS94SYCJ0PB9XS4BKV1W"},"keyed":true},"w":1792609843819.363}
  #|{"out":{"id":10,"subscribe":{"topic":"status","workspace":"01M5FXYS94SYCJ0PB9XS4BKV1W"},"keyed":true},"w":1792609843819.398}
  #|{"out":{"id":11,"subscribe":{"topic":"lockPrompts"},"keyed":true},"w":1792609843824.37}
  #|{"out":{"id":12,"call":"client.focus","params":{"visible":true,"focused":true,"workspace":"01M5FXYS94SYCJ0PB9XS4BKV1W"}},"w":1792609843826.985}
  #|{"out":{"id":13,"subscribe":{"topic":"notify"},"keyed":true},"w":1792609843826.996}
  #|{"out":{"id":14,"subscribe":{"topic":"notify","workspace":"01M5FXYS94SYCJ0PB9XS4BKV1W"},"keyed":true},"w":1792609843827.031}
  #|{"in":{"id":6,"value":{"available":true,"locked":false,"notice":true,"role":"owner","manages":true,"owner":true,"canSign":true,"signs":false,"me":{"device":"8dceb5f45193d2326c347c38c704ee6b11eb393f90d93fc95f65dd4b18f09433","code":"8UH-9J8","kind":"app","confirmed":false,"waiting":false,"asked":false},"signers":0,"members":[],"stations":[{"id":"2914835be3a565475e145ceb6539460dd59411548948b73ce83492a352591cca","name":"studio","version":"0.1.0","online":true,"protected":false}],"protected":0,"requests":[],"renew":[],"attention":0}},"w":1792609843849.128}
  #|{"in":{"id":7,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"stations":[{"station":"01M5FXYS94SYCJ0PB9XS4BKV1W/2914835be3a565475e145ceb6539460dd59411548948b73ce83492a352591cca","id":"2914835be3a565475e145ceb6539460dd59411548948b73ce83492a352591cca","name":"studio","state":"online"}],"loading":false,"days":[{"daysAgo":0,"at":1792609842399,"label":"今天","items":[{"id":"ember:c-9b2b990305","session":"ember:c-9b2b990305","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","agents":[{"key":"ember:c-9b2b990305","runtime":"claude","process":"warm","pending":0,"lastTurn":{"id":"ffde02f2-9b7c-4699-b45a-b12a2bf9a8f3","kind":"input","outcome":"completed","declared":"final","ending":"all_done","need":"answered the question that was asked","startedAt":1792609842331,"endedAt":1792609842401},"agentText":"默认模型","statusText":"已完成：answered the question that was asked"}],"last":{"seq":2,"authorKind":"agent","author":"ember:c-9b2b990305","text":"你好，我是测试用的 agent","createdAt":1792609842399,"by":{"kind":"agent","name":"agent","mine":false,"runtime":"claude","label":"agent"},"preview":"你好，我是测试用的 agent","time":{"createdAt":{"at":1792609842399,"ago":"刚刚","full":"10/22 03:10:42","until":"1 分钟内","past":true}}},"unread":true,"mine":true,"lastActiveAt":1792609842399,"station":"01M5FXYS94SYCJ0PB9XS4BKV1W/2914835be3a565475e145ceb6539460dd59411548948b73ce83492a352591cca","stationName":"studio","time":{"lastActiveAt":{"at":1792609842399,"ago":"刚刚","full":"10/22 03:10:42","until":"1 分钟内","past":true}},"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"peopleText":"你 发起","clientKey":"new:chat-38ce5d97f05d0be52b","pinned":false,"tone":"done"}]}],"trouble":null,"members":1,"leading":"agents","glyph":{"online":1,"dim":0,"connecting":0,"failing":0,"working":0,"summary":"studio","label":"1 台 station，1 台在线"},"note":{"reading":false,"text":null,"failing":[],"empty":false}}},"w":1792609843849.167}
  #|{"in":{"id":8,"value":{"app":"desktop","tabs":[{"part":"desktop","label":"桌面","days":[]},{"part":"web","label":"网页","days":[]},{"part":"android","label":"安卓","days":[]},{"part":"station","label":"Station","days":[]},{"part":"cloud","label":"云端","days":[]}],"loading":false}},"w":1792609843849.191}
  #|{"in":{"id":9,"value":{"workspaces":{"01M5FXYS94SYCJ0PB9XS4BKV1W":{"alert":0,"unread":1,"tone":"done","label":"1 个有新消息","badge":0,"items":[],"mineTone":"done"}},"badge":0,"badgeCounts":"attention","badgeKinds":{"on":true,"wait":true,"failed":true,"done":false,"message":false}}},"w":1792609843849.201}
  #|{"in":{"id":10,"value":{"items":[]}},"w":1792609843849.206}
  #|{"in":{"id":11,"value":{"pairing":[]}},"w":1792609843849.209}
  #|{"in":{"id":12,"ok":null},"w":1792609843849.211}
  #|{"in":{"id":13,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792609843849.216}
  #|{"in":{"id":14,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792609843849.221}
  #|{"out":{"id":15,"subscribe":{"topic":"longJobs","scope":"01M5FXYS94SYCJ0PB9XS4BKV1W"},"keyed":true},"w":1792609843849.26}
  #|{"out":{"id":16,"call":"notify.permission","params":{"state":"unknown"}},"w":1792609843851.994}
  #|{"in":{"id":15,"value":{"groups":[]}},"w":1792609843865.764}
  #|{"in":{"id":16,"ok":null},"w":1792609843865.791}
  #|{"step":"answered notify.permission","w":1792609843866.053}
  #|{"step":"tap icon:settings","w":1792609843882.922}
  #|{"step":"tap icon:settings","acted":true,"w":1792609843882.934}
  #|{"out":{"id":17,"subscribe":{"topic":"workspace","workspace":"01M5FXYS94SYCJ0PB9XS4BKV1W"},"keyed":true},"w":1792609843899.222}
  #|{"out":{"id":18,"subscribe":{"topic":"stations","scope":"01M5FXYS94SYCJ0PB9XS4BKV1W"},"keyed":true},"w":1792609843899.235}
  #|{"out":{"id":19,"subscribe":{"topic":"connects","scope":"01M5FXYS94SYCJ0PB9XS4BKV1W","mine":false},"keyed":true},"w":1792609843899.24}
  #|{"out":{"id":20,"subscribe":{"topic":"vaults","workspace":"01M5FXYS94SYCJ0PB9XS4BKV1W"},"keyed":true},"w":1792609843899.246}
  #|{"out":{"id":21,"subscribe":{"topic":"doing"},"keyed":true},"w":1792609843901.953}
  #|{"out":{"id":22,"call":"cache.usage","params":{}},"w":1792609843902.836}
  #|{"step":"answered cache.usage","w":1792609843903.02}
  #|{"in":{"id":17,"value":{"id":"01M5FXYS94SYCJ0PB9XS4BKV1W","name":"Dev","role":"owner","created_at":1792609838,"members":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":"https://example.test/p.png","role":"owner","added_at":1792609838}],"stations":[{"id":"2914835be3a565475e145ceb6539460dd59411548948b73ce83492a352591cca","name":"studio","emoji":null,"icon":null,"enrolled_at":1792609838,"enrolled_by":"alice","last_seen":1792609842,"version":"0.1.0","time":{"last_seen":{"past":true,"at":1792609842000,"ago":"刚刚","full":"10/22 03:10:42","until":"1 分钟内"}}}],"invitations":[],"added":[],"relays":[],"lock":null,"lock_requests":0,"time":{"created_at":{"past":true,"at":1792609838000,"ago":"刚刚","full":"10/22 03:10:38","until":"1 分钟内"}}}},"w":1792609843915.758}
  #|{"in":{"id":18,"value":[{"station":"01M5FXYS94SYCJ0PB9XS4BKV1W/2914835be3a565475e145ceb6539460dd59411548948b73ce83492a352591cca","id":"2914835be3a565475e145ceb6539460dd59411548948b73ce83492a352591cca","name":"studio","summary":"正在连接","face":"idle","line":"在线","online":true,"reconnecting":false,"lastSeen":1792609842,"version":"0.1.0","link":{"state":"online"},"runtimes":[{"runtime":"claude","models":["claude-sonnet-5-5"]}],"models":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792609842309,"time":{"checkedAt":{"at":1792609842309,"ago":"刚刚","full":"10/22 03:10:42","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"overview":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null,"summaryText":"最近 7 天检查了 0 个 chat","changeText":null}},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","email":"alice@example.test","name":"Name of alice","sub":"alice","role":"owner","workspace":"01M5FXYS94SYCJ0PB9XS4BKV1W","device":"8dceb5f45193d2326c347c38c704ee6b11eb393f90d93fc95f65dd4b18f09433"},"connects":[],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792609842184,"time":{"checkedAt":{"at":1792609842184,"ago":"刚刚","full":"10/22 03:10:42","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792609842309,"time":{"checkedAt":{"at":1792609842309,"ago":"刚刚","full":"10/22 03:10:42","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"modelsReading":false,"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]}],"processes":[],"counts":{"sessions":1,"running":0,"warm":1},"mesh":{"state":"running","origin":"http://127.0.0.1:18787","station":"2914835be3a565475e145ceb6539460dd59411548948b73ce83492a352591cca","workspace":"Dev","workspaceId":"01M5FXYS94SYCJ0PB9XS4BKV1W","name":"studio"},"slackUsers":[],"slackTeams":[],"slackApps":[],"feishuRegistrations":[],"disk":{"freeBytes":28400459776,"totalBytes":245107195904},"logins":[],"machineLogins":[],"sharing":true,"consoleSignIn":true,"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"google","name":"Google Gemini","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xai","name":"xAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"mistral","name":"Mistral","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"deepseek","name":"DeepSeek","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen","name":"Qwen","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai","name":"Kimi","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"kimi-code","name":"Kimi Code","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai","name":"Z.ai","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax","name":"MiniMax","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ant-ling","name":"Ant Ling","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"jev","name":"Jev","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen-cn","name":"Qwen (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"openrouter","name":"OpenRouter","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"opencode","name":"OpenCode Zen","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"groq","name":"Groq","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"together","name":"Together AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"fireworks","name":"Fireworks","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cerebras","name":"Cerebras","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"huggingface","name":"Hugging Face","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"nvidia","name":"NVIDIA","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"baseten","name":"Baseten","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ollama","name":"Ollama","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"custom","name":"Custom","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""}],"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792609839824},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.306","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792609839824},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-icon/apps/e2e-local/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792609839824},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-icon/apps/e2e-local/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792609839824},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","latest":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-icon/apps/e2e-local/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792609839824},{"id":"cursor","name":"Cursor","installed":false,"latest":"1.0.40","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792609839824},{"id":"devin","name":"Devin","installed":true,"version":"3000.11.92","latest":"3000.11.92","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-icon/apps/e2e-local/ember/station/test/fake/devin，不是用 Devin 的安装脚本装的，需在该机器上手动更新","state":"idle","checkedAt":1792609839824}],"processesText":"没有运行中的 agent 进程","agentEnv":[],"drive":{"roots":[],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false}},"betaOffered":false,"way":{"path":"直连","via":"direct"},"time":{"lastSeen":{"at":1792609842000,"ago":"刚刚","full":"10/22 03:10:42","until":"1 分钟内","past":true}},"joined":false}]},"w":1792609843915.882}
  #|{"in":{"id":19,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"items":[],"wait":{"reading":false,"text":null,"failing":[],"empty":true}}},"w":1792609843915.953}
  #|{"in":{"id":20,"value":{"available":true,"locked":false,"canSign":false,"setUp":false,"vaults":[{"id":"plain","name":"个人","owner":"alice","ownerName":"Name of alice","mine":true,"members":[{"sub":"alice","name":"Name of alice"}],"station":"2914835be3a565475e145ceb6539460dd59411548948b73ce83492a352591cca","stationName":"studio","items":0,"devices":0,"open":true,"keyed":true,"missing":0,"recoverable":false}],"requests":[],"refused":[{"station":"2914835be3a565475e145ceb6539460dd59411548948b73ce83492a352591cca","name":"studio","code":"vault_needs_lock"}],"plain":true}},"w":1792609843915.961}
  #|{"in":{"id":21,"value":{"doing":[]}},"w":1792609843915.968}
  #|{"in":{"id":22,"ok":{"chats":[{"station":"01M5FXYS94SYCJ0PB9XS4BKV1W/2914835be3a565475e145ceb6539460dd59411548948b73ce83492a352591cca","thread":1,"title":null,"sessions":["ember:c-9b2b990305"],"bytes":558}]}},"w":1792609843915.971}
  #|{"step":"wait 299","w":1792609843932.841}
  #|{"in":{"id":18,"delta":[{"path":[0,"host"],"set":{"hostname":"3720-Mac-mini-1","os":"macOS 27.0.1","arch":"arm64","cpus":10,"cpuModel":"Apple M4","load":0.29,"cpuBusy":0.13,"uptimeSec":89205,"memory":{"totalBytes":17179869184,"usedBytes":10154082304,"swapUsedBytes":216793088},"disk":{"path":"/tmp/mbe2e-C/data","totalBytes":245107195904,"freeBytes":28400340992},"emberRssBytes":162839768,"checkedAt":1792609843939,"summary":"10 核 · 16 GB","line":"macOS 27.0.1 · 10 核 · 16 GB · 已运行 1 天","facts":["3720-Mac-mini-1","macOS 27.0.1","arm64 · 10 核","已运行 1 天 0 小时"],"meters":[{"label":"CPU","short":"CPU","percent":13,"left":87,"level":"ok","value":"13%","remaining":"空闲 87%","big":"87","unit":"%","title":"CPU 空闲","total":"负载 2.9","note":"负载 2.9 · Apple M4"},{"label":"内存","short":"内存","percent":59,"left":41,"level":"ok","value":"9.5 GB / 16.0 GB","remaining":"剩 6.5 G","big":"6.5","unit":"GB","title":"内存剩","total":"共 16 GB","note":"swap 0.2 GB"},{"label":"磁盘","short":"磁盘","percent":88,"left":12,"level":"amber","value":"剩余 26.4 GB / 228 GB","remaining":"剩 26.4 G","big":"26.4","unit":"GB","title":"磁盘剩","total":"共 228 GB"}],"identity":"Apple M4 · 16 GB · macOS 27.0.1","details":[{"label":"主机名","value":"3720-Mac-mini-1"},{"label":"芯片","value":"Apple M4 · 10 核 · arm64"},{"label":"已运行","value":"1 天 0 小时"},{"label":"still.fail","value":"进程占用 155 MB"}],"usage":"内存 9.5 GB / 16.0 GB · 磁盘 剩余 26.4 GB / 228 GB","emberText":"still.fail 155 MB"}},{"path":[0,"line"],"set":"Apple M4"},{"path":[0,"summary"],"set":"空闲 · Apple M4 · 16 GB · macOS 27.0.1"}]},"w":1792609843965.796}
  #|{"step":"now tap =Station","w":1792609844233.167}
  #|{"step":"now tap =Station","acted":true,"w":1792609844233.232}
  #|{"step":"wait 300","w":1792609844262.406}
  #|{"step":"now until =studio","w":1792609844566.511}
  #|{"step":"tap icon:plus","w":1792609844566.581}
  #|{"step":"tap icon:plus","acted":true,"w":1792609844566.614}
  #|{"out":{"id":23,"subscribe":{"topic":"joinable","workspace":"01M5FXYS94SYCJ0PB9XS4BKV1W"},"keyed":true},"w":1792609844582.944}
  #|{"step":"wait 1449","w":1792609844599.509}
  #|{"in":{"id":23,"value":{"offered":false,"loading":false,"items":[]}},"w":1792609844599.693}
  #|{"step":"now until 添加 station","w":1792609846050.201}
  #|{"step":"tap 例如机器名","w":1792609846050.265}
  #|{"step":"tap 例如机器名","acted":true,"w":1792609846050.302}
  #|{"step":"type e2e-080726-b","w":1792609846091.909}
  #|{"step":"type e2e-080726-b","acted":true,"w":1792609846091.961}
  #|{"step":"tap =生成命令","w":1792609846104.698}
  #|{"step":"tap =生成命令","acted":true,"w":1792609846104.797}
  #|{"out":{"id":24,"call":"workspace.enroll","params":{"workspace":"01M5FXYS94SYCJ0PB9XS4BKV1W","name":"e2e-080726-b","account":"alice"}},"w":1792609846119.613}
  #|{"step":"answered workspace.enroll","w":1792609846121.662}
  #|{"in":{"id":24,"ok":{"token":"-","expires_at":1792613446,"install":"curl -fsSL http://127.0.0.1:18787/install.sh | sh -s -- oX6CBJyoi2UGrQql0oTdOshjiCZsq8h5s743pLdmOrE","installWindows":"& ([scriptblock]::Create((irm http://127.0.0.1:18787/install.ps1))) oX6CBJyoi2UGrQql0oTdOshjiCZsq8h5s743pLdmOrE","command":"stillfail station enroll http://127.0.0.1:18787 oX6CBJyoi2UGrQql0oTdOshjiCZsq8h5s743pLdmOrE"}},"w":1792609846152.313}
  #|{"step":"until 在该机器的终端中执行","w":1792609846195.231}
  #|{"step":"log do: second-station {LOG}","w":1792609846195.243}
  #|{"step":"second-station {LOG}"}
  #|{"step":"until 已加入","w":1792609846195.25}
  #|{"in":{"id":4,"delta":[{"path":[0,"workspaces",0,"stations"],"set":2}]},"w":1792609846499.113}
  #|{"in":{"id":17,"delta":[{"path":["stations"],"append":[{"id":"8eed7ed1fc389be23130b650fcc70c1f5863b8ee2d6bfe6a91a2d43f21900213","name":"e2e-080726-b","emoji":null,"icon":null,"enrolled_at":1792609846,"enrolled_by":"alice","last_seen":1792609846,"version":"0.1.0","time":{"last_seen":{"past":true,"at":1792609846000,"ago":"刚刚","full":"10/22 03:10:46","until":"1 分钟内"}}}]}]},"w":1792609846499.138}
  #|{"in":{"id":7,"delta":[{"path":["glyph","connecting"],"set":1},{"path":["glyph","dim"],"set":1},{"path":["glyph","label"],"set":"2 台 station，1 台在线，1 台正在连接"},{"path":["glyph","summary"],"set":"2 台 station"},{"path":["loading"],"set":true},{"path":["stations"],"append":[{"station":"01M5FXYS94SYCJ0PB9XS4BKV1W/8eed7ed1fc389be23130b650fcc70c1f5863b8ee2d6bfe6a91a2d43f21900213","id":"8eed7ed1fc389be23130b650fcc70c1f5863b8ee2d6bfe6a91a2d43f21900213","name":"e2e-080726-b","state":"connecting"}]}]},"w":1792609846499.158}
  #|{"in":{"id":18,"value":[{"station":"01M5FXYS94SYCJ0PB9XS4BKV1W/2914835be3a565475e145ceb6539460dd59411548948b73ce83492a352591cca","id":"2914835be3a565475e145ceb6539460dd59411548948b73ce83492a352591cca","name":"studio","summary":"空闲 · Apple M4 · 16 GB · macOS 27.0.1","face":"idle","line":"Apple M4","online":true,"reconnecting":false,"lastSeen":1792609842,"version":"0.1.0","link":{"state":"online"},"runtimes":[{"runtime":"claude","models":["claude-sonnet-5-5"]}],"models":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792609842309,"time":{"checkedAt":{"at":1792609842309,"ago":"刚刚","full":"10/22 03:10:42","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"overview":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null,"summaryText":"最近 7 天检查了 0 个 chat","changeText":null}},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","email":"alice@example.test","name":"Name of alice","sub":"alice","role":"owner","workspace":"01M5FXYS94SYCJ0PB9XS4BKV1W","device":"8dceb5f45193d2326c347c38c704ee6b11eb393f90d93fc95f65dd4b18f09433"},"connects":[],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792609842184,"time":{"checkedAt":{"at":1792609842184,"ago":"刚刚","full":"10/22 03:10:42","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792609842309,"time":{"checkedAt":{"at":1792609842309,"ago":"刚刚","full":"10/22 03:10:42","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"modelsReading":false,"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]}],"processes":[],"counts":{"sessions":1,"running":0,"warm":1},"mesh":{"state":"running","origin":"http://127.0.0.1:18787","station":"2914835be3a565475e145ceb6539460dd59411548948b73ce83492a352591cca","workspace":"Dev","workspaceId":"01M5FXYS94SYCJ0PB9XS4BKV1W","name":"studio"},"slackUsers":[],"slackTeams":[],"slackApps":[],"feishuRegistrations":[],"disk":{"freeBytes":28400156672,"totalBytes":245107195904},"logins":[],"machineLogins":[],"sharing":true,"consoleSignIn":true,"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"google","name":"Google Gemini","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xai","name":"xAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"mistral","name":"Mistral","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"deepseek","name":"DeepSeek","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen","name":"Qwen","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai","name":"Kimi","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"kimi-code","name":"Kimi Code","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai","name":"Z.ai","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax","name":"MiniMax","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ant-ling","name":"Ant Ling","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"jev","name":"Jev","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen-cn","name":"Qwen (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"openrouter","name":"OpenRouter","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"opencode","name":"OpenCode Zen","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"groq","name":"Groq","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"together","name":"Together AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"fireworks","name":"Fireworks","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cerebras","name":"Cerebras","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"huggingface","name":"Hugging Face","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"nvidia","name":"NVIDIA","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"baseten","name":"Baseten","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ollama","name":"Ollama","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"custom","name":"Custom","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""}],"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792609839824},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.306","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792609839824},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-icon/apps/e2e-local/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792609839824},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-icon/apps/e2e-local/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792609839824},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","latest":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-icon/apps/e2e-local/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792609839824},{"id":"cursor","name":"Cursor","installed":false,"latest":"1.0.40","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792609839824},{"id":"devin","name":"Devin","installed":true,"version":"3000.11.92","latest":"3000.11.92","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-icon/apps/e2e-local/ember/station/test/fake/devin，不是用 Devin 的安装脚本装的，需在该机器上手动更新","state":"idle","checkedAt":1792609839824}],"processesText":"没有运行中的 agent 进程","agentEnv":[],"drive":{"roots":[],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false}},"betaOffered":false,"host":{"hostname":"3720-Mac-mini-1","os":"macOS 27.0.1","arch":"arm64","cpus":10,"cpuModel":"Apple M4","load":0.29,"cpuBusy":0.13,"uptimeSec":89205,"memory":{"totalBytes":17179869184,"usedBytes":10154082304,"swapUsedBytes":216793088},"disk":{"path":"/tmp/mbe2e-C/data","totalBytes":245107195904,"freeBytes":28400340992},"emberRssBytes":162839768,"checkedAt":1792609843939,"summary":"10 核 · 16 GB","line":"macOS 27.0.1 · 10 核 · 16 GB · 已运行 1 天","facts":["3720-Mac-mini-1","macOS 27.0.1","arm64 · 10 核","已运行 1 天 0 小时"],"meters":[{"label":"CPU","short":"CPU","percent":13,"left":87,"level":"ok","value":"13%","remaining":"空闲 87%","big":"87","unit":"%","title":"CPU 空闲","total":"负载 2.9","note":"负载 2.9 · Apple M4"},{"label":"内存","short":"内存","percent":59,"left":41,"level":"ok","value":"9.5 GB / 16.0 GB","remaining":"剩 6.5 G","big":"6.5","unit":"GB","title":"内存剩","total":"共 16 GB","note":"swap 0.2 GB"},{"label":"磁盘","short":"磁盘","percent":88,"left":12,"level":"amber","value":"剩余 26.4 GB / 228 GB","remaining":"剩 26.4 G","big":"26.4","unit":"GB","title":"磁盘剩","total":"共 228 GB"}],"identity":"Apple M4 · 16 GB · macOS 27.0.1","details":[{"label":"主机名","value":"3720-Mac-mini-1"},{"label":"芯片","value":"Apple M4 · 10 核 · arm64"},{"label":"已运行","value":"1 天 0 小时"},{"label":"still.fail","value":"进程占用 155 MB"}],"usage":"内存 9.5 GB / 16.0 GB · 磁盘 剩余 26.4 GB / 228 GB","emberText":"still.fail 155 MB"},"way":{"path":"直连","via":"direct"},"time":{"lastSeen":{"at":1792609842000,"ago":"刚刚","full":"10/22 03:10:42","until":"1 分钟内","past":true}},"joined":false},{"station":"01M5FXYS94SYCJ0PB9XS4BKV1W/8eed7ed1fc389be23130b650fcc70c1f5863b8ee2d6bfe6a91a2d43f21900213","id":"8eed7ed1fc389be23130b650fcc70c1f5863b8ee2d6bfe6a91a2d43f21900213","name":"e2e-080726-b","summary":"正在连接","face":"idle","line":"在线","online":true,"reconnecting":true,"lastSeen":1792609846,"version":"0.1.0","link":{"state":"connecting"},"runtimes":[],"models":[],"betaOffered":false,"time":{"lastSeen":{"at":1792609846000,"ago":"刚刚","full":"10/22 03:10:46","until":"1 分钟内","past":true}},"joined":false}]},"w":1792609846499.282}
  #|{"in":{"id":19,"delta":[{"path":["wait","empty"],"set":false},{"path":["wait","reading"],"set":true},{"path":["wait","text"],"set":"正在从 e2e-080726-b 读取"}]},"w":1792609846499.361}
  #|{"in":{"id":6,"delta":[{"path":["stations"],"append":[{"id":"8eed7ed1fc389be23130b650fcc70c1f5863b8ee2d6bfe6a91a2d43f21900213","name":"e2e-080726-b","version":"0.1.0","online":true,"protected":false}]}]},"w":1792609846499.375}
  #|{"step":"tap =完成","w":1792609846501.072}
  #|{"step":"tap =完成","acted":true,"w":1792609846501.083}
  #|{"step":"wait 1449","w":1792609846515.974}
  #|{"step":"now until =e2e-080726-b","w":1792609847966.356}
  #|{"step":"tap =e2e-080726-b","w":1792609847966.413}
  #|{"step":"tap =e2e-080726-b","acted":true,"w":1792609847966.446}
  #|{"out":{"id":25,"subscribe":{"topic":"screens","station":"01M5FXYS94SYCJ0PB9XS4BKV1W/8eed7ed1fc389be23130b650fcc70c1f5863b8ee2d6bfe6a91a2d43f21900213"},"keyed":true},"w":1792609847984.113}
  #|{"out":{"id":26,"subscribe":{"topic":"machineLogins","station":"01M5FXYS94SYCJ0PB9XS4BKV1W/8eed7ed1fc389be23130b650fcc70c1f5863b8ee2d6bfe6a91a2d43f21900213"},"keyed":true},"w":1792609847984.193}
  #|{"out":{"id":27,"subscribe":{"topic":"memberships","station":"01M5FXYS94SYCJ0PB9XS4BKV1W/8eed7ed1fc389be23130b650fcc70c1f5863b8ee2d6bfe6a91a2d43f21900213"},"keyed":true},"w":1792609847984.241}
  #|{"out":{"id":28,"subscribe":{"topic":"adbShare"},"keyed":true},"w":1792609847986.11}
  #|{"step":"wait 300","w":1792609847987.174}
  #|{"in":{"id":25,"value":{"screens":[],"outdated":false,"control":true,"known":false}},"w":1792609847999.088}
  #|{"in":{"id":26,"value":{"supported":true,"loaded":false,"canLogin":true,"canRelay":true,"logins":[]}},"w":1792609847999.122}
  #|{"in":{"id":27,"value":{"manages":true,"loading":true,"canJoin":false,"workspaces":[]}},"w":1792609847999.146}
  #|{"in":{"id":28,"value":{"sharing":false,"phase":"off","tunnels":0}},"w":1792609847999.158}
  #|{"step":"now until 在此 station 上","w":1792609848299.842}
  #|{"step":"tap icon:more","w":1792609848299.901}
  #|{"step":"tap icon:more","acted":true,"w":1792609848299.946}
  #|{"step":"wait 1403","w":1792609848322.69}
  #|{"in":{"id":5,"value":{"state":"slow","text":"正在连接 e2e-080726-b ×2 · 2 秒 · 共 4 项 · 1 KB/s","items":[{"state":"slow","text":"正在连接 e2e-080726-b ×2","detail":"已等待 2 秒"},{"state":"slow","text":"e2e-080726-b 打开实时更新 ×2","detail":"已等待 2 秒，尚未收到数据"}]}},"w":1792609848649.079}
  #|{"in":{"id":10,"value":{"state":"slow","text":"正在连接 e2e-080726-b ×2 · 2 秒 · 共 4 项 · 1 KB/s","items":[{"state":"slow","text":"正在连接 e2e-080726-b ×2","detail":"已等待 2 秒"},{"state":"slow","text":"e2e-080726-b 打开实时更新 ×2","detail":"已等待 2 秒，尚未收到数据"}]}},"w":1792609848649.119}
  #|{"step":"now tap 从 workspace 移除","w":1792609849733.219}
  #|{"step":"now tap 从 workspace 移除","acted":true,"w":1792609849733.286}
  #|{"step":"wait 1230","w":1792609849750.349}
  #|{"in":{"id":5,"delta":[{"path":["items",0,"detail"],"set":"已等待 3 秒"},{"path":["items",1,"detail"],"set":"已等待 3 秒，尚未收到数据"},{"path":["text"],"set":"正在连接 e2e-080726-b ×2 · 3 秒 · 共 4 项"}]},"w":1792609849815.761}
  #|{"in":{"id":10,"delta":[{"path":["items",0,"detail"],"set":"已等待 3 秒"},{"path":["items",1,"detail"],"set":"已等待 3 秒，尚未收到数据"},{"path":["text"],"set":"正在连接 e2e-080726-b ×2 · 3 秒 · 共 4 项"}]},"w":1792609849815.869}
  #|{"in":{"id":5,"delta":[{"path":["items",0,"detail"],"set":"已等待 4 秒"},{"path":["items",0,"text"],"set":"正在连接 e2e-080726-b ×3"},{"path":["items",1,"detail"],"set":"已等待 4 秒，尚未收到数据"},{"path":["text"],"set":"正在连接 e2e-080726-b ×3 · 4 秒 · 共 5 项"}]},"w":1792609850932.403}
  #|{"in":{"id":10,"delta":[{"path":["items",0,"detail"],"set":"已等待 4 秒"},{"path":["items",0,"text"],"set":"正在连接 e2e-080726-b ×3"},{"path":["items",1,"detail"],"set":"已等待 4 秒，尚未收到数据"},{"path":["text"],"set":"正在连接 e2e-080726-b ×3 · 4 秒 · 共 5 项"}]},"w":1792609850932.499}
  #|{"step":"now until 移除「e2e-080726-b」","w":1792609850983.738}
  #|{"step":"tap =移除 station","w":1792609850983.803}
  #|{"step":"tap =移除 station","acted":true,"w":1792609850983.842}
  #|{"out":{"id":29,"call":"workspace.removeStation","params":{"workspace":"01M5FXYS94SYCJ0PB9XS4BKV1W","station":"8eed7ed1fc389be23130b650fcc70c1f5863b8ee2d6bfe6a91a2d43f21900213","account":"alice"}},"w":1792609850999.398}
  #|{"step":"answered workspace.removeStation","w":1792609851001.255}
  #|{"in":{"id":21,"value":{"doing":[{"call":"workspace.removeStation","params":{"workspace":"01M5FXYS94SYCJ0PB9XS4BKV1W","station":"8eed7ed1fc389be23130b650fcc70c1f5863b8ee2d6bfe6a91a2d43f21900213","account":"alice"},"since":1792609850999,"stage":"running"}]}},"w":1792609851065.761}
  #|{"in":{"id":10,"value":{"state":"slow","text":"正在连接 station · 3 秒 · 27 B/s","items":[{"state":"slow","text":"正在连接 station","detail":"已等待 3 秒"}]}},"w":1792609851065.794}
  #|{"in":{"id":4,"delta":[{"path":[0,"workspaces",0,"stations"],"set":1}]},"w":1792609851065.811}
  #|{"in":{"id":17,"delta":[{"path":["stations"],"set":[{"id":"2914835be3a565475e145ceb6539460dd59411548948b73ce83492a352591cca","name":"studio","emoji":null,"icon":null,"enrolled_at":1792609838,"enrolled_by":"alice","last_seen":1792609842,"version":"0.1.0","time":{"last_seen":{"past":true,"at":1792609842000,"ago":"刚刚","full":"10/22 03:10:42","until":"1 分钟内"}}}]}]},"w":1792609851065.828}
  #|{"in":{"id":5,"value":{"state":"slow","text":"正在连接 station · Dev · 3 秒 · 27 B/s","items":[{"state":"slow","text":"正在连接 station · Dev","detail":"已等待 3 秒"}]}},"w":1792609851065.844}
  #|{"in":{"id":7,"delta":[{"path":["glyph","connecting"],"set":0},{"path":["glyph","dim"],"set":0},{"path":["glyph","label"],"set":"1 台 station，1 台在线"},{"path":["glyph","summary"],"set":"studio"},{"path":["loading"],"set":false},{"path":["stations"],"set":[{"station":"01M5FXYS94SYCJ0PB9XS4BKV1W/2914835be3a565475e145ceb6539460dd59411548948b73ce83492a352591cca","id":"2914835be3a565475e145ceb6539460dd59411548948b73ce83492a352591cca","name":"studio","state":"online"}]}]},"w":1792609851065.856}
  #|{"in":{"id":18,"value":[{"station":"01M5FXYS94SYCJ0PB9XS4BKV1W/2914835be3a565475e145ceb6539460dd59411548948b73ce83492a352591cca","id":"2914835be3a565475e145ceb6539460dd59411548948b73ce83492a352591cca","name":"studio","summary":"空闲 · Apple M4 · 16 GB · macOS 27.0.1","face":"idle","line":"Apple M4","online":true,"reconnecting":false,"lastSeen":1792609842,"version":"0.1.0","link":{"state":"online"},"runtimes":[{"runtime":"claude","models":["claude-sonnet-5-5"]}],"models":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792609842309,"time":{"checkedAt":{"at":1792609842309,"ago":"刚刚","full":"10/22 03:10:42","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"overview":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null,"summaryText":"最近 7 天检查了 0 个 chat","changeText":null}},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","email":"alice@example.test","name":"Name of alice","sub":"alice","role":"owner","workspace":"01M5FXYS94SYCJ0PB9XS4BKV1W","device":"8dceb5f45193d2326c347c38c704ee6b11eb393f90d93fc95f65dd4b18f09433"},"connects":[],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792609842184,"time":{"checkedAt":{"at":1792609842184,"ago":"刚刚","full":"10/22 03:10:42","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792609842309,"time":{"checkedAt":{"at":1792609842309,"ago":"刚刚","full":"10/22 03:10:42","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"modelsReading":false,"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]}],"processes":[],"counts":{"sessions":1,"running":0,"warm":1},"mesh":{"state":"running","origin":"http://127.0.0.1:18787","station":"2914835be3a565475e145ceb6539460dd59411548948b73ce83492a352591cca","workspace":"Dev","workspaceId":"01M5FXYS94SYCJ0PB9XS4BKV1W","name":"studio"},"slackUsers":[],"slackTeams":[],"slackApps":[],"feishuRegistrations":[],"disk":{"freeBytes":28398657536,"totalBytes":245107195904},"logins":[],"machineLogins":[],"sharing":true,"consoleSignIn":true,"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"google","name":"Google Gemini","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xai","name":"xAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"mistral","name":"Mistral","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"deepseek","name":"DeepSeek","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen","name":"Qwen","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai","name":"Kimi","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"kimi-code","name":"Kimi Code","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai","name":"Z.ai","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax","name":"MiniMax","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ant-ling","name":"Ant Ling","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"jev","name":"Jev","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen-cn","name":"Qwen (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"openrouter","name":"OpenRouter","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"opencode","name":"OpenCode Zen","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"groq","name":"Groq","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"together","name":"Together AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"fireworks","name":"Fireworks","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cerebras","name":"Cerebras","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"huggingface","name":"Hugging Face","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"nvidia","name":"NVIDIA","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"baseten","name":"Baseten","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ollama","name":"Ollama","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"custom","name":"Custom","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""}],"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792609839824},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.306","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792609839824},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-icon/apps/e2e-local/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792609839824},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-icon/apps/e2e-local/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792609839824},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","latest":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-icon/apps/e2e-local/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792609839824},{"id":"cursor","name":"Cursor","installed":false,"latest":"1.0.40","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792609839824},{"id":"devin","name":"Devin","installed":true,"version":"3000.11.92","latest":"3000.11.92","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-icon/apps/e2e-local/ember/station/test/fake/devin，不是用 Devin 的安装脚本装的，需在该机器上手动更新","state":"idle","checkedAt":1792609839824}],"processesText":"没有运行中的 agent 进程","agentEnv":[],"drive":{"roots":[],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false}},"betaOffered":false,"host":{"hostname":"3720-Mac-mini-1","os":"macOS 27.0.1","arch":"arm64","cpus":10,"cpuModel":"Apple M4","load":0.29,"cpuBusy":0.13,"uptimeSec":89205,"memory":{"totalBytes":17179869184,"usedBytes":10154082304,"swapUsedBytes":216793088},"disk":{"path":"/tmp/mbe2e-C/data","totalBytes":245107195904,"freeBytes":28400340992},"emberRssBytes":162839768,"checkedAt":1792609843939,"summary":"10 核 · 16 GB","line":"macOS 27.0.1 · 10 核 · 16 GB · 已运行 1 天","facts":["3720-Mac-mini-1","macOS 27.0.1","arm64 · 10 核","已运行 1 天 0 小时"],"meters":[{"label":"CPU","short":"CPU","percent":13,"left":87,"level":"ok","value":"13%","remaining":"空闲 87%","big":"87","unit":"%","title":"CPU 空闲","total":"负载 2.9","note":"负载 2.9 · Apple M4"},{"label":"内存","short":"内存","percent":59,"left":41,"level":"ok","value":"9.5 GB / 16.0 GB","remaining":"剩 6.5 G","big":"6.5","unit":"GB","title":"内存剩","total":"共 16 GB","note":"swap 0.2 GB"},{"label":"磁盘","short":"磁盘","percent":88,"left":12,"level":"amber","value":"剩余 26.4 GB / 228 GB","remaining":"剩 26.4 G","big":"26.4","unit":"GB","title":"磁盘剩","total":"共 228 GB"}],"identity":"Apple M4 · 16 GB · macOS 27.0.1","details":[{"label":"主机名","value":"3720-Mac-mini-1"},{"label":"芯片","value":"Apple M4 · 10 核 · arm64"},{"label":"已运行","value":"1 天 0 小时"},{"label":"still.fail","value":"进程占用 155 MB"}],"usage":"内存 9.5 GB / 16.0 GB · 磁盘 剩余 26.4 GB / 228 GB","emberText":"still.fail 155 MB"},"way":{"path":"直连","via":"direct"},"time":{"lastSeen":{"at":1792609842000,"ago":"刚刚","full":"10/22 03:10:42","until":"1 分钟内","past":true}},"joined":false}]},"w":1792609851066.06}
  #|{"in":{"id":19,"delta":[{"path":["wait","empty"],"set":true},{"path":["wait","reading"],"set":false},{"path":["wait","text"],"set":null}]},"w":1792609851066.197}
  #|{"in":{"id":27,"value":{"manages":false,"loading":false,"canJoin":false,"workspaces":[]}},"w":1792609851066.212}
  #|{"in":{"id":29,"ok":{"ok":true}},"w":1792609851066.217}
  #|{"step":"until 已移除 station","w":1792609851082.993}
  #|{"step":"hover =studio","w":1792609851083.005}
  #|{"step":"hover =studio","acted":true,"w":1792609851115.978}
  #|{"step":"wait 2600","w":1792609851133.172}
  #|{"in":{"id":21,"value":{"doing":[]}},"w":1792609851182.449}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792609851799.072}
  #|{"in":{"id":10,"value":{"items":[]}},"w":1792609851799.129}
  #|{"step":"now until =studio","w":1792609853749.838}
  #|{"step":"gone e2e-080726-b","w":1792609853749.887}
  #|{"step":"log do: second-down","w":1792609853749.907}
  #|{"step":"second-down"}
  #|{"step":"","w":1792609853749.938}
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
  #|{"textrec":{"ib":["bef2954d97ce1d9f",6508,64],"r":[40,40,40,40]}}
  #|{"textrec":{"ib":["1d51432b25a425eb",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"ib":["fdb526ba00f881f4",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["c8ac90bf691295f0",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["31d8ec32aedeae00",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["a7ccae3554fe46cf",3232,64],"r":[28,28,28,28]}}
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
  #|{"textrec":{"s":[16,600,0,"Station"],"r":[0,1,10.266256332397461,195,1,1,5.999713897705078,36,2,1,8.899068832397461,44,3,1,5.999713897705078,36,4,1,4.046333312988281,196,5,1,9.432537078857422,34,6,1,9.466253280639648,47]}}
  #|{"textrec":{"s":[17,400,0,"设置"],"r":[0,1,16.851167315175097,197,1,1,16.851167315175097,198]}}
  #|{"textrec":{"s":[16,700,0,"studio"],"r":[0,1,8.73046875,199,1,1,6.26953125,200,2,1,9.72265625,201,3,1,10.109375,202,4,1,4.28125,74,5,1,9.6015625,71]}}
  #|{"textrec":{"s":[13,400,0,"空闲 · Apple M4 · 16 GB · macOS 27.0.1"],"r":[0,1,12.898832684824903,203,1,1,12.898832684824903,204,2,1,3.580078125,-1,3,1,6.228545204222122,205,4,1,3.580078125,-1,5,1,8.68359375,206,6,1,7.8583984375,11,7,1,7.8583984375,11,8,1,3.211914062500007,76,9,1,7.3505859375,14,10,1,3.580078125,-1,11,1,11.2861328125,207,12,1,8.2900390625,208,13,1,3.580078125,-1,14,1,6.228545204222115,205,15,1,3.580078125,-1,16,1,5.9541015625,209,17,1,8.201171875,210,18,1,3.580078125,-1,19,1,9.62939453125,211,20,1,8.4677734375,212,21,1,3.580078125,-1,22,1,6.228545204222115,205,23,1,3.580078125,-1,24,1,11.2353515625,80,25,1,7.0966796875,12,26,1,7.1982421875,13,27,1,9.953125,213,28,1,8.20751953125,214,29,1,3.580078125,-1,30,1,7.76953125,215,31,1,6.626953125,216,32,1,2.8310546875,81,33,1,7.6044921875,217,34,1,3.3388671875,81,35,1,5.763671875,209]}}
  #|{"textrec":{"s":[13,400,0,"↑"],"r":[0,1,10.080078125,218]}}
  #|{"textrec":{"s":[13,500,0," "],"r":[0,1,3.4683494567871094,-1]}}
  #|{"textrec":{"m":[13,500,0],"r":[12.568359375,2.7421875,18,12.568359375,2.7421875,0]}}
  #|{"textrec":{"s":[13,400,0,"↓"],"r":[0,1,10.080078125,219]}}
  #|{"textrec":{"s":[13,400,0,"直连"],"r":[0,1,12.898832684824903,220,1,1,12.898832684824903,221]}}
  #|{"textrec":{"s":[13,400,0,"当前延迟 "],"r":[0,1,12.898832684824903,222,1,1,12.898832684824903,223,2,1,12.898832684824903,224,3,1,12.898832684824903,225,4,1,3.580078125,-1]}}
  #|{"textrec":{"s":[13,500,0,"0 ms"],"r":[0,1,8.373004913330078,226,1,1,3.4683494567871094,-1,2,1,11.530966997146606,227,3,1,6.933351516723633,228]}}
  #|{"textrec":{"s":[11,600,0,"磁盘"],"r":[0,1,10.93579766536965,229,1,1,10.93579766536965,230]}}
  #|{"textrec":{"m":[11,600,0],"r":[10.634765625,2.3203125,16,10.634765625,2.3203125,0]}}
  #|{"textrec":{"s":[11,600,0,"剩 26.4 G"],"r":[0,1,10.93579766536965,231,1,1,2.9949302673339844,-1,2,1,6.9786479473114,232,3,1,7.189909219741821,233,4,1,3.368730068206787,234,5,1,7.336179733276367,235,6,1,2.9949302673339844,-1,7,1,8.372097969055176,236]}}
  #|{"textrec":{"g":197,"r":[2000,0,19,18,-1,-15,0]}}
  #|{"textrec":{"g":198,"r":[2020,0,18,17,-1,-14,0]}}
  #|{"textrec":{"ib":["b7b1dc2c98725280",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"g":229,"r":[0,32,13,12,-1,-10,0]}}
  #|{"textrec":{"g":230,"r":[14,32,13,12,-1,-10,0]}}
  #|{"textrec":{"g":231,"r":[28,32,13,13,-1,-10,0]}}
  #|{"textrec":{"g":232,"r":[42,32,9,10,-1,-9,0]}}
  #|{"textrec":{"g":233,"r":[52,32,9,11,-1,-9,0]}}
  #|{"textrec":{"g":234,"r":[62,32,5,5,-1,-3,0]}}
  #|{"textrec":{"g":235,"r":[68,32,9,10,-1,-9,0]}}
  #|{"textrec":{"g":236,"r":[78,32,10,11,-1,-9,0]}}
  #|{"textrec":{"g":199,"r":[89,32,11,12,-1,-10,0]}}
  #|{"textrec":{"g":200,"r":[101,32,8,14,-1,-12,0]}}
  #|{"textrec":{"g":201,"r":[110,32,10,12,0,-10,0]}}
  #|{"textrec":{"g":202,"r":[121,32,12,15,-1,-13,0]}}
  #|{"textrec":{"g":203,"r":[134,32,14,14,-1,-12,0]}}
  #|{"textrec":{"g":204,"r":[149,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":205,"r":[163,32,4,5,1,-7,0]}}
  #|{"textrec":{"g":206,"r":[168,32,11,12,-1,-11,0]}}
  #|{"textrec":{"g":207,"r":[180,32,12,12,0,-11,0]}}
  #|{"textrec":{"g":208,"r":[193,32,10,12,-1,-11,0]}}
  #|{"textrec":{"g":209,"r":[204,32,7,12,-1,-11,0]}}
  #|{"textrec":{"g":210,"r":[212,32,10,13,-1,-11,0]}}
  #|{"textrec":{"g":211,"r":[223,32,11,13,-1,-11,0]}}
  #|{"textrec":{"g":212,"r":[235,32,9,12,0,-11,0]}}
  #|{"textrec":{"g":213,"r":[245,32,12,13,-1,-11,0]}}
  #|{"textrec":{"g":214,"r":[258,32,10,13,-1,-11,0]}}
  #|{"textrec":{"g":215,"r":[269,32,9,12,-1,-11,0]}}
  #|{"textrec":{"g":216,"r":[279,32,9,12,-1,-11,0]}}
  #|{"textrec":{"g":217,"r":[289,32,10,13,-1,-11,0]}}
  #|{"textrec":{"g":195,"r":[300,32,12,15,-1,-13,0]}}
  #|{"textrec":{"g":44,"r":[313,32,11,12,-1,-10,0]}}
  #|{"textrec":{"g":196,"r":[325,32,5,15,0,-14,0]}}
  #|{"textrec":{"g":47,"r":[331,32,10,11,0,-10,0]}}
  #|{"textrec":{"ib":["2bb63fc1d380f765",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"s":[17,700,0,"添加 station"],"r":[0,1,16.851167315175097,237,1,1,16.851167315175097,238,2,1,3.951171875,-1,3,1,9.176513671875,239,4,1,6.561767578125,240,5,1,9.591552734375,241,6,1,6.58251953125,240,7,1,4.44921875,242,8,1,10.10205078125,243,9,1,10.230712890625,244]}}
  #|{"textrec":{"m":[17,700,0],"r":[16.435546875,3.5859375,24,16.435546875,3.5859375,0]}}
  #|{"textrec":{"s":[14,400,0,"station 是一台运行 still.fail 的机器。为它命名，然后在该机器的终端中执行生成的命令，它会安装 still.fail 并加入。"],"r":[0,1,7.1435546875,245,1,1,4.9013671875,61,2,1,7.57421875,57,3,1,4.935546875,61,4,1,3.30859375,246,5,1,8.12109375,247,6,1,8.0185546875,60,7,1,3.787109375,-1,8,1,13.891050583657588,52,9,1,13.891050583657588,248,10,1,13.891050583657588,249,11,1,13.891050583657588,250,12,1,13.891050583657588,251,13,1,3.787109375,-1,14,1,7.143554687500014,245,15,1,4.9013671875,61,16,1,3.30859375,246,17,1,3.390625,252,18,1,3.390625,252,19,1,3.80078125,253,20,1,4.607421875,254,21,1,7.4716796875,57,22,1,3.30859375,246,23,1,3.390625,252,24,1,3.787109375,-1,25,1,13.891050583657602,56,26,1,13.891050583657602,255,27,1,13.891050583657602,256,28,1,14.081712062256798,257,29,1,13.891050583657574,258,30,1,13.891050583657602,259,31,1,13.891050583657602,260,32,1,13.891050583657602,261,33,1,14.081712062256827,50,34,1,13.891050583657602,262,35,1,13.891050583657602,263,36,1,13.891050583657602,189,37,1,13.891050583657602,264,38,1,13.891050583657602,255,39,1,13.891050583657602,256,40,1,13.891050583657602,56,41,1,13.891050583657602,265,42,1,13.891050583657602,266,43,1,13.891050583657602,267,44,1,13.891050583657602,268,45,1,13.891050583657602,251,46,1,13.891050583657602,269,47,1,13.891050583657602,270,48,1,13.891050583657602,56,49,1,13.891050583657602,260,50,1,13.891050583657602,271,51,1,14.08171206225677,50,52,1,13.891050583657602,259,53,1,13.891050583657602,272,54,1,13.891050583657602,273,55,1,13.891050583657602,274,56,1,3.787109375,-1,57,1,7.1435546875,245,58,1,4.9013671875,61,59,1,3.30859375,246,60,1,3.390625,252,61,1,3.390625,252,62,1,3.80078125,253,63,1,4.607421875,254,64,1,7.4716796875,57,65,1,3.30859375,246,66,1,3.390625,252,67,1,3.787109375,-1,68,1,13.891050583657602,275,69,1,13.891050583657602,276,70,1,13.891050583657602,277,71,1,7.08171206225677,257]}}
  #|{"textrec":{"s":[13,600,0,"名称"],"r":[0,1,12.898832684824903,278,1,1,12.898832684824903,279]}}
  #|{"textrec":{"m":[13,600,0],"r":[12.568359375,2.7421875,18,12.568359375,2.7421875,0]}}
  #|{"textrec":{"s":[14,600,0,"取消"],"r":[0,1,13.891050583657588,280,1,1,13.891050583657588,281]}}
  #|{"textrec":{"m":[14,600,0],"r":[13.53515625,2.953125,20,13.53515625,2.953125,0]}}
  #|{"textrec":{"s":[14,600,0,"生成命令"],"r":[0,1,13.891050583657588,282,1,1,13.891050583657588,283,2,1,13.891050583657588,284,3,1,13.891050583657588,285]}}
  #|{"textrec":{"g":237,"r":[342,32,19,18,-1,-15,0]}}
  #|{"textrec":{"g":238,"r":[362,32,18,18,-1,-15,0]}}
  #|{"textrec":{"g":239,"r":[381,32,11,13,-1,-11,0]}}
  #|{"textrec":{"g":240,"r":[393,32,9,15,-1,-13,0]}}
  #|{"textrec":{"g":241,"r":[403,32,11,13,-1,-11,0]}}
  #|{"textrec":{"g":242,"r":[415,32,5,16,0,-15,0]}}
  #|{"textrec":{"g":243,"r":[421,32,12,13,-1,-11,0]}}
  #|{"textrec":{"g":244,"r":[434,32,11,12,0,-11,0]}}
  #|{"textrec":{"g":245,"r":[446,32,9,11,-1,-9,0]}}
  #|{"textrec":{"g":246,"r":[456,32,5,13,-1,-12,0]}}
  #|{"textrec":{"g":247,"r":[462,32,10,11,-1,-9,0]}}
  #|{"textrec":{"g":248,"r":[473,32,15,4,-1,-7,0]}}
  #|{"textrec":{"g":249,"r":[489,32,14,16,0,-13,0]}}
  #|{"textrec":{"g":250,"r":[504,32,16,15,-1,-12,0]}}
  #|{"textrec":{"g":251,"r":[521,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":252,"r":[537,32,4,13,0,-12,0]}}
  #|{"textrec":{"g":253,"r":[542,32,4,5,0,-3,0]}}
  #|{"textrec":{"g":254,"r":[547,32,7,13,-1,-12,0]}}
  #|{"textrec":{"g":255,"r":[555,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":256,"r":[572,32,16,15,-1,-12,0]}}
  #|{"textrec":{"g":257,"r":[589,32,6,6,0,-3,0]}}
  #|{"textrec":{"g":258,"r":[596,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":259,"r":[612,32,14,15,0,-13,0]}}
  #|{"textrec":{"g":260,"r":[627,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":261,"r":[644,32,14,16,-1,-13,0]}}
  #|{"textrec":{"g":262,"r":[659,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":263,"r":[676,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":264,"r":[692,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":265,"r":[709,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":266,"r":[726,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":267,"r":[742,32,14,16,0,-13,0]}}
  #|{"textrec":{"g":268,"r":[757,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":269,"r":[774,32,15,15,-1,-13,0]}}
  #|{"textrec":{"g":270,"r":[790,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":271,"r":[807,32,16,15,-1,-12,0]}}
  #|{"textrec":{"g":272,"r":[824,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":273,"r":[841,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":274,"r":[857,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":275,"r":[874,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":276,"r":[890,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":277,"r":[906,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":278,"r":[923,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":279,"r":[938,32,15,15,-1,-12,0]}}
  #|{"textrec":{"s":[15,400,0,"例如机器名：studio、mac-mini"],"r":[0,1,14.883268482490273,286,1,1,14.883268482490273,287,2,1,14.883268482490273,132,3,1,14.883268482490273,288,4,1,14.88326848249028,289,5,1,15.08754863813229,290,6,1,7.58056640625,91,7,1,5.17822265625,101,8,1,8.51806640625,163,9,1,8.9794921875,291,10,1,3.4716796875,102,11,1,8.6279296875,88,12,1,13.58754863813229,292,13,1,12.8173828125,161,14,1,8.0419921875,93,15,1,8.1591796875,94,16,1,6.8408203125,293,17,1,12.8173828125,161,18,1,3.4716796875,102,19,1,8.51806640625,103,20,1,3.4716796875,102]}}
  #|{"textrec":{"g":286,"r":[954,32,16,17,-1,-14,0]}}
  #|{"textrec":{"g":287,"r":[971,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":288,"r":[988,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":289,"r":[1006,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":290,"r":[1022,32,5,10,1,-10,0]}}
  #|{"textrec":{"g":163,"r":[1028,32,9,11,0,-9,0]}}
  #|{"textrec":{"g":291,"r":[1038,32,10,15,-1,-13,0]}}
  #|{"textrec":{"g":292,"r":[1049,32,7,7,0,-4,0]}}
  #|{"textrec":{"g":161,"r":[1057,32,13,11,0,-10,0]}}
  #|{"textrec":{"g":293,"r":[1071,32,7,4,0,-6,0]}}
  #|{"textrec":{"g":280,"r":[1079,32,16,15,-1,-12,0]}}
  #|{"textrec":{"g":281,"r":[1096,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":282,"r":[1112,32,15,15,-1,-13,0]}}
  #|{"textrec":{"g":283,"r":[1128,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":284,"r":[1145,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":285,"r":[1162,32,16,16,-1,-13,0]}}
  #|{"textrec":{"s":[15,400,0,"e2e-080726-b"],"r":[0,1,8.3349609375,95,1,1,8.78173828125,294,2,1,8.29833984375,95,3,1,6.8408203125,293,4,1,9.2138671875,164,5,1,9.345703125,295,6,1,9.0673828125,164,7,1,8.1591796875,296,8,1,8.818359375,294,9,1,9.31640625,297,10,1,6.8408203125,293,11,1,8.9794921875,162]}}
  #|{"textrec":{"g":294,"r":[1179,32,10,13,0,-12,0]}}
  #|{"textrec":{"g":164,"r":[1190,32,11,14,-1,-12,0]}}
  #|{"textrec":{"g":295,"r":[1202,32,11,14,-1,-12,0]}}
  #|{"textrec":{"g":296,"r":[1214,32,10,13,-1,-12,0]}}
  #|{"textrec":{"g":297,"r":[1225,32,11,14,-1,-12,0]}}
  #|{"textrec":{"g":162,"r":[1237,32,10,15,0,-13,0]}}
  #|{"textrec":{"s":[14,400,0,"在该机器的终端中执行："],"r":[0,1,13.891050583657588,189,1,1,13.891050583657588,264,2,1,13.891050583657588,255,3,1,13.891050583657588,256,4,1,13.891050583657588,56,5,1,13.891050583657588,265,6,1,13.891050583657588,266,7,1,13.891050583657588,267,8,1,13.891050583657588,268,9,1,13.891050583657588,251,10,1,7.081712062256798,298]}}
  #|{"textrec":{"m":[12,400,0],"r":[11.6015625,2.53125,17,11.6015625,2.53125,0]}}
  #|{"textrec":{"s":[12,400,2,"curl -fsSL http://127.0.0.1:18787/install.sh | sh -s -- oX6CBJyoi2UGrQql0oTdOshjiCZsq8h5s743pLdmOrE"],"r":[0,1,7.2,299,1,1,7.2,300,2,1,7.2,301,3,1,7.2,302,4,1,7.2,-1,5,1,7.2,303,6,1,7.2,304,7,1,7.2,305,8,1,7.2,306,9,1,7.2,307,10,1,7.2,-1,11,1,7.2,308,12,1,7.2,309,13,1,7.2,309,14,1,7.2,310,15,1,7.2,311,16,1,7.2,312,17,1,7.2,312,18,1,7.2,313,19,1,7.2,314,20,1,7.2,315,21,1,7.2,316,22,1,7.2,317,23,1,7.2,316,24,1,7.2,317,25,1,7.2,316,26,1,7.2,313,27,1,7.2,311,28,1,7.2,313,29,1,7.2,318,30,1,7.2,315,31,1,7.2,318,32,1,7.2,315,33,1,7.2,312,34,1,7.2,319,35,1,7.2,320,36,1,7.2,305,37,1,7.2,309,38,1,7.2,321,39,1,7.2,302,40,1,7.2,302,41,1,7.2,316,42,1,7.2,305,43,1,7.2,308,44,1,7.2,-1,45,1,7.2,322,46,1,7.2,-1,47,1,7.2,305,48,1,7.2,308,49,1,7.2,-1,50,1,7.2,303,51,1,7.2,305,52,1,7.2,-1,53,1,7.2,303,54,1,7.2,303,55,1,7.2,-1,56,1,7.2,323,57,1,7.2,324,58,1,7.2,325,59,1,7.2,326,60,1,7.2,327,61,1,7.2,328,62,1,7.2,329,63,1,7.2,323,64,1,7.2,319,65,1,7.2,314,66,1,7.2,330,67,1,7.2,331,68,1,7.2,301,69,1,7.2,332,70,1,7.2,333,71,1,7.2,302,72,1,7.2,317,73,1,7.2,323,74,1,7.2,334,75,1,7.2,335,76,1,7.2,336,77,1,7.2,305,78,1,7.2,308,79,1,7.2,337,80,1,7.2,319,81,1,7.2,326,82,1,7.2,338,83,1,7.2,305,84,1,7.2,333,85,1,7.2,318,86,1,7.2,308,87,1,7.2,339,88,1,7.2,305,89,1,7.2,315,90,1,7.2,340,91,1,7.2,341,92,1,7.2,310,93,1,7.2,307,94,1,7.2,335,95,1,7.2,342,96,1,7.2,336,97,1,7.2,301,98,1,7.2,343]}}
  #|{"textrec":{"m":[12,400,2],"r":[12.24005126953125,3.60003662109375,17,12.720025777816772,4.080008268356323,0]}}
  #|{"textrec":{"s":[13,400,0,"支持 macOS（Apple 芯片）和 Linux，Windows 需在 WSL 中运行；已安装 still.fail 的机器也使用此命令。它会安装 still.fail、加入此 workspace，并在后台持续运行。加入后，在其 Station 页添加 Profile。"],"r":[0,1,12.898832684824903,344,1,1,12.898832684824903,345,2,1,3.580078125,-1,3,1,11.2353515625,80,4,1,7.0966796875,12,5,1,7.1982421875,13,6,1,9.953125,213,7,1,8.20751953125,214,8,1,9.271984435797663,346,9,1,8.68359375,206,10,1,7.8583984375,11,11,1,7.8583984375,11,12,1,3.2119140625,76,13,1,7.3505859375,14,14,1,3.580078125,-1,15,1,12.89883268482491,347,16,1,12.898832684824896,348,17,1,3.8317120622567984,349,18,1,19.398832684824896,350,19,1,3.580078125,-1,20,1,7.30615234375,351,21,1,3.1357421875,77,22,1,7.50927734375,352,23,1,7.50927734375,353,24,1,6.7412109375,79,25,1,11.775875486381324,354,26,1,12.5048828125,355,27,1,3.1357421875,77,28,1,7.50927734375,352,29,1,7.9091796875,356,30,1,7.477539062499972,7,31,1,9.76904296875,6,32,1,6.63330078125,10,33,1,3.580078125,-1,34,1,12.898832684824924,142,35,1,12.898832684824924,1,36,1,3.580078125,-1,37,1,12.5048828125,355,38,1,8.20751953125,214,39,1,7.30615234375,351,40,1,3.580078125,-1,41,1,12.898832684824924,357,42,1,12.898832684824924,358,43,1,12.898832684824924,359,44,1,13.075875486381335,360,45,1,12.898832684824924,361,46,1,12.898832684824924,362,47,1,12.898832684824924,363,48,1,3.580078125,-1,49,1,6.69677734375,10,50,1,4.61474609375,82,51,1,3.1357421875,77,52,1,3.2119140625,76,53,1,3.2119140625,76,54,1,3.5927734375,81,55,1,4.341796875,364,56,1,7.00146484375,12,57,1,3.1357421875,77,58,1,3.2119140625,76,59,1,3.580078125,-1,60,1,12.898832684824924,5,61,1,12.898832684824924,365,62,1,12.898832684824868,366,63,1,12.898832684824924,367,64,1,12.898832684824924,368,65,1,12.898832684824924,369,66,1,12.898832684824924,370,67,1,12.898832684824924,371,68,1,12.898832684824924,372,69,1,13.075875486381278,373,70,1,12.898832684824924,374,71,1,12.898832684824924,375,72,1,12.898832684824924,362,73,1,12.898832684824924,363,74,1,3.580078125,-1,75,1,6.69677734375,10,76,1,4.61474609375,82,77,1,3.1357421875,77,78,1,3.2119140625,76,79,1,3.2119140625,76,80,1,3.5927734375,81,81,1,4.341796875,364,82,1,7.00146484375,12,83,1,3.1357421875,77,84,1,3.2119140625,76,85,1,13.075875486381278,141,86,1,12.898832684824924,376,87,1,12.898832684824924,377,88,1,12.898832684824924,370,89,1,3.580078125,-1,90,1,9.8642578125,6,91,1,7.4775390625,7,92,1,4.875,8,93,1,6.85546875,9,94,1,6.6015625,10,95,1,7.8583984375,11,96,1,7.0966796875,12,97,1,7.1982421875,13,98,1,7.3505859375,14,99,1,13.075875486381278,354,100,1,12.898832684824924,378,101,1,12.898832684824924,1,102,1,12.898832684824924,379,103,1,12.898832684824924,380,104,1,12.898832684824924,345,105,1,12.898832684824924,381,106,1,12.898832684824924,358,107,1,12.898832684824924,359,108,1,13.075875486381278,373,109,1,12.898832684824924,376,110,1,12.898832684824924,377,111,1,12.898832684824924,379,112,1,13.075875486381278,354,113,1,12.898832684824924,1,114,1,12.898832684824924,382,115,1,3.580078125,-1,116,1,8.20751953125,214,117,1,4.646484375,82,118,1,7.0966796875,12,119,1,4.646484375,82,120,1,3.1357421875,77,121,1,7.6044921875,7,122,1,7.50927734375,352,123,1,3.580078125,-1,124,1,12.89883268482481,383,125,1,12.89883268482481,384,126,1,12.89883268482481,376,127,1,3.580078125,-1,128,1,8.18212890625,385,129,1,4.77978515625,8,130,1,7.50927734375,7,131,1,4.62744140625,364,132,1,3.1357421875,77,133,1,3.2119140625,76,134,1,7.3505859375,14,135,1,6.575875486381392,373]}}
  #|{"textrec":{"s":[13,400,0,"等待机器加入… 执行命令后将自动继续 · 命令 1 小时内有效"],"r":[0,1,12.898832684824903,386,1,1,12.898832684824903,387,2,1,12.898832684824903,365,3,1,12.898832684824903,366,4,1,12.898832684824896,376,5,1,12.898832684824896,377,6,1,10.384765625,388,7,1,3.580078125,-1,8,1,12.898832684824896,389,9,1,12.898832684824896,359,10,1,12.898832684824896,371,11,1,12.898832684824896,372,12,1,12.898832684824896,379,13,1,12.898832684824896,390,14,1,12.898832684824896,391,15,1,12.898832684824896,392,16,1,12.898832684824896,393,17,1,12.898832684824896,381,18,1,3.580078125,-1,19,1,6.228545204222115,205,20,1,3.580078125,-1,21,1,12.898832684824896,371,22,1,12.898832684824896,372,23,1,3.580078125,-1,24,1,5.9541015625,209,25,1,3.580078125,-1,26,1,12.898832684824924,394,27,1,12.898832684824924,153,28,1,12.898832684824924,395,29,1,12.898832684824924,149,30,1,12.898832684824924,396]}}
  #|{"textrec":{"g":298,"r":[1248,32,5,10,1,-10,0]}}
  #|{"textrec":{"g":299,"r":[1254,32,8,10,0,-8,0]}}
  #|{"textrec":{"g":300,"r":[1263,32,8,10,0,-8,0]}}
  #|{"textrec":{"g":301,"r":[1272,32,8,9,0,-8,0]}}
  #|{"textrec":{"g":302,"r":[1281,32,9,11,-1,-10,0]}}
  #|{"textrec":{"g":303,"r":[1291,32,7,4,0,-6,0]}}
  #|{"textrec":{"g":304,"r":[1299,32,9,11,-1,-10,0]}}
  #|{"textrec":{"g":305,"r":[1309,32,8,10,0,-8,0]}}
  #|{"textrec":{"g":306,"r":[1318,32,9,12,-1,-10,0]}}
  #|{"textrec":{"g":307,"r":[1328,32,8,11,0,-10,0]}}
  #|{"textrec":{"g":308,"r":[1337,32,8,11,0,-10,0]}}
  #|{"textrec":{"g":309,"r":[1346,32,9,11,-1,-10,0]}}
  #|{"textrec":{"g":310,"r":[1356,32,8,12,0,-8,0]}}
  #|{"textrec":{"g":311,"r":[1365,32,5,10,1,-8,0]}}
  #|{"textrec":{"g":312,"r":[1371,32,9,14,-1,-11,0]}}
  #|{"textrec":{"g":313,"r":[1381,32,8,11,0,-10,0]}}
  #|{"textrec":{"g":314,"r":[1390,32,9,11,-1,-10,0]}}
  #|{"textrec":{"g":315,"r":[1400,32,9,11,-1,-10,0]}}
  #|{"textrec":{"g":316,"r":[1410,32,5,5,1,-3,0]}}
  #|{"textrec":{"g":317,"r":[1416,32,9,12,-1,-10,0]}}
  #|{"textrec":{"g":318,"r":[1426,32,9,12,-1,-10,0]}}
  #|{"textrec":{"g":319,"r":[1436,32,8,12,0,-11,0]}}
  #|{"textrec":{"g":320,"r":[1445,32,8,9,0,-8,0]}}
  #|{"textrec":{"g":321,"r":[1454,32,9,10,-1,-8,0]}}
  #|{"textrec":{"g":322,"r":[1464,32,4,14,2,-11,0]}}
  #|{"textrec":{"g":323,"r":[1469,32,8,10,0,-8,0]}}
  #|{"textrec":{"g":324,"r":[1478,32,9,11,-1,-10,0]}}
  #|{"textrec":{"g":325,"r":[1488,32,9,12,-1,-10,0]}}
  #|{"textrec":{"g":326,"r":[1498,32,8,12,0,-10,0]}}
  #|{"textrec":{"g":327,"r":[1507,32,8,11,0,-10,0]}}
  #|{"textrec":{"g":328,"r":[1516,32,8,12,-1,-10,0]}}
  #|{"textrec":{"g":329,"r":[1525,32,9,12,-1,-8,0]}}
  #|{"textrec":{"g":330,"r":[1535,32,8,12,0,-10,0]}}
  #|{"textrec":{"g":331,"r":[1544,32,8,12,0,-10,0]}}
  #|{"textrec":{"g":332,"r":[1553,32,9,14,-1,-10,0]}}
  #|{"textrec":{"g":333,"r":[1563,32,8,12,0,-8,0]}}
  #|{"textrec":{"g":334,"r":[1572,32,9,11,-1,-10,0]}}
  #|{"textrec":{"g":335,"r":[1582,32,8,12,0,-10,0]}}
  #|{"textrec":{"g":336,"r":[1591,32,8,12,0,-10,0]}}
  #|{"textrec":{"g":337,"r":[1600,32,7,15,0,-11,0]}}
  #|{"textrec":{"g":338,"r":[1608,32,8,11,0,-10,0]}}
  #|{"textrec":{"g":339,"r":[1617,32,9,12,-1,-10,0]}}
  #|{"textrec":{"g":340,"r":[1627,32,8,11,-1,-10,0]}}
  #|{"textrec":{"g":341,"r":[1636,32,9,12,-1,-10,0]}}
  #|{"textrec":{"g":342,"r":[1646,32,9,9,-1,-8,0]}}
  #|{"textrec":{"g":343,"r":[1656,32,8,11,0,-10,0]}}
  #|{"textrec":{"g":344,"r":[1665,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":345,"r":[1681,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":346,"r":[1697,32,5,15,4.033333333333333,-12,0]}}
  #|{"textrec":{"g":347,"r":[1703,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":348,"r":[1719,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":349,"r":[1734,32,6,15,-1,-12,0]}}
  #|{"textrec":{"g":350,"r":[1741,32,14,15,5.5,-12,0]}}
  #|{"textrec":{"g":351,"r":[1756,32,8,12,0,-11,0]}}
  #|{"textrec":{"g":352,"r":[1765,32,8,9,0,-8,0]}}
  #|{"textrec":{"g":353,"r":[1774,32,9,10,-1,-8,0]}}
  #|{"textrec":{"g":354,"r":[1784,32,5,7,0,-3,0]}}
  #|{"textrec":{"g":355,"r":[1790,32,15,12,-1,-11,0]}}
  #|{"textrec":{"g":356,"r":[1806,32,9,13,-1,-11,0]}}
  #|{"textrec":{"g":7,"r":[1816,32,9,10,-1,-8,0]}}
  #|{"textrec":{"g":6,"r":[1826,32,12,9,-1,-8,0]}}
  #|{"textrec":{"g":142,"r":[1839,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":1,"r":[1854,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":357,"r":[1869,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":358,"r":[1883,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":359,"r":[1899,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":360,"r":[1915,32,5,11,1,-9,0]}}
  #|{"textrec":{"g":361,"r":[1921,32,13,13,0,-11,0]}}
  #|{"textrec":{"g":362,"r":[1935,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":363,"r":[1950,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":364,"r":[1966,32,7,12,-1,-11,0]}}
  #|{"textrec":{"g":5,"r":[1974,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":365,"r":[1988,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":366,"r":[2004,32,15,14,-1,-11,0]}}
  #|{"textrec":{"g":367,"r":[2020,32,15,14,-1,-12,0]}}
  #|{"textrec":{"g":368,"r":[0,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":369,"r":[16,51,14,14,-1,-11,0]}}
  #|{"textrec":{"g":370,"r":[31,51,15,14,-1,-12,0]}}
  #|{"textrec":{"g":371,"r":[47,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":372,"r":[63,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":373,"r":[79,51,6,6,0,-3,0]}}
  #|{"textrec":{"g":374,"r":[86,51,14,14,-1,-12,0]}}
  #|{"textrec":{"g":375,"r":[101,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":141,"r":[117,51,6,6,0,-3,0]}}
  #|{"textrec":{"g":376,"r":[124,51,14,15,-1,-12,0]}}
  #|{"textrec":{"g":377,"r":[139,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":8,"r":[155,51,6,9,0,-8,0]}}
  #|{"textrec":{"g":9,"r":[162,51,8,12,0,-11,0]}}
  #|{"textrec":{"g":378,"r":[171,51,14,15,-1,-12,0]}}
  #|{"textrec":{"g":379,"r":[186,51,14,15,-1,-12,0]}}
  #|{"textrec":{"g":380,"r":[201,51,13,15,0,-12,0]}}
  #|{"textrec":{"g":381,"r":[215,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":382,"r":[231,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":383,"r":[247,51,14,14,-1,-11,0]}}
  #|{"textrec":{"g":384,"r":[262,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":385,"r":[278,51,9,12,0,-11,0]}}
  #|{"textrec":{"g":386,"r":[288,51,14,15,-1,-12,0]}}
  #|{"textrec":{"g":387,"r":[303,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":388,"r":[319,51,11,5,0,-3,0]}}
  #|{"textrec":{"g":389,"r":[331,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":390,"r":[347,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":391,"r":[363,51,11,15,1,-12,0]}}
  #|{"textrec":{"g":392,"r":[375,51,14,15,-1,-12,0]}}
  #|{"textrec":{"g":393,"r":[390,51,15,14,-1,-12,0]}}
  #|{"textrec":{"g":394,"r":[406,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":153,"r":[422,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":395,"r":[438,51,13,15,0,-12,0]}}
  #|{"textrec":{"g":149,"r":[452,51,14,15,-1,-12,0]}}
  #|{"textrec":{"g":396,"r":[467,51,15,15,-1,-12,0]}}
  #|{"textrec":{"ib":["b9bedad57f2a5f13",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"s":[12,400,0,"正在重新连接"],"r":[0,1,11.918287937743191,397,1,1,11.918287937743191,398,2,1,11.918287937743195,399,3,1,11.918287937743187,400,4,1,11.918287937743187,401,5,1,11.918287937743187,402]}}
  #|{"textrec":{"s":[16,700,0,"e2e-080726-b"],"r":[0,1,9.30078125,70,1,1,9.95703125,403,2,1,9.28125,70,3,1,7.4375,404,4,1,10.640625,405,5,1,10.75,406,6,1,10.4453125,405,7,1,9.203125,407,8,1,9.9765625,403,9,1,10.625,408,10,1,7.4375,404,11,1,10.109375,409]}}
  #|{"textrec":{"s":[13,400,0,"正在连接"],"r":[0,1,12.898832684824903,0,1,1,12.898832684824903,1,2,1,12.898832684824903,221,3,1,12.898832684824903,410]}}
  #|{"textrec":{"s":[14,400,0,"「e2e-080726-b」已加入，现在可以打开"],"r":[0,1,7.399481193255512,411,1,1,7.847656249999999,59,2,1,8.2646484375,126,3,1,7.8134765625,59,4,1,6.453125,412,5,1,8.66796875,184,6,1,8.791015625,193,7,1,8.53125,184,8,1,7.68359375,413,9,1,8.298828125,126,10,1,8.763671875,414,11,1,6.453125,412,12,1,8.44921875,415,13,1,4.793774319066145,416,14,1,20.891050583657574,417,15,1,13.891050583657602,276,16,1,13.891050583657602,277,17,1,14.081712062256798,50,18,1,13.891050583657574,418,19,1,13.891050583657602,189,20,1,13.891050583657602,419,21,1,13.891050583657602,420,22,1,13.891050583657602,421,23,1,13.891050583657602,97]}}
  #|{"textrec":{"s":[14,600,0,"完成"],"r":[0,1,13.891050583657588,422,1,1,13.891050583657588,283]}}
  #|{"textrec":{"g":403,"r":[483,51,11,14,0,-13,0]}}
  #|{"textrec":{"g":404,"r":[495,51,8,5,0,-7,0]}}
  #|{"textrec":{"g":405,"r":[504,51,11,15,0,-13,0]}}
  #|{"textrec":{"g":406,"r":[516,51,13,15,-1,-13,0]}}
  #|{"textrec":{"g":407,"r":[530,51,11,14,-1,-13,0]}}
  #|{"textrec":{"g":408,"r":[542,51,12,15,-1,-13,0]}}
  #|{"textrec":{"g":409,"r":[555,51,11,15,0,-13,0]}}
  #|{"textrec":{"g":0,"r":[567,51,14,13,-1,-11,0]}}
  #|{"textrec":{"g":221,"r":[582,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":410,"r":[598,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":397,"r":[614,51,14,12,-1,-10,0]}}
  #|{"textrec":{"g":398,"r":[629,51,14,14,-1,-11,0]}}
  #|{"textrec":{"g":399,"r":[644,51,14,13,-1,-11,0]}}
  #|{"textrec":{"g":400,"r":[659,51,14,14,-1,-11,0]}}
  #|{"textrec":{"g":401,"r":[674,51,14,14,-1,-11,0]}}
  #|{"textrec":{"g":402,"r":[689,51,14,14,-1,-11,0]}}
  #|{"textrec":{"g":411,"r":[704,51,7,12,1,-13,0]}}
  #|{"textrec":{"g":412,"r":[712,51,7,4,0,-6,0]}}
  #|{"textrec":{"g":413,"r":[720,51,10,12,-1,-11,0]}}
  #|{"textrec":{"g":414,"r":[731,51,11,14,-1,-12,0]}}
  #|{"textrec":{"g":415,"r":[743,51,9,14,0,-12,0]}}
  #|{"textrec":{"g":416,"r":[753,51,7,11,-1,-8,0]}}
  #|{"textrec":{"g":417,"r":[761,51,14,14,7,-12,0]}}
  #|{"textrec":{"g":418,"r":[776,51,16,15,-1,-12,0]}}
  #|{"textrec":{"g":419,"r":[793,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":420,"r":[809,51,15,16,0,-13,0]}}
  #|{"textrec":{"g":421,"r":[825,51,15,16,-1,-13,0]}}
  #|{"textrec":{"g":422,"r":[841,51,16,16,-1,-13,0]}}
  #|{"textrec":{"ib":["db8e2edd568ad1fd",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"s":[16,600,0,"e2e-080726-b"],"r":[0,1,9.127458572387695,46,1,1,9.717817306518555,423,2,1,9.100765228271484,46,3,1,7.363014221191406,424,4,1,10.31976318359375,425,5,1,10.440597534179688,426,6,1,10.138774871826172,425,7,1,8.996856689453125,427,8,1,9.744510650634766,423,9,1,10.3499755859375,428,10,1,7.363014221191406,424,11,1,9.891647338867188,429]}}
  #|{"textrec":{"s":[17,400,0,"Station"],"r":[0,1,10.40087890625,430,1,1,5.744140625,431,2,1,8.9482421875,432,3,1,5.744140625,431,4,1,3.7685546875,433,5,1,9.6123046875,434,6,1,9.48779296875,435]}}
  #|{"textrec":{"s":[15,600,0,"在此 station 上"],"r":[0,1,14.883268482490273,436,1,1,14.883268482490273,117,2,1,3.761730194091797,-1,3,1,8.000344634056091,437,4,1,5.658300518989563,438,5,1,8.40147078037262,439,6,1,5.683325529098511,438,7,1,3.8520312309265137,440,8,1,8.901597261428833,441,9,1,8.93320620059967,180,10,1,3.761730194091797,-1,11,1,14.883268482490266,442]}}
  #|{"textrec":{"s":[15,400,0,"共享调试"],"r":[0,1,14.883268482490273,443,1,1,14.883268482490273,444,2,1,14.883268482490273,445,3,1,14.883268482490273,446]}}
  #|{"textrec":{"g":430,"r":[858,51,12,16,-1,-14,0]}}
  #|{"textrec":{"g":431,"r":[871,51,8,15,-1,-13,0]}}
  #|{"textrec":{"g":432,"r":[880,51,11,13,-1,-11,0]}}
  #|{"textrec":{"g":433,"r":[892,51,5,15,0,-14,0]}}
  #|{"textrec":{"g":434,"r":[898,51,12,13,-1,-11,0]}}
  #|{"textrec":{"g":435,"r":[911,51,10,12,0,-11,0]}}
  #|{"textrec":{"g":436,"r":[922,51,16,17,-1,-14,0]}}
  #|{"textrec":{"g":437,"r":[939,51,10,12,-1,-10,0]}}
  #|{"textrec":{"g":438,"r":[950,51,8,13,-1,-11,0]}}
  #|{"textrec":{"g":439,"r":[959,51,10,12,-1,-10,0]}}
  #|{"textrec":{"g":440,"r":[970,51,6,14,-1,-13,0]}}
  #|{"textrec":{"g":441,"r":[977,51,11,12,-1,-10,0]}}
  #|{"textrec":{"g":442,"r":[989,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":443,"r":[1006,51,16,17,-1,-14,0]}}
  #|{"textrec":{"g":444,"r":[1023,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":445,"r":[1040,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":446,"r":[1057,51,17,16,-1,-13,0]}}
  #|{"textrec":{"g":46,"r":[1075,51,11,12,-1,-10,0]}}
  #|{"textrec":{"g":423,"r":[1087,51,11,14,0,-13,0]}}
  #|{"textrec":{"g":424,"r":[1099,51,8,5,0,-7,0]}}
  #|{"textrec":{"g":425,"r":[1108,51,11,15,0,-13,0]}}
  #|{"textrec":{"g":426,"r":[1120,51,12,15,-1,-13,0]}}
  #|{"textrec":{"g":427,"r":[1133,51,11,14,-1,-13,0]}}
  #|{"textrec":{"g":428,"r":[1145,51,12,15,-1,-13,0]}}
  #|{"textrec":{"g":429,"r":[1158,51,11,15,0,-13,0]}}
  #|{"textrec":{"ib":["ddfdc2820df8a676",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"s":[17,700,0,"e2e-080726-b"],"r":[0,1,9.782470703125,447,1,1,10.479736328125,448,2,1,9.76171875,447,3,1,7.802734375,449,4,1,11.2060546875,450,5,1,11.322265625,451,6,1,10.99853515625,450,7,1,9.6787109375,452,8,1,10.50048828125,448,9,1,11.189453125,453,10,1,7.802734375,449,11,1,10.6416015625,454]}}
  #|{"textrec":{"s":[15,400,0,"重命名"],"r":[0,1,14.883268482490273,455,1,1,14.883268482490273,456,2,1,14.883268482490273,289]}}
  #|{"textrec":{"s":[15,400,0,"图标"],"r":[0,1,14.883268482490273,457,1,1,14.883268482490273,458]}}
  #|{"textrec":{"s":[15,400,0,"从 workspace 移除"],"r":[0,1,14.883268482490273,459,1,1,3.984375,-1,2,1,11.2353515625,460,3,1,8.4814453125,88,4,1,5.478515625,89,5,1,7.763671875,90,6,1,7.470703125,91,7,1,8.920898437500007,92,8,1,8.0419921875,93,9,1,8.1591796875,94,10,1,8.3349609375,95,11,1,3.984375,-1,12,1,14.88326848249028,461,13,1,14.88326848249028,462]}}
  #|{"textrec":{"g":447,"r":[1170,51,12,13,-1,-11,0]}}
  #|{"textrec":{"g":448,"r":[1183,51,11,15,0,-14,0]}}
  #|{"textrec":{"g":449,"r":[1195,51,8,5,0,-7,0]}}
  #|{"textrec":{"g":450,"r":[1204,51,12,16,0,-14,0]}}
  #|{"textrec":{"g":451,"r":[1217,51,12,16,0,-14,0]}}
  #|{"textrec":{"g":452,"r":[1230,51,12,14,-1,-13,0]}}
  #|{"textrec":{"g":453,"r":[1243,51,12,16,0,-14,0]}}
  #|{"textrec":{"g":454,"r":[1256,51,12,16,0,-14,0]}}
  #|{"textrec":{"g":455,"r":[1269,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":456,"r":[1286,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":457,"r":[1303,51,15,16,0,-13,0]}}
  #|{"textrec":{"g":458,"r":[1319,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":459,"r":[1336,51,17,16,-1,-13,0]}}
  #|{"textrec":{"g":460,"r":[1354,51,14,10,-1,-9,0]}}
  #|{"textrec":{"g":461,"r":[1369,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":462,"r":[1386,51,16,16,0,-13,0]}}
  #|{"textrec":{"s":[17,700,0,"移除「e2e-080726-b」？"],"r":[0,1,16.851167315175097,463,1,1,25.351167315175097,464,2,1,6.366731517509727,465,3,1,9.782470703125,447,4,1,10.479736328125007,448,5,1,9.76171875,447,6,1,7.802734375,449,7,1,11.2060546875,450,8,1,11.322265625,451,9,1,10.99853515625,450,10,1,9.6787109375,452,11,1,10.50048828125,448,12,1,11.189453125,453,13,1,7.802734375,449,14,1,10.6416015625,454,15,1,8.194066147859928,466,16,1,8.582684824902714,467]}}
  #|{"textrec":{"s":[14,400,0,"它将断开与 still.fail cloud 的连接，成员无法再从这里访问它。该机器上的 still.fail 和数据不受影响，以后可以重新添加。"],"r":[0,1,13.891050583657588,259,1,1,13.891050583657588,468,2,1,13.891050583657588,469,3,1,13.891050583657588,97,4,1,13.891050583657588,470,5,1,3.787109375,-1,6,1,7.1435546875,245,7,1,4.9013671875,61,8,1,3.30859375,246,9,1,3.390625,252,10,1,3.390625,252,11,1,3.80078125,253,12,1,4.607421875,254,13,1,7.4716796875,57,14,1,3.30859375,246,15,1,3.390625,252,16,1,3.787109375,-1,17,1,7.683593750000014,471,18,1,3.390625,252,19,1,8.12109375,247,20,1,8.0185546875,472,21,1,8.44921875,473,22,1,3.787109375,-1,23,1,13.891050583657602,56,24,1,13.891050583657602,474,25,1,13.891050583657602,475,26,1,14.081712062256798,50,27,1,13.891050583657574,270,28,1,13.891050583657602,476,29,1,13.891050583657602,477,30,1,13.891050583657602,478,31,1,13.891050583657602,479,32,1,13.891050583657602,480,33,1,13.891050583657602,481,34,1,13.891050583657602,482,35,1,13.891050583657602,483,36,1,13.891050583657602,484,37,1,13.891050583657602,259,38,1,14.081712062256827,257,39,1,13.891050583657602,264,40,1,13.891050583657602,255,41,1,13.891050583657602,256,42,1,13.891050583657602,485,43,1,13.891050583657602,56,44,1,3.787109375,-1,45,1,7.1435546875,245,46,1,4.9013671875,61,47,1,3.30859375,246,48,1,3.390625,252,49,1,3.390625,252,50,1,3.80078125,253,51,1,4.607421875,254,52,1,7.4716796875,57,53,1,3.30859375,246,54,1,3.390625,252,55,1,3.787109375,-1,56,1,13.891050583657602,486,57,1,13.891050583657602,487,58,1,13.891050583657602,488,59,1,13.891050583657602,489,60,1,13.891050583657602,490,61,1,13.891050583657602,491,62,1,13.891050583657602,492,63,1,14.08171206225677,50,64,1,13.891050583657602,420,65,1,13.891050583657602,263,66,1,13.891050583657602,419,67,1,13.891050583657602,420,68,1,13.891050583657602,493,69,1,13.891050583657602,494,70,1,13.891050583657602,495,71,1,13.891050583657602,276,72,1,7.08171206225677,257]}}
  #|{"textrec":{"s":[14,600,0,"移除 station"],"r":[0,1,13.891050583657588,496,1,1,13.891050583657588,497,2,1,3.5793075561523438,-1,3,1,7.5353477001190186,498,4,1,5.349439859390259,499,5,1,7.909732103347778,500,6,1,5.372796535491943,499,7,1,3.663588523864746,501,8,1,8.376516819000244,502,9,1,8.406018495559692,503]}}
  #|{"textrec":{"g":463,"r":[1403,51,18,18,-1,-15,0]}}
  #|{"textrec":{"g":464,"r":[1422,51,18,18,0,-15,0]}}
  #|{"textrec":{"g":465,"r":[1441,51,9,13,-1.8333333333333304,-15,0]}}
  #|{"textrec":{"g":466,"r":[1451,51,9,13,-1,-10,0]}}
  #|{"textrec":{"g":467,"r":[1461,51,10,16,-1,-14,0]}}
  #|{"textrec":{"g":468,"r":[1472,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":469,"r":[1489,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":470,"r":[1506,51,15,16,-1,-13,0]}}
  #|{"textrec":{"g":471,"r":[1522,51,10,11,-1,-9,0]}}
  #|{"textrec":{"g":472,"r":[1533,51,9,11,0,-9,0]}}
  #|{"textrec":{"g":473,"r":[1543,51,10,14,-1,-12,0]}}
  #|{"textrec":{"g":474,"r":[1554,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":475,"r":[1571,51,15,16,-1,-13,0]}}
  #|{"textrec":{"g":476,"r":[1587,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":477,"r":[1603,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":478,"r":[1619,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":479,"r":[1636,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":480,"r":[1652,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":481,"r":[1669,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":482,"r":[1686,51,15,14,-1,-12,0]}}
  #|{"textrec":{"g":483,"r":[1702,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":484,"r":[1719,51,14,16,0,-13,0]}}
  #|{"textrec":{"g":485,"r":[1734,51,15,15,-1,-13,0]}}
  #|{"textrec":{"g":486,"r":[1750,51,15,16,-1,-13,0]}}
  #|{"textrec":{"g":487,"r":[1766,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":488,"r":[1783,51,15,16,-1,-13,0]}}
  #|{"textrec":{"g":489,"r":[1799,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":490,"r":[1815,51,15,16,-1,-13,0]}}
  #|{"textrec":{"g":491,"r":[1831,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":492,"r":[1848,51,14,16,0,-13,0]}}
  #|{"textrec":{"g":493,"r":[1863,51,15,16,-1,-13,0]}}
  #|{"textrec":{"g":494,"r":[1879,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":495,"r":[1896,51,16,15,-1,-12,0]}}
  #|{"textrec":{"g":496,"r":[1913,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":497,"r":[1930,51,16,15,-1,-12,0]}}
  #|{"textrec":{"g":498,"r":[1947,51,10,11,-1,-9,0]}}
  #|{"textrec":{"g":499,"r":[1958,51,7,13,-1,-11,0]}}
  #|{"textrec":{"g":500,"r":[1966,51,10,11,-1,-9,0]}}
  #|{"textrec":{"g":501,"r":[1977,51,5,13,-1,-12,0]}}
  #|{"textrec":{"g":502,"r":[1983,51,10,11,-1,-9,0]}}
  #|{"textrec":{"g":503,"r":[1994,51,9,10,0,-9,0]}}
  #|{"textrec":{"s":[16,600,0,"8eed7ed1fc389be23130b650fcc70c1f5863b8ee2d6bfe6a91a2d43f21900213"],"r":[0,1,10.440597534179688,426,1,1,9.102720260620117,46,2,1,9.127458572387695,46,3,1,9.891647338867188,504,4,1,8.861434936523438,427,5,1,8.835786819458008,46,6,1,9.891647338867188,504,7,1,7.594245910644531,505,8,1,5.78688907623291,506,9,1,8.765414237976074,507,10,1,10.144248962402344,508,11,1,10.452966690063477,426,12,1,10.337606430053711,509,13,1,9.891647338867188,429,14,1,9.127458572387695,46,15,1,9.744510650634766,423,16,1,10.144248962402344,508,17,1,7.594245910644531,505,18,1,10.119510650634766,508,19,1,10.295024871826172,425,20,1,9.891647338867188,429,21,1,10.3499755859375,428,22,1,10.035783767700195,510,23,1,10.31976318359375,425,24,1,5.78688907623291,506,25,1,8.765414237976074,507,26,1,8.77876091003418,507,27,1,8.904407501220703,427,28,1,10.214944839477539,425,29,1,8.92264175415039,507,30,1,7.594245910644531,505,31,1,5.944116592407227,506,32,1,10.035783767700195,510,33,1,10.440597534179688,426,34,1,10.288129806518555,428,35,1,10.107141494750977,508,36,1,9.86690902709961,429,37,1,10.41585922241211,426,38,1,9.102720260620117,46,39,1,9.127458572387695,46,40,1,9.717817306518555,423,41,1,9.864953994750977,504,42,1,10.3499755859375,428,43,1,9.891647338867188,429,44,1,5.78688907623291,506,45,1,8.970231056213379,46,46,1,10.3499755859375,428,47,1,8.899068832397461,44,48,1,10.3499755859375,509,49,1,7.594245910644531,505,50,1,8.899068832397461,44,51,1,9.717817306518555,423,52,1,9.864953994750977,504,53,1,10.42471694946289,511,54,1,10.144248962402344,508,55,1,5.944116592407227,506,56,1,9.744510650634766,423,57,1,7.594245910644531,505,58,1,10.3499755859375,509,59,1,10.31976318359375,425,60,1,10.31976318359375,425,61,1,9.744510650634766,423,62,1,7.594245910644531,505,63,1,10.144248962402344,508]}}
  #|{"textrec":{"s":[14,400,0,"已移除 station"],"r":[0,1,13.891050583657588,512,1,1,13.891050583657588,513,2,1,13.891050583657588,514,3,1,3.787109375,-1,4,1,7.1435546875,245,5,1,4.9013671875,61,6,1,7.57421875,57,7,1,4.935546875,61,8,1,3.30859375,246,9,1,8.12109375,247,10,1,8.0185546875,60]}}
  #|{"textrec":{"g":504,"r":[2004,51,11,15,-1,-13,0]}}
  #|{"textrec":{"g":505,"r":[2016,51,7,14,0,-13,0]}}
  #|{"textrec":{"g":506,"r":[2024,51,8,14,-1,-13,0]}}
  #|{"textrec":{"g":507,"r":[2033,51,11,12,-1,-10,0]}}
  #|{"textrec":{"g":508,"r":[0,70,11,15,0,-13,0]}}
  #|{"textrec":{"g":509,"r":[12,70,12,15,-1,-13,0]}}
  #|{"textrec":{"g":510,"r":[25,70,11,15,0,-13,0]}}
  #|{"textrec":{"g":511,"r":[37,70,12,14,-1,-13,0]}}
  #|{"textrec":{"g":512,"r":[50,70,14,14,0,-12,0]}}
  #|{"textrec":{"g":513,"r":[65,70,16,16,-1,-13,0]}}
  #|{"textrec":{"g":514,"r":[82,70,15,15,0,-12,0]}}
