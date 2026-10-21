// e2e/traces/sheet-drag.trace, made by scripts/trace.py from 12-sheet_drag.log: not edited by hand.

///|
/// What the app and its core said in the run, a line each.
pub let trace_sheet_drag : String =
  #|{"start":"base"}
  #|{"step":"drive-seed 032949"}
  #|{"env":{"MBUI_CLOUD":"http://127.0.0.1:18900","MBUI_CORE_ACCOUNT":"{\"sub\":\"alice\",\"email\":\"alice@example.test\",\"name\":\"Name of alice\",\"picture\":\"\",\"access\":\"-\",\"refresh\":\"-\",\"accessExpires\":1792524897}"}}
  #|{"out":{"id":1,"call":"client.device","params":{"client":"still.fail mbui","app":"desktop","userAgent":"Macintosh; Mac OS X"}},"w":1792524943610.512}
  #|{"in":{"id":1,"ok":null},"w":1792524943738.46}
  #|{"out":{"id":2,"subscribe":{"topic":"accounts"},"keyed":true},"w":1792524943738.487}
  #|{"out":{"id":3,"subscribe":{"topic":"prefs"},"keyed":true},"w":1792524943738.503}
  #|{"step":"# written by scripts/rerecord.sh from its test (src/sfreplay/emit.mbt): not edited by hand","w":1792524943740.696}
  #|{"step":"timeout 90000","w":1792524943740.705}
  #|{"step":"answered client.device","w":1792524943740.708}
  #|{"step":"answered client.focus","w":1792524943761.655}
  #|{"in":{"id":2,"value":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""}]},"w":1792524943827.887}
  #|{"in":{"id":3,"value":{"onlyMine":false,"onlyWatching":false,"onlyDecisions":false,"listFilter":{},"appearance":"system","rowPicture":"auto","absoluteTime":false,"lang":"zh","keys":{},"lastChat":{},"openChat":{},"chatTabs":{},"dropFiles":{},"driveViews":{},"resume":{},"stationUpdatesDismissed":{},"device":{"app":"desktop","phone":false,"handoff":false},"reader":{"size":18,"line":1.7,"margin":22,"face":"sans","indent":true,"paper":"follow"},"rails":{},"bars":{"sets":[["chats","files","profiles","stations"],["decisions","usage","connects","archive"]],"current":0},"barsBy":{}}},"w":1792524943827.909}
  #|{"out":{"id":4,"subscribe":{"topic":"workspaces"},"keyed":true},"w":1792524943827.932}
  #|{"out":{"id":5,"subscribe":{"topic":"status"},"keyed":true},"w":1792524943827.947}
  #|{"in":{"id":4,"value":[{"account":{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""},"workspaces":[{"id":"01M5DCN9EHV11TX62FVBT8G02C","name":"Dev","role":"owner","created_at":1792524592,"stations":1,"members":1,"relays":[],"time":{"created_at":{"past":true,"at":1792524592000,"ago":"6 分钟前","full":"10/21 03:29:52","until":"1 分钟内"}}}],"invitations":[],"relay_url":"http://127.0.0.1:18940","loaded":true,"beta":true}]},"w":1792524943844.555}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792524943844.57}
  #|{"out":{"id":6,"subscribe":{"topic":"lock","workspace":"01M5DCN9EHV11TX62FVBT8G02C"},"keyed":true},"w":1792524943844.599}
  #|{"out":{"id":7,"subscribe":{"topic":"chats","scope":"01M5DCN9EHV11TX62FVBT8G02C","mine":false},"keyed":true},"w":1792524943844.612}
  #|{"out":{"id":8,"subscribe":{"topic":"workspaceMarks","workspace":"01M5DCN9EHV11TX62FVBT8G02C"},"keyed":true},"w":1792524943844.733}
  #|{"out":{"id":9,"subscribe":{"topic":"status","workspace":"01M5DCN9EHV11TX62FVBT8G02C"},"keyed":true},"w":1792524943844.764}
  #|{"out":{"id":10,"call":"client.focus","params":{"visible":true,"focused":true,"workspace":"01M5DCN9EHV11TX62FVBT8G02C"}},"w":1792524943850.166}
  #|{"out":{"id":11,"subscribe":{"topic":"notify"},"keyed":true},"w":1792524943850.175}
  #|{"out":{"id":12,"subscribe":{"topic":"notify","workspace":"01M5DCN9EHV11TX62FVBT8G02C"},"keyed":true},"w":1792524943850.181}
  #|{"in":{"id":6,"value":{"available":true,"locked":false,"notice":true,"role":"owner","manages":true,"owner":true,"canSign":true,"signs":false,"me":{"device":"7508068c0838052834dcdd24dd864d54a9300b8708e8b2f2324424a37bc525fe","code":"2CS-XCW","kind":"app","confirmed":false,"waiting":false,"asked":false},"signers":0,"members":[],"stations":[{"id":"c008a2ee339e1d2873590d026fb43eabcc4b43ea9ae504c9d2c1d6517428b244","name":"studio","version":"0.1.0","online":true,"protected":false}],"protected":0,"requests":[],"renew":[],"attention":0}},"w":1792524943861.217}
  #|{"in":{"id":7,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"stations":[{"station":"01M5DCN9EHV11TX62FVBT8G02C/c008a2ee339e1d2873590d026fb43eabcc4b43ea9ae504c9d2c1d6517428b244","id":"c008a2ee339e1d2873590d026fb43eabcc4b43ea9ae504c9d2c1d6517428b244","name":"studio","state":"online"}],"loading":false,"days":[{"daysAgo":0,"at":1792524597114,"label":"今天","items":[{"id":"ember:c-680584e540","session":"ember:c-680584e540","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","agents":[{"key":"ember:c-680584e540","runtime":"claude","process":"warm","pending":0,"lastTurn":{"id":"bcf24f08-9b85-4698-bf0d-c70c9355816b","kind":"input","outcome":"completed","declared":"final","ending":"all_done","need":"answered the question that was asked","startedAt":1792524597028,"endedAt":1792524597117},"agentText":"默认模型","statusText":"已完成：answered the question that was asked"}],"last":{"seq":2,"authorKind":"agent","author":"ember:c-680584e540","text":"你好，我是测试用的 agent","createdAt":1792524597114,"by":{"kind":"agent","name":"agent","mine":false,"runtime":"claude","label":"agent"},"preview":"你好，我是测试用的 agent","time":{"createdAt":{"at":1792524597114,"ago":"6 分钟前","full":"10/21 03:29:57","until":"1 分钟内","past":true}}},"unread":true,"mine":true,"lastActiveAt":1792524597114,"station":"01M5DCN9EHV11TX62FVBT8G02C/c008a2ee339e1d2873590d026fb43eabcc4b43ea9ae504c9d2c1d6517428b244","stationName":"studio","time":{"lastActiveAt":{"at":1792524597114,"ago":"6 分钟前","full":"10/21 03:29:57","until":"1 分钟内","past":true}},"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"peopleText":"你 发起","clientKey":"new:chat-a35a0a154db00eb361","pinned":false,"tone":"done"}]}],"trouble":null,"members":1,"leading":"agents","glyph":{"online":1,"dim":0,"connecting":0,"failing":0,"working":0,"summary":"studio","label":"1 台 station，1 台在线"},"note":{"reading":false,"text":null,"failing":[],"empty":false}}},"w":1792524943861.247}
  #|{"in":{"id":8,"value":{"workspaces":{"01M5DCN9EHV11TX62FVBT8G02C":{"alert":0,"unread":1,"tone":"done","label":"1 个有新消息","badge":0,"items":[],"mineTone":"done"}},"badge":0,"badgeCounts":"attention","badgeKinds":{"on":true,"wait":true,"failed":true,"done":false,"message":false}}},"w":1792524943861.267}
  #|{"in":{"id":9,"value":{"items":[]}},"w":1792524943861.272}
  #|{"in":{"id":10,"ok":null},"w":1792524943861.275}
  #|{"in":{"id":11,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792524943861.28}
  #|{"in":{"id":12,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792524943861.284}
  #|{"out":{"id":13,"subscribe":{"topic":"longJobs","scope":"01M5DCN9EHV11TX62FVBT8G02C"},"keyed":true},"w":1792524943861.312}
  #|{"out":{"id":14,"call":"notify.permission","params":{"state":"unknown"}},"w":1792524943863.969}
  #|{"in":{"id":13,"value":{"groups":[]}},"w":1792524943879.621}
  #|{"in":{"id":14,"ok":null},"w":1792524943879.626}
  #|{"step":"answered notify.permission","w":1792524943879.882}
  #|{"step":"until 端到端测试","w":1792524943894.734}
  #|{"step":"tap =Dev","w":1792524943894.746}
  #|{"step":"tap =Dev","acted":true,"w":1792524943911.494}
  #|{"step":"rest","w":1792524943931.584}
  #|{"step":"now until 切换 workspace","w":1792524945394.817}
  #|{"step":"dragon 0 -300 400 切换 workspace","w":1792524945394.828}
  #|{"step":"dragon 0 -300 400 切换 workspace","acted":true,"w":1792524945411.557}
  #|{"step":"rest","w":1792524945828.275}
  #|{"in":{"id":5,"value":{"state":"slow","text":"正在连接 studio · 2 秒 · 共 2 项","items":[{"state":"slow","text":"正在连接 studio","detail":"已等待 2 秒"},{"state":"slow","text":"studio 打开实时更新","detail":"已等待 2 秒，尚未收到数据"}]}},"w":1792524946011.229}
  #|{"in":{"id":9,"value":{"state":"slow","text":"正在连接 studio · 2 秒 · 共 2 项","items":[{"state":"slow","text":"正在连接 studio","detail":"已等待 2 秒"},{"state":"slow","text":"studio 打开实时更新","detail":"已等待 2 秒，尚未收到数据"}]}},"w":1792524946011.25}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792524946777.896}
  #|{"in":{"id":9,"value":{"items":[]}},"w":1792524946777.916}
  #|{"in":{"id":7,"delta":[{"path":["days"],"key":["daysAgo"],"patch":0,"ops":[{"path":["items"],"key":["station","id"],"patch":["01M5DCN9EHV11TX62FVBT8G02C/c008a2ee339e1d2873590d026fb43eabcc4b43ea9ae504c9d2c1d6517428b244","ember:c-680584e540"],"ops":[{"path":["agents",0,"process"],"set":"cold"},{"path":["clientKey"],"remove":true}]}]}]},"w":1792524946961.217}
  #|{"step":"now dragon 0 640 400 切换 workspace","w":1792524947144.856}
  #|{"step":"now dragon 0 640 400 切换 workspace","acted":true,"w":1792524947161.454}
  #|{"step":"rest","w":1792524947578.274}
  #|{"step":"now gone 切换 workspace","w":1792524948961.458}
  #|{"step":"tap icon:ling","w":1792524948961.468}
  #|{"step":"tap icon:ling","acted":true,"w":1792524948978.067}
  #|{"out":{"id":15,"subscribe":{"topic":"newChat","scope":"01M5DCN9EHV11TX62FVBT8G02C"},"keyed":true},"w":1792524948994.643}
  #|{"step":"answered machineSessions.list","w":1792524948995.239}
  #|{"in":{"id":15,"value":{"kept":"","stations":[{"station":"01M5DCN9EHV11TX62FVBT8G02C/c008a2ee339e1d2873590d026fb43eabcc4b43ea9ae504c9d2c1d6517428b244","id":"c008a2ee339e1d2873590d026fb43eabcc4b43ea9ae504c9d2c1d6517428b244","name":"studio","summary":"正在连接","face":"idle","line":"在线","online":true,"reconnecting":false,"lastSeen":1792524598,"version":"0.1.0","link":{"state":"online"},"runtimes":[{"runtime":"claude","models":["claude-sonnet-5-5"]}],"models":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792524946741,"time":{"checkedAt":{"at":1792524946741,"ago":"刚刚","full":"10/21 03:35:46","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"overview":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null,"summaryText":"最近 7 天检查了 0 个 chat","changeText":null}},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","email":"alice@example.test","name":"Name of alice","sub":"alice","role":"owner","workspace":"01M5DCN9EHV11TX62FVBT8G02C","device":"7508068c0838052834dcdd24dd864d54a9300b8708e8b2f2324424a37bc525fe"},"connects":[],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792524946637,"time":{"checkedAt":{"at":1792524946637,"ago":"刚刚","full":"10/21 03:35:46","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792524946741,"time":{"checkedAt":{"at":1792524946741,"ago":"刚刚","full":"10/21 03:35:46","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]}],"processes":[],"counts":{"sessions":1,"running":0,"warm":0},"mesh":{"state":"running","origin":"http://127.0.0.1:18900","station":"c008a2ee339e1d2873590d026fb43eabcc4b43ea9ae504c9d2c1d6517428b244","workspace":"Dev","workspaceId":"01M5DCN9EHV11TX62FVBT8G02C","name":"studio"},"slackUsers":[],"slackTeams":[],"slackApps":[],"feishuRegistrations":[],"disk":{"freeBytes":66012348416,"totalBytes":245107195904},"logins":[],"machineLogins":[],"sharing":true,"consoleSignIn":true,"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"google","name":"Google Gemini","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xai","name":"xAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"mistral","name":"Mistral","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"deepseek","name":"DeepSeek","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen","name":"Qwen","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai","name":"Kimi","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai","name":"Z.ai","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax","name":"MiniMax","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ant-ling","name":"Ant Ling","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"jev","name":"Jev","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen-cn","name":"Qwen (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"openrouter","name":"OpenRouter","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"opencode","name":"OpenCode Zen","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"groq","name":"Groq","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"together","name":"Together AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"fireworks","name":"Fireworks","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cerebras","name":"Cerebras","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"huggingface","name":"Hugging Face","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"nvidia","name":"NVIDIA","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"baseten","name":"Baseten","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ollama","name":"Ollama","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"custom","name":"Custom","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""}],"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792524944291},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.304","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792524944291},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792524944291},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792524944291},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","latest":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792524944291}],"processesText":"没有运行中的 agent 进程","agentEnv":[],"drive":{"roots":[],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false}},"betaOffered":false,"way":{"path":"直连","via":"direct"},"time":{"lastSeen":{"at":1792524598000,"ago":"6 分钟前","full":"10/21 03:29:58","until":"1 分钟内","past":true}},"joined":false}],"any":true,"station":{"station":"01M5DCN9EHV11TX62FVBT8G02C/c008a2ee339e1d2873590d026fb43eabcc4b43ea9ae504c9d2c1d6517428b244","id":"c008a2ee339e1d2873590d026fb43eabcc4b43ea9ae504c9d2c1d6517428b244","name":"studio","summary":"正在连接","face":"idle","line":"在线","online":true,"reconnecting":false,"lastSeen":1792524598,"version":"0.1.0","link":{"state":"online"},"runtimes":[{"runtime":"claude","models":["claude-sonnet-5-5"]}],"models":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792524946741,"time":{"checkedAt":{"at":1792524946741,"ago":"刚刚","full":"10/21 03:35:46","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"overview":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null,"summaryText":"最近 7 天检查了 0 个 chat","changeText":null}},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","email":"alice@example.test","name":"Name of alice","sub":"alice","role":"owner","workspace":"01M5DCN9EHV11TX62FVBT8G02C","device":"7508068c0838052834dcdd24dd864d54a9300b8708e8b2f2324424a37bc525fe"},"connects":[],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792524946637,"time":{"checkedAt":{"at":1792524946637,"ago":"刚刚","full":"10/21 03:35:46","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792524946741,"time":{"checkedAt":{"at":1792524946741,"ago":"刚刚","full":"10/21 03:35:46","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]}],"processes":[],"counts":{"sessions":1,"running":0,"warm":0},"mesh":{"state":"running","origin":"http://127.0.0.1:18900","station":"c008a2ee339e1d2873590d026fb43eabcc4b43ea9ae504c9d2c1d6517428b244","workspace":"Dev","workspaceId":"01M5DCN9EHV11TX62FVBT8G02C","name":"studio"},"slackUsers":[],"slackTeams":[],"slackApps":[],"feishuRegistrations":[],"disk":{"freeBytes":66012348416,"totalBytes":245107195904},"logins":[],"machineLogins":[],"sharing":true,"consoleSignIn":true,"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"google","name":"Google Gemini","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xai","name":"xAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"mistral","name":"Mistral","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"deepseek","name":"DeepSeek","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen","name":"Qwen","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai","name":"Kimi","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai","name":"Z.ai","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax","name":"MiniMax","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ant-ling","name":"Ant Ling","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"jev","name":"Jev","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen-cn","name":"Qwen (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"openrouter","name":"OpenRouter","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"opencode","name":"OpenCode Zen","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"groq","name":"Groq","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"together","name":"Together AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"fireworks","name":"Fireworks","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cerebras","name":"Cerebras","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"huggingface","name":"Hugging Face","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"nvidia","name":"NVIDIA","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"baseten","name":"Baseten","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ollama","name":"Ollama","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"custom","name":"Custom","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""}],"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792524944291},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.304","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792524944291},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792524944291},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792524944291},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","latest":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792524944291}],"processesText":"没有运行中的 agent 进程","agentEnv":[],"drive":{"roots":[],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false}},"betaOffered":false,"way":{"path":"直连","via":"direct"},"time":{"lastSeen":{"at":1792524598000,"ago":"6 分钟前","full":"10/21 03:29:58","until":"1 分钟内","past":true}},"joined":false},"model":{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792524946741,"time":{"checkedAt":{"at":1792524946741,"ago":"刚刚","full":"10/21 03:35:46","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}},"runtime":"claude","efforts":["low","medium","high","xhigh","max"],"accounts":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792524946741,"time":{"checkedAt":{"at":1792524946741,"ago":"刚刚","full":"10/21 03:35:46","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}],"pickAccount":false,"waiting":false,"pick":{"fastAvailable":false,"options":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792524946741,"time":{"checkedAt":{"at":1792524946741,"ago":"刚刚","full":"10/21 03:35:46","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]},"availability":"here"}],"runtimeFixed":false,"value":{"model":"claude-sonnet-5-5","runtime":"claude"},"valueOption":{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792524946741,"time":{"checkedAt":{"at":1792524946741,"ago":"刚刚","full":"10/21 03:35:46","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]},"availability":"here"},"draft":{"model":"claude-sonnet-5-5","runtime":"claude"},"option":"claude-sonnet-5-5","runtimes":[],"efforts":["low","medium","high","xhigh","max"],"accounts":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792524946741,"time":{"checkedAt":{"at":1792524946741,"ago":"刚刚","full":"10/21 03:35:46","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}],"who":"账号","autoNote":"额度用完或登录失效时自动切换","changed":false,"was":["Sonnet 5.5","默认深度","自动 · "],"becomes":["Sonnet 5.5","默认深度","自动分配"],"modelText":"Sonnet 5.5","maker":{"id":"anthropic","name":"Anthropic"},"accountText":"自动分配","accountNote":"额度用完或登录失效时自动切换","accountWarn":false,"saveText":"无变更"},"frequent":[]}},"w":1792524949011.421}
  #|{"out":{"id":16,"call":"machineSessions.list","params":{"station":"01M5DCN9EHV11TX62FVBT8G02C/c008a2ee339e1d2873590d026fb43eabcc4b43ea9ae504c9d2c1d6517428b244"}},"w":1792524949017.196}
  #|{"out":{"id":17,"call":"draft.get","params":{"key":"new:01M5DCN9EHV11TX62FVBT8G02C/c008a2ee339e1d2873590d026fb43eabcc4b43ea9ae504c9d2c1d6517428b244"}},"w":1792524949017.208}
  #|{"in":{"id":17,"ok":{"text":"","quotes":[],"files":[],"id":"draft-a623c05a167f9b125a"}},"w":1792524949027.886}
  #|{"in":{"id":16,"ok":{"sessions":[]}},"w":1792524949027.913}
  #|{"step":"answered draft.get","w":1792524949044.979}
  #|{"in":{"id":15,"delta":[{"path":["station","overview","disk","freeBytes"],"set":66012172288},{"path":["stations",0,"overview","disk","freeBytes"],"set":66012172288}]},"w":1792524949061.218}
  #|{"step":"wait 380","w":1792524949061.574}
  #|{"in":{"id":15,"delta":[{"path":["station","host"],"set":{"hostname":"3720-Mac-mini-1","os":"macOS 27.0.1","arch":"arm64","cpus":10,"cpuModel":"Apple M4","load":0.9,"cpuBusy":0.17,"uptimeSec":4311,"memory":{"totalBytes":17179869184,"usedBytes":8858796032,"swapUsedBytes":358738821},"disk":{"path":"/tmp/mbe2e-C/data","totalBytes":245107195904,"freeBytes":66012135424},"emberRssBytes":140015224,"checkedAt":1792524949041,"summary":"10 核 · 16 GB","line":"macOS 27.0.1 · 10 核 · 16 GB · 已运行 0 天","facts":["3720-Mac-mini-1","macOS 27.0.1","arm64 · 10 核","已运行 1 小时"],"meters":[{"label":"CPU","short":"CPU","percent":17,"left":83,"level":"ok","value":"17%","remaining":"空闲 83%","big":"83","unit":"%","title":"CPU 空闲","total":"负载 9.0","note":"负载 9.0 · Apple M4"},{"label":"内存","short":"内存","percent":52,"left":48,"level":"ok","value":"8.3 GB / 16.0 GB","remaining":"剩 7.7 G","big":"7.7","unit":"GB","title":"内存剩","total":"共 16 GB","note":"swap 0.3 GB"},{"label":"磁盘","short":"磁盘","percent":73,"left":27,"level":"ok","value":"剩余 61.5 GB / 228 GB","remaining":"剩 61.5 G","big":"61.5","unit":"GB","title":"磁盘剩","total":"共 228 GB"}],"identity":"Apple M4 · 16 GB · macOS 27.0.1","details":[{"label":"主机名","value":"3720-Mac-mini-1"},{"label":"芯片","value":"Apple M4 · 10 核 · arm64"},{"label":"已运行","value":"1 小时"},{"label":"still.fail","value":"进程占用 134 MB"}],"usage":"内存 8.3 GB / 16.0 GB · 磁盘 剩余 61.5 GB / 228 GB","emberText":"still.fail 134 MB"}},{"path":["station","line"],"set":"Apple M4"},{"path":["station","summary"],"set":"空闲 · Apple M4 · 16 GB · macOS 27.0.1"},{"path":["stations",0,"host"],"set":{"hostname":"3720-Mac-mini-1","os":"macOS 27.0.1","arch":"arm64","cpus":10,"cpuModel":"Apple M4","load":0.9,"cpuBusy":0.17,"uptimeSec":4311,"memory":{"totalBytes":17179869184,"usedBytes":8858796032,"swapUsedBytes":358738821},"disk":{"path":"/tmp/mbe2e-C/data","totalBytes":245107195904,"freeBytes":66012135424},"emberRssBytes":140015224,"checkedAt":1792524949041,"summary":"10 核 · 16 GB","line":"macOS 27.0.1 · 10 核 · 16 GB · 已运行 0 天","facts":["3720-Mac-mini-1","macOS 27.0.1","arm64 · 10 核","已运行 1 小时"],"meters":[{"label":"CPU","short":"CPU","percent":17,"left":83,"level":"ok","value":"17%","remaining":"空闲 83%","big":"83","unit":"%","title":"CPU 空闲","total":"负载 9.0","note":"负载 9.0 · Apple M4"},{"label":"内存","short":"内存","percent":52,"left":48,"level":"ok","value":"8.3 GB / 16.0 GB","remaining":"剩 7.7 G","big":"7.7","unit":"GB","title":"内存剩","total":"共 16 GB","note":"swap 0.3 GB"},{"label":"磁盘","short":"磁盘","percent":73,"left":27,"level":"ok","value":"剩余 61.5 GB / 228 GB","remaining":"剩 61.5 G","big":"61.5","unit":"GB","title":"磁盘剩","total":"共 228 GB"}],"identity":"Apple M4 · 16 GB · macOS 27.0.1","details":[{"label":"主机名","value":"3720-Mac-mini-1"},{"label":"芯片","value":"Apple M4 · 10 核 · arm64"},{"label":"已运行","value":"1 小时"},{"label":"still.fail","value":"进程占用 134 MB"}],"usage":"内存 8.3 GB / 16.0 GB · 磁盘 剩余 61.5 GB / 228 GB","emberText":"still.fail 134 MB"}},{"path":["stations",0,"line"],"set":"Apple M4"},{"path":["stations",0,"summary"],"set":"空闲 · Apple M4 · 16 GB · macOS 27.0.1"}]},"w":1792524949194.61}
  #|{"step":"now until 想让 agent 做什么？","w":1792524949445.75}
  #|{"step":"tap =studio","w":1792524949445.828}
  #|{"step":"tap =studio","acted":true,"w":1792524949462.665}
  #|{"step":"rest","w":1792524949488.958}
  #|{"step":"now until 选择运行的 station","w":1792524950929.479}
  #|{"step":"dragon 0 40 304 选择运行的 station","w":1792524950929.52}
  #|{"step":"dragon 0 40 304 选择运行的 station","acted":true,"w":1792524950946.063}
  #|{"step":"rest","w":1792524951279.379}
  #|{"step":"now until 选择运行的 station","w":1792524952596.004}
  #|{"step":"dragon 0 200 304 选择运行的 station","w":1792524952596.045}
  #|{"step":"dragon 0 200 304 选择运行的 station","acted":true,"w":1792524952612.835}
  #|{"step":"rest","w":1792524952946.041}
  #|{"step":"now gone 选择运行的 station","w":1792524954362.547}
  #|{"step":"tap =studio","w":1792524954362.603}
  #|{"step":"tap =studio","acted":true,"w":1792524954379.161}
  #|{"step":"rest","w":1792524954396.354}
  #|{"step":"now tap1 =studio","w":1792524955845.979}
  #|{"step":"now tap1 =studio","acted":true,"w":1792524955862.691}
  #|{"out":{"id":18,"call":"newChat.pick","params":{"station":"c008a2ee339e1d2873590d026fb43eabcc4b43ea9ae504c9d2c1d6517428b244","scope":"01M5DCN9EHV11TX62FVBT8G02C"}},"w":1792524955878.272}
  #|{"step":"answered newChat.pick","w":1792524955879.493}
  #|{"in":{"id":18,"ok":null},"w":1792524955894.57}
  #|{"step":"rest","w":1792524955912.719}
  #|{"in":{"id":15,"delta":[{"path":["kept"],"set":"c008a2ee339e1d2873590d026fb43eabcc4b43ea9ae504c9d2c1d6517428b244"}]},"w":1792524956077.911}
  #|{"step":"now gone 选择运行的 station","w":1792524957345.821}
  #|{"step":"tap =取消","w":1792524957345.861}
  #|{"step":"tap =取消","acted":true,"w":1792524957362.522}
  #|{"step":"wait 380","w":1792524957380.731}
  #|{"step":"now until 端到端测试","w":1792524957762.747}
  #|{"step":"rest","w":1792524957762.799}
  #|{"step":"now rest","w":1792524958145.642}
  #|{"step":"","w":1792524958162.398}
  #|{"textrec":{"ib":["bfd9b0d6dc602826",12668,64],"r":[56,56,56,56]}}
  #|{"textrec":{"s":[13,400,0,"正在读取你的 workspace"],"r":[0,1,12.898832684824903,0,1,1,12.898832684824903,1,2,1,12.898832684824903,2,3,1,12.898832684824903,3,4,1,12.898832684824896,4,5,1,12.898832684824896,5,6,1,3.580078125,-1,7,1,9.8642578125,6,8,1,7.4775390625,7,9,1,4.875,8,10,1,6.85546875,9,11,1,6.6015625,10,12,1,7.8583984375,11,13,1,7.0966796875,12,14,1,7.1982421875,13,15,1,7.3505859375,14]}}
  #|{"textrec":{"m":[13,400,0],"r":[12.568359375,2.7421875,18]}}
  #|{"textrec":{"s":[24,700,0,"Dev"],"r":[0,1,17.075823068618774,15,1,1,13.365240812301636,16,2,1,12.759063005447388,17]}}
  #|{"textrec":{"m":[24,700,0],"r":[23.203125,5.0625,34]}}
  #|{"textrec":{"g":15,"r":[0,0,18,19,0,-18,0]}}
  #|{"textrec":{"g":16,"r":[19,0,15,16,-1,-14,0]}}
  #|{"textrec":{"g":17,"r":[35,0,15,15,-1,-14,0]}}
  #|{"textrec":{"ib":["02698e60df92657e",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"ib":["1d51432b25a425eb",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"ib":["bef2954d97ce1d9f",6508,64],"r":[40,40,40,40]}}
  #|{"textrec":{"ib":["fdb526ba00f881f4",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["a7ccae3554fe46cf",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["31d8ec32aedeae00",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["c8ac90bf691295f0",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"s":[15,400,0,"搜索全部内容"],"r":[0,1,14.883268482490273,18,1,1,14.883268482490273,19,2,1,14.883268482490273,20,3,1,14.883268482490273,21,4,1,14.88326848249028,22,5,1,14.88326848249028,23]}}
  #|{"textrec":{"m":[15,400,0],"r":[14.501953125,3.1640625,21]}}
  #|{"textrec":{"s":[15,600,0,"今天"],"r":[0,1,14.883268482490273,24,1,1,14.883268482490273,25]}}
  #|{"textrec":{"m":[15,600,0],"r":[14.501953125,3.1640625,21]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 post:你好，我是测试用的 agent"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,26,3,1,15.875486381322958,28,4,1,15.875486381322958,29,5,1,15.875486381322958,30,6,1,15.875486381322958,31,7,1,15.875486381322958,32,8,1,3.95001220703125,-1,9,1,9.824199676513672,33,10,1,9.432537078857422,34,11,1,8.471200942993164,35,12,1,5.973020553588867,36,13,1,4.952056884765625,37,14,1,15.875486381322958,38,15,1,15.875486381322958,39,16,1,16.09338521400778,40,17,1,15.875486381322958,41,18,1,15.875486381322958,42,19,1,15.87548638132293,28,20,1,15.875486381322958,29,21,1,15.875486381322958,43,22,1,15.875486381322958,30,23,1,3.95001220703125,-1,24,1,8.899068832397461,44,25,1,9.801153182983398,45,26,1,9.127458572387695,46,27,1,9.466253280639648,47,28,1,5.999713897705078,36]}}
  #|{"textrec":{"m":[16,600,0],"r":[15.46875,3.375,23]}}
  #|{"textrec":{"s":[14,400,0,"你好，我是测试用的 agent"],"r":[0,1,13.891050583657588,48,1,1,13.891050583657588,49,2,1,14.081712062256813,50,3,1,13.891050583657588,51,4,1,13.891050583657588,52,5,1,13.891050583657588,53,6,1,13.891050583657588,54,7,1,13.891050583657588,55,8,1,13.891050583657588,56,9,1,3.787109375000014,-1,10,1,7.57421875,57,11,1,8.380859375,58,12,1,7.84765625,59,13,1,8.0185546875,60,14,1,4.935546875,61]}}
  #|{"textrec":{"m":[14,400,0],"r":[13.53515625,2.953125,20]}}
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
  #|{"textrec":{"ib":["8bf9607b651cec61",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["d61ec6305f7d8c8b",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"s":[17,700,0,"切换 workspace"],"r":[0,1,16.851167315175097,63,1,1,16.851167315175097,64,2,1,3.951171875,-1,3,1,13.783447265625,65,4,1,9.915283203125,66,5,1,6.96435546875,67,6,1,9.60400390625,68,7,1,9.010498046875,69,8,1,10.56689453125,70,9,1,9.591552734375,71,10,1,9.55419921875,72,11,1,9.782470703125,73]}}
  #|{"textrec":{"m":[17,700,0],"r":[16.435546875,3.5859375,24]}}
  #|{"textrec":{"s":[15,400,0,"登录其他账号"],"r":[0,1,14.883268482490273,74,1,1,14.883268482490273,75,2,1,14.883268482490273,76,3,1,14.883268482490273,77,4,1,14.88326848249028,78,5,1,14.88326848249028,79]}}
  #|{"textrec":{"s":[12,400,0,"保留已登录账号，添加另一个账号"],"r":[0,1,11.918287937743191,80,1,1,11.918287937743191,81,2,1,11.918287937743195,82,3,1,11.918287937743187,83,4,1,11.918287937743187,84,5,1,11.918287937743187,85,6,1,11.918287937743187,86,7,1,12.081712062256813,87,8,1,11.918287937743187,88,9,1,11.918287937743187,89,10,1,11.918287937743187,90,11,1,11.918287937743202,91,12,1,11.918287937743202,92,13,1,11.918287937743202,85,14,1,11.918287937743202,86]}}
  #|{"textrec":{"m":[12,400,0],"r":[11.6015625,2.53125,17]}}
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
  #|{"textrec":{"m":[17,400,0],"r":[16.435546875,3.5859375,24]}}
  #|{"textrec":{"m":[16,400,0],"r":[15.46875,3.375,23]}}
  #|{"textrec":{"s":[22,700,0,"想让 agent 做什么？"],"r":[0,1,20.94548872180451,125,1,1,20.94548872180451,126,2,1,4.717369616031647,-1,3,1,12.220596134662628,127,4,1,13.331922113895416,128,5,1,12.428017258644104,129,6,1,12.945789515972137,130,7,1,8.15379598736763,131,8,1,4.717369616031647,-1,9,1,20.94548872180451,132,10,1,20.94548872180451,133,11,1,20.94548872180451,134,12,1,10.607142857142861,135]}}
  #|{"textrec":{"m":[22,700,0],"r":[21.26953125,4.640625,31]}}
  #|{"textrec":{"s":[14,400,0,"描述要做的事。它会在 studio 上使用所选模型新建会话。"],"r":[0,1,13.891050583657588,136,1,1,13.891050583657588,137,2,1,13.891050583657588,138,3,1,13.891050583657588,139,4,1,13.891050583657588,56,5,1,13.891050583657588,140,6,1,14.081712062256813,141,7,1,13.891050583657588,142,8,1,13.891050583657588,143,9,1,13.891050583657588,144,10,1,3.787109375,-1,11,1,7.1435546875,145,12,1,4.9013671875,61,13,1,8.0185546875,146,14,1,8.44921875,147,15,1,3.30859375,148,16,1,8.12109375,149,17,1,3.787109375,-1,18,1,13.891050583657574,150,19,1,13.891050583657602,151,20,1,13.891050583657602,55,21,1,13.891050583657602,152,22,1,13.891050583657602,153,23,1,13.891050583657602,154,24,1,13.891050583657602,155,25,1,13.891050583657602,156,26,1,13.891050583657602,157,27,1,13.891050583657602,143,28,1,13.891050583657602,158,29,1,7.081712062256827,141]}}
  #|{"textrec":{"s":[13,400,0,"studio"],"r":[0,1,6.69677734375,10,1,1,4.61474609375,159,2,1,7.50927734375,160,3,1,7.9091796875,161,4,1,3.1357421875,162,5,1,7.6044921875,7]}}
  #|{"textrec":{"s":[13,400,0,"Sonnet 5.5 · 默认深度"],"r":[0,1,8.20751953125,163,1,1,7.6044921875,7,2,1,7.50927734375,164,3,1,7.50927734375,164,4,1,7.3505859375,14,5,1,4.646484375,159,6,1,3.580078125,-1,7,1,7.73779296875,165,8,1,3.354736328125,166,9,1,7.753662109375,165,10,1,3.580078125,-1,11,1,6.228545204222115,167,12,1,3.580078125,-1,13,1,12.898832684824896,168,14,1,12.898832684824896,169,15,1,12.898832684824896,170,16,1,12.898832684824896,171]}}
  #|{"textrec":{"g":122,"r":[1430,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":123,"r":[1449,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":124,"r":[1468,0,18,18,-1,-15,0]}}
  #|{"textrec":{"ib":["a1e7be43eb966606",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"ib":["504a4df6beac534a",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["c5e03166c48d7075",105988,256],"r":[230,115,230,115]}}
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
  #|{"textrec":{"ib":["2b45ffca62dc37ab",1382,64],"r":[18,18,18,18]}}
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
