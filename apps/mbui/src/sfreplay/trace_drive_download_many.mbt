// e2e/traces/drive-download-many.trace, made by scripts/trace.py from 03-drive_download_many.log: not edited by hand.

///|
/// What the app and its core said in the run, a line each.
pub let trace_drive_download_many : String =
  #|{"step":"drive-big 105609"}
  #|{"env":{"MBUI_CLOUD":"http://127.0.0.1:18900","MBUI_CORE_ACCOUNT":"{\"sub\":\"alice\",\"email\":\"alice@example.test\",\"name\":\"Name of alice\",\"picture\":\"\",\"access\":\"-\",\"refresh\":\"-\",\"accessExpires\":1792531340}"}}
  #|{"out":{"id":1,"call":"client.device","params":{"client":"still.fail mbui","app":"desktop","userAgent":"Macintosh; Mac OS X"}},"w":1792531059977.802}
  #|{"in":{"id":1,"ok":null},"w":1792531060063.53}
  #|{"out":{"id":2,"subscribe":{"topic":"accounts"},"keyed":true},"w":1792531060063.554}
  #|{"out":{"id":3,"subscribe":{"topic":"prefs"},"keyed":true},"w":1792531060063.566}
  #|{"step":"# written by scripts/rerecord.sh from its test (src/sfreplay/emit.mbt): not edited by hand","w":1792531060064.918}
  #|{"step":"timeout 90000","w":1792531060064.923}
  #|{"step":"answered client.device","w":1792531060064.925}
  #|{"step":"answered client.focus","w":1792531060077.803}
  #|{"in":{"id":2,"value":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""}]},"w":1792531060160.744}
  #|{"in":{"id":3,"value":{"onlyMine":false,"onlyWatching":false,"onlyDecisions":false,"listFilter":{},"appearance":"system","rowPicture":"auto","absoluteTime":false,"lang":"zh","keys":{},"lastChat":{},"openChat":{"01M5DJSXYHSNZV6N1ZJRSKAKGM":{"station":"01M5DJSXYHSNZV6N1ZJRSKAKGM/584cb8e0c9c046dcf0fcddfe90a3f9cda0b4c94f9deef69edc45390bc9681141","key":"ember:c-d5058f311d"}},"chatTabs":{},"dropFiles":{},"driveViews":{},"resume":{},"stationUpdatesDismissed":{},"device":{"app":"desktop","phone":false,"handoff":false},"reader":{"size":18,"line":1.7,"margin":22,"face":"sans","indent":true,"paper":"follow"},"rails":{},"bars":{"sets":[["chats","files","profiles","stations"],["decisions","usage","connects","archive"]],"current":0},"barsBy":{}}},"w":1792531060160.768}
  #|{"out":{"id":4,"subscribe":{"topic":"workspaces"},"keyed":true},"w":1792531060160.79}
  #|{"out":{"id":5,"subscribe":{"topic":"status"},"keyed":true},"w":1792531060160.802}
  #|{"in":{"id":4,"value":[{"account":{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""},"workspaces":[{"id":"01M5DJSXYHSNZV6N1ZJRSKAKGM","name":"Dev","role":"owner","created_at":1792531036,"stations":1,"members":1,"relays":[],"time":{"created_at":{"past":true,"at":1792531036000,"ago":"刚刚","full":"10/21 05:17:16","until":"1 分钟内"}}}],"invitations":[],"relay_url":"http://127.0.0.1:18940","loaded":true,"beta":true}]},"w":1792531060179.313}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792531060179.326}
  #|{"out":{"id":6,"subscribe":{"topic":"lock","workspace":"01M5DJSXYHSNZV6N1ZJRSKAKGM"},"keyed":true},"w":1792531060179.355}
  #|{"out":{"id":7,"subscribe":{"topic":"chats","scope":"01M5DJSXYHSNZV6N1ZJRSKAKGM","mine":false},"keyed":true},"w":1792531060179.37}
  #|{"out":{"id":8,"subscribe":{"topic":"workspaceMarks","workspace":"01M5DJSXYHSNZV6N1ZJRSKAKGM"},"keyed":true},"w":1792531060179.493}
  #|{"out":{"id":9,"subscribe":{"topic":"stations","scope":"01M5DJSXYHSNZV6N1ZJRSKAKGM"},"keyed":true},"w":1792531060179.515}
  #|{"out":{"id":10,"subscribe":{"topic":"workspace","workspace":"01M5DJSXYHSNZV6N1ZJRSKAKGM"},"keyed":true},"w":1792531060179.519}
  #|{"out":{"id":11,"subscribe":{"topic":"status","workspace":"01M5DJSXYHSNZV6N1ZJRSKAKGM"},"keyed":true},"w":1792531060179.582}
  #|{"out":{"id":12,"call":"client.focus","params":{"visible":true,"focused":true,"workspace":"01M5DJSXYHSNZV6N1ZJRSKAKGM"}},"w":1792531060181.049}
  #|{"out":{"id":13,"subscribe":{"topic":"notify"},"keyed":true},"w":1792531060181.057}
  #|{"out":{"id":14,"subscribe":{"topic":"notify","workspace":"01M5DJSXYHSNZV6N1ZJRSKAKGM"},"keyed":true},"w":1792531060181.064}
  #|{"in":{"id":6,"value":{"available":true,"locked":false,"notice":true,"role":"owner","manages":true,"owner":true,"canSign":true,"signs":false,"me":{"device":"94465e51a8c39a778b9c760c3ba0d492430d29180a64dd7f482a4de67550282d","code":"FGA-GG5","kind":"app","confirmed":false,"waiting":false,"asked":false},"signers":0,"members":[],"stations":[{"id":"584cb8e0c9c046dcf0fcddfe90a3f9cda0b4c94f9deef69edc45390bc9681141","name":"studio","version":"0.1.0","online":true,"protected":false}],"protected":0,"requests":[],"renew":[],"attention":0}},"w":1792531060194.088}
  #|{"in":{"id":10,"value":{"id":"01M5DJSXYHSNZV6N1ZJRSKAKGM","name":"Dev","role":"owner","created_at":1792531036,"members":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":"https://example.test/p.png","role":"owner","added_at":1792531036}],"stations":[{"id":"584cb8e0c9c046dcf0fcddfe90a3f9cda0b4c94f9deef69edc45390bc9681141","name":"studio","emoji":null,"icon":null,"enrolled_at":1792531036,"enrolled_by":"alice","last_seen":1792531039,"version":"0.1.0","time":{"last_seen":{"past":true,"at":1792531039000,"ago":"刚刚","full":"10/21 05:17:19","until":"1 分钟内"}}}],"invitations":[],"added":[],"relays":[],"lock":null,"lock_requests":0,"time":{"created_at":{"past":true,"at":1792531036000,"ago":"刚刚","full":"10/21 05:17:16","until":"1 分钟内"}}}},"w":1792531060194.117}
  #|{"in":{"id":7,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"stations":[{"station":"01M5DJSXYHSNZV6N1ZJRSKAKGM/584cb8e0c9c046dcf0fcddfe90a3f9cda0b4c94f9deef69edc45390bc9681141","id":"584cb8e0c9c046dcf0fcddfe90a3f9cda0b4c94f9deef69edc45390bc9681141","name":"studio","state":"online"}],"loading":false,"days":[{"daysAgo":0,"at":1792531050591,"label":"今天","items":[{"id":"ember:c-d5058f311d","session":"ember:c-d5058f311d","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","agents":[{"key":"ember:c-d5058f311d","runtime":"claude","process":"warm","pending":0,"lastTurn":{"id":"fb1da1ac-1500-4b71-bc22-1ea38527a27b","kind":"nudge","outcome":"completed","startedAt":1792531050588,"endedAt":1792531050590},"agentText":"默认模型","mark":"failed","statusText":"出错：意外停止","badgeText":"失败，需要处理"}],"last":{"seq":4,"authorKind":"ember","author":"ember","authorName":"still.fail","text":"⚠️ 本轮 agent 未在对话中回复，以下是它最后输出的文字，由 station 代为转发（并非它发布的消息）；回复即可继续：\n\n> Your turn ended without a state, so nobody knows where the chat stands. Only a real unresolved need requires need_human. A factual a","createdAt":1792531050591,"by":{"kind":"ember","name":"still.fail","mine":false,"label":"still.fail"},"preview":"⚠️ 本轮 agent 未在对话中回复，以下是它最后输出的文字，由 station 代为转发（并非它发布的消息）；回复即可继续： Your turn ended without a state, so nobody knows where the chat stands. Only a real unresolved need requires need_human. A factual a","time":{"createdAt":{"at":1792531050591,"ago":"刚刚","full":"10/21 05:17:30","until":"1 分钟内","past":true}}},"unread":false,"mine":true,"lastActiveAt":1792531050591,"station":"01M5DJSXYHSNZV6N1ZJRSKAKGM/584cb8e0c9c046dcf0fcddfe90a3f9cda0b4c94f9deef69edc45390bc9681141","stationName":"studio","state":"failed","time":{"lastActiveAt":{"at":1792531050591,"ago":"刚刚","full":"10/21 05:17:30","until":"1 分钟内","past":true}},"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"peopleText":"你 发起","clientKey":"new:chat-d4b1907cb26e800abb","pinned":false,"stateText":"出错：意外停止","tone":"alert"}]}],"trouble":null,"members":1,"leading":"agents","glyph":{"online":1,"dim":0,"connecting":0,"failing":0,"working":0,"summary":"studio","label":"1 台 station，1 台在线"},"note":{"reading":false,"text":null,"failing":[],"empty":false}}},"w":1792531060194.15}
  #|{"in":{"id":8,"value":{"workspaces":{"01M5DJSXYHSNZV6N1ZJRSKAKGM":{"alert":1,"unread":0,"tone":"alert","label":"1 个出错","chat":{"station":"01M5DJSXYHSNZV6N1ZJRSKAKGM/584cb8e0c9c046dcf0fcddfe90a3f9cda0b4c94f9deef69edc45390bc9681141","key":"ember:c-d5058f311d"},"badge":0,"items":[{"kind":"alert","workspace":"01M5DJSXYHSNZV6N1ZJRSKAKGM","workspaceName":"Dev","station":"01M5DJSXYHSNZV6N1ZJRSKAKGM/584cb8e0c9c046dcf0fcddfe90a3f9cda0b4c94f9deef69edc45390bc9681141","stationName":"studio","session":"ember:c-d5058f311d","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","text":"出错：意外停止","seen":true,"at":1792531050591}],"mineTone":"alert"}},"badge":0,"badgeCounts":"attention","badgeKinds":{"on":true,"wait":true,"failed":true,"done":false,"message":false}}},"w":1792531060194.174}
  #|{"in":{"id":9,"value":[{"station":"01M5DJSXYHSNZV6N1ZJRSKAKGM/584cb8e0c9c046dcf0fcddfe90a3f9cda0b4c94f9deef69edc45390bc9681141","id":"584cb8e0c9c046dcf0fcddfe90a3f9cda0b4c94f9deef69edc45390bc9681141","name":"studio","summary":"空闲 · Apple M4 · 16 GB · macOS 27.0.1","face":"idle","line":"Apple M4","online":true,"reconnecting":false,"lastSeen":1792531039,"version":"0.1.0","link":{"state":"online"},"runtimes":[{"runtime":"claude","models":["claude-sonnet-5-5"]}],"models":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792531040014,"time":{"checkedAt":{"at":1792531040014,"ago":"刚刚","full":"10/21 05:17:20","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"overview":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null,"summaryText":"最近 7 天检查了 0 个 chat","changeText":null}},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","email":"alice@example.test","name":"Name of alice","sub":"alice","role":"owner","workspace":"01M5DJSXYHSNZV6N1ZJRSKAKGM","device":"94465e51a8c39a778b9c760c3ba0d492430d29180a64dd7f482a4de67550282d"},"connects":[],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792531039906,"time":{"checkedAt":{"at":1792531039906,"ago":"刚刚","full":"10/21 05:17:19","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792531040014,"time":{"checkedAt":{"at":1792531040014,"ago":"刚刚","full":"10/21 05:17:20","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]}],"processes":[],"counts":{"sessions":1,"running":0,"warm":1},"mesh":{"state":"running","origin":"http://127.0.0.1:18900","station":"584cb8e0c9c046dcf0fcddfe90a3f9cda0b4c94f9deef69edc45390bc9681141","workspace":"Dev","workspaceId":"01M5DJSXYHSNZV6N1ZJRSKAKGM","name":"studio"},"slackUsers":[],"slackTeams":[],"slackApps":[],"feishuRegistrations":[],"disk":{"freeBytes":60377313280,"totalBytes":245107195904},"logins":[],"machineLogins":[{"runtime":"claude","installed":true,"loggedIn":false,"usable":false,"text":"无法读取 Claude Code 的登录信息","offered":false},{"runtime":"codex","installed":true,"loggedIn":false,"usable":false,"text":"Codex 未登录","offered":false}],"sharing":true,"consoleSignIn":true,"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"google","name":"Google Gemini","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xai","name":"xAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"mistral","name":"Mistral","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"deepseek","name":"DeepSeek","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen","name":"Qwen","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai","name":"Kimi","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai","name":"Z.ai","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax","name":"MiniMax","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ant-ling","name":"Ant Ling","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"jev","name":"Jev","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen-cn","name":"Qwen (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"openrouter","name":"OpenRouter","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"opencode","name":"OpenCode Zen","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"groq","name":"Groq","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"together","name":"Together AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"fireworks","name":"Fireworks","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cerebras","name":"Cerebras","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"huggingface","name":"Hugging Face","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"nvidia","name":"NVIDIA","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"baseten","name":"Baseten","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ollama","name":"Ollama","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"custom","name":"Custom","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""}],"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792531037523},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.305","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792531037523},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792531037523},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792531037523},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","latest":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792531037523}],"processesText":"没有运行中的 agent 进程","agentEnv":[],"drive":{"roots":[{"path":"/tmp/mbe2e-C/home/e2e-105609","name":"e2e-105609","state":"ok"}],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false}},"betaOffered":false,"host":{"hostname":"3720-Mac-mini-1","os":"macOS 27.0.1","arch":"arm64","cpus":10,"cpuModel":"Apple M4","load":0.45,"cpuBusy":0.08,"uptimeSec":10405,"memory":{"totalBytes":17179869184,"usedBytes":9595355136,"swapUsedBytes":341961605},"disk":{"path":"/tmp/mbe2e-C/data","totalBytes":245107195904,"freeBytes":60434341888},"emberRssBytes":157709992,"checkedAt":1792531043874,"summary":"10 核 · 16 GB","line":"macOS 27.0.1 · 10 核 · 16 GB · 已运行 0 天","facts":["3720-Mac-mini-1","macOS 27.0.1","arm64 · 10 核","已运行 2 小时"],"meters":[{"label":"CPU","short":"CPU","percent":8,"left":92,"level":"ok","value":"8%","remaining":"空闲 92%","big":"92","unit":"%","title":"CPU 空闲","total":"负载 4.5","note":"负载 4.5 · Apple M4"},{"label":"内存","short":"内存","percent":56,"left":44,"level":"ok","value":"8.9 GB / 16.0 GB","remaining":"剩 7.1 G","big":"7.1","unit":"GB","title":"内存剩","total":"共 16 GB","note":"swap 0.3 GB"},{"label":"磁盘","short":"磁盘","percent":75,"left":25,"level":"amber","value":"剩余 56.3 GB / 228 GB","remaining":"剩 56.3 G","big":"56.3","unit":"GB","title":"磁盘剩","total":"共 228 GB"}],"identity":"Apple M4 · 16 GB · macOS 27.0.1","details":[{"label":"主机名","value":"3720-Mac-mini-1"},{"label":"芯片","value":"Apple M4 · 10 核 · arm64"},{"label":"已运行","value":"2 小时"},{"label":"still.fail","value":"进程占用 150 MB"}],"usage":"内存 8.9 GB / 16.0 GB · 磁盘 剩余 56.3 GB / 228 GB","emberText":"still.fail 150 MB"},"way":{"path":"直连","via":"direct"},"time":{"lastSeen":{"at":1792531039000,"ago":"刚刚","full":"10/21 05:17:19","until":"1 分钟内","past":true}},"joined":false}]},"w":1792531060194.279}
  #|{"in":{"id":11,"value":{"items":[]}},"w":1792531060194.368}
  #|{"in":{"id":12,"ok":null},"w":1792531060194.371}
  #|{"in":{"id":13,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792531060194.377}
  #|{"in":{"id":14,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792531060194.382}
  #|{"out":{"id":15,"subscribe":{"topic":"longJobs","scope":"01M5DJSXYHSNZV6N1ZJRSKAKGM"},"keyed":true},"w":1792531060194.422}
  #|{"out":{"id":16,"call":"notify.permission","params":{"state":"unknown"}},"w":1792531060196.538}
  #|{"in":{"id":9,"delta":[{"path":[0,"overview","disk","freeBytes"],"set":60377300992}]},"w":1792531060210.739}
  #|{"in":{"id":15,"value":{"groups":[]}},"w":1792531060210.756}
  #|{"in":{"id":16,"ok":null},"w":1792531060210.762}
  #|{"step":"#before drive-big 105609","w":1792531060211.099}
  #|{"step":"#env MBUI_OPEN_PAGE=files","w":1792531060211.101}
  #|{"step":"answered notify.permission","w":1792531060211.111}
  #|{"step":"rest","w":1792531060228.326}
  #|{"in":{"id":9,"delta":[{"path":[0,"host","checkedAt"],"set":1792531060221},{"path":[0,"host","details",3,"value"],"set":"进程占用 129 MB"},{"path":[0,"host","disk","freeBytes"],"set":60376227840},{"path":[0,"host","emberRssBytes"],"set":135574824},{"path":[0,"host","emberText"],"set":"still.fail 129 MB"},{"path":[0,"host","load"],"set":0.38},{"path":[0,"host","memory","usedBytes"],"set":9478455296},{"path":[0,"host","meters",0,"note"],"set":"负载 3.8 · Apple M4"},{"path":[0,"host","meters",0,"total"],"set":"负载 3.8"},{"path":[0,"host","meters",1,"big"],"set":"7.2"},{"path":[0,"host","meters",1,"left"],"set":45},{"path":[0,"host","meters",1,"percent"],"set":55},{"path":[0,"host","meters",1,"remaining"],"set":"剩 7.2 G"},{"path":[0,"host","meters",1,"value"],"set":"8.8 GB / 16.0 GB"},{"path":[0,"host","meters",2,"big"],"set":"56.2"},{"path":[0,"host","meters",2,"remaining"],"set":"剩 56.2 G"},{"path":[0,"host","meters",2,"value"],"set":"剩余 56.2 GB / 228 GB"},{"path":[0,"host","uptimeSec"],"set":10422},{"path":[0,"host","usage"],"set":"内存 8.8 GB / 16.0 GB · 磁盘 剩余 56.2 GB / 228 GB"}]},"w":1792531060260.758}
  #|{"step":"now tap =e2e-105609","w":1792531061344.598}
  #|{"step":"now tap =e2e-105609","acted":true,"w":1792531061361.47}
  #|{"out":{"id":17,"subscribe":{"topic":"drive","station":"01M5DJSXYHSNZV6N1ZJRSKAKGM/584cb8e0c9c046dcf0fcddfe90a3f9cda0b4c94f9deef69edc45390bc9681141","root":"/tmp/mbe2e-C/home/e2e-105609","path":""},"keyed":true},"w":1792531061377.95}
  #|{"step":"rest","w":1792531061383.933}
  #|{"in":{"id":17,"value":{"path":"","entries":[{"name":"子文件夹","dir":true,"size":0,"mtime":1792531040653,"type":"","kind":"folder","sizeText":"","timeText":"05:17"},{"name":"小说-e2e.txt","dir":false,"size":36779,"mtime":1792531040667,"type":"text/plain; charset=utf-8","kind":"text","sizeText":"36 KB","timeText":"05:17"},{"name":"说明.txt","dir":false,"size":43,"mtime":1792531040653,"type":"text/plain; charset=utf-8","kind":"text","sizeText":"43 B","timeText":"05:17"}],"truncated":false,"folders":1,"files":2,"countText":"1 个文件夹 · 2 个文件"}},"w":1792531061394.134}
  #|{"out":{"id":18,"subscribe":{"topic":"drivePlace","station":"01M5DJSXYHSNZV6N1ZJRSKAKGM/584cb8e0c9c046dcf0fcddfe90a3f9cda0b4c94f9deef69edc45390bc9681141","root":"/tmp/mbe2e-C/home/e2e-105609","path":"小说-e2e.txt"},"keyed":true},"w":1792531061398.072}
  #|{"out":{"id":19,"subscribe":{"topic":"drivePlace","station":"01M5DJSXYHSNZV6N1ZJRSKAKGM/584cb8e0c9c046dcf0fcddfe90a3f9cda0b4c94f9deef69edc45390bc9681141","root":"/tmp/mbe2e-C/home/e2e-105609","path":"说明.txt"},"keyed":true},"w":1792531061398.894}
  #|{"in":{"id":17,"value":{"path":"","entries":[{"name":"大文件","dir":true,"size":0,"mtime":1792531059963,"type":"","kind":"folder","sizeText":"","timeText":"05:17"},{"name":"子文件夹","dir":true,"size":0,"mtime":1792531040653,"type":"","kind":"folder","sizeText":"","timeText":"05:17"},{"name":"小说-e2e.txt","dir":false,"size":36779,"mtime":1792531040667,"type":"text/plain; charset=utf-8","kind":"text","sizeText":"36 KB","timeText":"05:17"},{"name":"说明.txt","dir":false,"size":43,"mtime":1792531040653,"type":"text/plain; charset=utf-8","kind":"text","sizeText":"43 B","timeText":"05:17"}],"truncated":false,"folders":2,"files":2,"countText":"2 个文件夹 · 2 个文件"}},"w":1792531061410.771}
  #|{"in":{"id":18,"value":null},"w":1792531061410.819}
  #|{"in":{"id":19,"value":null},"w":1792531061410.835}
  #|{"step":"now tap =大文件","w":1792531062494.796}
  #|{"step":"now tap =大文件","acted":true,"w":1792531062511.809}
  #|{"out":{"id":20,"subscribe":{"topic":"drive","station":"01M5DJSXYHSNZV6N1ZJRSKAKGM/584cb8e0c9c046dcf0fcddfe90a3f9cda0b4c94f9deef69edc45390bc9681141","root":"/tmp/mbe2e-C/home/e2e-105609","path":"大文件"},"keyed":true},"w":1792531062528.004}
  #|{"step":"rest","w":1792531062532.269}
  #|{"in":{"id":20,"value":{"path":"大文件","entries":[{"name":"大文件.bin","dir":false,"size":50331648,"mtime":1792531059963,"type":"application/octet-stream","kind":"other","sizeText":"48 MB","timeText":"05:17"},{"name":"附件.txt","dir":false,"size":40,"mtime":1792531059963,"type":"text/plain; charset=utf-8","kind":"text","sizeText":"40 B","timeText":"05:17"}],"truncated":false,"folders":0,"files":2,"countText":"2 个文件"}},"w":1792531062544.131}
  #|{"out":{"id":21,"subscribe":{"topic":"drivePlace","station":"01M5DJSXYHSNZV6N1ZJRSKAKGM/584cb8e0c9c046dcf0fcddfe90a3f9cda0b4c94f9deef69edc45390bc9681141","root":"/tmp/mbe2e-C/home/e2e-105609","path":"大文件/附件.txt"},"keyed":true},"w":1792531062546.833}
  #|{"in":{"id":21,"value":null},"w":1792531062560.773}
  #|{"step":"now hold 800 大文件.bin","w":1792531062861.423}
  #|{"step":"now hold 800 大文件.bin","acted":true,"w":1792531062878.102}
  #|{"step":"until 已选 1 项","w":1792531063711.56}
  #|{"step":"tap 附件.txt","w":1792531063711.626}
  #|{"step":"tap 附件.txt","acted":true,"w":1792531063728.2}
  #|{"step":"until 已选 2 项","w":1792531063744.745}
  #|{"step":"tap icon:more","w":1792531063763.232}
  #|{"step":"tap icon:more","acted":true,"w":1792531063794.806}
  #|{"step":"rest","w":1792531063822.403}
  #|{"step":"now tap 下载 2 个文件","w":1792531065228.296}
  #|{"step":"now tap 下载 2 个文件","acted":true,"w":1792531065245.19}
  #|{"out":{"id":22,"call":"drive.read","params":{"station":"01M5DJSXYHSNZV6N1ZJRSKAKGM/584cb8e0c9c046dcf0fcddfe90a3f9cda0b4c94f9deef69edc45390bc9681141","root":"/tmp/mbe2e-C/home/e2e-105609","path":"大文件/大文件.bin","offset":0,"length":4194304}},"w":1792531065262.646}
  #|{"out":{"id":23,"call":"drive.read","params":{"station":"01M5DJSXYHSNZV6N1ZJRSKAKGM/584cb8e0c9c046dcf0fcddfe90a3f9cda0b4c94f9deef69edc45390bc9681141","root":"/tmp/mbe2e-C/home/e2e-105609","path":"大文件/附件.txt","offset":0,"length":4194304}},"w":1792531065263.495}
  #|{"step":"answered drive.read","w":1792531065265.266}
  #|{"in":{"id":23,"ok":{"type":"text/plain; charset=utf-8","total":40,"mtime":1792531059963}},"w":1792531065277.418,"b":"e5928ce5a4a7e69687e4bbb6e4b880e8b5b7e4b88be8bdbde79a84e5b08fe69687e4bbb6e380820a"}
  #|{"step":"answered drive.read","w":1792531065294.736}
  #|{"in":{"id":22,"ok":{"type":"application/octet-stream","total":50331648,"mtime":1792531059963}},"w":1792531065327.706,"bn":4194304}
  #|{"out":{"id":24,"call":"drive.read","params":{"station":"01M5DJSXYHSNZV6N1ZJRSKAKGM/584cb8e0c9c046dcf0fcddfe90a3f9cda0b4c94f9deef69edc45390bc9681141","root":"/tmp/mbe2e-C/home/e2e-105609","path":"大文件/大文件.bin","offset":4194304,"length":4194304}},"w":1792531065328.02}
  #|{"step":"answered drive.read","w":1792531065344.305}
  #|{"in":{"id":24,"ok":{"type":"application/octet-stream","total":50331648,"mtime":1792531059963}},"w":1792531065377.497,"bn":4194304}
  #|{"out":{"id":25,"call":"drive.read","params":{"station":"01M5DJSXYHSNZV6N1ZJRSKAKGM/584cb8e0c9c046dcf0fcddfe90a3f9cda0b4c94f9deef69edc45390bc9681141","root":"/tmp/mbe2e-C/home/e2e-105609","path":"大文件/大文件.bin","offset":8388608,"length":4194304}},"w":1792531065377.814}
  #|{"step":"answered drive.read","w":1792531065394.36}
  #|{"in":{"id":25,"ok":{"type":"application/octet-stream","total":50331648,"mtime":1792531059963}},"w":1792531065427.534,"bn":4194304}
  #|{"out":{"id":26,"call":"drive.read","params":{"station":"01M5DJSXYHSNZV6N1ZJRSKAKGM/584cb8e0c9c046dcf0fcddfe90a3f9cda0b4c94f9deef69edc45390bc9681141","root":"/tmp/mbe2e-C/home/e2e-105609","path":"大文件/大文件.bin","offset":12582912,"length":4194304}},"w":1792531065428.367}
  #|{"step":"answered drive.read","w":1792531065444.347}
  #|{"in":{"id":26,"ok":{"type":"application/octet-stream","total":50331648,"mtime":1792531059963}},"w":1792531065477.693,"bn":4194304}
  #|{"out":{"id":27,"call":"drive.read","params":{"station":"01M5DJSXYHSNZV6N1ZJRSKAKGM/584cb8e0c9c046dcf0fcddfe90a3f9cda0b4c94f9deef69edc45390bc9681141","root":"/tmp/mbe2e-C/home/e2e-105609","path":"大文件/大文件.bin","offset":16777216,"length":4194304}},"w":1792531065478.013}
  #|{"step":"answered drive.read","w":1792531065494.531}
  #|{"in":{"id":27,"ok":{"type":"application/octet-stream","total":50331648,"mtime":1792531059963}},"w":1792531065527.678,"bn":4194304}
  #|{"out":{"id":28,"call":"drive.read","params":{"station":"01M5DJSXYHSNZV6N1ZJRSKAKGM/584cb8e0c9c046dcf0fcddfe90a3f9cda0b4c94f9deef69edc45390bc9681141","root":"/tmp/mbe2e-C/home/e2e-105609","path":"大文件/大文件.bin","offset":20971520,"length":4194304}},"w":1792531065528.46}
  #|{"step":"answered drive.read","w":1792531065544.324}
  #|{"in":{"id":28,"ok":{"type":"application/octet-stream","total":50331648,"mtime":1792531059963}},"w":1792531065577.694,"bn":4194304}
  #|{"out":{"id":29,"call":"drive.read","params":{"station":"01M5DJSXYHSNZV6N1ZJRSKAKGM/584cb8e0c9c046dcf0fcddfe90a3f9cda0b4c94f9deef69edc45390bc9681141","root":"/tmp/mbe2e-C/home/e2e-105609","path":"大文件/大文件.bin","offset":25165824,"length":4194304}},"w":1792531065578.035}
  #|{"step":"answered drive.read","w":1792531065594.351}
  #|{"in":{"id":29,"ok":{"type":"application/octet-stream","total":50331648,"mtime":1792531059963}},"w":1792531065627.561,"bn":4194304}
  #|{"out":{"id":30,"call":"drive.read","params":{"station":"01M5DJSXYHSNZV6N1ZJRSKAKGM/584cb8e0c9c046dcf0fcddfe90a3f9cda0b4c94f9deef69edc45390bc9681141","root":"/tmp/mbe2e-C/home/e2e-105609","path":"大文件/大文件.bin","offset":29360128,"length":4194304}},"w":1792531065628.331}
  #|{"step":"answered drive.read","w":1792531065644.27}
  #|{"in":{"id":30,"ok":{"type":"application/octet-stream","total":50331648,"mtime":1792531059963}},"w":1792531065677.658,"bn":4194304}
  #|{"out":{"id":31,"call":"drive.read","params":{"station":"01M5DJSXYHSNZV6N1ZJRSKAKGM/584cb8e0c9c046dcf0fcddfe90a3f9cda0b4c94f9deef69edc45390bc9681141","root":"/tmp/mbe2e-C/home/e2e-105609","path":"大文件/大文件.bin","offset":33554432,"length":4194304}},"w":1792531065677.986}
  #|{"step":"answered drive.read","w":1792531065694.351}
  #|{"in":{"id":31,"ok":{"type":"application/octet-stream","total":50331648,"mtime":1792531059963}},"w":1792531065727.691,"bn":4194304}
  #|{"out":{"id":32,"call":"drive.read","params":{"station":"01M5DJSXYHSNZV6N1ZJRSKAKGM/584cb8e0c9c046dcf0fcddfe90a3f9cda0b4c94f9deef69edc45390bc9681141","root":"/tmp/mbe2e-C/home/e2e-105609","path":"大文件/大文件.bin","offset":37748736,"length":4194304}},"w":1792531065728.48}
  #|{"step":"answered drive.read","w":1792531065744.328}
  #|{"in":{"id":32,"ok":{"type":"application/octet-stream","total":50331648,"mtime":1792531059963}},"w":1792531065777.691,"bn":4194304}
  #|{"out":{"id":33,"call":"drive.read","params":{"station":"01M5DJSXYHSNZV6N1ZJRSKAKGM/584cb8e0c9c046dcf0fcddfe90a3f9cda0b4c94f9deef69edc45390bc9681141","root":"/tmp/mbe2e-C/home/e2e-105609","path":"大文件/大文件.bin","offset":41943040,"length":4194304}},"w":1792531065778.04}
  #|{"step":"answered drive.read","w":1792531065794.277}
  #|{"in":{"id":33,"ok":{"type":"application/octet-stream","total":50331648,"mtime":1792531059963}},"w":1792531065827.694,"bn":4194304}
  #|{"out":{"id":34,"call":"drive.read","params":{"station":"01M5DJSXYHSNZV6N1ZJRSKAKGM/584cb8e0c9c046dcf0fcddfe90a3f9cda0b4c94f9deef69edc45390bc9681141","root":"/tmp/mbe2e-C/home/e2e-105609","path":"大文件/大文件.bin","offset":46137344,"length":4194304}},"w":1792531065828.469}
  #|{"step":"answered drive.read","w":1792531065844.278}
  #|{"in":{"id":34,"ok":{"type":"application/octet-stream","total":50331648,"mtime":1792531059963}},"w":1792531065877.708,"bn":4194304}
  #|{"step":"rest","w":1792531065894.222}
  #|{"step":"now gone %","w":1792531066694.666}
  #|{"step":"until 已保存到「下载」","w":1792531066694.72}
  #|{"step":"wait 2600","w":1792531066694.749}
  #|{"step":"wait 16","w":1792531069361.46}
  #|{"step":"now rest","w":1792531069528.068}
  #|{"step":"","w":1792531069544.715}
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
  #|{"textrec":{"s":[16,400,0,"端到端测试的对话 post:你好，我是测试用的 agent"],"r":[0,1,15.875486381322958,30,1,1,15.875486381322958,31,2,1,15.875486381322958,30,3,1,15.875486381322958,32,4,1,15.875486381322958,33,5,1,15.875486381322958,34,6,1,15.875486381322958,35,7,1,15.875486381322958,36,8,1,4.1875,-1,9,1,9.453125,37,10,1,9.140625,38,11,1,8.0234375,39,12,1,5.4609375,40,13,1,4.4375,41,14,1,15.875486381322958,42,15,1,15.875486381322958,43,16,1,16.09338521400778,44,17,1,15.875486381322958,45,18,1,15.875486381322958,46,19,1,15.87548638132293,32,20,1,15.875486381322958,33,21,1,15.875486381322958,47,22,1,15.875486381322958,34,23,1,4.1875,-1,24,1,8.515625,48,25,1,9.4375,49,26,1,8.828125,50,27,1,9.0234375,51,28,1,5.5,40]}}
  #|{"textrec":{"m":[16,400,0],"r":[15.46875,3.375,23]}}
  #|{"textrec":{"s":[14,400,0,"出错：意外停止"],"r":[0,1,13.891050583657588,52,1,1,13.891050583657588,53,2,1,14.081712062256813,54,3,1,13.891050583657588,55,4,1,13.891050583657588,56,5,1,13.891050583657588,57,6,1,13.891050583657588,58]}}
  #|{"textrec":{"m":[14,400,0],"r":[13.53515625,2.953125,20]}}
  #|{"textrec":{"s":[16,400,0,"…"],"r":[0,1,12.5625,59]}}
  #|{"textrec":{"s":[16,400,0,"端到端测试的对话 post:你好，我是测试用的…"],"r":[0,1,15.875486381322958,30,1,1,15.875486381322958,31,2,1,15.875486381322958,30,3,1,15.875486381322958,32,4,1,15.875486381322958,33,5,1,15.875486381322958,34,6,1,15.875486381322958,35,7,1,15.875486381322958,36,8,1,4.1875,-1,9,1,9.453125,37,10,1,9.140625,38,11,1,8.0234375,39,12,1,5.4609375,40,13,1,4.4375,41,14,1,15.875486381322958,42,15,1,15.875486381322958,43,16,1,16.09338521400778,44,17,1,15.875486381322958,45,18,1,15.875486381322958,46,19,1,15.87548638132293,32,20,1,15.875486381322958,33,21,1,15.875486381322958,47,22,1,15.875486381322958,34,23,1,12.5625,59]}}
  #|{"textrec":{"s":[15,600,0,"studio"],"r":[0,1,8.000344634056091,60,1,1,5.658300518989563,61,2,1,8.93320620059967,62,3,1,9.332013130187988,63,4,1,3.8520312309265137,64,5,1,8.901597261428833,65]}}
  #|{"textrec":{"s":[16,400,0,"主目录"],"r":[0,1,15.875486381322958,66,1,1,15.875486381322958,67,2,1,15.875486381322958,68]}}
  #|{"textrec":{"s":[16,400,0,"e2e-105609"],"r":[0,1,8.828125,50,1,1,9.3046875,69,2,1,8.7890625,50,3,1,7.234375,70,4,1,7.109375,71,5,1,9.765625,72,6,1,9.578125,73,7,1,9.875,74,8,1,9.765625,72,9,1,9.875,75]}}
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
  #|{"textrec":{"g":37,"r":[317,0,10,14,0,-10,0]}}
  #|{"textrec":{"g":38,"r":[328,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":39,"r":[340,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":40,"r":[351,0,8,14,-1,-12,0]}}
  #|{"textrec":{"g":41,"r":[360,0,5,11,0,-9,0]}}
  #|{"textrec":{"g":42,"r":[366,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":43,"r":[384,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":44,"r":[402,0,6,7,0,-3,0]}}
  #|{"textrec":{"g":45,"r":[409,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":46,"r":[427,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":47,"r":[445,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":59,"r":[462,0,13,5,0,-3,0]}}
  #|{"textrec":{"g":52,"r":[476,0,14,16,0,-13,0]}}
  #|{"textrec":{"g":53,"r":[491,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":54,"r":[508,0,5,10,1,-10,0]}}
  #|{"textrec":{"g":55,"r":[514,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":56,"r":[531,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":57,"r":[548,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":58,"r":[564,0,15,15,-1,-13,0]}}
  #|{"textrec":{"ib":["33d1dfbf90932d3b",1241,64],"r":[17,17,17,17]}}
  #|{"textrec":{"ib":["182b7158e0c0cae1",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["d61ec6305f7d8c8b",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["a1e7be43eb966606",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"g":60,"r":[580,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":61,"r":[591,0,8,13,-1,-11,0]}}
  #|{"textrec":{"g":62,"r":[600,0,10,12,0,-10,0]}}
  #|{"textrec":{"g":63,"r":[611,0,11,15,-1,-13,0]}}
  #|{"textrec":{"g":64,"r":[623,0,6,14,-1,-13,0]}}
  #|{"textrec":{"g":65,"r":[630,0,11,12,-1,-10,0]}}
  #|{"textrec":{"ib":["7d024a54eca23c07",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"ib":["4165e1c325ff4b32",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"g":20,"r":[642,0,18,18,-1,-15,0]}}
  #|{"textrec":{"g":21,"r":[661,0,19,18,-1,-15,0]}}
  #|{"textrec":{"g":66,"r":[681,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":67,"r":[699,0,14,16,1,-13,0]}}
  #|{"textrec":{"g":68,"r":[714,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":50,"r":[732,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":69,"r":[744,0,10,14,0,-13,0]}}
  #|{"textrec":{"g":70,"r":[755,0,8,5,0,-7,0]}}
  #|{"textrec":{"g":71,"r":[764,0,7,14,0,-13,0]}}
  #|{"textrec":{"g":72,"r":[772,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":73,"r":[784,0,10,15,0,-13,0]}}
  #|{"textrec":{"g":74,"r":[795,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":75,"r":[807,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":18,"r":[819,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":19,"r":[838,0,17,17,-1,-14,0]}}
  #|{"textrec":{"ib":["2bb63fc1d380f765",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"s":[17,400,0,"设置"],"r":[0,1,16.851167315175097,76,1,1,16.851167315175097,77]}}
  #|{"textrec":{"s":[16,600,0,"e2e-105609"],"r":[0,1,9.127458572387695,78,1,1,9.717817306518555,79,2,1,9.100765228271484,78,3,1,7.363014221191406,80,4,1,7.594245910644531,81,5,1,10.31976318359375,82,6,1,10.035783767700195,83,7,1,10.3499755859375,84,8,1,10.31976318359375,82,9,1,10.3499755859375,85]}}
  #|{"textrec":{"s":[17,400,0,"文件"],"r":[0,1,16.851167315175097,86,1,1,16.851167315175097,87]}}
  #|{"textrec":{"g":76,"r":[856,0,19,18,-1,-15,0]}}
  #|{"textrec":{"g":77,"r":[876,0,18,17,-1,-14,0]}}
  #|{"textrec":{"s":[13,400,0,"1 个文件夹 · 2 个文件"],"r":[0,1,5.9541015625,88,1,1,3.580078125,-1,2,1,12.898832684824903,89,3,1,12.898832684824903,90,4,1,12.898832684824903,91,5,1,12.898832684824903,92,6,1,3.580078125,-1,7,1,6.228545204222115,93,8,1,3.580078125,-1,9,1,7.76953125,94,10,1,3.580078125,-1,11,1,12.898832684824896,89,12,1,12.898832684824896,90,13,1,12.898832684824896,91]}}
  #|{"textrec":{"s":[15,400,0,"子文件夹"],"r":[0,1,14.883268482490273,95,1,1,14.883268482490273,96,2,1,14.883268482490273,97,3,1,14.883268482490273,98]}}
  #|{"textrec":{"s":[12,400,0,"05:17"],"r":[0,1,7.55859375,99,1,1,7.41796875,100,2,1,3.5625,101,3,1,5.56640625,102,4,1,6.83203125,103]}}
  #|{"textrec":{"m":[12,400,0],"r":[11.6015625,2.53125,17]}}
  #|{"textrec":{"s":[15,400,0,"小说-e2e.txt"],"r":[0,1,14.883268482490273,104,1,1,14.883268482490273,105,2,1,6.8408203125,106,3,1,8.3349609375,107,4,1,8.78173828125,108,5,1,8.29833984375,107,6,1,4.072265625,109,7,1,5.068359375,110,8,1,7.6318359375,111,9,1,5.21484375,110]}}
  #|{"textrec":{"s":[12,400,0,"36 KB · 05:17"],"r":[0,1,7.5234375,112,1,1,7.640625,113,2,1,3.375,-1,3,1,7.904296875,114,4,1,7.88671875,115,5,1,3.375,-1,6,1,5.754933455713626,116,7,1,3.375,-1,8,1,7.55859375,99,9,1,7.41796875,100,10,1,3.5625,101,11,1,5.56640625,102,12,1,6.83203125,103]}}
  #|{"textrec":{"s":[15,400,0,"说明.txt"],"r":[0,1,14.883268482490273,105,1,1,14.883268482490273,117,2,1,4.072265625,109,3,1,5.068359375,110,4,1,7.6318359375,111,5,1,5.21484375,110]}}
  #|{"textrec":{"s":[12,400,0,"43 B · 05:17"],"r":[0,1,7.72265625,118,1,1,7.5234375,112,2,1,3.375,-1,3,1,7.88671875,115,4,1,3.375,-1,5,1,5.754933455713626,116,6,1,3.375,-1,7,1,7.55859375,99,8,1,7.41796875,100,9,1,3.5625,101,10,1,5.56640625,102,11,1,6.83203125,103]}}
  #|{"textrec":{"s":[13,400,0,"2 个文件夹 · 2 个文件"],"r":[0,1,7.76953125,94,1,1,3.580078125,-1,2,1,12.898832684824903,89,3,1,12.898832684824903,90,4,1,12.898832684824903,91,5,1,12.898832684824903,92,6,1,3.580078125,-1,7,1,6.228545204222115,93,8,1,3.580078125,-1,9,1,7.76953125,94,10,1,3.580078125,-1,11,1,12.898832684824896,89,12,1,12.898832684824896,90,13,1,12.898832684824896,91]}}
  #|{"textrec":{"s":[15,400,0,"大文件"],"r":[0,1,14.883268482490273,119,1,1,14.883268482490273,96,2,1,14.883268482490273,97]}}
  #|{"textrec":{"g":86,"r":[895,0,18,18,-1,-15,0]}}
  #|{"textrec":{"g":87,"r":[914,0,18,18,-1,-15,0]}}
  #|{"textrec":{"g":94,"r":[933,0,9,12,-1,-11,0]}}
  #|{"textrec":{"g":89,"r":[943,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":90,"r":[959,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":91,"r":[975,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":92,"r":[991,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":93,"r":[1007,0,4,5,1,-7,0]}}
  #|{"textrec":{"ib":["275a1f2a0cb12622",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"ib":["b17c2fa67cbec771",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"g":119,"r":[1012,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":96,"r":[1029,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":97,"r":[1047,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":99,"r":[1064,0,9,12,-1,-10,0]}}
  #|{"textrec":{"g":100,"r":[1074,0,9,12,-1,-10,0]}}
  #|{"textrec":{"g":101,"r":[1084,0,4,9,0,-7,0]}}
  #|{"textrec":{"g":102,"r":[1089,0,7,11,-1,-10,0]}}
  #|{"textrec":{"g":103,"r":[1097,0,9,11,-1,-10,0]}}
  #|{"textrec":{"g":95,"r":[1107,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":98,"r":[1124,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":104,"r":[1141,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":105,"r":[1159,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":106,"r":[1177,0,7,4,0,-6,0]}}
  #|{"textrec":{"g":107,"r":[1185,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":108,"r":[1196,0,10,13,0,-12,0]}}
  #|{"textrec":{"g":109,"r":[1207,0,5,5,0,-3,0]}}
  #|{"textrec":{"g":110,"r":[1213,0,7,13,-1,-11,0]}}
  #|{"textrec":{"g":111,"r":[1221,0,10,10,-1,-9,0]}}
  #|{"textrec":{"g":112,"r":[1232,0,9,12,-1,-10,0]}}
  #|{"textrec":{"g":113,"r":[1242,0,9,12,-1,-10,0]}}
  #|{"textrec":{"g":114,"r":[1252,0,9,11,0,-10,0]}}
  #|{"textrec":{"g":115,"r":[1262,0,9,11,0,-10,0]}}
  #|{"textrec":{"g":116,"r":[1272,0,5,5,0,-7,0]}}
  #|{"textrec":{"g":117,"r":[1278,0,15,16,0,-13,0]}}
  #|{"textrec":{"g":118,"r":[1294,0,10,11,-1,-10,0]}}
  #|{"textrec":{"g":78,"r":[1305,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":79,"r":[1317,0,11,14,0,-13,0]}}
  #|{"textrec":{"g":80,"r":[1329,0,8,5,0,-7,0]}}
  #|{"textrec":{"g":81,"r":[1338,0,7,14,0,-13,0]}}
  #|{"textrec":{"g":82,"r":[1346,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":83,"r":[1358,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":84,"r":[1370,0,12,15,-1,-13,0]}}
  #|{"textrec":{"g":85,"r":[1383,0,12,15,-1,-13,0]}}
  #|{"textrec":{"ib":["0e910fb4d25445a3",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"ib":["b3685975cd23abc3",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["ddfdc2820df8a676",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"s":[16,600,0,"大文件"],"r":[0,1,15.875486381322958,120,1,1,15.875486381322958,18,2,1,15.875486381322958,19]}}
  #|{"textrec":{"s":[17,400,0,"e2e-105609"],"r":[0,1,9.2802734375,121,1,1,9.78662109375,122,2,1,9.23876953125,121,3,1,7.5869140625,123,4,1,7.4541015625,124,5,1,10.2763671875,125,6,1,10.0771484375,126,7,1,10.392578125,127,8,1,10.2763671875,125,9,1,10.392578125,128]}}
  #|{"textrec":{"s":[17,400,0,"…"],"r":[0,1,13.248046875,129]}}
  #|{"textrec":{"s":[17,400,0,"e2e-105…"],"r":[0,1,9.2802734375,121,1,1,9.78662109375,122,2,1,9.23876953125,121,3,1,7.5869140625,123,4,1,7.4541015625,124,5,1,10.2763671875,125,6,1,9.78662109375,126,7,1,12.95751953125,130]}}
  #|{"textrec":{"s":[13,400,0,"e2e-105609"],"r":[0,1,7.3505859375,14,1,1,7.73779296875,94,2,1,7.31884765625,14,3,1,6.0556640625,131,4,1,5.9541015625,88,5,1,8.1123046875,132,6,1,7.9599609375,133,7,1,8.201171875,134,8,1,8.1123046875,132,9,1,8.201171875,135]}}
  #|{"textrec":{"s":[13,600,0,"大文件"],"r":[0,1,12.898832684824903,136,1,1,12.898832684824903,137,2,1,12.898832684824903,138]}}
  #|{"textrec":{"m":[13,600,0],"r":[12.568359375,2.7421875,18]}}
  #|{"textrec":{"s":[13,400,0,"2 个文件"],"r":[0,1,7.76953125,94,1,1,3.580078125,-1,2,1,12.898832684824903,89,3,1,12.898832684824903,90,4,1,12.898832684824903,91]}}
  #|{"textrec":{"s":[15,400,0,"大文件.bin"],"r":[0,1,14.883268482490273,119,1,1,14.883268482490273,96,2,1,14.883268482490273,97,3,1,4.21875,109,4,1,8.9794921875,139,5,1,3.4716796875,140,6,1,8.518066406249993,141]}}
  #|{"textrec":{"s":[12,400,0,"48 MB · 05:17"],"r":[0,1,7.72265625,118,1,1,7.6640625,142,2,1,3.375,-1,3,1,10.48828125,143,4,1,7.88671875,115,5,1,3.375,-1,6,1,5.754933455713626,116,7,1,3.375,-1,8,1,7.55859375,99,9,1,7.41796875,100,10,1,3.5625,101,11,1,5.56640625,102,12,1,6.83203125,103]}}
  #|{"textrec":{"s":[15,400,0,"附件.txt"],"r":[0,1,14.883268482490273,144,1,1,14.883268482490273,97,2,1,4.072265625,109,3,1,5.068359375,110,4,1,7.6318359375,111,5,1,5.21484375,110]}}
  #|{"textrec":{"s":[12,400,0,"40 B · 05:17"],"r":[0,1,7.72265625,118,1,1,7.55859375,99,2,1,3.375,-1,3,1,7.88671875,115,4,1,3.375,-1,5,1,5.754933455713626,116,6,1,3.375,-1,7,1,7.55859375,99,8,1,7.41796875,100,9,1,3.5625,101,10,1,5.56640625,102,11,1,6.83203125,103]}}
  #|{"textrec":{"g":121,"r":[1396,0,11,13,-1,-11,0]}}
  #|{"textrec":{"g":122,"r":[1408,0,11,15,0,-14,0]}}
  #|{"textrec":{"g":123,"r":[1420,0,8,4,0,-7,0]}}
  #|{"textrec":{"g":124,"r":[1429,0,7,14,0,-13,0]}}
  #|{"textrec":{"g":125,"r":[1437,0,11,16,0,-14,0]}}
  #|{"textrec":{"g":126,"r":[1449,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":130,"r":[1461,0,14,6,-0.29052734375,-4,0]}}
  #|{"textrec":{"g":14,"r":[1476,0,9,10,-1,-8,0]}}
  #|{"textrec":{"g":131,"r":[1486,0,8,4,-1,-6,0]}}
  #|{"textrec":{"g":88,"r":[1495,0,7,12,-1,-11,0]}}
  #|{"textrec":{"g":132,"r":[1503,0,10,13,-1,-11,0]}}
  #|{"textrec":{"g":133,"r":[1514,0,10,13,-1,-11,0]}}
  #|{"textrec":{"g":134,"r":[1525,0,10,13,-1,-11,0]}}
  #|{"textrec":{"g":135,"r":[1536,0,10,13,-1,-11,0]}}
  #|{"textrec":{"ib":["6e1c0e81435b9033",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"g":139,"r":[1547,0,10,15,0,-13,0]}}
  #|{"textrec":{"g":140,"r":[1558,0,5,14,-1,-13,0]}}
  #|{"textrec":{"g":141,"r":[1564,0,9,11,0,-10,0]}}
  #|{"textrec":{"g":142,"r":[1574,0,9,12,-1,-10,0]}}
  #|{"textrec":{"g":143,"r":[1584,0,11,11,0,-10,0]}}
  #|{"textrec":{"g":144,"r":[1596,0,15,17,0,-14,0]}}
  #|{"textrec":{"g":136,"r":[1612,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":137,"r":[1628,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":138,"r":[1644,0,15,15,-1,-12,0]}}
  #|{"textrec":{"ib":["c63576325cefdb0c",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"g":120,"r":[1660,0,18,17,-1,-14,0]}}
  #|{"textrec":{"s":[16,600,0,"已选 1 项"],"r":[0,1,15.875486381322958,145,1,1,15.875486381322958,146,2,1,3.95001220703125,-1,3,1,7.594245910644531,81,4,1,3.95001220703125,-1,5,1,15.875486381322958,147]}}
  #|{"textrec":{"s":[17,400,0,"取消"],"r":[0,1,16.851167315175097,148,1,1,16.851167315175097,149]}}
  #|{"textrec":{"s":[15,400,0,"全选"],"r":[0,1,14.883268482490273,24,1,1,14.883268482490273,150]}}
  #|{"textrec":{"g":145,"r":[1679,0,16,17,0,-14,0]}}
  #|{"textrec":{"g":146,"r":[1696,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":147,"r":[1714,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":148,"r":[1733,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":149,"r":[1752,0,18,18,-1,-15,0]}}
  #|{"textrec":{"g":150,"r":[1771,0,16,16,-1,-13,0]}}
  #|{"textrec":{"ib":["d2e044956ae472e7",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"s":[16,600,0,"已选 2 项"],"r":[0,1,15.875486381322958,145,1,1,15.875486381322958,146,2,1,3.95001220703125,-1,3,1,9.744510650634766,79,4,1,3.95001220703125,-1,5,1,15.875486381322958,147]}}
  #|{"textrec":{"s":[15,400,0,"取消全选"],"r":[0,1,14.883268482490273,151,1,1,14.883268482490273,152,2,1,14.883268482490273,24,3,1,14.883268482490273,150]}}
  #|{"textrec":{"g":151,"r":[1788,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":152,"r":[1806,0,16,16,-1,-13,0]}}
  #|{"textrec":{"s":[17,700,0,"已选 2 项"],"r":[0,1,16.851167315175097,153,1,1,16.851167315175097,154,2,1,3.951171875,-1,3,1,10.50048828125,155,4,1,3.951171875,-1,5,1,16.85116731517509,156]}}
  #|{"textrec":{"m":[17,700,0],"r":[16.435546875,3.5859375,24]}}
  #|{"textrec":{"s":[15,400,0,"下载 2 个文件"],"r":[0,1,14.883268482490273,157,1,1,14.883268482490273,158,2,1,3.984375,-1,3,1,8.818359375,108,4,1,3.984375,-1,5,1,14.883268482490273,159,6,1,14.883268482490273,96,7,1,14.88326848249028,97]}}
  #|{"textrec":{"s":[15,400,0,"复制路径"],"r":[0,1,14.883268482490273,160,1,1,14.883268482490273,161,2,1,14.883268482490273,162,3,1,14.883268482490273,163]}}
  #|{"textrec":{"s":[15,400,0,"删除 2 项"],"r":[0,1,14.883268482490273,164,1,1,14.883268482490273,165,2,1,3.984375,-1,3,1,8.818359375,108,4,1,3.984375,-1,5,1,14.883268482490273,166]}}
  #|{"textrec":{"g":153,"r":[1823,0,17,17,0,-14,0]}}
  #|{"textrec":{"g":154,"r":[1841,0,18,18,-1,-15,0]}}
  #|{"textrec":{"g":155,"r":[1860,0,11,15,0,-14,0]}}
  #|{"textrec":{"g":156,"r":[1872,0,19,18,-1,-15,0]}}
  #|{"textrec":{"g":157,"r":[1892,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":158,"r":[1909,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":159,"r":[1926,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":160,"r":[1944,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":161,"r":[1961,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":162,"r":[1978,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":163,"r":[1996,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":164,"r":[2014,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":165,"r":[2031,0,16,16,0,-13,0]}}
  #|{"textrec":{"g":166,"r":[0,20,17,16,-1,-13,0]}}
  #|{"textrec":{"ib":["5586d6bf44ec35db",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["9a47fa114a34d016",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["0c818ea1c0c4e805",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"s":[11,600,0,"0%"],"r":[0,1,7.374134063720703,167,1,1,11.01141881942749,168]}}
  #|{"textrec":{"m":[11,600,0],"r":[10.634765625,2.3203125,16]}}
  #|{"textrec":{"g":167,"r":[18,20,9,11,-1,-9,0]}}
  #|{"textrec":{"g":168,"r":[28,20,13,11,-1,-9,0]}}
  #|{"textrec":{"s":[14,400,0,"已保存到「下载」"],"r":[0,1,13.891050583657588,169,1,1,13.891050583657588,170,2,1,13.891050583657588,171,3,1,20.891050583657588,172,4,1,5.066147859922182,173,5,1,13.891050583657588,174,6,1,13.891050583657588,175,7,1,7.127107652399474,176]}}
  #|{"textrec":{"g":169,"r":[42,20,14,14,0,-12,0]}}
  #|{"textrec":{"g":170,"r":[57,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":171,"r":[74,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":172,"r":[90,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":173,"r":[106,20,7,12,-1.333333333333333,-13,0]}}
  #|{"textrec":{"g":174,"r":[114,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":175,"r":[130,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":176,"r":[146,20,7,11,-1,-8,0]}}
  #|{"textrec":{"s":[11,600,0,"8%"],"r":[0,1,7.474215269088745,177,1,1,11.01141881942749,168]}}
  #|{"textrec":{"g":177,"r":[154,20,9,11,-1,-9,0]}}
  #|{"textrec":{"s":[11,600,0,"16%"],"r":[0,1,5.500340938568115,178,1,1,7.394905090332031,179,2,1,11.01141881942749,168]}}
  #|{"textrec":{"g":178,"r":[164,20,7,10,-1,-9,0]}}
  #|{"textrec":{"g":179,"r":[172,20,9,11,-1,-9,0]}}
  #|{"textrec":{"s":[11,600,0,"25%"],"r":[0,1,6.978647947311401,180,1,1,7.178898215293884,181,2,1,11.01141881942749,168]}}
  #|{"textrec":{"g":180,"r":[182,20,9,10,-1,-9,0]}}
  #|{"textrec":{"g":181,"r":[192,20,9,11,-1,-9,0]}}
  #|{"textrec":{"s":[11,600,0,"33%"],"r":[0,1,7.253468036651611,182,1,1,7.253468036651611,182,2,1,11.01141881942749,168]}}
  #|{"textrec":{"g":182,"r":[202,20,9,11,-1,-9,0]}}
  #|{"textrec":{"s":[11,600,0,"41%"],"r":[0,1,7.384075045585632,183,1,1,5.43812620639801,178,2,1,11.01141881942749,168]}}
  #|{"textrec":{"g":183,"r":[212,20,9,10,-1,-9,0]}}
  #|{"textrec":{"s":[11,600,0,"50%"],"r":[0,1,7.178898215293884,181,1,1,7.374134063720703,167,2,1,11.01141881942749,168]}}
  #|{"textrec":{"s":[11,600,0,"58%"],"r":[0,1,7.178898215293884,181,1,1,7.474215269088745,177,2,1,11.01141881942749,168]}}
  #|{"textrec":{"s":[11,600,0,"66%"],"r":[0,1,7.394905090332031,179,1,1,7.394905090332031,179,2,1,11.01141881942749,168]}}
  #|{"textrec":{"s":[11,600,0,"75%"],"r":[0,1,6.518346786499023,184,1,1,7.125187277793884,181,2,1,11.01141881942749,168]}}
  #|{"textrec":{"g":184,"r":[222,20,8,10,-1,-9,0]}}
  #|{"textrec":{"s":[11,600,0,"83%"],"r":[0,1,7.474215269088745,177,1,1,7.253468036651611,182,2,1,11.01141881942749,168]}}
  #|{"textrec":{"s":[11,600,0,"91%"],"r":[0,1,7.394905090332031,185,1,1,5.500340938568115,178,2,1,11.01141881942749,168]}}
  #|{"textrec":{"g":185,"r":[231,20,9,11,-1,-9,0]}}
