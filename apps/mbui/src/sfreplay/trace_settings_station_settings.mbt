// e2e/traces/settings-station-settings.trace, made by scripts/trace.py from 01-settings_station_settings.log: not edited by hand.

///|
/// What the app and its core said in the run, a line each.
pub let trace_settings_station_settings : String =
  #|{"env":{"MBUI_CLOUD":"http://127.0.0.1:18787","MBUI_CORE_ACCOUNT":"{\"sub\":\"alice\",\"email\":\"alice@example.test\",\"name\":\"Name of alice\",\"picture\":\"\",\"access\":\"-\",\"refresh\":\"-\",\"accessExpires\":1792594771}"}}
  #|{"out":{"id":1,"call":"client.device","params":{"client":"still.fail mbui","app":"desktop","userAgent":"Macintosh; Mac OS X"}},"w":1792594472802.387}
  #|{"in":{"id":1,"ok":null},"w":1792594472892.589}
  #|{"out":{"id":2,"subscribe":{"topic":"accounts"},"keyed":true},"w":1792594472892.613}
  #|{"out":{"id":3,"subscribe":{"topic":"prefs"},"keyed":true},"w":1792594472892.622}
  #|{"step":"# written by scripts/rerecord.sh from its test (src/sfreplay/emit.mbt): not edited by hand","w":1792594472894.053}
  #|{"step":"timeout 90000","w":1792594472894.06}
  #|{"step":"answered client.device","w":1792594472894.063}
  #|{"step":"answered client.focus","w":1792594472917.058}
  #|{"in":{"id":2,"value":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""}]},"w":1792594472983.407}
  #|{"in":{"id":3,"value":{"onlyMine":false,"onlyWatching":false,"onlyDecisions":false,"listFilter":{},"appearance":"system","rowPicture":"auto","absoluteTime":false,"lang":"zh","keys":{},"lastChat":{},"openChat":{},"chatTabs":{},"dropFiles":{},"driveViews":{},"filesTabs":{},"driveFavorites":{},"resume":{},"stationUpdatesDismissed":{},"device":{"app":"desktop","phone":false,"handoff":false},"reader":{"size":18,"line":1.7,"margin":22,"face":"sans","indent":true,"paper":"follow"},"rails":{},"bars":{"sets":[["chats","files","profiles","stations"],["decisions","usage","connects","archive"]],"current":0},"barsBy":{},"fonts":{},"faces":{"ui":{"id":"","name":"","mono":false,"family":"","files":[],"bytes":0},"text":{"id":"","name":"","mono":false,"family":"","files":[],"bytes":0},"code":{"id":"","name":"","mono":true,"family":"","files":[],"bytes":0},"list":[{"id":"inter","name":"Inter","mono":false,"family":"SF Inter","css":"http://127.0.0.1:18787/releases/fonts/inter/4.001/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/inter/4.001/var.ttf.gz","bytes":457818,"sha256":"29160a80ff49ddcab2c97711247e08b1fab27a484a329ce8b813d820dc559031"}],"preview":"http://127.0.0.1:18787/releases/fonts/inter/4.001/preview-194fa287.ttf","bytes":457818},{"id":"noto-sans-sc","name":"思源黑体","mono":false,"family":"SF Noto Sans SC","css":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/var.ttf.gz","bytes":11276563,"sha256":"a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da"}],"preview":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/preview-f0494178.ttf","bytes":11276563},{"id":"noto-serif-sc","name":"思源宋体","mono":false,"family":"SF Noto Serif SC","css":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/var.ttf.gz","bytes":15454579,"sha256":"050080d9255a86808f2945bffac582b31ef32bc36411ce29563b4961670c66f9"}],"preview":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/preview-001bbedf.ttf","bytes":15454579},{"id":"lxgw-wenkai","name":"霞鹜文楷","mono":false,"family":"SF LXGW WenKai","css":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/font.css","files":[{"weight":400,"url":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/400.ttf.gz","bytes":12904482,"sha256":"2d73eea94ad808999d90c0000c239a84a33b09d4bc6ab6c5b8bbf1eda8a7fc8b"},{"weight":500,"url":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/500.ttf.gz","bytes":13272430,"sha256":"f4b8a34d1f838fe411540cb7c97b1c384ac9738a876c4104500bc42508b2312a"}],"preview":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/preview-d3505af4.ttf","bytes":26176912},{"id":"jetbrains-mono","name":"JetBrains Mono","mono":true,"family":"SF JetBrains Mono","css":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/var.ttf.gz","bytes":90579,"sha256":"48715a42ec242c21e9f02692891e147d022299a52e48d5e413e1a942193ffeda"}],"preview":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/preview-ee73078f.ttf","bytes":90579},{"id":"fira-code","name":"Fira Code","mono":true,"family":"SF Fira Code","css":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/var.ttf.gz","bytes":137151,"sha256":"9335b082b3c7850d98a64b584f3417f65355f3471278bb5eeb8c6c0e8657aeeb"}],"preview":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/preview-555be27a.ttf","bytes":137151},{"id":"maple-mono","name":"Maple Mono","mono":true,"family":"SF Maple Mono CN","css":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/font.css","files":[{"weight":400,"url":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/400.ttf.gz","bytes":8352545,"sha256":"0fcc5139bfd5ab14ff989bb7dfd5236d0cafc10e60b9828569e6883613ab4085"},{"weight":600,"url":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/600.ttf.gz","bytes":8438132,"sha256":"96ed7ae26ee7c50b02b2d2b2bc0f1a0cbabe45ae5d6e6abf6678e2177c415677"}],"preview":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/preview-cffdf246.ttf","bytes":16790677}]}}},"w":1792594472983.454}
  #|{"out":{"id":4,"subscribe":{"topic":"workspaces"},"keyed":true},"w":1792594472983.508}
  #|{"out":{"id":5,"subscribe":{"topic":"status"},"keyed":true},"w":1792594472983.522}
  #|{"in":{"id":4,"value":[{"account":{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""},"workspaces":[{"id":"01M5FF9PQ31D5P8CDWDTHKC2JT","name":"Dev","role":"owner","created_at":1792594467,"stations":1,"members":1,"relays":[],"time":{"created_at":{"past":true,"at":1792594467000,"ago":"刚刚","full":"10/21 22:54:27","until":"1 分钟内"}}}],"invitations":[],"relay_url":"http://127.0.0.1:18740","loaded":true,"beta":true}]},"w":1792594473000.937}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792594473001.002}
  #|{"out":{"id":6,"subscribe":{"topic":"lock","workspace":"01M5FF9PQ31D5P8CDWDTHKC2JT"},"keyed":true},"w":1792594473001.042}
  #|{"out":{"id":7,"subscribe":{"topic":"chats","scope":"01M5FF9PQ31D5P8CDWDTHKC2JT","mine":false},"keyed":true},"w":1792594473001.058}
  #|{"out":{"id":8,"subscribe":{"topic":"changelog"},"keyed":true},"w":1792594473001.068}
  #|{"out":{"id":9,"subscribe":{"topic":"workspaceMarks","workspace":"01M5FF9PQ31D5P8CDWDTHKC2JT"},"keyed":true},"w":1792594473001.192}
  #|{"out":{"id":10,"subscribe":{"topic":"status","workspace":"01M5FF9PQ31D5P8CDWDTHKC2JT"},"keyed":true},"w":1792594473001.227}
  #|{"out":{"id":11,"subscribe":{"topic":"lockPrompts"},"keyed":true},"w":1792594473006.197}
  #|{"out":{"id":12,"call":"client.focus","params":{"visible":true,"focused":true,"workspace":"01M5FF9PQ31D5P8CDWDTHKC2JT"}},"w":1792594473008.659}
  #|{"out":{"id":13,"subscribe":{"topic":"notify"},"keyed":true},"w":1792594473008.669}
  #|{"out":{"id":14,"subscribe":{"topic":"notify","workspace":"01M5FF9PQ31D5P8CDWDTHKC2JT"},"keyed":true},"w":1792594473008.679}
  #|{"in":{"id":6,"value":{"available":true,"locked":false,"notice":true,"role":"owner","manages":true,"owner":true,"canSign":true,"signs":false,"me":{"device":"469da3039b6856545011dd1922aab9499ae2927d98e749a78f6601b2bec2836b","code":"7QX-ESL","kind":"app","confirmed":false,"waiting":false,"asked":false},"signers":0,"members":[],"stations":[{"id":"b6366b80471b3692e619292b92a10a8953856f348004d02d2bfb6ab8de072b7c","name":"studio","version":"0.1.0","online":true,"protected":false}],"protected":0,"requests":[],"renew":[],"attention":0}},"w":1792594473016.85}
  #|{"in":{"id":7,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"stations":[{"station":"01M5FF9PQ31D5P8CDWDTHKC2JT/b6366b80471b3692e619292b92a10a8953856f348004d02d2bfb6ab8de072b7c","id":"b6366b80471b3692e619292b92a10a8953856f348004d02d2bfb6ab8de072b7c","name":"studio","state":"online"}],"loading":false,"days":[{"daysAgo":0,"at":1792594471532,"label":"今天","items":[{"id":"ember:c-cbf43d2b7e","session":"ember:c-cbf43d2b7e","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","agents":[{"key":"ember:c-cbf43d2b7e","runtime":"claude","process":"warm","pending":0,"lastTurn":{"id":"6ae5cb03-c6d8-42b5-8493-c4a99b500aec","kind":"input","outcome":"completed","declared":"final","ending":"all_done","need":"answered the question that was asked","startedAt":1792594471454,"endedAt":1792594471534},"agentText":"默认模型","statusText":"已完成：answered the question that was asked"}],"last":{"seq":2,"authorKind":"agent","author":"ember:c-cbf43d2b7e","text":"你好，我是测试用的 agent","createdAt":1792594471532,"by":{"kind":"agent","name":"agent","mine":false,"runtime":"claude","label":"agent"},"preview":"你好，我是测试用的 agent","time":{"createdAt":{"at":1792594471532,"ago":"刚刚","full":"10/21 22:54:31","until":"1 分钟内","past":true}}},"unread":true,"mine":true,"lastActiveAt":1792594471532,"station":"01M5FF9PQ31D5P8CDWDTHKC2JT/b6366b80471b3692e619292b92a10a8953856f348004d02d2bfb6ab8de072b7c","stationName":"studio","time":{"lastActiveAt":{"at":1792594471532,"ago":"刚刚","full":"10/21 22:54:31","until":"1 分钟内","past":true}},"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"peopleText":"你 发起","clientKey":"new:chat-8508b32bc5552070be","pinned":false,"tone":"done"}]}],"trouble":null,"members":1,"leading":"agents","glyph":{"online":1,"dim":0,"connecting":0,"failing":0,"working":0,"summary":"studio","label":"1 台 station，1 台在线"},"note":{"reading":false,"text":null,"failing":[],"empty":false}}},"w":1792594473016.894}
  #|{"in":{"id":8,"value":{"app":"desktop","tabs":[{"part":"desktop","label":"桌面","days":[]},{"part":"web","label":"网页","days":[]},{"part":"android","label":"安卓","days":[]},{"part":"station","label":"Station","days":[]},{"part":"cloud","label":"云端","days":[]}],"loading":false}},"w":1792594473016.92}
  #|{"in":{"id":9,"value":{"workspaces":{"01M5FF9PQ31D5P8CDWDTHKC2JT":{"alert":0,"unread":1,"tone":"done","label":"1 个有新消息","badge":0,"items":[],"mineTone":"done"}},"badge":0,"badgeCounts":"attention","badgeKinds":{"on":true,"wait":true,"failed":true,"done":false,"message":false}}},"w":1792594473016.929}
  #|{"in":{"id":10,"value":{"items":[]}},"w":1792594473016.936}
  #|{"in":{"id":11,"value":{"pairing":[]}},"w":1792594473016.939}
  #|{"in":{"id":12,"ok":null},"w":1792594473016.942}
  #|{"in":{"id":13,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792594473016.954}
  #|{"in":{"id":14,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792594473016.965}
  #|{"out":{"id":15,"subscribe":{"topic":"longJobs","scope":"01M5FF9PQ31D5P8CDWDTHKC2JT"},"keyed":true},"w":1792594473017.017}
  #|{"out":{"id":16,"call":"notify.permission","params":{"state":"unknown"}},"w":1792594473019.69}
  #|{"in":{"id":15,"value":{"groups":[]}},"w":1792594473033.409}
  #|{"in":{"id":16,"ok":null},"w":1792594473033.418}
  #|{"step":"answered notify.permission","w":1792594473033.657}
  #|{"step":"tap icon:settings","w":1792594473050.285}
  #|{"step":"tap icon:settings","acted":true,"w":1792594473050.304}
  #|{"out":{"id":17,"subscribe":{"topic":"workspace","workspace":"01M5FF9PQ31D5P8CDWDTHKC2JT"},"keyed":true},"w":1792594473066.998}
  #|{"out":{"id":18,"subscribe":{"topic":"stations","scope":"01M5FF9PQ31D5P8CDWDTHKC2JT"},"keyed":true},"w":1792594473067.009}
  #|{"out":{"id":19,"subscribe":{"topic":"connects","scope":"01M5FF9PQ31D5P8CDWDTHKC2JT","mine":false},"keyed":true},"w":1792594473067.015}
  #|{"out":{"id":20,"subscribe":{"topic":"vaults","workspace":"01M5FF9PQ31D5P8CDWDTHKC2JT"},"keyed":true},"w":1792594473067.021}
  #|{"out":{"id":21,"subscribe":{"topic":"doing"},"keyed":true},"w":1792594473069.84}
  #|{"step":"wait 299","w":1792594473070.875}
  #|{"in":{"id":17,"value":{"id":"01M5FF9PQ31D5P8CDWDTHKC2JT","name":"Dev","role":"owner","created_at":1792594467,"members":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":"https://example.test/p.png","role":"owner","added_at":1792594467}],"stations":[{"id":"b6366b80471b3692e619292b92a10a8953856f348004d02d2bfb6ab8de072b7c","name":"studio","emoji":null,"icon":null,"enrolled_at":1792594468,"enrolled_by":"alice","last_seen":1792594471,"version":"0.1.0","time":{"last_seen":{"past":true,"at":1792594471000,"ago":"刚刚","full":"10/21 22:54:31","until":"1 分钟内"}}}],"invitations":[],"added":[],"relays":[],"lock":null,"lock_requests":0,"time":{"created_at":{"past":true,"at":1792594467000,"ago":"刚刚","full":"10/21 22:54:27","until":"1 分钟内"}}}},"w":1792594473083.427}
  #|{"in":{"id":18,"value":[{"station":"01M5FF9PQ31D5P8CDWDTHKC2JT/b6366b80471b3692e619292b92a10a8953856f348004d02d2bfb6ab8de072b7c","id":"b6366b80471b3692e619292b92a10a8953856f348004d02d2bfb6ab8de072b7c","name":"studio","summary":"正在连接","face":"idle","line":"在线","online":true,"reconnecting":false,"lastSeen":1792594471,"version":"0.1.0","link":{"state":"online"},"runtimes":[{"runtime":"claude","models":["claude-sonnet-5-5"]}],"models":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792594471432,"time":{"checkedAt":{"at":1792594471432,"ago":"刚刚","full":"10/21 22:54:31","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"overview":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null,"summaryText":"最近 7 天检查了 0 个 chat","changeText":null}},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","email":"alice@example.test","name":"Name of alice","sub":"alice","role":"owner","workspace":"01M5FF9PQ31D5P8CDWDTHKC2JT","device":"469da3039b6856545011dd1922aab9499ae2927d98e749a78f6601b2bec2836b"},"connects":[],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792594471312,"time":{"checkedAt":{"at":1792594471312,"ago":"刚刚","full":"10/21 22:54:31","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792594471432,"time":{"checkedAt":{"at":1792594471432,"ago":"刚刚","full":"10/21 22:54:31","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"modelsReading":false,"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]}],"processes":[],"counts":{"sessions":1,"running":0,"warm":1},"mesh":{"state":"running","origin":"http://127.0.0.1:18787","station":"b6366b80471b3692e619292b92a10a8953856f348004d02d2bfb6ab8de072b7c","workspace":"Dev","workspaceId":"01M5FF9PQ31D5P8CDWDTHKC2JT","name":"studio"},"slackUsers":[],"slackTeams":[],"slackApps":[],"feishuRegistrations":[],"disk":{"freeBytes":29824593920,"totalBytes":245107195904},"logins":[],"machineLogins":[],"sharing":true,"consoleSignIn":true,"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"google","name":"Google Gemini","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xai","name":"xAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"mistral","name":"Mistral","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"deepseek","name":"DeepSeek","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen","name":"Qwen","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai","name":"Kimi","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai","name":"Z.ai","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax","name":"MiniMax","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ant-ling","name":"Ant Ling","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"jev","name":"Jev","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen-cn","name":"Qwen (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"openrouter","name":"OpenRouter","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"opencode","name":"OpenCode Zen","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"groq","name":"Groq","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"together","name":"Together AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"fireworks","name":"Fireworks","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cerebras","name":"Cerebras","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"huggingface","name":"Hugging Face","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"nvidia","name":"NVIDIA","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"baseten","name":"Baseten","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ollama","name":"Ollama","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"custom","name":"Custom","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""}],"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792594468998},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.306","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792594468998},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-lockp/apps/e2e-local/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792594468998},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-lockp/apps/e2e-local/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792594468998},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","latest":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-lockp/apps/e2e-local/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792594468998},{"id":"cursor","name":"Cursor","installed":false,"latest":"1.0.40","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792594468998},{"id":"devin","name":"Devin","installed":true,"version":"3000.11.92","latest":"3000.11.92","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-lockp/apps/e2e-local/ember/station/test/fake/devin，不是用 Devin 的安装脚本装的，需在该机器上手动更新","state":"idle","checkedAt":1792594468998}],"processesText":"没有运行中的 agent 进程","agentEnv":[],"drive":{"roots":[],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false}},"betaOffered":false,"way":{"path":"直连","via":"direct"},"time":{"lastSeen":{"at":1792594471000,"ago":"刚刚","full":"10/21 22:54:31","until":"1 分钟内","past":true}},"joined":false}]},"w":1792594473083.546}
  #|{"in":{"id":19,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"items":[],"wait":{"reading":false,"text":null,"failing":[],"empty":true}}},"w":1792594473083.632}
  #|{"in":{"id":20,"value":{"available":true,"locked":false,"canSign":false,"setUp":false,"vaults":[{"id":"plain","name":"个人","owner":"alice","ownerName":"Name of alice","mine":true,"members":[{"sub":"alice","name":"Name of alice"}],"station":"b6366b80471b3692e619292b92a10a8953856f348004d02d2bfb6ab8de072b7c","stationName":"studio","items":0,"devices":0,"open":true,"keyed":true,"missing":0,"recoverable":false}],"requests":[],"refused":[{"station":"b6366b80471b3692e619292b92a10a8953856f348004d02d2bfb6ab8de072b7c","name":"studio","code":"vault_needs_lock"}],"plain":true}},"w":1792594473083.641}
  #|{"in":{"id":21,"value":{"doing":[]}},"w":1792594473083.647}
  #|{"in":{"id":18,"delta":[{"path":[0,"host"],"set":{"hostname":"3720-Mac-mini-1","os":"macOS 27.0.1","arch":"arm64","cpus":10,"cpuModel":"Apple M4","load":0.59,"cpuBusy":0.14,"uptimeSec":73835,"memory":{"totalBytes":17179869184,"usedBytes":9471950848,"swapUsedBytes":250347520},"disk":{"path":"/tmp/mbe2e-C/data","totalBytes":245107195904,"freeBytes":29824471040},"emberRssBytes":159349832,"checkedAt":1792594473109,"summary":"10 核 · 16 GB","line":"macOS 27.0.1 · 10 核 · 16 GB · 已运行 0 天","facts":["3720-Mac-mini-1","macOS 27.0.1","arm64 · 10 核","已运行 20 小时"],"meters":[{"label":"CPU","short":"CPU","percent":14,"left":86,"level":"ok","value":"14%","remaining":"空闲 86%","big":"86","unit":"%","title":"CPU 空闲","total":"负载 5.9","note":"负载 5.9 · Apple M4"},{"label":"内存","short":"内存","percent":55,"left":45,"level":"ok","value":"8.8 GB / 16.0 GB","remaining":"剩 7.2 G","big":"7.2","unit":"GB","title":"内存剩","total":"共 16 GB","note":"swap 0.2 GB"},{"label":"磁盘","short":"磁盘","percent":88,"left":12,"level":"amber","value":"剩余 27.8 GB / 228 GB","remaining":"剩 27.8 G","big":"27.8","unit":"GB","title":"磁盘剩","total":"共 228 GB"}],"identity":"Apple M4 · 16 GB · macOS 27.0.1","details":[{"label":"主机名","value":"3720-Mac-mini-1"},{"label":"芯片","value":"Apple M4 · 10 核 · arm64"},{"label":"已运行","value":"20 小时"},{"label":"still.fail","value":"进程占用 152 MB"}],"usage":"内存 8.8 GB / 16.0 GB · 磁盘 剩余 27.8 GB / 228 GB","emberText":"still.fail 152 MB"}},{"path":[0,"line"],"set":"Apple M4"},{"path":[0,"summary"],"set":"空闲 · Apple M4 · 16 GB · macOS 27.0.1"}]},"w":1792594473133.424}
  #|{"step":"now tap =Station","w":1792594473384.428}
  #|{"step":"now tap =Station","acted":true,"w":1792594473384.483}
  #|{"step":"wait 300","w":1792594473411.395}
  #|{"step":"now tap =studio","w":1792594473717.421}
  #|{"step":"now tap =studio","acted":true,"w":1792594473717.466}
  #|{"out":{"id":22,"subscribe":{"topic":"screens","station":"01M5FF9PQ31D5P8CDWDTHKC2JT/b6366b80471b3692e619292b92a10a8953856f348004d02d2bfb6ab8de072b7c"},"keyed":true},"w":1792594473735.477}
  #|{"out":{"id":23,"subscribe":{"topic":"machineLogins","station":"01M5FF9PQ31D5P8CDWDTHKC2JT/b6366b80471b3692e619292b92a10a8953856f348004d02d2bfb6ab8de072b7c"},"keyed":true},"w":1792594473735.512}
  #|{"out":{"id":24,"subscribe":{"topic":"memberships","station":"01M5FF9PQ31D5P8CDWDTHKC2JT/b6366b80471b3692e619292b92a10a8953856f348004d02d2bfb6ab8de072b7c"},"keyed":true},"w":1792594473735.531}
  #|{"out":{"id":25,"subscribe":{"topic":"adbShare"},"keyed":true},"w":1792594473741.211}
  #|{"step":"wait 300","w":1792594473742.526}
  #|{"in":{"id":22,"value":{"screens":[{"id":"desktop","kind":"desktop","title":"3720-Mac-mini-1","width":0,"height":0,"viewers":[],"controlledBy":[],"access":{"capture":false,"control":false,"message":"此 station 版本不含屏幕助手（stillfail-screen），请更新 station"},"clipboard":[],"drop":{"folder":"/tmp/mbe2e-C/home","reveal":true},"peek":false,"line":"此 station 版本不含屏幕助手（stillfail-screen），请更新 station","link":"/w/01M5FF9PQ31D5P8CDWDTHKC2JT/s/b6366b80471b3692e619292b92a10a8953856f348004d02d2bfb6ab8de072b7c/screen/desktop"}],"outdated":false,"control":true,"known":true}},"w":1792594473750.102}
  #|{"in":{"id":23,"value":{"supported":true,"loaded":true,"canLogin":true,"canRelay":true,"logins":[]}},"w":1792594473750.149}
  #|{"in":{"id":24,"value":{"manages":true,"loading":true,"canJoin":false,"workspaces":[]}},"w":1792594473750.165}
  #|{"in":{"id":24,"value":{"manages":true,"loading":false,"canJoin":true,"workspaces":[{"workspace":"01M5FF9PQ31D5P8CDWDTHKC2JT","name":"Dev","stationName":"studio","home":true,"here":true,"line":"主 workspace"}]}},"w":1792594473750.181}
  #|{"in":{"id":25,"value":{"sharing":false,"phase":"off","tunnels":0}},"w":1792594473750.197}
  #|{"step":"now wheelat 450 在此 station 上","w":1792594474067.883}
  #|{"step":"now wheelat 450 在此 station 上","acted":true,"w":1792594474067.966}
  #|{"step":"wait 900","w":1792594474088.928}
  #|{"step":"now tap 编辑变量","w":1792594475000.98}
  #|{"step":"now tap 编辑变量","acted":true,"w":1792594475001.063}
  #|{"out":{"id":26,"call":"agentEnv.form.open","params":{"station":"01M5FF9PQ31D5P8CDWDTHKC2JT/b6366b80471b3692e619292b92a10a8953856f348004d02d2bfb6ab8de072b7c","form":"mbui-env-1","input":{}}},"w":1792594475017.301}
  #|{"step":"answered agentEnv.form.open","w":1792594475019.535}
  #|{"in":{"id":26,"ok":{"text":"","dirty":false,"pending":false,"lines":[{"parts":[],"problem":null,"error":false}],"errors":0}},"w":1792594475033.454}
  #|{"out":{"id":27,"subscribe":{"topic":"agentEnvForm","station":"01M5FF9PQ31D5P8CDWDTHKC2JT/b6366b80471b3692e619292b92a10a8953856f348004d02d2bfb6ab8de072b7c","form":"mbui-env-1"},"keyed":true},"w":1792594475033.928}
  #|{"in":{"id":27,"value":{"text":"","dirty":false,"pending":false,"lines":[{"parts":[],"problem":null,"error":false}],"errors":0}},"w":1792594475055.675}
  #|{"step":"wait 1459","w":1792594475066.491}
  #|{"step":"now tap HTTPS_PROXY=","w":1792594476551.575}
  #|{"step":"now tap HTTPS_PROXY=","acted":true,"w":1792594476551.653}
  #|{"step":"type E2E_PROXY_080726=http://127.0.0.1:9","w":1792594476577.698}
  #|{"step":"type E2E_PROXY_080726=http://127.0.0.1:9","acted":true,"w":1792594476577.759}
  #|{"out":{"id":28,"call":"agentEnv.form.edit","params":{"station":"01M5FF9PQ31D5P8CDWDTHKC2JT/b6366b80471b3692e619292b92a10a8953856f348004d02d2bfb6ab8de072b7c","form":"mbui-env-1","input":{"text":"E2E_PROXY_080726=http://127.0.0.1:9"}}},"w":1792594476584.153}
  #|{"step":"answered agentEnv.form.edit","w":1792594476595.122}
  #|{"in":{"id":28,"ok":{"text":"E2E_PROXY_080726=http://127.0.0.1:9","dirty":true,"pending":false,"lines":[{"parts":[{"kind":"name","text":"E2E_PROXY_080726"},{"kind":"other","text":"="},{"kind":"value","text":"http://127.0.0.1:9"}],"problem":null,"error":false}],"errors":0}},"w":1792594476600.115}
  #|{"in":{"id":27,"delta":[{"path":["dirty"],"set":true},{"path":["lines",0,"parts"],"append":[{"kind":"name","text":"E2E_PROXY_080726"},{"kind":"other","text":"="},{"kind":"value","text":"http://127.0.0.1:9"}]},{"path":["text"],"set":"E2E_PROXY_080726=http://127.0.0.1:9"}]},"w":1792594476800.143}
  #|{"step":"tap =保存","w":1792594476818.546}
  #|{"step":"tap =保存","acted":true,"w":1792594476818.611}
  #|{"out":{"id":29,"call":"agentEnv.form.save","params":{"station":"01M5FF9PQ31D5P8CDWDTHKC2JT/b6366b80471b3692e619292b92a10a8953856f348004d02d2bfb6ab8de072b7c","form":"mbui-env-1","input":{}}},"w":1792594476834.413}
  #|{"step":"answered agentEnv.form.save","w":1792594476835.695}
  #|{"in":{"id":21,"value":{"doing":[{"call":"agentEnv.form.save","params":{"station":"01M5FF9PQ31D5P8CDWDTHKC2JT/b6366b80471b3692e619292b92a10a8953856f348004d02d2bfb6ab8de072b7c","form":"mbui-env-1"},"since":1792594476834,"stage":"running"}]}},"w":1792594476900.081}
  #|{"in":{"id":27,"delta":[{"path":["pending"],"set":true}]},"w":1792594476900.107}
  #|{"in":{"id":7,"delta":[{"path":["days"],"key":["daysAgo"],"patch":0,"ops":[{"path":["items"],"key":["station","id"],"patch":["01M5FF9PQ31D5P8CDWDTHKC2JT/b6366b80471b3692e619292b92a10a8953856f348004d02d2bfb6ab8de072b7c","ember:c-cbf43d2b7e"],"ops":[{"path":["agents",0,"process"],"set":"cold"}]}]}]},"w":1792594476900.12}
  #|{"in":{"id":18,"delta":[{"path":[0,"overview","agentEnv"],"append":[{"key":"E2E_PROXY_080726","secret":false,"value":"http://127.0.0.1:9"}]},{"path":[0,"overview","counts","warm"],"set":0},{"path":[0,"overview","disk","freeBytes"],"set":29824376832}]},"w":1792594476916.753}
  #|{"in":{"id":29,"ok":{"env":[{"key":"E2E_PROXY_080726","value":"http://127.0.0.1:9","secret":false}]}},"w":1792594476916.781}
  #|{"step":"until 已保存","w":1792594476942.631}
  #|{"step":"wait 2600","w":1792594476942.645}
  #|{"in":{"id":27,"delta":[{"path":["dirty"],"set":false},{"path":["pending"],"set":false}]},"w":1792594477016.777}
  #|{"in":{"id":21,"value":{"doing":[]}},"w":1792594477016.826}
  #|{"in":{"id":18,"delta":[{"path":[0,"overview","disk","freeBytes"],"set":29824303104}]},"w":1792594477033.423}
  #|{"step":"wait 100","w":1792594479551.09}
  #|{"step":"now until E2E_PROXY_080726","w":1792594479668.011}
  #|{"step":"tap 编辑变量","w":1792594479668.07}
  #|{"step":"tap 编辑变量","acted":true,"w":1792594479668.137}
  #|{"out":{"id":30,"call":"agentEnv.form.open","params":{"station":"01M5FF9PQ31D5P8CDWDTHKC2JT/b6366b80471b3692e619292b92a10a8953856f348004d02d2bfb6ab8de072b7c","form":"mbui-env-2","input":{}}},"w":1792594479683.985}
  #|{"step":"answered agentEnv.form.open","w":1792594479684.702}
  #|{"in":{"id":30,"ok":{"text":"E2E_PROXY_080726=http://127.0.0.1:9","dirty":false,"pending":false,"lines":[{"parts":[{"kind":"name","text":"E2E_PROXY_080726"},{"kind":"other","text":"="},{"kind":"value","text":"http://127.0.0.1:9"}],"problem":null,"error":false}],"errors":0}},"w":1792594479700.13}
  #|{"out":{"id":31,"subscribe":{"topic":"agentEnvForm","station":"01M5FF9PQ31D5P8CDWDTHKC2JT/b6366b80471b3692e619292b92a10a8953856f348004d02d2bfb6ab8de072b7c","form":"mbui-env-2"},"keyed":true},"w":1792594479700.567}
  #|{"in":{"id":31,"value":{"text":"E2E_PROXY_080726=http://127.0.0.1:9","dirty":false,"pending":false,"lines":[{"parts":[{"kind":"name","text":"E2E_PROXY_080726"},{"kind":"other","text":"="},{"kind":"value","text":"http://127.0.0.1:9"}],"problem":null,"error":false}],"errors":0}},"w":1792594479716.777}
  #|{"step":"wait 1459","w":1792594479718.058}
  #|{"step":"now until Agent 环境变量","w":1792594481201.451}
  #|{"step":"tap field:E2E_PROXY_080726=http","w":1792594481201.527}
  #|{"step":"tap field:E2E_PROXY_080726=http","acted":true,"w":1792594481201.563}
  #|{"step":"clear","w":1792594481218.071}
  #|{"step":"clear","acted":true,"w":1792594481218.192}
  #|{"out":{"id":32,"call":"agentEnv.form.edit","params":{"station":"01M5FF9PQ31D5P8CDWDTHKC2JT/b6366b80471b3692e619292b92a10a8953856f348004d02d2bfb6ab8de072b7c","form":"mbui-env-2","input":{"text":""}}},"w":1792594481234.169}
  #|{"step":"answered agentEnv.form.edit","w":1792594481235.125}
  #|{"in":{"id":32,"ok":{"text":"","dirty":true,"pending":false,"lines":[{"parts":[],"problem":null,"error":false}],"errors":0}},"w":1792594481250.121}
  #|{"in":{"id":31,"delta":[{"path":["dirty"],"set":true},{"path":["lines",0,"parts"],"set":[]},{"path":["text"],"set":""}]},"w":1792594481316.783}
  #|{"step":"tap =保存","w":1792594481334.611}
  #|{"step":"tap =保存","acted":true,"w":1792594481334.664}
  #|{"out":{"id":33,"call":"agentEnv.form.save","params":{"station":"01M5FF9PQ31D5P8CDWDTHKC2JT/b6366b80471b3692e619292b92a10a8953856f348004d02d2bfb6ab8de072b7c","form":"mbui-env-2","input":{}}},"w":1792594481350.849}
  #|{"step":"answered agentEnv.form.save","w":1792594481351.81}
  #|{"in":{"id":33,"ok":{"env":[]}},"w":1792594481416.768}
  #|{"in":{"id":31,"delta":[{"path":["dirty"],"set":false}]},"w":1792594481416.822}
  #|{"in":{"id":18,"delta":[{"path":[0,"overview","agentEnv"],"set":[]},{"path":[0,"overview","disk","freeBytes"],"set":29824266240}]},"w":1792594481416.838}
  #|{"in":{"id":27,"delta":[{"path":["lines",0,"parts"],"set":[]},{"path":["text"],"set":""}]},"w":1792594481416.861}
  #|{"step":"until 已保存","w":1792594481433.868}
  #|{"step":"wait 2600","w":1792594481433.886}
  #|{"step":"wait 100","w":1792594484184.916}
  #|{"step":"now until 暂无变量","w":1792594484301.361}
  #|{"step":"wheelat 1500 编辑变量","w":1792594484301.43}
  #|{"step":"wheelat 1500 编辑变量","acted":true,"w":1792594484301.484}
  #|{"step":"wait 900","w":1792594484324.469}
  #|{"step":"now tap =检查更新","w":1792594485234.282}
  #|{"step":"now tap =检查更新","acted":true,"w":1792594485234.356}
  #|{"out":{"id":34,"call":"software.check","params":{"station":"01M5FF9PQ31D5P8CDWDTHKC2JT/b6366b80471b3692e619292b92a10a8953856f348004d02d2bfb6ab8de072b7c"}},"w":1792594485250.508}
  #|{"step":"","w":1792594485251.113}
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
  #|{"textrec":{"ib":["fdb526ba00f881f4",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["1d51432b25a425eb",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"ib":["31d8ec32aedeae00",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["a7ccae3554fe46cf",3232,64],"r":[28,28,28,28]}}
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
  #|{"textrec":{"s":[16,600,0,"Station"],"r":[0,1,10.266256332397461,192,1,1,5.999713897705078,36,2,1,8.899068832397461,44,3,1,5.999713897705078,36,4,1,4.046333312988281,193,5,1,9.432537078857422,34,6,1,9.466253280639648,47]}}
  #|{"textrec":{"s":[17,400,0,"设置"],"r":[0,1,16.851167315175097,194,1,1,16.851167315175097,195]}}
  #|{"textrec":{"s":[16,700,0,"studio"],"r":[0,1,8.73046875,196,1,1,6.26953125,197,2,1,9.72265625,198,3,1,10.109375,199,4,1,4.28125,74,5,1,9.6015625,71]}}
  #|{"textrec":{"s":[13,400,0,"空闲 · Apple M4 · 16 GB · macOS 27.0.1"],"r":[0,1,12.898832684824903,200,1,1,12.898832684824903,201,2,1,3.580078125,-1,3,1,6.228545204222122,202,4,1,3.580078125,-1,5,1,8.68359375,203,6,1,7.8583984375,11,7,1,7.8583984375,11,8,1,3.211914062500007,76,9,1,7.3505859375,14,10,1,3.580078125,-1,11,1,11.2861328125,204,12,1,8.2900390625,205,13,1,3.580078125,-1,14,1,6.228545204222115,202,15,1,3.580078125,-1,16,1,5.9541015625,206,17,1,8.201171875,207,18,1,3.580078125,-1,19,1,9.62939453125,208,20,1,8.4677734375,209,21,1,3.580078125,-1,22,1,6.228545204222115,202,23,1,3.580078125,-1,24,1,11.2353515625,80,25,1,7.0966796875,12,26,1,7.1982421875,13,27,1,9.953125,210,28,1,8.20751953125,211,29,1,3.580078125,-1,30,1,7.76953125,212,31,1,6.626953125,213,32,1,2.8310546875,81,33,1,7.6044921875,214,34,1,3.3388671875,81,35,1,5.763671875,206]}}
  #|{"textrec":{"s":[13,400,0,"↑"],"r":[0,1,10.080078125,215]}}
  #|{"textrec":{"s":[13,500,0," "],"r":[0,1,3.4683494567871094,-1]}}
  #|{"textrec":{"m":[13,500,0],"r":[12.568359375,2.7421875,18,12.568359375,2.7421875,0]}}
  #|{"textrec":{"s":[13,400,0,"↓"],"r":[0,1,10.080078125,216]}}
  #|{"textrec":{"s":[13,400,0,"直连"],"r":[0,1,12.898832684824903,217,1,1,12.898832684824903,218]}}
  #|{"textrec":{"s":[13,400,0,"当前延迟 "],"r":[0,1,12.898832684824903,219,1,1,12.898832684824903,220,2,1,12.898832684824903,221,3,1,12.898832684824903,222,4,1,3.580078125,-1]}}
  #|{"textrec":{"s":[13,500,0,"0 ms"],"r":[0,1,8.373004913330078,223,1,1,3.4683494567871094,-1,2,1,11.530966997146606,224,3,1,6.933351516723633,225]}}
  #|{"textrec":{"s":[11,600,0,"磁盘"],"r":[0,1,10.93579766536965,226,1,1,10.93579766536965,227]}}
  #|{"textrec":{"m":[11,600,0],"r":[10.634765625,2.3203125,16,10.634765625,2.3203125,0]}}
  #|{"textrec":{"s":[11,600,0,"剩 27.8 G"],"r":[0,1,10.93579766536965,228,1,1,2.9949302673339844,-1,2,1,6.9786479473114,229,3,1,5.9642298221588135,230,4,1,2.8625084161758423,231,5,1,7.26071560382843,232,6,1,2.9949302673339844,-1,7,1,8.372097969055176,233]}}
  #|{"textrec":{"g":194,"r":[1967,0,19,18,-1,-15,0]}}
  #|{"textrec":{"g":195,"r":[1987,0,18,17,-1,-14,0]}}
  #|{"textrec":{"ib":["b7b1dc2c98725280",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"g":226,"r":[2006,0,13,12,-1,-10,0]}}
  #|{"textrec":{"g":227,"r":[2020,0,13,12,-1,-10,0]}}
  #|{"textrec":{"g":228,"r":[2034,0,13,13,-1,-10,0]}}
  #|{"textrec":{"g":229,"r":[0,32,9,10,-1,-9,0]}}
  #|{"textrec":{"g":230,"r":[10,32,8,10,-1,-9,0]}}
  #|{"textrec":{"g":231,"r":[19,32,5,5,-1,-3,0]}}
  #|{"textrec":{"g":232,"r":[25,32,9,11,-1,-9,0]}}
  #|{"textrec":{"g":233,"r":[35,32,10,11,-1,-9,0]}}
  #|{"textrec":{"g":196,"r":[46,32,11,12,-1,-10,0]}}
  #|{"textrec":{"g":197,"r":[58,32,8,14,-1,-12,0]}}
  #|{"textrec":{"g":198,"r":[67,32,10,12,0,-10,0]}}
  #|{"textrec":{"g":199,"r":[78,32,12,15,-1,-13,0]}}
  #|{"textrec":{"g":200,"r":[91,32,14,14,-1,-12,0]}}
  #|{"textrec":{"g":201,"r":[106,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":202,"r":[120,32,4,5,1,-7,0]}}
  #|{"textrec":{"g":203,"r":[125,32,11,12,-1,-11,0]}}
  #|{"textrec":{"g":204,"r":[137,32,12,12,0,-11,0]}}
  #|{"textrec":{"g":205,"r":[150,32,10,12,-1,-11,0]}}
  #|{"textrec":{"g":206,"r":[161,32,7,12,-1,-11,0]}}
  #|{"textrec":{"g":207,"r":[169,32,10,13,-1,-11,0]}}
  #|{"textrec":{"g":208,"r":[180,32,11,13,-1,-11,0]}}
  #|{"textrec":{"g":209,"r":[192,32,9,12,0,-11,0]}}
  #|{"textrec":{"g":210,"r":[202,32,12,13,-1,-11,0]}}
  #|{"textrec":{"g":211,"r":[215,32,10,13,-1,-11,0]}}
  #|{"textrec":{"g":212,"r":[226,32,9,12,-1,-11,0]}}
  #|{"textrec":{"g":213,"r":[236,32,9,12,-1,-11,0]}}
  #|{"textrec":{"g":214,"r":[246,32,10,13,-1,-11,0]}}
  #|{"textrec":{"g":192,"r":[257,32,12,15,-1,-13,0]}}
  #|{"textrec":{"g":44,"r":[270,32,11,12,-1,-10,0]}}
  #|{"textrec":{"g":193,"r":[282,32,5,15,0,-14,0]}}
  #|{"textrec":{"g":47,"r":[288,32,10,11,0,-10,0]}}
  #|{"textrec":{"ib":["2bb63fc1d380f765",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"s":[11,400,0,"Apple M4 · 16 GB · macOS 27.0.1"],"r":[0,1,7.4765625,234,1,1,6.7783203125,235,2,1,6.7783203125,235,3,1,2.8466796875,236,4,1,6.3486328125,237,5,1,3.158203125,-1,6,1,9.6787109375,238,7,1,7.1435546875,239,8,1,3.158203125,-1,9,1,5.2804038549793475,240,10,1,3.158203125,-1,11,1,5.166992187499993,241,12,1,7.068359375,242,13,1,3.158203125,-1,14,1,8.27685546875,243,15,1,7.2939453125,244,16,1,3.158203125,-1,17,1,5.28040385497934,240,18,1,3.158203125,-1,19,1,9.6357421875,245,20,1,6.1337890625,246,21,1,6.2197265625,247,22,1,8.55078125,248,23,1,7.07373046875,249,24,1,3.158203125,-1,25,1,6.703125,250,26,1,5.736328125,251,27,1,2.5244140625,252,28,1,6.5634765625,253,29,1,2.9541015625,252,30,1,5.005859375,241]}}
  #|{"textrec":{"m":[11,400,0],"r":[10.634765625,2.3203125,16,10.634765625,2.3203125,0]}}
  #|{"textrec":{"s":[16,600,0,"studio"],"r":[0,1,8.471200942993164,35,1,1,5.973020553588867,36,2,1,9.466253280639648,254,3,1,9.891647338867188,255,4,1,4.046333312988281,193,5,1,9.432537078857422,34]}}
  #|{"textrec":{"s":[17,400,0,"Station"],"r":[0,1,10.40087890625,256,1,1,5.744140625,257,2,1,8.9482421875,258,3,1,5.744140625,257,4,1,3.7685546875,259,5,1,9.6123046875,260,6,1,9.48779296875,261]}}
  #|{"textrec":{"s":[28,600,0,"86"],"r":[0,1,18.024728298187256,262,1,1,18.26149272918701,263]}}
  #|{"textrec":{"m":[28,600,0],"r":[27.0703125,5.90625,40,24.0787353515625,3.9212646484375,0]}}
  #|{"textrec":{"s":[15,500,0,"%"],"r":[0,1,14.252007007598877,264]}}
  #|{"textrec":{"m":[15,500,0],"r":[14.501953125,3.1640625,21,14.501953125,3.1640625,0]}}
  #|{"textrec":{"s":[13,500,0,"CPU 空闲"],"r":[0,1,9.350531578063965,265,1,1,8.364851832389832,266,2,1,9.618190050125122,267,3,1,3.4683494567871094,-1,4,1,12.898832684824903,268,5,1,12.898832684824903,269]}}
  #|{"textrec":{"s":[12,400,0,"负载 5.9"],"r":[0,1,11.918287937743191,270,1,1,11.918287937743191,271,2,1,3.375,-1,3,1,7.212890625,272,4,1,3.123046875,273,5,1,7.40625,274]}}
  #|{"textrec":{"m":[12,400,0],"r":[11.6015625,2.53125,17,11.6015625,2.53125,0]}}
  #|{"textrec":{"s":[28,600,0,"7.2"],"r":[0,1,14.867459774017334,275,1,1,5.5835723876953125,276,2,1,16.886554718017578,277]}}
  #|{"textrec":{"s":[15,500,0,"GB"],"r":[0,1,11.039557456970215,278,1,1,9.822771549224854,279]}}
  #|{"textrec":{"s":[13,500,0,"内存剩"],"r":[0,1,12.898832684824903,280,1,1,12.898832684824903,281,2,1,12.898832684824903,282]}}
  #|{"textrec":{"s":[12,400,0,"共 16 GB"],"r":[0,1,11.918287937743191,283,1,1,3.375,-1,2,1,5.56640625,284,3,1,7.640625,285,4,1,3.375,-1,5,1,8.958984374999996,286,6,1,7.88671875,287]}}
  #|{"textrec":{"s":[28,600,0,"27.8"],"r":[0,1,16.886554718017578,277,1,1,14.867459774017334,275,2,1,5.5835723876953125,276,3,1,18.046374320983887,262]}}
  #|{"textrec":{"s":[13,500,0,"磁盘剩"],"r":[0,1,12.898832684824903,288,1,1,12.898832684824903,289,2,1,12.898832684824903,282]}}
  #|{"textrec":{"s":[12,400,0,"共 228 GB"],"r":[0,1,11.918287937743191,283,1,1,3.375,-1,2,1,7.2421875,290,3,1,7.2421875,290,4,1,7.6640624999999964,291,5,1,3.375,-1,6,1,8.958984375,286,7,1,7.88671875,287]}}
  #|{"textrec":{"s":[13,400,0,"主机名"],"r":[0,1,12.898832684824903,292,1,1,12.898832684824903,293,2,1,12.898832684824903,294]}}
  #|{"textrec":{"s":[13,400,0,"3720-Mac-mini-1"],"r":[0,1,8.07421875,295,1,1,7.3251953125,213,2,1,7.76953125,212,3,1,8.1123046875,214,4,1,6.0556640625,296,5,1,11.2861328125,204,6,1,7.0966796875,12,7,1,7.1982421875,13,8,1,6.0556640625,296,9,1,11.2353515625,80,10,1,3.1357421875,77,11,1,7.50927734375,297,12,1,3.1357421875,77,13,1,6.0556640625,296,14,1,5.9541015625,206]}}
  #|{"textrec":{"s":[13,400,0,"芯片"],"r":[0,1,12.898832684824903,298,1,1,12.898832684824903,299]}}
  #|{"textrec":{"s":[13,400,0,"Apple M4 · 10 核 · arm64"],"r":[0,1,8.68359375,203,1,1,7.8583984375,11,2,1,7.8583984375,11,3,1,3.2119140625,76,4,1,7.3505859375,14,5,1,3.580078125,-1,6,1,11.2861328125,204,7,1,8.2900390625,205,8,1,3.580078125,-1,9,1,6.228545204222115,202,10,1,3.580078125,-1,11,1,5.9541015625,206,12,1,8.1123046875,214,13,1,3.580078125,-1,14,1,12.898832684824896,300,15,1,3.580078125,-1,16,1,6.228545204222115,202,17,1,3.580078125,-1,18,1,7.0966796875,12,19,1,4.9384765625,8,20,1,11.298828125,80,21,1,8.201171875,207,22,1,8.2900390625,205]}}
  #|{"textrec":{"s":[13,400,0,"已运行"],"r":[0,1,12.898832684824903,301,1,1,12.898832684824903,302,2,1,12.898832684824903,303]}}
  #|{"textrec":{"s":[13,400,0,"20 小时"],"r":[0,1,7.76953125,212,1,1,8.1123046875,214,2,1,3.580078125,-1,3,1,12.898832684824903,304,4,1,12.898832684824903,153]}}
  #|{"textrec":{"s":[13,400,0,"still.fail"],"r":[0,1,6.69677734375,10,1,1,4.61474609375,82,2,1,3.1357421875,77,3,1,3.2119140625,76,4,1,3.2119140625,76,5,1,3.5927734375,81,6,1,4.341796875,305,7,1,7.00146484375,12,8,1,3.1357421875,77,9,1,3.2119140625,76]}}
  #|{"textrec":{"s":[13,400,0,"进程占用 152 MB"],"r":[0,1,12.898832684824903,306,1,1,12.898832684824903,307,2,1,12.898832684824903,308,3,1,12.898832684824903,309,4,1,3.580078125,-1,5,1,5.9541015625,206,6,1,7.9599609375,310,7,1,7.76953125,212,8,1,3.580078125,-1,9,1,11.2861328125,204,10,1,8.4677734375,209]}}
  #|{"textrec":{"s":[13,400,0,"没有运行中的 agent 进程"],"r":[0,1,12.898832684824903,311,1,1,12.898832684824903,149,2,1,12.898832684824903,302,3,1,12.898832684824903,303,4,1,12.898832684824896,312,5,1,12.898832684824896,5,6,1,3.580078125,-1,7,1,7.0966796875,12,8,1,7.845703125,313,9,1,7.3505859375,14,10,1,7.50927734375,297,11,1,4.646484375,82,12,1,3.580078125,-1,13,1,12.898832684824896,306,14,1,12.898832684824896,307]}}
  #|{"textrec":{"s":[15,600,0,"在此 station 上"],"r":[0,1,14.883268482490273,314,1,1,14.883268482490273,117,2,1,3.761730194091797,-1,3,1,8.000344634056091,315,4,1,5.658300518989563,316,5,1,8.40147078037262,317,6,1,5.683325529098511,316,7,1,3.8520312309265137,318,8,1,8.901597261428833,319,9,1,8.93320620059967,180,10,1,3.761730194091797,-1,11,1,14.883268482490266,320]}}
  #|{"textrec":{"s":[15,400,0,"共享调试"],"r":[0,1,14.883268482490273,321,1,1,14.883268482490273,322,2,1,14.883268482490273,323,3,1,14.883268482490273,324]}}
  #|{"textrec":{"s":[14,400,0,"未开放"],"r":[0,1,13.891050583657588,96,1,1,13.891050583657588,97,2,1,13.891050583657588,325]}}
  #|{"textrec":{"s":[15,400,0,"文件"],"r":[0,1,14.883268482490273,326,1,1,14.883268482490273,327]}}
  #|{"textrec":{"s":[15,600,0,"Agent 环境变量"],"r":[0,1,10.209932327270508,328,1,1,9.027448296546936,329,2,1,8.615586161613464,85,3,1,8.93320620059967,180,4,1,5.683325529098511,316,5,1,3.761730194091797,-1,6,1,14.883268482490273,330,7,1,14.883268482490273,331,8,1,14.883268482490266,332,9,1,14.88326848249028,333]}}
  #|{"textrec":{"s":[15,400,0,"暂无变量"],"r":[0,1,14.883268482490273,334,1,1,14.883268482490273,335,2,1,14.883268482490273,336,3,1,14.883268482490273,116]}}
  #|{"textrec":{"s":[15,400,0,"编辑变量"],"r":[0,1,14.883268482490273,337,1,1,14.883268482490273,338,2,1,14.883268482490273,336,3,1,14.883268482490273,116]}}
  #|{"textrec":{"s":[15,600,0,"屏幕"],"r":[0,1,14.883268482490273,339,1,1,14.883268482490273,340]}}
  #|{"textrec":{"s":[15,400,0,"3720-Mac-mini-1"],"r":[0,1,9.169921875,341,1,1,8.3056640625,342,2,1,8.818359375,343,3,1,9.2138671875,164,4,1,6.8408203125,344,5,1,12.8759765625,345,6,1,8.0419921875,93,7,1,8.1591796875,94,8,1,6.8408203125,344,9,1,12.8173828125,161,10,1,3.4716796875,102,11,1,8.51806640625,103,12,1,3.4716796875,102,13,1,6.8408203125,344,14,1,6.7236328125,165]}}
  #|{"textrec":{"s":[13,400,0,"此 station 版本不含屏幕助手（stillfail-screen），请更新 station"],"r":[0,1,12.898832684824903,346,1,1,3.580078125,-1,2,1,6.69677734375,10,3,1,4.61474609375,82,4,1,7.0966796875,12,5,1,4.646484375,82,6,1,3.1357421875,77,7,1,7.6044921875,7,8,1,7.50927734375,297,9,1,3.580078125,-1,10,1,12.898832684824903,347,11,1,12.89883268482491,348,12,1,12.898832684824896,349,13,1,12.898832684824896,350,14,1,12.898832684824896,351,15,1,12.898832684824896,352,16,1,12.898832684824896,353,17,1,19.398832684824896,354,18,1,4.071984435797674,355,19,1,6.69677734375,10,20,1,4.61474609375,82,21,1,3.1357421875,77,22,1,3.2119140625,76,23,1,3.2119140625,76,24,1,4.5322265625,305,25,1,7.00146484375,12,26,1,3.1357421875,77,27,1,3.2119140625,76,28,1,6.0556640625,296,29,1,6.728515625,10,30,1,7.1982421875,13,31,1,4.77978515625,8,32,1,7.25537109375,14,33,1,7.3505859375,14,34,1,7.50927734375,297,35,1,5.456712062256827,356,36,1,13.075875486381335,357,37,1,12.898832684824924,358,38,1,12.898832684824924,359,39,1,12.898832684824924,150,40,1,3.580078125,-1,41,1,6.69677734375,10,42,1,4.61474609375,82,43,1,7.0966796875,12,44,1,4.646484375,82,45,1,3.1357421875,77,46,1,7.6044921875,7,47,1,7.50927734375,297]}}
  #|{"textrec":{"g":256,"r":[299,32,12,16,-1,-14,0]}}
  #|{"textrec":{"g":257,"r":[312,32,8,15,-1,-13,0]}}
  #|{"textrec":{"g":258,"r":[321,32,11,13,-1,-11,0]}}
  #|{"textrec":{"g":259,"r":[333,32,5,15,0,-14,0]}}
  #|{"textrec":{"g":260,"r":[339,32,12,13,-1,-11,0]}}
  #|{"textrec":{"g":261,"r":[352,32,10,12,0,-11,0]}}
  #|{"textrec":{"g":262,"r":[363,32,18,24,0,-22,0]}}
  #|{"textrec":{"g":263,"r":[382,32,18,24,0,-22,0]}}
  #|{"textrec":{"g":265,"r":[401,32,11,13,-1,-11,0]}}
  #|{"textrec":{"g":266,"r":[413,32,9,12,0,-11,0]}}
  #|{"textrec":{"g":267,"r":[423,32,10,13,0,-11,0]}}
  #|{"textrec":{"g":268,"r":[434,32,14,14,-1,-12,0]}}
  #|{"textrec":{"g":269,"r":[449,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":270,"r":[463,32,13,14,-1,-11,0]}}
  #|{"textrec":{"g":271,"r":[477,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":272,"r":[492,32,9,12,-1,-10,0]}}
  #|{"textrec":{"g":273,"r":[502,32,4,5,0,-3,0]}}
  #|{"textrec":{"g":274,"r":[507,32,9,12,-1,-10,0]}}
  #|{"textrec":{"g":292,"r":[517,32,14,14,-1,-12,0]}}
  #|{"textrec":{"g":293,"r":[532,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":294,"r":[548,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":298,"r":[563,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":299,"r":[579,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":301,"r":[594,32,13,13,0,-11,0]}}
  #|{"textrec":{"g":302,"r":[608,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":303,"r":[624,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":305,"r":[640,32,7,12,-1,-11,0]}}
  #|{"textrec":{"g":311,"r":[648,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":149,"r":[664,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":312,"r":[679,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":5,"r":[693,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":313,"r":[707,32,9,12,-1,-8,0]}}
  #|{"textrec":{"g":297,"r":[717,32,8,9,0,-8,0]}}
  #|{"textrec":{"g":306,"r":[726,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":307,"r":[742,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":314,"r":[758,32,16,17,-1,-14,0]}}
  #|{"textrec":{"g":315,"r":[775,32,10,12,-1,-10,0]}}
  #|{"textrec":{"g":316,"r":[786,32,8,13,-1,-11,0]}}
  #|{"textrec":{"g":317,"r":[795,32,10,12,-1,-10,0]}}
  #|{"textrec":{"g":318,"r":[806,32,6,14,-1,-13,0]}}
  #|{"textrec":{"g":319,"r":[813,32,11,12,-1,-10,0]}}
  #|{"textrec":{"g":320,"r":[825,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":321,"r":[842,32,16,17,-1,-14,0]}}
  #|{"textrec":{"g":322,"r":[859,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":323,"r":[876,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":324,"r":[893,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":326,"r":[911,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":327,"r":[929,32,16,17,-1,-14,0]}}
  #|{"textrec":{"g":339,"r":[946,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":340,"r":[963,32,17,17,-1,-14,0]}}
  #|{"textrec":{"ib":["dfa0b3408acf8bc7",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"g":341,"r":[981,32,10,14,0,-12,0]}}
  #|{"textrec":{"g":342,"r":[992,32,10,13,-1,-12,0]}}
  #|{"textrec":{"g":343,"r":[1003,32,10,13,0,-12,0]}}
  #|{"textrec":{"g":164,"r":[1014,32,11,14,-1,-12,0]}}
  #|{"textrec":{"g":344,"r":[1026,32,7,4,0,-6,0]}}
  #|{"textrec":{"g":345,"r":[1034,32,13,13,0,-12,0]}}
  #|{"textrec":{"g":161,"r":[1048,32,13,11,0,-10,0]}}
  #|{"textrec":{"g":165,"r":[1062,32,8,13,-1,-12,0]}}
  #|{"textrec":{"g":346,"r":[1071,32,15,14,-1,-12,0]}}
  #|{"textrec":{"g":7,"r":[1087,32,9,10,-1,-8,0]}}
  #|{"textrec":{"g":347,"r":[1097,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":348,"r":[1113,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":349,"r":[1129,32,15,14,-1,-11,0]}}
  #|{"textrec":{"g":350,"r":[1145,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":351,"r":[1161,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":352,"r":[1176,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":353,"r":[1192,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":354,"r":[1207,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":355,"r":[1223,32,5,15,-1.16666666666667,-12,0]}}
  #|{"textrec":{"g":296,"r":[1229,32,8,4,-1,-6,0]}}
  #|{"textrec":{"g":8,"r":[1238,32,6,9,0,-8,0]}}
  #|{"textrec":{"g":356,"r":[1245,32,6,15,-1,-12,0]}}
  #|{"textrec":{"g":357,"r":[1252,32,5,7,0,-3,0]}}
  #|{"textrec":{"g":358,"r":[1258,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":359,"r":[1274,32,15,14,-1,-11,0]}}
  #|{"textrec":{"g":150,"r":[1290,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":234,"r":[1306,32,10,10,-1,-9,0]}}
  #|{"textrec":{"g":235,"r":[1317,32,9,10,-1,-7,0]}}
  #|{"textrec":{"g":236,"r":[1327,32,4,11,-1,-10,0]}}
  #|{"textrec":{"g":237,"r":[1332,32,8,9,-1,-7,0]}}
  #|{"textrec":{"g":238,"r":[1341,32,11,10,-1,-9,0]}}
  #|{"textrec":{"g":239,"r":[1353,32,9,10,-1,-9,0]}}
  #|{"textrec":{"g":240,"r":[1363,32,5,4,0,-6,0]}}
  #|{"textrec":{"g":241,"r":[1369,32,6,10,-1,-9,0]}}
  #|{"textrec":{"g":242,"r":[1376,32,9,11,-1,-9,0]}}
  #|{"textrec":{"g":243,"r":[1386,32,10,11,-1,-9,0]}}
  #|{"textrec":{"g":244,"r":[1397,32,9,10,-1,-9,0]}}
  #|{"textrec":{"g":245,"r":[1407,32,11,8,-1,-7,0]}}
  #|{"textrec":{"g":246,"r":[1419,32,8,9,-1,-7,0]}}
  #|{"textrec":{"g":247,"r":[1428,32,8,9,-1,-7,0]}}
  #|{"textrec":{"g":248,"r":[1437,32,10,11,-1,-9,0]}}
  #|{"textrec":{"g":249,"r":[1448,32,9,11,-1,-9,0]}}
  #|{"textrec":{"g":250,"r":[1458,32,8,10,-1,-9,0]}}
  #|{"textrec":{"g":251,"r":[1467,32,8,10,-1,-9,0]}}
  #|{"textrec":{"g":252,"r":[1476,32,5,5,-1,-3,0]}}
  #|{"textrec":{"g":253,"r":[1482,32,9,11,-1,-9,0]}}
  #|{"textrec":{"g":264,"r":[1492,32,16,14,-1,-12,0]}}
  #|{"textrec":{"g":295,"r":[1509,32,10,13,-1,-11,0]}}
  #|{"textrec":{"g":300,"r":[1520,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":304,"r":[1536,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":153,"r":[1552,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":308,"r":[1568,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":309,"r":[1582,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":310,"r":[1597,32,10,13,-1,-11,0]}}
  #|{"textrec":{"g":254,"r":[1608,32,10,12,0,-10,0]}}
  #|{"textrec":{"g":255,"r":[1619,32,11,15,-1,-13,0]}}
  #|{"textrec":{"g":275,"r":[1631,32,17,22,-1,-21,0]}}
  #|{"textrec":{"g":276,"r":[1649,32,7,7,0,-5,0]}}
  #|{"textrec":{"g":277,"r":[1657,32,17,23,0,-22,0]}}
  #|{"textrec":{"g":280,"r":[1675,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":281,"r":[1689,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":282,"r":[1705,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":283,"r":[1720,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":284,"r":[1735,32,7,11,-1,-10,0]}}
  #|{"textrec":{"g":285,"r":[1743,32,9,12,-1,-10,0]}}
  #|{"textrec":{"g":286,"r":[1753,32,11,12,-1,-10,0]}}
  #|{"textrec":{"g":287,"r":[1765,32,9,11,0,-10,0]}}
  #|{"textrec":{"g":278,"r":[1775,32,13,14,-1,-12,0]}}
  #|{"textrec":{"g":279,"r":[1789,32,11,13,0,-12,0]}}
  #|{"textrec":{"g":288,"r":[1801,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":289,"r":[1817,32,15,14,-1,-12,0]}}
  #|{"textrec":{"g":290,"r":[1833,32,9,11,-1,-10,0]}}
  #|{"textrec":{"g":291,"r":[1843,32,9,12,-1,-10,0]}}
  #|{"textrec":{"g":325,"r":[1853,32,16,16,-1,-13,0]}}
  #|{"textrec":{"ib":["ddfdc2820df8a676",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"g":328,"r":[1870,32,13,13,-1,-12,0]}}
  #|{"textrec":{"g":329,"r":[1884,32,11,14,-1,-10,0]}}
  #|{"textrec":{"g":330,"r":[1896,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":331,"r":[1914,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":332,"r":[1932,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":333,"r":[1950,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":334,"r":[1967,32,15,17,0,-14,0]}}
  #|{"textrec":{"g":335,"r":[1983,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":336,"r":[2000,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":337,"r":[2018,32,16,17,-1,-14,0]}}
  #|{"textrec":{"g":338,"r":[0,57,17,16,-1,-13,0]}}
  #|{"textrec":{"s":[15,600,0,"搜索"],"r":[0,1,14.883268482490273,360,1,1,14.883268482490273,361]}}
  #|{"textrec":{"s":[15,400,0,"搜索个人数据"],"r":[0,1,14.883268482490273,18,1,1,14.883268482490273,19,2,1,14.883268482490273,362,3,1,14.883268482490273,363,4,1,14.88326848249028,364,5,1,14.88326848249028,365]}}
  #|{"textrec":{"s":[13,400,0,"workspace 成员也可搜索邮件、信息、日历、通讯录、备忘录和照片"],"r":[0,1,9.8642578125,6,1,1,7.4775390625,7,2,1,4.875,8,3,1,6.85546875,9,4,1,6.6015625,10,5,1,7.8583984375,11,6,1,7.0966796875,12,7,1,7.1982421875,13,8,1,7.3505859375,14,9,1,3.580078125,-1,10,1,12.898832684824896,140,11,1,12.898832684824896,366,12,1,12.898832684824896,367,13,1,12.898832684824896,368,14,1,12.898832684824896,369,15,1,12.898832684824896,370,16,1,12.898832684824896,371,17,1,12.898832684824896,372,18,1,13.075875486381335,141,19,1,12.898832684824896,373,20,1,12.898832684824896,152,21,1,13.075875486381335,141,22,1,12.898832684824896,374,23,1,12.898832684824896,375,24,1,13.075875486381335,141,25,1,12.898832684824924,154,26,1,12.898832684824924,376,27,1,12.898832684824924,377,28,1,13.075875486381335,141,29,1,12.898832684824924,378,30,1,12.898832684824924,379,31,1,12.898832684824924,377,32,1,12.898832684824924,380,33,1,12.898832684824924,381,34,1,12.898832684824924,299]}}
  #|{"textrec":{"g":360,"r":[18,57,17,16,-1,-13,0]}}
  #|{"textrec":{"g":361,"r":[36,57,16,16,-1,-13,0]}}
  #|{"textrec":{"g":362,"r":[53,57,17,16,-1,-13,0]}}
  #|{"textrec":{"g":363,"r":[71,57,17,16,-1,-13,0]}}
  #|{"textrec":{"g":364,"r":[89,57,17,16,-1,-13,0]}}
  #|{"textrec":{"g":365,"r":[107,57,16,16,-1,-13,0]}}
  #|{"textrec":{"g":6,"r":[124,57,12,9,-1,-8,0]}}
  #|{"textrec":{"g":9,"r":[137,57,8,12,0,-11,0]}}
  #|{"textrec":{"g":140,"r":[146,57,15,15,-1,-12,0]}}
  #|{"textrec":{"g":366,"r":[162,57,14,14,-1,-11,0]}}
  #|{"textrec":{"g":367,"r":[177,57,15,14,-1,-12,0]}}
  #|{"textrec":{"g":368,"r":[193,57,14,14,-1,-11,0]}}
  #|{"textrec":{"g":369,"r":[208,57,15,15,-1,-12,0]}}
  #|{"textrec":{"g":370,"r":[224,57,14,15,-1,-12,0]}}
  #|{"textrec":{"g":371,"r":[239,57,14,15,-1,-12,0]}}
  #|{"textrec":{"g":372,"r":[254,57,15,15,-1,-12,0]}}
  #|{"textrec":{"g":141,"r":[270,57,6,6,0,-3,0]}}
  #|{"textrec":{"g":373,"r":[277,57,15,15,-1,-12,0]}}
  #|{"textrec":{"g":152,"r":[293,57,15,15,-1,-12,0]}}
  #|{"textrec":{"g":374,"r":[309,57,11,14,1,-11,0]}}
  #|{"textrec":{"g":375,"r":[321,57,14,14,-1,-11,0]}}
  #|{"textrec":{"s":[15,600,0,"版本"],"r":[0,1,14.883268482490273,382,1,1,14.883268482490273,383]}}
  #|{"textrec":{"g":154,"r":[336,57,15,15,-1,-12,0]}}
  #|{"textrec":{"g":376,"r":[352,57,15,15,-1,-12,0]}}
  #|{"textrec":{"g":377,"r":[368,57,14,14,-1,-11,0]}}
  #|{"textrec":{"g":378,"r":[383,57,15,15,-1,-12,0]}}
  #|{"textrec":{"g":379,"r":[399,57,15,15,-1,-12,0]}}
  #|{"textrec":{"g":380,"r":[415,57,14,15,-1,-12,0]}}
  #|{"textrec":{"g":381,"r":[430,57,15,14,-1,-11,0]}}
  #|{"textrec":{"s":[13,400,0,"开发版"],"r":[0,1,12.898832684824903,384,1,1,12.898832684824903,385,2,1,12.898832684824903,347]}}
  #|{"textrec":{"s":[13,400,0,"并非通过安装脚本安装，无法在此更新；检查更新失败，点击「检查更新」重试"],"r":[0,1,12.898832684824903,386,1,1,12.898832684824903,387,2,1,12.898832684824903,154,3,1,12.898832684824903,388,4,1,12.898832684824896,389,5,1,12.898832684824896,390,6,1,12.898832684824896,391,7,1,12.898832684824896,348,8,1,12.898832684824896,389,9,1,12.898832684824896,390,10,1,13.075875486381335,357,11,1,12.898832684824896,392,12,1,12.898832684824896,393,13,1,12.898832684824896,1,14,1,12.898832684824896,346,15,1,12.898832684824896,359,16,1,12.898832684824896,150,17,1,13.075875486381335,394,18,1,12.898832684824896,395,19,1,12.898832684824924,396,20,1,12.898832684824924,359,21,1,12.898832684824924,150,22,1,12.898832684824924,397,23,1,12.898832684824924,398,24,1,13.075875486381335,357,25,1,12.898832684824924,399,26,1,19.398832684824924,400,27,1,4.704280155642039,401,28,1,12.898832684824924,395,29,1,12.898832684824924,396,30,1,12.898832684824924,359,31,1,12.898832684824924,150,32,1,4.451361867704293,402,33,1,19.398832684824924,403,34,1,12.898832684824924,404]}}
  #|{"textrec":{"s":[15,400,0,"Claude Code"],"r":[0,1,10.5029296875,405,1,1,3.5595703125,108,2,1,8.0419921875,93,3,1,8.51806640625,163,4,1,8.9794921875,406,5,1,8.3349609375,95,6,1,3.984375,-1,7,1,10.5029296875,405,8,1,8.6279296875,88,9,1,8.9794921875,406,10,1,8.3349609375,95]}}
  #|{"textrec":{"s":[13,400,0,"版本未知"],"r":[0,1,12.898832684824903,347,1,1,12.898832684824903,348,2,1,12.898832684824903,407,3,1,12.898832684824903,155]}}
  #|{"textrec":{"s":[13,400,0,"已是最新"],"r":[0,1,12.898832684824903,301,1,1,12.898832684824903,408,2,1,12.898832684824903,409,3,1,12.898832684824903,150]}}
  #|{"textrec":{"s":[15,400,0,"Codex"],"r":[0,1,10.5029296875,405,1,1,8.6279296875,88,2,1,8.9794921875,406,3,1,8.1884765625,95,4,1,7.4853515625,410]}}
  #|{"textrec":{"s":[13,400,0,"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-lockp/apps/e2e-local/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新；已是最新"],"r":[0,1,12.898832684824903,389,1,1,12.898832684824903,390,2,1,12.898832684824903,1,3,1,3.580078125,-1,4,1,3.884765625,411,5,1,9.5087890625,412,6,1,6.728515625,10,7,1,7.350585937500007,14,8,1,4.8115234375,8,9,1,6.6650390625,10,10,1,3.884765625,411,11,1,6.931640625,413,12,1,7.50927734375,414,13,1,7.50927734375,7,14,1,6.83642578125,413,15,1,3.1357421875,77,16,1,3.12939453125,415,17,1,3.1357421875,77,18,1,7.0966796875,12,19,1,7.50927734375,297,20,1,3.630859375,411,21,1,3.529296875,81,22,1,6.69677734375,10,23,1,4.61474609375,82,24,1,3.1357421875,77,25,1,3.2119140625,76,26,1,3.2119140625,76,27,1,4.5322265625,305,28,1,7.00146484375,12,29,1,3.1357421875,77,30,1,3.2119140625,76,31,1,3.884765625,411,32,1,4.77978515625,8,33,1,7.25537109375,14,34,1,11.2353515625,80,35,1,7.6044921875,7,36,1,4.598876953125,82,37,1,7.302978515625,14,38,1,3.884765625,411,39,1,6.728515625,10,40,1,7.3505859375,14,41,1,6.6650390625,10,42,1,6.6650390625,10,43,1,3.1357421875,77,44,1,7.6044921875,7,45,1,7.50927734375,297,46,1,6.728515625,10,47,1,3.884765625,411,48,1,8.201171875,207,49,1,5.9541015625,206,50,1,7.3505859375,14,51,1,7.9091796875,416,52,1,7.75048828125,417,53,1,5.79541015625,206,54,1,7.3505859375,14,55,1,8.07421875,295,56,1,8.201171875,207,57,1,8.2900390625,205,58,1,8.201171875,207,59,1,8.201171875,418,60,1,7.1982421875,13,61,1,7.3505859375,14,62,1,7.9599609375,310,63,1,8.201171875,418,64,1,8.07421875,295,65,1,7.0712890625,13,66,1,6.91259765625,213,67,1,6.81103515625,12,68,1,7.9091796875,417,69,1,7.9091796875,416,70,1,8.201171875,207,71,1,4.484619140625,305,72,1,7.055419921875,13,73,1,7.3505859375,14,74,1,4.484619140625,305,75,1,7.055419921875,13,76,1,7.9091796875,416,77,1,7.76953125,212,78,1,4.627441406249943,305,79,1,7.76953125,212,80,1,8.1123046875,214,81,1,7.76953125,212,82,1,7.22998046875,213,83,1,8.10595703125,207,84,1,7.76953125,212,85,1,7.0966796875,12,86,1,7.76953125,212,87,1,7.76953125,212,88,1,7.9599609375,310,89,1,7.1982421875,13,90,1,8.201171875,418,91,1,8.2900390625,205,92,1,7.0966796875,12,93,1,4.484619140625,305,94,1,7.207763671875,14,95,1,7.9091796875,417,96,1,7.0966796875,12,97,1,7.2236328125,14,98,1,7.1982421875,213,99,1,7.73779296875,212,100,1,7.16650390625,13,101,1,8.2265625,419,102,1,7.73779296875,212,103,1,7.87744140625,416,104,1,7.9091796875,417,105,1,7.9599609375,310,106,1,7.67431640625,212,107,1,8.19482421875,205,108,1,7.9599609375,310,109,1,8.07421875,295,110,1,8.201171875,418,111,1,5.9541015625,206,112,1,3.884765625,411,113,1,9.8642578125,6,114,1,7.4775390625,7,115,1,4.875,8,116,1,6.982421875,9,117,1,3.884765625,411,118,1,6.728515625,10,119,1,4.46875,305,120,1,5.89697265625,296,121,1,3.2119140625,76,122,1,7.6044921875,7,123,1,7.1982421875,13,124,1,6.982421875,9,125,1,7.8583984375,11,126,1,3.884765625,411,127,1,7.0966796875,12,128,1,7.8583984375,11,129,1,7.8583984375,11,130,1,6.728515625,10,131,1,3.884765625,411,132,1,7.3505859375,14,133,1,7.73779296875,212,134,1,7.31884765625,14,135,1,6.0556640625,296,136,1,3.2119140625,76,137,1,7.6044921875,7,138,1,7.1982421875,13,139,1,7.0966796875,12,140,1,3.2119140625,76,141,1,3.884765625,411,142,1,7.3505859375,14,143,1,11.2353515625,80,144,1,7.9091796875,417,145,1,7.3505859375,14,146,1,4.65283203125,8,147,1,3.66259765625,411,148,1,6.69677734375,10,149,1,4.61474609375,82,150,1,7.0966796875,12,151,1,4.646484375,82,152,1,3.1357421875,77,153,1,7.6044921875,7,154,1,7.50927734375,297,155,1,3.884765625,411,156,1,4.598876953125,82,157,1,7.302978515625,14,158,1,6.69677734375,10,159,1,4.61474609375,82,160,1,3.884765625,411,161,1,4.5322265625,305,162,1,7.00146484375,12,163,1,6.82373046875,9,164,1,7.19189453125,14,165,1,3.884765625,411,166,1,7.1982421875,13,167,1,7.6044921875,7,168,1,7.9091796875,416,169,1,7.2236328125,14,170,1,6.6142578125,79,171,1,13.075875486381392,357,172,1,12.89883268482481,386,173,1,12.89883268482481,387,174,1,12.89883268482481,154,175,1,12.89883268482481,388,176,1,3.580078125,-1,177,1,7.50927734375,297,178,1,7.8583984375,11,179,1,11.2353515625,80,180,1,3.580078125,-1,181,1,12.89883268482481,148,182,1,3.580078125,-1,183,1,9.572265625,420,184,1,7.6044921875,7,185,1,11.2353515625,80,186,1,7.3505859375,14,187,1,7.9091796875,417,188,1,4.77978515625,8,189,1,7.25537109375,14,190,1,9.9912109375,6,191,1,3.580078125,-1,192,1,12.89883268482481,389,193,1,12.89883268482481,390,194,1,13.075875486381392,357,195,1,12.89883268482481,142,196,1,12.89883268482481,1,197,1,12.89883268482481,421,198,1,12.89883268482481,293,199,1,12.89883268482481,422,200,1,12.89883268482481,423,201,1,12.89883268482481,354,202,1,12.89883268482481,424,203,1,12.89883268482481,359,204,1,12.89883268482481,150,205,1,13.075875486381392,394,206,1,12.89883268482481,301,207,1,12.89883268482481,408,208,1,12.89883268482481,409,209,1,12.89883268482481,150]}}
  #|{"textrec":{"s":[13,500,0,"0.2.1-rc.2"],"r":[0,1,8.090002655982971,223,1,1,3.6386033296585083,425,2,1,7.776639819145203,426,3,1,3.7105413675308228,425,4,1,5.945230960845947,427,5,1,6.116183757781982,428,6,1,5.043976902961731,429,7,1,7.241524338722229,430,8,1,3.9216055870056152,425,9,1,7.8543970584869385,426]}}
  #|{"textrec":{"s":[15,400,0,"DeepSeek Harness"],"r":[0,1,10.6640625,431,1,1,8.3349609375,95,2,1,8.3349609375,95,3,1,8.9208984375,92,4,1,9.32373046875,100,5,1,8.3349609375,95,6,1,8.3349609375,95,7,1,7.91015625,90,8,1,3.984375,-1,9,1,10.8984375,432,10,1,8.0419921875,93,11,1,5.5517578125,89,12,1,8.59130859375,103,13,1,8.3349609375,95,14,1,7.5439453125,91,15,1,7.5439453125,91]}}
  #|{"textrec":{"s":[13,400,0,"0.2.0"],"r":[0,1,7.8583984375,214,1,1,3.40234375,81,2,1,7.54736328125,212,3,1,3.43408203125,81,4,1,7.8583984375,214]}}
  #|{"textrec":{"s":[13,400,0,"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-lockp/apps/e2e-local/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新"],"r":[0,1,12.898832684824903,389,1,1,12.898832684824903,390,2,1,12.898832684824903,1,3,1,3.580078125,-1,4,1,3.884765625,411,5,1,9.5087890625,412,6,1,6.728515625,10,7,1,7.350585937500007,14,8,1,4.8115234375,8,9,1,6.6650390625,10,10,1,3.884765625,411,11,1,6.931640625,413,12,1,7.50927734375,414,13,1,7.50927734375,7,14,1,6.83642578125,413,15,1,3.1357421875,77,16,1,3.12939453125,415,17,1,3.1357421875,77,18,1,7.0966796875,12,19,1,7.50927734375,297,20,1,3.630859375,411,21,1,3.529296875,81,22,1,6.69677734375,10,23,1,4.61474609375,82,24,1,3.1357421875,77,25,1,3.2119140625,76,26,1,3.2119140625,76,27,1,4.5322265625,305,28,1,7.00146484375,12,29,1,3.1357421875,77,30,1,3.2119140625,76,31,1,3.884765625,411,32,1,4.77978515625,8,33,1,7.25537109375,14,34,1,11.2353515625,80,35,1,7.6044921875,7,36,1,4.598876953125,82,37,1,7.302978515625,14,38,1,3.884765625,411,39,1,6.728515625,10,40,1,7.3505859375,14,41,1,6.6650390625,10,42,1,6.6650390625,10,43,1,3.1357421875,77,44,1,7.6044921875,7,45,1,7.50927734375,297,46,1,6.728515625,10,47,1,3.884765625,411,48,1,8.201171875,207,49,1,5.9541015625,206,50,1,7.3505859375,14,51,1,7.9091796875,416,52,1,7.75048828125,417,53,1,5.79541015625,206,54,1,7.3505859375,14,55,1,8.07421875,295,56,1,8.201171875,207,57,1,8.2900390625,205,58,1,8.201171875,207,59,1,8.201171875,418,60,1,7.1982421875,13,61,1,7.3505859375,14,62,1,7.9599609375,310,63,1,8.201171875,418,64,1,8.07421875,295,65,1,7.0712890625,13,66,1,6.91259765625,213,67,1,6.81103515625,12,68,1,7.9091796875,417,69,1,7.9091796875,416,70,1,8.201171875,207,71,1,4.484619140625,305,72,1,7.055419921875,13,73,1,7.3505859375,14,74,1,4.484619140625,305,75,1,7.055419921875,13,76,1,7.9091796875,416,77,1,7.76953125,212,78,1,4.627441406249943,305,79,1,7.76953125,212,80,1,8.1123046875,214,81,1,7.76953125,212,82,1,7.22998046875,213,83,1,8.10595703125,207,84,1,7.76953125,212,85,1,7.0966796875,12,86,1,7.76953125,212,87,1,7.76953125,212,88,1,7.9599609375,310,89,1,7.1982421875,13,90,1,8.201171875,418,91,1,8.2900390625,205,92,1,7.0966796875,12,93,1,4.484619140625,305,94,1,7.207763671875,14,95,1,7.9091796875,417,96,1,7.0966796875,12,97,1,7.2236328125,14,98,1,7.1982421875,213,99,1,7.73779296875,212,100,1,7.16650390625,13,101,1,8.2265625,419,102,1,7.73779296875,212,103,1,7.87744140625,416,104,1,7.9091796875,417,105,1,7.9599609375,310,106,1,7.67431640625,212,107,1,8.19482421875,205,108,1,7.9599609375,310,109,1,8.07421875,295,110,1,8.201171875,418,111,1,5.9541015625,206,112,1,3.884765625,411,113,1,9.8642578125,6,114,1,7.4775390625,7,115,1,4.875,8,116,1,6.982421875,9,117,1,3.884765625,411,118,1,6.728515625,10,119,1,4.46875,305,120,1,5.89697265625,296,121,1,3.2119140625,76,122,1,7.6044921875,7,123,1,7.1982421875,13,124,1,6.982421875,9,125,1,7.8583984375,11,126,1,3.884765625,411,127,1,7.0966796875,12,128,1,7.8583984375,11,129,1,7.8583984375,11,130,1,6.728515625,10,131,1,3.884765625,411,132,1,7.3505859375,14,133,1,7.73779296875,212,134,1,7.31884765625,14,135,1,6.0556640625,296,136,1,3.2119140625,76,137,1,7.6044921875,7,138,1,7.1982421875,13,139,1,7.0966796875,12,140,1,3.2119140625,76,141,1,3.884765625,411,142,1,7.3505859375,14,143,1,11.2353515625,80,144,1,7.9091796875,417,145,1,7.3505859375,14,146,1,4.65283203125,8,147,1,3.66259765625,411,148,1,6.69677734375,10,149,1,4.61474609375,82,150,1,7.0966796875,12,151,1,4.646484375,82,152,1,3.1357421875,77,153,1,7.6044921875,7,154,1,7.50927734375,297,155,1,3.884765625,411,156,1,4.598876953125,82,157,1,7.302978515625,14,158,1,6.69677734375,10,159,1,4.61474609375,82,160,1,3.884765625,411,161,1,4.5322265625,305,162,1,7.00146484375,12,163,1,6.82373046875,9,164,1,7.19189453125,14,165,1,3.884765625,411,166,1,7.9091796875,416,167,1,6.728515625,10,168,1,7.57275390625,433,169,1,13.075875486381392,357,170,1,12.89883268482481,386,171,1,12.89883268482481,387,172,1,12.89883268482481,154,173,1,12.89883268482481,388,174,1,3.580078125,-1,175,1,7.50927734375,297,176,1,7.8583984375,11,177,1,11.2353515625,80,178,1,3.580078125,-1,179,1,12.89883268482481,148,180,1,3.580078125,-1,181,1,9.572265625,420,182,1,7.6044921875,7,183,1,11.2353515625,80,184,1,7.3505859375,14,185,1,7.9091796875,417,186,1,4.77978515625,8,187,1,7.25537109375,14,188,1,9.9912109375,6,189,1,3.580078125,-1,190,1,12.89883268482481,389,191,1,12.89883268482481,390,192,1,13.075875486381392,357,193,1,12.89883268482481,142,194,1,12.89883268482481,1,195,1,12.89883268482481,421,196,1,12.89883268482481,293,197,1,12.89883268482481,422,198,1,12.89883268482481,423,199,1,12.89883268482481,354,200,1,12.89883268482481,424,201,1,12.89883268482481,359,202,1,12.89883268482481,150]}}
  #|{"textrec":{"s":[15,400,0,"Grok Build"],"r":[0,1,10.96435546875,434,1,1,5.36865234375,89,2,1,8.51806640625,88,3,1,7.91015625,90,4,1,3.984375,-1,5,1,9.6240234375,435,6,1,8.51806640625,163,7,1,3.4716796875,102,8,1,3.5595703125,108,9,1,8.9794921875,406]}}
  #|{"textrec":{"s":[13,400,0,"1.0.62"],"r":[0,1,5.79541015625,206,1,1,3.37060546875,81,2,1,7.6044921875,214,3,1,3.275390625,81,4,1,7.947265625,207,5,1,7.76953125,212]}}
  #|{"textrec":{"s":[13,400,0,"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-lockp/apps/e2e-local/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新；已是最新"],"r":[0,1,12.898832684824903,389,1,1,12.898832684824903,390,2,1,12.898832684824903,1,3,1,3.580078125,-1,4,1,3.884765625,411,5,1,9.5087890625,412,6,1,6.728515625,10,7,1,7.350585937500007,14,8,1,4.8115234375,8,9,1,6.6650390625,10,10,1,3.884765625,411,11,1,6.931640625,413,12,1,7.50927734375,414,13,1,7.50927734375,7,14,1,6.83642578125,413,15,1,3.1357421875,77,16,1,3.12939453125,415,17,1,3.1357421875,77,18,1,7.0966796875,12,19,1,7.50927734375,297,20,1,3.630859375,411,21,1,3.529296875,81,22,1,6.69677734375,10,23,1,4.61474609375,82,24,1,3.1357421875,77,25,1,3.2119140625,76,26,1,3.2119140625,76,27,1,4.5322265625,305,28,1,7.00146484375,12,29,1,3.1357421875,77,30,1,3.2119140625,76,31,1,3.884765625,411,32,1,4.77978515625,8,33,1,7.25537109375,14,34,1,11.2353515625,80,35,1,7.6044921875,7,36,1,4.598876953125,82,37,1,7.302978515625,14,38,1,3.884765625,411,39,1,6.728515625,10,40,1,7.3505859375,14,41,1,6.6650390625,10,42,1,6.6650390625,10,43,1,3.1357421875,77,44,1,7.6044921875,7,45,1,7.50927734375,297,46,1,6.728515625,10,47,1,3.884765625,411,48,1,8.201171875,207,49,1,5.9541015625,206,50,1,7.3505859375,14,51,1,7.9091796875,416,52,1,7.75048828125,417,53,1,5.79541015625,206,54,1,7.3505859375,14,55,1,8.07421875,295,56,1,8.201171875,207,57,1,8.2900390625,205,58,1,8.201171875,207,59,1,8.201171875,418,60,1,7.1982421875,13,61,1,7.3505859375,14,62,1,7.9599609375,310,63,1,8.201171875,418,64,1,8.07421875,295,65,1,7.0712890625,13,66,1,6.91259765625,213,67,1,6.81103515625,12,68,1,7.9091796875,417,69,1,7.9091796875,416,70,1,8.201171875,207,71,1,4.484619140625,305,72,1,7.055419921875,13,73,1,7.3505859375,14,74,1,4.484619140625,305,75,1,7.055419921875,13,76,1,7.9091796875,416,77,1,7.76953125,212,78,1,4.627441406249943,305,79,1,7.76953125,212,80,1,8.1123046875,214,81,1,7.76953125,212,82,1,7.22998046875,213,83,1,8.10595703125,207,84,1,7.76953125,212,85,1,7.0966796875,12,86,1,7.76953125,212,87,1,7.76953125,212,88,1,7.9599609375,310,89,1,7.1982421875,13,90,1,8.201171875,418,91,1,8.2900390625,205,92,1,7.0966796875,12,93,1,4.484619140625,305,94,1,7.207763671875,14,95,1,7.9091796875,417,96,1,7.0966796875,12,97,1,7.2236328125,14,98,1,7.1982421875,213,99,1,7.73779296875,212,100,1,7.16650390625,13,101,1,8.2265625,419,102,1,7.73779296875,212,103,1,7.87744140625,416,104,1,7.9091796875,417,105,1,7.9599609375,310,106,1,7.67431640625,212,107,1,8.19482421875,205,108,1,7.9599609375,310,109,1,8.07421875,295,110,1,8.201171875,418,111,1,5.9541015625,206,112,1,3.884765625,411,113,1,9.8642578125,6,114,1,7.4775390625,7,115,1,4.875,8,116,1,6.982421875,9,117,1,3.884765625,411,118,1,6.728515625,10,119,1,4.46875,305,120,1,5.89697265625,296,121,1,3.2119140625,76,122,1,7.6044921875,7,123,1,7.1982421875,13,124,1,6.982421875,9,125,1,7.8583984375,11,126,1,3.884765625,411,127,1,7.0966796875,12,128,1,7.8583984375,11,129,1,7.8583984375,11,130,1,6.728515625,10,131,1,3.884765625,411,132,1,7.3505859375,14,133,1,7.73779296875,212,134,1,7.31884765625,14,135,1,6.0556640625,296,136,1,3.2119140625,76,137,1,7.6044921875,7,138,1,7.1982421875,13,139,1,7.0966796875,12,140,1,3.2119140625,76,141,1,3.884765625,411,142,1,7.3505859375,14,143,1,11.2353515625,80,144,1,7.9091796875,417,145,1,7.3505859375,14,146,1,4.65283203125,8,147,1,3.66259765625,411,148,1,6.69677734375,10,149,1,4.61474609375,82,150,1,7.0966796875,12,151,1,4.646484375,82,152,1,3.1357421875,77,153,1,7.6044921875,7,154,1,7.50927734375,297,155,1,3.884765625,411,156,1,4.598876953125,82,157,1,7.302978515625,14,158,1,6.69677734375,10,159,1,4.61474609375,82,160,1,3.884765625,411,161,1,4.5322265625,305,162,1,7.00146484375,12,163,1,6.82373046875,9,164,1,7.19189453125,14,165,1,3.884765625,411,166,1,7.845703125,313,167,1,4.77978515625,8,168,1,7.50927734375,7,169,1,6.982421875,9,170,1,13.075875486381392,357,171,1,12.89883268482481,386,172,1,12.89883268482481,387,173,1,12.89883268482481,154,174,1,12.89883268482481,388,175,1,3.580078125,-1,176,1,7.50927734375,297,177,1,7.8583984375,11,178,1,11.2353515625,80,179,1,3.580078125,-1,180,1,12.89883268482481,148,181,1,3.580078125,-1,182,1,9.572265625,420,183,1,7.6044921875,7,184,1,11.2353515625,80,185,1,7.3505859375,14,186,1,7.9091796875,417,187,1,4.77978515625,8,188,1,7.25537109375,14,189,1,9.9912109375,6,190,1,3.580078125,-1,191,1,12.89883268482481,389,192,1,12.89883268482481,390,193,1,13.075875486381392,357,194,1,12.89883268482481,142,195,1,12.89883268482481,1,196,1,12.89883268482481,421,197,1,12.89883268482481,293,198,1,12.89883268482481,422,199,1,12.89883268482481,423,200,1,12.89883268482481,354,201,1,12.89883268482481,424,202,1,12.89883268482481,359,203,1,12.89883268482481,150,204,1,13.075875486381392,394,205,1,12.89883268482481,301,206,1,12.89883268482481,408,207,1,12.89883268482481,409,208,1,12.89883268482481,150]}}
  #|{"textrec":{"s":[13,400,0,"安装"],"r":[0,1,12.898832684824903,389,1,1,12.898832684824903,390]}}
  #|{"textrec":{"s":[15,400,0,"Cursor"],"r":[0,1,10.5029296875,405,1,1,8.51806640625,163,2,1,5.4052734375,89,3,1,7.5439453125,91,4,1,8.6279296875,88,5,1,5.478515625,89]}}
  #|{"textrec":{"s":[13,400,0,"未安装"],"r":[0,1,12.898832684824903,407,1,1,12.898832684824903,389,2,1,12.898832684824903,390]}}
  #|{"textrec":{"s":[13,400,0," "],"r":[0,1,3.580078125,-1]}}
  #|{"textrec":{"s":[15,400,0,"Devin"],"r":[0,1,10.6640625,431,1,1,8.26171875,95,2,1,7.822265625,436,3,1,3.4716796875,102,4,1,8.51806640625,103]}}
  #|{"textrec":{"s":[13,400,0,"3000.11.92"],"r":[0,1,8.07421875,295,1,1,8.1123046875,214,2,1,8.1123046875,214,3,1,7.8583984375,214,4,1,3.3388671875,81,5,1,5.763671875,206,6,1,5.79541015625,206,7,1,3.37060546875,81,8,1,7.947265625,418,9,1,7.76953125,212]}}
  #|{"textrec":{"s":[13,400,0,"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-lockp/apps/e2e-local/ember/station/test/fake/devin，不是用 Devin 的安装脚本装的，需在该机器上手动更新；已是最新"],"r":[0,1,12.898832684824903,389,1,1,12.898832684824903,390,2,1,12.898832684824903,1,3,1,3.580078125,-1,4,1,3.884765625,411,5,1,9.5087890625,412,6,1,6.728515625,10,7,1,7.350585937500007,14,8,1,4.8115234375,8,9,1,6.6650390625,10,10,1,3.884765625,411,11,1,6.931640625,413,12,1,7.50927734375,414,13,1,7.50927734375,7,14,1,6.83642578125,413,15,1,3.1357421875,77,16,1,3.12939453125,415,17,1,3.1357421875,77,18,1,7.0966796875,12,19,1,7.50927734375,297,20,1,3.630859375,411,21,1,3.529296875,81,22,1,6.69677734375,10,23,1,4.61474609375,82,24,1,3.1357421875,77,25,1,3.2119140625,76,26,1,3.2119140625,76,27,1,4.5322265625,305,28,1,7.00146484375,12,29,1,3.1357421875,77,30,1,3.2119140625,76,31,1,3.884765625,411,32,1,4.77978515625,8,33,1,7.25537109375,14,34,1,11.2353515625,80,35,1,7.6044921875,7,36,1,4.598876953125,82,37,1,7.302978515625,14,38,1,3.884765625,411,39,1,6.728515625,10,40,1,7.3505859375,14,41,1,6.6650390625,10,42,1,6.6650390625,10,43,1,3.1357421875,77,44,1,7.6044921875,7,45,1,7.50927734375,297,46,1,6.728515625,10,47,1,3.884765625,411,48,1,8.201171875,207,49,1,5.9541015625,206,50,1,7.3505859375,14,51,1,7.9091796875,416,52,1,7.75048828125,417,53,1,5.79541015625,206,54,1,7.3505859375,14,55,1,8.07421875,295,56,1,8.201171875,207,57,1,8.2900390625,205,58,1,8.201171875,207,59,1,8.201171875,418,60,1,7.1982421875,13,61,1,7.3505859375,14,62,1,7.9599609375,310,63,1,8.201171875,418,64,1,8.07421875,295,65,1,7.0712890625,13,66,1,6.91259765625,213,67,1,6.81103515625,12,68,1,7.9091796875,417,69,1,7.9091796875,416,70,1,8.201171875,207,71,1,4.484619140625,305,72,1,7.055419921875,13,73,1,7.3505859375,14,74,1,4.484619140625,305,75,1,7.055419921875,13,76,1,7.9091796875,416,77,1,7.76953125,212,78,1,4.627441406249943,305,79,1,7.76953125,212,80,1,8.1123046875,214,81,1,7.76953125,212,82,1,7.22998046875,213,83,1,8.10595703125,207,84,1,7.76953125,212,85,1,7.0966796875,12,86,1,7.76953125,212,87,1,7.76953125,212,88,1,7.9599609375,310,89,1,7.1982421875,13,90,1,8.201171875,418,91,1,8.2900390625,205,92,1,7.0966796875,12,93,1,4.484619140625,305,94,1,7.207763671875,14,95,1,7.9091796875,417,96,1,7.0966796875,12,97,1,7.2236328125,14,98,1,7.1982421875,213,99,1,7.73779296875,212,100,1,7.16650390625,13,101,1,8.2265625,419,102,1,7.73779296875,212,103,1,7.87744140625,416,104,1,7.9091796875,417,105,1,7.9599609375,310,106,1,7.67431640625,212,107,1,8.19482421875,205,108,1,7.9599609375,310,109,1,8.07421875,295,110,1,8.201171875,418,111,1,5.9541015625,206,112,1,3.884765625,411,113,1,9.8642578125,6,114,1,7.4775390625,7,115,1,4.875,8,116,1,6.982421875,9,117,1,3.884765625,411,118,1,6.728515625,10,119,1,4.46875,305,120,1,5.89697265625,296,121,1,3.2119140625,76,122,1,7.6044921875,7,123,1,7.1982421875,13,124,1,6.982421875,9,125,1,7.8583984375,11,126,1,3.884765625,411,127,1,7.0966796875,12,128,1,7.8583984375,11,129,1,7.8583984375,11,130,1,6.728515625,10,131,1,3.884765625,411,132,1,7.3505859375,14,133,1,7.73779296875,212,134,1,7.31884765625,14,135,1,6.0556640625,296,136,1,3.2119140625,76,137,1,7.6044921875,7,138,1,7.1982421875,13,139,1,7.0966796875,12,140,1,3.2119140625,76,141,1,3.884765625,411,142,1,7.3505859375,14,143,1,11.2353515625,80,144,1,7.9091796875,417,145,1,7.3505859375,14,146,1,4.65283203125,8,147,1,3.66259765625,411,148,1,6.69677734375,10,149,1,4.61474609375,82,150,1,7.0966796875,12,151,1,4.646484375,82,152,1,3.1357421875,77,153,1,7.6044921875,7,154,1,7.50927734375,297,155,1,3.884765625,411,156,1,4.598876953125,82,157,1,7.302978515625,14,158,1,6.69677734375,10,159,1,4.61474609375,82,160,1,3.884765625,411,161,1,4.5322265625,305,162,1,7.00146484375,12,163,1,6.82373046875,9,164,1,7.19189453125,14,165,1,3.884765625,411,166,1,7.9091796875,416,167,1,7.287109375,14,168,1,6.90625,437,169,1,3.1357421875,77,170,1,7.50927734375,297,171,1,13.075875486381392,357,172,1,12.89883268482481,349,173,1,12.89883268482481,408,174,1,12.89883268482481,309,175,1,3.580078125,-1,176,1,9.369140625,438,177,1,7.287109375,14,178,1,6.90625,437,179,1,3.1357421875,77,180,1,7.50927734375,297,181,1,3.580078125,-1,182,1,12.89883268482481,5,183,1,12.89883268482481,389,184,1,12.89883268482481,390,185,1,12.89883268482481,391,186,1,12.89883268482481,348,187,1,12.89883268482481,390,188,1,12.89883268482481,5,189,1,13.075875486381392,357,190,1,12.89883268482481,142,191,1,12.89883268482481,1,192,1,12.89883268482481,421,193,1,12.89883268482481,293,194,1,12.89883268482481,422,195,1,12.89883268482481,423,196,1,12.89883268482481,354,197,1,12.89883268482481,424,198,1,12.89883268482481,359,199,1,12.89883268482481,150,200,1,13.075875486381392,394,201,1,12.89883268482481,301,202,1,12.89883268482481,408,203,1,12.89883268482481,409,204,1,12.89883268482481,150]}}
  #|{"textrec":{"g":382,"r":[446,57,17,16,-1,-13,0]}}
  #|{"textrec":{"g":383,"r":[464,57,17,16,-1,-13,0]}}
  #|{"textrec":{"g":384,"r":[482,57,14,14,-1,-11,0]}}
  #|{"textrec":{"g":385,"r":[497,57,14,15,-1,-12,0]}}
  #|{"textrec":{"g":386,"r":[512,57,14,15,-1,-12,0]}}
  #|{"textrec":{"g":387,"r":[527,57,15,15,-1,-12,0]}}
  #|{"textrec":{"g":388,"r":[543,57,15,15,-1,-12,0]}}
  #|{"textrec":{"g":389,"r":[559,57,14,15,-1,-12,0]}}
  #|{"textrec":{"g":390,"r":[574,57,15,15,-1,-12,0]}}
  #|{"textrec":{"g":391,"r":[590,57,14,15,-1,-12,0]}}
  #|{"textrec":{"g":392,"r":[605,57,14,14,-1,-11,0]}}
  #|{"textrec":{"g":393,"r":[620,57,15,15,-1,-12,0]}}
  #|{"textrec":{"g":1,"r":[636,57,14,15,-1,-12,0]}}
  #|{"textrec":{"g":394,"r":[651,57,5,11,1,-9,0]}}
  #|{"textrec":{"g":395,"r":[657,57,15,15,-1,-12,0]}}
  #|{"textrec":{"g":396,"r":[673,57,15,14,-1,-12,0]}}
  #|{"textrec":{"g":397,"r":[689,57,15,15,-1,-12,0]}}
  #|{"textrec":{"g":398,"r":[705,57,15,15,-1,-12,0]}}
  #|{"textrec":{"g":399,"r":[721,57,15,15,-1,-12,0]}}
  #|{"textrec":{"g":400,"r":[737,57,14,15,-1,-12,0]}}
  #|{"textrec":{"g":401,"r":[752,57,7,11,-1.1666666666666634,-12,0]}}
  #|{"textrec":{"g":402,"r":[760,57,7,11,-1,-8,0]}}
  #|{"textrec":{"g":403,"r":[768,57,14,14,5.5,-12,0]}}
  #|{"textrec":{"g":404,"r":[783,57,15,15,-1,-12,0]}}
  #|{"textrec":{"s":[17,700,0,"Agent 环境变量"],"r":[0,1,11.7705078125,439,1,1,10.288818359375,440,2,1,9.782470703125,441,3,1,10.230712890625,442,4,1,6.58251953125,443,5,1,3.951171875,-1,6,1,16.851167315175104,444,7,1,16.851167315175104,445,8,1,16.851167315175104,446,9,1,16.851167315175104,447]}}
  #|{"textrec":{"m":[17,700,0],"r":[16.435546875,3.5859375,24,16.435546875,3.5859375,0]}}
  #|{"textrec":{"s":[12,400,0,"此 station 启动的 agent、登录和任务都会加载这些变量，常用于设置 HTTP 代理。每行一个「变量名=值」，可直接粘贴 .env 内容，打码的值保持原样即不修改。Profile 中的同名变量优先。保存后，空闲的 agent 进程会重新启动，运行中的在本轮结束后生效。"],"r":[0,1,11.918287937743191,448,1,1,3.375,-1,2,1,6.251953125,449,3,1,4.330078125,450,4,1,6.6210937499999964,451,5,1,4.359375,450,6,1,2.96484375,452,7,1,7.08984375,453,8,1,7.001953125,454,9,1,3.375,-1,10,1,11.918287937743187,455,11,1,11.918287937743187,456,12,1,11.918287937743187,457,13,1,3.375,-1,14,1,6.62109375,451,15,1,7.3125,458,16,1,6.85546875,459,17,1,7.001953125,454,18,1,4.359375,450,19,1,12.081712062256798,460,20,1,11.918287937743202,461,21,1,11.918287937743202,462,22,1,11.918287937743202,463,23,1,11.918287937743202,464,24,1,11.918287937743202,465,25,1,11.918287937743202,466,26,1,11.918287937743202,467,27,1,11.918287937743202,468,28,1,11.918287937743202,271,29,1,11.918287937743173,469,30,1,11.918287937743173,470,31,1,11.918287937743173,471,32,1,11.918287937743173,472,33,1,12.081712062256827,473,34,1,11.918287937743173,474,35,1,11.918287937743173,475,36,1,11.918287937743173,476,37,1,11.918287937743173,477,38,1,11.918287937743173,478,39,1,3.375,-1,40,1,8.90625,479,41,1,7.60546875,480,42,1,7.60546875,480,43,1,7.623046875,481,44,1,3.375,-1,45,1,11.918287937743173,482,46,1,11.918287937743173,483,47,1,12.081712062256827,484,48,1,11.918287937743173,485,49,1,11.918287937743173,486,50,1,11.918287937743173,487,51,1,17.918287937743173,488,52,1,4.3540856031128214,489,53,1,11.918287937743173,471,54,1,11.918287937743173,472,55,1,11.91828793774323,490,56,1,7.55859375,491,57,1,11.91828793774323,492,58,1,5.608949416342398,493,59,1,12.08171206225677,473,60,1,11.91828793774323,494,61,1,11.91828793774323,495,62,1,11.91828793774323,496,63,1,11.91828793774323,497,64,1,11.91828793774323,498,65,1,3.375,-1,66,1,3.4453125,273,67,1,6.73828125,459,68,1,6.884765625,454,69,1,6.38671875,499,70,1,3.375,-1,71,1,11.91828793774323,500,72,1,11.91828793774323,501,73,1,12.08171206225677,473,74,1,11.91828793774323,502,75,1,11.91828793774323,503,76,1,11.91828793774323,457,77,1,11.91828793774323,492,78,1,11.91828793774323,504,79,1,11.91828793774323,505,80,1,11.91828793774323,506,81,1,11.91828793774323,507,82,1,11.91828793774323,508,83,1,11.91828793774323,509,84,1,11.91828793774323,510,85,1,11.91828793774323,511,86,1,12.08171206225677,484,87,1,7.623046875,481,88,1,4.482421875,512,89,1,7.001953125,453,90,1,4.341796875,513,91,1,2.96484375,452,92,1,3.03515625,514,93,1,6.85546875,459,94,1,3.375,-1,95,1,11.91828793774323,515,96,1,11.91828793774323,457,97,1,11.91828793774323,516,98,1,11.91828793774323,490,99,1,11.91828793774323,471,100,1,11.91828793774323,472,101,1,11.91828793774323,517,102,1,11.91828793774323,518,103,1,12.08171206225677,484,104,1,11.91828793774323,504,105,1,11.918287937743116,519,106,1,11.918287937743116,520,107,1,12.081712062256884,473,108,1,11.918287937743116,521,109,1,11.918287937743116,522,110,1,11.918287937743116,457,111,1,3.375,-1,112,1,6.62109375,451,113,1,7.3125,458,114,1,6.85546875,459,115,1,7.001953125,454,116,1,4.359375,450,117,1,3.375,-1,118,1,11.918287937743116,523,119,1,11.918287937743116,524,120,1,11.918287937743116,467,121,1,11.918287937743116,525,122,1,11.918287937743116,526,123,1,11.918287937743116,455,124,1,11.918287937743116,456,125,1,12.081712062256884,473,126,1,11.918287937743116,527,127,1,11.918287937743116,486,128,1,11.918287937743116,515,129,1,11.918287937743116,457,130,1,11.918287937743116,528,131,1,11.918287937743116,529,132,1,11.918287937743116,530,133,1,11.918287937743116,531,134,1,11.918287937743116,532,135,1,11.918287937743116,520,136,1,11.918287937743116,533,137,1,11.918287937743116,534,138,1,6.081712062256884,484]}}
  #|{"textrec":{"s":[14,600,0,"取消"],"r":[0,1,13.891050583657588,535,1,1,13.891050583657588,536]}}
  #|{"textrec":{"m":[14,600,0],"r":[13.53515625,2.953125,20,13.53515625,2.953125,0]}}
  #|{"textrec":{"s":[14,600,0,"保存"],"r":[0,1,13.891050583657588,537,1,1,13.891050583657588,538]}}
  #|{"textrec":{"g":439,"r":[799,57,14,14,-1,-13,0]}}
  #|{"textrec":{"g":440,"r":[814,57,12,16,-1,-11,0]}}
  #|{"textrec":{"g":441,"r":[827,57,12,13,-1,-11,0]}}
  #|{"textrec":{"g":442,"r":[840,57,11,12,0,-11,0]}}
  #|{"textrec":{"g":443,"r":[852,57,9,15,-1,-13,0]}}
  #|{"textrec":{"g":444,"r":[862,57,18,18,-1,-15,0]}}
  #|{"textrec":{"g":445,"r":[881,57,19,18,-1,-15,0]}}
  #|{"textrec":{"g":446,"r":[901,57,18,18,-1,-15,0]}}
  #|{"textrec":{"g":447,"r":[920,57,18,18,-1,-15,0]}}
  #|{"textrec":{"g":448,"r":[939,57,14,13,-1,-11,0]}}
  #|{"textrec":{"g":449,"r":[954,57,8,10,-1,-8,0]}}
  #|{"textrec":{"g":450,"r":[963,57,6,11,-1,-9,0]}}
  #|{"textrec":{"g":451,"r":[970,57,8,10,-1,-8,0]}}
  #|{"textrec":{"g":452,"r":[979,57,5,11,-1,-10,0]}}
  #|{"textrec":{"g":453,"r":[985,57,9,10,-1,-8,0]}}
  #|{"textrec":{"g":454,"r":[995,57,9,9,-1,-8,0]}}
  #|{"textrec":{"g":455,"r":[1005,57,13,14,-1,-11,0]}}
  #|{"textrec":{"g":456,"r":[1019,57,13,14,-1,-11,0]}}
  #|{"textrec":{"g":457,"r":[1033,57,13,14,-1,-11,0]}}
  #|{"textrec":{"g":458,"r":[1047,57,9,12,-1,-8,0]}}
  #|{"textrec":{"g":459,"r":[1057,57,9,10,-1,-8,0]}}
  #|{"textrec":{"g":460,"r":[1067,57,6,6,0,-3,0]}}
  #|{"textrec":{"g":461,"r":[1074,57,14,13,-1,-11,0]}}
  #|{"textrec":{"g":462,"r":[1089,57,13,14,-1,-11,0]}}
  #|{"textrec":{"g":463,"r":[1103,57,13,14,-1,-11,0]}}
  #|{"textrec":{"g":464,"r":[1117,57,14,14,-1,-11,0]}}
  #|{"textrec":{"g":465,"r":[1132,57,14,14,-1,-11,0]}}
  #|{"textrec":{"g":466,"r":[1147,57,13,14,-1,-11,0]}}
  #|{"textrec":{"g":467,"r":[1161,57,14,14,-1,-11,0]}}
  #|{"textrec":{"g":468,"r":[1176,57,13,14,-1,-11,0]}}
  #|{"textrec":{"g":469,"r":[1190,57,14,14,-1,-11,0]}}
  #|{"textrec":{"g":470,"r":[1205,57,14,13,-1,-11,0]}}
  #|{"textrec":{"g":471,"r":[1220,57,14,14,-1,-11,0]}}
  #|{"textrec":{"g":472,"r":[1235,57,14,13,-1,-11,0]}}
  #|{"textrec":{"g":473,"r":[1250,57,5,6,0,-3,0]}}
  #|{"textrec":{"g":474,"r":[1256,57,13,14,-1,-11,0]}}
  #|{"textrec":{"g":475,"r":[1270,57,13,14,-1,-11,0]}}
  #|{"textrec":{"g":476,"r":[1284,57,13,14,-1,-11,0]}}
  #|{"textrec":{"g":477,"r":[1298,57,14,14,-1,-11,0]}}
  #|{"textrec":{"g":478,"r":[1313,57,14,13,-1,-11,0]}}
  #|{"textrec":{"g":479,"r":[1328,57,9,11,0,-10,0]}}
  #|{"textrec":{"g":480,"r":[1338,57,10,11,-1,-10,0]}}
  #|{"textrec":{"g":481,"r":[1349,57,8,11,0,-10,0]}}
  #|{"textrec":{"g":482,"r":[1358,57,14,14,-1,-11,0]}}
  #|{"textrec":{"g":483,"r":[1373,57,14,13,-1,-11,0]}}
  #|{"textrec":{"g":484,"r":[1388,57,6,6,0,-3,0]}}
  #|{"textrec":{"g":485,"r":[1395,57,14,14,-1,-11,0]}}
  #|{"textrec":{"g":486,"r":[1410,57,14,14,-1,-11,0]}}
  #|{"textrec":{"g":487,"r":[1425,57,14,4,-1,-6,0]}}
  #|{"textrec":{"g":488,"r":[1440,57,14,14,-1,-11,0]}}
  #|{"textrec":{"g":489,"r":[1455,57,6,10,-0.9999999999999796,-11,0]}}
  #|{"textrec":{"g":490,"r":[1462,57,13,14,-1,-11,0]}}
  #|{"textrec":{"g":491,"r":[1476,57,9,7,-1,-7,0]}}
  #|{"textrec":{"g":492,"r":[1486,57,14,14,-1,-11,0]}}
  #|{"textrec":{"g":493,"r":[1501,57,7,10,-1,-7,0]}}
  #|{"textrec":{"g":494,"r":[1509,57,14,13,-1,-10,0]}}
  #|{"textrec":{"g":495,"r":[1524,57,14,13,-1,-11,0]}}
  #|{"textrec":{"g":496,"r":[1539,57,14,14,-1,-11,0]}}
  #|{"textrec":{"g":497,"r":[1554,57,14,14,-1,-11,0]}}
  #|{"textrec":{"g":498,"r":[1569,57,14,14,-1,-11,0]}}
  #|{"textrec":{"g":499,"r":[1584,57,9,9,-1,-8,0]}}
  #|{"textrec":{"g":500,"r":[1594,57,12,14,0,-11,0]}}
  #|{"textrec":{"g":501,"r":[1607,57,14,14,-1,-11,0]}}
  #|{"textrec":{"g":502,"r":[1622,57,14,14,-1,-11,0]}}
  #|{"textrec":{"g":503,"r":[1637,57,13,14,-1,-11,0]}}
  #|{"textrec":{"g":504,"r":[1651,57,14,14,-1,-11,0]}}
  #|{"textrec":{"g":505,"r":[1666,57,14,14,-1,-11,0]}}
  #|{"textrec":{"g":506,"r":[1681,57,13,14,-1,-11,0]}}
  #|{"textrec":{"g":507,"r":[1695,57,14,14,-1,-11,0]}}
  #|{"textrec":{"g":508,"r":[1710,57,13,14,-1,-11,0]}}
  #|{"textrec":{"g":509,"r":[1724,57,14,13,-1,-10,0]}}
  #|{"textrec":{"g":510,"r":[1739,57,14,14,-1,-11,0]}}
  #|{"textrec":{"g":511,"r":[1754,57,14,14,-1,-11,0]}}
  #|{"textrec":{"g":512,"r":[1769,57,7,9,-1,-8,0]}}
  #|{"textrec":{"g":513,"r":[1777,57,6,11,-1,-10,0]}}
  #|{"textrec":{"g":514,"r":[1784,57,4,11,0,-10,0]}}
  #|{"textrec":{"g":515,"r":[1789,57,12,14,0,-11,0]}}
  #|{"textrec":{"g":516,"r":[1802,57,12,14,0,-11,0]}}
  #|{"textrec":{"g":517,"r":[1815,57,14,14,-1,-11,0]}}
  #|{"textrec":{"g":518,"r":[1830,57,14,14,-1,-11,0]}}
  #|{"textrec":{"g":519,"r":[1845,57,14,14,-1,-11,0]}}
  #|{"textrec":{"g":520,"r":[1860,57,14,14,-1,-11,0]}}
  #|{"textrec":{"g":521,"r":[1875,57,13,13,-1,-11,0]}}
  #|{"textrec":{"g":522,"r":[1889,57,12,14,0,-11,0]}}
  #|{"textrec":{"g":523,"r":[1902,57,14,14,-1,-11,0]}}
  #|{"textrec":{"g":524,"r":[1917,57,14,14,-1,-11,0]}}
  #|{"textrec":{"g":525,"r":[1932,57,14,13,-1,-11,0]}}
  #|{"textrec":{"g":526,"r":[1947,57,14,14,-1,-11,0]}}
  #|{"textrec":{"g":527,"r":[1962,57,14,14,-1,-11,0]}}
  #|{"textrec":{"g":528,"r":[1977,57,14,14,-1,-11,0]}}
  #|{"textrec":{"g":529,"r":[1992,57,14,14,-1,-11,0]}}
  #|{"textrec":{"g":530,"r":[2007,57,14,14,-1,-11,0]}}
  #|{"textrec":{"g":531,"r":[2022,57,14,14,-1,-11,0]}}
  #|{"textrec":{"g":532,"r":[0,76,14,14,-1,-11,0]}}
  #|{"textrec":{"g":533,"r":[15,76,14,13,-1,-11,0]}}
  #|{"textrec":{"g":534,"r":[30,76,14,14,-1,-11,0]}}
  #|{"textrec":{"s":[13,400,0,"HTTPS_PROXY=http://127.0.0.1:7890\nNO_PROXY=localhost,.internal"],"r":[0,1,9.572265625,420,1,1,8.1630859375,539,2,1,8.1630859375,539,3,1,8.18212890625,540,4,1,8.20751953125,211,5,1,7.50927734375,541,6,1,8.18212890625,540,7,1,8.4169921875,542,8,1,9.79443359375,210,9,1,8.58837890625,543,10,1,7.83935546875,544,11,1,7.50927734375,545,12,1,7.57275390625,433,13,1,4.646484375,82,14,1,4.646484375,82,15,1,7.8583984375,11,16,1,3.783203125,546,17,1,3.884765625,411,18,1,3.884765625,411,19,1,5.9541015625,206,20,1,7.76953125,212,21,1,6.626953125,213,22,1,2.8310546875,81,23,1,7.6044921875,214,24,1,3.275390625,81,25,1,7.6044921875,214,26,1,3.3388671875,81,27,1,5.763671875,206,28,1,3.7197265625,546,29,1,7.16650390625,213,30,1,8.13134765625,419,31,1,8.201171875,418,32,1,8.1123046875,214,33,1,0,-1,34,1,9.572265625,547,35,1,9.66748046875,210,36,1,7.2236328125,541,37,1,8.18212890625,540,38,1,8.4169921875,542,39,1,9.79443359375,210,40,1,8.58837890625,543,41,1,7.83935546875,544,42,1,7.50927734375,545,43,1,3.2119140625,76,44,1,7.6044921875,7,45,1,7.1982421875,13,46,1,7.0966796875,12,47,1,3.2119140625,76,48,1,7.57275390625,433,49,1,7.6044921875,7,50,1,6.69677734375,10,51,1,4.61474609375,82,52,1,3.783203125,548,53,1,3.783203125,81,54,1,3.1357421875,77,55,1,7.50927734375,297,56,1,4.598876953125,82,57,1,7.302978515625,14,58,1,4.9384765625,8,59,1,7.57275390625,297,60,1,7.0966796875,12,61,1,3.2119140625,76]}}
  #|{"textrec":{"g":420,"r":[45,76,10,12,0,-11,0]}}
  #|{"textrec":{"g":539,"r":[56,76,10,12,-1,-11,0]}}
  #|{"textrec":{"g":540,"r":[67,76,9,12,0,-11,0]}}
  #|{"textrec":{"g":541,"r":[77,76,10,4,-1,-1,0]}}
  #|{"textrec":{"g":542,"r":[88,76,9,12,0,-11,0]}}
  #|{"textrec":{"g":543,"r":[98,76,11,12,-1,-11,0]}}
  #|{"textrec":{"g":544,"r":[110,76,11,12,-1,-11,0]}}
  #|{"textrec":{"g":545,"r":[122,76,10,7,-1,-7,0]}}
  #|{"textrec":{"g":433,"r":[133,76,8,12,0,-11,0]}}
  #|{"textrec":{"g":546,"r":[142,76,4,10,0,-8,0]}}
  #|{"textrec":{"g":411,"r":[147,76,6,15,-1,-11,0]}}
  #|{"textrec":{"g":419,"r":[154,76,10,13,-1,-11,0]}}
  #|{"textrec":{"g":418,"r":[165,76,10,13,-1,-11,0]}}
  #|{"textrec":{"g":547,"r":[176,76,10,12,0,-11,0]}}
  #|{"textrec":{"g":548,"r":[187,76,5,7,-1,-3,0]}}
  #|{"textrec":{"g":535,"r":[193,76,16,15,-1,-12,0]}}
  #|{"textrec":{"g":536,"r":[210,76,15,16,-1,-13,0]}}
  #|{"textrec":{"g":537,"r":[226,76,16,16,-1,-13,0]}}
  #|{"textrec":{"g":538,"r":[243,76,16,16,-1,-13,0]}}
  #|{"textrec":{"s":[13,400,0,"E2E_PROXY_080726=http://127.0.0.1:9"],"r":[0,1,7.66796875,549,1,1,7.76953125,212,2,1,7.66796875,549,3,1,7.50927734375,541,4,1,8.18212890625,540,5,1,8.4169921875,542,6,1,9.79443359375,210,7,1,8.58837890625,543,8,1,7.87109375,544,9,1,6.62060546875,541,10,1,7.794921875,214,11,1,8.2265625,419,12,1,7.9853515625,214,13,1,7.1982421875,213,14,1,7.76953125,212,15,1,8.201171875,207,16,1,8.1123046875,545,17,1,7.57275390625,433,18,1,4.646484375,82,19,1,4.646484375,82,20,1,7.8583984375,11,21,1,3.783203125,546,22,1,3.884765625,411,23,1,3.884765625,411,24,1,5.9541015625,206,25,1,7.76953125,212,26,1,6.626953125,213,27,1,2.8310546875,81,28,1,7.6044921875,214,29,1,3.275390625,81,30,1,7.6044921875,214,31,1,3.3388671875,81,32,1,5.763671875,206,33,1,3.783203125,546,34,1,8.201171875,418]}}
  #|{"textrec":{"g":549,"r":[260,76,8,12,0,-11,0]}}
  #|{"textrec":{"s":[14,400,0,"已保存"],"r":[0,1,13.891050583657588,550,1,1,13.891050583657588,551,2,1,13.891050583657588,552]}}
  #|{"textrec":{"s":[15,400,2,"E2E_PROXY_080726"],"r":[0,1,9,553,1,1,9,554,2,1,9,553,3,1,9,555,4,1,9,556,5,1,9,557,6,1,9,558,7,1,9,559,8,1,9,560,9,1,9,555,10,1,9,561,11,1,9,562,12,1,9,561,13,1,9,563,14,1,9,554,15,1,9,564]}}
  #|{"textrec":{"m":[15,400,2],"r":[15.300064086914062,4.5000457763671875,21,15.900032222270966,5.100010335445404,0]}}
  #|{"textrec":{"s":[13,400,2,"http://127.0.0.1:9"],"r":[0,1,7.8,565,1,1,7.8,566,2,1,7.8,566,3,1,7.8,567,4,1,7.8,568,5,1,7.8,569,6,1,7.8,569,7,1,7.8,570,8,1,7.8,571,9,1,7.8,572,10,1,7.8,573,11,1,7.8,574,12,1,7.8,573,13,1,7.8,574,14,1,7.8,573,15,1,7.8,570,16,1,7.8,568,17,1,7.8,575]}}
  #|{"textrec":{"m":[13,400,2],"r":[13.260055541992188,3.9000396728515625,18,13.78002792596817,4.420008957386017,0]}}
  #|{"textrec":{"g":553,"r":[269,76,9,13,0,-12,0]}}
  #|{"textrec":{"g":554,"r":[279,76,9,14,0,-13,0]}}
  #|{"textrec":{"g":555,"r":[289,76,11,4,-1,-1,0]}}
  #|{"textrec":{"g":556,"r":[301,76,10,13,0,-12,0]}}
  #|{"textrec":{"g":557,"r":[312,76,10,13,0,-12,0]}}
  #|{"textrec":{"g":558,"r":[323,76,9,15,0,-13,0]}}
  #|{"textrec":{"g":559,"r":[333,76,11,13,-1,-12,0]}}
  #|{"textrec":{"g":560,"r":[345,76,11,13,-1,-12,0]}}
  #|{"textrec":{"g":561,"r":[357,76,9,15,0,-13,0]}}
  #|{"textrec":{"g":562,"r":[367,76,11,15,-1,-13,0]}}
  #|{"textrec":{"g":563,"r":[379,76,10,13,0,-12,0]}}
  #|{"textrec":{"g":564,"r":[390,76,11,14,-1,-12,0]}}
  #|{"textrec":{"g":565,"r":[402,76,8,12,0,-11,0]}}
  #|{"textrec":{"g":566,"r":[411,76,9,12,-1,-11,0]}}
  #|{"textrec":{"g":567,"r":[421,76,8,13,0,-9,0]}}
  #|{"textrec":{"g":568,"r":[430,76,5,11,1,-9,0]}}
  #|{"textrec":{"g":569,"r":[436,76,9,15,-1,-12,0]}}
  #|{"textrec":{"g":570,"r":[446,76,9,12,0,-11,0]}}
  #|{"textrec":{"g":571,"r":[456,76,9,12,-1,-11,0]}}
  #|{"textrec":{"g":572,"r":[466,76,9,12,0,-11,0]}}
  #|{"textrec":{"g":573,"r":[476,76,5,5,1,-3,0]}}
  #|{"textrec":{"g":574,"r":[482,76,8,13,0,-11,0]}}
  #|{"textrec":{"g":575,"r":[491,76,9,12,-1,-11,0]}}
  #|{"textrec":{"g":550,"r":[501,76,14,14,0,-12,0]}}
  #|{"textrec":{"g":551,"r":[516,76,16,16,-1,-13,0]}}
  #|{"textrec":{"g":552,"r":[533,76,15,16,-1,-13,0]}}
  #|{"textrec":{"g":405,"r":[549,76,12,14,-1,-12,0]}}
  #|{"textrec":{"g":163,"r":[562,76,9,11,0,-9,0]}}
  #|{"textrec":{"g":406,"r":[572,76,10,15,-1,-13,0]}}
  #|{"textrec":{"g":407,"r":[583,76,15,15,-1,-12,0]}}
  #|{"textrec":{"g":155,"r":[599,76,14,14,-1,-12,0]}}
  #|{"textrec":{"g":408,"r":[614,76,14,14,-1,-11,0]}}
  #|{"textrec":{"g":409,"r":[629,76,14,14,-1,-11,0]}}
  #|{"textrec":{"g":410,"r":[644,76,10,10,-1,-9,0]}}
  #|{"textrec":{"g":412,"r":[655,76,10,13,0,-11,0]}}
  #|{"textrec":{"g":413,"r":[666,76,9,9,-1,-8,0]}}
  #|{"textrec":{"g":414,"r":[676,76,9,10,-1,-8,0]}}
  #|{"textrec":{"g":415,"r":[686,76,6,15,-2,-11,0]}}
  #|{"textrec":{"g":416,"r":[693,76,9,13,-1,-11,0]}}
  #|{"textrec":{"g":417,"r":[703,76,9,13,0,-11,0]}}
  #|{"textrec":{"g":148,"r":[713,76,15,15,-1,-12,0]}}
  #|{"textrec":{"g":142,"r":[729,76,14,14,-1,-11,0]}}
  #|{"textrec":{"g":421,"r":[744,76,15,15,-1,-12,0]}}
  #|{"textrec":{"g":422,"r":[760,76,15,14,-1,-11,0]}}
  #|{"textrec":{"g":423,"r":[776,76,14,14,-1,-12,0]}}
  #|{"textrec":{"g":424,"r":[791,76,14,15,-1,-12,0]}}
  #|{"textrec":{"g":431,"r":[806,76,11,13,0,-12,0]}}
  #|{"textrec":{"g":432,"r":[818,76,11,13,0,-12,0]}}
  #|{"textrec":{"g":223,"r":[830,76,10,13,-1,-11,0]}}
  #|{"textrec":{"g":425,"r":[841,76,4,5,0,-3,0]}}
  #|{"textrec":{"g":426,"r":[846,76,10,12,-1,-11,0]}}
  #|{"textrec":{"g":427,"r":[857,76,7,12,-1,-11,0]}}
  #|{"textrec":{"g":428,"r":[865,76,8,4,-1,-6,0]}}
  #|{"textrec":{"g":429,"r":[874,76,7,10,-1,-9,0]}}
  #|{"textrec":{"g":430,"r":[882,76,9,11,-1,-9,0]}}
  #|{"textrec":{"g":434,"r":[892,76,13,14,-1,-12,0]}}
  #|{"textrec":{"g":435,"r":[906,76,11,13,0,-12,0]}}
  #|{"textrec":{"g":436,"r":[918,76,10,10,-1,-9,0]}}
  #|{"textrec":{"ib":["74432b445e567838",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"g":437,"r":[929,76,9,9,-1,-8,0]}}
  #|{"textrec":{"g":438,"r":[939,76,10,12,0,-11,0]}}
  #|{"textrec":{"g":156,"r":[950,76,17,16,-1,-13,0]}}
  #|{"textrec":{"g":157,"r":[968,76,16,16,-1,-13,0]}}
  #|{"textrec":{"g":158,"r":[985,76,17,16,-1,-13,0]}}
  #|{"textrec":{"g":159,"r":[1003,76,17,17,-1,-14,0]}}
