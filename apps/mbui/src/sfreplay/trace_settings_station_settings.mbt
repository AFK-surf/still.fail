// e2e/traces/settings-station-settings.trace, made by scripts/trace.py from 02-settings_station_settings.log: not edited by hand.

///|
/// What the app and its core said in the run, a line each.
pub let trace_settings_station_settings : String =
  #|{"start":"base"}
  #|{"step":"drive-seed 080726"}
  #|{"env":{"MBUI_CLOUD":"http://127.0.0.1:18900","MBUI_CORE_ACCOUNT":"{\"sub\":\"alice\",\"email\":\"alice@example.test\",\"name\":\"Name of alice\",\"picture\":\"\",\"access\":\"-\",\"refresh\":\"-\",\"accessExpires\":1792537534}"}}
  #|{"out":{"id":1,"call":"client.device","params":{"client":"still.fail mbui","app":"desktop","userAgent":"Macintosh; Mac OS X"}},"w":1792537281758.409}
  #|{"in":{"id":1,"ok":null},"w":1792537281899.892}
  #|{"out":{"id":2,"subscribe":{"topic":"accounts"},"keyed":true},"w":1792537281899.917}
  #|{"out":{"id":3,"subscribe":{"topic":"prefs"},"keyed":true},"w":1792537281899.926}
  #|{"step":"# written by scripts/rerecord.sh from its test (src/sfreplay/emit.mbt): not edited by hand","w":1792537281901.439}
  #|{"step":"timeout 90000","w":1792537281901.446}
  #|{"step":"answered client.device","w":1792537281901.449}
  #|{"step":"answered client.focus","w":1792537281916.708}
  #|{"in":{"id":2,"value":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""}]},"w":1792537281965.902}
  #|{"in":{"id":3,"value":{"onlyMine":false,"onlyWatching":false,"onlyDecisions":false,"listFilter":{},"appearance":"system","rowPicture":"auto","absoluteTime":false,"lang":"zh","keys":{},"lastChat":{},"openChat":{},"chatTabs":{},"dropFiles":{},"driveViews":{},"resume":{},"stationUpdatesDismissed":{},"device":{"app":"desktop","phone":false,"handoff":false},"reader":{"size":18,"line":1.7,"margin":22,"face":"sans","indent":true,"paper":"follow"},"rails":{},"bars":{"sets":[["chats","files","profiles","stations"],["decisions","usage","connects","archive"]],"current":0},"barsBy":{}}},"w":1792537281965.922}
  #|{"out":{"id":4,"subscribe":{"topic":"workspaces"},"keyed":true},"w":1792537281965.946}
  #|{"out":{"id":5,"subscribe":{"topic":"status"},"keyed":true},"w":1792537281965.958}
  #|{"in":{"id":4,"value":[{"account":{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""},"workspaces":[{"id":"01M5DRPYX4418WR37BHVJ6FPTZ","name":"Dev","role":"owner","created_at":1792537230,"stations":1,"members":1,"relays":[],"time":{"created_at":{"past":true,"at":1792537230000,"ago":"1 分钟前","full":"10/21 07:00:30","until":"1 分钟内"}}}],"invitations":[],"relay_url":"http://127.0.0.1:18940","loaded":true,"beta":true}]},"w":1792537281982.577}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792537281982.592}
  #|{"out":{"id":6,"subscribe":{"topic":"lock","workspace":"01M5DRPYX4418WR37BHVJ6FPTZ"},"keyed":true},"w":1792537281982.628}
  #|{"out":{"id":7,"subscribe":{"topic":"chats","scope":"01M5DRPYX4418WR37BHVJ6FPTZ","mine":false},"keyed":true},"w":1792537281982.643}
  #|{"out":{"id":8,"subscribe":{"topic":"workspaceMarks","workspace":"01M5DRPYX4418WR37BHVJ6FPTZ"},"keyed":true},"w":1792537281982.766}
  #|{"out":{"id":9,"subscribe":{"topic":"status","workspace":"01M5DRPYX4418WR37BHVJ6FPTZ"},"keyed":true},"w":1792537281982.798}
  #|{"out":{"id":10,"call":"client.focus","params":{"visible":true,"focused":true,"workspace":"01M5DRPYX4418WR37BHVJ6FPTZ"}},"w":1792537281988.318}
  #|{"out":{"id":11,"subscribe":{"topic":"notify"},"keyed":true},"w":1792537281988.326}
  #|{"out":{"id":12,"subscribe":{"topic":"notify","workspace":"01M5DRPYX4418WR37BHVJ6FPTZ"},"keyed":true},"w":1792537281988.335}
  #|{"in":{"id":6,"value":{"available":true,"locked":false,"notice":true,"role":"owner","manages":true,"owner":true,"canSign":true,"signs":false,"me":{"device":"ac361e9a756c632009b68ba134099c39855124034dca05f66eab1e4ad93f3f7e","code":"WTQ-2Z8","kind":"app","confirmed":false,"waiting":false,"asked":false},"signers":0,"members":[],"stations":[{"id":"1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","name":"studio","version":"0.1.0","online":true,"protected":false}],"protected":0,"requests":[],"renew":[],"attention":0}},"w":1792537281999.244}
  #|{"in":{"id":7,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"stations":[{"station":"01M5DRPYX4418WR37BHVJ6FPTZ/1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","id":"1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","name":"studio","state":"online"}],"loading":false,"days":[{"daysAgo":0,"at":1792537234119,"label":"今天","items":[{"id":"ember:c-6701b915fb","session":"ember:c-6701b915fb","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","agents":[{"key":"ember:c-6701b915fb","runtime":"claude","process":"warm","pending":0,"lastTurn":{"id":"f8397996-f7e1-4dcd-a38d-89ece106af9b","kind":"input","outcome":"completed","declared":"final","ending":"all_done","need":"answered the question that was asked","startedAt":1792537234044,"endedAt":1792537234121},"agentText":"默认模型","statusText":"已完成：answered the question that was asked"}],"last":{"seq":2,"authorKind":"agent","author":"ember:c-6701b915fb","text":"你好，我是测试用的 agent","createdAt":1792537234119,"by":{"kind":"agent","name":"agent","mine":false,"runtime":"claude","label":"agent"},"preview":"你好，我是测试用的 agent","time":{"createdAt":{"at":1792537234119,"ago":"1 分钟前","full":"10/21 07:00:34","until":"1 分钟内","past":true}}},"unread":true,"mine":true,"lastActiveAt":1792537234119,"station":"01M5DRPYX4418WR37BHVJ6FPTZ/1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","stationName":"studio","time":{"lastActiveAt":{"at":1792537234119,"ago":"1 分钟前","full":"10/21 07:00:34","until":"1 分钟内","past":true}},"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"peopleText":"你 发起","clientKey":"new:chat-81c0c126917f8d1ed4","pinned":false,"tone":"done"}]}],"trouble":null,"members":1,"leading":"agents","glyph":{"online":1,"dim":0,"connecting":0,"failing":0,"working":0,"summary":"studio","label":"1 台 station，1 台在线"},"note":{"reading":false,"text":null,"failing":[],"empty":false}}},"w":1792537281999.274}
  #|{"in":{"id":8,"value":{"workspaces":{"01M5DRPYX4418WR37BHVJ6FPTZ":{"alert":0,"unread":1,"tone":"done","label":"1 个有新消息","badge":0,"items":[],"mineTone":"done"}},"badge":0,"badgeCounts":"attention","badgeKinds":{"on":true,"wait":true,"failed":true,"done":false,"message":false}}},"w":1792537281999.3}
  #|{"in":{"id":9,"value":{"items":[]}},"w":1792537281999.31}
  #|{"in":{"id":10,"ok":null},"w":1792537281999.313}
  #|{"in":{"id":11,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792537281999.319}
  #|{"in":{"id":12,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792537281999.323}
  #|{"out":{"id":13,"subscribe":{"topic":"longJobs","scope":"01M5DRPYX4418WR37BHVJ6FPTZ"},"keyed":true},"w":1792537281999.357}
  #|{"out":{"id":14,"call":"notify.permission","params":{"state":"unknown"}},"w":1792537282002.081}
  #|{"in":{"id":13,"value":{"groups":[]}},"w":1792537282018.743}
  #|{"in":{"id":14,"ok":null},"w":1792537282018.752}
  #|{"step":"answered notify.permission","w":1792537282019.006}
  #|{"step":"tap icon:settings","w":1792537282032.837}
  #|{"step":"tap icon:settings","acted":true,"w":1792537282049.471}
  #|{"out":{"id":15,"subscribe":{"topic":"workspace","workspace":"01M5DRPYX4418WR37BHVJ6FPTZ"},"keyed":true},"w":1792537282066.002}
  #|{"out":{"id":16,"subscribe":{"topic":"stations","scope":"01M5DRPYX4418WR37BHVJ6FPTZ"},"keyed":true},"w":1792537282066.015}
  #|{"out":{"id":17,"subscribe":{"topic":"connects","scope":"01M5DRPYX4418WR37BHVJ6FPTZ","mine":false},"keyed":true},"w":1792537282066.021}
  #|{"out":{"id":18,"subscribe":{"topic":"vaults","workspace":"01M5DRPYX4418WR37BHVJ6FPTZ"},"keyed":true},"w":1792537282066.026}
  #|{"out":{"id":19,"subscribe":{"topic":"doing"},"keyed":true},"w":1792537282070.19}
  #|{"step":"rest","w":1792537282071.048}
  #|{"in":{"id":15,"value":{"id":"01M5DRPYX4418WR37BHVJ6FPTZ","name":"Dev","role":"owner","created_at":1792537230,"members":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":"https://example.test/p.png","role":"owner","added_at":1792537230}],"stations":[{"id":"1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","name":"studio","emoji":null,"icon":null,"enrolled_at":1792537230,"enrolled_by":"alice","last_seen":1792537260,"version":"0.1.0","time":{"last_seen":{"past":true,"at":1792537260000,"ago":"刚刚","full":"10/21 07:01:00","until":"1 分钟内"}}}],"invitations":[],"added":[],"relays":[],"lock":null,"lock_requests":0,"time":{"created_at":{"past":true,"at":1792537230000,"ago":"1 分钟前","full":"10/21 07:00:30","until":"1 分钟内"}}}},"w":1792537282082.576}
  #|{"in":{"id":16,"value":[{"station":"01M5DRPYX4418WR37BHVJ6FPTZ/1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","id":"1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","name":"studio","summary":"正在连接","face":"idle","line":"在线","online":true,"reconnecting":true,"lastSeen":1792537260,"version":"0.1.0","link":{"state":"connecting"},"runtimes":[{"runtime":"claude","models":["claude-sonnet-5-5"]}],"models":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792537234017,"time":{"checkedAt":{"at":1792537234017,"ago":"1 分钟前","full":"10/21 07:00:34","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"overview":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null,"summaryText":"最近 7 天检查了 0 个 chat","changeText":null}},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","email":"alice@example.test","name":"Name of alice","sub":"alice","role":"owner","workspace":"01M5DRPYX4418WR37BHVJ6FPTZ","device":"ac361e9a756c632009b68ba134099c39855124034dca05f66eab1e4ad93f3f7e"},"connects":[],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792537233915,"time":{"checkedAt":{"at":1792537233915,"ago":"1 分钟前","full":"10/21 07:00:33","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792537234017,"time":{"checkedAt":{"at":1792537234017,"ago":"1 分钟前","full":"10/21 07:00:34","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]}],"processes":[],"counts":{"sessions":1,"running":0,"warm":1},"mesh":{"state":"running","origin":"http://127.0.0.1:18900","station":"1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","workspace":"Dev","workspaceId":"01M5DRPYX4418WR37BHVJ6FPTZ","name":"studio"},"slackUsers":[],"slackTeams":[],"slackApps":[],"feishuRegistrations":[],"disk":{"freeBytes":57871659008,"totalBytes":245107195904},"logins":[],"machineLogins":[{"runtime":"claude","installed":true,"loggedIn":false,"usable":false,"text":"无法读取 Claude Code 的登录信息","offered":false},{"runtime":"codex","installed":true,"loggedIn":false,"usable":false,"text":"Codex 未登录","offered":false}],"sharing":true,"consoleSignIn":true,"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"google","name":"Google Gemini","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xai","name":"xAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"mistral","name":"Mistral","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"deepseek","name":"DeepSeek","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen","name":"Qwen","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai","name":"Kimi","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai","name":"Z.ai","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax","name":"MiniMax","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ant-ling","name":"Ant Ling","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"jev","name":"Jev","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen-cn","name":"Qwen (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"openrouter","name":"OpenRouter","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"opencode","name":"OpenCode Zen","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"groq","name":"Groq","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"together","name":"Together AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"fireworks","name":"Fireworks","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cerebras","name":"Cerebras","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"huggingface","name":"Hugging Face","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"nvidia","name":"NVIDIA","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"baseten","name":"Baseten","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ollama","name":"Ollama","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"custom","name":"Custom","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""}],"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792537231526},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.305","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792537231526},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792537231526},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792537231526},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","latest":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792537231526}],"processesText":"没有运行中的 agent 进程","agentEnv":[],"drive":{"roots":[],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false}},"betaOffered":false,"time":{"lastSeen":{"at":1792537260000,"ago":"刚刚","full":"10/21 07:01:00","until":"1 分钟内","past":true}},"joined":false}]},"w":1792537282082.682}
  #|{"in":{"id":17,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"items":[],"wait":{"reading":false,"text":null,"failing":[],"empty":true}}},"w":1792537282082.755}
  #|{"in":{"id":18,"value":{"available":true,"locked":false,"canSign":false,"setUp":false,"vaults":[{"id":"plain","name":"个人","owner":"alice","ownerName":"Name of alice","mine":true,"members":[{"sub":"alice","name":"Name of alice"}],"station":"1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","stationName":"studio","items":0,"devices":0,"open":true,"keyed":true,"missing":0,"recoverable":false}],"requests":[],"refused":[{"station":"1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","name":"studio","code":"vault_needs_lock"}],"plain":true}},"w":1792537282082.762}
  #|{"in":{"id":19,"value":{"doing":[]}},"w":1792537282082.768}
  #|{"step":"now tap =Station","w":1792537282833.409}
  #|{"step":"now tap =Station","acted":true,"w":1792537282850.065}
  #|{"step":"rest","w":1792537282874.519}
  #|{"step":"now tap =studio","w":1792537283199.962}
  #|{"step":"now tap =studio","acted":true,"w":1792537283216.606}
  #|{"out":{"id":20,"subscribe":{"topic":"screens","station":"01M5DRPYX4418WR37BHVJ6FPTZ/1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3"},"keyed":true},"w":1792537283234.971}
  #|{"out":{"id":21,"subscribe":{"topic":"memberships","station":"01M5DRPYX4418WR37BHVJ6FPTZ/1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3"},"keyed":true},"w":1792537283235.08}
  #|{"out":{"id":22,"subscribe":{"topic":"adbShare"},"keyed":true},"w":1792537283237.833}
  #|{"step":"rest","w":1792537283242.024}
  #|{"in":{"id":20,"value":{"screens":[],"outdated":false,"control":true,"known":false}},"w":1792537283249.258}
  #|{"in":{"id":21,"value":{"manages":true,"loading":true,"canJoin":false,"workspaces":[]}},"w":1792537283249.294}
  #|{"in":{"id":22,"value":{"sharing":false,"phase":"off","tunnels":0}},"w":1792537283249.313}
  #|{"step":"now wheelat 450 在此 station 上","w":1792537283566.719}
  #|{"step":"now wheelat 450 在此 station 上","acted":true,"w":1792537283583.582}
  #|{"step":"rest","w":1792537283617.577}
  #|{"in":{"id":5,"value":{"state":"slow","text":"正在连接 studio · 2 秒 · 共 2 项","items":[{"state":"slow","text":"正在连接 studio","detail":"已等待 2 秒"},{"state":"slow","text":"studio 打开实时更新","detail":"已等待 2 秒，尚未收到数据"}]}},"w":1792537284015.951}
  #|{"in":{"id":9,"value":{"state":"slow","text":"正在连接 studio · 2 秒 · 共 2 项","items":[{"state":"slow","text":"正在连接 studio","detail":"已等待 2 秒"},{"state":"slow","text":"studio 打开实时更新","detail":"已等待 2 秒，尚未收到数据"}]}},"w":1792537284015.993}
  #|{"step":"now tap 编辑变量","w":1792537284917.677}
  #|{"step":"now tap 编辑变量","acted":true,"w":1792537284970.564}
  #|{"out":{"id":23,"call":"agentEnv.form.open","params":{"station":"01M5DRPYX4418WR37BHVJ6FPTZ/1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","form":"mbui-env-1","input":{}}},"w":1792537284970.769}
  #|{"step":"answered agentEnv.form.open","w":1792537284981.684}
  #|{"in":{"id":23,"ok":{"text":"","dirty":false,"pending":false,"lines":[{"parts":[],"problem":null,"error":false}],"errors":0}},"w":1792537285003.274}
  #|{"in":{"id":5,"value":{"state":"slow","text":"studio 打开实时更新 ×2 · 3 秒 · 共 2 项","items":[{"state":"slow","text":"studio 打开实时更新 ×2","detail":"已等待 3 秒，尚未收到数据"}]}},"w":1792537285003.308}
  #|{"in":{"id":9,"value":{"state":"slow","text":"studio 打开实时更新 ×2 · 3 秒 · 共 2 项","items":[{"state":"slow","text":"studio 打开实时更新 ×2","detail":"已等待 3 秒，尚未收到数据"}]}},"w":1792537285003.321}
  #|{"out":{"id":24,"subscribe":{"topic":"agentEnvForm","station":"01M5DRPYX4418WR37BHVJ6FPTZ/1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","form":"mbui-env-1"},"keyed":true},"w":1792537285003.423}
  #|{"in":{"id":24,"value":{"text":"","dirty":false,"pending":false,"lines":[{"parts":[],"problem":null,"error":false}],"errors":0}},"w":1792537285053.328}
  #|{"step":"rest","w":1792537285078.188}
  #|{"in":{"id":21,"value":{"manages":true,"loading":false,"canJoin":true,"workspaces":[{"workspace":"01M5DRPYX4418WR37BHVJ6FPTZ","name":"Dev","stationName":"studio","home":true,"here":true,"line":"主 workspace"}]}},"w":1792537285285.076}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792537285449.244}
  #|{"in":{"id":9,"value":{"items":[]}},"w":1792537285449.269}
  #|{"in":{"id":16,"delta":[{"path":[0,"link","state"],"set":"online"},{"path":[0,"overview","counts","warm"],"set":0},{"path":[0,"overview","disk","freeBytes"],"set":57607786496},{"path":[0,"overview","machineLogins"],"set":[]},{"path":[0,"overview","profiles",0,"check","checkedAt"],"set":1792537284772},{"path":[0,"overview","profiles",0,"check","time","checkedAt","ago"],"set":"刚刚"},{"path":[0,"overview","profiles",0,"check","time","checkedAt","at"],"set":1792537284772},{"path":[0,"overview","profiles",0,"check","time","checkedAt","full"],"set":"10/21 07:01:24"},{"path":[0,"overview","updates",0,"checkedAt"],"set":1792537282413},{"path":[0,"overview","updates",1,"checkedAt"],"set":1792537282413},{"path":[0,"overview","updates",2,"checkedAt"],"set":1792537282413},{"path":[0,"overview","updates",3,"checkedAt"],"set":1792537282413},{"path":[0,"overview","updates",4,"checkedAt"],"set":1792537282413},{"path":[0,"reconnecting"],"set":false}]},"w":1792537285482.763}
  #|{"in":{"id":7,"delta":[{"path":["days"],"key":["daysAgo"],"patch":0,"ops":[{"path":["items"],"key":["station","id"],"patch":["01M5DRPYX4418WR37BHVJ6FPTZ/1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","ember:c-6701b915fb"],"ops":[{"path":["agents",0,"process"],"set":"cold"},{"path":["clientKey"],"remove":true}]}]}]},"w":1792537285582.584}
  #|{"in":{"id":20,"value":{"screens":[{"id":"desktop","kind":"desktop","title":"3720-Mac-mini-1","width":0,"height":0,"viewers":[],"controlledBy":[],"access":{"capture":false,"control":false,"message":"此 station 版本不含屏幕助手（stillfail-screen），请更新 station"},"clipboard":[],"drop":{"folder":"/tmp/mbe2e-C/home","reveal":true},"peek":false,"line":"此 station 版本不含屏幕助手（stillfail-screen），请更新 station","link":"/w/01M5DRPYX4418WR37BHVJ6FPTZ/s/1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3/screen/desktop"}],"outdated":false,"control":true,"known":true}},"w":1792537285582.641}
  #|{"in":{"id":16,"delta":[{"path":[0,"host"],"set":{"hostname":"3720-Mac-mini-1","os":"macOS 27.0.1","arch":"arm64","cpus":10,"cpuModel":"Apple M4","load":1.05,"cpuBusy":0.82,"uptimeSec":16647,"memory":{"totalBytes":17179869184,"usedBytes":10279878656,"swapUsedBytes":325184389},"disk":{"path":"/tmp/mbe2e-C/data","totalBytes":245107195904,"freeBytes":57605767168},"emberRssBytes":140916176,"checkedAt":1792537285564,"summary":"10 核 · 16 GB","line":"macOS 27.0.1 · 10 核 · 16 GB · 已运行 0 天","facts":["3720-Mac-mini-1","macOS 27.0.1","arm64 · 10 核","已运行 4 小时"],"meters":[{"label":"CPU","short":"CPU","percent":82,"left":18,"level":"amber","value":"82%","remaining":"空闲 18%","big":"18","unit":"%","title":"CPU 空闲","total":"负载 10.5","note":"负载 10.5 · Apple M4"},{"label":"内存","short":"内存","percent":60,"left":40,"level":"ok","value":"9.6 GB / 16.0 GB","remaining":"剩 6.4 G","big":"6.4","unit":"GB","title":"内存剩","total":"共 16 GB","note":"swap 0.3 GB"},{"label":"磁盘","short":"磁盘","percent":76,"left":24,"level":"amber","value":"剩余 53.6 GB / 228 GB","remaining":"剩 53.6 G","big":"53.6","unit":"GB","title":"磁盘剩","total":"共 228 GB"}],"identity":"Apple M4 · 16 GB · macOS 27.0.1","details":[{"label":"主机名","value":"3720-Mac-mini-1"},{"label":"芯片","value":"Apple M4 · 10 核 · arm64"},{"label":"已运行","value":"4 小时"},{"label":"still.fail","value":"进程占用 134 MB"}],"usage":"内存 9.6 GB / 16.0 GB · 磁盘 剩余 53.6 GB / 228 GB","emberText":"still.fail 134 MB"}},{"path":[0,"line"],"set":"Apple M4"},{"path":[0,"summary"],"set":"空闲 · Apple M4 · 16 GB · macOS 27.0.1"}]},"w":1792537285682.591}
  #|{"in":{"id":16,"delta":[{"path":[0,"way"],"set":{"path":"直连","via":"direct"}}]},"w":1792537286638.42}
  #|{"step":"now tap HTTPS_PROXY=","w":1792537286800.157}
  #|{"step":"now tap HTTPS_PROXY=","acted":true,"w":1792537286854.822}
  #|{"step":"type E2E_PROXY_080726=http://127.0.0.1:9","w":1792537287035.911}
  #|{"step":"type E2E_PROXY_080726=http://127.0.0.1:9","acted":true,"w":1792537287035.938}
  #|{"out":{"id":25,"call":"agentEnv.form.edit","params":{"station":"01M5DRPYX4418WR37BHVJ6FPTZ/1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","form":"mbui-env-1","input":{"text":"E2E_PROXY_080726=http://127.0.0.1:9"}}},"w":1792537287037.184}
  #|{"step":"answered agentEnv.form.edit","w":1792537287049.478}
  #|{"in":{"id":25,"ok":{"text":"E2E_PROXY_080726=http://127.0.0.1:9","dirty":true,"pending":false,"lines":[{"parts":[{"kind":"name","text":"E2E_PROXY_080726"},{"kind":"other","text":"="},{"kind":"value","text":"http://127.0.0.1:9"}],"problem":null,"error":false}],"errors":0}},"w":1792537287066.182}
  #|{"in":{"id":24,"delta":[{"path":["dirty"],"set":true},{"path":["lines",0,"parts"],"append":[{"kind":"name","text":"E2E_PROXY_080726"},{"kind":"other","text":"="},{"kind":"value","text":"http://127.0.0.1:9"}]},{"path":["text"],"set":"E2E_PROXY_080726=http://127.0.0.1:9"}]},"w":1792537287115.939}
  #|{"step":"tap =保存","w":1792537287133.906}
  #|{"step":"tap =保存","acted":true,"w":1792537287153.434}
  #|{"out":{"id":26,"call":"agentEnv.form.save","params":{"station":"01M5DRPYX4418WR37BHVJ6FPTZ/1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","form":"mbui-env-1","input":{}}},"w":1792537287166.569}
  #|{"step":"answered agentEnv.form.save","w":1792537287167.424}
  #|{"in":{"id":26,"ok":{"env":[{"key":"E2E_PROXY_080726","value":"http://127.0.0.1:9","secret":false}]}},"w":1792537287215.9}
  #|{"step":"until 已保存","w":1792537287233.689}
  #|{"step":"wait 2600","w":1792537287233.72}
  #|{"in":{"id":24,"delta":[{"path":["dirty"],"set":false}]},"w":1792537287249.243}
  #|{"in":{"id":16,"delta":[{"path":[0,"overview","agentEnv"],"append":[{"key":"E2E_PROXY_080726","secret":false,"value":"http://127.0.0.1:9"}]},{"path":[0,"overview","disk","freeBytes"],"set":57601036288}]},"w":1792537287249.28}
  #|{"step":"now rest","w":1792537289849.769}
  #|{"step":"now until E2E_PROXY_080726","w":1792537289968.211}
  #|{"step":"tap 编辑变量","w":1792537289968.232}
  #|{"step":"tap 编辑变量","acted":true,"w":1792537289999.822}
  #|{"out":{"id":27,"call":"agentEnv.form.open","params":{"station":"01M5DRPYX4418WR37BHVJ6FPTZ/1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","form":"mbui-env-2","input":{}}},"w":1792537290016.126}
  #|{"step":"answered agentEnv.form.open","w":1792537290016.53}
  #|{"in":{"id":27,"ok":{"text":"E2E_PROXY_080726=http://127.0.0.1:9","dirty":false,"pending":false,"lines":[{"parts":[{"kind":"name","text":"E2E_PROXY_080726"},{"kind":"other","text":"="},{"kind":"value","text":"http://127.0.0.1:9"}],"problem":null,"error":false}],"errors":0}},"w":1792537290032.575}
  #|{"out":{"id":28,"subscribe":{"topic":"agentEnvForm","station":"01M5DRPYX4418WR37BHVJ6FPTZ/1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","form":"mbui-env-2"},"keyed":true},"w":1792537290033.085}
  #|{"in":{"id":28,"value":{"text":"E2E_PROXY_080726=http://127.0.0.1:9","dirty":false,"pending":false,"lines":[{"parts":[{"kind":"name","text":"E2E_PROXY_080726"},{"kind":"other","text":"="},{"kind":"value","text":"http://127.0.0.1:9"}],"problem":null,"error":false}],"errors":0}},"w":1792537290050.257}
  #|{"step":"rest","w":1792537290051.613}
  #|{"step":"now until Agent 环境变量","w":1792537291516.756}
  #|{"step":"tapxy 195 304","w":1792537291516.837}
  #|{"step":"tapxy 195 304","acted":true,"w":1792537291516.913}
  #|{"step":"clear","w":1792537291533.494}
  #|{"step":"clear","acted":true,"w":1792537291533.559}
  #|{"out":{"id":29,"call":"agentEnv.form.edit","params":{"station":"01M5DRPYX4418WR37BHVJ6FPTZ/1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","form":"mbui-env-2","input":{"text":""}}},"w":1792537291549.772}
  #|{"step":"answered agentEnv.form.edit","w":1792537291550.359}
  #|{"in":{"id":29,"ok":{"text":"","dirty":true,"pending":false,"lines":[{"parts":[],"problem":null,"error":false}],"errors":0}},"w":1792537291565.887}
  #|{"in":{"id":28,"delta":[{"path":["dirty"],"set":true},{"path":["lines",0,"parts"],"set":[]},{"path":["text"],"set":""}]},"w":1792537291732.55}
  #|{"step":"tap =保存","w":1792537291757.427}
  #|{"step":"tap =保存","acted":true,"w":1792537291800.582}
  #|{"out":{"id":30,"call":"agentEnv.form.save","params":{"station":"01M5DRPYX4418WR37BHVJ6FPTZ/1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","form":"mbui-env-2","input":{}}},"w":1792537291816.553}
  #|{"step":"until 已保存","w":1792537291817.26}
  #|{"in":{"id":30,"ok":{"env":[]}},"w":1792537291865.882}
  #|{"step":"wait 2600","w":1792537291867.374}
  #|{"in":{"id":28,"delta":[{"path":["dirty"],"set":false}]},"w":1792537291949.238}
  #|{"in":{"id":16,"delta":[{"path":[0,"overview","agentEnv"],"set":[]},{"path":[0,"overview","disk","freeBytes"],"set":57578045440}]},"w":1792537291965.886}
  #|{"in":{"id":24,"delta":[{"path":["lines",0,"parts"],"set":[]},{"path":["text"],"set":""}]},"w":1792537291965.921}
  #|{"step":"now until 暂无变量","w":1792537294633.241}
  #|{"step":"wheelat 1500 编辑变量","w":1792537294633.266}
  #|{"step":"wheelat 1500 编辑变量","acted":true,"w":1792537294649.945}
  #|{"step":"rest","w":1792537294667.453}
  #|{"step":"now tap =检查更新","w":1792537296033.44}
  #|{"step":"now tap =检查更新","acted":true,"w":1792537296050.072}
  #|{"out":{"id":31,"call":"software.check","params":{"station":"01M5DRPYX4418WR37BHVJ6FPTZ/1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3"}},"w":1792537296066.151}
  #|{"step":"rest","w":1792537296066.49}
  #|{"in":{"id":19,"value":{"doing":[{"call":"software.check","params":{"station":"01M5DRPYX4418WR37BHVJ6FPTZ/1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3"},"since":1792537296066,"stage":"running"}]}},"w":1792537296282.761}
  #|{"in":{"id":31,"ok":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792537296772},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.305","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792537296772},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792537296772},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792537296772},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","latest":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792537296772}]},"w":1792537296815.924}
  #|{"step":"","w":1792537296833.025}
  #|{"textrec":{"ib":["bfd9b0d6dc602826",12668,64],"r":[56,56,56,56]}}
  #|{"textrec":{"s":[13,400,0,"正在读取你的 workspace"],"r":[0,1,12.898832684824903,0,1,1,12.898832684824903,1,2,1,12.898832684824903,2,3,1,12.898832684824903,3,4,1,12.898832684824896,4,5,1,12.898832684824896,5,6,1,3.580078125,-1,7,1,9.8642578125,6,8,1,7.4775390625,7,9,1,4.875,8,10,1,6.85546875,9,11,1,6.6015625,10,12,1,7.8583984375,11,13,1,7.0966796875,12,14,1,7.1982421875,13,15,1,7.3505859375,14]}}
  #|{"textrec":{"m":[13,400,0],"r":[12.568359375,2.7421875,18]}}
  #|{"textrec":{"s":[24,700,0,"Dev"],"r":[0,1,17.075823068618774,15,1,1,13.365240812301636,16,2,1,12.759063005447388,17]}}
  #|{"textrec":{"m":[24,700,0],"r":[23.203125,5.0625,34]}}
  #|{"textrec":{"g":15,"r":[0,0,18,19,0,-18,0]}}
  #|{"textrec":{"g":16,"r":[19,0,15,16,-1,-14,0]}}
  #|{"textrec":{"g":17,"r":[35,0,15,15,-1,-14,0]}}
  #|{"textrec":{"ib":["1d51432b25a425eb",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"ib":["bef2954d97ce1d9f",6508,64],"r":[40,40,40,40]}}
  #|{"textrec":{"ib":["02698e60df92657e",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"ib":["fdb526ba00f881f4",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["a7ccae3554fe46cf",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["c8ac90bf691295f0",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["31d8ec32aedeae00",3232,64],"r":[28,28,28,28]}}
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
  #|{"textrec":{"s":[17,400,0,"会话"],"r":[0,1,16.851167315175097,63,1,1,16.851167315175097,64]}}
  #|{"textrec":{"m":[17,400,0],"r":[16.435546875,3.5859375,24]}}
  #|{"textrec":{"s":[32,700,8,"设置"],"r":[0,1,30.345864661654133,65,1,1,30.345864661654133,66]}}
  #|{"textrec":{"m":[32,700,0],"r":[30.9375,6.75,45]}}
  #|{"textrec":{"s":[16,700,0,"Name of alice"],"r":[0,1,11.9765625,67,1,1,9.12109375,68,2,1,14.6015625,69,3,1,9.30078125,70,4,1,3.8125,-1,5,1,9.6015625,71,6,1,6.21484375,72,7,1,3.8125,-1,8,1,9.12109375,68,9,1,4.40625,73,10,1,4.28125,74,11,1,9.0859375,75,12,1,9.30078125,70]}}
  #|{"textrec":{"m":[16,700,0],"r":[15.46875,3.375,23]}}
  #|{"textrec":{"s":[13,400,0,"alice@example.test"],"r":[0,1,7.0966796875,12,1,1,3.2119140625,76,2,1,3.1357421875,77,3,1,7.1982421875,13,4,1,7.3505859375,14,5,1,11.857421875,78,6,1,7.2236328125,14,7,1,6.6142578125,79,8,1,7.0966796875,12,9,1,11.2353515625,80,10,1,7.8583984375,11,11,1,3.2119140625,76,12,1,7.3505859375,14,13,1,3.65625,81,14,1,4.471923828125,82,15,1,7.302978515625,14,16,1,6.69677734375,10,17,1,4.61474609375,82]}}
  #|{"textrec":{"s":[23,600,0,"N"],"r":[0,1,16.576080499507952,83]}}
  #|{"textrec":{"m":[23,600,0],"r":[22.236328125,4.8515625,33]}}
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
  #|{"textrec":{"s":[15,600,0,"Dev · 你是Owner"],"r":[0,1,10.861195921897888,84,1,1,8.51915180683136,85,2,1,8.18638265132904,86,3,1,3.761730194091797,-1,4,1,7.186782927948599,168,5,1,3.761730194091797,-1,6,1,14.883268482490273,169,7,1,14.883268482490273,170,8,1,13.354362845420837,171,9,1,12.072962522506714,172,10,1,8.93320620059967,173,11,1,8.615586161613464,85,12,1,5.99338173866272,174]}}
  #|{"textrec":{"s":[14,400,0,"1 人"],"r":[0,1,6.34375,175,1,1,3.787109375,-1,2,1,13.891050583657588,176]}}
  #|{"textrec":{"s":[14,400,0,"0 条"],"r":[0,1,8.66796875,177,1,1,3.787109375,-1,2,1,13.891050583657588,178]}}
  #|{"textrec":{"s":[15,400,0,"密钥"],"r":[0,1,14.883268482490273,179,1,1,14.883268482490273,180]}}
  #|{"textrec":{"s":[14,400,0,"1/1 在线"],"r":[0,1,6.34375,175,1,1,4.115234375,181,2,1,6.34375,175,3,1,3.787109375,-1,4,1,13.891050583657588,182,5,1,13.891050583657588,183]}}
  #|{"textrec":{"s":[14,400,0,"0 个"],"r":[0,1,8.66796875,177,1,1,3.787109375,-1,2,1,13.891050583657588,184]}}
  #|{"textrec":{"s":[14,400,0,"1 个"],"r":[0,1,6.34375,175,1,1,3.787109375,-1,2,1,13.891050583657588,184]}}
  #|{"textrec":{"ib":["504a4df6beac534a",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["a1e7be43eb966606",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"g":63,"r":[666,0,18,18,-1,-15,0]}}
  #|{"textrec":{"g":64,"r":[685,0,19,18,-1,-15,0]}}
  #|{"textrec":{"g":65,"r":[705,0,31,31,0,-26,0]}}
  #|{"textrec":{"g":66,"r":[737,0,30,29,0,-25,0]}}
  #|{"textrec":{"g":84,"r":[768,0,12,13,0,-12,0]}}
  #|{"textrec":{"g":85,"r":[781,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":86,"r":[793,0,11,11,-1,-10,0]}}
  #|{"textrec":{"g":168,"r":[805,0,5,5,1,-8,0]}}
  #|{"textrec":{"g":169,"r":[811,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":170,"r":[828,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":171,"r":[845,0,13,14,-1,-12,0]}}
  #|{"textrec":{"g":172,"r":[859,0,14,11,-1,-10,0]}}
  #|{"textrec":{"g":173,"r":[874,0,10,11,0,-10,0]}}
  #|{"textrec":{"g":174,"r":[885,0,7,11,0,-10,0]}}
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
  #|{"textrec":{"g":179,"r":[1012,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":180,"r":[1029,0,16,16,-1,-13,0]}}
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
  #|{"textrec":{"g":175,"r":[1763,0,7,12,-1,-11,0]}}
  #|{"textrec":{"g":181,"r":[1771,0,7,16,-1,-12,0]}}
  #|{"textrec":{"g":182,"r":[1779,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":183,"r":[1795,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":120,"r":[1812,0,16,15,-1,-12,0]}}
  #|{"textrec":{"g":121,"r":[1829,0,15,16,0,-13,0]}}
  #|{"textrec":{"g":122,"r":[1845,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":123,"r":[1861,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":176,"r":[1878,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":177,"r":[1895,0,10,14,-1,-12,0]}}
  #|{"textrec":{"g":178,"r":[1906,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":184,"r":[1923,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":126,"r":[1940,0,9,13,0,-12,0]}}
  #|{"textrec":{"g":127,"r":[1950,0,16,16,-1,-13,0]}}
  #|{"textrec":{"ib":["b3685975cd23abc3",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"s":[16,600,0,"Station"],"r":[0,1,10.266256332397461,185,1,1,5.999713897705078,36,2,1,8.899068832397461,44,3,1,5.999713897705078,36,4,1,4.046333312988281,186,5,1,9.432537078857422,34,6,1,9.466253280639648,47]}}
  #|{"textrec":{"s":[17,400,0,"设置"],"r":[0,1,16.851167315175097,187,1,1,16.851167315175097,188]}}
  #|{"textrec":{"s":[12,400,0,"正在重新连接"],"r":[0,1,11.918287937743191,189,1,1,11.918287937743191,190,2,1,11.918287937743195,191,3,1,11.918287937743187,192,4,1,11.918287937743187,193,5,1,11.918287937743187,194]}}
  #|{"textrec":{"m":[12,400,0],"r":[11.6015625,2.53125,17]}}
  #|{"textrec":{"s":[16,700,0,"studio"],"r":[0,1,8.73046875,195,1,1,6.26953125,196,2,1,9.72265625,197,3,1,10.109375,198,4,1,4.28125,74,5,1,9.6015625,71]}}
  #|{"textrec":{"s":[13,400,0,"正在连接"],"r":[0,1,12.898832684824903,0,1,1,12.898832684824903,1,2,1,12.898832684824903,199,3,1,12.898832684824903,200]}}
  #|{"textrec":{"s":[13,400,0,"↑"],"r":[0,1,10.080078125,201]}}
  #|{"textrec":{"s":[13,500,0," "],"r":[0,1,3.4683494567871094,-1]}}
  #|{"textrec":{"m":[13,500,0],"r":[12.568359375,2.7421875,18]}}
  #|{"textrec":{"s":[13,400,0,"↓"],"r":[0,1,10.080078125,202]}}
  #|{"textrec":{"s":[13,400,0,"直连"],"r":[0,1,12.898832684824903,203,1,1,12.898832684824903,199]}}
  #|{"textrec":{"s":[13,400,0,"当前延迟 "],"r":[0,1,12.898832684824903,204,1,1,12.898832684824903,205,2,1,12.898832684824903,206,3,1,12.898832684824903,207,4,1,3.580078125,-1]}}
  #|{"textrec":{"s":[13,500,0,"0 ms"],"r":[0,1,8.373004913330078,208,1,1,3.4683494567871094,-1,2,1,11.530966997146606,209,3,1,6.933351516723633,210]}}
  #|{"textrec":{"g":187,"r":[1967,0,19,18,-1,-15,0]}}
  #|{"textrec":{"g":188,"r":[1987,0,18,17,-1,-14,0]}}
  #|{"textrec":{"ib":["b7b1dc2c98725280",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"g":195,"r":[2006,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":196,"r":[2018,0,8,14,-1,-12,0]}}
  #|{"textrec":{"g":197,"r":[2027,0,10,12,0,-10,0]}}
  #|{"textrec":{"g":198,"r":[0,32,12,15,-1,-13,0]}}
  #|{"textrec":{"g":0,"r":[13,32,14,13,-1,-11,0]}}
  #|{"textrec":{"g":1,"r":[28,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":199,"r":[43,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":200,"r":[59,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":185,"r":[75,32,12,15,-1,-13,0]}}
  #|{"textrec":{"g":44,"r":[88,32,11,12,-1,-10,0]}}
  #|{"textrec":{"g":186,"r":[100,32,5,15,0,-14,0]}}
  #|{"textrec":{"g":47,"r":[106,32,10,11,0,-10,0]}}
  #|{"textrec":{"g":189,"r":[117,32,14,12,-1,-10,0]}}
  #|{"textrec":{"g":190,"r":[132,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":191,"r":[147,32,14,13,-1,-11,0]}}
  #|{"textrec":{"g":192,"r":[162,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":193,"r":[177,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":194,"r":[192,32,14,14,-1,-11,0]}}
  #|{"textrec":{"ib":["2bb63fc1d380f765",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"s":[16,600,0,"studio"],"r":[0,1,8.471200942993164,35,1,1,5.973020553588867,36,2,1,9.466253280639648,211,3,1,9.891647338867188,212,4,1,4.046333312988281,186,5,1,9.432537078857422,34]}}
  #|{"textrec":{"s":[17,400,0,"Station"],"r":[0,1,10.40087890625,213,1,1,5.744140625,214,2,1,8.9482421875,215,3,1,5.744140625,214,4,1,3.7685546875,216,5,1,9.6123046875,217,6,1,9.48779296875,218]}}
  #|{"textrec":{"s":[13,400,0,"没有运行中的 agent 进程"],"r":[0,1,12.898832684824903,219,1,1,12.898832684824903,149,2,1,12.898832684824903,220,3,1,12.898832684824903,221,4,1,12.898832684824896,222,5,1,12.898832684824896,5,6,1,3.580078125,-1,7,1,7.0966796875,12,8,1,7.845703125,223,9,1,7.3505859375,14,10,1,7.50927734375,224,11,1,4.646484375,82,12,1,3.580078125,-1,13,1,12.898832684824896,225,14,1,12.898832684824896,226]}}
  #|{"textrec":{"s":[15,600,0,"在此 station 上"],"r":[0,1,14.883268482490273,227,1,1,14.883268482490273,117,2,1,3.761730194091797,-1,3,1,8.000344634056091,228,4,1,5.658300518989563,229,5,1,8.40147078037262,230,6,1,5.683325529098511,229,7,1,3.8520312309265137,231,8,1,8.901597261428833,232,9,1,8.93320620059967,173,10,1,3.761730194091797,-1,11,1,14.883268482490266,233]}}
  #|{"textrec":{"s":[15,400,0,"共享调试"],"r":[0,1,14.883268482490273,234,1,1,14.883268482490273,235,2,1,14.883268482490273,236,3,1,14.883268482490273,237]}}
  #|{"textrec":{"s":[14,400,0,"未开放"],"r":[0,1,13.891050583657588,96,1,1,13.891050583657588,97,2,1,13.891050583657588,238]}}
  #|{"textrec":{"s":[15,400,0,"文件"],"r":[0,1,14.883268482490273,239,1,1,14.883268482490273,240]}}
  #|{"textrec":{"s":[15,600,0,"Agent 环境变量"],"r":[0,1,10.209932327270508,241,1,1,9.027448296546936,242,2,1,8.615586161613464,85,3,1,8.93320620059967,173,4,1,5.683325529098511,229,5,1,3.761730194091797,-1,6,1,14.883268482490273,243,7,1,14.883268482490273,244,8,1,14.883268482490266,245,9,1,14.88326848249028,246]}}
  #|{"textrec":{"s":[15,400,0,"暂无变量"],"r":[0,1,14.883268482490273,247,1,1,14.883268482490273,248,2,1,14.883268482490273,249,3,1,14.883268482490273,116]}}
  #|{"textrec":{"s":[15,400,0,"编辑变量"],"r":[0,1,14.883268482490273,250,1,1,14.883268482490273,251,2,1,14.883268482490273,249,3,1,14.883268482490273,116]}}
  #|{"textrec":{"s":[15,600,0,"搜索"],"r":[0,1,14.883268482490273,252,1,1,14.883268482490273,253]}}
  #|{"textrec":{"s":[15,400,0,"搜索个人数据"],"r":[0,1,14.883268482490273,18,1,1,14.883268482490273,19,2,1,14.883268482490273,254,3,1,14.883268482490273,255,4,1,14.88326848249028,256,5,1,14.88326848249028,257]}}
  #|{"textrec":{"s":[13,400,0,"workspace 成员也可搜索邮件、信息、日历、通讯录、备忘录和照片"],"r":[0,1,9.8642578125,6,1,1,7.4775390625,7,2,1,4.875,8,3,1,6.85546875,9,4,1,6.6015625,10,5,1,7.8583984375,11,6,1,7.0966796875,12,7,1,7.1982421875,13,8,1,7.3505859375,14,9,1,3.580078125,-1,10,1,12.898832684824896,140,11,1,12.898832684824896,258,12,1,12.898832684824896,259,13,1,12.898832684824896,260,14,1,12.898832684824896,261,15,1,12.898832684824896,262,16,1,12.898832684824896,263,17,1,12.898832684824896,264,18,1,13.075875486381335,141,19,1,12.898832684824896,265,20,1,12.898832684824896,152,21,1,13.075875486381335,141,22,1,12.898832684824896,266,23,1,12.898832684824896,267,24,1,13.075875486381335,141,25,1,12.898832684824924,154,26,1,12.898832684824924,268,27,1,12.898832684824924,269,28,1,13.075875486381335,141,29,1,12.898832684824924,270,30,1,12.898832684824924,271,31,1,12.898832684824924,269,32,1,12.898832684824924,272,33,1,12.898832684824924,273,34,1,12.898832684824924,274]}}
  #|{"textrec":{"g":213,"r":[207,32,12,16,-1,-14,0]}}
  #|{"textrec":{"g":214,"r":[220,32,8,15,-1,-13,0]}}
  #|{"textrec":{"g":215,"r":[229,32,11,13,-1,-11,0]}}
  #|{"textrec":{"g":216,"r":[241,32,5,15,0,-14,0]}}
  #|{"textrec":{"g":217,"r":[247,32,12,13,-1,-11,0]}}
  #|{"textrec":{"g":218,"r":[260,32,10,12,0,-11,0]}}
  #|{"textrec":{"g":219,"r":[271,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":149,"r":[287,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":220,"r":[302,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":221,"r":[318,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":222,"r":[334,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":5,"r":[348,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":223,"r":[362,32,9,12,-1,-8,0]}}
  #|{"textrec":{"g":224,"r":[372,32,8,9,0,-8,0]}}
  #|{"textrec":{"g":225,"r":[381,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":226,"r":[397,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":227,"r":[413,32,16,17,-1,-14,0]}}
  #|{"textrec":{"g":228,"r":[430,32,10,12,-1,-10,0]}}
  #|{"textrec":{"g":229,"r":[441,32,8,13,-1,-11,0]}}
  #|{"textrec":{"g":230,"r":[450,32,10,12,-1,-10,0]}}
  #|{"textrec":{"g":231,"r":[461,32,6,14,-1,-13,0]}}
  #|{"textrec":{"g":232,"r":[468,32,11,12,-1,-10,0]}}
  #|{"textrec":{"g":233,"r":[480,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":234,"r":[497,32,16,17,-1,-14,0]}}
  #|{"textrec":{"g":235,"r":[514,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":236,"r":[531,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":237,"r":[548,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":239,"r":[566,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":240,"r":[584,32,16,17,-1,-14,0]}}
  #|{"textrec":{"g":241,"r":[601,32,13,13,-1,-12,0]}}
  #|{"textrec":{"g":242,"r":[615,32,11,14,-1,-10,0]}}
  #|{"textrec":{"g":243,"r":[627,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":244,"r":[645,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":245,"r":[663,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":246,"r":[681,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":247,"r":[698,32,15,17,0,-14,0]}}
  #|{"textrec":{"g":248,"r":[714,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":249,"r":[731,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":250,"r":[749,32,16,17,-1,-14,0]}}
  #|{"textrec":{"g":251,"r":[766,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":252,"r":[784,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":253,"r":[802,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":254,"r":[819,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":255,"r":[837,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":256,"r":[855,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":257,"r":[873,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":6,"r":[890,32,12,9,-1,-8,0]}}
  #|{"textrec":{"g":7,"r":[903,32,9,10,-1,-8,0]}}
  #|{"textrec":{"g":8,"r":[913,32,6,9,0,-8,0]}}
  #|{"textrec":{"g":9,"r":[920,32,8,12,0,-11,0]}}
  #|{"textrec":{"g":140,"r":[929,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":258,"r":[945,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":259,"r":[960,32,15,14,-1,-12,0]}}
  #|{"textrec":{"g":260,"r":[976,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":261,"r":[991,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":262,"r":[1007,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":263,"r":[1022,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":264,"r":[1037,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":141,"r":[1053,32,6,6,0,-3,0]}}
  #|{"textrec":{"g":265,"r":[1060,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":152,"r":[1076,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":266,"r":[1092,32,11,14,1,-11,0]}}
  #|{"textrec":{"g":267,"r":[1104,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":211,"r":[1119,32,10,12,0,-10,0]}}
  #|{"textrec":{"g":212,"r":[1130,32,11,15,-1,-13,0]}}
  #|{"textrec":{"g":238,"r":[1142,32,16,16,-1,-13,0]}}
  #|{"textrec":{"ib":["ddfdc2820df8a676",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"s":[15,600,0,"版本"],"r":[0,1,14.883268482490273,275,1,1,14.883268482490273,276]}}
  #|{"textrec":{"s":[13,400,0,"开发版"],"r":[0,1,12.898832684824903,277,1,1,12.898832684824903,278,2,1,12.898832684824903,279]}}
  #|{"textrec":{"s":[13,400,0,"并非通过安装脚本安装，无法在此更新；检查更新失败，点击「检查更新」重试"],"r":[0,1,12.898832684824903,280,1,1,12.898832684824903,281,2,1,12.898832684824903,154,3,1,12.898832684824903,282,4,1,12.898832684824896,283,5,1,12.898832684824896,284,6,1,12.898832684824896,285,7,1,12.898832684824896,286,8,1,12.898832684824896,283,9,1,12.898832684824896,284,10,1,13.075875486381335,287,11,1,12.898832684824896,288,12,1,12.898832684824896,289,13,1,12.898832684824896,1,14,1,12.898832684824896,290,15,1,12.898832684824896,291,16,1,12.898832684824896,150,17,1,13.075875486381335,292,18,1,12.898832684824896,293,19,1,12.898832684824924,294,20,1,12.898832684824924,291,21,1,12.898832684824924,150,22,1,12.898832684824924,295,23,1,12.898832684824924,296,24,1,13.075875486381335,287,25,1,12.898832684824924,297,26,1,19.398832684824924,298,27,1,4.704280155642039,299,28,1,12.898832684824924,293,29,1,12.898832684824924,294,30,1,12.898832684824924,291,31,1,12.898832684824924,150,32,1,4.451361867704293,300,33,1,19.398832684824924,301,34,1,12.898832684824924,302]}}
  #|{"textrec":{"s":[15,400,0,"Claude Code"],"r":[0,1,10.5029296875,303,1,1,3.5595703125,108,2,1,8.0419921875,93,3,1,8.51806640625,163,4,1,8.9794921875,304,5,1,8.3349609375,95,6,1,3.984375,-1,7,1,10.5029296875,303,8,1,8.6279296875,88,9,1,8.9794921875,304,10,1,8.3349609375,95]}}
  #|{"textrec":{"s":[13,400,0,"版本未知"],"r":[0,1,12.898832684824903,279,1,1,12.898832684824903,286,2,1,12.898832684824903,305,3,1,12.898832684824903,155]}}
  #|{"textrec":{"s":[13,400,0,"已是最新"],"r":[0,1,12.898832684824903,306,1,1,12.898832684824903,307,2,1,12.898832684824903,308,3,1,12.898832684824903,150]}}
  #|{"textrec":{"s":[15,400,0,"Codex"],"r":[0,1,10.5029296875,303,1,1,8.6279296875,88,2,1,8.9794921875,304,3,1,8.1884765625,95,4,1,7.4853515625,309]}}
  #|{"textrec":{"s":[13,400,0,"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新；已是最新"],"r":[0,1,12.898832684824903,283,1,1,12.898832684824903,284,2,1,12.898832684824903,1,3,1,3.580078125,-1,4,1,3.884765625,310,5,1,9.5087890625,311,6,1,6.728515625,10,7,1,7.350585937500007,14,8,1,4.8115234375,8,9,1,6.6650390625,10,10,1,3.884765625,310,11,1,6.931640625,312,12,1,7.50927734375,313,13,1,7.50927734375,7,14,1,6.83642578125,312,15,1,3.1357421875,77,16,1,3.12939453125,314,17,1,3.1357421875,77,18,1,7.0966796875,12,19,1,7.50927734375,224,20,1,3.630859375,310,21,1,3.529296875,81,22,1,6.69677734375,10,23,1,4.61474609375,82,24,1,3.1357421875,77,25,1,3.2119140625,76,26,1,3.2119140625,76,27,1,4.5322265625,315,28,1,7.00146484375,12,29,1,3.1357421875,77,30,1,3.2119140625,76,31,1,3.884765625,310,32,1,4.77978515625,8,33,1,7.25537109375,14,34,1,11.2353515625,80,35,1,7.6044921875,7,36,1,4.598876953125,82,37,1,7.302978515625,14,38,1,3.884765625,310,39,1,6.728515625,10,40,1,7.3505859375,14,41,1,6.6650390625,10,42,1,6.6650390625,10,43,1,3.1357421875,77,44,1,7.6044921875,7,45,1,7.50927734375,224,46,1,6.728515625,10,47,1,3.884765625,310,48,1,7.0966796875,12,49,1,7.1982421875,13,50,1,8.201171875,316,51,1,7.9091796875,317,52,1,8.07421875,318,53,1,4.62744140625,315,54,1,7.22998046875,319,55,1,7.97900390625,318,56,1,7.3505859375,14,57,1,4.5322265625,315,58,1,7.00146484375,12,59,1,7.0966796875,12,60,1,8.201171875,320,61,1,7.9091796875,317,62,1,4.62744140625,315,63,1,8.07421875,318,64,1,7.67431640625,321,65,1,8.19482421875,322,66,1,8.2265625,323,67,1,8.201171875,316,68,1,7.75048828125,317,69,1,5.79541015625,324,70,1,7.3505859375,14,71,1,7.1982421875,13,72,1,7.9599609375,325,73,1,8.201171875,316,74,1,7.1982421875,13,75,1,5.9541015625,324,76,1,8.1123046875,326,77,1,8.07421875,318,78,1,4.627441406249943,315,79,1,8.2265625,323,80,1,7.9091796875,317,81,1,8.2900390625,322,82,1,7.3505859375,14,83,1,7.9091796875,327,84,1,8.201171875,316,85,1,4.62744140625,315,86,1,4.484619140625,315,87,1,7.207763671875,14,88,1,8.07421875,318,89,1,7.76953125,321,90,1,8.201171875,320,91,1,5.9541015625,324,92,1,7.1982421875,13,93,1,7.73779296875,321,94,1,7.16650390625,13,95,1,7.9853515625,326,96,1,7.10302734375,319,97,1,8.01708984375,326,98,1,5.9541015625,324,99,1,4.484619140625,315,100,1,7.207763671875,14,101,1,8.2900390625,322,102,1,7.1982421875,13,103,1,7.9599609375,325,104,1,7.0966796875,12,105,1,8.201171875,320,106,1,7.9091796875,327,107,1,7.9091796875,327,108,1,8.1123046875,326,109,1,8.201171875,316,110,1,8.2900390625,322,111,1,8.2900390625,322,112,1,3.884765625,310,113,1,9.8642578125,6,114,1,7.4775390625,7,115,1,4.875,8,116,1,6.982421875,9,117,1,3.884765625,310,118,1,7.3505859375,14,119,1,7.73779296875,321,120,1,7.31884765625,14,121,1,6.0556640625,328,122,1,9.2294921875,329,123,1,3.884765625,310,124,1,7.3505859375,14,125,1,11.2353515625,80,126,1,7.9091796875,317,127,1,7.3505859375,14,128,1,4.65283203125,8,129,1,3.66259765625,310,130,1,6.69677734375,10,131,1,4.61474609375,82,132,1,7.0966796875,12,133,1,4.646484375,82,134,1,3.1357421875,77,135,1,7.6044921875,7,136,1,7.50927734375,224,137,1,3.884765625,310,138,1,4.598876953125,82,139,1,7.302978515625,14,140,1,6.69677734375,10,141,1,4.61474609375,82,142,1,3.884765625,310,143,1,4.5322265625,315,144,1,7.00146484375,12,145,1,6.82373046875,9,146,1,7.19189453125,14,147,1,3.884765625,310,148,1,7.1982421875,13,149,1,7.6044921875,7,150,1,7.9091796875,327,151,1,7.2236328125,14,152,1,6.6142578125,79,153,1,13.075875486381392,287,154,1,12.89883268482481,280,155,1,12.89883268482481,281,156,1,12.89883268482481,154,157,1,12.89883268482481,282,158,1,3.580078125,-1,159,1,7.50927734375,224,160,1,7.8583984375,11,161,1,11.2353515625,80,162,1,3.580078125,-1,163,1,12.89883268482481,148,164,1,3.580078125,-1,165,1,9.572265625,330,166,1,7.6044921875,7,167,1,11.2353515625,80,168,1,7.3505859375,14,169,1,7.9091796875,317,170,1,4.77978515625,8,171,1,7.25537109375,14,172,1,9.9912109375,6,173,1,3.580078125,-1,174,1,12.89883268482481,283,175,1,12.89883268482481,284,176,1,13.075875486381392,287,177,1,12.89883268482481,142,178,1,12.89883268482481,1,179,1,12.89883268482481,331,180,1,12.89883268482481,332,181,1,12.89883268482481,333,182,1,12.89883268482481,334,183,1,12.89883268482481,335,184,1,12.89883268482481,336,185,1,12.89883268482481,291,186,1,12.89883268482481,150,187,1,13.075875486381392,292,188,1,12.89883268482481,306,189,1,12.89883268482481,307,190,1,12.89883268482481,308,191,1,12.89883268482481,150]}}
  #|{"textrec":{"s":[13,500,0,"0.2.1-rc.2"],"r":[0,1,8.090002655982971,208,1,1,3.6386033296585083,337,2,1,7.776639819145203,338,3,1,3.7105413675308228,337,4,1,5.945230960845947,339,5,1,6.116183757781982,340,6,1,5.043976902961731,341,7,1,7.241524338722229,342,8,1,3.9216055870056152,337,9,1,7.8543970584869385,338]}}
  #|{"textrec":{"s":[15,400,0,"DeepSeek Harness"],"r":[0,1,10.6640625,343,1,1,8.3349609375,95,2,1,8.3349609375,95,3,1,8.9208984375,92,4,1,9.32373046875,100,5,1,8.3349609375,95,6,1,8.3349609375,95,7,1,7.91015625,90,8,1,3.984375,-1,9,1,10.8984375,344,10,1,8.0419921875,93,11,1,5.5517578125,89,12,1,8.59130859375,103,13,1,8.3349609375,95,14,1,7.5439453125,91,15,1,7.5439453125,91]}}
  #|{"textrec":{"s":[13,400,0,"0.2.0"],"r":[0,1,7.8583984375,326,1,1,3.40234375,81,2,1,7.54736328125,321,3,1,3.43408203125,81,4,1,7.8583984375,326]}}
  #|{"textrec":{"s":[13,400,0,"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新"],"r":[0,1,12.898832684824903,283,1,1,12.898832684824903,284,2,1,12.898832684824903,1,3,1,3.580078125,-1,4,1,3.884765625,310,5,1,9.5087890625,311,6,1,6.728515625,10,7,1,7.350585937500007,14,8,1,4.8115234375,8,9,1,6.6650390625,10,10,1,3.884765625,310,11,1,6.931640625,312,12,1,7.50927734375,313,13,1,7.50927734375,7,14,1,6.83642578125,312,15,1,3.1357421875,77,16,1,3.12939453125,314,17,1,3.1357421875,77,18,1,7.0966796875,12,19,1,7.50927734375,224,20,1,3.630859375,310,21,1,3.529296875,81,22,1,6.69677734375,10,23,1,4.61474609375,82,24,1,3.1357421875,77,25,1,3.2119140625,76,26,1,3.2119140625,76,27,1,4.5322265625,315,28,1,7.00146484375,12,29,1,3.1357421875,77,30,1,3.2119140625,76,31,1,3.884765625,310,32,1,4.77978515625,8,33,1,7.25537109375,14,34,1,11.2353515625,80,35,1,7.6044921875,7,36,1,4.598876953125,82,37,1,7.302978515625,14,38,1,3.884765625,310,39,1,6.728515625,10,40,1,7.3505859375,14,41,1,6.6650390625,10,42,1,6.6650390625,10,43,1,3.1357421875,77,44,1,7.6044921875,7,45,1,7.50927734375,224,46,1,6.728515625,10,47,1,3.884765625,310,48,1,7.0966796875,12,49,1,7.1982421875,13,50,1,8.201171875,316,51,1,7.9091796875,317,52,1,8.07421875,318,53,1,4.62744140625,315,54,1,7.22998046875,319,55,1,7.97900390625,318,56,1,7.3505859375,14,57,1,4.5322265625,315,58,1,7.00146484375,12,59,1,7.0966796875,12,60,1,8.201171875,320,61,1,7.9091796875,317,62,1,4.62744140625,315,63,1,8.07421875,318,64,1,7.67431640625,321,65,1,8.19482421875,322,66,1,8.2265625,323,67,1,8.201171875,316,68,1,7.75048828125,317,69,1,5.79541015625,324,70,1,7.3505859375,14,71,1,7.1982421875,13,72,1,7.9599609375,325,73,1,8.201171875,316,74,1,7.1982421875,13,75,1,5.9541015625,324,76,1,8.1123046875,326,77,1,8.07421875,318,78,1,4.627441406249943,315,79,1,8.2265625,323,80,1,7.9091796875,317,81,1,8.2900390625,322,82,1,7.3505859375,14,83,1,7.9091796875,327,84,1,8.201171875,316,85,1,4.62744140625,315,86,1,4.484619140625,315,87,1,7.207763671875,14,88,1,8.07421875,318,89,1,7.76953125,321,90,1,8.201171875,320,91,1,5.9541015625,324,92,1,7.1982421875,13,93,1,7.73779296875,321,94,1,7.16650390625,13,95,1,7.9853515625,326,96,1,7.10302734375,319,97,1,8.01708984375,326,98,1,5.9541015625,324,99,1,4.484619140625,315,100,1,7.207763671875,14,101,1,8.2900390625,322,102,1,7.1982421875,13,103,1,7.9599609375,325,104,1,7.0966796875,12,105,1,8.201171875,320,106,1,7.9091796875,327,107,1,7.9091796875,327,108,1,8.1123046875,326,109,1,8.201171875,316,110,1,8.2900390625,322,111,1,8.2900390625,322,112,1,3.884765625,310,113,1,9.8642578125,6,114,1,7.4775390625,7,115,1,4.875,8,116,1,6.982421875,9,117,1,3.884765625,310,118,1,7.3505859375,14,119,1,7.73779296875,321,120,1,7.31884765625,14,121,1,6.0556640625,328,122,1,9.2294921875,329,123,1,3.884765625,310,124,1,7.3505859375,14,125,1,11.2353515625,80,126,1,7.9091796875,317,127,1,7.3505859375,14,128,1,4.65283203125,8,129,1,3.66259765625,310,130,1,6.69677734375,10,131,1,4.61474609375,82,132,1,7.0966796875,12,133,1,4.646484375,82,134,1,3.1357421875,77,135,1,7.6044921875,7,136,1,7.50927734375,224,137,1,3.884765625,310,138,1,4.598876953125,82,139,1,7.302978515625,14,140,1,6.69677734375,10,141,1,4.61474609375,82,142,1,3.884765625,310,143,1,4.5322265625,315,144,1,7.00146484375,12,145,1,6.82373046875,9,146,1,7.19189453125,14,147,1,3.884765625,310,148,1,7.9091796875,327,149,1,6.728515625,10,150,1,7.57275390625,345,151,1,13.075875486381278,287,152,1,12.898832684824924,280,153,1,12.89883268482481,281,154,1,12.89883268482481,154,155,1,12.89883268482481,282,156,1,3.580078125,-1,157,1,7.50927734375,224,158,1,7.8583984375,11,159,1,11.2353515625,80,160,1,3.580078125,-1,161,1,12.89883268482481,148,162,1,3.580078125,-1,163,1,9.572265625,330,164,1,7.6044921875,7,165,1,11.2353515625,80,166,1,7.3505859375,14,167,1,7.9091796875,317,168,1,4.77978515625,8,169,1,7.25537109375,14,170,1,9.9912109375,6,171,1,3.580078125,-1,172,1,12.89883268482481,283,173,1,12.89883268482481,284,174,1,13.075875486381392,287,175,1,12.89883268482481,142,176,1,12.89883268482481,1,177,1,12.89883268482481,331,178,1,12.89883268482481,332,179,1,12.89883268482481,333,180,1,12.89883268482481,334,181,1,12.89883268482481,335,182,1,12.89883268482481,336,183,1,12.89883268482481,291,184,1,12.89883268482481,150]}}
  #|{"textrec":{"s":[15,400,0,"Grok Build"],"r":[0,1,10.96435546875,346,1,1,5.36865234375,89,2,1,8.51806640625,88,3,1,7.91015625,90,4,1,3.984375,-1,5,1,9.6240234375,347,6,1,8.51806640625,163,7,1,3.4716796875,102,8,1,3.5595703125,108,9,1,8.9794921875,304]}}
  #|{"textrec":{"s":[13,400,0,"1.0.62"],"r":[0,1,5.79541015625,324,1,1,3.37060546875,81,2,1,7.6044921875,326,3,1,3.275390625,81,4,1,7.947265625,316,5,1,7.76953125,321]}}
  #|{"textrec":{"s":[13,400,0,"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新；已是最新"],"r":[0,1,12.898832684824903,283,1,1,12.898832684824903,284,2,1,12.898832684824903,1,3,1,3.580078125,-1,4,1,3.884765625,310,5,1,9.5087890625,311,6,1,6.728515625,10,7,1,7.350585937500007,14,8,1,4.8115234375,8,9,1,6.6650390625,10,10,1,3.884765625,310,11,1,6.931640625,312,12,1,7.50927734375,313,13,1,7.50927734375,7,14,1,6.83642578125,312,15,1,3.1357421875,77,16,1,3.12939453125,314,17,1,3.1357421875,77,18,1,7.0966796875,12,19,1,7.50927734375,224,20,1,3.630859375,310,21,1,3.529296875,81,22,1,6.69677734375,10,23,1,4.61474609375,82,24,1,3.1357421875,77,25,1,3.2119140625,76,26,1,3.2119140625,76,27,1,4.5322265625,315,28,1,7.00146484375,12,29,1,3.1357421875,77,30,1,3.2119140625,76,31,1,3.884765625,310,32,1,4.77978515625,8,33,1,7.25537109375,14,34,1,11.2353515625,80,35,1,7.6044921875,7,36,1,4.598876953125,82,37,1,7.302978515625,14,38,1,3.884765625,310,39,1,6.728515625,10,40,1,7.3505859375,14,41,1,6.6650390625,10,42,1,6.6650390625,10,43,1,3.1357421875,77,44,1,7.6044921875,7,45,1,7.50927734375,224,46,1,6.728515625,10,47,1,3.884765625,310,48,1,7.0966796875,12,49,1,7.1982421875,13,50,1,8.201171875,316,51,1,7.9091796875,317,52,1,8.07421875,318,53,1,4.62744140625,315,54,1,7.22998046875,319,55,1,7.97900390625,318,56,1,7.3505859375,14,57,1,4.5322265625,315,58,1,7.00146484375,12,59,1,7.0966796875,12,60,1,8.201171875,320,61,1,7.9091796875,317,62,1,4.62744140625,315,63,1,8.07421875,318,64,1,7.67431640625,321,65,1,8.19482421875,322,66,1,8.2265625,323,67,1,8.201171875,316,68,1,7.75048828125,317,69,1,5.79541015625,324,70,1,7.3505859375,14,71,1,7.1982421875,13,72,1,7.9599609375,325,73,1,8.201171875,316,74,1,7.1982421875,13,75,1,5.9541015625,324,76,1,8.1123046875,326,77,1,8.07421875,318,78,1,4.627441406249943,315,79,1,8.2265625,323,80,1,7.9091796875,317,81,1,8.2900390625,322,82,1,7.3505859375,14,83,1,7.9091796875,327,84,1,8.201171875,316,85,1,4.62744140625,315,86,1,4.484619140625,315,87,1,7.207763671875,14,88,1,8.07421875,318,89,1,7.76953125,321,90,1,8.201171875,320,91,1,5.9541015625,324,92,1,7.1982421875,13,93,1,7.73779296875,321,94,1,7.16650390625,13,95,1,7.9853515625,326,96,1,7.10302734375,319,97,1,8.01708984375,326,98,1,5.9541015625,324,99,1,4.484619140625,315,100,1,7.207763671875,14,101,1,8.2900390625,322,102,1,7.1982421875,13,103,1,7.9599609375,325,104,1,7.0966796875,12,105,1,8.201171875,320,106,1,7.9091796875,327,107,1,7.9091796875,327,108,1,8.1123046875,326,109,1,8.201171875,316,110,1,8.2900390625,322,111,1,8.2900390625,322,112,1,3.884765625,310,113,1,9.8642578125,6,114,1,7.4775390625,7,115,1,4.875,8,116,1,6.982421875,9,117,1,3.884765625,310,118,1,7.3505859375,14,119,1,7.73779296875,321,120,1,7.31884765625,14,121,1,6.0556640625,328,122,1,9.2294921875,329,123,1,3.884765625,310,124,1,7.3505859375,14,125,1,11.2353515625,80,126,1,7.9091796875,317,127,1,7.3505859375,14,128,1,4.65283203125,8,129,1,3.66259765625,310,130,1,6.69677734375,10,131,1,4.61474609375,82,132,1,7.0966796875,12,133,1,4.646484375,82,134,1,3.1357421875,77,135,1,7.6044921875,7,136,1,7.50927734375,224,137,1,3.884765625,310,138,1,4.598876953125,82,139,1,7.302978515625,14,140,1,6.69677734375,10,141,1,4.61474609375,82,142,1,3.884765625,310,143,1,4.5322265625,315,144,1,7.00146484375,12,145,1,6.82373046875,9,146,1,7.19189453125,14,147,1,3.884765625,310,148,1,7.845703125,223,149,1,4.77978515625,8,150,1,7.50927734375,7,151,1,6.982421875,9,152,1,13.075875486381278,287,153,1,12.898832684824924,280,154,1,12.89883268482481,281,155,1,12.89883268482481,154,156,1,12.89883268482481,282,157,1,3.580078125,-1,158,1,7.50927734375,224,159,1,7.8583984375,11,160,1,11.2353515625,80,161,1,3.580078125,-1,162,1,12.89883268482481,148,163,1,3.580078125,-1,164,1,9.572265625,330,165,1,7.6044921875,7,166,1,11.2353515625,80,167,1,7.3505859375,14,168,1,7.9091796875,317,169,1,4.77978515625,8,170,1,7.25537109375,14,171,1,9.9912109375,6,172,1,3.580078125,-1,173,1,12.89883268482481,283,174,1,12.89883268482481,284,175,1,13.075875486381392,287,176,1,12.89883268482481,142,177,1,12.89883268482481,1,178,1,12.89883268482481,331,179,1,12.89883268482481,332,180,1,12.89883268482481,333,181,1,12.89883268482481,334,182,1,12.89883268482481,335,183,1,12.89883268482481,336,184,1,12.89883268482481,291,185,1,12.89883268482481,150,186,1,13.075875486381392,292,187,1,12.89883268482481,306,188,1,12.89883268482481,307,189,1,12.89883268482481,308,190,1,12.89883268482481,150]}}
  #|{"textrec":{"g":154,"r":[1159,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":268,"r":[1175,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":269,"r":[1191,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":270,"r":[1206,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":271,"r":[1222,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":272,"r":[1238,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":273,"r":[1253,32,15,14,-1,-11,0]}}
  #|{"textrec":{"g":274,"r":[1269,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":275,"r":[1284,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":276,"r":[1302,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":277,"r":[1320,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":278,"r":[1335,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":279,"r":[1350,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":280,"r":[1366,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":281,"r":[1381,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":282,"r":[1397,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":283,"r":[1413,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":284,"r":[1428,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":285,"r":[1444,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":286,"r":[1459,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":287,"r":[1475,32,5,7,0,-3,0]}}
  #|{"textrec":{"g":288,"r":[1481,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":289,"r":[1496,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":290,"r":[1512,32,15,14,-1,-12,0]}}
  #|{"textrec":{"g":291,"r":[1528,32,15,14,-1,-11,0]}}
  #|{"textrec":{"g":150,"r":[1544,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":292,"r":[1560,32,5,11,1,-9,0]}}
  #|{"textrec":{"g":293,"r":[1566,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":294,"r":[1582,32,15,14,-1,-12,0]}}
  #|{"textrec":{"g":295,"r":[1598,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":296,"r":[1614,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":297,"r":[1630,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":298,"r":[1646,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":299,"r":[1661,32,7,11,-1.1666666666666634,-12,0]}}
  #|{"textrec":{"g":300,"r":[1669,32,7,11,-1,-8,0]}}
  #|{"textrec":{"g":301,"r":[1677,32,14,14,5.5,-12,0]}}
  #|{"textrec":{"g":302,"r":[1692,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":303,"r":[1708,32,12,14,-1,-12,0]}}
  #|{"textrec":{"g":163,"r":[1721,32,9,11,0,-9,0]}}
  #|{"textrec":{"g":304,"r":[1731,32,10,15,-1,-13,0]}}
  #|{"textrec":{"g":305,"r":[1742,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":155,"r":[1758,32,14,14,-1,-12,0]}}
  #|{"textrec":{"g":306,"r":[1773,32,13,13,0,-11,0]}}
  #|{"textrec":{"g":307,"r":[1787,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":308,"r":[1802,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":309,"r":[1817,32,10,10,-1,-9,0]}}
  #|{"textrec":{"g":310,"r":[1828,32,6,15,-1,-11,0]}}
  #|{"textrec":{"g":311,"r":[1835,32,10,13,0,-11,0]}}
  #|{"textrec":{"g":312,"r":[1846,32,9,9,-1,-8,0]}}
  #|{"textrec":{"g":313,"r":[1856,32,9,10,-1,-8,0]}}
  #|{"textrec":{"g":314,"r":[1866,32,6,15,-2,-11,0]}}
  #|{"textrec":{"g":315,"r":[1873,32,7,12,-1,-11,0]}}
  #|{"textrec":{"g":316,"r":[1881,32,10,13,-1,-11,0]}}
  #|{"textrec":{"g":317,"r":[1892,32,9,13,0,-11,0]}}
  #|{"textrec":{"g":318,"r":[1902,32,10,13,-1,-11,0]}}
  #|{"textrec":{"g":319,"r":[1913,32,9,12,-1,-11,0]}}
  #|{"textrec":{"g":320,"r":[1923,32,10,13,-1,-11,0]}}
  #|{"textrec":{"g":321,"r":[1934,32,9,12,-1,-11,0]}}
  #|{"textrec":{"g":322,"r":[1944,32,10,12,-1,-11,0]}}
  #|{"textrec":{"g":323,"r":[1955,32,10,13,-1,-11,0]}}
  #|{"textrec":{"g":324,"r":[1966,32,7,12,-1,-11,0]}}
  #|{"textrec":{"g":325,"r":[1974,32,10,13,-1,-11,0]}}
  #|{"textrec":{"g":326,"r":[1985,32,10,13,-1,-11,0]}}
  #|{"textrec":{"g":327,"r":[1996,32,9,13,-1,-11,0]}}
  #|{"textrec":{"g":328,"r":[2006,32,8,4,-1,-6,0]}}
  #|{"textrec":{"g":329,"r":[2015,32,11,13,-1,-11,0]}}
  #|{"textrec":{"g":148,"r":[2027,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":330,"r":[0,50,10,12,0,-11,0]}}
  #|{"textrec":{"g":142,"r":[11,50,14,14,-1,-11,0]}}
  #|{"textrec":{"g":331,"r":[26,50,15,15,-1,-12,0]}}
  #|{"textrec":{"g":332,"r":[42,50,15,15,-1,-12,0]}}
  #|{"textrec":{"g":333,"r":[58,50,15,14,-1,-11,0]}}
  #|{"textrec":{"g":334,"r":[74,50,14,14,-1,-12,0]}}
  #|{"textrec":{"g":335,"r":[89,50,15,15,-1,-12,0]}}
  #|{"textrec":{"g":336,"r":[105,50,14,15,-1,-12,0]}}
  #|{"textrec":{"g":343,"r":[120,50,11,13,0,-12,0]}}
  #|{"textrec":{"g":344,"r":[132,50,11,13,0,-12,0]}}
  #|{"textrec":{"g":208,"r":[144,50,10,13,-1,-11,0]}}
  #|{"textrec":{"g":337,"r":[155,50,4,5,0,-3,0]}}
  #|{"textrec":{"g":338,"r":[160,50,10,12,-1,-11,0]}}
  #|{"textrec":{"g":339,"r":[171,50,7,12,-1,-11,0]}}
  #|{"textrec":{"g":340,"r":[179,50,8,4,-1,-6,0]}}
  #|{"textrec":{"g":341,"r":[188,50,7,10,-1,-9,0]}}
  #|{"textrec":{"g":342,"r":[196,50,9,11,-1,-9,0]}}
  #|{"textrec":{"ib":["74432b445e567838",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"s":[17,700,0,"Agent 环境变量"],"r":[0,1,11.7705078125,348,1,1,10.288818359375,349,2,1,9.782470703125,350,3,1,10.230712890625,351,4,1,6.58251953125,352,5,1,3.951171875,-1,6,1,16.851167315175104,353,7,1,16.851167315175104,354,8,1,16.851167315175104,355,9,1,16.851167315175104,356]}}
  #|{"textrec":{"m":[17,700,0],"r":[16.435546875,3.5859375,24]}}
  #|{"textrec":{"s":[12,400,0,"此 station 启动的 agent、登录和任务都会加载这些变量，常用于设置 HTTP 代理。每行一个「变量名=值」，可直接粘贴 .env 内容，打码的值保持原样即不修改。Profile 中的同名变量优先。保存后，空闲的 agent 进程会重新启动，运行中的在本轮结束后生效。"],"r":[0,1,11.918287937743191,357,1,1,3.375,-1,2,1,6.251953125,358,3,1,4.330078125,359,4,1,6.6210937499999964,360,5,1,4.359375,359,6,1,2.96484375,361,7,1,7.08984375,362,8,1,7.001953125,363,9,1,3.375,-1,10,1,11.918287937743187,364,11,1,11.918287937743187,365,12,1,11.918287937743187,366,13,1,3.375,-1,14,1,6.62109375,360,15,1,7.3125,367,16,1,6.85546875,368,17,1,7.001953125,363,18,1,4.359375,359,19,1,12.081712062256798,369,20,1,11.918287937743202,370,21,1,11.918287937743202,371,22,1,11.918287937743202,372,23,1,11.918287937743202,373,24,1,11.918287937743202,374,25,1,11.918287937743202,375,26,1,11.918287937743202,376,27,1,11.918287937743202,377,28,1,11.918287937743202,378,29,1,11.918287937743173,379,30,1,11.918287937743173,380,31,1,11.918287937743173,381,32,1,11.918287937743173,382,33,1,12.081712062256827,383,34,1,11.918287937743173,384,35,1,11.918287937743173,385,36,1,11.918287937743173,386,37,1,11.918287937743173,387,38,1,11.918287937743173,388,39,1,3.375,-1,40,1,8.90625,389,41,1,7.60546875,390,42,1,7.60546875,390,43,1,7.623046875,391,44,1,3.375,-1,45,1,11.918287937743173,392,46,1,11.918287937743173,393,47,1,12.081712062256827,394,48,1,11.918287937743173,395,49,1,11.918287937743173,396,50,1,11.918287937743173,397,51,1,17.918287937743173,398,52,1,4.3540856031128214,399,53,1,11.918287937743173,381,54,1,11.918287937743173,382,55,1,11.91828793774323,400,56,1,7.55859375,401,57,1,11.91828793774323,402,58,1,5.608949416342398,403,59,1,12.08171206225677,383,60,1,11.91828793774323,404,61,1,11.91828793774323,405,62,1,11.91828793774323,194,63,1,11.91828793774323,406,64,1,11.91828793774323,407,65,1,3.375,-1,66,1,3.4453125,408,67,1,6.73828125,368,68,1,6.884765625,363,69,1,6.38671875,409,70,1,3.375,-1,71,1,11.91828793774323,410,72,1,11.91828793774323,411,73,1,12.08171206225677,383,74,1,11.91828793774323,412,75,1,11.91828793774323,413,76,1,11.91828793774323,366,77,1,11.91828793774323,402,78,1,11.91828793774323,414,79,1,11.91828793774323,415,80,1,11.91828793774323,416,81,1,11.91828793774323,417,82,1,11.91828793774323,418,83,1,11.91828793774323,419,84,1,11.91828793774323,420,85,1,11.91828793774323,421,86,1,12.08171206225677,394,87,1,7.623046875,391,88,1,4.482421875,422,89,1,7.001953125,362,90,1,4.341796875,423,91,1,2.96484375,361,92,1,3.03515625,424,93,1,6.85546875,368,94,1,3.375,-1,95,1,11.91828793774323,425,96,1,11.91828793774323,366,97,1,11.91828793774323,426,98,1,11.91828793774323,400,99,1,11.91828793774323,381,100,1,11.91828793774323,382,101,1,11.91828793774323,427,102,1,11.91828793774323,428,103,1,12.08171206225677,394,104,1,11.91828793774323,414,105,1,11.918287937743116,429,106,1,11.918287937743116,430,107,1,12.081712062256884,383,108,1,11.918287937743116,431,109,1,11.918287937743116,432,110,1,11.918287937743116,366,111,1,3.375,-1,112,1,6.62109375,360,113,1,7.3125,367,114,1,6.85546875,368,115,1,7.001953125,363,116,1,4.359375,359,117,1,3.375,-1,118,1,11.918287937743116,433,119,1,11.918287937743116,434,120,1,11.918287937743116,376,121,1,11.918287937743116,191,122,1,11.918287937743116,192,123,1,11.918287937743116,364,124,1,11.918287937743116,365,125,1,12.081712062256884,383,126,1,11.918287937743116,435,127,1,11.918287937743116,396,128,1,11.918287937743116,425,129,1,11.918287937743116,366,130,1,11.918287937743116,190,131,1,11.918287937743116,436,132,1,11.918287937743116,437,133,1,11.918287937743116,438,134,1,11.918287937743116,439,135,1,11.918287937743116,430,136,1,11.918287937743116,440,137,1,11.918287937743116,441,138,1,6.081712062256884,394]}}
  #|{"textrec":{"s":[14,600,0,"取消"],"r":[0,1,13.891050583657588,442,1,1,13.891050583657588,443]}}
  #|{"textrec":{"m":[14,600,0],"r":[13.53515625,2.953125,20]}}
  #|{"textrec":{"s":[14,600,0,"保存"],"r":[0,1,13.891050583657588,444,1,1,13.891050583657588,445]}}
  #|{"textrec":{"g":348,"r":[206,50,14,14,-1,-13,0]}}
  #|{"textrec":{"g":349,"r":[221,50,12,16,-1,-11,0]}}
  #|{"textrec":{"g":350,"r":[234,50,12,13,-1,-11,0]}}
  #|{"textrec":{"g":351,"r":[247,50,11,12,0,-11,0]}}
  #|{"textrec":{"g":352,"r":[259,50,9,15,-1,-13,0]}}
  #|{"textrec":{"g":353,"r":[269,50,18,18,-1,-15,0]}}
  #|{"textrec":{"g":354,"r":[288,50,19,18,-1,-15,0]}}
  #|{"textrec":{"g":355,"r":[308,50,18,18,-1,-15,0]}}
  #|{"textrec":{"g":356,"r":[327,50,18,18,-1,-15,0]}}
  #|{"textrec":{"g":357,"r":[346,50,14,13,-1,-11,0]}}
  #|{"textrec":{"g":358,"r":[361,50,8,10,-1,-8,0]}}
  #|{"textrec":{"g":359,"r":[370,50,6,11,-1,-9,0]}}
  #|{"textrec":{"g":360,"r":[377,50,8,10,-1,-8,0]}}
  #|{"textrec":{"g":361,"r":[386,50,5,11,-1,-10,0]}}
  #|{"textrec":{"g":362,"r":[392,50,9,10,-1,-8,0]}}
  #|{"textrec":{"g":363,"r":[402,50,9,9,-1,-8,0]}}
  #|{"textrec":{"g":364,"r":[412,50,13,14,-1,-11,0]}}
  #|{"textrec":{"g":365,"r":[426,50,13,14,-1,-11,0]}}
  #|{"textrec":{"g":366,"r":[440,50,13,14,-1,-11,0]}}
  #|{"textrec":{"g":367,"r":[454,50,9,12,-1,-8,0]}}
  #|{"textrec":{"g":368,"r":[464,50,9,10,-1,-8,0]}}
  #|{"textrec":{"g":369,"r":[474,50,6,6,0,-3,0]}}
  #|{"textrec":{"g":370,"r":[481,50,14,13,-1,-11,0]}}
  #|{"textrec":{"g":371,"r":[496,50,13,14,-1,-11,0]}}
  #|{"textrec":{"g":372,"r":[510,50,13,14,-1,-11,0]}}
  #|{"textrec":{"g":373,"r":[524,50,14,14,-1,-11,0]}}
  #|{"textrec":{"g":374,"r":[539,50,14,14,-1,-11,0]}}
  #|{"textrec":{"g":375,"r":[554,50,13,14,-1,-11,0]}}
  #|{"textrec":{"g":376,"r":[568,50,14,14,-1,-11,0]}}
  #|{"textrec":{"g":377,"r":[583,50,13,14,-1,-11,0]}}
  #|{"textrec":{"g":378,"r":[597,50,14,14,-1,-11,0]}}
  #|{"textrec":{"g":379,"r":[612,50,14,14,-1,-11,0]}}
  #|{"textrec":{"g":380,"r":[627,50,14,13,-1,-11,0]}}
  #|{"textrec":{"g":381,"r":[642,50,14,14,-1,-11,0]}}
  #|{"textrec":{"g":382,"r":[657,50,14,13,-1,-11,0]}}
  #|{"textrec":{"g":383,"r":[672,50,5,6,0,-3,0]}}
  #|{"textrec":{"g":384,"r":[678,50,13,14,-1,-11,0]}}
  #|{"textrec":{"g":385,"r":[692,50,13,14,-1,-11,0]}}
  #|{"textrec":{"g":386,"r":[706,50,13,14,-1,-11,0]}}
  #|{"textrec":{"g":387,"r":[720,50,14,14,-1,-11,0]}}
  #|{"textrec":{"g":388,"r":[735,50,14,13,-1,-11,0]}}
  #|{"textrec":{"g":389,"r":[750,50,9,11,0,-10,0]}}
  #|{"textrec":{"g":390,"r":[760,50,10,11,-1,-10,0]}}
  #|{"textrec":{"g":391,"r":[771,50,8,11,0,-10,0]}}
  #|{"textrec":{"g":392,"r":[780,50,14,14,-1,-11,0]}}
  #|{"textrec":{"g":393,"r":[795,50,14,13,-1,-11,0]}}
  #|{"textrec":{"g":394,"r":[810,50,6,6,0,-3,0]}}
  #|{"textrec":{"g":395,"r":[817,50,14,14,-1,-11,0]}}
  #|{"textrec":{"g":396,"r":[832,50,14,14,-1,-11,0]}}
  #|{"textrec":{"g":397,"r":[847,50,14,4,-1,-6,0]}}
  #|{"textrec":{"g":398,"r":[862,50,14,14,-1,-11,0]}}
  #|{"textrec":{"g":399,"r":[877,50,6,10,-0.9999999999999796,-11,0]}}
  #|{"textrec":{"g":400,"r":[884,50,13,14,-1,-11,0]}}
  #|{"textrec":{"g":401,"r":[898,50,9,7,-1,-7,0]}}
  #|{"textrec":{"g":402,"r":[908,50,14,14,-1,-11,0]}}
  #|{"textrec":{"g":403,"r":[923,50,7,10,-1,-7,0]}}
  #|{"textrec":{"g":404,"r":[931,50,14,13,-1,-10,0]}}
  #|{"textrec":{"g":405,"r":[946,50,14,13,-1,-11,0]}}
  #|{"textrec":{"g":406,"r":[961,50,14,14,-1,-11,0]}}
  #|{"textrec":{"g":407,"r":[976,50,14,14,-1,-11,0]}}
  #|{"textrec":{"g":408,"r":[991,50,4,5,0,-3,0]}}
  #|{"textrec":{"g":409,"r":[996,50,9,9,-1,-8,0]}}
  #|{"textrec":{"g":410,"r":[1006,50,12,14,0,-11,0]}}
  #|{"textrec":{"g":411,"r":[1019,50,14,14,-1,-11,0]}}
  #|{"textrec":{"g":412,"r":[1034,50,14,14,-1,-11,0]}}
  #|{"textrec":{"g":413,"r":[1049,50,13,14,-1,-11,0]}}
  #|{"textrec":{"g":414,"r":[1063,50,14,14,-1,-11,0]}}
  #|{"textrec":{"g":415,"r":[1078,50,14,14,-1,-11,0]}}
  #|{"textrec":{"g":416,"r":[1093,50,13,14,-1,-11,0]}}
  #|{"textrec":{"g":417,"r":[1107,50,14,14,-1,-11,0]}}
  #|{"textrec":{"g":418,"r":[1122,50,13,14,-1,-11,0]}}
  #|{"textrec":{"g":419,"r":[1136,50,14,13,-1,-10,0]}}
  #|{"textrec":{"g":420,"r":[1151,50,14,14,-1,-11,0]}}
  #|{"textrec":{"g":421,"r":[1166,50,14,14,-1,-11,0]}}
  #|{"textrec":{"g":422,"r":[1181,50,7,9,-1,-8,0]}}
  #|{"textrec":{"g":423,"r":[1189,50,6,11,-1,-10,0]}}
  #|{"textrec":{"g":424,"r":[1196,50,4,11,0,-10,0]}}
  #|{"textrec":{"g":425,"r":[1201,50,12,14,0,-11,0]}}
  #|{"textrec":{"g":426,"r":[1214,50,12,14,0,-11,0]}}
  #|{"textrec":{"g":427,"r":[1227,50,14,14,-1,-11,0]}}
  #|{"textrec":{"g":428,"r":[1242,50,14,14,-1,-11,0]}}
  #|{"textrec":{"g":429,"r":[1257,50,14,14,-1,-11,0]}}
  #|{"textrec":{"g":430,"r":[1272,50,14,14,-1,-11,0]}}
  #|{"textrec":{"g":431,"r":[1287,50,13,13,-1,-11,0]}}
  #|{"textrec":{"g":432,"r":[1301,50,12,14,0,-11,0]}}
  #|{"textrec":{"g":433,"r":[1314,50,14,14,-1,-11,0]}}
  #|{"textrec":{"g":434,"r":[1329,50,14,14,-1,-11,0]}}
  #|{"textrec":{"g":435,"r":[1344,50,14,14,-1,-11,0]}}
  #|{"textrec":{"g":436,"r":[1359,50,14,14,-1,-11,0]}}
  #|{"textrec":{"g":437,"r":[1374,50,14,14,-1,-11,0]}}
  #|{"textrec":{"g":438,"r":[1389,50,14,14,-1,-11,0]}}
  #|{"textrec":{"g":439,"r":[1404,50,14,14,-1,-11,0]}}
  #|{"textrec":{"g":440,"r":[1419,50,14,13,-1,-11,0]}}
  #|{"textrec":{"g":441,"r":[1434,50,14,14,-1,-11,0]}}
  #|{"textrec":{"s":[13,400,0,"HTTPS_PROXY=http://127.0.0.1:7890\nNO_PROXY=localhost,.internal"],"r":[0,1,9.572265625,330,1,1,8.1630859375,446,2,1,8.1630859375,446,3,1,8.18212890625,447,4,1,8.20751953125,448,5,1,7.50927734375,449,6,1,8.18212890625,447,7,1,8.4169921875,450,8,1,9.79443359375,451,9,1,8.58837890625,452,10,1,7.83935546875,453,11,1,7.50927734375,454,12,1,7.57275390625,345,13,1,4.646484375,82,14,1,4.646484375,82,15,1,7.8583984375,11,16,1,3.783203125,455,17,1,3.884765625,310,18,1,3.884765625,310,19,1,5.9541015625,324,20,1,7.76953125,321,21,1,6.626953125,319,22,1,2.8310546875,81,23,1,7.6044921875,326,24,1,3.275390625,81,25,1,7.6044921875,326,26,1,3.3388671875,81,27,1,5.763671875,324,28,1,3.7197265625,455,29,1,7.16650390625,319,30,1,8.13134765625,323,31,1,8.201171875,320,32,1,8.1123046875,326,33,1,0,-1,34,1,9.572265625,456,35,1,9.66748046875,451,36,1,7.2236328125,449,37,1,8.18212890625,447,38,1,8.4169921875,450,39,1,9.79443359375,451,40,1,8.58837890625,452,41,1,7.83935546875,453,42,1,7.50927734375,454,43,1,3.2119140625,76,44,1,7.6044921875,7,45,1,7.1982421875,13,46,1,7.0966796875,12,47,1,3.2119140625,76,48,1,7.57275390625,345,49,1,7.6044921875,7,50,1,6.69677734375,10,51,1,4.61474609375,82,52,1,3.783203125,457,53,1,3.783203125,81,54,1,3.1357421875,77,55,1,7.50927734375,224,56,1,4.598876953125,82,57,1,7.302978515625,14,58,1,4.9384765625,8,59,1,7.57275390625,224,60,1,7.0966796875,12,61,1,3.2119140625,76]}}
  #|{"textrec":{"g":446,"r":[1449,50,10,12,-1,-11,0]}}
  #|{"textrec":{"g":447,"r":[1460,50,9,12,0,-11,0]}}
  #|{"textrec":{"g":448,"r":[1470,50,10,13,-1,-11,0]}}
  #|{"textrec":{"g":449,"r":[1481,50,10,4,-1,-1,0]}}
  #|{"textrec":{"g":450,"r":[1492,50,9,12,0,-11,0]}}
  #|{"textrec":{"g":451,"r":[1502,50,12,13,-1,-11,0]}}
  #|{"textrec":{"g":452,"r":[1515,50,11,12,-1,-11,0]}}
  #|{"textrec":{"g":453,"r":[1527,50,11,12,-1,-11,0]}}
  #|{"textrec":{"g":454,"r":[1539,50,10,7,-1,-7,0]}}
  #|{"textrec":{"g":345,"r":[1550,50,8,12,0,-11,0]}}
  #|{"textrec":{"g":455,"r":[1559,50,4,10,0,-8,0]}}
  #|{"textrec":{"g":456,"r":[1564,50,10,12,0,-11,0]}}
  #|{"textrec":{"g":457,"r":[1575,50,5,7,-1,-3,0]}}
  #|{"textrec":{"g":442,"r":[1581,50,16,15,-1,-12,0]}}
  #|{"textrec":{"g":443,"r":[1598,50,15,16,-1,-13,0]}}
  #|{"textrec":{"g":444,"r":[1614,50,16,16,-1,-13,0]}}
  #|{"textrec":{"g":445,"r":[1631,50,16,16,-1,-13,0]}}
  #|{"textrec":{"s":[11,400,0,"在线"],"r":[0,1,10.93579766536965,458,1,1,10.93579766536965,459]}}
  #|{"textrec":{"m":[11,400,0],"r":[10.634765625,2.3203125,16]}}
  #|{"textrec":{"g":458,"r":[1648,50,13,13,-1,-10,0]}}
  #|{"textrec":{"g":459,"r":[1662,50,13,13,-1,-10,0]}}
  #|{"textrec":{"s":[15,600,0,"屏幕"],"r":[0,1,14.883268482490273,460,1,1,14.883268482490273,461]}}
  #|{"textrec":{"s":[15,400,0,"3720-Mac-mini-1"],"r":[0,1,9.169921875,462,1,1,8.3056640625,463,2,1,8.818359375,464,3,1,9.2138671875,164,4,1,6.8408203125,465,5,1,12.8759765625,466,6,1,8.0419921875,93,7,1,8.1591796875,94,8,1,6.8408203125,465,9,1,12.8173828125,161,10,1,3.4716796875,102,11,1,8.51806640625,103,12,1,3.4716796875,102,13,1,6.8408203125,465,14,1,6.7236328125,165]}}
  #|{"textrec":{"s":[13,400,0,"此 station 版本不含屏幕助手（stillfail-screen），请更新 station"],"r":[0,1,12.898832684824903,290,1,1,3.580078125,-1,2,1,6.69677734375,10,3,1,4.61474609375,82,4,1,7.0966796875,12,5,1,4.646484375,82,6,1,3.1357421875,77,7,1,7.6044921875,7,8,1,7.50927734375,224,9,1,3.580078125,-1,10,1,12.898832684824903,279,11,1,12.89883268482491,286,12,1,12.898832684824896,467,13,1,12.898832684824896,468,14,1,12.898832684824896,469,15,1,12.898832684824896,470,16,1,12.898832684824896,471,17,1,19.398832684824896,335,18,1,4.071984435797674,472,19,1,6.69677734375,10,20,1,4.61474609375,82,21,1,3.1357421875,77,22,1,3.2119140625,76,23,1,3.2119140625,76,24,1,4.5322265625,315,25,1,7.00146484375,12,26,1,3.1357421875,77,27,1,3.2119140625,76,28,1,6.0556640625,328,29,1,6.728515625,10,30,1,7.1982421875,13,31,1,4.77978515625,8,32,1,7.25537109375,14,33,1,7.3505859375,14,34,1,7.50927734375,224,35,1,5.456712062256827,473,36,1,13.075875486381335,287,37,1,12.898832684824924,474,38,1,12.898832684824924,291,39,1,12.898832684824924,150,40,1,3.580078125,-1,41,1,6.69677734375,10,42,1,4.61474609375,82,43,1,7.0966796875,12,44,1,4.646484375,82,45,1,3.1357421875,77,46,1,7.6044921875,7,47,1,7.50927734375,224]}}
  #|{"textrec":{"g":460,"r":[1676,50,16,16,-1,-13,0]}}
  #|{"textrec":{"g":461,"r":[1693,50,17,17,-1,-14,0]}}
  #|{"textrec":{"g":462,"r":[1711,50,10,14,0,-12,0]}}
  #|{"textrec":{"g":463,"r":[1722,50,10,13,-1,-12,0]}}
  #|{"textrec":{"g":464,"r":[1733,50,10,13,0,-12,0]}}
  #|{"textrec":{"g":164,"r":[1744,50,11,14,-1,-12,0]}}
  #|{"textrec":{"g":465,"r":[1756,50,7,4,0,-6,0]}}
  #|{"textrec":{"g":466,"r":[1764,50,13,13,0,-12,0]}}
  #|{"textrec":{"g":161,"r":[1778,50,13,11,0,-10,0]}}
  #|{"textrec":{"g":165,"r":[1792,50,8,13,-1,-12,0]}}
  #|{"textrec":{"g":467,"r":[1801,50,15,14,-1,-11,0]}}
  #|{"textrec":{"g":468,"r":[1817,50,15,15,-1,-12,0]}}
  #|{"textrec":{"g":469,"r":[1833,50,14,14,-1,-11,0]}}
  #|{"textrec":{"g":470,"r":[1848,50,15,15,-1,-12,0]}}
  #|{"textrec":{"g":471,"r":[1864,50,14,15,-1,-12,0]}}
  #|{"textrec":{"g":472,"r":[1879,50,5,15,-1.16666666666667,-12,0]}}
  #|{"textrec":{"g":473,"r":[1885,50,6,15,-1,-12,0]}}
  #|{"textrec":{"g":474,"r":[1892,50,15,15,-1,-12,0]}}
  #|{"textrec":{"ib":["dfa0b3408acf8bc7",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"s":[11,400,0,"Apple M4 · 16 GB · macOS 27.0.1"],"r":[0,1,7.4765625,475,1,1,6.7783203125,476,2,1,6.7783203125,476,3,1,2.8466796875,477,4,1,6.3486328125,478,5,1,3.158203125,-1,6,1,9.6787109375,479,7,1,7.1435546875,480,8,1,3.158203125,-1,9,1,5.2804038549793475,481,10,1,3.158203125,-1,11,1,5.166992187499993,482,12,1,7.068359375,483,13,1,3.158203125,-1,14,1,8.27685546875,484,15,1,7.2939453125,485,16,1,3.158203125,-1,17,1,5.28040385497934,481,18,1,3.158203125,-1,19,1,9.6357421875,486,20,1,6.1337890625,487,21,1,6.2197265625,488,22,1,8.55078125,489,23,1,7.07373046875,490,24,1,3.158203125,-1,25,1,6.703125,491,26,1,5.736328125,492,27,1,2.5244140625,493,28,1,6.5634765625,494,29,1,2.9541015625,493,30,1,5.005859375,482]}}
  #|{"textrec":{"g":475,"r":[1908,50,10,10,-1,-9,0]}}
  #|{"textrec":{"g":476,"r":[1919,50,9,10,-1,-7,0]}}
  #|{"textrec":{"g":477,"r":[1929,50,4,11,-1,-10,0]}}
  #|{"textrec":{"g":478,"r":[1934,50,8,9,-1,-7,0]}}
  #|{"textrec":{"g":479,"r":[1943,50,11,10,-1,-9,0]}}
  #|{"textrec":{"g":480,"r":[1955,50,9,10,-1,-9,0]}}
  #|{"textrec":{"g":481,"r":[1965,50,5,4,0,-6,0]}}
  #|{"textrec":{"g":482,"r":[1971,50,6,10,-1,-9,0]}}
  #|{"textrec":{"g":483,"r":[1978,50,9,11,-1,-9,0]}}
  #|{"textrec":{"g":484,"r":[1988,50,10,11,-1,-9,0]}}
  #|{"textrec":{"g":485,"r":[1999,50,9,10,-1,-9,0]}}
  #|{"textrec":{"g":486,"r":[2009,50,11,8,-1,-7,0]}}
  #|{"textrec":{"g":487,"r":[2021,50,8,9,-1,-7,0]}}
  #|{"textrec":{"g":488,"r":[2030,50,8,9,-1,-7,0]}}
  #|{"textrec":{"g":489,"r":[0,69,10,11,-1,-9,0]}}
  #|{"textrec":{"g":490,"r":[11,69,9,11,-1,-9,0]}}
  #|{"textrec":{"g":491,"r":[21,69,8,10,-1,-9,0]}}
  #|{"textrec":{"g":492,"r":[30,69,8,10,-1,-9,0]}}
  #|{"textrec":{"g":493,"r":[39,69,5,5,-1,-3,0]}}
  #|{"textrec":{"g":494,"r":[45,69,9,11,-1,-9,0]}}
  #|{"textrec":{"s":[13,400,0,"E2E_PROXY_080726=http://127.0.0.1:9"],"r":[0,1,7.66796875,495,1,1,7.76953125,321,2,1,7.66796875,495,3,1,7.50927734375,449,4,1,8.18212890625,447,5,1,8.4169921875,450,6,1,9.79443359375,451,7,1,8.58837890625,452,8,1,7.87109375,453,9,1,6.62060546875,449,10,1,7.794921875,326,11,1,8.2265625,323,12,1,7.9853515625,326,13,1,7.1982421875,319,14,1,7.76953125,321,15,1,8.201171875,316,16,1,8.1123046875,454,17,1,7.57275390625,345,18,1,4.646484375,82,19,1,4.646484375,82,20,1,7.8583984375,11,21,1,3.783203125,455,22,1,3.884765625,310,23,1,3.884765625,310,24,1,5.9541015625,324,25,1,7.76953125,321,26,1,6.626953125,319,27,1,2.8310546875,81,28,1,7.6044921875,326,29,1,3.275390625,81,30,1,7.6044921875,326,31,1,3.3388671875,81,32,1,5.763671875,324,33,1,3.783203125,455,34,1,8.201171875,320]}}
  #|{"textrec":{"g":495,"r":[55,69,8,12,0,-11,0]}}
  #|{"textrec":{"s":[14,400,0,"已保存"],"r":[0,1,13.891050583657588,496,1,1,13.891050583657588,497,2,1,13.891050583657588,498]}}
  #|{"textrec":{"g":496,"r":[64,69,14,14,0,-12,0]}}
  #|{"textrec":{"g":497,"r":[79,69,16,16,-1,-13,0]}}
  #|{"textrec":{"g":498,"r":[96,69,15,16,-1,-13,0]}}
  #|{"textrec":{"s":[15,400,2,"E2E_PROXY_080726"],"r":[0,1,9.2724609375,499,1,1,9.2724609375,500,2,1,9.2724609375,499,3,1,9.2724609375,501,4,1,9.2724609375,502,5,1,9.2724609375,503,6,1,9.2724609375,504,7,1,9.2724609375,505,8,1,9.2724609375,506,9,1,9.2724609375,501,10,1,9.2724609375,507,11,1,9.2724609375,508,12,1,9.2724609375,507,13,1,9.2724609375,509,14,1,9.2724609375,500,15,1,9.2724609375,510]}}
  #|{"textrec":{"m":[15,400,2],"r":[14.501953125,3.1640625,21]}}
  #|{"textrec":{"s":[13,400,2,"http://127.0.0.1:9"],"r":[0,1,8.0361328125,511,1,1,8.0361328125,512,2,1,8.0361328125,512,3,1,8.0361328125,513,4,1,8.0361328125,514,5,1,8.0361328125,515,6,1,8.0361328125,515,7,1,8.0361328125,516,8,1,8.0361328125,517,9,1,8.0361328125,518,10,1,8.0361328125,519,11,1,8.0361328125,520,12,1,8.0361328125,519,13,1,8.0361328125,520,14,1,8.0361328125,519,15,1,8.0361328125,516,16,1,8.0361328125,514,17,1,8.0361328125,521]}}
  #|{"textrec":{"m":[13,400,2],"r":[12.568359375,2.7421875,18]}}
  #|{"textrec":{"g":499,"r":[112,69,9,13,0,-12,0]}}
  #|{"textrec":{"g":500,"r":[122,69,10,13,0,-12,0]}}
  #|{"textrec":{"g":501,"r":[133,69,11,4,-1,0,0]}}
  #|{"textrec":{"g":502,"r":[145,69,10,13,0,-12,0]}}
  #|{"textrec":{"g":503,"r":[156,69,10,13,0,-12,0]}}
  #|{"textrec":{"g":504,"r":[167,69,11,14,-1,-12,0]}}
  #|{"textrec":{"g":505,"r":[179,69,11,13,-1,-12,0]}}
  #|{"textrec":{"g":506,"r":[191,69,11,13,-1,-12,0]}}
  #|{"textrec":{"g":507,"r":[203,69,10,14,0,-12,0]}}
  #|{"textrec":{"g":508,"r":[214,69,11,14,-1,-12,0]}}
  #|{"textrec":{"g":509,"r":[226,69,10,13,0,-12,0]}}
  #|{"textrec":{"g":510,"r":[237,69,10,14,0,-12,0]}}
  #|{"textrec":{"g":511,"r":[248,69,8,12,0,-11,0]}}
  #|{"textrec":{"g":512,"r":[257,69,8,12,0,-10,0]}}
  #|{"textrec":{"g":513,"r":[266,69,9,13,0,-9,0]}}
  #|{"textrec":{"g":514,"r":[276,69,6,11,1,-9,0]}}
  #|{"textrec":{"g":515,"r":[283,69,8,14,0,-12,0]}}
  #|{"textrec":{"g":516,"r":[292,69,9,12,0,-11,0]}}
  #|{"textrec":{"g":517,"r":[302,69,8,12,0,-11,0]}}
  #|{"textrec":{"g":518,"r":[311,69,9,12,0,-11,0]}}
  #|{"textrec":{"g":519,"r":[321,69,6,6,1,-4,0]}}
  #|{"textrec":{"g":520,"r":[328,69,10,13,-1,-11,0]}}
  #|{"textrec":{"g":521,"r":[339,69,10,12,-1,-11,0]}}
  #|{"textrec":{"g":346,"r":[350,69,13,14,-1,-12,0]}}
  #|{"textrec":{"g":347,"r":[364,69,11,13,0,-12,0]}}
  #|{"textrec":{"g":156,"r":[376,69,17,16,-1,-13,0]}}
  #|{"textrec":{"g":157,"r":[394,69,16,16,-1,-13,0]}}
  #|{"textrec":{"g":158,"r":[411,69,17,16,-1,-13,0]}}
  #|{"textrec":{"g":159,"r":[429,69,17,17,-1,-14,0]}}
  #|{"textrec":{"s":[15,400,0,"正在检查"],"r":[0,1,14.883268482490273,522,1,1,14.883268482490273,523,2,1,14.883268482490273,156,3,1,14.883268482490273,157]}}
  #|{"textrec":{"g":522,"r":[447,69,16,15,-1,-13,0]}}
  #|{"textrec":{"g":523,"r":[464,69,16,17,-1,-14,0]}}
