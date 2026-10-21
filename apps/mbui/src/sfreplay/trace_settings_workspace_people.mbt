// e2e/traces/settings-workspace-people.trace, made by scripts/trace.py from 07-settings_workspace_people.log: not edited by hand.

///|
/// What the app and its core said in the run, a line each.
pub let trace_settings_workspace_people : String =
  #|{"start":"base"}
  #|{"step":"drive-seed 080726"}
  #|{"env":{"MBUI_CLOUD":"http://127.0.0.1:18900","MBUI_CORE_ACCOUNT":"{\"sub\":\"alice\",\"email\":\"alice@example.test\",\"name\":\"Name of alice\",\"picture\":\"\",\"access\":\"-\",\"refresh\":\"-\",\"accessExpires\":1792532523}"}}
  #|{"out":{"id":1,"call":"client.device","params":{"client":"still.fail mbui","app":"desktop","userAgent":"Macintosh; Mac OS X"}},"w":1792532451463.466}
  #|{"in":{"id":1,"ok":null},"w":1792532451590.759}
  #|{"out":{"id":2,"subscribe":{"topic":"accounts"},"keyed":true},"w":1792532451590.785}
  #|{"out":{"id":3,"subscribe":{"topic":"prefs"},"keyed":true},"w":1792532451590.798}
  #|{"step":"# written by scripts/rerecord.sh from its test (src/sfreplay/emit.mbt): not edited by hand","w":1792532451592.33}
  #|{"step":"timeout 90000","w":1792532451592.337}
  #|{"step":"answered client.device","w":1792532451592.339}
  #|{"step":"answered client.focus","w":1792532451619.775}
  #|{"in":{"id":2,"value":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""}]},"w":1792532451669.359}
  #|{"in":{"id":3,"value":{"onlyMine":false,"onlyWatching":false,"onlyDecisions":false,"listFilter":{},"appearance":"system","rowPicture":"auto","absoluteTime":false,"lang":"zh","keys":{},"lastChat":{},"openChat":{},"chatTabs":{},"dropFiles":{},"driveViews":{},"resume":{},"stationUpdatesDismissed":{},"device":{"app":"desktop","phone":false,"handoff":false},"reader":{"size":18,"line":1.7,"margin":22,"face":"sans","indent":true,"paper":"follow"},"rails":{},"bars":{"sets":[["chats","files","profiles","stations"],["decisions","usage","connects","archive"]],"current":0},"barsBy":{}}},"w":1792532451669.384}
  #|{"out":{"id":4,"subscribe":{"topic":"workspaces"},"keyed":true},"w":1792532451669.408}
  #|{"out":{"id":5,"subscribe":{"topic":"status"},"keyed":true},"w":1792532451669.424}
  #|{"in":{"id":4,"value":[{"account":{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""},"workspaces":[{"id":"01M5DKY0ZBKMJ6GSMJ7D9N001T","name":"Dev","role":"owner","created_at":1792532218,"stations":1,"members":1,"relays":[],"time":{"created_at":{"past":true,"at":1792532218000,"ago":"4 分钟前","full":"10/21 05:36:58","until":"1 分钟内"}}}],"invitations":[],"relay_url":"http://127.0.0.1:18940","loaded":true,"beta":true}]},"w":1792532451686.024}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792532451686.037}
  #|{"out":{"id":6,"subscribe":{"topic":"lock","workspace":"01M5DKY0ZBKMJ6GSMJ7D9N001T"},"keyed":true},"w":1792532451686.069}
  #|{"out":{"id":7,"subscribe":{"topic":"chats","scope":"01M5DKY0ZBKMJ6GSMJ7D9N001T","mine":false},"keyed":true},"w":1792532451686.083}
  #|{"out":{"id":8,"subscribe":{"topic":"workspaceMarks","workspace":"01M5DKY0ZBKMJ6GSMJ7D9N001T"},"keyed":true},"w":1792532451686.206}
  #|{"out":{"id":9,"subscribe":{"topic":"status","workspace":"01M5DKY0ZBKMJ6GSMJ7D9N001T"},"keyed":true},"w":1792532451686.237}
  #|{"out":{"id":10,"call":"client.focus","params":{"visible":true,"focused":true,"workspace":"01M5DKY0ZBKMJ6GSMJ7D9N001T"}},"w":1792532451691.77}
  #|{"out":{"id":11,"subscribe":{"topic":"notify"},"keyed":true},"w":1792532451691.779}
  #|{"out":{"id":12,"subscribe":{"topic":"notify","workspace":"01M5DKY0ZBKMJ6GSMJ7D9N001T"},"keyed":true},"w":1792532451691.785}
  #|{"in":{"id":6,"value":{"available":true,"locked":false,"notice":true,"role":"owner","manages":true,"owner":true,"canSign":true,"signs":false,"me":{"device":"0ee418d30016ef14ebed33eef7efb03416fc94d02ad3ce9040666660f9c9fe10","code":"Q7P-HKS","kind":"app","confirmed":false,"waiting":false,"asked":false},"signers":0,"members":[],"stations":[{"id":"3f478fdc0fafa1a059f546ae5e01493a8c0684e1cdae03aa318f819879640e42","name":"studio","version":"0.1.0","online":true,"protected":false}],"protected":0,"requests":[],"renew":[],"attention":0}},"w":1792532451704.569}
  #|{"in":{"id":7,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"stations":[{"station":"01M5DKY0ZBKMJ6GSMJ7D9N001T/3f478fdc0fafa1a059f546ae5e01493a8c0684e1cdae03aa318f819879640e42","id":"3f478fdc0fafa1a059f546ae5e01493a8c0684e1cdae03aa318f819879640e42","name":"studio","state":"online"}],"loading":false,"days":[{"daysAgo":0,"at":1792532222982,"label":"今天","items":[{"id":"ember:c-e5c56c6d05","session":"ember:c-e5c56c6d05","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","agents":[{"key":"ember:c-e5c56c6d05","runtime":"claude","process":"warm","pending":0,"lastTurn":{"id":"4e3d603f-ff87-4576-8fbb-8c454f448570","kind":"input","outcome":"completed","declared":"final","ending":"all_done","need":"answered the question that was asked","startedAt":1792532222913,"endedAt":1792532222984},"agentText":"默认模型","statusText":"已完成：answered the question that was asked"}],"last":{"seq":2,"authorKind":"agent","author":"ember:c-e5c56c6d05","text":"你好，我是测试用的 agent","createdAt":1792532222982,"by":{"kind":"agent","name":"agent","mine":false,"runtime":"claude","label":"agent"},"preview":"你好，我是测试用的 agent","time":{"createdAt":{"at":1792532222982,"ago":"4 分钟前","full":"10/21 05:37:02","until":"1 分钟内","past":true}}},"unread":true,"mine":true,"lastActiveAt":1792532222982,"station":"01M5DKY0ZBKMJ6GSMJ7D9N001T/3f478fdc0fafa1a059f546ae5e01493a8c0684e1cdae03aa318f819879640e42","stationName":"studio","time":{"lastActiveAt":{"at":1792532222982,"ago":"4 分钟前","full":"10/21 05:37:02","until":"1 分钟内","past":true}},"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"peopleText":"你 发起","clientKey":"new:chat-66f59c969c10159282","pinned":false,"tone":"done"}]}],"trouble":null,"members":1,"leading":"agents","glyph":{"online":1,"dim":0,"connecting":0,"failing":0,"working":0,"summary":"studio","label":"1 台 station，1 台在线"},"note":{"reading":false,"text":null,"failing":[],"empty":false}}},"w":1792532451704.599}
  #|{"in":{"id":8,"value":{"workspaces":{"01M5DKY0ZBKMJ6GSMJ7D9N001T":{"alert":0,"unread":1,"tone":"done","label":"1 个有新消息","badge":0,"items":[],"mineTone":"done"}},"badge":0,"badgeCounts":"attention","badgeKinds":{"on":true,"wait":true,"failed":true,"done":false,"message":false}}},"w":1792532451704.621}
  #|{"in":{"id":9,"value":{"items":[]}},"w":1792532451704.626}
  #|{"in":{"id":10,"ok":null},"w":1792532451704.629}
  #|{"in":{"id":11,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792532451704.634}
  #|{"in":{"id":12,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792532451704.639}
  #|{"out":{"id":13,"subscribe":{"topic":"longJobs","scope":"01M5DKY0ZBKMJ6GSMJ7D9N001T"},"keyed":true},"w":1792532451704.664}
  #|{"out":{"id":14,"call":"notify.permission","params":{"state":"unknown"}},"w":1792532451707.472}
  #|{"in":{"id":13,"value":{"groups":[]}},"w":1792532451719.356}
  #|{"in":{"id":14,"ok":null},"w":1792532451719.362}
  #|{"step":"answered notify.permission","w":1792532451719.589}
  #|{"step":"tap icon:settings","w":1792532451736.244}
  #|{"step":"tap icon:settings","acted":true,"w":1792532451752.894}
  #|{"out":{"id":15,"subscribe":{"topic":"workspace","workspace":"01M5DKY0ZBKMJ6GSMJ7D9N001T"},"keyed":true},"w":1792532451769.497}
  #|{"out":{"id":16,"subscribe":{"topic":"stations","scope":"01M5DKY0ZBKMJ6GSMJ7D9N001T"},"keyed":true},"w":1792532451769.514}
  #|{"out":{"id":17,"subscribe":{"topic":"connects","scope":"01M5DKY0ZBKMJ6GSMJ7D9N001T","mine":false},"keyed":true},"w":1792532451769.522}
  #|{"out":{"id":18,"subscribe":{"topic":"vaults","workspace":"01M5DKY0ZBKMJ6GSMJ7D9N001T"},"keyed":true},"w":1792532451769.53}
  #|{"out":{"id":19,"subscribe":{"topic":"doing"},"keyed":true},"w":1792532451774.6}
  #|{"step":"rest","w":1792532451775.658}
  #|{"in":{"id":15,"value":{"id":"01M5DKY0ZBKMJ6GSMJ7D9N001T","name":"Dev","role":"owner","created_at":1792532218,"members":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":"https://example.test/p.png","role":"owner","added_at":1792532218}],"stations":[{"id":"3f478fdc0fafa1a059f546ae5e01493a8c0684e1cdae03aa318f819879640e42","name":"studio","emoji":null,"icon":null,"enrolled_at":1792532219,"enrolled_by":"alice","last_seen":1792532224,"version":"0.1.0","time":{"last_seen":{"past":true,"at":1792532224000,"ago":"4 分钟前","full":"10/21 05:37:04","until":"1 分钟内"}}}],"invitations":[],"added":[],"relays":[],"lock":null,"lock_requests":0,"time":{"created_at":{"past":true,"at":1792532218000,"ago":"4 分钟前","full":"10/21 05:36:58","until":"1 分钟内"}}}},"w":1792532451786.029}
  #|{"in":{"id":16,"value":[{"station":"01M5DKY0ZBKMJ6GSMJ7D9N001T/3f478fdc0fafa1a059f546ae5e01493a8c0684e1cdae03aa318f819879640e42","id":"3f478fdc0fafa1a059f546ae5e01493a8c0684e1cdae03aa318f819879640e42","name":"studio","summary":"正在连接","face":"idle","line":"在线","online":true,"reconnecting":true,"lastSeen":1792532224,"version":"0.1.0","link":{"state":"connecting"},"runtimes":[{"runtime":"claude","models":["claude-sonnet-5-5"]}],"models":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792532222891,"time":{"checkedAt":{"at":1792532222891,"ago":"4 分钟前","full":"10/21 05:37:02","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"overview":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null,"summaryText":"最近 7 天检查了 0 个 chat","changeText":null}},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","email":"alice@example.test","name":"Name of alice","sub":"alice","role":"owner","workspace":"01M5DKY0ZBKMJ6GSMJ7D9N001T","device":"0ee418d30016ef14ebed33eef7efb03416fc94d02ad3ce9040666660f9c9fe10"},"connects":[],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792532222777,"time":{"checkedAt":{"at":1792532222777,"ago":"4 分钟前","full":"10/21 05:37:02","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792532222891,"time":{"checkedAt":{"at":1792532222891,"ago":"4 分钟前","full":"10/21 05:37:02","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]}],"processes":[],"counts":{"sessions":1,"running":0,"warm":1},"mesh":{"state":"running","origin":"http://127.0.0.1:18900","station":"3f478fdc0fafa1a059f546ae5e01493a8c0684e1cdae03aa318f819879640e42","workspace":"Dev","workspaceId":"01M5DKY0ZBKMJ6GSMJ7D9N001T","name":"studio"},"slackUsers":[],"slackTeams":[],"slackApps":[],"feishuRegistrations":[],"disk":{"freeBytes":57720881152,"totalBytes":245107195904},"logins":[],"machineLogins":[],"sharing":true,"consoleSignIn":true,"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"google","name":"Google Gemini","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xai","name":"xAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"mistral","name":"Mistral","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"deepseek","name":"DeepSeek","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen","name":"Qwen","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai","name":"Kimi","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai","name":"Z.ai","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax","name":"MiniMax","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ant-ling","name":"Ant Ling","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"jev","name":"Jev","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen-cn","name":"Qwen (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"openrouter","name":"OpenRouter","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"opencode","name":"OpenCode Zen","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"groq","name":"Groq","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"together","name":"Together AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"fireworks","name":"Fireworks","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cerebras","name":"Cerebras","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"huggingface","name":"Hugging Face","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"nvidia","name":"NVIDIA","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"baseten","name":"Baseten","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ollama","name":"Ollama","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"custom","name":"Custom","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""}],"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792532220372},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.305","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792532220372},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792532220372},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792532220372},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","latest":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792532220372}],"processesText":"没有运行中的 agent 进程","agentEnv":[],"drive":{"roots":[],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false}},"betaOffered":false,"time":{"lastSeen":{"at":1792532224000,"ago":"4 分钟前","full":"10/21 05:37:04","until":"1 分钟内","past":true}},"joined":false}]},"w":1792532451786.169}
  #|{"in":{"id":17,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"items":[],"wait":{"reading":false,"text":null,"failing":[],"empty":true}}},"w":1792532451786.263}
  #|{"in":{"id":18,"value":{"available":true,"locked":false,"canSign":false,"setUp":false,"vaults":[{"id":"plain","name":"个人","owner":"alice","ownerName":"Name of alice","mine":true,"members":[{"sub":"alice","name":"Name of alice"}],"station":"3f478fdc0fafa1a059f546ae5e01493a8c0684e1cdae03aa318f819879640e42","stationName":"studio","items":0,"devices":0,"open":true,"keyed":true,"missing":0,"recoverable":false}],"requests":[],"refused":[{"station":"3f478fdc0fafa1a059f546ae5e01493a8c0684e1cdae03aa318f819879640e42","name":"studio","code":"vault_needs_lock"}],"plain":true}},"w":1792532451786.272}
  #|{"in":{"id":19,"value":{"doing":[]}},"w":1792532451786.28}
  #|{"step":"now tap =Workspace","w":1792532452536.75}
  #|{"step":"now tap =Workspace","acted":true,"w":1792532452553.464}
  #|{"out":{"id":20,"call":"picture","params":{"url":"https://example.test/p.png"}},"w":1792532452576.092}
  #|{"step":"answered picture","w":1792532452580.57}
  #|{"in":{"id":20,"error":{"code":"picture","message":"无法加载图片：error sending request for url (https://example.test/p.png): client error (Connect): tls handshake eof"}},"w":1792532452769.393}
  #|{"step":"rest","w":1792532452787.175}
  #|{"step":"now until alice@example.test","w":1792532452886.74}
  #|{"step":"tap icon:user-plus","w":1792532452886.771}
  #|{"step":"tap icon:user-plus","acted":true,"w":1792532452903.437}
  #|{"step":"rest","w":1792532452920.187}
  #|{"in":{"id":5,"value":{"state":"slow","text":"正在连接 studio ×3 · 2 秒 · 共 5 项","items":[{"state":"slow","text":"正在连接 studio ×3","detail":"已等待 2 秒"},{"state":"slow","text":"studio 打开实时更新 ×2","detail":"已等待 2 秒，尚未收到数据"}]}},"w":1792532453819.407}
  #|{"in":{"id":9,"value":{"state":"slow","text":"正在连接 studio ×3 · 2 秒 · 共 5 项","items":[{"state":"slow","text":"正在连接 studio ×3","detail":"已等待 2 秒"},{"state":"slow","text":"studio 打开实时更新 ×2","detail":"已等待 2 秒，尚未收到数据"}]}},"w":1792532453819.497}
  #|{"step":"now until 添加成员","w":1792532454420.414}
  #|{"step":"tap name@example.com","w":1792532454420.536}
  #|{"step":"tap name@example.com","acted":true,"w":1792532454437.276}
  #|{"step":"type e2e-080726@example.test","w":1792532454463.246}
  #|{"step":"type e2e-080726@example.test","acted":true,"w":1792532454463.298}
  #|{"step":"tap =添加","w":1792532454472.07}
  #|{"step":"tap =添加","acted":true,"w":1792532454487.269}
  #|{"out":{"id":21,"call":"workspace.addMembers","params":{"workspace":"01M5DKY0ZBKMJ6GSMJ7D9N001T","role":"member","emails":["e2e-080726@example.test"],"account":"alice"}},"w":1792532454503.402}
  #|{"step":"answered workspace.addMembers","w":1792532454504.364}
  #|{"in":{"id":21,"ok":{"joined":[],"added":["e2e-080726@example.test"],"already":[],"view":{"id":"01M5DKY0ZBKMJ6GSMJ7D9N001T","name":"Dev","role":"owner","created_at":1792532218,"members":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":"https://example.test/p.png","role":"owner","added_at":1792532218}],"stations":[{"id":"3f478fdc0fafa1a059f546ae5e01493a8c0684e1cdae03aa318f819879640e42","name":"studio","emoji":null,"icon":null,"enrolled_at":1792532219,"enrolled_by":"alice","last_seen":1792532224,"version":"0.1.0"}],"invitations":[],"added":[{"email":"e2e-080726@example.test","role":"member","added_by":"alice","added_at":1792532454}],"relays":[],"lock":null,"lock_requests":0}}},"w":1792532454552.717}
  #|{"in":{"id":15,"delta":[{"path":["added"],"append":[{"email":"e2e-080726@example.test","role":"member","added_by":"alice","added_at":1792532454}]}]},"w":1792532454569.354}
  #|{"in":{"id":9,"value":{"state":"slow","text":"studio 打开实时更新 ×2 · 3 秒 · 共 2 项","items":[{"state":"slow","text":"studio 打开实时更新 ×2","detail":"已等待 3 秒，尚未收到数据"}]}},"w":1792532454569.373}
  #|{"in":{"id":5,"value":{"state":"slow","text":"studio 打开实时更新 ×2 · 3 秒 · 共 2 项","items":[{"state":"slow","text":"studio 打开实时更新 ×2","detail":"已等待 3 秒，尚未收到数据"}]}},"w":1792532454569.384}
  #|{"step":"until =完成","w":1792532454570.973}
  #|{"step":"tap =完成","w":1792532454570.981}
  #|{"step":"tap =完成","acted":true,"w":1792532454587.704}
  #|{"step":"rest","w":1792532454603.014}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792532454652.682}
  #|{"in":{"id":9,"value":{"items":[]}},"w":1792532454652.696}
  #|{"in":{"id":16,"delta":[{"path":[0,"link","state"],"set":"online"},{"path":[0,"overview","counts","warm"],"set":0},{"path":[0,"overview","disk","freeBytes"],"set":58486226944},{"path":[0,"overview","profiles",0,"check","checkedAt"],"set":1792532454492},{"path":[0,"overview","profiles",0,"check","time","checkedAt","ago"],"set":"刚刚"},{"path":[0,"overview","profiles",0,"check","time","checkedAt","at"],"set":1792532454492},{"path":[0,"overview","profiles",0,"check","time","checkedAt","full"],"set":"10/21 05:40:54"},{"path":[0,"overview","updates",0,"checkedAt"],"set":1792532452272},{"path":[0,"overview","updates",1,"checkedAt"],"set":1792532452272},{"path":[0,"overview","updates",2,"checkedAt"],"set":1792532452272},{"path":[0,"overview","updates",3,"checkedAt"],"set":1792532452272},{"path":[0,"overview","updates",4,"checkedAt"],"set":1792532452272},{"path":[0,"reconnecting"],"set":false}]},"w":1792532454669.362}
  #|{"in":{"id":16,"delta":[{"path":[0,"host"],"set":{"hostname":"3720-Mac-mini-1","os":"macOS 27.0.1","arch":"arm64","cpus":10,"cpuModel":"Apple M4","load":0.36,"cpuBusy":0.1,"uptimeSec":11816,"memory":{"totalBytes":17179869184,"usedBytes":10256809984,"swapUsedBytes":341961605},"disk":{"path":"/tmp/mbe2e-C/data","totalBytes":245107195904,"freeBytes":58486222848},"emberRssBytes":139540016,"checkedAt":1792532454648,"summary":"10 核 · 16 GB","line":"macOS 27.0.1 · 10 核 · 16 GB · 已运行 0 天","facts":["3720-Mac-mini-1","macOS 27.0.1","arm64 · 10 核","已运行 3 小时"],"meters":[{"label":"CPU","short":"CPU","percent":10,"left":90,"level":"ok","value":"10%","remaining":"空闲 90%","big":"90","unit":"%","title":"CPU 空闲","total":"负载 3.6","note":"负载 3.6 · Apple M4"},{"label":"内存","short":"内存","percent":60,"left":40,"level":"ok","value":"9.6 GB / 16.0 GB","remaining":"剩 6.4 G","big":"6.4","unit":"GB","title":"内存剩","total":"共 16 GB","note":"swap 0.3 GB"},{"label":"磁盘","short":"磁盘","percent":76,"left":24,"level":"amber","value":"剩余 54.5 GB / 228 GB","remaining":"剩 54.5 G","big":"54.5","unit":"GB","title":"磁盘剩","total":"共 228 GB"}],"identity":"Apple M4 · 16 GB · macOS 27.0.1","details":[{"label":"主机名","value":"3720-Mac-mini-1"},{"label":"芯片","value":"Apple M4 · 10 核 · arm64"},{"label":"已运行","value":"3 小时"},{"label":"still.fail","value":"进程占用 133 MB"}],"usage":"内存 9.6 GB / 16.0 GB · 磁盘 剩余 54.5 GB / 228 GB","emberText":"still.fail 133 MB"}},{"path":[0,"line"],"set":"Apple M4"},{"path":[0,"summary"],"set":"空闲 · Apple M4 · 16 GB · macOS 27.0.1"}]},"w":1792532454802.718}
  #|{"in":{"id":7,"delta":[{"path":["days"],"key":["daysAgo"],"patch":0,"ops":[{"path":["items"],"key":["station","id"],"patch":["01M5DKY0ZBKMJ6GSMJ7D9N001T/3f478fdc0fafa1a059f546ae5e01493a8c0684e1cdae03aa318f819879640e42","ember:c-e5c56c6d05"],"ops":[{"path":["agents",0,"process"],"set":"cold"},{"path":["clientKey"],"remove":true}]}]}]},"w":1792532454802.775}
  #|{"in":{"id":16,"delta":[{"path":[0,"way"],"set":{"path":"直连","via":"direct"}}]},"w":1792532456102.71}
  #|{"step":"now until e2e-080726@example.test","w":1792532456103.649}
  #|{"step":"tap =移除","w":1792532456103.679}
  #|{"step":"tap =移除","acted":true,"w":1792532456120.222}
  #|{"out":{"id":22,"call":"workspace.removeAdded","params":{"workspace":"01M5DKY0ZBKMJ6GSMJ7D9N001T","email":"e2e-080726@example.test","account":"alice"}},"w":1792532456136.444}
  #|{"step":"answered workspace.removeAdded","w":1792532456136.934}
  #|{"in":{"id":19,"value":{"doing":[{"call":"workspace.removeAdded","params":{"workspace":"01M5DKY0ZBKMJ6GSMJ7D9N001T","email":"e2e-080726@example.test","account":"alice"},"since":1792532456136,"stage":"running"}]}},"w":1792532456202.704}
  #|{"in":{"id":15,"delta":[{"path":["added"],"set":[]},{"path":["stations",0,"last_seen"],"set":1792532454},{"path":["stations",0,"time","last_seen","ago"],"set":"刚刚"},{"path":["stations",0,"time","last_seen","at"],"set":1792532454000},{"path":["stations",0,"time","last_seen","full"],"set":"10/21 05:40:54"}]},"w":1792532456202.742}
  #|{"in":{"id":16,"delta":[{"path":[0,"lastSeen"],"set":1792532454},{"path":[0,"overview","disk","freeBytes"],"set":58486046720},{"path":[0,"time","lastSeen","ago"],"set":"刚刚"},{"path":[0,"time","lastSeen","at"],"set":1792532454000},{"path":[0,"time","lastSeen","full"],"set":"10/21 05:40:54"}]},"w":1792532456202.788}
  #|{"in":{"id":22,"ok":{"id":"01M5DKY0ZBKMJ6GSMJ7D9N001T","name":"Dev","role":"owner","created_at":1792532218,"members":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":"https://example.test/p.png","role":"owner","added_at":1792532218}],"stations":[{"id":"3f478fdc0fafa1a059f546ae5e01493a8c0684e1cdae03aa318f819879640e42","name":"studio","emoji":null,"icon":null,"enrolled_at":1792532219,"enrolled_by":"alice","last_seen":1792532454,"version":"0.1.0"}],"invitations":[],"added":[],"relays":[],"lock":null,"lock_requests":0}},"w":1792532456202.825}
  #|{"step":"gone e2e-080726@example.test","w":1792532456219.853}
  #|{"step":"tap =Workspace 图标","w":1792532456219.865}
  #|{"step":"tap =Workspace 图标","acted":true,"w":1792532456236.264}
  #|{"step":"rest","w":1792532456253.244}
  #|{"in":{"id":19,"value":{"doing":[]}},"w":1792532456269.359}
  #|{"step":"now tap =Emoji","w":1792532457753.882}
  #|{"step":"now tap =Emoji","acted":true,"w":1792532457770.696}
  #|{"step":"tap 粘贴或输入任意 emoji","w":1792532457787.179}
  #|{"step":"tap 粘贴或输入任意 emoji","acted":true,"w":1792532457835.864}
  #|{"step":"paste 🌲","w":1792532457846.845}
  #|{"step":"paste 🌲","acted":true,"w":1792532457847.906}
  #|{"out":{"id":23,"call":"workspace.rename","params":{"workspace":"01M5DKY0ZBKMJ6GSMJ7D9N001T","emoji":"🌲","icon":"","account":"alice"}},"w":1792532457852.864}
  #|{"step":"answered workspace.rename","w":1792532457853.725}
  #|{"in":{"id":19,"value":{"doing":[{"call":"workspace.rename","params":{"workspace":"01M5DKY0ZBKMJ6GSMJ7D9N001T","emoji":"🌲","icon":"","account":"alice"},"since":1792532457853,"stage":"running"}]}},"w":1792532457919.378}
  #|{"in":{"id":4,"delta":[{"path":[0,"workspaces",0,"emoji"],"set":"🌲"}]},"w":1792532457919.436}
  #|{"in":{"id":15,"delta":[{"path":["emoji"],"set":"🌲"}]},"w":1792532457919.449}
  #|{"in":{"id":16,"delta":[{"path":[0,"overview","disk","freeBytes"],"set":58485919744}]},"w":1792532457919.456}
  #|{"in":{"id":23,"ok":{"id":"01M5DKY0ZBKMJ6GSMJ7D9N001T","name":"Dev","emoji":"🌲","role":"owner","created_at":1792532218,"members":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":"https://example.test/p.png","role":"owner","added_at":1792532218}],"stations":[{"id":"3f478fdc0fafa1a059f546ae5e01493a8c0684e1cdae03aa318f819879640e42","name":"studio","emoji":null,"icon":null,"enrolled_at":1792532219,"enrolled_by":"alice","last_seen":1792532454,"version":"0.1.0"}],"invitations":[],"added":[],"relays":[],"lock":null,"lock_requests":0}},"w":1792532457919.475}
  #|{"step":"until 已设置图标","w":1792532457936.461}
  #|{"step":"rest","w":1792532457936.473}
  #|{"in":{"id":19,"value":{"doing":[]}},"w":1792532458002.674}
  #|{"step":"now until =🌲","w":1792532459353.301}
  #|{"step":"tap =Workspace 图标","w":1792532459353.33}
  #|{"step":"tap =Workspace 图标","acted":true,"w":1792532459370.259}
  #|{"step":"rest","w":1792532459386.879}
  #|{"step":"now tap =图标","w":1792532460887.536}
  #|{"step":"now tap =图标","acted":true,"w":1792532460904.094}
  #|{"step":"tap 搜索图标","w":1792532460920.843}
  #|{"step":"tap 搜索图标","acted":true,"w":1792532460954.18}
  #|{"step":"type zzzz","w":1792532460971.122}
  #|{"step":"type zzzz","acted":true,"w":1792532460971.165}
  #|{"step":"tap 不使用图标","w":1792532460990.84}
  #|{"step":"tap 不使用图标","acted":true,"w":1792532461004.068}
  #|{"out":{"id":24,"call":"workspace.rename","params":{"workspace":"01M5DKY0ZBKMJ6GSMJ7D9N001T","emoji":"","icon":"","account":"alice"}},"w":1792532461020.149}
  #|{"step":"answered workspace.rename","w":1792532461020.949}
  #|{"in":{"id":24,"ok":{"id":"01M5DKY0ZBKMJ6GSMJ7D9N001T","name":"Dev","role":"owner","created_at":1792532218,"members":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":"https://example.test/p.png","role":"owner","added_at":1792532218}],"stations":[{"id":"3f478fdc0fafa1a059f546ae5e01493a8c0684e1cdae03aa318f819879640e42","name":"studio","emoji":null,"icon":null,"enrolled_at":1792532219,"enrolled_by":"alice","last_seen":1792532454,"version":"0.1.0"}],"invitations":[],"added":[],"relays":[],"lock":null,"lock_requests":0}},"w":1792532461086.035}
  #|{"in":{"id":4,"delta":[{"path":[0,"workspaces",0,"emoji"],"remove":true}]},"w":1792532461086.091}
  #|{"in":{"id":15,"delta":[{"path":["emoji"],"remove":true}]},"w":1792532461086.105}
  #|{"in":{"id":16,"delta":[{"path":[0,"overview","disk","freeBytes"],"set":58485854208}]},"w":1792532461086.112}
  #|{"step":"rest","w":1792532461103.126}
  #|{"step":"now rest","w":1792532462520.073}
  #|{"step":"","w":1792532462536.828}
  #|{"textrec":{"ib":["bfd9b0d6dc602826",12668,64],"r":[56,56,56,56]}}
  #|{"textrec":{"s":[13,400,0,"正在读取你的 workspace"],"r":[0,1,12.898832684824903,0,1,1,12.898832684824903,1,2,1,12.898832684824903,2,3,1,12.898832684824903,3,4,1,12.898832684824896,4,5,1,12.898832684824896,5,6,1,3.580078125,-1,7,1,9.8642578125,6,8,1,7.4775390625,7,9,1,4.875,8,10,1,6.85546875,9,11,1,6.6015625,10,12,1,7.8583984375,11,13,1,7.0966796875,12,14,1,7.1982421875,13,15,1,7.3505859375,14]}}
  #|{"textrec":{"m":[13,400,0],"r":[12.568359375,2.7421875,18]}}
  #|{"textrec":{"s":[24,700,0,"Dev"],"r":[0,1,17.075823068618774,15,1,1,13.365240812301636,16,2,1,12.759063005447388,17]}}
  #|{"textrec":{"m":[24,700,0],"r":[23.203125,5.0625,34]}}
  #|{"textrec":{"g":15,"r":[0,0,18,19,0,-18,0]}}
  #|{"textrec":{"g":16,"r":[19,0,15,16,-1,-14,0]}}
  #|{"textrec":{"g":17,"r":[35,0,15,15,-1,-14,0]}}
  #|{"textrec":{"ib":["02698e60df92657e",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"ib":["fdb526ba00f881f4",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["1d51432b25a425eb",1108,64],"r":[16,16,16,16]}}
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
  #|{"textrec":{"s":[17,400,0,"设置"],"r":[0,1,16.851167315175097,185,1,1,16.851167315175097,186]}}
  #|{"textrec":{"s":[32,700,8,"Dev"],"r":[0,1,22.8046875,187,1,1,17.5390625,188,2,1,17.3046875,189]}}
  #|{"textrec":{"s":[13,400,0,"你是Owner · 1 人 · 1 台 station · 点击名称可重命名"],"r":[0,1,12.898832684824903,4,1,1,12.898832684824903,190,2,1,11.578125,191,3,1,9.9912109375,6,4,1,7.50927734375,192,5,1,7.3505859375,14,6,1,4.875,8,7,1,3.580078125,-1,8,1,6.228545204222115,193,9,1,3.580078125,-1,10,1,5.9541015625,194,11,1,3.580078125,-1,12,1,12.89883268482491,195,13,1,3.580078125,-1,14,1,6.228545204222115,193,15,1,3.580078125,-1,16,1,5.9541015625,194,17,1,3.580078125,-1,18,1,12.898832684824896,196,19,1,3.580078125,-1,20,1,6.69677734375,10,21,1,4.61474609375,82,22,1,7.0966796875,12,23,1,4.646484375,82,24,1,3.1357421875,77,25,1,7.6044921875,7,26,1,7.50927734375,192,27,1,3.580078125,-1,28,1,6.228545204222115,193,29,1,3.580078125,-1,30,1,12.898832684824896,197,31,1,12.898832684824896,198,32,1,12.898832684824896,199,33,1,12.898832684824896,200,34,1,12.898832684824924,201,35,1,12.898832684824924,202,36,1,12.898832684824924,203,37,1,12.898832684824924,199]}}
  #|{"textrec":{"s":[14,400,0,"未设置"],"r":[0,1,13.891050583657588,96,1,1,13.891050583657588,204,2,1,13.891050583657588,205]}}
  #|{"textrec":{"s":[15,400,0,"Workspace 图标"],"r":[0,1,13.916015625,87,1,1,8.26171875,88,2,1,5.478515625,89,3,1,7.763671875,90,4,1,7.470703125,91,5,1,8.9208984375,92,6,1,8.0419921875,93,7,1,8.1591796875,94,8,1,8.3349609375,95,9,1,3.984375,-1,10,1,14.88326848249028,206,11,1,14.88326848249028,207]}}
  #|{"textrec":{"s":[15,600,0,"成员"],"r":[0,1,14.883268482490273,208,1,1,14.883268482490273,209]}}
  #|{"textrec":{"s":[13,400,0,"1 人"],"r":[0,1,5.9541015625,194,1,1,3.580078125,-1,2,1,12.898832684824903,195]}}
  #|{"textrec":{"s":[13,400,0,"Owner"],"r":[0,1,9.953125,191,1,1,9.9912109375,6,2,1,7.50927734375,192,3,1,7.3505859375,14,4,1,4.875,8]}}
  #|{"textrec":{"s":[15,400,0,"Name of alice"],"r":[0,1,10.8984375,210,1,1,8.0419921875,93,2,1,12.8173828125,161,3,1,8.3349609375,95,4,1,3.984375,-1,5,1,8.6279296875,88,6,1,5.19287109375,107,7,1,3.984375,-1,8,1,8.0419921875,93,9,1,3.5595703125,108,10,1,3.4716796875,102,11,1,8.1591796875,94,12,1,8.3349609375,95]}}
  #|{"textrec":{"s":[12,400,0,"你"],"r":[0,1,11.918287937743191,211]}}
  #|{"textrec":{"m":[12,400,0],"r":[11.6015625,2.53125,17]}}
  #|{"textrec":{"s":[14,600,0,"N"],"r":[0,1,10.469682216644287,212]}}
  #|{"textrec":{"m":[14,600,0],"r":[13.53515625,2.953125,20]}}
  #|{"textrec":{"s":[15,600,0,"中继"],"r":[0,1,14.883268482490273,213,1,1,14.883268482490273,214]}}
  #|{"textrec":{"s":[15,400,0,"添加中继"],"r":[0,1,14.883268482490273,215,1,1,14.883268482490273,216,2,1,14.883268482490273,217,3,1,14.883268482490273,218]}}
  #|{"textrec":{"s":[13,400,0,"除 still.fail 的中继外，station 和成员设备也会通过这些中继连接，并自动选择最快的。"],"r":[0,1,12.898832684824903,219,1,1,3.580078125,-1,2,1,6.69677734375,10,3,1,4.61474609375,82,4,1,3.1357421875,77,5,1,3.2119140625,76,6,1,3.2119140625,76,7,1,3.5927734375,81,8,1,4.341796875,220,9,1,7.00146484375,12,10,1,3.1357421875,77,11,1,3.2119140625,76,12,1,3.580078125,-1,13,1,12.898832684824903,5,14,1,12.89883268482491,221,15,1,12.898832684824896,222,16,1,12.898832684824896,223,17,1,11.775875486381324,224,18,1,6.69677734375,10,19,1,4.61474609375,82,20,1,7.0966796875,12,21,1,4.646484375,82,22,1,3.1357421875,77,23,1,7.6044921875,7,24,1,7.50927734375,192,25,1,3.580078125,-1,26,1,12.898832684824896,225,27,1,12.898832684824896,140,28,1,12.898832684824896,226,29,1,12.898832684824896,227,30,1,12.898832684824896,228,31,1,12.898832684824896,229,32,1,12.898832684824924,230,33,1,12.898832684824924,154,34,1,12.898832684824924,231,35,1,12.898832684824924,232,36,1,12.898832684824924,233,37,1,12.898832684824924,221,38,1,12.898832684824924,222,39,1,12.898832684824924,234,40,1,12.898832684824924,235,41,1,13.075875486381335,224,42,1,12.898832684824924,236,43,1,12.898832684824924,237,44,1,12.898832684824924,238,45,1,12.898832684824924,239,46,1,12.898832684824924,240,47,1,12.898832684824924,241,48,1,12.898832684824924,242,49,1,12.898832684824924,5,50,1,6.575875486381335,243]}}
  #|{"textrec":{"s":[15,400,0,"退出此 workspace"],"r":[0,1,14.883268482490273,244,1,1,14.883268482490273,245,2,1,14.883268482490273,246,3,1,3.984375,-1,4,1,11.2353515625,247,5,1,8.481445312499993,88,6,1,5.478515625,89,7,1,7.763671875,90,8,1,7.470703125,91,9,1,8.9208984375,92,10,1,8.0419921875,93,11,1,8.1591796875,94,12,1,8.3349609375,95]}}
  #|{"textrec":{"s":[15,400,0,"删除 workspace"],"r":[0,1,14.883268482490273,248,1,1,14.883268482490273,249,2,1,3.984375,-1,3,1,11.2353515625,247,4,1,8.4814453125,88,5,1,5.478515625,89,6,1,7.763671875,90,7,1,7.470703125,91,8,1,8.9208984375,92,9,1,8.0419921875,93,10,1,8.1591796875,94,11,1,8.3349609375,95]}}
  #|{"textrec":{"g":185,"r":[1967,0,19,18,-1,-15,0]}}
  #|{"textrec":{"g":186,"r":[1987,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":187,"r":[2006,0,23,25,0,-24,0]}}
  #|{"textrec":{"g":188,"r":[0,32,19,21,-1,-19,0]}}
  #|{"textrec":{"g":189,"r":[20,32,19,19,-1,-18,0]}}
  #|{"textrec":{"g":4,"r":[40,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":190,"r":[55,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":191,"r":[70,32,12,13,-1,-11,0]}}
  #|{"textrec":{"g":6,"r":[83,32,12,9,-1,-8,0]}}
  #|{"textrec":{"g":192,"r":[96,32,8,9,0,-8,0]}}
  #|{"textrec":{"g":8,"r":[105,32,6,9,0,-8,0]}}
  #|{"textrec":{"g":193,"r":[112,32,4,5,1,-7,0]}}
  #|{"textrec":{"g":194,"r":[117,32,7,12,-1,-11,0]}}
  #|{"textrec":{"g":195,"r":[125,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":196,"r":[141,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":7,"r":[155,32,9,10,-1,-8,0]}}
  #|{"textrec":{"g":197,"r":[165,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":198,"r":[181,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":199,"r":[196,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":200,"r":[211,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":201,"r":[227,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":202,"r":[242,32,14,14,-1,-12,0]}}
  #|{"textrec":{"g":203,"r":[257,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":206,"r":[273,32,15,16,0,-13,0]}}
  #|{"textrec":{"g":207,"r":[289,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":208,"r":[306,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":209,"r":[324,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":213,"r":[341,32,15,17,0,-14,0]}}
  #|{"textrec":{"g":214,"r":[357,32,16,17,-1,-14,0]}}
  #|{"textrec":{"g":215,"r":[374,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":216,"r":[392,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":217,"r":[409,32,15,16,0,-13,0]}}
  #|{"textrec":{"g":218,"r":[425,32,16,16,-1,-14,0]}}
  #|{"textrec":{"g":219,"r":[442,32,14,15,0,-12,0]}}
  #|{"textrec":{"g":220,"r":[457,32,7,12,-1,-11,0]}}
  #|{"textrec":{"g":5,"r":[465,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":221,"r":[479,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":222,"r":[493,32,15,14,-1,-12,0]}}
  #|{"textrec":{"g":223,"r":[509,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":224,"r":[525,32,5,7,0,-3,0]}}
  #|{"textrec":{"g":225,"r":[531,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":140,"r":[546,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":226,"r":[562,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":227,"r":[577,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":228,"r":[593,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":229,"r":[609,32,15,14,-1,-12,0]}}
  #|{"textrec":{"g":230,"r":[625,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":154,"r":[641,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":231,"r":[657,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":232,"r":[673,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":233,"r":[689,32,14,14,-1,-12,0]}}
  #|{"textrec":{"g":234,"r":[704,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":235,"r":[720,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":236,"r":[736,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":237,"r":[751,32,11,15,1,-12,0]}}
  #|{"textrec":{"g":238,"r":[763,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":239,"r":[778,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":240,"r":[794,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":241,"r":[810,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":242,"r":[825,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":243,"r":[841,32,6,6,0,-3,0]}}
  #|{"textrec":{"g":244,"r":[848,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":245,"r":[865,32,15,16,0,-13,0]}}
  #|{"textrec":{"g":246,"r":[881,32,16,15,-1,-13,0]}}
  #|{"textrec":{"g":247,"r":[898,32,14,10,-1,-9,0]}}
  #|{"textrec":{"g":248,"r":[913,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":249,"r":[930,32,16,16,0,-13,0]}}
  #|{"textrec":{"g":212,"r":[947,32,11,12,0,-11,0]}}
  #|{"textrec":{"g":210,"r":[959,32,11,13,0,-12,0]}}
  #|{"textrec":{"g":161,"r":[971,32,13,11,0,-10,0]}}
  #|{"textrec":{"g":211,"r":[985,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":204,"r":[1000,32,16,15,-1,-12,0]}}
  #|{"textrec":{"g":205,"r":[1017,32,15,15,-1,-12,0]}}
  #|{"textrec":{"ib":["58f428943dcf9c03",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"s":[17,700,0,"添加成员"],"r":[0,1,16.851167315175097,250,1,1,16.851167315175097,251,2,1,16.851167315175097,252,3,1,16.851167315175097,253]}}
  #|{"textrec":{"m":[17,700,0],"r":[16.435546875,3.5859375,24]}}
  #|{"textrec":{"s":[14,400,0,"成员会直接加入「Dev」，无需对方接受：登录过 still.fail 的人立即加入，其他人首次用此邮箱登录时自动加入。"],"r":[0,1,13.891050583657588,254,1,1,13.891050583657588,255,2,1,13.891050583657588,256,3,1,13.891050583657588,257,4,1,13.891050583657588,258,5,1,13.891050583657588,259,6,1,20.891050583657588,260,7,1,5.066147859922182,261,8,1,10.021484375,262,9,1,7.779296875,59,10,1,7.369140624999986,263,11,1,6.543774319066159,264,12,1,14.081712062256798,50,13,1,13.891050583657602,265,14,1,13.891050583657602,266,15,1,13.891050583657602,267,16,1,13.891050583657602,268,17,1,13.891050583657602,258,18,1,13.891050583657602,269,19,1,14.081712062256798,270,20,1,13.891050583657574,271,21,1,13.891050583657602,272,22,1,13.891050583657602,273,23,1,3.787109375,-1,24,1,7.1435546875,274,25,1,4.9013671875,61,26,1,3.30859375,275,27,1,3.390625,276,28,1,3.390625,276,29,1,3.80078125,277,30,1,4.607421875,278,31,1,7.4716796875,57,32,1,3.30859375,275,33,1,3.390625,276,34,1,3.787109375,-1,35,1,13.891050583657602,56,36,1,13.891050583657602,176,37,1,13.891050583657602,279,38,1,13.891050583657602,280,39,1,13.891050583657602,259,40,1,13.891050583657602,260,41,1,14.081712062256827,50,42,1,13.891050583657602,281,43,1,13.891050583657602,282,44,1,13.891050583657602,176,45,1,13.891050583657602,283,46,1,13.891050583657602,284,47,1,13.891050583657602,55,48,1,13.891050583657602,285,49,1,13.891050583657602,286,50,1,13.891050583657602,287,51,1,13.891050583657602,271,52,1,13.891050583657602,272,53,1,13.891050583657602,288,54,1,13.891050583657602,289,55,1,13.891050583657602,290,56,1,13.891050583657602,259,57,1,13.891050583657602,260,58,1,7.08171206225677,291]}}
  #|{"textrec":{"s":[13,600,0,"邮箱"],"r":[0,1,12.898832684824903,292,1,1,12.898832684824903,293]}}
  #|{"textrec":{"m":[13,600,0],"r":[12.568359375,2.7421875,18]}}
  #|{"textrec":{"s":[14,600,0,"从 Slack 选择成员"],"r":[0,1,13.891050583657588,294,1,1,3.5793075561523438,-1,2,1,9.106021165847778,295,3,1,3.762936592102051,296,4,1,7.909732103347778,297,5,1,7.930358409881592,298,6,1,7.9685118198394775,299,7,1,3.5793075561523438,-1,8,1,13.891050583657588,300,9,1,13.891050583657588,301,10,1,13.891050583657588,302,11,1,13.891050583657588,303]}}
  #|{"textrec":{"s":[13,600,0,"角色"],"r":[0,1,12.898832684824903,304,1,1,12.898832684824903,305]}}
  #|{"textrec":{"s":[15,400,0,"成员"],"r":[0,1,14.883268482490273,306,1,1,14.883268482490273,307]}}
  #|{"textrec":{"s":[12,400,0,"使用 workspace 里的 station"],"r":[0,1,11.918287937743191,308,1,1,11.918287937743191,309,2,1,3.375,-1,3,1,9.17578125,310,4,1,6.97265625,311,5,1,4.5703125,312,6,1,6.3984375,313,7,1,6.1640625,314,8,1,7.324218749999993,315,9,1,6.62109375,316,10,1,6.71484375,317,11,1,6.85546875,318,12,1,3.375,-1,13,1,11.918287937743187,319,14,1,11.918287937743187,320,15,1,3.375,-1,16,1,6.251953125,314,17,1,4.330078125,321,18,1,6.62109375,316,19,1,4.359375,321,20,1,2.96484375,322,21,1,7.08984375,311,22,1,7.001953125,323]}}
  #|{"textrec":{"s":[15,400,0,"管理员"],"r":[0,1,14.883268482490273,324,1,1,14.883268482490273,325,2,1,14.883268482490273,307]}}
  #|{"textrec":{"s":[12,400,0,"邀请成员、添加和移除 station"],"r":[0,1,11.918287937743191,326,1,1,11.918287937743191,327,2,1,11.918287937743195,328,3,1,11.918287937743187,329,4,1,12.081712062256813,330,5,1,11.918287937743187,331,6,1,11.918287937743187,332,7,1,11.918287937743187,333,8,1,11.918287937743187,334,9,1,11.918287937743187,335,10,1,3.375,-1,11,1,6.251953124999986,314,12,1,4.330078125,321,13,1,6.62109375,316,14,1,4.359375,321,15,1,2.96484375,322,16,1,7.08984375,311,17,1,7.001953125,323]}}
  #|{"textrec":{"s":[15,400,0,"Owner"],"r":[0,1,11.337890625,336,1,1,11.3818359375,247,2,1,8.51806640625,103,3,1,8.3349609375,95,4,1,5.478515625,89]}}
  #|{"textrec":{"s":[12,400,0,"管理所有内容，包括成员角色和删除 workspace"],"r":[0,1,11.918287937743191,337,1,1,11.918287937743191,338,2,1,11.918287937743195,339,3,1,11.918287937743187,340,4,1,11.918287937743187,341,5,1,11.918287937743187,342,6,1,12.081712062256813,343,7,1,11.918287937743187,344,8,1,11.918287937743187,345,9,1,11.918287937743187,328,10,1,11.918287937743187,329,11,1,11.918287937743202,346,12,1,11.918287937743202,347,13,1,11.918287937743202,333,14,1,11.918287937743202,348,15,1,11.918287937743202,335,16,1,3.375,-1,17,1,9.17578125,310,18,1,6.97265625,311,19,1,4.5703125,312,20,1,6.3984375,313,21,1,6.1640625,314,22,1,7.32421875,315,23,1,6.62109375,316,24,1,6.71484375,317,25,1,6.85546875,318]}}
  #|{"textrec":{"s":[14,600,0,"取消"],"r":[0,1,13.891050583657588,349,1,1,13.891050583657588,350]}}
  #|{"textrec":{"s":[14,600,0,"添加"],"r":[0,1,13.891050583657588,351,1,1,13.891050583657588,352]}}
  #|{"textrec":{"g":250,"r":[1033,32,19,18,-1,-15,0]}}
  #|{"textrec":{"g":251,"r":[1053,32,18,18,-1,-15,0]}}
  #|{"textrec":{"g":252,"r":[1072,32,19,18,-1,-15,0]}}
  #|{"textrec":{"g":253,"r":[1092,32,18,18,-1,-15,0]}}
  #|{"textrec":{"g":254,"r":[1111,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":255,"r":[1128,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":256,"r":[1144,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":257,"r":[1161,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":258,"r":[1177,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":259,"r":[1193,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":260,"r":[1209,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":261,"r":[1226,32,7,12,-1.333333333333333,-13,0]}}
  #|{"textrec":{"g":262,"r":[1234,32,11,12,0,-11,0]}}
  #|{"textrec":{"g":263,"r":[1246,32,10,10,-1,-9,0]}}
  #|{"textrec":{"g":264,"r":[1257,32,7,11,-1,-8,0]}}
  #|{"textrec":{"g":265,"r":[1265,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":266,"r":[1281,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":267,"r":[1297,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":268,"r":[1313,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":269,"r":[1329,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":270,"r":[1345,32,5,10,1,-10,0]}}
  #|{"textrec":{"g":271,"r":[1351,32,16,15,-1,-13,0]}}
  #|{"textrec":{"g":272,"r":[1368,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":273,"r":[1384,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":274,"r":[1401,32,9,11,-1,-9,0]}}
  #|{"textrec":{"g":275,"r":[1411,32,5,13,-1,-12,0]}}
  #|{"textrec":{"g":276,"r":[1417,32,4,13,0,-12,0]}}
  #|{"textrec":{"g":277,"r":[1422,32,4,5,0,-3,0]}}
  #|{"textrec":{"g":278,"r":[1427,32,7,13,-1,-12,0]}}
  #|{"textrec":{"g":279,"r":[1435,32,16,15,-1,-13,0]}}
  #|{"textrec":{"g":280,"r":[1452,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":281,"r":[1468,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":282,"r":[1484,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":283,"r":[1500,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":284,"r":[1516,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":285,"r":[1533,32,16,14,-1,-12,0]}}
  #|{"textrec":{"g":286,"r":[1550,32,14,16,0,-13,0]}}
  #|{"textrec":{"g":287,"r":[1565,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":288,"r":[1581,32,15,16,0,-13,0]}}
  #|{"textrec":{"g":289,"r":[1597,32,12,16,1,-13,0]}}
  #|{"textrec":{"g":290,"r":[1610,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":291,"r":[1626,32,6,6,0,-3,0]}}
  #|{"textrec":{"g":292,"r":[1633,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":293,"r":[1648,32,15,15,-1,-12,0]}}
  #|{"textrec":{"s":[15,400,0,"name@example.com，可粘贴多个"],"r":[0,1,8.51806640625,103,1,1,8.0419921875,93,2,1,12.8173828125,161,3,1,8.3349609375,95,4,1,13.53515625,353,5,1,8.1884765625,95,6,1,7.4853515625,354,7,1,8.0419921875,93,8,1,12.8173828125,161,9,1,8.9208984375,92,10,1,3.5595703125,108,11,1,8.3349609375,95,12,1,4.072265625,160,13,1,8.0126953125,94,14,1,8.6279296875,88,15,1,12.8173828125,161,16,1,15.08754863813229,355,17,1,14.88326848249028,356,18,1,14.88326848249028,357,19,1,14.88326848249028,358,20,1,14.88326848249028,359,21,1,14.88326848249028,360]}}
  #|{"textrec":{"g":353,"r":[1664,32,14,15,0,-12,0]}}
  #|{"textrec":{"g":354,"r":[1679,32,10,10,-1,-9,0]}}
  #|{"textrec":{"g":160,"r":[1690,32,5,5,0,-3,0]}}
  #|{"textrec":{"g":355,"r":[1696,32,5,7,0,-3,0]}}
  #|{"textrec":{"g":356,"r":[1702,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":357,"r":[1719,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":358,"r":[1736,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":359,"r":[1753,32,15,16,0,-13,0]}}
  #|{"textrec":{"g":360,"r":[1769,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":294,"r":[1787,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":295,"r":[1804,32,11,14,-1,-12,0]}}
  #|{"textrec":{"g":296,"r":[1816,32,4,13,0,-12,0]}}
  #|{"textrec":{"g":297,"r":[1821,32,10,11,-1,-9,0]}}
  #|{"textrec":{"g":298,"r":[1832,32,10,11,-1,-9,0]}}
  #|{"textrec":{"g":299,"r":[1843,32,9,13,0,-12,0]}}
  #|{"textrec":{"g":300,"r":[1853,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":301,"r":[1870,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":302,"r":[1887,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":303,"r":[1904,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":304,"r":[1920,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":305,"r":[1935,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":306,"r":[1951,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":307,"r":[1969,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":308,"r":[1986,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":309,"r":[2001,32,13,14,-1,-11,0]}}
  #|{"textrec":{"g":310,"r":[2015,32,11,9,-1,-8,0]}}
  #|{"textrec":{"g":311,"r":[2027,32,9,10,-1,-8,0]}}
  #|{"textrec":{"g":312,"r":[2037,32,7,9,-1,-8,0]}}
  #|{"textrec":{"g":313,"r":[0,54,8,11,0,-10,0]}}
  #|{"textrec":{"g":314,"r":[9,54,8,10,-1,-8,0]}}
  #|{"textrec":{"g":315,"r":[18,54,9,12,-1,-8,0]}}
  #|{"textrec":{"g":316,"r":[28,54,8,10,-1,-8,0]}}
  #|{"textrec":{"g":317,"r":[37,54,9,10,-1,-8,0]}}
  #|{"textrec":{"g":318,"r":[47,54,9,10,-1,-8,0]}}
  #|{"textrec":{"g":319,"r":[57,54,13,13,-1,-11,0]}}
  #|{"textrec":{"g":320,"r":[71,54,13,14,-1,-11,0]}}
  #|{"textrec":{"g":321,"r":[85,54,6,11,-1,-9,0]}}
  #|{"textrec":{"g":322,"r":[92,54,5,11,-1,-10,0]}}
  #|{"textrec":{"g":323,"r":[98,54,9,9,-1,-8,0]}}
  #|{"textrec":{"g":324,"r":[108,54,16,17,-1,-14,0]}}
  #|{"textrec":{"g":325,"r":[125,54,17,16,-1,-13,0]}}
  #|{"textrec":{"g":326,"r":[143,54,14,14,-1,-11,0]}}
  #|{"textrec":{"g":327,"r":[158,54,14,14,-1,-11,0]}}
  #|{"textrec":{"g":328,"r":[173,54,14,14,-1,-11,0]}}
  #|{"textrec":{"g":329,"r":[188,54,13,14,-1,-11,0]}}
  #|{"textrec":{"g":330,"r":[202,54,6,6,0,-3,0]}}
  #|{"textrec":{"g":331,"r":[209,54,14,14,-1,-11,0]}}
  #|{"textrec":{"g":332,"r":[224,54,13,14,-1,-11,0]}}
  #|{"textrec":{"g":333,"r":[238,54,13,14,-1,-11,0]}}
  #|{"textrec":{"g":334,"r":[252,54,14,14,-1,-11,0]}}
  #|{"textrec":{"g":335,"r":[267,54,14,14,-1,-11,0]}}
  #|{"textrec":{"g":336,"r":[282,54,13,14,-1,-12,0]}}
  #|{"textrec":{"g":337,"r":[296,54,14,14,-1,-11,0]}}
  #|{"textrec":{"g":338,"r":[311,54,14,13,-1,-11,0]}}
  #|{"textrec":{"g":339,"r":[326,54,14,14,-1,-11,0]}}
  #|{"textrec":{"g":340,"r":[341,54,14,14,-1,-11,0]}}
  #|{"textrec":{"g":341,"r":[356,54,12,14,0,-11,0]}}
  #|{"textrec":{"g":342,"r":[369,54,14,14,-1,-11,0]}}
  #|{"textrec":{"g":343,"r":[384,54,5,6,0,-3,0]}}
  #|{"textrec":{"g":344,"r":[390,54,13,14,-1,-11,0]}}
  #|{"textrec":{"g":345,"r":[404,54,14,14,-1,-11,0]}}
  #|{"textrec":{"g":346,"r":[419,54,13,14,-1,-11,0]}}
  #|{"textrec":{"g":347,"r":[433,54,14,13,-1,-11,0]}}
  #|{"textrec":{"g":348,"r":[448,54,13,14,-1,-11,0]}}
  #|{"textrec":{"g":349,"r":[462,54,16,15,-1,-12,0]}}
  #|{"textrec":{"g":350,"r":[479,54,15,16,-1,-13,0]}}
  #|{"textrec":{"g":351,"r":[495,54,16,16,-1,-13,0]}}
  #|{"textrec":{"g":352,"r":[512,54,15,16,-1,-13,0]}}
  #|{"textrec":{"ib":["e13e77444a4987cd",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"s":[15,400,0,"e2e-080726@example.test"],"r":[0,1,8.3349609375,95,1,1,8.78173828125,361,2,1,8.29833984375,95,3,1,6.8408203125,362,4,1,9.2138671875,164,5,1,9.345703125,363,6,1,9.0673828125,164,7,1,8.1591796875,364,8,1,8.818359375,361,9,1,9.31640625,365,10,1,13.53515625,353,11,1,8.1884765625,95,12,1,7.4853515625,354,13,1,8.0419921875,93,14,1,12.8173828125,161,15,1,8.9208984375,92,16,1,3.5595703125,108,17,1,8.3349609375,95,18,1,4.072265625,160,19,1,5.013427734375,101,20,1,8.280029296875,95,21,1,7.58056640625,91,22,1,5.17822265625,101]}}
  #|{"textrec":{"g":361,"r":[528,54,10,13,0,-12,0]}}
  #|{"textrec":{"g":362,"r":[539,54,7,4,0,-6,0]}}
  #|{"textrec":{"g":164,"r":[547,54,11,14,-1,-12,0]}}
  #|{"textrec":{"g":363,"r":[559,54,11,14,-1,-12,0]}}
  #|{"textrec":{"g":364,"r":[571,54,10,13,-1,-12,0]}}
  #|{"textrec":{"g":365,"r":[582,54,11,14,-1,-12,0]}}
  #|{"textrec":{"s":[14,400,0,"1 人首次登录 still.fail 时自动加入。"],"r":[0,1,6.34375,175,1,1,3.787109375,-1,2,1,13.891050583657588,176,3,1,13.891050583657588,283,4,1,13.891050583657588,284,5,1,13.891050583657588,271,6,1,13.891050583657588,272,7,1,3.787109375,-1,8,1,7.1435546875,274,9,1,4.9013671875,61,10,1,3.30859375,275,11,1,3.390625,276,12,1,3.390625,276,13,1,3.80078125,277,14,1,4.607421875,278,15,1,7.4716796875,57,16,1,3.30859375,275,17,1,3.390625000000014,276,18,1,3.787109375,-1,19,1,13.891050583657602,288,20,1,13.891050583657602,289,21,1,13.891050583657602,290,22,1,13.891050583657602,259,23,1,13.891050583657602,260,24,1,7.081712062256798,291]}}
  #|{"textrec":{"s":[14,600,0,"完成"],"r":[0,1,13.891050583657588,366,1,1,13.891050583657588,302]}}
  #|{"textrec":{"g":366,"r":[594,54,16,16,-1,-13,0]}}
  #|{"textrec":{"s":[13,400,0,"1 人 · 1 人待加入"],"r":[0,1,5.9541015625,194,1,1,3.580078125,-1,2,1,12.898832684824903,195,3,1,3.580078125,-1,4,1,6.228545204222122,193,5,1,3.580078125,-1,6,1,5.9541015625,194,7,1,3.580078125,-1,8,1,12.898832684824903,195,9,1,12.898832684824903,367,10,1,12.898832684824896,368,11,1,12.898832684824896,369]}}
  #|{"textrec":{"s":[14,400,0,"移除"],"r":[0,1,13.891050583657588,370,1,1,13.891050583657588,371]}}
  #|{"textrec":{"s":[13,400,0,"成员 · 尚未登录，首次登录时自动加入"],"r":[0,1,12.898832684824903,140,1,1,12.898832684824903,226,2,1,3.580078125,-1,3,1,6.228545204222122,193,4,1,3.580078125,-1,5,1,12.898832684824903,372,6,1,12.898832684824896,373,7,1,12.898832684824896,374,8,1,12.898832684824896,375,9,1,13.075875486381321,224,10,1,12.89883268482491,376,11,1,12.898832684824896,377,12,1,12.898832684824896,374,13,1,12.898832684824896,375,14,1,12.898832684824896,153,15,1,12.898832684824896,237,16,1,12.898832684824896,238,17,1,12.898832684824896,368,18,1,12.898832684824896,369]}}
  #|{"textrec":{"s":[14,600,0,"E"],"r":[0,1,8.42106556892395,378]}}
  #|{"textrec":{"g":367,"r":[611,54,15,15,-1,-12,0]}}
  #|{"textrec":{"g":368,"r":[627,54,14,15,-1,-12,0]}}
  #|{"textrec":{"g":369,"r":[642,54,15,15,-1,-12,0]}}
  #|{"textrec":{"g":378,"r":[658,54,9,12,0,-11,0]}}
  #|{"textrec":{"g":372,"r":[668,54,13,15,0,-12,0]}}
  #|{"textrec":{"g":373,"r":[682,54,15,15,-1,-12,0]}}
  #|{"textrec":{"g":374,"r":[698,54,15,14,-1,-12,0]}}
  #|{"textrec":{"g":375,"r":[714,54,14,14,-1,-11,0]}}
  #|{"textrec":{"g":376,"r":[729,54,14,15,-1,-12,0]}}
  #|{"textrec":{"g":377,"r":[744,54,15,15,-1,-12,0]}}
  #|{"textrec":{"g":153,"r":[760,54,15,15,-1,-12,0]}}
  #|{"textrec":{"g":370,"r":[776,54,16,16,-1,-13,0]}}
  #|{"textrec":{"g":371,"r":[793,54,15,15,0,-12,0]}}
  #|{"textrec":{"s":[14,400,0,"已移除"],"r":[0,1,13.891050583657588,379,1,1,13.891050583657588,370,2,1,13.891050583657588,371]}}
  #|{"textrec":{"g":379,"r":[809,54,14,14,0,-12,0]}}
  #|{"textrec":{"s":[17,700,0,"为 Dev 选择图标"],"r":[0,1,16.851167315175097,380,1,1,3.951171875,-1,2,1,12.272705078125,381,3,1,9.657958984375,382,4,1,9.350830078125,383,5,1,3.951171875,-1,6,1,16.851167315175097,384,7,1,16.85116731517509,385,8,1,16.851167315175104,386,9,1,16.851167315175104,387]}}
  #|{"textrec":{"s":[14,400,0,"图标"],"r":[0,1,13.891050583657588,388,1,1,13.891050583657588,389]}}
  #|{"textrec":{"s":[14,400,0,"Emoji"],"r":[0,1,8.189453125,390,1,1,12.03125,391,2,1,8.12109375,392,3,1,3.3017578125,393,4,1,3.30859375,275]}}
  #|{"textrec":{"g":380,"r":[824,54,18,18,-1,-15,0]}}
  #|{"textrec":{"g":381,"r":[843,54,13,14,0,-13,0]}}
  #|{"textrec":{"g":382,"r":[857,54,12,13,-1,-11,0]}}
  #|{"textrec":{"g":383,"r":[870,54,12,12,-1,-11,0]}}
  #|{"textrec":{"g":384,"r":[883,54,18,18,-1,-15,0]}}
  #|{"textrec":{"g":385,"r":[902,54,19,18,-1,-15,0]}}
  #|{"textrec":{"g":386,"r":[922,54,17,18,0,-15,0]}}
  #|{"textrec":{"g":387,"r":[940,54,19,18,-1,-15,0]}}
  #|{"textrec":{"g":388,"r":[960,54,14,15,0,-12,0]}}
  #|{"textrec":{"g":389,"r":[975,54,16,16,-1,-13,0]}}
  #|{"textrec":{"g":390,"r":[992,54,9,12,0,-11,0]}}
  #|{"textrec":{"g":391,"r":[1002,54,13,10,0,-9,0]}}
  #|{"textrec":{"g":392,"r":[1016,54,10,11,-1,-9,0]}}
  #|{"textrec":{"g":393,"r":[1027,54,6,16,-2,-12,0]}}
  #|{"textrec":{"s":[15,400,0,"搜索图标"],"r":[0,1,14.883268482490273,18,1,1,14.883268482490273,19,2,1,14.883268482490273,206,3,1,14.883268482490273,207]}}
  #|{"textrec":{"ib":["c59432c5000c83af",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["f3a63645b2b177c6",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["852b4e6a49d3648f",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["fd874e05fb9b5192",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["b18c1cc3846c3baa",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["fdbd52a7420b8407",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["0140c2fcc55fb7a3",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["9872acd75025fa45",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["e3625ff7b887e5d5",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["f70d27221324e04d",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["2e433cf14d12a470",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["52165091c406f76e",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["81ebb6c22de7d807",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["73276ca2e98dac36",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["831b4b6395caefb3",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["e18616ba8edb6199",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["9d47fa06c59e694f",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["92ba415d1cbe60c9",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["e4b1db8f02b00443",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["6e6f9ccfe1de4d2a",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["cb260dab697695da",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["256bba7de97c7543",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["d5496ec447f8d228",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["dd2cbe3041e90a66",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["178cee66652be656",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["0f44b5fd6962fc13",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["2af8b0987fc90f7e",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["b8dab9fa3f1ff73f",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["da5e61986e576501",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["851f0a949e744371",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["309f625f422dc1d7",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["54eff43d780f079e",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["7a06953d95c0f059",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["e1b77d200c5c4c25",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["62958280f5f10d73",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["69ecc233357449dc",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["a80e1a07af2c98d8",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["39654e104d774096",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["fd4ed8de2daaacd8",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["263c1aa2c6e9443d",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["5f604515b302a091",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["f669c84831d9b180",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["c2d20a08c8bba55e",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["4d704c8399a0d4a5",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["3f361b2a077f6740",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["bb082ad546583b2b",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["52f8bea21fed46ff",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"ib":["424d7ced268f76bc",2396,64],"r":[24,24,24,24]}}
  #|{"textrec":{"s":[26,400,0,"🖥️"],"r":[0,3,30,394]}}
  #|{"textrec":{"m":[26,400,0],"r":[25.13671875,5.484375,37]}}
  #|{"textrec":{"s":[26,400,0,"💻"],"r":[0,2,30,395]}}
  #|{"textrec":{"s":[26,400,0,"🍎"],"r":[0,2,30,396]}}
  #|{"textrec":{"s":[26,400,0,"🐧"],"r":[0,2,30,397]}}
  #|{"textrec":{"s":[26,400,0,"🪟"],"r":[0,2,30,398]}}
  #|{"textrec":{"s":[26,400,0,"☁️"],"r":[0,2,30,399]}}
  #|{"textrec":{"s":[26,400,0,"🏠"],"r":[0,2,30,400]}}
  #|{"textrec":{"s":[26,400,0,"🏢"],"r":[0,2,30,401]}}
  #|{"textrec":{"s":[26,400,0,"🚀"],"r":[0,2,30,402]}}
  #|{"textrec":{"s":[26,400,0,"⚡"],"r":[0,1,30,403]}}
  #|{"textrec":{"s":[26,400,0,"🔥"],"r":[0,2,30,404]}}
  #|{"textrec":{"s":[26,400,0,"🧪"],"r":[0,2,30,405]}}
  #|{"textrec":{"s":[26,400,0,"🛠️"],"r":[0,3,30,406]}}
  #|{"textrec":{"s":[26,400,0,"🐳"],"r":[0,2,30,407]}}
  #|{"textrec":{"s":[26,400,0,"🦀"],"r":[0,2,30,408]}}
  #|{"textrec":{"s":[26,400,0,"🐙"],"r":[0,2,30,409]}}
  #|{"textrec":{"s":[26,400,0,"🌲"],"r":[0,2,30,410]}}
  #|{"textrec":{"s":[26,400,0,"🌊"],"r":[0,2,30,411]}}
  #|{"textrec":{"s":[26,400,0,"🌙"],"r":[0,2,30,412]}}
  #|{"textrec":{"s":[26,400,0,"☀️"],"r":[0,2,30,413]}}
  #|{"textrec":{"s":[26,400,0,"🍊"],"r":[0,2,30,414]}}
  #|{"textrec":{"s":[26,400,0,"🍋"],"r":[0,2,30,415]}}
  #|{"textrec":{"s":[26,400,0,"🍇"],"r":[0,2,30,416]}}
  #|{"textrec":{"s":[26,400,0,"🐱"],"r":[0,2,30,417]}}
  #|{"textrec":{"s":[26,400,0,"🐶"],"r":[0,2,30,418]}}
  #|{"textrec":{"s":[26,400,0,"🦊"],"r":[0,2,30,419]}}
  #|{"textrec":{"s":[26,400,0,"🐼"],"r":[0,2,30,420]}}
  #|{"textrec":{"s":[26,400,0,"🐸"],"r":[0,2,30,421]}}
  #|{"textrec":{"s":[26,400,0,"🦉"],"r":[0,2,30,422]}}
  #|{"textrec":{"s":[26,400,0,"🐝"],"r":[0,2,30,423]}}
  #|{"textrec":{"s":[26,400,0,"🦄"],"r":[0,2,30,424]}}
  #|{"textrec":{"s":[26,400,0,"🐢"],"r":[0,2,30,425]}}
  #|{"textrec":{"s":[26,400,0,"🌵"],"r":[0,2,30,426]}}
  #|{"textrec":{"s":[26,400,0,"🌸"],"r":[0,2,30,427]}}
  #|{"textrec":{"s":[26,400,0,"🍄"],"r":[0,2,30,428]}}
  #|{"textrec":{"s":[26,400,0,"🌈"],"r":[0,2,30,429]}}
  #|{"textrec":{"s":[26,400,0,"❄️"],"r":[0,2,30,430]}}
  #|{"textrec":{"s":[26,400,0,"⭐"],"r":[0,1,30,431]}}
  #|{"textrec":{"s":[26,400,0,"🪐"],"r":[0,2,30,432]}}
  #|{"textrec":{"s":[26,400,0,"🌍"],"r":[0,2,30,433]}}
  #|{"textrec":{"s":[26,400,0,"🍉"],"r":[0,2,30,434]}}
  #|{"textrec":{"s":[26,400,0,"🍒"],"r":[0,2,30,435]}}
  #|{"textrec":{"s":[26,400,0,"🥑"],"r":[0,2,30,436]}}
  #|{"textrec":{"s":[26,400,0,"🍕"],"r":[0,2,30,437]}}
  #|{"textrec":{"s":[26,400,0,"☕"],"r":[0,1,30,438]}}
  #|{"textrec":{"s":[26,400,0,"🎧"],"r":[0,2,30,439]}}
  #|{"textrec":{"s":[26,400,0,"🎮"],"r":[0,2,30,440]}}
  #|{"textrec":{"s":[26,400,0,"🤖"],"r":[0,2,30,441]}}
  #|{"textrec":{"s":[15,400,0,"上传图片"],"r":[0,1,14.883268482490273,442,1,1,14.883268482490273,443,2,1,14.883268482490273,206,3,1,14.883268482490273,444]}}
  #|{"textrec":{"s":[15,400,0,"粘贴或输入任意 emoji"],"r":[0,1,14.883268482490273,357,1,1,14.883268482490273,358,2,1,14.883268482490273,445,3,1,14.883268482490273,446,4,1,14.88326848249028,447,5,1,14.88326848249028,448,6,1,14.88326848249028,449,7,1,3.984375,-1,8,1,8.3349609375,95,9,1,12.8173828125,161,10,1,8.6279296875,88,11,1,3.46435546875,450,12,1,3.4716796875,102]}}
  #|{"textrec":{"g":445,"r":[1034,54,16,16,-1,-13,0]}}
  #|{"textrec":{"g":446,"r":[1051,54,17,16,-1,-13,0]}}
  #|{"textrec":{"g":447,"r":[1069,54,16,16,-1,-13,0]}}
  #|{"textrec":{"g":448,"r":[1086,54,16,16,-1,-13,0]}}
  #|{"textrec":{"g":449,"r":[1103,54,16,17,-1,-14,0]}}
  #|{"textrec":{"g":450,"r":[1120,54,6,17,-2,-13,0]}}
  #|{"textrec":{"g":394,"r":[1127,54,32,34,-1,-27,1]}}
  #|{"textrec":{"g":395,"r":[1160,54,32,34,-1,-27,1]}}
  #|{"textrec":{"g":396,"r":[1193,54,32,34,-1,-27,1]}}
  #|{"textrec":{"g":397,"r":[1226,54,32,34,-1,-27,1]}}
  #|{"textrec":{"g":398,"r":[1259,54,32,34,-1,-27,1]}}
  #|{"textrec":{"g":399,"r":[1292,54,32,34,-1,-27,1]}}
  #|{"textrec":{"g":400,"r":[1325,54,32,34,-1,-27,1]}}
  #|{"textrec":{"g":401,"r":[1358,54,32,34,-1,-27,1]}}
  #|{"textrec":{"g":402,"r":[1391,54,32,34,-1,-27,1]}}
  #|{"textrec":{"g":403,"r":[1424,54,32,34,-1,-27,1]}}
  #|{"textrec":{"g":404,"r":[1457,54,32,34,-1,-27,1]}}
  #|{"textrec":{"g":405,"r":[1490,54,32,34,-1,-27,1]}}
  #|{"textrec":{"g":406,"r":[1523,54,32,34,-1,-27,1]}}
  #|{"textrec":{"g":407,"r":[1556,54,32,34,-1,-27,1]}}
  #|{"textrec":{"g":408,"r":[1589,54,32,34,-1,-27,1]}}
  #|{"textrec":{"g":409,"r":[1622,54,32,34,-1,-27,1]}}
  #|{"textrec":{"g":410,"r":[1655,54,32,34,-1,-27,1]}}
  #|{"textrec":{"g":411,"r":[1688,54,32,34,-1,-27,1]}}
  #|{"textrec":{"g":412,"r":[1721,54,32,34,-1,-27,1]}}
  #|{"textrec":{"g":413,"r":[1754,54,32,34,-1,-27,1]}}
  #|{"textrec":{"g":414,"r":[1787,54,32,34,-1,-27,1]}}
  #|{"textrec":{"g":415,"r":[1820,54,32,34,-1,-27,1]}}
  #|{"textrec":{"g":416,"r":[1853,54,32,34,-1,-27,1]}}
  #|{"textrec":{"g":417,"r":[1886,54,32,34,-1,-27,1]}}
  #|{"textrec":{"g":418,"r":[1919,54,32,34,-1,-27,1]}}
  #|{"textrec":{"g":419,"r":[1952,54,32,34,-1,-27,1]}}
  #|{"textrec":{"g":420,"r":[1985,54,32,34,-1,-27,1]}}
  #|{"textrec":{"g":421,"r":[0,89,32,34,-1,-27,1]}}
  #|{"textrec":{"g":422,"r":[33,89,32,34,-1,-27,1]}}
  #|{"textrec":{"g":423,"r":[66,89,32,34,-1,-27,1]}}
  #|{"textrec":{"g":424,"r":[99,89,32,34,-1,-27,1]}}
  #|{"textrec":{"g":425,"r":[132,89,32,34,-1,-27,1]}}
  #|{"textrec":{"g":426,"r":[165,89,32,34,-1,-27,1]}}
  #|{"textrec":{"g":427,"r":[198,89,32,34,-1,-27,1]}}
  #|{"textrec":{"g":428,"r":[231,89,32,34,-1,-27,1]}}
  #|{"textrec":{"g":429,"r":[264,89,32,34,-1,-27,1]}}
  #|{"textrec":{"g":430,"r":[297,89,32,34,-1,-27,1]}}
  #|{"textrec":{"g":431,"r":[330,89,32,34,-1,-27,1]}}
  #|{"textrec":{"g":432,"r":[363,89,32,34,-1,-27,1]}}
  #|{"textrec":{"g":433,"r":[396,89,32,34,-1,-27,1]}}
  #|{"textrec":{"g":434,"r":[429,89,32,34,-1,-27,1]}}
  #|{"textrec":{"g":435,"r":[462,89,32,34,-1,-27,1]}}
  #|{"textrec":{"g":436,"r":[495,89,32,34,-1,-27,1]}}
  #|{"textrec":{"g":437,"r":[528,89,32,34,-1,-27,1]}}
  #|{"textrec":{"g":438,"r":[561,89,32,34,-1,-27,1]}}
  #|{"textrec":{"g":439,"r":[594,89,32,34,-1,-27,1]}}
  #|{"textrec":{"g":440,"r":[627,89,32,34,-1,-27,1]}}
  #|{"textrec":{"g":441,"r":[660,89,32,34,-1,-27,1]}}
  #|{"textrec":{"g":442,"r":[693,89,16,15,-1,-13,0]}}
  #|{"textrec":{"g":443,"r":[710,89,17,16,-1,-13,0]}}
  #|{"textrec":{"g":444,"r":[728,89,15,16,0,-13,0]}}
  #|{"textrec":{"ib":["8c7eb8ec73207294",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"s":[14,400,0,"已设置图标"],"r":[0,1,13.891050583657588,379,1,1,13.891050583657588,204,2,1,13.891050583657588,205,3,1,13.891050583657588,388,4,1,13.891050583657588,389]}}
  #|{"textrec":{"s":[27,400,0,"🌲"],"r":[0,2,31,451]}}
  #|{"textrec":{"m":[27,400,0],"r":[26.103515625,5.6953125,38]}}
  #|{"textrec":{"s":[18,400,0,"🌲"],"r":[0,2,24,452]}}
  #|{"textrec":{"m":[18,400,0],"r":[17.40234375,3.796875,26]}}
  #|{"textrec":{"g":451,"r":[744,89,33,35,-1,-28,1]}}
  #|{"textrec":{"g":452,"r":[778,89,26,24,-1,-19,1]}}
  #|{"textrec":{"ib":["eb4b656b422604d1",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["7bcaf0ba053d9a45",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["da3b3bab9d01d4f7",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"s":[15,400,0,"不使用图标"],"r":[0,1,14.883268482490273,453,1,1,14.883268482490273,454,2,1,14.883268482490273,115,3,1,14.883268482490273,206,4,1,14.88326848249028,207]}}
  #|{"textrec":{"s":[15,400,0,"zzzz"],"r":[0,1,7.8515625,455,1,1,7.8515625,455,2,1,7.8515625,455,3,1,7.8515625,455]}}
  #|{"textrec":{"s":[15,400,0,"未找到图标"],"r":[0,1,14.883268482490273,456,1,1,14.883268482490273,457,2,1,14.883268482490273,458,3,1,14.883268482490273,206,4,1,14.88326848249028,207]}}
  #|{"textrec":{"g":455,"r":[805,89,9,10,0,-9,0]}}
  #|{"textrec":{"g":456,"r":[815,89,16,16,-1,-13,0]}}
  #|{"textrec":{"g":457,"r":[832,89,16,16,-1,-13,0]}}
  #|{"textrec":{"g":458,"r":[849,89,16,16,-1,-13,0]}}
  #|{"textrec":{"g":453,"r":[866,89,16,16,-1,-13,0]}}
  #|{"textrec":{"g":454,"r":[883,89,17,17,-1,-14,0]}}
  #|{"textrec":{"ib":["89c5d19878d01c5b",1688,64],"r":[20,20,20,20]}}
