// e2e/traces/settings-device-pages.trace, made by scripts/trace.py from 09-settings_device_pages.log: not edited by hand.

///|
/// What the app and its core said in the run, a line each.
pub let trace_settings_device_pages : String =
  #|{"start":"base"}
  #|{"step":"drive-seed 032949"}
  #|{"env":{"MBUI_CLOUD":"http://127.0.0.1:18900","MBUI_CORE_ACCOUNT":"{\"sub\":\"alice\",\"email\":\"alice@example.test\",\"name\":\"Name of alice\",\"picture\":\"\",\"access\":\"-\",\"refresh\":\"-\",\"accessExpires\":1792524897}"}}
  #|{"out":{"id":1,"call":"client.device","params":{"client":"still.fail mbui","app":"desktop","userAgent":"Macintosh; Mac OS X"}},"w":1792524897013.036}
  #|{"in":{"id":1,"ok":null},"w":1792524897207.345}
  #|{"out":{"id":2,"subscribe":{"topic":"accounts"},"keyed":true},"w":1792524897207.372}
  #|{"out":{"id":3,"subscribe":{"topic":"prefs"},"keyed":true},"w":1792524897207.383}
  #|{"step":"# written by scripts/rerecord.sh from its test (src/sfreplay/emit.mbt): not edited by hand","w":1792524897209.236}
  #|{"step":"timeout 90000","w":1792524897209.243}
  #|{"step":"answered client.device","w":1792524897209.246}
  #|{"step":"answered client.focus","w":1792524897228.253}
  #|{"in":{"id":2,"value":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""}]},"w":1792524897277.79}
  #|{"in":{"id":3,"value":{"onlyMine":false,"onlyWatching":false,"onlyDecisions":false,"listFilter":{},"appearance":"system","rowPicture":"auto","absoluteTime":false,"lang":"zh","keys":{},"lastChat":{},"openChat":{},"chatTabs":{},"dropFiles":{},"driveViews":{},"resume":{},"stationUpdatesDismissed":{},"device":{"app":"desktop","phone":false,"handoff":false},"reader":{"size":18,"line":1.7,"margin":22,"face":"sans","indent":true,"paper":"follow"},"rails":{},"bars":{"sets":[["chats","files","profiles","stations"],["decisions","usage","connects","archive"]],"current":0},"barsBy":{}}},"w":1792524897277.811}
  #|{"out":{"id":4,"subscribe":{"topic":"workspaces"},"keyed":true},"w":1792524897277.835}
  #|{"out":{"id":5,"subscribe":{"topic":"status"},"keyed":true},"w":1792524897277.847}
  #|{"in":{"id":4,"value":[{"account":{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""},"workspaces":[{"id":"01M5DCN9EHV11TX62FVBT8G02C","name":"Dev","role":"owner","created_at":1792524592,"stations":1,"members":1,"relays":[],"time":{"created_at":{"past":true,"at":1792524592000,"ago":"5 分钟前","full":"10/21 03:29:52","until":"1 分钟内"}}}],"invitations":[],"relay_url":"http://127.0.0.1:18940","loaded":false,"beta":true}]},"w":1792524897294.475}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792524897294.5}
  #|{"out":{"id":6,"subscribe":{"topic":"lock","workspace":"01M5DCN9EHV11TX62FVBT8G02C"},"keyed":true},"w":1792524897294.54}
  #|{"out":{"id":7,"subscribe":{"topic":"chats","scope":"01M5DCN9EHV11TX62FVBT8G02C","mine":false},"keyed":true},"w":1792524897294.561}
  #|{"out":{"id":8,"subscribe":{"topic":"workspaceMarks","workspace":"01M5DCN9EHV11TX62FVBT8G02C"},"keyed":true},"w":1792524897294.689}
  #|{"out":{"id":9,"subscribe":{"topic":"status","workspace":"01M5DCN9EHV11TX62FVBT8G02C"},"keyed":true},"w":1792524897294.721}
  #|{"out":{"id":10,"call":"client.focus","params":{"visible":true,"focused":true,"workspace":"01M5DCN9EHV11TX62FVBT8G02C"}},"w":1792524897300.339}
  #|{"out":{"id":11,"subscribe":{"topic":"notify"},"keyed":true},"w":1792524897300.35}
  #|{"out":{"id":12,"subscribe":{"topic":"notify","workspace":"01M5DCN9EHV11TX62FVBT8G02C"},"keyed":true},"w":1792524897300.356}
  #|{"in":{"id":4,"delta":[{"path":[0,"loaded"],"set":true}]},"w":1792524897311.12}
  #|{"in":{"id":6,"value":{"available":true,"locked":false,"notice":true,"role":"owner","manages":true,"owner":true,"canSign":true,"signs":false,"me":{"device":"7508068c0838052834dcdd24dd864d54a9300b8708e8b2f2324424a37bc525fe","code":"2CS-XCW","kind":"app","confirmed":false,"waiting":false,"asked":false},"signers":0,"members":[],"stations":[{"id":"c008a2ee339e1d2873590d026fb43eabcc4b43ea9ae504c9d2c1d6517428b244","name":"studio","version":"0.1.0","online":true,"protected":false}],"protected":0,"requests":[],"renew":[],"attention":0}},"w":1792524897311.137}
  #|{"in":{"id":7,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"stations":[{"station":"01M5DCN9EHV11TX62FVBT8G02C/c008a2ee339e1d2873590d026fb43eabcc4b43ea9ae504c9d2c1d6517428b244","id":"c008a2ee339e1d2873590d026fb43eabcc4b43ea9ae504c9d2c1d6517428b244","name":"studio","state":"online"}],"loading":false,"days":[{"daysAgo":0,"at":1792524597114,"label":"今天","items":[{"id":"ember:c-680584e540","session":"ember:c-680584e540","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","agents":[{"key":"ember:c-680584e540","runtime":"claude","process":"warm","pending":0,"lastTurn":{"id":"bcf24f08-9b85-4698-bf0d-c70c9355816b","kind":"input","outcome":"completed","declared":"final","ending":"all_done","need":"answered the question that was asked","startedAt":1792524597028,"endedAt":1792524597117},"agentText":"默认模型","statusText":"已完成：answered the question that was asked"}],"last":{"seq":2,"authorKind":"agent","author":"ember:c-680584e540","text":"你好，我是测试用的 agent","createdAt":1792524597114,"by":{"kind":"agent","name":"agent","mine":false,"runtime":"claude","label":"agent"},"preview":"你好，我是测试用的 agent","time":{"createdAt":{"at":1792524597114,"ago":"5 分钟前","full":"10/21 03:29:57","until":"1 分钟内","past":true}}},"unread":true,"mine":true,"lastActiveAt":1792524597114,"station":"01M5DCN9EHV11TX62FVBT8G02C/c008a2ee339e1d2873590d026fb43eabcc4b43ea9ae504c9d2c1d6517428b244","stationName":"studio","time":{"lastActiveAt":{"at":1792524597114,"ago":"5 分钟前","full":"10/21 03:29:57","until":"1 分钟内","past":true}},"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"peopleText":"你 发起","clientKey":"new:chat-a35a0a154db00eb361","pinned":false,"tone":"done"}]}],"trouble":null,"members":1,"leading":"agents","glyph":{"online":1,"dim":0,"connecting":0,"failing":0,"working":0,"summary":"studio","label":"1 台 station，1 台在线"},"note":{"reading":false,"text":null,"failing":[],"empty":false}}},"w":1792524897311.169}
  #|{"in":{"id":8,"value":{"workspaces":{"01M5DCN9EHV11TX62FVBT8G02C":{"alert":0,"unread":1,"tone":"done","label":"1 个有新消息","badge":0,"items":[],"mineTone":"done"}},"badge":0,"badgeCounts":"attention","badgeKinds":{"on":true,"wait":true,"failed":true,"done":false,"message":false}}},"w":1792524897311.191}
  #|{"in":{"id":9,"value":{"items":[]}},"w":1792524897311.196}
  #|{"in":{"id":10,"ok":null},"w":1792524897311.198}
  #|{"in":{"id":11,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792524897311.203}
  #|{"in":{"id":12,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792524897311.207}
  #|{"out":{"id":13,"subscribe":{"topic":"longJobs","scope":"01M5DCN9EHV11TX62FVBT8G02C"},"keyed":true},"w":1792524897311.244}
  #|{"out":{"id":14,"call":"notify.permission","params":{"state":"unknown"}},"w":1792524897313.988}
  #|{"in":{"id":13,"value":{"groups":[]}},"w":1792524897329.799}
  #|{"in":{"id":14,"ok":null},"w":1792524897329.813}
  #|{"step":"answered notify.permission","w":1792524897330.235}
  #|{"step":"tap icon:settings","w":1792524897344.807}
  #|{"step":"tap icon:settings","acted":true,"w":1792524897361.425}
  #|{"out":{"id":15,"subscribe":{"topic":"workspace","workspace":"01M5DCN9EHV11TX62FVBT8G02C"},"keyed":true},"w":1792524897377.954}
  #|{"out":{"id":16,"subscribe":{"topic":"stations","scope":"01M5DCN9EHV11TX62FVBT8G02C"},"keyed":true},"w":1792524897377.97}
  #|{"out":{"id":17,"subscribe":{"topic":"connects","scope":"01M5DCN9EHV11TX62FVBT8G02C","mine":false},"keyed":true},"w":1792524897377.983}
  #|{"out":{"id":18,"subscribe":{"topic":"vaults","workspace":"01M5DCN9EHV11TX62FVBT8G02C"},"keyed":true},"w":1792524897377.989}
  #|{"out":{"id":19,"subscribe":{"topic":"doing"},"keyed":true},"w":1792524897385.397}
  #|{"step":"rest","w":1792524897386.964}
  #|{"in":{"id":15,"value":{"id":"01M5DCN9EHV11TX62FVBT8G02C","name":"Dev","role":"owner","created_at":1792524592,"members":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":"https://example.test/p.png","role":"owner","added_at":1792524592}],"stations":[{"id":"c008a2ee339e1d2873590d026fb43eabcc4b43ea9ae504c9d2c1d6517428b244","name":"studio","emoji":null,"icon":null,"enrolled_at":1792524593,"enrolled_by":"alice","last_seen":1792524598,"version":"0.1.0","time":{"last_seen":{"past":true,"at":1792524598000,"ago":"5 分钟前","full":"10/21 03:29:58","until":"1 分钟内"}}}],"invitations":[],"added":[],"relays":[],"lock":null,"lock_requests":0,"time":{"created_at":{"past":true,"at":1792524592000,"ago":"5 分钟前","full":"10/21 03:29:52","until":"1 分钟内"}}}},"w":1792524897394.476}
  #|{"in":{"id":16,"value":[{"station":"01M5DCN9EHV11TX62FVBT8G02C/c008a2ee339e1d2873590d026fb43eabcc4b43ea9ae504c9d2c1d6517428b244","id":"c008a2ee339e1d2873590d026fb43eabcc4b43ea9ae504c9d2c1d6517428b244","name":"studio","summary":"正在连接","face":"idle","line":"在线","online":true,"reconnecting":true,"lastSeen":1792524598,"version":"0.1.0","link":{"state":"connecting"},"runtimes":[{"runtime":"claude","models":["claude-sonnet-5-5"]}],"models":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792524597005,"time":{"checkedAt":{"at":1792524597005,"ago":"5 分钟前","full":"10/21 03:29:57","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"overview":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null,"summaryText":"最近 7 天检查了 0 个 chat","changeText":null}},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","email":"alice@example.test","name":"Name of alice","sub":"alice","role":"owner","workspace":"01M5DCN9EHV11TX62FVBT8G02C","device":"7508068c0838052834dcdd24dd864d54a9300b8708e8b2f2324424a37bc525fe"},"connects":[],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792524596815,"time":{"checkedAt":{"at":1792524596815,"ago":"5 分钟前","full":"10/21 03:29:56","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792524597005,"time":{"checkedAt":{"at":1792524597005,"ago":"5 分钟前","full":"10/21 03:29:57","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]}],"processes":[],"counts":{"sessions":1,"running":0,"warm":1},"mesh":{"state":"running","origin":"http://127.0.0.1:18900","station":"c008a2ee339e1d2873590d026fb43eabcc4b43ea9ae504c9d2c1d6517428b244","workspace":"Dev","workspaceId":"01M5DCN9EHV11TX62FVBT8G02C","name":"studio"},"slackUsers":[],"slackTeams":[],"slackApps":[],"feishuRegistrations":[],"disk":{"freeBytes":67701837824,"totalBytes":245107195904},"logins":[],"machineLogins":[],"sharing":true,"consoleSignIn":true,"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"google","name":"Google Gemini","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xai","name":"xAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"mistral","name":"Mistral","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"deepseek","name":"DeepSeek","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen","name":"Qwen","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai","name":"Kimi","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai","name":"Z.ai","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax","name":"MiniMax","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ant-ling","name":"Ant Ling","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"jev","name":"Jev","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen-cn","name":"Qwen (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"openrouter","name":"OpenRouter","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"opencode","name":"OpenCode Zen","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"groq","name":"Groq","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"together","name":"Together AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"fireworks","name":"Fireworks","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cerebras","name":"Cerebras","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"huggingface","name":"Hugging Face","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"nvidia","name":"NVIDIA","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"baseten","name":"Baseten","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ollama","name":"Ollama","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"custom","name":"Custom","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""}],"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792524594499},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.304","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792524594499},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792524594499},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792524594499},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792524594499}],"processesText":"没有运行中的 agent 进程","agentEnv":[],"drive":{"roots":[],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false}},"betaOffered":false,"time":{"lastSeen":{"at":1792524598000,"ago":"5 分钟前","full":"10/21 03:29:58","until":"1 分钟内","past":true}},"joined":false}]},"w":1792524897394.583}
  #|{"in":{"id":17,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"items":[],"wait":{"reading":false,"text":null,"failing":[],"empty":true}}},"w":1792524897394.656}
  #|{"in":{"id":18,"value":{"available":true,"locked":false,"canSign":false,"setUp":false,"vaults":[{"id":"plain","name":"个人","owner":"alice","ownerName":"Name of alice","mine":true,"members":[{"sub":"alice","name":"Name of alice"}],"station":"c008a2ee339e1d2873590d026fb43eabcc4b43ea9ae504c9d2c1d6517428b244","stationName":"studio","items":0,"devices":0,"open":true,"keyed":true,"missing":0,"recoverable":false}],"requests":[],"refused":[{"station":"c008a2ee339e1d2873590d026fb43eabcc4b43ea9ae504c9d2c1d6517428b244","name":"studio","code":"vault_needs_lock"}],"plain":true}},"w":1792524897394.664}
  #|{"in":{"id":19,"value":{"doing":[]}},"w":1792524897394.671}
  #|{"step":"now wheelat 500 Workspace","w":1792524898145.239}
  #|{"step":"now wheelat 500 Workspace","acted":true,"w":1792524898161.896}
  #|{"step":"rest","w":1792524898183.417}
  #|{"in":{"id":5,"value":{"state":"slow","text":"正在连接 studio ×3 · 2 秒 · 共 5 项","items":[{"state":"slow","text":"正在连接 studio ×3","detail":"已等待 2 秒"},{"state":"slow","text":"studio 打开实时更新 ×2","detail":"已等待 2 秒，尚未收到数据"}]}},"w":1792524899461.205}
  #|{"in":{"id":9,"value":{"state":"slow","text":"正在连接 studio ×3 · 2 秒 · 共 5 项","items":[{"state":"slow","text":"正在连接 studio ×3","detail":"已等待 2 秒"},{"state":"slow","text":"studio 打开实时更新 ×2","detail":"已等待 2 秒，尚未收到数据"}]}},"w":1792524899461.288}
  #|{"step":"now tap =下方栏","w":1792524899478.812}
  #|{"step":"now tap =下方栏","acted":true,"w":1792524899495.46}
  #|{"step":"rest","w":1792524899532.811}
  #|{"step":"now until 第 1 栏","w":1792524899828.458}
  #|{"step":"tapxy 345 199","w":1792524899828.488}
  #|{"step":"tapxy 345 199","acted":true,"w":1792524899828.508}
  #|{"out":{"id":20,"call":"prefs.set","params":{"barsBy":{"01M5DCN9EHV11TX62FVBT8G02C":{"sets":[["chats","files","profiles"],["decisions","usage","connects","archive"]],"current":0}}}},"w":1792524899844.79}
  #|{"step":"answered prefs.set","w":1792524899845.22}
  #|{"in":{"id":20,"ok":null},"w":1792524899861.146}
  #|{"step":"tap =添加","w":1792524899878.464}
  #|{"step":"tap =添加","acted":true,"w":1792524899895.008}
  #|{"step":"rest","w":1792524899911.498}
  #|{"in":{"id":3,"delta":[{"path":["barsBy","01M5DCN9EHV11TX62FVBT8G02C"],"set":{"sets":[["chats","files","profiles"],["decisions","usage","connects","archive"]],"current":0}}]},"w":1792524900027.807}
  #|{"in":{"id":5,"value":{"state":"slow","text":"studio 打开实时更新 ×2 · 3 秒 · 共 2 项 · 42 B/s","items":[{"state":"slow","text":"studio 打开实时更新 ×2","detail":"已等待 3 秒，尚未收到数据"}]}},"w":1792524900211.179}
  #|{"in":{"id":9,"value":{"state":"slow","text":"studio 打开实时更新 ×2 · 3 秒 · 共 2 项 · 42 B/s","items":[{"state":"slow","text":"studio 打开实时更新 ×2","detail":"已等待 3 秒，尚未收到数据"}]}},"w":1792524900211.22}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792524900261.129}
  #|{"in":{"id":9,"value":{"items":[]}},"w":1792524900261.144}
  #|{"in":{"id":16,"delta":[{"path":[0,"link","state"],"set":"online"},{"path":[0,"models",0,"accounts","claude",0,"quota","checkedAt"],"set":1792524900228},{"path":[0,"models",0,"accounts","claude",0,"quota","time","checkedAt","ago"],"set":"刚刚"},{"path":[0,"models",0,"accounts","claude",0,"quota","time","checkedAt","at"],"set":1792524900228},{"path":[0,"models",0,"accounts","claude",0,"quota","time","checkedAt","full"],"set":"10/21 03:35:00"},{"path":[0,"overview","counts","warm"],"set":0},{"path":[0,"overview","disk","freeBytes"],"set":65421324288},{"path":[0,"overview","profiles",0,"check","checkedAt"],"set":1792524900052},{"path":[0,"overview","profiles",0,"check","time","checkedAt","ago"],"set":"刚刚"},{"path":[0,"overview","profiles",0,"check","time","checkedAt","at"],"set":1792524900052},{"path":[0,"overview","profiles",0,"check","time","checkedAt","full"],"set":"10/21 03:35:00"},{"path":[0,"overview","profiles",0,"quota","checkedAt"],"set":1792524900228},{"path":[0,"overview","profiles",0,"quota","time","checkedAt","ago"],"set":"刚刚"},{"path":[0,"overview","profiles",0,"quota","time","checkedAt","at"],"set":1792524900228},{"path":[0,"overview","profiles",0,"quota","time","checkedAt","full"],"set":"10/21 03:35:00"},{"path":[0,"overview","updates",0,"checkedAt"],"set":1792524897717},{"path":[0,"overview","updates",1,"checkedAt"],"set":1792524897717},{"path":[0,"overview","updates",2,"checkedAt"],"set":1792524897717},{"path":[0,"overview","updates",3,"checkedAt"],"set":1792524897717},{"path":[0,"overview","updates",4,"checkedAt"],"set":1792524897717},{"path":[0,"overview","updates",4,"latest"],"set":"1.0.62"},{"path":[0,"reconnecting"],"set":false}]},"w":1792524900261.162}
  #|{"in":{"id":7,"delta":[{"path":["days"],"key":["daysAgo"],"patch":0,"ops":[{"path":["items"],"key":["station","id"],"patch":["01M5DCN9EHV11TX62FVBT8G02C/c008a2ee339e1d2873590d026fb43eabcc4b43ea9ae504c9d2c1d6517428b244","ember:c-680584e540"],"ops":[{"path":["agents",0,"process"],"set":"cold"},{"path":["clientKey"],"remove":true}]}]}]},"w":1792524900361.126}
  #|{"in":{"id":16,"delta":[{"path":[0,"host"],"set":{"hostname":"3720-Mac-mini-1","os":"macOS 27.0.1","arch":"arm64","cpus":10,"cpuModel":"Apple M4","load":1.29,"cpuBusy":0.44,"uptimeSec":4262,"memory":{"totalBytes":17179869184,"usedBytes":8753758208,"swapUsedBytes":358738821},"disk":{"path":"/tmp/mbe2e-C/data","totalBytes":245107195904,"freeBytes":65421258752},"emberRssBytes":138147280,"checkedAt":1792524900283,"summary":"10 核 · 16 GB","line":"macOS 27.0.1 · 10 核 · 16 GB · 已运行 0 天","facts":["3720-Mac-mini-1","macOS 27.0.1","arm64 · 10 核","已运行 1 小时"],"meters":[{"label":"CPU","short":"CPU","percent":44,"left":56,"level":"ok","value":"44%","remaining":"空闲 56%","big":"56","unit":"%","title":"CPU 空闲","total":"负载 12.9","note":"负载 12.9 · Apple M4"},{"label":"内存","short":"内存","percent":51,"left":49,"level":"ok","value":"8.2 GB / 16.0 GB","remaining":"剩 7.8 G","big":"7.8","unit":"GB","title":"内存剩","total":"共 16 GB","note":"swap 0.3 GB"},{"label":"磁盘","short":"磁盘","percent":73,"left":27,"level":"ok","value":"剩余 60.9 GB / 228 GB","remaining":"剩 60.9 G","big":"60.9","unit":"GB","title":"磁盘剩","total":"共 228 GB"}],"identity":"Apple M4 · 16 GB · macOS 27.0.1","details":[{"label":"主机名","value":"3720-Mac-mini-1"},{"label":"芯片","value":"Apple M4 · 10 核 · arm64"},{"label":"已运行","value":"1 小时"},{"label":"still.fail","value":"进程占用 132 MB"}],"usage":"内存 8.2 GB / 16.0 GB · 磁盘 剩余 60.9 GB / 228 GB","emberText":"still.fail 132 MB"}},{"path":[0,"line"],"set":"Apple M4"},{"path":[0,"summary"],"set":"空闲 · Apple M4 · 16 GB · macOS 27.0.1"}]},"w":1792524900561.222}
  #|{"step":"now until 添加到第 1 栏","w":1792524901395.665}
  #|{"step":"tap =用量","w":1792524901395.708}
  #|{"step":"tap =用量","acted":true,"w":1792524901412.42}
  #|{"out":{"id":21,"call":"prefs.set","params":{"barsBy":{"01M5DCN9EHV11TX62FVBT8G02C":{"sets":[["chats","files","profiles","usage"],["decisions","usage","connects","archive"]],"current":0}}}},"w":1792524901428.507}
  #|{"step":"answered prefs.set","w":1792524901429.3}
  #|{"in":{"id":21,"ok":null},"w":1792524901444.501}
  #|{"step":"rest","w":1792524901462.595}
  #|{"in":{"id":3,"delta":[{"path":["barsBy","01M5DCN9EHV11TX62FVBT8G02C","sets",0],"append":["usage"]}]},"w":1792524901577.835}
  #|{"in":{"id":16,"delta":[{"path":[0,"way"],"set":{"path":"直连","via":"direct"}}]},"w":1792524901894.481}
  #|{"step":"now back","w":1792524902911.643}
  #|{"step":"now back","acted":true,"w":1792524902911.656}
  #|{"step":"rest","w":1792524902928.842}
  #|{"step":"now tap =本机缓存","w":1792524903244.976}
  #|{"step":"now tap =本机缓存","acted":true,"w":1792524903261.59}
  #|{"out":{"id":22,"call":"cache.usage","params":{}},"w":1792524903279.845}
  #|{"step":"answered cache.usage","w":1792524903280.064}
  #|{"in":{"id":22,"ok":{"chats":[{"station":"01M5DCN9EHV11TX62FVBT8G02C/c008a2ee339e1d2873590d026fb43eabcc4b43ea9ae504c9d2c1d6517428b244","thread":1,"title":null,"sessions":["ember:c-680584e540"],"bytes":558}]}},"w":1792524903294.471}
  #|{"step":"rest","w":1792524903311.58}
  #|{"step":"now until chat #1","w":1792524903594.964}
  #|{"step":"back","w":1792524903594.987}
  #|{"step":"back","acted":true,"w":1792524903595.001}
  #|{"step":"rest","w":1792524903611.893}
  #|{"step":"now tap =更新日志","w":1792524903928.473}
  #|{"step":"now tap =更新日志","acted":true,"w":1792524903945.203}
  #|{"out":{"id":23,"subscribe":{"topic":"changelog"},"keyed":true},"w":1792524903961.6}
  #|{"step":"rest","w":1792524903964.481}
  #|{"in":{"id":23,"value":{"app":"desktop","tabs":[{"part":"desktop","label":"桌面","days":[]},{"part":"web","label":"网页","days":[]},{"part":"android","label":"安卓","days":[]},{"part":"station","label":"Station","days":[]},{"part":"cloud","label":"云端","days":[]}],"loading":false}},"w":1792524903977.832}
  #|{"step":"now back","w":1792524904278.513}
  #|{"step":"now back","acted":true,"w":1792524904278.537}
  #|{"step":"rest","w":1792524904295.559}
  #|{"step":"now wheelat -500 =本机缓存","w":1792524904628.505}
  #|{"step":"now wheelat -500 =本机缓存","acted":true,"w":1792524904645.356}
  #|{"step":"rest","w":1792524904662.549}
  #|{"step":"now tap =用量","w":1792524905961.641}
  #|{"step":"now tap =用量","acted":true,"w":1792524905978.517}
  #|{"out":{"id":24,"subscribe":{"topic":"usage","scope":"01M5DCN9EHV11TX62FVBT8G02C","days":7},"keyed":true},"w":1792524905995.129}
  #|{"step":"rest","w":1792524905998.284}
  #|{"in":{"id":24,"value":{"days":7,"wait":{"reading":true,"text":"正在从 studio 读取","failing":[],"empty":false},"empty":true,"tiles":[{"label":"折合费用","value":"$0","sub":"按 API 标准单价估算"},{"label":"模型调用","value":"0 次","sub":"日均 0 次"},{"label":"输入 token","value":"0","sub":"缓存命中 0%"},{"label":"输出 token","value":"0","sub":"平均每次 0"}],"series":[],"daily":[{"day":"2026-10-15","label":"10/15","today":false,"cost":0,"costText":"$0","calls":0,"callsText":"0 次调用","parts":[],"partsText":[]},{"day":"2026-10-16","label":"10/16","today":false,"cost":0,"costText":"$0","calls":0,"callsText":"0 次调用","parts":[],"partsText":[]},{"day":"2026-10-17","label":"10/17","today":false,"cost":0,"costText":"$0","calls":0,"callsText":"0 次调用","parts":[],"partsText":[]},{"day":"2026-10-18","label":"10/18","today":false,"cost":0,"costText":"$0","calls":0,"callsText":"0 次调用","parts":[],"partsText":[]},{"day":"2026-10-19","label":"10/19","today":false,"cost":0,"costText":"$0","calls":0,"callsText":"0 次调用","parts":[],"partsText":[]},{"day":"2026-10-20","label":"10/20","today":false,"cost":0,"costText":"$0","calls":0,"callsText":"0 次调用","parts":[],"partsText":[]},{"day":"2026-10-21","label":"10/21","today":true,"cost":0,"costText":"$0","calls":0,"callsText":"0 次调用","parts":[],"partsText":[]}],"max":0,"lists":[{"key":"people","title":"按人","items":[]},{"key":"chats","title":"按对话","items":[]},{"key":"profiles","title":"按账号","items":[]},{"key":"models","title":"按模型","items":[]}],"notes":[],"basis":"订阅账号不按 token 收费；费用按 API 标准单价估算，不含长上下文和服务等级等加价","prices":[{"station":"studio","note":"station 尚未提供价目表，请更新 station 后查看","rows":[]}]}},"w":1792524906011.268}
  #|{"in":{"id":24,"delta":[{"path":["prices",0,"note"],"set":"美元 / 100 万 token · 各类 token × 单价后相加；Claude fast ×2。GPT 按标准短上下文估算，仅记录输入、缓存读取和输出。GPT 价目核对于 2026-10-02，Claude 沿用 2026-09 价目"},{"path":["wait","empty"],"set":true},{"path":["wait","reading"],"set":false},{"path":["wait","text"],"set":null}]},"w":1792524906177.857}
  #|{"step":"now tap 查看价目表","w":1792524906311.528}
  #|{"step":"now tap 查看价目表","acted":true,"w":1792524906328.456}
  #|{"step":"rest","w":1792524906350.414}
  #|{"step":"now until =价目表","w":1792524906671.321}
  #|{"step":"rest","w":1792524906671.343}
  #|{"step":"","w":1792524906694.913}
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
  #|{"textrec":{"ib":["a7ccae3554fe46cf",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["bef2954d97ce1d9f",6508,64],"r":[40,40,40,40]}}
  #|{"textrec":{"ib":["31d8ec32aedeae00",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["fdb526ba00f881f4",3232,64],"r":[28,28,28,28]}}
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
  #|{"textrec":{"ib":["d61ec6305f7d8c8b",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["182b7158e0c0cae1",866,64],"r":[14,14,14,14]}}
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
  #|{"textrec":{"g":135,"r":[1967,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":136,"r":[1984,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":137,"r":[2001,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":138,"r":[2017,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":139,"r":[0,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":140,"r":[16,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":141,"r":[32,32,6,6,0,-3,0]}}
  #|{"textrec":{"g":142,"r":[39,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":143,"r":[54,32,15,14,-1,-11,0]}}
  #|{"textrec":{"g":144,"r":[70,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":145,"r":[86,32,15,13,-1,-11,0]}}
  #|{"textrec":{"g":146,"r":[102,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":147,"r":[116,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":148,"r":[132,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":149,"r":[148,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":150,"r":[163,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":151,"r":[179,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":152,"r":[194,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":153,"r":[210,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":154,"r":[226,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":155,"r":[242,32,14,14,-1,-12,0]}}
  #|{"textrec":{"g":4,"r":[257,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":160,"r":[272,32,5,5,0,-3,0]}}
  #|{"textrec":{"g":161,"r":[278,32,13,11,0,-10,0]}}
  #|{"textrec":{"g":162,"r":[292,32,10,15,0,-13,0]}}
  #|{"textrec":{"g":163,"r":[303,32,9,11,0,-9,0]}}
  #|{"textrec":{"g":164,"r":[313,32,11,14,-1,-12,0]}}
  #|{"textrec":{"g":165,"r":[325,32,8,13,-1,-12,0]}}
  #|{"textrec":{"g":156,"r":[334,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":157,"r":[352,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":158,"r":[369,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":159,"r":[387,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":166,"r":[405,32,12,16,1,-13,0]}}
  #|{"textrec":{"g":167,"r":[418,32,16,16,-1,-13,0]}}
  #|{"textrec":{"s":[17,400,0,"设置"],"r":[0,1,16.851167315175097,185,1,1,16.851167315175097,186]}}
  #|{"textrec":{"s":[32,700,8,"下方栏"],"r":[0,1,30.345864661654133,187,1,1,30.345864661654133,188,2,1,30.345864661654133,189]}}
  #|{"textrec":{"s":[13,400,0,"可以设置多栏，每栏最多 4 个位置，底部显示当前栏。有多栏时，在栏上向上滑动可切换。按住图标左右拖动可调整顺序。"],"r":[0,1,12.898832684824903,190,1,1,12.898832684824903,191,2,1,12.898832684824903,192,3,1,12.898832684824903,193,4,1,12.898832684824896,194,5,1,12.898832684824896,195,6,1,13.075875486381321,196,7,1,12.89883268482491,197,8,1,12.898832684824896,195,9,1,12.898832684824896,198,10,1,12.898832684824896,194,11,1,3.580078125,-1,12,1,8.2900390625,199,13,1,3.580078125,-1,14,1,12.898832684824896,200,15,1,12.898832684824896,201,16,1,12.898832684824896,193,17,1,13.075875486381335,196,18,1,12.898832684824896,202,19,1,12.898832684824896,203,20,1,12.898832684824896,204,21,1,12.898832684824896,205,22,1,12.898832684824924,206,23,1,12.898832684824924,207,24,1,12.898832684824924,195,25,1,13.075875486381335,208,26,1,12.898832684824924,149,27,1,12.898832684824924,194,28,1,12.898832684824924,195,29,1,12.898832684824924,153,30,1,13.075875486381335,196,31,1,12.898832684824924,1,32,1,12.898832684824924,195,33,1,12.898832684824924,209,34,1,12.898832684824924,210,35,1,12.898832684824924,209,36,1,12.898832684824924,211,37,1,12.898832684824924,212,38,1,12.898832684824924,190,39,1,12.898832684824924,213,40,1,12.898832684824924,214,41,1,13.075875486381278,208,42,1,12.898832684824924,215,43,1,12.898832684824924,216,44,1,12.898832684824924,217,45,1,12.898832684824924,218,46,1,12.898832684824924,219,47,1,12.898832684824924,220,48,1,12.898832684824924,221,49,1,12.898832684824924,212,50,1,12.898832684824924,190,51,1,12.898832684824924,222,52,1,12.898832684824924,223,53,1,12.898832684824924,224,54,1,12.898832684824924,225,55,1,6.575875486381278,208]}}
  #|{"textrec":{"s":[13,600,0,"第 1 栏"],"r":[0,1,12.898832684824903,226,1,1,3.3871192932128906,-1,2,1,6.348059177398682,227,3,1,3.3871192932128906,-1,4,1,12.898832684824903,228]}}
  #|{"textrec":{"m":[13,600,0],"r":[12.568359375,2.7421875,18]}}
  #|{"textrec":{"s":[11,600,0,"当前"],"r":[0,1,10.93579766536965,229,1,1,10.93579766536965,230]}}
  #|{"textrec":{"m":[11,600,0],"r":[10.634765625,2.3203125,16]}}
  #|{"textrec":{"s":[13,400,0,"删除"],"r":[0,1,12.898832684824903,231,1,1,12.898832684824903,232]}}
  #|{"textrec":{"s":[12,400,0,"对话"],"r":[0,1,11.918287937743191,233,1,1,11.918287937743191,234]}}
  #|{"textrec":{"m":[12,400,0],"r":[11.6015625,2.53125,17]}}
  #|{"textrec":{"s":[12,400,0,"文件"],"r":[0,1,11.918287937743191,235,1,1,11.918287937743191,236]}}
  #|{"textrec":{"s":[12,400,0,"Profile"],"r":[0,1,7.623046875,237,1,1,4.482421875,238,2,1,7.001953125,239,3,1,4.341796875,240,4,1,2.96484375,241,5,1,3.03515625,242,6,1,6.85546875,243]}}
  #|{"textrec":{"s":[12,400,0,"Station"],"r":[0,1,7.646484375,244,1,1,4.359375,245,2,1,6.62109375,246,3,1,4.359375,245,4,1,2.96484375,241,5,1,7.08984375,239,6,1,7.001953125,247]}}
  #|{"textrec":{"s":[13,600,0,"第 2 栏"],"r":[0,1,12.898832684824903,226,1,1,3.3871192932128906,-1,2,1,8.095149278640747,248,3,1,3.3871192932128906,-1,4,1,12.898832684824903,228]}}
  #|{"textrec":{"s":[13,400,0,"设为当前"],"r":[0,1,12.898832684824903,192,1,1,12.898832684824903,249,2,1,12.898832684824903,206,3,1,12.898832684824903,207]}}
  #|{"textrec":{"s":[12,400,0,"奏"],"r":[0,1,11.918287937743191,250]}}
  #|{"textrec":{"s":[12,400,0,"用量"],"r":[0,1,11.918287937743191,251,1,1,11.918287937743191,252]}}
  #|{"textrec":{"s":[12,400,0,"连接"],"r":[0,1,11.918287937743191,253,1,1,11.918287937743191,254]}}
  #|{"textrec":{"s":[12,400,0,"已归档"],"r":[0,1,11.918287937743191,255,1,1,11.918287937743191,256,2,1,11.918287937743195,257]}}
  #|{"textrec":{"s":[15,400,0,"新建栏"],"r":[0,1,14.883268482490273,159,1,1,14.883268482490273,258,2,1,14.883268482490273,130]}}
  #|{"textrec":{"s":[13,400,0,"删除到只剩一栏时，无法在栏上向上滑动"],"r":[0,1,12.898832684824903,231,1,1,12.898832684824903,232,2,1,12.898832684824903,259,3,1,12.898832684824903,260,4,1,12.898832684824896,261,5,1,12.898832684824896,262,6,1,12.898832684824896,195,7,1,12.898832684824896,153,8,1,13.075875486381321,196,9,1,12.89883268482491,263,10,1,12.898832684824896,264,11,1,12.898832684824896,1,12,1,12.898832684824896,195,13,1,12.898832684824896,209,14,1,12.898832684824896,210,15,1,12.898832684824896,209,16,1,12.898832684824896,211,17,1,12.898832684824896,212]}}
  #|{"textrec":{"g":185,"r":[435,32,19,18,-1,-15,0]}}
  #|{"textrec":{"g":186,"r":[455,32,18,17,-1,-14,0]}}
  #|{"textrec":{"g":187,"r":[474,32,30,30,0,-25,0]}}
  #|{"textrec":{"g":188,"r":[505,32,30,31,0,-26,0]}}
  #|{"textrec":{"g":189,"r":[536,32,31,31,-1,-26,0]}}
  #|{"textrec":{"g":190,"r":[568,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":191,"r":[583,32,14,15,0,-12,0]}}
  #|{"textrec":{"g":192,"r":[598,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":193,"r":[614,32,15,13,-1,-11,0]}}
  #|{"textrec":{"g":194,"r":[630,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":195,"r":[644,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":196,"r":[660,32,5,7,0,-3,0]}}
  #|{"textrec":{"g":197,"r":[666,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":198,"r":[682,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":199,"r":[697,32,10,12,-1,-11,0]}}
  #|{"textrec":{"g":200,"r":[708,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":201,"r":[724,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":202,"r":[740,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":203,"r":[756,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":204,"r":[771,32,14,13,-1,-11,0]}}
  #|{"textrec":{"g":205,"r":[786,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":206,"r":[801,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":207,"r":[815,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":208,"r":[831,32,6,6,0,-3,0]}}
  #|{"textrec":{"g":1,"r":[838,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":209,"r":[853,32,14,14,-1,-12,0]}}
  #|{"textrec":{"g":210,"r":[868,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":211,"r":[882,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":212,"r":[897,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":213,"r":[912,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":214,"r":[927,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":215,"r":[943,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":216,"r":[959,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":217,"r":[975,32,13,14,0,-11,0]}}
  #|{"textrec":{"g":218,"r":[989,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":219,"r":[1005,32,14,14,-1,-12,0]}}
  #|{"textrec":{"g":220,"r":[1020,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":221,"r":[1035,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":222,"r":[1051,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":223,"r":[1066,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":224,"r":[1082,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":225,"r":[1098,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":226,"r":[1113,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":227,"r":[1129,32,7,12,-1,-11,0]}}
  #|{"textrec":{"g":228,"r":[1137,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":248,"r":[1153,32,10,12,-1,-11,0]}}
  #|{"textrec":{"g":231,"r":[1164,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":232,"r":[1179,32,14,15,0,-12,0]}}
  #|{"textrec":{"g":259,"r":[1194,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":260,"r":[1209,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":261,"r":[1224,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":262,"r":[1239,32,15,4,-1,-7,0]}}
  #|{"textrec":{"g":263,"r":[1255,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":264,"r":[1270,32,15,15,-1,-12,0]}}
  #|{"textrec":{"ib":["3884ec9f83a49286",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"g":233,"r":[1286,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":234,"r":[1301,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":250,"r":[1316,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":258,"r":[1331,32,16,16,-1,-13,0]}}
  #|{"textrec":{"ib":["56bb520611ebcb9b",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["59d67194788e1d50",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"g":229,"r":[1348,32,11,13,0,-10,0]}}
  #|{"textrec":{"g":230,"r":[1360,32,13,13,-1,-10,0]}}
  #|{"textrec":{"ib":["83b02002cdf98bf6",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"g":235,"r":[1374,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":236,"r":[1389,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":251,"r":[1404,32,13,14,-1,-11,0]}}
  #|{"textrec":{"g":252,"r":[1418,32,14,13,-1,-11,0]}}
  #|{"textrec":{"ib":["118284b9121e03f9",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["0e1f660116efa475",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"g":237,"r":[1433,32,8,11,0,-10,0]}}
  #|{"textrec":{"g":238,"r":[1442,32,7,9,-1,-8,0]}}
  #|{"textrec":{"g":239,"r":[1450,32,9,10,-1,-8,0]}}
  #|{"textrec":{"g":240,"r":[1460,32,6,11,-1,-10,0]}}
  #|{"textrec":{"g":241,"r":[1467,32,5,11,-1,-10,0]}}
  #|{"textrec":{"g":242,"r":[1473,32,4,11,0,-10,0]}}
  #|{"textrec":{"g":243,"r":[1478,32,9,10,-1,-8,0]}}
  #|{"textrec":{"g":253,"r":[1488,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":254,"r":[1503,32,14,14,-1,-11,0]}}
  #|{"textrec":{"ib":["1ddbc5816774da4d",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["42d30f74945d8af0",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"g":249,"r":[1518,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":244,"r":[1533,32,9,12,-1,-10,0]}}
  #|{"textrec":{"g":245,"r":[1543,32,6,11,-1,-9,0]}}
  #|{"textrec":{"g":246,"r":[1550,32,8,10,-1,-8,0]}}
  #|{"textrec":{"g":247,"r":[1559,32,9,9,-1,-8,0]}}
  #|{"textrec":{"g":255,"r":[1569,32,13,12,0,-10,0]}}
  #|{"textrec":{"g":256,"r":[1583,32,13,14,-1,-11,0]}}
  #|{"textrec":{"g":257,"r":[1597,32,14,14,-1,-11,0]}}
  #|{"textrec":{"ib":["7b1e099b1a8c58bf",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["a9172ef01835e6be",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"s":[12,400,0,"添加"],"r":[0,1,11.918287937743191,265,1,1,11.918287937743191,266]}}
  #|{"textrec":{"g":265,"r":[1612,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":266,"r":[1627,32,13,14,-1,-11,0]}}
  #|{"textrec":{"ib":["d3afa98d6d4238aa",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"s":[13,400,0,"还可添加 1 个"],"r":[0,1,12.898832684824903,267,1,1,12.898832684824903,190,2,1,12.898832684824903,268,3,1,12.898832684824903,269,4,1,3.580078125,-1,5,1,5.9541015625,270,6,1,3.580078125,-1,7,1,12.898832684824896,200]}}
  #|{"textrec":{"s":[17,700,0,"添加到第 1 栏"],"r":[0,1,16.851167315175097,271,1,1,16.851167315175097,272,2,1,16.851167315175097,273,3,1,16.851167315175097,274,4,1,3.951171875,-1,5,1,8.267578125,275,6,1,3.951171875,-1,7,1,16.851167315175104,276]}}
  #|{"textrec":{"m":[17,700,0],"r":[16.435546875,3.5859375,24]}}
  #|{"textrec":{"s":[15,400,0,"对话"],"r":[0,1,14.883268482490273,277,1,1,14.883268482490273,278]}}
  #|{"textrec":{"s":[12,400,0,"已在此栏"],"r":[0,1,11.918287937743191,255,1,1,11.918287937743191,279,2,1,11.918287937743195,280,3,1,11.918287937743187,281]}}
  #|{"textrec":{"s":[15,400,0,"奏"],"r":[0,1,14.883268482490273,282]}}
  #|{"textrec":{"s":[15,400,0,"文件"],"r":[0,1,14.883268482490273,283,1,1,14.883268482490273,284]}}
  #|{"textrec":{"s":[15,400,0,"已归档"],"r":[0,1,14.883268482490273,285,1,1,14.883268482490273,286,2,1,14.883268482490273,287]}}
  #|{"textrec":{"g":271,"r":[1641,32,19,18,-1,-15,0]}}
  #|{"textrec":{"g":272,"r":[1661,32,18,18,-1,-15,0]}}
  #|{"textrec":{"g":273,"r":[1680,32,18,18,-1,-15,0]}}
  #|{"textrec":{"g":274,"r":[1699,32,18,18,-1,-15,0]}}
  #|{"textrec":{"g":275,"r":[1718,32,8,14,0,-13,0]}}
  #|{"textrec":{"g":276,"r":[1727,32,18,18,-1,-15,0]}}
  #|{"textrec":{"g":267,"r":[1746,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":268,"r":[1762,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":269,"r":[1778,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":270,"r":[1793,32,7,12,-1,-11,0]}}
  #|{"textrec":{"g":277,"r":[1801,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":278,"r":[1818,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":279,"r":[1836,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":280,"r":[1851,32,14,13,-1,-11,0]}}
  #|{"textrec":{"g":281,"r":[1866,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":282,"r":[1881,32,16,17,-1,-14,0]}}
  #|{"textrec":{"g":283,"r":[1898,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":284,"r":[1916,32,16,17,-1,-14,0]}}
  #|{"textrec":{"g":285,"r":[1933,32,15,16,0,-13,0]}}
  #|{"textrec":{"g":286,"r":[1949,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":287,"r":[1966,32,16,16,-1,-13,0]}}
  #|{"textrec":{"s":[13,400,0,"已满"],"r":[0,1,12.898832684824903,288,1,1,12.898832684824903,289]}}
  #|{"textrec":{"g":288,"r":[1983,32,13,13,0,-11,0]}}
  #|{"textrec":{"g":289,"r":[1997,32,15,15,-1,-12,0]}}
  #|{"textrec":{"s":[32,700,8,"本机缓存"],"r":[0,1,30.345864661654133,290,1,1,30.345864661654133,291,2,1,30.345864661654133,292,3,1,30.345864661654133,293]}}
  #|{"textrec":{"s":[13,400,0,"此设备上缓存的聊天记录和打开过的文件，再次查看时无需重新下载。删除仅影响此设备，station 上的数据不受影响。"],"r":[0,1,12.898832684824903,294,1,1,12.898832684824903,192,2,1,12.898832684824903,295,3,1,12.898832684824903,209,4,1,12.898832684824896,296,5,1,12.898832684824896,297,6,1,12.898832684824896,5,7,1,12.898832684824896,298,8,1,12.898832684824896,299,9,1,12.898832684824896,300,10,1,12.898832684824896,301,11,1,12.898832684824896,302,12,1,12.898832684824896,303,13,1,12.898832684824896,304,14,1,12.898832684824896,305,15,1,12.898832684824896,5,16,1,12.898832684824896,306,17,1,12.898832684824896,307,18,1,13.075875486381335,196,19,1,12.898832684824896,308,20,1,12.898832684824924,309,21,1,12.898832684824924,310,22,1,12.898832684824924,311,23,1,12.898832684824924,153,24,1,12.898832684824924,263,25,1,12.898832684824924,142,26,1,12.898832684824924,312,27,1,12.898832684824924,150,28,1,12.898832684824924,313,29,1,12.898832684824924,314,30,1,13.075875486381335,208,31,1,12.898832684824924,231,32,1,12.898832684824924,232,33,1,12.898832684824924,315,34,1,12.898832684824924,316,35,1,12.898832684824924,317,36,1,12.898832684824924,294,37,1,12.898832684824924,192,38,1,12.898832684824924,295,39,1,11.775875486381267,196,40,1,6.69677734375,10,41,1,4.61474609375,82,42,1,7.0966796875,12,43,1,4.646484375,82,44,1,3.1357421875,77,45,1,7.6044921875,7,46,1,7.50927734375,318,47,1,3.580078125,-1,48,1,12.898832684824924,209,49,1,12.898832684824924,5,50,1,12.898832684824924,319,51,1,12.898832684824924,320,52,1,12.898832684824924,321,53,1,12.898832684824924,322,54,1,12.898832684824924,316,55,1,12.898832684824924,317,56,1,6.575875486381278,208]}}
  #|{"textrec":{"s":[15,600,0,"按 chat"],"r":[0,1,14.883268482490273,323,1,1,3.761730194091797,-1,2,1,8.423570394515991,324,3,1,9.00644838809967,325,4,1,8.40147078037262,326,5,1,5.683325529098511,327]}}
  #|{"textrec":{"s":[13,400,0,"共 558 B"],"r":[0,1,12.898832684824903,328,1,1,3.580078125,-1,2,1,7.9599609375,329,3,1,7.9599609375,329,4,1,8.2265625,330,5,1,3.580078125,-1,6,1,8.4677734375,331]}}
  #|{"textrec":{"s":[14,400,0,"558 B"],"r":[0,1,8.50390625,332,1,1,8.50390625,332,2,1,8.791015625,333,3,1,3.787109375,-1,4,1,9.05078125,334]}}
  #|{"textrec":{"s":[15,400,0,"chat #1"],"r":[0,1,8.1591796875,94,1,1,8.59130859375,335,2,1,8.0419921875,93,3,1,5.21484375,101,4,1,3.984375,-1,5,1,9.2138671875,336,6,1,6.7236328125,165]}}
  #|{"textrec":{"s":[13,400,0,"消息 558 B"],"r":[0,1,12.898832684824903,151,1,1,12.898832684824903,152,2,1,3.580078125,-1,3,1,7.9599609375,329,4,1,7.9599609375,329,5,1,8.2265625,330,6,1,3.580078125,-1,7,1,8.4677734375,331]}}
  #|{"textrec":{"s":[15,400,0,"全部清除"],"r":[0,1,14.883268482490273,20,1,1,14.883268482490273,21,2,1,14.883268482490273,337,3,1,14.883268482490273,338]}}
  #|{"textrec":{"g":290,"r":[2013,32,32,31,-1,-26,0]}}
  #|{"textrec":{"g":291,"r":[0,64,32,31,-1,-26,0]}}
  #|{"textrec":{"g":292,"r":[33,64,32,31,-1,-26,0]}}
  #|{"textrec":{"g":293,"r":[66,64,31,31,-1,-26,0]}}
  #|{"textrec":{"g":294,"r":[98,64,15,14,-1,-12,0]}}
  #|{"textrec":{"g":295,"r":[114,64,15,15,-1,-12,0]}}
  #|{"textrec":{"g":296,"r":[130,64,15,15,-1,-12,0]}}
  #|{"textrec":{"g":297,"r":[146,64,15,15,-1,-12,0]}}
  #|{"textrec":{"g":5,"r":[162,64,13,15,0,-12,0]}}
  #|{"textrec":{"g":298,"r":[176,64,14,15,-1,-12,0]}}
  #|{"textrec":{"g":299,"r":[191,64,15,14,-1,-11,0]}}
  #|{"textrec":{"g":300,"r":[207,64,15,14,-1,-12,0]}}
  #|{"textrec":{"g":301,"r":[223,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":302,"r":[238,64,14,15,-1,-12,0]}}
  #|{"textrec":{"g":303,"r":[253,64,14,15,-1,-12,0]}}
  #|{"textrec":{"g":304,"r":[268,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":305,"r":[283,64,15,15,-1,-12,0]}}
  #|{"textrec":{"g":306,"r":[299,64,15,15,-1,-12,0]}}
  #|{"textrec":{"g":307,"r":[315,64,15,15,-1,-12,0]}}
  #|{"textrec":{"g":308,"r":[331,64,15,14,-1,-11,0]}}
  #|{"textrec":{"g":309,"r":[347,64,15,15,-1,-12,0]}}
  #|{"textrec":{"g":310,"r":[363,64,15,14,-1,-12,0]}}
  #|{"textrec":{"g":311,"r":[379,64,14,15,-1,-12,0]}}
  #|{"textrec":{"g":312,"r":[394,64,14,14,-1,-12,0]}}
  #|{"textrec":{"g":313,"r":[409,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":314,"r":[424,64,15,15,-1,-12,0]}}
  #|{"textrec":{"g":315,"r":[440,64,15,15,-1,-12,0]}}
  #|{"textrec":{"g":316,"r":[456,64,15,15,-1,-12,0]}}
  #|{"textrec":{"g":317,"r":[472,64,14,15,-1,-12,0]}}
  #|{"textrec":{"g":7,"r":[487,64,9,10,-1,-8,0]}}
  #|{"textrec":{"g":318,"r":[497,64,8,9,0,-8,0]}}
  #|{"textrec":{"g":319,"r":[506,64,15,15,-1,-12,0]}}
  #|{"textrec":{"g":320,"r":[522,64,15,15,-1,-12,0]}}
  #|{"textrec":{"g":321,"r":[538,64,15,14,-1,-11,0]}}
  #|{"textrec":{"g":322,"r":[554,64,14,15,-1,-12,0]}}
  #|{"textrec":{"g":323,"r":[569,64,17,17,-1,-14,0]}}
  #|{"textrec":{"g":324,"r":[587,64,11,12,-1,-10,0]}}
  #|{"textrec":{"g":325,"r":[599,64,10,14,0,-13,0]}}
  #|{"textrec":{"g":326,"r":[610,64,10,12,-1,-10,0]}}
  #|{"textrec":{"g":327,"r":[621,64,8,13,-1,-11,0]}}
  #|{"textrec":{"g":335,"r":[630,64,9,14,0,-13,0]}}
  #|{"textrec":{"g":336,"r":[640,64,12,13,-1,-12,0]}}
  #|{"textrec":{"g":329,"r":[653,64,10,13,-1,-11,0]}}
  #|{"textrec":{"g":330,"r":[664,64,10,13,-1,-11,0]}}
  #|{"textrec":{"g":331,"r":[675,64,9,12,0,-11,0]}}
  #|{"textrec":{"g":337,"r":[685,64,16,16,-1,-13,0]}}
  #|{"textrec":{"g":338,"r":[702,64,16,16,0,-13,0]}}
  #|{"textrec":{"g":332,"r":[719,64,9,13,0,-11,0]}}
  #|{"textrec":{"g":333,"r":[729,64,11,14,-1,-12,0]}}
  #|{"textrec":{"g":334,"r":[741,64,10,12,0,-11,0]}}
  #|{"textrec":{"g":328,"r":[752,64,14,15,-1,-12,0]}}
  #|{"textrec":{"s":[32,700,8,"更新日志"],"r":[0,1,30.345864661654133,339,1,1,30.345864661654133,340,2,1,30.345864661654133,341,3,1,30.345864661654133,342]}}
  #|{"textrec":{"s":[14,400,0,"桌面"],"r":[0,1,13.891050583657588,343,1,1,13.891050583657588,344]}}
  #|{"textrec":{"s":[14,400,0,"网页"],"r":[0,1,13.891050583657588,345,1,1,13.891050583657588,346]}}
  #|{"textrec":{"s":[14,400,0,"安卓"],"r":[0,1,13.891050583657588,347,1,1,13.891050583657588,348]}}
  #|{"textrec":{"s":[14,400,0,"Station"],"r":[0,1,8.7705078125,349,1,1,4.935546875,61,2,1,7.57421875,57,3,1,4.935546875,61,4,1,3.30859375,350,5,1,8.12109375,351,6,1,8.0185546875,60]}}
  #|{"textrec":{"s":[14,400,0,"云端"],"r":[0,1,13.891050583657588,352,1,1,13.891050583657588,353]}}
  #|{"textrec":{"s":[14,400,0,"暂无更新记录"],"r":[0,1,13.891050583657588,354,1,1,13.891050583657588,355,2,1,13.891050583657588,356,3,1,13.891050583657588,357,4,1,13.891050583657588,358,5,1,13.891050583657588,359]}}
  #|{"textrec":{"g":339,"r":[767,64,31,30,0,-25,0]}}
  #|{"textrec":{"g":340,"r":[799,64,31,32,-1,-27,0]}}
  #|{"textrec":{"g":341,"r":[831,64,23,30,4,-25,0]}}
  #|{"textrec":{"g":342,"r":[855,64,31,30,0,-26,0]}}
  #|{"textrec":{"g":354,"r":[887,64,14,16,0,-13,0]}}
  #|{"textrec":{"g":355,"r":[902,64,15,15,-1,-12,0]}}
  #|{"textrec":{"g":356,"r":[918,64,16,15,-1,-12,0]}}
  #|{"textrec":{"g":357,"r":[935,64,16,16,-1,-13,0]}}
  #|{"textrec":{"g":358,"r":[952,64,16,15,-1,-13,0]}}
  #|{"textrec":{"g":359,"r":[969,64,15,15,-1,-12,0]}}
  #|{"textrec":{"g":343,"r":[985,64,15,16,-1,-13,0]}}
  #|{"textrec":{"g":344,"r":[1001,64,15,15,-1,-12,0]}}
  #|{"textrec":{"g":345,"r":[1017,64,14,15,0,-12,0]}}
  #|{"textrec":{"g":346,"r":[1032,64,15,15,-1,-12,0]}}
  #|{"textrec":{"g":347,"r":[1048,64,15,16,-1,-13,0]}}
  #|{"textrec":{"g":348,"r":[1064,64,15,16,-1,-13,0]}}
  #|{"textrec":{"g":349,"r":[1080,64,11,14,-1,-12,0]}}
  #|{"textrec":{"g":350,"r":[1092,64,5,13,-1,-12,0]}}
  #|{"textrec":{"g":351,"r":[1098,64,10,11,-1,-9,0]}}
  #|{"textrec":{"g":352,"r":[1109,64,15,15,-1,-12,0]}}
  #|{"textrec":{"g":353,"r":[1125,64,15,16,-1,-13,0]}}
  #|{"textrec":{"s":[16,600,0,"用量"],"r":[0,1,15.875486381322958,43,1,1,15.875486381322958,360]}}
  #|{"textrec":{"s":[13,400,0,"7 天"],"r":[0,1,7.3251953125,361,1,1,3.580078125,-1,2,1,12.898832684824903,299]}}
  #|{"textrec":{"s":[13,400,0,"30 天"],"r":[0,1,8.07421875,362,1,1,8.1123046875,363,2,1,3.580078125,-1,3,1,12.898832684824903,299]}}
  #|{"textrec":{"s":[12,400,0,"折合费用"],"r":[0,1,11.918287937743191,364,1,1,11.918287937743191,365,2,1,11.918287937743195,366,3,1,11.918287937743187,251]}}
  #|{"textrec":{"s":[22,700,0,"$0"],"r":[0,1,14.22948682308197,367,1,1,14.468548357486725,368]}}
  #|{"textrec":{"m":[22,700,0],"r":[21.26953125,4.640625,31]}}
  #|{"textrec":{"s":[12,400,0,"查看价目表 →"],"r":[0,1,11.918287937743191,369,1,1,11.918287937743191,370,2,1,11.918287937743195,371,3,1,11.918287937743187,372,4,1,11.918287937743187,373,5,1,3.375,-1,6,1,10.869140625,374]}}
  #|{"textrec":{"s":[12,400,0,"模型调用"],"r":[0,1,11.918287937743191,375,1,1,11.918287937743191,376,2,1,11.918287937743195,377,3,1,11.918287937743187,251]}}
  #|{"textrec":{"s":[22,700,0,"0 次"],"r":[0,1,14.468548357486725,368,1,1,4.717369616031647,-1,2,1,20.94548872180451,378]}}
  #|{"textrec":{"s":[12,400,0,"日均 0 次"],"r":[0,1,11.918287937743191,379,1,1,11.918287937743191,380,2,1,3.375,-1,3,1,7.55859375,381,4,1,3.375,-1,5,1,11.918287937743195,382]}}
  #|{"textrec":{"s":[12,400,0,"输入 token"],"r":[0,1,11.918287937743191,383,1,1,11.918287937743191,384,2,1,3.375,-1,3,1,4.3154296875,245,4,1,7.0458984375,239,5,1,6.369140625,385,6,1,6.708984375,243,7,1,7.001953125,247]}}
  #|{"textrec":{"s":[22,700,0,"0"],"r":[0,1,14.468548357486725,368]}}
  #|{"textrec":{"s":[12,400,0,"缓存命中 0%"],"r":[0,1,11.918287937743191,386,1,1,11.918287937743191,387,2,1,11.918287937743195,388,3,1,11.918287937743187,389,4,1,3.375,-1,5,1,7.55859375,381,6,1,11.103515625,390]}}
  #|{"textrec":{"s":[12,400,0,"输出 token"],"r":[0,1,11.918287937743191,383,1,1,11.918287937743191,391,2,1,3.375,-1,3,1,4.3154296875,245,4,1,7.0458984375,239,5,1,6.369140625,385,6,1,6.708984375,243,7,1,7.001953125,247]}}
  #|{"textrec":{"s":[12,400,0,"平均每次 0"],"r":[0,1,11.918287937743191,392,1,1,11.918287937743191,380,2,1,11.918287937743195,393,3,1,11.918287937743187,382,4,1,3.375,-1,5,1,7.55859375,381]}}
  #|{"textrec":{"s":[12,400,0,"订阅账号不按 token 收费；费用按 API 标准单价估算，不含长上下文和服务等级等加价"],"r":[0,1,11.918287937743191,394,1,1,11.918287937743191,395,2,1,11.918287937743195,396,3,1,11.918287937743187,397,4,1,11.918287937743187,398,5,1,11.918287937743187,399,6,1,3.375,-1,7,1,4.3154296875,245,8,1,7.0458984375,239,9,1,6.369140625,385,10,1,6.708984375,243,11,1,7.001953125,247,12,1,3.375,-1,13,1,11.918287937743187,400,14,1,11.918287937743202,366,15,1,12.081712062256798,401,16,1,11.918287937743202,366,17,1,11.918287937743202,251,18,1,11.918287937743202,399,19,1,3.375,-1,20,1,8.0859375,402,21,1,7.623046875,237,22,1,3.2109375,403,23,1,3.375,-1,24,1,11.918287937743202,404,25,1,11.918287937743202,405,26,1,11.918287937743202,406,27,1,11.918287937743202,371,28,1,11.918287937743202,407,29,1,11.918287937743173,408,30,1,12.081712062256827,409,31,1,11.918287937743173,398,32,1,11.918287937743173,410,33,1,11.918287937743173,411,34,1,11.918287937743173,412,35,1,11.918287937743173,413,36,1,11.918287937743173,235,37,1,11.918287937743173,414,38,1,11.918287937743173,415,39,1,11.918287937743173,416,40,1,11.918287937743173,417,41,1,11.918287937743173,418,42,1,11.918287937743173,417,43,1,11.918287937743173,266,44,1,11.918287937743173,371]}}
  #|{"textrec":{"g":364,"r":[1141,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":365,"r":[1156,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":366,"r":[1171,64,13,14,-1,-11,0]}}
  #|{"textrec":{"g":367,"r":[1185,64,15,22,0,-19,0]}}
  #|{"textrec":{"g":368,"r":[1201,64,15,19,0,-17,0]}}
  #|{"textrec":{"g":369,"r":[1217,64,14,13,-1,-11,0]}}
  #|{"textrec":{"g":370,"r":[1232,64,13,14,-1,-11,0]}}
  #|{"textrec":{"g":371,"r":[1246,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":372,"r":[1261,64,11,13,0,-10,0]}}
  #|{"textrec":{"g":373,"r":[1273,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":374,"r":[1288,64,11,10,0,-9,0]}}
  #|{"textrec":{"g":383,"r":[1300,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":384,"r":[1315,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":385,"r":[1330,64,8,11,0,-10,0]}}
  #|{"textrec":{"g":386,"r":[1339,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":387,"r":[1354,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":388,"r":[1369,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":389,"r":[1384,64,12,14,0,-11,0]}}
  #|{"textrec":{"g":381,"r":[1397,64,9,12,-1,-10,0]}}
  #|{"textrec":{"g":390,"r":[1407,64,13,12,-1,-10,0]}}
  #|{"textrec":{"g":394,"r":[1421,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":395,"r":[1436,64,12,14,0,-11,0]}}
  #|{"textrec":{"g":396,"r":[1449,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":397,"r":[1464,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":398,"r":[1479,64,14,13,-1,-10,0]}}
  #|{"textrec":{"g":399,"r":[1494,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":400,"r":[1509,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":401,"r":[1524,64,4,11,1,-9,0]}}
  #|{"textrec":{"g":402,"r":[1529,64,10,11,-1,-10,0]}}
  #|{"textrec":{"g":403,"r":[1540,64,4,11,0,-10,0]}}
  #|{"textrec":{"g":404,"r":[1545,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":405,"r":[1560,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":406,"r":[1575,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":407,"r":[1590,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":408,"r":[1605,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":409,"r":[1620,64,5,6,0,-3,0]}}
  #|{"textrec":{"g":410,"r":[1626,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":411,"r":[1641,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":412,"r":[1656,64,14,13,-1,-11,0]}}
  #|{"textrec":{"g":413,"r":[1671,64,14,13,-1,-10,0]}}
  #|{"textrec":{"g":414,"r":[1686,64,13,14,-1,-11,0]}}
  #|{"textrec":{"g":415,"r":[1700,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":416,"r":[1715,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":417,"r":[1730,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":418,"r":[1745,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":360,"r":[1760,64,17,17,-1,-14,0]}}
  #|{"textrec":{"g":375,"r":[1778,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":376,"r":[1793,64,13,13,-1,-11,0]}}
  #|{"textrec":{"g":377,"r":[1807,64,13,14,-1,-11,0]}}
  #|{"textrec":{"g":378,"r":[1821,64,23,23,-1,-19,0]}}
  #|{"textrec":{"g":379,"r":[1845,64,10,14,1,-11,0]}}
  #|{"textrec":{"g":380,"r":[1856,64,13,14,-1,-11,0]}}
  #|{"textrec":{"g":382,"r":[1870,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":391,"r":[1885,64,12,14,0,-11,0]}}
  #|{"textrec":{"g":392,"r":[1898,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":393,"r":[1913,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":361,"r":[1928,64,9,12,-1,-11,0]}}
  #|{"textrec":{"s":[14,400,0,"这段时间没有用量"],"r":[0,1,13.891050583657588,419,1,1,13.891050583657588,420,2,1,13.891050583657588,421,3,1,13.891050583657588,422,4,1,13.891050583657588,423,5,1,13.891050583657588,424,6,1,13.891050583657588,55,7,1,13.891050583657588,425]}}
  #|{"textrec":{"s":[13,400,0,"agent 调用模型消耗的 token，按 API 价格折算为费用"],"r":[0,1,7.0966796875,12,1,1,7.845703125,426,2,1,7.3505859375,14,3,1,7.50927734375,318,4,1,4.646484375,82,5,1,3.580078125,-1,6,1,12.898832684824903,222,7,1,12.898832684824903,427,8,1,12.89883268482491,428,9,1,12.898832684824896,429,10,1,12.898832684824896,151,11,1,12.898832684824896,430,12,1,12.898832684824896,5,13,1,3.580078125,-1,14,1,4.598876953125,82,15,1,7.556884765625,7,16,1,6.82373046875,9,17,1,7.19189453125,14,18,1,7.50927734375,318,19,1,13.075875486381335,196,20,1,12.898832684824896,215,21,1,3.580078125,-1,22,1,8.68359375,431,23,1,8.18212890625,432,24,1,3.40234375,433,25,1,3.580078125,-1,26,1,12.898832684824896,434,27,1,12.898832684824896,435,28,1,12.898832684824896,436,29,1,12.898832684824924,437,30,1,12.898832684824924,249,31,1,12.898832684824924,438,32,1,12.898832684824924,427]}}
  #|{"textrec":{"g":362,"r":[1938,64,10,13,-1,-11,0]}}
  #|{"textrec":{"g":363,"r":[1949,64,10,13,-1,-11,0]}}
  #|{"textrec":{"g":419,"r":[1960,64,16,16,-1,-13,0]}}
  #|{"textrec":{"g":420,"r":[1977,64,16,16,-1,-13,0]}}
  #|{"textrec":{"g":421,"r":[1994,64,15,16,0,-13,0]}}
  #|{"textrec":{"g":422,"r":[2010,64,14,16,0,-13,0]}}
  #|{"textrec":{"g":423,"r":[2025,64,16,15,-1,-12,0]}}
  #|{"textrec":{"g":424,"r":[0,97,15,16,-1,-13,0]}}
  #|{"textrec":{"g":425,"r":[16,97,15,15,-1,-12,0]}}
  #|{"textrec":{"g":426,"r":[32,97,9,12,-1,-8,0]}}
  #|{"textrec":{"g":427,"r":[42,97,14,14,-1,-11,0]}}
  #|{"textrec":{"g":428,"r":[57,97,15,15,-1,-12,0]}}
  #|{"textrec":{"g":429,"r":[73,97,14,14,-1,-12,0]}}
  #|{"textrec":{"g":430,"r":[88,97,15,15,-1,-12,0]}}
  #|{"textrec":{"g":9,"r":[104,97,8,12,0,-11,0]}}
  #|{"textrec":{"g":431,"r":[113,97,11,12,-1,-11,0]}}
  #|{"textrec":{"g":432,"r":[125,97,9,12,0,-11,0]}}
  #|{"textrec":{"g":433,"r":[135,97,4,12,0,-11,0]}}
  #|{"textrec":{"g":434,"r":[140,97,15,15,-1,-12,0]}}
  #|{"textrec":{"g":435,"r":[156,97,15,15,-1,-12,0]}}
  #|{"textrec":{"g":436,"r":[172,97,14,15,-1,-12,0]}}
  #|{"textrec":{"g":437,"r":[187,97,14,15,-1,-12,0]}}
  #|{"textrec":{"g":438,"r":[202,97,14,15,-1,-12,0]}}
  #|{"textrec":{"s":[17,400,0,"用量"],"r":[0,1,16.851167315175097,439,1,1,16.851167315175097,440]}}
  #|{"textrec":{"s":[32,700,8,"价目表"],"r":[0,1,30.345864661654133,441,1,1,30.345864661654133,442,2,1,30.345864661654133,443]}}
  #|{"textrec":{"s":[13,400,0,"当前各台 station 用于折算费用的单价"],"r":[0,1,12.898832684824903,206,1,1,12.898832684824903,207,2,1,12.898832684824903,444,3,1,12.898832684824903,445,4,1,3.580078125,-1,5,1,6.69677734375,10,6,1,4.61474609375,82,7,1,7.0966796875,12,8,1,4.646484375,82,9,1,3.1357421875,77,10,1,7.6044921875,7,11,1,7.50927734375,318,12,1,3.580078125,-1,13,1,12.898832684824896,427,14,1,12.898832684824896,446,15,1,12.898832684824896,436,16,1,12.898832684824896,437,17,1,12.898832684824896,438,18,1,12.898832684824896,427,19,1,12.898832684824896,5,20,1,12.898832684824896,447,21,1,12.898832684824896,434]}}
  #|{"textrec":{"s":[16,600,0,"studio"],"r":[0,1,8.471200942993164,35,1,1,5.973020553588867,36,2,1,9.466253280639648,448,3,1,9.891647338867188,449,4,1,4.046333312988281,450,5,1,9.432537078857422,34]}}
  #|{"textrec":{"s":[12,400,0,"美元 / 100 万 token · 各类 token × 单价后相加；Claude fast ×2。GPT 按标准短上下文估算，仅记录输入、缓存读取和输出。GPT 价目核对于 2026-10-02，Claude 沿用 2026-09 价目"],"r":[0,1,11.918287937743191,451,1,1,11.918287937743191,452,2,1,3.375,-1,3,1,3.65625,453,4,1,3.375,-1,5,1,5.56640625,454,6,1,7.55859375,381,7,1,7.55859375,381,8,1,3.375,-1,9,1,11.918287937743195,455,10,1,3.375,-1,11,1,4.3154296875,245,12,1,7.0458984375,239,13,1,6.369140625,385,14,1,6.708984375,243,15,1,7.001953125,247,16,1,3.375,-1,17,1,5.754933455713626,456,18,1,3.375,-1,19,1,11.918287937743202,457,20,1,11.918287937743202,458,21,1,3.375,-1,22,1,4.3154296875,245,23,1,7.0458984375,239,24,1,6.369140625,385,25,1,6.708984375,243,26,1,7.001953125,247,27,1,3.375,-1,28,1,7.55859375,459,29,1,3.375,-1,30,1,11.918287937743202,406,31,1,11.918287937743202,371,32,1,11.918287937743202,460,33,1,11.918287937743202,461,34,1,11.918287937743202,266,35,1,12.081712062256798,401,36,1,8.58984375,462,37,1,3.03515625,242,38,1,6.62109375,246,39,1,7.001953125,463,40,1,7.37109375,464,41,1,6.85546875,243,42,1,3.375,-1,43,1,4.25390625,240,44,1,6.533203125,246,45,1,6.251953125,465,46,1,4.330078125,245,47,1,3.375,-1,48,1,7.55859375,459,49,1,7.2421875,466,50,1,12.081712062256827,467,51,1,8.958984375,468,52,1,7.623046875,237,53,1,7.60546875,469,54,1,3.375,-1,55,1,11.918287937743173,399,56,1,11.918287937743173,404,57,1,11.918287937743173,405,58,1,11.918287937743173,470,59,1,11.918287937743173,412,60,1,11.918287937743173,413,61,1,11.918287937743173,235,62,1,11.918287937743173,407,63,1,11.918287937743173,408,64,1,12.081712062256827,409,65,1,11.91828793774323,471,66,1,11.91828793774323,472,67,1,11.91828793774323,473,68,1,11.91828793774323,383,69,1,11.91828793774323,384,70,1,12.08171206225677,474,71,1,11.91828793774323,386,72,1,11.91828793774323,387,73,1,11.91828793774323,475,74,1,11.91828793774323,476,75,1,11.91828793774323,414,76,1,11.91828793774323,383,77,1,11.91828793774323,391,78,1,12.08171206225677,467,79,1,8.958984375,468,80,1,7.623046875,237,81,1,7.60546875,469,82,1,3.375,-1,83,1,11.91828793774323,371,84,1,11.91828793774323,372,85,1,11.91828793774323,477,86,1,11.91828793774323,233,87,1,11.91828793774323,478,88,1,3.375,-1,89,1,7.2421875,466,90,1,7.55859375,381,91,1,7.2421875,466,92,1,7.640625,479,93,1,5.66015625,480,94,1,5.56640625,454,95,1,7.55859375,381,96,1,5.66015625,480,97,1,7.55859375,381,98,1,7.2421875,466,99,1,10.881712062256838,409,100,1,8.58984375,462,101,1,3.03515625,242,102,1,6.62109375,246,103,1,7.001953125,463,104,1,7.37109375,464,105,1,6.85546875,243,106,1,3.375,-1,107,1,11.91828793774323,481,108,1,11.91828793774323,251,109,1,3.375,-1,110,1,7.2421875,466,111,1,7.55859375,381,112,1,7.2421875,466,113,1,7.640625,479,114,1,5.66015625,480,115,1,7.55859375,381,116,1,7.640625,482,117,1,3.375,-1,118,1,11.91828793774323,371,119,1,11.91828793774323,372]}}
  #|{"textrec":{"s":[12,400,0,"这段时间没有模型用量"],"r":[0,1,11.918287937743191,483,1,1,11.918287937743191,484,2,1,11.918287937743195,485,3,1,11.918287937743187,486,4,1,11.918287937743187,487,5,1,11.918287937743187,488,6,1,11.918287937743187,375,7,1,11.918287937743187,376,8,1,11.918287937743187,251,9,1,11.918287937743187,252]}}
  #|{"textrec":{"g":439,"r":[217,97,17,17,-1,-14,0]}}
  #|{"textrec":{"g":440,"r":[235,97,18,18,-1,-15,0]}}
  #|{"textrec":{"g":441,"r":[254,97,32,31,-1,-26,0]}}
  #|{"textrec":{"g":442,"r":[287,97,24,30,3,-25,0]}}
  #|{"textrec":{"g":443,"r":[312,97,31,31,-1,-26,0]}}
  #|{"textrec":{"g":444,"r":[344,97,15,15,-1,-12,0]}}
  #|{"textrec":{"g":445,"r":[360,97,13,15,0,-12,0]}}
  #|{"textrec":{"g":446,"r":[374,97,14,14,-1,-11,0]}}
  #|{"textrec":{"g":447,"r":[389,97,14,15,-1,-12,0]}}
  #|{"textrec":{"g":448,"r":[404,97,10,12,0,-10,0]}}
  #|{"textrec":{"g":449,"r":[415,97,11,15,-1,-13,0]}}
  #|{"textrec":{"g":450,"r":[427,97,5,15,0,-14,0]}}
  #|{"textrec":{"g":451,"r":[433,97,14,14,-1,-11,0]}}
  #|{"textrec":{"g":452,"r":[448,97,13,13,-1,-10,0]}}
  #|{"textrec":{"g":453,"r":[462,97,6,14,-1,-10,0]}}
  #|{"textrec":{"g":454,"r":[469,97,7,11,-1,-10,0]}}
  #|{"textrec":{"g":455,"r":[477,97,13,13,-1,-10,0]}}
  #|{"textrec":{"g":456,"r":[491,97,5,5,0,-7,0]}}
  #|{"textrec":{"g":457,"r":[497,97,14,14,-1,-11,0]}}
  #|{"textrec":{"g":458,"r":[512,97,14,14,-1,-11,0]}}
  #|{"textrec":{"g":459,"r":[527,97,8,9,0,-8,0]}}
  #|{"textrec":{"g":460,"r":[536,97,14,14,-1,-11,0]}}
  #|{"textrec":{"g":461,"r":[551,97,13,14,-1,-11,0]}}
  #|{"textrec":{"g":462,"r":[565,97,10,12,-1,-10,0]}}
  #|{"textrec":{"g":463,"r":[576,97,9,10,-1,-8,0]}}
  #|{"textrec":{"g":464,"r":[586,97,9,12,-1,-10,0]}}
  #|{"textrec":{"g":465,"r":[596,97,8,10,-1,-8,0]}}
  #|{"textrec":{"g":466,"r":[605,97,9,11,-1,-10,0]}}
  #|{"textrec":{"g":467,"r":[615,97,6,6,0,-3,0]}}
  #|{"textrec":{"g":468,"r":[622,97,11,12,-1,-10,0]}}
  #|{"textrec":{"g":469,"r":[634,97,10,11,-1,-10,0]}}
  #|{"textrec":{"g":470,"r":[645,97,14,13,-1,-11,0]}}
  #|{"textrec":{"g":471,"r":[660,97,14,14,-1,-11,0]}}
  #|{"textrec":{"g":472,"r":[675,97,14,13,-1,-11,0]}}
  #|{"textrec":{"g":473,"r":[690,97,13,14,-1,-11,0]}}
  #|{"textrec":{"g":474,"r":[704,97,6,6,0,-3,0]}}
  #|{"textrec":{"g":475,"r":[711,97,14,14,-1,-11,0]}}
  #|{"textrec":{"g":476,"r":[726,97,14,14,-1,-11,0]}}
  #|{"textrec":{"g":477,"r":[741,97,14,14,-1,-11,0]}}
  #|{"textrec":{"g":478,"r":[756,97,13,14,-1,-11,0]}}
  #|{"textrec":{"g":479,"r":[770,97,9,12,-1,-10,0]}}
  #|{"textrec":{"g":480,"r":[780,97,7,4,-1,-5,0]}}
  #|{"textrec":{"g":481,"r":[788,97,14,14,-1,-11,0]}}
  #|{"textrec":{"g":482,"r":[803,97,9,12,-1,-10,0]}}
  #|{"textrec":{"g":483,"r":[813,97,14,14,-1,-11,0]}}
  #|{"textrec":{"g":484,"r":[828,97,14,14,-1,-11,0]}}
  #|{"textrec":{"g":485,"r":[843,97,14,14,-1,-11,0]}}
  #|{"textrec":{"g":486,"r":[858,97,12,14,0,-11,0]}}
  #|{"textrec":{"g":487,"r":[871,97,14,14,-1,-11,0]}}
  #|{"textrec":{"g":488,"r":[886,97,14,14,-1,-11,0]}}
