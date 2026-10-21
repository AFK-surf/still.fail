// e2e/traces/settings-station-mark.trace, made by scripts/trace.py from 01-settings_station_mark.log: not edited by hand.

///|
/// What the app and its core said in the run, a line each.
pub let trace_settings_station_mark : String =
  #|{"env":{"MBUI_CLOUD":"http://127.0.0.1:18787","MBUI_CORE_ACCOUNT":"{\"sub\":\"alice\",\"email\":\"alice@example.test\",\"name\":\"Name of alice\",\"picture\":\"\",\"access\":\"-\",\"refresh\":\"-\",\"accessExpires\":1792625951}"}}
  #|{"out":{"id":1,"call":"client.device","params":{"client":"still.fail mbui","app":"desktop","userAgent":"Macintosh; Mac OS X"}},"w":1792625652845.91}
  #|{"in":{"id":1,"ok":null},"w":1792625652935.57}
  #|{"out":{"id":2,"subscribe":{"topic":"accounts"},"keyed":true},"w":1792625652935.595}
  #|{"out":{"id":3,"subscribe":{"topic":"prefs"},"keyed":true},"w":1792625652935.606}
  #|{"step":"# written by scripts/rerecord.sh from its test (src/sfreplay/emit.mbt): not edited by hand","w":1792625652937.552}
  #|{"step":"timeout 90000","w":1792625652937.562}
  #|{"step":"answered client.device","w":1792625652937.565}
  #|{"step":"answered client.focus","w":1792625652967.412}
  #|{"in":{"id":2,"value":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""}]},"w":1792625653082.296}
  #|{"in":{"id":3,"value":{"onlyMine":false,"onlyWatching":false,"onlyDecisions":false,"listFilter":{},"appearance":"system","rowPicture":"auto","absoluteTime":false,"lang":"zh","keys":{},"lastChat":{},"openChat":{},"chatTabs":{},"dropFiles":{},"driveViews":{},"filesTabs":{},"driveFavorites":{},"resume":{},"stationUpdatesDismissed":{},"device":{"app":"desktop","phone":false,"handoff":false},"reader":{"size":18,"line":1.7,"margin":22,"face":"sans","indent":true,"paper":"follow"},"rails":{},"bars":{"sets":[["chats","files","profiles","stations"],["decisions","usage","connects","archive"]],"current":0},"barsBy":{},"fonts":{},"faces":{"ui":{"id":"","name":"","mono":false,"family":"","files":[],"bytes":0},"text":{"id":"","name":"","mono":false,"family":"","files":[],"bytes":0},"code":{"id":"","name":"","mono":true,"family":"","files":[],"bytes":0},"list":[{"id":"inter","name":"Inter","mono":false,"family":"SF Inter","css":"http://127.0.0.1:18787/releases/fonts/inter/4.001/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/inter/4.001/var.ttf.gz","bytes":457818,"sha256":"29160a80ff49ddcab2c97711247e08b1fab27a484a329ce8b813d820dc559031"}],"preview":"http://127.0.0.1:18787/releases/fonts/inter/4.001/preview-194fa287.ttf","bytes":457818},{"id":"noto-sans-sc","name":"思源黑体","mono":false,"family":"SF Noto Sans SC","css":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/var.ttf.gz","bytes":11276563,"sha256":"a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da"}],"preview":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/preview-f0494178.ttf","bytes":11276563},{"id":"noto-serif-sc","name":"思源宋体","mono":false,"family":"SF Noto Serif SC","css":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/var.ttf.gz","bytes":15454579,"sha256":"050080d9255a86808f2945bffac582b31ef32bc36411ce29563b4961670c66f9"}],"preview":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/preview-001bbedf.ttf","bytes":15454579},{"id":"lxgw-wenkai","name":"霞鹜文楷","mono":false,"family":"SF LXGW WenKai","css":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/font.css","files":[{"weight":400,"url":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/400.ttf.gz","bytes":12904482,"sha256":"2d73eea94ad808999d90c0000c239a84a33b09d4bc6ab6c5b8bbf1eda8a7fc8b"},{"weight":500,"url":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/500.ttf.gz","bytes":13272430,"sha256":"f4b8a34d1f838fe411540cb7c97b1c384ac9738a876c4104500bc42508b2312a"}],"preview":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/preview-d3505af4.ttf","bytes":26176912},{"id":"jetbrains-mono","name":"JetBrains Mono","mono":true,"family":"SF JetBrains Mono","css":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/var.ttf.gz","bytes":90579,"sha256":"48715a42ec242c21e9f02692891e147d022299a52e48d5e413e1a942193ffeda"}],"preview":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/preview-ee73078f.ttf","bytes":90579},{"id":"fira-code","name":"Fira Code","mono":true,"family":"SF Fira Code","css":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/var.ttf.gz","bytes":137151,"sha256":"9335b082b3c7850d98a64b584f3417f65355f3471278bb5eeb8c6c0e8657aeeb"}],"preview":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/preview-555be27a.ttf","bytes":137151},{"id":"maple-mono","name":"Maple Mono","mono":true,"family":"SF Maple Mono CN","css":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/font.css","files":[{"weight":400,"url":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/400.ttf.gz","bytes":8352545,"sha256":"0fcc5139bfd5ab14ff989bb7dfd5236d0cafc10e60b9828569e6883613ab4085"},{"weight":600,"url":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/600.ttf.gz","bytes":8438132,"sha256":"96ed7ae26ee7c50b02b2d2b2bc0f1a0cbabe45ae5d6e6abf6678e2177c415677"}],"preview":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/preview-cffdf246.ttf","bytes":16790677}]}}},"w":1792625653082.346}
  #|{"out":{"id":4,"subscribe":{"topic":"workspaces"},"keyed":true},"w":1792625653082.416}
  #|{"out":{"id":5,"subscribe":{"topic":"status"},"keyed":true},"w":1792625653082.429}
  #|{"in":{"id":4,"value":[{"account":{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""},"workspaces":[{"id":"01M5GD17MEW7BP2FSGAM4QJ4MP","name":"Dev","role":"owner","created_at":1792625647,"stations":1,"members":1,"relays":[],"time":{"created_at":{"past":true,"at":1792625647000,"ago":"刚刚","full":"10/22 07:34:07","until":"1 分钟内"}}}],"invitations":[],"relay_url":"http://127.0.0.1:18740","loaded":true,"beta":true}]},"w":1792625653099.018}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792625653099.042}
  #|{"out":{"id":6,"subscribe":{"topic":"lock","workspace":"01M5GD17MEW7BP2FSGAM4QJ4MP"},"keyed":true},"w":1792625653099.1}
  #|{"out":{"id":7,"subscribe":{"topic":"chats","scope":"01M5GD17MEW7BP2FSGAM4QJ4MP","mine":false},"keyed":true},"w":1792625653099.12}
  #|{"out":{"id":8,"subscribe":{"topic":"changelog"},"keyed":true},"w":1792625653099.13}
  #|{"out":{"id":9,"subscribe":{"topic":"workspaceMarks","workspace":"01M5GD17MEW7BP2FSGAM4QJ4MP"},"keyed":true},"w":1792625653099.298}
  #|{"out":{"id":10,"subscribe":{"topic":"status","workspace":"01M5GD17MEW7BP2FSGAM4QJ4MP"},"keyed":true},"w":1792625653099.346}
  #|{"out":{"id":11,"subscribe":{"topic":"lockPrompts"},"keyed":true},"w":1792625653105.66}
  #|{"out":{"id":12,"call":"client.focus","params":{"visible":true,"focused":true,"workspace":"01M5GD17MEW7BP2FSGAM4QJ4MP"}},"w":1792625653109.47}
  #|{"out":{"id":13,"subscribe":{"topic":"notify"},"keyed":true},"w":1792625653109.485}
  #|{"out":{"id":14,"subscribe":{"topic":"notify","workspace":"01M5GD17MEW7BP2FSGAM4QJ4MP"},"keyed":true},"w":1792625653109.494}
  #|{"in":{"id":6,"value":{"available":true,"locked":false,"notice":true,"role":"owner","manages":true,"owner":true,"canSign":true,"signs":false,"me":{"device":"bc88612f935071d4b11dde1fc559166f67b9a7534d38601c4fdc28a1ad0e26da","code":"SL8-9JU","kind":"app","confirmed":false,"waiting":false,"asked":false},"signers":0,"members":[],"stations":[{"id":"3644c1f1299247f3d7915b26f55131b2f03a3ffd0ad985d7d4dd73113d915f33","name":"studio","version":"0.1.0","online":true,"protected":false}],"protected":0,"requests":[],"renew":[],"attention":0}},"w":1792625653115.622}
  #|{"in":{"id":7,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"stations":[{"station":"01M5GD17MEW7BP2FSGAM4QJ4MP/3644c1f1299247f3d7915b26f55131b2f03a3ffd0ad985d7d4dd73113d915f33","id":"3644c1f1299247f3d7915b26f55131b2f03a3ffd0ad985d7d4dd73113d915f33","name":"studio","state":"online"}],"loading":false,"days":[{"daysAgo":0,"at":1792625651230,"label":"今天","items":[{"id":"ember:c-3dc10bdd6c","session":"ember:c-3dc10bdd6c","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","agents":[{"key":"ember:c-3dc10bdd6c","runtime":"claude","process":"warm","pending":0,"lastTurn":{"id":"fec3a0f6-4f55-4377-94d2-d4ea7b171138","kind":"input","outcome":"completed","declared":"final","ending":"all_done","need":"answered the question that was asked","startedAt":1792625651149,"endedAt":1792625651233},"agentText":"默认模型","statusText":"已完成：answered the question that was asked"}],"last":{"seq":2,"authorKind":"agent","author":"ember:c-3dc10bdd6c","text":"你好，我是测试用的 agent","createdAt":1792625651230,"by":{"kind":"agent","name":"agent","mine":false,"runtime":"claude","label":"agent"},"preview":"你好，我是测试用的 agent","time":{"createdAt":{"at":1792625651230,"ago":"刚刚","full":"10/22 07:34:11","until":"1 分钟内","past":true}}},"unread":true,"mine":true,"lastActiveAt":1792625651230,"station":"01M5GD17MEW7BP2FSGAM4QJ4MP/3644c1f1299247f3d7915b26f55131b2f03a3ffd0ad985d7d4dd73113d915f33","stationName":"studio","time":{"lastActiveAt":{"at":1792625651230,"ago":"刚刚","full":"10/22 07:34:11","until":"1 分钟内","past":true}},"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"peopleText":"你 发起","clientKey":"new:chat-2426690af0adeb39c8","pinned":false,"tone":"done"}]}],"trouble":null,"members":1,"leading":"agents","glyph":{"online":1,"dim":0,"connecting":0,"failing":0,"working":0,"summary":"studio","label":"1 台 station，1 台在线"},"note":{"reading":false,"text":null,"failing":[],"empty":false}}},"w":1792625653115.662}
  #|{"in":{"id":8,"value":{"app":"desktop","tabs":[{"part":"desktop","label":"桌面","days":[]},{"part":"web","label":"网页","days":[]},{"part":"android","label":"安卓","days":[]},{"part":"station","label":"Station","days":[]},{"part":"cloud","label":"云端","days":[]}],"loading":false}},"w":1792625653115.692}
  #|{"in":{"id":9,"value":{"workspaces":{"01M5GD17MEW7BP2FSGAM4QJ4MP":{"alert":0,"unread":1,"tone":"done","label":"1 个有新消息","badge":0,"items":[],"mineTone":"done"}},"badge":0,"badgeCounts":"attention","badgeKinds":{"on":true,"wait":true,"failed":true,"done":false,"message":false}}},"w":1792625653115.702}
  #|{"in":{"id":10,"value":{"items":[]}},"w":1792625653115.709}
  #|{"in":{"id":11,"value":{"pairing":[]}},"w":1792625653115.713}
  #|{"in":{"id":12,"ok":null},"w":1792625653115.717}
  #|{"in":{"id":13,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792625653115.726}
  #|{"in":{"id":14,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792625653115.732}
  #|{"out":{"id":15,"subscribe":{"topic":"longJobs","scope":"01M5GD17MEW7BP2FSGAM4QJ4MP"},"keyed":true},"w":1792625653115.771}
  #|{"out":{"id":16,"call":"notify.permission","params":{"state":"unknown"}},"w":1792625653119.601}
  #|{"in":{"id":15,"value":{"groups":[]}},"w":1792625653132.294}
  #|{"in":{"id":16,"ok":null},"w":1792625653132.31}
  #|{"step":"answered notify.permission","w":1792625653132.804}
  #|{"step":"tap icon:settings","w":1792625653149.326}
  #|{"step":"tap icon:settings","acted":true,"w":1792625653149.357}
  #|{"out":{"id":17,"subscribe":{"topic":"workspace","workspace":"01M5GD17MEW7BP2FSGAM4QJ4MP"},"keyed":true},"w":1792625653165.827}
  #|{"out":{"id":18,"subscribe":{"topic":"stations","scope":"01M5GD17MEW7BP2FSGAM4QJ4MP"},"keyed":true},"w":1792625653165.845}
  #|{"out":{"id":19,"subscribe":{"topic":"connects","scope":"01M5GD17MEW7BP2FSGAM4QJ4MP","mine":false},"keyed":true},"w":1792625653165.852}
  #|{"out":{"id":20,"subscribe":{"topic":"vaults","workspace":"01M5GD17MEW7BP2FSGAM4QJ4MP"},"keyed":true},"w":1792625653165.86}
  #|{"out":{"id":21,"subscribe":{"topic":"doing"},"keyed":true},"w":1792625653169.815}
  #|{"out":{"id":22,"call":"cache.usage","params":{}},"w":1792625653171.366}
  #|{"step":"answered cache.usage","w":1792625653171.642}
  #|{"in":{"id":17,"value":{"id":"01M5GD17MEW7BP2FSGAM4QJ4MP","name":"Dev","role":"owner","created_at":1792625647,"members":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":"https://example.test/p.png","role":"owner","added_at":1792625647}],"stations":[{"id":"3644c1f1299247f3d7915b26f55131b2f03a3ffd0ad985d7d4dd73113d915f33","name":"studio","emoji":null,"icon":null,"enrolled_at":1792625647,"enrolled_by":"alice","last_seen":1792625651,"version":"0.1.0","time":{"last_seen":{"past":true,"at":1792625651000,"ago":"刚刚","full":"10/22 07:34:11","until":"1 分钟内"}}}],"invitations":[],"added":[],"relays":[],"lock":null,"lock_requests":0,"time":{"created_at":{"past":true,"at":1792625647000,"ago":"刚刚","full":"10/22 07:34:07","until":"1 分钟内"}}}},"w":1792625653182.308}
  #|{"in":{"id":18,"value":[{"station":"01M5GD17MEW7BP2FSGAM4QJ4MP/3644c1f1299247f3d7915b26f55131b2f03a3ffd0ad985d7d4dd73113d915f33","id":"3644c1f1299247f3d7915b26f55131b2f03a3ffd0ad985d7d4dd73113d915f33","name":"studio","summary":"正在连接","face":"idle","line":"在线","online":true,"reconnecting":false,"lastSeen":1792625651,"version":"0.1.0","link":{"state":"online"},"runtimes":[{"runtime":"claude","models":["claude-sonnet-5-5"]}],"models":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792625651120,"time":{"checkedAt":{"at":1792625651120,"ago":"刚刚","full":"10/22 07:34:11","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"overview":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null,"summaryText":"最近 7 天检查了 0 个 chat","changeText":null}},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","email":"alice@example.test","name":"Name of alice","sub":"alice","role":"owner","workspace":"01M5GD17MEW7BP2FSGAM4QJ4MP","device":"bc88612f935071d4b11dde1fc559166f67b9a7534d38601c4fdc28a1ad0e26da"},"connects":[],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792625651002,"time":{"checkedAt":{"at":1792625651002,"ago":"刚刚","full":"10/22 07:34:11","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792625651120,"time":{"checkedAt":{"at":1792625651120,"ago":"刚刚","full":"10/22 07:34:11","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"modelsReading":false,"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]}],"processes":[],"counts":{"sessions":1,"running":0,"warm":1},"mesh":{"state":"running","origin":"http://127.0.0.1:18787","station":"3644c1f1299247f3d7915b26f55131b2f03a3ffd0ad985d7d4dd73113d915f33","workspace":"Dev","workspaceId":"01M5GD17MEW7BP2FSGAM4QJ4MP","name":"studio"},"slackUsers":[],"slackTeams":[],"slackApps":[],"feishuRegistrations":[],"disk":{"freeBytes":80409616384,"totalBytes":994631127040},"logins":[],"machineLogins":[],"sharing":true,"consoleSignIn":true,"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"google","name":"Google Gemini","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xai","name":"xAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"mistral","name":"Mistral","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"deepseek","name":"DeepSeek","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen","name":"Qwen","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai","name":"Kimi","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"kimi-code","name":"Kimi Code","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai","name":"Z.ai","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax","name":"MiniMax","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ant-ling","name":"Ant Ling","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"jev","name":"Jev","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen-cn","name":"Qwen (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"openrouter","name":"OpenRouter","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"opencode","name":"OpenCode Zen","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"groq","name":"Groq","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"together","name":"Together AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"fireworks","name":"Fireworks","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cerebras","name":"Cerebras","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"huggingface","name":"Hugging Face","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"nvidia","name":"NVIDIA","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"baseten","name":"Baseten","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ollama","name":"Ollama","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"custom","name":"Custom","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""}],"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792625648602},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.307","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792625648602},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-ime/apps/e2e-local/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792625648602},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-ime/apps/e2e-local/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792625648602},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-ime/apps/e2e-local/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792625648602},{"id":"cursor","name":"Cursor","installed":false,"latest":"1.0.40","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792625648602},{"id":"devin","name":"Devin","installed":true,"version":"3000.11.92","latest":"3000.11.92","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-ime/apps/e2e-local/ember/station/test/fake/devin，不是用 Devin 的安装脚本装的，需在该机器上手动更新","state":"idle","checkedAt":1792625648602}],"processesText":"没有运行中的 agent 进程","agentEnv":[],"drive":{"roots":[],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false}},"betaOffered":false,"way":{"path":"直连","via":"direct"},"time":{"lastSeen":{"at":1792625651000,"ago":"刚刚","full":"10/22 07:34:11","until":"1 分钟内","past":true}},"joined":false}]},"w":1792625653182.461}
  #|{"in":{"id":19,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"items":[],"wait":{"reading":false,"text":null,"failing":[],"empty":true}}},"w":1792625653182.558}
  #|{"in":{"id":20,"value":{"available":true,"locked":false,"canSign":false,"setUp":false,"vaults":[{"id":"plain","name":"个人","owner":"alice","ownerName":"Name of alice","mine":true,"members":[{"sub":"alice","name":"Name of alice"}],"station":"3644c1f1299247f3d7915b26f55131b2f03a3ffd0ad985d7d4dd73113d915f33","stationName":"studio","items":0,"devices":0,"open":true,"keyed":true,"missing":0,"recoverable":false}],"requests":[],"refused":[{"station":"3644c1f1299247f3d7915b26f55131b2f03a3ffd0ad985d7d4dd73113d915f33","name":"studio","code":"vault_needs_lock"}],"plain":true}},"w":1792625653182.569}
  #|{"in":{"id":21,"value":{"doing":[]}},"w":1792625653182.578}
  #|{"in":{"id":22,"ok":{"chats":[{"station":"01M5GD17MEW7BP2FSGAM4QJ4MP/3644c1f1299247f3d7915b26f55131b2f03a3ffd0ad985d7d4dd73113d915f33","thread":1,"title":null,"sessions":["ember:c-3dc10bdd6c"],"bytes":558}]}},"w":1792625653182.583}
  #|{"step":"wait 299","w":1792625653199.536}
  #|{"step":"now tap =Station","w":1792625653499.18}
  #|{"step":"now tap =Station","acted":true,"w":1792625653499.202}
  #|{"out":{"id":23,"subscribe":{"topic":"stationNet","station":"01M5GD17MEW7BP2FSGAM4QJ4MP/3644c1f1299247f3d7915b26f55131b2f03a3ffd0ad985d7d4dd73113d915f33"},"keyed":true},"w":1792625653516.845}
  #|{"step":"wait 300","w":1792625653518.676}
  #|{"in":{"id":23,"value":{"path":"直连","via":"direct","rtt":{"text":"1 ms","level":"ok"},"rttHistory":[],"down":"—","up":"—","total":"今天共 ↓ 50 KB · ↑ 53 KB","downTotal":"50 KB","upTotal":"53 KB","lan":["192.168.0.126:64217","192.168.20.10:64217","192.168.20.107:64217"]}},"w":1792625653532.296}
  #|{"step":"now tap =studio","w":1792625653832.387}
  #|{"step":"now tap =studio","acted":true,"w":1792625653832.407}
  #|{"out":{"id":24,"subscribe":{"topic":"screens","station":"01M5GD17MEW7BP2FSGAM4QJ4MP/3644c1f1299247f3d7915b26f55131b2f03a3ffd0ad985d7d4dd73113d915f33"},"keyed":true},"w":1792625653849.344}
  #|{"out":{"id":25,"subscribe":{"topic":"machineLogins","station":"01M5GD17MEW7BP2FSGAM4QJ4MP/3644c1f1299247f3d7915b26f55131b2f03a3ffd0ad985d7d4dd73113d915f33"},"keyed":true},"w":1792625653849.366}
  #|{"out":{"id":26,"subscribe":{"topic":"memberships","station":"01M5GD17MEW7BP2FSGAM4QJ4MP/3644c1f1299247f3d7915b26f55131b2f03a3ffd0ad985d7d4dd73113d915f33"},"keyed":true},"w":1792625653849.377}
  #|{"out":{"id":27,"subscribe":{"topic":"adbShare"},"keyed":true},"w":1792625653850.257}
  #|{"step":"wait 300","w":1792625653851.176}
  #|{"in":{"id":24,"value":{"screens":[{"id":"desktop","kind":"desktop","title":"zuozijians-Mac-Studio","width":0,"height":0,"viewers":[],"controlledBy":[],"access":{"capture":false,"control":false,"message":"此 station 版本不含屏幕助手（stillfail-screen），请更新 station"},"clipboard":[],"drop":{"folder":"/tmp/mbe2e-C/home","reveal":true},"peek":false,"line":"此 station 版本不含屏幕助手（stillfail-screen），请更新 station","link":"/w/01M5GD17MEW7BP2FSGAM4QJ4MP/s/3644c1f1299247f3d7915b26f55131b2f03a3ffd0ad985d7d4dd73113d915f33/screen/desktop"}],"outdated":false,"control":true,"known":true}},"w":1792625653865.635}
  #|{"in":{"id":25,"value":{"supported":true,"loaded":true,"canLogin":true,"canRelay":true,"logins":[]}},"w":1792625653865.653}
  #|{"in":{"id":26,"value":{"manages":true,"loading":true,"canJoin":false,"workspaces":[]}},"w":1792625653865.658}
  #|{"in":{"id":27,"value":{"sharing":false,"phase":"off","tunnels":0}},"w":1792625653865.662}
  #|{"in":{"id":26,"value":{"manages":true,"loading":false,"canJoin":true,"workspaces":[{"workspace":"01M5GD17MEW7BP2FSGAM4QJ4MP","name":"Dev","stationName":"studio","home":true,"here":true,"line":"主 workspace"}]}},"w":1792625654065.623}
  #|{"step":"now until 在此 station 上","w":1792625654165.772}
  #|{"step":"tap icon:more","w":1792625654165.788}
  #|{"step":"tap icon:more","acted":true,"w":1792625654165.803}
  #|{"step":"wait 1403","w":1792625654183.924}
  #|{"in":{"id":23,"delta":[{"path":["down"],"set":"900 B/s"},{"path":["downTotal"],"set":"52 KB"},{"path":["rttHistory"],"append":[0.3]},{"path":["total"],"set":"今天共 ↓ 52 KB · ↑ 55 KB"},{"path":["up"],"set":"996 B/s"},{"path":["upTotal"],"set":"55 KB"}]},"w":1792625655532.291}
  #|{"step":"now tap =图标","w":1792625655599.114}
  #|{"step":"now tap =图标","acted":true,"w":1792625655599.134}
  #|{"step":"wait 1419","w":1792625655615.817}
  #|{"in":{"id":18,"delta":[{"path":[0,"host"],"set":{"hostname":"zuozijians-Mac-Studio","os":"macOS 27.0.1","arch":"arm64","cpus":12,"cpuModel":"Apple M2 Max","load":0.36,"cpuBusy":0.19,"uptimeSec":109399,"memory":{"totalBytes":68719476736,"usedBytes":35554246656,"swapUsedBytes":329515008},"disk":{"path":"/tmp/mbe2e-C/data","totalBytes":994631127040,"freeBytes":80409100288},"emberRssBytes":215089152,"checkedAt":1792625656202,"summary":"12 核 · 64 GB","line":"macOS 27.0.1 · 12 核 · 64 GB · 已运行 1 天","facts":["zuozijians-Mac-Studio","macOS 27.0.1","arm64 · 12 核","已运行 1 天 6 小时"],"meters":[{"label":"CPU","short":"CPU","percent":19,"left":81,"level":"ok","value":"19%","remaining":"空闲 81%","big":"81","unit":"%","title":"CPU 空闲","total":"负载 4.3","note":"负载 4.3 · Apple M2 Max"},{"label":"内存","short":"内存","percent":52,"left":48,"level":"ok","value":"33.1 GB / 64.0 GB","remaining":"剩 30.9 G","big":"30.9","unit":"GB","title":"内存剩","total":"共 64 GB","note":"swap 0.3 GB"},{"label":"磁盘","short":"磁盘","percent":92,"left":8,"level":"red","value":"剩余 74.9 GB / 926 GB","remaining":"剩 74.9 G","big":"74.9","unit":"GB","title":"磁盘剩","total":"共 926 GB"}],"identity":"Apple M2 Max · 64 GB · macOS 27.0.1","details":[{"label":"主机名","value":"zuozijians-Mac-Studio"},{"label":"芯片","value":"Apple M2 Max · 12 核 · arm64"},{"label":"已运行","value":"1 天 6 小时"},{"label":"still.fail","value":"进程占用 205 MB"}],"usage":"内存 33.1 GB / 64.0 GB · 磁盘 剩余 74.9 GB / 926 GB","emberText":"still.fail 205 MB"}},{"path":[0,"line"],"set":"Apple M2 Max"},{"path":[0,"summary"],"set":"空闲 · Apple M2 Max · 64 GB · macOS 27.0.1"}]},"w":1792625656465.635}
  #|{"step":"now until 为 studio 选择图标","w":1792625657049.33}
  #|{"step":"tap 搜索图标","w":1792625657049.357}
  #|{"step":"tap 搜索图标","acted":true,"w":1792625657049.37}
  #|{"step":"type robot","w":1792625657068.644}
  #|{"step":"type robot","acted":true,"w":1792625657068.657}
  #|{"step":"tap img:glyph/robot","w":1792625657083.318}
  #|{"step":"tap img:glyph/robot","acted":true,"w":1792625657083.332}
  #|{"out":{"id":28,"call":"workspace.renameStation","params":{"workspace":"01M5GD17MEW7BP2FSGAM4QJ4MP","station":"3644c1f1299247f3d7915b26f55131b2f03a3ffd0ad985d7d4dd73113d915f33","emoji":"🤖","icon":"glyph:robot","account":"alice"}},"w":1792625657099.072}
  #|{"step":"answered workspace.renameStation","w":1792625657099.231}
  #|{"in":{"id":28,"ok":{"id":"01M5GD17MEW7BP2FSGAM4QJ4MP","name":"Dev","role":"owner","created_at":1792625647,"members":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":"https://example.test/p.png","role":"owner","added_at":1792625647}],"stations":[{"id":"3644c1f1299247f3d7915b26f55131b2f03a3ffd0ad985d7d4dd73113d915f33","name":"studio","emoji":"🤖","icon":"glyph:robot","enrolled_at":1792625647,"enrolled_by":"alice","last_seen":1792625651,"version":"0.1.0"}],"invitations":[],"added":[],"relays":[],"lock":null,"lock_requests":0}},"w":1792625657132.287}
  #|{"step":"until 已设置图标","w":1792625657149.569}
  #|{"step":"wait 1454","w":1792625657149.581}
  #|{"in":{"id":17,"delta":[{"path":["stations",0,"emoji"],"set":"🤖"},{"path":["stations",0,"icon"],"set":"glyph:robot"}]},"w":1792625657165.624}
  #|{"in":{"id":18,"delta":[{"path":[0,"emoji"],"set":"🤖"},{"path":[0,"icon"],"set":"glyph:robot"},{"path":[0,"overview","disk","freeBytes"],"set":80409300992}]},"w":1792625657165.644}
  #|{"in":{"id":23,"delta":[{"path":["down"],"set":"1.6 KB/s"},{"path":["downTotal"],"set":"55 KB"},{"path":["rttHistory"],"append":[0.3]},{"path":["total"],"set":"今天共 ↓ 55 KB · ↑ 55 KB"},{"path":["up"],"set":"69 B/s"}]},"w":1792625657615.605}
  #|{"step":"now tap icon:more","w":1792625658615.745}
  #|{"step":"now tap icon:more","acted":true,"w":1792625658615.769}
  #|{"step":"wait 1403","w":1792625658632.714}
  #|{"in":{"id":23,"delta":[{"path":["down"],"set":"9.0 KB/s"},{"path":["downTotal"],"set":"74 KB"},{"path":["rttHistory"],"append":[0.4]},{"path":["total"],"set":"今天共 ↓ 74 KB · ↑ 77 KB"},{"path":["up"],"set":"10 KB/s"},{"path":["upTotal"],"set":"77 KB"}]},"w":1792625659615.61}
  #|{"step":"now tap =图标","w":1792625660049.178}
  #|{"step":"now tap =图标","acted":true,"w":1792625660049.202}
  #|{"step":"wait 1419","w":1792625660065.84}
  #|{"step":"now tap =Emoji","w":1792625661499.191}
  #|{"step":"now tap =Emoji","acted":true,"w":1792625661499.215}
  #|{"step":"tap 粘贴或输入任意 emoji","w":1792625661515.874}
  #|{"step":"tap 粘贴或输入任意 emoji","acted":true,"w":1792625661548.657}
  #|{"step":"paste 🚀","w":1792625661557.815}
  #|{"step":"paste 🚀","acted":true,"w":1792625661558.342}
  #|{"out":{"id":29,"call":"workspace.renameStation","params":{"workspace":"01M5GD17MEW7BP2FSGAM4QJ4MP","station":"3644c1f1299247f3d7915b26f55131b2f03a3ffd0ad985d7d4dd73113d915f33","emoji":"🚀","icon":"","account":"alice"}},"w":1792625661565.693}
  #|{"step":"answered workspace.renameStation","w":1792625661565.976}
  #|{"in":{"id":29,"ok":{"id":"01M5GD17MEW7BP2FSGAM4QJ4MP","name":"Dev","role":"owner","created_at":1792625647,"members":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":"https://example.test/p.png","role":"owner","added_at":1792625647}],"stations":[{"id":"3644c1f1299247f3d7915b26f55131b2f03a3ffd0ad985d7d4dd73113d915f33","name":"studio","emoji":"🚀","icon":null,"enrolled_at":1792625647,"enrolled_by":"alice","last_seen":1792625651,"version":"0.1.0"}],"invitations":[],"added":[],"relays":[],"lock":null,"lock_requests":0}},"w":1792625661582.273}
  #|{"step":"until 已设置图标","w":1792625661599.348}
  #|{"step":"wait 1454","w":1792625661599.361}
  #|{"in":{"id":17,"delta":[{"path":["stations",0,"emoji"],"set":"🚀"},{"path":["stations",0,"icon"],"set":null}]},"w":1792625661632.269}
  #|{"in":{"id":18,"delta":[{"path":[0,"emoji"],"set":"🚀"},{"path":[0,"overview","disk","freeBytes"],"set":80409145344},{"path":[0,"icon"],"remove":true}]},"w":1792625661632.293}
  #|{"in":{"id":23,"delta":[{"path":["down"],"set":"0 B/s"},{"path":["rttHistory"],"append":[0.4]},{"path":["up"],"set":"33 B/s"}]},"w":1792625661682.27}
  #|{"step":"now tap icon:more","w":1792625663082.544}
  #|{"step":"now tap icon:more","acted":true,"w":1792625663082.578}
  #|{"step":"wait 1403","w":1792625663100.148}
  #|{"in":{"id":23,"delta":[{"path":["down"],"set":"80 B/s"},{"path":["rttHistory"],"append":[0.4]},{"path":["up"],"set":"101 B/s"}]},"w":1792625663882.258}
  #|{"step":"now tap =图标","w":1792625664516.669}
  #|{"step":"now tap =图标","acted":true,"w":1792625664516.765}
  #|{"step":"wait 1419","w":1792625664534.106}
  #|{"step":"now tap =图标","w":1792625665967.228}
  #|{"step":"now tap =图标","acted":true,"w":1792625665967.326}
  #|{"step":"tap 搜索图标","w":1792625665990.316}
  #|{"step":"tap 搜索图标","acted":true,"w":1792625665990.381}
  #|{"step":"type zzzz","w":1792625666004.01}
  #|{"step":"type zzzz","acted":true,"w":1792625666004.06}
  #|{"step":"tap 不使用图标","w":1792625666020.005}
  #|{"step":"tap 不使用图标","acted":true,"w":1792625666020.088}
  #|{"out":{"id":30,"call":"workspace.renameStation","params":{"workspace":"01M5GD17MEW7BP2FSGAM4QJ4MP","station":"3644c1f1299247f3d7915b26f55131b2f03a3ffd0ad985d7d4dd73113d915f33","emoji":"","icon":"","account":"alice"}},"w":1792625666033.035}
  #|{"step":"answered workspace.renameStation","w":1792625666033.977}
  #|{"in":{"id":23,"delta":[{"path":["down"],"set":"0 B/s"},{"path":["rttHistory"],"append":[0.4]},{"path":["up"],"set":"0 B/s"}]},"w":1792625666048.974}
  #|{"in":{"id":21,"value":{"doing":[{"call":"workspace.renameStation","params":{"workspace":"01M5GD17MEW7BP2FSGAM4QJ4MP","station":"3644c1f1299247f3d7915b26f55131b2f03a3ffd0ad985d7d4dd73113d915f33","emoji":"","icon":"","account":"alice"},"since":1792625666034,"stage":"running"}]}},"w":1792625666049.053}
  #|{"in":{"id":30,"ok":{"id":"01M5GD17MEW7BP2FSGAM4QJ4MP","name":"Dev","role":"owner","created_at":1792625647,"members":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":"https://example.test/p.png","role":"owner","added_at":1792625647}],"stations":[{"id":"3644c1f1299247f3d7915b26f55131b2f03a3ffd0ad985d7d4dd73113d915f33","name":"studio","emoji":null,"icon":null,"enrolled_at":1792625647,"enrolled_by":"alice","last_seen":1792625651,"version":"0.1.0"}],"invitations":[],"added":[],"relays":[],"lock":null,"lock_requests":0}},"w":1792625666082.3}
  #|{"step":"wait 1454","w":1792625666099.467}
  #|{"in":{"id":17,"delta":[{"path":["stations",0,"emoji"],"set":null}]},"w":1792625666215.654}
  #|{"in":{"id":18,"delta":[{"path":[0,"overview","disk","freeBytes"],"set":80417071104},{"path":[0,"emoji"],"remove":true}]},"w":1792625666215.705}
  #|{"in":{"id":21,"value":{"doing":[]}},"w":1792625666232.282}
  #|{"step":"","w":1792625667717.222}
  #|{"textrec":{"m":[15,400,0],"r":[14.501953125,3.1640625,21,14.501953125,3.1640625,0]}}
  #|{"textrec":{"ib":["777730150a25a9d5",12668,64],"r":[56,56,56,56]}}
  #|{"textrec":{"s":[13,400,0,"正在读取你的 workspace"],"r":[0,1,12.898832684824903,0,1,1,12.898832684824903,1,2,1,12.898832684824903,2,3,1,12.898832684824903,3,4,1,12.898832684824896,4,5,1,12.898832684824896,5,6,1,3.580078125,-1,7,1,9.8642578125,6,8,1,7.4775390625,7,9,1,4.875,8,10,1,6.85546875,9,11,1,6.6015625,10,12,1,7.8583984375,11,13,1,7.0966796875,12,14,1,7.1982421875,13,15,1,7.3505859375,14]}}
  #|{"textrec":{"m":[13,400,0],"r":[12.568359375,2.7421875,18,12.568359375,2.7421875,0]}}
  #|{"textrec":{"s":[24,700,0,"Dev"],"r":[0,1,17.075823068618774,15,1,1,13.365240812301636,16,2,1,12.759063005447388,17]}}
  #|{"textrec":{"m":[24,700,0],"r":[23.203125,5.0625,34,20.638916015625,3.361083984375,0]}}
  #|{"textrec":{"g":15,"r":[0,0,18,19,0,-18,0]}}
  #|{"textrec":{"g":16,"r":[19,0,15,16,-1,-14,0]}}
  #|{"textrec":{"g":17,"r":[35,0,15,15,-1,-14,0]}}
  #|{"textrec":{"ib":["ae43d83affe59cac",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"ib":["fc7740984bab85e7",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"ib":["bef2954d97ce1d9f",6508,64],"r":[40,40,40,40]}}
  #|{"textrec":{"ib":["09d4470aafd7f0ac",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["107866ff96758644",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["bc50a50f7296bc53",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["b974a367bb8f9fe8",3232,64],"r":[28,28,28,28]}}
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
  #|{"textrec":{"ib":["c7923253081c8f8d",1241,64],"r":[17,17,17,17]}}
  #|{"textrec":{"ib":["6184392a954200b2",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["c5eddd6892582c35",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["dba2e3be139a9be6",1688,64],"r":[20,20,20,20]}}
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
  #|{"textrec":{"ib":["36defacdc9a07f7e",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["bb3a6b4f2738b76c",2026,64],"r":[22,22,22,22]}}
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
  #|{"textrec":{"ib":["2fd6ddea2f20a6ea",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"s":[16,600,0,"Station"],"r":[0,1,10.266256332397461,195,1,1,5.999713897705078,36,2,1,8.899068832397461,44,3,1,5.999713897705078,36,4,1,4.046333312988281,196,5,1,9.432537078857422,34,6,1,9.466253280639648,47]}}
  #|{"textrec":{"s":[17,400,0,"设置"],"r":[0,1,16.851167315175097,197,1,1,16.851167315175097,198]}}
  #|{"textrec":{"s":[16,700,0,"studio"],"r":[0,1,8.73046875,199,1,1,6.26953125,200,2,1,9.72265625,201,3,1,10.109375,202,4,1,4.28125,74,5,1,9.6015625,71]}}
  #|{"textrec":{"s":[13,400,0,"正在连接"],"r":[0,1,12.898832684824903,0,1,1,12.898832684824903,1,2,1,12.898832684824903,203,3,1,12.898832684824903,204]}}
  #|{"textrec":{"s":[13,400,0,"↑"],"r":[0,1,10.080078125,205]}}
  #|{"textrec":{"s":[13,500,0," "],"r":[0,1,3.4683494567871094,-1]}}
  #|{"textrec":{"m":[13,500,0],"r":[12.568359375,2.7421875,18,12.568359375,2.7421875,0]}}
  #|{"textrec":{"s":[13,400,0,"↓"],"r":[0,1,10.080078125,206]}}
  #|{"textrec":{"s":[13,400,0,"直连"],"r":[0,1,12.898832684824903,207,1,1,12.898832684824903,203]}}
  #|{"textrec":{"s":[13,400,0,"当前延迟 "],"r":[0,1,12.898832684824903,208,1,1,12.898832684824903,209,2,1,12.898832684824903,210,3,1,12.898832684824903,211,4,1,3.580078125,-1]}}
  #|{"textrec":{"s":[13,500,0,"0 ms"],"r":[0,1,8.373004913330078,212,1,1,3.4683494567871094,-1,2,1,11.530966997146606,213,3,1,6.933351516723633,214]}}
  #|{"textrec":{"s":[13,400,0,"共 53 KB"],"r":[0,1,12.898832684824903,215,1,1,3.580078125,-1,2,1,7.9599609375,216,3,1,8.07421875,217,4,1,3.580078125,-1,5,1,8.48681640625,218,6,1,8.4677734375,219]}}
  #|{"textrec":{"s":[13,500,0,"—"],"r":[0,1,11.440923571586609,220]}}
  #|{"textrec":{"s":[13,400,0,"共 50 KB"],"r":[0,1,12.898832684824903,215,1,1,3.580078125,-1,2,1,7.9599609375,216,3,1,8.1123046875,221,4,1,3.580078125,-1,5,1,8.48681640625,218,6,1,8.4677734375,219]}}
  #|{"textrec":{"s":[13,500,0,"1 ms"],"r":[0,1,6.182214260101318,222,1,1,3.4683494567871094,-1,2,1,11.530966997146606,213,3,1,6.933351516723633,214]}}
  #|{"textrec":{"g":197,"r":[2000,0,19,18,-1,-15,0]}}
  #|{"textrec":{"g":198,"r":[2020,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":207,"r":[0,32,14,14,-1,-12,0]}}
  #|{"textrec":{"g":203,"r":[15,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":208,"r":[31,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":209,"r":[45,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":210,"r":[61,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":211,"r":[77,32,15,15,-1,-12,0]}}
  #|{"textrec":{"ib":["e766de4433f00faa",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"g":199,"r":[93,32,11,12,-1,-10,0]}}
  #|{"textrec":{"g":200,"r":[105,32,8,14,-1,-12,0]}}
  #|{"textrec":{"g":201,"r":[114,32,10,12,0,-10,0]}}
  #|{"textrec":{"g":202,"r":[125,32,12,15,-1,-13,0]}}
  #|{"textrec":{"g":0,"r":[138,32,14,13,-1,-11,0]}}
  #|{"textrec":{"g":1,"r":[153,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":204,"r":[168,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":222,"r":[184,32,7,12,-1,-11,0]}}
  #|{"textrec":{"g":213,"r":[192,32,13,10,-1,-9,0]}}
  #|{"textrec":{"g":214,"r":[206,32,9,11,-1,-9,0]}}
  #|{"textrec":{"g":195,"r":[216,32,12,15,-1,-13,0]}}
  #|{"textrec":{"g":44,"r":[229,32,11,12,-1,-10,0]}}
  #|{"textrec":{"g":196,"r":[241,32,5,15,0,-14,0]}}
  #|{"textrec":{"g":47,"r":[247,32,10,11,0,-10,0]}}
  #|{"textrec":{"g":205,"r":[258,32,10,13,0,-11,0]}}
  #|{"textrec":{"g":206,"r":[269,32,10,13,0,-11,0]}}
  #|{"textrec":{"g":220,"r":[280,32,14,4,-1,-6,0]}}
  #|{"textrec":{"g":215,"r":[295,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":216,"r":[310,32,10,13,-1,-11,0]}}
  #|{"textrec":{"g":217,"r":[321,32,10,13,-1,-11,0]}}
  #|{"textrec":{"g":218,"r":[332,32,10,12,0,-11,0]}}
  #|{"textrec":{"g":219,"r":[343,32,9,12,0,-11,0]}}
  #|{"textrec":{"g":221,"r":[353,32,10,13,-1,-11,0]}}
  #|{"textrec":{"ib":["c47756bd948dc828",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"s":[11,400,0,"在线"],"r":[0,1,10.93579766536965,223,1,1,10.93579766536965,224]}}
  #|{"textrec":{"m":[11,400,0],"r":[10.634765625,2.3203125,16,10.634765625,2.3203125,0]}}
  #|{"textrec":{"s":[16,600,0,"studio"],"r":[0,1,8.471200942993164,35,1,1,5.973020553588867,36,2,1,9.466253280639648,225,3,1,9.891647338867188,226,4,1,4.046333312988281,196,5,1,9.432537078857422,34]}}
  #|{"textrec":{"s":[17,400,0,"Station"],"r":[0,1,10.40087890625,227,1,1,5.744140625,228,2,1,8.9482421875,229,3,1,5.744140625,228,4,1,3.7685546875,230,5,1,9.6123046875,231,6,1,9.48779296875,232]}}
  #|{"textrec":{"s":[13,400,0,"没有运行中的 agent 进程"],"r":[0,1,12.898832684824903,233,1,1,12.898832684824903,149,2,1,12.898832684824903,234,3,1,12.898832684824903,235,4,1,12.898832684824896,236,5,1,12.898832684824896,5,6,1,3.580078125,-1,7,1,7.0966796875,12,8,1,7.845703125,237,9,1,7.3505859375,14,10,1,7.50927734375,238,11,1,4.646484375,82,12,1,3.580078125,-1,13,1,12.898832684824896,239,14,1,12.898832684824896,240]}}
  #|{"textrec":{"s":[15,600,0,"在此 station 上"],"r":[0,1,14.883268482490273,241,1,1,14.883268482490273,117,2,1,3.761730194091797,-1,3,1,8.000344634056091,242,4,1,5.658300518989563,243,5,1,8.40147078037262,244,6,1,5.683325529098511,243,7,1,3.8520312309265137,245,8,1,8.901597261428833,246,9,1,8.93320620059967,180,10,1,3.761730194091797,-1,11,1,14.883268482490266,247]}}
  #|{"textrec":{"s":[15,400,0,"共享调试"],"r":[0,1,14.883268482490273,248,1,1,14.883268482490273,249,2,1,14.883268482490273,250,3,1,14.883268482490273,251]}}
  #|{"textrec":{"s":[14,400,0,"未开放"],"r":[0,1,13.891050583657588,96,1,1,13.891050583657588,97,2,1,13.891050583657588,252]}}
  #|{"textrec":{"s":[15,400,0,"文件"],"r":[0,1,14.883268482490273,253,1,1,14.883268482490273,254]}}
  #|{"textrec":{"s":[15,600,0,"Agent 环境变量"],"r":[0,1,10.209932327270508,255,1,1,9.027448296546936,256,2,1,8.615586161613464,85,3,1,8.93320620059967,180,4,1,5.683325529098511,243,5,1,3.761730194091797,-1,6,1,14.883268482490273,257,7,1,14.883268482490273,258,8,1,14.883268482490266,259,9,1,14.88326848249028,260]}}
  #|{"textrec":{"s":[15,400,0,"暂无变量"],"r":[0,1,14.883268482490273,261,1,1,14.883268482490273,262,2,1,14.883268482490273,263,3,1,14.883268482490273,116]}}
  #|{"textrec":{"s":[15,400,0,"编辑变量"],"r":[0,1,14.883268482490273,264,1,1,14.883268482490273,265,2,1,14.883268482490273,263,3,1,14.883268482490273,116]}}
  #|{"textrec":{"s":[15,600,0,"搜索"],"r":[0,1,14.883268482490273,266,1,1,14.883268482490273,267]}}
  #|{"textrec":{"s":[15,400,0,"搜索个人数据"],"r":[0,1,14.883268482490273,18,1,1,14.883268482490273,19,2,1,14.883268482490273,268,3,1,14.883268482490273,269,4,1,14.88326848249028,270,5,1,14.88326848249028,271]}}
  #|{"textrec":{"s":[13,400,0,"workspace 成员也可搜索邮件、信息、日历、通讯录、备忘录和照片"],"r":[0,1,9.8642578125,6,1,1,7.4775390625,7,2,1,4.875,8,3,1,6.85546875,9,4,1,6.6015625,10,5,1,7.8583984375,11,6,1,7.0966796875,12,7,1,7.1982421875,13,8,1,7.3505859375,14,9,1,3.580078125,-1,10,1,12.898832684824896,140,11,1,12.898832684824896,272,12,1,12.898832684824896,273,13,1,12.898832684824896,274,14,1,12.898832684824896,275,15,1,12.898832684824896,276,16,1,12.898832684824896,277,17,1,12.898832684824896,278,18,1,13.075875486381335,141,19,1,12.898832684824896,279,20,1,12.898832684824896,152,21,1,13.075875486381335,141,22,1,12.898832684824896,280,23,1,12.898832684824896,281,24,1,13.075875486381335,141,25,1,12.898832684824924,154,26,1,12.898832684824924,282,27,1,12.898832684824924,283,28,1,13.075875486381335,141,29,1,12.898832684824924,284,30,1,12.898832684824924,285,31,1,12.898832684824924,283,32,1,12.898832684824924,286,33,1,12.898832684824924,287,34,1,12.898832684824924,288]}}
  #|{"textrec":{"s":[15,600,0,"屏幕"],"r":[0,1,14.883268482490273,289,1,1,14.883268482490273,290]}}
  #|{"textrec":{"s":[15,400,0,"zuozijians-Mac-Studio"],"r":[0,1,7.8515625,291,1,1,8.51806640625,163,2,1,8.51806640625,88,3,1,7.74169921875,291,4,1,3.4716796875,102,5,1,3.46435546875,292,6,1,3.4716796875,102,7,1,8.0419921875,93,8,1,8.51806640625,103,9,1,7.6171875,91,10,1,6.8408203125,293,11,1,12.8759765625,294,12,1,8.0419921875,93,13,1,8.1591796875,94,14,1,6.8408203125,293,15,1,9.32373046875,100,16,1,5.21484375,101,17,1,8.51806640625,163,18,1,8.9794921875,295,19,1,3.4716796875,102,20,1,8.6279296875,88]}}
  #|{"textrec":{"s":[13,400,0,"此 station 版本不含屏幕助手（stillfail-screen），请更新 station"],"r":[0,1,12.898832684824903,296,1,1,3.580078125,-1,2,1,6.69677734375,10,3,1,4.61474609375,82,4,1,7.0966796875,12,5,1,4.646484375,82,6,1,3.1357421875,77,7,1,7.6044921875,7,8,1,7.50927734375,238,9,1,3.580078125,-1,10,1,12.898832684824903,297,11,1,12.89883268482491,298,12,1,12.898832684824896,299,13,1,12.898832684824896,300,14,1,12.898832684824896,301,15,1,12.898832684824896,302,16,1,12.898832684824896,303,17,1,19.398832684824896,304,18,1,4.071984435797674,305,19,1,6.69677734375,10,20,1,4.61474609375,82,21,1,3.1357421875,77,22,1,3.2119140625,76,23,1,3.2119140625,76,24,1,4.5322265625,306,25,1,7.00146484375,12,26,1,3.1357421875,77,27,1,3.2119140625,76,28,1,6.0556640625,307,29,1,6.728515625,10,30,1,7.1982421875,13,31,1,4.77978515625,8,32,1,7.25537109375,14,33,1,7.3505859375,14,34,1,7.50927734375,238,35,1,5.456712062256827,308,36,1,13.075875486381335,309,37,1,12.898832684824924,310,38,1,12.898832684824924,311,39,1,12.898832684824924,150,40,1,3.580078125,-1,41,1,6.69677734375,10,42,1,4.61474609375,82,43,1,7.0966796875,12,44,1,4.646484375,82,45,1,3.1357421875,77,46,1,7.6044921875,7,47,1,7.50927734375,238]}}
  #|{"textrec":{"g":227,"r":[364,32,12,16,-1,-14,0]}}
  #|{"textrec":{"g":228,"r":[377,32,8,15,-1,-13,0]}}
  #|{"textrec":{"g":229,"r":[386,32,11,13,-1,-11,0]}}
  #|{"textrec":{"g":230,"r":[398,32,5,15,0,-14,0]}}
  #|{"textrec":{"g":231,"r":[404,32,12,13,-1,-11,0]}}
  #|{"textrec":{"g":232,"r":[417,32,10,12,0,-11,0]}}
  #|{"textrec":{"g":233,"r":[428,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":149,"r":[444,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":234,"r":[459,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":235,"r":[475,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":236,"r":[491,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":5,"r":[505,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":237,"r":[519,32,9,12,-1,-8,0]}}
  #|{"textrec":{"g":238,"r":[529,32,8,9,0,-8,0]}}
  #|{"textrec":{"g":239,"r":[538,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":240,"r":[554,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":241,"r":[570,32,16,17,-1,-14,0]}}
  #|{"textrec":{"g":242,"r":[587,32,10,12,-1,-10,0]}}
  #|{"textrec":{"g":243,"r":[598,32,8,13,-1,-11,0]}}
  #|{"textrec":{"g":244,"r":[607,32,10,12,-1,-10,0]}}
  #|{"textrec":{"g":245,"r":[618,32,6,14,-1,-13,0]}}
  #|{"textrec":{"g":246,"r":[625,32,11,12,-1,-10,0]}}
  #|{"textrec":{"g":247,"r":[637,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":248,"r":[654,32,16,17,-1,-14,0]}}
  #|{"textrec":{"g":249,"r":[671,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":250,"r":[688,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":251,"r":[705,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":253,"r":[723,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":254,"r":[741,32,16,17,-1,-14,0]}}
  #|{"textrec":{"g":289,"r":[758,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":290,"r":[775,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":255,"r":[793,32,13,13,-1,-12,0]}}
  #|{"textrec":{"g":256,"r":[807,32,11,14,-1,-10,0]}}
  #|{"textrec":{"g":257,"r":[819,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":258,"r":[837,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":259,"r":[855,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":260,"r":[873,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":261,"r":[890,32,15,17,0,-14,0]}}
  #|{"textrec":{"g":262,"r":[906,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":263,"r":[923,32,17,17,-1,-14,0]}}
  #|{"textrec":{"ib":["7849ac311190abd2",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"g":291,"r":[941,32,9,10,0,-9,0]}}
  #|{"textrec":{"g":163,"r":[951,32,9,11,0,-9,0]}}
  #|{"textrec":{"g":292,"r":[961,32,6,17,-2,-13,0]}}
  #|{"textrec":{"g":293,"r":[968,32,7,4,0,-6,0]}}
  #|{"textrec":{"g":294,"r":[976,32,13,13,0,-12,0]}}
  #|{"textrec":{"g":295,"r":[990,32,10,15,-1,-13,0]}}
  #|{"textrec":{"g":296,"r":[1001,32,15,14,-1,-12,0]}}
  #|{"textrec":{"g":7,"r":[1017,32,9,10,-1,-8,0]}}
  #|{"textrec":{"g":297,"r":[1027,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":298,"r":[1043,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":299,"r":[1059,32,15,14,-1,-11,0]}}
  #|{"textrec":{"g":300,"r":[1075,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":301,"r":[1091,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":302,"r":[1106,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":303,"r":[1122,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":304,"r":[1137,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":305,"r":[1153,32,5,15,-1.16666666666667,-12,0]}}
  #|{"textrec":{"g":306,"r":[1159,32,7,12,-1,-11,0]}}
  #|{"textrec":{"g":307,"r":[1167,32,8,4,-1,-6,0]}}
  #|{"textrec":{"g":8,"r":[1176,32,6,9,0,-8,0]}}
  #|{"textrec":{"g":308,"r":[1183,32,6,15,-1,-12,0]}}
  #|{"textrec":{"g":309,"r":[1190,32,5,7,0,-3,0]}}
  #|{"textrec":{"g":310,"r":[1196,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":311,"r":[1212,32,15,14,-1,-11,0]}}
  #|{"textrec":{"g":150,"r":[1228,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":225,"r":[1244,32,10,12,0,-10,0]}}
  #|{"textrec":{"g":226,"r":[1255,32,11,15,-1,-13,0]}}
  #|{"textrec":{"g":223,"r":[1267,32,13,13,-1,-10,0]}}
  #|{"textrec":{"g":224,"r":[1281,32,13,13,-1,-10,0]}}
  #|{"textrec":{"g":252,"r":[1295,32,16,16,-1,-13,0]}}
  #|{"textrec":{"ib":["bb8194441930dadc",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"s":[17,700,0,"studio"],"r":[0,1,9.176513671875,312,1,1,6.561767578125,313,2,1,10.230712890625,314,3,1,10.6416015625,315,4,1,4.44921875,316,5,1,10.10205078125,317]}}
  #|{"textrec":{"m":[17,700,0],"r":[16.435546875,3.5859375,24,16.435546875,3.5859375,0]}}
  #|{"textrec":{"s":[15,400,0,"重命名"],"r":[0,1,14.883268482490273,318,1,1,14.883268482490273,319,2,1,14.883268482490273,320]}}
  #|{"textrec":{"s":[15,400,0,"图标"],"r":[0,1,14.883268482490273,321,1,1,14.883268482490273,322]}}
  #|{"textrec":{"s":[15,400,0,"从 workspace 移除"],"r":[0,1,14.883268482490273,323,1,1,3.984375,-1,2,1,11.2353515625,324,3,1,8.4814453125,88,4,1,5.478515625,89,5,1,7.763671875,90,6,1,7.470703125,91,7,1,8.920898437500007,92,8,1,8.0419921875,93,9,1,8.1591796875,94,10,1,8.3349609375,95,11,1,3.984375,-1,12,1,14.88326848249028,325,13,1,14.88326848249028,326]}}
  #|{"textrec":{"g":312,"r":[1312,32,11,13,-1,-11,0]}}
  #|{"textrec":{"g":313,"r":[1324,32,9,15,-1,-13,0]}}
  #|{"textrec":{"g":314,"r":[1334,32,11,13,0,-11,0]}}
  #|{"textrec":{"g":315,"r":[1346,32,12,16,-1,-14,0]}}
  #|{"textrec":{"g":316,"r":[1359,32,5,16,0,-15,0]}}
  #|{"textrec":{"g":317,"r":[1365,32,12,13,-1,-11,0]}}
  #|{"textrec":{"g":318,"r":[1378,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":319,"r":[1395,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":320,"r":[1412,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":321,"r":[1428,32,15,16,0,-13,0]}}
  #|{"textrec":{"g":322,"r":[1444,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":323,"r":[1461,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":324,"r":[1479,32,14,10,-1,-9,0]}}
  #|{"textrec":{"g":325,"r":[1494,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":326,"r":[1511,32,16,16,0,-13,0]}}
  #|{"textrec":{"s":[13,400,0,"共 55 KB"],"r":[0,1,12.898832684824903,215,1,1,3.580078125,-1,2,1,7.9599609375,216,3,1,7.9599609375,216,4,1,3.580078125,-1,5,1,8.48681640625,218,6,1,8.4677734375,219]}}
  #|{"textrec":{"s":[13,500,0,"996 B/s"],"r":[0,1,8.424629211425781,327,1,1,8.424629211425781,327,2,1,8.424629211425781,328,3,1,3.4683494567871094,-1,4,1,8.640021800994873,329,5,1,4.026754140853882,330,6,1,6.933351516723633,214]}}
  #|{"textrec":{"s":[13,400,0,"共 52 KB"],"r":[0,1,12.898832684824903,215,1,1,3.580078125,-1,2,1,7.9599609375,216,3,1,7.76953125,331,4,1,3.580078125,-1,5,1,8.48681640625,218,6,1,8.4677734375,219]}}
  #|{"textrec":{"s":[13,500,0,"900 B/s"],"r":[0,1,8.424629211425781,327,1,1,8.373004913330078,212,2,1,8.373004913330078,212,3,1,3.4683494567871094,-1,4,1,8.640021800994873,329,5,1,4.026754140853882,330,6,1,6.933351516723633,214]}}
  #|{"textrec":{"g":327,"r":[1528,32,10,13,-1,-11,0]}}
  #|{"textrec":{"g":328,"r":[1539,32,10,13,-1,-11,0]}}
  #|{"textrec":{"g":329,"r":[1550,32,10,12,0,-11,0]}}
  #|{"textrec":{"g":330,"r":[1561,32,7,15,-1,-11,0]}}
  #|{"textrec":{"g":212,"r":[1569,32,10,13,-1,-11,0]}}
  #|{"textrec":{"g":331,"r":[1580,32,9,12,-1,-11,0]}}
  #|{"textrec":{"s":[17,700,0,"为 studio 选择图标"],"r":[0,1,16.851167315175097,332,1,1,3.951171875,-1,2,1,9.176513671875,312,3,1,6.561767578125,313,4,1,10.230712890625,314,5,1,10.6416015625,315,6,1,4.44921875,316,7,1,10.102050781250007,317,8,1,3.951171875,-1,9,1,16.851167315175104,333,10,1,16.851167315175104,334,11,1,16.851167315175104,335,12,1,16.851167315175104,336]}}
  #|{"textrec":{"s":[14,400,0,"图标"],"r":[0,1,13.891050583657588,337,1,1,13.891050583657588,338]}}
  #|{"textrec":{"s":[14,400,0,"Emoji"],"r":[0,1,8.189453125,339,1,1,12.03125,340,2,1,8.12109375,341,3,1,3.3017578125,342,4,1,3.30859375,343]}}
  #|{"textrec":{"g":332,"r":[1590,32,18,18,-1,-15,0]}}
  #|{"textrec":{"g":333,"r":[1609,32,18,18,-1,-15,0]}}
  #|{"textrec":{"g":334,"r":[1628,32,19,18,-1,-15,0]}}
  #|{"textrec":{"g":335,"r":[1648,32,17,18,0,-15,0]}}
  #|{"textrec":{"g":336,"r":[1666,32,19,18,-1,-15,0]}}
  #|{"textrec":{"g":337,"r":[1686,32,14,15,0,-12,0]}}
  #|{"textrec":{"g":338,"r":[1701,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":339,"r":[1718,32,9,12,0,-11,0]}}
  #|{"textrec":{"g":340,"r":[1728,32,13,10,0,-9,0]}}
  #|{"textrec":{"g":341,"r":[1742,32,10,11,-1,-9,0]}}
  #|{"textrec":{"g":342,"r":[1753,32,6,16,-2,-12,0]}}
  #|{"textrec":{"g":343,"r":[1760,32,5,13,-1,-12,0]}}
  #|{"textrec":{"s":[15,400,0,"搜索图标"],"r":[0,1,14.883268482490273,18,1,1,14.883268482490273,19,2,1,14.883268482490273,321,3,1,14.883268482490273,322]}}
  #|{"textrec":{"ib":["f6e98b13a1afe582",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["c2f3496aed2fe0ae",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["1f1890bdfe9ffc9a",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["14170ccdd15d643b",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["12853e0955ee8ef2",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["32e0c40760ff6532",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["f7bb4705ee18d6c5",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["c6f2dc3c351390fb",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["1e36fc42cd984eeb",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["133a8cc6d8e7ade6",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["e22c5b10ae9790c0",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["1bca7a86e998d724",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["69001494142e61da",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["6f54db5e7bdae157",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["c429b783c2070d54",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["dbb01c9a7aab0329",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["bcf9c60c380c37f3",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["6461515b0e9cc9ea",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["aca10700f7b994c2",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["c78ba622d4bb0747",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["72917ee66838b184",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["af6d2487a93995a5",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["5c7ee1b23daef19f",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["42754ed3ead9ab90",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["1f37d20c06db3da4",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["7215c5d943ebeb51",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["a753eb1b7fcddc99",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["7c6a7658a8accdfe",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["34a84e8aca93a2a6",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["96ae8afd495ca086",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["7228cdae3afbcb85",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["cfafdbd7d81b12f4",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["c504dc3d9bd27805",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["f99d3c62a6617516",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["21c99f7de1c554d6",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["16d7a9079381e4c8",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["6120633738dd01a8",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["c40cf8e78cf0bc56",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["a408dcbaaf93c450",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["92113db51b26c1e9",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["cb0b17a17e5b2b0e",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["a321e1862da7921f",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["46e0ef3d9625b3d9",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["9da67b67f7bb336d",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["81f2dd58544d21ef",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["28a93384406469ad",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["fc55784856e82578",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["4c3392d5e6bb6d09",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"s":[11,400,0,"Apple M2 Max · 64 GB · macOS 27.0.1"],"r":[0,1,7.4765625,344,1,1,6.7783203125,345,2,1,6.7783203125,345,3,1,2.8466796875,346,4,1,6.3486328125,347,5,1,3.158203125,-1,6,1,9.6787109375,348,7,1,6.703125,349,8,1,3.158203125,-1,9,1,9.6787109375,348,10,1,6.1337890625,350,11,1,5.8330078125,351,12,1,3.158203125,-1,13,1,5.28040385497934,352,14,1,3.158203125,-1,15,1,7.068359375,353,16,1,7.1435546875,354,17,1,3.158203125,-1,18,1,8.27685546875,355,19,1,7.2939453125,356,20,1,3.158203125,-1,21,1,5.28040385497934,352,22,1,3.158203125,-1,23,1,9.6357421875,357,24,1,6.1337890625,350,25,1,6.2197265625,358,26,1,8.55078125,359,27,1,7.07373046875,360,28,1,3.158203125,-1,29,1,6.703125,349,30,1,5.736328125,361,31,1,2.5244140625,362,32,1,6.5634765625,363,33,1,2.9541015625,362,34,1,5.005859375,364]}}
  #|{"textrec":{"s":[11,400,0,"…"],"r":[0,1,8.916015625,365]}}
  #|{"textrec":{"s":[11,400,0,"Apple M2 Max · 64 GB · macOS 27.…"],"r":[0,1,7.4765625,344,1,1,6.7783203125,345,2,1,6.7783203125,345,3,1,2.8466796875,346,4,1,6.3486328125,347,5,1,3.158203125,-1,6,1,9.6787109375,348,7,1,6.703125,349,8,1,3.158203125,-1,9,1,9.6787109375,348,10,1,6.1337890625,350,11,1,5.8330078125,351,12,1,3.158203125,-1,13,1,5.28040385497934,352,14,1,3.158203125,-1,15,1,7.068359375,353,16,1,7.1435546875,354,17,1,3.158203125,-1,18,1,8.27685546875,355,19,1,7.2939453125,356,20,1,3.158203125,-1,21,1,5.28040385497934,352,22,1,3.158203125,-1,23,1,9.6357421875,357,24,1,6.1337890625,350,25,1,6.2197265625,358,26,1,8.55078125,359,27,1,7.07373046875,360,28,1,3.158203125,-1,29,1,6.703125,349,30,1,5.736328125,361,31,1,2.7392578125,362,32,1,8.916015625,365]}}
  #|{"textrec":{"s":[28,600,0,"81"],"r":[0,1,18.046374320983887,366,1,1,13.446255683898926,367]}}
  #|{"textrec":{"m":[28,600,0],"r":[27.0703125,5.90625,40,24.0787353515625,3.9212646484375,0]}}
  #|{"textrec":{"s":[15,500,0,"%"],"r":[0,1,14.252007007598877,368]}}
  #|{"textrec":{"m":[15,500,0],"r":[14.501953125,3.1640625,21,14.501953125,3.1640625,0]}}
  #|{"textrec":{"s":[13,500,0,"CPU 空闲"],"r":[0,1,9.350531578063965,369,1,1,8.364851832389832,370,2,1,9.618190050125122,371,3,1,3.4683494567871094,-1,4,1,12.898832684824903,372,5,1,12.898832684824903,373]}}
  #|{"textrec":{"s":[12,400,0,"负载 4.3"],"r":[0,1,11.918287937743191,374,1,1,11.918287937743191,375,2,1,3.375,-1,3,1,7.517578125,376,4,1,3.181640625,377,5,1,7.34765625,378]}}
  #|{"textrec":{"m":[12,400,0],"r":[11.6015625,2.53125,17,11.6015625,2.53125,0]}}
  #|{"textrec":{"s":[28,600,0,"30.9"],"r":[0,1,17.602505683898926,379,1,1,17.899405002593994,380,2,1,6.547446250915527,381,3,1,18.289981365203857,382]}}
  #|{"textrec":{"s":[15,500,0,"GB"],"r":[0,1,11.039557456970215,383,1,1,9.822771549224854,384]}}
  #|{"textrec":{"s":[13,500,0,"内存剩"],"r":[0,1,12.898832684824903,385,1,1,12.898832684824903,386,2,1,12.898832684824903,387]}}
  #|{"textrec":{"s":[12,400,0,"共 64 GB"],"r":[0,1,11.918287937743191,388,1,1,3.375,-1,2,1,7.640625,389,3,1,7.72265625,376,4,1,3.3749999999999964,-1,5,1,8.958984375,390,6,1,7.88671875,391]}}
  #|{"textrec":{"s":[28,600,0,"74.9"],"r":[0,1,15.31406545639038,392,1,1,17.24337863922119,393,2,1,6.864175796508789,381,3,1,18.289981365203857,382]}}
  #|{"textrec":{"s":[13,500,0,"磁盘剩"],"r":[0,1,12.898832684824903,394,1,1,12.898832684824903,395,2,1,12.898832684824903,387]}}
  #|{"textrec":{"s":[12,400,0,"共 926 GB"],"r":[0,1,11.918287937743191,388,1,1,3.375,-1,2,1,7.640625,396,3,1,7.2421875,397,4,1,7.6406249999999964,389,5,1,3.375,-1,6,1,8.958984375,390,7,1,7.88671875,391]}}
  #|{"textrec":{"s":[13,400,0,"主机名"],"r":[0,1,12.898832684824903,398,1,1,12.898832684824903,399,2,1,12.898832684824903,400]}}
  #|{"textrec":{"s":[13,400,0,"zuozijians-Mac-Studio"],"r":[0,1,6.931640625,401,1,1,7.50927734375,402,2,1,7.50927734375,7,3,1,6.83642578125,401,4,1,3.1357421875,77,5,1,3.12939453125,403,6,1,3.1357421875,77,7,1,7.0966796875,12,8,1,7.50927734375,238,9,1,6.728515625,10,10,1,6.0556640625,307,11,1,11.2861328125,404,12,1,7.0966796875,12,13,1,7.1982421875,13,14,1,6.0556640625,307,15,1,8.20751953125,405,16,1,4.646484375,82,17,1,7.50927734375,402,18,1,7.9091796875,406,19,1,3.1357421875,77,20,1,7.6044921875,7]}}
  #|{"textrec":{"s":[13,400,0,"芯片"],"r":[0,1,12.898832684824903,407,1,1,12.898832684824903,288]}}
  #|{"textrec":{"s":[13,400,0,"Apple M2 Max · 12 核 · arm64"],"r":[0,1,8.68359375,408,1,1,7.8583984375,11,2,1,7.8583984375,11,3,1,3.2119140625,76,4,1,7.3505859375,14,5,1,3.580078125,-1,6,1,11.2861328125,404,7,1,7.76953125,331,8,1,3.580078125,-1,9,1,11.2861328125,404,10,1,7.0966796875,12,11,1,6.7412109375,79,12,1,3.580078125,-1,13,1,6.228545204222115,409,14,1,3.580078125,-1,15,1,5.9541015625,410,16,1,7.76953125,331,17,1,3.580078125,-1,18,1,12.898832684824896,411,19,1,3.580078125,-1,20,1,6.228545204222115,409,21,1,3.580078125,-1,22,1,7.0966796875,12,23,1,4.9384765625,8,24,1,11.298828125,80,25,1,8.201171875,412,26,1,8.2900390625,413]}}
  #|{"textrec":{"s":[13,400,0,"已运行"],"r":[0,1,12.898832684824903,414,1,1,12.898832684824903,234,2,1,12.898832684824903,235]}}
  #|{"textrec":{"s":[13,400,0,"1 天 6 小时"],"r":[0,1,5.9541015625,410,1,1,3.580078125,-1,2,1,12.898832684824903,415,3,1,3.580078125,-1,4,1,8.201171875,412,5,1,3.580078125,-1,6,1,12.898832684824903,416,7,1,12.898832684824903,153]}}
  #|{"textrec":{"s":[13,400,0,"still.fail"],"r":[0,1,6.69677734375,10,1,1,4.61474609375,82,2,1,3.1357421875,77,3,1,3.2119140625,76,4,1,3.2119140625,76,5,1,3.5927734375,81,6,1,4.341796875,306,7,1,7.00146484375,12,8,1,3.1357421875,77,9,1,3.2119140625,76]}}
  #|{"textrec":{"s":[13,400,0,"进程占用 205 MB"],"r":[0,1,12.898832684824903,239,1,1,12.898832684824903,240,2,1,12.898832684824903,417,3,1,12.898832684824903,418,4,1,3.580078125,-1,5,1,7.76953125,331,6,1,8.1123046875,221,7,1,7.9599609375,216,8,1,3.580078125,-1,9,1,11.2861328125,404,10,1,8.4677734375,219]}}
  #|{"textrec":{"g":344,"r":[1766,32,10,10,-1,-9,0]}}
  #|{"textrec":{"g":345,"r":[1777,32,9,10,-1,-7,0]}}
  #|{"textrec":{"g":346,"r":[1787,32,4,11,-1,-10,0]}}
  #|{"textrec":{"g":347,"r":[1792,32,8,9,-1,-7,0]}}
  #|{"textrec":{"g":348,"r":[1801,32,11,10,-1,-9,0]}}
  #|{"textrec":{"g":349,"r":[1813,32,8,10,-1,-9,0]}}
  #|{"textrec":{"g":350,"r":[1822,32,8,9,-1,-7,0]}}
  #|{"textrec":{"g":351,"r":[1831,32,8,8,-1,-7,0]}}
  #|{"textrec":{"g":352,"r":[1840,32,5,4,0,-6,0]}}
  #|{"textrec":{"g":353,"r":[1846,32,9,11,-1,-9,0]}}
  #|{"textrec":{"g":354,"r":[1856,32,9,10,-1,-9,0]}}
  #|{"textrec":{"g":355,"r":[1866,32,10,11,-1,-9,0]}}
  #|{"textrec":{"g":356,"r":[1877,32,9,10,-1,-9,0]}}
  #|{"textrec":{"g":357,"r":[1887,32,11,8,-1,-7,0]}}
  #|{"textrec":{"g":358,"r":[1899,32,8,9,-1,-7,0]}}
  #|{"textrec":{"g":359,"r":[1908,32,10,11,-1,-9,0]}}
  #|{"textrec":{"g":360,"r":[1919,32,9,11,-1,-9,0]}}
  #|{"textrec":{"g":361,"r":[1929,32,8,10,-1,-9,0]}}
  #|{"textrec":{"g":362,"r":[1938,32,5,5,-1,-3,0]}}
  #|{"textrec":{"g":365,"r":[1944,32,10,5,-1,-3,0]}}
  #|{"textrec":{"g":366,"r":[1955,32,18,24,0,-22,0]}}
  #|{"textrec":{"g":367,"r":[1974,32,11,22,0,-21,0]}}
  #|{"textrec":{"g":368,"r":[1986,32,16,14,-1,-12,0]}}
  #|{"textrec":{"g":369,"r":[2003,32,11,13,-1,-11,0]}}
  #|{"textrec":{"g":370,"r":[2015,32,9,12,0,-11,0]}}
  #|{"textrec":{"g":371,"r":[2025,32,10,13,0,-11,0]}}
  #|{"textrec":{"g":372,"r":[0,57,14,14,-1,-12,0]}}
  #|{"textrec":{"g":373,"r":[15,57,13,15,0,-12,0]}}
  #|{"textrec":{"g":374,"r":[29,57,13,14,-1,-11,0]}}
  #|{"textrec":{"g":375,"r":[43,57,14,14,-1,-11,0]}}
  #|{"textrec":{"g":376,"r":[58,57,10,11,-1,-10,0]}}
  #|{"textrec":{"g":377,"r":[69,57,4,5,0,-3,0]}}
  #|{"textrec":{"g":378,"r":[74,57,9,12,-1,-10,0]}}
  #|{"textrec":{"g":379,"r":[84,57,17,24,0,-22,0]}}
  #|{"textrec":{"g":380,"r":[102,57,18,24,0,-22,0]}}
  #|{"textrec":{"g":381,"r":[121,57,7,7,0,-5,0]}}
  #|{"textrec":{"g":382,"r":[129,57,18,24,0,-22,0]}}
  #|{"textrec":{"g":383,"r":[148,57,13,14,-1,-12,0]}}
  #|{"textrec":{"g":384,"r":[162,57,11,13,0,-12,0]}}
  #|{"textrec":{"g":385,"r":[174,57,13,15,0,-12,0]}}
  #|{"textrec":{"g":386,"r":[188,57,15,15,-1,-12,0]}}
  #|{"textrec":{"g":387,"r":[204,57,14,15,-1,-12,0]}}
  #|{"textrec":{"g":388,"r":[219,57,14,14,-1,-11,0]}}
  #|{"textrec":{"g":389,"r":[234,57,9,12,-1,-10,0]}}
  #|{"textrec":{"g":390,"r":[244,57,11,12,-1,-10,0]}}
  #|{"textrec":{"g":391,"r":[256,57,9,11,0,-10,0]}}
  #|{"textrec":{"g":392,"r":[266,57,17,22,-1,-21,0]}}
  #|{"textrec":{"g":393,"r":[284,57,18,22,0,-21,0]}}
  #|{"textrec":{"g":394,"r":[303,57,15,15,-1,-12,0]}}
  #|{"textrec":{"g":395,"r":[319,57,15,14,-1,-12,0]}}
  #|{"textrec":{"g":396,"r":[335,57,9,12,-1,-10,0]}}
  #|{"textrec":{"g":397,"r":[345,57,9,11,-1,-10,0]}}
  #|{"textrec":{"g":398,"r":[355,57,14,14,-1,-12,0]}}
  #|{"textrec":{"g":399,"r":[370,57,15,15,-1,-12,0]}}
  #|{"textrec":{"g":400,"r":[386,57,14,15,-1,-12,0]}}
  #|{"textrec":{"g":401,"r":[401,57,9,9,-1,-8,0]}}
  #|{"textrec":{"g":402,"r":[411,57,9,10,-1,-8,0]}}
  #|{"textrec":{"g":403,"r":[421,57,6,15,-2,-11,0]}}
  #|{"textrec":{"g":404,"r":[428,57,12,12,0,-11,0]}}
  #|{"textrec":{"g":405,"r":[441,57,10,13,-1,-11,0]}}
  #|{"textrec":{"g":406,"r":[452,57,9,13,-1,-11,0]}}
  #|{"textrec":{"g":407,"r":[462,57,15,15,-1,-12,0]}}
  #|{"textrec":{"g":288,"r":[478,57,14,15,-1,-12,0]}}
  #|{"textrec":{"g":408,"r":[493,57,11,12,-1,-11,0]}}
  #|{"textrec":{"g":409,"r":[505,57,4,5,1,-7,0]}}
  #|{"textrec":{"g":410,"r":[510,57,7,12,-1,-11,0]}}
  #|{"textrec":{"g":411,"r":[518,57,15,15,-1,-12,0]}}
  #|{"textrec":{"g":412,"r":[534,57,10,13,-1,-11,0]}}
  #|{"textrec":{"g":413,"r":[545,57,10,12,-1,-11,0]}}
  #|{"textrec":{"g":414,"r":[556,57,13,13,0,-11,0]}}
  #|{"textrec":{"g":415,"r":[570,57,15,14,-1,-11,0]}}
  #|{"textrec":{"g":416,"r":[586,57,15,15,-1,-12,0]}}
  #|{"textrec":{"g":153,"r":[602,57,15,15,-1,-12,0]}}
  #|{"textrec":{"g":417,"r":[618,57,13,15,0,-12,0]}}
  #|{"textrec":{"g":418,"r":[632,57,14,14,-1,-11,0]}}
  #|{"textrec":{"s":[15,400,0,"robot"],"r":[0,1,5.36865234375,89,1,1,8.51806640625,88,2,1,8.9794921875,162,3,1,8.6279296875,88,4,1,5.21484375,101]}}
  #|{"textrec":{"s":[15,400,0,"上传图片"],"r":[0,1,14.883268482490273,419,1,1,14.883268482490273,420,2,1,14.883268482490273,321,3,1,14.883268482490273,421]}}
  #|{"textrec":{"g":162,"r":[647,57,10,15,0,-13,0]}}
  #|{"textrec":{"g":419,"r":[658,57,16,15,-1,-13,0]}}
  #|{"textrec":{"g":420,"r":[675,57,17,16,-1,-13,0]}}
  #|{"textrec":{"g":421,"r":[693,57,15,16,0,-13,0]}}
  #|{"textrec":{"ib":["9f80ba5aa8a0be33",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"s":[14,400,0,"已设置图标"],"r":[0,1,13.891050583657588,422,1,1,13.891050583657588,423,2,1,13.891050583657588,424,3,1,13.891050583657588,337,4,1,13.891050583657588,338]}}
  #|{"textrec":{"g":422,"r":[709,57,14,14,0,-12,0]}}
  #|{"textrec":{"g":423,"r":[724,57,16,15,-1,-12,0]}}
  #|{"textrec":{"g":424,"r":[741,57,15,15,-1,-12,0]}}
  #|{"textrec":{"s":[13,500,0,"69 B/s"],"r":[0,1,8.424629211425781,328,1,1,8.424629211425781,327,2,1,3.4683494567871094,-1,3,1,8.640021800994873,329,4,1,4.026754140853882,330,5,1,6.933351516723633,214]}}
  #|{"textrec":{"s":[13,500,0,"1.6 KB/s"],"r":[0,1,6.017703652381897,222,1,1,3.589407444000244,425,2,1,8.153265357017517,328,3,1,3.4683494567871094,-1,4,1,8.727731347084045,426,5,1,8.640021800994873,329,6,1,4.026754140853882,330,7,1,6.933351516723633,214]}}
  #|{"textrec":{"g":425,"r":[757,57,4,5,0,-3,0]}}
  #|{"textrec":{"g":426,"r":[762,57,10,12,0,-11,0]}}
  #|{"textrec":{"ib":["8711b36433668935",983,64],"r":[15,15,15,15]}}
  #|{"textrec":{"s":[13,400,0,"共 77 KB"],"r":[0,1,12.898832684824903,215,1,1,3.580078125,-1,2,1,7.4521484375,427,3,1,7.4521484375,427,4,1,3.580078125,-1,5,1,8.48681640625,218,6,1,8.4677734375,219]}}
  #|{"textrec":{"s":[13,500,0,"10 KB/s"],"r":[0,1,6.182214260101318,222,1,1,8.373004913330078,212,2,1,3.4683494567871094,-1,3,1,8.727731347084045,426,4,1,8.640021800994873,329,5,1,4.026754140853882,330,6,1,6.933351516723633,214]}}
  #|{"textrec":{"s":[13,400,0,"共 74 KB"],"r":[0,1,12.898832684824903,215,1,1,3.580078125,-1,2,1,6.9443359375,427,3,1,7.9091796875,413,4,1,3.580078125,-1,5,1,8.48681640625,218,6,1,8.4677734375,219]}}
  #|{"textrec":{"s":[13,500,0,"9.0 KB/s"],"r":[0,1,8.141626954078674,327,1,1,3.4709157943725586,425,2,1,8.101641058921814,212,3,1,3.4683494567871094,-1,4,1,8.727731347084045,426,5,1,8.640021800994873,329,6,1,4.026754140853882,330,7,1,6.933351516723633,214]}}
  #|{"textrec":{"g":427,"r":[773,57,9,12,-1,-11,0]}}
  #|{"textrec":{"ib":["33dde8b3ab9dab99",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"s":[26,400,0,"🖥️"],"r":[0,3,30,428]}}
  #|{"textrec":{"m":[26,400,0],"r":[25.13671875,5.484375,37,22.35882568359375,3.64117431640625,0]}}
  #|{"textrec":{"s":[26,400,0,"💻"],"r":[0,2,30,429]}}
  #|{"textrec":{"s":[26,400,0,"🍎"],"r":[0,2,30,430]}}
  #|{"textrec":{"s":[26,400,0,"🐧"],"r":[0,2,30,431]}}
  #|{"textrec":{"s":[26,400,0,"🪟"],"r":[0,2,30,432]}}
  #|{"textrec":{"s":[26,400,0,"☁️"],"r":[0,2,30,433]}}
  #|{"textrec":{"s":[26,400,0,"🏠"],"r":[0,2,30,434]}}
  #|{"textrec":{"s":[26,400,0,"🏢"],"r":[0,2,30,435]}}
  #|{"textrec":{"s":[26,400,0,"🚀"],"r":[0,2,30,436]}}
  #|{"textrec":{"s":[26,400,0,"⚡"],"r":[0,1,30,437]}}
  #|{"textrec":{"s":[26,400,0,"🔥"],"r":[0,2,30,438]}}
  #|{"textrec":{"s":[26,400,0,"🧪"],"r":[0,2,30,439]}}
  #|{"textrec":{"s":[26,400,0,"🛠️"],"r":[0,3,30,440]}}
  #|{"textrec":{"s":[26,400,0,"🐳"],"r":[0,2,30,441]}}
  #|{"textrec":{"s":[26,400,0,"🦀"],"r":[0,2,30,442]}}
  #|{"textrec":{"s":[26,400,0,"🐙"],"r":[0,2,30,443]}}
  #|{"textrec":{"s":[26,400,0,"🌲"],"r":[0,2,30,444]}}
  #|{"textrec":{"s":[26,400,0,"🌊"],"r":[0,2,30,445]}}
  #|{"textrec":{"s":[26,400,0,"🌙"],"r":[0,2,30,446]}}
  #|{"textrec":{"s":[26,400,0,"☀️"],"r":[0,2,30,447]}}
  #|{"textrec":{"s":[26,400,0,"🍊"],"r":[0,2,30,448]}}
  #|{"textrec":{"s":[26,400,0,"🍋"],"r":[0,2,30,449]}}
  #|{"textrec":{"s":[26,400,0,"🍇"],"r":[0,2,30,450]}}
  #|{"textrec":{"s":[26,400,0,"🐱"],"r":[0,2,30,451]}}
  #|{"textrec":{"s":[26,400,0,"🐶"],"r":[0,2,30,452]}}
  #|{"textrec":{"s":[26,400,0,"🦊"],"r":[0,2,30,453]}}
  #|{"textrec":{"s":[26,400,0,"🐼"],"r":[0,2,30,454]}}
  #|{"textrec":{"s":[26,400,0,"🐸"],"r":[0,2,30,455]}}
  #|{"textrec":{"s":[26,400,0,"🦉"],"r":[0,2,30,456]}}
  #|{"textrec":{"s":[26,400,0,"🐝"],"r":[0,2,30,457]}}
  #|{"textrec":{"s":[26,400,0,"🦄"],"r":[0,2,30,458]}}
  #|{"textrec":{"s":[26,400,0,"🐢"],"r":[0,2,30,459]}}
  #|{"textrec":{"s":[26,400,0,"🌵"],"r":[0,2,30,460]}}
  #|{"textrec":{"s":[26,400,0,"🌸"],"r":[0,2,30,461]}}
  #|{"textrec":{"s":[26,400,0,"🍄"],"r":[0,2,30,462]}}
  #|{"textrec":{"s":[26,400,0,"🌈"],"r":[0,2,30,463]}}
  #|{"textrec":{"s":[26,400,0,"❄️"],"r":[0,2,30,464]}}
  #|{"textrec":{"s":[26,400,0,"⭐"],"r":[0,1,30,465]}}
  #|{"textrec":{"s":[26,400,0,"🪐"],"r":[0,2,30,466]}}
  #|{"textrec":{"s":[26,400,0,"🌍"],"r":[0,2,30,467]}}
  #|{"textrec":{"s":[26,400,0,"🍉"],"r":[0,2,30,468]}}
  #|{"textrec":{"s":[26,400,0,"🍒"],"r":[0,2,30,469]}}
  #|{"textrec":{"s":[26,400,0,"🥑"],"r":[0,2,30,470]}}
  #|{"textrec":{"s":[26,400,0,"🍕"],"r":[0,2,30,471]}}
  #|{"textrec":{"s":[26,400,0,"☕"],"r":[0,1,30,472]}}
  #|{"textrec":{"s":[26,400,0,"🎧"],"r":[0,2,30,473]}}
  #|{"textrec":{"s":[26,400,0,"🎮"],"r":[0,2,30,474]}}
  #|{"textrec":{"s":[26,400,0,"🤖"],"r":[0,2,30,475]}}
  #|{"textrec":{"s":[15,400,0,"不使用图标"],"r":[0,1,14.883268482490273,476,1,1,14.883268482490273,477,2,1,14.883268482490273,115,3,1,14.883268482490273,321,4,1,14.88326848249028,322]}}
  #|{"textrec":{"s":[15,400,0,"粘贴或输入任意 emoji"],"r":[0,1,14.883268482490273,478,1,1,14.883268482490273,479,2,1,14.883268482490273,480,3,1,14.883268482490273,481,4,1,14.88326848249028,482,5,1,14.88326848249028,483,6,1,14.88326848249028,484,7,1,3.984375,-1,8,1,8.3349609375,95,9,1,12.8173828125,161,10,1,8.6279296875,88,11,1,3.46435546875,292,12,1,3.4716796875,102]}}
  #|{"textrec":{"g":478,"r":[783,57,16,16,-1,-13,0]}}
  #|{"textrec":{"g":479,"r":[800,57,16,16,-1,-13,0]}}
  #|{"textrec":{"g":480,"r":[817,57,16,16,-1,-13,0]}}
  #|{"textrec":{"g":481,"r":[834,57,17,16,-1,-13,0]}}
  #|{"textrec":{"g":482,"r":[852,57,16,16,-1,-13,0]}}
  #|{"textrec":{"g":483,"r":[869,57,16,16,-1,-13,0]}}
  #|{"textrec":{"g":484,"r":[886,57,16,17,-1,-14,0]}}
  #|{"textrec":{"g":161,"r":[903,57,13,11,0,-10,0]}}
  #|{"textrec":{"g":428,"r":[917,57,32,34,-1,-27,1]}}
  #|{"textrec":{"g":429,"r":[950,57,32,34,-1,-27,1]}}
  #|{"textrec":{"g":430,"r":[983,57,32,34,-1,-27,1]}}
  #|{"textrec":{"g":431,"r":[1016,57,32,34,-1,-27,1]}}
  #|{"textrec":{"g":432,"r":[1049,57,32,34,-1,-27,1]}}
  #|{"textrec":{"g":433,"r":[1082,57,32,34,-1,-27,1]}}
  #|{"textrec":{"g":434,"r":[1115,57,32,34,-1,-27,1]}}
  #|{"textrec":{"g":435,"r":[1148,57,32,34,-1,-27,1]}}
  #|{"textrec":{"g":436,"r":[1181,57,32,34,-1,-27,1]}}
  #|{"textrec":{"g":437,"r":[1214,57,32,34,-1,-27,1]}}
  #|{"textrec":{"g":438,"r":[1247,57,32,34,-1,-27,1]}}
  #|{"textrec":{"g":439,"r":[1280,57,32,34,-1,-27,1]}}
  #|{"textrec":{"g":440,"r":[1313,57,32,34,-1,-27,1]}}
  #|{"textrec":{"g":441,"r":[1346,57,32,34,-1,-27,1]}}
  #|{"textrec":{"g":442,"r":[1379,57,32,34,-1,-27,1]}}
  #|{"textrec":{"g":443,"r":[1412,57,32,34,-1,-27,1]}}
  #|{"textrec":{"g":444,"r":[1445,57,32,34,-1,-27,1]}}
  #|{"textrec":{"g":445,"r":[1478,57,32,34,-1,-27,1]}}
  #|{"textrec":{"g":446,"r":[1511,57,32,34,-1,-27,1]}}
  #|{"textrec":{"g":447,"r":[1544,57,32,34,-1,-27,1]}}
  #|{"textrec":{"g":448,"r":[1577,57,32,34,-1,-27,1]}}
  #|{"textrec":{"g":449,"r":[1610,57,32,34,-1,-27,1]}}
  #|{"textrec":{"g":450,"r":[1643,57,32,34,-1,-27,1]}}
  #|{"textrec":{"g":451,"r":[1676,57,32,34,-1,-27,1]}}
  #|{"textrec":{"g":452,"r":[1709,57,32,34,-1,-27,1]}}
  #|{"textrec":{"g":453,"r":[1742,57,32,34,-1,-27,1]}}
  #|{"textrec":{"g":454,"r":[1775,57,32,34,-1,-27,1]}}
  #|{"textrec":{"g":455,"r":[1808,57,32,34,-1,-27,1]}}
  #|{"textrec":{"g":456,"r":[1841,57,32,34,-1,-27,1]}}
  #|{"textrec":{"g":457,"r":[1874,57,32,34,-1,-27,1]}}
  #|{"textrec":{"g":458,"r":[1907,57,32,34,-1,-27,1]}}
  #|{"textrec":{"g":459,"r":[1940,57,32,34,-1,-27,1]}}
  #|{"textrec":{"g":460,"r":[1973,57,32,34,-1,-27,1]}}
  #|{"textrec":{"g":461,"r":[2006,57,32,34,-1,-27,1]}}
  #|{"textrec":{"g":462,"r":[0,92,32,34,-1,-27,1]}}
  #|{"textrec":{"g":463,"r":[33,92,32,34,-1,-27,1]}}
  #|{"textrec":{"g":464,"r":[66,92,32,34,-1,-27,1]}}
  #|{"textrec":{"g":465,"r":[99,92,32,34,-1,-27,1]}}
  #|{"textrec":{"g":466,"r":[132,92,32,34,-1,-27,1]}}
  #|{"textrec":{"g":467,"r":[165,92,32,34,-1,-27,1]}}
  #|{"textrec":{"g":468,"r":[198,92,32,34,-1,-27,1]}}
  #|{"textrec":{"g":469,"r":[231,92,32,34,-1,-27,1]}}
  #|{"textrec":{"g":470,"r":[264,92,32,34,-1,-27,1]}}
  #|{"textrec":{"g":471,"r":[297,92,32,34,-1,-27,1]}}
  #|{"textrec":{"g":472,"r":[330,92,32,34,-1,-27,1]}}
  #|{"textrec":{"g":473,"r":[363,92,32,34,-1,-27,1]}}
  #|{"textrec":{"g":474,"r":[396,92,32,34,-1,-27,1]}}
  #|{"textrec":{"g":475,"r":[429,92,32,34,-1,-27,1]}}
  #|{"textrec":{"s":[13,500,0,"33 B/s"],"r":[0,1,8.274399280548096,485,1,1,8.274399280548096,485,2,1,3.4683494567871094,-1,3,1,8.640021800994873,329,4,1,4.026754140853882,330,5,1,6.933351516723633,214]}}
  #|{"textrec":{"s":[13,500,0,"0 B/s"],"r":[0,1,8.373004913330078,212,1,1,3.4683494567871094,-1,2,1,8.640021800994873,329,3,1,4.026754140853882,330,4,1,6.933351516723633,214]}}
  #|{"textrec":{"g":485,"r":[462,92,10,13,-1,-11,0]}}
  #|{"textrec":{"s":[13.5,400,0,"🚀"],"r":[0,2,19,486]}}
  #|{"textrec":{"m":[13.5,400,0],"r":[13.0517578125,2.84765625,19,13.0517578125,2.84765625,0]}}
  #|{"textrec":{"g":486,"r":[473,92,21,19,-1,-15,1]}}
  #|{"textrec":{"s":[13,500,0,"101 B/s"],"r":[0,1,6.182214260101318,222,1,1,8.373004913330078,212,2,1,6.182214260101318,222,3,1,3.4683494567871094,-1,4,1,8.640021800994873,329,5,1,4.026754140853882,330,6,1,6.933351516723633,214]}}
  #|{"textrec":{"s":[13,500,0,"80 B/s"],"r":[0,1,8.477952003479004,487,1,1,8.361366510391235,212,2,1,3.4683494567871094,-1,3,1,8.640021800994873,329,4,1,4.026754140853882,330,5,1,6.933351516723633,214]}}
  #|{"textrec":{"g":487,"r":[495,92,10,13,-1,-11,0]}}
  #|{"textrec":{"s":[15,400,0,"zzzz"],"r":[0,1,7.8515625,291,1,1,7.8515625,291,2,1,7.8515625,291,3,1,7.8515625,291]}}
  #|{"textrec":{"s":[15,400,0,"未找到图标"],"r":[0,1,14.883268482490273,488,1,1,14.883268482490273,489,2,1,14.883268482490273,490,3,1,14.883268482490273,321,4,1,14.88326848249028,322]}}
  #|{"textrec":{"g":488,"r":[506,92,16,16,-1,-13,0]}}
  #|{"textrec":{"g":489,"r":[523,92,16,16,-1,-13,0]}}
  #|{"textrec":{"g":490,"r":[540,92,16,16,-1,-13,0]}}
  #|{"textrec":{"g":476,"r":[557,92,16,16,-1,-13,0]}}
  #|{"textrec":{"g":477,"r":[574,92,17,17,-1,-14,0]}}
  #|{"textrec":{"ib":["7dc59d31662997da",1688,64],"r":[20,20,20,20]}}
