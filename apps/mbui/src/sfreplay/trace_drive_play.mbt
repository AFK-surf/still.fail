// e2e/traces/drive-play.trace, made by scripts/trace.py from 02-drive_play.log: not edited by hand.

///|
/// What the app and its core said in the run, a line each.
pub let trace_drive_play : String =
  #|{"step":"drive-media 105609"}
  #|{"env":{"MBUI_CLOUD":"http://127.0.0.1:18950","MBUI_CORE_ACCOUNT":"{\"sub\":\"alice\",\"email\":\"alice@example.test\",\"name\":\"Name of alice\",\"picture\":\"\",\"access\":\"-\",\"refresh\":\"-\",\"accessExpires\":1792504025}"}}
  #|{"out":{"id":1,"call":"client.device","params":{"client":"still.fail mbui","app":"desktop","userAgent":"Macintosh; Mac OS X"}},"w":1792503743610.303}
  #|{"in":{"id":1,"ok":null},"w":1792503743697.808}
  #|{"out":{"id":2,"subscribe":{"topic":"accounts"},"keyed":true},"w":1792503743697.833}
  #|{"out":{"id":3,"subscribe":{"topic":"prefs"},"keyed":true},"w":1792503743697.842}
  #|{"step":"# written by scripts/rerecord.sh from its test (src/sfreplay/emit.mbt): not edited by hand","w":1792503743699.177}
  #|{"step":"timeout 90000","w":1792503743699.184}
  #|{"step":"answered client.device","w":1792503743699.186}
  #|{"step":"answered client.focus","w":1792503743727.207}
  #|{"in":{"id":2,"value":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""}]},"w":1792503743793.574}
  #|{"in":{"id":3,"value":{"onlyMine":false,"onlyWatching":false,"onlyDecisions":false,"listFilter":{},"appearance":"system","rowPicture":"auto","absoluteTime":false,"lang":"zh","keys":{},"lastChat":{},"openChat":{},"chatTabs":{},"dropFiles":{},"driveViews":{},"resume":{},"stationUpdatesDismissed":{},"device":{"app":"desktop","phone":false,"handoff":false},"reader":{"size":18,"line":1.7,"margin":22,"face":"sans","indent":true,"paper":"follow"},"rails":{},"bars":{"sets":[["chats","files","profiles","stations"],["decisions","usage","connects","archive"]],"current":0},"barsBy":{}}},"w":1792503743793.598}
  #|{"out":{"id":4,"subscribe":{"topic":"workspaces"},"keyed":true},"w":1792503743793.625}
  #|{"out":{"id":5,"subscribe":{"topic":"status"},"keyed":true},"w":1792503743793.658}
  #|{"in":{"id":4,"value":[{"account":{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""},"workspaces":[{"id":"01M5CRR81QFXBEVXTPQQ9FHXDF","name":"Dev","role":"owner","created_at":1792503717,"stations":1,"members":1,"relays":[],"time":{"created_at":{"past":true,"at":1792503717000,"ago":"刚刚","full":"10/20 21:41:57","until":"1 分钟内"}}}],"invitations":[],"relay_url":"http://127.0.0.1:18990","loaded":true,"beta":true}]},"w":1792503743826.821}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792503743826.841}
  #|{"out":{"id":6,"subscribe":{"topic":"lock","workspace":"01M5CRR81QFXBEVXTPQQ9FHXDF"},"keyed":true},"w":1792503743826.872}
  #|{"out":{"id":7,"subscribe":{"topic":"chats","scope":"01M5CRR81QFXBEVXTPQQ9FHXDF","mine":false},"keyed":true},"w":1792503743826.884}
  #|{"out":{"id":8,"subscribe":{"topic":"workspaceMarks","workspace":"01M5CRR81QFXBEVXTPQQ9FHXDF"},"keyed":true},"w":1792503743827.005}
  #|{"out":{"id":9,"subscribe":{"topic":"stations","scope":"01M5CRR81QFXBEVXTPQQ9FHXDF"},"keyed":true},"w":1792503743827.025}
  #|{"out":{"id":10,"subscribe":{"topic":"workspace","workspace":"01M5CRR81QFXBEVXTPQQ9FHXDF"},"keyed":true},"w":1792503743827.029}
  #|{"out":{"id":11,"call":"client.focus","params":{"visible":true,"focused":true,"workspace":"01M5CRR81QFXBEVXTPQQ9FHXDF"}},"w":1792503743828.408}
  #|{"out":{"id":12,"subscribe":{"topic":"notify"},"keyed":true},"w":1792503743828.421}
  #|{"out":{"id":13,"subscribe":{"topic":"notify","workspace":"01M5CRR81QFXBEVXTPQQ9FHXDF"},"keyed":true},"w":1792503743828.428}
  #|{"in":{"id":6,"value":{"available":true,"locked":false,"notice":true,"role":"owner","manages":true,"owner":true,"canSign":true,"signs":false,"me":{"device":"0827dadd992a1d38518b299177b24ede71ff89112e0c9c1bd3c02546a1941b58","code":"4HL-EY3","kind":"app","confirmed":false,"waiting":false,"asked":false},"signers":0,"members":[],"stations":[{"id":"de5d36c19b0b44b5ac0ab2a9e16f6238933115e3c4c92607767170885cef7802","name":"studio","version":"0.1.0","online":true,"protected":false}],"protected":0,"requests":[],"renew":[],"attention":0}},"w":1792503743843.504}
  #|{"in":{"id":10,"value":{"id":"01M5CRR81QFXBEVXTPQQ9FHXDF","name":"Dev","role":"owner","created_at":1792503717,"members":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":"https://example.test/p.png","role":"owner","added_at":1792503717}],"stations":[{"id":"de5d36c19b0b44b5ac0ab2a9e16f6238933115e3c4c92607767170885cef7802","name":"studio","emoji":null,"icon":null,"enrolled_at":1792503720,"enrolled_by":"alice","last_seen":1792503724,"version":"0.1.0","time":{"last_seen":{"past":true,"at":1792503724000,"ago":"刚刚","full":"10/20 21:42:04","until":"1 分钟内"}}}],"invitations":[],"added":[],"relays":[],"lock":null,"lock_requests":0,"time":{"created_at":{"past":true,"at":1792503717000,"ago":"刚刚","full":"10/20 21:41:57","until":"1 分钟内"}}}},"w":1792503743843.527}
  #|{"in":{"id":7,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"stations":[{"station":"01M5CRR81QFXBEVXTPQQ9FHXDF/de5d36c19b0b44b5ac0ab2a9e16f6238933115e3c4c92607767170885cef7802","id":"de5d36c19b0b44b5ac0ab2a9e16f6238933115e3c4c92607767170885cef7802","name":"studio","state":"online"}],"loading":false,"days":[{"daysAgo":0,"at":1792503724998,"label":"今天","items":[{"id":"ember:c-391f672101","session":"ember:c-391f672101","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","agents":[{"key":"ember:c-391f672101","runtime":"claude","process":"warm","pending":0,"lastTurn":{"id":"bc124e2d-f7f0-4daa-8eb2-60da68999cc1","kind":"input","outcome":"completed","declared":"final","ending":"all_done","need":"answered the question that was asked","startedAt":1792503724898,"endedAt":1792503725000},"agentText":"默认模型","statusText":"已完成：answered the question that was asked"}],"last":{"seq":2,"authorKind":"agent","author":"ember:c-391f672101","text":"你好，我是测试用的 agent","createdAt":1792503724998,"by":{"kind":"agent","name":"agent","mine":false,"runtime":"claude","label":"agent"},"preview":"你好，我是测试用的 agent","time":{"createdAt":{"at":1792503724998,"ago":"刚刚","full":"10/20 21:42:04","until":"1 分钟内","past":true}}},"unread":true,"mine":true,"lastActiveAt":1792503724998,"station":"01M5CRR81QFXBEVXTPQQ9FHXDF/de5d36c19b0b44b5ac0ab2a9e16f6238933115e3c4c92607767170885cef7802","stationName":"studio","time":{"lastActiveAt":{"at":1792503724998,"ago":"刚刚","full":"10/20 21:42:04","until":"1 分钟内","past":true}},"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"peopleText":"你 发起","clientKey":"new:chat-5b38079725b824a23f","pinned":false,"tone":"done"}]}],"trouble":null,"members":1,"leading":"agents","glyph":{"online":1,"dim":0,"connecting":0,"failing":0,"working":0,"summary":"studio","label":"1 台 station，1 台在线"},"note":{"reading":false,"text":null,"failing":[],"empty":false}}},"w":1792503743843.556}
  #|{"in":{"id":8,"value":{"workspaces":{"01M5CRR81QFXBEVXTPQQ9FHXDF":{"alert":0,"unread":1,"tone":"done","label":"1 个有新消息","badge":0,"items":[],"mineTone":"done"}},"badge":0,"badgeCounts":"attention","badgeKinds":{"on":true,"wait":true,"failed":true,"done":false,"message":false}}},"w":1792503743843.576}
  #|{"in":{"id":9,"value":[{"station":"01M5CRR81QFXBEVXTPQQ9FHXDF/de5d36c19b0b44b5ac0ab2a9e16f6238933115e3c4c92607767170885cef7802","id":"de5d36c19b0b44b5ac0ab2a9e16f6238933115e3c4c92607767170885cef7802","name":"studio","summary":"空闲 · Apple M4 · 16 GB · macOS 26.5","face":"idle","line":"Apple M4","online":true,"reconnecting":false,"lastSeen":1792503724,"version":"0.1.0","link":{"state":"online"},"runtimes":[{"runtime":"claude","models":["claude-sonnet-5-5"]}],"models":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792503724600,"time":{"checkedAt":{"at":1792503724600,"ago":"刚刚","full":"10/20 21:42:04","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"overview":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null,"summaryText":"最近 7 天检查了 0 个 chat","changeText":null}},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","email":"alice@example.test","name":"Name of alice","sub":"alice","role":"owner","workspace":"01M5CRR81QFXBEVXTPQQ9FHXDF","device":"0827dadd992a1d38518b299177b24ede71ff89112e0c9c1bd3c02546a1941b58"},"connects":[],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-D/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792503724239,"time":{"checkedAt":{"at":1792503724239,"ago":"刚刚","full":"10/20 21:42:04","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792503724600,"time":{"checkedAt":{"at":1792503724600,"ago":"刚刚","full":"10/20 21:42:04","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]}],"processes":[],"counts":{"sessions":1,"running":0,"warm":1},"mesh":{"state":"running","origin":"http://127.0.0.1:18950","station":"de5d36c19b0b44b5ac0ab2a9e16f6238933115e3c4c92607767170885cef7802","workspace":"Dev","workspaceId":"01M5CRR81QFXBEVXTPQQ9FHXDF","name":"studio"},"slackUsers":[],"slackTeams":[],"slackApps":[],"feishuRegistrations":[],"disk":{"freeBytes":12579581952,"totalBytes":245107195904},"logins":[],"machineLogins":[{"runtime":"claude","installed":true,"loggedIn":false,"usable":false,"text":"无法读取 Claude Code 的登录信息","offered":false},{"runtime":"codex","installed":true,"loggedIn":false,"usable":false,"text":"Codex 未登录","offered":false}],"sharing":true,"consoleSignIn":true,"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"google","name":"Google Gemini","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xai","name":"xAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"mistral","name":"Mistral","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"deepseek","name":"DeepSeek","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen","name":"Qwen","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai","name":"Kimi","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai","name":"Z.ai","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax","name":"MiniMax","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ant-ling","name":"Ant Ling","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"jev","name":"Jev","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen-cn","name":"Qwen (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"openrouter","name":"OpenRouter","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"opencode","name":"OpenCode Zen","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"groq","name":"Groq","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"together","name":"Together AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"fireworks","name":"Fireworks","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cerebras","name":"Cerebras","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"huggingface","name":"Hugging Face","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"nvidia","name":"NVIDIA","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"baseten","name":"Baseten","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ollama","name":"Ollama","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"custom","name":"Custom","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""}],"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792503722169},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.304","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792503722169},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-D/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792503722169},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-D/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792503722169},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","latest":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-D/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792503722169}],"processesText":"没有运行中的 agent 进程","agentEnv":[],"drive":{"roots":[{"path":"/tmp/mbe2e-D/home/e2e-105609","name":"e2e-105609","state":"ok"}],"anywhere":true,"home":"/tmp/mbe2e-D/home"},"search":{"files":"spotlight","personal":false}},"betaOffered":false,"host":{"hostname":"3720-Mac-mini-1","os":"macOS 26.5","arch":"arm64","cpus":10,"cpuModel":"Apple M4","load":1.92,"cpuBusy":0.53,"uptimeSec":8006461,"memory":{"totalBytes":17179869184,"usedBytes":13956595712,"swapUsedBytes":7307788288},"disk":{"path":"/tmp/mbe2e-D/data","totalBytes":245107195904,"freeBytes":12653424640},"emberRssBytes":156317232,"checkedAt":1792503733182,"summary":"10 核 · 16 GB","line":"macOS 26.5 · 10 核 · 16 GB · 已运行 92 天","facts":["3720-Mac-mini-1","macOS 26.5","arm64 · 10 核","已运行 92 天 16 小时"],"meters":[{"label":"CPU","short":"CPU","percent":53,"left":47,"level":"ok","value":"53%","remaining":"空闲 47%","big":"47","unit":"%","title":"CPU 空闲","total":"负载 19.2","note":"负载 19.2 · Apple M4"},{"label":"内存","short":"内存","percent":81,"left":19,"level":"amber","value":"13.0 GB / 16.0 GB","remaining":"剩 3.0 G","big":"3.0","unit":"GB","title":"内存剩","total":"共 16 GB","note":"swap 6.8 GB"},{"label":"磁盘","short":"磁盘","percent":95,"left":5,"level":"red","value":"剩余 11.8 GB / 228 GB","remaining":"剩 11.8 G","big":"11.8","unit":"GB","title":"磁盘剩","total":"共 228 GB"}],"identity":"Apple M4 · 16 GB · macOS 26.5","details":[{"label":"主机名","value":"3720-Mac-mini-1"},{"label":"芯片","value":"Apple M4 · 10 核 · arm64"},{"label":"已运行","value":"92 天 16 小时"},{"label":"still.fail","value":"进程占用 149 MB"}],"usage":"内存 13.0 GB / 16.0 GB · 磁盘 剩余 11.8 GB / 228 GB","emberText":"still.fail 149 MB"},"way":{"path":"直连","via":"direct"},"time":{"lastSeen":{"at":1792503724000,"ago":"刚刚","full":"10/20 21:42:04","until":"1 分钟内","past":true}},"joined":false}]},"w":1792503743843.683}
  #|{"in":{"id":11,"ok":null},"w":1792503743843.764}
  #|{"in":{"id":12,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792503743843.77}
  #|{"in":{"id":13,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792503743843.774}
  #|{"out":{"id":14,"subscribe":{"topic":"longJobs","scope":"01M5CRR81QFXBEVXTPQQ9FHXDF"},"keyed":true},"w":1792503743843.81}
  #|{"out":{"id":15,"call":"notify.permission","params":{"state":"unknown"}},"w":1792503743845.708}
  #|{"in":{"id":9,"delta":[{"path":[0,"overview","disk","freeBytes"],"set":12576387072}]},"w":1792503743860.165}
  #|{"in":{"id":14,"value":{"groups":[]}},"w":1792503743860.181}
  #|{"in":{"id":15,"ok":null},"w":1792503743860.187}
  #|{"step":"#before drive-media 105609","w":1792503743860.522}
  #|{"step":"#env MBUI_OPEN_PAGE=files","w":1792503743860.524}
  #|{"step":"answered notify.permission","w":1792503743860.525}
  #|{"step":"wait 266","w":1792503743877.382}
  #|{"in":{"id":9,"delta":[{"path":[0,"host","checkedAt"],"set":1792503743871},{"path":[0,"host","cpuBusy"],"set":0.78},{"path":[0,"host","details",3,"value"],"set":"进程占用 144 MB"},{"path":[0,"host","disk","freeBytes"],"set":12572934144},{"path":[0,"host","emberRssBytes"],"set":150909864},{"path":[0,"host","emberText"],"set":"still.fail 144 MB"},{"path":[0,"host","load"],"set":2.03},{"path":[0,"host","memory","usedBytes"],"set":12914868224},{"path":[0,"host","meters",0,"big"],"set":"22"},{"path":[0,"host","meters",0,"left"],"set":22},{"path":[0,"host","meters",0,"level"],"set":"amber"},{"path":[0,"host","meters",0,"note"],"set":"负载 20.3 · Apple M4"},{"path":[0,"host","meters",0,"percent"],"set":78},{"path":[0,"host","meters",0,"remaining"],"set":"空闲 22%"},{"path":[0,"host","meters",0,"total"],"set":"负载 20.3"},{"path":[0,"host","meters",0,"value"],"set":"78%"},{"path":[0,"host","meters",1,"big"],"set":"4.0"},{"path":[0,"host","meters",1,"left"],"set":25},{"path":[0,"host","meters",1,"percent"],"set":75},{"path":[0,"host","meters",1,"remaining"],"set":"剩 4.0 G"},{"path":[0,"host","meters",1,"value"],"set":"12.0 GB / 16.0 GB"},{"path":[0,"host","meters",2,"big"],"set":"11.7"},{"path":[0,"host","meters",2,"remaining"],"set":"剩 11.7 G"},{"path":[0,"host","meters",2,"value"],"set":"剩余 11.7 GB / 228 GB"},{"path":[0,"host","uptimeSec"],"set":8006471},{"path":[0,"host","usage"],"set":"内存 12.0 GB / 16.0 GB · 磁盘 剩余 11.7 GB / 228 GB"}]},"w":1792503743893.493}
  #|{"step":"now tap =e2e-105609","w":1792503744143.863}
  #|{"step":"now tap =e2e-105609","acted":true,"w":1792503744160.482}
  #|{"out":{"id":16,"subscribe":{"topic":"drive","station":"01M5CRR81QFXBEVXTPQQ9FHXDF/de5d36c19b0b44b5ac0ab2a9e16f6238933115e3c4c92607767170885cef7802","root":"/tmp/mbe2e-D/home/e2e-105609","path":""},"keyed":true},"w":1792503744177.03}
  #|{"step":"wait 266","w":1792503744185.679}
  #|{"in":{"id":16,"value":{"path":"","entries":[{"name":"子文件夹","dir":true,"size":0,"mtime":1792503726894,"type":"","kind":"folder","sizeText":"","timeText":"21:42"},{"name":"影音","dir":true,"size":0,"mtime":1792503743552,"type":"","kind":"folder","sizeText":"","timeText":"21:42"},{"name":"小说-e2e.txt","dir":false,"size":36779,"mtime":1792503726915,"type":"text/plain; charset=utf-8","kind":"text","sizeText":"36 KB","timeText":"21:42"},{"name":"说明.txt","dir":false,"size":43,"mtime":1792503726893,"type":"text/plain; charset=utf-8","kind":"text","sizeText":"43 B","timeText":"21:42"}],"truncated":false,"folders":2,"files":2,"countText":"2 个文件夹 · 2 个文件"}},"w":1792503744193.521}
  #|{"out":{"id":17,"subscribe":{"topic":"drivePlace","station":"01M5CRR81QFXBEVXTPQQ9FHXDF/de5d36c19b0b44b5ac0ab2a9e16f6238933115e3c4c92607767170885cef7802","root":"/tmp/mbe2e-D/home/e2e-105609","path":"小说-e2e.txt"},"keyed":true},"w":1792503744198.285}
  #|{"out":{"id":18,"subscribe":{"topic":"drivePlace","station":"01M5CRR81QFXBEVXTPQQ9FHXDF/de5d36c19b0b44b5ac0ab2a9e16f6238933115e3c4c92607767170885cef7802","root":"/tmp/mbe2e-D/home/e2e-105609","path":"说明.txt"},"keyed":true},"w":1792503744200.507}
  #|{"in":{"id":17,"value":null},"w":1792503744210.174}
  #|{"in":{"id":18,"value":null},"w":1792503744210.198}
  #|{"step":"now tap 影音","w":1792503744462.076}
  #|{"step":"now tap 影音","acted":true,"w":1792503744495.183}
  #|{"out":{"id":19,"subscribe":{"topic":"drive","station":"01M5CRR81QFXBEVXTPQQ9FHXDF/de5d36c19b0b44b5ac0ab2a9e16f6238933115e3c4c92607767170885cef7802","root":"/tmp/mbe2e-D/home/e2e-105609","path":"影音"},"keyed":true},"w":1792503744511.71}
  #|{"step":"wait 283","w":1792503744513.112}
  #|{"in":{"id":19,"value":{"path":"影音","entries":[{"name":"片尾曲.m4a","dir":false,"size":45252,"mtime":1792503743551,"type":"audio/mp4","kind":"audio","sizeText":"44 KB","timeText":"21:42"},{"name":"第01集.mp4","dir":false,"size":2276541,"mtime":1792503743331,"type":"video/mp4","kind":"video","sizeText":"2.2 MB","timeText":"21:42"},{"name":"第01集.srt","dir":false,"size":97,"mtime":1792503743552,"type":"application/x-subrip","kind":"subtitle","sizeText":"97 B","timeText":"21:42"},{"name":"第02集.mp4","dir":false,"size":461621,"mtime":1792503743495,"type":"video/mp4","kind":"video","sizeText":"451 KB","timeText":"21:42"}],"truncated":false,"folders":0,"files":4,"countText":"4 个文件"}},"w":1792503744544.835}
  #|{"step":"now until 第01集.mp4","w":1792503744812.477}
  #|{"step":"until 片尾曲.m4a","w":1792503744812.526}
  #|{"step":"tap 第01集.mp4","w":1792503744812.557}
  #|{"step":"tap 第01集.mp4","acted":true,"w":1792503744828.947}
  #|{"out":{"id":20,"subscribe":{"topic":"drivePlace","station":"01M5CRR81QFXBEVXTPQQ9FHXDF/de5d36c19b0b44b5ac0ab2a9e16f6238933115e3c4c92607767170885cef7802","root":"/tmp/mbe2e-D/home/e2e-105609","path":"影音/第01集.mp4"},"keyed":true},"w":1792503744851.95}
  #|{"out":{"id":21,"call":"drive.read","params":{"station":"01M5CRR81QFXBEVXTPQQ9FHXDF/de5d36c19b0b44b5ac0ab2a9e16f6238933115e3c4c92607767170885cef7802","root":"/tmp/mbe2e-D/home/e2e-105609","path":"影音/第01集.srt","offset":0,"length":4194304}},"w":1792503744855.608}
  #|{"step":"answered drive.read","w":1792503744861.543}
  #|{"in":{"id":20,"value":null},"w":1792503744861.707}
  #|{"info":{"view":1,"state":0,"at":[-1,0,1,0,0,0,0,1,0,0]},"w":1792503745098.74}
  #|{"in":{"id":21,"ok":{"type":"application/x-subrip","total":97,"mtime":1792503743552}},"w":1792503745099.657,"b":"310a30303a30303a30302c323030202d2d3e2030303a30303a30342c3030300ae7acace4b880e58fa5e5ad97e5b9950a0a320a30303a30303a30342c303030202d2d3e2030303a30303a30372c3530300ae7acace4ba8ce58fa5e5ad97e5b9950a"}
  #|{"out":{"id":22,"call":"drive.read","params":{"station":"01M5CRR81QFXBEVXTPQQ9FHXDF/de5d36c19b0b44b5ac0ab2a9e16f6238933115e3c4c92607767170885cef7802","root":"/tmp/mbe2e-D/home/e2e-105609","path":"影音/第01集.mp4","offset":0,"length":2}},"w":1792503745128.843}
  #|{"step":"wait 283","w":1792503745129.03}
  #|{"in":{"id":22,"ok":{"type":"video/mp4","total":2276541,"mtime":1792503743331}},"w":1792503745144.817,"b":"0000"}
  #|{"info":{"view":1,"state":0,"at":[-1,0,1,0,0,2,0,1,0,0]},"w":1792503745144.937}
  #|{"out":{"id":23,"call":"drive.read","params":{"station":"01M5CRR81QFXBEVXTPQQ9FHXDF/de5d36c19b0b44b5ac0ab2a9e16f6238933115e3c4c92607767170885cef7802","root":"/tmp/mbe2e-D/home/e2e-105609","path":"影音/第01集.mp4","offset":0,"length":2276541}},"w":1792503745161.761}
  #|{"in":{"id":23,"ok":{"type":"video/mp4","total":2276541,"mtime":1792503743331}},"w":1792503745195.1,"bn":2276541}
  #|{"info":{"view":1,"state":0,"at":[-1,0,1,0,0,2276543,0,1,0,0]},"w":1792503746977.893}
  #|{"step":"now until 2 / 3","w":1792503746978.19}
  #|{"step":"answered drive.read","w":1792503746978.198}
  #|{"step":"answered drive.read","w":1792503746990.572}
  #|{"step":"until 第一句字幕","w":1792503747002.436}
  #|{"info":{"view":1,"state":0,"at":[20000,0,1,640,360,2276543,0,1,0,0]},"w":1792503747656.456}
  #|{"info":{"view":1,"state":1,"at":[20000,0,1,640,360,2276543,1,0,20000,0]},"w":1792503747678.1}
  #|{"info":{"view":1,"state":1,"at":[20000,13.522686,1,640,360,2276543,1,0,20000,0]},"w":1792503747844.807}
  #|{"info":{"view":1,"state":1,"at":[20000,13.797894,1,640,360,2276543,1,0,20000,0]},"w":1792503747845.076}
  #|{"info":{"view":1,"state":1,"at":[20000,30.185686,1,640,360,2276543,1,0,20000,0]},"w":1792503747861.471}
  #|{"info":{"view":1,"state":1,"at":[20000,30.403144,1,640,360,2276543,1,0,20000,0]},"w":1792503747861.687}
  #|{"info":{"view":1,"state":1,"at":[20000,46.849852999999996,1,640,360,2276543,1,0,20000,0]},"w":1792503747878.134}
  #|{"info":{"view":1,"state":1,"at":[20000,46.997769000000005,1,640,360,2276543,1,0,20000,0]},"w":1792503747878.274}
  #|{"info":{"view":1,"state":1,"at":[20000,63.525268999999994,1,640,360,2276543,1,0,20000,0]},"w":1792503747894.808}
  #|{"info":{"view":1,"state":1,"at":[20000,63.777603,1,640,360,2276543,1,0,20000,0]},"w":1792503747895.061}
  #|{"info":{"view":1,"state":1,"at":[20000,80.16435299999999,1,640,360,2276543,1,0,20000,0]},"w":1792503747911.446}
  #|{"info":{"view":1,"state":1,"at":[20000,80.303769,1,640,360,2276543,1,0,20000,0]},"w":1792503747911.58}
  #|{"info":{"view":1,"state":1,"at":[20000,96.83860299999999,1,640,360,2276543,1,0,20000,0]},"w":1792503747928.122}
  #|{"info":{"view":1,"state":1,"at":[20000,96.978686,1,640,360,2276543,1,0,20000,0]},"w":1792503747928.255}
  #|{"info":{"view":1,"state":1,"at":[20000,113.507978,1,640,360,2276543,1,0,20000,0]},"w":1792503747944.79}
  #|{"info":{"view":1,"state":1,"at":[20000,113.647436,1,640,360,2276543,1,0,20000,0]},"w":1792503747944.923}
  #|{"info":{"view":1,"state":1,"at":[20000,130.173019,1,640,360,2276543,1,0,20000,0]},"w":1792503747961.454}
  #|{"info":{"view":1,"state":1,"at":[20000,130.297853,1,640,360,2276543,1,0,20000,0]},"w":1792503747961.573}
  #|{"info":{"view":1,"state":1,"at":[20000,146.833436,1,640,360,2276543,1,0,20000,0]},"w":1792503747978.115}
  #|{"info":{"view":1,"state":1,"at":[20000,146.957603,1,640,360,2276543,1,0,20000,0]},"w":1792503747978.233}
  #|{"info":{"view":1,"state":1,"at":[20000,163.506436,1,640,360,2276543,1,0,20000,0]},"w":1792503747994.787}
  #|{"info":{"view":1,"state":1,"at":[20000,163.634019,1,640,360,2276543,1,0,20000,0]},"w":1792503747994.91}
  #|{"info":{"view":1,"state":1,"at":[20000,180.168936,1,640,360,2276543,1,0,20000,0]},"w":1792503748011.45}
  #|{"info":{"view":1,"state":1,"at":[20000,180.289061,1,640,360,2276543,1,0,20000,0]},"w":1792503748011.564}
  #|{"info":{"view":1,"state":1,"at":[20000,196.836353,1,640,360,2276543,1,0,20000,0]},"w":1792503748028.118}
  #|{"info":{"view":1,"state":1,"at":[20000,196.96251900000001,1,640,360,2276543,1,0,20000,0]},"w":1792503748028.238}
  #|{"info":{"view":1,"state":1,"at":[20000,213.500936,1,640,360,2276543,1,0,20000,0]},"w":1792503748044.782}
  #|{"info":{"view":1,"state":1,"at":[20000,230.556394,1,640,360,2276543,1,0,20000,0]},"w":1792503748061.841}
  #|{"step":"back","w":1792503748062.011}
  #|{"step":"back","acted":true,"w":1792503748062.019}
  #|{"info":{"view":1,"state":1,"at":[20000,230.804269,1,640,360,2276543,1,0,20000,0]},"w":1792503748062.08}
  #|{"info":{"view":1,"state":1,"at":[20000,231.061103,1,640,360,2276543,1,0,20000,0]},"w":1792503748062.336}
  #|{"step":"wait 283","w":1792503748071.489}
  #|{"info":{"view":1,"state":1,"at":[20000,246.865644,1,640,360,2276543,1,0,20000,0]},"w":1792503748078.15}
  #|{"info":{"view":1,"state":1,"at":[20000,247.257269,1,640,360,2276543,1,0,20000,0]},"w":1792503748078.534}
  #|{"info":{"view":1,"state":1,"at":[20000,263.520603,1,640,360,2276543,1,0,20000,0]},"w":1792503748094.804}
  #|{"info":{"view":1,"state":1,"at":[20000,263.870144,1,640,360,2276543,1,0,20000,0]},"w":1792503748095.147}
  #|{"info":{"view":1,"state":1,"at":[20000,280.186936,1,640,360,2276543,1,0,20000,0]},"w":1792503748111.469}
  #|{"info":{"view":1,"state":1,"at":[20000,280.537686,1,640,360,2276543,1,0,20000,0]},"w":1792503748111.815}
  #|{"info":{"view":1,"state":1,"at":[20000,296.844894,1,640,360,2276543,1,0,20000,0]},"w":1792503748128.125}
  #|{"info":{"view":1,"state":1,"at":[20000,297.17231100000004,1,640,360,2276543,1,0,20000,0]},"w":1792503748128.45}
  #|{"info":{"view":1,"state":1,"at":[20000,313.50506099999996,1,640,360,2276543,1,0,20000,0]},"w":1792503748144.785}
  #|{"info":{"view":1,"state":1,"at":[20000,313.802811,1,640,360,2276543,1,0,20000,0]},"w":1792503748145.079}
  #|{"info":{"view":1,"state":1,"at":[20000,330.192936,1,640,360,2276543,1,0,20000,0]},"w":1792503748161.475}
  #|{"info":{"view":1,"state":1,"at":[20000,330.571769,1,640,360,2276543,1,0,20000,0]},"w":1792503748161.849}
  #|{"info":{"view":1,"state":1,"at":[20000,346.83626899999996,1,640,360,2276543,1,0,20000,0]},"w":1792503748178.117}
  #|{"info":{"view":1,"state":1,"at":[20000,347.146561,1,640,360,2276543,1,0,20000,0]},"w":1792503748178.421}
  #|{"info":{"view":1,"state":1,"at":[20000,363.52772799999997,1,640,360,2276543,1,0,20000,0]},"w":1792503748194.81}
  #|{"info":{"view":1,"state":1,"at":[20000,363.948353,1,640,360,2276543,1,0,20000,0]},"w":1792503748195.225}
  #|{"info":{"view":1,"state":1,"at":[20000,380.166603,1,640,360,2276543,1,0,20000,0]},"w":1792503748211.447}
  #|{"info":{"view":1,"state":1,"at":[20000,380.480394,1,640,360,2276543,1,0,20000,0]},"w":1792503748211.755}
  #|{"info":{"view":1,"state":1,"at":[20000,396.824811,1,640,360,2276543,1,0,20000,0]},"w":1792503748228.104}
  #|{"info":{"view":1,"state":1,"at":[20000,397.09781100000004,1,640,360,2276543,1,0,20000,0]},"w":1792503748228.373}
  #|{"info":{"view":1,"state":1,"at":[20000,413.51793599999996,1,640,360,2276543,1,0,20000,0]},"w":1792503748244.798}
  #|{"info":{"view":1,"state":1,"at":[20000,413.78814400000005,1,640,360,2276543,1,0,20000,0]},"w":1792503748245.063}
  #|{"info":{"view":1,"state":1,"at":[20000,430.297602,1,640,360,2276543,1,0,20000,0]},"w":1792503748261.582}
  #|{"info":{"view":1,"state":1,"at":[20000,430.698311,1,640,360,2276543,1,0,20000,0]},"w":1792503748261.976}
  #|{"info":{"view":1,"state":1,"at":[20000,446.86985200000004,1,640,360,2276543,1,0,20000,0]},"w":1792503748278.161}
  #|{"info":{"view":1,"state":1,"at":[20000,447.42501899999996,1,640,360,2276543,1,0,20000,0]},"w":1792503748278.706}
  #|{"info":{"view":1,"state":1,"at":[20000,463.539227,1,640,360,2276543,1,0,20000,0]},"w":1792503748294.825}
  #|{"info":{"view":1,"state":1,"at":[20000,464.013436,1,640,360,2276543,1,0,20000,0]},"w":1792503748295.292}
  #|{"info":{"view":1,"state":1,"at":[20000,480.21360200000004,1,640,360,2276543,1,0,20000,0]},"w":1792503748311.499}
  #|{"info":{"view":1,"state":1,"at":[20000,480.589227,1,640,360,2276543,1,0,20000,0]},"w":1792503748311.867}
  #|{"info":{"view":1,"state":1,"at":[20000,496.841811,1,640,360,2276543,1,0,20000,0]},"w":1792503748328.125}
  #|{"info":{"view":1,"state":1,"at":[20000,497.142977,1,640,360,2276543,1,0,20000,0]},"w":1792503748328.421}
  #|{"info":{"view":1,"state":1,"at":[20000,513.504311,1,640,360,2276543,1,0,20000,0]},"w":1792503748344.786}
  #|{"info":{"view":1,"state":1,"at":[20000,513.873769,1,640,360,2276543,1,0,20000,0]},"w":1792503748345.149}
  #|{"info":{"view":1,"state":1,"at":[20000,530.1545610000001,1,640,360,2276543,1,0,20000,0]},"w":1792503748361.437}
  #|{"info":{"view":1,"state":1,"at":[20000,530.436936,1,640,360,2276543,1,0,20000,0]},"w":1792503748361.713}
  #|{"step":"now answered drive.place","w":1792503748361.802}
  #|{"info":{"view":1,"state":1,"at":[20000,546.817519,1,640,360,2276543,1,0,20000,0]},"w":1792503748378.096}
  #|{"out":{"id":24,"call":"drive.place","params":{"station":"01M5CRR81QFXBEVXTPQQ9FHXDF/de5d36c19b0b44b5ac0ab2a9e16f6238933115e3c4c92607767170885cef7802","root":"/tmp/mbe2e-D/home/e2e-105609","path":"影音/第01集.mp4","at":547,"of":20000}},"w":1792503748378.23}
  #|{"in":{"id":24,"ok":null},"w":1792503748394.755}
  #|{"step":"until 第02集.mp4","w":1792503748411.729}
  #|{"step":"tap 第01集.mp4","w":1792503748411.738}
  #|{"step":"tap 第01集.mp4","acted":true,"w":1792503748428.481}
  #|{"in":{"id":20,"value":{"at":547,"of":20000,"changed":1792503748378}},"w":1792503748444.757}
  #|{"out":{"id":25,"call":"drive.read","params":{"station":"01M5CRR81QFXBEVXTPQQ9FHXDF/de5d36c19b0b44b5ac0ab2a9e16f6238933115e3c4c92607767170885cef7802","root":"/tmp/mbe2e-D/home/e2e-105609","path":"影音/第01集.srt","offset":0,"length":4194304}},"w":1792503748445.861}
  #|{"info":{"view":2,"state":0,"at":[-1,547,1,0,0,0,0,1,0,0]},"w":1792503748446.024}
  #|{"step":"answered drive.read","w":1792503748446.114}
  #|{"in":{"id":25,"ok":{"type":"application/x-subrip","total":97,"mtime":1792503743552}},"w":1792503748476.778,"b":"310a30303a30303a30302c323030202d2d3e2030303a30303a30342c3030300ae7acace4b880e58fa5e5ad97e5b9950a0a320a30303a30303a30342c303030202d2d3e2030303a30303a30372c3530300ae7acace4ba8ce58fa5e5ad97e5b9950a"}
  #|{"out":{"id":26,"call":"drive.read","params":{"station":"01M5CRR81QFXBEVXTPQQ9FHXDF/de5d36c19b0b44b5ac0ab2a9e16f6238933115e3c4c92607767170885cef7802","root":"/tmp/mbe2e-D/home/e2e-105609","path":"影音/第01集.mp4","offset":0,"length":2}},"w":1792503748477.515}
  #|{"in":{"id":26,"ok":{"type":"video/mp4","total":2276541,"mtime":1792503743331}},"w":1792503748493.44,"b":"0000"}
  #|{"info":{"view":2,"state":0,"at":[-1,547,1,0,0,2,0,1,0,0]},"w":1792503748493.495}
  #|{"step":"wait 283","w":1792503748493.836}
  #|{"out":{"id":27,"call":"drive.read","params":{"station":"01M5CRR81QFXBEVXTPQQ9FHXDF/de5d36c19b0b44b5ac0ab2a9e16f6238933115e3c4c92607767170885cef7802","root":"/tmp/mbe2e-D/home/e2e-105609","path":"影音/第01集.mp4","offset":0,"length":2276541}},"w":1792503748510.33}
  #|{"in":{"id":27,"ok":{"type":"video/mp4","total":2276541,"mtime":1792503743331}},"w":1792503748543.524,"bn":2276541}
  #|{"info":{"view":2,"state":0,"at":[-1,547,1,0,0,2276543,0,1,0,0]},"w":1792503749967.024}
  #|{"step":"now until 2 / 3","w":1792503749967.46}
  #|{"step":"answered drive.read","w":1792503749967.466}
  #|{"step":"answered drive.read","w":1792503749977.275}
  #|{"info":{"view":2,"state":1,"at":[20000,547,1,640,360,2276543,1,0,20000,0]},"w":1792503750010.26}
  #|{"step":"until / 0:20","w":1792503750010.757}
  #|{"step":"tap icon:forward-15","w":1792503750010.763}
  #|{"step":"tap icon:forward-15","acted":true,"w":1792503750027.056}
  #|{"info":{"view":2,"state":1,"at":[20000,15547,1,640,360,2276543,1,0,20000,0]},"w":1792503750043.954}
  #|{"step":"tap icon:forward-15","w":1792503750044.082}
  #|{"step":"tap icon:forward-15","acted":true,"w":1792503750060.564}
  #|{"info":{"view":2,"state":1,"at":[20000,20000,1,640,360,2276543,1,0,20000,0]},"w":1792503750083.817}
  #|{"step":"until 播放结束","w":1792503750084.03}
  #|{"info":{"view":2,"state":1,"at":[20000,20000,0,640,360,2276543,1,0,20000,1]},"w":1792503750176.783}
  #|{"step":"tap 下一个：第02集.mp4","w":1792503750208.027}
  #|{"step":"tap 下一个：第02集.mp4","acted":true,"w":1792503750261.718}
  #|{"out":{"id":28,"subscribe":{"topic":"drivePlace","station":"01M5CRR81QFXBEVXTPQQ9FHXDF/de5d36c19b0b44b5ac0ab2a9e16f6238933115e3c4c92607767170885cef7802","root":"/tmp/mbe2e-D/home/e2e-105609","path":"影音/第02集.mp4"},"keyed":true},"w":1792503750278.261}
  #|{"step":"answered drive.place","w":1792503750278.618}
  #|{"in":{"id":28,"value":null},"w":1792503750294.752}
  #|{"out":{"id":29,"call":"drive.place","params":{"station":"01M5CRR81QFXBEVXTPQQ9FHXDF/de5d36c19b0b44b5ac0ab2a9e16f6238933115e3c4c92607767170885cef7802","root":"/tmp/mbe2e-D/home/e2e-105609","path":"影音/第01集.mp4","at":20000,"of":20000}},"w":1792503750294.826}
  #|{"info":{"view":3,"state":0,"at":[-1,0,1,0,0,0,0,1,0,0]},"w":1792503750296.466}
  #|{"in":{"id":29,"ok":null},"w":1792503750326.765}
  #|{"out":{"id":30,"call":"drive.read","params":{"station":"01M5CRR81QFXBEVXTPQQ9FHXDF/de5d36c19b0b44b5ac0ab2a9e16f6238933115e3c4c92607767170885cef7802","root":"/tmp/mbe2e-D/home/e2e-105609","path":"影音/第02集.mp4","offset":0,"length":2}},"w":1792503750326.924}
  #|{"in":{"id":30,"ok":{"type":"video/mp4","total":461621,"mtime":1792503743495}},"w":1792503750343.431,"b":"0000"}
  #|{"info":{"view":3,"state":0,"at":[-1,0,1,0,0,2,0,1,0,0]},"w":1792503750343.506}
  #|{"step":"until 3 / 3","w":1792503750343.761}
  #|{"step":"answered drive.read","w":1792503750343.765}
  #|{"out":{"id":31,"call":"drive.read","params":{"station":"01M5CRR81QFXBEVXTPQQ9FHXDF/de5d36c19b0b44b5ac0ab2a9e16f6238933115e3c4c92607767170885cef7802","root":"/tmp/mbe2e-D/home/e2e-105609","path":"影音/第02集.mp4","offset":0,"length":461621}},"w":1792503750360.238}
  #|{"step":"answered drive.read","w":1792503750360.368}
  #|{"in":{"id":20,"value":{"at":20000,"of":20000,"changed":1792503750294}},"w":1792503750376.768}
  #|{"in":{"id":31,"ok":{"type":"video/mp4","total":461621,"mtime":1792503743495}},"w":1792503750376.802,"bn":461621}
  #|{"info":{"view":3,"state":0,"at":[-1,0,1,0,0,461623,0,1,0,0]},"w":1792503750630.877}
  #|{"step":"until / 0:04","w":1792503750639.995}
  #|{"info":{"view":3,"state":1,"at":[4000,0,1,640,360,461623,1,0,4000,0]},"w":1792503750660.119}
  #|{"step":"back","w":1792503750660.604}
  #|{"step":"back","acted":true,"w":1792503750660.61}
  #|{"step":"wait 283","w":1792503750677.201}
  #|{"info":{"view":3,"state":1,"at":[4000,4.782001,1,640,360,461623,1,0,4000,0]},"w":1792503750726.773}
  #|{"info":{"view":3,"state":1,"at":[4000,5.0913759999999995,1,640,360,461623,1,0,4000,0]},"w":1792503750727.076}
  #|{"info":{"view":3,"state":1,"at":[4000,21.42721,1,640,360,461623,1,0,4000,0]},"w":1792503750743.413}
  #|{"info":{"view":3,"state":1,"at":[4000,21.598001,1,640,360,461623,1,0,4000,0]},"w":1792503750743.582}
  #|{"info":{"view":3,"state":1,"at":[4000,38.097376000000004,1,640,360,461623,1,0,4000,0]},"w":1792503750760.083}
  #|{"info":{"view":3,"state":1,"at":[4000,38.275543,1,640,360,461623,1,0,4000,0]},"w":1792503750760.26}
  #|{"info":{"view":3,"state":1,"at":[4000,54.783792999999996,1,640,360,461623,1,0,4000,0]},"w":1792503750776.774}
  #|{"info":{"view":3,"state":1,"at":[4000,55.037668,1,640,360,461623,1,0,4000,0]},"w":1792503750777.021}
  #|{"info":{"view":3,"state":1,"at":[4000,71.444626,1,640,360,461623,1,0,4000,0]},"w":1792503750793.433}
  #|{"info":{"view":3,"state":1,"at":[4000,71.698501,1,640,360,461623,1,0,4000,0]},"w":1792503750793.683}
  #|{"info":{"view":3,"state":1,"at":[4000,88.126418,1,640,360,461623,1,0,4000,0]},"w":1792503750810.116}
  #|{"info":{"view":3,"state":1,"at":[4000,88.426293,1,640,360,461623,1,0,4000,0]},"w":1792503750810.411}
  #|{"info":{"view":3,"state":1,"at":[4000,104.78571000000001,1,640,360,461623,1,0,4000,0]},"w":1792503750826.775}
  #|{"info":{"view":3,"state":1,"at":[4000,105.06275099999999,1,640,360,461623,1,0,4000,0]},"w":1792503750827.047}
  #|{"info":{"view":3,"state":1,"at":[4000,121.446501,1,640,360,461623,1,0,4000,0]},"w":1792503750843.437}
  #|{"info":{"view":3,"state":1,"at":[4000,121.73108500000001,1,640,360,461623,1,0,4000,0]},"w":1792503750843.716}
  #|{"info":{"view":3,"state":1,"at":[4000,138.140335,1,640,360,461623,1,0,4000,0]},"w":1792503750860.132}
  #|{"info":{"view":3,"state":1,"at":[4000,138.48491800000002,1,640,360,461623,1,0,4000,0]},"w":1792503750860.469}
  #|{"info":{"view":3,"state":1,"at":[4000,154.77371000000002,1,640,360,461623,1,0,4000,0]},"w":1792503750876.761}
  #|{"info":{"view":3,"state":1,"at":[4000,155.018835,1,640,360,461623,1,0,4000,0]},"w":1792503750877.002}
  #|{"info":{"view":3,"state":1,"at":[4000,171.44525099999998,1,640,360,461623,1,0,4000,0]},"w":1792503750893.435}
  #|{"info":{"view":3,"state":1,"at":[4000,171.705085,1,640,360,461623,1,0,4000,0]},"w":1792503750893.689}
  #|{"info":{"view":3,"state":1,"at":[4000,188.136585,1,640,360,461623,1,0,4000,0]},"w":1792503750910.126}
  #|{"info":{"view":3,"state":1,"at":[4000,188.451876,1,640,360,461623,1,0,4000,0]},"w":1792503750910.436}
  #|{"info":{"view":3,"state":1,"at":[4000,204.78579299999998,1,640,360,461623,1,0,4000,0]},"w":1792503750926.776}
  #|{"info":{"view":3,"state":1,"at":[4000,205.08779299999998,1,640,360,461623,1,0,4000,0]},"w":1792503750927.072}
  #|{"info":{"view":3,"state":1,"at":[4000,221.457043,1,640,360,461623,1,0,4000,0]},"w":1792503750943.446}
  #|{"info":{"view":3,"state":1,"at":[4000,221.77921,1,640,360,461623,1,0,4000,0]},"w":1792503750943.764}
  #|{"info":{"view":3,"state":1,"at":[4000,238.12491799999998,1,640,360,461623,1,0,4000,0]},"w":1792503750960.114}
  #|{"info":{"view":3,"state":1,"at":[4000,238.429418,1,640,360,461623,1,0,4000,0]},"w":1792503750960.413}
  #|{"step":"now answered drive.place","w":1792503750960.517}
  #|{"info":{"view":3,"state":1,"at":[4000,254.798168,1,640,360,461623,1,0,4000,0]},"w":1792503750976.788}
  #|{"info":{"view":3,"state":1,"at":[4000,255.11096,1,640,360,461623,1,0,4000,0]},"w":1792503750977.095}
  #|{"info":{"view":3,"state":1,"at":[4000,271.453418,1,640,360,461623,1,0,4000,0]},"w":1792503750993.442}
  #|{"out":{"id":32,"call":"drive.place","params":{"station":"01M5CRR81QFXBEVXTPQQ9FHXDF/de5d36c19b0b44b5ac0ab2a9e16f6238933115e3c4c92607767170885cef7802","root":"/tmp/mbe2e-D/home/e2e-105609","path":"影音/第02集.mp4","at":271,"of":4000}},"w":1792503750993.6}
  #|{"in":{"id":32,"ok":null},"w":1792503751010.095}
  #|{"step":"tap 片尾曲.m4a","w":1792503751026.921}
  #|{"step":"tap 片尾曲.m4a","acted":true,"w":1792503751043.685}
  #|{"out":{"id":33,"subscribe":{"topic":"drivePlace","station":"01M5CRR81QFXBEVXTPQQ9FHXDF/de5d36c19b0b44b5ac0ab2a9e16f6238933115e3c4c92607767170885cef7802","root":"/tmp/mbe2e-D/home/e2e-105609","path":"影音/片尾曲.m4a"},"keyed":true},"w":1792503751060.243}
  #|{"step":"wait 283","w":1792503751060.506}
  #|{"in":{"id":28,"value":{"at":271,"of":4000,"changed":1792503750993}},"w":1792503751076.757}
  #|{"in":{"id":33,"value":null},"w":1792503751076.77}
  #|{"info":{"view":4,"state":0,"at":[-1,0,1,0,0,0,0,1,0,0]},"w":1792503751078.72}
  #|{"out":{"id":34,"call":"drive.read","params":{"station":"01M5CRR81QFXBEVXTPQQ9FHXDF/de5d36c19b0b44b5ac0ab2a9e16f6238933115e3c4c92607767170885cef7802","root":"/tmp/mbe2e-D/home/e2e-105609","path":"影音/片尾曲.m4a","offset":0,"length":2}},"w":1792503751093.896}
  #|{"in":{"id":34,"ok":{"type":"audio/mp4","total":45252,"mtime":1792503743551}},"w":1792503751110.103,"b":"0000"}
  #|{"info":{"view":4,"state":0,"at":[-1,0,1,0,0,2,0,1,0,0]},"w":1792503751110.177}
  #|{"out":{"id":35,"call":"drive.read","params":{"station":"01M5CRR81QFXBEVXTPQQ9FHXDF/de5d36c19b0b44b5ac0ab2a9e16f6238933115e3c4c92607767170885cef7802","root":"/tmp/mbe2e-D/home/e2e-105609","path":"影音/片尾曲.m4a","offset":0,"length":45252}},"w":1792503751127.221}
  #|{"in":{"id":35,"ok":{"type":"audio/mp4","total":45252,"mtime":1792503743551}},"w":1792503751143.433,"bn":45252}
  #|{"info":{"view":4,"state":0,"at":[-1,0,1,0,0,45254,0,1,0,0]},"w":1792503751151.9}
  #|{"info":{"view":4,"state":0,"at":[4975.32879818594,0,1,0,0,45254,0,1,0,0]},"w":1792503751172.739}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,0,1,0,0,45254,0,0,5000,0]},"w":1792503751176.753}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,3.4404150000000002,1,0,0,45254,0,0,5000,0]},"w":1792503751226.75}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,3.706248,1,0,0,45254,0,0,5000,0]},"w":1792503751227.013}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,20.124956,1,0,0,45254,0,0,5000,0]},"w":1792503751243.438}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,20.419998000000003,1,0,0,45254,0,0,5000,0]},"w":1792503751243.728}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,36.794706000000005,1,0,0,45254,0,0,5000,0]},"w":1792503751260.106}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,37.087081,1,0,0,45254,0,0,5000,0]},"w":1792503751260.395}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,53.475331000000004,1,0,0,45254,0,0,5000,0]},"w":1792503751276.79}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,53.815623,1,0,0,45254,0,0,5000,0]},"w":1792503751277.123}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,70.13279,1,0,0,45254,0,0,5000,0]},"w":1792503751293.446}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,70.436623,1,0,0,45254,0,0,5000,0]},"w":1792503751293.744}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,86.79716499999999,1,0,0,45254,0,0,5000,0]},"w":1792503751310.11}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,87.10541500000001,1,0,0,45254,0,0,5000,0]},"w":1792503751310.413}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,103.464248,1,0,0,45254,0,0,5000,0]},"w":1792503751326.778}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,103.77666500000001,1,0,0,45254,0,0,5000,0]},"w":1792503751327.084}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,120.120706,1,0,0,45254,0,0,5000,0]},"w":1792503751343.431}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,120.395706,1,0,0,45254,0,0,5000,0]},"w":1792503751343.703}
  #|{"step":"now until 1 / 3","w":1792503751343.791}
  #|{"step":"answered drive.read","w":1792503751343.798}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,136.788915,1,0,0,45254,0,0,5000,0]},"w":1792503751360.1}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,137.052706,1,0,0,45254,0,0,5000,0]},"w":1792503751360.359}
  #|{"step":"answered drive.read","w":1792503751360.444}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,153.461915,1,0,0,45254,0,0,5000,0]},"w":1792503751376.773}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,153.620081,1,0,0,45254,0,0,5000,0]},"w":1792503751376.926}
  #|{"step":"back","w":1792503751377.027}
  #|{"step":"back","acted":true,"w":1792503751377.031}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,170.11778999999999,1,0,0,45254,0,0,5000,0]},"w":1792503751393.428}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,170.30795600000002,1,0,0,45254,0,0,5000,0]},"w":1792503751393.613}
  #|{"step":"wait 283","w":1792503751393.701}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,186.81329,1,0,0,45254,0,0,5000,0]},"w":1792503751410.129}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,187.170956,1,0,0,45254,0,0,5000,0]},"w":1792503751410.478}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,203.45691499999998,1,0,0,45254,0,0,5000,0]},"w":1792503751426.767}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,203.749748,1,0,0,45254,0,0,5000,0]},"w":1792503751427.056}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,220.13295599999998,1,0,0,45254,0,0,5000,0]},"w":1792503751443.445}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,220.43974799999998,1,0,0,45254,0,0,5000,0]},"w":1792503751443.746}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,236.800748,1,0,0,45254,0,0,5000,0]},"w":1792503751460.117}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,237.12554,1,0,0,45254,0,0,5000,0]},"w":1792503751460.434}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,253.46220600000004,1,0,0,45254,0,0,5000,0]},"w":1792503751476.773}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,253.72366499999998,1,0,0,45254,0,0,5000,0]},"w":1792503751477.03}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,270.113331,1,0,0,45254,0,0,5000,0]},"w":1792503751493.422}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,270.34578999999997,1,0,0,45254,0,0,5000,0]},"w":1792503751493.651}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,286.794081,1,0,0,45254,0,0,5000,0]},"w":1792503751510.104}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,287.076498,1,0,0,45254,0,0,5000,0]},"w":1792503751510.382}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,303.44462300000004,1,0,0,45254,0,0,5000,0]},"w":1792503751526.754}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,303.681581,1,0,0,45254,0,0,5000,0]},"w":1792503751526.986}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,320.136248,1,0,0,45254,0,0,5000,0]},"w":1792503751543.461}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,320.583998,1,0,0,45254,0,0,5000,0]},"w":1792503751543.89}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,336.79312300000004,1,0,0,45254,0,0,5000,0]},"w":1792503751560.103}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,337.083248,1,0,0,45254,0,0,5000,0]},"w":1792503751560.389}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,353.443373,1,0,0,45254,0,0,5000,0]},"w":1792503751576.753}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,353.699206,1,0,0,45254,0,0,5000,0]},"w":1792503751577.004}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,370.11679,1,0,0,45254,0,0,5000,0]},"w":1792503751593.426}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,370.401831,1,0,0,45254,0,0,5000,0]},"w":1792503751593.708}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,386.79103999999995,1,0,0,45254,0,0,5000,0]},"w":1792503751610.104}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,387.10729,1,0,0,45254,0,0,5000,0]},"w":1792503751610.412}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,403.424248,1,0,0,45254,0,0,5000,0]},"w":1792503751626.729}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,403.606956,1,0,0,45254,0,0,5000,0]},"w":1792503751626.911}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,420.093956,1,0,0,45254,0,0,5000,0]},"w":1792503751643.4}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,420.30699799999996,1,0,0,45254,0,0,5000,0]},"w":1792503751643.612}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,436.877707,1,0,0,45254,0,0,5000,0]},"w":1792503751660.197}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,437.16879,1,0,0,45254,0,0,5000,0]},"w":1792503751660.481}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,453.449832,1,0,0,45254,0,0,5000,0]},"w":1792503751676.767}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,453.741082,1,0,0,45254,0,0,5000,0]},"w":1792503751677.053}
  #|{"step":"now answered drive.place","w":1792503751677.14}
  #|{"info":{"view":4,"state":1,"at":[4975.32879818594,470.14537299999995,1,0,0,45254,0,0,5000,0]},"w":1792503751693.471}
  #|{"out":{"id":36,"call":"drive.place","params":{"station":"01M5CRR81QFXBEVXTPQQ9FHXDF/de5d36c19b0b44b5ac0ab2a9e16f6238933115e3c4c92607767170885cef7802","root":"/tmp/mbe2e-D/home/e2e-105609","path":"影音/片尾曲.m4a","at":470,"of":4975}},"w":1792503751693.812}
  #|{"in":{"id":36,"ok":null},"w":1792503751710.079}
  #|{"step":"until 片尾曲.m4a","w":1792503751726.955}
  #|{"step":"","w":1792503751726.965}
