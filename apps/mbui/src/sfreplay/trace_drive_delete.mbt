// e2e/traces/drive-delete.trace, made by scripts/trace.py from 03-drive_delete.log: not edited by hand.

///|
/// What the app and its core said in the run, a line each.
pub let trace_drive_delete : String =
  #|{"env":{"MBUI_CLOUD":"http://127.0.0.1:18900","MBUI_CORE_ACCOUNT":"{\"sub\":\"alice\",\"email\":\"alice@example.test\",\"name\":\"Name of alice\",\"picture\":\"\",\"access\":\"-\",\"refresh\":\"-\",\"accessExpires\":1792532800}"}}
  #|{"out":{"id":1,"call":"client.device","params":{"client":"still.fail mbui","app":"desktop","userAgent":"Macintosh; Mac OS X"}},"w":1792532523685.885}
  #|{"in":{"id":1,"ok":null},"w":1792532523771.825}
  #|{"out":{"id":2,"subscribe":{"topic":"accounts"},"keyed":true},"w":1792532523771.849}
  #|{"out":{"id":3,"subscribe":{"topic":"prefs"},"keyed":true},"w":1792532523771.858}
  #|{"step":"# written by scripts/rerecord.sh from its test (src/sfreplay/emit.mbt): not edited by hand","w":1792532523773.258}
  #|{"step":"timeout 90000","w":1792532523773.264}
  #|{"step":"answered client.device","w":1792532523773.267}
  #|{"step":"answered client.focus","w":1792532523786.374}
  #|{"in":{"id":2,"value":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""}]},"w":1792532523869.098}
  #|{"in":{"id":3,"value":{"onlyMine":false,"onlyWatching":false,"onlyDecisions":false,"listFilter":{},"appearance":"system","rowPicture":"auto","absoluteTime":false,"lang":"zh","keys":{},"lastChat":{},"openChat":{},"chatTabs":{},"dropFiles":{},"driveViews":{},"resume":{},"stationUpdatesDismissed":{},"device":{"app":"desktop","phone":false,"handoff":false},"reader":{"size":18,"line":1.7,"margin":22,"face":"sans","indent":true,"paper":"follow"},"rails":{},"bars":{"sets":[["chats","files","profiles","stations"],["decisions","usage","connects","archive"]],"current":0},"barsBy":{}}},"w":1792532523869.118}
  #|{"out":{"id":4,"subscribe":{"topic":"workspaces"},"keyed":true},"w":1792532523869.142}
  #|{"out":{"id":5,"subscribe":{"topic":"status"},"keyed":true},"w":1792532523869.154}
  #|{"in":{"id":4,"value":[{"account":{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""},"workspaces":[{"id":"01M5DM6G5X6C2XCHD6HEHVZJ3K","name":"Dev","role":"owner","created_at":1792532496,"stations":1,"members":1,"relays":[],"time":{"created_at":{"past":true,"at":1792532496000,"ago":"刚刚","full":"10/21 05:41:36","until":"1 分钟内"}}}],"invitations":[],"relay_url":"http://127.0.0.1:18940","loaded":true,"beta":true}]},"w":1792532523888.399}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792532523888.413}
  #|{"out":{"id":6,"subscribe":{"topic":"lock","workspace":"01M5DM6G5X6C2XCHD6HEHVZJ3K"},"keyed":true},"w":1792532523888.446}
  #|{"out":{"id":7,"subscribe":{"topic":"chats","scope":"01M5DM6G5X6C2XCHD6HEHVZJ3K","mine":false},"keyed":true},"w":1792532523888.464}
  #|{"out":{"id":8,"subscribe":{"topic":"workspaceMarks","workspace":"01M5DM6G5X6C2XCHD6HEHVZJ3K"},"keyed":true},"w":1792532523888.59}
  #|{"out":{"id":9,"subscribe":{"topic":"stations","scope":"01M5DM6G5X6C2XCHD6HEHVZJ3K"},"keyed":true},"w":1792532523888.611}
  #|{"out":{"id":10,"subscribe":{"topic":"workspace","workspace":"01M5DM6G5X6C2XCHD6HEHVZJ3K"},"keyed":true},"w":1792532523888.616}
  #|{"out":{"id":11,"subscribe":{"topic":"status","workspace":"01M5DM6G5X6C2XCHD6HEHVZJ3K"},"keyed":true},"w":1792532523888.681}
  #|{"out":{"id":12,"call":"client.focus","params":{"visible":true,"focused":true,"workspace":"01M5DM6G5X6C2XCHD6HEHVZJ3K"}},"w":1792532523890.12}
  #|{"out":{"id":13,"subscribe":{"topic":"notify"},"keyed":true},"w":1792532523890.132}
  #|{"out":{"id":14,"subscribe":{"topic":"notify","workspace":"01M5DM6G5X6C2XCHD6HEHVZJ3K"},"keyed":true},"w":1792532523890.138}
  #|{"in":{"id":6,"value":{"available":true,"locked":false,"notice":true,"role":"owner","manages":true,"owner":true,"canSign":true,"signs":false,"me":{"device":"04bbf18e8880832bdc5bd41814d83bee575be23c157fd36a1d3d685d23d5bfd3","code":"LMV-EMX","kind":"app","confirmed":false,"waiting":false,"asked":false},"signers":0,"members":[],"stations":[{"id":"166923bb2524533997f726f20a74178d0a3425a5ab28c2c71a017d32d7e2c39b","name":"studio","version":"0.1.0","online":true,"protected":false}],"protected":0,"requests":[],"renew":[],"attention":0}},"w":1792532523902.436}
  #|{"in":{"id":10,"value":{"id":"01M5DM6G5X6C2XCHD6HEHVZJ3K","name":"Dev","role":"owner","created_at":1792532496,"members":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":"https://example.test/p.png","role":"owner","added_at":1792532496}],"stations":[{"id":"166923bb2524533997f726f20a74178d0a3425a5ab28c2c71a017d32d7e2c39b","name":"studio","emoji":null,"icon":null,"enrolled_at":1792532497,"enrolled_by":"alice","last_seen":1792532500,"version":"0.1.0","time":{"last_seen":{"past":true,"at":1792532500000,"ago":"刚刚","full":"10/21 05:41:40","until":"1 分钟内"}}}],"invitations":[],"added":[],"relays":[],"lock":null,"lock_requests":0,"time":{"created_at":{"past":true,"at":1792532496000,"ago":"刚刚","full":"10/21 05:41:36","until":"1 分钟内"}}}},"w":1792532523902.459}
  #|{"in":{"id":7,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"stations":[{"station":"01M5DM6G5X6C2XCHD6HEHVZJ3K/166923bb2524533997f726f20a74178d0a3425a5ab28c2c71a017d32d7e2c39b","id":"166923bb2524533997f726f20a74178d0a3425a5ab28c2c71a017d32d7e2c39b","name":"studio","state":"online"}],"loading":false,"days":[{"daysAgo":0,"at":1792532500703,"label":"今天","items":[{"id":"ember:c-a6e027d17d","session":"ember:c-a6e027d17d","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","agents":[{"key":"ember:c-a6e027d17d","runtime":"claude","process":"warm","pending":0,"lastTurn":{"id":"c00ae853-a223-4708-9565-54cc5206669b","kind":"input","outcome":"completed","declared":"final","ending":"all_done","need":"answered the question that was asked","startedAt":1792532500632,"endedAt":1792532500705},"agentText":"默认模型","statusText":"已完成：answered the question that was asked"}],"last":{"seq":2,"authorKind":"agent","author":"ember:c-a6e027d17d","text":"你好，我是测试用的 agent","createdAt":1792532500703,"by":{"kind":"agent","name":"agent","mine":false,"runtime":"claude","label":"agent"},"preview":"你好，我是测试用的 agent","time":{"createdAt":{"at":1792532500703,"ago":"刚刚","full":"10/21 05:41:40","until":"1 分钟内","past":true}}},"unread":true,"mine":true,"lastActiveAt":1792532500703,"station":"01M5DM6G5X6C2XCHD6HEHVZJ3K/166923bb2524533997f726f20a74178d0a3425a5ab28c2c71a017d32d7e2c39b","stationName":"studio","time":{"lastActiveAt":{"at":1792532500703,"ago":"刚刚","full":"10/21 05:41:40","until":"1 分钟内","past":true}},"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"peopleText":"你 发起","clientKey":"new:chat-be694113cea746f6bc","pinned":false,"tone":"done"}]}],"trouble":null,"members":1,"leading":"agents","glyph":{"online":1,"dim":0,"connecting":0,"failing":0,"working":0,"summary":"studio","label":"1 台 station，1 台在线"},"note":{"reading":false,"text":null,"failing":[],"empty":false}}},"w":1792532523902.484}
  #|{"in":{"id":8,"value":{"workspaces":{"01M5DM6G5X6C2XCHD6HEHVZJ3K":{"alert":0,"unread":1,"tone":"done","label":"1 个有新消息","badge":0,"items":[],"mineTone":"done"}},"badge":0,"badgeCounts":"attention","badgeKinds":{"on":true,"wait":true,"failed":true,"done":false,"message":false}}},"w":1792532523902.502}
  #|{"in":{"id":9,"value":[{"station":"01M5DM6G5X6C2XCHD6HEHVZJ3K/166923bb2524533997f726f20a74178d0a3425a5ab28c2c71a017d32d7e2c39b","id":"166923bb2524533997f726f20a74178d0a3425a5ab28c2c71a017d32d7e2c39b","name":"studio","summary":"空闲 · Apple M4 · 16 GB · macOS 27.0.1","face":"idle","line":"Apple M4","online":true,"reconnecting":false,"lastSeen":1792532500,"version":"0.1.0","link":{"state":"online"},"runtimes":[{"runtime":"claude","models":["claude-sonnet-5-5"]}],"models":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792532500610,"time":{"checkedAt":{"at":1792532500610,"ago":"刚刚","full":"10/21 05:41:40","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"overview":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null,"summaryText":"最近 7 天检查了 0 个 chat","changeText":null}},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","email":"alice@example.test","name":"Name of alice","sub":"alice","role":"owner","workspace":"01M5DM6G5X6C2XCHD6HEHVZJ3K","device":"04bbf18e8880832bdc5bd41814d83bee575be23c157fd36a1d3d685d23d5bfd3"},"connects":[],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792532500499,"time":{"checkedAt":{"at":1792532500499,"ago":"刚刚","full":"10/21 05:41:40","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792532500610,"time":{"checkedAt":{"at":1792532500610,"ago":"刚刚","full":"10/21 05:41:40","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]}],"processes":[],"counts":{"sessions":1,"running":0,"warm":1},"mesh":{"state":"running","origin":"http://127.0.0.1:18900","station":"166923bb2524533997f726f20a74178d0a3425a5ab28c2c71a017d32d7e2c39b","workspace":"Dev","workspaceId":"01M5DM6G5X6C2XCHD6HEHVZJ3K","name":"studio"},"slackUsers":[],"slackTeams":[],"slackApps":[],"feishuRegistrations":[],"disk":{"freeBytes":58479349760,"totalBytes":245107195904},"logins":[],"machineLogins":[{"runtime":"claude","installed":true,"loggedIn":false,"usable":false,"text":"无法读取 Claude Code 的登录信息","offered":false},{"runtime":"codex","installed":true,"loggedIn":false,"usable":false,"text":"Codex 未登录","offered":false}],"sharing":true,"consoleSignIn":true,"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"google","name":"Google Gemini","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xai","name":"xAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"mistral","name":"Mistral","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"deepseek","name":"DeepSeek","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen","name":"Qwen","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai","name":"Kimi","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai","name":"Z.ai","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax","name":"MiniMax","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ant-ling","name":"Ant Ling","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"jev","name":"Jev","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen-cn","name":"Qwen (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"openrouter","name":"OpenRouter","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"opencode","name":"OpenCode Zen","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"groq","name":"Groq","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"together","name":"Together AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"fireworks","name":"Fireworks","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cerebras","name":"Cerebras","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"huggingface","name":"Hugging Face","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"nvidia","name":"NVIDIA","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"baseten","name":"Baseten","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ollama","name":"Ollama","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"custom","name":"Custom","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""}],"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792532498065},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.305","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792532498065},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792532498065},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792532498065},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","latest":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792532498065}],"processesText":"没有运行中的 agent 进程","agentEnv":[],"drive":{"roots":[{"path":"/tmp/mbe2e-C/home/e2e-082940","name":"e2e-082940","state":"ok"}],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false}},"betaOffered":false,"host":{"hostname":"3720-Mac-mini-1","os":"macOS 27.0.1","arch":"arm64","cpus":10,"cpuModel":"Apple M4","load":0.3,"cpuBusy":0.09,"uptimeSec":11866,"memory":{"totalBytes":17179869184,"usedBytes":10174955520,"swapUsedBytes":341961605},"disk":{"path":"/tmp/mbe2e-C/data","totalBytes":245107195904,"freeBytes":58480762880},"emberRssBytes":155956688,"checkedAt":1792532504413,"summary":"10 核 · 16 GB","line":"macOS 27.0.1 · 10 核 · 16 GB · 已运行 0 天","facts":["3720-Mac-mini-1","macOS 27.0.1","arm64 · 10 核","已运行 3 小时"],"meters":[{"label":"CPU","short":"CPU","percent":9,"left":91,"level":"ok","value":"9%","remaining":"空闲 91%","big":"91","unit":"%","title":"CPU 空闲","total":"负载 3.0","note":"负载 3.0 · Apple M4"},{"label":"内存","short":"内存","percent":59,"left":41,"level":"ok","value":"9.5 GB / 16.0 GB","remaining":"剩 6.5 G","big":"6.5","unit":"GB","title":"内存剩","total":"共 16 GB","note":"swap 0.3 GB"},{"label":"磁盘","short":"磁盘","percent":76,"left":24,"level":"amber","value":"剩余 54.5 GB / 228 GB","remaining":"剩 54.5 G","big":"54.5","unit":"GB","title":"磁盘剩","total":"共 228 GB"}],"identity":"Apple M4 · 16 GB · macOS 27.0.1","details":[{"label":"主机名","value":"3720-Mac-mini-1"},{"label":"芯片","value":"Apple M4 · 10 核 · arm64"},{"label":"已运行","value":"3 小时"},{"label":"still.fail","value":"进程占用 149 MB"}],"usage":"内存 9.5 GB / 16.0 GB · 磁盘 剩余 54.5 GB / 228 GB","emberText":"still.fail 149 MB"},"way":{"path":"直连","via":"direct"},"time":{"lastSeen":{"at":1792532500000,"ago":"刚刚","full":"10/21 05:41:40","until":"1 分钟内","past":true}},"joined":false}]},"w":1792532523902.59}
  #|{"in":{"id":11,"value":{"items":[]}},"w":1792532523902.668}
  #|{"in":{"id":12,"ok":null},"w":1792532523902.67}
  #|{"in":{"id":13,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792532523902.676}
  #|{"in":{"id":14,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792532523902.68}
  #|{"out":{"id":15,"subscribe":{"topic":"longJobs","scope":"01M5DM6G5X6C2XCHD6HEHVZJ3K"},"keyed":true},"w":1792532523902.71}
  #|{"out":{"id":16,"call":"notify.permission","params":{"state":"unknown"}},"w":1792532523904.865}
  #|{"in":{"id":9,"delta":[{"path":[0,"host","checkedAt"],"set":1792532521902},{"path":[0,"host","cpuBusy"],"set":0.06},{"path":[0,"host","details",3,"value"],"set":"进程占用 129 MB"},{"path":[0,"host","disk","freeBytes"],"set":58480607232},{"path":[0,"host","emberRssBytes"],"set":135279768},{"path":[0,"host","emberText"],"set":"still.fail 129 MB"},{"path":[0,"host","load"],"set":0.29},{"path":[0,"host","memory","usedBytes"],"set":9879044096},{"path":[0,"host","meters",0,"big"],"set":"94"},{"path":[0,"host","meters",0,"left"],"set":94},{"path":[0,"host","meters",0,"note"],"set":"负载 2.9 · Apple M4"},{"path":[0,"host","meters",0,"percent"],"set":6},{"path":[0,"host","meters",0,"remaining"],"set":"空闲 94%"},{"path":[0,"host","meters",0,"total"],"set":"负载 2.9"},{"path":[0,"host","meters",0,"value"],"set":"6%"},{"path":[0,"host","meters",1,"big"],"set":"6.8"},{"path":[0,"host","meters",1,"left"],"set":42},{"path":[0,"host","meters",1,"percent"],"set":58},{"path":[0,"host","meters",1,"remaining"],"set":"剩 6.8 G"},{"path":[0,"host","meters",1,"value"],"set":"9.2 GB / 16.0 GB"},{"path":[0,"host","uptimeSec"],"set":11883},{"path":[0,"host","usage"],"set":"内存 9.2 GB / 16.0 GB · 磁盘 剩余 54.5 GB / 228 GB"},{"path":[0,"overview","disk","freeBytes"],"set":58479345664}]},"w":1792532523919.114}
  #|{"in":{"id":15,"value":{"groups":[]}},"w":1792532523919.162}
  #|{"in":{"id":16,"ok":null},"w":1792532523919.165}
  #|{"step":"#env MBUI_OPEN_PAGE=files","w":1792532523919.402}
  #|{"step":"answered notify.permission","w":1792532523919.404}
  #|{"step":"rest","w":1792532523936.105}
  #|{"step":"now tap =e2e-082940","w":1792532525053.077}
  #|{"step":"now tap =e2e-082940","acted":true,"w":1792532525069.821}
  #|{"out":{"id":17,"subscribe":{"topic":"drive","station":"01M5DM6G5X6C2XCHD6HEHVZJ3K/166923bb2524533997f726f20a74178d0a3425a5ab28c2c71a017d32d7e2c39b","root":"/tmp/mbe2e-C/home/e2e-082940","path":""},"keyed":true},"w":1792532525086.268}
  #|{"step":"rest","w":1792532525092.57}
  #|{"in":{"id":17,"value":{"path":"","entries":[{"name":"子文件夹","dir":true,"size":0,"mtime":1792532501251,"type":"","kind":"folder","sizeText":"","timeText":"05:41"},{"name":"小说-e2e.txt","dir":false,"size":36779,"mtime":1792532501265,"type":"text/plain; charset=utf-8","kind":"text","sizeText":"36 KB","timeText":"05:41"},{"name":"照片-082940.jpg","dir":false,"size":5526,"mtime":1792532513684,"type":"image/jpeg","kind":"image","sizeText":"5.4 KB","timeText":"05:41"},{"name":"说明.txt","dir":false,"size":43,"mtime":1792532501251,"type":"text/plain; charset=utf-8","kind":"text","sizeText":"43 B","timeText":"05:41"}],"truncated":false,"folders":1,"files":3,"countText":"1 个文件夹 · 3 个文件"}},"w":1792532525102.489}
  #|{"out":{"id":18,"subscribe":{"topic":"drivePlace","station":"01M5DM6G5X6C2XCHD6HEHVZJ3K/166923bb2524533997f726f20a74178d0a3425a5ab28c2c71a017d32d7e2c39b","root":"/tmp/mbe2e-C/home/e2e-082940","path":"小说-e2e.txt"},"keyed":true},"w":1792532525106.167}
  #|{"out":{"id":19,"subscribe":{"topic":"drivePlace","station":"01M5DM6G5X6C2XCHD6HEHVZJ3K/166923bb2524533997f726f20a74178d0a3425a5ab28c2c71a017d32d7e2c39b","root":"/tmp/mbe2e-C/home/e2e-082940","path":"说明.txt"},"keyed":true},"w":1792532525108.267}
  #|{"in":{"id":18,"value":null},"w":1792532525119.123}
  #|{"in":{"id":19,"value":null},"w":1792532525119.157}
  #|{"step":"now hold 800 照片-082940.jpg","w":1792532526203.166}
  #|{"step":"now hold 800 照片-082940.jpg","acted":true,"w":1792532526219.887}
  #|{"step":"until 已选 1 项","w":1792532527053.162}
  #|{"step":"tap icon:more","w":1792532527053.228}
  #|{"step":"tap icon:more","acted":true,"w":1792532527069.774}
  #|{"step":"rest","w":1792532527100.582}
  #|{"step":"now until 复制路径","w":1792532528536.81}
  #|{"step":"tap icon:trash","w":1792532528536.856}
  #|{"step":"tap icon:trash","acted":true,"w":1792532528553.517}
  #|{"step":"rest","w":1792532528570.157}
  #|{"step":"now until 删除「照片-082940.jpg」？","w":1792532529920.013}
  #|{"step":"tap =删除","w":1792532529920.055}
  #|{"step":"tap =删除","acted":true,"w":1792532529936.81}
  #|{"out":{"id":20,"call":"drive.remove","params":{"station":"01M5DM6G5X6C2XCHD6HEHVZJ3K/166923bb2524533997f726f20a74178d0a3425a5ab28c2c71a017d32d7e2c39b","root":"/tmp/mbe2e-C/home/e2e-082940","path":"照片-082940.jpg","permanent":true}},"w":1792532529952.704}
  #|{"step":"answered drive.remove","w":1792532529954.007}
  #|{"in":{"id":20,"ok":{}},"w":1792532529985.756}
  #|{"step":"rest","w":1792532530003.595}
  #|{"in":{"id":17,"value":{"path":"","entries":[{"name":"子文件夹","dir":true,"size":0,"mtime":1792532501251,"type":"","kind":"folder","sizeText":"","timeText":"05:41"},{"name":"小说-e2e.txt","dir":false,"size":36779,"mtime":1792532501265,"type":"text/plain; charset=utf-8","kind":"text","sizeText":"36 KB","timeText":"05:41"},{"name":"说明.txt","dir":false,"size":43,"mtime":1792532501251,"type":"text/plain; charset=utf-8","kind":"text","sizeText":"43 B","timeText":"05:41"}],"truncated":false,"folders":1,"files":2,"countText":"1 个文件夹 · 2 个文件"}},"w":1792532530169.118}
  #|{"step":"now gone 照片-082940.jpg","w":1792532531403.388}
  #|{"step":"rest","w":1792532531403.426}
  #|{"step":"","w":1792532531419.814}
  #|{"textrec":{"ib":["bfd9b0d6dc602826",12668,64],"r":[56,56,56,56]}}
  #|{"textrec":{"s":[13,400,0,"正在读取你的 workspace"],"r":[0,1,12.898832684824903,0,1,1,12.898832684824903,1,2,1,12.898832684824903,2,3,1,12.898832684824903,3,4,1,12.898832684824896,4,5,1,12.898832684824896,5,6,1,3.580078125,-1,7,1,9.8642578125,6,8,1,7.4775390625,7,9,1,4.875,8,10,1,6.85546875,9,11,1,6.6015625,10,12,1,7.8583984375,11,13,1,7.0966796875,12,14,1,7.1982421875,13,15,1,7.3505859375,14]}}
  #|{"textrec":{"m":[13,400,0],"r":[12.568359375,2.7421875,18]}}
  #|{"textrec":{"s":[24,700,0,"Dev"],"r":[0,1,17.075823068618774,15,1,1,13.365240812301636,16,2,1,12.759063005447388,17]}}
  #|{"textrec":{"m":[24,700,0],"r":[23.203125,5.0625,34]}}
  #|{"textrec":{"s":[16,600,0,"文件"],"r":[0,1,15.875486381322958,18,1,1,15.875486381322958,19]}}
  #|{"textrec":{"m":[16,600,0],"r":[15.46875,3.375,23]}}
  #|{"textrec":{"s":[17,400,0,"对话"],"r":[0,1,16.851167315175097,20,1,1,16.851167315175097,21]}}
  #|{"textrec":{"m":[17,400,0],"r":[16.435546875,3.5859375,24]}}
  #|{"textrec":{"g":15,"r":[0,0,18,19,0,-18,0]}}
  #|{"textrec":{"g":16,"r":[19,0,15,16,-1,-14,0]}}
  #|{"textrec":{"g":17,"r":[35,0,15,15,-1,-14,0]}}
  #|{"textrec":{"ib":["02698e60df92657e",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"ib":["1d51432b25a425eb",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"s":[15,400,0,"搜索全部内容"],"r":[0,1,14.883268482490273,22,1,1,14.883268482490273,23,2,1,14.883268482490273,24,3,1,14.883268482490273,25,4,1,14.88326848249028,26,5,1,14.88326848249028,27]}}
  #|{"textrec":{"m":[15,400,0],"r":[14.501953125,3.1640625,21]}}
  #|{"textrec":{"s":[15,600,0,"今天"],"r":[0,1,14.883268482490273,28,1,1,14.883268482490273,29]}}
  #|{"textrec":{"m":[15,600,0],"r":[14.501953125,3.1640625,21]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 post:你好，我是测试用的 agent"],"r":[0,1,15.875486381322958,30,1,1,15.875486381322958,31,2,1,15.875486381322958,30,3,1,15.875486381322958,32,4,1,15.875486381322958,33,5,1,15.875486381322958,34,6,1,15.875486381322958,35,7,1,15.875486381322958,36,8,1,3.95001220703125,-1,9,1,9.824199676513672,37,10,1,9.432537078857422,38,11,1,8.471200942993164,39,12,1,5.973020553588867,40,13,1,4.952056884765625,41,14,1,15.875486381322958,42,15,1,15.875486381322958,43,16,1,16.09338521400778,44,17,1,15.875486381322958,45,18,1,15.875486381322958,46,19,1,15.87548638132293,32,20,1,15.875486381322958,33,21,1,15.875486381322958,47,22,1,15.875486381322958,34,23,1,3.95001220703125,-1,24,1,8.899068832397461,48,25,1,9.801153182983398,49,26,1,9.127458572387695,50,27,1,9.466253280639648,51,28,1,5.999713897705078,40]}}
  #|{"textrec":{"s":[14,400,0,"你好，我是测试用的 agent"],"r":[0,1,13.891050583657588,52,1,1,13.891050583657588,53,2,1,14.081712062256813,54,3,1,13.891050583657588,55,4,1,13.891050583657588,56,5,1,13.891050583657588,57,6,1,13.891050583657588,58,7,1,13.891050583657588,59,8,1,13.891050583657588,60,9,1,3.787109375000014,-1,10,1,7.57421875,61,11,1,8.380859375,62,12,1,7.84765625,63,13,1,8.0185546875,64,14,1,4.935546875,65]}}
  #|{"textrec":{"m":[14,400,0],"r":[13.53515625,2.953125,20]}}
  #|{"textrec":{"s":[16,600,0,"…"],"r":[0,1,14.076484680175781,66]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 post:你好，我是测试用的…"],"r":[0,1,15.875486381322958,30,1,1,15.875486381322958,31,2,1,15.875486381322958,30,3,1,15.875486381322958,32,4,1,15.875486381322958,33,5,1,15.875486381322958,34,6,1,15.875486381322958,35,7,1,15.875486381322958,36,8,1,3.95001220703125,-1,9,1,9.824199676513672,37,10,1,9.432537078857422,38,11,1,8.471200942993164,39,12,1,5.973020553588867,40,13,1,4.952056884765625,41,14,1,15.875486381322958,42,15,1,15.875486381322958,43,16,1,16.09338521400778,44,17,1,15.875486381322958,45,18,1,15.875486381322958,46,19,1,15.87548638132293,32,20,1,15.875486381322958,33,21,1,15.875486381322958,47,22,1,15.875486381322958,34,23,1,14.076484680175781,66]}}
  #|{"textrec":{"s":[15,600,0,"studio"],"r":[0,1,8.000344634056091,67,1,1,5.658300518989563,68,2,1,8.93320620059967,69,3,1,9.332013130187988,70,4,1,3.8520312309265137,71,5,1,8.901597261428833,72]}}
  #|{"textrec":{"s":[16,400,0,"主目录"],"r":[0,1,15.875486381322958,73,1,1,15.875486381322958,74,2,1,15.875486381322958,75]}}
  #|{"textrec":{"m":[16,400,0],"r":[15.46875,3.375,23]}}
  #|{"textrec":{"s":[16,400,0,"e2e-082940"],"r":[0,1,8.828125,76,1,1,9.3046875,77,2,1,8.7890625,76,3,1,7.234375,78,4,1,9.765625,79,5,1,9.90625,80,6,1,9.34375,77,7,1,9.875,81,8,1,9.984375,82,9,1,9.765625,79]}}
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
  #|{"textrec":{"g":67,"r":[666,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":68,"r":[677,0,8,13,-1,-11,0]}}
  #|{"textrec":{"g":69,"r":[686,0,10,12,0,-10,0]}}
  #|{"textrec":{"g":70,"r":[697,0,11,15,-1,-13,0]}}
  #|{"textrec":{"g":71,"r":[709,0,6,14,-1,-13,0]}}
  #|{"textrec":{"g":72,"r":[716,0,11,12,-1,-10,0]}}
  #|{"textrec":{"ib":["4165e1c325ff4b32",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"ib":["7d024a54eca23c07",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"g":20,"r":[728,0,18,18,-1,-15,0]}}
  #|{"textrec":{"g":21,"r":[747,0,19,18,-1,-15,0]}}
  #|{"textrec":{"g":73,"r":[767,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":74,"r":[785,0,14,16,1,-13,0]}}
  #|{"textrec":{"g":75,"r":[800,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":76,"r":[818,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":77,"r":[830,0,10,14,0,-13,0]}}
  #|{"textrec":{"g":78,"r":[841,0,8,5,0,-7,0]}}
  #|{"textrec":{"g":79,"r":[850,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":80,"r":[862,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":81,"r":[874,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":82,"r":[886,0,12,14,-1,-13,0]}}
  #|{"textrec":{"g":18,"r":[899,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":19,"r":[918,0,17,17,-1,-14,0]}}
  #|{"textrec":{"ib":["2bb63fc1d380f765",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"s":[17,400,0,"设置"],"r":[0,1,16.851167315175097,83,1,1,16.851167315175097,84]}}
  #|{"textrec":{"s":[16,600,0,"e2e-082940"],"r":[0,1,9.127458572387695,50,1,1,9.717817306518555,85,2,1,9.100765228271484,50,3,1,7.363014221191406,86,4,1,10.31976318359375,87,5,1,10.465335845947266,88,6,1,9.744510650634766,85,7,1,10.3499755859375,89,8,1,10.42471694946289,90,9,1,10.31976318359375,87]}}
  #|{"textrec":{"s":[17,400,0,"文件"],"r":[0,1,16.851167315175097,91,1,1,16.851167315175097,92]}}
  #|{"textrec":{"g":83,"r":[936,0,19,18,-1,-15,0]}}
  #|{"textrec":{"g":84,"r":[956,0,18,17,-1,-14,0]}}
  #|{"textrec":{"s":[13,400,0,"1 个文件夹 · 3 个文件"],"r":[0,1,5.9541015625,93,1,1,3.580078125,-1,2,1,12.898832684824903,94,3,1,12.898832684824903,95,4,1,12.898832684824903,96,5,1,12.898832684824903,97,6,1,3.580078125,-1,7,1,6.228545204222115,98,8,1,3.580078125,-1,9,1,8.07421875,99,10,1,3.580078125,-1,11,1,12.898832684824896,94,12,1,12.898832684824896,95,13,1,12.898832684824896,96]}}
  #|{"textrec":{"s":[15,400,0,"子文件夹"],"r":[0,1,14.883268482490273,100,1,1,14.883268482490273,101,2,1,14.883268482490273,102,3,1,14.883268482490273,103]}}
  #|{"textrec":{"s":[12,400,0,"05:41"],"r":[0,1,7.55859375,104,1,1,7.41796875,105,2,1,3.5625,106,3,1,7.6640625,107,4,1,5.5078125,108]}}
  #|{"textrec":{"m":[12,400,0],"r":[11.6015625,2.53125,17]}}
  #|{"textrec":{"s":[15,400,0,"小说-e2e.txt"],"r":[0,1,14.883268482490273,109,1,1,14.883268482490273,110,2,1,6.8408203125,111,3,1,8.3349609375,112,4,1,8.78173828125,113,5,1,8.29833984375,112,6,1,4.072265625,114,7,1,5.068359375,115,8,1,7.6318359375,116,9,1,5.21484375,115]}}
  #|{"textrec":{"s":[12,400,0,"36 KB · 05:41"],"r":[0,1,7.5234375,117,1,1,7.640625,118,2,1,3.375,-1,3,1,7.904296875,119,4,1,7.88671875,120,5,1,3.375,-1,6,1,5.754933455713626,121,7,1,3.375,-1,8,1,7.55859375,104,9,1,7.41796875,105,10,1,3.5625,106,11,1,7.6640625,107,12,1,5.5078125,108]}}
  #|{"textrec":{"s":[15,400,0,"照片-082940.jpg"],"r":[0,1,14.883268482490273,122,1,1,14.883268482490273,123,2,1,6.8408203125,111,3,1,9.2138671875,124,4,1,9.345703125,125,5,1,8.818359375,113,6,1,9.31640625,126,7,1,9.4189453125,127,8,1,8.9208984375,124,9,1,3.92578125,114,10,1,3.46435546875,128,11,1,8.9208984375,129,12,1,8.90625,130]}}
  #|{"textrec":{"s":[12,400,0,"5.4 KB · 05:41"],"r":[0,1,7.212890625,105,1,1,3.181640625,131,2,1,7.546875,107,3,1,3.375,-1,4,1,7.904296875,119,5,1,7.88671875,120,6,1,3.375,-1,7,1,5.754933455713626,121,8,1,3.375,-1,9,1,7.55859375,104,10,1,7.41796875,105,11,1,3.5625,106,12,1,7.6640625,107,13,1,5.5078125,108]}}
  #|{"textrec":{"s":[15,400,0,"说明.txt"],"r":[0,1,14.883268482490273,110,1,1,14.883268482490273,132,2,1,4.072265625,114,3,1,5.068359375,115,4,1,7.6318359375,116,5,1,5.21484375,115]}}
  #|{"textrec":{"s":[12,400,0,"43 B · 05:41"],"r":[0,1,7.72265625,107,1,1,7.5234375,117,2,1,3.375,-1,3,1,7.88671875,120,4,1,3.375,-1,5,1,5.754933455713626,121,6,1,3.375,-1,7,1,7.55859375,104,8,1,7.41796875,105,9,1,3.5625,106,10,1,7.6640625,107,11,1,5.5078125,108]}}
  #|{"textrec":{"g":91,"r":[975,0,18,18,-1,-15,0]}}
  #|{"textrec":{"g":92,"r":[994,0,18,18,-1,-15,0]}}
  #|{"textrec":{"g":93,"r":[1013,0,7,12,-1,-11,0]}}
  #|{"textrec":{"g":94,"r":[1021,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":95,"r":[1037,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":96,"r":[1053,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":97,"r":[1069,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":98,"r":[1085,0,4,5,1,-7,0]}}
  #|{"textrec":{"g":99,"r":[1090,0,10,13,-1,-11,0]}}
  #|{"textrec":{"ib":["b17c2fa67cbec771",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"ib":["23c7a61557c7b0d0",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"ib":["275a1f2a0cb12622",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"g":100,"r":[1101,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":101,"r":[1118,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":102,"r":[1136,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":103,"r":[1153,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":104,"r":[1170,0,9,12,-1,-10,0]}}
  #|{"textrec":{"g":105,"r":[1180,0,9,12,-1,-10,0]}}
  #|{"textrec":{"g":106,"r":[1190,0,4,9,0,-7,0]}}
  #|{"textrec":{"g":107,"r":[1195,0,10,11,-1,-10,0]}}
  #|{"textrec":{"g":108,"r":[1206,0,7,11,-1,-10,0]}}
  #|{"textrec":{"g":109,"r":[1214,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":110,"r":[1232,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":111,"r":[1250,0,7,4,0,-6,0]}}
  #|{"textrec":{"g":112,"r":[1258,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":113,"r":[1269,0,10,13,0,-12,0]}}
  #|{"textrec":{"g":114,"r":[1280,0,5,5,0,-3,0]}}
  #|{"textrec":{"g":115,"r":[1286,0,7,13,-1,-11,0]}}
  #|{"textrec":{"g":116,"r":[1294,0,10,10,-1,-9,0]}}
  #|{"textrec":{"g":117,"r":[1305,0,9,12,-1,-10,0]}}
  #|{"textrec":{"g":118,"r":[1315,0,9,12,-1,-10,0]}}
  #|{"textrec":{"g":119,"r":[1325,0,9,11,0,-10,0]}}
  #|{"textrec":{"g":120,"r":[1335,0,9,11,0,-10,0]}}
  #|{"textrec":{"g":121,"r":[1345,0,5,5,0,-7,0]}}
  #|{"textrec":{"g":122,"r":[1351,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":123,"r":[1368,0,15,16,0,-13,0]}}
  #|{"textrec":{"g":124,"r":[1384,0,11,14,-1,-12,0]}}
  #|{"textrec":{"g":125,"r":[1396,0,11,14,-1,-12,0]}}
  #|{"textrec":{"g":126,"r":[1408,0,11,14,-1,-12,0]}}
  #|{"textrec":{"g":127,"r":[1420,0,11,13,-1,-12,0]}}
  #|{"textrec":{"g":128,"r":[1432,0,6,17,-2,-13,0]}}
  #|{"textrec":{"g":129,"r":[1439,0,10,14,0,-10,0]}}
  #|{"textrec":{"g":130,"r":[1450,0,10,14,-1,-10,0]}}
  #|{"textrec":{"g":131,"r":[1461,0,4,5,0,-3,0]}}
  #|{"textrec":{"g":132,"r":[1466,0,15,16,0,-13,0]}}
  #|{"textrec":{"g":50,"r":[1482,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":85,"r":[1494,0,11,14,0,-13,0]}}
  #|{"textrec":{"g":86,"r":[1506,0,8,5,0,-7,0]}}
  #|{"textrec":{"g":87,"r":[1515,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":88,"r":[1527,0,12,15,-1,-13,0]}}
  #|{"textrec":{"g":89,"r":[1540,0,12,15,-1,-13,0]}}
  #|{"textrec":{"g":90,"r":[1553,0,12,14,-1,-13,0]}}
  #|{"textrec":{"ib":["0e910fb4d25445a3",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"ib":["b3685975cd23abc3",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["ddfdc2820df8a676",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"s":[16,600,0,"已选 1 项"],"r":[0,1,15.875486381322958,133,1,1,15.875486381322958,134,2,1,3.95001220703125,-1,3,1,7.594245910644531,135,4,1,3.95001220703125,-1,5,1,15.875486381322958,136]}}
  #|{"textrec":{"s":[17,400,0,"取消"],"r":[0,1,16.851167315175097,137,1,1,16.851167315175097,138]}}
  #|{"textrec":{"s":[15,400,0,"全选"],"r":[0,1,14.883268482490273,24,1,1,14.883268482490273,139]}}
  #|{"textrec":{"g":133,"r":[1566,0,16,17,0,-14,0]}}
  #|{"textrec":{"g":134,"r":[1583,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":135,"r":[1601,0,7,14,0,-13,0]}}
  #|{"textrec":{"g":136,"r":[1609,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":137,"r":[1628,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":138,"r":[1647,0,18,18,-1,-15,0]}}
  #|{"textrec":{"g":139,"r":[1666,0,16,16,-1,-13,0]}}
  #|{"textrec":{"ib":["d2e044956ae472e7",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"s":[17,700,0,"照片-082940.jpg"],"r":[0,1,16.851167315175097,140,1,1,16.851167315175097,141,2,1,7.802734375,142,3,1,11.2060546875,143,4,1,11.36376953125,144,5,1,10.50048828125,145,6,1,11.189453125,146,7,1,11.24755859375,147,8,1,10.770263671875,143,9,1,5.042724609375,148,10,1,4.445068359375,149,11,1,10.56689453125,150,12,1,10.537841796875014,151]}}
  #|{"textrec":{"m":[17,700,0],"r":[16.435546875,3.5859375,24]}}
  #|{"textrec":{"s":[15,400,0,"重命名"],"r":[0,1,14.883268482490273,152,1,1,14.883268482490273,153,2,1,14.883268482490273,154]}}
  #|{"textrec":{"s":[15,400,0,"下载"],"r":[0,1,14.883268482490273,155,1,1,14.883268482490273,156]}}
  #|{"textrec":{"s":[15,400,0,"分享"],"r":[0,1,14.883268482490273,157,1,1,14.883268482490273,158]}}
  #|{"textrec":{"s":[15,400,0,"复制路径"],"r":[0,1,14.883268482490273,159,1,1,14.883268482490273,160,2,1,14.883268482490273,161,3,1,14.883268482490273,162]}}
  #|{"textrec":{"s":[15,400,0,"删除"],"r":[0,1,14.883268482490273,163,1,1,14.883268482490273,164]}}
  #|{"textrec":{"g":140,"r":[1683,0,18,18,-1,-15,0]}}
  #|{"textrec":{"g":141,"r":[1702,0,16,18,0,-15,0]}}
  #|{"textrec":{"g":142,"r":[1719,0,8,5,0,-7,0]}}
  #|{"textrec":{"g":143,"r":[1728,0,12,16,0,-14,0]}}
  #|{"textrec":{"g":144,"r":[1741,0,12,16,0,-14,0]}}
  #|{"textrec":{"g":145,"r":[1754,0,11,15,0,-14,0]}}
  #|{"textrec":{"g":146,"r":[1766,0,12,16,0,-14,0]}}
  #|{"textrec":{"g":147,"r":[1779,0,13,14,-1,-13,0]}}
  #|{"textrec":{"g":148,"r":[1793,0,6,6,0,-4,0]}}
  #|{"textrec":{"g":149,"r":[1800,0,7,20,-2,-15,0]}}
  #|{"textrec":{"g":150,"r":[1808,0,12,16,0,-11,0]}}
  #|{"textrec":{"g":151,"r":[1821,0,12,16,-1,-11,0]}}
  #|{"textrec":{"g":152,"r":[1834,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":153,"r":[1851,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":154,"r":[1868,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":155,"r":[1884,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":156,"r":[1901,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":157,"r":[1918,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":158,"r":[1935,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":159,"r":[1952,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":160,"r":[1969,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":161,"r":[1986,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":162,"r":[2004,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":163,"r":[2022,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":164,"r":[0,21,16,16,0,-13,0]}}
  #|{"textrec":{"ib":["e51cacbaf3e3367d",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["5586d6bf44ec35db",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["87df7748e7ef6ab9",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["9a47fa114a34d016",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["0c818ea1c0c4e805",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"s":[17,700,0,"删除「照片-082940.jpg」？"],"r":[0,1,16.851167315175097,165,1,1,25.351167315175097,166,2,1,6.366731517509727,167,3,1,16.851167315175097,140,4,1,16.85116731517509,141,5,1,7.802734375,142,6,1,11.2060546875,143,7,1,11.36376953125,144,8,1,10.50048828125,145,9,1,11.189453125,146,10,1,11.24755859375,147,11,1,10.770263671875,143,12,1,5.042724609375,148,13,1,4.445068359375,149,14,1,10.56689453125,150,15,1,10.537841796875,151,16,1,8.194066147859928,168,17,1,8.582684824902714,169]}}
  #|{"textrec":{"s":[14,400,0,"文件将从 station 上删除，且无法恢复"],"r":[0,1,13.891050583657588,170,1,1,13.891050583657588,171,2,1,13.891050583657588,172,3,1,13.891050583657588,173,4,1,3.787109375,-1,5,1,7.1435546875,174,6,1,4.9013671875,65,7,1,7.57421875,61,8,1,4.935546875,65,9,1,3.30859375,175,10,1,8.12109375,176,11,1,8.0185546875,64,12,1,3.787109375,-1,13,1,13.891050583657588,177,14,1,13.891050583657588,178,15,1,13.891050583657574,179,16,1,14.081712062256798,54,17,1,13.891050583657574,180,18,1,13.891050583657602,181,19,1,13.891050583657602,182,20,1,13.891050583657602,183,21,1,13.891050583657602,184]}}
  #|{"textrec":{"s":[14,600,0,"取消"],"r":[0,1,13.891050583657588,185,1,1,13.891050583657588,186]}}
  #|{"textrec":{"m":[14,600,0],"r":[13.53515625,2.953125,20]}}
  #|{"textrec":{"s":[14,600,0,"删除"],"r":[0,1,13.891050583657588,187,1,1,13.891050583657588,188]}}
  #|{"textrec":{"g":165,"r":[17,21,18,18,-1,-15,0]}}
  #|{"textrec":{"g":166,"r":[36,21,18,18,0,-15,0]}}
  #|{"textrec":{"g":167,"r":[55,21,9,13,-1.8333333333333304,-15,0]}}
  #|{"textrec":{"g":168,"r":[65,21,9,13,-1,-10,0]}}
  #|{"textrec":{"g":169,"r":[75,21,10,16,-1,-14,0]}}
  #|{"textrec":{"g":170,"r":[86,21,16,16,-1,-13,0]}}
  #|{"textrec":{"g":171,"r":[103,21,16,16,-1,-13,0]}}
  #|{"textrec":{"g":172,"r":[120,21,16,16,-1,-13,0]}}
  #|{"textrec":{"g":173,"r":[137,21,16,16,-1,-13,0]}}
  #|{"textrec":{"g":174,"r":[154,21,9,11,-1,-9,0]}}
  #|{"textrec":{"g":175,"r":[164,21,5,13,-1,-12,0]}}
  #|{"textrec":{"g":176,"r":[170,21,10,11,-1,-9,0]}}
  #|{"textrec":{"g":177,"r":[181,21,15,15,-1,-13,0]}}
  #|{"textrec":{"g":178,"r":[197,21,15,16,-1,-13,0]}}
  #|{"textrec":{"g":179,"r":[213,21,15,15,0,-12,0]}}
  #|{"textrec":{"g":180,"r":[229,21,15,14,-1,-12,0]}}
  #|{"textrec":{"g":181,"r":[245,21,15,15,-1,-12,0]}}
  #|{"textrec":{"g":182,"r":[261,21,16,16,-1,-13,0]}}
  #|{"textrec":{"g":183,"r":[278,21,16,16,-1,-13,0]}}
  #|{"textrec":{"g":184,"r":[295,21,15,16,-1,-13,0]}}
  #|{"textrec":{"g":185,"r":[311,21,16,15,-1,-12,0]}}
  #|{"textrec":{"g":186,"r":[328,21,15,16,-1,-13,0]}}
  #|{"textrec":{"g":187,"r":[344,21,15,16,-1,-13,0]}}
  #|{"textrec":{"g":188,"r":[360,21,16,15,-1,-12,0]}}
  #|{"textrec":{"ib":["d2ccd5cf9373640b",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"s":[13,400,0,"1 个文件夹 · 2 个文件"],"r":[0,1,5.9541015625,93,1,1,3.580078125,-1,2,1,12.898832684824903,94,3,1,12.898832684824903,95,4,1,12.898832684824903,96,5,1,12.898832684824903,97,6,1,3.580078125,-1,7,1,6.228545204222115,98,8,1,3.580078125,-1,9,1,7.76953125,189,10,1,3.580078125,-1,11,1,12.898832684824896,94,12,1,12.898832684824896,95,13,1,12.898832684824896,96]}}
  #|{"textrec":{"g":189,"r":[377,21,9,12,-1,-11,0]}}
