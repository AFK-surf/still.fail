// e2e/traces/station-rename.trace, made by scripts/trace.py from 04-station_rename.log: not edited by hand.

///|
/// What the app and its core said in the run, a line each.
pub let trace_station_rename : String =
  #|{"start":"base"}
  #|{"step":"drive-seed 082939"}
  #|{"env":{"MBUI_CLOUD":"http://127.0.0.1:18900","MBUI_CORE_ACCOUNT":"{\"sub\":\"alice\",\"email\":\"alice@example.test\",\"name\":\"Name of alice\",\"picture\":\"\",\"access\":\"-\",\"refresh\":\"-\",\"accessExpires\":1792529364}"}}
  #|{"out":{"id":1,"call":"client.device","params":{"client":"still.fail mbui","app":"desktop","userAgent":"Macintosh; Mac OS X"}},"w":1792529131262.326}
  #|{"in":{"id":1,"ok":null},"w":1792529132327.901}
  #|{"out":{"id":2,"subscribe":{"topic":"accounts"},"keyed":true},"w":1792529132327.948}
  #|{"out":{"id":3,"subscribe":{"topic":"prefs"},"keyed":true},"w":1792529132327.97}
  #|{"step":"# written by scripts/rerecord.sh from its test (src/sfreplay/emit.mbt): not edited by hand","w":1792529132364.867}
  #|{"step":"timeout 90000","w":1792529132365.154}
  #|{"step":"answered client.device","w":1792529132365.99}
  #|{"step":"answered client.focus","w":1792529132916.452}
  #|{"in":{"id":2,"value":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""}]},"w":1792529133724.735}
  #|{"in":{"id":3,"value":{"onlyMine":false,"onlyWatching":false,"onlyDecisions":false,"listFilter":{},"appearance":"system","rowPicture":"auto","absoluteTime":false,"lang":"zh","keys":{},"lastChat":{},"openChat":{},"chatTabs":{},"dropFiles":{},"driveViews":{},"resume":{},"stationUpdatesDismissed":{},"device":{"app":"desktop","phone":false,"handoff":false},"reader":{"size":18,"line":1.7,"margin":22,"face":"sans","indent":true,"paper":"follow"},"rails":{},"bars":{"sets":[["chats","files","profiles","stations"],["decisions","usage","connects","archive"]],"current":0},"barsBy":{}}},"w":1792529133725.371}
  #|{"out":{"id":4,"subscribe":{"topic":"workspaces"},"keyed":true},"w":1792529133725.413}
  #|{"out":{"id":5,"subscribe":{"topic":"status"},"keyed":true},"w":1792529133725.434}
  #|{"in":{"id":4,"value":[{"account":{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""},"workspaces":[{"id":"01M5DGXKV9S6M382F9X64C8V7T","name":"Dev","role":"owner","created_at":1792529059,"stations":1,"members":1,"relays":[],"time":{"created_at":{"past":true,"at":1792529059000,"ago":"1 分钟前","full":"10/21 04:44:19","until":"1 分钟内"}}}],"invitations":[],"relay_url":"http://127.0.0.1:18940","loaded":true,"beta":true}]},"w":1792529133740.985}
  #|{"in":{"id":5,"value":{"state":"slow","text":"正在连接 studio · 2 秒 · 共 2 项","items":[{"state":"slow","text":"正在连接 studio","detail":"已等待 2 秒"},{"state":"slow","text":"studio 打开实时更新","detail":"已等待 2 秒，尚未收到数据"}]}},"w":1792529133741.05}
  #|{"out":{"id":6,"subscribe":{"topic":"lock","workspace":"01M5DGXKV9S6M382F9X64C8V7T"},"keyed":true},"w":1792529133741.128}
  #|{"out":{"id":7,"subscribe":{"topic":"chats","scope":"01M5DGXKV9S6M382F9X64C8V7T","mine":false},"keyed":true},"w":1792529133741.316}
  #|{"out":{"id":8,"subscribe":{"topic":"workspaceMarks","workspace":"01M5DGXKV9S6M382F9X64C8V7T"},"keyed":true},"w":1792529133741.642}
  #|{"out":{"id":9,"subscribe":{"topic":"status","workspace":"01M5DGXKV9S6M382F9X64C8V7T"},"keyed":true},"w":1792529133741.722}
  #|{"out":{"id":10,"call":"client.focus","params":{"visible":true,"focused":true,"workspace":"01M5DGXKV9S6M382F9X64C8V7T"}},"w":1792529133766.844}
  #|{"out":{"id":11,"subscribe":{"topic":"notify"},"keyed":true},"w":1792529133766.879}
  #|{"out":{"id":12,"subscribe":{"topic":"notify","workspace":"01M5DGXKV9S6M382F9X64C8V7T"},"keyed":true},"w":1792529133766.898}
  #|{"in":{"id":6,"value":{"available":true,"locked":false,"notice":true,"role":"owner","manages":true,"owner":true,"canSign":true,"signs":false,"me":{"device":"00cb202f6dec0b293d76bd23f73e0dd619123df8213927bcdfc8d75821088da2","code":"SYM-FEK","kind":"app","confirmed":false,"waiting":false,"asked":false},"signers":0,"members":[],"stations":[{"id":"88a5ce0cf215b1e3267a98a057c8b17394922e982d6b46cbfea0dedd6df10706","name":"studio","version":"0.1.0","online":true,"protected":false}],"protected":0,"requests":[],"renew":[],"attention":0}},"w":1792529133785.874}
  #|{"in":{"id":7,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"stations":[{"station":"01M5DGXKV9S6M382F9X64C8V7T/88a5ce0cf215b1e3267a98a057c8b17394922e982d6b46cbfea0dedd6df10706","id":"88a5ce0cf215b1e3267a98a057c8b17394922e982d6b46cbfea0dedd6df10706","name":"studio","state":"online"}],"loading":false,"days":[{"daysAgo":0,"at":1792529064420,"label":"今天","items":[{"id":"ember:c-45483a50d8","session":"ember:c-45483a50d8","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","agents":[{"key":"ember:c-45483a50d8","runtime":"claude","process":"warm","pending":0,"lastTurn":{"id":"7024836f-0be2-4319-ab37-554aacc82567","kind":"input","outcome":"completed","declared":"final","ending":"all_done","need":"answered the question that was asked","startedAt":1792529064270,"endedAt":1792529064425},"agentText":"默认模型","statusText":"已完成：answered the question that was asked"}],"last":{"seq":2,"authorKind":"agent","author":"ember:c-45483a50d8","text":"你好，我是测试用的 agent","createdAt":1792529064420,"by":{"kind":"agent","name":"agent","mine":false,"runtime":"claude","label":"agent"},"preview":"你好，我是测试用的 agent","time":{"createdAt":{"at":1792529064420,"ago":"1 分钟前","full":"10/21 04:44:24","until":"1 分钟内","past":true}}},"unread":true,"mine":true,"lastActiveAt":1792529064420,"station":"01M5DGXKV9S6M382F9X64C8V7T/88a5ce0cf215b1e3267a98a057c8b17394922e982d6b46cbfea0dedd6df10706","stationName":"studio","time":{"lastActiveAt":{"at":1792529064420,"ago":"1 分钟前","full":"10/21 04:44:24","until":"1 分钟内","past":true}},"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"peopleText":"你 发起","clientKey":"new:chat-f109494dda205412bd","pinned":false,"tone":"done"}]}],"trouble":null,"members":1,"leading":"agents","glyph":{"online":1,"dim":0,"connecting":0,"failing":0,"working":0,"summary":"studio","label":"1 台 station，1 台在线"},"note":{"reading":false,"text":null,"failing":[],"empty":false}}},"w":1792529133785.931}
  #|{"in":{"id":8,"value":{"workspaces":{"01M5DGXKV9S6M382F9X64C8V7T":{"alert":0,"unread":1,"tone":"done","label":"1 个有新消息","badge":0,"items":[],"mineTone":"done"}},"badge":0,"badgeCounts":"attention","badgeKinds":{"on":true,"wait":true,"failed":true,"done":false,"message":false}}},"w":1792529133785.977}
  #|{"in":{"id":9,"value":{"state":"slow","text":"正在连接 studio · 2 秒 · 共 2 项","items":[{"state":"slow","text":"正在连接 studio","detail":"已等待 2 秒"},{"state":"slow","text":"studio 打开实时更新","detail":"已等待 2 秒，尚未收到数据"}]}},"w":1792529133787.782}
  #|{"in":{"id":10,"ok":null},"w":1792529133787.809}
  #|{"in":{"id":11,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792529133787.824}
  #|{"in":{"id":12,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792529133787.834}
  #|{"out":{"id":13,"subscribe":{"topic":"longJobs","scope":"01M5DGXKV9S6M382F9X64C8V7T"},"keyed":true},"w":1792529133787.929}
  #|{"out":{"id":14,"call":"notify.permission","params":{"state":"unknown"}},"w":1792529133804.531}
  #|{"in":{"id":13,"value":{"groups":[]}},"w":1792529133845.786}
  #|{"in":{"id":14,"ok":null},"w":1792529133850.541}
  #|{"step":"answered notify.permission","w":1792529133860.357}
  #|{"step":"until 端到端测试","w":1792529133876.038}
  #|{"step":"tap icon:settings","w":1792529133876.056}
  #|{"step":"tap icon:settings","acted":true,"w":1792529133908.691}
  #|{"out":{"id":15,"subscribe":{"topic":"workspace","workspace":"01M5DGXKV9S6M382F9X64C8V7T"},"keyed":true},"w":1792529133909.176}
  #|{"out":{"id":16,"subscribe":{"topic":"stations","scope":"01M5DGXKV9S6M382F9X64C8V7T"},"keyed":true},"w":1792529133909.215}
  #|{"out":{"id":17,"subscribe":{"topic":"connects","scope":"01M5DGXKV9S6M382F9X64C8V7T","mine":false},"keyed":true},"w":1792529133909.229}
  #|{"out":{"id":18,"subscribe":{"topic":"vaults","workspace":"01M5DGXKV9S6M382F9X64C8V7T"},"keyed":true},"w":1792529133909.245}
  #|{"out":{"id":19,"subscribe":{"topic":"doing"},"keyed":true},"w":1792529133941.417}
  #|{"step":"wait 300","w":1792529133946.754}
  #|{"in":{"id":15,"value":{"id":"01M5DGXKV9S6M382F9X64C8V7T","name":"Dev","role":"owner","created_at":1792529059,"members":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":"https://example.test/p.png","role":"owner","added_at":1792529059}],"stations":[{"id":"88a5ce0cf215b1e3267a98a057c8b17394922e982d6b46cbfea0dedd6df10706","name":"studio","emoji":null,"icon":null,"enrolled_at":1792529060,"enrolled_by":"alice","last_seen":1792529076,"version":"0.1.0","time":{"last_seen":{"past":true,"at":1792529076000,"ago":"1 分钟前","full":"10/21 04:44:36","until":"1 分钟内"}}}],"invitations":[],"added":[],"relays":[],"lock":null,"lock_requests":0,"time":{"created_at":{"past":true,"at":1792529059000,"ago":"1 分钟前","full":"10/21 04:44:19","until":"1 分钟内"}}}},"w":1792529133946.885}
  #|{"in":{"id":16,"value":[{"station":"01M5DGXKV9S6M382F9X64C8V7T/88a5ce0cf215b1e3267a98a057c8b17394922e982d6b46cbfea0dedd6df10706","id":"88a5ce0cf215b1e3267a98a057c8b17394922e982d6b46cbfea0dedd6df10706","name":"studio","summary":"正在连接","face":"idle","line":"在线","online":true,"reconnecting":true,"lastSeen":1792529076,"version":"0.1.0","link":{"state":"connecting"},"runtimes":[{"runtime":"claude","models":["claude-sonnet-5-5"]}],"models":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792529064201,"time":{"checkedAt":{"at":1792529064201,"ago":"1 分钟前","full":"10/21 04:44:24","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"overview":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null,"summaryText":"最近 7 天检查了 0 个 chat","changeText":null}},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","email":"alice@example.test","name":"Name of alice","sub":"alice","role":"owner","workspace":"01M5DGXKV9S6M382F9X64C8V7T","device":"00cb202f6dec0b293d76bd23f73e0dd619123df8213927bcdfc8d75821088da2"},"connects":[],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792529064008,"time":{"checkedAt":{"at":1792529064008,"ago":"1 分钟前","full":"10/21 04:44:24","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792529064201,"time":{"checkedAt":{"at":1792529064201,"ago":"1 分钟前","full":"10/21 04:44:24","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]}],"processes":[],"counts":{"sessions":1,"running":0,"warm":1},"mesh":{"state":"running","origin":"http://127.0.0.1:18900","station":"88a5ce0cf215b1e3267a98a057c8b17394922e982d6b46cbfea0dedd6df10706","workspace":"Dev","workspaceId":"01M5DGXKV9S6M382F9X64C8V7T","name":"studio"},"slackUsers":[],"slackTeams":[],"slackApps":[],"feishuRegistrations":[],"disk":{"freeBytes":62537682944,"totalBytes":245107195904},"logins":[],"machineLogins":[],"sharing":true,"consoleSignIn":true,"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"google","name":"Google Gemini","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xai","name":"xAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"mistral","name":"Mistral","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"deepseek","name":"DeepSeek","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen","name":"Qwen","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai","name":"Kimi","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai","name":"Z.ai","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax","name":"MiniMax","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ant-ling","name":"Ant Ling","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"jev","name":"Jev","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen-cn","name":"Qwen (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"openrouter","name":"OpenRouter","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"opencode","name":"OpenCode Zen","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"groq","name":"Groq","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"together","name":"Together AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"fireworks","name":"Fireworks","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cerebras","name":"Cerebras","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"huggingface","name":"Hugging Face","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"nvidia","name":"NVIDIA","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"baseten","name":"Baseten","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ollama","name":"Ollama","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"custom","name":"Custom","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""}],"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792529061706},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.304","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792529061706},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792529061706},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792529061706},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","latest":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792529061706}],"processesText":"没有运行中的 agent 进程","agentEnv":[],"drive":{"roots":[],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false}},"betaOffered":false,"time":{"lastSeen":{"at":1792529076000,"ago":"1 分钟前","full":"10/21 04:44:36","until":"1 分钟内","past":true}},"joined":false}]},"w":1792529133947.086}
  #|{"in":{"id":17,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"items":[],"wait":{"reading":false,"text":null,"failing":[],"empty":true}}},"w":1792529133947.239}
  #|{"in":{"id":18,"value":{"available":true,"locked":false,"canSign":false,"setUp":false,"vaults":[],"requests":[],"refused":[],"plain":true}},"w":1792529133947.253}
  #|{"in":{"id":19,"value":{"doing":[]}},"w":1792529133947.26}
  #|{"step":"now tap =Station","w":1792529134251.172}
  #|{"step":"now tap =Station","acted":true,"w":1792529134275.043}
  #|{"step":"wait 300","w":1792529134302.537}
  #|{"step":"now tap =studio","w":1792529134611.303}
  #|{"step":"now tap =studio","acted":true,"w":1792529134625.14}
  #|{"out":{"id":20,"subscribe":{"topic":"screens","station":"01M5DGXKV9S6M382F9X64C8V7T/88a5ce0cf215b1e3267a98a057c8b17394922e982d6b46cbfea0dedd6df10706"},"keyed":true},"w":1792529134644.008}
  #|{"out":{"id":21,"subscribe":{"topic":"memberships","station":"01M5DGXKV9S6M382F9X64C8V7T/88a5ce0cf215b1e3267a98a057c8b17394922e982d6b46cbfea0dedd6df10706"},"keyed":true},"w":1792529134644.061}
  #|{"out":{"id":22,"subscribe":{"topic":"adbShare"},"keyed":true},"w":1792529134645.495}
  #|{"step":"wait 300","w":1792529134649.508}
  #|{"in":{"id":20,"value":{"screens":[],"outdated":false,"control":true,"known":false}},"w":1792529134658.046}
  #|{"in":{"id":21,"value":{"manages":true,"loading":true,"canJoin":false,"workspaces":[]}},"w":1792529134658.08}
  #|{"in":{"id":22,"value":{"sharing":false,"phase":"off","tunnels":0}},"w":1792529134658.092}
  #|{"step":"now until 在此 station 上","w":1792529134984.16}
  #|{"step":"tap icon:more","w":1792529134987.468}
  #|{"step":"tap icon:more","acted":true,"w":1792529134992.571}
  #|{"in":{"id":5,"delta":[{"path":["items",0,"detail"],"set":"已等待 3 秒"},{"path":["items",1,"detail"],"set":"已等待 3 秒，尚未收到数据"},{"path":["text"],"set":"正在连接 studio · 3 秒 · 共 2 项"}]},"w":1792529135007.618}
  #|{"in":{"id":9,"delta":[{"path":["items",0,"detail"],"set":"已等待 3 秒"},{"path":["items",1,"detail"],"set":"已等待 3 秒，尚未收到数据"},{"path":["text"],"set":"正在连接 studio · 3 秒 · 共 2 项"}]},"w":1792529135007.644}
  #|{"step":"rest","w":1792529135011.812}
  #|{"in":{"id":5,"value":{"state":"slow","text":"studio 打开实时更新 · 4 秒 · 151 B/s","items":[{"state":"slow","text":"studio 打开实时更新","detail":"已等待 4 秒，尚未收到数据"}]}},"w":1792529135841.351}
  #|{"in":{"id":9,"value":{"state":"slow","text":"studio 打开实时更新 · 4 秒 · 151 B/s","items":[{"state":"slow","text":"studio 打开实时更新","detail":"已等待 4 秒，尚未收到数据"}]}},"w":1792529135841.387}
  #|{"in":{"id":18,"delta":[{"path":["vaults"],"key":["id"],"put":{"id":"plain","name":"个人","owner":"alice","ownerName":"Name of alice","mine":true,"members":[{"sub":"alice","name":"Name of alice"}],"station":"88a5ce0cf215b1e3267a98a057c8b17394922e982d6b46cbfea0dedd6df10706","stationName":"studio","items":0,"devices":0,"open":true,"keyed":true,"missing":0,"recoverable":false},"before":null}]},"w":1792529135841.42}
  #|{"in":{"id":21,"value":{"manages":true,"loading":false,"canJoin":true,"workspaces":[{"workspace":"01M5DGXKV9S6M382F9X64C8V7T","name":"Dev","stationName":"studio","home":true,"here":true,"line":"主 workspace"}]}},"w":1792529135841.44}
  #|{"in":{"id":5,"delta":[{"path":["text"],"set":"studio 打开实时更新 · 4 秒 · 294 B/s"}]},"w":1792529135907.791}
  #|{"in":{"id":9,"delta":[{"path":["text"],"set":"studio 打开实时更新 · 4 秒 · 294 B/s"}]},"w":1792529135907.815}
  #|{"in":{"id":18,"delta":[{"path":["refused"],"append":[{"station":"88a5ce0cf215b1e3267a98a057c8b17394922e982d6b46cbfea0dedd6df10706","name":"studio","code":"vault_needs_lock"}]}]},"w":1792529135907.821}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792529136009.188}
  #|{"in":{"id":9,"value":{"items":[]}},"w":1792529136009.214}
  #|{"in":{"id":16,"delta":[{"path":[0,"link","state"],"set":"online"},{"path":[0,"overview","counts","warm"],"set":0},{"path":[0,"overview","disk","freeBytes"],"set":62193954816},{"path":[0,"overview","profiles",0,"check","checkedAt"],"set":1792529134998},{"path":[0,"overview","profiles",0,"check","time","checkedAt","ago"],"set":"刚刚"},{"path":[0,"overview","profiles",0,"check","time","checkedAt","at"],"set":1792529134998},{"path":[0,"overview","profiles",0,"check","time","checkedAt","full"],"set":"10/21 04:45:34"},{"path":[0,"overview","updates",0,"checkedAt"],"set":1792529133599},{"path":[0,"overview","updates",1,"checkedAt"],"set":1792529133599},{"path":[0,"overview","updates",2,"checkedAt"],"set":1792529133599},{"path":[0,"overview","updates",3,"checkedAt"],"set":1792529133599},{"path":[0,"overview","updates",4,"checkedAt"],"set":1792529133599},{"path":[0,"reconnecting"],"set":false},{"path":[0,"way"],"set":{"path":"直连","via":"direct"}}]},"w":1792529136025.851}
  #|{"in":{"id":20,"value":{"screens":[{"id":"desktop","kind":"desktop","title":"3720-Mac-mini-1","width":0,"height":0,"viewers":[],"controlledBy":[],"access":{"capture":false,"control":false,"message":"此 station 版本不含屏幕助手（stillfail-screen），请更新 station"},"clipboard":[],"drop":{"folder":"/tmp/mbe2e-C/home","reveal":true},"peek":false,"line":"此 station 版本不含屏幕助手（stillfail-screen），请更新 station","link":"/w/01M5DGXKV9S6M382F9X64C8V7T/s/88a5ce0cf215b1e3267a98a057c8b17394922e982d6b46cbfea0dedd6df10706/screen/desktop"}],"outdated":false,"control":true,"known":true}},"w":1792529136057.616}
  #|{"in":{"id":7,"delta":[{"path":["days"],"key":["daysAgo"],"patch":0,"ops":[{"path":["items"],"key":["station","id"],"patch":["01M5DGXKV9S6M382F9X64C8V7T/88a5ce0cf215b1e3267a98a057c8b17394922e982d6b46cbfea0dedd6df10706","ember:c-45483a50d8"],"ops":[{"path":["agents",0,"process"],"set":"cold"},{"path":["clientKey"],"remove":true}]}]}]},"w":1792529136325.209}
  #|{"step":"now tap1 重命名","w":1792529136445.423}
  #|{"step":"now tap1 重命名","acted":true,"w":1792529136458.515}
  #|{"step":"rest","w":1792529136482.647}
  #|{"in":{"id":16,"delta":[{"path":[0,"host"],"set":{"hostname":"3720-Mac-mini-1","os":"macOS 27.0.1","arch":"arm64","cpus":10,"cpuModel":"Apple M4","load":1.31,"cpuBusy":1,"uptimeSec":8498,"memory":{"totalBytes":17179869184,"usedBytes":13031620608,"swapUsedBytes":341961605},"disk":{"path":"/tmp/mbe2e-C/data","totalBytes":245107195904,"freeBytes":62193848320},"emberRssBytes":139605360,"checkedAt":1792529136252,"summary":"10 核 · 16 GB","line":"macOS 27.0.1 · 10 核 · 16 GB · 已运行 0 天","facts":["3720-Mac-mini-1","macOS 27.0.1","arm64 · 10 核","已运行 2 小时"],"meters":[{"label":"CPU","short":"CPU","percent":100,"left":0,"level":"red","value":"100%","remaining":"空闲 0%","big":"0","unit":"%","title":"CPU 空闲","total":"负载 13.1","note":"负载 13.1 · Apple M4"},{"label":"内存","short":"内存","percent":76,"left":24,"level":"amber","value":"12.1 GB / 16.0 GB","remaining":"剩 3.9 G","big":"3.9","unit":"GB","title":"内存剩","total":"共 16 GB","note":"swap 0.3 GB"},{"label":"磁盘","short":"磁盘","percent":75,"left":25,"level":"amber","value":"剩余 57.9 GB / 228 GB","remaining":"剩 57.9 G","big":"57.9","unit":"GB","title":"磁盘剩","total":"共 228 GB"}],"identity":"Apple M4 · 16 GB · macOS 27.0.1","details":[{"label":"主机名","value":"3720-Mac-mini-1"},{"label":"芯片","value":"Apple M4 · 10 核 · arm64"},{"label":"已运行","value":"2 小时"},{"label":"still.fail","value":"进程占用 133 MB"}],"usage":"内存 12.1 GB / 16.0 GB · 磁盘 剩余 57.9 GB / 228 GB","emberText":"still.fail 133 MB"}},{"path":[0,"line"],"set":"Apple M4"},{"path":[0,"summary"],"set":"空闲 · Apple M4 · 16 GB · macOS 27.0.1"}]},"w":1792529136507.647}
  #|{"step":"now until station 名称","w":1792529138045.792}
  #|{"step":"clear","w":1792529138045.808}
  #|{"step":"clear","acted":true,"w":1792529138045.828}
  #|{"step":"type e2e-082939","w":1792529138060.532}
  #|{"step":"type e2e-082939","acted":true,"w":1792529138060.542}
  #|{"step":"tap =保存","w":1792529138089.283}
  #|{"step":"tap =保存","acted":true,"w":1792529138117.316}
  #|{"out":{"id":23,"call":"workspace.renameStation","params":{"workspace":"01M5DGXKV9S6M382F9X64C8V7T","station":"88a5ce0cf215b1e3267a98a057c8b17394922e982d6b46cbfea0dedd6df10706","name":"e2e-082939","account":"alice"}},"w":1792529138117.599}
  #|{"step":"answered workspace.renameStation","w":1792529138118.162}
  #|{"in":{"id":23,"ok":{"id":"01M5DGXKV9S6M382F9X64C8V7T","name":"Dev","role":"owner","created_at":1792529059,"members":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":"https://example.test/p.png","role":"owner","added_at":1792529059}],"stations":[{"id":"88a5ce0cf215b1e3267a98a057c8b17394922e982d6b46cbfea0dedd6df10706","name":"e2e-082939","emoji":null,"icon":null,"enrolled_at":1792529060,"enrolled_by":"alice","last_seen":1792529135,"version":"0.1.0"}],"invitations":[],"added":[],"relays":[],"lock":null,"lock_requests":0}},"w":1792529138158.475}
  #|{"step":"until 已重命名","w":1792529138186.435}
  #|{"step":"rest","w":1792529138186.462}
  #|{"in":{"id":15,"delta":[{"path":["stations",0,"last_seen"],"set":1792529135},{"path":["stations",0,"name"],"set":"e2e-082939"},{"path":["stations",0,"time","last_seen","ago"],"set":"刚刚"},{"path":["stations",0,"time","last_seen","at"],"set":1792529135000},{"path":["stations",0,"time","last_seen","full"],"set":"10/21 04:45:35"}]},"w":1792529138224.306}
  #|{"in":{"id":7,"delta":[{"path":["days"],"key":["daysAgo"],"patch":0,"ops":[{"path":["items"],"key":["station","id"],"patch":["01M5DGXKV9S6M382F9X64C8V7T/88a5ce0cf215b1e3267a98a057c8b17394922e982d6b46cbfea0dedd6df10706","ember:c-45483a50d8"],"ops":[{"path":["stationName"],"set":"e2e-082939"}]}]},{"path":["glyph","summary"],"set":"e2e-082939"},{"path":["stations",0,"name"],"set":"e2e-082939"}]},"w":1792529138224.364}
  #|{"in":{"id":16,"delta":[{"path":[0,"lastSeen"],"set":1792529135},{"path":[0,"name"],"set":"e2e-082939"},{"path":[0,"overview","disk","freeBytes"],"set":62189514752},{"path":[0,"overview","mesh","name"],"set":"e2e-082939"},{"path":[0,"time","lastSeen","ago"],"set":"刚刚"},{"path":[0,"time","lastSeen","at"],"set":1792529135000},{"path":[0,"time","lastSeen","full"],"set":"10/21 04:45:35"}]},"w":1792529138224.394}
  #|{"step":"now until =e2e-082939","w":1792529139683.681}
  #|{"step":"tap icon:more","w":1792529139683.689}
  #|{"step":"tap icon:more","acted":true,"w":1792529139743.434}
  #|{"step":"rest","w":1792529139787.394}
  #|{"step":"now tap1 重命名","w":1792529141222.391}
  #|{"step":"now tap1 重命名","acted":true,"w":1792529141264.457}
  #|{"step":"rest","w":1792529141278.403}
  #|{"step":"now until station 名称","w":1792529142658.483}
  #|{"step":"clear","w":1792529142658.506}
  #|{"step":"clear","acted":true,"w":1792529142658.52}
  #|{"step":"type studio","w":1792529142684.672}
  #|{"step":"type studio","acted":true,"w":1792529142684.688}
  #|{"step":"tap =保存","w":1792529142714.116}
  #|{"step":"tap =保存","acted":true,"w":1792529142753.224}
  #|{"out":{"id":24,"call":"workspace.renameStation","params":{"workspace":"01M5DGXKV9S6M382F9X64C8V7T","station":"88a5ce0cf215b1e3267a98a057c8b17394922e982d6b46cbfea0dedd6df10706","name":"studio","account":"alice"}},"w":1792529142791.708}
  #|{"step":"answered workspace.renameStation","w":1792529142792.093}
  #|{"in":{"id":19,"value":{"doing":[{"call":"workspace.renameStation","params":{"workspace":"01M5DGXKV9S6M382F9X64C8V7T","station":"88a5ce0cf215b1e3267a98a057c8b17394922e982d6b46cbfea0dedd6df10706","name":"studio","account":"alice"},"since":1792529142791,"stage":"running"}]}},"w":1792529142903.148}
  #|{"in":{"id":24,"ok":{"id":"01M5DGXKV9S6M382F9X64C8V7T","name":"Dev","role":"owner","created_at":1792529059,"members":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":"https://example.test/p.png","role":"owner","added_at":1792529059}],"stations":[{"id":"88a5ce0cf215b1e3267a98a057c8b17394922e982d6b46cbfea0dedd6df10706","name":"studio","emoji":null,"icon":null,"enrolled_at":1792529060,"enrolled_by":"alice","last_seen":1792529135,"version":"0.1.0"}],"invitations":[],"added":[],"relays":[],"lock":null,"lock_requests":0}},"w":1792529143007.638}
  #|{"in":{"id":7,"delta":[{"path":["days"],"key":["daysAgo"],"patch":0,"ops":[{"path":["items"],"key":["station","id"],"patch":["01M5DGXKV9S6M382F9X64C8V7T/88a5ce0cf215b1e3267a98a057c8b17394922e982d6b46cbfea0dedd6df10706","ember:c-45483a50d8"],"ops":[{"path":["stationName"],"set":"studio"}]}]},{"path":["glyph","summary"],"set":"studio"},{"path":["stations",0,"name"],"set":"studio"}]},"w":1792529143007.701}
  #|{"in":{"id":16,"delta":[{"path":[0,"name"],"set":"studio"},{"path":[0,"overview","disk","freeBytes"],"set":62189215744},{"path":[0,"overview","mesh","name"],"set":"studio"}]},"w":1792529143007.727}
  #|{"in":{"id":15,"delta":[{"path":["stations",0,"name"],"set":"studio"}]},"w":1792529143007.744}
  #|{"in":{"id":19,"value":{"doing":[]}},"w":1792529143007.754}
  #|{"step":"until 已重命名","w":1792529143031.247}
  #|{"step":"rest","w":1792529143031.271}
  #|{"step":"now until =studio","w":1792529144614.644}
  #|{"step":"wait 1183","w":1792529144614.659}
  #|{"step":"now rest","w":1792529145828.549}
  #|{"step":"now rest","w":1792529145926.818}
  #|{"step":"","w":1792529145941.518}
  #|{"textrec":{"ib":["bfd9b0d6dc602826",12668,64],"r":[56,56,56,56]}}
  #|{"textrec":{"s":[13,400,0,"正在读取你的 workspace"],"r":[0,1,12.898832684824903,0,1,1,12.898832684824903,1,2,1,12.898832684824903,2,3,1,12.898832684824903,3,4,1,12.898832684824896,4,5,1,12.898832684824896,5,6,1,3.580078125,-1,7,1,9.8642578125,6,8,1,7.4775390625,7,9,1,4.875,8,10,1,6.85546875,9,11,1,6.6015625,10,12,1,7.8583984375,11,13,1,7.0966796875,12,14,1,7.1982421875,13,15,1,7.3505859375,14]}}
  #|{"textrec":{"m":[13,400,0],"r":[12.568359375,2.7421875,18]}}
  #|{"textrec":{"g":0,"r":[0,0,14,13,-1,-11,0]}}
  #|{"textrec":{"g":1,"r":[15,0,14,15,-1,-12,0]}}
  #|{"textrec":{"g":2,"r":[30,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":3,"r":[46,0,15,14,-1,-11,0]}}
  #|{"textrec":{"g":4,"r":[62,0,14,15,-1,-12,0]}}
  #|{"textrec":{"g":5,"r":[77,0,13,15,0,-12,0]}}
  #|{"textrec":{"g":6,"r":[91,0,12,9,-1,-8,0]}}
  #|{"textrec":{"g":7,"r":[104,0,9,10,-1,-8,0]}}
  #|{"textrec":{"g":8,"r":[114,0,6,9,0,-8,0]}}
  #|{"textrec":{"g":9,"r":[121,0,8,12,0,-11,0]}}
  #|{"textrec":{"g":10,"r":[130,0,9,10,-1,-8,0]}}
  #|{"textrec":{"g":11,"r":[140,0,9,12,0,-8,0]}}
  #|{"textrec":{"g":12,"r":[150,0,9,10,-1,-8,0]}}
  #|{"textrec":{"g":13,"r":[160,0,9,10,-1,-8,0]}}
  #|{"textrec":{"g":14,"r":[170,0,9,10,-1,-8,0]}}
  #|{"textrec":{"s":[24,700,0,"Dev"],"r":[0,1,17.075823068618774,15,1,1,13.365240812301636,16,2,1,12.759063005447388,17]}}
  #|{"textrec":{"m":[24,700,0],"r":[23.203125,5.0625,34]}}
  #|{"textrec":{"g":15,"r":[180,0,18,19,0,-18,0]}}
  #|{"textrec":{"g":16,"r":[199,0,15,16,-1,-14,0]}}
  #|{"textrec":{"g":17,"r":[215,0,15,15,-1,-14,0]}}
  #|{"textrec":{"ib":["02698e60df92657e",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"ib":["1d51432b25a425eb",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"ib":["bef2954d97ce1d9f",6508,64],"r":[40,40,40,40]}}
  #|{"textrec":{"ib":["a7ccae3554fe46cf",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["c8ac90bf691295f0",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["fdb526ba00f881f4",3232,64],"r":[28,28,28,28]}}
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
  #|{"textrec":{"g":18,"r":[231,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":19,"r":[249,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":20,"r":[266,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":21,"r":[284,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":22,"r":[301,0,15,16,0,-13,0]}}
  #|{"textrec":{"g":23,"r":[317,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":24,"r":[334,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":25,"r":[352,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":26,"r":[370,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":27,"r":[388,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":28,"r":[406,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":29,"r":[424,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":30,"r":[443,0,16,17,0,-14,0]}}
  #|{"textrec":{"g":31,"r":[460,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":32,"r":[478,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":33,"r":[497,0,11,14,0,-10,0]}}
  #|{"textrec":{"g":34,"r":[509,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":35,"r":[521,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":36,"r":[533,0,8,14,-1,-12,0]}}
  #|{"textrec":{"g":37,"r":[542,0,5,12,0,-10,0]}}
  #|{"textrec":{"g":38,"r":[548,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":39,"r":[566,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":40,"r":[584,0,6,8,0,-4,0]}}
  #|{"textrec":{"g":41,"r":[591,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":42,"r":[610,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":43,"r":[628,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":62,"r":[645,0,14,6,0,-4,0]}}
  #|{"textrec":{"g":48,"r":[660,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":49,"r":[676,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":50,"r":[693,0,5,7,0,-3,0]}}
  #|{"textrec":{"g":51,"r":[699,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":52,"r":[716,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":53,"r":[732,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":54,"r":[748,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":55,"r":[765,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":56,"r":[781,0,14,16,0,-13,0]}}
  #|{"textrec":{"g":57,"r":[796,0,9,11,-1,-9,0]}}
  #|{"textrec":{"g":58,"r":[806,0,10,13,-1,-9,0]}}
  #|{"textrec":{"g":59,"r":[817,0,10,11,-1,-9,0]}}
  #|{"textrec":{"g":60,"r":[828,0,9,10,0,-9,0]}}
  #|{"textrec":{"g":61,"r":[838,0,7,13,-1,-11,0]}}
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
  #|{"textrec":{"s":[15,400,0,"密钥"],"r":[0,1,14.883268482490273,177,1,1,14.883268482490273,178]}}
  #|{"textrec":{"s":[14,400,0,"1/1 在线"],"r":[0,1,6.34375,175,1,1,4.115234375,179,2,1,6.34375,175,3,1,3.787109375,-1,4,1,13.891050583657588,180,5,1,13.891050583657588,181]}}
  #|{"textrec":{"s":[14,400,0,"0 个"],"r":[0,1,8.66796875,182,1,1,3.787109375,-1,2,1,13.891050583657588,183]}}
  #|{"textrec":{"s":[14,400,0,"1 个"],"r":[0,1,6.34375,175,1,1,3.787109375,-1,2,1,13.891050583657588,183]}}
  #|{"textrec":{"g":65,"r":[846,0,31,31,0,-26,0]}}
  #|{"textrec":{"g":66,"r":[878,0,30,29,0,-25,0]}}
  #|{"textrec":{"ib":["a1e7be43eb966606",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"ib":["504a4df6beac534a",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"g":63,"r":[909,0,18,18,-1,-15,0]}}
  #|{"textrec":{"g":64,"r":[928,0,19,18,-1,-15,0]}}
  #|{"textrec":{"g":83,"r":[948,0,17,19,0,-18,0]}}
  #|{"textrec":{"g":84,"r":[966,0,12,13,0,-12,0]}}
  #|{"textrec":{"g":85,"r":[979,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":86,"r":[991,0,11,11,-1,-10,0]}}
  #|{"textrec":{"g":168,"r":[1003,0,5,5,1,-8,0]}}
  #|{"textrec":{"g":169,"r":[1009,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":170,"r":[1026,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":171,"r":[1043,0,13,14,-1,-12,0]}}
  #|{"textrec":{"g":172,"r":[1057,0,14,11,-1,-10,0]}}
  #|{"textrec":{"g":173,"r":[1072,0,10,11,0,-10,0]}}
  #|{"textrec":{"g":174,"r":[1083,0,7,11,0,-10,0]}}
  #|{"textrec":{"g":87,"r":[1091,0,16,13,-1,-12,0]}}
  #|{"textrec":{"g":88,"r":[1108,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":89,"r":[1120,0,7,11,0,-10,0]}}
  #|{"textrec":{"g":90,"r":[1128,0,9,14,0,-13,0]}}
  #|{"textrec":{"g":91,"r":[1138,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":92,"r":[1149,0,10,14,0,-10,0]}}
  #|{"textrec":{"g":93,"r":[1160,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":94,"r":[1171,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":95,"r":[1182,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":99,"r":[1193,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":177,"r":[1210,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":178,"r":[1227,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":100,"r":[1244,0,11,14,-1,-12,0]}}
  #|{"textrec":{"g":101,"r":[1256,0,7,13,-1,-11,0]}}
  #|{"textrec":{"g":102,"r":[1264,0,5,14,-1,-13,0]}}
  #|{"textrec":{"g":103,"r":[1270,0,9,11,0,-10,0]}}
  #|{"textrec":{"g":104,"r":[1280,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":105,"r":[1297,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":106,"r":[1314,0,10,13,0,-12,0]}}
  #|{"textrec":{"g":107,"r":[1325,0,7,14,-1,-13,0]}}
  #|{"textrec":{"g":108,"r":[1333,0,4,14,0,-13,0]}}
  #|{"textrec":{"g":109,"r":[1338,0,13,16,1,-13,0]}}
  #|{"textrec":{"g":110,"r":[1352,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":111,"r":[1369,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":112,"r":[1387,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":113,"r":[1404,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":114,"r":[1422,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":115,"r":[1439,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":116,"r":[1455,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":117,"r":[1472,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":118,"r":[1490,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":119,"r":[1508,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":124,"r":[1526,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":125,"r":[1544,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":128,"r":[1562,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":129,"r":[1579,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":130,"r":[1596,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":131,"r":[1613,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":132,"r":[1631,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":133,"r":[1649,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":134,"r":[1667,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":67,"r":[1684,0,12,14,0,-13,0]}}
  #|{"textrec":{"g":68,"r":[1697,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":69,"r":[1709,0,15,11,0,-10,0]}}
  #|{"textrec":{"g":70,"r":[1725,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":71,"r":[1737,0,12,12,-1,-10,0]}}
  #|{"textrec":{"g":72,"r":[1750,0,8,14,-1,-13,0]}}
  #|{"textrec":{"g":73,"r":[1759,0,5,14,0,-13,0]}}
  #|{"textrec":{"g":74,"r":[1765,0,5,15,0,-14,0]}}
  #|{"textrec":{"g":75,"r":[1771,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":76,"r":[1783,0,4,12,0,-11,0]}}
  #|{"textrec":{"g":77,"r":[1788,0,5,12,-1,-11,0]}}
  #|{"textrec":{"g":78,"r":[1794,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":79,"r":[1809,0,9,9,-1,-8,0]}}
  #|{"textrec":{"g":80,"r":[1819,0,12,9,0,-8,0]}}
  #|{"textrec":{"g":81,"r":[1832,0,4,5,0,-3,0]}}
  #|{"textrec":{"g":82,"r":[1837,0,7,12,-1,-10,0]}}
  #|{"textrec":{"g":96,"r":[1845,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":97,"r":[1861,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":98,"r":[1877,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":175,"r":[1893,0,7,12,-1,-11,0]}}
  #|{"textrec":{"g":179,"r":[1901,0,7,16,-1,-12,0]}}
  #|{"textrec":{"g":180,"r":[1909,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":181,"r":[1925,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":120,"r":[1942,0,16,15,-1,-12,0]}}
  #|{"textrec":{"g":121,"r":[1959,0,15,16,0,-13,0]}}
  #|{"textrec":{"g":122,"r":[1975,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":123,"r":[1991,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":176,"r":[2008,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":182,"r":[2025,0,10,14,-1,-12,0]}}
  #|{"textrec":{"g":183,"r":[0,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":126,"r":[17,32,9,13,0,-12,0]}}
  #|{"textrec":{"g":127,"r":[27,32,16,16,-1,-13,0]}}
  #|{"textrec":{"ib":["b3685975cd23abc3",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"s":[16,600,0,"Station"],"r":[0,1,10.266256332397461,184,1,1,5.999713897705078,36,2,1,8.899068832397461,44,3,1,5.999713897705078,36,4,1,4.046333312988281,185,5,1,9.432537078857422,34,6,1,9.466253280639648,47]}}
  #|{"textrec":{"s":[17,400,0,"设置"],"r":[0,1,16.851167315175097,186,1,1,16.851167315175097,187]}}
  #|{"textrec":{"s":[12,400,0,"正在重新连接"],"r":[0,1,11.918287937743191,188,1,1,11.918287937743191,189,2,1,11.918287937743195,190,3,1,11.918287937743187,191,4,1,11.918287937743187,192,5,1,11.918287937743187,193]}}
  #|{"textrec":{"m":[12,400,0],"r":[11.6015625,2.53125,17]}}
  #|{"textrec":{"s":[16,700,0,"studio"],"r":[0,1,8.73046875,194,1,1,6.26953125,195,2,1,9.72265625,196,3,1,10.109375,197,4,1,4.28125,74,5,1,9.6015625,71]}}
  #|{"textrec":{"s":[13,400,0,"正在连接"],"r":[0,1,12.898832684824903,0,1,1,12.898832684824903,1,2,1,12.898832684824903,198,3,1,12.898832684824903,199]}}
  #|{"textrec":{"s":[13,400,0,"↑"],"r":[0,1,10.080078125,200]}}
  #|{"textrec":{"s":[13,500,0," "],"r":[0,1,3.4683494567871094,-1]}}
  #|{"textrec":{"m":[13,500,0],"r":[12.568359375,2.7421875,18]}}
  #|{"textrec":{"s":[13,400,0,"↓"],"r":[0,1,10.080078125,201]}}
  #|{"textrec":{"s":[13,400,0,"直连"],"r":[0,1,12.898832684824903,202,1,1,12.898832684824903,198]}}
  #|{"textrec":{"s":[13,400,0,"当前延迟 "],"r":[0,1,12.898832684824903,203,1,1,12.898832684824903,204,2,1,12.898832684824903,205,3,1,12.898832684824903,206,4,1,3.580078125,-1]}}
  #|{"textrec":{"s":[13,500,0,"0 ms"],"r":[0,1,8.373004913330078,207,1,1,3.4683494567871094,-1,2,1,11.530966997146606,208,3,1,6.933351516723633,209]}}
  #|{"textrec":{"g":186,"r":[44,32,19,18,-1,-15,0]}}
  #|{"textrec":{"g":187,"r":[64,32,18,17,-1,-14,0]}}
  #|{"textrec":{"g":194,"r":[83,32,11,12,-1,-10,0]}}
  #|{"textrec":{"g":195,"r":[95,32,8,14,-1,-12,0]}}
  #|{"textrec":{"g":196,"r":[104,32,10,12,0,-10,0]}}
  #|{"textrec":{"g":197,"r":[115,32,12,15,-1,-13,0]}}
  #|{"textrec":{"g":198,"r":[128,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":199,"r":[144,32,15,15,-1,-12,0]}}
  #|{"textrec":{"ib":["b7b1dc2c98725280",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"g":184,"r":[160,32,12,15,-1,-13,0]}}
  #|{"textrec":{"g":44,"r":[173,32,11,12,-1,-10,0]}}
  #|{"textrec":{"g":185,"r":[185,32,5,15,0,-14,0]}}
  #|{"textrec":{"g":47,"r":[191,32,10,11,0,-10,0]}}
  #|{"textrec":{"g":188,"r":[202,32,14,12,-1,-10,0]}}
  #|{"textrec":{"g":189,"r":[217,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":190,"r":[232,32,14,13,-1,-11,0]}}
  #|{"textrec":{"g":191,"r":[247,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":192,"r":[262,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":193,"r":[277,32,14,14,-1,-11,0]}}
  #|{"textrec":{"ib":["3a089f86e58e836f",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["d199cb74c5a62786",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["9e48044fa6815e02",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["2bb63fc1d380f765",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["5018c6b0c428bd67",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["0ac9db1649fc9777",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["dc2a7c23677cea3f",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["0b44c3b15eb4e72a",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"s":[16,600,0,"studio"],"r":[0,1,8.471200942993164,35,1,1,5.973020553588867,36,2,1,9.466253280639648,210,3,1,9.891647338867188,211,4,1,4.046333312988281,185,5,1,9.432537078857422,34]}}
  #|{"textrec":{"s":[17,400,0,"Station"],"r":[0,1,10.40087890625,212,1,1,5.744140625,213,2,1,8.9482421875,214,3,1,5.744140625,213,4,1,3.7685546875,215,5,1,9.6123046875,216,6,1,9.48779296875,217]}}
  #|{"textrec":{"s":[13,400,0,"没有运行中的 agent 进程"],"r":[0,1,12.898832684824903,218,1,1,12.898832684824903,149,2,1,12.898832684824903,219,3,1,12.898832684824903,220,4,1,12.898832684824896,221,5,1,12.898832684824896,5,6,1,3.580078125,-1,7,1,7.0966796875,12,8,1,7.845703125,222,9,1,7.3505859375,14,10,1,7.50927734375,223,11,1,4.646484375,82,12,1,3.580078125,-1,13,1,12.898832684824896,224,14,1,12.898832684824896,225]}}
  #|{"textrec":{"s":[15,600,0,"在此 station 上"],"r":[0,1,14.883268482490273,226,1,1,14.883268482490273,117,2,1,3.761730194091797,-1,3,1,8.000344634056091,227,4,1,5.658300518989563,228,5,1,8.40147078037262,229,6,1,5.683325529098511,228,7,1,3.8520312309265137,230,8,1,8.901597261428833,231,9,1,8.93320620059967,173,10,1,3.761730194091797,-1,11,1,14.883268482490266,232]}}
  #|{"textrec":{"s":[15,400,0,"共享调试"],"r":[0,1,14.883268482490273,233,1,1,14.883268482490273,234,2,1,14.883268482490273,235,3,1,14.883268482490273,236]}}
  #|{"textrec":{"s":[14,400,0,"未开放"],"r":[0,1,13.891050583657588,96,1,1,13.891050583657588,97,2,1,13.891050583657588,237]}}
  #|{"textrec":{"s":[15,400,0,"文件"],"r":[0,1,14.883268482490273,238,1,1,14.883268482490273,239]}}
  #|{"textrec":{"s":[15,600,0,"Agent 环境变量"],"r":[0,1,10.209932327270508,240,1,1,9.027448296546936,241,2,1,8.615586161613464,85,3,1,8.93320620059967,173,4,1,5.683325529098511,228,5,1,3.761730194091797,-1,6,1,14.883268482490273,242,7,1,14.883268482490273,243,8,1,14.883268482490266,244,9,1,14.88326848249028,245]}}
  #|{"textrec":{"s":[15,400,0,"暂无变量"],"r":[0,1,14.883268482490273,246,1,1,14.883268482490273,247,2,1,14.883268482490273,248,3,1,14.883268482490273,116]}}
  #|{"textrec":{"s":[15,400,0,"编辑变量"],"r":[0,1,14.883268482490273,249,1,1,14.883268482490273,250,2,1,14.883268482490273,248,3,1,14.883268482490273,116]}}
  #|{"textrec":{"s":[15,600,0,"搜索"],"r":[0,1,14.883268482490273,251,1,1,14.883268482490273,252]}}
  #|{"textrec":{"s":[15,400,0,"搜索个人数据"],"r":[0,1,14.883268482490273,18,1,1,14.883268482490273,19,2,1,14.883268482490273,253,3,1,14.883268482490273,254,4,1,14.88326848249028,255,5,1,14.88326848249028,256]}}
  #|{"textrec":{"s":[13,400,0,"workspace 成员也可搜索邮件、信息、日历、通讯录、备忘录和照片"],"r":[0,1,9.8642578125,6,1,1,7.4775390625,7,2,1,4.875,8,3,1,6.85546875,9,4,1,6.6015625,10,5,1,7.8583984375,11,6,1,7.0966796875,12,7,1,7.1982421875,13,8,1,7.3505859375,14,9,1,3.580078125,-1,10,1,12.898832684824896,140,11,1,12.898832684824896,257,12,1,12.898832684824896,258,13,1,12.898832684824896,259,14,1,12.898832684824896,260,15,1,12.898832684824896,261,16,1,12.898832684824896,262,17,1,12.898832684824896,263,18,1,13.075875486381335,141,19,1,12.898832684824896,264,20,1,12.898832684824896,152,21,1,13.075875486381335,141,22,1,12.898832684824896,265,23,1,12.898832684824896,266,24,1,13.075875486381335,141,25,1,12.898832684824924,154,26,1,12.898832684824924,267,27,1,12.898832684824924,268,28,1,13.075875486381335,141,29,1,12.898832684824924,269,30,1,12.898832684824924,270,31,1,12.898832684824924,268,32,1,12.898832684824924,271,33,1,12.898832684824924,272,34,1,12.898832684824924,273]}}
  #|{"textrec":{"ib":["a32136b675dfede6",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["80471d92f205f03a",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"g":226,"r":[292,32,16,17,-1,-14,0]}}
  #|{"textrec":{"g":227,"r":[309,32,10,12,-1,-10,0]}}
  #|{"textrec":{"g":228,"r":[320,32,8,13,-1,-11,0]}}
  #|{"textrec":{"g":229,"r":[329,32,10,12,-1,-10,0]}}
  #|{"textrec":{"g":230,"r":[340,32,6,14,-1,-13,0]}}
  #|{"textrec":{"g":231,"r":[347,32,11,12,-1,-10,0]}}
  #|{"textrec":{"g":232,"r":[359,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":240,"r":[376,32,13,13,-1,-12,0]}}
  #|{"textrec":{"g":241,"r":[390,32,11,14,-1,-10,0]}}
  #|{"textrec":{"g":242,"r":[402,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":243,"r":[420,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":244,"r":[438,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":245,"r":[456,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":251,"r":[473,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":252,"r":[491,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":212,"r":[508,32,12,16,-1,-14,0]}}
  #|{"textrec":{"g":213,"r":[521,32,8,15,-1,-13,0]}}
  #|{"textrec":{"g":214,"r":[530,32,11,13,-1,-11,0]}}
  #|{"textrec":{"g":215,"r":[542,32,5,15,0,-14,0]}}
  #|{"textrec":{"g":216,"r":[548,32,12,13,-1,-11,0]}}
  #|{"textrec":{"g":217,"r":[561,32,10,12,0,-11,0]}}
  #|{"textrec":{"g":218,"r":[572,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":149,"r":[588,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":219,"r":[603,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":220,"r":[619,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":221,"r":[635,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":222,"r":[649,32,9,12,-1,-8,0]}}
  #|{"textrec":{"g":223,"r":[659,32,8,9,0,-8,0]}}
  #|{"textrec":{"g":224,"r":[668,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":225,"r":[684,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":233,"r":[700,32,16,17,-1,-14,0]}}
  #|{"textrec":{"g":234,"r":[717,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":235,"r":[734,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":236,"r":[751,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":238,"r":[769,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":239,"r":[787,32,16,17,-1,-14,0]}}
  #|{"textrec":{"g":246,"r":[804,32,15,17,0,-14,0]}}
  #|{"textrec":{"g":247,"r":[820,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":248,"r":[837,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":249,"r":[855,32,16,17,-1,-14,0]}}
  #|{"textrec":{"g":250,"r":[872,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":253,"r":[890,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":254,"r":[908,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":255,"r":[926,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":256,"r":[944,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":140,"r":[961,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":257,"r":[977,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":258,"r":[992,32,15,14,-1,-12,0]}}
  #|{"textrec":{"g":259,"r":[1008,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":260,"r":[1023,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":261,"r":[1039,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":262,"r":[1054,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":263,"r":[1069,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":141,"r":[1085,32,6,6,0,-3,0]}}
  #|{"textrec":{"g":264,"r":[1092,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":152,"r":[1108,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":265,"r":[1124,32,11,14,1,-11,0]}}
  #|{"textrec":{"g":266,"r":[1136,32,14,14,-1,-11,0]}}
  #|{"textrec":{"ib":["21d27b298626ff58",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"g":210,"r":[1151,32,10,12,0,-10,0]}}
  #|{"textrec":{"g":211,"r":[1162,32,11,15,-1,-13,0]}}
  #|{"textrec":{"ib":["f50dcfc8e7b09e13",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["d2ccd5cf9373640b",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"g":237,"r":[1174,32,16,16,-1,-13,0]}}
  #|{"textrec":{"ib":["a84714a0d118c5eb",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["3e89fb0d7a2d2be5",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["ddfdc2820df8a676",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"ib":["abd519d291ad649c",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["550a89fdd3627b9e",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["bc56d3e0d751880c",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"s":[17,700,0,"studio"],"r":[0,1,9.176513671875,274,1,1,6.561767578125,275,2,1,10.230712890625,276,3,1,10.6416015625,277,4,1,4.44921875,278,5,1,10.10205078125,279]}}
  #|{"textrec":{"m":[17,700,0],"r":[16.435546875,3.5859375,24]}}
  #|{"textrec":{"s":[15,400,0,"重命名"],"r":[0,1,14.883268482490273,280,1,1,14.883268482490273,281,2,1,14.883268482490273,282]}}
  #|{"textrec":{"s":[15,400,0,"图标"],"r":[0,1,14.883268482490273,283,1,1,14.883268482490273,284]}}
  #|{"textrec":{"s":[15,400,0,"从 workspace 移除"],"r":[0,1,14.883268482490273,285,1,1,3.984375,-1,2,1,11.2353515625,286,3,1,8.4814453125,88,4,1,5.478515625,89,5,1,7.763671875,90,6,1,7.470703125,91,7,1,8.920898437500007,92,8,1,8.0419921875,93,9,1,8.1591796875,94,10,1,8.3349609375,95,11,1,3.984375,-1,12,1,14.88326848249028,287,13,1,14.88326848249028,288]}}
  #|{"textrec":{"g":274,"r":[1191,32,11,13,-1,-11,0]}}
  #|{"textrec":{"g":275,"r":[1203,32,9,15,-1,-13,0]}}
  #|{"textrec":{"g":276,"r":[1213,32,11,13,0,-11,0]}}
  #|{"textrec":{"g":277,"r":[1225,32,12,16,-1,-14,0]}}
  #|{"textrec":{"g":278,"r":[1238,32,5,16,0,-15,0]}}
  #|{"textrec":{"g":279,"r":[1244,32,12,13,-1,-11,0]}}
  #|{"textrec":{"g":280,"r":[1257,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":281,"r":[1274,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":282,"r":[1291,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":283,"r":[1307,32,15,16,0,-13,0]}}
  #|{"textrec":{"g":284,"r":[1323,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":285,"r":[1340,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":286,"r":[1358,32,14,10,-1,-9,0]}}
  #|{"textrec":{"g":287,"r":[1373,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":288,"r":[1390,32,16,16,0,-13,0]}}
  #|{"textrec":{"ib":["8702d89573d5efdf",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["70da3a129cd335a2",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["56cdacf263ae288e",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["536c426c0236d661",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["365bf49de4f5d505",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["8a3f7c664f10bd54",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["831523b197f71e32",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"s":[11,400,0,"在线"],"r":[0,1,10.93579766536965,289,1,1,10.93579766536965,290]}}
  #|{"textrec":{"m":[11,400,0],"r":[10.634765625,2.3203125,16]}}
  #|{"textrec":{"g":289,"r":[1407,32,13,13,-1,-10,0]}}
  #|{"textrec":{"g":290,"r":[1421,32,13,13,-1,-10,0]}}
  #|{"textrec":{"s":[15,600,0,"屏幕"],"r":[0,1,14.883268482490273,291,1,1,14.883268482490273,292]}}
  #|{"textrec":{"s":[15,400,0,"3720-Mac-mini-1"],"r":[0,1,9.169921875,293,1,1,8.3056640625,294,2,1,8.818359375,295,3,1,9.2138671875,164,4,1,6.8408203125,296,5,1,12.8759765625,297,6,1,8.0419921875,93,7,1,8.1591796875,94,8,1,6.8408203125,296,9,1,12.8173828125,161,10,1,3.4716796875,102,11,1,8.51806640625,103,12,1,3.4716796875,102,13,1,6.8408203125,296,14,1,6.7236328125,165]}}
  #|{"textrec":{"s":[13,400,0,"此 station 版本不含屏幕助手（stillfail-screen），请更新 station"],"r":[0,1,12.898832684824903,298,1,1,3.580078125,-1,2,1,6.69677734375,10,3,1,4.61474609375,82,4,1,7.0966796875,12,5,1,4.646484375,82,6,1,3.1357421875,77,7,1,7.6044921875,7,8,1,7.50927734375,223,9,1,3.580078125,-1,10,1,12.898832684824903,299,11,1,12.89883268482491,300,12,1,12.898832684824896,301,13,1,12.898832684824896,302,14,1,12.898832684824896,303,15,1,12.898832684824896,304,16,1,12.898832684824896,305,17,1,19.398832684824896,306,18,1,4.071984435797674,307,19,1,6.69677734375,10,20,1,4.61474609375,82,21,1,3.1357421875,77,22,1,3.2119140625,76,23,1,3.2119140625,76,24,1,4.5322265625,308,25,1,7.00146484375,12,26,1,3.1357421875,77,27,1,3.2119140625,76,28,1,6.0556640625,309,29,1,6.728515625,10,30,1,7.1982421875,13,31,1,4.77978515625,8,32,1,7.25537109375,14,33,1,7.3505859375,14,34,1,7.50927734375,223,35,1,5.456712062256827,310,36,1,13.075875486381335,311,37,1,12.898832684824924,312,38,1,12.898832684824924,313,39,1,12.898832684824924,150,40,1,3.580078125,-1,41,1,6.69677734375,10,42,1,4.61474609375,82,43,1,7.0966796875,12,44,1,4.646484375,82,45,1,3.1357421875,77,46,1,7.6044921875,7,47,1,7.50927734375,223]}}
  #|{"textrec":{"g":291,"r":[1435,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":292,"r":[1452,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":293,"r":[1470,32,10,14,0,-12,0]}}
  #|{"textrec":{"g":294,"r":[1481,32,10,13,-1,-12,0]}}
  #|{"textrec":{"g":295,"r":[1492,32,10,13,0,-12,0]}}
  #|{"textrec":{"g":164,"r":[1503,32,11,14,-1,-12,0]}}
  #|{"textrec":{"g":296,"r":[1515,32,7,4,0,-6,0]}}
  #|{"textrec":{"g":297,"r":[1523,32,13,13,0,-12,0]}}
  #|{"textrec":{"g":161,"r":[1537,32,13,11,0,-10,0]}}
  #|{"textrec":{"g":165,"r":[1551,32,8,13,-1,-12,0]}}
  #|{"textrec":{"g":298,"r":[1560,32,15,14,-1,-12,0]}}
  #|{"textrec":{"g":299,"r":[1576,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":300,"r":[1592,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":301,"r":[1608,32,15,14,-1,-11,0]}}
  #|{"textrec":{"g":302,"r":[1624,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":303,"r":[1640,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":304,"r":[1655,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":305,"r":[1671,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":306,"r":[1686,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":307,"r":[1702,32,5,15,-1.16666666666667,-12,0]}}
  #|{"textrec":{"g":308,"r":[1708,32,7,12,-1,-11,0]}}
  #|{"textrec":{"g":309,"r":[1716,32,8,4,-1,-6,0]}}
  #|{"textrec":{"g":310,"r":[1725,32,6,15,-1,-12,0]}}
  #|{"textrec":{"g":311,"r":[1732,32,5,7,0,-3,0]}}
  #|{"textrec":{"g":312,"r":[1738,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":313,"r":[1754,32,15,14,-1,-11,0]}}
  #|{"textrec":{"g":150,"r":[1770,32,15,15,-1,-12,0]}}
  #|{"textrec":{"ib":["dfa0b3408acf8bc7",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"s":[17,700,0,"station 名称"],"r":[0,1,9.176513671875,274,1,1,6.561767578125,275,2,1,9.591552734375,314,3,1,6.58251953125,275,4,1,4.44921875,278,5,1,10.10205078125,279,6,1,10.230712890625,315,7,1,3.951171875,-1,8,1,16.851167315175104,316,9,1,16.851167315175104,317]}}
  #|{"textrec":{"s":[14,600,0,"取消"],"r":[0,1,13.891050583657588,318,1,1,13.891050583657588,319]}}
  #|{"textrec":{"m":[14,600,0],"r":[13.53515625,2.953125,20]}}
  #|{"textrec":{"s":[14,600,0,"保存"],"r":[0,1,13.891050583657588,320,1,1,13.891050583657588,321]}}
  #|{"textrec":{"s":[15,400,0,"studio"],"r":[0,1,7.58056640625,91,1,1,5.17822265625,101,2,1,8.51806640625,163,3,1,8.9794921875,322,4,1,3.4716796875,102,5,1,8.6279296875,88]}}
  #|{"textrec":{"g":314,"r":[1786,32,11,13,-1,-11,0]}}
  #|{"textrec":{"g":315,"r":[1798,32,11,12,0,-11,0]}}
  #|{"textrec":{"g":316,"r":[1810,32,17,18,-1,-15,0]}}
  #|{"textrec":{"g":317,"r":[1828,32,19,18,-1,-15,0]}}
  #|{"textrec":{"g":163,"r":[1848,32,9,11,0,-9,0]}}
  #|{"textrec":{"g":322,"r":[1858,32,10,15,-1,-13,0]}}
  #|{"textrec":{"g":318,"r":[1869,32,16,15,-1,-12,0]}}
  #|{"textrec":{"g":319,"r":[1886,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":320,"r":[1902,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":321,"r":[1919,32,16,16,-1,-13,0]}}
  #|{"textrec":{"s":[11,400,0,"Apple M4 · 16 GB · macOS 27.0.1"],"r":[0,1,7.4765625,323,1,1,6.7783203125,324,2,1,6.7783203125,324,3,1,2.8466796875,325,4,1,6.3486328125,326,5,1,3.158203125,-1,6,1,9.6787109375,327,7,1,7.1435546875,328,8,1,3.158203125,-1,9,1,5.2804038549793475,329,10,1,3.158203125,-1,11,1,5.166992187499993,330,12,1,7.068359375,331,13,1,3.158203125,-1,14,1,8.27685546875,332,15,1,7.2939453125,333,16,1,3.158203125,-1,17,1,5.28040385497934,329,18,1,3.158203125,-1,19,1,9.6357421875,334,20,1,6.1337890625,335,21,1,6.2197265625,336,22,1,8.55078125,337,23,1,7.07373046875,338,24,1,3.158203125,-1,25,1,6.703125,339,26,1,5.736328125,340,27,1,2.5244140625,341,28,1,6.5634765625,342,29,1,2.9541015625,341,30,1,5.005859375,330]}}
  #|{"textrec":{"s":[28,600,0,"0"],"r":[0,1,18.237780570983887,343]}}
  #|{"textrec":{"m":[28,600,0],"r":[27.0703125,5.90625,40]}}
  #|{"textrec":{"s":[15,500,0,"%"],"r":[0,1,14.252007007598877,344]}}
  #|{"textrec":{"m":[15,500,0],"r":[14.501953125,3.1640625,21]}}
  #|{"textrec":{"s":[13,500,0,"CPU 空闲"],"r":[0,1,9.350531578063965,345,1,1,8.364851832389832,346,2,1,9.618190050125122,347,3,1,3.4683494567871094,-1,4,1,12.898832684824903,348,5,1,12.898832684824903,349]}}
  #|{"textrec":{"s":[12,400,0,"负载 13.1"],"r":[0,1,11.918287937743191,350,1,1,11.918287937743191,351,2,1,3.375,-1,3,1,5.56640625,352,4,1,7.318359375,353,5,1,3.181640625,354,6,1,5.390625,352]}}
  #|{"textrec":{"s":[28,600,0,"3.9"],"r":[0,1,17.48401165008545,355,1,1,6.724035739898682,356,2,1,18.289981365203857,357]}}
  #|{"textrec":{"s":[15,500,0,"GB"],"r":[0,1,11.039557456970215,358,1,1,9.822771549224854,359]}}
  #|{"textrec":{"s":[13,500,0,"内存剩"],"r":[0,1,12.898832684824903,360,1,1,12.898832684824903,361,2,1,12.898832684824903,362]}}
  #|{"textrec":{"s":[12,400,0,"共 16 GB"],"r":[0,1,11.918287937743191,363,1,1,3.375,-1,2,1,5.56640625,352,3,1,7.640625,364,4,1,3.375,-1,5,1,8.958984374999996,365,6,1,7.88671875,366]}}
  #|{"textrec":{"s":[28,600,0,"57.9"],"r":[0,1,17.471708297729492,367,1,1,14.867459774017334,368,2,1,5.590415000915527,356,3,1,18.289981365203857,357]}}
  #|{"textrec":{"s":[13,500,0,"磁盘剩"],"r":[0,1,12.898832684824903,369,1,1,12.898832684824903,370,2,1,12.898832684824903,362]}}
  #|{"textrec":{"s":[12,400,0,"共 228 GB"],"r":[0,1,11.918287937743191,363,1,1,3.375,-1,2,1,7.2421875,371,3,1,7.2421875,371,4,1,7.6640624999999964,372,5,1,3.375,-1,6,1,8.958984375,365,7,1,7.88671875,366]}}
  #|{"textrec":{"s":[13,400,0,"主机名"],"r":[0,1,12.898832684824903,373,1,1,12.898832684824903,374,2,1,12.898832684824903,375]}}
  #|{"textrec":{"s":[13,400,0,"3720-Mac-mini-1"],"r":[0,1,8.07421875,376,1,1,7.3251953125,377,2,1,7.76953125,378,3,1,8.1123046875,379,4,1,6.0556640625,309,5,1,11.2861328125,380,6,1,7.0966796875,12,7,1,7.1982421875,13,8,1,6.0556640625,309,9,1,11.2353515625,80,10,1,3.1357421875,77,11,1,7.50927734375,223,12,1,3.1357421875,77,13,1,6.0556640625,309,14,1,5.9541015625,381]}}
  #|{"textrec":{"s":[13,400,0,"芯片"],"r":[0,1,12.898832684824903,382,1,1,12.898832684824903,273]}}
  #|{"textrec":{"s":[13,400,0,"Apple M4 · 10 核 · arm64"],"r":[0,1,8.68359375,383,1,1,7.8583984375,11,2,1,7.8583984375,11,3,1,3.2119140625,76,4,1,7.3505859375,14,5,1,3.580078125,-1,6,1,11.2861328125,380,7,1,8.2900390625,384,8,1,3.580078125,-1,9,1,6.228545204222115,385,10,1,3.580078125,-1,11,1,5.9541015625,381,12,1,8.1123046875,379,13,1,3.580078125,-1,14,1,12.898832684824896,386,15,1,3.580078125,-1,16,1,6.228545204222115,385,17,1,3.580078125,-1,18,1,7.0966796875,12,19,1,4.9384765625,8,20,1,11.298828125,80,21,1,8.201171875,387,22,1,8.2900390625,384]}}
  #|{"textrec":{"s":[13,400,0,"已运行"],"r":[0,1,12.898832684824903,388,1,1,12.898832684824903,219,2,1,12.898832684824903,220]}}
  #|{"textrec":{"s":[13,400,0,"2 小时"],"r":[0,1,7.76953125,378,1,1,3.580078125,-1,2,1,12.898832684824903,389,3,1,12.898832684824903,153]}}
  #|{"textrec":{"s":[13,400,0,"still.fail"],"r":[0,1,6.69677734375,10,1,1,4.61474609375,82,2,1,3.1357421875,77,3,1,3.2119140625,76,4,1,3.2119140625,76,5,1,3.5927734375,81,6,1,4.341796875,308,7,1,7.00146484375,12,8,1,3.1357421875,77,9,1,3.2119140625,76]}}
  #|{"textrec":{"s":[13,400,0,"进程占用 133 MB"],"r":[0,1,12.898832684824903,224,1,1,12.898832684824903,225,2,1,12.898832684824903,390,3,1,12.898832684824903,391,4,1,3.580078125,-1,5,1,5.9541015625,381,6,1,8.07421875,376,7,1,8.07421875,376,8,1,3.580078125,-1,9,1,11.2861328125,380,10,1,8.4677734375,392]}}
  #|{"textrec":{"g":323,"r":[1936,32,10,10,-1,-9,0]}}
  #|{"textrec":{"g":324,"r":[1947,32,9,10,-1,-7,0]}}
  #|{"textrec":{"g":325,"r":[1957,32,4,11,-1,-10,0]}}
  #|{"textrec":{"g":326,"r":[1962,32,8,9,-1,-7,0]}}
  #|{"textrec":{"g":327,"r":[1971,32,11,10,-1,-9,0]}}
  #|{"textrec":{"g":328,"r":[1983,32,9,10,-1,-9,0]}}
  #|{"textrec":{"g":329,"r":[1993,32,5,4,0,-6,0]}}
  #|{"textrec":{"g":330,"r":[1999,32,6,10,-1,-9,0]}}
  #|{"textrec":{"g":331,"r":[2006,32,9,11,-1,-9,0]}}
  #|{"textrec":{"g":332,"r":[2016,32,10,11,-1,-9,0]}}
  #|{"textrec":{"g":333,"r":[2027,32,9,10,-1,-9,0]}}
  #|{"textrec":{"g":334,"r":[0,51,11,8,-1,-7,0]}}
  #|{"textrec":{"g":335,"r":[12,51,8,9,-1,-7,0]}}
  #|{"textrec":{"g":336,"r":[21,51,8,9,-1,-7,0]}}
  #|{"textrec":{"g":337,"r":[30,51,10,11,-1,-9,0]}}
  #|{"textrec":{"g":338,"r":[41,51,9,11,-1,-9,0]}}
  #|{"textrec":{"g":339,"r":[51,51,8,10,-1,-9,0]}}
  #|{"textrec":{"g":340,"r":[60,51,8,10,-1,-9,0]}}
  #|{"textrec":{"g":341,"r":[69,51,5,5,-1,-3,0]}}
  #|{"textrec":{"g":342,"r":[75,51,9,11,-1,-9,0]}}
  #|{"textrec":{"g":343,"r":[85,51,18,24,0,-22,0]}}
  #|{"textrec":{"g":344,"r":[104,51,16,14,-1,-12,0]}}
  #|{"textrec":{"g":345,"r":[121,51,11,13,-1,-11,0]}}
  #|{"textrec":{"g":346,"r":[133,51,9,12,0,-11,0]}}
  #|{"textrec":{"g":347,"r":[143,51,10,13,0,-11,0]}}
  #|{"textrec":{"g":348,"r":[154,51,14,14,-1,-12,0]}}
  #|{"textrec":{"g":349,"r":[169,51,13,15,0,-12,0]}}
  #|{"textrec":{"g":350,"r":[183,51,13,14,-1,-11,0]}}
  #|{"textrec":{"g":351,"r":[197,51,14,14,-1,-11,0]}}
  #|{"textrec":{"g":352,"r":[212,51,7,11,-1,-10,0]}}
  #|{"textrec":{"g":353,"r":[220,51,9,12,-1,-10,0]}}
  #|{"textrec":{"g":354,"r":[230,51,4,5,0,-3,0]}}
  #|{"textrec":{"g":355,"r":[235,51,17,24,0,-22,0]}}
  #|{"textrec":{"g":356,"r":[253,51,7,7,0,-5,0]}}
  #|{"textrec":{"g":357,"r":[261,51,18,24,0,-22,0]}}
  #|{"textrec":{"g":358,"r":[280,51,13,14,-1,-12,0]}}
  #|{"textrec":{"g":359,"r":[294,51,11,13,0,-12,0]}}
  #|{"textrec":{"g":360,"r":[306,51,13,15,0,-12,0]}}
  #|{"textrec":{"g":361,"r":[320,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":362,"r":[336,51,14,15,-1,-12,0]}}
  #|{"textrec":{"g":363,"r":[351,51,14,14,-1,-11,0]}}
  #|{"textrec":{"g":364,"r":[366,51,9,12,-1,-10,0]}}
  #|{"textrec":{"g":365,"r":[376,51,11,12,-1,-10,0]}}
  #|{"textrec":{"g":366,"r":[388,51,9,11,0,-10,0]}}
  #|{"textrec":{"g":367,"r":[398,51,18,23,0,-21,0]}}
  #|{"textrec":{"g":368,"r":[417,51,17,22,-1,-21,0]}}
  #|{"textrec":{"g":369,"r":[435,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":370,"r":[451,51,15,14,-1,-12,0]}}
  #|{"textrec":{"g":371,"r":[467,51,9,11,-1,-10,0]}}
  #|{"textrec":{"g":372,"r":[477,51,9,12,-1,-10,0]}}
  #|{"textrec":{"g":373,"r":[487,51,14,14,-1,-12,0]}}
  #|{"textrec":{"g":374,"r":[502,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":375,"r":[518,51,14,15,-1,-12,0]}}
  #|{"textrec":{"g":376,"r":[533,51,10,13,-1,-11,0]}}
  #|{"textrec":{"g":377,"r":[544,51,9,12,-1,-11,0]}}
  #|{"textrec":{"g":378,"r":[554,51,9,12,-1,-11,0]}}
  #|{"textrec":{"g":379,"r":[564,51,10,13,-1,-11,0]}}
  #|{"textrec":{"g":380,"r":[575,51,12,12,0,-11,0]}}
  #|{"textrec":{"g":381,"r":[588,51,7,12,-1,-11,0]}}
  #|{"textrec":{"g":382,"r":[596,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":273,"r":[612,51,14,15,-1,-12,0]}}
  #|{"textrec":{"g":383,"r":[627,51,11,12,-1,-11,0]}}
  #|{"textrec":{"g":384,"r":[639,51,10,12,-1,-11,0]}}
  #|{"textrec":{"g":385,"r":[650,51,4,5,1,-7,0]}}
  #|{"textrec":{"g":386,"r":[655,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":387,"r":[671,51,10,13,-1,-11,0]}}
  #|{"textrec":{"g":388,"r":[682,51,13,13,0,-11,0]}}
  #|{"textrec":{"g":389,"r":[696,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":153,"r":[712,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":390,"r":[728,51,13,15,0,-12,0]}}
  #|{"textrec":{"g":391,"r":[742,51,14,14,-1,-11,0]}}
  #|{"textrec":{"g":392,"r":[757,51,9,12,0,-11,0]}}
  #|{"textrec":{"s":[15,400,0,"例如机器名：studio"],"r":[0,1,14.883268482490273,393,1,1,14.883268482490273,394,2,1,14.883268482490273,132,3,1,14.883268482490273,395,4,1,14.88326848249028,282,5,1,15.08754863813229,396,6,1,7.58056640625,91,7,1,5.17822265625,101,8,1,8.51806640625,163,9,1,8.9794921875,322,10,1,3.4716796875,102,11,1,8.6279296875,88]}}
  #|{"textrec":{"g":393,"r":[767,51,16,17,-1,-14,0]}}
  #|{"textrec":{"g":394,"r":[784,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":395,"r":[801,51,17,16,-1,-13,0]}}
  #|{"textrec":{"g":396,"r":[819,51,5,10,1,-10,0]}}
  #|{"textrec":{"s":[15,400,0,"e2e-082939"],"r":[0,1,8.3349609375,95,1,1,8.78173828125,295,2,1,8.29833984375,95,3,1,6.8408203125,296,4,1,9.2138671875,164,5,1,9.345703125,397,6,1,8.818359375,295,7,1,9.31640625,398,8,1,9.169921875,293,9,1,9.31640625,398]}}
  #|{"textrec":{"g":397,"r":[825,51,11,14,-1,-12,0]}}
  #|{"textrec":{"g":398,"r":[837,51,11,14,-1,-12,0]}}
  #|{"textrec":{"s":[14,400,0,"已重命名"],"r":[0,1,13.891050583657588,399,1,1,13.891050583657588,400,2,1,13.891050583657588,401,3,1,13.891050583657588,402]}}
  #|{"textrec":{"g":399,"r":[849,51,14,14,0,-12,0]}}
  #|{"textrec":{"g":400,"r":[864,51,15,16,-1,-13,0]}}
  #|{"textrec":{"g":401,"r":[880,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":402,"r":[897,51,14,16,-1,-13,0]}}
  #|{"textrec":{"s":[16,600,0,"e2e-082939"],"r":[0,1,9.127458572387695,46,1,1,9.717817306518555,403,2,1,9.100765228271484,46,3,1,7.363014221191406,404,4,1,10.31976318359375,405,5,1,10.465335845947266,406,6,1,9.744510650634766,403,7,1,10.312868118286133,407,8,1,10.094772338867188,408,9,1,10.337606430053711,407]}}
  #|{"textrec":{"g":46,"r":[912,51,11,12,-1,-10,0]}}
  #|{"textrec":{"g":403,"r":[924,51,11,14,0,-13,0]}}
  #|{"textrec":{"g":404,"r":[936,51,8,5,0,-7,0]}}
  #|{"textrec":{"g":405,"r":[945,51,11,15,0,-13,0]}}
  #|{"textrec":{"g":406,"r":[957,51,12,15,-1,-13,0]}}
  #|{"textrec":{"g":407,"r":[970,51,12,15,-1,-13,0]}}
  #|{"textrec":{"g":408,"r":[983,51,11,15,0,-13,0]}}
  #|{"textrec":{"s":[17,700,0,"e2e-082939"],"r":[0,1,9.782470703125,409,1,1,10.479736328125,410,2,1,9.76171875,409,3,1,7.802734375,411,4,1,11.2060546875,412,5,1,11.36376953125,413,6,1,10.50048828125,410,7,1,11.127197265625,414,8,1,10.857421875,415,9,1,11.168701171875,414]}}
  #|{"textrec":{"g":409,"r":[995,51,12,13,-1,-11,0]}}
  #|{"textrec":{"g":410,"r":[1008,51,11,15,0,-14,0]}}
  #|{"textrec":{"g":411,"r":[1020,51,8,5,0,-7,0]}}
  #|{"textrec":{"g":412,"r":[1029,51,12,16,0,-14,0]}}
  #|{"textrec":{"g":413,"r":[1042,51,12,16,0,-14,0]}}
  #|{"textrec":{"g":414,"r":[1055,51,12,16,0,-14,0]}}
  #|{"textrec":{"g":415,"r":[1068,51,12,16,0,-14,0]}}
