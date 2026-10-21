// e2e/traces/drive-play.trace, made by scripts/trace.py from 02-drive_play.log: not edited by hand.

///|
/// What the app and its core said in the run, a line each.
pub let trace_drive_play : String =
  #|{"step":"drive-media 105609"}
  #|{"env":{"MBUI_CLOUD":"http://127.0.0.1:18787","MBUI_CORE_ACCOUNT":"{\"sub\":\"alice\",\"email\":\"alice@example.test\",\"name\":\"Name of alice\",\"picture\":\"\",\"access\":\"-\",\"refresh\":\"-\",\"accessExpires\":1792593275}"}}
  #|{"out":{"id":1,"call":"client.device","params":{"client":"still.fail mbui","app":"desktop","userAgent":"Macintosh; Mac OS X"}},"w":1792592978417.391}
  #|{"in":{"id":1,"ok":null},"w":1792592978494.634}
  #|{"out":{"id":2,"subscribe":{"topic":"accounts"},"keyed":true},"w":1792592978494.659}
  #|{"out":{"id":3,"subscribe":{"topic":"prefs"},"keyed":true},"w":1792592978494.669}
  #|{"step":"# written by scripts/rerecord.sh from its test (src/sfreplay/emit.mbt): not edited by hand","w":1792592978496.076}
  #|{"step":"timeout 90000","w":1792592978496.081}
  #|{"step":"answered client.device","w":1792592978496.084}
  #|{"step":"answered client.focus","w":1792592978522.563}
  #|{"in":{"id":2,"value":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""}]},"w":1792592978588.598}
  #|{"in":{"id":3,"value":{"onlyMine":false,"onlyWatching":false,"onlyDecisions":false,"listFilter":{},"appearance":"system","rowPicture":"auto","absoluteTime":false,"lang":"zh","keys":{},"lastChat":{},"openChat":{},"chatTabs":{},"dropFiles":{},"driveViews":{},"resume":{},"stationUpdatesDismissed":{},"device":{"app":"desktop","phone":false,"handoff":false},"reader":{"size":18,"line":1.7,"margin":22,"face":"sans","indent":true,"paper":"follow"},"rails":{},"bars":{"sets":[["chats","files","profiles","stations"],["decisions","usage","connects","archive"]],"current":0},"barsBy":{},"fonts":{},"faces":{"ui":{"id":"","name":"","mono":false,"family":"","files":[],"bytes":0},"text":{"id":"","name":"","mono":false,"family":"","files":[],"bytes":0},"code":{"id":"","name":"","mono":true,"family":"","files":[],"bytes":0},"list":[{"id":"inter","name":"Inter","mono":false,"family":"SF Inter","css":"http://127.0.0.1:18787/releases/fonts/inter/4.001/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/inter/4.001/var.ttf.gz","bytes":457818,"sha256":"29160a80ff49ddcab2c97711247e08b1fab27a484a329ce8b813d820dc559031"}],"preview":"http://127.0.0.1:18787/releases/fonts/inter/4.001/preview-194fa287.ttf","bytes":457818},{"id":"noto-sans-sc","name":"思源黑体","mono":false,"family":"SF Noto Sans SC","css":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/var.ttf.gz","bytes":11276563,"sha256":"a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da"}],"preview":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/preview-f0494178.ttf","bytes":11276563},{"id":"noto-serif-sc","name":"思源宋体","mono":false,"family":"SF Noto Serif SC","css":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/var.ttf.gz","bytes":15454579,"sha256":"050080d9255a86808f2945bffac582b31ef32bc36411ce29563b4961670c66f9"}],"preview":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/preview-001bbedf.ttf","bytes":15454579},{"id":"lxgw-wenkai","name":"霞鹜文楷","mono":false,"family":"SF LXGW WenKai","css":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/font.css","files":[{"weight":400,"url":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/400.ttf.gz","bytes":12904482,"sha256":"2d73eea94ad808999d90c0000c239a84a33b09d4bc6ab6c5b8bbf1eda8a7fc8b"},{"weight":500,"url":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/500.ttf.gz","bytes":13272430,"sha256":"f4b8a34d1f838fe411540cb7c97b1c384ac9738a876c4104500bc42508b2312a"}],"preview":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/preview-d3505af4.ttf","bytes":26176912},{"id":"jetbrains-mono","name":"JetBrains Mono","mono":true,"family":"SF JetBrains Mono","css":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/var.ttf.gz","bytes":90579,"sha256":"48715a42ec242c21e9f02692891e147d022299a52e48d5e413e1a942193ffeda"}],"preview":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/preview-ee73078f.ttf","bytes":90579},{"id":"fira-code","name":"Fira Code","mono":true,"family":"SF Fira Code","css":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/var.ttf.gz","bytes":137151,"sha256":"9335b082b3c7850d98a64b584f3417f65355f3471278bb5eeb8c6c0e8657aeeb"}],"preview":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/preview-555be27a.ttf","bytes":137151},{"id":"maple-mono","name":"Maple Mono","mono":true,"family":"SF Maple Mono CN","css":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/font.css","files":[{"weight":400,"url":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/400.ttf.gz","bytes":8352545,"sha256":"0fcc5139bfd5ab14ff989bb7dfd5236d0cafc10e60b9828569e6883613ab4085"},{"weight":600,"url":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/600.ttf.gz","bytes":8438132,"sha256":"96ed7ae26ee7c50b02b2d2b2bc0f1a0cbabe45ae5d6e6abf6678e2177c415677"}],"preview":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/preview-cffdf246.ttf","bytes":16790677}]}}},"w":1792592978588.642}
  #|{"out":{"id":4,"subscribe":{"topic":"workspaces"},"keyed":true},"w":1792592978588.691}
  #|{"out":{"id":5,"subscribe":{"topic":"status"},"keyed":true},"w":1792592978588.7}
  #|{"in":{"id":4,"value":[{"account":{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""},"workspaces":[{"id":"01M5FDW1FW86V3FFXE2V16Z744","name":"Dev","role":"owner","created_at":1792592971,"stations":1,"members":1,"relays":[],"time":{"created_at":{"past":true,"at":1792592971000,"ago":"刚刚","full":"10/21 22:29:31","until":"1 分钟内"}}}],"invitations":[],"relay_url":"http://127.0.0.1:18740","loaded":true,"beta":true}]},"w":1792592978605.275}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792592978605.392}
  #|{"out":{"id":6,"subscribe":{"topic":"lock","workspace":"01M5FDW1FW86V3FFXE2V16Z744"},"keyed":true},"w":1792592978605.427}
  #|{"out":{"id":7,"subscribe":{"topic":"chats","scope":"01M5FDW1FW86V3FFXE2V16Z744","mine":false},"keyed":true},"w":1792592978605.448}
  #|{"out":{"id":8,"subscribe":{"topic":"changelog"},"keyed":true},"w":1792592978605.457}
  #|{"out":{"id":9,"subscribe":{"topic":"workspaceMarks","workspace":"01M5FDW1FW86V3FFXE2V16Z744"},"keyed":true},"w":1792592978605.586}
  #|{"out":{"id":10,"subscribe":{"topic":"stations","scope":"01M5FDW1FW86V3FFXE2V16Z744"},"keyed":true},"w":1792592978605.608}
  #|{"out":{"id":11,"subscribe":{"topic":"workspace","workspace":"01M5FDW1FW86V3FFXE2V16Z744"},"keyed":true},"w":1792592978605.612}
  #|{"out":{"id":12,"subscribe":{"topic":"status","workspace":"01M5FDW1FW86V3FFXE2V16Z744"},"keyed":true},"w":1792592978605.677}
  #|{"out":{"id":13,"subscribe":{"topic":"lockPrompts"},"keyed":true},"w":1792592978605.706}
  #|{"out":{"id":14,"call":"client.focus","params":{"visible":true,"focused":true,"workspace":"01M5FDW1FW86V3FFXE2V16Z744"}},"w":1792592978608.834}
  #|{"out":{"id":15,"subscribe":{"topic":"notify"},"keyed":true},"w":1792592978608.843}
  #|{"out":{"id":16,"subscribe":{"topic":"notify","workspace":"01M5FDW1FW86V3FFXE2V16Z744"},"keyed":true},"w":1792592978608.851}
  #|{"in":{"id":6,"value":{"available":true,"locked":false,"notice":true,"role":"owner","manages":true,"owner":true,"canSign":true,"signs":false,"me":{"device":"b1f916167a90c4e4164de95952b631cbbcd46a5dc864a223da0917697bd1d126","code":"BGQ-Q8D","kind":"app","confirmed":false,"waiting":false,"asked":false},"signers":0,"members":[],"stations":[{"id":"022644157b6993d24e2ad3d221f5a5bcbf5e81ba0df87f71239a029ac2bd4b2c","name":"studio","version":"0.1.0","online":true,"protected":false}],"protected":0,"requests":[],"renew":[],"attention":0}},"w":1792592978624.614}
  #|{"in":{"id":11,"value":{"id":"01M5FDW1FW86V3FFXE2V16Z744","name":"Dev","role":"owner","created_at":1792592971,"members":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":"https://example.test/p.png","role":"owner","added_at":1792592971}],"stations":[{"id":"022644157b6993d24e2ad3d221f5a5bcbf5e81ba0df87f71239a029ac2bd4b2c","name":"studio","emoji":null,"icon":null,"enrolled_at":1792592971,"enrolled_by":"alice","last_seen":1792592975,"version":"0.1.0","time":{"last_seen":{"past":true,"at":1792592975000,"ago":"刚刚","full":"10/21 22:29:35","until":"1 分钟内"}}}],"invitations":[],"added":[],"relays":[],"lock":null,"lock_requests":0,"time":{"created_at":{"past":true,"at":1792592971000,"ago":"刚刚","full":"10/21 22:29:31","until":"1 分钟内"}}}},"w":1792592978624.637}
  #|{"in":{"id":7,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"stations":[{"station":"01M5FDW1FW86V3FFXE2V16Z744/022644157b6993d24e2ad3d221f5a5bcbf5e81ba0df87f71239a029ac2bd4b2c","id":"022644157b6993d24e2ad3d221f5a5bcbf5e81ba0df87f71239a029ac2bd4b2c","name":"studio","state":"online"}],"loading":false,"days":[{"daysAgo":0,"at":1792592975203,"label":"今天","items":[{"id":"ember:c-4e06bfe5d4","session":"ember:c-4e06bfe5d4","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","agents":[{"key":"ember:c-4e06bfe5d4","runtime":"claude","process":"warm","pending":0,"lastTurn":{"id":"b468902a-6641-4195-a38b-d756fb195533","kind":"input","outcome":"completed","declared":"final","ending":"all_done","need":"answered the question that was asked","startedAt":1792592975138,"endedAt":1792592975206},"agentText":"默认模型","statusText":"已完成：answered the question that was asked"}],"last":{"seq":2,"authorKind":"agent","author":"ember:c-4e06bfe5d4","text":"你好，我是测试用的 agent","createdAt":1792592975203,"by":{"kind":"agent","name":"agent","mine":false,"runtime":"claude","label":"agent"},"preview":"你好，我是测试用的 agent","time":{"createdAt":{"at":1792592975203,"ago":"刚刚","full":"10/21 22:29:35","until":"1 分钟内","past":true}}},"unread":true,"mine":true,"lastActiveAt":1792592975203,"station":"01M5FDW1FW86V3FFXE2V16Z744/022644157b6993d24e2ad3d221f5a5bcbf5e81ba0df87f71239a029ac2bd4b2c","stationName":"studio","time":{"lastActiveAt":{"at":1792592975203,"ago":"刚刚","full":"10/21 22:29:35","until":"1 分钟内","past":true}},"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"peopleText":"你 发起","clientKey":"new:chat-8c8228a9f62fb91cc6","pinned":false,"tone":"done"}]}],"trouble":null,"members":1,"leading":"agents","glyph":{"online":1,"dim":0,"connecting":0,"failing":0,"working":0,"summary":"studio","label":"1 台 station，1 台在线"},"note":{"reading":false,"text":null,"failing":[],"empty":false}}},"w":1792592978624.661}
  #|{"in":{"id":8,"value":{"app":"desktop","tabs":[{"part":"desktop","label":"桌面","days":[]},{"part":"web","label":"网页","days":[]},{"part":"android","label":"安卓","days":[]},{"part":"station","label":"Station","days":[]},{"part":"cloud","label":"云端","days":[]}],"loading":false}},"w":1792592978624.679}
  #|{"in":{"id":9,"value":{"workspaces":{"01M5FDW1FW86V3FFXE2V16Z744":{"alert":0,"unread":1,"tone":"done","label":"1 个有新消息","badge":0,"items":[],"mineTone":"done"}},"badge":0,"badgeCounts":"attention","badgeKinds":{"on":true,"wait":true,"failed":true,"done":false,"message":false}}},"w":1792592978624.687}
  #|{"in":{"id":10,"value":[{"station":"01M5FDW1FW86V3FFXE2V16Z744/022644157b6993d24e2ad3d221f5a5bcbf5e81ba0df87f71239a029ac2bd4b2c","id":"022644157b6993d24e2ad3d221f5a5bcbf5e81ba0df87f71239a029ac2bd4b2c","name":"studio","summary":"空闲 · Apple M4 · 16 GB · macOS 27.0.1","face":"idle","line":"Apple M4","online":true,"reconnecting":false,"lastSeen":1792592975,"version":"0.1.0","link":{"state":"online"},"runtimes":[{"runtime":"claude","models":["claude-sonnet-5-5"]}],"models":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792592975117,"time":{"checkedAt":{"at":1792592975117,"ago":"刚刚","full":"10/21 22:29:35","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"overview":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null,"summaryText":"最近 7 天检查了 0 个 chat","changeText":null}},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","email":"alice@example.test","name":"Name of alice","sub":"alice","role":"owner","workspace":"01M5FDW1FW86V3FFXE2V16Z744","device":"b1f916167a90c4e4164de95952b631cbbcd46a5dc864a223da0917697bd1d126"},"connects":[],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792592975000,"time":{"checkedAt":{"at":1792592975000,"ago":"刚刚","full":"10/21 22:29:35","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792592975117,"time":{"checkedAt":{"at":1792592975117,"ago":"刚刚","full":"10/21 22:29:35","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"modelsReading":false,"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]}],"processes":[],"counts":{"sessions":1,"running":0,"warm":1},"mesh":{"state":"running","origin":"http://127.0.0.1:18787","station":"022644157b6993d24e2ad3d221f5a5bcbf5e81ba0df87f71239a029ac2bd4b2c","workspace":"Dev","workspaceId":"01M5FDW1FW86V3FFXE2V16Z744","name":"studio"},"slackUsers":[],"slackTeams":[],"slackApps":[],"feishuRegistrations":[],"disk":{"freeBytes":30698336256,"totalBytes":245107195904},"logins":[],"machineLogins":[],"sharing":true,"consoleSignIn":true,"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"google","name":"Google Gemini","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xai","name":"xAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"mistral","name":"Mistral","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"deepseek","name":"DeepSeek","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen","name":"Qwen","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai","name":"Kimi","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai","name":"Z.ai","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax","name":"MiniMax","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ant-ling","name":"Ant Ling","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"jev","name":"Jev","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen-cn","name":"Qwen (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"openrouter","name":"OpenRouter","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"opencode","name":"OpenCode Zen","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"groq","name":"Groq","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"together","name":"Together AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"fireworks","name":"Fireworks","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cerebras","name":"Cerebras","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"huggingface","name":"Hugging Face","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"nvidia","name":"NVIDIA","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"baseten","name":"Baseten","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ollama","name":"Ollama","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"custom","name":"Custom","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""}],"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792592975688},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.306","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792592975688},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-lockp/apps/e2e-local/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792592975688},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-lockp/apps/e2e-local/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792592975688},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","latest":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-lockp/apps/e2e-local/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792592975688},{"id":"cursor","name":"Cursor","installed":false,"latest":"1.0.40","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792592975688},{"id":"devin","name":"Devin","installed":true,"version":"3000.11.92","latest":"3000.11.92","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-lockp/apps/e2e-local/ember/station/test/fake/devin，不是用 Devin 的安装脚本装的，需在该机器上手动更新","state":"idle","checkedAt":1792592975688}],"processesText":"没有运行中的 agent 进程","agentEnv":[],"drive":{"roots":[{"path":"/tmp/mbe2e-C/home/e2e-105609","name":"e2e-105609","state":"ok"}],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false}},"betaOffered":false,"host":{"hostname":"3720-Mac-mini-1","os":"macOS 27.0.1","arch":"arm64","cpus":10,"cpuModel":"Apple M4","load":0.25,"cpuBusy":0.13,"uptimeSec":72338,"memory":{"totalBytes":17179869184,"usedBytes":9663266816,"swapUsedBytes":250347520},"disk":{"path":"/tmp/mbe2e-C/data","totalBytes":245107195904,"freeBytes":30701244416},"emberRssBytes":160889640,"checkedAt":1792592976698,"summary":"10 核 · 16 GB","line":"macOS 27.0.1 · 10 核 · 16 GB · 已运行 0 天","facts":["3720-Mac-mini-1","macOS 27.0.1","arm64 · 10 核","已运行 20 小时"],"meters":[{"label":"CPU","short":"CPU","percent":13,"left":87,"level":"ok","value":"13%","remaining":"空闲 87%","big":"87","unit":"%","title":"CPU 空闲","total":"负载 2.5","note":"负载 2.5 · Apple M4"},{"label":"内存","short":"内存","percent":56,"left":44,"level":"ok","value":"9.0 GB / 16.0 GB","remaining":"剩 7.0 G","big":"7.0","unit":"GB","title":"内存剩","total":"共 16 GB","note":"swap 0.2 GB"},{"label":"磁盘","short":"磁盘","percent":87,"left":13,"level":"amber","value":"剩余 28.6 GB / 228 GB","remaining":"剩 28.6 G","big":"28.6","unit":"GB","title":"磁盘剩","total":"共 228 GB"}],"identity":"Apple M4 · 16 GB · macOS 27.0.1","details":[{"label":"主机名","value":"3720-Mac-mini-1"},{"label":"芯片","value":"Apple M4 · 10 核 · arm64"},{"label":"已运行","value":"20 小时"},{"label":"still.fail","value":"进程占用 153 MB"}],"usage":"内存 9.0 GB / 16.0 GB · 磁盘 剩余 28.6 GB / 228 GB","emberText":"still.fail 153 MB"},"way":{"path":"直连","via":"direct"},"time":{"lastSeen":{"at":1792592975000,"ago":"刚刚","full":"10/21 22:29:35","until":"1 分钟内","past":true}},"joined":false}]},"w":1792592978624.777}
  #|{"in":{"id":12,"value":{"items":[]}},"w":1792592978624.851}
  #|{"in":{"id":13,"value":{"pairing":[]}},"w":1792592978624.854}
  #|{"in":{"id":14,"ok":null},"w":1792592978624.856}
  #|{"in":{"id":15,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792592978624.862}
  #|{"in":{"id":16,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792592978624.865}
  #|{"out":{"id":17,"subscribe":{"topic":"longJobs","scope":"01M5FDW1FW86V3FFXE2V16Z744"},"keyed":true},"w":1792592978624.901}
  #|{"out":{"id":18,"call":"notify.permission","params":{"state":"unknown"}},"w":1792592978627.12}
  #|{"in":{"id":10,"delta":[{"path":[0,"overview","disk","freeBytes"],"set":30698299392}]},"w":1792592978638.601}
  #|{"in":{"id":17,"value":{"groups":[]}},"w":1792592978638.613}
  #|{"in":{"id":18,"ok":null},"w":1792592978638.617}
  #|{"step":"#before drive-media 105609","w":1792592978638.84}
  #|{"step":"#env MBUI_OPEN_PAGE=files","w":1792592978638.842}
  #|{"step":"answered notify.permission","w":1792592978638.844}
  #|{"step":"wait 299","w":1792592978655.688}
  #|{"step":"now tap =e2e-105609","w":1792592978955.793}
  #|{"step":"now tap =e2e-105609","acted":true,"w":1792592978955.91}
  #|{"out":{"id":19,"subscribe":{"topic":"drive","station":"01M5FDW1FW86V3FFXE2V16Z744/022644157b6993d24e2ad3d221f5a5bcbf5e81ba0df87f71239a029ac2bd4b2c","root":"/tmp/mbe2e-C/home/e2e-105609","path":""},"keyed":true},"w":1792592978972.446}
  #|{"step":"wait 300","w":1792592978978.762}
  #|{"in":{"id":19,"value":{"path":"","entries":[{"name":"子文件夹","dir":true,"size":0,"mtime":1792592975747,"type":"","kind":"folder","sizeText":"","timeText":"22:29"},{"name":"影音","dir":true,"size":0,"mtime":1792592978401,"type":"","kind":"folder","sizeText":"","timeText":"22:29"},{"name":"小说-e2e.txt","dir":false,"size":36779,"mtime":1792592975761,"type":"text/plain; charset=utf-8","kind":"text","sizeText":"36 KB","timeText":"22:29"},{"name":"说明.txt","dir":false,"size":43,"mtime":1792592975747,"type":"text/plain; charset=utf-8","kind":"text","sizeText":"43 B","timeText":"22:29"}],"truncated":false,"folders":2,"files":2,"countText":"2 个文件夹 · 2 个文件"}},"w":1792592978988.663}
  #|{"out":{"id":20,"subscribe":{"topic":"drivePlace","station":"01M5FDW1FW86V3FFXE2V16Z744/022644157b6993d24e2ad3d221f5a5bcbf5e81ba0df87f71239a029ac2bd4b2c","root":"/tmp/mbe2e-C/home/e2e-105609","path":"小说-e2e.txt"},"keyed":true},"w":1792592978992.325}
  #|{"out":{"id":21,"subscribe":{"topic":"drivePlace","station":"01M5FDW1FW86V3FFXE2V16Z744/022644157b6993d24e2ad3d221f5a5bcbf5e81ba0df87f71239a029ac2bd4b2c","root":"/tmp/mbe2e-C/home/e2e-105609","path":"说明.txt"},"keyed":true},"w":1792592978993.019}
  #|{"in":{"id":20,"value":null},"w":1792592979005.293}
  #|{"in":{"id":21,"value":null},"w":1792592979005.323}
  #|{"step":"now tap 影音","w":1792592979289.557}
  #|{"step":"now tap 影音","acted":true,"w":1792592979289.642}
  #|{"out":{"id":22,"subscribe":{"topic":"drive","station":"01M5FDW1FW86V3FFXE2V16Z744/022644157b6993d24e2ad3d221f5a5bcbf5e81ba0df87f71239a029ac2bd4b2c","root":"/tmp/mbe2e-C/home/e2e-105609","path":"影音"},"keyed":true},"w":1792592979305.722}
  #|{"step":"wait 300","w":1792592979308.66}
  #|{"in":{"id":22,"value":{"path":"影音","entries":[{"name":"片尾曲.m4a","dir":false,"size":45252,"mtime":1792592978400,"type":"audio/mp4","kind":"audio","sizeText":"44 KB","timeText":"22:29"},{"name":"第01集.mp4","dir":false,"size":2276541,"mtime":1792592978204,"type":"video/mp4","kind":"video","sizeText":"2.2 MB","timeText":"22:29"},{"name":"第01集.srt","dir":false,"size":97,"mtime":1792592978401,"type":"application/x-subrip","kind":"subtitle","sizeText":"97 B","timeText":"22:29"},{"name":"第02集.mp4","dir":false,"size":461621,"mtime":1792592978343,"type":"video/mp4","kind":"video","sizeText":"451 KB","timeText":"22:29"}],"truncated":false,"folders":0,"files":4,"countText":"4 个文件"}},"w":1792592979321.994}
  #|{"step":"now until 第01集.mp4","w":1792592979622.467}
  #|{"step":"until 片尾曲.m4a","w":1792592979622.517}
  #|{"step":"tap 第01集.mp4","w":1792592979622.525}
  #|{"step":"tap 第01集.mp4","acted":true,"w":1792592979622.556}
  #|{"out":{"id":23,"subscribe":{"topic":"drivePlace","station":"01M5FDW1FW86V3FFXE2V16Z744/022644157b6993d24e2ad3d221f5a5bcbf5e81ba0df87f71239a029ac2bd4b2c","root":"/tmp/mbe2e-C/home/e2e-105609","path":"影音/第01集.mp4"},"keyed":true},"w":1792592979639.279}
  #|{"out":{"id":24,"call":"drive.read","params":{"station":"01M5FDW1FW86V3FFXE2V16Z744/022644157b6993d24e2ad3d221f5a5bcbf5e81ba0df87f71239a029ac2bd4b2c","root":"/tmp/mbe2e-C/home/e2e-105609","path":"影音/第01集.srt","offset":0,"length":4194304}},"w":1792592979639.417}
  #|{"step":"answered drive.read","w":1792592979644.188}
  #|{"in":{"id":23,"value":null},"w":1792592979655.295}
  #|{"in":{"id":24,"ok":{"type":"application/x-subrip","total":97,"mtime":1792592978401}},"w":1792592979655.34,"b":"310a30303a30303a30302c323030202d2d3e2030303a30303a30342c3030300ae7acace4b880e58fa5e5ad97e5b9950a0a320a30303a30303a30342c303030202d2d3e2030303a30303a30372c3530300ae7acace4ba8ce58fa5e5ad97e5b9950a"}
  #|{"info":{"view":1,"state":0,"at":[-1,0,1,0,0,0,0,1,0,0]},"w":1792592979673.039}
  #|{"out":{"id":25,"call":"drive.read","params":{"station":"01M5FDW1FW86V3FFXE2V16Z744/022644157b6993d24e2ad3d221f5a5bcbf5e81ba0df87f71239a029ac2bd4b2c","root":"/tmp/mbe2e-C/home/e2e-105609","path":"影音/第01集.mp4","offset":0,"length":2}},"w":1792592979690.165}
  #|{"step":"wait 300","w":1792592979690.435}
  #|{"in":{"id":25,"ok":{"type":"video/mp4","total":2276541,"mtime":1792592978204}},"w":1792592979705.275,"b":"0000"}
  #|{"info":{"view":1,"state":0,"at":[-1,0,1,0,0,2,0,1,0,0]},"w":1792592979705.476}
  #|{"out":{"id":26,"call":"drive.read","params":{"station":"01M5FDW1FW86V3FFXE2V16Z744/022644157b6993d24e2ad3d221f5a5bcbf5e81ba0df87f71239a029ac2bd4b2c","root":"/tmp/mbe2e-C/home/e2e-105609","path":"影音/第01集.mp4","offset":0,"length":2276541}},"w":1792592979722.291}
  #|{"in":{"id":26,"ok":{"type":"video/mp4","total":2276541,"mtime":1792592978204}},"w":1792592979755.466,"bn":2276541}
  #|{"info":{"view":1,"state":0,"at":[-1,0,1,0,0,2276543,0,1,0,0]},"w":1792592979755.702}
  #|{"info":{"view":1,"state":0,"at":[20000,0,1,640,360,2276543,0,1,0,0]},"w":1792592979833.287}
  #|{"info":{"view":1,"state":1,"at":[20000,0,1,640,360,2276543,0,1,20000,0]},"w":1792592979835.401}
  #|{"info":{"view":1,"state":1,"at":[20000,0,1,640,360,2276543,1,0,20000,0]},"w":1792592979855.324}
  #|{"info":{"view":1,"state":1,"at":[20000,14.277345,1,640,360,2276543,1,0,20000,0]},"w":1792592979955.368}
  #|{"info":{"view":1,"state":1,"at":[20000,14.488302999999998,1,640,360,2276543,1,0,20000,0]},"w":1792592979955.566}
  #|{"info":{"view":1,"state":1,"at":[20000,30.856845,1,640,360,2276543,1,0,20000,0]},"w":1792592979971.935}
  #|{"info":{"view":1,"state":1,"at":[20000,30.962428,1,640,360,2276543,1,0,20000,0]},"w":1792592979972.039}
  #|{"info":{"view":1,"state":1,"at":[20000,47.522428,1,640,360,2276543,1,0,20000,0]},"w":1792592979988.604}
  #|{"info":{"view":1,"state":1,"at":[20000,47.623636,1,640,360,2276543,1,0,20000,0]},"w":1792592979988.701}
  #|{"info":{"view":1,"state":1,"at":[20000,64.211636,1,640,360,2276543,1,0,20000,0]},"w":1792592980005.296}
  #|{"info":{"view":1,"state":1,"at":[20000,64.33272,1,640,360,2276543,1,0,20000,0]},"w":1792592980005.41}
  #|{"step":"now until 2 / 3","w":1792592980005.446}
  #|{"step":"answered drive.read","w":1792592980005.454}
  #|{"info":{"view":1,"state":1,"at":[20000,80.854053,1,640,360,2276543,1,0,20000,0]},"w":1792592980021.932}
  #|{"info":{"view":1,"state":1,"at":[20000,80.92692799999999,1,640,360,2276543,1,0,20000,0]},"w":1792592980022.004}
  #|{"step":"answered drive.read","w":1792592980022.049}
  #|{"info":{"view":1,"state":1,"at":[20000,97.536761,1,640,360,2276543,1,0,20000,0]},"w":1792592980038.62}
  #|{"info":{"view":1,"state":1,"at":[20000,97.635178,1,640,360,2276543,1,0,20000,0]},"w":1792592980038.713}
  #|{"step":"until 第一句字幕","w":1792592980038.747}
  #|{"info":{"view":1,"state":1,"at":[20000,114.186886,1,640,360,2276543,1,0,20000,0]},"w":1792592980055.265}
  #|{"info":{"view":1,"state":1,"at":[20000,114.253511,1,640,360,2276543,1,0,20000,0]},"w":1792592980055.331}
  #|{"info":{"view":1,"state":1,"at":[20000,130.85622,1,640,360,2276543,1,0,20000,0]},"w":1792592980071.935}
  #|{"info":{"view":1,"state":1,"at":[20000,130.953261,1,640,360,2276543,1,0,20000,0]},"w":1792592980072.031}
  #|{"info":{"view":1,"state":1,"at":[20000,147.541136,1,640,360,2276543,1,0,20000,0]},"w":1792592980088.625}
  #|{"info":{"view":1,"state":1,"at":[20000,147.72297,1,640,360,2276543,1,0,20000,0]},"w":1792592980088.803}
  #|{"info":{"view":1,"state":1,"at":[20000,164.19967799999998,1,640,360,2276543,1,0,20000,0]},"w":1792592980105.282}
  #|{"info":{"view":1,"state":1,"at":[20000,164.34097,1,640,360,2276543,1,0,20000,0]},"w":1792592980105.42}
  #|{"info":{"view":1,"state":1,"at":[20000,180.89217799999997,1,640,360,2276543,1,0,20000,0]},"w":1792592980121.981}
  #|{"info":{"view":1,"state":1,"at":[20000,181.089428,1,640,360,2276543,1,0,20000,0]},"w":1792592980122.17}
  #|{"info":{"view":1,"state":1,"at":[20000,197.573511,1,640,360,2276543,1,0,20000,0]},"w":1792592980138.668}
  #|{"info":{"view":1,"state":1,"at":[20000,197.93547,1,640,360,2276543,1,0,20000,0]},"w":1792592980139.021}
  #|{"info":{"view":1,"state":1,"at":[20000,214.197803,1,640,360,2276543,1,0,20000,0]},"w":1792592980155.284}
  #|{"info":{"view":1,"state":1,"at":[20000,216.447553,1,640,360,2276543,1,0,20000,0]},"w":1792592980157.527}
  #|{"step":"back","w":1792592980157.649}
  #|{"step":"back","acted":true,"w":1792592980157.66}
  #|{"info":{"view":1,"state":1,"at":[20000,230.88547,1,640,360,2276543,1,0,20000,0]},"w":1792592980171.97}
  #|{"info":{"view":1,"state":1,"at":[20000,231.197511,1,640,360,2276543,1,0,20000,0]},"w":1792592980172.275}
  #|{"step":"wait 300","w":1792592980172.369}
  #|{"info":{"view":1,"state":1,"at":[20000,247.537845,1,640,360,2276543,1,0,20000,0]},"w":1792592980188.622}
  #|{"info":{"view":1,"state":1,"at":[20000,247.863553,1,640,360,2276543,1,0,20000,0]},"w":1792592980188.942}
  #|{"info":{"view":1,"state":1,"at":[20000,264.20959500000004,1,640,360,2276543,1,0,20000,0]},"w":1792592980205.297}
  #|{"info":{"view":1,"state":1,"at":[20000,264.501303,1,640,360,2276543,1,0,20000,0]},"w":1792592980205.579}
  #|{"info":{"view":1,"state":1,"at":[20000,280.892636,1,640,360,2276543,1,0,20000,0]},"w":1792592980221.983}
  #|{"info":{"view":1,"state":1,"at":[20000,281.117136,1,640,360,2276543,1,0,20000,0]},"w":1792592980222.195}
  #|{"info":{"view":1,"state":1,"at":[20000,297.526053,1,640,360,2276543,1,0,20000,0]},"w":1792592980238.605}
  #|{"info":{"view":1,"state":1,"at":[20000,297.746636,1,640,360,2276543,1,0,20000,0]},"w":1792592980238.825}
  #|{"info":{"view":1,"state":1,"at":[20000,314.19897000000003,1,640,360,2276543,1,0,20000,0]},"w":1792592980255.279}
  #|{"info":{"view":1,"state":1,"at":[20000,314.440636,1,640,360,2276543,1,0,20000,0]},"w":1792592980255.519}
  #|{"info":{"view":1,"state":1,"at":[20000,330.860636,1,640,360,2276543,1,0,20000,0]},"w":1792592980271.939}
  #|{"info":{"view":1,"state":1,"at":[20000,331.076928,1,640,360,2276543,1,0,20000,0]},"w":1792592980272.155}
  #|{"info":{"view":1,"state":1,"at":[20000,347.525303,1,640,360,2276543,1,0,20000,0]},"w":1792592980288.605}
  #|{"info":{"view":1,"state":1,"at":[20000,347.74142800000004,1,640,360,2276543,1,0,20000,0]},"w":1792592980288.82}
  #|{"info":{"view":1,"state":1,"at":[20000,364.194345,1,640,360,2276543,1,0,20000,0]},"w":1792592980305.274}
  #|{"info":{"view":1,"state":1,"at":[20000,364.424511,1,640,360,2276543,1,0,20000,0]},"w":1792592980305.504}
  #|{"info":{"view":1,"state":1,"at":[20000,380.90826100000004,1,640,360,2276543,1,0,20000,0]},"w":1792592980322.003}
  #|{"info":{"view":1,"state":1,"at":[20000,381.76392799999996,1,640,360,2276543,1,0,20000,0]},"w":1792592980322.856}
  #|{"info":{"view":1,"state":1,"at":[20000,397.55367800000005,1,640,360,2276543,1,0,20000,0]},"w":1792592980338.644}
  #|{"info":{"view":1,"state":1,"at":[20000,397.92684499999996,1,640,360,2276543,1,0,20000,0]},"w":1792592980339.007}
  #|{"info":{"view":1,"state":1,"at":[20000,414.263678,1,640,360,2276543,1,0,20000,0]},"w":1792592980355.373}
  #|{"info":{"view":1,"state":1,"at":[20000,415.41397,1,640,360,2276543,1,0,20000,0]},"w":1792592980356.504}
  #|{"info":{"view":1,"state":1,"at":[20000,430.89930300000003,1,640,360,2276543,1,0,20000,0]},"w":1792592980371.999}
  #|{"info":{"view":1,"state":1,"at":[20000,431.985511,1,640,360,2276543,1,0,20000,0]},"w":1792592980373.073}
  #|{"info":{"view":1,"state":1,"at":[20000,447.59688600000004,1,640,360,2276543,1,0,20000,0]},"w":1792592980388.707}
  #|{"info":{"view":1,"state":1,"at":[20000,448.994053,1,640,360,2276543,1,0,20000,0]},"w":1792592980390.085}
  #|{"info":{"view":1,"state":1,"at":[20000,464.26426100000003,1,640,360,2276543,1,0,20000,0]},"w":1792592980405.371}
  #|{"info":{"view":1,"state":1,"at":[20000,465.606261,1,640,360,2276543,1,0,20000,0]},"w":1792592980406.698}
  #|{"info":{"view":1,"state":1,"at":[20000,480.917428,1,640,360,2276543,1,0,20000,0]},"w":1792592980422.023}
  #|{"info":{"view":1,"state":1,"at":[20000,482.23242799999997,1,640,360,2276543,1,0,20000,0]},"w":1792592980423.324}
  #|{"info":{"view":1,"state":1,"at":[20000,497.594178,1,640,360,2276543,1,0,20000,0]},"w":1792592980438.697}
  #|{"info":{"view":1,"state":1,"at":[20000,498.95617799999997,1,640,360,2276543,1,0,20000,0]},"w":1792592980440.047}
  #|{"info":{"view":1,"state":1,"at":[20000,514.2577200000001,1,640,360,2276543,1,0,20000,0]},"w":1792592980455.36}
  #|{"info":{"view":1,"state":1,"at":[20000,515.92197,1,640,360,2276543,1,0,20000,0]},"w":1792592980457.013}
  #|{"info":{"view":1,"state":1,"at":[20000,530.9168450000001,1,640,360,2276543,1,0,20000,0]},"w":1792592980472.017}
  #|{"out":{"id":27,"call":"drive.place","params":{"station":"01M5FDW1FW86V3FFXE2V16Z744/022644157b6993d24e2ad3d221f5a5bcbf5e81ba0df87f71239a029ac2bd4b2c","root":"/tmp/mbe2e-C/home/e2e-105609","path":"影音/第01集.mp4","at":531,"of":20000}},"w":1792592980473.082}
  #|{"step":"now answered drive.place","w":1792592980475.498}
  #|{"in":{"id":27,"ok":null},"w":1792592980488.631}
  #|{"step":"until 第02集.mp4","w":1792592980506.19}
  #|{"step":"tap 第01集.mp4","w":1792592980506.229}
  #|{"step":"tap 第01集.mp4","acted":true,"w":1792592980506.259}
  #|{"out":{"id":28,"call":"drive.read","params":{"station":"01M5FDW1FW86V3FFXE2V16Z744/022644157b6993d24e2ad3d221f5a5bcbf5e81ba0df87f71239a029ac2bd4b2c","root":"/tmp/mbe2e-C/home/e2e-105609","path":"影音/第01集.srt","offset":0,"length":4194304}},"w":1792592980525.904}
  #|{"info":{"view":2,"state":0,"at":[-1,0,1,0,0,0,0,1,0,0]},"w":1792592980526.674}
  #|{"step":"answered drive.read","w":1792592980526.997}
  #|{"in":{"id":23,"value":{"at":531,"of":20000,"changed":1792592980473}},"w":1792592980538.624}
  #|{"in":{"id":28,"ok":{"type":"application/x-subrip","total":97,"mtime":1792592978401}},"w":1792592980538.662,"b":"310a30303a30303a30302c323030202d2d3e2030303a30303a30342c3030300ae7acace4b880e58fa5e5ad97e5b9950a0a320a30303a30303a30342c303030202d2d3e2030303a30303a30372c3530300ae7acace4ba8ce58fa5e5ad97e5b9950a"}
  #|{"out":{"id":29,"call":"drive.read","params":{"station":"01M5FDW1FW86V3FFXE2V16Z744/022644157b6993d24e2ad3d221f5a5bcbf5e81ba0df87f71239a029ac2bd4b2c","root":"/tmp/mbe2e-C/home/e2e-105609","path":"影音/第01集.mp4","offset":0,"length":2}},"w":1792592980539.836}
  #|{"in":{"id":29,"ok":{"type":"video/mp4","total":2276541,"mtime":1792592978204}},"w":1792592980555.317,"b":"0000"}
  #|{"info":{"view":2,"state":0,"at":[-1,0,1,0,0,2,0,1,0,0]},"w":1792592980555.496}
  #|{"step":"wait 300","w":1792592980556.855}
  #|{"out":{"id":30,"call":"drive.read","params":{"station":"01M5FDW1FW86V3FFXE2V16Z744/022644157b6993d24e2ad3d221f5a5bcbf5e81ba0df87f71239a029ac2bd4b2c","root":"/tmp/mbe2e-C/home/e2e-105609","path":"影音/第01集.mp4","offset":0,"length":2276541}},"w":1792592980573.122}
  #|{"in":{"id":30,"ok":{"type":"video/mp4","total":2276541,"mtime":1792592978204}},"w":1792592980605.558,"bn":2276541}
  #|{"info":{"view":2,"state":0,"at":[-1,0,1,0,0,2276543,0,1,0,0]},"w":1792592980606.059}
  #|{"info":{"view":2,"state":0,"at":[20000,0,1,640,360,2276543,0,1,0,0]},"w":1792592980622.286}
  #|{"info":{"view":2,"state":1,"at":[20000,0,1,640,360,2276543,1,0,20000,0]},"w":1792592980638.635}
  #|{"info":{"view":2,"state":1,"at":[20000,6.910863,1,640,360,2276543,1,0,20000,0]},"w":1792592980705.365}
  #|{"info":{"view":2,"state":1,"at":[20000,7.9716130000000005,1,640,360,2276543,1,0,20000,0]},"w":1792592980706.414}
  #|{"info":{"view":2,"state":1,"at":[20000,23.561988,1,640,360,2276543,1,0,20000,0]},"w":1792592980722.018}
  #|{"info":{"view":2,"state":1,"at":[20000,24.727655000000002,1,640,360,2276543,1,0,20000,0]},"w":1792592980723.168}
  #|{"info":{"view":2,"state":1,"at":[20000,40.229488,1,640,360,2276543,1,0,20000,0]},"w":1792592980738.685}
  #|{"info":{"view":2,"state":1,"at":[20000,41.464529999999996,1,640,360,2276543,1,0,20000,0]},"w":1792592980739.905}
  #|{"info":{"view":2,"state":1,"at":[20000,56.925905,1,640,360,2276543,1,0,20000,0]},"w":1792592980755.387}
  #|{"info":{"view":2,"state":1,"at":[20000,58.281822,1,640,360,2276543,1,0,20000,0]},"w":1792592980756.725}
  #|{"info":{"view":2,"state":1,"at":[20000,73.573405,1,640,360,2276543,1,0,20000,0]},"w":1792592980772.03}
  #|{"info":{"view":2,"state":1,"at":[20000,74.89153,1,640,360,2276543,1,0,20000,0]},"w":1792592980773.333}
  #|{"info":{"view":2,"state":1,"at":[20000,90.24673800000001,1,640,360,2276543,1,0,20000,0]},"w":1792592980788.703}
  #|{"info":{"view":2,"state":1,"at":[20000,91.53053,1,640,360,2276543,1,0,20000,0]},"w":1792592980789.973}
  #|{"info":{"view":2,"state":1,"at":[20000,106.907072,1,640,360,2276543,1,0,20000,0]},"w":1792592980805.364}
  #|{"info":{"view":2,"state":1,"at":[20000,108.279197,1,640,360,2276543,1,0,20000,0]},"w":1792592980806.727}
  #|{"info":{"view":2,"state":1,"at":[20000,123.573488,1,640,360,2276543,1,0,20000,0]},"w":1792592980822.029}
  #|{"info":{"view":2,"state":1,"at":[20000,124.84173799999999,1,640,360,2276543,1,0,20000,0]},"w":1792592980823.284}
  #|{"info":{"view":2,"state":1,"at":[20000,140.248697,1,640,360,2276543,1,0,20000,0]},"w":1792592980838.71}
  #|{"info":{"view":2,"state":1,"at":[20000,141.02490500000002,1,640,360,2276543,1,0,20000,0]},"w":1792592980839.468}
  #|{"info":{"view":2,"state":1,"at":[20000,156.92107199999998,1,640,360,2276543,1,0,20000,0]},"w":1792592980855.387}
  #|{"info":{"view":2,"state":1,"at":[20000,157.59103,1,640,360,2276543,1,0,20000,0]},"w":1792592980856.034}
  #|{"info":{"view":2,"state":1,"at":[20000,173.58036299999998,1,640,360,2276543,1,0,20000,0]},"w":1792592980872.042}
  #|{"info":{"view":2,"state":1,"at":[20000,174.21811300000002,1,640,360,2276543,1,0,20000,0]},"w":1792592980872.659}
  #|{"step":"now until 2 / 3","w":1792592980872.943}
  #|{"step":"answered drive.read","w":1792592980872.971}
  #|{"info":{"view":2,"state":1,"at":[20000,190.25678,1,640,360,2276543,1,0,20000,0]},"w":1792592980888.72}
  #|{"info":{"view":2,"state":1,"at":[20000,190.898988,1,640,360,2276543,1,0,20000,0]},"w":1792592980889.34}
  #|{"step":"answered drive.read","w":1792592980889.632}
  #|{"info":{"view":2,"state":1,"at":[20000,206.908697,1,640,360,2276543,1,0,20000,0]},"w":1792592980905.367}
  #|{"info":{"view":2,"state":1,"at":[20000,207.60228,1,640,360,2276543,1,0,20000,0]},"w":1792592980906.043}
  #|{"step":"until / 0:20","w":1792592980906.322}
  #|{"step":"tap icon:forward-15","w":1792592980906.344}
  #|{"step":"tap icon:forward-15","acted":true,"w":1792592980906.374}
  #|{"info":{"view":2,"state":1,"at":[20000,223.626822,1,640,360,2276543,1,0,20000,0]},"w":1792592980922.091}
  #|{"info":{"view":2,"state":1,"at":[20000,15224,1,640,360,2276543,1,0,20000,0]},"w":1792592980924.02}
  #|{"step":"tap icon:forward-15","w":1792592980924.311}
  #|{"step":"tap icon:forward-15","acted":true,"w":1792592980924.36}
  #|{"info":{"view":2,"state":1,"at":[20000,20000,1,640,360,2276543,1,0,20000,0]},"w":1792592980974.53}
  #|{"step":"until 播放结束","w":1792592980974.798}
  #|{"info":{"view":2,"state":1,"at":[20000,20000,0,640,360,2276543,1,0,20000,1]},"w":1792592981088.687}
  #|{"step":"tap 下一个：第02集.mp4","w":1792592981094.791}
  #|{"step":"tap 下一个：第02集.mp4","acted":true,"w":1792592981094.833}
  #|{"out":{"id":31,"subscribe":{"topic":"drivePlace","station":"01M5FDW1FW86V3FFXE2V16Z744/022644157b6993d24e2ad3d221f5a5bcbf5e81ba0df87f71239a029ac2bd4b2c","root":"/tmp/mbe2e-C/home/e2e-105609","path":"影音/第02集.mp4"},"keyed":true},"w":1792592981105.986}
  #|{"step":"answered drive.place","w":1792592981107.078}
  #|{"in":{"id":31,"value":null},"w":1792592981121.979}
  #|{"out":{"id":32,"call":"drive.place","params":{"station":"01M5FDW1FW86V3FFXE2V16Z744/022644157b6993d24e2ad3d221f5a5bcbf5e81ba0df87f71239a029ac2bd4b2c","root":"/tmp/mbe2e-C/home/e2e-105609","path":"影音/第01集.mp4","at":20000,"of":20000}},"w":1792592981128.033}
  #|{"info":{"view":3,"state":0,"at":[-1,0,1,0,0,0,0,1,0,0]},"w":1792592981129.903}
  #|{"in":{"id":32,"ok":null},"w":1792592981138.632}
  #|{"out":{"id":33,"call":"drive.read","params":{"station":"01M5FDW1FW86V3FFXE2V16Z744/022644157b6993d24e2ad3d221f5a5bcbf5e81ba0df87f71239a029ac2bd4b2c","root":"/tmp/mbe2e-C/home/e2e-105609","path":"影音/第02集.mp4","offset":0,"length":2}},"w":1792592981139.318}
  #|{"in":{"id":33,"ok":{"type":"video/mp4","total":461621,"mtime":1792592978343}},"w":1792592981155.312,"b":"0000"}
  #|{"info":{"view":3,"state":0,"at":[-1,0,1,0,0,2,0,1,0,0]},"w":1792592981155.508}
  #|{"step":"until 3 / 3","w":1792592981156.284}
  #|{"step":"answered drive.read","w":1792592981156.297}
  #|{"out":{"id":34,"call":"drive.read","params":{"station":"01M5FDW1FW86V3FFXE2V16Z744/022644157b6993d24e2ad3d221f5a5bcbf5e81ba0df87f71239a029ac2bd4b2c","root":"/tmp/mbe2e-C/home/e2e-105609","path":"影音/第02集.mp4","offset":0,"length":461621}},"w":1792592981172.151}
  #|{"step":"answered drive.read","w":1792592981172.293}
  #|{"in":{"id":23,"value":{"at":20000,"of":20000,"changed":1792592981128}},"w":1792592981188.618}
  #|{"in":{"id":34,"ok":{"type":"video/mp4","total":461621,"mtime":1792592978343}},"w":1792592981188.676,"bn":461621}
  #|{"info":{"view":3,"state":0,"at":[-1,0,1,0,0,461623,0,1,0,0]},"w":1792592981188.851}
  #|{"info":{"view":3,"state":0,"at":[4000,0,1,640,360,461623,0,1,0,0]},"w":1792592981205.975}
  #|{"step":"until / 0:04","w":1792592981207.822}
  #|{"step":"back","w":1792592981207.867}
  #|{"step":"back","acted":true,"w":1792592981207.907}
  #|{"info":{"view":3,"state":1,"at":[4000,0,1,640,360,461623,1,0,4000,0]},"w":1792592981221.961}
  #|{"step":"wait 300","w":1792592981222.562}
  #|{"info":{"view":3,"state":1,"at":[4000,3.530113,1,640,360,461623,1,0,4000,0]},"w":1792592981288.658}
  #|{"info":{"view":3,"state":1,"at":[4000,4.697571,1,640,360,461623,1,0,4000,0]},"w":1792592981289.811}
  #|{"info":{"view":3,"state":1,"at":[4000,20.192071,1,640,360,461623,1,0,4000,0]},"w":1792592981305.314}
  #|{"info":{"view":3,"state":1,"at":[4000,21.257696,1,640,360,461623,1,0,4000,0]},"w":1792592981306.37}
  #|{"info":{"view":3,"state":1,"at":[4000,36.913363,1,640,360,461623,1,0,4000,0]},"w":1792592981322.047}
  #|{"info":{"view":3,"state":1,"at":[4000,38.307946,1,640,360,461623,1,0,4000,0]},"w":1792592981323.426}
  #|{"info":{"view":3,"state":1,"at":[4000,53.547071,1,640,360,461623,1,0,4000,0]},"w":1792592981338.673}
  #|{"info":{"view":3,"state":1,"at":[4000,54.758155,1,640,360,461623,1,0,4000,0]},"w":1792592981339.872}
  #|{"info":{"view":3,"state":1,"at":[4000,70.22578,1,640,360,461623,1,0,4000,0]},"w":1792592981355.357}
  #|{"info":{"view":3,"state":1,"at":[4000,71.55344600000001,1,640,360,461623,1,0,4000,0]},"w":1792592981356.669}
  #|{"info":{"view":3,"state":1,"at":[4000,86.88553,1,640,360,461623,1,0,4000,0]},"w":1792592981372.013}
  #|{"info":{"view":3,"state":1,"at":[4000,88.14202999999999,1,640,360,461623,1,0,4000,0]},"w":1792592981373.257}
  #|{"info":{"view":3,"state":1,"at":[4000,103.565155,1,640,360,461623,1,0,4000,0]},"w":1792592981388.694}
  #|{"info":{"view":3,"state":1,"at":[4000,104.83502999999999,1,640,360,461623,1,0,4000,0]},"w":1792592981389.952}
  #|{"info":{"view":3,"state":1,"at":[4000,120.260988,1,640,360,461623,1,0,4000,0]},"w":1792592981405.402}
  #|{"info":{"view":3,"state":1,"at":[4000,121.754238,1,640,360,461623,1,0,4000,0]},"w":1792592981406.876}
  #|{"info":{"view":3,"state":1,"at":[4000,136.94886300000002,1,640,360,461623,1,0,4000,0]},"w":1792592981422.094}
  #|{"info":{"view":3,"state":1,"at":[4000,138.45348800000002,1,640,360,461623,1,0,4000,0]},"w":1792592981423.576}
  #|{"info":{"view":3,"state":1,"at":[4000,153.600405,1,640,360,461623,1,0,4000,0]},"w":1792592981438.745}
  #|{"info":{"view":3,"state":1,"at":[4000,155.147905,1,640,360,461623,1,0,4000,0]},"w":1792592981440.271}
  #|{"info":{"view":3,"state":1,"at":[4000,170.29982099999998,1,640,360,461623,1,0,4000,0]},"w":1792592981455.446}
  #|{"info":{"view":3,"state":1,"at":[4000,171.938863,1,640,360,461623,1,0,4000,0]},"w":1792592981457.064}
  #|{"info":{"view":3,"state":1,"at":[4000,186.930071,1,640,360,461623,1,0,4000,0]},"w":1792592981472.071}
  #|{"info":{"view":3,"state":1,"at":[4000,188.35244600000001,1,640,360,461623,1,0,4000,0]},"w":1792592981473.473}
  #|{"info":{"view":3,"state":1,"at":[4000,203.577946,1,640,360,461623,1,0,4000,0]},"w":1792592981488.713}
  #|{"info":{"view":3,"state":1,"at":[4000,204.96098800000001,1,640,360,461623,1,0,4000,0]},"w":1792592981490.081}
  #|{"info":{"view":3,"state":1,"at":[4000,220.218696,1,640,360,461623,1,0,4000,0]},"w":1792592981505.347}
  #|{"info":{"view":3,"state":1,"at":[4000,221.486405,1,640,360,461623,1,0,4000,0]},"w":1792592981506.603}
  #|{"info":{"view":3,"state":1,"at":[4000,236.890863,1,640,360,461623,1,0,4000,0]},"w":1792592981522.021}
  #|{"out":{"id":35,"call":"drive.place","params":{"station":"01M5FDW1FW86V3FFXE2V16Z744/022644157b6993d24e2ad3d221f5a5bcbf5e81ba0df87f71239a029ac2bd4b2c","root":"/tmp/mbe2e-C/home/e2e-105609","path":"影音/第02集.mp4","at":237,"of":4000}},"w":1792592981523.068}
  #|{"step":"now answered drive.place","w":1792592981524.852}
  #|{"in":{"id":35,"ok":null},"w":1792592981538.633}
  #|{"step":"tap 片尾曲.m4a","w":1792592981556.662}
  #|{"step":"tap 片尾曲.m4a","acted":true,"w":1792592981556.715}
  #|{"out":{"id":36,"subscribe":{"topic":"drivePlace","station":"01M5FDW1FW86V3FFXE2V16Z744/022644157b6993d24e2ad3d221f5a5bcbf5e81ba0df87f71239a029ac2bd4b2c","root":"/tmp/mbe2e-C/home/e2e-105609","path":"影音/片尾曲.m4a"},"keyed":true},"w":1792592981572.605}
  #|{"step":"wait 300","w":1792592981573.556}
  #|{"in":{"id":31,"value":{"at":237,"of":4000,"changed":1792592981523}},"w":1792592981588.65}
  #|{"in":{"id":36,"value":null},"w":1792592981588.701}
  #|{"info":{"view":4,"state":0,"at":[-1,0,1,0,0,0,0,1,0,0]},"w":1792592981597.219}
  #|{"out":{"id":37,"call":"drive.read","params":{"station":"01M5FDW1FW86V3FFXE2V16Z744/022644157b6993d24e2ad3d221f5a5bcbf5e81ba0df87f71239a029ac2bd4b2c","root":"/tmp/mbe2e-C/home/e2e-105609","path":"影音/片尾曲.m4a","offset":0,"length":2}},"w":1792592981606.12}
  #|{"in":{"id":37,"ok":{"type":"audio/mp4","total":45252,"mtime":1792592978400}},"w":1792592981621.979,"b":"0000"}
  #|{"info":{"view":4,"state":0,"at":[-1,0,1,0,0,2,0,1,0,0]},"w":1792592981622.196}
  #|{"out":{"id":38,"call":"drive.read","params":{"station":"01M5FDW1FW86V3FFXE2V16Z744/022644157b6993d24e2ad3d221f5a5bcbf5e81ba0df87f71239a029ac2bd4b2c","root":"/tmp/mbe2e-C/home/e2e-105609","path":"影音/片尾曲.m4a","offset":0,"length":45252}},"w":1792592981640.769}
  #|{"in":{"id":38,"ok":{"type":"audio/mp4","total":45252,"mtime":1792592978400}},"w":1792592981655.658,"bn":45252}
  #|{"info":{"view":4,"state":0,"at":[-1,0,1,0,0,45254,0,1,0,0]},"w":1792592981655.865}
  #|{"info":{"view":4,"state":0,"at":[4975.32879818594,0,1,0,0,45254,0,1,0,0]},"w":1792592981681.759}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,0,1,0,0,45254,0,0,5000,0]},"w":1792592981688.765}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,5.59345,1,0,0,45254,0,0,5000,0]},"w":1792592981738.745}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,7.270117000000001,1,0,0,45254,0,0,5000,0]},"w":1792592981740.4}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,22.247825,1,0,0,45254,0,0,5000,0]},"w":1792592981755.394}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,23.71745,1,0,0,45254,0,0,5000,0]},"w":1792592981756.845}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,38.918075,1,0,0,45254,0,0,5000,0]},"w":1792592981772.065}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,40.405659,1,0,0,45254,0,0,5000,0]},"w":1792592981773.533}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,55.582367,1,0,0,45254,0,0,5000,0]},"w":1792592981788.73}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,57.051367,1,0,0,45254,0,0,5000,0]},"w":1792592981790.181}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,72.243617,1,0,0,45254,0,0,5000,0]},"w":1792592981805.393}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,73.66307499999999,1,0,0,45254,0,0,5000,0]},"w":1792592981806.79}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,88.919075,1,0,0,45254,0,0,5000,0]},"w":1792592981822.068}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,90.333492,1,0,0,45254,0,0,5000,0]},"w":1792592981823.461}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,105.626784,1,0,0,45254,0,0,5000,0]},"w":1792592981838.775}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,107.10486700000001,1,0,0,45254,0,0,5000,0]},"w":1792592981840.244}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,122.267992,1,0,0,45254,0,0,5000,0]},"w":1792592981855.422}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,123.789617,1,0,0,45254,0,0,5000,0]},"w":1792592981856.921}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,138.93774200000001,1,0,0,45254,0,0,5000,0]},"w":1792592981872.092}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,140.491992,1,0,0,45254,0,0,5000,0]},"w":1792592981873.623}
  #|{"step":"now until 1 / 3","w":1792592981873.955}
  #|{"step":"answered drive.read","w":1792592981873.997}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,155.62790900000002,1,0,0,45254,0,0,5000,0]},"w":1792592981888.782}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,156.488325,1,0,0,45254,0,0,5000,0]},"w":1792592981889.616}
  #|{"step":"answered drive.read","w":1792592981890.006}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,172.281992,1,0,0,45254,0,0,5000,0]},"w":1792592981905.439}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,173.025909,1,0,0,45254,0,0,5000,0]},"w":1792592981906.156}
  #|{"step":"back","w":1792592981906.55}
  #|{"step":"back","acted":true,"w":1792592981906.574}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,188.948117,1,0,0,45254,0,0,5000,0]},"w":1792592981922.103}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,190.11495,1,0,0,45254,0,0,5000,0]},"w":1792592981923.241}
  #|{"step":"wait 300","w":1792592981923.576}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,205.585784,1,0,0,45254,0,0,5000,0]},"w":1792592981938.731}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,207.018575,1,0,0,45254,0,0,5000,0]},"w":1792592981940.145}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,222.25661699999998,1,0,0,45254,0,0,5000,0]},"w":1792592981955.406}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,223.726784,1,0,0,45254,0,0,5000,0]},"w":1792592981956.854}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,238.921575,1,0,0,45254,0,0,5000,0]},"w":1792592981972.069}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,240.439617,1,0,0,45254,0,0,5000,0]},"w":1792592981973.569}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,255.6037,1,0,0,45254,0,0,5000,0]},"w":1792592981988.752}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,257.050075,1,0,0,45254,0,0,5000,0]},"w":1792592981990.177}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,272.26178400000003,1,0,0,45254,0,0,5000,0]},"w":1792592982005.409}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,273.62811700000003,1,0,0,45254,0,0,5000,0]},"w":1792592982006.756}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,288.835909,1,0,0,45254,0,0,5000,0]},"w":1792592982021.959}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,289.28640900000005,1,0,0,45254,0,0,5000,0]},"w":1792592982022.4}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,305.513742,1,0,0,45254,0,0,5000,0]},"w":1792592982038.633}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,305.974284,1,0,0,45254,0,0,5000,0]},"w":1792592982039.086}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,322.200325,1,0,0,45254,0,0,5000,0]},"w":1792592982055.338}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,322.906159,1,0,0,45254,0,0,5000,0]},"w":1792592982056.02}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,338.892534,1,0,0,45254,0,0,5000,0]},"w":1792592982072.019}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,339.19807499999996,1,0,0,45254,0,0,5000,0]},"w":1792592982072.309}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,355.4962,1,0,0,45254,0,0,5000,0]},"w":1792592982088.611}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,355.788992,1,0,0,45254,0,0,5000,0]},"w":1792592982088.901}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,372.15511699999996,1,0,0,45254,0,0,5000,0]},"w":1792592982105.267}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,372.39145,1,0,0,45254,0,0,5000,0]},"w":1792592982105.503}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,388.824742,1,0,0,45254,0,0,5000,0]},"w":1792592982121.938}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,389.05761700000005,1,0,0,45254,0,0,5000,0]},"w":1792592982122.169}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,405.4932,1,0,0,45254,0,0,5000,0]},"w":1792592982138.606}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,405.720492,1,0,0,45254,0,0,5000,0]},"w":1792592982138.833}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,422.1702,1,0,0,45254,0,0,5000,0]},"w":1792592982155.287}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,422.556575,1,0,0,45254,0,0,5000,0]},"w":1792592982155.672}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,439.23920100000004,1,0,0,45254,0,0,5000,0]},"w":1792592982172.385}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,440.113201,1,0,0,45254,0,0,5000,0]},"w":1792592982173.243}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,455.60445100000004,1,0,0,45254,0,0,5000,0]},"w":1792592982188.758}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,456.84120099999996,1,0,0,45254,0,0,5000,0]},"w":1792592982189.971}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,472.246368,1,0,0,45254,0,0,5000,0]},"w":1792592982205.397}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,473.67353499999996,1,0,0,45254,0,0,5000,0]},"w":1792592982206.808}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,488.90132600000004,1,0,0,45254,0,0,5000,0]},"w":1792592982222.052}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,490.31032600000003,1,0,0,45254,0,0,5000,0]},"w":1792592982223.442}
  #|{"step":"now answered drive.place","w":1792592982223.714}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,505.569951,1,0,0,45254,0,0,5000,0]},"w":1792592982238.719}
  #|{"out":{"id":39,"call":"drive.place","params":{"station":"01M5FDW1FW86V3FFXE2V16Z744/022644157b6993d24e2ad3d221f5a5bcbf5e81ba0df87f71239a029ac2bd4b2c","root":"/tmp/mbe2e-C/home/e2e-105609","path":"影音/片尾曲.m4a","at":506,"of":4975}},"w":1792592982239.904}
  #|{"in":{"id":39,"ok":null},"w":1792592982255.302}
  #|{"step":"until 片尾曲.m4a","w":1792592982272.957}
  #|{"step":"","w":1792592982272.992}
  #|{"textrec":{"ib":["bfd9b0d6dc602826",12668,64],"r":[56,56,56,56]}}
  #|{"textrec":{"s":[13,400,0,"正在读取你的 workspace"],"r":[0,1,12.898832684824903,0,1,1,12.898832684824903,1,2,1,12.898832684824903,2,3,1,12.898832684824903,3,4,1,12.898832684824896,4,5,1,12.898832684824896,5,6,1,3.580078125,-1,7,1,9.8642578125,6,8,1,7.4775390625,7,9,1,4.875,8,10,1,6.85546875,9,11,1,6.6015625,10,12,1,7.8583984375,11,13,1,7.0966796875,12,14,1,7.1982421875,13,15,1,7.3505859375,14]}}
  #|{"textrec":{"m":[13,400,0],"r":[12.568359375,2.7421875,18,12.568359375,2.7421875,0]}}
  #|{"textrec":{"s":[24,700,0,"Dev"],"r":[0,1,17.075823068618774,15,1,1,13.365240812301636,16,2,1,12.759063005447388,17]}}
  #|{"textrec":{"m":[24,700,0],"r":[23.203125,5.0625,34,20.638916015625,3.361083984375,0]}}
  #|{"textrec":{"s":[16,600,0,"文件"],"r":[0,1,15.875486381322958,18,1,1,15.875486381322958,19]}}
  #|{"textrec":{"m":[16,600,0],"r":[15.46875,3.375,23,15.46875,3.375,0]}}
  #|{"textrec":{"s":[17,400,0,"对话"],"r":[0,1,16.851167315175097,20,1,1,16.851167315175097,21]}}
  #|{"textrec":{"m":[17,400,0],"r":[16.435546875,3.5859375,24,16.435546875,3.5859375,0]}}
  #|{"textrec":{"g":15,"r":[0,0,18,19,0,-18,0]}}
  #|{"textrec":{"g":16,"r":[19,0,15,16,-1,-14,0]}}
  #|{"textrec":{"g":17,"r":[35,0,15,15,-1,-14,0]}}
  #|{"textrec":{"ib":["02698e60df92657e",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"ib":["1d51432b25a425eb",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"s":[15,400,0,"搜索全部内容"],"r":[0,1,14.883268482490273,22,1,1,14.883268482490273,23,2,1,14.883268482490273,24,3,1,14.883268482490273,25,4,1,14.88326848249028,26,5,1,14.88326848249028,27]}}
  #|{"textrec":{"m":[15,400,0],"r":[14.501953125,3.1640625,21,14.501953125,3.1640625,0]}}
  #|{"textrec":{"s":[15,600,0,"今天"],"r":[0,1,14.883268482490273,28,1,1,14.883268482490273,29]}}
  #|{"textrec":{"m":[15,600,0],"r":[14.501953125,3.1640625,21,14.501953125,3.1640625,0]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 post:你好，我是测试用的 agent"],"r":[0,1,15.875486381322958,30,1,1,15.875486381322958,31,2,1,15.875486381322958,30,3,1,15.875486381322958,32,4,1,15.875486381322958,33,5,1,15.875486381322958,34,6,1,15.875486381322958,35,7,1,15.875486381322958,36,8,1,3.95001220703125,-1,9,1,9.824199676513672,37,10,1,9.432537078857422,38,11,1,8.471200942993164,39,12,1,5.973020553588867,40,13,1,4.952056884765625,41,14,1,15.875486381322958,42,15,1,15.875486381322958,43,16,1,16.09338521400778,44,17,1,15.875486381322958,45,18,1,15.875486381322958,46,19,1,15.87548638132293,32,20,1,15.875486381322958,33,21,1,15.875486381322958,47,22,1,15.875486381322958,34,23,1,3.95001220703125,-1,24,1,8.899068832397461,48,25,1,9.801153182983398,49,26,1,9.127458572387695,50,27,1,9.466253280639648,51,28,1,5.999713897705078,40]}}
  #|{"textrec":{"s":[14,400,0,"你好，我是测试用的 agent"],"r":[0,1,13.891050583657588,52,1,1,13.891050583657588,53,2,1,14.081712062256813,54,3,1,13.891050583657588,55,4,1,13.891050583657588,56,5,1,13.891050583657588,57,6,1,13.891050583657588,58,7,1,13.891050583657588,59,8,1,13.891050583657588,60,9,1,3.787109375000014,-1,10,1,7.57421875,61,11,1,8.380859375,62,12,1,7.84765625,63,13,1,8.0185546875,64,14,1,4.935546875,65]}}
  #|{"textrec":{"m":[14,400,0],"r":[13.53515625,2.953125,20,13.53515625,2.953125,0]}}
  #|{"textrec":{"s":[16,600,0,"…"],"r":[0,1,14.076484680175781,66]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 post:你好，我是测试用的…"],"r":[0,1,15.875486381322958,30,1,1,15.875486381322958,31,2,1,15.875486381322958,30,3,1,15.875486381322958,32,4,1,15.875486381322958,33,5,1,15.875486381322958,34,6,1,15.875486381322958,35,7,1,15.875486381322958,36,8,1,3.95001220703125,-1,9,1,9.824199676513672,37,10,1,9.432537078857422,38,11,1,8.471200942993164,39,12,1,5.973020553588867,40,13,1,4.952056884765625,41,14,1,15.875486381322958,42,15,1,15.875486381322958,43,16,1,16.09338521400778,44,17,1,15.875486381322958,45,18,1,15.875486381322958,46,19,1,15.87548638132293,32,20,1,15.875486381322958,33,21,1,15.875486381322958,47,22,1,15.875486381322958,34,23,1,14.076484680175781,66]}}
  #|{"textrec":{"s":[15,600,0,"studio"],"r":[0,1,8.000344634056091,67,1,1,5.658300518989563,68,2,1,8.93320620059967,69,3,1,9.332013130187988,70,4,1,3.8520312309265137,71,5,1,8.901597261428833,72]}}
  #|{"textrec":{"s":[16,400,0,"主目录"],"r":[0,1,15.875486381322958,73,1,1,15.875486381322958,74,2,1,15.875486381322958,75]}}
  #|{"textrec":{"m":[16,400,0],"r":[15.46875,3.375,23,15.46875,3.375,0]}}
  #|{"textrec":{"s":[16,400,0,"e2e-105609"],"r":[0,1,8.828125,76,1,1,9.3046875,77,2,1,8.7890625,76,3,1,7.234375,78,4,1,7.109375,79,5,1,9.765625,80,6,1,9.578125,81,7,1,9.875,82,8,1,9.765625,80,9,1,9.875,83]}}
  #|{"textrec":{"g":22,"r":[51,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":23,"r":[69,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":24,"r":[86,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":25,"r":[104,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":26,"r":[121,0,15,16,0,-13,0]}}
  #|{"textrec":{"g":27,"r":[137,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":28,"r":[154,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":29,"r":[172,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":30,"r":[190,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":31,"r":[208,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":32,"r":[226,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":33,"r":[244,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":34,"r":[263,0,16,17,0,-14,0]}}
  #|{"textrec":{"g":35,"r":[280,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":36,"r":[298,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":37,"r":[317,0,11,14,0,-10,0]}}
  #|{"textrec":{"g":38,"r":[329,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":39,"r":[341,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":40,"r":[353,0,8,14,-1,-12,0]}}
  #|{"textrec":{"g":41,"r":[362,0,5,12,0,-10,0]}}
  #|{"textrec":{"g":42,"r":[368,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":43,"r":[386,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":44,"r":[404,0,6,8,0,-4,0]}}
  #|{"textrec":{"g":45,"r":[411,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":46,"r":[430,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":47,"r":[448,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":66,"r":[465,0,14,6,0,-4,0]}}
  #|{"textrec":{"g":52,"r":[480,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":53,"r":[496,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":54,"r":[513,0,5,7,0,-3,0]}}
  #|{"textrec":{"g":55,"r":[519,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":56,"r":[536,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":57,"r":[552,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":58,"r":[568,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":59,"r":[585,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":60,"r":[601,0,14,16,0,-13,0]}}
  #|{"textrec":{"g":61,"r":[616,0,9,11,-1,-9,0]}}
  #|{"textrec":{"g":62,"r":[626,0,10,13,-1,-9,0]}}
  #|{"textrec":{"g":63,"r":[637,0,10,11,-1,-9,0]}}
  #|{"textrec":{"g":64,"r":[648,0,9,10,0,-9,0]}}
  #|{"textrec":{"g":65,"r":[658,0,7,13,-1,-11,0]}}
  #|{"textrec":{"ib":["33d1dfbf90932d3b",1241,64],"r":[17,17,17,17]}}
  #|{"textrec":{"ib":["182b7158e0c0cae1",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["d61ec6305f7d8c8b",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["a1e7be43eb966606",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"g":20,"r":[666,0,18,18,-1,-15,0]}}
  #|{"textrec":{"g":21,"r":[685,0,19,18,-1,-15,0]}}
  #|{"textrec":{"g":67,"r":[705,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":68,"r":[716,0,8,13,-1,-11,0]}}
  #|{"textrec":{"g":69,"r":[725,0,10,12,0,-10,0]}}
  #|{"textrec":{"g":70,"r":[736,0,11,15,-1,-13,0]}}
  #|{"textrec":{"g":71,"r":[748,0,6,14,-1,-13,0]}}
  #|{"textrec":{"g":72,"r":[755,0,11,12,-1,-10,0]}}
  #|{"textrec":{"ib":["4165e1c325ff4b32",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"ib":["7d024a54eca23c07",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"g":73,"r":[767,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":74,"r":[785,0,14,16,1,-13,0]}}
  #|{"textrec":{"g":75,"r":[800,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":76,"r":[818,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":77,"r":[830,0,10,14,0,-13,0]}}
  #|{"textrec":{"g":78,"r":[841,0,8,5,0,-7,0]}}
  #|{"textrec":{"g":79,"r":[850,0,7,14,0,-13,0]}}
  #|{"textrec":{"g":80,"r":[858,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":81,"r":[870,0,10,15,0,-13,0]}}
  #|{"textrec":{"g":82,"r":[881,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":83,"r":[893,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":18,"r":[905,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":19,"r":[924,0,17,17,-1,-14,0]}}
  #|{"textrec":{"ib":["2bb63fc1d380f765",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"s":[17,400,0,"设置"],"r":[0,1,16.851167315175097,84,1,1,16.851167315175097,85]}}
  #|{"textrec":{"s":[16,600,0,"e2e-105609"],"r":[0,1,9.127458572387695,50,1,1,9.717817306518555,86,2,1,9.100765228271484,50,3,1,7.363014221191406,87,4,1,7.594245910644531,88,5,1,10.31976318359375,89,6,1,10.035783767700195,90,7,1,10.3499755859375,91,8,1,10.31976318359375,89,9,1,10.3499755859375,92]}}
  #|{"textrec":{"s":[17,400,0,"文件"],"r":[0,1,16.851167315175097,93,1,1,16.851167315175097,94]}}
  #|{"textrec":{"g":84,"r":[942,0,19,18,-1,-15,0]}}
  #|{"textrec":{"g":85,"r":[962,0,18,17,-1,-14,0]}}
  #|{"textrec":{"s":[13,400,0,"2 个文件夹 · 2 个文件"],"r":[0,1,7.76953125,95,1,1,3.580078125,-1,2,1,12.898832684824903,96,3,1,12.898832684824903,97,4,1,12.898832684824903,98,5,1,12.898832684824903,99,6,1,3.580078125,-1,7,1,6.228545204222115,100,8,1,3.580078125,-1,9,1,7.76953125,95,10,1,3.580078125,-1,11,1,12.898832684824896,96,12,1,12.898832684824896,97,13,1,12.898832684824896,98]}}
  #|{"textrec":{"s":[15,400,0,"子文件夹"],"r":[0,1,14.883268482490273,101,1,1,14.883268482490273,102,2,1,14.883268482490273,103,3,1,14.883268482490273,104]}}
  #|{"textrec":{"s":[12,400,0,"22:29"],"r":[0,1,7.2421875,105,1,1,7.2421875,105,2,1,3.591796875,106,3,1,7.271484375,105,4,1,7.640625,107]}}
  #|{"textrec":{"m":[12,400,0],"r":[11.6015625,2.53125,17,11.6015625,2.53125,0]}}
  #|{"textrec":{"s":[15,400,0,"影音"],"r":[0,1,14.883268482490273,108,1,1,14.883268482490273,109]}}
  #|{"textrec":{"s":[15,400,0,"小说-e2e.txt"],"r":[0,1,14.883268482490273,110,1,1,14.883268482490273,111,2,1,6.8408203125,112,3,1,8.3349609375,113,4,1,8.78173828125,114,5,1,8.29833984375,113,6,1,4.072265625,115,7,1,5.068359375,116,8,1,7.6318359375,117,9,1,5.21484375,116]}}
  #|{"textrec":{"s":[12,400,0,"36 KB · 22:29"],"r":[0,1,7.5234375,118,1,1,7.640625,119,2,1,3.375,-1,3,1,7.904296875,120,4,1,7.88671875,121,5,1,3.375,-1,6,1,5.754933455713626,122,7,1,3.375,-1,8,1,7.2421875,105,9,1,7.2421875,105,10,1,3.591796875,106,11,1,7.271484375,105,12,1,7.640625,107]}}
  #|{"textrec":{"s":[15,400,0,"说明.txt"],"r":[0,1,14.883268482490273,111,1,1,14.883268482490273,123,2,1,4.072265625,115,3,1,5.068359375,116,4,1,7.6318359375,117,5,1,5.21484375,116]}}
  #|{"textrec":{"s":[12,400,0,"43 B · 22:29"],"r":[0,1,7.72265625,124,1,1,7.5234375,118,2,1,3.375,-1,3,1,7.88671875,121,4,1,3.375,-1,5,1,5.754933455713626,122,6,1,3.375,-1,7,1,7.2421875,105,8,1,7.2421875,105,9,1,3.591796875,106,10,1,7.271484375,105,11,1,7.640625,107]}}
  #|{"textrec":{"g":93,"r":[981,0,18,18,-1,-15,0]}}
  #|{"textrec":{"g":94,"r":[1000,0,18,18,-1,-15,0]}}
  #|{"textrec":{"g":95,"r":[1019,0,9,12,-1,-11,0]}}
  #|{"textrec":{"g":96,"r":[1029,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":97,"r":[1045,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":98,"r":[1061,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":99,"r":[1077,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":100,"r":[1093,0,4,5,1,-7,0]}}
  #|{"textrec":{"ib":["275a1f2a0cb12622",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"ib":["b17c2fa67cbec771",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"g":101,"r":[1098,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":102,"r":[1115,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":103,"r":[1133,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":104,"r":[1150,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":105,"r":[1167,0,9,11,-1,-10,0]}}
  #|{"textrec":{"g":106,"r":[1177,0,4,9,0,-7,0]}}
  #|{"textrec":{"g":107,"r":[1182,0,9,12,-1,-10,0]}}
  #|{"textrec":{"g":108,"r":[1192,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":109,"r":[1210,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":110,"r":[1227,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":111,"r":[1245,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":112,"r":[1263,0,7,4,0,-6,0]}}
  #|{"textrec":{"g":113,"r":[1271,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":114,"r":[1282,0,10,13,0,-12,0]}}
  #|{"textrec":{"g":115,"r":[1293,0,5,5,0,-3,0]}}
  #|{"textrec":{"g":116,"r":[1299,0,7,13,-1,-11,0]}}
  #|{"textrec":{"g":117,"r":[1307,0,10,10,-1,-9,0]}}
  #|{"textrec":{"g":118,"r":[1318,0,9,12,-1,-10,0]}}
  #|{"textrec":{"g":119,"r":[1328,0,9,12,-1,-10,0]}}
  #|{"textrec":{"g":120,"r":[1338,0,9,11,0,-10,0]}}
  #|{"textrec":{"g":121,"r":[1348,0,9,11,0,-10,0]}}
  #|{"textrec":{"g":122,"r":[1358,0,5,5,0,-7,0]}}
  #|{"textrec":{"g":123,"r":[1364,0,15,16,0,-13,0]}}
  #|{"textrec":{"g":124,"r":[1380,0,10,11,-1,-10,0]}}
  #|{"textrec":{"g":50,"r":[1391,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":86,"r":[1403,0,11,14,0,-13,0]}}
  #|{"textrec":{"g":87,"r":[1415,0,8,5,0,-7,0]}}
  #|{"textrec":{"g":88,"r":[1424,0,7,14,0,-13,0]}}
  #|{"textrec":{"g":89,"r":[1432,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":90,"r":[1444,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":91,"r":[1456,0,12,15,-1,-13,0]}}
  #|{"textrec":{"g":92,"r":[1469,0,12,15,-1,-13,0]}}
  #|{"textrec":{"ib":["0e910fb4d25445a3",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"ib":["ddfdc2820df8a676",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"ib":["b3685975cd23abc3",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"s":[16,600,0,"影音"],"r":[0,1,15.875486381322958,125,1,1,15.875486381322958,126]}}
  #|{"textrec":{"s":[17,400,0,"e2e-105609"],"r":[0,1,9.2802734375,127,1,1,9.78662109375,128,2,1,9.23876953125,127,3,1,7.5869140625,129,4,1,7.4541015625,130,5,1,10.2763671875,131,6,1,10.0771484375,132,7,1,10.392578125,133,8,1,10.2763671875,131,9,1,10.392578125,134]}}
  #|{"textrec":{"s":[17,400,0,"…"],"r":[0,1,13.248046875,135]}}
  #|{"textrec":{"s":[17,400,0,"e2e-105…"],"r":[0,1,9.2802734375,127,1,1,9.78662109375,128,2,1,9.23876953125,127,3,1,7.5869140625,129,4,1,7.4541015625,130,5,1,10.2763671875,131,6,1,9.78662109375,132,7,1,12.95751953125,136]}}
  #|{"textrec":{"s":[13,400,0,"e2e-105609"],"r":[0,1,7.3505859375,14,1,1,7.73779296875,95,2,1,7.31884765625,14,3,1,6.0556640625,137,4,1,5.9541015625,138,5,1,8.1123046875,139,6,1,7.9599609375,140,7,1,8.201171875,141,8,1,8.1123046875,139,9,1,8.201171875,142]}}
  #|{"textrec":{"s":[13,600,0,"影音"],"r":[0,1,12.898832684824903,143,1,1,12.898832684824903,144]}}
  #|{"textrec":{"m":[13,600,0],"r":[12.568359375,2.7421875,18,12.568359375,2.7421875,0]}}
  #|{"textrec":{"s":[13,400,0,"4 个文件"],"r":[0,1,8.2900390625,145,1,1,3.580078125,-1,2,1,12.898832684824903,96,3,1,12.898832684824903,97,4,1,12.898832684824903,98]}}
  #|{"textrec":{"s":[15,400,0,"片尾曲.m4a"],"r":[0,1,14.883268482490273,146,1,1,14.883268482490273,147,2,1,14.883268482490273,148,3,1,4.21875,115,4,1,12.8173828125,149,5,1,9.418945312499993,150,6,1,8.0419921875,151]}}
  #|{"textrec":{"s":[12,400,0,"44 KB · 22:29"],"r":[0,1,7.72265625,124,1,1,7.72265625,124,2,1,3.375,-1,3,1,7.904296875,120,4,1,7.88671875,121,5,1,3.375,-1,6,1,5.754933455713626,122,7,1,3.375,-1,8,1,7.2421875,105,9,1,7.2421875,105,10,1,3.591796875,106,11,1,7.271484375,105,12,1,7.640625,107]}}
  #|{"textrec":{"s":[15,400,0,"第01集.mp4"],"r":[0,1,14.883268482490273,152,1,1,11.0888671875,153,2,1,8.5986328125,154,3,1,14.883268482490273,155,4,1,4.21875,115,5,1,12.8173828125,149,6,1,8.9208984375,156,7,1,9.4189453125,150]}}
  #|{"textrec":{"s":[12,400,0,"2.2 MB · 22:29"],"r":[0,1,7.154296875,105,1,1,3.357421875,157,2,1,7.125,105,3,1,3.375,-1,4,1,10.48828125,158,5,1,7.88671875,121,6,1,3.375,-1,7,1,5.754933455713626,122,8,1,3.375,-1,9,1,7.2421875,105,10,1,7.2421875,105,11,1,3.591796875,106,12,1,7.271484375,105,13,1,7.640625,107]}}
  #|{"textrec":{"s":[15,400,0,"第01集.srt"],"r":[0,1,14.883268482490273,152,1,1,11.0888671875,153,2,1,8.5986328125,154,3,1,14.883268482490273,155,4,1,4.21875,115,5,1,7.6171875,159,6,1,5.5517578125,160,7,1,5.2880859375,116]}}
  #|{"textrec":{"s":[12,400,0,"97 B · 22:29"],"r":[0,1,7.5234375,107,1,1,6.71484375,161,2,1,3.375,-1,3,1,7.88671875,121,4,1,3.375,-1,5,1,5.754933455713626,122,6,1,3.375,-1,7,1,7.2421875,105,8,1,7.2421875,105,9,1,3.591796875,106,10,1,7.271484375,105,11,1,7.640625,107]}}
  #|{"textrec":{"s":[15,400,0,"第02集.mp4"],"r":[0,1,14.883268482490273,152,1,1,11.0888671875,153,2,1,10.693359375,114,3,1,14.883268482490273,155,4,1,4.21875,115,5,1,12.8173828125,149,6,1,8.9208984375,156,7,1,9.4189453125,150]}}
  #|{"textrec":{"s":[12,400,0,"451 KB · 22:29"],"r":[0,1,7.72265625,124,1,1,7.41796875,162,2,1,5.56640625,163,3,1,3.375,-1,4,1,7.904296875,120,5,1,7.88671875,121,6,1,3.375,-1,7,1,5.754933455713626,122,8,1,3.375,-1,9,1,7.2421875,105,10,1,7.2421875,105,11,1,3.591796875,106,12,1,7.271484375,105,13,1,7.640625,107]}}
  #|{"textrec":{"g":127,"r":[1482,0,11,13,-1,-11,0]}}
  #|{"textrec":{"g":128,"r":[1494,0,11,15,0,-14,0]}}
  #|{"textrec":{"g":129,"r":[1506,0,8,4,0,-7,0]}}
  #|{"textrec":{"g":130,"r":[1515,0,7,14,0,-13,0]}}
  #|{"textrec":{"g":131,"r":[1523,0,11,16,0,-14,0]}}
  #|{"textrec":{"g":132,"r":[1535,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":136,"r":[1547,0,14,6,-0.29052734375,-4,0]}}
  #|{"textrec":{"g":14,"r":[1562,0,9,10,-1,-8,0]}}
  #|{"textrec":{"g":137,"r":[1572,0,8,4,-1,-6,0]}}
  #|{"textrec":{"g":138,"r":[1581,0,7,12,-1,-11,0]}}
  #|{"textrec":{"g":139,"r":[1589,0,10,13,-1,-11,0]}}
  #|{"textrec":{"g":140,"r":[1600,0,10,13,-1,-11,0]}}
  #|{"textrec":{"g":141,"r":[1611,0,10,13,-1,-11,0]}}
  #|{"textrec":{"g":142,"r":[1622,0,10,13,-1,-11,0]}}
  #|{"textrec":{"g":145,"r":[1633,0,10,12,-1,-11,0]}}
  #|{"textrec":{"ib":["96f36fe05edfa445",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"ib":["97df5131f09b2974",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"g":146,"r":[1644,0,15,16,0,-13,0]}}
  #|{"textrec":{"g":147,"r":[1660,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":148,"r":[1677,0,14,16,0,-13,0]}}
  #|{"textrec":{"g":149,"r":[1692,0,13,11,0,-10,0]}}
  #|{"textrec":{"g":150,"r":[1706,0,11,13,-1,-12,0]}}
  #|{"textrec":{"g":151,"r":[1718,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":152,"r":[1729,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":153,"r":[1746,0,11,14,-1,-12,0]}}
  #|{"textrec":{"g":154,"r":[1758,0,8,13,-1,-12,0]}}
  #|{"textrec":{"g":155,"r":[1767,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":156,"r":[1784,0,10,14,0,-10,0]}}
  #|{"textrec":{"g":157,"r":[1795,0,4,5,0,-3,0]}}
  #|{"textrec":{"g":158,"r":[1800,0,11,11,0,-10,0]}}
  #|{"textrec":{"g":159,"r":[1812,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":160,"r":[1823,0,7,11,0,-10,0]}}
  #|{"textrec":{"g":161,"r":[1831,0,9,11,-1,-10,0]}}
  #|{"textrec":{"g":162,"r":[1841,0,9,12,-1,-10,0]}}
  #|{"textrec":{"g":163,"r":[1851,0,7,11,-1,-10,0]}}
  #|{"textrec":{"g":143,"r":[1859,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":144,"r":[1875,0,14,15,-1,-12,0]}}
  #|{"textrec":{"ib":["c63576325cefdb0c",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"g":125,"r":[1890,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":126,"r":[1909,0,17,17,-1,-14,0]}}
  #|{"textrec":{"s":[12,600,0,"0:00"],"r":[0,1,7.9741973876953125,164,1,1,3.9484176635742188,165,2,1,7.9741973876953125,164,3,1,7.9741973876953125,164]}}
  #|{"textrec":{"m":[12,600,0],"r":[11.6015625,2.53125,17,11.6015625,2.53125,0]}}
  #|{"textrec":{"s":[12,400,0," / --:--"],"r":[0,1,3.375,-1,1,1,3.65625,166,2,1,3.375,-1,3,1,5.66015625,167,4,1,5.66015625,167,5,1,3.5625,106,6,1,5.66015625,167,7,1,5.66015625,167]}}
  #|{"textrec":{"s":[12,600,0,"1×"],"r":[0,1,5.930059432983398,168,1,1,7.874007225036621,169]}}
  #|{"textrec":{"s":[15,600,0,"第01集.mp4"],"r":[0,1,14.883268482490273,170,1,1,11.60837173461914,171,2,1,9.053199291229248,172,3,1,14.883268482490273,173,4,1,4.701147079467773,174,5,1,13.406463861465454,175,6,1,9.268780946731567,176,7,1,9.83176589012146,177]}}
  #|{"textrec":{"s":[12,400,0,"2 / 3"],"r":[0,1,7.2421875,105,1,1,3.375,-1,2,1,3.65625,166,3,1,3.375,-1,4,1,7.5234375,118]}}
  #|{"textrec":{"g":164,"r":[1927,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":165,"r":[1938,0,4,10,0,-8,0]}}
  #|{"textrec":{"g":166,"r":[1943,0,6,14,-1,-10,0]}}
  #|{"textrec":{"g":167,"r":[1950,0,7,4,-1,-5,0]}}
  #|{"textrec":{"ib":["f00e470aace2a081",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["af0d7cb1109658d2",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"g":170,"r":[1958,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":171,"r":[1975,0,12,14,-1,-12,0]}}
  #|{"textrec":{"g":172,"r":[1988,0,8,13,-1,-12,0]}}
  #|{"textrec":{"g":173,"r":[1997,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":174,"r":[2014,0,5,6,0,-4,0]}}
  #|{"textrec":{"g":175,"r":[2020,0,14,11,0,-10,0]}}
  #|{"textrec":{"g":176,"r":[2035,0,10,14,0,-10,0]}}
  #|{"textrec":{"g":177,"r":[0,20,12,13,-1,-12,0]}}
  #|{"textrec":{"ib":["2d6cd96a3768a333",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["13aa32d5ea22b559",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["c58bfada23ab4c58",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["924e0a5889de9908",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"s":[12,400,0," / 0:20"],"r":[0,1,3.375,-1,1,1,3.65625,166,2,1,3.375,-1,3,1,7.55859375,178,4,1,3.591796875,106,5,1,7.271484375,105,6,1,7.55859375,178]}}
  #|{"textrec":{"g":178,"r":[13,20,9,12,-1,-10,0]}}
  #|{"textrec":{"g":168,"r":[23,20,7,11,-1,-10,0]}}
  #|{"textrec":{"g":169,"r":[31,20,9,9,-1,-8,0]}}
  #|{"textrec":{"ib":["9afe52c45983c87a",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["666e55c8b6341385",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["9312e605623e30af",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"s":[16,400,0,"第一句字幕"],"r":[0,1,15.875486381322958,179,1,1,15.875486381322958,180,2,1,15.875486381322958,181,3,1,15.875486381322958,182,4,1,15.875486381322958,183]}}
  #|{"textrec":{"g":179,"r":[41,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":180,"r":[59,20,17,4,-1,-8,0]}}
  #|{"textrec":{"g":181,"r":[77,20,16,17,-1,-14,0]}}
  #|{"textrec":{"g":182,"r":[94,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":183,"r":[112,20,18,17,-1,-14,0]}}
  #|{"textrec":{"s":[12,600,0,"0:01"],"r":[0,1,7.9741973876953125,164,1,1,3.9484176635742188,165,2,1,7.9741973876953125,164,3,1,5.930059432983398,168]}}
  #|{"textrec":{"s":[12,600,0,"0:15"],"r":[0,1,7.9741973876953125,164,1,1,3.9484176635742188,165,2,1,5.930059432983398,168,3,1,7.7612128257751465,184]}}
  #|{"textrec":{"g":184,"r":[131,20,10,12,-1,-10,0]}}
  #|{"textrec":{"s":[12,600,0,"0:20"],"r":[0,1,7.946366786956787,164,1,1,3.9406070709228516,165,2,1,7.562777996063232,185,3,1,7.9741973876953125,164]}}
  #|{"textrec":{"g":185,"r":[142,20,9,11,-1,-10,0]}}
  #|{"textrec":{"s":[14,400,0,"播放结束"],"r":[0,1,13.891050583657588,186,1,1,13.891050583657588,187,2,1,13.891050583657588,188,3,1,13.891050583657588,189]}}
  #|{"textrec":{"s":[14,400,0,"下一个：第02集.mp4"],"r":[0,1,13.891050583657588,190,1,1,13.891050583657588,191,2,1,13.891050583657588,192,3,1,14.081712062256813,193,4,1,13.891050583657588,194,5,1,10.41796875,195,6,1,10.048828125,196,7,1,13.891050583657588,197,8,1,4.005859375,198,9,1,12.03125,199,10,1,8.39453125,200,11,1,8.859375,201]}}
  #|{"textrec":{"g":186,"r":[152,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":187,"r":[169,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":188,"r":[186,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":189,"r":[202,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":190,"r":[219,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":191,"r":[235,20,15,4,-1,-7,0]}}
  #|{"textrec":{"g":192,"r":[251,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":193,"r":[268,20,5,10,1,-10,0]}}
  #|{"textrec":{"g":194,"r":[274,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":195,"r":[290,20,10,14,-1,-12,0]}}
  #|{"textrec":{"g":196,"r":[301,20,9,13,0,-12,0]}}
  #|{"textrec":{"g":197,"r":[311,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":198,"r":[327,20,4,5,0,-3,0]}}
  #|{"textrec":{"g":199,"r":[332,20,13,10,0,-9,0]}}
  #|{"textrec":{"g":200,"r":[346,20,9,13,0,-9,0]}}
  #|{"textrec":{"g":201,"r":[356,20,11,12,-1,-11,0]}}
  #|{"textrec":{"s":[15,600,0,"第02集.mp4"],"r":[0,1,14.883268482490273,170,1,1,11.60837173461914,171,2,1,11.069072484970093,202,3,1,14.883268482490273,173,4,1,4.701147079467773,174,5,1,13.406463861465454,175,6,1,9.268780946731567,176,7,1,9.83176589012146,177]}}
  #|{"textrec":{"s":[12,400,0,"3 / 3"],"r":[0,1,7.5234375,118,1,1,3.375,-1,2,1,3.65625,166,3,1,3.375,-1,4,1,7.5234375,118]}}
  #|{"textrec":{"g":202,"r":[368,20,11,13,-1,-12,0]}}
  #|{"textrec":{"s":[12,400,0," / 0:04"],"r":[0,1,3.375,-1,1,1,3.65625,166,2,1,3.375,-1,3,1,7.55859375,178,4,1,3.5625,106,5,1,7.55859375,178,6,1,7.72265625,124]}}
  #|{"textrec":{"s":[16,400,0,"片尾曲.m4a"],"r":[0,1,15.875486381322958,203,1,1,15.875486381322958,204,2,1,15.875486381322958,205,3,1,4.4375,206,4,1,13.609375,207,5,1,9.984375,208,6,1,8.515625,209]}}
  #|{"textrec":{"s":[15,600,0,"片尾曲.m4a"],"r":[0,1,14.883268482490273,210,1,1,14.883268482490273,211,2,1,14.883268482490273,212,3,1,4.701147079467773,174,4,1,13.406463861465454,175,5,1,9.831765890121453,177,6,1,8.40147078037262,213]}}
  #|{"textrec":{"s":[12,400,0,"1 / 3"],"r":[0,1,5.56640625,163,1,1,3.375,-1,2,1,3.65625,166,3,1,3.375,-1,4,1,7.5234375,118]}}
  #|{"textrec":{"g":203,"r":[380,20,15,17,0,-14,0]}}
  #|{"textrec":{"g":204,"r":[396,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":205,"r":[414,20,15,17,0,-14,0]}}
  #|{"textrec":{"g":206,"r":[430,20,5,5,0,-3,0]}}
  #|{"textrec":{"g":207,"r":[436,20,14,11,0,-10,0]}}
  #|{"textrec":{"g":208,"r":[451,20,12,14,-1,-13,0]}}
  #|{"textrec":{"g":209,"r":[464,20,10,12,-1,-10,0]}}
  #|{"textrec":{"g":210,"r":[475,20,15,16,0,-13,0]}}
  #|{"textrec":{"g":211,"r":[491,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":212,"r":[508,20,15,17,0,-14,0]}}
  #|{"textrec":{"g":213,"r":[524,20,10,12,-1,-10,0]}}
  #|{"textrec":{"s":[12,400,0," / 0:05"],"r":[0,1,3.375,-1,1,1,3.65625,166,2,1,3.375,-1,3,1,7.55859375,178,4,1,3.5625,106,5,1,7.55859375,178,6,1,7.41796875,162]}}
  #|{"textrec":{"ib":["d055295857a347b8",12668,64],"r":[56,56,56,56]}}
