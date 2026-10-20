// e2e/traces/settings-connect.trace, made by scripts/trace.py from 01-settings_connect.log: not edited by hand.

///|
/// What the app and its core said in the run, a line each.
pub let trace_settings_connect : String =
  #|{"start":"base"}
  #|{"step":"drive-seed 080726"}
  #|{"step":"peer connect-put e2e-080726"}
  #|{"env":{"MBUI_CLOUD":"http://127.0.0.1:18900","MBUI_CORE_ACCOUNT":"{\"sub\":\"alice\",\"email\":\"alice@example.test\",\"name\":\"Name of alice\",\"picture\":\"\",\"access\":\"-\",\"refresh\":\"-\",\"accessExpires\":1792534388}"}}
  #|{"out":{"id":1,"call":"client.device","params":{"client":"still.fail mbui","app":"desktop","userAgent":"Macintosh; Mac OS X"}},"w":1792534103833.408}
  #|{"in":{"id":1,"ok":null},"w":1792534103927.089}
  #|{"out":{"id":2,"subscribe":{"topic":"accounts"},"keyed":true},"w":1792534103927.122}
  #|{"out":{"id":3,"subscribe":{"topic":"prefs"},"keyed":true},"w":1792534103927.133}
  #|{"step":"# written by scripts/rerecord.sh from its test (src/sfreplay/emit.mbt): not edited by hand","w":1792534103928.809}
  #|{"step":"timeout 90000","w":1792534103928.819}
  #|{"step":"answered client.device","w":1792534103928.821}
  #|{"step":"answered client.focus","w":1792534103944.588}
  #|{"in":{"id":2,"value":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""}]},"w":1792534104027.05}
  #|{"in":{"id":3,"value":{"onlyMine":false,"onlyWatching":false,"onlyDecisions":false,"listFilter":{},"appearance":"system","rowPicture":"auto","absoluteTime":false,"lang":"zh","keys":{},"lastChat":{},"openChat":{},"chatTabs":{},"dropFiles":{},"driveViews":{},"resume":{},"stationUpdatesDismissed":{},"device":{"app":"desktop","phone":false,"handoff":false},"reader":{"size":18,"line":1.7,"margin":22,"face":"sans","indent":true,"paper":"follow"},"rails":{},"bars":{"sets":[["chats","files","profiles","stations"],["decisions","usage","connects","archive"]],"current":0},"barsBy":{}}},"w":1792534104027.074}
  #|{"out":{"id":4,"subscribe":{"topic":"workspaces"},"keyed":true},"w":1792534104027.109}
  #|{"out":{"id":5,"subscribe":{"topic":"status"},"keyed":true},"w":1792534104027.124}
  #|{"in":{"id":4,"value":[{"account":{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""},"workspaces":[{"id":"01M5DNPYJQDZZ8G5SCF3BD72M7","name":"Dev","role":"owner","created_at":1792534084,"stations":1,"members":1,"relays":[],"time":{"created_at":{"past":true,"at":1792534084000,"ago":"刚刚","full":"10/21 06:08:04","until":"1 分钟内"}}}],"invitations":[],"relay_url":"http://127.0.0.1:18940","loaded":true,"beta":true}]},"w":1792534104044.719}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792534104044.739}
  #|{"out":{"id":6,"subscribe":{"topic":"lock","workspace":"01M5DNPYJQDZZ8G5SCF3BD72M7"},"keyed":true},"w":1792534104044.781}
  #|{"out":{"id":7,"subscribe":{"topic":"chats","scope":"01M5DNPYJQDZZ8G5SCF3BD72M7","mine":false},"keyed":true},"w":1792534104044.798}
  #|{"out":{"id":8,"subscribe":{"topic":"workspaceMarks","workspace":"01M5DNPYJQDZZ8G5SCF3BD72M7"},"keyed":true},"w":1792534104044.922}
  #|{"out":{"id":9,"subscribe":{"topic":"status","workspace":"01M5DNPYJQDZZ8G5SCF3BD72M7"},"keyed":true},"w":1792534104044.954}
  #|{"out":{"id":10,"call":"client.focus","params":{"visible":true,"focused":true,"workspace":"01M5DNPYJQDZZ8G5SCF3BD72M7"}},"w":1792534104050.635}
  #|{"out":{"id":11,"subscribe":{"topic":"notify"},"keyed":true},"w":1792534104050.647}
  #|{"out":{"id":12,"subscribe":{"topic":"notify","workspace":"01M5DNPYJQDZZ8G5SCF3BD72M7"},"keyed":true},"w":1792534104050.653}
  #|{"in":{"id":6,"value":{"available":true,"locked":false,"notice":true,"role":"owner","manages":true,"owner":true,"canSign":true,"signs":false,"me":{"device":"02feb9d77444e2db96dbb0a69ecefc2e326ce6b8759d84c92cdd3ec12b6e6566","code":"U9T-HZ9","kind":"app","confirmed":false,"waiting":false,"asked":false},"signers":0,"members":[],"stations":[{"id":"e17595128f3a25c314142585a6162d3f6c2c9b9d456c8af0c76325044a94c7fc","name":"studio","version":"0.1.0","online":true,"protected":false}],"protected":0,"requests":[],"renew":[],"attention":0}},"w":1792534104060.373}
  #|{"in":{"id":7,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"stations":[{"station":"01M5DNPYJQDZZ8G5SCF3BD72M7/e17595128f3a25c314142585a6162d3f6c2c9b9d456c8af0c76325044a94c7fc","id":"e17595128f3a25c314142585a6162d3f6c2c9b9d456c8af0c76325044a94c7fc","name":"studio","state":"online"}],"loading":false,"days":[{"daysAgo":0,"at":1792534088443,"label":"今天","items":[{"id":"ember:c-0dce3e4342","session":"ember:c-0dce3e4342","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","agents":[{"key":"ember:c-0dce3e4342","runtime":"claude","process":"cold","pending":0,"lastTurn":{"id":"dfa49bb4-4958-413c-8dd7-06a54803fbe8","kind":"input","outcome":"completed","declared":"final","ending":"all_done","need":"answered the question that was asked","startedAt":1792534088375,"endedAt":1792534088445},"agentText":"默认模型","statusText":"已完成：answered the question that was asked"}],"last":{"seq":2,"authorKind":"agent","author":"ember:c-0dce3e4342","text":"你好，我是测试用的 agent","createdAt":1792534088443,"by":{"kind":"agent","name":"agent","mine":false,"runtime":"claude","label":"agent"},"preview":"你好，我是测试用的 agent","time":{"createdAt":{"at":1792534088443,"ago":"刚刚","full":"10/21 06:08:08","until":"1 分钟内","past":true}}},"unread":true,"mine":true,"lastActiveAt":1792534088443,"station":"01M5DNPYJQDZZ8G5SCF3BD72M7/e17595128f3a25c314142585a6162d3f6c2c9b9d456c8af0c76325044a94c7fc","stationName":"studio","time":{"lastActiveAt":{"at":1792534088443,"ago":"刚刚","full":"10/21 06:08:08","until":"1 分钟内","past":true}},"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"peopleText":"你 发起","pinned":false,"tone":"done"}]}],"trouble":null,"members":1,"leading":"agents","glyph":{"online":1,"dim":0,"connecting":0,"failing":0,"working":0,"summary":"studio","label":"1 台 station，1 台在线"},"note":{"reading":false,"text":null,"failing":[],"empty":false}}},"w":1792534104060.402}
  #|{"in":{"id":8,"value":{"workspaces":{"01M5DNPYJQDZZ8G5SCF3BD72M7":{"alert":0,"unread":1,"tone":"done","label":"1 个有新消息","badge":0,"items":[],"mineTone":"done"}},"badge":0,"badgeCounts":"attention","badgeKinds":{"on":true,"wait":true,"failed":true,"done":false,"message":false}}},"w":1792534104060.427}
  #|{"in":{"id":9,"value":{"items":[]}},"w":1792534104060.433}
  #|{"in":{"id":10,"ok":null},"w":1792534104060.436}
  #|{"in":{"id":11,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792534104060.442}
  #|{"in":{"id":12,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792534104060.447}
  #|{"out":{"id":13,"subscribe":{"topic":"longJobs","scope":"01M5DNPYJQDZZ8G5SCF3BD72M7"},"keyed":true},"w":1792534104060.479}
  #|{"out":{"id":14,"call":"notify.permission","params":{"state":"unknown"}},"w":1792534104063.604}
  #|{"in":{"id":13,"value":{"groups":[]}},"w":1792534104077.042}
  #|{"in":{"id":14,"ok":null},"w":1792534104077.119}
  #|{"step":"answered notify.permission","w":1792534104077.675}
  #|{"step":"#before peer connect-put e2e-080726","w":1792534104094.044}
  #|{"step":"tap icon:settings","w":1792534104094.046}
  #|{"step":"tap icon:settings","acted":true,"w":1792534104110.693}
  #|{"out":{"id":15,"subscribe":{"topic":"workspace","workspace":"01M5DNPYJQDZZ8G5SCF3BD72M7"},"keyed":true},"w":1792534104127.153}
  #|{"out":{"id":16,"subscribe":{"topic":"stations","scope":"01M5DNPYJQDZZ8G5SCF3BD72M7"},"keyed":true},"w":1792534104127.17}
  #|{"out":{"id":17,"subscribe":{"topic":"connects","scope":"01M5DNPYJQDZZ8G5SCF3BD72M7","mine":false},"keyed":true},"w":1792534104127.176}
  #|{"out":{"id":18,"subscribe":{"topic":"vaults","workspace":"01M5DNPYJQDZZ8G5SCF3BD72M7"},"keyed":true},"w":1792534104127.182}
  #|{"out":{"id":19,"subscribe":{"topic":"doing"},"keyed":true},"w":1792534104131.447}
  #|{"step":"rest","w":1792534104132.352}
  #|{"in":{"id":15,"value":{"id":"01M5DNPYJQDZZ8G5SCF3BD72M7","name":"Dev","role":"owner","created_at":1792534084,"members":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":"https://example.test/p.png","role":"owner","added_at":1792534084}],"stations":[{"id":"e17595128f3a25c314142585a6162d3f6c2c9b9d456c8af0c76325044a94c7fc","name":"studio","emoji":null,"icon":null,"enrolled_at":1792534084,"enrolled_by":"alice","last_seen":1792534103,"version":"0.1.0","time":{"last_seen":{"past":true,"at":1792534103000,"ago":"刚刚","full":"10/21 06:08:23","until":"1 分钟内"}}}],"invitations":[],"added":[],"relays":[],"lock":null,"lock_requests":0,"time":{"created_at":{"past":true,"at":1792534084000,"ago":"刚刚","full":"10/21 06:08:04","until":"1 分钟内"}}}},"w":1792534104143.719}
  #|{"in":{"id":16,"value":[{"station":"01M5DNPYJQDZZ8G5SCF3BD72M7/e17595128f3a25c314142585a6162d3f6c2c9b9d456c8af0c76325044a94c7fc","id":"e17595128f3a25c314142585a6162d3f6c2c9b9d456c8af0c76325044a94c7fc","name":"studio","summary":"正在连接","face":"idle","line":"在线","online":true,"reconnecting":false,"lastSeen":1792534103,"version":"0.1.0","link":{"state":"online"},"runtimes":[{"runtime":"claude","models":["claude-sonnet-5-5"]}],"models":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792534088354,"time":{"checkedAt":{"at":1792534088354,"ago":"刚刚","full":"10/21 06:08:08","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"overview":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null,"summaryText":"最近 7 天检查了 0 个 chat","changeText":null}},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","email":"alice@example.test","name":"Name of alice","sub":"alice","role":"owner","workspace":"01M5DNPYJQDZZ8G5SCF3BD72M7","device":"02feb9d77444e2db96dbb0a69ecefc2e326ce6b8759d84c92cdd3ec12b6e6566"},"connects":[{"id":"e2e-080726","name":"e2e-080726","enabled":true,"kind":"slack","mode":"multi-session","requireMention":true,"bind":{"runtime":"claude","model":"claude-sonnet-5-5"},"slack":{"appToken":"","botToken":""},"connection":{"state":"no_tokens"},"createdBy":{"id":"alice@example.test","name":"Name of alice"},"sessions":0,"statusText":"未连接 Slack","presence":"offline","modeText":"多会话","modeShort":"多会话","runtimeText":"Claude Code","runText":"Claude Code · Sonnet 5.5","modelName":"Sonnet 5.5"}],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":["e2e-080726"],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792534103657,"time":{"checkedAt":{"at":1792534103657,"ago":"刚刚","full":"10/21 06:08:23","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792534088354,"time":{"checkedAt":{"at":1792534088354,"ago":"刚刚","full":"10/21 06:08:08","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]}],"processes":[],"counts":{"sessions":1,"running":0,"warm":0},"mesh":{"state":"running","origin":"http://127.0.0.1:18900","station":"e17595128f3a25c314142585a6162d3f6c2c9b9d456c8af0c76325044a94c7fc","workspace":"Dev","workspaceId":"01M5DNPYJQDZZ8G5SCF3BD72M7","name":"studio"},"slackUsers":[],"slackTeams":[],"slackApps":[],"feishuRegistrations":[],"disk":{"freeBytes":57264824320,"totalBytes":245107195904},"logins":[],"machineLogins":[],"sharing":true,"consoleSignIn":true,"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"google","name":"Google Gemini","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xai","name":"xAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"mistral","name":"Mistral","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"deepseek","name":"DeepSeek","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen","name":"Qwen","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai","name":"Kimi","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai","name":"Z.ai","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax","name":"MiniMax","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ant-ling","name":"Ant Ling","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"jev","name":"Jev","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen-cn","name":"Qwen (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"openrouter","name":"OpenRouter","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"opencode","name":"OpenCode Zen","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"groq","name":"Groq","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"together","name":"Together AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"fireworks","name":"Fireworks","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cerebras","name":"Cerebras","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"huggingface","name":"Hugging Face","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"nvidia","name":"NVIDIA","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"baseten","name":"Baseten","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ollama","name":"Ollama","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"custom","name":"Custom","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""}],"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792534101236},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.305","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792534101236},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792534101236},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792534101236},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","latest":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792534101236}],"processesText":"没有运行中的 agent 进程","agentEnv":[],"drive":{"roots":[],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false}},"betaOffered":false,"way":{"path":"直连","via":"direct"},"time":{"lastSeen":{"at":1792534103000,"ago":"刚刚","full":"10/21 06:08:23","until":"1 分钟内","past":true}},"joined":false}]},"w":1792534104143.842}
  #|{"in":{"id":17,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"items":[{"station":"01M5DNPYJQDZZ8G5SCF3BD72M7/e17595128f3a25c314142585a6162d3f6c2c9b9d456c8af0c76325044a94c7fc","stationName":"studio","connect":{"id":"e2e-080726","name":"e2e-080726","enabled":true,"kind":"slack","mode":"multi-session","requireMention":true,"bind":{"runtime":"claude","model":"claude-sonnet-5-5"},"slack":{"appToken":"","botToken":""},"connection":{"state":"no_tokens"},"createdBy":{"id":"alice@example.test","name":"Name of alice","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"sessions":0,"statusText":"未连接 Slack","presence":"offline","modeText":"多会话","modeShort":"多会话","runtimeText":"Claude Code","runText":"Claude Code · Sonnet 5.5","modelName":"Sonnet 5.5"},"sessions":[],"candidates":[{"key":"ember:c-0dce3e4342","connect":"ember","scope":"all","createdBy":"alice@example.test","boundTo":[],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"},"participants":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"}],"runtime":"claude","profile":"cc","profilePinned":false,"runtimeSessionId":"558b6c00-ca02-4274-a3fa-146a325ca2fc","workspace":"/tmp/mbe2e-C/data/sessions/ember/c-0dce3e4342/workspace","running":false,"createdAt":1792534088309,"lastActiveAt":1792534088445,"process":"cold","turns":1,"pending":0,"firstText":"端到端测试的对话 post:你好，我是测试用的 agent","lastTurn":{"id":"dfa49bb4-4958-413c-8dd7-06a54803fbe8","kind":"input","outcome":"completed","declared":"final","ending":"all_done","need":"answered the question that was asked","startedAt":1792534088375,"endedAt":1792534088445},"statusText":"已完成：answered the question that was asked","tone":"green","titleText":"端到端测试的对话 post:你好，我是测试用的 agent","agentText":"默认模型","runtimeText":"Claude Code","processText":"已释放","efforts":["low","medium","high","xhigh","max"],"time":{"createdAt":{"at":1792534088309,"ago":"刚刚","full":"10/21 06:08:08","until":"1 分钟内","past":true},"lastActiveAt":{"at":1792534088445,"ago":"刚刚","full":"10/21 06:08:08","until":"1 分钟内","past":true}},"chat":1,"description":"单会话 · ember · 1 轮 · 刚刚","current":false}],"running":0}],"wait":{"reading":false,"text":null,"failing":[],"empty":false}}},"w":1792534104143.935}
  #|{"in":{"id":18,"value":{"available":true,"locked":false,"canSign":false,"setUp":false,"vaults":[{"id":"plain","name":"个人","owner":"alice","ownerName":"Name of alice","mine":true,"members":[{"sub":"alice","name":"Name of alice"}],"station":"e17595128f3a25c314142585a6162d3f6c2c9b9d456c8af0c76325044a94c7fc","stationName":"studio","items":0,"devices":0,"open":true,"keyed":true,"missing":0,"recoverable":false}],"requests":[],"refused":[{"station":"e17595128f3a25c314142585a6162d3f6c2c9b9d456c8af0c76325044a94c7fc","name":"studio","code":"vault_needs_lock"}],"plain":true}},"w":1792534104143.957}
  #|{"in":{"id":19,"value":{"doing":[]}},"w":1792534104143.964}
  #|{"in":{"id":16,"delta":[{"path":[0,"host"],"set":{"hostname":"3720-Mac-mini-1","os":"macOS 27.0.1","arch":"arm64","cpus":10,"cpuModel":"Apple M4","load":0.52,"cpuBusy":0.17,"uptimeSec":13466,"memory":{"totalBytes":17179869184,"usedBytes":10091003904,"swapUsedBytes":325184389},"disk":{"path":"/tmp/mbe2e-C/data","totalBytes":245107195904,"freeBytes":57263570944},"emberRssBytes":140228264,"checkedAt":1792534104173,"summary":"10 核 · 16 GB","line":"macOS 27.0.1 · 10 核 · 16 GB · 已运行 0 天","facts":["3720-Mac-mini-1","macOS 27.0.1","arm64 · 10 核","已运行 3 小时"],"meters":[{"label":"CPU","short":"CPU","percent":17,"left":83,"level":"ok","value":"17%","remaining":"空闲 83%","big":"83","unit":"%","title":"CPU 空闲","total":"负载 5.2","note":"负载 5.2 · Apple M4"},{"label":"内存","short":"内存","percent":59,"left":41,"level":"ok","value":"9.4 GB / 16.0 GB","remaining":"剩 6.6 G","big":"6.6","unit":"GB","title":"内存剩","total":"共 16 GB","note":"swap 0.3 GB"},{"label":"磁盘","short":"磁盘","percent":77,"left":23,"level":"amber","value":"剩余 53.3 GB / 228 GB","remaining":"剩 53.3 G","big":"53.3","unit":"GB","title":"磁盘剩","total":"共 228 GB"}],"identity":"Apple M4 · 16 GB · macOS 27.0.1","details":[{"label":"主机名","value":"3720-Mac-mini-1"},{"label":"芯片","value":"Apple M4 · 10 核 · arm64"},{"label":"已运行","value":"3 小时"},{"label":"still.fail","value":"进程占用 134 MB"}],"usage":"内存 9.4 GB / 16.0 GB · 磁盘 剩余 53.3 GB / 228 GB","emberText":"still.fail 134 MB"}},{"path":[0,"line"],"set":"Apple M4"},{"path":[0,"summary"],"set":"空闲 · Apple M4 · 16 GB · macOS 27.0.1"}]},"w":1792534104210.421}
  #|{"step":"now tap =连接","w":1792534104894.322}
  #|{"step":"now tap =连接","acted":true,"w":1792534104911.048}
  #|{"step":"rest","w":1792534104933.052}
  #|{"step":"now tap =e2e-080726","w":1792534105260.721}
  #|{"step":"now tap =e2e-080726","acted":true,"w":1792534105277.288}
  #|{"step":"rest","w":1792534105296.999}
  #|{"step":"now until 此连接尚未接入 Slack","w":1792534105610.669}
  #|{"step":"tap icon:more","w":1792534105610.681}
  #|{"step":"tap icon:more","acted":true,"w":1792534105627.546}
  #|{"step":"rest","w":1792534105645.483}
  #|{"step":"now tap =停用","w":1792534107110.553}
  #|{"step":"now tap =停用","acted":true,"w":1792534107127.211}
  #|{"out":{"id":20,"call":"connect.put","params":{"station":"01M5DNPYJQDZZ8G5SCF3BD72M7/e17595128f3a25c314142585a6162d3f6c2c9b9d456c8af0c76325044a94c7fc","id":"e2e-080726","input":{"enabled":false}}},"w":1792534107143.737}
  #|{"step":"answered connect.put","w":1792534107143.869}
  #|{"in":{"id":20,"ok":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null},"canEditPolicy":true},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","sub":"alice","email":"alice@example.test","name":"Name of alice","role":"owner","workspace":"01M5DNPYJQDZZ8G5SCF3BD72M7","device":"02feb9d77444e2db96dbb0a69ecefc2e326ce6b8759d84c92cdd3ec12b6e6566","lockDevice":{"base":"02feb9d77444e2db96dbb0a69ecefc2e326ce6b8759d84c92cdd3ec12b6e6566","proof":"33a6bc536bc59977f015aac2a1de161ac3d2dfcf66dd4f26303849d4a4dc6bb36c6ea0bb688ff8505c2eb75fddd8d8cb38d6f008e6c3100b103cace3ab903a0a"},"home":true},"mesh":{"state":"running","origin":"http://127.0.0.1:18900","station":"e17595128f3a25c314142585a6162d3f6c2c9b9d456c8af0c76325044a94c7fc","workspace":"Dev","workspaceId":"01M5DNPYJQDZZ8G5SCF3BD72M7","name":"studio"},"connects":[{"id":"e2e-080726","name":"e2e-080726","team":null,"botImage":null,"enabled":false,"kind":"slack","mode":"multi-session","requireMention":true,"bind":{"runtime":"claude","model":"claude-sonnet-5-5","effort":null,"profile":null},"slack":{"appToken":"","botToken":""},"connection":{"state":"disabled"},"createdBy":{"id":"alice@example.test","name":"Name of alice"},"sessions":0,"session":null}],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"email":null,"access":{"kind":"env","key":"","provider":null,"endpoint":null,"protocol":null,"login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"model":null,"models":["claude-sonnet-5-5"],"env":[],"usedBy":["e2e-080726"],"loginCommand":"","machine":false,"backgroundOnMessage":true,"fast":null,"check":{"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","models":null,"checkedAt":1792534103657,"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口","reason":"no_probabilities","model":null,"provider":null,"models":[]}},"login":null,"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792534088354},"share":null,"workspaces":[]}],"footprint":null,"processes":[],"counts":{"sessions":1,"running":0,"warm":0},"slackUsers":[],"slackTeams":[],"disk":{"freeBytes":57235648512,"totalBytes":245107195904},"logins":[],"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs"},{"id":"google","name":"Google Gemini","group":"labs"},{"id":"xai","name":"xAI","group":"labs"},{"id":"mistral","name":"Mistral","group":"labs"},{"id":"deepseek","name":"DeepSeek","group":"labs"},{"id":"qwen","name":"Qwen","group":"labs"},{"id":"moonshotai","name":"Kimi","group":"labs"},{"id":"zai","name":"Z.ai","group":"labs"},{"id":"minimax","name":"MiniMax","group":"labs"},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs"},{"id":"ant-ling","name":"Ant Ling","group":"labs"},{"id":"jev","name":"Jev","group":"labs"},{"id":"qwen-cn","name":"Qwen (China)","group":"labs"},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs"},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs"},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs"},{"id":"openrouter","name":"OpenRouter","group":"gateways"},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways"},{"id":"opencode","name":"OpenCode Zen","group":"gateways"},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways"},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted"},{"id":"groq","name":"Groq","group":"hosted"},{"id":"together","name":"Together AI","group":"hosted"},{"id":"fireworks","name":"Fireworks","group":"hosted"},{"id":"cerebras","name":"Cerebras","group":"hosted"},{"id":"huggingface","name":"Hugging Face","group":"hosted"},{"id":"nvidia","name":"NVIDIA","group":"hosted"},{"id":"baseten","name":"Baseten","group":"hosted"},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted"},{"id":"ollama","name":"Ollama","group":"local"},{"id":"custom","name":"Custom","group":"local"}],"machineLogins":[],"consoleSignIn":true,"sharing":true,"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792534101236},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.305","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792534101236},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792534101236},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792534101236},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","latest":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792534101236}],"slackApps":[],"agentEnv":[],"drive":{"roots":[],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false},"feedback":true,"feishuRegistrations":[]}},"w":1792534107177.069}
  #|{"step":"until 已停用","w":1792534107194.307}
  #|{"step":"rest","w":1792534107194.32}
  #|{"in":{"id":16,"delta":[{"path":[0,"overview","connects",0,"connection","state"],"set":"disabled"},{"path":[0,"overview","connects",0,"enabled"],"set":false},{"path":[0,"overview","connects",0,"statusText"],"set":"已停用"},{"path":[0,"overview","disk","freeBytes"],"set":57235648512}]},"w":1792534107310.385}
  #|{"in":{"id":17,"delta":[{"path":["items",0,"connect","connection","state"],"set":"disabled"},{"path":["items",0,"connect","enabled"],"set":false},{"path":["items",0,"connect","statusText"],"set":"已停用"}]},"w":1792534107310.468}
  #|{"step":"now tap 每个 thread 一个会话","w":1792534108628.33}
  #|{"step":"now tap 每个 thread 一个会话","acted":true,"w":1792534108644.944}
  #|{"step":"rest","w":1792534108661.332}
  #|{"step":"now tap 所有 thread 共用一个会话","w":1792534110161.15}
  #|{"step":"now tap 所有 thread 共用一个会话","acted":true,"w":1792534110177.718}
  #|{"step":"until 改为单会话","w":1792534110194.45}
  #|{"step":"tap 改为单会话","w":1792534110222.674}
  #|{"step":"tap 改为单会话","acted":true,"w":1792534110261.621}
  #|{"out":{"id":21,"call":"connect.put","params":{"station":"01M5DNPYJQDZZ8G5SCF3BD72M7/e17595128f3a25c314142585a6162d3f6c2c9b9d456c8af0c76325044a94c7fc","id":"e2e-080726","input":{"mode":"single-session","requireMention":true}}},"w":1792534110277.577}
  #|{"step":"answered connect.put","w":1792534110278.31}
  #|{"in":{"id":19,"value":{"doing":[{"call":"connect.put","params":{"station":"01M5DNPYJQDZZ8G5SCF3BD72M7/e17595128f3a25c314142585a6162d3f6c2c9b9d456c8af0c76325044a94c7fc","id":"e2e-080726"},"since":1792534110277,"stage":"running"}]}},"w":1792534110343.686}
  #|{"in":{"id":21,"ok":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null},"canEditPolicy":true},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","sub":"alice","email":"alice@example.test","name":"Name of alice","role":"owner","workspace":"01M5DNPYJQDZZ8G5SCF3BD72M7","device":"02feb9d77444e2db96dbb0a69ecefc2e326ce6b8759d84c92cdd3ec12b6e6566","lockDevice":{"base":"02feb9d77444e2db96dbb0a69ecefc2e326ce6b8759d84c92cdd3ec12b6e6566","proof":"33a6bc536bc59977f015aac2a1de161ac3d2dfcf66dd4f26303849d4a4dc6bb36c6ea0bb688ff8505c2eb75fddd8d8cb38d6f008e6c3100b103cace3ab903a0a"},"home":true},"mesh":{"state":"running","origin":"http://127.0.0.1:18900","station":"e17595128f3a25c314142585a6162d3f6c2c9b9d456c8af0c76325044a94c7fc","workspace":"Dev","workspaceId":"01M5DNPYJQDZZ8G5SCF3BD72M7","name":"studio"},"connects":[{"id":"e2e-080726","name":"e2e-080726","team":null,"botImage":null,"enabled":false,"kind":"slack","mode":"single-session","requireMention":true,"bind":{"runtime":"claude","model":"claude-sonnet-5-5","effort":null,"profile":null},"slack":{"appToken":"","botToken":""},"connection":{"state":"disabled"},"createdBy":{"id":"alice@example.test","name":"Name of alice"},"sessions":0,"session":null}],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"email":null,"access":{"kind":"env","key":"","provider":null,"endpoint":null,"protocol":null,"login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"model":null,"models":["claude-sonnet-5-5"],"env":[],"usedBy":["e2e-080726"],"loginCommand":"","machine":false,"backgroundOnMessage":true,"fast":null,"check":{"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","models":null,"checkedAt":1792534103657,"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口","reason":"no_probabilities","model":null,"provider":null,"models":[]}},"login":null,"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792534088354},"share":null,"workspaces":[]}],"footprint":null,"processes":[],"counts":{"sessions":1,"running":0,"warm":0},"slackUsers":[],"slackTeams":[],"disk":{"freeBytes":57005244416,"totalBytes":245107195904},"logins":[],"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs"},{"id":"google","name":"Google Gemini","group":"labs"},{"id":"xai","name":"xAI","group":"labs"},{"id":"mistral","name":"Mistral","group":"labs"},{"id":"deepseek","name":"DeepSeek","group":"labs"},{"id":"qwen","name":"Qwen","group":"labs"},{"id":"moonshotai","name":"Kimi","group":"labs"},{"id":"zai","name":"Z.ai","group":"labs"},{"id":"minimax","name":"MiniMax","group":"labs"},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs"},{"id":"ant-ling","name":"Ant Ling","group":"labs"},{"id":"jev","name":"Jev","group":"labs"},{"id":"qwen-cn","name":"Qwen (China)","group":"labs"},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs"},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs"},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs"},{"id":"openrouter","name":"OpenRouter","group":"gateways"},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways"},{"id":"opencode","name":"OpenCode Zen","group":"gateways"},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways"},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted"},{"id":"groq","name":"Groq","group":"hosted"},{"id":"together","name":"Together AI","group":"hosted"},{"id":"fireworks","name":"Fireworks","group":"hosted"},{"id":"cerebras","name":"Cerebras","group":"hosted"},{"id":"huggingface","name":"Hugging Face","group":"hosted"},{"id":"nvidia","name":"NVIDIA","group":"hosted"},{"id":"baseten","name":"Baseten","group":"hosted"},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted"},{"id":"ollama","name":"Ollama","group":"local"},{"id":"custom","name":"Custom","group":"local"}],"machineLogins":[],"consoleSignIn":true,"sharing":true,"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792534101236},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.305","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792534101236},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792534101236},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792534101236},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","latest":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792534101236}],"slackApps":[],"agentEnv":[],"drive":{"roots":[],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false},"feedback":true,"feishuRegistrations":[]}},"w":1792534110343.748}
  #|{"step":"until 已更改会话方式","w":1792534110362.25}
  #|{"step":"rest","w":1792534110362.272}
  #|{"in":{"id":16,"delta":[{"path":[0,"overview","connects",0,"mode"],"set":"single-session"},{"path":[0,"overview","connects",0,"modeShort"],"set":"单会话"},{"path":[0,"overview","connects",0,"modeText"],"set":"单会话 · @ 唤醒"},{"path":[0,"overview","disk","freeBytes"],"set":57005244416}]},"w":1792534110410.515}
  #|{"in":{"id":17,"delta":[{"path":["items",0,"connect","mode"],"set":"single-session"},{"path":["items",0,"connect","modeShort"],"set":"单会话"},{"path":["items",0,"connect","modeText"],"set":"单会话 · @ 唤醒"}]},"w":1792534110410.596}
  #|{"in":{"id":19,"value":{"doing":[]}},"w":1792534110410.646}
  #|{"step":"now tap icon:more","w":1792534111838.965}
  #|{"step":"now tap icon:more","acted":true,"w":1792534111877.711}
  #|{"step":"rest","w":1792534111902.983}
  #|{"step":"now tap 更换 token","w":1792534113371.465}
  #|{"step":"now tap 更换 token","acted":true,"w":1792534113395.737}
  #|{"out":{"id":22,"call":"slack.tokens.edit","params":{"station":"01M5DNPYJQDZZ8G5SCF3BD72M7/e17595128f3a25c314142585a6162d3f6c2c9b9d456c8af0c76325044a94c7fc","form":"mbui-tokens-1","input":{"connect":"e2e-080726"}}},"w":1792534113413.504}
  #|{"step":"answered slack.tokens.edit","w":1792534113414.118}
  #|{"in":{"id":22,"ok":{"appToken":"","botToken":"","verified":null,"errors":[],"ready":true}},"w":1792534113427.039}
  #|{"out":{"id":23,"subscribe":{"topic":"slackTokens","station":"01M5DNPYJQDZZ8G5SCF3BD72M7/e17595128f3a25c314142585a6162d3f6c2c9b9d456c8af0c76325044a94c7fc","form":"mbui-tokens-1"},"keyed":true},"w":1792534113427.243}
  #|{"in":{"id":23,"value":{"appToken":"","botToken":"","verified":null,"errors":[],"ready":true}},"w":1792534113443.709}
  #|{"step":"rest","w":1792534113444.445}
  #|{"step":"now until App-Level Token","w":1792534114794.706}
  #|{"step":"tap xapp-","w":1792534114794.735}
  #|{"step":"tap xapp-","acted":true,"w":1792534114811.569}
  #|{"step":"type xapp-1-madeup-080726","w":1792534114834.646}
  #|{"step":"type xapp-1-madeup-080726","acted":true,"w":1792534114834.687}
  #|{"out":{"id":24,"call":"slack.tokens.edit","params":{"station":"01M5DNPYJQDZZ8G5SCF3BD72M7/e17595128f3a25c314142585a6162d3f6c2c9b9d456c8af0c76325044a94c7fc","form":"mbui-tokens-1","input":{"appToken":"xapp-1-madeup-080726"}}},"w":1792534114844.745}
  #|{"step":"answered slack.tokens.edit","w":1792534114846.842}
  #|{"in":{"id":24,"ok":{"appToken":"xapp-1-madeup-080726","botToken":"","verified":null,"errors":[],"ready":true}},"w":1792534114860.379}
  #|{"step":"tap xoxb-","w":1792534114877.848}
  #|{"step":"tap xoxb-","acted":true,"w":1792534114894.228}
  #|{"in":{"id":23,"delta":[{"path":["appToken"],"set":"xapp-1-madeup-080726"}]},"w":1792534114910.345}
  #|{"step":"type xoxb-madeup-080726","w":1792534114911.015}
  #|{"step":"type xoxb-madeup-080726","acted":true,"w":1792534114911.035}
  #|{"out":{"id":25,"call":"slack.tokens.edit","params":{"station":"01M5DNPYJQDZZ8G5SCF3BD72M7/e17595128f3a25c314142585a6162d3f6c2c9b9d456c8af0c76325044a94c7fc","form":"mbui-tokens-1","input":{"botToken":"xoxb-madeup-080726"}}},"w":1792534114927.684}
  #|{"step":"answered slack.tokens.edit","w":1792534114928.154}
  #|{"in":{"id":25,"ok":{"appToken":"xapp-1-madeup-080726","botToken":"xoxb-madeup-080726","verified":null,"errors":[],"ready":true}},"w":1792534114946.629}
  #|{"step":"tap 保存并连接","w":1792534114961.428}
  #|{"step":"tap 保存并连接","acted":true,"w":1792534114978.211}
  #|{"out":{"id":26,"call":"slack.tokens.verify","params":{"station":"01M5DNPYJQDZZ8G5SCF3BD72M7/e17595128f3a25c314142585a6162d3f6c2c9b9d456c8af0c76325044a94c7fc","form":"mbui-tokens-1"}},"w":1792534114994.005}
  #|{"step":"answered slack.tokens.verify","w":1792534114994.952}
  #|{"in":{"id":23,"delta":[{"path":["botToken"],"set":"xoxb-madeup-080726"}]},"w":1792534115010.361}
  #|{"in":{"id":19,"value":{"doing":[{"call":"slack.tokens.verify","params":{"station":"01M5DNPYJQDZZ8G5SCF3BD72M7/e17595128f3a25c314142585a6162d3f6c2c9b9d456c8af0c76325044a94c7fc","form":"mbui-tokens-1"},"since":1792534114994,"stage":"running"}]}},"w":1792534115010.41}
  #|{"in":{"id":26,"ok":false},"w":1792534116960.368}
  #|{"step":"tap 取消","w":1792534116978.485}
  #|{"step":"tap 取消","acted":true,"w":1792534116995.235}
  #|{"out":{"id":27,"call":"slack.tokens.drop","params":{"station":"01M5DNPYJQDZZ8G5SCF3BD72M7/e17595128f3a25c314142585a6162d3f6c2c9b9d456c8af0c76325044a94c7fc","form":"mbui-tokens-1"}},"w":1792534117010.816}
  #|{"step":"answered slack.tokens.drop","w":1792534117012.099}
  #|{"in":{"id":27,"ok":{"appToken":"","botToken":"","verified":null,"errors":[],"ready":false}},"w":1792534117027.038}
  #|{"in":{"id":23,"value":{"appToken":"","botToken":"","verified":null,"errors":[],"ready":false}},"w":1792534117027.192}
  #|{"in":{"id":19,"value":{"doing":[]}},"w":1792534117027.216}
  #|{"step":"rest","w":1792534117044.573}
  #|{"step":"now tap icon:more","w":1792534118494.396}
  #|{"step":"now tap icon:more","acted":true,"w":1792534118511.358}
  #|{"step":"rest","w":1792534118528.861}
  #|{"step":"now tap 删除连接","w":1792534119994.713}
  #|{"step":"now tap 删除连接","acted":true,"w":1792534120011.595}
  #|{"step":"rest","w":1792534120028.12}
  #|{"in":{"id":16,"delta":[{"path":[0,"overview","disk","freeBytes"],"set":56845758464},{"path":[0,"overview","machineLogins"],"append":[{"runtime":"claude","installed":true,"loggedIn":false,"usable":false,"text":"无法读取 Claude Code 的登录信息","offered":false},{"runtime":"codex","installed":true,"loggedIn":false,"usable":false,"text":"Codex 未登录","offered":false}]}]},"w":1792534120810.354}
  #|{"step":"now until 删除「e2e-080726」","w":1792534121444.761}
  #|{"step":"tap =删除连接","w":1792534121444.825}
  #|{"step":"tap =删除连接","acted":true,"w":1792534121461.654}
  #|{"out":{"id":28,"call":"connect.delete","params":{"station":"01M5DNPYJQDZZ8G5SCF3BD72M7/e17595128f3a25c314142585a6162d3f6c2c9b9d456c8af0c76325044a94c7fc","id":"e2e-080726"}},"w":1792534121477.371}
  #|{"step":"answered connect.delete","w":1792534121480.904}
  #|{"in":{"id":19,"value":{"doing":[{"call":"connect.delete","params":{"station":"01M5DNPYJQDZZ8G5SCF3BD72M7/e17595128f3a25c314142585a6162d3f6c2c9b9d456c8af0c76325044a94c7fc","id":"e2e-080726"},"since":1792534121477,"stage":"running"}]}},"w":1792534121543.649}
  #|{"in":{"id":16,"delta":[{"path":[0,"overview","connects"],"set":[]},{"path":[0,"overview","disk","freeBytes"],"set":57181888512},{"path":[0,"overview","profiles",0,"usedBy"],"set":[]}]},"w":1792534121543.682}
  #|{"in":{"id":17,"delta":[{"path":["items"],"set":[]},{"path":["wait","empty"],"set":true}]},"w":1792534121543.712}
  #|{"in":{"id":28,"ok":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null},"canEditPolicy":true},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","sub":"alice","email":"alice@example.test","name":"Name of alice","role":"owner","workspace":"01M5DNPYJQDZZ8G5SCF3BD72M7","device":"02feb9d77444e2db96dbb0a69ecefc2e326ce6b8759d84c92cdd3ec12b6e6566","lockDevice":{"base":"02feb9d77444e2db96dbb0a69ecefc2e326ce6b8759d84c92cdd3ec12b6e6566","proof":"33a6bc536bc59977f015aac2a1de161ac3d2dfcf66dd4f26303849d4a4dc6bb36c6ea0bb688ff8505c2eb75fddd8d8cb38d6f008e6c3100b103cace3ab903a0a"},"home":true},"mesh":{"state":"running","origin":"http://127.0.0.1:18900","station":"e17595128f3a25c314142585a6162d3f6c2c9b9d456c8af0c76325044a94c7fc","workspace":"Dev","workspaceId":"01M5DNPYJQDZZ8G5SCF3BD72M7","name":"studio"},"connects":[],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"email":null,"access":{"kind":"env","key":"","provider":null,"endpoint":null,"protocol":null,"login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"model":null,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"fast":null,"check":{"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","models":null,"checkedAt":1792534103657,"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口","reason":"no_probabilities","model":null,"provider":null,"models":[]}},"login":null,"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792534088354},"share":null,"workspaces":[]}],"footprint":null,"processes":[],"counts":{"sessions":1,"running":0,"warm":0},"slackUsers":[],"slackTeams":[],"disk":{"freeBytes":57181888512,"totalBytes":245107195904},"logins":[],"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs"},{"id":"google","name":"Google Gemini","group":"labs"},{"id":"xai","name":"xAI","group":"labs"},{"id":"mistral","name":"Mistral","group":"labs"},{"id":"deepseek","name":"DeepSeek","group":"labs"},{"id":"qwen","name":"Qwen","group":"labs"},{"id":"moonshotai","name":"Kimi","group":"labs"},{"id":"zai","name":"Z.ai","group":"labs"},{"id":"minimax","name":"MiniMax","group":"labs"},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs"},{"id":"ant-ling","name":"Ant Ling","group":"labs"},{"id":"jev","name":"Jev","group":"labs"},{"id":"qwen-cn","name":"Qwen (China)","group":"labs"},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs"},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs"},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs"},{"id":"openrouter","name":"OpenRouter","group":"gateways"},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways"},{"id":"opencode","name":"OpenCode Zen","group":"gateways"},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways"},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted"},{"id":"groq","name":"Groq","group":"hosted"},{"id":"together","name":"Together AI","group":"hosted"},{"id":"fireworks","name":"Fireworks","group":"hosted"},{"id":"cerebras","name":"Cerebras","group":"hosted"},{"id":"huggingface","name":"Hugging Face","group":"hosted"},{"id":"nvidia","name":"NVIDIA","group":"hosted"},{"id":"baseten","name":"Baseten","group":"hosted"},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted"},{"id":"ollama","name":"Ollama","group":"local"},{"id":"custom","name":"Custom","group":"local"}],"machineLogins":[{"runtime":"claude","installed":true,"loggedIn":false,"email":null,"plan":null,"usable":false,"quota":null,"text":"无法读取 Claude Code 的登录信息"},{"runtime":"codex","installed":true,"loggedIn":false,"email":null,"plan":null,"usable":false,"quota":null,"text":"Codex 未登录"}],"consoleSignIn":true,"sharing":true,"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792534101236},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.305","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792534101236},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792534101236},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792534101236},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","latest":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792534101236}],"slackApps":[],"agentEnv":[],"drive":{"roots":[],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false},"feedback":true,"feishuRegistrations":[]}},"w":1792534121543.811}
  #|{"step":"until 已删除连接","w":1792534121560.612}
  #|{"step":"hover =连接","w":1792534121560.623}
  #|{"in":{"id":19,"value":{"doing":[]}},"w":1792534121593.635}
  #|{"step":"hover =连接","acted":true,"w":1792534121794.038}
  #|{"step":"wait 2600","w":1792534121810.452}
  #|{"in":{"id":16,"delta":[{"path":[0,"host","checkedAt"],"set":1792534124077},{"path":[0,"host","cpuBusy"],"set":0.44},{"path":[0,"host","details",3,"value"],"set":"进程占用 136 MB"},{"path":[0,"host","disk","freeBytes"],"set":57181745152},{"path":[0,"host","emberRssBytes"],"set":142112424},{"path":[0,"host","emberText"],"set":"still.fail 136 MB"},{"path":[0,"host","load"],"set":0.71},{"path":[0,"host","memory","usedBytes"],"set":9767534592},{"path":[0,"host","meters",0,"big"],"set":"56"},{"path":[0,"host","meters",0,"left"],"set":56},{"path":[0,"host","meters",0,"note"],"set":"负载 7.1 · Apple M4"},{"path":[0,"host","meters",0,"percent"],"set":44},{"path":[0,"host","meters",0,"remaining"],"set":"空闲 56%"},{"path":[0,"host","meters",0,"total"],"set":"负载 7.1"},{"path":[0,"host","meters",0,"value"],"set":"44%"},{"path":[0,"host","meters",1,"big"],"set":"6.9"},{"path":[0,"host","meters",1,"left"],"set":43},{"path":[0,"host","meters",1,"percent"],"set":57},{"path":[0,"host","meters",1,"remaining"],"set":"剩 6.9 G"},{"path":[0,"host","meters",1,"value"],"set":"9.1 GB / 16.0 GB"},{"path":[0,"host","uptimeSec"],"set":13486},{"path":[0,"host","usage"],"set":"内存 9.1 GB / 16.0 GB · 磁盘 剩余 53.3 GB / 228 GB"}]},"w":1792534124460.479}
  #|{"step":"now rest","w":1792534124461.68}
  #|{"step":"now tap icon:plus","w":1792534124477.371}
  #|{"step":"now tap icon:plus","acted":true,"w":1792534124494.088}
  #|{"out":{"id":29,"subscribe":{"topic":"connectFlow","station":"01M5DNPYJQDZZ8G5SCF3BD72M7/e17595128f3a25c314142585a6162d3f6c2c9b9d456c8af0c76325044a94c7fc","form":"mbui-connect-1"},"keyed":true},"w":1792534124510.701}
  #|{"out":{"id":30,"call":"connect.flow.open","params":{"station":"01M5DNPYJQDZZ8G5SCF3BD72M7/e17595128f3a25c314142585a6162d3f6c2c9b9d456c8af0c76325044a94c7fc","form":"mbui-connect-1","input":{"mobile":true,"resume":null}}},"w":1792534124511.536}
  #|{"step":"answered connect.flow.open","w":1792534124511.809}
  #|{"in":{"id":29,"error":{"code":"invalid_params","message":"连接草稿已关闭"}},"w":1792534124526.983}
  #|{"in":{"id":30,"ok":{"step":"platform","platform":null,"feishu":{"way":"scan","appId":"","appSecret":"","lark":false,"canVerify":false,"verified":false,"errors":[],"failed":false,"creating":false,"error":null,"connect":null},"resume":null,"mobile":true,"team":null,"adding":false,"settings":{"name":"still.fail","displayName":"still.fail","description":"Coding agent in your threads (still.fail)","longDescription":"","backgroundColor":"#F3E3D3","groups":{"base":true,"public":true,"dm":true,"customize":true,"files":true,"reactions":true,"channels":true,"people":true,"extras":true,"canvases":true,"lists":true,"topics":true,"usergroups":true,"search":true,"connect":true,"more":true}},"icon":null,"iconError":null,"madeId":null,"config":"","mode":"multi-session","requireMention":true,"platforms":["slack","feishu"],"title":"选择平台","back":"close","number":1,"total":5,"gettingToken":false,"noProfile":false,"configReady":false,"configError":null,"canMake":false,"canCreate":true,"teams":[],"chosen":null,"made":null,"pick":{"fastAvailable":false,"fastText":null,"options":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"runtimes":["claude"],"maker":{"id":"anthropic","name":"Anthropic"},"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"id":"cc","name":"cc","current":false,"spent":null,"efforts":["low","medium","high","xhigh","max"],"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792534088354},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]},"spent":null,"availability":"here"}],"runtimeFixed":false,"value":{"model":"claude-sonnet-5-5","runtime":"claude","effort":null,"fast":null,"profile":null},"valueOption":{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"runtimes":["claude"],"maker":{"id":"anthropic","name":"Anthropic"},"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"id":"cc","name":"cc","current":false,"spent":null,"efforts":["low","medium","high","xhigh","max"],"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792534088354},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]},"spent":null,"availability":"here"},"account":{"text":"自动分配","auto":true,"level":null,"profile":null},"draft":{"model":"claude-sonnet-5-5","runtime":"claude","effort":null,"profile":null,"fast":null},"option":"claude-sonnet-5-5","runtimes":[],"efforts":["low","medium","high","xhigh","max"],"accounts":[{"id":"cc","name":"cc","current":false,"spent":null,"efforts":["low","medium","high","xhigh","max"],"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792534088354},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}],"dropped":null,"who":"账号","whoLevel":null,"autoNote":"额度用完或登录失效时自动切换","changed":false,"was":["Sonnet 5.5","默认深度","自动 · "],"becomes":["Sonnet 5.5","默认深度","自动分配"],"force":null,"modelText":"Sonnet 5.5","maker":{"id":"anthropic","name":"Anthropic"},"accountText":"自动分配","accountNote":"额度用完或登录失效时自动切换","accountWarn":false,"saveText":"无变更","next":{"model":"claude-sonnet-5-5","runtime":"claude","effort":null,"profile":null,"fast":null},"borrow":null}}},"w":1792534124527.149}
  #|{"step":"rest","w":1792534124544.225}
  #|{"in":{"id":29,"value":{"step":"platform","title":"选择平台","back":"close","number":1,"total":5,"mobile":true,"adding":false,"settings":{"name":"still.fail","displayName":"still.fail","description":"Coding agent in your threads (still.fail)","longDescription":"","backgroundColor":"#F3E3D3","groups":{"base":true,"public":true,"dm":true,"customize":true,"files":true,"reactions":true,"channels":true,"people":true,"extras":true,"canvases":true,"lists":true,"topics":true,"usergroups":true,"search":true,"connect":true,"more":true}},"config":"","configReady":false,"mode":"multi-session","requireMention":true,"gettingToken":false,"noProfile":false,"canMake":false,"canCreate":true,"teams":[],"pick":{"fastAvailable":false,"options":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792534088354,"time":{"checkedAt":{"at":1792534088354,"ago":"刚刚","full":"10/21 06:08:08","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]},"availability":"here"}],"runtimeFixed":false,"value":{"model":"claude-sonnet-5-5","runtime":"claude"},"valueOption":{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792534088354,"time":{"checkedAt":{"at":1792534088354,"ago":"刚刚","full":"10/21 06:08:08","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]},"availability":"here"},"account":{"text":"自动分配","auto":true},"draft":{"model":"claude-sonnet-5-5","runtime":"claude"},"option":"claude-sonnet-5-5","runtimes":[],"efforts":["low","medium","high","xhigh","max"],"accounts":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792534088354,"time":{"checkedAt":{"at":1792534088354,"ago":"刚刚","full":"10/21 06:08:08","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}],"who":"账号","autoNote":"额度用完或登录失效时自动切换","changed":false,"was":["Sonnet 5.5","默认深度","自动 · "],"becomes":["Sonnet 5.5","默认深度","自动分配"],"modelText":"Sonnet 5.5","maker":{"id":"anthropic","name":"Anthropic"},"accountText":"自动分配","accountNote":"额度用完或登录失效时自动切换","accountWarn":false,"saveText":"无变更"},"platforms":["slack","feishu"],"feishu":{"way":"scan","appId":"","appSecret":"","lark":false,"canVerify":false,"verified":false,"errors":[],"failed":false,"creating":false}}},"w":1792534124677.164}
  #|{"step":"now until 选择平台","w":1792534124827.622}
  #|{"step":"tap =Slack","w":1792534124827.66}
  #|{"step":"tap =Slack","acted":true,"w":1792534124844.661}
  #|{"out":{"id":31,"call":"connect.flow.edit","params":{"station":"01M5DNPYJQDZZ8G5SCF3BD72M7/e17595128f3a25c314142585a6162d3f6c2c9b9d456c8af0c76325044a94c7fc","form":"mbui-connect-1","input":{"platform":"slack"}}},"w":1792534124860.75}
  #|{"step":"answered connect.flow.edit","w":1792534124861.262}
  #|{"in":{"id":31,"ok":{"step":"platform","platform":"slack","feishu":{"way":"scan","appId":"","appSecret":"","lark":false,"canVerify":false,"verified":false,"errors":[],"failed":false,"creating":false,"error":null,"connect":null},"resume":null,"mobile":true,"team":null,"adding":false,"settings":{"name":"still.fail","displayName":"still.fail","description":"Coding agent in your threads (still.fail)","longDescription":"","backgroundColor":"#F3E3D3","groups":{"base":true,"public":true,"dm":true,"customize":true,"files":true,"reactions":true,"channels":true,"people":true,"extras":true,"canvases":true,"lists":true,"topics":true,"usergroups":true,"search":true,"connect":true,"more":true}},"icon":null,"iconError":null,"madeId":null,"config":"","mode":"multi-session","requireMention":true,"platforms":["slack","feishu"],"title":"选择平台","back":"close","number":1,"total":5,"gettingToken":false,"noProfile":false,"configReady":false,"configError":null,"canMake":false,"canCreate":true,"teams":[],"chosen":null,"made":null,"pick":{"fastAvailable":false,"fastText":null,"options":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"runtimes":["claude"],"maker":{"id":"anthropic","name":"Anthropic"},"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"id":"cc","name":"cc","current":false,"spent":null,"efforts":["low","medium","high","xhigh","max"],"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792534088354},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]},"spent":null,"availability":"here"}],"runtimeFixed":false,"value":{"model":"claude-sonnet-5-5","runtime":"claude","effort":null,"fast":null,"profile":null},"valueOption":{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"runtimes":["claude"],"maker":{"id":"anthropic","name":"Anthropic"},"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"id":"cc","name":"cc","current":false,"spent":null,"efforts":["low","medium","high","xhigh","max"],"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792534088354},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]},"spent":null,"availability":"here"},"account":{"text":"自动分配","auto":true,"level":null,"profile":null},"draft":{"model":"claude-sonnet-5-5","runtime":"claude","effort":null,"profile":null,"fast":null},"option":"claude-sonnet-5-5","runtimes":[],"efforts":["low","medium","high","xhigh","max"],"accounts":[{"id":"cc","name":"cc","current":false,"spent":null,"efforts":["low","medium","high","xhigh","max"],"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792534088354},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}],"dropped":null,"who":"账号","whoLevel":null,"autoNote":"额度用完或登录失效时自动切换","changed":false,"was":["Sonnet 5.5","默认深度","自动 · "],"becomes":["Sonnet 5.5","默认深度","自动分配"],"force":null,"modelText":"Sonnet 5.5","maker":{"id":"anthropic","name":"Anthropic"},"accountText":"自动分配","accountNote":"额度用完或登录失效时自动切换","accountWarn":false,"saveText":"无变更","next":{"model":"claude-sonnet-5-5","runtime":"claude","effort":null,"profile":null,"fast":null},"borrow":null}}},"w":1792534124877.224}
  #|{"step":"tap =下一步","w":1792534124894.324}
  #|{"step":"tap =下一步","acted":true,"w":1792534124911.151}
  #|{"out":{"id":32,"call":"connect.flow.go","params":{"station":"01M5DNPYJQDZZ8G5SCF3BD72M7/e17595128f3a25c314142585a6162d3f6c2c9b9d456c8af0c76325044a94c7fc","form":"mbui-connect-1","input":{"to":"team"}}},"w":1792534124927.389}
  #|{"step":"answered connect.flow.go","w":1792534124927.81}
  #|{"in":{"id":29,"delta":[{"path":["platform"],"set":"slack"}]},"w":1792534124943.68}
  #|{"in":{"id":32,"ok":{}},"w":1792534124943.737}
  #|{"step":"tap 添加配置 token","w":1792534124960.919}
  #|{"in":{"id":29,"delta":[{"path":["back"],"set":"platform"},{"path":["number"],"set":2},{"path":["step"],"set":"team"},{"path":["title"],"set":"选择 Slack 工作区"}]},"w":1792534125143.704}
  #|{"step":"tap 添加配置 token","acted":true,"w":1792534125261.301}
  #|{"out":{"id":33,"call":"connect.flow.go","params":{"station":"01M5DNPYJQDZZ8G5SCF3BD72M7/e17595128f3a25c314142585a6162d3f6c2c9b9d456c8af0c76325044a94c7fc","form":"mbui-connect-1","input":{"to":"token"}}},"w":1792534125277.367}
  #|{"step":"answered connect.flow.go","w":1792534125277.786}
  #|{"in":{"id":33,"ok":{}},"w":1792534125293.66}
  #|{"step":"tap =打开","w":1792534125310.961}
  #|{"in":{"id":29,"delta":[{"path":["back"],"set":"team"},{"path":["number"],"set":1},{"path":["step"],"set":"token"},{"path":["title"],"set":"添加配置 token"}]},"w":1792534125444.071}
  #|{"step":"tap =打开","acted":true,"w":1792534125594.595}
  #|{"step":"rest","w":1792534125611.168}
  #|{"step":"","w":1792534125644.424}
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
  #|{"textrec":{"ib":["fdb526ba00f881f4",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["c8ac90bf691295f0",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["31d8ec32aedeae00",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["bef2954d97ce1d9f",6508,64],"r":[40,40,40,40]}}
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
  #|{"textrec":{"s":[16,600,0,"连接"],"r":[0,1,15.875486381322958,185,1,1,15.875486381322958,186]}}
  #|{"textrec":{"s":[17,400,0,"设置"],"r":[0,1,16.851167315175097,187,1,1,16.851167315175097,188]}}
  #|{"textrec":{"s":[15,600,0,"studio"],"r":[0,1,8.000344634056091,189,1,1,5.658300518989563,190,2,1,8.93320620059967,191,3,1,9.332013130187988,192,4,1,3.8520312309265137,193,5,1,8.901597261428833,194]}}
  #|{"textrec":{"s":[12,400,0,"未连接 Slack"],"r":[0,1,11.918287937743191,195,1,1,11.918287937743191,196,2,1,11.918287937743195,197,3,1,3.375,-1,4,1,7.646484375,198,5,1,3.03515625,199,6,1,6.62109375,200,7,1,6.71484375,201,8,1,6.515625,202]}}
  #|{"textrec":{"m":[12,400,0],"r":[11.6015625,2.53125,17]}}
  #|{"textrec":{"s":[15,400,0,"e2e-080726"],"r":[0,1,8.3349609375,95,1,1,8.78173828125,203,2,1,8.29833984375,95,3,1,6.8408203125,204,4,1,9.2138671875,164,5,1,9.345703125,205,6,1,9.0673828125,164,7,1,8.1591796875,206,8,1,8.818359375,203,9,1,9.31640625,207]}}
  #|{"textrec":{"s":[13,400,0,"多会话 · Claude Code · Sonnet 5.5"],"r":[0,1,12.898832684824903,208,1,1,12.898832684824903,209,2,1,12.898832684824903,210,3,1,3.580078125,-1,4,1,6.228545204222122,211,5,1,3.580078125,-1,6,1,9.2294921875,212,7,1,3.2119140625,76,8,1,7.0966796875,12,9,1,7.50927734375,213,10,1,7.9091796875,214,11,1,7.3505859375,14,12,1,3.580078125,-1,13,1,9.2294921875,212,14,1,7.6044921875,7,15,1,7.9091796875,214,16,1,7.3505859375,14,17,1,3.580078125,-1,18,1,6.228545204222115,211,19,1,3.580078125,-1,20,1,8.20751953125,215,21,1,7.6044921875,7,22,1,7.50927734375,216,23,1,7.50927734375,216,24,1,7.3505859375,14,25,1,4.646484375,82,26,1,3.580078125,-1,27,1,7.73779296875,217,28,1,3.354736328125,81,29,1,7.753662109375,217]}}
  #|{"textrec":{"s":[13,400,0,"…"],"r":[0,1,10.384765625,218]}}
  #|{"textrec":{"s":[13,400,0,"多会话 · Claude Code · Sonn…"],"r":[0,1,12.898832684824903,208,1,1,12.898832684824903,209,2,1,12.898832684824903,210,3,1,3.580078125,-1,4,1,6.228545204222122,211,5,1,3.580078125,-1,6,1,9.2294921875,212,7,1,3.2119140625,76,8,1,7.0966796875,12,9,1,7.50927734375,213,10,1,7.9091796875,214,11,1,7.3505859375,14,12,1,3.580078125,-1,13,1,9.2294921875,212,14,1,7.6044921875,7,15,1,7.9091796875,214,16,1,7.3505859375,14,17,1,3.580078125,-1,18,1,6.228545204222115,211,19,1,3.580078125,-1,20,1,8.20751953125,215,21,1,7.6044921875,7,22,1,7.50927734375,216,23,1,7.50927734375,216,24,1,10.384765625,218]}}
  #|{"textrec":{"g":187,"r":[1967,0,19,18,-1,-15,0]}}
  #|{"textrec":{"g":188,"r":[1987,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":189,"r":[2006,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":190,"r":[2017,0,8,13,-1,-11,0]}}
  #|{"textrec":{"g":191,"r":[2026,0,10,12,0,-10,0]}}
  #|{"textrec":{"g":192,"r":[0,32,11,15,-1,-13,0]}}
  #|{"textrec":{"g":193,"r":[12,32,6,14,-1,-13,0]}}
  #|{"textrec":{"g":194,"r":[19,32,11,12,-1,-10,0]}}
  #|{"textrec":{"ib":["ae2e80af250a0610",1241,64],"r":[17,17,17,17]}}
  #|{"textrec":{"g":203,"r":[31,32,10,13,0,-12,0]}}
  #|{"textrec":{"g":204,"r":[42,32,7,4,0,-6,0]}}
  #|{"textrec":{"g":164,"r":[50,32,11,14,-1,-12,0]}}
  #|{"textrec":{"g":205,"r":[62,32,11,14,-1,-12,0]}}
  #|{"textrec":{"g":206,"r":[74,32,10,13,-1,-12,0]}}
  #|{"textrec":{"g":207,"r":[85,32,11,14,-1,-12,0]}}
  #|{"textrec":{"g":208,"r":[97,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":209,"r":[111,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":210,"r":[127,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":211,"r":[143,32,4,5,1,-7,0]}}
  #|{"textrec":{"g":212,"r":[148,32,11,13,-1,-11,0]}}
  #|{"textrec":{"g":213,"r":[160,32,9,10,-1,-8,0]}}
  #|{"textrec":{"g":214,"r":[170,32,9,13,-1,-11,0]}}
  #|{"textrec":{"g":7,"r":[180,32,9,10,-1,-8,0]}}
  #|{"textrec":{"g":215,"r":[190,32,10,13,-1,-11,0]}}
  #|{"textrec":{"g":216,"r":[201,32,8,9,0,-8,0]}}
  #|{"textrec":{"g":218,"r":[210,32,11,5,0,-3,0]}}
  #|{"textrec":{"g":185,"r":[222,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":186,"r":[240,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":195,"r":[258,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":196,"r":[273,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":197,"r":[288,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":198,"r":[303,32,9,12,-1,-10,0]}}
  #|{"textrec":{"g":199,"r":[313,32,4,11,0,-10,0]}}
  #|{"textrec":{"g":200,"r":[318,32,8,10,-1,-8,0]}}
  #|{"textrec":{"g":201,"r":[327,32,9,10,-1,-8,0]}}
  #|{"textrec":{"g":202,"r":[337,32,8,11,0,-10,0]}}
  #|{"textrec":{"ib":["2bb63fc1d380f765",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"s":[11,400,0,"未连接 Slack"],"r":[0,1,10.93579766536965,219,1,1,10.93579766536965,220,2,1,10.935797665369652,221,3,1,3.158203125,-1,4,1,7.07373046875,222,5,1,2.8466796875,223,6,1,6.1337890625,224,7,1,6.2197265625,225,8,1,6.037109374999993,226]}}
  #|{"textrec":{"m":[11,400,0],"r":[10.634765625,2.3203125,16]}}
  #|{"textrec":{"s":[16,600,0,"e2e-080726"],"r":[0,1,9.127458572387695,46,1,1,9.717817306518555,227,2,1,9.100765228271484,46,3,1,7.363014221191406,228,4,1,10.31976318359375,229,5,1,10.440597534179688,230,6,1,10.138774871826172,229,7,1,8.996856689453125,231,8,1,9.744510650634766,227,9,1,10.3499755859375,232]}}
  #|{"textrec":{"s":[17,400,0,"连接"],"r":[0,1,16.851167315175097,233,1,1,16.851167315175097,234]}}
  #|{"textrec":{"s":[15,400,0,"Slack"],"r":[0,1,9.32373046875,100,1,1,3.5595703125,108,2,1,8.0419921875,93,3,1,8.1591796875,94,4,1,7.91015625,90]}}
  #|{"textrec":{"s":[13,400,0,"studio · 所属 你"],"r":[0,1,6.69677734375,10,1,1,4.61474609375,82,2,1,7.50927734375,213,3,1,7.9091796875,214,4,1,3.1357421875,77,5,1,7.6044921875,7,6,1,3.580078125,-1,7,1,6.228545204222122,211,8,1,3.580078125,-1,9,1,12.898832684824903,235,10,1,12.89883268482491,236,11,1,3.580078125,-1,12,1,12.898832684824896,4]}}
  #|{"textrec":{"s":[13,400,0,"此连接尚未接入 Slack。"],"r":[0,1,12.898832684824903,237,1,1,12.898832684824903,238,2,1,12.898832684824903,239,3,1,12.898832684824903,240,4,1,12.898832684824896,241,5,1,12.898832684824896,239,6,1,12.898832684824896,242,7,1,3.580078125,-1,8,1,8.20751953125,215,9,1,3.2119140625,76,10,1,7.0966796875,12,11,1,7.1982421875,13,12,1,6.982421875,9,13,1,6.575875486381335,243]}}
  #|{"textrec":{"s":[13,400,0,"填写 token"],"r":[0,1,12.898832684824903,244,1,1,12.898832684824903,245,2,1,3.580078125,-1,3,1,4.598876953125,82,4,1,7.556884765625,7,5,1,6.82373046875,9,6,1,7.19189453125,14,7,1,7.50927734375,216]}}
  #|{"textrec":{"s":[15,600,0,"运行方式"],"r":[0,1,14.883268482490273,246,1,1,14.883268482490273,247,2,1,14.883268482490273,248,3,1,14.883268482490273,249]}}
  #|{"textrec":{"s":[13,400,0,"模型"],"r":[0,1,12.898832684824903,250,1,1,12.898832684824903,251]}}
  #|{"textrec":{"s":[15,400,0,"Sonnet 5.5 · 默认深度 · 自动分配"],"r":[0,1,9.32373046875,100,1,1,8.6279296875,88,2,1,8.51806640625,103,3,1,8.51806640625,103,4,1,8.3349609375,95,5,1,5.21484375,101,6,1,3.984375,-1,7,1,8.78173828125,252,8,1,3.724365234375,160,9,1,8.800048828125,252,10,1,3.984375,-1,11,1,7.186782927948599,253,12,1,3.984375,-1,13,1,14.88326848249028,254,14,1,14.88326848249028,255,15,1,14.88326848249028,256,16,1,14.88326848249028,257,17,1,3.984375,-1,18,1,7.186782927948599,253,19,1,3.984375,-1,20,1,14.88326848249028,109,21,1,14.88326848249028,110,22,1,14.88326848249028,258,23,1,14.88326848249028,259]}}
  #|{"textrec":{"s":[13,400,0,"会话"],"r":[0,1,12.898832684824903,209,1,1,12.898832684824903,210]}}
  #|{"textrec":{"s":[15,400,0,"每个 thread 一个会话"],"r":[0,1,14.883268482490273,260,1,1,14.883268482490273,261,2,1,3.984375,-1,3,1,5.21484375,101,4,1,8.59130859375,262,5,1,5.36865234375,89,6,1,8.22509765625,95,7,1,8.0419921875,93,8,1,8.9794921875,263,9,1,3.984375,-1,10,1,14.883268482490266,264,11,1,14.88326848249028,261,12,1,14.88326848249028,265,13,1,14.88326848249028,266]}}
  #|{"textrec":{"s":[13,400,0,"在 thread 中 @ 它即开启一个新会话，该 thread 的后续消息都进入此会话"],"r":[0,1,12.898832684824903,1,1,1,3.580078125,-1,2,1,4.646484375,82,3,1,7.57275390625,267,4,1,4.77978515625,8,5,1,7.25537109375,14,6,1,7.0966796875,12,7,1,7.9091796875,214,8,1,3.580078125,-1,9,1,12.898832684824903,268,10,1,3.580078125,-1,11,1,11.857421875,78,12,1,3.580078125,-1,13,1,12.89883268482491,269,14,1,12.898832684824896,270,15,1,12.898832684824896,271,16,1,12.898832684824896,272,17,1,12.898832684824896,273,18,1,12.898832684824896,274,19,1,12.898832684824896,150,20,1,12.898832684824896,209,21,1,12.898832684824896,210,22,1,13.075875486381335,275,23,1,12.898832684824896,276,24,1,3.580078125,-1,25,1,4.646484375,82,26,1,7.57275390625,267,27,1,4.77978515625,8,28,1,7.255371093750028,14,29,1,7.0966796875,12,30,1,7.9091796875,214,31,1,3.580078125,-1,32,1,12.898832684824924,5,33,1,12.898832684824924,277,34,1,12.898832684824924,278,35,1,12.898832684824924,151,36,1,12.898832684824924,152,37,1,12.898832684824924,279,38,1,12.898832684824924,280,39,1,12.898832684824924,242,40,1,12.898832684824924,237,41,1,12.898832684824924,209,42,1,12.898832684824924,210]}}
  #|{"textrec":{"s":[13,400,0,"运行于 Claude Code，创建后无法更改；如需使用其他运行时，请新建连接。进行中的会话继续使用开始时的设置。"],"r":[0,1,12.898832684824903,281,1,1,12.898832684824903,282,2,1,12.898832684824903,283,3,1,3.580078125,-1,4,1,9.2294921875,212,5,1,3.2119140625,76,6,1,7.0966796875,12,7,1,7.509277343750007,213,8,1,7.9091796875,214,9,1,7.3505859375,14,10,1,3.580078125,-1,11,1,9.2294921875,212,12,1,7.6044921875,7,13,1,7.9091796875,214,14,1,7.3505859375,14,15,1,13.075875486381335,275,16,1,12.898832684824896,284,17,1,12.898832684824896,285,18,1,12.898832684824896,277,19,1,12.898832684824896,286,20,1,12.898832684824896,287,21,1,12.898832684824896,288,22,1,12.898832684824896,289,23,1,13.075875486381335,290,24,1,12.898832684824896,291,25,1,12.898832684824924,142,26,1,12.898832684824924,292,27,1,12.898832684824924,293,28,1,12.898832684824924,294,29,1,12.898832684824924,295,30,1,12.898832684824924,281,31,1,12.898832684824924,282,32,1,12.898832684824924,153,33,1,13.075875486381335,275,34,1,12.898832684824924,296,35,1,12.898832684824924,150,36,1,12.898832684824924,285,37,1,12.898832684824924,238,38,1,12.898832684824924,239,39,1,13.075875486381335,243,40,1,12.898832684824924,280,41,1,12.898832684824924,282,42,1,12.898832684824924,268,43,1,12.898832684824924,5,44,1,12.898832684824924,209,45,1,12.898832684824868,210,46,1,12.898832684824924,297,47,1,12.898832684824924,278,48,1,12.898832684824924,292,49,1,12.898832684824924,293,50,1,12.898832684824924,271,51,1,12.898832684824924,298,52,1,12.898832684824924,153,53,1,12.898832684824924,5,54,1,12.898832684824924,299,55,1,12.898832684824924,300,56,1,6.575875486381278,243]}}
  #|{"textrec":{"s":[15,600,0,"Slack app"],"r":[0,1,9.68320906162262,301,1,1,3.9584755897521973,302,2,1,8.40147078037262,303,3,1,8.423570394515991,304,4,1,8.464449048042297,305,5,1,3.761730194091797,-1,6,1,8.40147078037262,303,7,1,9.268780946731567,306,8,1,9.268780946731567,306]}}
  #|{"textrec":{"s":[15,400,0,"名字、头像和权限"],"r":[0,1,14.883268482490273,307,1,1,14.883268482490273,308,2,1,15.087548638132297,309,3,1,14.883268482490273,310,4,1,14.883268482490266,311,5,1,14.88326848249028,312,6,1,14.88326848249028,313,7,1,14.88326848249028,314]}}
  #|{"textrec":{"s":[13,400,0,"修改会写入 Slack 中的此 app"],"r":[0,1,12.898832684824903,315,1,1,12.898832684824903,289,2,1,12.898832684824903,209,3,1,12.898832684824903,245,4,1,12.898832684824896,242,5,1,3.580078125,-1,6,1,8.20751953125,215,7,1,3.2119140625,76,8,1,7.0966796875,12,9,1,7.1982421875,13,10,1,6.982421875,9,11,1,3.580078125,-1,12,1,12.898832684824896,268,13,1,12.898832684824896,5,14,1,12.898832684824896,237,15,1,3.580078125,-1,16,1,7.0966796875,12,17,1,7.8583984375,11,18,1,7.8583984375,11]}}
  #|{"textrec":{"s":[15,600,0,"最近会话"],"r":[0,1,14.883268482490273,316,1,1,14.883268482490273,317,2,1,14.883268482490273,318,3,1,14.883268482490273,319]}}
  #|{"textrec":{"s":[15,400,0,"暂无会话。在 Slack 中 @e2e-080726 即可开始。"],"r":[0,1,14.883268482490273,320,1,1,14.883268482490273,321,2,1,14.883268482490273,265,3,1,14.883268482490273,266,4,1,15.08754863813229,322,5,1,14.88326848249028,323,6,1,3.984375,-1,7,1,9.32373046875,100,8,1,3.5595703125,108,9,1,8.0419921875,93,10,1,8.1591796875,94,11,1,7.91015625,90,12,1,3.984375,-1,13,1,14.88326848249028,324,14,1,3.984375,-1,15,1,13.53515625,325,16,1,8.3349609375,95,17,1,8.78173828125,203,18,1,8.29833984375,95,19,1,6.8408203125,204,20,1,9.2138671875,164,21,1,9.345703125,205,22,1,9.0673828125,164,23,1,8.1591796875,206,24,1,8.818359375,203,25,1,9.31640625,207,26,1,3.984375,-1,27,1,14.88326848249028,326,28,1,14.88326848249028,327,29,1,14.88326848249028,328,30,1,14.88326848249028,329,31,1,7.5875486381323185,322]}}
  #|{"textrec":{"g":233,"r":[346,32,18,18,-1,-15,0]}}
  #|{"textrec":{"g":234,"r":[365,32,18,18,-1,-15,0]}}
  #|{"textrec":{"g":237,"r":[384,32,15,14,-1,-12,0]}}
  #|{"textrec":{"g":238,"r":[400,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":239,"r":[416,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":240,"r":[432,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":241,"r":[446,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":242,"r":[462,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":9,"r":[478,32,8,12,0,-11,0]}}
  #|{"textrec":{"g":243,"r":[487,32,6,6,0,-3,0]}}
  #|{"textrec":{"g":246,"r":[494,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":247,"r":[512,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":248,"r":[529,32,16,17,-1,-14,0]}}
  #|{"textrec":{"g":249,"r":[546,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":250,"r":[563,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":251,"r":[579,32,14,14,-1,-12,0]}}
  #|{"textrec":{"g":281,"r":[594,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":282,"r":[610,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":283,"r":[626,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":275,"r":[641,32,5,7,0,-3,0]}}
  #|{"textrec":{"g":284,"r":[647,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":285,"r":[662,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":277,"r":[678,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":286,"r":[693,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":287,"r":[708,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":288,"r":[724,32,15,14,-1,-11,0]}}
  #|{"textrec":{"g":289,"r":[740,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":290,"r":[756,32,5,11,1,-9,0]}}
  #|{"textrec":{"g":291,"r":[762,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":142,"r":[777,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":292,"r":[792,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":293,"r":[808,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":294,"r":[823,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":295,"r":[839,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":153,"r":[855,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":296,"r":[871,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":150,"r":[887,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":280,"r":[903,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":268,"r":[919,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":5,"r":[933,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":297,"r":[947,32,15,14,-1,-12,0]}}
  #|{"textrec":{"g":278,"r":[963,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":271,"r":[979,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":298,"r":[994,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":299,"r":[1010,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":300,"r":[1026,32,15,13,-1,-11,0]}}
  #|{"textrec":{"g":301,"r":[1042,32,12,14,-1,-12,0]}}
  #|{"textrec":{"g":302,"r":[1055,32,5,14,0,-13,0]}}
  #|{"textrec":{"g":303,"r":[1061,32,10,12,-1,-10,0]}}
  #|{"textrec":{"g":304,"r":[1072,32,11,12,-1,-10,0]}}
  #|{"textrec":{"g":305,"r":[1084,32,10,14,0,-13,0]}}
  #|{"textrec":{"g":306,"r":[1095,32,10,14,0,-10,0]}}
  #|{"textrec":{"g":316,"r":[1106,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":317,"r":[1123,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":318,"r":[1141,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":319,"r":[1159,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":320,"r":[1177,32,15,17,0,-14,0]}}
  #|{"textrec":{"g":321,"r":[1193,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":265,"r":[1210,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":266,"r":[1228,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":322,"r":[1246,32,7,7,0,-4,0]}}
  #|{"textrec":{"g":323,"r":[1254,32,16,17,-1,-14,0]}}
  #|{"textrec":{"g":324,"r":[1271,32,15,16,0,-13,0]}}
  #|{"textrec":{"g":325,"r":[1287,32,14,15,0,-12,0]}}
  #|{"textrec":{"g":326,"r":[1302,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":327,"r":[1319,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":328,"r":[1336,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":329,"r":[1353,32,16,16,-1,-13,0]}}
  #|{"textrec":{"ib":["76961adfc9864d7d",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"g":307,"r":[1370,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":308,"r":[1386,32,16,17,-1,-14,0]}}
  #|{"textrec":{"g":309,"r":[1403,32,7,7,0,-4,0]}}
  #|{"textrec":{"g":310,"r":[1411,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":311,"r":[1428,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":312,"r":[1446,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":313,"r":[1463,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":314,"r":[1481,32,16,16,0,-13,0]}}
  #|{"textrec":{"g":315,"r":[1498,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":245,"r":[1514,32,14,14,-1,-11,0]}}
  #|{"textrec":{"ib":["78b0ba5fc1dd19af",2593,64],"r":[25,25,25,25]}}
  #|{"textrec":{"g":235,"r":[1529,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":236,"r":[1545,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":4,"r":[1560,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":252,"r":[1575,32,10,14,0,-12,0]}}
  #|{"textrec":{"g":160,"r":[1586,32,5,5,0,-3,0]}}
  #|{"textrec":{"g":253,"r":[1592,32,5,5,1,-8,0]}}
  #|{"textrec":{"g":254,"r":[1598,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":255,"r":[1616,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":256,"r":[1634,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":257,"r":[1652,32,16,17,-1,-14,0]}}
  #|{"textrec":{"g":258,"r":[1669,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":259,"r":[1686,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":260,"r":[1703,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":261,"r":[1721,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":262,"r":[1739,32,9,14,0,-13,0]}}
  #|{"textrec":{"g":263,"r":[1749,32,10,15,-1,-13,0]}}
  #|{"textrec":{"g":264,"r":[1760,32,16,4,-1,-7,0]}}
  #|{"textrec":{"g":1,"r":[1777,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":267,"r":[1792,32,8,12,0,-11,0]}}
  #|{"textrec":{"g":8,"r":[1801,32,6,9,0,-8,0]}}
  #|{"textrec":{"g":269,"r":[1808,32,14,14,-1,-12,0]}}
  #|{"textrec":{"g":270,"r":[1823,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":272,"r":[1838,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":273,"r":[1853,32,15,4,-1,-7,0]}}
  #|{"textrec":{"g":274,"r":[1869,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":276,"r":[1885,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":151,"r":[1901,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":152,"r":[1916,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":279,"r":[1932,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":46,"r":[1947,32,11,12,-1,-10,0]}}
  #|{"textrec":{"g":227,"r":[1959,32,11,14,0,-13,0]}}
  #|{"textrec":{"g":228,"r":[1971,32,8,5,0,-7,0]}}
  #|{"textrec":{"g":229,"r":[1980,32,11,15,0,-13,0]}}
  #|{"textrec":{"g":230,"r":[1992,32,12,15,-1,-13,0]}}
  #|{"textrec":{"g":231,"r":[2005,32,11,14,-1,-13,0]}}
  #|{"textrec":{"g":232,"r":[2017,32,12,15,-1,-13,0]}}
  #|{"textrec":{"g":219,"r":[2030,32,13,13,-1,-10,0]}}
  #|{"textrec":{"g":220,"r":[0,51,13,13,-1,-10,0]}}
  #|{"textrec":{"g":221,"r":[14,51,13,13,-1,-10,0]}}
  #|{"textrec":{"g":222,"r":[28,51,9,11,-1,-9,0]}}
  #|{"textrec":{"g":223,"r":[38,51,4,11,-1,-10,0]}}
  #|{"textrec":{"g":224,"r":[43,51,8,9,-1,-7,0]}}
  #|{"textrec":{"g":225,"r":[52,51,8,9,-1,-7,0]}}
  #|{"textrec":{"g":226,"r":[61,51,8,11,-1,-10,0]}}
  #|{"textrec":{"g":244,"r":[70,51,15,15,-1,-12,0]}}
  #|{"textrec":{"ib":["ddfdc2820df8a676",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"s":[17,700,0,"e2e-080726"],"r":[0,1,9.782470703125,330,1,1,10.479736328125,331,2,1,9.76171875,330,3,1,7.802734375,332,4,1,11.2060546875,333,5,1,11.322265625,334,6,1,10.99853515625,333,7,1,9.6787109375,335,8,1,10.50048828125,331,9,1,11.189453125,336]}}
  #|{"textrec":{"m":[17,700,0],"r":[16.435546875,3.5859375,24]}}
  #|{"textrec":{"s":[15,400,0,"重新连接"],"r":[0,1,14.883268482490273,337,1,1,14.883268482490273,159,2,1,14.883268482490273,104,3,1,14.883268482490273,105]}}
  #|{"textrec":{"s":[15,400,0,"更换 token"],"r":[0,1,14.883268482490273,158,1,1,14.883268482490273,338,2,1,3.984375,-1,3,1,5.159912109375,101,4,1,8.572998046875,88,5,1,7.72705078125,90,6,1,8.15185546875,95,7,1,8.51806640625,103]}}
  #|{"textrec":{"s":[15,400,0,"停用"],"r":[0,1,14.883268482490273,339,1,1,14.883268482490273,115]}}
  #|{"textrec":{"s":[12,400,0,"Slack 连接将断开"],"r":[0,1,7.646484375,198,1,1,3.03515625,199,2,1,6.62109375,200,3,1,6.71484375,201,4,1,6.515625,202,5,1,3.375,-1,6,1,11.918287937743187,196,7,1,11.918287937743187,197,8,1,11.918287937743187,340,9,1,11.918287937743187,341,10,1,11.918287937743187,342]}}
  #|{"textrec":{"s":[15,400,0,"更改所属用户"],"r":[0,1,14.883268482490273,158,1,1,14.883268482490273,343,2,1,14.883268482490273,344,3,1,14.883268482490273,345,4,1,14.88326848249028,115,5,1,14.88326848249028,346]}}
  #|{"textrec":{"s":[12,400,0,"你"],"r":[0,1,11.918287937743191,347]}}
  #|{"textrec":{"s":[15,400,0,"删除连接"],"r":[0,1,14.883268482490273,348,1,1,14.883268482490273,349,2,1,14.883268482490273,104,3,1,14.883268482490273,105]}}
  #|{"textrec":{"g":330,"r":[86,51,12,13,-1,-11,0]}}
  #|{"textrec":{"g":331,"r":[99,51,11,15,0,-14,0]}}
  #|{"textrec":{"g":332,"r":[111,51,8,5,0,-7,0]}}
  #|{"textrec":{"g":333,"r":[120,51,12,16,0,-14,0]}}
  #|{"textrec":{"g":334,"r":[133,51,12,16,0,-14,0]}}
  #|{"textrec":{"g":335,"r":[146,51,12,14,-1,-13,0]}}
  #|{"textrec":{"g":336,"r":[159,51,12,16,0,-14,0]}}
  #|{"textrec":{"g":337,"r":[172,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":159,"r":[189,51,17,17,-1,-14,0]}}
  #|{"textrec":{"g":158,"r":[207,51,17,16,-1,-13,0]}}
  #|{"textrec":{"g":338,"r":[225,51,17,17,-1,-14,0]}}
  #|{"textrec":{"g":339,"r":[243,51,16,17,-1,-14,0]}}
  #|{"textrec":{"g":340,"r":[260,51,14,14,-1,-11,0]}}
  #|{"textrec":{"g":341,"r":[275,51,14,14,-1,-11,0]}}
  #|{"textrec":{"g":342,"r":[290,51,14,13,-1,-10,0]}}
  #|{"textrec":{"g":343,"r":[305,51,17,16,-1,-13,0]}}
  #|{"textrec":{"g":344,"r":[323,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":345,"r":[340,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":346,"r":[357,51,15,17,-1,-14,0]}}
  #|{"textrec":{"g":347,"r":[373,51,14,14,-1,-11,0]}}
  #|{"textrec":{"g":348,"r":[388,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":349,"r":[405,51,16,16,0,-13,0]}}
  #|{"textrec":{"s":[14,400,0,"已停用，Slack 连接已断开"],"r":[0,1,13.891050583657588,350,1,1,13.891050583657588,351,2,1,13.891050583657588,55,3,1,12.681712062256807,50,4,1,8.7705078125,352,5,1,3.390625,353,6,1,7.57421875,57,7,1,7.68359375,354,8,1,7.451171875,355,9,1,3.787109375,-1,10,1,13.891050583657588,356,11,1,13.891050583657588,357,12,1,13.891050583657602,350,13,1,13.891050583657602,358,14,1,13.891050583657602,97]}}
  #|{"textrec":{"g":350,"r":[422,51,14,14,0,-12,0]}}
  #|{"textrec":{"g":351,"r":[437,51,15,16,-1,-13,0]}}
  #|{"textrec":{"g":352,"r":[453,51,11,14,-1,-12,0]}}
  #|{"textrec":{"g":353,"r":[465,51,4,13,0,-12,0]}}
  #|{"textrec":{"g":354,"r":[470,51,10,11,-1,-9,0]}}
  #|{"textrec":{"g":355,"r":[481,51,9,13,0,-12,0]}}
  #|{"textrec":{"g":356,"r":[491,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":357,"r":[508,51,15,16,-1,-13,0]}}
  #|{"textrec":{"g":358,"r":[524,51,16,16,-1,-13,0]}}
  #|{"textrec":{"s":[11,400,0,"已停用"],"r":[0,1,10.93579766536965,359,1,1,10.93579766536965,360,2,1,10.935797665369652,361]}}
  #|{"textrec":{"g":359,"r":[541,51,13,12,-1,-10,0]}}
  #|{"textrec":{"g":360,"r":[555,51,12,13,-1,-10,0]}}
  #|{"textrec":{"g":361,"r":[568,51,12,12,-1,-10,0]}}
  #|{"textrec":{"s":[17,700,0,"会话方式"],"r":[0,1,16.851167315175097,362,1,1,16.851167315175097,363,2,1,16.851167315175097,364,3,1,16.851167315175097,365]}}
  #|{"textrec":{"s":[15,600,0,"每个 thread 一个会话"],"r":[0,1,14.883268482490273,366,1,1,14.883268482490273,367,2,1,3.761730194091797,-1,3,1,5.683325529098511,190,4,1,9.00644838809967,368,5,1,5.895114541053772,174,6,1,8.517318964004517,85,7,1,8.40147078037262,303,8,1,9.332013130187988,192,9,1,3.761730194091797,-1,10,1,14.883268482490266,369,11,1,14.88326848249028,367,12,1,14.88326848249028,318,13,1,14.88326848249028,319]}}
  #|{"textrec":{"s":[15,600,0,"所有 thread 共用一个会话"],"r":[0,1,14.883268482490273,370,1,1,14.883268482490273,371,2,1,3.761730194091797,-1,3,1,5.683325529098511,190,4,1,9.00644838809967,368,5,1,5.895114541053772,174,6,1,8.517318964004517,85,7,1,8.40147078037262,303,8,1,9.332013130187988,192,9,1,3.761730194091797,-1,10,1,14.883268482490266,372,11,1,14.88326848249028,373,12,1,14.88326848249028,369,13,1,14.88326848249028,367,14,1,14.88326848249028,318,15,1,14.88326848249028,319]}}
  #|{"textrec":{"s":[13,400,0,"它看到的所有 thread 都进入同一个会话，适合长期值守的助手"],"r":[0,1,12.898832684824903,269,1,1,12.898832684824903,374,2,1,12.898832684824903,375,3,1,12.898832684824903,5,4,1,12.898832684824896,235,5,1,12.898832684824896,149,6,1,3.580078125,-1,7,1,4.646484375,82,8,1,7.57275390625,267,9,1,4.77978515625,8,10,1,7.25537109375,14,11,1,7.0966796875,12,12,1,7.9091796875,214,13,1,3.580078125,-1,14,1,12.898832684824896,279,15,1,12.898832684824896,280,16,1,12.898832684824896,242,17,1,12.898832684824896,376,18,1,12.898832684824896,273,19,1,12.898832684824896,274,20,1,12.898832684824896,209,21,1,12.898832684824896,210,22,1,13.075875486381335,275,23,1,12.898832684824896,377,24,1,12.898832684824924,378,25,1,12.898832684824924,379,26,1,12.898832684824924,380,27,1,12.898832684824924,381,28,1,12.898832684824924,382,29,1,12.898832684824924,5,30,1,12.898832684824924,383,31,1,12.898832684824924,384]}}
  #|{"textrec":{"s":[14,600,0,"取消"],"r":[0,1,13.891050583657588,385,1,1,13.891050583657588,386]}}
  #|{"textrec":{"m":[14,600,0],"r":[13.53515625,2.953125,20]}}
  #|{"textrec":{"s":[14,600,0,"确认更改"],"r":[0,1,13.891050583657588,387,1,1,13.891050583657588,388,2,1,13.891050583657588,389,3,1,13.891050583657588,390]}}
  #|{"textrec":{"g":362,"r":[581,51,19,18,-1,-15,0]}}
  #|{"textrec":{"g":363,"r":[601,51,19,18,-1,-15,0]}}
  #|{"textrec":{"g":364,"r":[621,51,18,18,-1,-15,0]}}
  #|{"textrec":{"g":365,"r":[640,51,18,18,-1,-15,0]}}
  #|{"textrec":{"g":366,"r":[659,51,17,17,-1,-14,0]}}
  #|{"textrec":{"g":367,"r":[677,51,17,16,-1,-13,0]}}
  #|{"textrec":{"g":368,"r":[695,51,10,14,0,-13,0]}}
  #|{"textrec":{"g":369,"r":[706,51,16,5,-1,-8,0]}}
  #|{"textrec":{"g":370,"r":[723,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":371,"r":[740,51,16,17,-1,-14,0]}}
  #|{"textrec":{"g":372,"r":[757,51,16,17,-1,-14,0]}}
  #|{"textrec":{"g":373,"r":[774,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":374,"r":[791,51,14,15,-1,-12,0]}}
  #|{"textrec":{"g":375,"r":[806,51,14,15,-1,-12,0]}}
  #|{"textrec":{"g":149,"r":[821,51,14,15,-1,-12,0]}}
  #|{"textrec":{"g":376,"r":[836,51,13,14,0,-11,0]}}
  #|{"textrec":{"g":377,"r":[850,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":378,"r":[866,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":379,"r":[882,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":380,"r":[898,51,14,15,-1,-12,0]}}
  #|{"textrec":{"g":381,"r":[913,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":382,"r":[929,51,14,15,-1,-12,0]}}
  #|{"textrec":{"g":383,"r":[944,51,14,15,-1,-12,0]}}
  #|{"textrec":{"g":384,"r":[959,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":385,"r":[975,51,16,15,-1,-12,0]}}
  #|{"textrec":{"g":386,"r":[992,51,15,16,-1,-13,0]}}
  #|{"textrec":{"g":387,"r":[1008,51,15,16,-1,-13,0]}}
  #|{"textrec":{"g":388,"r":[1024,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":389,"r":[1041,51,16,15,-1,-12,0]}}
  #|{"textrec":{"g":390,"r":[1058,51,16,16,-1,-13,0]}}
  #|{"textrec":{"s":[14,600,0,"仅在被 @ 时唤醒"],"r":[0,1,13.891050583657588,391,1,1,13.891050583657588,392,2,1,13.891050583657588,393,3,1,3.5793075561523438,-1,4,1,12.781262159347534,394,5,1,3.5793075561523438,-1,6,1,13.891050583657588,395,7,1,13.891050583657588,396,8,1,13.891050583657588,397]}}
  #|{"textrec":{"s":[13,400,0,"被 @ 的 thread 中，后续回复无需再 @。"],"r":[0,1,12.898832684824903,398,1,1,3.580078125,-1,2,1,11.857421875,78,3,1,3.580078125,-1,4,1,12.898832684824903,5,5,1,3.580078125,-1,6,1,4.646484375,82,7,1,7.57275390625,267,8,1,4.77978515625,8,9,1,7.25537109375,14,10,1,7.0966796875,12,11,1,7.9091796875,214,12,1,3.580078125,-1,13,1,12.89883268482491,268,14,1,13.075875486381321,275,15,1,12.89883268482491,277,16,1,12.898832684824896,278,17,1,12.898832684824896,399,18,1,12.898832684824896,400,19,1,12.898832684824896,286,20,1,12.898832684824896,142,21,1,12.898832684824896,401,22,1,3.580078125,-1,23,1,11.857421875,78,24,1,6.575875486381335,243]}}
  #|{"textrec":{"s":[13,600,0,"更改后"],"r":[0,1,12.898832684824903,402,1,1,12.898832684824903,403,2,1,12.898832684824903,404]}}
  #|{"textrec":{"m":[13,600,0],"r":[12.568359375,2.7421875,18]}}
  #|{"textrec":{"s":[13,400,0,"· 此后它收到的消息都将进入同一个会话；现有各 thread 的会话不再接收新消息，包括这些 thread 中的回复。记录会保留。"],"r":[0,1,6.22854520422212,211,1,1,3.580078124999999,-1,2,1,12.898832684824903,237,3,1,12.8988326848249,277,4,1,12.898832684824903,269,5,1,12.898832684824903,405,6,1,12.898832684824896,375,7,1,12.898832684824896,5,8,1,12.898832684824896,151,9,1,12.898832684824896,152,10,1,12.898832684824896,279,11,1,12.898832684824896,406,12,1,12.898832684824896,280,13,1,12.898832684824896,242,14,1,12.898832684824896,376,15,1,12.898832684824896,273,16,1,12.898832684824896,274,17,1,12.898832684824896,209,18,1,12.898832684824896,210,19,1,13.075875486381335,290,20,1,12.898832684824896,407,21,1,12.898832684824924,149,22,1,12.898832684824924,408,23,1,3.580078125,-1,24,1,4.646484375,82,25,1,7.57275390625,267,26,1,4.77978515625,8,27,1,7.25537109375,14,28,1,7.0966796875,12,29,1,7.9091796875,214,30,1,3.580078125,-1,31,1,12.898832684824924,5,32,1,12.898832684824924,209,33,1,12.898832684824924,210,34,1,12.898832684824924,409,35,1,12.898832684824924,401,36,1,12.898832684824924,239,37,1,12.898832684824924,405,38,1,12.898832684824924,150,39,1,12.898832684824924,151,40,1,12.898832684824924,152,41,1,13.075875486381335,275,42,1,12.898832684824924,410,43,1,12.898832684824924,411,44,1,12.898832684824924,412,45,1,12.898832684824924,413,46,1,3.580078125,-1,47,1,4.646484375,82,48,1,7.57275390625,267,49,1,4.77978515625,8,50,1,7.25537109375,14,51,1,7.0966796875,12,52,1,7.9091796875,214,53,1,3.580078125,-1,54,1,12.898832684824924,268,55,1,12.898832684824924,5,56,1,12.898832684824924,399,57,1,12.898832684824924,400,58,1,13.075875486381278,243,59,1,12.898832684824924,414,60,1,12.898832684824924,415,61,1,12.898832684824924,209,62,1,12.898832684824924,416,63,1,12.898832684824924,417,64,1,6.575875486381278,243]}}
  #|{"textrec":{"s":[13,400,0,"· 下一条消息将开始新的单会话；也可在切换后选择已有会话。"],"r":[0,1,6.22854520422212,211,1,1,3.580078124999999,-1,2,1,12.898832684824903,418,3,1,12.8988326848249,273,4,1,12.898832684824903,419,5,1,12.898832684824903,151,6,1,12.898832684824896,152,7,1,12.898832684824896,406,8,1,12.898832684824896,271,9,1,12.898832684824896,298,10,1,12.898832684824896,150,11,1,12.898832684824896,5,12,1,12.898832684824896,420,13,1,12.898832684824896,209,14,1,12.898832684824896,210,15,1,13.075875486381335,290,16,1,12.898832684824896,421,17,1,12.898832684824896,422,18,1,12.898832684824896,1,19,1,12.898832684824896,423,20,1,12.898832684824896,424,21,1,12.898832684824924,277,22,1,12.898832684824924,425,23,1,12.898832684824924,426,24,1,12.898832684824924,427,25,1,12.898832684824924,149,26,1,12.898832684824924,209,27,1,12.898832684824924,210,28,1,6.575875486381335,243]}}
  #|{"textrec":{"s":[14,600,0,"改为单会话"],"r":[0,1,13.891050583657588,390,1,1,13.891050583657588,428,2,1,13.891050583657588,429,3,1,13.891050583657588,430,4,1,13.891050583657588,431]}}
  #|{"textrec":{"g":391,"r":[1075,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":392,"r":[1092,51,15,16,-1,-13,0]}}
  #|{"textrec":{"g":393,"r":[1108,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":394,"r":[1125,51,15,14,-1,-11,0]}}
  #|{"textrec":{"g":395,"r":[1141,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":396,"r":[1158,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":397,"r":[1175,51,16,15,-1,-12,0]}}
  #|{"textrec":{"g":398,"r":[1192,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":399,"r":[1208,51,13,14,0,-11,0]}}
  #|{"textrec":{"g":400,"r":[1222,51,14,15,-1,-12,0]}}
  #|{"textrec":{"g":401,"r":[1237,51,15,14,-1,-11,0]}}
  #|{"textrec":{"g":402,"r":[1253,51,15,14,-1,-11,0]}}
  #|{"textrec":{"g":403,"r":[1269,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":404,"r":[1285,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":405,"r":[1301,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":406,"r":[1317,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":407,"r":[1333,51,15,14,-1,-11,0]}}
  #|{"textrec":{"g":408,"r":[1349,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":409,"r":[1365,51,15,14,-1,-11,0]}}
  #|{"textrec":{"g":410,"r":[1381,51,14,15,-1,-12,0]}}
  #|{"textrec":{"g":411,"r":[1396,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":412,"r":[1412,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":413,"r":[1428,51,14,14,-1,-12,0]}}
  #|{"textrec":{"g":414,"r":[1443,51,15,14,-1,-12,0]}}
  #|{"textrec":{"g":415,"r":[1459,51,14,14,-1,-11,0]}}
  #|{"textrec":{"g":416,"r":[1474,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":417,"r":[1490,51,14,15,-1,-12,0]}}
  #|{"textrec":{"g":418,"r":[1505,51,14,14,-1,-11,0]}}
  #|{"textrec":{"g":419,"r":[1520,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":420,"r":[1536,51,14,15,-1,-12,0]}}
  #|{"textrec":{"g":421,"r":[1551,51,15,14,-1,-12,0]}}
  #|{"textrec":{"g":422,"r":[1567,51,14,14,-1,-11,0]}}
  #|{"textrec":{"g":423,"r":[1582,51,14,15,-1,-12,0]}}
  #|{"textrec":{"g":424,"r":[1597,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":425,"r":[1613,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":426,"r":[1629,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":427,"r":[1645,51,13,13,0,-11,0]}}
  #|{"textrec":{"g":428,"r":[1659,51,15,16,-1,-13,0]}}
  #|{"textrec":{"g":429,"r":[1675,51,15,16,-1,-13,0]}}
  #|{"textrec":{"g":430,"r":[1691,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":431,"r":[1708,51,16,16,-1,-13,0]}}
  #|{"textrec":{"s":[14,400,0,"已更改会话方式"],"r":[0,1,13.891050583657588,350,1,1,13.891050583657588,432,2,1,13.891050583657588,433,3,1,13.891050583657588,434,4,1,13.891050583657588,435,5,1,13.891050583657588,436,6,1,13.891050583657588,437]}}
  #|{"textrec":{"ib":["8c8c0c76062a8613",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"g":432,"r":[1725,51,16,15,-1,-12,0]}}
  #|{"textrec":{"g":433,"r":[1742,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":434,"r":[1759,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":435,"r":[1776,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":436,"r":[1793,51,15,16,-1,-13,0]}}
  #|{"textrec":{"g":437,"r":[1809,51,15,16,-1,-13,0]}}
  #|{"textrec":{"ib":["2bebfda158dabefd",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"s":[15,400,0,"所有 thread 共用一个会话"],"r":[0,1,14.883268482490273,344,1,1,14.883268482490273,438,2,1,3.984375,-1,3,1,5.21484375,101,4,1,8.59130859375,262,5,1,5.36865234375,89,6,1,8.22509765625,95,7,1,8.0419921875,93,8,1,8.9794921875,263,9,1,3.984375,-1,10,1,14.883268482490266,439,11,1,14.88326848249028,115,12,1,14.88326848249028,264,13,1,14.88326848249028,261,14,1,14.88326848249028,265,15,1,14.88326848249028,266]}}
  #|{"textrec":{"s":[13,400,0,"它看到的所有 thread 都进入同一个会话，适合长期值守的助手仅在被 @ 时唤醒。"],"r":[0,1,12.898832684824903,269,1,1,12.898832684824903,374,2,1,12.898832684824903,375,3,1,12.898832684824903,5,4,1,12.898832684824896,235,5,1,12.898832684824896,149,6,1,3.580078125,-1,7,1,4.646484375,82,8,1,7.57275390625,267,9,1,4.77978515625,8,10,1,7.25537109375,14,11,1,7.0966796875,12,12,1,7.9091796875,214,13,1,3.580078125,-1,14,1,12.898832684824896,279,15,1,12.898832684824896,280,16,1,12.898832684824896,242,17,1,12.898832684824896,376,18,1,12.898832684824896,273,19,1,12.898832684824896,274,20,1,12.898832684824896,209,21,1,12.898832684824896,210,22,1,13.075875486381335,275,23,1,12.898832684824896,377,24,1,12.898832684824924,378,25,1,12.898832684824924,379,26,1,12.898832684824924,380,27,1,12.898832684824924,381,28,1,12.898832684824924,382,29,1,12.898832684824924,5,30,1,12.898832684824924,383,31,1,12.898832684824924,384,32,1,12.898832684824924,440,33,1,12.898832684824924,1,34,1,12.898832684824924,398,35,1,3.580078125,-1,36,1,11.857421875,78,37,1,3.580078125,-1,38,1,12.898832684824924,153,39,1,12.898832684824924,441,40,1,12.898832684824924,442,41,1,6.575875486381335,243]}}
  #|{"textrec":{"s":[13,400,0,"当前"],"r":[0,1,12.898832684824903,443,1,1,12.898832684824903,444]}}
  #|{"textrec":{"s":[15,400,0,"暂无会话；下一条消息将开始新会话。"],"r":[0,1,14.883268482490273,320,1,1,14.883268482490273,321,2,1,14.883268482490273,265,3,1,14.883268482490273,266,4,1,15.08754863813229,445,5,1,14.88326848249028,128,6,1,14.88326848249028,264,7,1,14.88326848249028,446,8,1,14.88326848249028,447,9,1,14.88326848249028,448,10,1,14.88326848249028,449,11,1,14.88326848249028,328,12,1,14.88326848249028,329,13,1,14.88326848249028,159,14,1,14.88326848249028,265,15,1,14.88326848249028,266,16,1,7.58754863813229,322]}}
  #|{"textrec":{"g":438,"r":[1825,51,16,17,-1,-14,0]}}
  #|{"textrec":{"g":439,"r":[1842,51,16,17,-1,-14,0]}}
  #|{"textrec":{"g":440,"r":[1859,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":441,"r":[1875,51,14,15,0,-12,0]}}
  #|{"textrec":{"g":442,"r":[1890,51,15,14,-1,-11,0]}}
  #|{"textrec":{"g":443,"r":[1906,51,13,15,0,-12,0]}}
  #|{"textrec":{"g":444,"r":[1920,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":445,"r":[1936,51,5,12,1,-10,0]}}
  #|{"textrec":{"g":446,"r":[1942,51,16,17,-1,-14,0]}}
  #|{"textrec":{"g":447,"r":[1959,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":448,"r":[1976,51,16,17,-1,-14,0]}}
  #|{"textrec":{"g":449,"r":[1993,51,16,16,-1,-13,0]}}
  #|{"textrec":{"s":[15,400,0,"启用"],"r":[0,1,14.883268482490273,450,1,1,14.883268482490273,115]}}
  #|{"textrec":{"g":450,"r":[2010,51,15,17,-1,-14,0]}}
  #|{"textrec":{"s":[17,700,0,"Slack token"],"r":[0,1,11.044189453125,451,1,1,4.58203125,452,2,1,9.591552734375,453,3,1,9.55419921875,454,4,1,9.790771484375,455,5,1,3.951171875,-1,6,1,6.5513916015625,456,7,1,10.0709228515625,457,8,1,9.52099609375,455,9,1,9.5126953125,330,10,1,10.230712890625,458]}}
  #|{"textrec":{"s":[12,400,0,"可仅更换其中一个，留空的一项将沿用已保存的值。"],"r":[0,1,11.918287937743191,459,1,1,11.918287937743191,460,2,1,11.918287937743195,461,3,1,11.918287937743187,462,4,1,11.918287937743187,463,5,1,11.918287937743187,464,6,1,11.918287937743187,465,7,1,11.918287937743187,466,8,1,12.081712062256813,467,9,1,11.918287937743187,468,10,1,11.918287937743187,469,11,1,11.918287937743202,470,12,1,11.918287937743202,465,13,1,11.918287937743202,471,14,1,11.918287937743202,340,15,1,11.918287937743202,472,16,1,11.918287937743202,473,17,1,11.918287937743202,474,18,1,11.918287937743202,475,19,1,11.918287937743202,476,20,1,11.918287937743202,470,21,1,11.918287937743202,477,22,1,6.081712062256827,478]}}
  #|{"textrec":{"s":[13,600,0,"App-Level Token"],"r":[0,1,9.165990829467773,479,1,1,8.159896612167358,480,2,1,8.159896612167358,480,3,1,6.160183429718018,481,4,1,7.3685595989227295,482,5,1,7.351526618003845,483,6,1,7.08481502532959,484,7,1,7.456791400909424,483,8,1,3.5576319694519043,485,9,1,3.3871192932128906,-1,10,1,7.765498876571655,486,11,1,7.2270050048828125,487,12,1,7.273967742919922,488,13,1,7.404953241348267,483,14,1,7.869065165519714,489]}}
  #|{"textrec":{"s":[13,600,0,"Bot Token"],"r":[0,1,8.765251636505127,490,1,1,7.841670751571655,487,2,1,5.052501916885376,491,3,1,3.3871192932128906,-1,4,1,7.765498876571655,486,5,1,7.2270050048828125,487,6,1,7.273967742919922,488,7,1,7.404953241348267,483,8,1,7.869065165519714,489]}}
  #|{"textrec":{"s":[14,600,0,"保存并连接"],"r":[0,1,13.891050583657588,492,1,1,13.891050583657588,493,2,1,13.891050583657588,494,3,1,13.891050583657588,495,4,1,13.891050583657588,496]}}
  #|{"textrec":{"g":451,"r":[2026,51,13,16,-1,-14,0]}}
  #|{"textrec":{"g":452,"r":[2040,51,5,15,0,-14,0]}}
  #|{"textrec":{"g":453,"r":[0,70,11,13,-1,-11,0]}}
  #|{"textrec":{"g":454,"r":[12,70,12,13,-1,-11,0]}}
  #|{"textrec":{"g":455,"r":[25,70,11,15,0,-14,0]}}
  #|{"textrec":{"g":456,"r":[37,70,9,15,-1,-13,0]}}
  #|{"textrec":{"g":457,"r":[47,70,12,13,-1,-11,0]}}
  #|{"textrec":{"g":458,"r":[60,70,11,12,0,-11,0]}}
  #|{"textrec":{"g":459,"r":[72,70,14,13,-1,-10,0]}}
  #|{"textrec":{"g":460,"r":[87,70,14,14,-1,-11,0]}}
  #|{"textrec":{"g":461,"r":[102,70,14,14,-1,-11,0]}}
  #|{"textrec":{"g":462,"r":[117,70,14,14,-1,-11,0]}}
  #|{"textrec":{"g":463,"r":[132,70,14,14,-1,-11,0]}}
  #|{"textrec":{"g":464,"r":[147,70,12,14,0,-11,0]}}
  #|{"textrec":{"g":465,"r":[160,70,14,4,-1,-6,0]}}
  #|{"textrec":{"g":466,"r":[175,70,14,14,-1,-11,0]}}
  #|{"textrec":{"g":467,"r":[190,70,5,6,0,-3,0]}}
  #|{"textrec":{"g":468,"r":[196,70,13,14,-1,-11,0]}}
  #|{"textrec":{"g":469,"r":[210,70,13,13,-1,-11,0]}}
  #|{"textrec":{"g":470,"r":[224,70,13,14,-1,-11,0]}}
  #|{"textrec":{"g":471,"r":[238,70,14,14,-1,-11,0]}}
  #|{"textrec":{"g":472,"r":[253,70,14,14,-1,-11,0]}}
  #|{"textrec":{"g":473,"r":[268,70,13,14,-1,-11,0]}}
  #|{"textrec":{"g":474,"r":[282,70,13,12,0,-10,0]}}
  #|{"textrec":{"g":475,"r":[296,70,14,14,-1,-11,0]}}
  #|{"textrec":{"g":476,"r":[311,70,14,14,-1,-11,0]}}
  #|{"textrec":{"g":477,"r":[326,70,14,14,-1,-11,0]}}
  #|{"textrec":{"g":478,"r":[341,70,6,6,0,-3,0]}}
  #|{"textrec":{"g":479,"r":[348,70,11,12,-1,-11,0]}}
  #|{"textrec":{"g":480,"r":[360,70,10,13,-1,-9,0]}}
  #|{"textrec":{"g":481,"r":[371,70,8,5,-1,-6,0]}}
  #|{"textrec":{"g":482,"r":[380,70,8,12,0,-11,0]}}
  #|{"textrec":{"g":483,"r":[389,70,10,11,-1,-9,0]}}
  #|{"textrec":{"g":484,"r":[400,70,10,9,-1,-8,0]}}
  #|{"textrec":{"g":485,"r":[411,70,4,12,0,-11,0]}}
  #|{"textrec":{"g":486,"r":[416,70,10,12,-1,-11,0]}}
  #|{"textrec":{"g":487,"r":[427,70,10,11,-1,-9,0]}}
  #|{"textrec":{"g":488,"r":[438,70,9,12,0,-11,0]}}
  #|{"textrec":{"g":489,"r":[448,70,10,10,-1,-9,0]}}
  #|{"textrec":{"s":[15,400,0,"xapp-…"],"r":[0,1,7.6318359375,497,1,1,8.0419921875,93,2,1,8.9208984375,92,3,1,8.9208984375,92,4,1,6.8408203125,204,5,1,11.8359375,498]}}
  #|{"textrec":{"g":497,"r":[459,70,10,10,-1,-9,0]}}
  #|{"textrec":{"g":498,"r":[470,70,12,5,0,-3,0]}}
  #|{"textrec":{"g":490,"r":[483,70,10,12,0,-11,0]}}
  #|{"textrec":{"g":491,"r":[494,70,7,12,-1,-10,0]}}
  #|{"textrec":{"s":[15,400,0,"xoxb-…"],"r":[0,1,7.44873046875,497,1,1,8.26171875,88,2,1,7.44873046875,497,3,1,8.9794921875,162,4,1,6.8408203125,204,5,1,11.8359375,498]}}
  #|{"textrec":{"g":162,"r":[502,70,10,15,0,-13,0]}}
  #|{"textrec":{"g":492,"r":[513,70,16,16,-1,-13,0]}}
  #|{"textrec":{"g":493,"r":[530,70,16,16,-1,-13,0]}}
  #|{"textrec":{"g":494,"r":[547,70,15,16,-1,-13,0]}}
  #|{"textrec":{"g":495,"r":[563,70,16,16,-1,-13,0]}}
  #|{"textrec":{"g":496,"r":[580,70,16,16,-1,-13,0]}}
  #|{"textrec":{"s":[15,400,0,"••••••••••••••••••••"],"r":[0,1,6.8408203125,499,1,1,6.8408203125,499,2,1,6.8408203125,499,3,1,6.8408203125,499,4,1,6.8408203125,499,5,1,6.8408203125,499,6,1,6.8408203125,499,7,1,6.8408203125,499,8,1,6.8408203125,499,9,1,6.8408203125,499,10,1,6.8408203125,499,11,1,6.8408203125,499,12,1,6.8408203125,499,13,1,6.8408203125,499,14,1,6.8408203125,499,15,1,6.8408203125,499,16,1,6.8408203125,499,17,1,6.8408203125,499,18,1,6.8408203125,499,19,1,6.8408203125,499]}}
  #|{"textrec":{"g":499,"r":[597,70,6,6,1,-7,0]}}
  #|{"textrec":{"s":[15,400,0,"••••••••••••••••••"],"r":[0,1,6.8408203125,499,1,1,6.8408203125,499,2,1,6.8408203125,499,3,1,6.8408203125,499,4,1,6.8408203125,499,5,1,6.8408203125,499,6,1,6.8408203125,499,7,1,6.8408203125,499,8,1,6.8408203125,499,9,1,6.8408203125,499,10,1,6.8408203125,499,11,1,6.8408203125,499,12,1,6.8408203125,499,13,1,6.8408203125,499,14,1,6.8408203125,499,15,1,6.8408203125,499,16,1,6.8408203125,499,17,1,6.8408203125,499]}}
  #|{"textrec":{"ib":["ccd649eca3bf4dd2",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["b43f4f6b8a048c9c",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["a166358366a2c7c6",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["e5005926b33d7d54",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["fed6b749074aab0c",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["8160409f90c92b7c",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["f17e87b528e1c822",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["59961bf9c5ad7788",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["cf9567e1f15ab3c5",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["70475e3728fbc435",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["360e0c082436cbc7",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["d3a1d1342969b59b",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["bbd448ff28fe936d",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["21d2ac9a344fcb61",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["178ccce5f296f519",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["71a6b38fbb6493bb",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["6672b542a3215b57",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["546aea41996968b5",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["469c155b74082082",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["025f9b0d9b49aeb7",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["8303ef222fd366b6",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["2e7db177a7ee20d1",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["faf3e0666bde0f15",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["966a3e3fd25fca1d",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"s":[17,700,0,"删除「e2e-080726」？"],"r":[0,1,16.851167315175097,500,1,1,25.351167315175097,501,2,1,6.366731517509727,502,3,1,9.782470703125,330,4,1,10.479736328125007,331,5,1,9.76171875,330,6,1,7.802734375,332,7,1,11.2060546875,333,8,1,11.322265625,334,9,1,10.99853515625,333,10,1,9.6787109375,335,11,1,10.50048828125,331,12,1,11.189453125,336,13,1,8.194066147859928,503,14,1,8.582684824902714,504]}}
  #|{"textrec":{"s":[14,400,0,"Slack 连接将断开。Slack 中的 app 需要你手动删除。"],"r":[0,1,8.7705078125,352,1,1,3.390625,353,2,1,7.57421875,57,3,1,7.68359375,354,4,1,7.451171875,355,5,1,3.787109375,-1,6,1,13.891050583657588,356,7,1,13.891050583657588,357,8,1,13.891050583657588,505,9,1,13.891050583657588,358,10,1,13.891050583657588,97,11,1,14.081712062256813,506,12,1,8.7705078125,352,13,1,3.390625,353,14,1,7.57421875,57,15,1,7.68359375,354,16,1,7.451171875,355,17,1,3.787109375,-1,18,1,13.891050583657574,507,19,1,13.891050583657602,56,20,1,3.787109375,-1,21,1,7.57421875,57,22,1,8.39453125,508,23,1,8.39453125,508,24,1,3.787109375,-1,25,1,13.891050583657602,509,26,1,13.891050583657602,510,27,1,13.891050583657602,48,28,1,13.891050583657602,511,29,1,13.891050583657602,512,30,1,13.891050583657602,513,31,1,13.891050583657602,514,32,1,7.081712062256827,506]}}
  #|{"textrec":{"s":[14,600,0,"删除连接"],"r":[0,1,13.891050583657588,515,1,1,13.891050583657588,516,2,1,13.891050583657588,495,3,1,13.891050583657588,496]}}
  #|{"textrec":{"g":500,"r":[604,70,18,18,-1,-15,0]}}
  #|{"textrec":{"g":501,"r":[623,70,18,18,0,-15,0]}}
  #|{"textrec":{"g":502,"r":[642,70,9,13,-1.8333333333333304,-15,0]}}
  #|{"textrec":{"g":503,"r":[652,70,9,13,-1,-10,0]}}
  #|{"textrec":{"g":504,"r":[662,70,10,16,-1,-14,0]}}
  #|{"textrec":{"g":505,"r":[673,70,16,16,-1,-13,0]}}
  #|{"textrec":{"g":506,"r":[690,70,6,6,0,-3,0]}}
  #|{"textrec":{"g":507,"r":[697,70,14,16,0,-13,0]}}
  #|{"textrec":{"g":508,"r":[712,70,9,13,0,-9,0]}}
  #|{"textrec":{"g":509,"r":[722,70,15,15,-1,-12,0]}}
  #|{"textrec":{"g":510,"r":[738,70,16,15,-1,-12,0]}}
  #|{"textrec":{"g":511,"r":[755,70,15,16,-1,-13,0]}}
  #|{"textrec":{"g":512,"r":[771,70,15,16,-1,-13,0]}}
  #|{"textrec":{"g":513,"r":[787,70,15,16,-1,-13,0]}}
  #|{"textrec":{"g":514,"r":[803,70,15,15,0,-12,0]}}
  #|{"textrec":{"g":515,"r":[819,70,15,16,-1,-13,0]}}
  #|{"textrec":{"g":516,"r":[835,70,16,15,-1,-12,0]}}
  #|{"textrec":{"s":[12,400,0,"已停用"],"r":[0,1,11.918287937743191,474,1,1,11.918287937743191,517,2,1,11.918287937743195,473]}}
  #|{"textrec":{"s":[13,400,0,"单会话 · @ 唤醒 · Claude Code · Sonnet 5.5"],"r":[0,1,12.898832684824903,420,1,1,12.898832684824903,209,2,1,12.898832684824903,210,3,1,3.580078125,-1,4,1,6.228545204222122,211,5,1,3.580078125,-1,6,1,11.857421875,78,7,1,3.580078125,-1,8,1,12.898832684824896,441,9,1,12.898832684824896,442,10,1,3.580078125,-1,11,1,6.228545204222115,211,12,1,3.580078125,-1,13,1,9.2294921875,212,14,1,3.2119140625,76,15,1,7.0966796875,12,16,1,7.50927734375,213,17,1,7.9091796875,214,18,1,7.3505859375,14,19,1,3.580078125,-1,20,1,9.2294921875,212,21,1,7.6044921875,7,22,1,7.9091796875,214,23,1,7.3505859375,14,24,1,3.580078125,-1,25,1,6.228545204222115,211,26,1,3.580078125,-1,27,1,8.20751953125,215,28,1,7.6044921875,7,29,1,7.50927734375,216,30,1,7.50927734375,216,31,1,7.3505859375,14,32,1,4.646484375,82,33,1,3.580078125,-1,34,1,7.73779296875,217,35,1,3.354736328125,81,36,1,7.753662109375028,217]}}
  #|{"textrec":{"s":[13,400,0,"单会话 · @ 唤醒 · Claude Code · S…"],"r":[0,1,12.898832684824903,420,1,1,12.898832684824903,209,2,1,12.898832684824903,210,3,1,3.580078125,-1,4,1,6.228545204222122,211,5,1,3.580078125,-1,6,1,11.857421875,78,7,1,3.580078125,-1,8,1,12.898832684824896,441,9,1,12.898832684824896,442,10,1,3.580078125,-1,11,1,6.228545204222115,211,12,1,3.580078125,-1,13,1,9.2294921875,212,14,1,3.2119140625,76,15,1,7.0966796875,12,16,1,7.50927734375,213,17,1,7.9091796875,214,18,1,7.3505859375,14,19,1,3.580078125,-1,20,1,9.2294921875,212,21,1,7.6044921875,7,22,1,7.9091796875,214,23,1,7.3505859375,14,24,1,3.580078125,-1,25,1,6.228545204222115,211,26,1,3.580078125,-1,27,1,8.20751953125,215,28,1,10.384765625,218]}}
  #|{"textrec":{"g":517,"r":[852,70,13,14,-1,-11,0]}}
  #|{"textrec":{"s":[14,400,0,"连接不存在"],"r":[0,1,13.891050583657588,356,1,1,13.891050583657588,357,2,1,13.891050583657588,518,3,1,13.891050583657588,519,4,1,13.891050583657588,182]}}
  #|{"textrec":{"s":[14,400,0,"已删除连接"],"r":[0,1,13.891050583657588,350,1,1,13.891050583657588,513,2,1,13.891050583657588,514,3,1,13.891050583657588,356,4,1,13.891050583657588,357]}}
  #|{"textrec":{"s":[15,400,0,"此机器上暂无连接"],"r":[0,1,14.883268482490273,520,1,1,14.883268482490273,132,2,1,14.883268482490273,521,3,1,14.883268482490273,522,4,1,14.88326848249028,320,5,1,14.88326848249028,321,6,1,14.88326848249028,104,7,1,14.88326848249028,105]}}
  #|{"textrec":{"s":[14,400,0,"连接是用户访问 still.fail 的入口，例如一个 Slack app。每个连接运行在一台 station 上，并绑定一个模型。"],"r":[0,1,13.891050583657588,356,1,1,13.891050583657588,357,2,1,13.891050583657588,52,3,1,13.891050583657588,55,4,1,13.891050583657588,523,5,1,13.891050583657588,524,6,1,13.891050583657588,525,7,1,3.787109375,-1,8,1,7.1435546875,526,9,1,4.9013671875,61,10,1,3.30859375,527,11,1,3.390625,353,12,1,3.390625,353,13,1,3.80078125,528,14,1,4.607421874999986,529,15,1,7.4716796875,57,16,1,3.30859375,527,17,1,3.390625,353,18,1,3.787109375,-1,19,1,13.891050583657602,56,20,1,13.891050583657602,530,21,1,13.891050583657602,531,22,1,14.081712062256798,50,23,1,13.891050583657574,532,24,1,13.891050583657602,533,25,1,13.891050583657602,534,26,1,13.891050583657602,184,27,1,3.787109375,-1,28,1,8.7705078125,352,29,1,3.390625,353,30,1,7.57421875,57,31,1,7.68359375,354,32,1,7.451171875,355,33,1,3.787109375,-1,34,1,7.57421875,57,35,1,8.39453125,508,36,1,8.39453125,508,37,1,14.081712062256827,506,38,1,13.891050583657602,535,39,1,13.891050583657602,184,40,1,13.891050583657602,356,41,1,13.891050583657602,357,42,1,13.891050583657602,536,43,1,13.891050583657602,537,44,1,13.891050583657602,182,45,1,13.891050583657602,534,46,1,13.891050583657602,538,47,1,3.787109375,-1,48,1,7.1435546875,526,49,1,4.9013671875,61,50,1,7.57421875,57,51,1,4.935546875,61,52,1,3.30859375,527,53,1,8.12109375,539,54,1,8.018554687499943,60,55,1,3.787109375,-1,56,1,13.891050583657602,540,57,1,14.08171206225677,50,58,1,13.891050583657602,541,59,1,13.891050583657602,542,60,1,13.891050583657602,543,61,1,13.891050583657602,534,62,1,13.891050583657602,184,63,1,13.891050583657602,544,64,1,13.891050583657602,545,65,1,7.08171206225677,506]}}
  #|{"textrec":{"g":520,"r":[866,70,16,15,-1,-13,0]}}
  #|{"textrec":{"g":521,"r":[883,70,17,16,-1,-13,0]}}
  #|{"textrec":{"g":522,"r":[901,70,16,15,-1,-13,0]}}
  #|{"textrec":{"g":523,"r":[918,70,14,16,-1,-13,0]}}
  #|{"textrec":{"g":524,"r":[933,70,16,16,-1,-13,0]}}
  #|{"textrec":{"g":525,"r":[950,70,14,16,0,-13,0]}}
  #|{"textrec":{"g":526,"r":[965,70,9,11,-1,-9,0]}}
  #|{"textrec":{"g":527,"r":[975,70,5,13,-1,-12,0]}}
  #|{"textrec":{"g":528,"r":[981,70,4,5,0,-3,0]}}
  #|{"textrec":{"g":529,"r":[986,70,7,13,-1,-12,0]}}
  #|{"textrec":{"g":530,"r":[994,70,16,16,-1,-13,0]}}
  #|{"textrec":{"g":531,"r":[1011,70,13,13,0,-11,0]}}
  #|{"textrec":{"g":532,"r":[1025,70,15,16,-1,-13,0]}}
  #|{"textrec":{"g":533,"r":[1041,70,15,16,-1,-13,0]}}
  #|{"textrec":{"g":534,"r":[1057,70,15,4,-1,-7,0]}}
  #|{"textrec":{"g":535,"r":[1073,70,16,16,-1,-13,0]}}
  #|{"textrec":{"g":536,"r":[1090,70,16,15,-1,-12,0]}}
  #|{"textrec":{"g":537,"r":[1107,70,15,16,-1,-13,0]}}
  #|{"textrec":{"g":538,"r":[1123,70,14,16,0,-13,0]}}
  #|{"textrec":{"g":539,"r":[1138,70,10,11,-1,-9,0]}}
  #|{"textrec":{"g":540,"r":[1149,70,15,15,-1,-13,0]}}
  #|{"textrec":{"g":541,"r":[1165,70,15,16,-1,-13,0]}}
  #|{"textrec":{"g":542,"r":[1181,70,15,16,-1,-13,0]}}
  #|{"textrec":{"g":543,"r":[1197,70,15,16,-1,-13,0]}}
  #|{"textrec":{"g":544,"r":[1213,70,16,16,-1,-13,0]}}
  #|{"textrec":{"g":545,"r":[1230,70,15,15,-1,-12,0]}}
  #|{"textrec":{"g":518,"r":[1246,70,15,15,-1,-12,0]}}
  #|{"textrec":{"g":519,"r":[1262,70,15,16,-1,-13,0]}}
  #|{"textrec":{"s":[16,600,0,"添加连接"],"r":[0,1,15.875486381322958,546,1,1,15.875486381322958,547,2,1,15.875486381322958,185,3,1,15.875486381322958,186]}}
  #|{"textrec":{"s":[17,400,0,"取消"],"r":[0,1,16.851167315175097,548,1,1,16.851167315175097,549]}}
  #|{"textrec":{"g":548,"r":[1278,70,18,17,-1,-14,0]}}
  #|{"textrec":{"g":549,"r":[1297,70,18,18,-1,-15,0]}}
  #|{"textrec":{"g":546,"r":[1316,70,18,17,-1,-14,0]}}
  #|{"textrec":{"g":547,"r":[1335,70,17,17,-1,-14,0]}}
  #|{"textrec":{"s":[17,600,0,"添加连接"],"r":[0,1,16.851167315175097,550,1,1,16.851167315175097,551,2,1,16.851167315175097,552,3,1,16.851167315175097,553]}}
  #|{"textrec":{"m":[17,600,0],"r":[16.435546875,3.5859375,24]}}
  #|{"textrec":{"s":[11,400,0,"选择平台 · 1 / 5"],"r":[0,1,10.93579766536965,554,1,1,10.93579766536965,555,2,1,10.935797665369652,556,3,1,10.935797665369648,557,4,1,3.158203125,-1,5,1,5.2804038549793475,558,6,1,3.158203125,-1,7,1,5.1669921875,559,8,1,3.158203125,-1,9,1,3.416015625,560,10,1,3.158203125,-1,11,1,6.8642578125,561]}}
  #|{"textrec":{"s":[12,400,0,"在 Slack 的频道和私信中使用"],"r":[0,1,11.918287937743191,562,1,1,3.375,-1,2,1,7.646484375,198,3,1,3.03515625,199,4,1,6.6210937499999964,200,5,1,6.71484375,201,6,1,6.515625,202,7,1,3.375,-1,8,1,11.918287937743187,470,9,1,11.918287937743187,563,10,1,11.918287937743187,564,11,1,11.918287937743187,565,12,1,11.918287937743187,566,13,1,11.918287937743187,567,14,1,11.918287937743187,464,15,1,11.918287937743202,568,16,1,11.918287937743202,473]}}
  #|{"textrec":{"s":[15,400,0,"飞书"],"r":[0,1,14.883268482490273,569,1,1,14.883268482490273,570]}}
  #|{"textrec":{"s":[12,400,0,"在飞书的群和私聊中使用，含国际版 Lark"],"r":[0,1,11.918287937743191,562,1,1,11.918287937743191,571,2,1,11.918287937743195,572,3,1,11.918287937743187,470,4,1,11.918287937743187,573,5,1,11.918287937743187,565,6,1,11.918287937743187,566,7,1,11.918287937743187,574,8,1,11.918287937743187,464,9,1,11.918287937743187,568,10,1,11.918287937743187,473,11,1,12.081712062256798,467,12,1,11.918287937743202,575,13,1,11.918287937743202,576,14,1,11.918287937743202,577,15,1,11.918287937743202,578,16,1,3.375,-1,17,1,6.814453125,579,18,1,6.62109375,200,19,1,4.5703125,580,20,1,6.515625,202]}}
  #|{"textrec":{"s":[14,600,0,"下一步"],"r":[0,1,13.891050583657588,581,1,1,13.891050583657588,582,2,1,13.891050583657588,583]}}
  #|{"textrec":{"g":550,"r":[1353,70,19,18,-1,-15,0]}}
  #|{"textrec":{"g":551,"r":[1373,70,18,18,-1,-15,0]}}
  #|{"textrec":{"g":552,"r":[1392,70,18,18,-1,-15,0]}}
  #|{"textrec":{"g":553,"r":[1411,70,18,18,-1,-15,0]}}
  #|{"textrec":{"g":554,"r":[1430,70,13,13,-1,-10,0]}}
  #|{"textrec":{"g":555,"r":[1444,70,13,12,-1,-10,0]}}
  #|{"textrec":{"g":556,"r":[1458,70,13,13,-1,-10,0]}}
  #|{"textrec":{"g":557,"r":[1472,70,13,13,-1,-10,0]}}
  #|{"textrec":{"g":558,"r":[1486,70,5,4,0,-6,0]}}
  #|{"textrec":{"g":559,"r":[1492,70,6,10,-1,-9,0]}}
  #|{"textrec":{"g":560,"r":[1499,70,6,13,-1,-10,0]}}
  #|{"textrec":{"g":561,"r":[1506,70,9,11,-1,-9,0]}}
  #|{"textrec":{"g":562,"r":[1516,70,14,14,-1,-11,0]}}
  #|{"textrec":{"g":563,"r":[1531,70,14,14,-1,-11,0]}}
  #|{"textrec":{"g":564,"r":[1546,70,14,14,-1,-11,0]}}
  #|{"textrec":{"g":565,"r":[1561,70,13,14,-1,-11,0]}}
  #|{"textrec":{"g":566,"r":[1575,70,14,14,-1,-11,0]}}
  #|{"textrec":{"g":567,"r":[1590,70,14,14,-1,-11,0]}}
  #|{"textrec":{"g":568,"r":[1605,70,14,14,-1,-11,0]}}
  #|{"textrec":{"g":569,"r":[1620,70,16,16,-1,-13,0]}}
  #|{"textrec":{"g":570,"r":[1637,70,16,16,-1,-13,0]}}
  #|{"textrec":{"g":571,"r":[1654,70,14,12,-1,-10,0]}}
  #|{"textrec":{"g":572,"r":[1669,70,13,14,-1,-11,0]}}
  #|{"textrec":{"g":573,"r":[1683,70,14,14,-1,-11,0]}}
  #|{"textrec":{"g":574,"r":[1698,70,13,14,-1,-11,0]}}
  #|{"textrec":{"g":575,"r":[1712,70,14,14,-1,-11,0]}}
  #|{"textrec":{"g":576,"r":[1727,70,12,14,0,-11,0]}}
  #|{"textrec":{"g":577,"r":[1740,70,14,14,-1,-11,0]}}
  #|{"textrec":{"g":578,"r":[1755,70,14,14,-1,-11,0]}}
  #|{"textrec":{"g":579,"r":[1770,70,8,11,0,-10,0]}}
  #|{"textrec":{"g":580,"r":[1779,70,7,9,-1,-8,0]}}
  #|{"textrec":{"g":581,"r":[1787,70,15,15,-1,-12,0]}}
  #|{"textrec":{"g":582,"r":[1803,70,15,4,-1,-7,0]}}
  #|{"textrec":{"g":583,"r":[1819,70,15,16,-1,-13,0]}}
  #|{"textrec":{"ib":["2a1e0543c4d4f8c0",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["ca3c0dc6df833a30",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["e13e77444a4987cd",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"s":[17,400,0,"上一步"],"r":[0,1,16.851167315175097,584,1,1,16.851167315175097,585,2,1,16.851167315175097,586]}}
  #|{"textrec":{"s":[11,400,0,"选择 Slack 工作区 · 2 / 5"],"r":[0,1,10.93579766536965,554,1,1,10.93579766536965,555,2,1,3.158203125,-1,3,1,7.0737304687499964,222,4,1,2.8466796875,223,5,1,6.1337890625,224,6,1,6.2197265625,225,7,1,6.037109375,226,8,1,3.158203125,-1,9,1,10.935797665369648,587,10,1,10.935797665369648,588,11,1,10.935797665369648,589,12,1,3.158203125,-1,13,1,5.28040385497934,558,14,1,3.158203125,-1,15,1,6.703125,590,16,1,3.158203125,-1,17,1,3.416015625,560,18,1,3.158203125,-1,19,1,6.8642578125,561]}}
  #|{"textrec":{"s":[14,400,0,"有了 Slack 配置 token，still.fail 会替你在 Slack 中创建 app：名称、头像和权限都在这里填写，无需在 Slack 后台逐项配置。该 token 仅供你使用。"],"r":[0,1,13.891050583657588,591,1,1,13.891050583657588,592,2,1,3.787109375,-1,3,1,8.7705078125,352,4,1,3.390625,353,5,1,7.57421875,57,6,1,7.68359375,354,7,1,7.451171875,355,8,1,3.787109375,-1,9,1,13.891050583657588,593,10,1,13.891050583657588,594,11,1,3.787109375,-1,12,1,4.88427734375,61,13,1,8.06982421875,539,14,1,7.2802734375,355,15,1,7.6767578125,59,16,1,8.0185546875,60,17,1,12.681712062256821,50,18,1,7.1435546875,526,19,1,4.9013671875,61,20,1,3.30859375,527,21,1,3.390625,353,22,1,3.390625,353,23,1,3.80078125,528,24,1,4.607421875,529,25,1,7.4716796875,57,26,1,3.30859375,527,27,1,3.390625,353,28,1,3.787109375,-1,29,1,13.891050583657574,434,30,1,13.891050583657602,595,31,1,13.891050583657602,48,32,1,13.891050583657602,182,33,1,3.787109375,-1,34,1,8.7705078125,352,35,1,3.390625,353,36,1,7.57421875,57,37,1,7.68359375,354,38,1,7.451171875,355,39,1,3.787109375,-1,40,1,13.891050583657602,507,41,1,13.891050583657602,596,42,1,13.891050583657602,597,43,1,3.787109375,-1,44,1,7.57421875,57,45,1,8.39453125,508,46,1,8.39453125,508,47,1,14.081712062256827,598,48,1,13.891050583657602,599,49,1,13.891050583657602,600,50,1,14.081712062256827,601,51,1,13.891050583657602,602,52,1,13.891050583657602,603,53,1,13.891050583657602,604,54,1,13.891050583657602,605,55,1,13.891050583657602,606,56,1,13.891050583657602,607,57,1,13.891050583657545,182,58,1,13.891050583657602,608,59,1,13.891050583657602,609,60,1,13.891050583657602,610,61,1,13.891050583657602,611,62,1,14.08171206225677,50,63,1,13.891050583657602,612,64,1,13.891050583657602,509,65,1,13.891050583657602,182,66,1,3.787109375,-1,67,1,8.7705078125,352,68,1,3.390625,353,69,1,7.57421875,57,70,1,7.68359375,354,71,1,7.451171875,355,72,1,3.787109375,-1,73,1,13.891050583657602,613,74,1,13.891050583657602,538,75,1,13.891050583657602,614,76,1,13.891050583657602,615,77,1,13.891050583657602,593,78,1,13.891050583657602,594,79,1,14.08171206225677,506,80,1,13.891050583657602,616,81,1,3.787109375,-1,82,1,4.88427734375,61,83,1,8.06982421875,539,84,1,7.2802734375,355,85,1,7.6767578125,59,86,1,8.0185546875,60,87,1,3.787109375,-1,88,1,13.891050583657602,617,89,1,13.891050583657602,618,90,1,13.891050583657602,48,91,1,13.891050583657602,619,92,1,13.891050583657602,55,93,1,7.08171206225677,506]}}
  #|{"textrec":{"s":[14,600,0,"添加配置 token"],"r":[0,1,13.891050583657588,620,1,1,13.891050583657588,621,2,1,13.891050583657588,622,3,1,13.891050583657588,623,4,1,3.5793075561523438,-1,5,1,5.3377615213394165,624,6,1,8.341481804847717,625,7,1,7.765144348144531,626,8,1,7.906205654144287,627,9,1,8.406018495559692,628]}}
  #|{"textrec":{"s":[14,400,0,"不使用配置 token，在 Slack 中手动创建 app"],"r":[0,1,13.891050583657588,518,1,1,13.891050583657588,619,2,1,13.891050583657588,55,3,1,13.891050583657588,593,4,1,13.891050583657588,594,5,1,3.787109375,-1,6,1,4.88427734375,61,7,1,8.06982421875,539,8,1,7.2802734375,355,9,1,7.6767578125,59,10,1,8.0185546875,60,11,1,14.081712062256813,50,12,1,13.891050583657574,182,13,1,3.787109375,-1,14,1,8.7705078125,352,15,1,3.390625,353,16,1,7.57421875,57,17,1,7.68359375,354,18,1,7.451171875,355,19,1,3.787109375,-1,20,1,13.891050583657602,507,21,1,13.891050583657602,511,22,1,13.891050583657602,512,23,1,13.891050583657602,596,24,1,13.891050583657602,597,25,1,3.787109375,-1,26,1,7.57421875,57,27,1,8.39453125,508,28,1,8.39453125,508]}}
  #|{"textrec":{"g":584,"r":[1835,70,18,18,-1,-15,0]}}
  #|{"textrec":{"g":585,"r":[1854,70,18,4,-1,-8,0]}}
  #|{"textrec":{"g":586,"r":[1873,70,18,18,-1,-15,0]}}
  #|{"textrec":{"g":587,"r":[1892,70,13,11,-1,-9,0]}}
  #|{"textrec":{"g":588,"r":[1906,70,13,13,-1,-10,0]}}
  #|{"textrec":{"g":589,"r":[1920,70,12,12,0,-10,0]}}
  #|{"textrec":{"g":590,"r":[1933,70,8,10,-1,-9,0]}}
  #|{"textrec":{"g":591,"r":[1942,70,15,16,-1,-13,0]}}
  #|{"textrec":{"g":592,"r":[1958,70,13,15,0,-12,0]}}
  #|{"textrec":{"g":593,"r":[1972,70,16,15,-1,-12,0]}}
  #|{"textrec":{"g":594,"r":[1989,70,15,15,-1,-12,0]}}
  #|{"textrec":{"g":595,"r":[2005,70,16,16,-1,-13,0]}}
  #|{"textrec":{"g":596,"r":[2022,70,15,16,-1,-13,0]}}
  #|{"textrec":{"g":597,"r":[0,89,15,16,-1,-13,0]}}
  #|{"textrec":{"g":598,"r":[16,89,5,10,1,-10,0]}}
  #|{"textrec":{"g":599,"r":[22,89,14,16,-1,-13,0]}}
  #|{"textrec":{"g":600,"r":[37,89,16,16,-1,-13,0]}}
  #|{"textrec":{"g":601,"r":[54,89,6,6,0,-3,0]}}
  #|{"textrec":{"g":602,"r":[61,89,15,16,-1,-13,0]}}
  #|{"textrec":{"g":603,"r":[77,89,16,16,-1,-13,0]}}
  #|{"textrec":{"g":604,"r":[94,89,15,16,-1,-13,0]}}
  #|{"textrec":{"g":605,"r":[110,89,16,16,-1,-13,0]}}
  #|{"textrec":{"g":606,"r":[127,89,15,15,0,-12,0]}}
  #|{"textrec":{"g":607,"r":[143,89,15,16,-1,-13,0]}}
  #|{"textrec":{"g":608,"r":[159,89,16,16,-1,-13,0]}}
  #|{"textrec":{"g":609,"r":[176,89,15,14,-1,-12,0]}}
  #|{"textrec":{"g":610,"r":[192,89,16,16,-1,-13,0]}}
  #|{"textrec":{"g":611,"r":[209,89,15,15,-1,-12,0]}}
  #|{"textrec":{"g":612,"r":[225,89,15,15,-1,-12,0]}}
  #|{"textrec":{"g":613,"r":[241,89,15,16,-1,-13,0]}}
  #|{"textrec":{"g":614,"r":[257,89,16,15,-1,-12,0]}}
  #|{"textrec":{"g":615,"r":[274,89,16,15,-1,-12,0]}}
  #|{"textrec":{"g":616,"r":[291,89,16,16,-1,-13,0]}}
  #|{"textrec":{"g":617,"r":[308,89,16,16,-1,-13,0]}}
  #|{"textrec":{"g":618,"r":[325,89,16,16,-1,-13,0]}}
  #|{"textrec":{"g":619,"r":[342,89,16,16,-1,-13,0]}}
  #|{"textrec":{"g":620,"r":[359,89,16,16,-1,-13,0]}}
  #|{"textrec":{"g":621,"r":[376,89,15,16,-1,-13,0]}}
  #|{"textrec":{"g":622,"r":[392,89,16,15,-1,-12,0]}}
  #|{"textrec":{"g":623,"r":[409,89,15,15,-1,-12,0]}}
  #|{"textrec":{"g":624,"r":[425,89,7,13,-1,-11,0]}}
  #|{"textrec":{"g":625,"r":[433,89,10,11,-1,-9,0]}}
  #|{"textrec":{"g":626,"r":[444,89,9,13,0,-12,0]}}
  #|{"textrec":{"g":627,"r":[454,89,10,11,-1,-9,0]}}
  #|{"textrec":{"g":628,"r":[465,89,9,10,0,-9,0]}}
  #|{"textrec":{"s":[11,400,0,"添加配置 token · 1 / 5"],"r":[0,1,10.93579766536965,629,1,1,10.93579766536965,630,2,1,10.935797665369652,631,3,1,10.935797665369648,632,4,1,3.158203125,-1,5,1,4.020263671875,633,6,1,6.523193359375,634,7,1,5.90283203125,226,8,1,6.214355468749993,635,9,1,6.48291015625,636,10,1,3.158203125,-1,11,1,5.28040385497934,558,12,1,3.158203125,-1,13,1,5.1669921875,559,14,1,3.158203125,-1,15,1,3.416015625,560,16,1,3.158203125,-1,17,1,6.8642578125,561]}}
  #|{"textrec":{"s":[14,400,0,"1."],"r":[0,1,6.1728515625,175,1,1,3.8349609375,528]}}
  #|{"textrec":{"s":[14,400,0,"打开 api.slack.com/apps，用 bot 所在 Slack 工作区的账号登录。"],"r":[0,1,13.891050583657588,637,1,1,13.891050583657588,97,2,1,3.787109375,-1,3,1,7.57421875,57,4,1,8.39453125,508,5,1,3.30859375,527,6,1,4.005859375,528,7,1,7.177734375,526,8,1,3.390625,353,9,1,7.57421875,57,10,1,7.68359375,354,11,1,7.451171875,355,12,1,3.869140625,528,13,1,7.546875,354,14,1,8.12109375,539,15,1,12.03125,638,16,1,4.115234375,181,17,1,7.57421875,57,18,1,8.39453125,508,19,1,8.39453125,508,20,1,7.177734375,526,21,1,14.081712062256798,50,22,1,13.891050583657602,55,23,1,3.787109375,-1,24,1,8.44921875,639,25,1,8.12109375,539,26,1,4.935546875,61,27,1,3.787109375,-1,28,1,13.891050583657602,640,29,1,13.891050583657602,182,30,1,3.787109375,-1,31,1,8.7705078125,352,32,1,3.390625,353,33,1,7.57421875,57,34,1,7.68359375,354,35,1,7.451171875,355,36,1,3.787109375,-1,37,1,13.891050583657602,641,38,1,13.891050583657602,642,39,1,13.891050583657602,643,40,1,13.891050583657602,56,41,1,13.891050583657602,644,42,1,13.891050583657602,645,43,1,13.891050583657602,646,44,1,13.891050583657602,647,45,1,7.081712062256827,506]}}
  #|{"textrec":{"s":[14,400,0,"打开"],"r":[0,1,13.891050583657588,637,1,1,13.891050583657588,97]}}
  #|{"textrec":{"s":[14,400,0,"2."],"r":[0,1,8.1962890625,126,1,1,3.9033203125,528]}}
  #|{"textrec":{"s":[14,400,0,"滚动到页面底部的「Your App Configuration Tokens」，点击 Generate Token，选择此工作区。"],"r":[0,1,13.891050583657588,648,1,1,13.891050583657588,512,2,1,13.891050583657588,649,3,1,13.891050583657588,650,4,1,13.891050583657588,651,5,1,13.891050583657588,652,6,1,13.891050583657588,653,7,1,20.891050583657588,56,8,1,5.066147859922182,654,9,1,8.4423828125,655,10,1,7.5400390625,539,11,1,8.0185546875,656,12,1,5.181640625,657,13,1,3.787109375,-1,14,1,9.283203125,658,15,1,8.39453125,508,16,1,8.39453125,508,17,1,3.787109375,-1,18,1,9.87109375,659,19,1,8.12109375,539,20,1,8.0185546875,60,21,1,4.9150390625,529,22,1,3.30859375,527,23,1,8.380859375,58,24,1,8.0185546875,656,25,1,5.181640625,657,26,1,7.57421875,57,27,1,4.935546875,61,28,1,3.30859375,527,29,1,8.12109375,539,30,1,8.0185546875,60,31,1,3.787109375,-1,32,1,8.0390625,660,33,1,7.4375,539,34,1,7.2802734375,355,35,1,7.6767578125,59,36,1,8.0185546875,60,37,1,7.177734375,526,38,1,6.543774319066131,661,39,1,14.081712062256827,50,40,1,13.891050583657602,662,41,1,13.891050583657602,663,42,1,3.787109375,-1,43,1,10.3017578125,664,44,1,7.84765625,59,45,1,8.0185546875,60,46,1,7.84765625,59,47,1,5.181640625,657,48,1,7.57421875,57,49,1,4.88427734375,61,50,1,7.79638671875,59,51,1,3.787109375,-1,52,1,8.0390625,660,53,1,7.4375,539,54,1,7.2802734375,355,55,1,7.6767578125,59,56,1,8.0185546875,60,57,1,14.081712062256827,50,58,1,13.891050583657602,665,59,1,13.891050583657602,666,60,1,13.891050583657602,667,61,1,13.891050583657602,641,62,1,13.891050583657602,642,63,1,13.891050583657602,643,64,1,7.08171206225677,506]}}
  #|{"textrec":{"s":[14,400,0,"3."],"r":[0,1,8.3876953125,668,1,1,3.7666015625,528]}}
  #|{"textrec":{"s":[14,400,0,"将以 xoxe-1- 开头的 Refresh Token 粘贴到下方。still.fail 会自动续期，无需再手动处理。"],"r":[0,1,13.891050583657588,505,1,1,13.891050583657588,669,2,1,3.787109375,-1,3,1,7.0205078125,670,4,1,7.779296875,539,5,1,6.849609375,670,6,1,7.6767578125,59,7,1,6.453125,671,8,1,6.34375,175,9,1,6.453125,671,10,1,3.787109375,-1,11,1,13.891050583657588,97,12,1,13.891050583657588,602,13,1,13.891050583657588,56,14,1,3.787109375000014,-1,15,1,8.8935546875,672,16,1,7.7451171875,59,17,1,4.9150390625,529,18,1,5.0791015625,657,19,1,7.7451171875,59,20,1,7.177734375,526,21,1,8.0869140625,673,22,1,3.787109375,-1,23,1,8.0390625,660,24,1,7.4375,539,25,1,7.2802734375,355,26,1,7.6767578125,59,27,1,8.0185546875,60,28,1,3.787109375,-1,29,1,13.891050583657602,674,30,1,13.891050583657602,675,31,1,13.891050583657602,649,32,1,13.891050583657602,676,33,1,13.891050583657602,436,34,1,14.081712062256827,506,35,1,7.1435546875,526,36,1,4.9013671875,61,37,1,3.30859375,527,38,1,3.390625,353,39,1,3.390625,353,40,1,3.80078125,528,41,1,4.607421875,529,42,1,7.4716796875,57,43,1,3.30859375,527,44,1,3.390625,353,45,1,3.787109375,-1,46,1,13.891050583657602,434,47,1,13.891050583657602,677,48,1,13.891050583657602,512,49,1,13.891050583657602,678,50,1,13.891050583657602,679,51,1,14.081712062256827,50,52,1,13.891050583657602,612,53,1,13.891050583657602,509,54,1,13.891050583657602,680,55,1,13.891050583657602,511,56,1,13.891050583657602,512,57,1,13.891050583657545,681,58,1,13.891050583657602,682,59,1,7.08171206225677,506]}}
  #|{"textrec":{"s":[14,600,0,"添加"],"r":[0,1,13.891050583657588,620,1,1,13.891050583657588,621]}}
  #|{"textrec":{"g":629,"r":[475,89,13,13,-1,-10,0]}}
  #|{"textrec":{"g":630,"r":[489,89,12,13,-1,-10,0]}}
  #|{"textrec":{"g":631,"r":[502,89,13,13,-1,-10,0]}}
  #|{"textrec":{"g":632,"r":[516,89,13,12,-1,-10,0]}}
  #|{"textrec":{"g":633,"r":[530,89,6,11,-1,-9,0]}}
  #|{"textrec":{"g":634,"r":[537,89,8,9,-1,-7,0]}}
  #|{"textrec":{"g":635,"r":[546,89,8,9,-1,-7,0]}}
  #|{"textrec":{"g":636,"r":[555,89,8,8,-1,-7,0]}}
  #|{"textrec":{"g":637,"r":[564,89,15,16,-1,-13,0]}}
  #|{"textrec":{"g":638,"r":[580,89,13,10,0,-9,0]}}
  #|{"textrec":{"g":639,"r":[594,89,9,14,0,-12,0]}}
  #|{"textrec":{"g":640,"r":[604,89,16,16,-1,-13,0]}}
  #|{"textrec":{"g":641,"r":[621,89,15,14,-1,-12,0]}}
  #|{"textrec":{"g":642,"r":[637,89,15,16,-1,-13,0]}}
  #|{"textrec":{"g":643,"r":[653,89,14,14,0,-12,0]}}
  #|{"textrec":{"g":644,"r":[668,89,16,16,-1,-13,0]}}
  #|{"textrec":{"g":645,"r":[685,89,15,15,-1,-12,0]}}
  #|{"textrec":{"g":646,"r":[701,89,16,15,-1,-13,0]}}
  #|{"textrec":{"g":647,"r":[718,89,15,15,-1,-12,0]}}
  #|{"textrec":{"g":648,"r":[734,89,16,16,-1,-13,0]}}
  #|{"textrec":{"g":649,"r":[751,89,15,16,-1,-13,0]}}
  #|{"textrec":{"g":650,"r":[767,89,15,15,-1,-12,0]}}
  #|{"textrec":{"g":651,"r":[783,89,15,15,-1,-12,0]}}
  #|{"textrec":{"g":652,"r":[799,89,15,16,-1,-13,0]}}
  #|{"textrec":{"g":653,"r":[815,89,15,16,-1,-13,0]}}
  #|{"textrec":{"g":654,"r":[831,89,7,12,-1.333333333333333,-13,0]}}
  #|{"textrec":{"g":655,"r":[839,89,11,12,-1,-11,0]}}
  #|{"textrec":{"g":656,"r":[851,89,9,11,0,-9,0]}}
  #|{"textrec":{"g":657,"r":[861,89,6,10,0,-9,0]}}
  #|{"textrec":{"g":658,"r":[868,89,11,12,-1,-11,0]}}
  #|{"textrec":{"g":659,"r":[880,89,12,14,-1,-12,0]}}
  #|{"textrec":{"g":660,"r":[893,89,11,12,-1,-11,0]}}
  #|{"textrec":{"g":661,"r":[905,89,7,11,-1,-8,0]}}
  #|{"textrec":{"g":662,"r":[913,89,15,16,-1,-13,0]}}
  #|{"textrec":{"g":663,"r":[929,89,15,16,-1,-13,0]}}
  #|{"textrec":{"g":664,"r":[945,89,12,14,-1,-12,0]}}
  #|{"textrec":{"g":665,"r":[958,89,16,16,-1,-13,0]}}
  #|{"textrec":{"g":666,"r":[975,89,16,16,-1,-13,0]}}
  #|{"textrec":{"g":667,"r":[992,89,16,14,-1,-12,0]}}
  #|{"textrec":{"g":668,"r":[1009,89,10,14,-1,-12,0]}}
  #|{"textrec":{"g":669,"r":[1020,89,15,16,0,-13,0]}}
  #|{"textrec":{"g":670,"r":[1036,89,9,10,-1,-9,0]}}
  #|{"textrec":{"g":671,"r":[1046,89,7,4,0,-6,0]}}
  #|{"textrec":{"g":672,"r":[1054,89,10,12,0,-11,0]}}
  #|{"textrec":{"g":673,"r":[1065,89,9,13,0,-12,0]}}
  #|{"textrec":{"g":674,"r":[1075,89,15,16,-1,-13,0]}}
  #|{"textrec":{"g":675,"r":[1091,89,15,16,-1,-13,0]}}
  #|{"textrec":{"g":676,"r":[1107,89,15,15,-1,-12,0]}}
  #|{"textrec":{"g":677,"r":[1123,89,12,16,1,-13,0]}}
  #|{"textrec":{"g":678,"r":[1136,89,16,16,-1,-13,0]}}
  #|{"textrec":{"g":679,"r":[1153,89,15,16,-1,-13,0]}}
  #|{"textrec":{"g":680,"r":[1169,89,15,15,-1,-12,0]}}
  #|{"textrec":{"g":681,"r":[1185,89,16,16,-1,-13,0]}}
  #|{"textrec":{"g":682,"r":[1202,89,16,14,-1,-12,0]}}
  #|{"textrec":{"s":[15,400,0,"xoxe-1-…"],"r":[0,1,7.44873046875,497,1,1,8.26171875,88,2,1,7.265625,497,3,1,8.15185546875,95,4,1,6.8408203125,204,5,1,6.7236328125,165,6,1,6.8408203125,204,7,1,11.8359375,498]}}
  #|{"textrec":{"g":165,"r":[1219,89,8,13,-1,-12,0]}}
