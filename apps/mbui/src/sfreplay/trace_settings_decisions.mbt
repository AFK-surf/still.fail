// e2e/traces/settings-decisions.trace, made by scripts/trace.py from 01-settings_decisions.log: not edited by hand.

///|
/// What the app and its core said in the run, a line each.
pub let trace_settings_decisions : String =
  #|{"env":{"MBUI_CLOUD":"http://127.0.0.1:18787","MBUI_CORE_ACCOUNT":"{\"sub\":\"alice\",\"email\":\"alice@example.test\",\"name\":\"Name of alice\",\"picture\":\"\",\"access\":\"-\",\"refresh\":\"-\",\"accessExpires\":1792593834}"}}
  #|{"out":{"id":1,"call":"client.device","params":{"client":"still.fail mbui","app":"desktop","userAgent":"Macintosh; Mac OS X"}},"w":1792593535655.064}
  #|{"in":{"id":1,"ok":null},"w":1792593535745.07}
  #|{"out":{"id":2,"subscribe":{"topic":"accounts"},"keyed":true},"w":1792593535745.095}
  #|{"out":{"id":3,"subscribe":{"topic":"prefs"},"keyed":true},"w":1792593535745.104}
  #|{"step":"# written by scripts/rerecord.sh from its test (src/sfreplay/emit.mbt): not edited by hand","w":1792593535746.555}
  #|{"step":"timeout 90000","w":1792593535746.561}
  #|{"step":"answered client.device","w":1792593535746.563}
  #|{"step":"answered client.focus","w":1792593535772.775}
  #|{"in":{"id":2,"value":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""}]},"w":1792593535822.435}
  #|{"out":{"id":4,"subscribe":{"topic":"workspaces"},"keyed":true},"w":1792593535822.455}
  #|{"out":{"id":5,"subscribe":{"topic":"status"},"keyed":true},"w":1792593535822.465}
  #|{"in":{"id":3,"value":{"onlyMine":false,"onlyWatching":false,"onlyDecisions":false,"listFilter":{},"appearance":"system","rowPicture":"auto","absoluteTime":false,"lang":"zh","keys":{},"lastChat":{},"openChat":{},"chatTabs":{},"dropFiles":{},"driveViews":{},"resume":{},"stationUpdatesDismissed":{},"device":{"app":"desktop","phone":false,"handoff":false},"reader":{"size":18,"line":1.7,"margin":22,"face":"sans","indent":true,"paper":"follow"},"rails":{},"bars":{"sets":[["chats","files","profiles","stations"],["decisions","usage","connects","archive"]],"current":0},"barsBy":{},"fonts":{},"faces":{"ui":{"id":"","name":"","mono":false,"family":"","files":[],"bytes":0},"text":{"id":"","name":"","mono":false,"family":"","files":[],"bytes":0},"code":{"id":"","name":"","mono":true,"family":"","files":[],"bytes":0},"list":[{"id":"inter","name":"Inter","mono":false,"family":"SF Inter","css":"http://127.0.0.1:18787/releases/fonts/inter/4.001/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/inter/4.001/var.ttf.gz","bytes":457818,"sha256":"29160a80ff49ddcab2c97711247e08b1fab27a484a329ce8b813d820dc559031"}],"preview":"http://127.0.0.1:18787/releases/fonts/inter/4.001/preview-194fa287.ttf","bytes":457818},{"id":"noto-sans-sc","name":"思源黑体","mono":false,"family":"SF Noto Sans SC","css":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/var.ttf.gz","bytes":11276563,"sha256":"a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da"}],"preview":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/preview-f0494178.ttf","bytes":11276563},{"id":"noto-serif-sc","name":"思源宋体","mono":false,"family":"SF Noto Serif SC","css":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/var.ttf.gz","bytes":15454579,"sha256":"050080d9255a86808f2945bffac582b31ef32bc36411ce29563b4961670c66f9"}],"preview":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/preview-001bbedf.ttf","bytes":15454579},{"id":"lxgw-wenkai","name":"霞鹜文楷","mono":false,"family":"SF LXGW WenKai","css":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/font.css","files":[{"weight":400,"url":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/400.ttf.gz","bytes":12904482,"sha256":"2d73eea94ad808999d90c0000c239a84a33b09d4bc6ab6c5b8bbf1eda8a7fc8b"},{"weight":500,"url":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/500.ttf.gz","bytes":13272430,"sha256":"f4b8a34d1f838fe411540cb7c97b1c384ac9738a876c4104500bc42508b2312a"}],"preview":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/preview-d3505af4.ttf","bytes":26176912},{"id":"jetbrains-mono","name":"JetBrains Mono","mono":true,"family":"SF JetBrains Mono","css":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/var.ttf.gz","bytes":90579,"sha256":"48715a42ec242c21e9f02692891e147d022299a52e48d5e413e1a942193ffeda"}],"preview":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/preview-ee73078f.ttf","bytes":90579},{"id":"fira-code","name":"Fira Code","mono":true,"family":"SF Fira Code","css":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/var.ttf.gz","bytes":137151,"sha256":"9335b082b3c7850d98a64b584f3417f65355f3471278bb5eeb8c6c0e8657aeeb"}],"preview":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/preview-555be27a.ttf","bytes":137151},{"id":"maple-mono","name":"Maple Mono","mono":true,"family":"SF Maple Mono CN","css":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/font.css","files":[{"weight":400,"url":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/400.ttf.gz","bytes":8352545,"sha256":"0fcc5139bfd5ab14ff989bb7dfd5236d0cafc10e60b9828569e6883613ab4085"},{"weight":600,"url":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/600.ttf.gz","bytes":8438132,"sha256":"96ed7ae26ee7c50b02b2d2b2bc0f1a0cbabe45ae5d6e6abf6678e2177c415677"}],"preview":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/preview-cffdf246.ttf","bytes":16790677}]}}},"w":1792593535839.14}
  #|{"in":{"id":4,"value":[{"account":{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""},"workspaces":[{"id":"01M5FED3EHEBYH94Y3JSEGQ3RP","name":"Dev","role":"owner","created_at":1792593530,"stations":1,"members":1,"relays":[],"time":{"created_at":{"past":true,"at":1792593530000,"ago":"刚刚","full":"10/21 22:38:50","until":"1 分钟内"}}}],"invitations":[],"relay_url":"http://127.0.0.1:18740","loaded":true,"beta":true}]},"w":1792593535839.183}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792593535839.191}
  #|{"out":{"id":6,"subscribe":{"topic":"lock","workspace":"01M5FED3EHEBYH94Y3JSEGQ3RP"},"keyed":true},"w":1792593535839.226}
  #|{"out":{"id":7,"subscribe":{"topic":"chats","scope":"01M5FED3EHEBYH94Y3JSEGQ3RP","mine":false},"keyed":true},"w":1792593535839.24}
  #|{"out":{"id":8,"subscribe":{"topic":"changelog"},"keyed":true},"w":1792593535839.246}
  #|{"out":{"id":9,"subscribe":{"topic":"workspaceMarks","workspace":"01M5FED3EHEBYH94Y3JSEGQ3RP"},"keyed":true},"w":1792593535839.365}
  #|{"out":{"id":10,"subscribe":{"topic":"status","workspace":"01M5FED3EHEBYH94Y3JSEGQ3RP"},"keyed":true},"w":1792593535839.397}
  #|{"out":{"id":11,"subscribe":{"topic":"lockPrompts"},"keyed":true},"w":1792593535844.378}
  #|{"out":{"id":12,"call":"client.focus","params":{"visible":true,"focused":true,"workspace":"01M5FED3EHEBYH94Y3JSEGQ3RP"}},"w":1792593535847.055}
  #|{"out":{"id":13,"subscribe":{"topic":"notify"},"keyed":true},"w":1792593535847.067}
  #|{"out":{"id":14,"subscribe":{"topic":"notify","workspace":"01M5FED3EHEBYH94Y3JSEGQ3RP"},"keyed":true},"w":1792593535847.075}
  #|{"in":{"id":6,"value":{"available":true,"locked":false,"notice":true,"role":"owner","manages":true,"owner":true,"canSign":true,"signs":false,"me":{"device":"223c0c7ce7721c9ee84b3d77ff01527194951483506624c091d7466f653b7d75","code":"T2W-AQ6","kind":"app","confirmed":false,"waiting":false,"asked":false},"signers":0,"members":[],"stations":[{"id":"a50950eb977afc9e099230f8168be11d1c759528b65a8922606e59594c8d7b1b","name":"studio","version":"0.1.0","online":true,"protected":false}],"protected":0,"requests":[],"renew":[],"attention":0}},"w":1792593535858.203}
  #|{"in":{"id":7,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"stations":[{"station":"01M5FED3EHEBYH94Y3JSEGQ3RP/a50950eb977afc9e099230f8168be11d1c759528b65a8922606e59594c8d7b1b","id":"a50950eb977afc9e099230f8168be11d1c759528b65a8922606e59594c8d7b1b","name":"studio","state":"online"}],"loading":false,"days":[{"daysAgo":0,"at":1792593534385,"label":"今天","items":[{"id":"ember:c-e276135fd0","session":"ember:c-e276135fd0","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","agents":[{"key":"ember:c-e276135fd0","runtime":"claude","process":"warm","pending":0,"lastTurn":{"id":"aef8e2ca-dcbb-42c9-a71a-b49cf966b715","kind":"input","outcome":"completed","declared":"final","ending":"all_done","need":"answered the question that was asked","startedAt":1792593534319,"endedAt":1792593534388},"agentText":"默认模型","statusText":"已完成：answered the question that was asked"}],"last":{"seq":2,"authorKind":"agent","author":"ember:c-e276135fd0","text":"你好，我是测试用的 agent","createdAt":1792593534385,"by":{"kind":"agent","name":"agent","mine":false,"runtime":"claude","label":"agent"},"preview":"你好，我是测试用的 agent","time":{"createdAt":{"at":1792593534385,"ago":"刚刚","full":"10/21 22:38:54","until":"1 分钟内","past":true}}},"unread":true,"mine":true,"lastActiveAt":1792593534385,"station":"01M5FED3EHEBYH94Y3JSEGQ3RP/a50950eb977afc9e099230f8168be11d1c759528b65a8922606e59594c8d7b1b","stationName":"studio","time":{"lastActiveAt":{"at":1792593534385,"ago":"刚刚","full":"10/21 22:38:54","until":"1 分钟内","past":true}},"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"peopleText":"你 发起","clientKey":"new:chat-fb93dfcebba3c4ea40","pinned":false,"tone":"done"}]}],"trouble":null,"members":1,"leading":"agents","glyph":{"online":1,"dim":0,"connecting":0,"failing":0,"working":0,"summary":"studio","label":"1 台 station，1 台在线"},"note":{"reading":false,"text":null,"failing":[],"empty":false}}},"w":1792593535858.233}
  #|{"in":{"id":8,"value":{"app":"desktop","tabs":[{"part":"desktop","label":"桌面","days":[]},{"part":"web","label":"网页","days":[]},{"part":"android","label":"安卓","days":[]},{"part":"station","label":"Station","days":[]},{"part":"cloud","label":"云端","days":[]}],"loading":false}},"w":1792593535858.253}
  #|{"in":{"id":9,"value":{"workspaces":{"01M5FED3EHEBYH94Y3JSEGQ3RP":{"alert":0,"unread":1,"tone":"done","label":"1 个有新消息","badge":0,"items":[],"mineTone":"done"}},"badge":0,"badgeCounts":"attention","badgeKinds":{"on":true,"wait":true,"failed":true,"done":false,"message":false}}},"w":1792593535858.261}
  #|{"in":{"id":10,"value":{"items":[]}},"w":1792593535858.265}
  #|{"in":{"id":11,"value":{"pairing":[]}},"w":1792593535858.267}
  #|{"in":{"id":12,"ok":null},"w":1792593535858.269}
  #|{"in":{"id":13,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792593535858.274}
  #|{"in":{"id":14,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792593535858.278}
  #|{"out":{"id":15,"subscribe":{"topic":"longJobs","scope":"01M5FED3EHEBYH94Y3JSEGQ3RP"},"keyed":true},"w":1792593535858.313}
  #|{"out":{"id":16,"call":"notify.permission","params":{"state":"unknown"}},"w":1792593535860.949}
  #|{"in":{"id":15,"value":{"groups":[]}},"w":1792593535872.434}
  #|{"in":{"id":16,"ok":null},"w":1792593535872.439}
  #|{"step":"answered notify.permission","w":1792593535872.649}
  #|{"step":"tap icon:settings","w":1792593535889.328}
  #|{"step":"tap icon:settings","acted":true,"w":1792593535889.34}
  #|{"out":{"id":17,"subscribe":{"topic":"workspace","workspace":"01M5FED3EHEBYH94Y3JSEGQ3RP"},"keyed":true},"w":1792593535905.882}
  #|{"out":{"id":18,"subscribe":{"topic":"stations","scope":"01M5FED3EHEBYH94Y3JSEGQ3RP"},"keyed":true},"w":1792593535905.898}
  #|{"out":{"id":19,"subscribe":{"topic":"connects","scope":"01M5FED3EHEBYH94Y3JSEGQ3RP","mine":false},"keyed":true},"w":1792593535905.904}
  #|{"out":{"id":20,"subscribe":{"topic":"vaults","workspace":"01M5FED3EHEBYH94Y3JSEGQ3RP"},"keyed":true},"w":1792593535905.911}
  #|{"out":{"id":21,"subscribe":{"topic":"doing"},"keyed":true},"w":1792593535908.657}
  #|{"step":"wait 299","w":1792593535909.655}
  #|{"in":{"id":17,"value":{"id":"01M5FED3EHEBYH94Y3JSEGQ3RP","name":"Dev","role":"owner","created_at":1792593530,"members":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":"https://example.test/p.png","role":"owner","added_at":1792593530}],"stations":[{"id":"a50950eb977afc9e099230f8168be11d1c759528b65a8922606e59594c8d7b1b","name":"studio","emoji":null,"icon":null,"enrolled_at":1792593530,"enrolled_by":"alice","last_seen":1792593534,"version":"0.1.0","time":{"last_seen":{"past":true,"at":1792593534000,"ago":"刚刚","full":"10/21 22:38:54","until":"1 分钟内"}}}],"invitations":[],"added":[],"relays":[],"lock":null,"lock_requests":0,"time":{"created_at":{"past":true,"at":1792593530000,"ago":"刚刚","full":"10/21 22:38:50","until":"1 分钟内"}}}},"w":1792593535922.478}
  #|{"in":{"id":18,"value":[{"station":"01M5FED3EHEBYH94Y3JSEGQ3RP/a50950eb977afc9e099230f8168be11d1c759528b65a8922606e59594c8d7b1b","id":"a50950eb977afc9e099230f8168be11d1c759528b65a8922606e59594c8d7b1b","name":"studio","summary":"正在连接","face":"idle","line":"在线","online":true,"reconnecting":false,"lastSeen":1792593534,"version":"0.1.0","link":{"state":"online"},"runtimes":[{"runtime":"claude","models":["claude-sonnet-5-5"]}],"models":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792593534298,"time":{"checkedAt":{"at":1792593534298,"ago":"刚刚","full":"10/21 22:38:54","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"overview":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null,"summaryText":"最近 7 天检查了 0 个 chat","changeText":null}},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","email":"alice@example.test","name":"Name of alice","sub":"alice","role":"owner","workspace":"01M5FED3EHEBYH94Y3JSEGQ3RP","device":"223c0c7ce7721c9ee84b3d77ff01527194951483506624c091d7466f653b7d75"},"connects":[],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792593534181,"time":{"checkedAt":{"at":1792593534181,"ago":"刚刚","full":"10/21 22:38:54","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792593534298,"time":{"checkedAt":{"at":1792593534298,"ago":"刚刚","full":"10/21 22:38:54","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"modelsReading":false,"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]}],"processes":[],"counts":{"sessions":1,"running":0,"warm":1},"mesh":{"state":"running","origin":"http://127.0.0.1:18787","station":"a50950eb977afc9e099230f8168be11d1c759528b65a8922606e59594c8d7b1b","workspace":"Dev","workspaceId":"01M5FED3EHEBYH94Y3JSEGQ3RP","name":"studio"},"slackUsers":[],"slackTeams":[],"slackApps":[],"feishuRegistrations":[],"disk":{"freeBytes":31500103680,"totalBytes":245107195904},"logins":[],"machineLogins":[],"sharing":true,"consoleSignIn":true,"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"google","name":"Google Gemini","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xai","name":"xAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"mistral","name":"Mistral","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"deepseek","name":"DeepSeek","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen","name":"Qwen","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai","name":"Kimi","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai","name":"Z.ai","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax","name":"MiniMax","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ant-ling","name":"Ant Ling","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"jev","name":"Jev","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen-cn","name":"Qwen (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"openrouter","name":"OpenRouter","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"opencode","name":"OpenCode Zen","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"groq","name":"Groq","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"together","name":"Together AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"fireworks","name":"Fireworks","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cerebras","name":"Cerebras","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"huggingface","name":"Hugging Face","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"nvidia","name":"NVIDIA","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"baseten","name":"Baseten","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ollama","name":"Ollama","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"custom","name":"Custom","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""}],"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792593533546},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.306","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792593533546},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-lockp/apps/e2e-local/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792593533546},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-lockp/apps/e2e-local/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792593533546},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","latest":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-lockp/apps/e2e-local/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792593533546},{"id":"cursor","name":"Cursor","installed":false,"latest":"1.0.40","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792593533546},{"id":"devin","name":"Devin","installed":true,"version":"3000.11.92","latest":"3000.11.92","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-lockp/apps/e2e-local/ember/station/test/fake/devin，不是用 Devin 的安装脚本装的，需在该机器上手动更新","state":"idle","checkedAt":1792593533546}],"processesText":"没有运行中的 agent 进程","agentEnv":[],"drive":{"roots":[],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false}},"betaOffered":false,"way":{"path":"直连","via":"direct"},"time":{"lastSeen":{"at":1792593534000,"ago":"刚刚","full":"10/21 22:38:54","until":"1 分钟内","past":true}},"joined":false}]},"w":1792593535922.603}
  #|{"in":{"id":19,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"items":[],"wait":{"reading":false,"text":null,"failing":[],"empty":true}}},"w":1792593535922.681}
  #|{"in":{"id":20,"value":{"available":true,"locked":false,"canSign":false,"setUp":false,"vaults":[{"id":"plain","name":"个人","owner":"alice","ownerName":"Name of alice","mine":true,"members":[{"sub":"alice","name":"Name of alice"}],"station":"a50950eb977afc9e099230f8168be11d1c759528b65a8922606e59594c8d7b1b","stationName":"studio","items":0,"devices":0,"open":true,"keyed":true,"missing":0,"recoverable":false}],"requests":[],"refused":[{"station":"a50950eb977afc9e099230f8168be11d1c759528b65a8922606e59594c8d7b1b","name":"studio","code":"vault_needs_lock"}],"plain":true}},"w":1792593535922.69}
  #|{"in":{"id":21,"value":{"doing":[]}},"w":1792593535922.696}
  #|{"in":{"id":18,"delta":[{"path":[0,"host"],"set":{"hostname":"3720-Mac-mini-1","os":"macOS 27.0.1","arch":"arm64","cpus":10,"cpuModel":"Apple M4","load":0.81,"cpuBusy":0.12,"uptimeSec":72897,"memory":{"totalBytes":17179869184,"usedBytes":9015345152,"swapUsedBytes":250347520},"disk":{"path":"/tmp/mbe2e-C/data","totalBytes":245107195904,"freeBytes":31499980800},"emberRssBytes":162364632,"checkedAt":1792593535947,"summary":"10 核 · 16 GB","line":"macOS 27.0.1 · 10 核 · 16 GB · 已运行 0 天","facts":["3720-Mac-mini-1","macOS 27.0.1","arm64 · 10 核","已运行 20 小时"],"meters":[{"label":"CPU","short":"CPU","percent":12,"left":88,"level":"ok","value":"12%","remaining":"空闲 88%","big":"88","unit":"%","title":"CPU 空闲","total":"负载 8.1","note":"负载 8.1 · Apple M4"},{"label":"内存","short":"内存","percent":52,"left":48,"level":"ok","value":"8.4 GB / 16.0 GB","remaining":"剩 7.6 G","big":"7.6","unit":"GB","title":"内存剩","total":"共 16 GB","note":"swap 0.2 GB"},{"label":"磁盘","short":"磁盘","percent":87,"left":13,"level":"amber","value":"剩余 29.3 GB / 228 GB","remaining":"剩 29.3 G","big":"29.3","unit":"GB","title":"磁盘剩","total":"共 228 GB"}],"identity":"Apple M4 · 16 GB · macOS 27.0.1","details":[{"label":"主机名","value":"3720-Mac-mini-1"},{"label":"芯片","value":"Apple M4 · 10 核 · arm64"},{"label":"已运行","value":"20 小时"},{"label":"still.fail","value":"进程占用 155 MB"}],"usage":"内存 8.4 GB / 16.0 GB · 磁盘 剩余 29.3 GB / 228 GB","emberText":"still.fail 155 MB"}},{"path":[0,"line"],"set":"Apple M4"},{"path":[0,"summary"],"set":"空闲 · Apple M4 · 16 GB · macOS 27.0.1"}]},"w":1792593535972.458}
  #|{"step":"now wheelat 300 Workspace","w":1792593536223.347}
  #|{"step":"now wheelat 300 Workspace","acted":true,"w":1792593536223.44}
  #|{"step":"wait 900","w":1792593536248.123}
  #|{"step":"now tap =自动决策","w":1792593537156.497}
  #|{"step":"now tap =自动决策","acted":true,"w":1792593537156.61}
  #|{"step":"wait 300","w":1792593537178.053}
  #|{"step":"now tap 归档建议","w":1792593537506.363}
  #|{"step":"now tap 归档建议","acted":true,"w":1792593537506.432}
  #|{"out":{"id":22,"subscribe":{"topic":"decisionForm","station":"01M5FED3EHEBYH94Y3JSEGQ3RP/a50950eb977afc9e099230f8168be11d1c759528b65a8922606e59594c8d7b1b","form":"mbui-decision-1"},"keyed":true},"w":1792593537522.839}
  #|{"out":{"id":23,"call":"automaticDecisions.form.open","params":{"station":"01M5FED3EHEBYH94Y3JSEGQ3RP/a50950eb977afc9e099230f8168be11d1c759528b65a8922606e59594c8d7b1b","form":"mbui-decision-1","input":{}}},"w":1792593537526.45}
  #|{"step":"answered automaticDecisions.form.open","w":1792593537526.794}
  #|{"in":{"id":22,"value":null},"w":1792593537539.144}
  #|{"in":{"id":23,"ok":{"enabled":false,"model":"","dirty":false,"pending":false}},"w":1792593537539.182}
  #|{"step":"wait 300","w":1792593537556.517}
  #|{"in":{"id":22,"value":{"enabled":false,"model":"","dirty":false,"pending":false,"pick":{"options":[],"runtimeFixed":true,"value":{"model":"","runtime":"codex"},"valueOption":null,"draft":{"model":"","runtime":"codex"},"option":"","changed":false,"runtimes":[],"efforts":[],"accounts":[],"who":"","autoNote":"","was":[],"becomes":[],"modelText":"","accountText":"","accountNote":"","accountWarn":false,"saveText":""}}},"w":1792593537605.843}
  #|{"step":"now tap =启用","w":1792593537873.086}
  #|{"step":"now tap =启用","acted":true,"w":1792593537873.155}
  #|{"out":{"id":24,"call":"automaticDecisions.form.edit","params":{"station":"01M5FED3EHEBYH94Y3JSEGQ3RP/a50950eb977afc9e099230f8168be11d1c759528b65a8922606e59594c8d7b1b","form":"mbui-decision-1","input":{"enabled":true}}},"w":1792593537889.393}
  #|{"step":"answered automaticDecisions.form.edit","w":1792593537889.735}
  #|{"in":{"id":24,"ok":{"enabled":true,"model":"","dirty":true,"pending":false}},"w":1792593537905.819}
  #|{"step":"tap 保存修改","w":1792593537923.183}
  #|{"in":{"id":22,"delta":[{"path":["dirty"],"set":true},{"path":["enabled"],"set":true}]},"w":1792593538039.153}
  #|{"step":"tap 保存修改","acted":true,"w":1792593538042.765}
  #|{"out":{"id":25,"call":"automaticDecisions.form.save","params":{"station":"01M5FED3EHEBYH94Y3JSEGQ3RP/a50950eb977afc9e099230f8168be11d1c759528b65a8922606e59594c8d7b1b","form":"mbui-decision-1","input":{}}},"w":1792593538056.088}
  #|{"step":"answered automaticDecisions.form.save","w":1792593538056.402}
  #|{"in":{"id":25,"error":{"code":"invalid_params","message":"请选择用于完成检查的模型"}},"w":1792593538072.487}
  #|{"step":"until 请选择用于完成检查的模型","w":1792593538093.878}
  #|{"step":"tap =启用","w":1792593538093.91}
  #|{"step":"tap =启用","acted":true,"w":1792593538093.941}
  #|{"out":{"id":26,"call":"automaticDecisions.form.edit","params":{"station":"01M5FED3EHEBYH94Y3JSEGQ3RP/a50950eb977afc9e099230f8168be11d1c759528b65a8922606e59594c8d7b1b","form":"mbui-decision-1","input":{"enabled":false}}},"w":1792593538106.186}
  #|{"step":"answered automaticDecisions.form.edit","w":1792593538106.595}
  #|{"in":{"id":26,"ok":{"enabled":false,"model":"","dirty":false,"pending":false}},"w":1792593538122.491}
  #|{"in":{"id":21,"value":{"doing":[{"call":"automaticDecisions.form.save","params":{"station":"01M5FED3EHEBYH94Y3JSEGQ3RP/a50950eb977afc9e099230f8168be11d1c759528b65a8922606e59594c8d7b1b","form":"mbui-decision-1"},"since":1792593538056,"stage":"failed","error":"请选择用于完成检查的模型"}]}},"w":1792593538122.567}
  #|{"in":{"id":22,"delta":[{"path":["dirty"],"set":false},{"path":["enabled"],"set":false}]},"w":1792593538122.609}
  #|{"step":"gone 保存修改","w":1792593538139.889}
  #|{"step":"wait 2600","w":1792593538139.927}
  #|{"step":"wait 100","w":1792593540739.964}
  #|{"step":"","w":1792593540856.86}
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
  #|{"textrec":{"ib":["fdb526ba00f881f4",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["1d51432b25a425eb",1108,64],"r":[16,16,16,16]}}
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
  #|{"textrec":{"g":183,"r":[1878,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":184,"r":[1895,0,10,14,-1,-12,0]}}
  #|{"textrec":{"g":185,"r":[1906,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":191,"r":[1923,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":126,"r":[1940,0,9,13,0,-12,0]}}
  #|{"textrec":{"g":127,"r":[1950,0,16,16,-1,-13,0]}}
  #|{"textrec":{"ib":["b3685975cd23abc3",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"g":135,"r":[1967,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":136,"r":[1984,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":137,"r":[2001,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":138,"r":[2017,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":139,"r":[0,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":140,"r":[16,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":141,"r":[32,32,6,6,0,-3,0]}}
  #|{"textrec":{"g":142,"r":[39,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":143,"r":[54,32,15,14,-1,-11,0]}}
  #|{"textrec":{"g":144,"r":[70,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":145,"r":[86,32,15,13,-1,-11,0]}}
  #|{"textrec":{"g":146,"r":[102,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":147,"r":[116,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":148,"r":[132,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":149,"r":[148,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":150,"r":[163,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":151,"r":[179,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":152,"r":[194,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":153,"r":[210,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":154,"r":[226,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":155,"r":[242,32,14,14,-1,-12,0]}}
  #|{"textrec":{"g":4,"r":[257,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":160,"r":[272,32,5,5,0,-3,0]}}
  #|{"textrec":{"g":161,"r":[278,32,13,11,0,-10,0]}}
  #|{"textrec":{"g":162,"r":[292,32,10,15,0,-13,0]}}
  #|{"textrec":{"g":163,"r":[303,32,9,11,0,-9,0]}}
  #|{"textrec":{"g":164,"r":[313,32,11,14,-1,-12,0]}}
  #|{"textrec":{"g":165,"r":[325,32,8,13,-1,-12,0]}}
  #|{"textrec":{"g":156,"r":[334,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":157,"r":[352,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":158,"r":[369,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":159,"r":[387,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":166,"r":[405,32,12,16,1,-13,0]}}
  #|{"textrec":{"g":167,"r":[418,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":168,"r":[435,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":169,"r":[453,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":170,"r":[471,32,16,17,-1,-14,0]}}
  #|{"textrec":{"g":171,"r":[488,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":172,"r":[506,32,16,17,0,-14,0]}}
  #|{"textrec":{"g":173,"r":[523,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":174,"r":[540,32,17,16,-1,-13,0]}}
  #|{"textrec":{"s":[17,400,0,"设置"],"r":[0,1,16.851167315175097,192,1,1,16.851167315175097,193]}}
  #|{"textrec":{"s":[32,700,8,"自动决策"],"r":[0,1,30.345864661654133,194,1,1,30.345864661654133,195,2,1,30.345864661654133,196,3,1,30.345864661654133,197]}}
  #|{"textrec":{"s":[15,400,0,"归档建议"],"r":[0,1,14.883268482490273,198,1,1,14.883268482490273,199,2,1,14.883268482490273,200,3,1,14.883268482490273,201]}}
  #|{"textrec":{"s":[13,400,0,"标记完成后判断是否推荐归档"],"r":[0,1,12.898832684824903,202,1,1,12.898832684824903,203,2,1,12.898832684824903,139,3,1,12.898832684824903,140,4,1,12.898832684824896,204,5,1,12.898832684824896,205,6,1,12.898832684824896,206,7,1,12.898832684824896,207,8,1,12.898832684824896,208,9,1,12.898832684824896,209,10,1,12.898832684824896,210,11,1,12.898832684824896,211,12,1,12.898832684824896,212]}}
  #|{"textrec":{"g":192,"r":[558,32,19,18,-1,-15,0]}}
  #|{"textrec":{"g":193,"r":[578,32,18,17,-1,-14,0]}}
  #|{"textrec":{"g":194,"r":[597,32,24,31,3,-26,0]}}
  #|{"textrec":{"g":195,"r":[622,32,30,31,0,-26,0]}}
  #|{"textrec":{"g":196,"r":[653,32,31,31,0,-26,0]}}
  #|{"textrec":{"g":197,"r":[685,32,30,32,0,-27,0]}}
  #|{"textrec":{"g":198,"r":[716,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":199,"r":[733,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":200,"r":[750,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":201,"r":[767,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":202,"r":[785,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":203,"r":[801,32,15,14,-1,-12,0]}}
  #|{"textrec":{"g":204,"r":[817,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":205,"r":[832,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":206,"r":[847,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":207,"r":[863,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":208,"r":[878,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":209,"r":[893,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":210,"r":[908,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":211,"r":[923,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":212,"r":[938,32,14,15,-1,-12,0]}}
  #|{"textrec":{"s":[17,400,0,"自动决策"],"r":[0,1,16.851167315175097,213,1,1,16.851167315175097,214,2,1,16.851167315175097,215,3,1,16.851167315175097,216]}}
  #|{"textrec":{"s":[32,700,8,"归档建议"],"r":[0,1,30.345864661654133,217,1,1,30.345864661654133,218,2,1,30.345864661654133,219,3,1,30.345864661654133,220]}}
  #|{"textrec":{"s":[15,600,0,"studio"],"r":[0,1,8.000344634056091,221,1,1,5.658300518989563,222,2,1,8.93320620059967,223,3,1,9.332013130187988,224,4,1,3.8520312309265137,225,5,1,8.901597261428833,226]}}
  #|{"textrec":{"s":[13,400,0,"正在读取配置"],"r":[0,1,12.898832684824903,0,1,1,12.898832684824903,1,2,1,12.898832684824903,2,3,1,12.898832684824903,3,4,1,12.898832684824896,227,5,1,12.898832684824896,228]}}
  #|{"textrec":{"g":213,"r":[953,32,14,18,1,-15,0]}}
  #|{"textrec":{"g":214,"r":[968,32,18,18,-1,-15,0]}}
  #|{"textrec":{"g":215,"r":[987,32,18,18,-1,-15,0]}}
  #|{"textrec":{"g":216,"r":[1006,32,18,18,-1,-15,0]}}
  #|{"textrec":{"g":217,"r":[1025,32,29,31,0,-26,0]}}
  #|{"textrec":{"g":218,"r":[1055,32,31,31,-1,-26,0]}}
  #|{"textrec":{"g":219,"r":[1087,32,30,31,0,-26,0]}}
  #|{"textrec":{"g":220,"r":[1118,32,31,31,0,-26,0]}}
  #|{"textrec":{"g":221,"r":[1150,32,10,12,-1,-10,0]}}
  #|{"textrec":{"g":222,"r":[1161,32,8,13,-1,-11,0]}}
  #|{"textrec":{"g":223,"r":[1170,32,10,12,0,-10,0]}}
  #|{"textrec":{"g":224,"r":[1181,32,11,15,-1,-13,0]}}
  #|{"textrec":{"g":225,"r":[1193,32,6,14,-1,-13,0]}}
  #|{"textrec":{"g":226,"r":[1200,32,11,12,-1,-10,0]}}
  #|{"textrec":{"g":0,"r":[1212,32,14,13,-1,-11,0]}}
  #|{"textrec":{"g":1,"r":[1227,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":2,"r":[1242,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":3,"r":[1258,32,15,14,-1,-11,0]}}
  #|{"textrec":{"g":227,"r":[1274,32,15,14,-1,-11,0]}}
  #|{"textrec":{"g":228,"r":[1290,32,15,13,-1,-11,0]}}
  #|{"textrec":{"s":[15,400,0,"启用"],"r":[0,1,14.883268482490273,229,1,1,14.883268482490273,115]}}
  #|{"textrec":{"s":[14,400,0,"选择模型"],"r":[0,1,13.891050583657588,230,1,1,13.891050583657588,231,2,1,13.891050583657588,232,3,1,13.891050583657588,233]}}
  #|{"textrec":{"s":[15,400,0,"决策模型"],"r":[0,1,14.883268482490273,111,1,1,14.883268482490273,112,2,1,14.883268482490273,234,3,1,14.883268482490273,235]}}
  #|{"textrec":{"s":[15,400,0,"归档策略"],"r":[0,1,14.883268482490273,198,1,1,14.883268482490273,199,2,1,14.883268482490273,112,3,1,14.883268482490273,236]}}
  #|{"textrec":{"s":[13,400,0,"8 个选项 · 最近 7 天检查了 0 个 chat"],"r":[0,1,8.2265625,237,1,1,3.580078125,-1,2,1,12.898832684824903,238,3,1,12.898832684824903,239,4,1,12.898832684824903,240,5,1,3.580078125,-1,6,1,6.228545204222122,241,7,1,3.580078125,-1,8,1,12.898832684824896,242,9,1,12.898832684824896,243,10,1,3.580078125,-1,11,1,7.3251953125,244,12,1,3.580078125,-1,13,1,12.898832684824896,245,14,1,12.898832684824896,246,15,1,12.898832684824896,247,16,1,12.898832684824896,248,17,1,3.580078125,-1,18,1,8.1123046875,249,19,1,3.580078125,-1,20,1,12.898832684824896,238,21,1,3.580078125,-1,22,1,7.1982421875,13,23,1,7.57275390625,250,24,1,7.0966796875,12,25,1,4.646484375,82]}}
  #|{"textrec":{"g":229,"r":[1306,32,15,17,-1,-14,0]}}
  #|{"textrec":{"g":234,"r":[1322,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":235,"r":[1340,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":236,"r":[1357,32,16,16,0,-13,0]}}
  #|{"textrec":{"g":237,"r":[1374,32,10,13,-1,-11,0]}}
  #|{"textrec":{"g":238,"r":[1385,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":239,"r":[1401,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":240,"r":[1417,32,15,14,-1,-11,0]}}
  #|{"textrec":{"g":241,"r":[1433,32,4,5,1,-7,0]}}
  #|{"textrec":{"g":242,"r":[1438,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":243,"r":[1453,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":244,"r":[1469,32,9,12,-1,-11,0]}}
  #|{"textrec":{"g":245,"r":[1479,32,15,14,-1,-11,0]}}
  #|{"textrec":{"g":246,"r":[1495,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":247,"r":[1511,32,15,14,-1,-12,0]}}
  #|{"textrec":{"g":248,"r":[1527,32,13,14,0,-11,0]}}
  #|{"textrec":{"g":249,"r":[1541,32,10,13,-1,-11,0]}}
  #|{"textrec":{"g":250,"r":[1552,32,8,12,0,-11,0]}}
  #|{"textrec":{"g":230,"r":[1561,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":231,"r":[1578,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":232,"r":[1595,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":233,"r":[1612,32,15,15,-1,-12,0]}}
  #|{"textrec":{"ib":["0e910fb4d25445a3",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"s":[14,600,0,"保存修改"],"r":[0,1,13.891050583657588,251,1,1,13.891050583657588,252,2,1,13.891050583657588,253,3,1,13.891050583657588,254]}}
  #|{"textrec":{"m":[14,600,0],"r":[13.53515625,2.953125,20,13.53515625,2.953125,0]}}
  #|{"textrec":{"g":251,"r":[1628,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":252,"r":[1645,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":253,"r":[1662,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":254,"r":[1679,32,16,16,-1,-13,0]}}
  #|{"textrec":{"s":[14,400,0,"无法自动决策配置：请选择用于完成检查的模型"],"r":[0,1,13.891050583657588,255,1,1,13.891050583657588,256,2,1,13.891050583657588,257,3,1,13.891050583657588,258,4,1,13.891050583657588,259,5,1,13.891050583657588,260,6,1,13.891050583657588,261,7,1,13.891050583657588,262,8,1,14.081712062256813,263,9,1,13.891050583657588,264,10,1,13.891050583657574,230,11,1,13.891050583657602,231,12,1,13.891050583657602,55,13,1,13.891050583657602,265,14,1,13.891050583657602,266,15,1,13.891050583657602,267,16,1,13.891050583657602,268,17,1,13.891050583657602,269,18,1,13.891050583657602,56,19,1,13.891050583657602,232,20,1,13.891050583657602,233]}}
  #|{"textrec":{"g":255,"r":[1696,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":256,"r":[1712,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":257,"r":[1729,32,12,16,1,-13,0]}}
  #|{"textrec":{"g":258,"r":[1742,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":259,"r":[1758,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":260,"r":[1775,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":261,"r":[1791,32,16,15,-1,-12,0]}}
  #|{"textrec":{"g":262,"r":[1808,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":263,"r":[1824,32,5,10,1,-10,0]}}
  #|{"textrec":{"g":264,"r":[1830,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":265,"r":[1847,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":266,"r":[1863,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":267,"r":[1879,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":268,"r":[1896,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":269,"r":[1913,32,16,15,-1,-13,0]}}
