// e2e/traces/settings-profile.trace, made by scripts/trace.py from 01-settings_profile.run.log: not edited by hand.

///|
/// What the app and its core said in the run, a line each.
pub let trace_settings_profile : String =
  #|{"start":"base"}
  #|{"step":"drive-seed 080726"}
  #|{"env":{"MBUI_CLOUD":"http://127.0.0.1:18900","MBUI_CORE_ACCOUNT":"{\"sub\":\"alice\",\"email\":\"alice@example.test\",\"name\":\"Name of alice\",\"picture\":\"\",\"access\":\"-\",\"refresh\":\"-\",\"accessExpires\":1792537534}"}}
  #|{"out":{"id":1,"call":"client.device","params":{"client":"still.fail mbui","app":"desktop","userAgent":"Macintosh; Mac OS X"}},"w":1792537266152.893}
  #|{"in":{"id":1,"ok":null},"w":1792537266272.765}
  #|{"out":{"id":2,"subscribe":{"topic":"accounts"},"keyed":true},"w":1792537266272.791}
  #|{"out":{"id":3,"subscribe":{"topic":"prefs"},"keyed":true},"w":1792537266272.8}
  #|{"step":"# written by scripts/rerecord.sh from its test (src/sfreplay/emit.mbt): not edited by hand","w":1792537266274.197}
  #|{"step":"timeout 90000","w":1792537266274.205}
  #|{"step":"answered client.device","w":1792537266274.208}
  #|{"step":"answered client.focus","w":1792537266299.608}
  #|{"in":{"id":2,"value":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""}]},"w":1792537266349.318}
  #|{"in":{"id":3,"value":{"onlyMine":false,"onlyWatching":false,"onlyDecisions":false,"listFilter":{},"appearance":"system","rowPicture":"auto","absoluteTime":false,"lang":"zh","keys":{},"lastChat":{},"openChat":{},"chatTabs":{},"dropFiles":{},"driveViews":{},"resume":{},"stationUpdatesDismissed":{},"device":{"app":"desktop","phone":false,"handoff":false},"reader":{"size":18,"line":1.7,"margin":22,"face":"sans","indent":true,"paper":"follow"},"rails":{},"bars":{"sets":[["chats","files","profiles","stations"],["decisions","usage","connects","archive"]],"current":0},"barsBy":{}}},"w":1792537266349.361}
  #|{"out":{"id":4,"subscribe":{"topic":"workspaces"},"keyed":true},"w":1792537266349.411}
  #|{"out":{"id":5,"subscribe":{"topic":"status"},"keyed":true},"w":1792537266349.432}
  #|{"in":{"id":4,"value":[{"account":{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""},"workspaces":[{"id":"01M5DRPYX4418WR37BHVJ6FPTZ","name":"Dev","role":"owner","created_at":1792537230,"stations":1,"members":1,"relays":[],"time":{"created_at":{"past":true,"at":1792537230000,"ago":"刚刚","full":"10/21 07:00:30","until":"1 分钟内"}}}],"invitations":[],"relay_url":"http://127.0.0.1:18940","loaded":true,"beta":true}]},"w":1792537266365.987}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792537266366.002}
  #|{"out":{"id":6,"subscribe":{"topic":"lock","workspace":"01M5DRPYX4418WR37BHVJ6FPTZ"},"keyed":true},"w":1792537266366.051}
  #|{"out":{"id":7,"subscribe":{"topic":"chats","scope":"01M5DRPYX4418WR37BHVJ6FPTZ","mine":false},"keyed":true},"w":1792537266366.071}
  #|{"out":{"id":8,"subscribe":{"topic":"workspaceMarks","workspace":"01M5DRPYX4418WR37BHVJ6FPTZ"},"keyed":true},"w":1792537266366.217}
  #|{"out":{"id":9,"subscribe":{"topic":"status","workspace":"01M5DRPYX4418WR37BHVJ6FPTZ"},"keyed":true},"w":1792537266366.252}
  #|{"out":{"id":10,"call":"client.focus","params":{"visible":true,"focused":true,"workspace":"01M5DRPYX4418WR37BHVJ6FPTZ"}},"w":1792537266371.725}
  #|{"out":{"id":11,"subscribe":{"topic":"notify"},"keyed":true},"w":1792537266371.733}
  #|{"out":{"id":12,"subscribe":{"topic":"notify","workspace":"01M5DRPYX4418WR37BHVJ6FPTZ"},"keyed":true},"w":1792537266371.744}
  #|{"in":{"id":6,"value":{"available":true,"locked":false,"notice":true,"role":"owner","manages":true,"owner":true,"canSign":true,"signs":false,"me":{"device":"ac361e9a756c632009b68ba134099c39855124034dca05f66eab1e4ad93f3f7e","code":"WTQ-2Z8","kind":"app","confirmed":false,"waiting":false,"asked":false},"signers":0,"members":[],"stations":[{"id":"1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","name":"studio","version":"0.1.0","online":true,"protected":false}],"protected":0,"requests":[],"renew":[],"attention":0}},"w":1792537266383.499}
  #|{"in":{"id":7,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"stations":[{"station":"01M5DRPYX4418WR37BHVJ6FPTZ/1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","id":"1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","name":"studio","state":"online"}],"loading":false,"days":[{"daysAgo":0,"at":1792537234119,"label":"今天","items":[{"id":"ember:c-6701b915fb","session":"ember:c-6701b915fb","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","agents":[{"key":"ember:c-6701b915fb","runtime":"claude","process":"warm","pending":0,"lastTurn":{"id":"f8397996-f7e1-4dcd-a38d-89ece106af9b","kind":"input","outcome":"completed","declared":"final","ending":"all_done","need":"answered the question that was asked","startedAt":1792537234044,"endedAt":1792537234121},"agentText":"默认模型","statusText":"已完成：answered the question that was asked"}],"last":{"seq":2,"authorKind":"agent","author":"ember:c-6701b915fb","text":"你好，我是测试用的 agent","createdAt":1792537234119,"by":{"kind":"agent","name":"agent","mine":false,"runtime":"claude","label":"agent"},"preview":"你好，我是测试用的 agent","time":{"createdAt":{"at":1792537234119,"ago":"刚刚","full":"10/21 07:00:34","until":"1 分钟内","past":true}}},"unread":true,"mine":true,"lastActiveAt":1792537234119,"station":"01M5DRPYX4418WR37BHVJ6FPTZ/1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","stationName":"studio","time":{"lastActiveAt":{"at":1792537234119,"ago":"刚刚","full":"10/21 07:00:34","until":"1 分钟内","past":true}},"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"peopleText":"你 发起","clientKey":"new:chat-81c0c126917f8d1ed4","pinned":false,"tone":"done"}]}],"trouble":null,"members":1,"leading":"agents","glyph":{"online":1,"dim":0,"connecting":0,"failing":0,"working":0,"summary":"studio","label":"1 台 station，1 台在线"},"note":{"reading":false,"text":null,"failing":[],"empty":false}}},"w":1792537266383.53}
  #|{"in":{"id":8,"value":{"workspaces":{"01M5DRPYX4418WR37BHVJ6FPTZ":{"alert":0,"unread":1,"tone":"done","label":"1 个有新消息","badge":0,"items":[],"mineTone":"done"}},"badge":0,"badgeCounts":"attention","badgeKinds":{"on":true,"wait":true,"failed":true,"done":false,"message":false}}},"w":1792537266383.555}
  #|{"in":{"id":9,"value":{"items":[]}},"w":1792537266383.562}
  #|{"in":{"id":10,"ok":null},"w":1792537266383.564}
  #|{"in":{"id":11,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792537266383.576}
  #|{"in":{"id":12,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792537266383.58}
  #|{"out":{"id":13,"subscribe":{"topic":"longJobs","scope":"01M5DRPYX4418WR37BHVJ6FPTZ"},"keyed":true},"w":1792537266383.613}
  #|{"out":{"id":14,"call":"notify.permission","params":{"state":"unknown"}},"w":1792537266386.331}
  #|{"in":{"id":13,"value":{"groups":[]}},"w":1792537266399.32}
  #|{"in":{"id":14,"ok":null},"w":1792537266399.351}
  #|{"step":"answered notify.permission","w":1792537266399.694}
  #|{"step":"tap icon:settings","w":1792537266416.318}
  #|{"step":"tap icon:settings","acted":true,"w":1792537266432.957}
  #|{"out":{"id":15,"subscribe":{"topic":"workspace","workspace":"01M5DRPYX4418WR37BHVJ6FPTZ"},"keyed":true},"w":1792537266449.521}
  #|{"out":{"id":16,"subscribe":{"topic":"stations","scope":"01M5DRPYX4418WR37BHVJ6FPTZ"},"keyed":true},"w":1792537266449.544}
  #|{"out":{"id":17,"subscribe":{"topic":"connects","scope":"01M5DRPYX4418WR37BHVJ6FPTZ","mine":false},"keyed":true},"w":1792537266449.559}
  #|{"out":{"id":18,"subscribe":{"topic":"vaults","workspace":"01M5DRPYX4418WR37BHVJ6FPTZ"},"keyed":true},"w":1792537266449.566}
  #|{"out":{"id":19,"subscribe":{"topic":"doing"},"keyed":true},"w":1792537266454.837}
  #|{"step":"rest","w":1792537266455.911}
  #|{"in":{"id":15,"value":{"id":"01M5DRPYX4418WR37BHVJ6FPTZ","name":"Dev","role":"owner","created_at":1792537230,"members":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":"https://example.test/p.png","role":"owner","added_at":1792537230}],"stations":[{"id":"1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","name":"studio","emoji":null,"icon":null,"enrolled_at":1792537230,"enrolled_by":"alice","last_seen":1792537260,"version":"0.1.0","time":{"last_seen":{"past":true,"at":1792537260000,"ago":"刚刚","full":"10/21 07:01:00","until":"1 分钟内"}}}],"invitations":[],"added":[],"relays":[],"lock":null,"lock_requests":0,"time":{"created_at":{"past":true,"at":1792537230000,"ago":"刚刚","full":"10/21 07:00:30","until":"1 分钟内"}}}},"w":1792537266465.998}
  #|{"in":{"id":16,"value":[{"station":"01M5DRPYX4418WR37BHVJ6FPTZ/1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","id":"1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","name":"studio","summary":"正在连接","face":"idle","line":"在线","online":true,"reconnecting":true,"lastSeen":1792537260,"version":"0.1.0","link":{"state":"connecting"},"runtimes":[{"runtime":"claude","models":["claude-sonnet-5-5"]}],"models":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792537234017,"time":{"checkedAt":{"at":1792537234017,"ago":"刚刚","full":"10/21 07:00:34","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"overview":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null,"summaryText":"最近 7 天检查了 0 个 chat","changeText":null}},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","email":"alice@example.test","name":"Name of alice","sub":"alice","role":"owner","workspace":"01M5DRPYX4418WR37BHVJ6FPTZ","device":"ac361e9a756c632009b68ba134099c39855124034dca05f66eab1e4ad93f3f7e"},"connects":[],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792537233915,"time":{"checkedAt":{"at":1792537233915,"ago":"刚刚","full":"10/21 07:00:33","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792537234017,"time":{"checkedAt":{"at":1792537234017,"ago":"刚刚","full":"10/21 07:00:34","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]}],"processes":[],"counts":{"sessions":1,"running":0,"warm":1},"mesh":{"state":"running","origin":"http://127.0.0.1:18900","station":"1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","workspace":"Dev","workspaceId":"01M5DRPYX4418WR37BHVJ6FPTZ","name":"studio"},"slackUsers":[],"slackTeams":[],"slackApps":[],"feishuRegistrations":[],"disk":{"freeBytes":57871659008,"totalBytes":245107195904},"logins":[],"machineLogins":[{"runtime":"claude","installed":true,"loggedIn":false,"usable":false,"text":"无法读取 Claude Code 的登录信息","offered":false},{"runtime":"codex","installed":true,"loggedIn":false,"usable":false,"text":"Codex 未登录","offered":false}],"sharing":true,"consoleSignIn":true,"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"google","name":"Google Gemini","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xai","name":"xAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"mistral","name":"Mistral","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"deepseek","name":"DeepSeek","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen","name":"Qwen","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai","name":"Kimi","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai","name":"Z.ai","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax","name":"MiniMax","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ant-ling","name":"Ant Ling","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"jev","name":"Jev","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen-cn","name":"Qwen (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"openrouter","name":"OpenRouter","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"opencode","name":"OpenCode Zen","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"groq","name":"Groq","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"together","name":"Together AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"fireworks","name":"Fireworks","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cerebras","name":"Cerebras","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"huggingface","name":"Hugging Face","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"nvidia","name":"NVIDIA","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"baseten","name":"Baseten","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ollama","name":"Ollama","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"custom","name":"Custom","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""}],"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792537231526},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.305","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792537231526},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792537231526},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792537231526},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","latest":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792537231526}],"processesText":"没有运行中的 agent 进程","agentEnv":[],"drive":{"roots":[],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false}},"betaOffered":false,"time":{"lastSeen":{"at":1792537260000,"ago":"刚刚","full":"10/21 07:01:00","until":"1 分钟内","past":true}},"joined":false}]},"w":1792537266466.145}
  #|{"in":{"id":17,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"items":[],"wait":{"reading":false,"text":null,"failing":[],"empty":true}}},"w":1792537266466.245}
  #|{"in":{"id":18,"value":{"available":true,"locked":false,"canSign":false,"setUp":false,"vaults":[{"id":"plain","name":"个人","owner":"alice","ownerName":"Name of alice","mine":true,"members":[{"sub":"alice","name":"Name of alice"}],"station":"1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","stationName":"studio","items":0,"devices":0,"open":true,"keyed":true,"missing":0,"recoverable":false}],"requests":[],"refused":[{"station":"1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","name":"studio","code":"vault_needs_lock"}],"plain":true}},"w":1792537266466.254}
  #|{"in":{"id":19,"value":{"doing":[]}},"w":1792537266466.262}
  #|{"step":"now tap =Profile","w":1792537267216.718}
  #|{"step":"now tap =Profile","acted":true,"w":1792537267233.65}
  #|{"out":{"id":20,"subscribe":{"topic":"profiles","scope":"01M5DRPYX4418WR37BHVJ6FPTZ"},"keyed":true},"w":1792537267250.287}
  #|{"step":"rest","w":1792537267253.072}
  #|{"in":{"id":20,"value":{"items":[{"key":"01M5DRPYX4418WR37BHVJ6FPTZ/1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3/cc","group":"key","groupTitle":"API Key","station":"01M5DRPYX4418WR37BHVJ6FPTZ/1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","stationId":"1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","stationName":"studio","profile":{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792537233915,"time":{"checkedAt":{"at":1792537233915,"ago":"刚刚","full":"10/21 07:00:33","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792537234017,"time":{"checkedAt":{"at":1792537234017,"ago":"刚刚","full":"10/21 07:00:34","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]},"shared":false,"host":"1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","hostName":"studio","hostOnline":true,"usable":true,"where":"仅在 studio","stations":[{"id":"1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","station":"01M5DRPYX4418WR37BHVJ6FPTZ/1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","name":"studio","online":true,"allowed":true}],"editable":true,"canShare":true,"members":[{"station":"01M5DRPYX4418WR37BHVJ6FPTZ/1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","stationId":"1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","stationName":"studio","online":true,"profileId":"cc","role":"own","about":"此 station 自有的 key","usable":true,"checkText":"无法检查","checkTone":"neutral","usedBy":0}]}],"wait":{"reading":false,"text":null,"failing":[],"empty":false}}},"w":1792537267266.11}
  #|{"step":"now tap =cc","w":1792537267583.18}
  #|{"step":"now tap =cc","acted":true,"w":1792537267599.902}
  #|{"out":{"id":21,"subscribe":{"topic":"memberships","station":"01M5DRPYX4418WR37BHVJ6FPTZ/1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3"},"keyed":true},"w":1792537267618.559}
  #|{"step":"rest","w":1792537267629.899}
  #|{"in":{"id":21,"value":{"manages":true,"loading":true,"canJoin":false,"workspaces":[]}},"w":1792537267632.655}
  #|{"step":"now until 使用它的连接","w":1792537267950.154}
  #|{"step":"tap icon:more","w":1792537267950.197}
  #|{"step":"tap icon:more","acted":true,"w":1792537267966.991}
  #|{"step":"rest","w":1792537267988.421}
  #|{"in":{"id":5,"value":{"state":"slow","text":"正在连接 studio ×3 · 2 秒 · 共 5 项","items":[{"state":"slow","text":"正在连接 studio ×3","detail":"已等待 2 秒"},{"state":"slow","text":"studio 打开实时更新 ×2","detail":"已等待 2 秒，尚未收到数据"}]}},"w":1792537268599.346}
  #|{"in":{"id":9,"value":{"state":"slow","text":"正在连接 studio ×3 · 2 秒 · 共 5 项","items":[{"state":"slow","text":"正在连接 studio ×3","detail":"已等待 2 秒"},{"state":"slow","text":"studio 打开实时更新 ×2","detail":"已等待 2 秒，尚未收到数据"}]}},"w":1792537268599.426}
  #|{"in":{"id":5,"value":{"state":"slow","text":"studio 打开实时更新 ×2 · 3 秒 · 共 2 项 · 283 B/s","items":[{"state":"slow","text":"studio 打开实时更新 ×2","detail":"已等待 3 秒，尚未收到数据"}]}},"w":1792537269282.638}
  #|{"in":{"id":9,"value":{"state":"slow","text":"studio 打开实时更新 ×2 · 3 秒 · 共 2 项 · 283 B/s","items":[{"state":"slow","text":"studio 打开实时更新 ×2","detail":"已等待 3 秒，尚未收到数据"}]}},"w":1792537269282.68}
  #|{"in":{"id":21,"value":{"manages":true,"loading":false,"canJoin":true,"workspaces":[{"workspace":"01M5DRPYX4418WR37BHVJ6FPTZ","name":"Dev","stationName":"studio","home":true,"here":true,"line":"主 workspace"}]}},"w":1792537269282.699}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792537269332.611}
  #|{"in":{"id":9,"value":{"items":[]}},"w":1792537269332.624}
  #|{"in":{"id":16,"delta":[{"path":[0,"link","state"],"set":"online"},{"path":[0,"overview","counts","warm"],"set":0},{"path":[0,"overview","disk","freeBytes"],"set":57865101312},{"path":[0,"overview","machineLogins"],"set":[]},{"path":[0,"overview","profiles",0,"check","checkedAt"],"set":1792537269161},{"path":[0,"overview","profiles",0,"check","time","checkedAt","at"],"set":1792537269161},{"path":[0,"overview","profiles",0,"check","time","checkedAt","full"],"set":"10/21 07:01:09"},{"path":[0,"overview","updates",0,"checkedAt"],"set":1792537266754},{"path":[0,"overview","updates",1,"checkedAt"],"set":1792537266754},{"path":[0,"overview","updates",2,"checkedAt"],"set":1792537266754},{"path":[0,"overview","updates",3,"checkedAt"],"set":1792537266754},{"path":[0,"overview","updates",4,"checkedAt"],"set":1792537266754},{"path":[0,"reconnecting"],"set":false}]},"w":1792537269332.635}
  #|{"in":{"id":20,"delta":[{"path":["items",0,"profile","check","checkedAt"],"set":1792537269161},{"path":["items",0,"profile","check","time","checkedAt","at"],"set":1792537269161},{"path":["items",0,"profile","check","time","checkedAt","full"],"set":"10/21 07:01:09"}]},"w":1792537269332.672}
  #|{"in":{"id":16,"delta":[{"path":[0,"host"],"set":{"hostname":"3720-Mac-mini-1","os":"macOS 27.0.1","arch":"arm64","cpus":10,"cpuModel":"Apple M4","load":0.86,"cpuBusy":0.11,"uptimeSec":16631,"memory":{"totalBytes":17179869184,"usedBytes":9794109440,"swapUsedBytes":325184389},"disk":{"path":"/tmp/mbe2e-C/data","totalBytes":245107195904,"freeBytes":57865031680},"emberRssBytes":140064400,"checkedAt":1792537269324,"summary":"10 核 · 16 GB","line":"macOS 27.0.1 · 10 核 · 16 GB · 已运行 0 天","facts":["3720-Mac-mini-1","macOS 27.0.1","arm64 · 10 核","已运行 4 小时"],"meters":[{"label":"CPU","short":"CPU","percent":11,"left":89,"level":"ok","value":"11%","remaining":"空闲 89%","big":"89","unit":"%","title":"CPU 空闲","total":"负载 8.6","note":"负载 8.6 · Apple M4"},{"label":"内存","short":"内存","percent":57,"left":43,"level":"ok","value":"9.1 GB / 16.0 GB","remaining":"剩 6.9 G","big":"6.9","unit":"GB","title":"内存剩","total":"共 16 GB","note":"swap 0.3 GB"},{"label":"磁盘","short":"磁盘","percent":76,"left":24,"level":"amber","value":"剩余 53.9 GB / 228 GB","remaining":"剩 53.9 G","big":"53.9","unit":"GB","title":"磁盘剩","total":"共 228 GB"}],"identity":"Apple M4 · 16 GB · macOS 27.0.1","details":[{"label":"主机名","value":"3720-Mac-mini-1"},{"label":"芯片","value":"Apple M4 · 10 核 · arm64"},{"label":"已运行","value":"4 小时"},{"label":"still.fail","value":"进程占用 134 MB"}],"usage":"内存 9.1 GB / 16.0 GB · 磁盘 剩余 53.9 GB / 228 GB","emberText":"still.fail 134 MB"}},{"path":[0,"line"],"set":"Apple M4"},{"path":[0,"summary"],"set":"空闲 · Apple M4 · 16 GB · macOS 27.0.1"}]},"w":1792537269399.303}
  #|{"in":{"id":7,"delta":[{"path":["days"],"key":["daysAgo"],"patch":0,"ops":[{"path":["items"],"key":["station","id"],"patch":["01M5DRPYX4418WR37BHVJ6FPTZ/1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","ember:c-6701b915fb"],"ops":[{"path":["agents",0,"process"],"set":"cold"},{"path":["clientKey"],"remove":true}]}]}]},"w":1792537269399.348}
  #|{"step":"now tap =重命名","w":1792537269432.817}
  #|{"step":"now tap =重命名","acted":true,"w":1792537269449.532}
  #|{"step":"rest","w":1792537269466.251}
  #|{"step":"now until Profile 名称","w":1792537270816.996}
  #|{"step":"clear","w":1792537270817.03}
  #|{"step":"clear","acted":true,"w":1792537270817.092}
  #|{"step":"type e2e-080726","w":1792537270834.675}
  #|{"step":"type e2e-080726","acted":true,"w":1792537270834.705}
  #|{"step":"tap =保存","w":1792537270851.726}
  #|{"step":"tap =保存","acted":true,"w":1792537270866.949}
  #|{"out":{"id":22,"call":"profile.put","params":{"station":"01M5DRPYX4418WR37BHVJ6FPTZ/1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","id":"cc","input":{"name":"e2e-080726"}}},"w":1792537270882.895}
  #|{"step":"answered profile.put","w":1792537270883.919}
  #|{"in":{"id":16,"delta":[{"path":[0,"way"],"set":{"path":"直连","via":"direct"}}]},"w":1792537270899.313}
  #|{"in":{"id":19,"value":{"doing":[{"call":"profile.put","params":{"station":"01M5DRPYX4418WR37BHVJ6FPTZ/1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","id":"cc"},"since":1792537270883,"stage":"running"}]}},"w":1792537270899.378}
  #|{"in":{"id":22,"ok":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null},"canEditPolicy":true},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","sub":"alice","email":"alice@example.test","name":"Name of alice","role":"owner","workspace":"01M5DRPYX4418WR37BHVJ6FPTZ","device":"ac361e9a756c632009b68ba134099c39855124034dca05f66eab1e4ad93f3f7e","lockDevice":{"base":"ac361e9a756c632009b68ba134099c39855124034dca05f66eab1e4ad93f3f7e","proof":"ddbb76f6a4b862e9009ef1d4dff22f183124741c803b98dd5bcbc19e29522eb6b55cccddc8b5406002e49317c550f5580865fa668a4979387431f19805d15609"},"home":true},"mesh":{"state":"running","origin":"http://127.0.0.1:18900","station":"1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","workspace":"Dev","workspaceId":"01M5DRPYX4418WR37BHVJ6FPTZ","name":"studio"},"connects":[],"profiles":[{"id":"cc","name":"e2e-080726","runtime":"claude","runtimes":["claude"],"email":null,"access":{"kind":"env","key":"","provider":null,"endpoint":null,"protocol":null,"login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"model":null,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"fast":null,"check":{"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","models":null,"checkedAt":1792537269161,"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口","reason":"no_probabilities","model":null,"provider":null,"models":[]}},"login":null,"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792537234017},"share":null,"workspaces":[]}],"footprint":null,"processes":[],"counts":{"sessions":1,"running":0,"warm":0},"slackUsers":[],"slackTeams":[],"disk":{"freeBytes":57862975488,"totalBytes":245107195904},"logins":[],"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs"},{"id":"google","name":"Google Gemini","group":"labs"},{"id":"xai","name":"xAI","group":"labs"},{"id":"mistral","name":"Mistral","group":"labs"},{"id":"deepseek","name":"DeepSeek","group":"labs"},{"id":"qwen","name":"Qwen","group":"labs"},{"id":"moonshotai","name":"Kimi","group":"labs"},{"id":"zai","name":"Z.ai","group":"labs"},{"id":"minimax","name":"MiniMax","group":"labs"},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs"},{"id":"ant-ling","name":"Ant Ling","group":"labs"},{"id":"jev","name":"Jev","group":"labs"},{"id":"qwen-cn","name":"Qwen (China)","group":"labs"},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs"},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs"},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs"},{"id":"openrouter","name":"OpenRouter","group":"gateways"},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways"},{"id":"opencode","name":"OpenCode Zen","group":"gateways"},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways"},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted"},{"id":"groq","name":"Groq","group":"hosted"},{"id":"together","name":"Together AI","group":"hosted"},{"id":"fireworks","name":"Fireworks","group":"hosted"},{"id":"cerebras","name":"Cerebras","group":"hosted"},{"id":"huggingface","name":"Hugging Face","group":"hosted"},{"id":"nvidia","name":"NVIDIA","group":"hosted"},{"id":"baseten","name":"Baseten","group":"hosted"},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted"},{"id":"ollama","name":"Ollama","group":"local"},{"id":"custom","name":"Custom","group":"local"}],"machineLogins":[],"consoleSignIn":true,"sharing":true,"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792537266754},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.305","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792537266754},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792537266754},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792537266754},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","latest":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792537266754}],"slackApps":[],"agentEnv":[],"drive":{"roots":[],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false},"feedback":true,"feishuRegistrations":[]}},"w":1792537270932.648}
  #|{"step":"until 已重命名","w":1792537270950.352}
  #|{"step":"rest","w":1792537270950.368}
  #|{"in":{"id":19,"value":{"doing":[]}},"w":1792537271015.962}
  #|{"in":{"id":16,"delta":[{"path":[0,"models",0,"accounts","claude",0,"name"],"set":"e2e-080726"},{"path":[0,"overview","disk","freeBytes"],"set":57862975488},{"path":[0,"overview","profiles",0,"name"],"set":"e2e-080726"}]},"w":1792537271016.014}
  #|{"in":{"id":20,"delta":[{"path":["items",0,"profile","name"],"set":"e2e-080726"}]},"w":1792537271016.069}
  #|{"step":"now until =e2e-080726","w":1792537272332.87}
  #|{"step":"tap icon:more","w":1792537272332.879}
  #|{"step":"tap icon:more","acted":true,"w":1792537272349.463}
  #|{"step":"rest","w":1792537272367.036}
  #|{"step":"now tap 重新检查","w":1792537273834.206}
  #|{"step":"now tap 重新检查","acted":true,"w":1792537273867.083}
  #|{"out":{"id":23,"call":"profile.check","params":{"station":"01M5DRPYX4418WR37BHVJ6FPTZ/1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","id":"cc"}},"w":1792537273882.948}
  #|{"step":"answered profile.check","w":1792537273883.799}
  #|{"in":{"id":23,"ok":{"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","models":null,"checkedAt":1792537273887,"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口","reason":"no_probabilities","model":null,"provider":null,"models":[],"fingerprint":"e3621a9191e007ebda98bf119f3017d5d9700c79c1c7a1cfd209306fc68d4458"}}},"w":1792537273915.937}
  #|{"step":"tap icon:more","w":1792537273933.363}
  #|{"step":"tap icon:more","acted":true,"w":1792537273949.882}
  #|{"step":"rest","w":1792537273967.224}
  #|{"in":{"id":16,"delta":[{"path":[0,"overview","disk","freeBytes"],"set":57986940928},{"path":[0,"overview","profiles",0,"check","checkedAt"],"set":1792537273887},{"path":[0,"overview","profiles",0,"check","time","checkedAt","at"],"set":1792537273887},{"path":[0,"overview","profiles",0,"check","time","checkedAt","full"],"set":"10/21 07:01:13"}]},"w":1792537274099.282}
  #|{"in":{"id":20,"delta":[{"path":["items",0,"profile","check","checkedAt"],"set":1792537273887},{"path":["items",0,"profile","check","time","checkedAt","at"],"set":1792537273887},{"path":["items",0,"profile","check","time","checkedAt","full"],"set":"10/21 07:01:13"}]},"w":1792537274099.386}
  #|{"step":"now tap =重命名","w":1792537275416.856}
  #|{"step":"now tap =重命名","acted":true,"w":1792537275433.585}
  #|{"step":"rest","w":1792537275450.202}
  #|{"step":"now clear","w":1792537276800.751}
  #|{"step":"now clear","acted":true,"w":1792537276800.808}
  #|{"step":"type cc","w":1792537276817.422}
  #|{"step":"type cc","acted":true,"w":1792537276817.462}
  #|{"step":"tap =保存","w":1792537276834.162}
  #|{"step":"tap =保存","acted":true,"w":1792537276850.848}
  #|{"out":{"id":24,"call":"profile.put","params":{"station":"01M5DRPYX4418WR37BHVJ6FPTZ/1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","id":"cc","input":{"name":"cc"}}},"w":1792537276866.418}
  #|{"step":"answered profile.put","w":1792537276867.697}
  #|{"in":{"id":24,"ok":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null},"canEditPolicy":true},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","sub":"alice","email":"alice@example.test","name":"Name of alice","role":"owner","workspace":"01M5DRPYX4418WR37BHVJ6FPTZ","device":"ac361e9a756c632009b68ba134099c39855124034dca05f66eab1e4ad93f3f7e","lockDevice":{"base":"ac361e9a756c632009b68ba134099c39855124034dca05f66eab1e4ad93f3f7e","proof":"ddbb76f6a4b862e9009ef1d4dff22f183124741c803b98dd5bcbc19e29522eb6b55cccddc8b5406002e49317c550f5580865fa668a4979387431f19805d15609"},"home":true},"mesh":{"state":"running","origin":"http://127.0.0.1:18900","station":"1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","workspace":"Dev","workspaceId":"01M5DRPYX4418WR37BHVJ6FPTZ","name":"studio"},"connects":[],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"email":null,"access":{"kind":"env","key":"","provider":null,"endpoint":null,"protocol":null,"login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"model":null,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"fast":null,"check":{"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","models":null,"checkedAt":1792537273887,"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口","reason":"no_probabilities","model":null,"provider":null,"models":[]}},"login":null,"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792537234017},"share":null,"workspaces":[]}],"footprint":null,"processes":[],"counts":{"sessions":1,"running":0,"warm":0},"slackUsers":[],"slackTeams":[],"disk":{"freeBytes":57944289280,"totalBytes":245107195904},"logins":[],"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs"},{"id":"google","name":"Google Gemini","group":"labs"},{"id":"xai","name":"xAI","group":"labs"},{"id":"mistral","name":"Mistral","group":"labs"},{"id":"deepseek","name":"DeepSeek","group":"labs"},{"id":"qwen","name":"Qwen","group":"labs"},{"id":"moonshotai","name":"Kimi","group":"labs"},{"id":"zai","name":"Z.ai","group":"labs"},{"id":"minimax","name":"MiniMax","group":"labs"},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs"},{"id":"ant-ling","name":"Ant Ling","group":"labs"},{"id":"jev","name":"Jev","group":"labs"},{"id":"qwen-cn","name":"Qwen (China)","group":"labs"},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs"},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs"},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs"},{"id":"openrouter","name":"OpenRouter","group":"gateways"},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways"},{"id":"opencode","name":"OpenCode Zen","group":"gateways"},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways"},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted"},{"id":"groq","name":"Groq","group":"hosted"},{"id":"together","name":"Together AI","group":"hosted"},{"id":"fireworks","name":"Fireworks","group":"hosted"},{"id":"cerebras","name":"Cerebras","group":"hosted"},{"id":"huggingface","name":"Hugging Face","group":"hosted"},{"id":"nvidia","name":"NVIDIA","group":"hosted"},{"id":"baseten","name":"Baseten","group":"hosted"},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted"},{"id":"ollama","name":"Ollama","group":"local"},{"id":"custom","name":"Custom","group":"local"}],"machineLogins":[],"consoleSignIn":true,"sharing":true,"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792537266754},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.305","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792537266754},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792537266754},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792537266754},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","latest":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792537266754}],"slackApps":[],"agentEnv":[],"drive":{"roots":[],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false},"feedback":true,"feishuRegistrations":[]}},"w":1792537276915.936}
  #|{"in":{"id":16,"delta":[{"path":[0,"models",0,"accounts","claude",0,"name"],"set":"cc"},{"path":[0,"overview","disk","freeBytes"],"set":57944289280},{"path":[0,"overview","profiles",0,"name"],"set":"cc"}]},"w":1792537276932.553}
  #|{"in":{"id":20,"delta":[{"path":["items",0,"profile","name"],"set":"cc"}]},"w":1792537276932.579}
  #|{"step":"rest","w":1792537276932.852}
  #|{"step":"now until =cc","w":1792537278317.022}
  #|{"step":"back","w":1792537278317.052}
  #|{"step":"back","acted":true,"w":1792537278317.072}
  #|{"step":"rest","w":1792537278334.285}
  #|{"step":"now until =Profile","w":1792537278667.127}
  #|{"step":"tap icon:plus","w":1792537278667.16}
  #|{"step":"tap icon:plus","acted":true,"w":1792537278683.866}
  #|{"out":{"id":25,"subscribe":{"topic":"profileFlow","station":"01M5DRPYX4418WR37BHVJ6FPTZ/1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","form":"mbui-profile-1"},"keyed":true},"w":1792537278700.039}
  #|{"out":{"id":26,"call":"profile.flow.open","params":{"station":"01M5DRPYX4418WR37BHVJ6FPTZ/1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","form":"mbui-profile-1"}},"w":1792537278702.35}
  #|{"step":"answered profile.flow.open","w":1792537278702.837}
  #|{"in":{"id":25,"value":null},"w":1792537278715.973}
  #|{"in":{"id":26,"ok":null},"w":1792537278716.035}
  #|{"step":"rest","w":1792537278733.316}
  #|{"in":{"id":25,"value":{"step":"pick","station":"01M5DRPYX4418WR37BHVJ6FPTZ/1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","title":"选择服务商","hint":"订阅和 API key 都在这里添加，选择服务商开始","groups":[{"id":"labs","title":"模型厂商","providers":[{"id":"openai","name":"OpenAI","group":"labs","mark":"openai","kind":"api-provider","hasKey":true,"hasPlan":true,"runtime":"codex","endpointRequired":false,"endpointExample":null,"protocols":[],"keyOptional":false,"uses":["codex","dsh"],"usesText":"Codex · DeepSeek Harness","regions":[]},{"id":"anthropic","name":"Anthropic","group":"labs","mark":"anthropic","kind":"anthropic-api","hasKey":true,"hasPlan":true,"runtime":"claude","endpointRequired":false,"endpointExample":null,"protocols":[],"keyOptional":false,"uses":["claude","dsh"],"usesText":"Claude Code · DeepSeek Harness","regions":[]},{"id":"google","name":"Google Gemini","group":"labs","mark":"gemini","kind":"api-provider","hasKey":true,"hasPlan":false,"runtime":null,"endpointRequired":false,"endpointExample":null,"protocols":[],"keyOptional":false,"uses":["dsh","decision"],"usesText":"DeepSeek Harness · 自动决策","regions":[]},{"id":"xai","name":"xAI","group":"labs","mark":"xai","kind":"api-provider","hasKey":true,"hasPlan":true,"runtime":"grok","endpointRequired":false,"endpointExample":null,"protocols":[],"keyOptional":false,"uses":["codex","dsh","grok"],"usesText":"Codex · DeepSeek Harness · Grok Build","regions":[]},{"id":"mistral","name":"Mistral","group":"labs","mark":"mistral","kind":"api-provider","hasKey":true,"hasPlan":false,"runtime":null,"endpointRequired":false,"endpointExample":null,"protocols":[],"keyOptional":false,"uses":["dsh","decision"],"usesText":"DeepSeek Harness · 自动决策","regions":[]},{"id":"deepseek","name":"DeepSeek","group":"labs","mark":"deepseek","kind":"api-provider","hasKey":true,"hasPlan":false,"runtime":null,"endpointRequired":false,"endpointExample":null,"protocols":[],"keyOptional":false,"uses":["dsh","decision"],"usesText":"DeepSeek Harness · 自动决策","regions":[]},{"id":"qwen","name":"Qwen","group":"labs","mark":"qwen","kind":"api-provider","hasKey":true,"hasPlan":false,"runtime":null,"endpointRequired":false,"endpointExample":null,"protocols":[],"keyOptional":false,"uses":["dsh","decision"],"usesText":"DeepSeek Harness · 自动决策","regions":[{"id":"qwen","label":"国际"},{"id":"qwen-cn","label":"中国"}]},{"id":"moonshotai","name":"Kimi","group":"labs","mark":"kimi","kind":"api-provider","hasKey":true,"hasPlan":false,"runtime":null,"endpointRequired":false,"endpointExample":null,"protocols":[],"keyOptional":false,"uses":["dsh","decision"],"usesText":"DeepSeek Harness · 自动决策","regions":[{"id":"moonshotai","label":"国际"},{"id":"moonshotai-cn","label":"中国"}]},{"id":"zai","name":"Z.ai","group":"labs","mark":"zhipu","kind":"api-provider","hasKey":true,"hasPlan":false,"runtime":null,"endpointRequired":false,"endpointExample":null,"protocols":[],"keyOptional":false,"uses":["dsh","decision"],"usesText":"DeepSeek Harness · 自动决策","regions":[{"id":"zai","label":"国际"},{"id":"zai-coding-cn","label":"中国"}]},{"id":"minimax","name":"MiniMax","group":"labs","mark":"minimax","kind":"api-provider","hasKey":true,"hasPlan":false,"runtime":null,"endpointRequired":false,"endpointExample":null,"protocols":[],"keyOptional":false,"uses":["claude","dsh"],"usesText":"Claude Code · DeepSeek Harness","regions":[{"id":"minimax","label":"国际"},{"id":"minimax-cn","label":"中国"}]},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs","mark":"xiaomi","kind":"api-provider","hasKey":true,"hasPlan":false,"runtime":null,"endpointRequired":false,"endpointExample":null,"protocols":[],"keyOptional":false,"uses":["dsh","decision"],"usesText":"DeepSeek Harness · 自动决策","regions":[]},{"id":"ant-ling","name":"Ant Ling","group":"labs","mark":"ant-ling","kind":"api-provider","hasKey":true,"hasPlan":false,"runtime":null,"endpointRequired":false,"endpointExample":null,"protocols":[],"keyOptional":false,"uses":["dsh","decision"],"usesText":"DeepSeek Harness · 自动决策","regions":[]},{"id":"jev","name":"Jev","group":"labs","mark":null,"kind":"api-provider","hasKey":true,"hasPlan":false,"runtime":null,"endpointRequired":false,"endpointExample":null,"protocols":[],"keyOptional":false,"uses":["decision"],"usesText":"自动决策","regions":[]}]},{"id":"gateways","title":"中转站","providers":[{"id":"openrouter","name":"OpenRouter","group":"gateways","mark":"openrouter","kind":"api-provider","hasKey":true,"hasPlan":false,"runtime":null,"endpointRequired":false,"endpointExample":null,"protocols":[],"keyOptional":false,"uses":["claude","dsh","decision"],"usesText":"Claude Code · DeepSeek Harness · 自动决策","regions":[]},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways","mark":"vercel","kind":"api-provider","hasKey":true,"hasPlan":false,"runtime":null,"endpointRequired":false,"endpointExample":null,"protocols":[],"keyOptional":false,"uses":["claude","dsh"],"usesText":"Claude Code · DeepSeek Harness","regions":[]},{"id":"opencode","name":"OpenCode Zen","group":"gateways","mark":"opencode","kind":"api-provider","hasKey":true,"hasPlan":false,"runtime":null,"endpointRequired":false,"endpointExample":null,"protocols":[],"keyOptional":false,"uses":["claude","codex","dsh","decision"],"usesText":"Claude Code · Codex · DeepSeek Harness · 自动决策","regions":[]},{"id":"opencode-go","name":"OpenCode Go","group":"gateways","mark":"opencode","kind":"opencode-go","hasKey":true,"hasPlan":true,"runtime":null,"endpointRequired":false,"endpointExample":null,"protocols":[],"keyOptional":false,"uses":["claude","codex","dsh","decision"],"usesText":"Claude Code · Codex · DeepSeek Harness · 自动决策","regions":[]},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways","mark":"cloudflare","kind":"api-provider","hasKey":true,"hasPlan":false,"runtime":null,"endpointRequired":true,"endpointExample":"https://gateway.ai.cloudflare.com/v1/<account>/<gateway>","protocols":["chat_completions","responses","anthropic"],"keyOptional":false,"uses":["dsh","decision"],"usesText":"DeepSeek Harness · 自动决策","regions":[]}]},{"id":"hosted","title":"云上托管","providers":[{"id":"azure-openai","name":"Azure OpenAI","group":"hosted","mark":"azure","kind":"api-provider","hasKey":true,"hasPlan":false,"runtime":null,"endpointRequired":true,"endpointExample":"https://<resource>.openai.azure.com/openai/v1","protocols":["responses"],"keyOptional":false,"uses":["codex","dsh"],"usesText":"Codex · DeepSeek Harness","regions":[]},{"id":"groq","name":"Groq","group":"hosted","mark":"groq","kind":"api-provider","hasKey":true,"hasPlan":false,"runtime":null,"endpointRequired":false,"endpointExample":null,"protocols":[],"keyOptional":false,"uses":["dsh","decision"],"usesText":"DeepSeek Harness · 自动决策","regions":[]},{"id":"together","name":"Together AI","group":"hosted","mark":"together","kind":"api-provider","hasKey":true,"hasPlan":false,"runtime":null,"endpointRequired":false,"endpointExample":null,"protocols":[],"keyOptional":false,"uses":["dsh","decision"],"usesText":"DeepSeek Harness · 自动决策","regions":[]},{"id":"fireworks","name":"Fireworks","group":"hosted","mark":"fireworks","kind":"api-provider","hasKey":true,"hasPlan":false,"runtime":null,"endpointRequired":false,"endpointExample":null,"protocols":[],"keyOptional":false,"uses":["claude","dsh","decision"],"usesText":"Claude Code · DeepSeek Harness · 自动决策","regions":[]},{"id":"cerebras","name":"Cerebras","group":"hosted","mark":"cerebras","kind":"api-provider","hasKey":true,"hasPlan":false,"runtime":null,"endpointRequired":false,"endpointExample":null,"protocols":[],"keyOptional":false,"uses":["dsh","decision"],"usesText":"DeepSeek Harness · 自动决策","regions":[]},{"id":"huggingface","name":"Hugging Face","group":"hosted","mark":"huggingface","kind":"api-provider","hasKey":true,"hasPlan":false,"runtime":null,"endpointRequired":false,"endpointExample":null,"protocols":[],"keyOptional":false,"uses":["dsh","decision"],"usesText":"DeepSeek Harness · 自动决策","regions":[]},{"id":"nvidia","name":"NVIDIA","group":"hosted","mark":"nvidia","kind":"api-provider","hasKey":true,"hasPlan":false,"runtime":null,"endpointRequired":false,"endpointExample":null,"protocols":[],"keyOptional":false,"uses":["dsh","decision"],"usesText":"DeepSeek Harness · 自动决策","regions":[]},{"id":"baseten","name":"Baseten","group":"hosted","mark":"baseten","kind":"api-provider","hasKey":true,"hasPlan":false,"runtime":null,"endpointRequired":false,"endpointExample":null,"protocols":[],"keyOptional":false,"uses":["dsh","decision"],"usesText":"DeepSeek Harness · 自动决策","regions":[]},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted","mark":"cloudflare","kind":"api-provider","hasKey":true,"hasPlan":false,"runtime":null,"endpointRequired":true,"endpointExample":"https://api.cloudflare.com/client/v4/accounts/<account>/ai/v1","protocols":["chat_completions"],"keyOptional":false,"uses":["dsh","decision"],"usesText":"DeepSeek Harness · 自动决策","regions":[]}]},{"id":"local","title":"本地","providers":[{"id":"ollama","name":"Ollama","group":"local","mark":null,"kind":"api-provider","hasKey":true,"hasPlan":false,"runtime":null,"endpointRequired":true,"endpointExample":"https://ollama.example.com/v1","protocols":["chat_completions"],"keyOptional":true,"uses":["dsh","decision"],"usesText":"DeepSeek Harness · 自动决策","regions":[]},{"id":"custom","name":"Custom","group":"local","mark":null,"kind":"api-provider","hasKey":true,"hasPlan":false,"runtime":null,"endpointRequired":true,"endpointExample":"https://api.example.com/v1","protocols":["chat_completions","responses","anthropic"],"keyOptional":true,"uses":["dsh","decision"],"usesText":"DeepSeek Harness · 自动决策","regions":[]},{"id":"env-claude","name":"环境变量（Claude Code）","group":"local","kind":"env","hasKey":false,"hasPlan":false,"runtime":"claude","endpointRequired":false,"protocols":[],"keyOptional":true,"uses":["claude"],"usesText":"Claude Code"},{"id":"env-codex","name":"环境变量（Codex）","group":"local","kind":"env","hasKey":false,"hasPlan":false,"runtime":"codex","endpointRequired":false,"protocols":[],"keyOptional":true,"uses":["codex"],"usesText":"Codex"},{"id":"env-dsh","name":"环境变量（DeepSeek Harness）","group":"local","kind":"env","hasKey":false,"hasPlan":false,"runtime":"dsh","endpointRequired":false,"protocols":[],"keyOptional":true,"uses":["dsh"],"usesText":"DeepSeek Harness"},{"id":"env-grok","name":"环境变量（Grok Build）","group":"local","kind":"env","hasKey":false,"hasPlan":false,"runtime":"grok","endpointRequired":false,"protocols":[],"keyOptional":true,"uses":["grok"],"usesText":"Grok Build"}]}],"tile":null,"method":null,"choices":[],"showEndpoint":false,"endpoint":"","protocols":[],"regions":[],"region":null,"showKey":false,"key":"","keyLabel":"","canSubmit":false,"pending":false,"submitLabel":"","usesLine":"","error":null,"signIn":null}},"w":1792537278899.731}
  #|{"step":"now until 选择服务商","w":1792537279036.736}
  #|{"step":"tap =Anthropic","w":1792537279036.766}
  #|{"step":"tap =Anthropic","acted":true,"w":1792537279066.599}
  #|{"out":{"id":27,"call":"profile.flow.edit","params":{"station":"01M5DRPYX4418WR37BHVJ6FPTZ/1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","form":"mbui-profile-1","input":{"provider":"anthropic"}}},"w":1792537279082.913}
  #|{"step":"answered profile.flow.edit","w":1792537279083.541}
  #|{"in":{"id":27,"ok":null},"w":1792537279099.254}
  #|{"in":{"id":25,"delta":[{"path":["choices"],"append":[{"id":"plan","title":"订阅 · Claude","hint":"Claude Pro / Max，用于运行 Claude Code。在浏览器中登录一次。"},{"id":"key","title":"API key","hint":"使用 Anthropic 的 API key，按量计费"}]},{"path":["hint"],"set":""},{"path":["step"],"set":"method"},{"path":["tile"],"set":{"id":"anthropic","name":"Anthropic","group":"labs","mark":"anthropic","kind":"anthropic-api","hasKey":true,"hasPlan":true,"runtime":"claude","endpointRequired":false,"endpointExample":null,"protocols":[],"keyOptional":false,"uses":["claude","dsh"],"usesText":"Claude Code · DeepSeek Harness","regions":[]}},{"path":["title"],"set":"连接 Anthropic"}]},"w":1792537279249.301}
  #|{"step":"tap =API key","w":1792537279275.556}
  #|{"step":"tap =API key","acted":true,"w":1792537279283.384}
  #|{"out":{"id":28,"call":"profile.flow.edit","params":{"station":"01M5DRPYX4418WR37BHVJ6FPTZ/1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","form":"mbui-profile-1","input":{"method":"key"}}},"w":1792537279299.655}
  #|{"step":"answered profile.flow.edit","w":1792537279300.092}
  #|{"in":{"id":28,"ok":null},"w":1792537279315.96}
  #|{"in":{"id":25,"delta":[{"path":["choices"],"set":[]},{"path":["endpointHint"],"set":null},{"path":["keyHint"],"set":"key 仅保存在此 station 上"},{"path":["keyLabel"],"set":"API key"},{"path":["method"],"set":"key"},{"path":["protocol"],"set":null},{"path":["showKey"],"set":true},{"path":["step"],"set":"connect"},{"path":["submitLabel"],"set":"验证并添加"},{"path":["usesLine"],"set":"添加后可用于：Claude Code · DeepSeek Harness"}]},"w":1792537279404.191}
  #|{"step":"tap 验证可用后再添加","w":1792537279467.764}
  #|{"step":"tap 验证可用后再添加","acted":true,"w":1792537279566.509}
  #|{"step":"type sk-ant-madeup-080726-0000000000","w":1792537279584.019}
  #|{"step":"type sk-ant-madeup-080726-0000000000","acted":true,"w":1792537279584.248}
  #|{"out":{"id":29,"call":"profile.flow.edit","params":{"station":"01M5DRPYX4418WR37BHVJ6FPTZ/1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","form":"mbui-profile-1","input":{"key":"sk-ant-madeup-080726-0000000000"}}},"w":1792537279602.114}
  #|{"step":"answered profile.flow.edit","w":1792537279610.777}
  #|{"in":{"id":29,"ok":null},"w":1792537279616.176}
  #|{"in":{"id":25,"delta":[{"path":["canSubmit"],"set":true},{"path":["key"],"set":"sk-ant-madeup-080726-0000000000"}]},"w":1792537279782.842}
  #|{"step":"tap 验证并添加","w":1792537279802.618}
  #|{"step":"tap 验证并添加","acted":true,"w":1792537279819.107}
  #|{"out":{"id":30,"call":"profile.flow.submit","params":{"station":"01M5DRPYX4418WR37BHVJ6FPTZ/1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","form":"mbui-profile-1"}},"w":1792537279834.35}
  #|{"step":"back","w":1792537279834.741}
  #|{"step":"back","acted":true,"w":1792537279834.757}
  #|{"step":"rest","w":1792537279849.855}
  #|{"in":{"id":19,"value":{"doing":[{"call":"profile.flow.submit","params":{"station":"01M5DRPYX4418WR37BHVJ6FPTZ/1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","form":"mbui-profile-1"},"since":1792537279834,"stage":"running"}]}},"w":1792537280052.735}
  #|{"in":{"id":25,"delta":[{"path":["canSubmit"],"set":false},{"path":["pending"],"set":true}]},"w":1792537280052.78}
  #|{"out":{"id":31,"call":"profile.flow.drop","params":{"station":"01M5DRPYX4418WR37BHVJ6FPTZ/1956c7ca33df6fd77e0cd82620e86f26cae29936160d16e1adec1ac1166ed4c3","form":"mbui-profile-1"}},"w":1792537280150.974}
  #|{"in":{"id":31,"ok":null},"w":1792537280167.792}
  #|{"in":{"id":25,"value":null},"w":1792537280266.95}
  #|{"in":{"id":30,"error":{"code":"http_400","message":"验证没通过：Anthropic 拒绝了这个 key（401）","status":400}},"w":1792537280269.027}
  #|{"step":"now answered profile.flow.drop","w":1792537280287.572}
  #|{"step":"","w":1792537280299.765}
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
  #|{"textrec":{"ib":["fdb526ba00f881f4",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["a7ccae3554fe46cf",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["bef2954d97ce1d9f",6508,64],"r":[40,40,40,40]}}
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
  #|{"textrec":{"ib":["d61ec6305f7d8c8b",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["8bf9607b651cec61",3232,64],"r":[28,28,28,28]}}
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
  #|{"textrec":{"s":[16,600,0,"Profile"],"r":[0,1,10.239953994750977,185,1,1,6.225622177124023,186,2,1,9.327718734741211,34,3,1,5.944116592407227,187,4,1,4.046333312988281,188,5,1,4.159873962402344,189,6,1,9.127458572387695,46]}}
  #|{"textrec":{"s":[17,400,0,"设置"],"r":[0,1,16.851167315175097,190,1,1,16.851167315175097,191]}}
  #|{"textrec":{"s":[15,600,0,"API Key"],"r":[0,1,10.429658889770508,192,1,1,9.65855062007904,193,2,1,4.261693954467773,194,3,1,3.761730194091797,-1,4,1,9.82150912284851,195,5,1,8.214586973190308,85,6,1,8.328588008880615,196]}}
  #|{"textrec":{"s":[15,400,0,"cc"],"r":[0,1,8.1591796875,94,1,1,8.1591796875,94]}}
  #|{"textrec":{"s":[13,400,0,"仅在 studio"],"r":[0,1,12.898832684824903,197,1,1,12.898832684824903,1,2,1,3.580078125,-1,3,1,6.69677734375,10,4,1,4.61474609375,82,5,1,7.50927734375,198,6,1,7.9091796875,199,7,1,3.1357421875,77,8,1,7.6044921875,7]}}
  #|{"textrec":{"g":190,"r":[1967,0,19,18,-1,-15,0]}}
  #|{"textrec":{"g":191,"r":[1987,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":197,"r":[2006,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":1,"r":[2022,0,14,15,-1,-12,0]}}
  #|{"textrec":{"g":198,"r":[2037,0,9,10,-1,-8,0]}}
  #|{"textrec":{"g":199,"r":[0,32,9,13,-1,-11,0]}}
  #|{"textrec":{"g":7,"r":[10,32,9,10,-1,-8,0]}}
  #|{"textrec":{"ib":["d2b320ef40c51d36",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"g":192,"r":[20,32,13,13,-1,-12,0]}}
  #|{"textrec":{"g":193,"r":[34,32,11,13,0,-12,0]}}
  #|{"textrec":{"g":194,"r":[46,32,5,13,0,-12,0]}}
  #|{"textrec":{"g":195,"r":[52,32,11,13,0,-12,0]}}
  #|{"textrec":{"g":196,"r":[64,32,11,14,-1,-10,0]}}
  #|{"textrec":{"g":185,"r":[76,32,11,14,0,-13,0]}}
  #|{"textrec":{"g":186,"r":[88,32,8,11,0,-10,0]}}
  #|{"textrec":{"g":187,"r":[97,32,8,14,-1,-13,0]}}
  #|{"textrec":{"g":188,"r":[106,32,5,15,0,-14,0]}}
  #|{"textrec":{"g":189,"r":[112,32,5,14,0,-13,0]}}
  #|{"textrec":{"g":46,"r":[118,32,11,12,-1,-10,0]}}
  #|{"textrec":{"ib":["2bb63fc1d380f765",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"s":[11,400,0,"自定义环境变量"],"r":[0,1,10.93579766536965,200,1,1,10.93579766536965,201,2,1,10.935797665369652,202,3,1,10.935797665369648,203,4,1,10.935797665369648,204,5,1,10.935797665369655,205,6,1,10.935797665369648,206]}}
  #|{"textrec":{"m":[11,400,0],"r":[10.634765625,2.3203125,16]}}
  #|{"textrec":{"s":[16,600,0,"cc"],"r":[0,1,8.92264175415039,207,1,1,8.92264175415039,207]}}
  #|{"textrec":{"s":[17,400,0,"studio"],"r":[0,1,8.42529296875,208,1,1,5.70263671875,209,2,1,9.48779296875,210,3,1,10.0107421875,211,4,1,3.7685546875,212,5,1,9.6123046875,213]}}
  #|{"textrec":{"s":[12,400,0,"无法检查"],"r":[0,1,11.918287937743191,214,1,1,11.918287937743191,215,2,1,11.918287937743195,216,3,1,11.918287937743187,217]}}
  #|{"textrec":{"m":[12,400,0],"r":[11.6015625,2.53125,17]}}
  #|{"textrec":{"s":[13,400,0,"自定义环境变量，still.fail 无法自动检查 · 刚刚检查"],"r":[0,1,12.898832684824903,218,1,1,12.898832684824903,219,2,1,12.898832684824903,220,3,1,12.898832684824903,221,4,1,12.898832684824896,222,5,1,12.898832684824896,223,6,1,12.898832684824896,224,7,1,11.775875486381324,225,8,1,6.69677734375,10,9,1,4.61474609375,82,10,1,3.1357421875,77,11,1,3.2119140625,76,12,1,3.2119140625,76,13,1,3.5927734375,81,14,1,4.341796875,226,15,1,7.00146484375,12,16,1,3.1357421875,77,17,1,3.2119140625,76,18,1,3.580078125,-1,19,1,12.898832684824896,227,20,1,12.898832684824896,228,21,1,12.898832684824896,218,22,1,12.898832684824896,229,23,1,12.898832684824896,230,24,1,12.898832684824896,231,25,1,3.580078125,-1,26,1,6.228545204222115,232,27,1,3.580078125,-1,28,1,12.898832684824896,233,29,1,12.898832684824924,233,30,1,12.898832684824924,230,31,1,12.898832684824924,231]}}
  #|{"textrec":{"s":[15,600,0,"额度"],"r":[0,1,14.883268482490273,234,1,1,14.883268482490273,235]}}
  #|{"textrec":{"s":[14,400,0,"查询额度"],"r":[0,1,13.891050583657588,236,1,1,13.891050583657588,237,2,1,13.891050583657588,238,3,1,13.891050583657588,239]}}
  #|{"textrec":{"s":[12,400,0,"刚刚查询"],"r":[0,1,11.918287937743191,240,1,1,11.918287937743191,240,2,1,11.918287937743195,217,3,1,11.918287937743187,241]}}
  #|{"textrec":{"s":[13,400,0,"自定义环境变量的账号无法查询额度"],"r":[0,1,12.898832684824903,218,1,1,12.898832684824903,219,2,1,12.898832684824903,220,3,1,12.898832684824903,221,4,1,12.898832684824896,222,5,1,12.898832684824896,223,6,1,12.898832684824896,224,7,1,12.898832684824896,5,8,1,12.898832684824896,242,9,1,12.898832684824896,243,10,1,12.898832684824896,227,11,1,12.898832684824896,228,12,1,12.898832684824896,231,13,1,12.898832684824896,244,14,1,12.898832684824896,245,15,1,12.898832684824896,246]}}
  #|{"textrec":{"s":[15,600,0,"分享"],"r":[0,1,14.883268482490273,247,1,1,14.883268482490273,248]}}
  #|{"textrec":{"s":[15,400,0,"分享给其他 station"],"r":[0,1,14.883268482490273,249,1,1,14.883268482490273,250,2,1,14.883268482490273,251,3,1,14.883268482490273,252,4,1,14.88326848249028,253,5,1,3.984375,-1,6,1,7.58056640625,91,7,1,5.17822265625,101,8,1,8.0419921875,93,9,1,5.21484375,101,10,1,3.4716796875,102,11,1,8.6279296875,88,12,1,8.51806640625,103]}}
  #|{"textrec":{"s":[13,400,0,"目前仅在 studio 上使用"],"r":[0,1,12.898832684824903,254,1,1,12.898832684824903,255,2,1,12.898832684824903,197,3,1,12.898832684824903,1,4,1,3.580078125,-1,5,1,6.69677734375,10,6,1,4.61474609375,82,7,1,7.50927734375,198,8,1,7.9091796875,199,9,1,3.1357421875,77,10,1,7.6044921875,7,11,1,3.580078125,-1,12,1,12.898832684824896,256,13,1,12.898832684824896,257,14,1,12.898832684824896,258]}}
  #|{"textrec":{"s":[15,600,0,"运行"],"r":[0,1,14.883268482490273,259,1,1,14.883268482490273,260]}}
  #|{"textrec":{"s":[15,400,0,"新消息到达时，将正在执行的命令转到后台"],"r":[0,1,14.883268482490273,159,1,1,14.883268482490273,261,2,1,14.883268482490273,262,3,1,14.883268482490273,263,4,1,14.88326848249028,264,5,1,14.88326848249028,265,6,1,15.08754863813229,266,7,1,14.88326848249028,267,8,1,14.88326848249028,268,9,1,14.88326848249028,269,10,1,14.88326848249028,270,11,1,14.88326848249028,271,12,1,14.88326848249028,272,13,1,14.88326848249028,273,14,1,14.88326848249028,274,15,1,14.88326848249028,275,16,1,14.88326848249028,263,17,1,14.88326848249028,276,18,1,14.88326848249028,277]}}
  #|{"textrec":{"s":[13,400,0,"命令和 subagent 转到后台继续运行，agent 立即读取消息。"],"r":[0,1,12.898832684824903,278,1,1,12.898832684824903,279,2,1,12.898832684824903,280,3,1,3.580078125,-1,4,1,6.728515625,10,5,1,7.50927734375,198,6,1,7.909179687500007,281,7,1,7.0966796875,12,8,1,7.845703125,282,9,1,7.3505859375,14,10,1,7.50927734375,283,11,1,4.646484375,82,12,1,3.580078125,-1,13,1,12.898832684824896,284,14,1,12.898832684824896,285,15,1,12.898832684824896,286,16,1,12.898832684824896,287,17,1,12.898832684824896,288,18,1,12.898832684824896,289,19,1,12.898832684824896,290,20,1,12.898832684824896,291,21,1,11.775875486381324,225,22,1,7.0966796875,12,23,1,7.845703125,282,24,1,7.3505859375,14,25,1,7.50927734375,283,26,1,4.646484375,82,27,1,3.580078125,-1,28,1,12.898832684824924,292,29,1,12.898832684824924,293,30,1,12.898832684824924,2,31,1,12.898832684824924,3,32,1,12.898832684824924,151,33,1,12.898832684824924,152,34,1,6.575875486381335,294]}}
  #|{"textrec":{"s":[15,600,0,"模型 · 启用 1 / 1"],"r":[0,1,14.883268482490273,295,1,1,14.883268482490273,296,2,1,3.761730194091797,-1,3,1,7.186782927948599,168,4,1,3.761730194091797,-1,5,1,14.883268482490273,297,6,1,14.883268482490273,298,7,1,3.761730194091797,-1,8,1,7.178199291229248,299,9,1,3.761730194091797,-1,10,1,4.618881940841675,300,11,1,3.761730194091797,-1,12,1,7.178199291229248,299]}}
  #|{"textrec":{"s":[13,400,0,"只有勾选的模型可在新对话和连接中选择。"],"r":[0,1,12.898832684824903,301,1,1,12.898832684824903,149,2,1,12.898832684824903,302,3,1,12.898832684824903,303,4,1,12.898832684824896,5,5,1,12.898832684824896,304,6,1,12.898832684824896,305,7,1,12.898832684824896,306,8,1,12.898832684824896,1,9,1,12.898832684824896,150,10,1,12.898832684824896,307,11,1,12.898832684824896,308,12,1,12.898832684824896,280,13,1,12.898832684824896,309,14,1,12.898832684824896,310,15,1,12.898832684824896,311,16,1,12.898832684824896,303,17,1,12.898832684824896,312,18,1,6.575875486381335,294]}}
  #|{"textrec":{"s":[14,400,0,"刷新模型"],"r":[0,1,13.891050583657588,313,1,1,13.891050583657588,314,2,1,13.891050583657588,315,3,1,13.891050583657588,316]}}
  #|{"textrec":{"s":[14,400,0,"全选"],"r":[0,1,13.891050583657588,317,1,1,13.891050583657588,318]}}
  #|{"textrec":{"s":[14,400,0,"全不选"],"r":[0,1,13.891050583657588,317,1,1,13.891050583657588,319,2,1,13.891050583657588,318]}}
  #|{"textrec":{"s":[13,400,0,"Sonnet"],"r":[0,1,8.20751953125,320,1,1,7.6044921875,7,2,1,7.50927734375,283,3,1,7.50927734375,283,4,1,7.3505859375,14,5,1,4.646484375,82]}}
  #|{"textrec":{"s":[14,400,0,"Sonnet 5.5"],"r":[0,1,8.7705078125,321,1,1,8.12109375,322,2,1,8.0185546875,60,3,1,8.0185546875,60,4,1,7.84765625,59,5,1,4.935546875,61,6,1,3.787109375,-1,7,1,8.2646484375,323,8,1,3.54443359375,324,9,1,8.28173828125,323]}}
  #|{"textrec":{"s":[15,600,0,"使用它的连接"],"r":[0,1,14.883268482490273,325,1,1,14.883268482490273,298,2,1,14.883268482490273,326,3,1,14.883268482490273,327,4,1,14.88326848249028,328,5,1,14.88326848249028,329]}}
  #|{"textrec":{"s":[15,400,0,"暂无连接使用此 Profile"],"r":[0,1,14.883268482490273,330,1,1,14.883268482490273,331,2,1,14.883268482490273,104,3,1,14.883268482490273,105,4,1,14.88326848249028,332,5,1,14.88326848249028,115,6,1,14.88326848249028,333,7,1,3.984375,-1,8,1,9.29443359375,106,9,1,5.36865234375,89,10,1,8.51806640625,88,11,1,5.19287109375,107,12,1,3.4716796875,102,13,1,3.5595703125,108,14,1,8.3349609375,95]}}
  #|{"textrec":{"g":208,"r":[130,32,11,13,-1,-11,0]}}
  #|{"textrec":{"g":209,"r":[142,32,8,15,-1,-13,0]}}
  #|{"textrec":{"g":210,"r":[151,32,10,12,0,-10,0]}}
  #|{"textrec":{"g":211,"r":[162,32,12,16,-1,-14,0]}}
  #|{"textrec":{"g":212,"r":[175,32,5,15,0,-14,0]}}
  #|{"textrec":{"g":213,"r":[181,32,12,13,-1,-11,0]}}
  #|{"textrec":{"g":234,"r":[194,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":235,"r":[212,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":240,"r":[230,32,13,14,-1,-11,0]}}
  #|{"textrec":{"g":217,"r":[244,32,14,13,-1,-11,0]}}
  #|{"textrec":{"g":241,"r":[259,32,13,14,-1,-11,0]}}
  #|{"textrec":{"g":218,"r":[273,32,11,15,1,-12,0]}}
  #|{"textrec":{"g":219,"r":[285,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":220,"r":[301,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":221,"r":[317,32,15,14,-1,-11,0]}}
  #|{"textrec":{"g":222,"r":[333,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":223,"r":[349,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":224,"r":[365,32,14,14,-1,-12,0]}}
  #|{"textrec":{"g":5,"r":[380,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":242,"r":[394,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":243,"r":[410,32,15,14,-1,-11,0]}}
  #|{"textrec":{"g":227,"r":[426,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":228,"r":[441,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":231,"r":[457,32,15,14,-1,-12,0]}}
  #|{"textrec":{"g":244,"r":[473,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":245,"r":[488,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":246,"r":[504,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":247,"r":[520,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":248,"r":[537,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":249,"r":[555,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":250,"r":[572,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":251,"r":[589,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":252,"r":[607,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":253,"r":[624,32,16,17,-1,-14,0]}}
  #|{"textrec":{"g":254,"r":[641,32,11,14,1,-11,0]}}
  #|{"textrec":{"g":255,"r":[653,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":256,"r":[669,32,14,14,-1,-12,0]}}
  #|{"textrec":{"g":257,"r":[684,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":258,"r":[700,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":259,"r":[715,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":260,"r":[733,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":159,"r":[750,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":261,"r":[768,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":262,"r":[785,32,16,17,-1,-14,0]}}
  #|{"textrec":{"g":263,"r":[802,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":264,"r":[819,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":265,"r":[837,32,15,16,0,-13,0]}}
  #|{"textrec":{"g":266,"r":[853,32,5,7,0,-3,0]}}
  #|{"textrec":{"g":267,"r":[859,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":268,"r":[876,32,16,15,-1,-13,0]}}
  #|{"textrec":{"g":269,"r":[893,32,16,17,-1,-14,0]}}
  #|{"textrec":{"g":270,"r":[910,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":271,"r":[928,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":272,"r":[945,32,15,17,0,-14,0]}}
  #|{"textrec":{"g":273,"r":[961,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":274,"r":[978,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":275,"r":[996,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":276,"r":[1014,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":277,"r":[1031,32,15,16,0,-13,0]}}
  #|{"textrec":{"g":278,"r":[1047,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":279,"r":[1063,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":280,"r":[1079,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":281,"r":[1094,32,9,13,0,-11,0]}}
  #|{"textrec":{"g":282,"r":[1104,32,9,12,-1,-8,0]}}
  #|{"textrec":{"g":283,"r":[1114,32,8,9,0,-8,0]}}
  #|{"textrec":{"g":284,"r":[1123,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":285,"r":[1139,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":286,"r":[1154,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":287,"r":[1169,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":288,"r":[1183,32,15,14,-1,-12,0]}}
  #|{"textrec":{"g":289,"r":[1199,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":290,"r":[1215,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":291,"r":[1231,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":225,"r":[1247,32,5,7,0,-3,0]}}
  #|{"textrec":{"g":292,"r":[1253,32,15,14,-1,-12,0]}}
  #|{"textrec":{"g":293,"r":[1269,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":2,"r":[1284,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":3,"r":[1300,32,15,14,-1,-11,0]}}
  #|{"textrec":{"g":151,"r":[1316,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":152,"r":[1331,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":294,"r":[1347,32,6,6,0,-3,0]}}
  #|{"textrec":{"g":295,"r":[1354,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":296,"r":[1372,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":297,"r":[1389,32,16,17,-1,-14,0]}}
  #|{"textrec":{"g":298,"r":[1406,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":299,"r":[1423,32,8,13,-1,-12,0]}}
  #|{"textrec":{"g":300,"r":[1432,32,7,17,-1,-13,0]}}
  #|{"textrec":{"g":301,"r":[1440,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":149,"r":[1455,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":302,"r":[1470,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":303,"r":[1485,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":304,"r":[1501,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":305,"r":[1517,32,14,14,-1,-12,0]}}
  #|{"textrec":{"g":306,"r":[1532,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":150,"r":[1547,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":307,"r":[1563,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":308,"r":[1579,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":309,"r":[1595,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":310,"r":[1611,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":311,"r":[1627,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":312,"r":[1641,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":313,"r":[1657,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":314,"r":[1673,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":315,"r":[1690,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":316,"r":[1707,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":320,"r":[1723,32,10,13,-1,-11,0]}}
  #|{"textrec":{"g":325,"r":[1734,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":326,"r":[1752,32,15,17,0,-14,0]}}
  #|{"textrec":{"g":327,"r":[1768,32,15,17,0,-14,0]}}
  #|{"textrec":{"g":328,"r":[1784,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":329,"r":[1802,32,16,17,-1,-14,0]}}
  #|{"textrec":{"g":330,"r":[1819,32,15,17,0,-14,0]}}
  #|{"textrec":{"g":331,"r":[1835,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":332,"r":[1852,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":333,"r":[1870,32,16,15,-1,-13,0]}}
  #|{"textrec":{"ib":["553115ca6cfb9bdf",2798,64],"r":[26,26,26,26]}}
  #|{"textrec":{"ib":["17b98c49fa7ec127",757,64],"r":[13,13,13,13]}}
  #|{"textrec":{"g":214,"r":[1887,32,14,13,-1,-10,0]}}
  #|{"textrec":{"g":215,"r":[1902,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":216,"r":[1917,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":226,"r":[1932,32,7,12,-1,-11,0]}}
  #|{"textrec":{"g":229,"r":[1940,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":230,"r":[1955,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":232,"r":[1971,32,4,5,1,-7,0]}}
  #|{"textrec":{"g":233,"r":[1976,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":321,"r":[1991,32,11,14,-1,-12,0]}}
  #|{"textrec":{"g":322,"r":[2003,32,10,11,-1,-9,0]}}
  #|{"textrec":{"g":323,"r":[2014,32,9,13,0,-11,0]}}
  #|{"textrec":{"g":324,"r":[2024,32,4,5,0,-3,0]}}
  #|{"textrec":{"g":200,"r":[2029,32,10,13,0,-10,0]}}
  #|{"textrec":{"g":201,"r":[0,50,13,13,-1,-10,0]}}
  #|{"textrec":{"g":202,"r":[14,50,13,13,-1,-10,0]}}
  #|{"textrec":{"g":203,"r":[28,50,13,13,-1,-10,0]}}
  #|{"textrec":{"g":204,"r":[42,50,13,13,-1,-10,0]}}
  #|{"textrec":{"g":205,"r":[56,50,13,13,-1,-10,0]}}
  #|{"textrec":{"g":206,"r":[70,50,13,12,-1,-10,0]}}
  #|{"textrec":{"g":207,"r":[84,50,11,12,-1,-10,0]}}
  #|{"textrec":{"g":317,"r":[96,50,16,15,-1,-13,0]}}
  #|{"textrec":{"g":318,"r":[113,50,16,16,-1,-13,0]}}
  #|{"textrec":{"g":236,"r":[130,50,16,15,-1,-13,0]}}
  #|{"textrec":{"g":237,"r":[147,50,15,16,-1,-13,0]}}
  #|{"textrec":{"g":238,"r":[163,50,16,16,-1,-13,0]}}
  #|{"textrec":{"g":239,"r":[180,50,16,16,-1,-13,0]}}
  #|{"textrec":{"g":319,"r":[197,50,15,15,-1,-12,0]}}
  #|{"textrec":{"ib":["ddfdc2820df8a676",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"s":[17,700,0,"cc"],"r":[0,1,9.55419921875,334,1,1,9.55419921875,334]}}
  #|{"textrec":{"m":[17,700,0],"r":[16.435546875,3.5859375,24]}}
  #|{"textrec":{"s":[15,400,0,"重命名"],"r":[0,1,14.883268482490273,335,1,1,14.883268482490273,273,2,1,14.883268482490273,336]}}
  #|{"textrec":{"s":[15,400,0,"重新检查"],"r":[0,1,14.883268482490273,335,1,1,14.883268482490273,159,2,1,14.883268482490273,156,3,1,14.883268482490273,157]}}
  #|{"textrec":{"s":[15,400,0,"删除 Profile"],"r":[0,1,14.883268482490273,337,1,1,14.883268482490273,338,2,1,3.984375,-1,3,1,9.29443359375,106,4,1,5.36865234375,89,5,1,8.51806640625,88,6,1,5.19287109375,107,7,1,3.4716796875,102,8,1,3.5595703125,108,9,1,8.3349609375,95]}}
  #|{"textrec":{"g":334,"r":[213,50,12,13,-1,-11,0]}}
  #|{"textrec":{"g":335,"r":[226,50,16,16,-1,-13,0]}}
  #|{"textrec":{"g":336,"r":[243,50,15,16,-1,-13,0]}}
  #|{"textrec":{"g":156,"r":[259,50,17,16,-1,-13,0]}}
  #|{"textrec":{"g":157,"r":[277,50,16,16,-1,-13,0]}}
  #|{"textrec":{"g":337,"r":[294,50,16,16,-1,-13,0]}}
  #|{"textrec":{"g":338,"r":[311,50,16,16,0,-13,0]}}
  #|{"textrec":{"s":[17,700,0,"Profile 名称"],"r":[0,1,11.019287109375,339,1,1,6.860595703125,340,2,1,9.998291015625,341,3,1,6.503662109375,342,4,1,4.44921875,343,5,1,4.58203125,344,6,1,9.782470703125,345,7,1,3.951171875,-1,8,1,16.851167315175104,346,9,1,16.851167315175104,347]}}
  #|{"textrec":{"s":[14,600,0,"取消"],"r":[0,1,13.891050583657588,348,1,1,13.891050583657588,349]}}
  #|{"textrec":{"m":[14,600,0],"r":[13.53515625,2.953125,20]}}
  #|{"textrec":{"s":[14,600,0,"保存"],"r":[0,1,13.891050583657588,350,1,1,13.891050583657588,351]}}
  #|{"textrec":{"g":339,"r":[328,50,12,14,0,-13,0]}}
  #|{"textrec":{"g":340,"r":[341,50,8,12,0,-11,0]}}
  #|{"textrec":{"g":341,"r":[350,50,12,13,-1,-11,0]}}
  #|{"textrec":{"g":342,"r":[363,50,9,15,-1,-14,0]}}
  #|{"textrec":{"g":343,"r":[373,50,5,16,0,-15,0]}}
  #|{"textrec":{"g":344,"r":[379,50,5,15,0,-14,0]}}
  #|{"textrec":{"g":345,"r":[385,50,12,13,-1,-11,0]}}
  #|{"textrec":{"g":346,"r":[398,50,17,18,-1,-15,0]}}
  #|{"textrec":{"g":347,"r":[416,50,19,18,-1,-15,0]}}
  #|{"textrec":{"g":348,"r":[436,50,16,15,-1,-12,0]}}
  #|{"textrec":{"g":349,"r":[453,50,15,16,-1,-13,0]}}
  #|{"textrec":{"g":350,"r":[469,50,16,16,-1,-13,0]}}
  #|{"textrec":{"g":351,"r":[486,50,16,16,-1,-13,0]}}
  #|{"textrec":{"s":[15,400,0,"名称"],"r":[0,1,14.883268482490273,336,1,1,14.883268482490273,352]}}
  #|{"textrec":{"g":352,"r":[503,50,17,17,-1,-14,0]}}
  #|{"textrec":{"s":[15,400,0,"e2e-080726"],"r":[0,1,8.3349609375,95,1,1,8.78173828125,353,2,1,8.29833984375,95,3,1,6.8408203125,354,4,1,9.2138671875,164,5,1,9.345703125,355,6,1,9.0673828125,164,7,1,8.1591796875,356,8,1,8.818359375,353,9,1,9.31640625,357]}}
  #|{"textrec":{"g":353,"r":[521,50,10,13,0,-12,0]}}
  #|{"textrec":{"g":354,"r":[532,50,7,4,0,-6,0]}}
  #|{"textrec":{"g":164,"r":[540,50,11,14,-1,-12,0]}}
  #|{"textrec":{"g":355,"r":[552,50,11,14,-1,-12,0]}}
  #|{"textrec":{"g":356,"r":[564,50,10,13,-1,-12,0]}}
  #|{"textrec":{"g":357,"r":[575,50,11,14,-1,-12,0]}}
  #|{"textrec":{"s":[14,400,0,"已重命名"],"r":[0,1,13.891050583657588,358,1,1,13.891050583657588,359,2,1,13.891050583657588,360,3,1,13.891050583657588,361]}}
  #|{"textrec":{"g":358,"r":[587,50,14,14,0,-12,0]}}
  #|{"textrec":{"g":359,"r":[602,50,15,16,-1,-13,0]}}
  #|{"textrec":{"g":360,"r":[618,50,16,16,-1,-13,0]}}
  #|{"textrec":{"g":361,"r":[635,50,14,16,-1,-13,0]}}
  #|{"textrec":{"s":[16,600,0,"e2e-080726"],"r":[0,1,9.127458572387695,46,1,1,9.717817306518555,362,2,1,9.100765228271484,46,3,1,7.363014221191406,363,4,1,10.31976318359375,364,5,1,10.440597534179688,365,6,1,10.138774871826172,364,7,1,8.996856689453125,366,8,1,9.744510650634766,362,9,1,10.3499755859375,367]}}
  #|{"textrec":{"g":362,"r":[650,50,11,14,0,-13,0]}}
  #|{"textrec":{"g":363,"r":[662,50,8,5,0,-7,0]}}
  #|{"textrec":{"g":364,"r":[671,50,11,15,0,-13,0]}}
  #|{"textrec":{"g":365,"r":[683,50,12,15,-1,-13,0]}}
  #|{"textrec":{"g":366,"r":[696,50,11,14,-1,-13,0]}}
  #|{"textrec":{"g":367,"r":[708,50,12,15,-1,-13,0]}}
  #|{"textrec":{"s":[17,700,0,"e2e-080726"],"r":[0,1,9.782470703125,345,1,1,10.479736328125,368,2,1,9.76171875,345,3,1,7.802734375,369,4,1,11.2060546875,370,5,1,11.322265625,371,6,1,10.99853515625,370,7,1,9.6787109375,372,8,1,10.50048828125,368,9,1,11.189453125,373]}}
  #|{"textrec":{"g":368,"r":[721,50,11,15,0,-14,0]}}
  #|{"textrec":{"g":369,"r":[733,50,8,5,0,-7,0]}}
  #|{"textrec":{"g":370,"r":[742,50,12,16,0,-14,0]}}
  #|{"textrec":{"g":371,"r":[755,50,12,16,0,-14,0]}}
  #|{"textrec":{"g":372,"r":[768,50,12,14,-1,-13,0]}}
  #|{"textrec":{"g":373,"r":[781,50,12,16,0,-14,0]}}
  #|{"textrec":{"s":[14,400,0,"已检查"],"r":[0,1,13.891050583657588,358,1,1,13.891050583657588,374,2,1,13.891050583657588,236]}}
  #|{"textrec":{"g":374,"r":[794,50,16,16,-1,-13,0]}}
  #|{"textrec":{"s":[17,400,0,"取消"],"r":[0,1,16.851167315175097,375,1,1,16.851167315175097,376]}}
  #|{"textrec":{"s":[17,600,0,"添加 Profile"],"r":[0,1,16.851167315175097,377,1,1,16.851167315175097,378,2,1,4.097278594970703,-1,3,1,10.780341744422913,379,4,1,6.515114188194275,380,5,1,9.811091780662537,381,6,1,6.216014504432678,382,7,1,4.199619770050049,383,8,1,4.32025671005249,384,9,1,9.598315358161926,385]}}
  #|{"textrec":{"m":[17,600,0],"r":[16.435546875,3.5859375,24]}}
  #|{"textrec":{"s":[11,400,0,"studio"],"r":[0,1,5.79541015625,386,1,1,4.03369140625,387,2,1,6.48291015625,388,3,1,6.8212890625,389,4,1,2.7822265625,390,5,1,6.5634765625,391]}}
  #|{"textrec":{"s":[17,400,0,"选择服务商"],"r":[0,1,16.851167315175097,392,1,1,16.851167315175097,393,2,1,16.851167315175097,394,3,1,16.851167315175097,395,4,1,16.851167315175104,396]}}
  #|{"textrec":{"g":392,"r":[811,50,18,18,-1,-15,0]}}
  #|{"textrec":{"g":393,"r":[830,50,18,18,-1,-15,0]}}
  #|{"textrec":{"g":394,"r":[849,50,18,17,-1,-14,0]}}
  #|{"textrec":{"g":395,"r":[868,50,18,18,-1,-15,0]}}
  #|{"textrec":{"g":396,"r":[887,50,18,18,-1,-15,0]}}
  #|{"textrec":{"g":377,"r":[906,50,19,18,-1,-15,0]}}
  #|{"textrec":{"g":378,"r":[926,50,18,18,-1,-15,0]}}
  #|{"textrec":{"g":379,"r":[945,50,12,14,0,-13,0]}}
  #|{"textrec":{"g":380,"r":[958,50,8,12,0,-11,0]}}
  #|{"textrec":{"g":381,"r":[967,50,12,13,-1,-11,0]}}
  #|{"textrec":{"g":382,"r":[980,50,9,15,-1,-14,0]}}
  #|{"textrec":{"g":383,"r":[990,50,5,16,0,-15,0]}}
  #|{"textrec":{"g":384,"r":[996,50,5,15,0,-14,0]}}
  #|{"textrec":{"g":385,"r":[1002,50,12,13,-1,-11,0]}}
  #|{"textrec":{"g":386,"r":[1015,50,8,9,-1,-7,0]}}
  #|{"textrec":{"g":387,"r":[1024,50,6,11,-1,-9,0]}}
  #|{"textrec":{"g":388,"r":[1031,50,8,9,-1,-7,0]}}
  #|{"textrec":{"g":389,"r":[1040,50,8,12,-1,-10,0]}}
  #|{"textrec":{"g":390,"r":[1049,50,5,11,-1,-10,0]}}
  #|{"textrec":{"g":391,"r":[1055,50,8,9,-1,-7,0]}}
  #|{"textrec":{"s":[17,600,0,"选择服务商"],"r":[0,1,16.851167315175097,397,1,1,16.851167315175097,398,2,1,16.851167315175097,399,3,1,16.851167315175097,400,4,1,16.851167315175104,401]}}
  #|{"textrec":{"s":[13,400,0,"订阅和 API key 都在这里添加，选择服务商开始"],"r":[0,1,12.898832684824903,402,1,1,12.898832684824903,403,2,1,12.898832684824903,280,3,1,3.580078125,-1,4,1,8.68359375,404,5,1,8.18212890625,405,6,1,3.40234375,406,7,1,3.580078125000007,-1,8,1,6.82373046875,9,9,1,7.12841796875,14,10,1,6.9189453125,407,11,1,3.580078125,-1,12,1,12.898832684824896,408,13,1,12.898832684824896,1,14,1,12.898832684824896,409,15,1,12.898832684824896,410,16,1,12.898832684824896,411,17,1,12.898832684824896,412,18,1,13.075875486381335,225,19,1,12.898832684824896,303,20,1,12.898832684824896,312,21,1,12.898832684824896,413,22,1,12.898832684824896,138,23,1,12.898832684824896,414,24,1,12.898832684824896,415,25,1,12.898832684824924,416]}}
  #|{"textrec":{"s":[13,400,0,"模型厂商"],"r":[0,1,12.898832684824903,304,1,1,12.898832684824903,305,2,1,12.898832684824903,417,3,1,12.898832684824903,414]}}
  #|{"textrec":{"s":[15,400,0,"OpenAI"],"r":[0,1,11.337890625,418,1,1,8.9208984375,92,2,1,8.3349609375,95,3,1,8.51806640625,103,4,1,9.873046875,419,5,1,3.779296875,420]}}
  #|{"textrec":{"s":[15,400,0,"Anthropic"],"r":[0,1,9.873046875,419,1,1,8.51806640625,103,2,1,5.21484375,101,3,1,8.59130859375,421,4,1,5.36865234375,89,5,1,8.51806640625,88,6,1,8.9208984375,92,7,1,3.4716796875,102,8,1,8.1591796875,94]}}
  #|{"textrec":{"s":[15,400,0,"Google Gemini"],"r":[0,1,10.96435546875,422,1,1,8.6279296875,88,2,1,8.6279296875,88,3,1,8.90625,423,4,1,3.5595703125,108,5,1,8.3349609375,95,6,1,3.984375,-1,7,1,10.96435546875,422,8,1,8.3349609375,95,9,1,12.8173828125,161,10,1,3.4716796875,102,11,1,8.51806640625,103,12,1,3.4716796875,102]}}
  #|{"textrec":{"s":[15,400,0,"xAI"],"r":[0,1,7.59521484375,424,1,1,9.83642578125,419,2,1,3.779296875,420]}}
  #|{"textrec":{"s":[15,400,0,"Mistral"],"r":[0,1,12.8759765625,425,1,1,3.4716796875,102,2,1,7.58056640625,91,3,1,5.17822265625,101,4,1,5.478515625,89,5,1,8.0419921875,93,6,1,3.5595703125,108]}}
  #|{"textrec":{"s":[15,400,0,"DeepSeek"],"r":[0,1,10.6640625,426,1,1,8.3349609375,95,2,1,8.3349609375,95,3,1,8.9208984375,92,4,1,9.32373046875,100,5,1,8.3349609375,95,6,1,8.3349609375,95,7,1,7.91015625,90]}}
  #|{"textrec":{"s":[15,400,0,"Qwen"],"r":[0,1,11.337890625,427,1,1,11.2353515625,428,2,1,8.1884765625,95,3,1,8.51806640625,103]}}
  #|{"textrec":{"s":[15,400,0,"Kimi"],"r":[0,1,9.64599609375,429,1,1,3.4716796875,102,2,1,12.8173828125,161,3,1,3.4716796875,102]}}
  #|{"textrec":{"s":[15,400,0,"Z.ai"],"r":[0,1,9.68994140625,430,1,1,4.21875,160,2,1,8.0419921875,93,3,1,3.4716796875,102]}}
  #|{"textrec":{"s":[15,400,0,"MiniMax"],"r":[0,1,12.8759765625,425,1,1,3.4716796875,102,2,1,8.51806640625,103,3,1,3.4716796875,102,4,1,12.8759765625,425,5,1,8.0419921875,93,6,1,7.6318359375,424]}}
  #|{"textrec":{"s":[15,400,0,"Xiaomi MiMo"],"r":[0,1,9.9462890625,431,1,1,3.4716796875,102,2,1,8.0419921875,93,3,1,8.6279296875,88,4,1,12.8173828125,161,5,1,3.4716796875,102,6,1,3.984375,-1,7,1,12.8759765625,425,8,1,3.4716796875,102,9,1,12.8759765625,425,10,1,8.6279296875,88]}}
  #|{"textrec":{"s":[15,400,0,"Ant Ling"],"r":[0,1,9.873046875,419,1,1,8.51806640625,103,2,1,5.21484375,101,3,1,3.984375,-1,4,1,8.28369140625,432,5,1,3.4716796875,102,6,1,8.51806640625,103,7,1,8.90625,423]}}
  #|{"textrec":{"s":[15,400,0,"Jev"],"r":[0,1,7.8369140625,433,1,1,8.26171875,95,2,1,7.822265625,434]}}
  #|{"textrec":{"s":[13,400,0,"中转站"],"r":[0,1,12.898832684824903,311,1,1,12.898832684824903,284,2,1,12.898832684824903,435]}}
  #|{"textrec":{"s":[15,400,0,"OpenRouter"],"r":[0,1,11.337890625,418,1,1,8.9208984375,92,2,1,8.3349609375,95,3,1,8.51806640625,103,4,1,9.45556640625,436,5,1,8.51806640625,88,6,1,8.51806640625,163,7,1,5.159912109375,101,8,1,8.280029296875,95,9,1,5.478515625,89]}}
  #|{"textrec":{"s":[15,400,0,"Vercel AI Gateway"],"r":[0,1,9.5068359375,437,1,1,7.96875,95,2,1,5.36865234375,89,3,1,8.04931640625,94,4,1,8.3349609375,95,5,1,3.5595703125,108,6,1,3.984375,-1,7,1,9.873046875,419,8,1,3.779296875,420,9,1,3.984375,-1,10,1,10.96435546875,422,11,1,8.0419921875,93,12,1,5.159912109375,101,13,1,8.280029296875,95,14,1,11.27197265625,428,15,1,7.78564453125,93,16,1,7.763671875,438]}}
  #|{"textrec":{"s":[15,400,0,"OpenCode Zen"],"r":[0,1,11.337890625,418,1,1,8.9208984375,92,2,1,8.3349609375,95,3,1,8.51806640625,103,4,1,10.5029296875,439,5,1,8.6279296875,88,6,1,8.9794921875,440,7,1,8.3349609375,95,8,1,3.984375,-1,9,1,9.580078125,430,10,1,8.22509765625,95,11,1,8.51806640625,103]}}
  #|{"textrec":{"s":[15,400,0,"OpenCode Go"],"r":[0,1,11.337890625,418,1,1,8.9208984375,92,2,1,8.3349609375,95,3,1,8.51806640625,103,4,1,10.5029296875,439,5,1,8.6279296875,88,6,1,8.9794921875,440,7,1,8.3349609375,95,8,1,3.984375,-1,9,1,10.96435546875,422,10,1,8.6279296875,88]}}
  #|{"textrec":{"s":[15,400,0,"Cloudflare AI Gateway"],"r":[0,1,10.5029296875,439,1,1,3.5595703125,108,2,1,8.6279296875,88,3,1,8.51806640625,163,4,1,8.9794921875,440,5,1,5.19287109375,107,6,1,3.5595703125,108,7,1,8.0419921875,93,8,1,5.36865234375,89,9,1,8.22509765625,95,10,1,3.984375,-1,11,1,9.873046875,419,12,1,3.779296875,420,13,1,3.984375,-1,14,1,10.96435546875,422,15,1,8.0419921875,93,16,1,5.159912109375,101,17,1,8.280029296875,95,18,1,11.27197265625,428,19,1,7.78564453125,93,20,1,7.763671875,438]}}
  #|{"textrec":{"g":375,"r":[1064,50,18,17,-1,-14,0]}}
  #|{"textrec":{"g":376,"r":[1083,50,18,18,-1,-15,0]}}
  #|{"textrec":{"g":397,"r":[1102,50,18,18,-1,-15,0]}}
  #|{"textrec":{"g":398,"r":[1121,50,19,18,-1,-15,0]}}
  #|{"textrec":{"g":399,"r":[1141,50,18,18,-1,-15,0]}}
  #|{"textrec":{"g":400,"r":[1160,50,18,18,-1,-15,0]}}
  #|{"textrec":{"g":401,"r":[1179,50,18,18,-1,-15,0]}}
  #|{"textrec":{"g":402,"r":[1198,50,15,15,-1,-12,0]}}
  #|{"textrec":{"g":403,"r":[1214,50,13,15,0,-12,0]}}
  #|{"textrec":{"g":404,"r":[1228,50,11,12,-1,-11,0]}}
  #|{"textrec":{"g":405,"r":[1240,50,9,12,0,-11,0]}}
  #|{"textrec":{"g":406,"r":[1250,50,4,12,0,-11,0]}}
  #|{"textrec":{"g":9,"r":[1255,50,8,12,0,-11,0]}}
  #|{"textrec":{"g":407,"r":[1264,50,9,12,-1,-8,0]}}
  #|{"textrec":{"g":408,"r":[1274,50,14,15,-1,-12,0]}}
  #|{"textrec":{"g":409,"r":[1289,50,15,15,-1,-12,0]}}
  #|{"textrec":{"g":410,"r":[1305,50,14,13,-1,-11,0]}}
  #|{"textrec":{"g":411,"r":[1320,50,15,15,-1,-12,0]}}
  #|{"textrec":{"g":412,"r":[1336,50,14,15,-1,-12,0]}}
  #|{"textrec":{"g":413,"r":[1351,50,15,14,-1,-11,0]}}
  #|{"textrec":{"g":138,"r":[1367,50,15,15,-1,-12,0]}}
  #|{"textrec":{"g":414,"r":[1383,50,14,15,-1,-12,0]}}
  #|{"textrec":{"g":415,"r":[1398,50,14,14,-1,-11,0]}}
  #|{"textrec":{"g":416,"r":[1413,50,15,15,-1,-12,0]}}
  #|{"textrec":{"g":417,"r":[1429,50,14,14,-1,-11,0]}}
  #|{"textrec":{"g":418,"r":[1444,50,13,14,-1,-12,0]}}
  #|{"textrec":{"g":419,"r":[1458,50,12,13,-1,-12,0]}}
  #|{"textrec":{"g":420,"r":[1471,50,4,13,0,-12,0]}}
  #|{"textrec":{"g":421,"r":[1476,50,9,14,0,-13,0]}}
  #|{"textrec":{"g":422,"r":[1486,50,13,14,-1,-12,0]}}
  #|{"textrec":{"g":423,"r":[1500,50,10,14,-1,-10,0]}}
  #|{"textrec":{"g":161,"r":[1511,50,13,11,0,-10,0]}}
  #|{"textrec":{"g":424,"r":[1525,50,10,10,-1,-9,0]}}
  #|{"textrec":{"g":425,"r":[1536,50,13,13,0,-12,0]}}
  #|{"textrec":{"g":426,"r":[1550,50,11,13,0,-12,0]}}
  #|{"textrec":{"g":427,"r":[1562,50,13,15,-1,-12,0]}}
  #|{"textrec":{"g":428,"r":[1576,50,14,10,-1,-9,0]}}
  #|{"textrec":{"g":429,"r":[1591,50,11,13,0,-12,0]}}
  #|{"textrec":{"g":430,"r":[1603,50,10,13,0,-12,0]}}
  #|{"textrec":{"g":160,"r":[1614,50,5,5,0,-3,0]}}
  #|{"textrec":{"g":431,"r":[1620,50,12,13,-1,-12,0]}}
  #|{"textrec":{"g":432,"r":[1633,50,9,13,0,-12,0]}}
  #|{"textrec":{"g":433,"r":[1643,50,9,14,-1,-12,0]}}
  #|{"textrec":{"g":434,"r":[1653,50,10,10,-1,-9,0]}}
  #|{"textrec":{"g":435,"r":[1664,50,15,15,-1,-12,0]}}
  #|{"textrec":{"g":436,"r":[1680,50,11,13,0,-12,0]}}
  #|{"textrec":{"g":163,"r":[1692,50,9,11,0,-9,0]}}
  #|{"textrec":{"g":437,"r":[1702,50,12,13,-1,-12,0]}}
  #|{"textrec":{"g":438,"r":[1715,50,10,13,-1,-9,0]}}
  #|{"textrec":{"ib":["f7d3baf10841b61d",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"ib":["7e9322e1e57d8f14",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"ib":["9ec0c7d4565791e8",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"ib":["1a67d445e0141881",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"ib":["39ac0a6c75b310b8",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"ib":["696d002b176ad4fa",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"ib":["a32099c476296f3f",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"ib":["3abf219eddf6203f",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"ib":["690cbce6990d858d",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"ib":["6970d96f886d6fb3",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"ib":["e932ab59ee7feee8",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"ib":["1fd6fa30b6d8229b",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"ib":["f87f07e363909302",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"ib":["543ae25d0f4b1d5b",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"ib":["7303c0bcb31a9483",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"s":[17,600,0,"连接 Anthropic"],"r":[0,1,16.851167315175097,441,1,1,16.851167315175097,442,2,1,4.097278594970703,-1,3,1,11.654264450073242,443,4,1,9.958284735679626,444,5,1,6.2750866413116455,445,6,1,10.041292548179626,446,7,1,6.515114188194275,380,8,1,9.811091780662537,381,9,1,10.338602781295776,447,10,1,4.199619770050049,383,11,1,9.38069748878479,448]}}
  #|{"textrec":{"s":[15,400,0,"订阅 · Claude"],"r":[0,1,14.883268482490273,449,1,1,14.883268482490273,450,2,1,3.984375,-1,3,1,7.186782927948599,451,4,1,3.984375,-1,5,1,10.5029296875,439,6,1,3.5595703125,108,7,1,8.0419921875,93,8,1,8.51806640625,163,9,1,8.9794921875,440,10,1,8.3349609375,95]}}
  #|{"textrec":{"s":[12,400,0,"Claude Pro / Max，用于运行 Claude Code。在浏览器中登录一次。"],"r":[0,1,8.58984375,452,1,1,3.03515625,453,2,1,6.62109375,454,3,1,7.001953125,455,4,1,7.37109375,456,5,1,6.85546875,457,6,1,3.375,-1,7,1,7.623046875,458,8,1,4.482421875,459,9,1,7.001953125,460,10,1,3.375,-1,11,1,3.65625,461,12,1,3.375,-1,13,1,10.48828125,462,14,1,6.62109375,454,15,1,6.29296875,463,16,1,12.081712062256813,464,17,1,11.918287937743187,465,18,1,11.918287937743202,466,19,1,11.918287937743202,467,20,1,11.918287937743202,468,21,1,3.375,-1,22,1,8.58984375,452,23,1,3.03515625,453,24,1,6.62109375,454,25,1,7.001953125,455,26,1,7.37109375,456,27,1,6.85546875,457,28,1,3.375,-1,29,1,8.58984375,452,30,1,7.08984375,460,31,1,7.37109375,456,32,1,6.85546875,457,33,1,12.081712062256798,469,34,1,11.918287937743202,470,35,1,11.918287937743202,471,36,1,11.918287937743173,472,37,1,11.918287937743173,473,38,1,11.918287937743173,474,39,1,11.918287937743173,475,40,1,11.918287937743173,476,41,1,11.918287937743173,477,42,1,11.918287937743173,478,43,1,6.081712062256827,469]}}
  #|{"textrec":{"s":[15,400,0,"API key"],"r":[0,1,9.873046875,419,1,1,9.29443359375,106,2,1,3.779296875,420,3,1,3.984375,-1,4,1,7.72705078125,90,5,1,8.07861328125,95,6,1,7.8369140625,438]}}
  #|{"textrec":{"s":[12,400,0,"使用 Anthropic 的 API key，按量计费"],"r":[0,1,11.918287937743191,479,1,1,11.918287937743191,465,2,1,3.375,-1,3,1,8.0859375,480,4,1,7.001953125,481,5,1,4.359375,482,6,1,7.060546875,483,7,1,4.482421875,459,8,1,7.001953124999993,460,9,1,7.32421875,484,10,1,2.96484375,485,11,1,6.71484375,486,12,1,3.375,-1,13,1,11.918287937743187,487,14,1,3.375,-1,15,1,8.0859375,480,16,1,7.623046875,458,17,1,3.2109375,488,18,1,3.375,-1,19,1,6.369140625000014,489,20,1,6.650390625,457,21,1,6.45703125,490,22,1,12.081712062256798,464,23,1,11.918287937743202,491,24,1,11.918287937743202,492,25,1,11.918287937743202,493,26,1,11.918287937743202,494]}}
  #|{"textrec":{"g":441,"r":[1726,50,18,18,-1,-15,0]}}
  #|{"textrec":{"g":442,"r":[1745,50,18,18,-1,-15,0]}}
  #|{"textrec":{"g":443,"r":[1764,50,14,14,-1,-13,0]}}
  #|{"textrec":{"g":444,"r":[1779,50,11,12,0,-11,0]}}
  #|{"textrec":{"g":445,"r":[1791,50,8,15,-1,-13,0]}}
  #|{"textrec":{"g":446,"r":[1800,50,11,15,0,-14,0]}}
  #|{"textrec":{"g":447,"r":[1812,50,11,16,0,-11,0]}}
  #|{"textrec":{"g":448,"r":[1824,50,12,13,-1,-11,0]}}
  #|{"textrec":{"g":449,"r":[1837,50,17,16,-1,-13,0]}}
  #|{"textrec":{"g":450,"r":[1855,50,15,17,0,-14,0]}}
  #|{"textrec":{"g":451,"r":[1871,50,5,5,1,-8,0]}}
  #|{"textrec":{"g":439,"r":[1877,50,12,14,-1,-12,0]}}
  #|{"textrec":{"g":440,"r":[1890,50,10,15,-1,-13,0]}}
  #|{"textrec":{"g":452,"r":[1901,50,10,12,-1,-10,0]}}
  #|{"textrec":{"g":453,"r":[1912,50,4,11,0,-10,0]}}
  #|{"textrec":{"g":454,"r":[1917,50,8,10,-1,-8,0]}}
  #|{"textrec":{"g":455,"r":[1926,50,9,10,-1,-8,0]}}
  #|{"textrec":{"g":456,"r":[1936,50,9,12,-1,-10,0]}}
  #|{"textrec":{"g":457,"r":[1946,50,9,10,-1,-8,0]}}
  #|{"textrec":{"g":458,"r":[1956,50,8,11,0,-10,0]}}
  #|{"textrec":{"g":459,"r":[1965,50,7,9,-1,-8,0]}}
  #|{"textrec":{"g":460,"r":[1973,50,9,10,-1,-8,0]}}
  #|{"textrec":{"g":461,"r":[1983,50,6,14,-1,-10,0]}}
  #|{"textrec":{"g":462,"r":[1990,50,11,11,0,-10,0]}}
  #|{"textrec":{"g":463,"r":[2002,50,8,9,-1,-8,0]}}
  #|{"textrec":{"g":464,"r":[2011,50,5,6,0,-3,0]}}
  #|{"textrec":{"g":465,"r":[2017,50,13,14,-1,-11,0]}}
  #|{"textrec":{"g":466,"r":[2031,50,13,14,-1,-11,0]}}
  #|{"textrec":{"g":467,"r":[0,69,14,14,-1,-11,0]}}
  #|{"textrec":{"g":468,"r":[15,69,14,14,-1,-11,0]}}
  #|{"textrec":{"g":469,"r":[30,69,6,6,0,-3,0]}}
  #|{"textrec":{"g":470,"r":[37,69,14,14,-1,-11,0]}}
  #|{"textrec":{"g":471,"r":[52,69,13,14,-1,-11,0]}}
  #|{"textrec":{"g":472,"r":[66,69,13,14,-1,-11,0]}}
  #|{"textrec":{"g":473,"r":[80,69,14,14,-1,-11,0]}}
  #|{"textrec":{"g":474,"r":[95,69,12,14,0,-11,0]}}
  #|{"textrec":{"g":475,"r":[108,69,14,13,-1,-11,0]}}
  #|{"textrec":{"g":476,"r":[123,69,13,14,-1,-11,0]}}
  #|{"textrec":{"g":477,"r":[137,69,14,4,-1,-6,0]}}
  #|{"textrec":{"g":478,"r":[152,69,14,14,-1,-11,0]}}
  #|{"textrec":{"g":479,"r":[167,69,14,14,-1,-11,0]}}
  #|{"textrec":{"g":480,"r":[182,69,10,11,-1,-10,0]}}
  #|{"textrec":{"g":481,"r":[193,69,9,9,-1,-8,0]}}
  #|{"textrec":{"g":482,"r":[203,69,6,11,-1,-9,0]}}
  #|{"textrec":{"g":483,"r":[210,69,8,11,0,-10,0]}}
  #|{"textrec":{"g":484,"r":[219,69,9,12,-1,-8,0]}}
  #|{"textrec":{"g":485,"r":[229,69,5,11,-1,-10,0]}}
  #|{"textrec":{"g":486,"r":[235,69,9,10,-1,-8,0]}}
  #|{"textrec":{"g":487,"r":[245,69,13,14,-1,-11,0]}}
  #|{"textrec":{"g":488,"r":[259,69,4,11,0,-10,0]}}
  #|{"textrec":{"g":489,"r":[264,69,8,11,0,-10,0]}}
  #|{"textrec":{"g":490,"r":[273,69,9,12,-1,-8,0]}}
  #|{"textrec":{"g":491,"r":[283,69,14,14,-1,-11,0]}}
  #|{"textrec":{"g":492,"r":[298,69,14,13,-1,-11,0]}}
  #|{"textrec":{"g":493,"r":[313,69,14,14,-1,-11,0]}}
  #|{"textrec":{"g":494,"r":[328,69,13,14,-1,-11,0]}}
  #|{"textrec":{"s":[13,600,0,"API key"],"r":[0,1,9.165990829467773,495,1,1,8.497696995735168,496,2,1,3.8204212188720703,497,3,1,3.3871192932128906,-1,4,1,7.273967742919922,498,5,1,7.321376800537109,499,6,1,7.345062732696533,500]}}
  #|{"textrec":{"m":[13,600,0],"r":[12.568359375,2.7421875,18]}}
  #|{"textrec":{"s":[12,400,0,"key 仅保存在此 station 上"],"r":[0,1,6.369140625,489,1,1,6.650390625,457,2,1,6.45703125,490,3,1,3.375,-1,4,1,11.918287937743187,501,5,1,11.918287937743187,502,6,1,11.918287937743187,503,7,1,11.918287937743187,470,8,1,11.918287937743187,504,9,1,3.375,-1,10,1,6.251953125,505,11,1,4.330078125,482,12,1,6.62109375,454,13,1,4.359375,482,14,1,2.96484375,485,15,1,7.08984375,460,16,1,7.001953125,481,17,1,3.375,-1,18,1,11.918287937743187,506]}}
  #|{"textrec":{"s":[14,600,0,"验证并添加"],"r":[0,1,13.891050583657588,507,1,1,13.891050583657588,508,2,1,13.891050583657588,509,3,1,13.891050583657588,510,4,1,13.891050583657588,511]}}
  #|{"textrec":{"s":[13,400,0,"添加后可用于：Claude Code · DeepSeek Harness"],"r":[0,1,12.898832684824903,411,1,1,12.898832684824903,412,2,1,12.898832684824903,286,3,1,12.898832684824903,306,4,1,12.898832684824896,258,5,1,12.898832684824896,512,6,1,13.075875486381321,513,7,1,9.2294921875,514,8,1,3.2119140625,76,9,1,7.0966796875,12,10,1,7.50927734375,198,11,1,7.9091796875,199,12,1,7.350585937499986,14,13,1,3.580078125,-1,14,1,9.2294921875,514,15,1,7.6044921875,7,16,1,7.9091796875,199,17,1,7.3505859375,14,18,1,3.580078125,-1,19,1,6.228545204222115,232,20,1,3.580078125,-1,21,1,9.369140625,515,22,1,7.3505859375,14,23,1,7.3505859375,14,24,1,7.8583984375,11,25,1,8.20751953125,320,26,1,7.3505859375,14,27,1,7.3505859375,14,28,1,6.982421875,9,29,1,3.580078125,-1,30,1,9.572265624999972,516,31,1,7.0966796875,12,32,1,4.9384765625,8,33,1,7.57275390625,283,34,1,7.3505859375,14,35,1,6.6650390625,10,36,1,6.6650390625,10]}}
  #|{"textrec":{"g":495,"r":[342,69,11,12,-1,-11,0]}}
  #|{"textrec":{"g":496,"r":[354,69,9,12,0,-11,0]}}
  #|{"textrec":{"g":497,"r":[364,69,4,12,0,-11,0]}}
  #|{"textrec":{"g":498,"r":[369,69,9,12,0,-11,0]}}
  #|{"textrec":{"g":499,"r":[379,69,10,11,-1,-9,0]}}
  #|{"textrec":{"g":500,"r":[390,69,10,12,-1,-8,0]}}
  #|{"textrec":{"s":[15,400,0,"验证可用后再添加"],"r":[0,1,14.883268482490273,517,1,1,14.883268482490273,518,2,1,14.883268482490273,519,3,1,14.883268482490273,115,4,1,14.88326848249028,276,5,1,14.88326848249028,520,6,1,14.88326848249028,521,7,1,14.88326848249028,522]}}
  #|{"textrec":{"g":517,"r":[401,69,17,16,-1,-13,0]}}
  #|{"textrec":{"g":518,"r":[419,69,17,15,-1,-13,0]}}
  #|{"textrec":{"g":519,"r":[437,69,16,16,-1,-13,0]}}
  #|{"textrec":{"g":520,"r":[454,69,16,16,-1,-13,0]}}
  #|{"textrec":{"g":521,"r":[471,69,17,16,-1,-13,0]}}
  #|{"textrec":{"g":522,"r":[489,69,16,16,-1,-13,0]}}
  #|{"textrec":{"g":501,"r":[506,69,14,14,-1,-11,0]}}
  #|{"textrec":{"g":502,"r":[521,69,14,14,-1,-11,0]}}
  #|{"textrec":{"g":503,"r":[536,69,14,14,-1,-11,0]}}
  #|{"textrec":{"g":504,"r":[551,69,14,13,-1,-11,0]}}
  #|{"textrec":{"g":505,"r":[566,69,8,10,-1,-8,0]}}
  #|{"textrec":{"g":506,"r":[575,69,14,13,-1,-11,0]}}
  #|{"textrec":{"g":507,"r":[590,69,16,16,-1,-13,0]}}
  #|{"textrec":{"g":508,"r":[607,69,16,15,-1,-13,0]}}
  #|{"textrec":{"g":509,"r":[624,69,15,16,-1,-13,0]}}
  #|{"textrec":{"g":510,"r":[640,69,16,16,-1,-13,0]}}
  #|{"textrec":{"g":511,"r":[657,69,15,16,-1,-13,0]}}
  #|{"textrec":{"g":512,"r":[673,69,14,14,-1,-11,0]}}
  #|{"textrec":{"g":513,"r":[688,69,4,9,1,-9,0]}}
  #|{"textrec":{"g":514,"r":[693,69,11,13,-1,-11,0]}}
  #|{"textrec":{"g":515,"r":[705,69,10,12,0,-11,0]}}
  #|{"textrec":{"g":516,"r":[716,69,10,12,0,-11,0]}}
  #|{"textrec":{"g":8,"r":[727,69,6,9,0,-8,0]}}
  #|{"textrec":{"s":[15,400,0,"•••••••••••••••••••••••••••••••"],"r":[0,1,6.8408203125,523,1,1,6.8408203125,523,2,1,6.8408203125,523,3,1,6.8408203125,523,4,1,6.8408203125,523,5,1,6.8408203125,523,6,1,6.8408203125,523,7,1,6.8408203125,523,8,1,6.8408203125,523,9,1,6.8408203125,523,10,1,6.8408203125,523,11,1,6.8408203125,523,12,1,6.8408203125,523,13,1,6.8408203125,523,14,1,6.8408203125,523,15,1,6.8408203125,523,16,1,6.8408203125,523,17,1,6.8408203125,523,18,1,6.8408203125,523,19,1,6.8408203125,523,20,1,6.8408203125,523,21,1,6.8408203125,523,22,1,6.8408203125,523,23,1,6.8408203125,523,24,1,6.8408203125,523,25,1,6.8408203125,523,26,1,6.8408203125,523,27,1,6.8408203125,523,28,1,6.8408203125,523,29,1,6.8408203125,523,30,1,6.8408203125,523]}}
  #|{"textrec":{"g":523,"r":[734,69,6,6,1,-7,0]}}
