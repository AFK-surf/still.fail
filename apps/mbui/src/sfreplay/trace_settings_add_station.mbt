// e2e/traces/settings-add-station.trace, made by scripts/trace.py from 01-settings_add_station.run.log: not edited by hand.

///|
/// What the app and its core said in the run, a line each.
pub let trace_settings_add_station : String =
  #|{"start":"base"}
  #|{"step":"drive-seed 080726"}
  #|{"env":{"MBUI_CLOUD":"http://127.0.0.1:18900","MBUI_CORE_ACCOUNT":"{\"sub\":\"alice\",\"email\":\"alice@example.test\",\"name\":\"Name of alice\",\"picture\":\"\",\"access\":\"-\",\"refresh\":\"-\",\"accessExpires\":1792533180}"}}
  #|{"out":{"id":1,"call":"client.device","params":{"client":"still.fail mbui","app":"desktop","userAgent":"Macintosh; Mac OS X"}},"w":1792532891284.68}
  #|{"in":{"id":1,"ok":null},"w":1792532891398.906}
  #|{"out":{"id":2,"subscribe":{"topic":"accounts"},"keyed":true},"w":1792532891398.943}
  #|{"out":{"id":3,"subscribe":{"topic":"prefs"},"keyed":true},"w":1792532891398.96}
  #|{"step":"# written by scripts/rerecord.sh from its test (src/sfreplay/emit.mbt): not edited by hand","w":1792532891402.068}
  #|{"step":"timeout 90000","w":1792532891402.086}
  #|{"step":"answered client.device","w":1792532891402.103}
  #|{"step":"answered client.focus","w":1792532891435.106}
  #|{"in":{"id":2,"value":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""}]},"w":1792532891484.44}
  #|{"in":{"id":3,"value":{"onlyMine":false,"onlyWatching":false,"onlyDecisions":false,"listFilter":{},"appearance":"system","rowPicture":"auto","absoluteTime":false,"lang":"zh","keys":{},"lastChat":{},"openChat":{},"chatTabs":{},"dropFiles":{},"driveViews":{},"resume":{},"stationUpdatesDismissed":{},"device":{"app":"desktop","phone":false,"handoff":false},"reader":{"size":18,"line":1.7,"margin":22,"face":"sans","indent":true,"paper":"follow"},"rails":{},"bars":{"sets":[["chats","files","profiles","stations"],["decisions","usage","connects","archive"]],"current":0},"barsBy":{}}},"w":1792532891484.464}
  #|{"out":{"id":4,"subscribe":{"topic":"workspaces"},"keyed":true},"w":1792532891484.493}
  #|{"out":{"id":5,"subscribe":{"topic":"status"},"keyed":true},"w":1792532891484.509}
  #|{"in":{"id":4,"value":[{"account":{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""},"workspaces":[{"id":"01M5DMJ2XHDVX85EMMG6Y5N5BW","name":"Dev","role":"owner","created_at":1792532876,"stations":1,"members":1,"relays":[],"time":{"created_at":{"past":true,"at":1792532876000,"ago":"刚刚","full":"10/21 05:47:56","until":"1 分钟内"}}}],"invitations":[],"relay_url":"http://127.0.0.1:18940","loaded":true,"beta":true}]},"w":1792532891501.103}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792532891501.116}
  #|{"out":{"id":6,"subscribe":{"topic":"lock","workspace":"01M5DMJ2XHDVX85EMMG6Y5N5BW"},"keyed":true},"w":1792532891501.144}
  #|{"out":{"id":7,"subscribe":{"topic":"chats","scope":"01M5DMJ2XHDVX85EMMG6Y5N5BW","mine":false},"keyed":true},"w":1792532891501.159}
  #|{"out":{"id":8,"subscribe":{"topic":"workspaceMarks","workspace":"01M5DMJ2XHDVX85EMMG6Y5N5BW"},"keyed":true},"w":1792532891501.281}
  #|{"out":{"id":9,"subscribe":{"topic":"status","workspace":"01M5DMJ2XHDVX85EMMG6Y5N5BW"},"keyed":true},"w":1792532891501.313}
  #|{"out":{"id":10,"call":"client.focus","params":{"visible":true,"focused":true,"workspace":"01M5DMJ2XHDVX85EMMG6Y5N5BW"}},"w":1792532891506.741}
  #|{"out":{"id":11,"subscribe":{"topic":"notify"},"keyed":true},"w":1792532891506.751}
  #|{"out":{"id":12,"subscribe":{"topic":"notify","workspace":"01M5DMJ2XHDVX85EMMG6Y5N5BW"},"keyed":true},"w":1792532891506.757}
  #|{"in":{"id":6,"value":{"available":true,"locked":false,"notice":true,"role":"owner","manages":true,"owner":true,"canSign":true,"signs":false,"me":{"device":"1915699e2549926924933eeeebef0b46f9bbaa16779f550436f92c16fc19e812","code":"L2F-FLD","kind":"app","confirmed":false,"waiting":false,"asked":false},"signers":0,"members":[],"stations":[{"id":"bb13a80c91c04f8ffaa4e7763853c9f95ef37c729dc491de6f5e899c13eacc83","name":"studio","version":"0.1.0","online":true,"protected":false}],"protected":0,"requests":[],"renew":[],"attention":0}},"w":1792532891517.774}
  #|{"in":{"id":7,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"stations":[{"station":"01M5DMJ2XHDVX85EMMG6Y5N5BW/bb13a80c91c04f8ffaa4e7763853c9f95ef37c729dc491de6f5e899c13eacc83","id":"bb13a80c91c04f8ffaa4e7763853c9f95ef37c729dc491de6f5e899c13eacc83","name":"studio","state":"online"}],"loading":false,"days":[{"daysAgo":0,"at":1792532880174,"label":"今天","items":[{"id":"ember:c-2c805eb174","session":"ember:c-2c805eb174","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","agents":[{"key":"ember:c-2c805eb174","runtime":"claude","process":"warm","pending":0,"lastTurn":{"id":"71a60e2d-dce1-4c2a-9fab-8124e55aac85","kind":"input","outcome":"completed","declared":"final","ending":"all_done","need":"answered the question that was asked","startedAt":1792532880064,"endedAt":1792532880179},"agentText":"默认模型","statusText":"已完成：answered the question that was asked"}],"last":{"seq":2,"authorKind":"agent","author":"ember:c-2c805eb174","text":"你好，我是测试用的 agent","createdAt":1792532880174,"by":{"kind":"agent","name":"agent","mine":false,"runtime":"claude","label":"agent"},"preview":"你好，我是测试用的 agent","time":{"createdAt":{"at":1792532880174,"ago":"刚刚","full":"10/21 05:48:00","until":"1 分钟内","past":true}}},"unread":true,"mine":true,"lastActiveAt":1792532880174,"station":"01M5DMJ2XHDVX85EMMG6Y5N5BW/bb13a80c91c04f8ffaa4e7763853c9f95ef37c729dc491de6f5e899c13eacc83","stationName":"studio","time":{"lastActiveAt":{"at":1792532880174,"ago":"刚刚","full":"10/21 05:48:00","until":"1 分钟内","past":true}},"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"peopleText":"你 发起","clientKey":"new:chat-012af7064fb62c9450","pinned":false,"tone":"done"}]}],"trouble":null,"members":1,"leading":"agents","glyph":{"online":1,"dim":0,"connecting":0,"failing":0,"working":0,"summary":"studio","label":"1 台 station，1 台在线"},"note":{"reading":false,"text":null,"failing":[],"empty":false}}},"w":1792532891517.804}
  #|{"in":{"id":8,"value":{"workspaces":{"01M5DMJ2XHDVX85EMMG6Y5N5BW":{"alert":0,"unread":1,"tone":"done","label":"1 个有新消息","badge":0,"items":[],"mineTone":"done"}},"badge":0,"badgeCounts":"attention","badgeKinds":{"on":true,"wait":true,"failed":true,"done":false,"message":false}}},"w":1792532891517.827}
  #|{"in":{"id":9,"value":{"items":[]}},"w":1792532891517.832}
  #|{"in":{"id":10,"ok":null},"w":1792532891517.834}
  #|{"in":{"id":11,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792532891517.843}
  #|{"in":{"id":12,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792532891517.847}
  #|{"out":{"id":13,"subscribe":{"topic":"longJobs","scope":"01M5DMJ2XHDVX85EMMG6Y5N5BW"},"keyed":true},"w":1792532891517.874}
  #|{"out":{"id":14,"call":"notify.permission","params":{"state":"unknown"}},"w":1792532891520.486}
  #|{"in":{"id":13,"value":{"groups":[]}},"w":1792532891536.49}
  #|{"in":{"id":14,"ok":null},"w":1792532891536.498}
  #|{"step":"answered notify.permission","w":1792532891536.752}
  #|{"step":"tap icon:settings","w":1792532891551.308}
  #|{"step":"tap icon:settings","acted":true,"w":1792532891568.043}
  #|{"out":{"id":15,"subscribe":{"topic":"workspace","workspace":"01M5DMJ2XHDVX85EMMG6Y5N5BW"},"keyed":true},"w":1792532891584.588}
  #|{"out":{"id":16,"subscribe":{"topic":"stations","scope":"01M5DMJ2XHDVX85EMMG6Y5N5BW"},"keyed":true},"w":1792532891584.626}
  #|{"out":{"id":17,"subscribe":{"topic":"connects","scope":"01M5DMJ2XHDVX85EMMG6Y5N5BW","mine":false},"keyed":true},"w":1792532891584.634}
  #|{"out":{"id":18,"subscribe":{"topic":"vaults","workspace":"01M5DMJ2XHDVX85EMMG6Y5N5BW"},"keyed":true},"w":1792532891584.64}
  #|{"out":{"id":19,"subscribe":{"topic":"doing"},"keyed":true},"w":1792532891590.381}
  #|{"step":"rest","w":1792532891591.442}
  #|{"in":{"id":15,"value":{"id":"01M5DMJ2XHDVX85EMMG6Y5N5BW","name":"Dev","role":"owner","created_at":1792532876,"members":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":"https://example.test/p.png","role":"owner","added_at":1792532876}],"stations":[{"id":"bb13a80c91c04f8ffaa4e7763853c9f95ef37c729dc491de6f5e899c13eacc83","name":"studio","emoji":null,"icon":null,"enrolled_at":1792532876,"enrolled_by":"alice","last_seen":1792532882,"version":"0.1.0","time":{"last_seen":{"past":true,"at":1792532882000,"ago":"刚刚","full":"10/21 05:48:02","until":"1 分钟内"}}}],"invitations":[],"added":[],"relays":[],"lock":null,"lock_requests":0,"time":{"created_at":{"past":true,"at":1792532876000,"ago":"刚刚","full":"10/21 05:47:56","until":"1 分钟内"}}}},"w":1792532891601.114}
  #|{"in":{"id":16,"value":[{"station":"01M5DMJ2XHDVX85EMMG6Y5N5BW/bb13a80c91c04f8ffaa4e7763853c9f95ef37c729dc491de6f5e899c13eacc83","id":"bb13a80c91c04f8ffaa4e7763853c9f95ef37c729dc491de6f5e899c13eacc83","name":"studio","summary":"正在连接","face":"idle","line":"在线","online":true,"reconnecting":true,"lastSeen":1792532882,"version":"0.1.0","link":{"state":"connecting"},"runtimes":[{"runtime":"claude","models":["claude-sonnet-5-5"]}],"models":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792532880018,"time":{"checkedAt":{"at":1792532880018,"ago":"刚刚","full":"10/21 05:48:00","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"overview":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null,"summaryText":"最近 7 天检查了 0 个 chat","changeText":null}},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","email":"alice@example.test","name":"Name of alice","sub":"alice","role":"owner","workspace":"01M5DMJ2XHDVX85EMMG6Y5N5BW","device":"1915699e2549926924933eeeebef0b46f9bbaa16779f550436f92c16fc19e812"},"connects":[],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792532879869,"time":{"checkedAt":{"at":1792532879869,"ago":"刚刚","full":"10/21 05:47:59","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792532880018,"time":{"checkedAt":{"at":1792532880018,"ago":"刚刚","full":"10/21 05:48:00","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]}],"processes":[],"counts":{"sessions":1,"running":0,"warm":1},"mesh":{"state":"running","origin":"http://127.0.0.1:18900","station":"bb13a80c91c04f8ffaa4e7763853c9f95ef37c729dc491de6f5e899c13eacc83","workspace":"Dev","workspaceId":"01M5DMJ2XHDVX85EMMG6Y5N5BW","name":"studio"},"slackUsers":[],"slackTeams":[],"slackApps":[],"feishuRegistrations":[],"disk":{"freeBytes":58179633152,"totalBytes":245107195904},"logins":[],"machineLogins":[],"sharing":true,"consoleSignIn":true,"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"google","name":"Google Gemini","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xai","name":"xAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"mistral","name":"Mistral","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"deepseek","name":"DeepSeek","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen","name":"Qwen","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai","name":"Kimi","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai","name":"Z.ai","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax","name":"MiniMax","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ant-ling","name":"Ant Ling","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"jev","name":"Jev","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen-cn","name":"Qwen (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"openrouter","name":"OpenRouter","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"opencode","name":"OpenCode Zen","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"groq","name":"Groq","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"together","name":"Together AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"fireworks","name":"Fireworks","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cerebras","name":"Cerebras","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"huggingface","name":"Hugging Face","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"nvidia","name":"NVIDIA","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"baseten","name":"Baseten","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ollama","name":"Ollama","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"custom","name":"Custom","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""}],"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792532877416},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.305","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792532877416},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792532877416},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792532877416},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","latest":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792532877416}],"processesText":"没有运行中的 agent 进程","agentEnv":[],"drive":{"roots":[],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false}},"betaOffered":false,"time":{"lastSeen":{"at":1792532882000,"ago":"刚刚","full":"10/21 05:48:02","until":"1 分钟内","past":true}},"joined":false}]},"w":1792532891601.256}
  #|{"in":{"id":17,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"items":[],"wait":{"reading":false,"text":null,"failing":[],"empty":true}}},"w":1792532891601.345}
  #|{"in":{"id":18,"value":{"available":true,"locked":false,"canSign":false,"setUp":false,"vaults":[{"id":"plain","name":"个人","owner":"alice","ownerName":"Name of alice","mine":true,"members":[{"sub":"alice","name":"Name of alice"}],"station":"bb13a80c91c04f8ffaa4e7763853c9f95ef37c729dc491de6f5e899c13eacc83","stationName":"studio","items":0,"devices":0,"open":true,"keyed":true,"missing":0,"recoverable":false}],"requests":[],"refused":[{"station":"bb13a80c91c04f8ffaa4e7763853c9f95ef37c729dc491de6f5e899c13eacc83","name":"studio","code":"vault_needs_lock"}],"plain":true}},"w":1792532891601.355}
  #|{"in":{"id":19,"value":{"doing":[]}},"w":1792532891601.362}
  #|{"step":"now tap =Station","w":1792532892352.057}
  #|{"step":"now tap =Station","acted":true,"w":1792532892368.766}
  #|{"step":"rest","w":1792532892394.32}
  #|{"step":"now until =studio","w":1792532892717.887}
  #|{"step":"tap icon:plus","w":1792532892717.894}
  #|{"step":"tap icon:plus","acted":true,"w":1792532892734.555}
  #|{"out":{"id":20,"subscribe":{"topic":"joinable","workspace":"01M5DMJ2XHDVX85EMMG6Y5N5BW"},"keyed":true},"w":1792532892751.171}
  #|{"step":"rest","w":1792532892755.187}
  #|{"in":{"id":20,"value":{"offered":false,"loading":false,"items":[]}},"w":1792532892767.763}
  #|{"in":{"id":5,"value":{"state":"slow","text":"正在连接 studio ×3 · 2 秒 · 共 5 项","items":[{"state":"slow","text":"正在连接 studio ×3","detail":"已等待 2 秒"},{"state":"slow","text":"studio 打开实时更新 ×2","detail":"已等待 2 秒，尚未收到数据"}]}},"w":1792532893801.152}
  #|{"in":{"id":9,"value":{"state":"slow","text":"正在连接 studio ×3 · 2 秒 · 共 5 项","items":[{"state":"slow","text":"正在连接 studio ×3","detail":"已等待 2 秒"},{"state":"slow","text":"studio 打开实时更新 ×2","detail":"已等待 2 秒，尚未收到数据"}]}},"w":1792532893801.244}
  #|{"step":"now until 添加 station","w":1792532894218.809}
  #|{"step":"tap 例如机器名","w":1792532894218.867}
  #|{"step":"tap 例如机器名","acted":true,"w":1792532894235.564}
  #|{"step":"type e2e-080726-b","w":1792532894263.047}
  #|{"step":"type e2e-080726-b","acted":true,"w":1792532894263.071}
  #|{"step":"tap =生成命令","w":1792532894275.495}
  #|{"step":"tap =生成命令","acted":true,"w":1792532894284.874}
  #|{"out":{"id":21,"call":"workspace.enroll","params":{"workspace":"01M5DMJ2XHDVX85EMMG6Y5N5BW","name":"e2e-080726-b","account":"alice"}},"w":1792532894301.183}
  #|{"step":"answered workspace.enroll","w":1792532894301.398}
  #|{"in":{"id":21,"ok":{"token":"-","expires_at":1792536494,"install":"curl -fsSL http://127.0.0.1:18900/install.sh | sh -s -- N_56ewh5HwjSXf79IBNqKRXWmT1ukciD9YcQ9O5OIZk","installWindows":"& ([scriptblock]::Create((irm http://127.0.0.1:18900/install.ps1))) N_56ewh5HwjSXf79IBNqKRXWmT1ukciD9YcQ9O5OIZk","command":"stillfail station enroll http://127.0.0.1:18900 N_56ewh5HwjSXf79IBNqKRXWmT1ukciD9YcQ9O5OIZk"}},"w":1792532894317.764}
  #|{"step":"until 在该机器的终端中执行","w":1792532894334.784}
  #|{"step":"log do: second-station {LOG}","w":1792532894334.795}
  #|{"step":"second-station {LOG}"}
  #|{"step":"until 已加入","w":1792532894334.799}
  #|{"in":{"id":9,"delta":[{"path":["items",0,"detail"],"set":"已等待 3 秒"},{"path":["items",1,"detail"],"set":"已等待 3 秒，尚未收到数据"},{"path":["text"],"set":"正在连接 studio ×3 · 3 秒 · 共 5 项"}]},"w":1792532894386.35}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792532894434.423}
  #|{"in":{"id":9,"value":{"items":[]}},"w":1792532894434.437}
  #|{"in":{"id":7,"delta":[{"path":["days"],"key":["daysAgo"],"patch":0,"ops":[{"path":["items"],"key":["station","id"],"patch":["01M5DMJ2XHDVX85EMMG6Y5N5BW/bb13a80c91c04f8ffaa4e7763853c9f95ef37c729dc491de6f5e899c13eacc83","ember:c-2c805eb174"],"ops":[{"path":["agents",0,"process"],"set":"cold"},{"path":["clientKey"],"remove":true}]}]}]},"w":1792532894534.417}
  #|{"in":{"id":16,"delta":[{"path":[0,"link","state"],"set":"online"},{"path":[0,"overview","counts","warm"],"set":0},{"path":[0,"overview","disk","freeBytes"],"set":58172600320},{"path":[0,"overview","profiles",0,"check","checkedAt"],"set":1792532894318},{"path":[0,"overview","profiles",0,"check","time","checkedAt","at"],"set":1792532894318},{"path":[0,"overview","profiles",0,"check","time","checkedAt","full"],"set":"10/21 05:48:14"},{"path":[0,"overview","updates",0,"checkedAt"],"set":1792532891962},{"path":[0,"overview","updates",1,"checkedAt"],"set":1792532891962},{"path":[0,"overview","updates",2,"checkedAt"],"set":1792532891962},{"path":[0,"overview","updates",3,"checkedAt"],"set":1792532891962},{"path":[0,"overview","updates",4,"checkedAt"],"set":1792532891962},{"path":[0,"reconnecting"],"set":false}]},"w":1792532894534.453}
  #|{"in":{"id":16,"value":[{"station":"01M5DMJ2XHDVX85EMMG6Y5N5BW/bb13a80c91c04f8ffaa4e7763853c9f95ef37c729dc491de6f5e899c13eacc83","id":"bb13a80c91c04f8ffaa4e7763853c9f95ef37c729dc491de6f5e899c13eacc83","name":"studio","summary":"空闲 · Apple M4 · 16 GB · macOS 27.0.1","face":"idle","line":"Apple M4","online":true,"reconnecting":false,"lastSeen":1792532894,"version":"0.1.0","link":{"state":"online"},"runtimes":[{"runtime":"claude","models":["claude-sonnet-5-5"]}],"models":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792532880018,"time":{"checkedAt":{"at":1792532880018,"ago":"刚刚","full":"10/21 05:48:00","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"overview":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null,"summaryText":"最近 7 天检查了 0 个 chat","changeText":null}},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","email":"alice@example.test","name":"Name of alice","sub":"alice","role":"owner","workspace":"01M5DMJ2XHDVX85EMMG6Y5N5BW","device":"1915699e2549926924933eeeebef0b46f9bbaa16779f550436f92c16fc19e812"},"connects":[],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792532894318,"time":{"checkedAt":{"at":1792532894318,"ago":"刚刚","full":"10/21 05:48:14","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792532880018,"time":{"checkedAt":{"at":1792532880018,"ago":"刚刚","full":"10/21 05:48:00","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]}],"processes":[],"counts":{"sessions":1,"running":0,"warm":0},"mesh":{"state":"running","origin":"http://127.0.0.1:18900","station":"bb13a80c91c04f8ffaa4e7763853c9f95ef37c729dc491de6f5e899c13eacc83","workspace":"Dev","workspaceId":"01M5DMJ2XHDVX85EMMG6Y5N5BW","name":"studio"},"slackUsers":[],"slackTeams":[],"slackApps":[],"feishuRegistrations":[],"disk":{"freeBytes":58172354560,"totalBytes":245107195904},"logins":[],"machineLogins":[],"sharing":true,"consoleSignIn":true,"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"google","name":"Google Gemini","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xai","name":"xAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"mistral","name":"Mistral","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"deepseek","name":"DeepSeek","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen","name":"Qwen","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai","name":"Kimi","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai","name":"Z.ai","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax","name":"MiniMax","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ant-ling","name":"Ant Ling","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"jev","name":"Jev","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen-cn","name":"Qwen (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"openrouter","name":"OpenRouter","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"opencode","name":"OpenCode Zen","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"groq","name":"Groq","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"together","name":"Together AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"fireworks","name":"Fireworks","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cerebras","name":"Cerebras","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"huggingface","name":"Hugging Face","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"nvidia","name":"NVIDIA","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"baseten","name":"Baseten","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ollama","name":"Ollama","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"custom","name":"Custom","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""}],"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792532891962},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.305","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792532891962},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792532891962},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792532891962},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","latest":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792532891962}],"processesText":"没有运行中的 agent 进程","agentEnv":[],"drive":{"roots":[],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false}},"betaOffered":false,"host":{"hostname":"3720-Mac-mini-1","os":"macOS 27.0.1","arch":"arm64","cpus":10,"cpuModel":"Apple M4","load":0.35,"cpuBusy":0.25,"uptimeSec":12256,"memory":{"totalBytes":17179869184,"usedBytes":9815539712,"swapUsedBytes":333572997},"disk":{"path":"/tmp/mbe2e-C/data","totalBytes":245107195904,"freeBytes":58172497920},"emberRssBytes":138557048,"checkedAt":1792532894464,"summary":"10 核 · 16 GB","line":"macOS 27.0.1 · 10 核 · 16 GB · 已运行 0 天","facts":["3720-Mac-mini-1","macOS 27.0.1","arm64 · 10 核","已运行 3 小时"],"meters":[{"label":"CPU","short":"CPU","percent":25,"left":75,"level":"ok","value":"25%","remaining":"空闲 75%","big":"75","unit":"%","title":"CPU 空闲","total":"负载 3.5","note":"负载 3.5 · Apple M4"},{"label":"内存","short":"内存","percent":57,"left":43,"level":"ok","value":"9.1 GB / 16.0 GB","remaining":"剩 6.9 G","big":"6.9","unit":"GB","title":"内存剩","total":"共 16 GB","note":"swap 0.3 GB"},{"label":"磁盘","short":"磁盘","percent":76,"left":24,"level":"amber","value":"剩余 54.2 GB / 228 GB","remaining":"剩 54.2 G","big":"54.2","unit":"GB","title":"磁盘剩","total":"共 228 GB"}],"identity":"Apple M4 · 16 GB · macOS 27.0.1","details":[{"label":"主机名","value":"3720-Mac-mini-1"},{"label":"芯片","value":"Apple M4 · 10 核 · arm64"},{"label":"已运行","value":"3 小时"},{"label":"still.fail","value":"进程占用 132 MB"}],"usage":"内存 9.1 GB / 16.0 GB · 磁盘 剩余 54.2 GB / 228 GB","emberText":"still.fail 132 MB"},"time":{"lastSeen":{"at":1792532894000,"ago":"刚刚","full":"10/21 05:48:14","until":"1 分钟内","past":true}},"joined":false},{"station":"01M5DMJ2XHDVX85EMMG6Y5N5BW/3393fc76a6422b2a1640c4d5593165cff397ad429fe70ecc5e9ae63dbdae8b35","id":"3393fc76a6422b2a1640c4d5593165cff397ad429fe70ecc5e9ae63dbdae8b35","name":"e2e-080726-b","summary":"正在连接","face":"idle","line":"在线","online":true,"reconnecting":true,"lastSeen":1792532894,"version":"0.1.0","link":{"state":"connecting"},"runtimes":[],"models":[],"betaOffered":false,"time":{"lastSeen":{"at":1792532894000,"ago":"刚刚","full":"10/21 05:48:14","until":"1 分钟内","past":true}},"joined":false}]},"w":1792532894601.298}
  #|{"in":{"id":4,"delta":[{"path":[0,"workspaces",0,"stations"],"set":2}]},"w":1792532894601.458}
  #|{"in":{"id":15,"delta":[{"path":["stations"],"set":[{"id":"bb13a80c91c04f8ffaa4e7763853c9f95ef37c729dc491de6f5e899c13eacc83","name":"studio","emoji":null,"icon":null,"enrolled_at":1792532876,"enrolled_by":"alice","last_seen":1792532894,"version":"0.1.0","time":{"last_seen":{"past":true,"at":1792532894000,"ago":"刚刚","full":"10/21 05:48:14","until":"1 分钟内"}}},{"id":"3393fc76a6422b2a1640c4d5593165cff397ad429fe70ecc5e9ae63dbdae8b35","name":"e2e-080726-b","emoji":null,"icon":null,"enrolled_at":1792532894,"enrolled_by":"alice","last_seen":1792532894,"version":"0.1.0","time":{"last_seen":{"past":true,"at":1792532894000,"ago":"刚刚","full":"10/21 05:48:14","until":"1 分钟内"}}}]}]},"w":1792532894601.483}
  #|{"in":{"id":7,"delta":[{"path":["glyph","connecting"],"set":1},{"path":["glyph","dim"],"set":1},{"path":["glyph","label"],"set":"2 台 station，1 台在线，1 台正在连接"},{"path":["glyph","summary"],"set":"2 台 station"},{"path":["loading"],"set":true},{"path":["stations"],"append":[{"station":"01M5DMJ2XHDVX85EMMG6Y5N5BW/3393fc76a6422b2a1640c4d5593165cff397ad429fe70ecc5e9ae63dbdae8b35","id":"3393fc76a6422b2a1640c4d5593165cff397ad429fe70ecc5e9ae63dbdae8b35","name":"e2e-080726-b","state":"connecting"}]}]},"w":1792532894601.51}
  #|{"in":{"id":17,"delta":[{"path":["wait","empty"],"set":false},{"path":["wait","reading"],"set":true},{"path":["wait","text"],"set":"正在从 e2e-080726-b 读取"}]},"w":1792532894601.533}
  #|{"step":"tap =完成","w":1792532894604.566}
  #|{"step":"tap =完成","acted":true,"w":1792532894618.08}
  #|{"step":"rest","w":1792532894634.695}
  #|{"in":{"id":16,"delta":[{"path":[0,"way"],"set":{"path":"直连","via":"direct"}}]},"w":1792532896017.843}
  #|{"step":"now until =e2e-080726-b","w":1792532896117.977}
  #|{"step":"tap =e2e-080726-b","w":1792532896117.988}
  #|{"step":"tap =e2e-080726-b","acted":true,"w":1792532896134.647}
  #|{"out":{"id":22,"subscribe":{"topic":"screens","station":"01M5DMJ2XHDVX85EMMG6Y5N5BW/3393fc76a6422b2a1640c4d5593165cff397ad429fe70ecc5e9ae63dbdae8b35"},"keyed":true},"w":1792532896152.562}
  #|{"out":{"id":23,"subscribe":{"topic":"memberships","station":"01M5DMJ2XHDVX85EMMG6Y5N5BW/3393fc76a6422b2a1640c4d5593165cff397ad429fe70ecc5e9ae63dbdae8b35"},"keyed":true},"w":1792532896152.597}
  #|{"out":{"id":24,"subscribe":{"topic":"adbShare"},"keyed":true},"w":1792532896153.076}
  #|{"step":"rest","w":1792532896153.326}
  #|{"in":{"id":22,"value":{"screens":[],"outdated":false,"control":true,"known":false}},"w":1792532896167.754}
  #|{"in":{"id":23,"value":{"manages":true,"loading":true,"canJoin":false,"workspaces":[]}},"w":1792532896167.782}
  #|{"in":{"id":24,"value":{"sharing":false,"phase":"off","tunnels":0}},"w":1792532896167.792}
  #|{"step":"now until 在此 station 上","w":1792532896467.893}
  #|{"step":"tap icon:more","w":1792532896467.912}
  #|{"step":"tap icon:more","acted":true,"w":1792532896485.079}
  #|{"step":"rest","w":1792532896505.68}
  #|{"in":{"id":5,"value":{"state":"slow","text":"正在连接 e2e-080726-b ×2 · 2 秒 · 共 4 项 · 3 KB/s","items":[{"state":"slow","text":"正在连接 e2e-080726-b ×2","detail":"已等待 2 秒"},{"state":"slow","text":"e2e-080726-b 打开实时更新 ×2","detail":"已等待 2 秒，尚未收到数据"}]}},"w":1792532896934.466}
  #|{"in":{"id":9,"value":{"state":"slow","text":"正在连接 e2e-080726-b ×2 · 2 秒 · 共 4 项 · 3 KB/s","items":[{"state":"slow","text":"正在连接 e2e-080726-b ×2","detail":"已等待 2 秒"},{"state":"slow","text":"e2e-080726-b 打开实时更新 ×2","detail":"已等待 2 秒，尚未收到数据"}]}},"w":1792532896951.152}
  #|{"step":"now tap 从 workspace 移除","w":1792532897934.703}
  #|{"in":{"id":5,"delta":[{"path":["items",0,"detail"],"set":"已等待 3 秒"},{"path":["items",1,"detail"],"set":"已等待 3 秒，尚未收到数据"},{"path":["text"],"set":"正在连接 e2e-080726-b ×2 · 3 秒 · 共 4 项"}]},"w":1792532897951.073}
  #|{"in":{"id":9,"delta":[{"path":["items",0,"detail"],"set":"已等待 3 秒"},{"path":["items",1,"detail"],"set":"已等待 3 秒，尚未收到数据"},{"path":["text"],"set":"正在连接 e2e-080726-b ×2 · 3 秒 · 共 4 项"}]},"w":1792532897951.096}
  #|{"step":"now tap 从 workspace 移除","acted":true,"w":1792532897951.421}
  #|{"step":"rest","w":1792532897968.143}
  #|{"in":{"id":5,"delta":[{"path":["items",0,"detail"],"set":"已等待 4 秒"},{"path":["items",0,"text"],"set":"正在连接 e2e-080726-b ×3"},{"path":["items",1,"detail"],"set":"已等待 4 秒，尚未收到数据"},{"path":["text"],"set":"正在连接 e2e-080726-b ×3 · 4 秒 · 共 5 项"}]},"w":1792532899034.405}
  #|{"in":{"id":9,"delta":[{"path":["items",0,"detail"],"set":"已等待 4 秒"},{"path":["items",0,"text"],"set":"正在连接 e2e-080726-b ×3"},{"path":["items",1,"detail"],"set":"已等待 4 秒，尚未收到数据"},{"path":["text"],"set":"正在连接 e2e-080726-b ×3 · 4 秒 · 共 5 项"}]},"w":1792532899034.431}
  #|{"step":"now until 移除「e2e-080726-b」","w":1792532899234.973}
  #|{"step":"tap =移除 station","w":1792532899234.991}
  #|{"step":"tap =移除 station","acted":true,"w":1792532899251.794}
  #|{"out":{"id":25,"call":"workspace.removeStation","params":{"workspace":"01M5DMJ2XHDVX85EMMG6Y5N5BW","station":"3393fc76a6422b2a1640c4d5593165cff397ad429fe70ecc5e9ae63dbdae8b35","account":"alice"}},"w":1792532899267.925}
  #|{"step":"answered workspace.removeStation","w":1792532899268.806}
  #|{"in":{"id":5,"value":{"state":"slow","text":"e2e-080726-b 打开实时更新 ×2 · 4 秒 · 共 2 项 · 130 B/s","items":[{"state":"slow","text":"e2e-080726-b 打开实时更新 ×2","detail":"已等待 4 秒，尚未收到数据"}]}},"w":1792532899284.872}
  #|{"in":{"id":9,"value":{"state":"slow","text":"e2e-080726-b 打开实时更新 ×2 · 4 秒 · 共 2 项 · 130 B/s","items":[{"state":"slow","text":"e2e-080726-b 打开实时更新 ×2","detail":"已等待 4 秒，尚未收到数据"}]}},"w":1792532899284.915}
  #|{"in":{"id":19,"value":{"doing":[{"call":"workspace.removeStation","params":{"workspace":"01M5DMJ2XHDVX85EMMG6Y5N5BW","station":"3393fc76a6422b2a1640c4d5593165cff397ad429fe70ecc5e9ae63dbdae8b35","account":"alice"},"since":1792532899268,"stage":"running"}]}},"w":1792532899284.935}
  #|{"in":{"id":23,"value":{"manages":true,"loading":false,"canJoin":true,"workspaces":[{"workspace":"01M5DMJ2XHDVX85EMMG6Y5N5BW","name":"Dev","stationName":"e2e-080726-b","home":true,"here":true,"line":"主 workspace"}]}},"w":1792532899284.951}
  #|{"in":{"id":25,"ok":{"ok":true}},"w":1792532899317.732}
  #|{"step":"until 已移除 station","w":1792532899335.616}
  #|{"step":"rest","w":1792532899335.636}
  #|{"in":{"id":9,"value":{"items":[]}},"w":1792532899467.729}
  #|{"in":{"id":4,"delta":[{"path":[0,"workspaces",0,"stations"],"set":1}]},"w":1792532899467.749}
  #|{"in":{"id":15,"delta":[{"path":["stations"],"set":[{"id":"bb13a80c91c04f8ffaa4e7763853c9f95ef37c729dc491de6f5e899c13eacc83","name":"studio","emoji":null,"icon":null,"enrolled_at":1792532876,"enrolled_by":"alice","last_seen":1792532894,"version":"0.1.0","time":{"last_seen":{"past":true,"at":1792532894000,"ago":"刚刚","full":"10/21 05:48:14","until":"1 分钟内"}}}]}]},"w":1792532899467.762}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792532899467.777}
  #|{"in":{"id":19,"value":{"doing":[]}},"w":1792532899467.781}
  #|{"in":{"id":7,"delta":[{"path":["glyph","connecting"],"set":0},{"path":["glyph","dim"],"set":0},{"path":["glyph","label"],"set":"1 台 station，1 台在线"},{"path":["glyph","summary"],"set":"studio"},{"path":["loading"],"set":false},{"path":["stations"],"set":[{"station":"01M5DMJ2XHDVX85EMMG6Y5N5BW/bb13a80c91c04f8ffaa4e7763853c9f95ef37c729dc491de6f5e899c13eacc83","id":"bb13a80c91c04f8ffaa4e7763853c9f95ef37c729dc491de6f5e899c13eacc83","name":"studio","state":"online"}]}]},"w":1792532899467.788}
  #|{"in":{"id":16,"value":[{"station":"01M5DMJ2XHDVX85EMMG6Y5N5BW/bb13a80c91c04f8ffaa4e7763853c9f95ef37c729dc491de6f5e899c13eacc83","id":"bb13a80c91c04f8ffaa4e7763853c9f95ef37c729dc491de6f5e899c13eacc83","name":"studio","summary":"空闲 · Apple M4 · 16 GB · macOS 27.0.1","face":"idle","line":"Apple M4","online":true,"reconnecting":false,"lastSeen":1792532894,"version":"0.1.0","link":{"state":"online"},"runtimes":[{"runtime":"claude","models":["claude-sonnet-5-5"]}],"models":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792532880018,"time":{"checkedAt":{"at":1792532880018,"ago":"刚刚","full":"10/21 05:48:00","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"overview":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null,"summaryText":"最近 7 天检查了 0 个 chat","changeText":null}},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","email":"alice@example.test","name":"Name of alice","sub":"alice","role":"owner","workspace":"01M5DMJ2XHDVX85EMMG6Y5N5BW","device":"1915699e2549926924933eeeebef0b46f9bbaa16779f550436f92c16fc19e812"},"connects":[],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792532894318,"time":{"checkedAt":{"at":1792532894318,"ago":"刚刚","full":"10/21 05:48:14","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792532880018,"time":{"checkedAt":{"at":1792532880018,"ago":"刚刚","full":"10/21 05:48:00","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]}],"processes":[],"counts":{"sessions":1,"running":0,"warm":0},"mesh":{"state":"running","origin":"http://127.0.0.1:18900","station":"bb13a80c91c04f8ffaa4e7763853c9f95ef37c729dc491de6f5e899c13eacc83","workspace":"Dev","workspaceId":"01M5DMJ2XHDVX85EMMG6Y5N5BW","name":"studio"},"slackUsers":[],"slackTeams":[],"slackApps":[],"feishuRegistrations":[],"disk":{"freeBytes":58171928576,"totalBytes":245107195904},"logins":[],"machineLogins":[],"sharing":true,"consoleSignIn":true,"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"google","name":"Google Gemini","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xai","name":"xAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"mistral","name":"Mistral","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"deepseek","name":"DeepSeek","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen","name":"Qwen","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai","name":"Kimi","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai","name":"Z.ai","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax","name":"MiniMax","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ant-ling","name":"Ant Ling","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"jev","name":"Jev","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen-cn","name":"Qwen (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"openrouter","name":"OpenRouter","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"opencode","name":"OpenCode Zen","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"groq","name":"Groq","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"together","name":"Together AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"fireworks","name":"Fireworks","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cerebras","name":"Cerebras","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"huggingface","name":"Hugging Face","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"nvidia","name":"NVIDIA","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"baseten","name":"Baseten","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ollama","name":"Ollama","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"custom","name":"Custom","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""}],"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792532891962},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.305","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792532891962},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792532891962},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792532891962},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","latest":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792532891962}],"processesText":"没有运行中的 agent 进程","agentEnv":[],"drive":{"roots":[],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false}},"betaOffered":false,"host":{"hostname":"3720-Mac-mini-1","os":"macOS 27.0.1","arch":"arm64","cpus":10,"cpuModel":"Apple M4","load":0.35,"cpuBusy":0.25,"uptimeSec":12256,"memory":{"totalBytes":17179869184,"usedBytes":9815539712,"swapUsedBytes":333572997},"disk":{"path":"/tmp/mbe2e-C/data","totalBytes":245107195904,"freeBytes":58172497920},"emberRssBytes":138557048,"checkedAt":1792532894464,"summary":"10 核 · 16 GB","line":"macOS 27.0.1 · 10 核 · 16 GB · 已运行 0 天","facts":["3720-Mac-mini-1","macOS 27.0.1","arm64 · 10 核","已运行 3 小时"],"meters":[{"label":"CPU","short":"CPU","percent":25,"left":75,"level":"ok","value":"25%","remaining":"空闲 75%","big":"75","unit":"%","title":"CPU 空闲","total":"负载 3.5","note":"负载 3.5 · Apple M4"},{"label":"内存","short":"内存","percent":57,"left":43,"level":"ok","value":"9.1 GB / 16.0 GB","remaining":"剩 6.9 G","big":"6.9","unit":"GB","title":"内存剩","total":"共 16 GB","note":"swap 0.3 GB"},{"label":"磁盘","short":"磁盘","percent":76,"left":24,"level":"amber","value":"剩余 54.2 GB / 228 GB","remaining":"剩 54.2 G","big":"54.2","unit":"GB","title":"磁盘剩","total":"共 228 GB"}],"identity":"Apple M4 · 16 GB · macOS 27.0.1","details":[{"label":"主机名","value":"3720-Mac-mini-1"},{"label":"芯片","value":"Apple M4 · 10 核 · arm64"},{"label":"已运行","value":"3 小时"},{"label":"still.fail","value":"进程占用 132 MB"}],"usage":"内存 9.1 GB / 16.0 GB · 磁盘 剩余 54.2 GB / 228 GB","emberText":"still.fail 132 MB"},"way":{"path":"直连","via":"direct"},"time":{"lastSeen":{"at":1792532894000,"ago":"刚刚","full":"10/21 05:48:14","until":"1 分钟内","past":true}},"joined":false}]},"w":1792532899467.891}
  #|{"in":{"id":17,"delta":[{"path":["wait","empty"],"set":true},{"path":["wait","reading"],"set":false},{"path":["wait","text"],"set":null}]},"w":1792532899467.972}
  #|{"in":{"id":23,"value":{"manages":false,"loading":false,"canJoin":false,"workspaces":[]}},"w":1792532899467.978}
  #|{"step":"now until =studio","w":1792532900701.135}
  #|{"step":"gone e2e-080726-b","w":1792532900701.158}
  #|{"step":"rest","w":1792532900701.164}
  #|{"step":"log do: second-down","w":1792532900717.773}
  #|{"step":"second-down"}
  #|{"step":"now rest","w":1792532900717.778}
  #|{"step":"","w":1792532900734.572}
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
  #|{"textrec":{"ib":["a7ccae3554fe46cf",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["fdb526ba00f881f4",3232,64],"r":[28,28,28,28]}}
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
  #|{"textrec":{"ib":["8a3f7c664f10bd54",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["bc56d3e0d751880c",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["8702d89573d5efdf",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["2bb63fc1d380f765",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["70da3a129cd335a2",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["831523b197f71e32",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["56cdacf263ae288e",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["536c426c0236d661",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"s":[17,700,0,"添加 station"],"r":[0,1,16.851167315175097,211,1,1,16.851167315175097,212,2,1,3.951171875,-1,3,1,9.176513671875,213,4,1,6.561767578125,214,5,1,9.591552734375,215,6,1,6.58251953125,214,7,1,4.44921875,216,8,1,10.10205078125,217,9,1,10.230712890625,218]}}
  #|{"textrec":{"m":[17,700,0],"r":[16.435546875,3.5859375,24]}}
  #|{"textrec":{"s":[14,400,0,"station 是一台运行 still.fail 的机器。为它命名，然后在该机器的终端中执行生成的命令，它会安装 still.fail 并加入。"],"r":[0,1,7.1435546875,219,1,1,4.9013671875,61,2,1,7.57421875,57,3,1,4.935546875,61,4,1,3.30859375,220,5,1,8.12109375,221,6,1,8.0185546875,60,7,1,3.787109375,-1,8,1,13.891050583657588,52,9,1,13.891050583657588,222,10,1,13.891050583657588,223,11,1,13.891050583657588,224,12,1,13.891050583657588,225,13,1,3.787109375,-1,14,1,7.143554687500014,219,15,1,4.9013671875,61,16,1,3.30859375,220,17,1,3.390625,226,18,1,3.390625,226,19,1,3.80078125,227,20,1,4.607421875,228,21,1,7.4716796875,57,22,1,3.30859375,220,23,1,3.390625,226,24,1,3.787109375,-1,25,1,13.891050583657602,56,26,1,13.891050583657602,229,27,1,13.891050583657602,230,28,1,14.081712062256798,231,29,1,13.891050583657574,232,30,1,13.891050583657602,233,31,1,13.891050583657602,234,32,1,13.891050583657602,235,33,1,14.081712062256827,50,34,1,13.891050583657602,236,35,1,13.891050583657602,237,36,1,13.891050583657602,182,37,1,13.891050583657602,238,38,1,13.891050583657602,229,39,1,13.891050583657602,230,40,1,13.891050583657602,56,41,1,13.891050583657602,239,42,1,13.891050583657602,240,43,1,13.891050583657602,241,44,1,13.891050583657602,242,45,1,13.891050583657602,225,46,1,13.891050583657602,243,47,1,13.891050583657602,244,48,1,13.891050583657602,56,49,1,13.891050583657602,234,50,1,13.891050583657602,245,51,1,14.08171206225677,50,52,1,13.891050583657602,233,53,1,13.891050583657602,246,54,1,13.891050583657602,247,55,1,13.891050583657602,248,56,1,3.787109375,-1,57,1,7.1435546875,219,58,1,4.9013671875,61,59,1,3.30859375,220,60,1,3.390625,226,61,1,3.390625,226,62,1,3.80078125,227,63,1,4.607421875,228,64,1,7.4716796875,57,65,1,3.30859375,220,66,1,3.390625,226,67,1,3.787109375,-1,68,1,13.891050583657602,249,69,1,13.891050583657602,250,70,1,13.891050583657602,251,71,1,7.08171206225677,231]}}
  #|{"textrec":{"s":[13,600,0,"名称"],"r":[0,1,12.898832684824903,252,1,1,12.898832684824903,253]}}
  #|{"textrec":{"m":[13,600,0],"r":[12.568359375,2.7421875,18]}}
  #|{"textrec":{"s":[14,600,0,"取消"],"r":[0,1,13.891050583657588,254,1,1,13.891050583657588,255]}}
  #|{"textrec":{"m":[14,600,0],"r":[13.53515625,2.953125,20]}}
  #|{"textrec":{"s":[14,600,0,"生成命令"],"r":[0,1,13.891050583657588,256,1,1,13.891050583657588,257,2,1,13.891050583657588,258,3,1,13.891050583657588,259]}}
  #|{"textrec":{"g":211,"r":[207,32,19,18,-1,-15,0]}}
  #|{"textrec":{"g":212,"r":[227,32,18,18,-1,-15,0]}}
  #|{"textrec":{"g":213,"r":[246,32,11,13,-1,-11,0]}}
  #|{"textrec":{"g":214,"r":[258,32,9,15,-1,-13,0]}}
  #|{"textrec":{"g":215,"r":[268,32,11,13,-1,-11,0]}}
  #|{"textrec":{"g":216,"r":[280,32,5,16,0,-15,0]}}
  #|{"textrec":{"g":217,"r":[286,32,12,13,-1,-11,0]}}
  #|{"textrec":{"g":218,"r":[299,32,11,12,0,-11,0]}}
  #|{"textrec":{"g":219,"r":[311,32,9,11,-1,-9,0]}}
  #|{"textrec":{"g":220,"r":[321,32,5,13,-1,-12,0]}}
  #|{"textrec":{"g":221,"r":[327,32,10,11,-1,-9,0]}}
  #|{"textrec":{"g":222,"r":[338,32,15,4,-1,-7,0]}}
  #|{"textrec":{"g":223,"r":[354,32,14,16,0,-13,0]}}
  #|{"textrec":{"g":224,"r":[369,32,16,15,-1,-12,0]}}
  #|{"textrec":{"g":225,"r":[386,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":226,"r":[402,32,4,13,0,-12,0]}}
  #|{"textrec":{"g":227,"r":[407,32,4,5,0,-3,0]}}
  #|{"textrec":{"g":228,"r":[412,32,7,13,-1,-12,0]}}
  #|{"textrec":{"g":229,"r":[420,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":230,"r":[437,32,16,15,-1,-12,0]}}
  #|{"textrec":{"g":231,"r":[454,32,6,6,0,-3,0]}}
  #|{"textrec":{"g":232,"r":[461,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":233,"r":[477,32,14,15,0,-13,0]}}
  #|{"textrec":{"g":234,"r":[492,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":235,"r":[509,32,14,16,-1,-13,0]}}
  #|{"textrec":{"g":236,"r":[524,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":237,"r":[541,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":238,"r":[557,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":239,"r":[574,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":240,"r":[591,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":241,"r":[607,32,14,16,0,-13,0]}}
  #|{"textrec":{"g":242,"r":[622,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":243,"r":[639,32,15,15,-1,-13,0]}}
  #|{"textrec":{"g":244,"r":[655,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":245,"r":[672,32,16,15,-1,-12,0]}}
  #|{"textrec":{"g":246,"r":[689,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":247,"r":[706,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":248,"r":[722,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":249,"r":[739,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":250,"r":[755,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":251,"r":[771,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":252,"r":[788,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":253,"r":[803,32,15,15,-1,-12,0]}}
  #|{"textrec":{"s":[15,400,0,"例如机器名：studio、mac-mini"],"r":[0,1,14.883268482490273,260,1,1,14.883268482490273,261,2,1,14.883268482490273,132,3,1,14.883268482490273,262,4,1,14.88326848249028,263,5,1,15.08754863813229,264,6,1,7.58056640625,91,7,1,5.17822265625,101,8,1,8.51806640625,163,9,1,8.9794921875,265,10,1,3.4716796875,102,11,1,8.6279296875,88,12,1,13.58754863813229,266,13,1,12.8173828125,161,14,1,8.0419921875,93,15,1,8.1591796875,94,16,1,6.8408203125,267,17,1,12.8173828125,161,18,1,3.4716796875,102,19,1,8.51806640625,103,20,1,3.4716796875,102]}}
  #|{"textrec":{"g":260,"r":[819,32,16,17,-1,-14,0]}}
  #|{"textrec":{"g":261,"r":[836,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":262,"r":[853,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":263,"r":[871,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":264,"r":[887,32,5,10,1,-10,0]}}
  #|{"textrec":{"g":163,"r":[893,32,9,11,0,-9,0]}}
  #|{"textrec":{"g":265,"r":[903,32,10,15,-1,-13,0]}}
  #|{"textrec":{"g":266,"r":[914,32,7,7,0,-4,0]}}
  #|{"textrec":{"g":161,"r":[922,32,13,11,0,-10,0]}}
  #|{"textrec":{"g":267,"r":[936,32,7,4,0,-6,0]}}
  #|{"textrec":{"g":254,"r":[944,32,16,15,-1,-12,0]}}
  #|{"textrec":{"g":255,"r":[961,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":256,"r":[977,32,15,15,-1,-13,0]}}
  #|{"textrec":{"g":257,"r":[993,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":258,"r":[1010,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":259,"r":[1027,32,16,16,-1,-13,0]}}
  #|{"textrec":{"ib":["365bf49de4f5d505",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["3a089f86e58e836f",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["d199cb74c5a62786",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["9e48044fa6815e02",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["5018c6b0c428bd67",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["0ac9db1649fc9777",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["dc2a7c23677cea3f",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["0b44c3b15eb4e72a",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["a32136b675dfede6",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["80471d92f205f03a",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["21d27b298626ff58",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["f50dcfc8e7b09e13",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["d2ccd5cf9373640b",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["a84714a0d118c5eb",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["3e89fb0d7a2d2be5",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["abd519d291ad649c",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["550a89fdd3627b9e",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"s":[15,400,0,"e2e-080726-b"],"r":[0,1,8.3349609375,95,1,1,8.78173828125,268,2,1,8.29833984375,95,3,1,6.8408203125,267,4,1,9.2138671875,164,5,1,9.345703125,269,6,1,9.0673828125,164,7,1,8.1591796875,270,8,1,8.818359375,268,9,1,9.31640625,271,10,1,6.8408203125,267,11,1,8.9794921875,162]}}
  #|{"textrec":{"g":268,"r":[1044,32,10,13,0,-12,0]}}
  #|{"textrec":{"g":164,"r":[1055,32,11,14,-1,-12,0]}}
  #|{"textrec":{"g":269,"r":[1067,32,11,14,-1,-12,0]}}
  #|{"textrec":{"g":270,"r":[1079,32,10,13,-1,-12,0]}}
  #|{"textrec":{"g":271,"r":[1090,32,11,14,-1,-12,0]}}
  #|{"textrec":{"g":162,"r":[1102,32,10,15,0,-13,0]}}
  #|{"textrec":{"s":[14,400,0,"在该机器的终端中执行："],"r":[0,1,13.891050583657588,182,1,1,13.891050583657588,238,2,1,13.891050583657588,229,3,1,13.891050583657588,230,4,1,13.891050583657588,56,5,1,13.891050583657588,239,6,1,13.891050583657588,240,7,1,13.891050583657588,241,8,1,13.891050583657588,242,9,1,13.891050583657588,225,10,1,7.081712062256798,272]}}
  #|{"textrec":{"s":[12,400,2,"curl -fsSL http://127.0.0.1:18900/install.sh | sh -s -- N_56ewh5HwjSXf79IBNqKRXWmT1ukciD9YcQ9O5OIZk"],"r":[0,1,7.41796875,273,1,1,7.41796875,274,2,1,7.41796875,275,3,1,7.41796875,276,4,1,7.41796875,-1,5,1,7.41796875,277,6,1,7.41796875,278,7,1,7.41796875,279,8,1,7.41796875,280,9,1,7.41796875,281,10,1,7.41796875,-1,11,1,7.41796875,282,12,1,7.41796875,283,13,1,7.41796875,283,14,1,7.41796875,284,15,1,7.41796875,285,16,1,7.41796875,286,17,1,7.41796875,286,18,1,7.41796875,287,19,1,7.41796875,288,20,1,7.41796875,289,21,1,7.41796875,290,22,1,7.41796875,291,23,1,7.41796875,290,24,1,7.41796875,291,25,1,7.41796875,290,26,1,7.41796875,287,27,1,7.41796875,285,28,1,7.41796875,287,29,1,7.41796875,292,30,1,7.41796875,293,31,1,7.41796875,291,32,1,7.41796875,291,33,1,7.41796875,286,34,1,7.41796875,294,35,1,7.41796875,295,36,1,7.41796875,279,37,1,7.41796875,283,38,1,7.41796875,296,39,1,7.41796875,276,40,1,7.41796875,276,41,1,7.41796875,290,42,1,7.41796875,279,43,1,7.41796875,282,44,1,7.41796875,-1,45,1,7.41796875,297,46,1,7.41796875,-1,47,1,7.41796875,279,48,1,7.41796875,282,49,1,7.41796875,-1,50,1,7.41796875,277,51,1,7.41796875,279,52,1,7.41796875,-1,53,1,7.41796875,277,54,1,7.41796875,277,55,1,7.41796875,-1,56,1,7.41796875,298,57,1,7.41796875,299,58,1,7.41796875,300,59,1,7.41796875,301,60,1,7.41796875,302,61,1,7.41796875,303,62,1,7.41796875,282,63,1,7.41796875,300,64,1,7.41796875,304,65,1,7.41796875,303,66,1,7.41796875,305,67,1,7.41796875,280,68,1,7.41796875,306,69,1,7.41796875,278,70,1,7.41796875,289,71,1,7.41796875,293,72,1,7.41796875,307,73,1,7.41796875,308,74,1,7.41796875,298,75,1,7.41796875,309,76,1,7.41796875,310,77,1,7.41796875,311,78,1,7.41796875,306,79,1,7.41796875,312,80,1,7.41796875,313,81,1,7.41796875,314,82,1,7.41796875,287,83,1,7.41796875,274,84,1,7.41796875,315,85,1,7.41796875,273,86,1,7.41796875,294,87,1,7.41796875,316,88,1,7.41796875,293,89,1,7.41796875,317,90,1,7.41796875,273,91,1,7.41796875,318,92,1,7.41796875,293,93,1,7.41796875,319,94,1,7.41796875,300,95,1,7.41796875,319,96,1,7.41796875,307,97,1,7.41796875,320,98,1,7.41796875,315]}}
  #|{"textrec":{"m":[12,400,2],"r":[11.6015625,2.53125,17]}}
  #|{"textrec":{"s":[13,400,0,"支持 macOS（Apple 芯片）和 Linux，Windows 需在 WSL 中运行；已安装 still.fail 的机器也使用此命令。它会安装 still.fail、加入此 workspace，并在后台持续运行。加入后，在其 Station 页添加 Profile。"],"r":[0,1,12.898832684824903,321,1,1,12.898832684824903,322,2,1,3.580078125,-1,3,1,11.2353515625,80,4,1,7.0966796875,12,5,1,7.1982421875,13,6,1,9.953125,323,7,1,8.20751953125,324,8,1,9.271984435797663,325,9,1,8.68359375,326,10,1,7.8583984375,11,11,1,7.8583984375,11,12,1,3.2119140625,76,13,1,7.3505859375,14,14,1,3.580078125,-1,15,1,12.89883268482491,327,16,1,12.898832684824896,328,17,1,3.8317120622567984,329,18,1,19.398832684824896,330,19,1,3.580078125,-1,20,1,7.30615234375,331,21,1,3.1357421875,77,22,1,7.50927734375,332,23,1,7.50927734375,333,24,1,6.7412109375,79,25,1,11.775875486381324,334,26,1,12.5048828125,335,27,1,3.1357421875,77,28,1,7.50927734375,332,29,1,7.9091796875,336,30,1,7.477539062499972,7,31,1,9.76904296875,6,32,1,6.63330078125,10,33,1,3.580078125,-1,34,1,12.898832684824924,142,35,1,12.898832684824924,1,36,1,3.580078125,-1,37,1,12.5048828125,335,38,1,8.20751953125,324,39,1,7.30615234375,331,40,1,3.580078125,-1,41,1,12.898832684824924,337,42,1,12.898832684824924,338,43,1,12.898832684824924,339,44,1,13.075875486381335,340,45,1,12.898832684824924,341,46,1,12.898832684824924,342,47,1,12.898832684824924,343,48,1,3.580078125,-1,49,1,6.69677734375,10,50,1,4.61474609375,82,51,1,3.1357421875,77,52,1,3.2119140625,76,53,1,3.2119140625,76,54,1,3.5927734375,81,55,1,4.341796875,344,56,1,7.00146484375,12,57,1,3.1357421875,77,58,1,3.2119140625,76,59,1,3.580078125,-1,60,1,12.898832684824924,5,61,1,12.898832684824924,345,62,1,12.898832684824868,346,63,1,12.898832684824924,347,64,1,12.898832684824924,348,65,1,12.898832684824924,349,66,1,12.898832684824924,350,67,1,12.898832684824924,351,68,1,12.898832684824924,352,69,1,13.075875486381278,353,70,1,12.898832684824924,354,71,1,12.898832684824924,355,72,1,12.898832684824924,342,73,1,12.898832684824924,343,74,1,3.580078125,-1,75,1,6.69677734375,10,76,1,4.61474609375,82,77,1,3.1357421875,77,78,1,3.2119140625,76,79,1,3.2119140625,76,80,1,3.5927734375,81,81,1,4.341796875,344,82,1,7.00146484375,12,83,1,3.1357421875,77,84,1,3.2119140625,76,85,1,13.075875486381278,141,86,1,12.898832684824924,356,87,1,12.898832684824924,357,88,1,12.898832684824924,350,89,1,3.580078125,-1,90,1,9.8642578125,6,91,1,7.4775390625,7,92,1,4.875,8,93,1,6.85546875,9,94,1,6.6015625,10,95,1,7.8583984375,11,96,1,7.0966796875,12,97,1,7.1982421875,13,98,1,7.3505859375,14,99,1,13.075875486381278,334,100,1,12.898832684824924,358,101,1,12.898832684824924,1,102,1,12.898832684824924,359,103,1,12.898832684824924,360,104,1,12.898832684824924,322,105,1,12.898832684824924,361,106,1,12.898832684824924,338,107,1,12.898832684824924,339,108,1,13.075875486381278,353,109,1,12.898832684824924,356,110,1,12.898832684824924,357,111,1,12.898832684824924,359,112,1,13.075875486381278,334,113,1,12.898832684824924,1,114,1,12.898832684824924,362,115,1,3.580078125,-1,116,1,8.20751953125,324,117,1,4.646484375,82,118,1,7.0966796875,12,119,1,4.646484375,82,120,1,3.1357421875,77,121,1,7.6044921875,7,122,1,7.50927734375,332,123,1,3.580078125,-1,124,1,12.89883268482481,363,125,1,12.89883268482481,364,126,1,12.89883268482481,356,127,1,3.580078125,-1,128,1,8.18212890625,365,129,1,4.77978515625,8,130,1,7.50927734375,7,131,1,4.62744140625,344,132,1,3.1357421875,77,133,1,3.2119140625,76,134,1,7.3505859375,14,135,1,6.575875486381392,353]}}
  #|{"textrec":{"s":[13,400,0,"等待机器加入… 执行命令后将自动继续 · 命令 1 小时内有效"],"r":[0,1,12.898832684824903,366,1,1,12.898832684824903,367,2,1,12.898832684824903,345,3,1,12.898832684824903,346,4,1,12.898832684824896,356,5,1,12.898832684824896,357,6,1,10.384765625,368,7,1,3.580078125,-1,8,1,12.898832684824896,369,9,1,12.898832684824896,339,10,1,12.898832684824896,351,11,1,12.898832684824896,352,12,1,12.898832684824896,359,13,1,12.898832684824896,370,14,1,12.898832684824896,371,15,1,12.898832684824896,372,16,1,12.898832684824896,373,17,1,12.898832684824896,361,18,1,3.580078125,-1,19,1,6.228545204222115,374,20,1,3.580078125,-1,21,1,12.898832684824896,351,22,1,12.898832684824896,352,23,1,3.580078125,-1,24,1,5.9541015625,375,25,1,3.580078125,-1,26,1,12.898832684824924,376,27,1,12.898832684824924,153,28,1,12.898832684824924,377,29,1,12.898832684824924,149,30,1,12.898832684824924,378]}}
  #|{"textrec":{"g":272,"r":[1113,32,5,10,1,-10,0]}}
  #|{"textrec":{"g":273,"r":[1119,32,8,10,0,-8,0]}}
  #|{"textrec":{"g":274,"r":[1128,32,8,10,0,-8,0]}}
  #|{"textrec":{"g":275,"r":[1137,32,8,9,0,-8,0]}}
  #|{"textrec":{"g":276,"r":[1146,32,8,11,0,-10,0]}}
  #|{"textrec":{"g":277,"r":[1155,32,9,4,-1,-6,0]}}
  #|{"textrec":{"g":278,"r":[1165,32,8,11,0,-10,0]}}
  #|{"textrec":{"g":279,"r":[1174,32,8,10,0,-8,0]}}
  #|{"textrec":{"g":280,"r":[1183,32,9,12,-1,-10,0]}}
  #|{"textrec":{"g":281,"r":[1193,32,8,11,0,-10,0]}}
  #|{"textrec":{"g":282,"r":[1202,32,8,11,0,-10,0]}}
  #|{"textrec":{"g":283,"r":[1211,32,9,12,-1,-10,0]}}
  #|{"textrec":{"g":284,"r":[1221,32,8,12,0,-8,0]}}
  #|{"textrec":{"g":285,"r":[1230,32,5,10,1,-8,0]}}
  #|{"textrec":{"g":286,"r":[1236,32,8,13,0,-11,0]}}
  #|{"textrec":{"g":287,"r":[1245,32,9,11,-1,-10,0]}}
  #|{"textrec":{"g":288,"r":[1255,32,8,11,0,-10,0]}}
  #|{"textrec":{"g":289,"r":[1264,32,9,11,-1,-10,0]}}
  #|{"textrec":{"g":290,"r":[1274,32,5,6,1,-4,0]}}
  #|{"textrec":{"g":291,"r":[1280,32,9,12,-1,-10,0]}}
  #|{"textrec":{"g":292,"r":[1290,32,9,12,-1,-10,0]}}
  #|{"textrec":{"g":293,"r":[1300,32,9,11,-1,-10,0]}}
  #|{"textrec":{"g":294,"r":[1310,32,8,12,0,-11,0]}}
  #|{"textrec":{"g":295,"r":[1319,32,8,9,0,-8,0]}}
  #|{"textrec":{"g":296,"r":[1328,32,8,10,0,-8,0]}}
  #|{"textrec":{"g":297,"r":[1337,32,4,15,2,-11,0]}}
  #|{"textrec":{"g":298,"r":[1342,32,9,11,-1,-10,0]}}
  #|{"textrec":{"g":299,"r":[1352,32,9,4,-1,-1,0]}}
  #|{"textrec":{"g":300,"r":[1362,32,9,12,-1,-10,0]}}
  #|{"textrec":{"g":301,"r":[1372,32,9,12,-1,-10,0]}}
  #|{"textrec":{"g":302,"r":[1382,32,8,10,0,-8,0]}}
  #|{"textrec":{"g":303,"r":[1391,32,10,9,-1,-8,0]}}
  #|{"textrec":{"g":304,"r":[1402,32,9,11,-1,-10,0]}}
  #|{"textrec":{"g":305,"r":[1412,32,7,14,0,-11,0]}}
  #|{"textrec":{"g":306,"r":[1420,32,10,11,-1,-10,0]}}
  #|{"textrec":{"g":307,"r":[1431,32,7,11,0,-10,0]}}
  #|{"textrec":{"g":308,"r":[1439,32,8,11,0,-10,0]}}
  #|{"textrec":{"g":309,"r":[1448,32,9,12,-1,-8,0]}}
  #|{"textrec":{"g":310,"r":[1458,32,9,11,0,-10,0]}}
  #|{"textrec":{"g":311,"r":[1468,32,8,11,0,-10,0]}}
  #|{"textrec":{"g":312,"r":[1477,32,10,11,-1,-10,0]}}
  #|{"textrec":{"g":313,"r":[1488,32,9,9,-1,-8,0]}}
  #|{"textrec":{"g":314,"r":[1498,32,9,11,-1,-10,0]}}
  #|{"textrec":{"g":315,"r":[1508,32,8,11,0,-10,0]}}
  #|{"textrec":{"g":316,"r":[1517,32,9,11,-1,-10,0]}}
  #|{"textrec":{"g":317,"r":[1527,32,10,11,-1,-10,0]}}
  #|{"textrec":{"g":318,"r":[1538,32,9,12,-1,-10,0]}}
  #|{"textrec":{"g":319,"r":[1548,32,9,12,-1,-10,0]}}
  #|{"textrec":{"g":320,"r":[1558,32,9,11,-1,-10,0]}}
  #|{"textrec":{"g":321,"r":[1568,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":322,"r":[1584,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":323,"r":[1600,32,12,13,-1,-11,0]}}
  #|{"textrec":{"g":324,"r":[1613,32,10,13,-1,-11,0]}}
  #|{"textrec":{"g":325,"r":[1624,32,5,15,4.033333333333333,-12,0]}}
  #|{"textrec":{"g":326,"r":[1630,32,11,12,-1,-11,0]}}
  #|{"textrec":{"g":327,"r":[1642,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":328,"r":[1658,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":329,"r":[1673,32,6,15,-1,-12,0]}}
  #|{"textrec":{"g":330,"r":[1680,32,14,15,5.5,-12,0]}}
  #|{"textrec":{"g":331,"r":[1695,32,8,12,0,-11,0]}}
  #|{"textrec":{"g":332,"r":[1704,32,8,9,0,-8,0]}}
  #|{"textrec":{"g":333,"r":[1713,32,9,10,-1,-8,0]}}
  #|{"textrec":{"g":334,"r":[1723,32,5,7,0,-3,0]}}
  #|{"textrec":{"g":335,"r":[1729,32,15,12,-1,-11,0]}}
  #|{"textrec":{"g":336,"r":[1745,32,9,13,-1,-11,0]}}
  #|{"textrec":{"g":7,"r":[1755,32,9,10,-1,-8,0]}}
  #|{"textrec":{"g":6,"r":[1765,32,12,9,-1,-8,0]}}
  #|{"textrec":{"g":142,"r":[1778,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":337,"r":[1793,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":338,"r":[1807,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":339,"r":[1823,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":340,"r":[1839,32,5,11,1,-9,0]}}
  #|{"textrec":{"g":341,"r":[1845,32,13,13,0,-11,0]}}
  #|{"textrec":{"g":342,"r":[1859,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":343,"r":[1874,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":344,"r":[1890,32,7,12,-1,-11,0]}}
  #|{"textrec":{"g":5,"r":[1898,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":345,"r":[1912,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":346,"r":[1928,32,15,14,-1,-11,0]}}
  #|{"textrec":{"g":347,"r":[1944,32,15,14,-1,-12,0]}}
  #|{"textrec":{"g":348,"r":[1960,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":349,"r":[1976,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":350,"r":[1991,32,15,14,-1,-12,0]}}
  #|{"textrec":{"g":351,"r":[2007,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":352,"r":[2023,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":353,"r":[2039,32,6,6,0,-3,0]}}
  #|{"textrec":{"g":354,"r":[0,51,14,14,-1,-12,0]}}
  #|{"textrec":{"g":355,"r":[15,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":141,"r":[31,51,6,6,0,-3,0]}}
  #|{"textrec":{"g":356,"r":[38,51,14,15,-1,-12,0]}}
  #|{"textrec":{"g":357,"r":[53,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":8,"r":[69,51,6,9,0,-8,0]}}
  #|{"textrec":{"g":9,"r":[76,51,8,12,0,-11,0]}}
  #|{"textrec":{"g":358,"r":[85,51,14,15,-1,-12,0]}}
  #|{"textrec":{"g":359,"r":[100,51,14,15,-1,-12,0]}}
  #|{"textrec":{"g":360,"r":[115,51,13,15,0,-12,0]}}
  #|{"textrec":{"g":361,"r":[129,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":362,"r":[145,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":363,"r":[161,51,14,14,-1,-11,0]}}
  #|{"textrec":{"g":364,"r":[176,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":365,"r":[192,51,9,12,0,-11,0]}}
  #|{"textrec":{"g":366,"r":[202,51,14,15,-1,-12,0]}}
  #|{"textrec":{"g":367,"r":[217,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":368,"r":[233,51,11,5,0,-3,0]}}
  #|{"textrec":{"g":369,"r":[245,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":370,"r":[261,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":371,"r":[277,51,11,15,1,-12,0]}}
  #|{"textrec":{"g":372,"r":[289,51,14,15,-1,-12,0]}}
  #|{"textrec":{"g":373,"r":[304,51,15,14,-1,-12,0]}}
  #|{"textrec":{"g":374,"r":[320,51,4,5,1,-7,0]}}
  #|{"textrec":{"g":375,"r":[325,51,7,12,-1,-11,0]}}
  #|{"textrec":{"g":376,"r":[333,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":153,"r":[349,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":377,"r":[365,51,13,15,0,-12,0]}}
  #|{"textrec":{"g":149,"r":[379,51,14,15,-1,-12,0]}}
  #|{"textrec":{"g":378,"r":[394,51,15,15,-1,-12,0]}}
  #|{"textrec":{"ib":["b9bedad57f2a5f13",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"s":[13,400,0,"空闲 · Apple M4 · 16 GB · macOS 27.0.1"],"r":[0,1,12.898832684824903,379,1,1,12.898832684824903,380,2,1,3.580078125,-1,3,1,6.228545204222122,374,4,1,3.580078125,-1,5,1,8.68359375,326,6,1,7.8583984375,11,7,1,7.8583984375,11,8,1,3.211914062500007,76,9,1,7.3505859375,14,10,1,3.580078125,-1,11,1,11.2861328125,381,12,1,8.2900390625,382,13,1,3.580078125,-1,14,1,6.228545204222115,374,15,1,3.580078125,-1,16,1,5.9541015625,375,17,1,8.201171875,383,18,1,3.580078125,-1,19,1,9.62939453125,384,20,1,8.4677734375,385,21,1,3.580078125,-1,22,1,6.228545204222115,374,23,1,3.580078125,-1,24,1,11.2353515625,80,25,1,7.0966796875,12,26,1,7.1982421875,13,27,1,9.953125,323,28,1,8.20751953125,324,29,1,3.580078125,-1,30,1,7.76953125,386,31,1,6.626953125,387,32,1,2.8310546875,81,33,1,7.6044921875,388,34,1,3.3388671875,81,35,1,5.763671875,375]}}
  #|{"textrec":{"s":[11,600,0,"磁盘"],"r":[0,1,10.93579766536965,389,1,1,10.93579766536965,390]}}
  #|{"textrec":{"m":[11,600,0],"r":[10.634765625,2.3203125,16]}}
  #|{"textrec":{"s":[11,600,0,"剩 54.2 G"],"r":[0,1,10.93579766536965,391,1,1,2.9949302673339844,-1,2,1,7.1788982152938825,392,3,1,7.317828059196472,393,4,1,3.481967568397522,394,5,1,6.905241250991821,395,6,1,2.9949302673339844,-1,7,1,8.372097969055176,396]}}
  #|{"textrec":{"s":[16,700,0,"e2e-080726-b"],"r":[0,1,9.30078125,70,1,1,9.95703125,397,2,1,9.28125,70,3,1,7.4375,398,4,1,10.640625,399,5,1,10.75,400,6,1,10.4453125,399,7,1,9.203125,401,8,1,9.9765625,397,9,1,10.625,402,10,1,7.4375,398,11,1,10.109375,403]}}
  #|{"textrec":{"s":[14,400,0,"「e2e-080726-b」已加入，现在可以打开"],"r":[0,1,7.399481193255512,404,1,1,7.847656249999999,59,2,1,8.2646484375,126,3,1,7.8134765625,59,4,1,6.453125,405,5,1,8.66796875,177,6,1,8.791015625,406,7,1,8.53125,177,8,1,7.68359375,407,9,1,8.298828125,126,10,1,8.763671875,408,11,1,6.453125,405,12,1,8.44921875,409,13,1,4.793774319066145,410,14,1,20.891050583657574,411,15,1,13.891050583657602,250,16,1,13.891050583657602,251,17,1,14.081712062256798,50,18,1,13.891050583657574,412,19,1,13.891050583657602,182,20,1,13.891050583657602,413,21,1,13.891050583657602,414,22,1,13.891050583657602,415,23,1,13.891050583657602,97]}}
  #|{"textrec":{"s":[14,600,0,"完成"],"r":[0,1,13.891050583657588,416,1,1,13.891050583657588,257]}}
  #|{"textrec":{"g":379,"r":[410,51,14,14,-1,-12,0]}}
  #|{"textrec":{"g":380,"r":[425,51,13,15,0,-12,0]}}
  #|{"textrec":{"g":381,"r":[439,51,12,12,0,-11,0]}}
  #|{"textrec":{"g":382,"r":[452,51,10,12,-1,-11,0]}}
  #|{"textrec":{"g":383,"r":[463,51,10,13,-1,-11,0]}}
  #|{"textrec":{"g":384,"r":[474,51,11,13,-1,-11,0]}}
  #|{"textrec":{"g":385,"r":[486,51,9,12,0,-11,0]}}
  #|{"textrec":{"g":386,"r":[496,51,9,12,-1,-11,0]}}
  #|{"textrec":{"g":387,"r":[506,51,9,12,-1,-11,0]}}
  #|{"textrec":{"g":388,"r":[516,51,10,13,-1,-11,0]}}
  #|{"textrec":{"g":389,"r":[527,51,13,12,-1,-10,0]}}
  #|{"textrec":{"g":390,"r":[541,51,13,12,-1,-10,0]}}
  #|{"textrec":{"g":391,"r":[555,51,13,13,-1,-10,0]}}
  #|{"textrec":{"g":392,"r":[569,51,9,11,-1,-9,0]}}
  #|{"textrec":{"g":393,"r":[579,51,9,10,-1,-9,0]}}
  #|{"textrec":{"g":394,"r":[589,51,5,5,-1,-3,0]}}
  #|{"textrec":{"g":395,"r":[595,51,9,10,-1,-9,0]}}
  #|{"textrec":{"g":396,"r":[605,51,10,11,-1,-9,0]}}
  #|{"textrec":{"g":397,"r":[616,51,11,14,0,-13,0]}}
  #|{"textrec":{"g":398,"r":[628,51,8,5,0,-7,0]}}
  #|{"textrec":{"g":399,"r":[637,51,11,15,0,-13,0]}}
  #|{"textrec":{"g":400,"r":[649,51,13,15,-1,-13,0]}}
  #|{"textrec":{"g":401,"r":[663,51,11,14,-1,-13,0]}}
  #|{"textrec":{"g":402,"r":[675,51,12,15,-1,-13,0]}}
  #|{"textrec":{"g":403,"r":[688,51,11,15,0,-13,0]}}
  #|{"textrec":{"g":404,"r":[700,51,7,12,1,-13,0]}}
  #|{"textrec":{"g":405,"r":[708,51,7,4,0,-6,0]}}
  #|{"textrec":{"g":406,"r":[716,51,11,14,-1,-12,0]}}
  #|{"textrec":{"g":407,"r":[728,51,10,12,-1,-11,0]}}
  #|{"textrec":{"g":408,"r":[739,51,11,14,-1,-12,0]}}
  #|{"textrec":{"g":409,"r":[751,51,9,14,0,-12,0]}}
  #|{"textrec":{"g":410,"r":[761,51,7,11,-1,-8,0]}}
  #|{"textrec":{"g":411,"r":[769,51,14,14,7,-12,0]}}
  #|{"textrec":{"g":412,"r":[784,51,16,15,-1,-12,0]}}
  #|{"textrec":{"g":413,"r":[801,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":414,"r":[817,51,15,16,0,-13,0]}}
  #|{"textrec":{"g":415,"r":[833,51,15,16,-1,-13,0]}}
  #|{"textrec":{"g":416,"r":[849,51,16,16,-1,-13,0]}}
  #|{"textrec":{"ib":["db8e2edd568ad1fd",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"s":[16,600,0,"e2e-080726-b"],"r":[0,1,9.127458572387695,46,1,1,9.717817306518555,417,2,1,9.100765228271484,46,3,1,7.363014221191406,418,4,1,10.31976318359375,419,5,1,10.440597534179688,420,6,1,10.138774871826172,419,7,1,8.996856689453125,421,8,1,9.744510650634766,417,9,1,10.3499755859375,422,10,1,7.363014221191406,418,11,1,9.891647338867188,423]}}
  #|{"textrec":{"s":[17,400,0,"Station"],"r":[0,1,10.40087890625,424,1,1,5.744140625,425,2,1,8.9482421875,426,3,1,5.744140625,425,4,1,3.7685546875,427,5,1,9.6123046875,428,6,1,9.48779296875,429]}}
  #|{"textrec":{"s":[15,600,0,"在此 station 上"],"r":[0,1,14.883268482490273,430,1,1,14.883268482490273,117,2,1,3.761730194091797,-1,3,1,8.000344634056091,431,4,1,5.658300518989563,432,5,1,8.40147078037262,433,6,1,5.683325529098511,432,7,1,3.8520312309265137,434,8,1,8.901597261428833,435,9,1,8.93320620059967,173,10,1,3.761730194091797,-1,11,1,14.883268482490266,436]}}
  #|{"textrec":{"s":[15,400,0,"共享调试"],"r":[0,1,14.883268482490273,437,1,1,14.883268482490273,438,2,1,14.883268482490273,439,3,1,14.883268482490273,440]}}
  #|{"textrec":{"g":424,"r":[866,51,12,16,-1,-14,0]}}
  #|{"textrec":{"g":425,"r":[879,51,8,15,-1,-13,0]}}
  #|{"textrec":{"g":426,"r":[888,51,11,13,-1,-11,0]}}
  #|{"textrec":{"g":427,"r":[900,51,5,15,0,-14,0]}}
  #|{"textrec":{"g":428,"r":[906,51,12,13,-1,-11,0]}}
  #|{"textrec":{"g":429,"r":[919,51,10,12,0,-11,0]}}
  #|{"textrec":{"g":430,"r":[930,51,16,17,-1,-14,0]}}
  #|{"textrec":{"g":431,"r":[947,51,10,12,-1,-10,0]}}
  #|{"textrec":{"g":432,"r":[958,51,8,13,-1,-11,0]}}
  #|{"textrec":{"g":433,"r":[967,51,10,12,-1,-10,0]}}
  #|{"textrec":{"g":434,"r":[978,51,6,14,-1,-13,0]}}
  #|{"textrec":{"g":435,"r":[985,51,11,12,-1,-10,0]}}
  #|{"textrec":{"g":436,"r":[997,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":437,"r":[1014,51,16,17,-1,-14,0]}}
  #|{"textrec":{"g":438,"r":[1031,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":439,"r":[1048,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":440,"r":[1065,51,17,16,-1,-13,0]}}
  #|{"textrec":{"g":46,"r":[1083,51,11,12,-1,-10,0]}}
  #|{"textrec":{"g":417,"r":[1095,51,11,14,0,-13,0]}}
  #|{"textrec":{"g":418,"r":[1107,51,8,5,0,-7,0]}}
  #|{"textrec":{"g":419,"r":[1116,51,11,15,0,-13,0]}}
  #|{"textrec":{"g":420,"r":[1128,51,12,15,-1,-13,0]}}
  #|{"textrec":{"g":421,"r":[1141,51,11,14,-1,-13,0]}}
  #|{"textrec":{"g":422,"r":[1153,51,12,15,-1,-13,0]}}
  #|{"textrec":{"g":423,"r":[1166,51,11,15,0,-13,0]}}
  #|{"textrec":{"ib":["ddfdc2820df8a676",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"s":[17,700,0,"e2e-080726-b"],"r":[0,1,9.782470703125,441,1,1,10.479736328125,442,2,1,9.76171875,441,3,1,7.802734375,443,4,1,11.2060546875,444,5,1,11.322265625,445,6,1,10.99853515625,444,7,1,9.6787109375,446,8,1,10.50048828125,442,9,1,11.189453125,447,10,1,7.802734375,443,11,1,10.6416015625,448]}}
  #|{"textrec":{"s":[15,400,0,"重命名"],"r":[0,1,14.883268482490273,449,1,1,14.883268482490273,450,2,1,14.883268482490273,263]}}
  #|{"textrec":{"s":[15,400,0,"图标"],"r":[0,1,14.883268482490273,451,1,1,14.883268482490273,452]}}
  #|{"textrec":{"s":[15,400,0,"从 workspace 移除"],"r":[0,1,14.883268482490273,453,1,1,3.984375,-1,2,1,11.2353515625,454,3,1,8.4814453125,88,4,1,5.478515625,89,5,1,7.763671875,90,6,1,7.470703125,91,7,1,8.920898437500007,92,8,1,8.0419921875,93,9,1,8.1591796875,94,10,1,8.3349609375,95,11,1,3.984375,-1,12,1,14.88326848249028,455,13,1,14.88326848249028,456]}}
  #|{"textrec":{"g":441,"r":[1178,51,12,13,-1,-11,0]}}
  #|{"textrec":{"g":442,"r":[1191,51,11,15,0,-14,0]}}
  #|{"textrec":{"g":443,"r":[1203,51,8,5,0,-7,0]}}
  #|{"textrec":{"g":444,"r":[1212,51,12,16,0,-14,0]}}
  #|{"textrec":{"g":445,"r":[1225,51,12,16,0,-14,0]}}
  #|{"textrec":{"g":446,"r":[1238,51,12,14,-1,-13,0]}}
  #|{"textrec":{"g":447,"r":[1251,51,12,16,0,-14,0]}}
  #|{"textrec":{"g":448,"r":[1264,51,12,16,0,-14,0]}}
  #|{"textrec":{"g":449,"r":[1277,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":450,"r":[1294,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":451,"r":[1311,51,15,16,0,-13,0]}}
  #|{"textrec":{"g":452,"r":[1327,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":453,"r":[1344,51,17,16,-1,-13,0]}}
  #|{"textrec":{"g":454,"r":[1362,51,14,10,-1,-9,0]}}
  #|{"textrec":{"g":455,"r":[1377,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":456,"r":[1394,51,16,16,0,-13,0]}}
  #|{"textrec":{"s":[17,700,0,"移除「e2e-080726-b」？"],"r":[0,1,16.851167315175097,457,1,1,25.351167315175097,458,2,1,6.366731517509727,459,3,1,9.782470703125,441,4,1,10.479736328125007,442,5,1,9.76171875,441,6,1,7.802734375,443,7,1,11.2060546875,444,8,1,11.322265625,445,9,1,10.99853515625,444,10,1,9.6787109375,446,11,1,10.50048828125,442,12,1,11.189453125,447,13,1,7.802734375,443,14,1,10.6416015625,448,15,1,8.194066147859928,460,16,1,8.582684824902714,461]}}
  #|{"textrec":{"s":[14,400,0,"它将断开与 still.fail cloud 的连接，成员无法再从这里访问它。该机器上的 still.fail 和数据不受影响，以后可以重新添加。"],"r":[0,1,13.891050583657588,233,1,1,13.891050583657588,462,2,1,13.891050583657588,463,3,1,13.891050583657588,97,4,1,13.891050583657588,464,5,1,3.787109375,-1,6,1,7.1435546875,219,7,1,4.9013671875,61,8,1,3.30859375,220,9,1,3.390625,226,10,1,3.390625,226,11,1,3.80078125,227,12,1,4.607421875,228,13,1,7.4716796875,57,14,1,3.30859375,220,15,1,3.390625,226,16,1,3.787109375,-1,17,1,7.683593750000014,465,18,1,3.390625,226,19,1,8.12109375,221,20,1,8.0185546875,466,21,1,8.44921875,467,22,1,3.787109375,-1,23,1,13.891050583657602,56,24,1,13.891050583657602,468,25,1,13.891050583657602,469,26,1,14.081712062256798,50,27,1,13.891050583657574,244,28,1,13.891050583657602,470,29,1,13.891050583657602,471,30,1,13.891050583657602,472,31,1,13.891050583657602,473,32,1,13.891050583657602,474,33,1,13.891050583657602,475,34,1,13.891050583657602,476,35,1,13.891050583657602,477,36,1,13.891050583657602,478,37,1,13.891050583657602,233,38,1,14.081712062256827,231,39,1,13.891050583657602,238,40,1,13.891050583657602,229,41,1,13.891050583657602,230,42,1,13.891050583657602,479,43,1,13.891050583657602,56,44,1,3.787109375,-1,45,1,7.1435546875,219,46,1,4.9013671875,61,47,1,3.30859375,220,48,1,3.390625,226,49,1,3.390625,226,50,1,3.80078125,227,51,1,4.607421875,228,52,1,7.4716796875,57,53,1,3.30859375,220,54,1,3.390625,226,55,1,3.787109375,-1,56,1,13.891050583657602,480,57,1,13.891050583657602,481,58,1,13.891050583657602,482,59,1,13.891050583657602,483,60,1,13.891050583657602,484,61,1,13.891050583657602,485,62,1,13.891050583657602,486,63,1,14.08171206225677,50,64,1,13.891050583657602,414,65,1,13.891050583657602,237,66,1,13.891050583657602,413,67,1,13.891050583657602,414,68,1,13.891050583657602,487,69,1,13.891050583657602,488,70,1,13.891050583657602,489,71,1,13.891050583657602,250,72,1,7.08171206225677,231]}}
  #|{"textrec":{"s":[14,600,0,"移除 station"],"r":[0,1,13.891050583657588,490,1,1,13.891050583657588,491,2,1,3.5793075561523438,-1,3,1,7.5353477001190186,492,4,1,5.349439859390259,493,5,1,7.909732103347778,494,6,1,5.372796535491943,493,7,1,3.663588523864746,495,8,1,8.376516819000244,496,9,1,8.406018495559692,497]}}
  #|{"textrec":{"g":457,"r":[1411,51,18,18,-1,-15,0]}}
  #|{"textrec":{"g":458,"r":[1430,51,18,18,0,-15,0]}}
  #|{"textrec":{"g":459,"r":[1449,51,9,13,-1.8333333333333304,-15,0]}}
  #|{"textrec":{"g":460,"r":[1459,51,9,13,-1,-10,0]}}
  #|{"textrec":{"g":461,"r":[1469,51,10,16,-1,-14,0]}}
  #|{"textrec":{"g":462,"r":[1480,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":463,"r":[1497,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":464,"r":[1514,51,15,16,-1,-13,0]}}
  #|{"textrec":{"g":465,"r":[1530,51,10,11,-1,-9,0]}}
  #|{"textrec":{"g":466,"r":[1541,51,9,11,0,-9,0]}}
  #|{"textrec":{"g":467,"r":[1551,51,10,14,-1,-12,0]}}
  #|{"textrec":{"g":468,"r":[1562,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":469,"r":[1579,51,15,16,-1,-13,0]}}
  #|{"textrec":{"g":470,"r":[1595,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":471,"r":[1611,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":472,"r":[1627,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":473,"r":[1644,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":474,"r":[1660,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":475,"r":[1677,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":476,"r":[1694,51,15,14,-1,-12,0]}}
  #|{"textrec":{"g":477,"r":[1710,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":478,"r":[1727,51,14,16,0,-13,0]}}
  #|{"textrec":{"g":479,"r":[1742,51,15,15,-1,-13,0]}}
  #|{"textrec":{"g":480,"r":[1758,51,15,16,-1,-13,0]}}
  #|{"textrec":{"g":481,"r":[1774,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":482,"r":[1791,51,15,16,-1,-13,0]}}
  #|{"textrec":{"g":483,"r":[1807,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":484,"r":[1823,51,15,16,-1,-13,0]}}
  #|{"textrec":{"g":485,"r":[1839,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":486,"r":[1856,51,14,16,0,-13,0]}}
  #|{"textrec":{"g":487,"r":[1871,51,15,16,-1,-13,0]}}
  #|{"textrec":{"g":488,"r":[1887,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":489,"r":[1904,51,16,15,-1,-12,0]}}
  #|{"textrec":{"g":490,"r":[1921,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":491,"r":[1938,51,16,15,-1,-12,0]}}
  #|{"textrec":{"g":492,"r":[1955,51,10,11,-1,-9,0]}}
  #|{"textrec":{"g":493,"r":[1966,51,7,13,-1,-11,0]}}
  #|{"textrec":{"g":494,"r":[1974,51,10,11,-1,-9,0]}}
  #|{"textrec":{"g":495,"r":[1985,51,5,13,-1,-12,0]}}
  #|{"textrec":{"g":496,"r":[1991,51,10,11,-1,-9,0]}}
  #|{"textrec":{"g":497,"r":[2002,51,9,10,0,-9,0]}}
  #|{"textrec":{"s":[14,400,0,"已移除 station"],"r":[0,1,13.891050583657588,498,1,1,13.891050583657588,499,2,1,13.891050583657588,500,3,1,3.787109375,-1,4,1,7.1435546875,219,5,1,4.9013671875,61,6,1,7.57421875,57,7,1,4.935546875,61,8,1,3.30859375,220,9,1,8.12109375,221,10,1,8.0185546875,60]}}
  #|{"textrec":{"g":498,"r":[2012,51,14,14,0,-12,0]}}
  #|{"textrec":{"g":499,"r":[2027,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":500,"r":[0,70,15,15,0,-12,0]}}
  #|{"textrec":{"s":[16,600,0,"3393fc76a6422b2a1640c4d5593165cff397ad429fe70ecc5e9ae63dbdae8b35"],"r":[0,1,10.144248962402344,501,1,1,10.131879806518555,501,2,1,10.300498962402344,502,3,1,10.107141494750977,501,4,1,5.78688907623291,503,5,1,8.621533393859863,504,6,1,8.904407501220703,421,7,1,10.245157241821289,422,8,1,8.899068832397461,44,9,1,10.3499755859375,422,10,1,10.42471694946289,505,11,1,9.744510650634766,417,12,1,9.744510650634766,417,13,1,9.891647338867188,423,14,1,9.744510650634766,417,15,1,8.685522079467773,44,16,1,7.380699157714844,506,17,1,10.3499755859375,422,18,1,10.42471694946289,505,19,1,10.31976318359375,419,20,1,8.92264175415039,504,21,1,10.42471694946289,505,22,1,9.891647338867188,507,23,1,10.035783767700195,508,24,1,10.035783767700195,508,25,1,10.312868118286133,502,26,1,10.107141494750977,501,27,1,7.594245910644531,506,28,1,10.3499755859375,422,29,1,10.035783767700195,508,30,1,9.029415130615234,504,31,1,6.075628280639648,503,32,1,5.968854904174805,503,33,1,10.131879806518555,501,34,1,10.181356430053711,502,35,1,8.70713996887207,421,36,1,8.609352111816406,44,37,1,9.891647338867188,507,38,1,10.42471694946289,505,39,1,9.744510650634766,417,40,1,10.3499755859375,502,41,1,5.78688907623291,503,42,1,8.80161190032959,46,43,1,8.879669189453125,421,44,1,10.214944839477539,419,45,1,9.127458572387695,46,46,1,8.92264175415039,504,47,1,8.92264175415039,504,48,1,10.035783767700195,508,49,1,9.127458572387695,46,50,1,10.3499755859375,502,51,1,8.899068832397461,44,52,1,9.127458572387695,46,53,1,10.312868118286133,422,54,1,10.082403182983398,501,55,1,9.86690902709961,507,56,1,9.891647338867188,423,57,1,9.891647338867188,507,58,1,8.899068832397461,44,59,1,9.127458572387695,46,60,1,10.465335845947266,420,61,1,9.86690902709961,423,62,1,10.119510650634766,501,63,1,10.035783767700195,508]}}
  #|{"textrec":{"g":501,"r":[16,70,11,15,0,-13,0]}}
  #|{"textrec":{"g":502,"r":[28,70,12,15,-1,-13,0]}}
  #|{"textrec":{"g":503,"r":[41,70,8,14,-1,-13,0]}}
  #|{"textrec":{"g":504,"r":[50,70,11,12,-1,-10,0]}}
  #|{"textrec":{"g":505,"r":[62,70,12,14,-1,-13,0]}}
  #|{"textrec":{"g":506,"r":[75,70,7,14,0,-13,0]}}
  #|{"textrec":{"g":507,"r":[83,70,11,15,-1,-13,0]}}
  #|{"textrec":{"g":508,"r":[95,70,11,15,0,-13,0]}}
