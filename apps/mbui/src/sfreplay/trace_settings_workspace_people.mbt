// e2e/traces/settings-workspace-people.trace, made by scripts/trace.py from 01-settings_workspace_people.log: not edited by hand.

///|
/// What the app and its core said in the run, a line each.
pub let trace_settings_workspace_people : String =
  #|{"env":{"MBUI_CLOUD":"http://127.0.0.1:18787","MBUI_CORE_ACCOUNT":"{\"sub\":\"alice\",\"email\":\"alice@example.test\",\"name\":\"Name of alice\",\"picture\":\"\",\"access\":\"-\",\"refresh\":\"-\",\"accessExpires\":1792610359}"}}
  #|{"out":{"id":1,"call":"client.device","params":{"client":"still.fail mbui","app":"desktop","userAgent":"Macintosh; Mac OS X"}},"w":1792610060756.276}
  #|{"in":{"id":1,"ok":null},"w":1792610060851.611}
  #|{"out":{"id":2,"subscribe":{"topic":"accounts"},"keyed":true},"w":1792610060851.635}
  #|{"out":{"id":3,"subscribe":{"topic":"prefs"},"keyed":true},"w":1792610060851.644}
  #|{"step":"# written by scripts/rerecord.sh from its test (src/sfreplay/emit.mbt): not edited by hand","w":1792610060853.197}
  #|{"step":"timeout 90000","w":1792610060853.204}
  #|{"step":"answered client.device","w":1792610060853.207}
  #|{"step":"answered client.focus","w":1792610060867.351}
  #|{"in":{"id":2,"value":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""}]},"w":1792610060933.669}
  #|{"in":{"id":3,"value":{"onlyMine":false,"onlyWatching":false,"onlyDecisions":false,"listFilter":{},"appearance":"system","rowPicture":"auto","absoluteTime":false,"lang":"zh","keys":{},"lastChat":{},"openChat":{},"chatTabs":{},"dropFiles":{},"driveViews":{},"filesTabs":{},"driveFavorites":{},"resume":{},"stationUpdatesDismissed":{},"device":{"app":"desktop","phone":false,"handoff":false},"reader":{"size":18,"line":1.7,"margin":22,"face":"sans","indent":true,"paper":"follow"},"rails":{},"bars":{"sets":[["chats","files","profiles","stations"],["decisions","usage","connects","archive"]],"current":0},"barsBy":{},"fonts":{},"faces":{"ui":{"id":"","name":"","mono":false,"family":"","files":[],"bytes":0},"text":{"id":"","name":"","mono":false,"family":"","files":[],"bytes":0},"code":{"id":"","name":"","mono":true,"family":"","files":[],"bytes":0},"list":[{"id":"inter","name":"Inter","mono":false,"family":"SF Inter","css":"http://127.0.0.1:18787/releases/fonts/inter/4.001/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/inter/4.001/var.ttf.gz","bytes":457818,"sha256":"29160a80ff49ddcab2c97711247e08b1fab27a484a329ce8b813d820dc559031"}],"preview":"http://127.0.0.1:18787/releases/fonts/inter/4.001/preview-194fa287.ttf","bytes":457818},{"id":"noto-sans-sc","name":"思源黑体","mono":false,"family":"SF Noto Sans SC","css":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/var.ttf.gz","bytes":11276563,"sha256":"a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da"}],"preview":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/preview-f0494178.ttf","bytes":11276563},{"id":"noto-serif-sc","name":"思源宋体","mono":false,"family":"SF Noto Serif SC","css":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/var.ttf.gz","bytes":15454579,"sha256":"050080d9255a86808f2945bffac582b31ef32bc36411ce29563b4961670c66f9"}],"preview":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/preview-001bbedf.ttf","bytes":15454579},{"id":"lxgw-wenkai","name":"霞鹜文楷","mono":false,"family":"SF LXGW WenKai","css":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/font.css","files":[{"weight":400,"url":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/400.ttf.gz","bytes":12904482,"sha256":"2d73eea94ad808999d90c0000c239a84a33b09d4bc6ab6c5b8bbf1eda8a7fc8b"},{"weight":500,"url":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/500.ttf.gz","bytes":13272430,"sha256":"f4b8a34d1f838fe411540cb7c97b1c384ac9738a876c4104500bc42508b2312a"}],"preview":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/preview-d3505af4.ttf","bytes":26176912},{"id":"jetbrains-mono","name":"JetBrains Mono","mono":true,"family":"SF JetBrains Mono","css":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/var.ttf.gz","bytes":90579,"sha256":"48715a42ec242c21e9f02692891e147d022299a52e48d5e413e1a942193ffeda"}],"preview":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/preview-ee73078f.ttf","bytes":90579},{"id":"fira-code","name":"Fira Code","mono":true,"family":"SF Fira Code","css":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/var.ttf.gz","bytes":137151,"sha256":"9335b082b3c7850d98a64b584f3417f65355f3471278bb5eeb8c6c0e8657aeeb"}],"preview":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/preview-555be27a.ttf","bytes":137151},{"id":"maple-mono","name":"Maple Mono","mono":true,"family":"SF Maple Mono CN","css":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/font.css","files":[{"weight":400,"url":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/400.ttf.gz","bytes":8352545,"sha256":"0fcc5139bfd5ab14ff989bb7dfd5236d0cafc10e60b9828569e6883613ab4085"},{"weight":600,"url":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/600.ttf.gz","bytes":8438132,"sha256":"96ed7ae26ee7c50b02b2d2b2bc0f1a0cbabe45ae5d6e6abf6678e2177c415677"}],"preview":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/preview-cffdf246.ttf","bytes":16790677}]}}},"w":1792610060933.709}
  #|{"out":{"id":4,"subscribe":{"topic":"workspaces"},"keyed":true},"w":1792610060933.762}
  #|{"out":{"id":5,"subscribe":{"topic":"status"},"keyed":true},"w":1792610060933.773}
  #|{"in":{"id":4,"value":[{"account":{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""},"workspaces":[{"id":"01M5FY5DA1GD828B38YK5K8SGK","name":"Dev","role":"owner","created_at":1792610055,"stations":1,"members":1,"relays":[],"time":{"created_at":{"past":true,"at":1792610055000,"ago":"刚刚","full":"10/22 03:14:15","until":"1 分钟内"}}}],"invitations":[],"relay_url":"http://127.0.0.1:18740","loaded":true,"beta":true}]},"w":1792610060950.742}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792610060950.758}
  #|{"out":{"id":6,"subscribe":{"topic":"lock","workspace":"01M5FY5DA1GD828B38YK5K8SGK"},"keyed":true},"w":1792610060950.797}
  #|{"out":{"id":7,"subscribe":{"topic":"chats","scope":"01M5FY5DA1GD828B38YK5K8SGK","mine":false},"keyed":true},"w":1792610060950.811}
  #|{"out":{"id":8,"subscribe":{"topic":"changelog"},"keyed":true},"w":1792610060950.819}
  #|{"out":{"id":9,"subscribe":{"topic":"workspaceMarks","workspace":"01M5FY5DA1GD828B38YK5K8SGK"},"keyed":true},"w":1792610060950.945}
  #|{"out":{"id":10,"subscribe":{"topic":"status","workspace":"01M5FY5DA1GD828B38YK5K8SGK"},"keyed":true},"w":1792610060950.981}
  #|{"out":{"id":11,"subscribe":{"topic":"lockPrompts"},"keyed":true},"w":1792610060955.796}
  #|{"out":{"id":12,"call":"client.focus","params":{"visible":true,"focused":true,"workspace":"01M5FY5DA1GD828B38YK5K8SGK"}},"w":1792610060958.083}
  #|{"out":{"id":13,"subscribe":{"topic":"notify"},"keyed":true},"w":1792610060958.09}
  #|{"out":{"id":14,"subscribe":{"topic":"notify","workspace":"01M5FY5DA1GD828B38YK5K8SGK"},"keyed":true},"w":1792610060958.098}
  #|{"in":{"id":6,"value":{"available":true,"locked":false,"notice":true,"role":"owner","manages":true,"owner":true,"canSign":true,"signs":false,"me":{"device":"64f8e7fc2067d6dff4be792d7538e0bd18113bc19ec3362d4b40415f6cfc65bf","code":"CPZ-RRG","kind":"app","confirmed":false,"waiting":false,"asked":false},"signers":0,"members":[],"stations":[{"id":"0df49ce7b9582e4f8805ab237a8b7319bae0dc27ac2ef74932ce16c20d667d96","name":"studio","version":"0.1.0","online":true,"protected":false}],"protected":0,"requests":[],"renew":[],"attention":0}},"w":1792610060966.997}
  #|{"in":{"id":7,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"stations":[{"station":"01M5FY5DA1GD828B38YK5K8SGK/0df49ce7b9582e4f8805ab237a8b7319bae0dc27ac2ef74932ce16c20d667d96","id":"0df49ce7b9582e4f8805ab237a8b7319bae0dc27ac2ef74932ce16c20d667d96","name":"studio","state":"online"}],"loading":false,"days":[{"daysAgo":0,"at":1792610059514,"label":"今天","items":[{"id":"ember:c-27d1d4baaf","session":"ember:c-27d1d4baaf","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","agents":[{"key":"ember:c-27d1d4baaf","runtime":"claude","process":"warm","pending":0,"lastTurn":{"id":"1516cadb-c1ec-4533-9961-97bb4e18f8c3","kind":"input","outcome":"completed","declared":"final","ending":"all_done","need":"answered the question that was asked","startedAt":1792610059446,"endedAt":1792610059517},"agentText":"默认模型","statusText":"已完成：answered the question that was asked"}],"last":{"seq":2,"authorKind":"agent","author":"ember:c-27d1d4baaf","text":"你好，我是测试用的 agent","createdAt":1792610059514,"by":{"kind":"agent","name":"agent","mine":false,"runtime":"claude","label":"agent"},"preview":"你好，我是测试用的 agent","time":{"createdAt":{"at":1792610059514,"ago":"刚刚","full":"10/22 03:14:19","until":"1 分钟内","past":true}}},"unread":true,"mine":true,"lastActiveAt":1792610059514,"station":"01M5FY5DA1GD828B38YK5K8SGK/0df49ce7b9582e4f8805ab237a8b7319bae0dc27ac2ef74932ce16c20d667d96","stationName":"studio","time":{"lastActiveAt":{"at":1792610059514,"ago":"刚刚","full":"10/22 03:14:19","until":"1 分钟内","past":true}},"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"peopleText":"你 发起","clientKey":"new:chat-4c7c0fcd5ee1d829a2","pinned":false,"tone":"done"}]}],"trouble":null,"members":1,"leading":"agents","glyph":{"online":1,"dim":0,"connecting":0,"failing":0,"working":0,"summary":"studio","label":"1 台 station，1 台在线"},"note":{"reading":false,"text":null,"failing":[],"empty":false}}},"w":1792610060967.048}
  #|{"in":{"id":8,"value":{"app":"desktop","tabs":[{"part":"desktop","label":"桌面","days":[]},{"part":"web","label":"网页","days":[]},{"part":"android","label":"安卓","days":[]},{"part":"station","label":"Station","days":[]},{"part":"cloud","label":"云端","days":[]}],"loading":false}},"w":1792610060967.067}
  #|{"in":{"id":9,"value":{"workspaces":{"01M5FY5DA1GD828B38YK5K8SGK":{"alert":0,"unread":1,"tone":"done","label":"1 个有新消息","badge":0,"items":[],"mineTone":"done"}},"badge":0,"badgeCounts":"attention","badgeKinds":{"on":true,"wait":true,"failed":true,"done":false,"message":false}}},"w":1792610060967.073}
  #|{"in":{"id":10,"value":{"items":[]}},"w":1792610060967.078}
  #|{"in":{"id":11,"value":{"pairing":[]}},"w":1792610060967.08}
  #|{"in":{"id":12,"ok":null},"w":1792610060967.082}
  #|{"in":{"id":13,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792610060967.087}
  #|{"in":{"id":14,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792610060967.091}
  #|{"out":{"id":15,"subscribe":{"topic":"longJobs","scope":"01M5FY5DA1GD828B38YK5K8SGK"},"keyed":true},"w":1792610060967.121}
  #|{"out":{"id":16,"call":"notify.permission","params":{"state":"unknown"}},"w":1792610060969.523}
  #|{"in":{"id":15,"value":{"groups":[]}},"w":1792610060983.61}
  #|{"in":{"id":16,"ok":null},"w":1792610060983.635}
  #|{"step":"answered notify.permission","w":1792610060983.88}
  #|{"step":"tap icon:settings","w":1792610061000.509}
  #|{"step":"tap icon:settings","acted":true,"w":1792610061000.528}
  #|{"out":{"id":17,"subscribe":{"topic":"workspace","workspace":"01M5FY5DA1GD828B38YK5K8SGK"},"keyed":true},"w":1792610061017.139}
  #|{"out":{"id":18,"subscribe":{"topic":"stations","scope":"01M5FY5DA1GD828B38YK5K8SGK"},"keyed":true},"w":1792610061017.151}
  #|{"out":{"id":19,"subscribe":{"topic":"connects","scope":"01M5FY5DA1GD828B38YK5K8SGK","mine":false},"keyed":true},"w":1792610061017.157}
  #|{"out":{"id":20,"subscribe":{"topic":"vaults","workspace":"01M5FY5DA1GD828B38YK5K8SGK"},"keyed":true},"w":1792610061017.164}
  #|{"out":{"id":21,"subscribe":{"topic":"doing"},"keyed":true},"w":1792610061019.857}
  #|{"out":{"id":22,"call":"cache.usage","params":{}},"w":1792610061020.701}
  #|{"step":"answered cache.usage","w":1792610061020.893}
  #|{"in":{"id":17,"value":{"id":"01M5FY5DA1GD828B38YK5K8SGK","name":"Dev","role":"owner","created_at":1792610055,"members":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":"https://example.test/p.png","role":"owner","added_at":1792610055}],"stations":[{"id":"0df49ce7b9582e4f8805ab237a8b7319bae0dc27ac2ef74932ce16c20d667d96","name":"studio","emoji":null,"icon":null,"enrolled_at":1792610056,"enrolled_by":"alice","last_seen":1792610059,"version":"0.1.0","time":{"last_seen":{"past":true,"at":1792610059000,"ago":"刚刚","full":"10/22 03:14:19","until":"1 分钟内"}}}],"invitations":[],"added":[],"relays":[],"lock":null,"lock_requests":0,"time":{"created_at":{"past":true,"at":1792610055000,"ago":"刚刚","full":"10/22 03:14:15","until":"1 分钟内"}}}},"w":1792610061033.603}
  #|{"in":{"id":18,"value":[{"station":"01M5FY5DA1GD828B38YK5K8SGK/0df49ce7b9582e4f8805ab237a8b7319bae0dc27ac2ef74932ce16c20d667d96","id":"0df49ce7b9582e4f8805ab237a8b7319bae0dc27ac2ef74932ce16c20d667d96","name":"studio","summary":"正在连接","face":"idle","line":"在线","online":true,"reconnecting":false,"lastSeen":1792610059,"version":"0.1.0","link":{"state":"online"},"runtimes":[{"runtime":"claude","models":["claude-sonnet-5-5"]}],"models":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792610059426,"time":{"checkedAt":{"at":1792610059426,"ago":"刚刚","full":"10/22 03:14:19","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"overview":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null,"summaryText":"最近 7 天检查了 0 个 chat","changeText":null}},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","email":"alice@example.test","name":"Name of alice","sub":"alice","role":"owner","workspace":"01M5FY5DA1GD828B38YK5K8SGK","device":"64f8e7fc2067d6dff4be792d7538e0bd18113bc19ec3362d4b40415f6cfc65bf"},"connects":[],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792610059299,"time":{"checkedAt":{"at":1792610059299,"ago":"刚刚","full":"10/22 03:14:19","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792610059426,"time":{"checkedAt":{"at":1792610059426,"ago":"刚刚","full":"10/22 03:14:19","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"modelsReading":false,"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]}],"processes":[],"counts":{"sessions":1,"running":0,"warm":1},"mesh":{"state":"running","origin":"http://127.0.0.1:18787","station":"0df49ce7b9582e4f8805ab237a8b7319bae0dc27ac2ef74932ce16c20d667d96","workspace":"Dev","workspaceId":"01M5FY5DA1GD828B38YK5K8SGK","name":"studio"},"slackUsers":[],"slackTeams":[],"slackApps":[],"feishuRegistrations":[],"disk":{"freeBytes":28381765632,"totalBytes":245107195904},"logins":[],"machineLogins":[],"sharing":true,"consoleSignIn":true,"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"google","name":"Google Gemini","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xai","name":"xAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"mistral","name":"Mistral","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"deepseek","name":"DeepSeek","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen","name":"Qwen","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai","name":"Kimi","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"kimi-code","name":"Kimi Code","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai","name":"Z.ai","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax","name":"MiniMax","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ant-ling","name":"Ant Ling","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"jev","name":"Jev","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen-cn","name":"Qwen (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"openrouter","name":"OpenRouter","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"opencode","name":"OpenCode Zen","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"groq","name":"Groq","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"together","name":"Together AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"fireworks","name":"Fireworks","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cerebras","name":"Cerebras","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"huggingface","name":"Hugging Face","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"nvidia","name":"NVIDIA","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"baseten","name":"Baseten","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ollama","name":"Ollama","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"custom","name":"Custom","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""}],"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792610056871},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.306","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792610056871},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-icon/apps/e2e-local/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792610056871},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-icon/apps/e2e-local/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792610056871},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","latest":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-icon/apps/e2e-local/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792610056871},{"id":"cursor","name":"Cursor","installed":false,"latest":"1.0.40","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792610056871},{"id":"devin","name":"Devin","installed":true,"version":"3000.11.92","latest":"3000.11.92","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-icon/apps/e2e-local/ember/station/test/fake/devin，不是用 Devin 的安装脚本装的，需在该机器上手动更新","state":"idle","checkedAt":1792610056871}],"processesText":"没有运行中的 agent 进程","agentEnv":[],"drive":{"roots":[],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false}},"betaOffered":false,"way":{"path":"直连","via":"direct"},"time":{"lastSeen":{"at":1792610059000,"ago":"刚刚","full":"10/22 03:14:19","until":"1 分钟内","past":true}},"joined":false}]},"w":1792610061033.718}
  #|{"in":{"id":19,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"items":[],"wait":{"reading":false,"text":null,"failing":[],"empty":true}}},"w":1792610061033.795}
  #|{"in":{"id":20,"value":{"available":true,"locked":false,"canSign":false,"setUp":false,"vaults":[{"id":"plain","name":"个人","owner":"alice","ownerName":"Name of alice","mine":true,"members":[{"sub":"alice","name":"Name of alice"}],"station":"0df49ce7b9582e4f8805ab237a8b7319bae0dc27ac2ef74932ce16c20d667d96","stationName":"studio","items":0,"devices":0,"open":true,"keyed":true,"missing":0,"recoverable":false}],"requests":[],"refused":[{"station":"0df49ce7b9582e4f8805ab237a8b7319bae0dc27ac2ef74932ce16c20d667d96","name":"studio","code":"vault_needs_lock"}],"plain":true}},"w":1792610061033.804}
  #|{"in":{"id":21,"value":{"doing":[]}},"w":1792610061033.811}
  #|{"in":{"id":22,"ok":{"chats":[{"station":"01M5FY5DA1GD828B38YK5K8SGK/0df49ce7b9582e4f8805ab237a8b7319bae0dc27ac2ef74932ce16c20d667d96","thread":1,"title":null,"sessions":["ember:c-27d1d4baaf"],"bytes":558}]}},"w":1792610061033.815}
  #|{"step":"wait 299","w":1792610061050.758}
  #|{"in":{"id":18,"delta":[{"path":[0,"host"],"set":{"hostname":"3720-Mac-mini-1","os":"macOS 27.0.1","arch":"arm64","cpus":10,"cpuModel":"Apple M4","load":0.19,"cpuBusy":0.12,"uptimeSec":89423,"memory":{"totalBytes":17179869184,"usedBytes":10191405056,"swapUsedBytes":216793088},"disk":{"path":"/tmp/mbe2e-C/data","totalBytes":245107195904,"freeBytes":28381642752},"emberRssBytes":162266424,"checkedAt":1792610061057,"summary":"10 核 · 16 GB","line":"macOS 27.0.1 · 10 核 · 16 GB · 已运行 1 天","facts":["3720-Mac-mini-1","macOS 27.0.1","arm64 · 10 核","已运行 1 天 0 小时"],"meters":[{"label":"CPU","short":"CPU","percent":12,"left":88,"level":"ok","value":"12%","remaining":"空闲 88%","big":"88","unit":"%","title":"CPU 空闲","total":"负载 1.9","note":"负载 1.9 · Apple M4"},{"label":"内存","short":"内存","percent":59,"left":41,"level":"ok","value":"9.5 GB / 16.0 GB","remaining":"剩 6.5 G","big":"6.5","unit":"GB","title":"内存剩","total":"共 16 GB","note":"swap 0.2 GB"},{"label":"磁盘","short":"磁盘","percent":88,"left":12,"level":"amber","value":"剩余 26.4 GB / 228 GB","remaining":"剩 26.4 G","big":"26.4","unit":"GB","title":"磁盘剩","total":"共 228 GB"}],"identity":"Apple M4 · 16 GB · macOS 27.0.1","details":[{"label":"主机名","value":"3720-Mac-mini-1"},{"label":"芯片","value":"Apple M4 · 10 核 · arm64"},{"label":"已运行","value":"1 天 0 小时"},{"label":"still.fail","value":"进程占用 155 MB"}],"usage":"内存 9.5 GB / 16.0 GB · 磁盘 剩余 26.4 GB / 228 GB","emberText":"still.fail 155 MB"}},{"path":[0,"line"],"set":"Apple M4"},{"path":[0,"summary"],"set":"空闲 · Apple M4 · 16 GB · macOS 27.0.1"}]},"w":1792610061083.67}
  #|{"step":"now tap =Workspace","w":1792610061351.343}
  #|{"step":"now tap =Workspace","acted":true,"w":1792610061351.415}
  #|{"out":{"id":23,"call":"picture","params":{"url":"https://example.test/p.png"}},"w":1792610061373.842}
  #|{"step":"answered picture","w":1792610061378.756}
  #|{"in":{"id":23,"error":{"code":"picture","message":"无法加载图片：error sending request for url (https://example.test/p.png): client error (Connect): tls handshake eof"}},"w":1792610061550.299}
  #|{"step":"wait 300","w":1792610061568.086}
  #|{"step":"now until alice@example.test","w":1792610061904.685}
  #|{"step":"tap icon:user-plus","w":1792610061904.716}
  #|{"step":"tap icon:user-plus","acted":true,"w":1792610061904.748}
  #|{"step":"wait 1455","w":1792610061921.038}
  #|{"step":"now until 添加成员","w":1792610063388.499}
  #|{"step":"tap name@example.com","w":1792610063388.546}
  #|{"step":"tap name@example.com","acted":true,"w":1792610063388.603}
  #|{"step":"type e2e-080726@example.test","w":1792610063412.409}
  #|{"step":"type e2e-080726@example.test","acted":true,"w":1792610063412.445}
  #|{"step":"tap =添加","w":1792610063423.106}
  #|{"step":"tap =添加","acted":true,"w":1792610063423.149}
  #|{"out":{"id":24,"call":"workspace.addMembers","params":{"workspace":"01M5FY5DA1GD828B38YK5K8SGK","role":"member","emails":["e2e-080726@example.test"],"account":"alice"}},"w":1792610063437.79}
  #|{"step":"answered workspace.addMembers","w":1792610063439.819}
  #|{"in":{"id":24,"ok":{"joined":[],"added":["e2e-080726@example.test"],"already":[],"view":{"id":"01M5FY5DA1GD828B38YK5K8SGK","name":"Dev","role":"owner","created_at":1792610055,"members":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":"https://example.test/p.png","role":"owner","added_at":1792610055}],"stations":[{"id":"0df49ce7b9582e4f8805ab237a8b7319bae0dc27ac2ef74932ce16c20d667d96","name":"studio","emoji":null,"icon":null,"enrolled_at":1792610056,"enrolled_by":"alice","last_seen":1792610059,"version":"0.1.0"}],"invitations":[],"added":[{"email":"e2e-080726@example.test","role":"member","added_by":"alice","added_at":1792610063}],"relays":[],"lock":null,"lock_requests":0}}},"w":1792610063487.348}
  #|{"in":{"id":17,"delta":[{"path":["added"],"append":[{"email":"e2e-080726@example.test","role":"member","added_by":"alice","added_at":1792610063}]}]},"w":1792610063503.983}
  #|{"in":{"id":18,"delta":[{"path":[0,"overview","disk","freeBytes"],"set":28383711232}]},"w":1792610063503.994}
  #|{"step":"until =完成","w":1792610063505.124}
  #|{"step":"tap =完成","w":1792610063505.13}
  #|{"step":"tap =完成","acted":true,"w":1792610063505.137}
  #|{"step":"wait 1455","w":1792610063534.163}
  #|{"step":"now until e2e-080726@example.test","w":1792610065000.847}
  #|{"step":"tap =移除","w":1792610065000.884}
  #|{"step":"tap =移除","acted":true,"w":1792610065000.915}
  #|{"out":{"id":25,"call":"workspace.removeAdded","params":{"workspace":"01M5FY5DA1GD828B38YK5K8SGK","email":"e2e-080726@example.test","account":"alice"}},"w":1792610065017.286}
  #|{"step":"answered workspace.removeAdded","w":1792610065017.706}
  #|{"in":{"id":25,"ok":{"id":"01M5FY5DA1GD828B38YK5K8SGK","name":"Dev","role":"owner","created_at":1792610055,"members":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":"https://example.test/p.png","role":"owner","added_at":1792610055}],"stations":[{"id":"0df49ce7b9582e4f8805ab237a8b7319bae0dc27ac2ef74932ce16c20d667d96","name":"studio","emoji":null,"icon":null,"enrolled_at":1792610056,"enrolled_by":"alice","last_seen":1792610059,"version":"0.1.0"}],"invitations":[],"added":[],"relays":[],"lock":null,"lock_requests":0}},"w":1792610065066.938}
  #|{"step":"gone e2e-080726@example.test","w":1792610065083.856}
  #|{"in":{"id":17,"delta":[{"path":["added"],"set":[]}]},"w":1792610065100.258}
  #|{"step":"tap =Workspace 图标","w":1792610065100.837}
  #|{"step":"tap =Workspace 图标","acted":true,"w":1792610065100.875}
  #|{"in":{"id":18,"delta":[{"path":[0,"overview","disk","freeBytes"],"set":28383608832}]},"w":1792610065116.954}
  #|{"step":"wait 1454","w":1792610065117.421}
  #|{"step":"now tap =Emoji","w":1792610066585.118}
  #|{"step":"now tap =Emoji","acted":true,"w":1792610066585.173}
  #|{"step":"tap 粘贴或输入任意 emoji","w":1792610066601.713}
  #|{"step":"tap 粘贴或输入任意 emoji","acted":true,"w":1792610066641.399}
  #|{"step":"paste 🌲","w":1792610066651.637}
  #|{"step":"paste 🌲","acted":true,"w":1792610066652.269}
  #|{"out":{"id":26,"call":"workspace.rename","params":{"workspace":"01M5FY5DA1GD828B38YK5K8SGK","emoji":"🌲","icon":"","account":"alice"}},"w":1792610066670.93}
  #|{"step":"answered workspace.rename","w":1792610066671.793}
  #|{"in":{"id":21,"value":{"doing":[{"call":"workspace.rename","params":{"workspace":"01M5FY5DA1GD828B38YK5K8SGK","emoji":"🌲","icon":"","account":"alice"},"since":1792610066671,"stage":"running"}]}},"w":1792610066737.407}
  #|{"in":{"id":4,"delta":[{"path":[0,"workspaces",0,"emoji"],"set":"🌲"}]},"w":1792610066737.453}
  #|{"in":{"id":17,"delta":[{"path":["emoji"],"set":"🌲"}]},"w":1792610066737.478}
  #|{"in":{"id":26,"ok":{"id":"01M5FY5DA1GD828B38YK5K8SGK","name":"Dev","emoji":"🌲","role":"owner","created_at":1792610055,"members":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":"https://example.test/p.png","role":"owner","added_at":1792610055}],"stations":[{"id":"0df49ce7b9582e4f8805ab237a8b7319bae0dc27ac2ef74932ce16c20d667d96","name":"studio","emoji":null,"icon":null,"enrolled_at":1792610056,"enrolled_by":"alice","last_seen":1792610059,"version":"0.1.0"}],"invitations":[],"added":[],"relays":[],"lock":null,"lock_requests":0}},"w":1792610066737.51}
  #|{"step":"until 已设置图标","w":1792610066754.517}
  #|{"step":"wait 1454","w":1792610066754.538}
  #|{"in":{"id":21,"value":{"doing":[]}},"w":1792610066887.428}
  #|{"in":{"id":18,"delta":[{"path":[0,"overview","disk","freeBytes"],"set":28399714304}]},"w":1792610066887.498}
  #|{"step":"now until =🌲","w":1792610068238.09}
  #|{"step":"tap =Workspace 图标","w":1792610068238.132}
  #|{"step":"tap =Workspace 图标","acted":true,"w":1792610068238.162}
  #|{"step":"wait 1454","w":1792610068254.788}
  #|{"step":"now tap =图标","w":1792610069722.135}
  #|{"step":"now tap =图标","acted":true,"w":1792610069722.167}
  #|{"step":"tap 搜索图标","w":1792610069739.974}
  #|{"step":"tap 搜索图标","acted":true,"w":1792610069740.025}
  #|{"step":"type zzzz","w":1792610069755.276}
  #|{"step":"type zzzz","acted":true,"w":1792610069755.31}
  #|{"step":"tap 不使用图标","w":1792610069773.429}
  #|{"step":"tap 不使用图标","acted":true,"w":1792610069773.463}
  #|{"out":{"id":27,"call":"workspace.rename","params":{"workspace":"01M5FY5DA1GD828B38YK5K8SGK","emoji":"","icon":"","account":"alice"}},"w":1792610069787.715}
  #|{"step":"answered workspace.rename","w":1792610069788.161}
  #|{"in":{"id":27,"ok":{"id":"01M5FY5DA1GD828B38YK5K8SGK","name":"Dev","role":"owner","created_at":1792610055,"members":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":"https://example.test/p.png","role":"owner","added_at":1792610055}],"stations":[{"id":"0df49ce7b9582e4f8805ab237a8b7319bae0dc27ac2ef74932ce16c20d667d96","name":"studio","emoji":null,"icon":null,"enrolled_at":1792610056,"enrolled_by":"alice","last_seen":1792610059,"version":"0.1.0"}],"invitations":[],"added":[],"relays":[],"lock":null,"lock_requests":0}},"w":1792610069854.059}
  #|{"in":{"id":4,"delta":[{"path":[0,"workspaces",0,"emoji"],"remove":true}]},"w":1792610069854.09}
  #|{"in":{"id":17,"delta":[{"path":["emoji"],"remove":true}]},"w":1792610069854.097}
  #|{"in":{"id":18,"delta":[{"path":[0,"overview","disk","freeBytes"],"set":28379418624}]},"w":1792610069854.102}
  #|{"step":"wait 1454","w":1792610069871.42}
  #|{"step":"","w":1792610071354.474}
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
  #|{"textrec":{"ib":["a7ccae3554fe46cf",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["bef2954d97ce1d9f",6508,64],"r":[40,40,40,40]}}
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
  #|{"textrec":{"s":[32,700,8,"Dev"],"r":[0,1,22.8046875,197,1,1,17.5390625,198,2,1,17.3046875,199]}}
  #|{"textrec":{"s":[13,400,0,"你是Owner · 1 人 · 1 台 station · 点击名称可重命名"],"r":[0,1,12.898832684824903,4,1,1,12.898832684824903,200,2,1,11.578125,201,3,1,9.9912109375,6,4,1,7.50927734375,202,5,1,7.3505859375,14,6,1,4.875,8,7,1,3.580078125,-1,8,1,6.228545204222115,203,9,1,3.580078125,-1,10,1,5.9541015625,204,11,1,3.580078125,-1,12,1,12.89883268482491,205,13,1,3.580078125,-1,14,1,6.228545204222115,203,15,1,3.580078125,-1,16,1,5.9541015625,204,17,1,3.580078125,-1,18,1,12.898832684824896,206,19,1,3.580078125,-1,20,1,6.69677734375,10,21,1,4.61474609375,82,22,1,7.0966796875,12,23,1,4.646484375,82,24,1,3.1357421875,77,25,1,7.6044921875,7,26,1,7.50927734375,202,27,1,3.580078125,-1,28,1,6.228545204222115,203,29,1,3.580078125,-1,30,1,12.898832684824896,207,31,1,12.898832684824896,208,32,1,12.898832684824896,209,33,1,12.898832684824896,210,34,1,12.898832684824924,211,35,1,12.898832684824924,212,36,1,12.898832684824924,213,37,1,12.898832684824924,209]}}
  #|{"textrec":{"s":[14,400,0,"未设置"],"r":[0,1,13.891050583657588,96,1,1,13.891050583657588,214,2,1,13.891050583657588,215]}}
  #|{"textrec":{"s":[15,400,0,"Workspace 图标"],"r":[0,1,13.916015625,87,1,1,8.26171875,88,2,1,5.478515625,89,3,1,7.763671875,90,4,1,7.470703125,91,5,1,8.9208984375,92,6,1,8.0419921875,93,7,1,8.1591796875,94,8,1,8.3349609375,95,9,1,3.984375,-1,10,1,14.88326848249028,216,11,1,14.88326848249028,217]}}
  #|{"textrec":{"s":[15,600,0,"成员"],"r":[0,1,14.883268482490273,218,1,1,14.883268482490273,219]}}
  #|{"textrec":{"s":[13,400,0,"1 人"],"r":[0,1,5.9541015625,204,1,1,3.580078125,-1,2,1,12.898832684824903,205]}}
  #|{"textrec":{"s":[13,400,0,"Owner"],"r":[0,1,9.953125,201,1,1,9.9912109375,6,2,1,7.50927734375,202,3,1,7.3505859375,14,4,1,4.875,8]}}
  #|{"textrec":{"s":[15,400,0,"Name of alice"],"r":[0,1,10.8984375,220,1,1,8.0419921875,93,2,1,12.8173828125,161,3,1,8.3349609375,95,4,1,3.984375,-1,5,1,8.6279296875,88,6,1,5.19287109375,107,7,1,3.984375,-1,8,1,8.0419921875,93,9,1,3.5595703125,108,10,1,3.4716796875,102,11,1,8.1591796875,94,12,1,8.3349609375,95]}}
  #|{"textrec":{"s":[12,400,0,"你"],"r":[0,1,11.918287937743191,221]}}
  #|{"textrec":{"m":[12,400,0],"r":[11.6015625,2.53125,17,11.6015625,2.53125,0]}}
  #|{"textrec":{"s":[14,600,0,"N"],"r":[0,1,10.469682216644287,222]}}
  #|{"textrec":{"m":[14,600,0],"r":[13.53515625,2.953125,20,13.53515625,2.953125,0]}}
  #|{"textrec":{"s":[15,600,0,"中继"],"r":[0,1,14.883268482490273,223,1,1,14.883268482490273,224]}}
  #|{"textrec":{"s":[15,400,0,"添加中继"],"r":[0,1,14.883268482490273,225,1,1,14.883268482490273,226,2,1,14.883268482490273,227,3,1,14.883268482490273,228]}}
  #|{"textrec":{"s":[13,400,0,"除 still.fail 的中继外，station 和成员设备也会通过这些中继连接，并自动选择最快的。"],"r":[0,1,12.898832684824903,229,1,1,3.580078125,-1,2,1,6.69677734375,10,3,1,4.61474609375,82,4,1,3.1357421875,77,5,1,3.2119140625,76,6,1,3.2119140625,76,7,1,3.5927734375,81,8,1,4.341796875,230,9,1,7.00146484375,12,10,1,3.1357421875,77,11,1,3.2119140625,76,12,1,3.580078125,-1,13,1,12.898832684824903,5,14,1,12.89883268482491,231,15,1,12.898832684824896,232,16,1,12.898832684824896,233,17,1,11.775875486381324,234,18,1,6.69677734375,10,19,1,4.61474609375,82,20,1,7.0966796875,12,21,1,4.646484375,82,22,1,3.1357421875,77,23,1,7.6044921875,7,24,1,7.50927734375,202,25,1,3.580078125,-1,26,1,12.898832684824896,235,27,1,12.898832684824896,140,28,1,12.898832684824896,236,29,1,12.898832684824896,237,30,1,12.898832684824896,238,31,1,12.898832684824896,239,32,1,12.898832684824924,240,33,1,12.898832684824924,154,34,1,12.898832684824924,241,35,1,12.898832684824924,242,36,1,12.898832684824924,243,37,1,12.898832684824924,231,38,1,12.898832684824924,232,39,1,12.898832684824924,244,40,1,12.898832684824924,245,41,1,13.075875486381335,234,42,1,12.898832684824924,246,43,1,12.898832684824924,247,44,1,12.898832684824924,248,45,1,12.898832684824924,249,46,1,12.898832684824924,250,47,1,12.898832684824924,251,48,1,12.898832684824924,252,49,1,12.898832684824924,5,50,1,6.575875486381335,253]}}
  #|{"textrec":{"s":[15,400,0,"退出此 workspace"],"r":[0,1,14.883268482490273,254,1,1,14.883268482490273,255,2,1,14.883268482490273,256,3,1,3.984375,-1,4,1,11.2353515625,257,5,1,8.481445312499993,88,6,1,5.478515625,89,7,1,7.763671875,90,8,1,7.470703125,91,9,1,8.9208984375,92,10,1,8.0419921875,93,11,1,8.1591796875,94,12,1,8.3349609375,95]}}
  #|{"textrec":{"s":[15,400,0,"删除 workspace"],"r":[0,1,14.883268482490273,258,1,1,14.883268482490273,259,2,1,3.984375,-1,3,1,11.2353515625,257,4,1,8.4814453125,88,5,1,5.478515625,89,6,1,7.763671875,90,7,1,7.470703125,91,8,1,8.9208984375,92,9,1,8.0419921875,93,10,1,8.1591796875,94,11,1,8.3349609375,95]}}
  #|{"textrec":{"g":195,"r":[2000,0,19,18,-1,-15,0]}}
  #|{"textrec":{"g":196,"r":[2020,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":197,"r":[0,32,23,25,0,-24,0]}}
  #|{"textrec":{"g":198,"r":[24,32,19,21,-1,-19,0]}}
  #|{"textrec":{"g":199,"r":[44,32,19,19,-1,-18,0]}}
  #|{"textrec":{"g":4,"r":[64,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":200,"r":[79,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":201,"r":[94,32,12,13,-1,-11,0]}}
  #|{"textrec":{"g":6,"r":[107,32,12,9,-1,-8,0]}}
  #|{"textrec":{"g":202,"r":[120,32,8,9,0,-8,0]}}
  #|{"textrec":{"g":8,"r":[129,32,6,9,0,-8,0]}}
  #|{"textrec":{"g":203,"r":[136,32,4,5,1,-7,0]}}
  #|{"textrec":{"g":204,"r":[141,32,7,12,-1,-11,0]}}
  #|{"textrec":{"g":205,"r":[149,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":206,"r":[165,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":7,"r":[179,32,9,10,-1,-8,0]}}
  #|{"textrec":{"g":207,"r":[189,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":208,"r":[205,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":209,"r":[220,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":210,"r":[235,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":211,"r":[251,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":212,"r":[266,32,14,14,-1,-12,0]}}
  #|{"textrec":{"g":213,"r":[281,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":216,"r":[297,32,15,16,0,-13,0]}}
  #|{"textrec":{"g":217,"r":[313,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":218,"r":[330,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":219,"r":[348,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":223,"r":[365,32,15,17,0,-14,0]}}
  #|{"textrec":{"g":224,"r":[381,32,16,17,-1,-14,0]}}
  #|{"textrec":{"g":225,"r":[398,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":226,"r":[416,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":227,"r":[433,32,15,16,0,-13,0]}}
  #|{"textrec":{"g":228,"r":[449,32,16,16,-1,-14,0]}}
  #|{"textrec":{"g":229,"r":[466,32,14,15,0,-12,0]}}
  #|{"textrec":{"g":230,"r":[481,32,7,12,-1,-11,0]}}
  #|{"textrec":{"g":5,"r":[489,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":231,"r":[503,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":232,"r":[517,32,15,14,-1,-12,0]}}
  #|{"textrec":{"g":233,"r":[533,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":234,"r":[549,32,5,7,0,-3,0]}}
  #|{"textrec":{"g":235,"r":[555,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":140,"r":[570,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":236,"r":[586,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":237,"r":[601,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":238,"r":[617,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":239,"r":[633,32,15,14,-1,-12,0]}}
  #|{"textrec":{"g":240,"r":[649,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":154,"r":[665,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":241,"r":[681,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":242,"r":[697,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":243,"r":[713,32,14,14,-1,-12,0]}}
  #|{"textrec":{"g":244,"r":[728,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":245,"r":[744,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":246,"r":[760,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":247,"r":[775,32,11,15,1,-12,0]}}
  #|{"textrec":{"g":248,"r":[787,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":249,"r":[802,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":250,"r":[818,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":251,"r":[834,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":252,"r":[849,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":253,"r":[865,32,6,6,0,-3,0]}}
  #|{"textrec":{"g":254,"r":[872,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":255,"r":[889,32,15,16,0,-13,0]}}
  #|{"textrec":{"g":256,"r":[905,32,16,15,-1,-13,0]}}
  #|{"textrec":{"g":257,"r":[922,32,14,10,-1,-9,0]}}
  #|{"textrec":{"g":258,"r":[937,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":259,"r":[954,32,16,16,0,-13,0]}}
  #|{"textrec":{"g":222,"r":[971,32,11,12,0,-11,0]}}
  #|{"textrec":{"g":220,"r":[983,32,11,13,0,-12,0]}}
  #|{"textrec":{"g":161,"r":[995,32,13,11,0,-10,0]}}
  #|{"textrec":{"g":221,"r":[1009,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":214,"r":[1024,32,16,15,-1,-12,0]}}
  #|{"textrec":{"g":215,"r":[1041,32,15,15,-1,-12,0]}}
  #|{"textrec":{"ib":["58f428943dcf9c03",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"s":[17,700,0,"添加成员"],"r":[0,1,16.851167315175097,260,1,1,16.851167315175097,261,2,1,16.851167315175097,262,3,1,16.851167315175097,263]}}
  #|{"textrec":{"m":[17,700,0],"r":[16.435546875,3.5859375,24,16.435546875,3.5859375,0]}}
  #|{"textrec":{"s":[14,400,0,"成员会直接加入「Dev」，无需对方接受：登录过 still.fail 的人立即加入，其他人首次用此邮箱登录时自动加入。"],"r":[0,1,13.891050583657588,264,1,1,13.891050583657588,265,2,1,13.891050583657588,266,3,1,13.891050583657588,267,4,1,13.891050583657588,268,5,1,13.891050583657588,269,6,1,20.891050583657588,270,7,1,5.066147859922182,271,8,1,10.021484375,272,9,1,7.779296875,59,10,1,7.369140624999986,273,11,1,6.543774319066159,274,12,1,14.081712062256798,50,13,1,13.891050583657602,275,14,1,13.891050583657602,276,15,1,13.891050583657602,277,16,1,13.891050583657602,278,17,1,13.891050583657602,268,18,1,13.891050583657602,279,19,1,14.081712062256798,280,20,1,13.891050583657574,281,21,1,13.891050583657602,282,22,1,13.891050583657602,283,23,1,3.787109375,-1,24,1,7.1435546875,284,25,1,4.9013671875,61,26,1,3.30859375,285,27,1,3.390625,286,28,1,3.390625,286,29,1,3.80078125,287,30,1,4.607421875,288,31,1,7.4716796875,57,32,1,3.30859375,285,33,1,3.390625,286,34,1,3.787109375,-1,35,1,13.891050583657602,56,36,1,13.891050583657602,183,37,1,13.891050583657602,289,38,1,13.891050583657602,290,39,1,13.891050583657602,269,40,1,13.891050583657602,270,41,1,14.081712062256827,50,42,1,13.891050583657602,291,43,1,13.891050583657602,292,44,1,13.891050583657602,183,45,1,13.891050583657602,293,46,1,13.891050583657602,294,47,1,13.891050583657602,55,48,1,13.891050583657602,295,49,1,13.891050583657602,296,50,1,13.891050583657602,297,51,1,13.891050583657602,281,52,1,13.891050583657602,282,53,1,13.891050583657602,298,54,1,13.891050583657602,299,55,1,13.891050583657602,300,56,1,13.891050583657602,269,57,1,13.891050583657602,270,58,1,7.08171206225677,301]}}
  #|{"textrec":{"s":[13,600,0,"邮箱"],"r":[0,1,12.898832684824903,302,1,1,12.898832684824903,303]}}
  #|{"textrec":{"m":[13,600,0],"r":[12.568359375,2.7421875,18,12.568359375,2.7421875,0]}}
  #|{"textrec":{"s":[14,600,0,"从 Slack 选择成员"],"r":[0,1,13.891050583657588,304,1,1,3.5793075561523438,-1,2,1,9.106021165847778,305,3,1,3.762936592102051,306,4,1,7.909732103347778,307,5,1,7.930358409881592,308,6,1,7.9685118198394775,309,7,1,3.5793075561523438,-1,8,1,13.891050583657588,310,9,1,13.891050583657588,311,10,1,13.891050583657588,312,11,1,13.891050583657588,313]}}
  #|{"textrec":{"s":[13,600,0,"角色"],"r":[0,1,12.898832684824903,314,1,1,12.898832684824903,315]}}
  #|{"textrec":{"s":[15,400,0,"成员"],"r":[0,1,14.883268482490273,316,1,1,14.883268482490273,317]}}
  #|{"textrec":{"s":[12,400,0,"使用 workspace 里的 station"],"r":[0,1,11.918287937743191,318,1,1,11.918287937743191,319,2,1,3.375,-1,3,1,9.17578125,320,4,1,6.97265625,321,5,1,4.5703125,322,6,1,6.3984375,323,7,1,6.1640625,324,8,1,7.324218749999993,325,9,1,6.62109375,326,10,1,6.71484375,327,11,1,6.85546875,328,12,1,3.375,-1,13,1,11.918287937743187,329,14,1,11.918287937743187,330,15,1,3.375,-1,16,1,6.251953125,324,17,1,4.330078125,331,18,1,6.62109375,326,19,1,4.359375,331,20,1,2.96484375,332,21,1,7.08984375,321,22,1,7.001953125,333]}}
  #|{"textrec":{"s":[15,400,0,"管理员"],"r":[0,1,14.883268482490273,334,1,1,14.883268482490273,335,2,1,14.883268482490273,317]}}
  #|{"textrec":{"s":[12,400,0,"邀请成员、添加和移除 station"],"r":[0,1,11.918287937743191,336,1,1,11.918287937743191,337,2,1,11.918287937743195,338,3,1,11.918287937743187,339,4,1,12.081712062256813,340,5,1,11.918287937743187,341,6,1,11.918287937743187,342,7,1,11.918287937743187,343,8,1,11.918287937743187,344,9,1,11.918287937743187,345,10,1,3.375,-1,11,1,6.251953124999986,324,12,1,4.330078125,331,13,1,6.62109375,326,14,1,4.359375,331,15,1,2.96484375,332,16,1,7.08984375,321,17,1,7.001953125,333]}}
  #|{"textrec":{"s":[15,400,0,"Owner"],"r":[0,1,11.337890625,346,1,1,11.3818359375,257,2,1,8.51806640625,103,3,1,8.3349609375,95,4,1,5.478515625,89]}}
  #|{"textrec":{"s":[12,400,0,"管理所有内容，包括成员角色和删除 workspace"],"r":[0,1,11.918287937743191,347,1,1,11.918287937743191,348,2,1,11.918287937743195,349,3,1,11.918287937743187,350,4,1,11.918287937743187,351,5,1,11.918287937743187,352,6,1,12.081712062256813,353,7,1,11.918287937743187,354,8,1,11.918287937743187,355,9,1,11.918287937743187,338,10,1,11.918287937743187,339,11,1,11.918287937743202,356,12,1,11.918287937743202,357,13,1,11.918287937743202,343,14,1,11.918287937743202,358,15,1,11.918287937743202,345,16,1,3.375,-1,17,1,9.17578125,320,18,1,6.97265625,321,19,1,4.5703125,322,20,1,6.3984375,323,21,1,6.1640625,324,22,1,7.32421875,325,23,1,6.62109375,326,24,1,6.71484375,327,25,1,6.85546875,328]}}
  #|{"textrec":{"s":[14,600,0,"取消"],"r":[0,1,13.891050583657588,359,1,1,13.891050583657588,360]}}
  #|{"textrec":{"s":[14,600,0,"添加"],"r":[0,1,13.891050583657588,361,1,1,13.891050583657588,362]}}
  #|{"textrec":{"g":260,"r":[1057,32,19,18,-1,-15,0]}}
  #|{"textrec":{"g":261,"r":[1077,32,18,18,-1,-15,0]}}
  #|{"textrec":{"g":262,"r":[1096,32,19,18,-1,-15,0]}}
  #|{"textrec":{"g":263,"r":[1116,32,18,18,-1,-15,0]}}
  #|{"textrec":{"g":264,"r":[1135,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":265,"r":[1152,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":266,"r":[1168,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":267,"r":[1185,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":268,"r":[1201,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":269,"r":[1217,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":270,"r":[1233,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":271,"r":[1250,32,7,12,-1.333333333333333,-13,0]}}
  #|{"textrec":{"g":272,"r":[1258,32,11,12,0,-11,0]}}
  #|{"textrec":{"g":273,"r":[1270,32,10,10,-1,-9,0]}}
  #|{"textrec":{"g":274,"r":[1281,32,7,11,-1,-8,0]}}
  #|{"textrec":{"g":275,"r":[1289,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":276,"r":[1305,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":277,"r":[1321,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":278,"r":[1337,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":279,"r":[1353,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":280,"r":[1369,32,5,10,1,-10,0]}}
  #|{"textrec":{"g":281,"r":[1375,32,16,15,-1,-13,0]}}
  #|{"textrec":{"g":282,"r":[1392,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":283,"r":[1408,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":284,"r":[1425,32,9,11,-1,-9,0]}}
  #|{"textrec":{"g":285,"r":[1435,32,5,13,-1,-12,0]}}
  #|{"textrec":{"g":286,"r":[1441,32,4,13,0,-12,0]}}
  #|{"textrec":{"g":287,"r":[1446,32,4,5,0,-3,0]}}
  #|{"textrec":{"g":288,"r":[1451,32,7,13,-1,-12,0]}}
  #|{"textrec":{"g":289,"r":[1459,32,16,15,-1,-13,0]}}
  #|{"textrec":{"g":290,"r":[1476,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":291,"r":[1492,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":292,"r":[1508,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":293,"r":[1524,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":294,"r":[1540,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":295,"r":[1557,32,16,14,-1,-12,0]}}
  #|{"textrec":{"g":296,"r":[1574,32,14,16,0,-13,0]}}
  #|{"textrec":{"g":297,"r":[1589,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":298,"r":[1605,32,15,16,0,-13,0]}}
  #|{"textrec":{"g":299,"r":[1621,32,12,16,1,-13,0]}}
  #|{"textrec":{"g":300,"r":[1634,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":301,"r":[1650,32,6,6,0,-3,0]}}
  #|{"textrec":{"g":302,"r":[1657,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":303,"r":[1672,32,15,15,-1,-12,0]}}
  #|{"textrec":{"s":[15,400,0,"name@example.com，可粘贴多个"],"r":[0,1,8.51806640625,103,1,1,8.0419921875,93,2,1,12.8173828125,161,3,1,8.3349609375,95,4,1,13.53515625,363,5,1,8.1884765625,95,6,1,7.4853515625,364,7,1,8.0419921875,93,8,1,12.8173828125,161,9,1,8.9208984375,92,10,1,3.5595703125,108,11,1,8.3349609375,95,12,1,4.072265625,160,13,1,8.0126953125,94,14,1,8.6279296875,88,15,1,12.8173828125,161,16,1,15.08754863813229,365,17,1,14.88326848249028,366,18,1,14.88326848249028,367,19,1,14.88326848249028,368,20,1,14.88326848249028,369,21,1,14.88326848249028,370]}}
  #|{"textrec":{"g":363,"r":[1688,32,14,15,0,-12,0]}}
  #|{"textrec":{"g":364,"r":[1703,32,10,10,-1,-9,0]}}
  #|{"textrec":{"g":160,"r":[1714,32,5,5,0,-3,0]}}
  #|{"textrec":{"g":365,"r":[1720,32,5,7,0,-3,0]}}
  #|{"textrec":{"g":366,"r":[1726,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":367,"r":[1743,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":368,"r":[1760,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":369,"r":[1777,32,15,16,0,-13,0]}}
  #|{"textrec":{"g":370,"r":[1793,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":304,"r":[1811,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":305,"r":[1828,32,11,14,-1,-12,0]}}
  #|{"textrec":{"g":306,"r":[1840,32,4,13,0,-12,0]}}
  #|{"textrec":{"g":307,"r":[1845,32,10,11,-1,-9,0]}}
  #|{"textrec":{"g":308,"r":[1856,32,10,11,-1,-9,0]}}
  #|{"textrec":{"g":309,"r":[1867,32,9,13,0,-12,0]}}
  #|{"textrec":{"g":310,"r":[1877,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":311,"r":[1894,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":312,"r":[1911,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":313,"r":[1928,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":314,"r":[1944,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":315,"r":[1959,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":316,"r":[1975,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":317,"r":[1993,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":318,"r":[2010,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":319,"r":[2025,32,13,14,-1,-11,0]}}
  #|{"textrec":{"g":320,"r":[0,58,11,9,-1,-8,0]}}
  #|{"textrec":{"g":321,"r":[12,58,9,10,-1,-8,0]}}
  #|{"textrec":{"g":322,"r":[22,58,7,9,-1,-8,0]}}
  #|{"textrec":{"g":323,"r":[30,58,8,11,0,-10,0]}}
  #|{"textrec":{"g":324,"r":[39,58,8,10,-1,-8,0]}}
  #|{"textrec":{"g":325,"r":[48,58,9,12,-1,-8,0]}}
  #|{"textrec":{"g":326,"r":[58,58,8,10,-1,-8,0]}}
  #|{"textrec":{"g":327,"r":[67,58,9,10,-1,-8,0]}}
  #|{"textrec":{"g":328,"r":[77,58,9,10,-1,-8,0]}}
  #|{"textrec":{"g":329,"r":[87,58,13,13,-1,-11,0]}}
  #|{"textrec":{"g":330,"r":[101,58,13,14,-1,-11,0]}}
  #|{"textrec":{"g":331,"r":[115,58,6,11,-1,-9,0]}}
  #|{"textrec":{"g":332,"r":[122,58,5,11,-1,-10,0]}}
  #|{"textrec":{"g":333,"r":[128,58,9,9,-1,-8,0]}}
  #|{"textrec":{"g":334,"r":[138,58,16,17,-1,-14,0]}}
  #|{"textrec":{"g":335,"r":[155,58,17,16,-1,-13,0]}}
  #|{"textrec":{"g":336,"r":[173,58,14,14,-1,-11,0]}}
  #|{"textrec":{"g":337,"r":[188,58,14,14,-1,-11,0]}}
  #|{"textrec":{"g":338,"r":[203,58,14,14,-1,-11,0]}}
  #|{"textrec":{"g":339,"r":[218,58,13,14,-1,-11,0]}}
  #|{"textrec":{"g":340,"r":[232,58,6,6,0,-3,0]}}
  #|{"textrec":{"g":341,"r":[239,58,14,14,-1,-11,0]}}
  #|{"textrec":{"g":342,"r":[254,58,13,14,-1,-11,0]}}
  #|{"textrec":{"g":343,"r":[268,58,13,14,-1,-11,0]}}
  #|{"textrec":{"g":344,"r":[282,58,14,14,-1,-11,0]}}
  #|{"textrec":{"g":345,"r":[297,58,14,14,-1,-11,0]}}
  #|{"textrec":{"g":346,"r":[312,58,13,14,-1,-12,0]}}
  #|{"textrec":{"g":347,"r":[326,58,14,14,-1,-11,0]}}
  #|{"textrec":{"g":348,"r":[341,58,14,13,-1,-11,0]}}
  #|{"textrec":{"g":349,"r":[356,58,14,14,-1,-11,0]}}
  #|{"textrec":{"g":350,"r":[371,58,14,14,-1,-11,0]}}
  #|{"textrec":{"g":351,"r":[386,58,12,14,0,-11,0]}}
  #|{"textrec":{"g":352,"r":[399,58,14,14,-1,-11,0]}}
  #|{"textrec":{"g":353,"r":[414,58,5,6,0,-3,0]}}
  #|{"textrec":{"g":354,"r":[420,58,13,14,-1,-11,0]}}
  #|{"textrec":{"g":355,"r":[434,58,14,14,-1,-11,0]}}
  #|{"textrec":{"g":356,"r":[449,58,13,14,-1,-11,0]}}
  #|{"textrec":{"g":357,"r":[463,58,14,13,-1,-11,0]}}
  #|{"textrec":{"g":358,"r":[478,58,13,14,-1,-11,0]}}
  #|{"textrec":{"g":359,"r":[492,58,16,15,-1,-12,0]}}
  #|{"textrec":{"g":360,"r":[509,58,15,16,-1,-13,0]}}
  #|{"textrec":{"g":361,"r":[525,58,16,16,-1,-13,0]}}
  #|{"textrec":{"g":362,"r":[542,58,15,16,-1,-13,0]}}
  #|{"textrec":{"ib":["e13e77444a4987cd",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"s":[15,400,0,"e2e-080726@example.test"],"r":[0,1,8.3349609375,95,1,1,8.78173828125,371,2,1,8.29833984375,95,3,1,6.8408203125,372,4,1,9.2138671875,164,5,1,9.345703125,373,6,1,9.0673828125,164,7,1,8.1591796875,374,8,1,8.818359375,371,9,1,9.31640625,375,10,1,13.53515625,363,11,1,8.1884765625,95,12,1,7.4853515625,364,13,1,8.0419921875,93,14,1,12.8173828125,161,15,1,8.9208984375,92,16,1,3.5595703125,108,17,1,8.3349609375,95,18,1,4.072265625,160,19,1,5.013427734375,101,20,1,8.280029296875,95,21,1,7.58056640625,91,22,1,5.17822265625,101]}}
  #|{"textrec":{"g":371,"r":[558,58,10,13,0,-12,0]}}
  #|{"textrec":{"g":372,"r":[569,58,7,4,0,-6,0]}}
  #|{"textrec":{"g":164,"r":[577,58,11,14,-1,-12,0]}}
  #|{"textrec":{"g":373,"r":[589,58,11,14,-1,-12,0]}}
  #|{"textrec":{"g":374,"r":[601,58,10,13,-1,-12,0]}}
  #|{"textrec":{"g":375,"r":[612,58,11,14,-1,-12,0]}}
  #|{"textrec":{"s":[14,400,0,"1 人首次登录 still.fail 时自动加入。"],"r":[0,1,6.34375,182,1,1,3.787109375,-1,2,1,13.891050583657588,183,3,1,13.891050583657588,293,4,1,13.891050583657588,294,5,1,13.891050583657588,281,6,1,13.891050583657588,282,7,1,3.787109375,-1,8,1,7.1435546875,284,9,1,4.9013671875,61,10,1,3.30859375,285,11,1,3.390625,286,12,1,3.390625,286,13,1,3.80078125,287,14,1,4.607421875,288,15,1,7.4716796875,57,16,1,3.30859375,285,17,1,3.390625000000014,286,18,1,3.787109375,-1,19,1,13.891050583657602,298,20,1,13.891050583657602,299,21,1,13.891050583657602,300,22,1,13.891050583657602,269,23,1,13.891050583657602,270,24,1,7.081712062256798,301]}}
  #|{"textrec":{"s":[14,600,0,"完成"],"r":[0,1,13.891050583657588,376,1,1,13.891050583657588,312]}}
  #|{"textrec":{"g":376,"r":[624,58,16,16,-1,-13,0]}}
  #|{"textrec":{"s":[13,400,0,"1 人 · 1 人待加入"],"r":[0,1,5.9541015625,204,1,1,3.580078125,-1,2,1,12.898832684824903,205,3,1,3.580078125,-1,4,1,6.228545204222122,203,5,1,3.580078125,-1,6,1,5.9541015625,204,7,1,3.580078125,-1,8,1,12.898832684824903,205,9,1,12.898832684824903,377,10,1,12.898832684824896,378,11,1,12.898832684824896,379]}}
  #|{"textrec":{"s":[14,400,0,"移除"],"r":[0,1,13.891050583657588,380,1,1,13.891050583657588,381]}}
  #|{"textrec":{"s":[13,400,0,"成员 · 尚未登录，首次登录时自动加入"],"r":[0,1,12.898832684824903,140,1,1,12.898832684824903,236,2,1,3.580078125,-1,3,1,6.228545204222122,203,4,1,3.580078125,-1,5,1,12.898832684824903,382,6,1,12.898832684824896,383,7,1,12.898832684824896,384,8,1,12.898832684824896,385,9,1,13.075875486381321,234,10,1,12.89883268482491,386,11,1,12.898832684824896,387,12,1,12.898832684824896,384,13,1,12.898832684824896,385,14,1,12.898832684824896,153,15,1,12.898832684824896,247,16,1,12.898832684824896,248,17,1,12.898832684824896,378,18,1,12.898832684824896,379]}}
  #|{"textrec":{"s":[14,600,0,"E"],"r":[0,1,8.42106556892395,388]}}
  #|{"textrec":{"g":377,"r":[641,58,15,15,-1,-12,0]}}
  #|{"textrec":{"g":378,"r":[657,58,14,15,-1,-12,0]}}
  #|{"textrec":{"g":379,"r":[672,58,15,15,-1,-12,0]}}
  #|{"textrec":{"g":388,"r":[688,58,9,12,0,-11,0]}}
  #|{"textrec":{"g":382,"r":[698,58,13,15,0,-12,0]}}
  #|{"textrec":{"g":383,"r":[712,58,15,15,-1,-12,0]}}
  #|{"textrec":{"g":384,"r":[728,58,15,14,-1,-12,0]}}
  #|{"textrec":{"g":385,"r":[744,58,14,14,-1,-11,0]}}
  #|{"textrec":{"g":386,"r":[759,58,14,15,-1,-12,0]}}
  #|{"textrec":{"g":387,"r":[774,58,15,15,-1,-12,0]}}
  #|{"textrec":{"g":153,"r":[790,58,15,15,-1,-12,0]}}
  #|{"textrec":{"g":380,"r":[806,58,16,16,-1,-13,0]}}
  #|{"textrec":{"g":381,"r":[823,58,15,15,0,-12,0]}}
  #|{"textrec":{"s":[14,400,0,"已移除"],"r":[0,1,13.891050583657588,389,1,1,13.891050583657588,380,2,1,13.891050583657588,381]}}
  #|{"textrec":{"g":389,"r":[839,58,14,14,0,-12,0]}}
  #|{"textrec":{"s":[17,700,0,"为 Dev 选择图标"],"r":[0,1,16.851167315175097,390,1,1,3.951171875,-1,2,1,12.272705078125,391,3,1,9.657958984375,392,4,1,9.350830078125,393,5,1,3.951171875,-1,6,1,16.851167315175097,394,7,1,16.85116731517509,395,8,1,16.851167315175104,396,9,1,16.851167315175104,397]}}
  #|{"textrec":{"s":[14,400,0,"图标"],"r":[0,1,13.891050583657588,398,1,1,13.891050583657588,399]}}
  #|{"textrec":{"s":[14,400,0,"Emoji"],"r":[0,1,8.189453125,400,1,1,12.03125,401,2,1,8.12109375,402,3,1,3.3017578125,403,4,1,3.30859375,285]}}
  #|{"textrec":{"g":390,"r":[854,58,18,18,-1,-15,0]}}
  #|{"textrec":{"g":391,"r":[873,58,13,14,0,-13,0]}}
  #|{"textrec":{"g":392,"r":[887,58,12,13,-1,-11,0]}}
  #|{"textrec":{"g":393,"r":[900,58,12,12,-1,-11,0]}}
  #|{"textrec":{"g":394,"r":[913,58,18,18,-1,-15,0]}}
  #|{"textrec":{"g":395,"r":[932,58,19,18,-1,-15,0]}}
  #|{"textrec":{"g":396,"r":[952,58,17,18,0,-15,0]}}
  #|{"textrec":{"g":397,"r":[970,58,19,18,-1,-15,0]}}
  #|{"textrec":{"g":398,"r":[990,58,14,15,0,-12,0]}}
  #|{"textrec":{"g":399,"r":[1005,58,16,16,-1,-13,0]}}
  #|{"textrec":{"g":400,"r":[1022,58,9,12,0,-11,0]}}
  #|{"textrec":{"g":401,"r":[1032,58,13,10,0,-9,0]}}
  #|{"textrec":{"g":402,"r":[1046,58,10,11,-1,-9,0]}}
  #|{"textrec":{"g":403,"r":[1057,58,6,16,-2,-12,0]}}
  #|{"textrec":{"s":[15,400,0,"搜索图标"],"r":[0,1,14.883268482490273,18,1,1,14.883268482490273,19,2,1,14.883268482490273,216,3,1,14.883268482490273,217]}}
  #|{"textrec":{"ib":["f3a63645b2b177c6",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["852b4e6a49d3648f",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["c59432c5000c83af",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["fd874e05fb9b5192",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["fdbd52a7420b8407",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["b18c1cc3846c3baa",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["9872acd75025fa45",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["e3625ff7b887e5d5",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["0140c2fcc55fb7a3",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["52165091c406f76e",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["2e433cf14d12a470",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["f70d27221324e04d",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["81ebb6c22de7d807",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["831b4b6395caefb3",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["73276ca2e98dac36",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["9d47fa06c59e694f",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["92ba415d1cbe60c9",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["e18616ba8edb6199",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["6e6f9ccfe1de4d2a",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["e4b1db8f02b00443",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["cb260dab697695da",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["dd2cbe3041e90a66",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["d5496ec447f8d228",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["256bba7de97c7543",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["178cee66652be656",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["2af8b0987fc90f7e",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["0f44b5fd6962fc13",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["b8dab9fa3f1ff73f",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["da5e61986e576501",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["851f0a949e744371",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["54eff43d780f079e",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["7a06953d95c0f059",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["309f625f422dc1d7",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["69ecc233357449dc",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["e1b77d200c5c4c25",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["62958280f5f10d73",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["fd4ed8de2daaacd8",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["a80e1a07af2c98d8",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["f669c84831d9b180",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["39654e104d774096",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["263c1aa2c6e9443d",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["5f604515b302a091",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["c2d20a08c8bba55e",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["3f361b2a077f6740",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["4d704c8399a0d4a5",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["424d7ced268f76bc",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["52f8bea21fed46ff",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["bb082ad546583b2b",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"s":[26,400,0,"🖥️"],"r":[0,3,30,404]}}
  #|{"textrec":{"m":[26,400,0],"r":[25.13671875,5.484375,37,22.35882568359375,3.64117431640625,0]}}
  #|{"textrec":{"s":[26,400,0,"💻"],"r":[0,2,30,405]}}
  #|{"textrec":{"s":[26,400,0,"🍎"],"r":[0,2,30,406]}}
  #|{"textrec":{"s":[26,400,0,"🐧"],"r":[0,2,30,407]}}
  #|{"textrec":{"s":[26,400,0,"🪟"],"r":[0,2,30,408]}}
  #|{"textrec":{"s":[26,400,0,"☁️"],"r":[0,2,30,409]}}
  #|{"textrec":{"s":[26,400,0,"🏠"],"r":[0,2,30,410]}}
  #|{"textrec":{"s":[26,400,0,"🏢"],"r":[0,2,30,411]}}
  #|{"textrec":{"s":[26,400,0,"🚀"],"r":[0,2,30,412]}}
  #|{"textrec":{"s":[26,400,0,"⚡"],"r":[0,1,30,413]}}
  #|{"textrec":{"s":[26,400,0,"🔥"],"r":[0,2,30,414]}}
  #|{"textrec":{"s":[26,400,0,"🧪"],"r":[0,2,30,415]}}
  #|{"textrec":{"s":[26,400,0,"🛠️"],"r":[0,3,30,416]}}
  #|{"textrec":{"s":[26,400,0,"🐳"],"r":[0,2,30,417]}}
  #|{"textrec":{"s":[26,400,0,"🦀"],"r":[0,2,30,418]}}
  #|{"textrec":{"s":[26,400,0,"🐙"],"r":[0,2,30,419]}}
  #|{"textrec":{"s":[26,400,0,"🌲"],"r":[0,2,30,420]}}
  #|{"textrec":{"s":[26,400,0,"🌊"],"r":[0,2,30,421]}}
  #|{"textrec":{"s":[26,400,0,"🌙"],"r":[0,2,30,422]}}
  #|{"textrec":{"s":[26,400,0,"☀️"],"r":[0,2,30,423]}}
  #|{"textrec":{"s":[26,400,0,"🍊"],"r":[0,2,30,424]}}
  #|{"textrec":{"s":[26,400,0,"🍋"],"r":[0,2,30,425]}}
  #|{"textrec":{"s":[26,400,0,"🍇"],"r":[0,2,30,426]}}
  #|{"textrec":{"s":[26,400,0,"🐱"],"r":[0,2,30,427]}}
  #|{"textrec":{"s":[26,400,0,"🐶"],"r":[0,2,30,428]}}
  #|{"textrec":{"s":[26,400,0,"🦊"],"r":[0,2,30,429]}}
  #|{"textrec":{"s":[26,400,0,"🐼"],"r":[0,2,30,430]}}
  #|{"textrec":{"s":[26,400,0,"🐸"],"r":[0,2,30,431]}}
  #|{"textrec":{"s":[26,400,0,"🦉"],"r":[0,2,30,432]}}
  #|{"textrec":{"s":[26,400,0,"🐝"],"r":[0,2,30,433]}}
  #|{"textrec":{"s":[26,400,0,"🦄"],"r":[0,2,30,434]}}
  #|{"textrec":{"s":[26,400,0,"🐢"],"r":[0,2,30,435]}}
  #|{"textrec":{"s":[26,400,0,"🌵"],"r":[0,2,30,436]}}
  #|{"textrec":{"s":[26,400,0,"🌸"],"r":[0,2,30,437]}}
  #|{"textrec":{"s":[26,400,0,"🍄"],"r":[0,2,30,438]}}
  #|{"textrec":{"s":[26,400,0,"🌈"],"r":[0,2,30,439]}}
  #|{"textrec":{"s":[26,400,0,"❄️"],"r":[0,2,30,440]}}
  #|{"textrec":{"s":[26,400,0,"⭐"],"r":[0,1,30,441]}}
  #|{"textrec":{"s":[26,400,0,"🪐"],"r":[0,2,30,442]}}
  #|{"textrec":{"s":[26,400,0,"🌍"],"r":[0,2,30,443]}}
  #|{"textrec":{"s":[26,400,0,"🍉"],"r":[0,2,30,444]}}
  #|{"textrec":{"s":[26,400,0,"🍒"],"r":[0,2,30,445]}}
  #|{"textrec":{"s":[26,400,0,"🥑"],"r":[0,2,30,446]}}
  #|{"textrec":{"s":[26,400,0,"🍕"],"r":[0,2,30,447]}}
  #|{"textrec":{"s":[26,400,0,"☕"],"r":[0,1,30,448]}}
  #|{"textrec":{"s":[26,400,0,"🎧"],"r":[0,2,30,449]}}
  #|{"textrec":{"s":[26,400,0,"🎮"],"r":[0,2,30,450]}}
  #|{"textrec":{"s":[26,400,0,"🤖"],"r":[0,2,30,451]}}
  #|{"textrec":{"s":[15,400,0,"上传图片"],"r":[0,1,14.883268482490273,452,1,1,14.883268482490273,453,2,1,14.883268482490273,216,3,1,14.883268482490273,454]}}
  #|{"textrec":{"s":[15,400,0,"粘贴或输入任意 emoji"],"r":[0,1,14.883268482490273,367,1,1,14.883268482490273,368,2,1,14.883268482490273,455,3,1,14.883268482490273,456,4,1,14.88326848249028,457,5,1,14.88326848249028,458,6,1,14.88326848249028,459,7,1,3.984375,-1,8,1,8.3349609375,95,9,1,12.8173828125,161,10,1,8.6279296875,88,11,1,3.46435546875,460,12,1,3.4716796875,102]}}
  #|{"textrec":{"g":455,"r":[1064,58,16,16,-1,-13,0]}}
  #|{"textrec":{"g":456,"r":[1081,58,17,16,-1,-13,0]}}
  #|{"textrec":{"g":457,"r":[1099,58,16,16,-1,-13,0]}}
  #|{"textrec":{"g":458,"r":[1116,58,16,16,-1,-13,0]}}
  #|{"textrec":{"g":459,"r":[1133,58,16,17,-1,-14,0]}}
  #|{"textrec":{"g":460,"r":[1150,58,6,17,-2,-13,0]}}
  #|{"textrec":{"g":404,"r":[1157,58,32,34,-1,-27,1]}}
  #|{"textrec":{"g":405,"r":[1190,58,32,34,-1,-27,1]}}
  #|{"textrec":{"g":406,"r":[1223,58,32,34,-1,-27,1]}}
  #|{"textrec":{"g":407,"r":[1256,58,32,34,-1,-27,1]}}
  #|{"textrec":{"g":408,"r":[1289,58,32,34,-1,-27,1]}}
  #|{"textrec":{"g":409,"r":[1322,58,32,34,-1,-27,1]}}
  #|{"textrec":{"g":410,"r":[1355,58,32,34,-1,-27,1]}}
  #|{"textrec":{"g":411,"r":[1388,58,32,34,-1,-27,1]}}
  #|{"textrec":{"g":412,"r":[1421,58,32,34,-1,-27,1]}}
  #|{"textrec":{"g":413,"r":[1454,58,32,34,-1,-27,1]}}
  #|{"textrec":{"g":414,"r":[1487,58,32,34,-1,-27,1]}}
  #|{"textrec":{"g":415,"r":[1520,58,32,34,-1,-27,1]}}
  #|{"textrec":{"g":416,"r":[1553,58,32,34,-1,-27,1]}}
  #|{"textrec":{"g":417,"r":[1586,58,32,34,-1,-27,1]}}
  #|{"textrec":{"g":418,"r":[1619,58,32,34,-1,-27,1]}}
  #|{"textrec":{"g":419,"r":[1652,58,32,34,-1,-27,1]}}
  #|{"textrec":{"g":420,"r":[1685,58,32,34,-1,-27,1]}}
  #|{"textrec":{"g":421,"r":[1718,58,32,34,-1,-27,1]}}
  #|{"textrec":{"g":422,"r":[1751,58,32,34,-1,-27,1]}}
  #|{"textrec":{"g":423,"r":[1784,58,32,34,-1,-27,1]}}
  #|{"textrec":{"g":424,"r":[1817,58,32,34,-1,-27,1]}}
  #|{"textrec":{"g":425,"r":[1850,58,32,34,-1,-27,1]}}
  #|{"textrec":{"g":426,"r":[1883,58,32,34,-1,-27,1]}}
  #|{"textrec":{"g":427,"r":[1916,58,32,34,-1,-27,1]}}
  #|{"textrec":{"g":428,"r":[1949,58,32,34,-1,-27,1]}}
  #|{"textrec":{"g":429,"r":[1982,58,32,34,-1,-27,1]}}
  #|{"textrec":{"g":430,"r":[2015,58,32,34,-1,-27,1]}}
  #|{"textrec":{"g":431,"r":[0,93,32,34,-1,-27,1]}}
  #|{"textrec":{"g":432,"r":[33,93,32,34,-1,-27,1]}}
  #|{"textrec":{"g":433,"r":[66,93,32,34,-1,-27,1]}}
  #|{"textrec":{"g":434,"r":[99,93,32,34,-1,-27,1]}}
  #|{"textrec":{"g":435,"r":[132,93,32,34,-1,-27,1]}}
  #|{"textrec":{"g":436,"r":[165,93,32,34,-1,-27,1]}}
  #|{"textrec":{"g":437,"r":[198,93,32,34,-1,-27,1]}}
  #|{"textrec":{"g":438,"r":[231,93,32,34,-1,-27,1]}}
  #|{"textrec":{"g":439,"r":[264,93,32,34,-1,-27,1]}}
  #|{"textrec":{"g":440,"r":[297,93,32,34,-1,-27,1]}}
  #|{"textrec":{"g":441,"r":[330,93,32,34,-1,-27,1]}}
  #|{"textrec":{"g":442,"r":[363,93,32,34,-1,-27,1]}}
  #|{"textrec":{"g":443,"r":[396,93,32,34,-1,-27,1]}}
  #|{"textrec":{"g":444,"r":[429,93,32,34,-1,-27,1]}}
  #|{"textrec":{"g":445,"r":[462,93,32,34,-1,-27,1]}}
  #|{"textrec":{"g":446,"r":[495,93,32,34,-1,-27,1]}}
  #|{"textrec":{"g":447,"r":[528,93,32,34,-1,-27,1]}}
  #|{"textrec":{"g":448,"r":[561,93,32,34,-1,-27,1]}}
  #|{"textrec":{"g":449,"r":[594,93,32,34,-1,-27,1]}}
  #|{"textrec":{"g":450,"r":[627,93,32,34,-1,-27,1]}}
  #|{"textrec":{"g":451,"r":[660,93,32,34,-1,-27,1]}}
  #|{"textrec":{"g":452,"r":[693,93,16,15,-1,-13,0]}}
  #|{"textrec":{"g":453,"r":[710,93,17,16,-1,-13,0]}}
  #|{"textrec":{"g":454,"r":[728,93,15,16,0,-13,0]}}
  #|{"textrec":{"ib":["8c7eb8ec73207294",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"s":[14,400,0,"已设置图标"],"r":[0,1,13.891050583657588,389,1,1,13.891050583657588,214,2,1,13.891050583657588,215,3,1,13.891050583657588,398,4,1,13.891050583657588,399]}}
  #|{"textrec":{"s":[27,400,0,"🌲"],"r":[0,2,31,461]}}
  #|{"textrec":{"m":[27,400,0],"r":[26.103515625,5.6953125,38,23.218780517578125,3.781219482421875,0]}}
  #|{"textrec":{"s":[18,400,0,"🌲"],"r":[0,2,24,462]}}
  #|{"textrec":{"m":[18,400,0],"r":[17.40234375,3.796875,26,17.40234375,3.796875,0]}}
  #|{"textrec":{"g":461,"r":[744,93,33,35,-1,-28,1]}}
  #|{"textrec":{"g":462,"r":[778,93,26,24,-1,-19,1]}}
  #|{"textrec":{"s":[15,400,0,"不使用图标"],"r":[0,1,14.883268482490273,463,1,1,14.883268482490273,464,2,1,14.883268482490273,115,3,1,14.883268482490273,216,4,1,14.88326848249028,217]}}
  #|{"textrec":{"s":[15,400,0,"zzzz"],"r":[0,1,7.8515625,465,1,1,7.8515625,465,2,1,7.8515625,465,3,1,7.8515625,465]}}
  #|{"textrec":{"s":[15,400,0,"未找到图标"],"r":[0,1,14.883268482490273,466,1,1,14.883268482490273,467,2,1,14.883268482490273,468,3,1,14.883268482490273,216,4,1,14.88326848249028,217]}}
  #|{"textrec":{"g":465,"r":[805,93,9,10,0,-9,0]}}
  #|{"textrec":{"g":466,"r":[815,93,16,16,-1,-13,0]}}
  #|{"textrec":{"g":467,"r":[832,93,16,16,-1,-13,0]}}
  #|{"textrec":{"g":468,"r":[849,93,16,16,-1,-13,0]}}
  #|{"textrec":{"g":463,"r":[866,93,16,16,-1,-13,0]}}
  #|{"textrec":{"g":464,"r":[883,93,17,17,-1,-14,0]}}
  #|{"textrec":{"ib":["89c5d19878d01c5b",1688,64],"r":[20,20,20,20]}}
