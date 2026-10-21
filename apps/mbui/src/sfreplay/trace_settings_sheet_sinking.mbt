// e2e/traces/settings-sheet-sinking.trace, made by scripts/trace.py from 02-settings_sheet_sinking.log: not edited by hand.

///|
/// What the app and its core said in the run, a line each.
pub let trace_settings_sheet_sinking : String =
  #|{"start":"base"}
  #|{"step":"drive-seed 082939"}
  #|{"env":{"MBUI_CLOUD":"http://127.0.0.1:18900","MBUI_CORE_ACCOUNT":"{\"sub\":\"alice\",\"email\":\"alice@example.test\",\"name\":\"Name of alice\",\"picture\":\"\",\"access\":\"-\",\"refresh\":\"-\",\"accessExpires\":1792529364}"}}
  #|{"out":{"id":1,"call":"client.device","params":{"client":"still.fail mbui","app":"desktop","userAgent":"Macintosh; Mac OS X"}},"w":1792529107069.569}
  #|{"in":{"id":1,"ok":null},"w":1792529107213.469}
  #|{"out":{"id":2,"subscribe":{"topic":"accounts"},"keyed":true},"w":1792529107213.508}
  #|{"out":{"id":3,"subscribe":{"topic":"prefs"},"keyed":true},"w":1792529107213.526}
  #|{"step":"# written by scripts/rerecord.sh from its test (src/sfreplay/emit.mbt): not edited by hand","w":1792529107216.345}
  #|{"step":"timeout 90000","w":1792529107216.359}
  #|{"step":"answered client.device","w":1792529107216.362}
  #|{"step":"answered client.focus","w":1792529107258.603}
  #|{"in":{"id":2,"value":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""}]},"w":1792529107324.337}
  #|{"in":{"id":3,"value":{"onlyMine":false,"onlyWatching":false,"onlyDecisions":false,"listFilter":{},"appearance":"system","rowPicture":"auto","absoluteTime":false,"lang":"zh","keys":{},"lastChat":{},"openChat":{},"chatTabs":{},"dropFiles":{},"driveViews":{},"resume":{},"stationUpdatesDismissed":{},"device":{"app":"desktop","phone":false,"handoff":false},"reader":{"size":18,"line":1.7,"margin":22,"face":"sans","indent":true,"paper":"follow"},"rails":{},"bars":{"sets":[["chats","files","profiles","stations"],["decisions","usage","connects","archive"]],"current":0},"barsBy":{}}},"w":1792529107324.387}
  #|{"out":{"id":4,"subscribe":{"topic":"workspaces"},"keyed":true},"w":1792529107324.459}
  #|{"out":{"id":5,"subscribe":{"topic":"status"},"keyed":true},"w":1792529107324.49}
  #|{"in":{"id":4,"value":[{"account":{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""},"workspaces":[{"id":"01M5DGXKV9S6M382F9X64C8V7T","name":"Dev","role":"owner","created_at":1792529059,"stations":1,"members":1,"relays":[],"time":{"created_at":{"past":true,"at":1792529059000,"ago":"1 分钟前","full":"10/21 04:44:19","until":"1 分钟内"}}}],"invitations":[],"relay_url":"http://127.0.0.1:18940","loaded":true,"beta":true}]},"w":1792529107341.042}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792529107341.105}
  #|{"out":{"id":6,"subscribe":{"topic":"lock","workspace":"01M5DGXKV9S6M382F9X64C8V7T"},"keyed":true},"w":1792529107341.178}
  #|{"out":{"id":7,"subscribe":{"topic":"chats","scope":"01M5DGXKV9S6M382F9X64C8V7T","mine":false},"keyed":true},"w":1792529107341.212}
  #|{"out":{"id":8,"subscribe":{"topic":"workspaceMarks","workspace":"01M5DGXKV9S6M382F9X64C8V7T"},"keyed":true},"w":1792529107341.534}
  #|{"out":{"id":9,"subscribe":{"topic":"status","workspace":"01M5DGXKV9S6M382F9X64C8V7T"},"keyed":true},"w":1792529107341.608}
  #|{"out":{"id":10,"call":"client.focus","params":{"visible":true,"focused":true,"workspace":"01M5DGXKV9S6M382F9X64C8V7T"}},"w":1792529107349.53}
  #|{"out":{"id":11,"subscribe":{"topic":"notify"},"keyed":true},"w":1792529107349.544}
  #|{"out":{"id":12,"subscribe":{"topic":"notify","workspace":"01M5DGXKV9S6M382F9X64C8V7T"},"keyed":true},"w":1792529107349.551}
  #|{"in":{"id":6,"value":{"available":true,"locked":false,"notice":true,"role":"owner","manages":true,"owner":true,"canSign":true,"signs":false,"me":{"device":"00cb202f6dec0b293d76bd23f73e0dd619123df8213927bcdfc8d75821088da2","code":"SYM-FEK","kind":"app","confirmed":false,"waiting":false,"asked":false},"signers":0,"members":[],"stations":[{"id":"88a5ce0cf215b1e3267a98a057c8b17394922e982d6b46cbfea0dedd6df10706","name":"studio","version":"0.1.0","online":true,"protected":false}],"protected":0,"requests":[],"renew":[],"attention":0}},"w":1792529107358.314}
  #|{"in":{"id":7,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"stations":[{"station":"01M5DGXKV9S6M382F9X64C8V7T/88a5ce0cf215b1e3267a98a057c8b17394922e982d6b46cbfea0dedd6df10706","id":"88a5ce0cf215b1e3267a98a057c8b17394922e982d6b46cbfea0dedd6df10706","name":"studio","state":"online"}],"loading":false,"days":[{"daysAgo":0,"at":1792529064420,"label":"今天","items":[{"id":"ember:c-45483a50d8","session":"ember:c-45483a50d8","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","agents":[{"key":"ember:c-45483a50d8","runtime":"claude","process":"warm","pending":0,"lastTurn":{"id":"7024836f-0be2-4319-ab37-554aacc82567","kind":"input","outcome":"completed","declared":"final","ending":"all_done","need":"answered the question that was asked","startedAt":1792529064270,"endedAt":1792529064425},"agentText":"默认模型","statusText":"已完成：answered the question that was asked"}],"last":{"seq":2,"authorKind":"agent","author":"ember:c-45483a50d8","text":"你好，我是测试用的 agent","createdAt":1792529064420,"by":{"kind":"agent","name":"agent","mine":false,"runtime":"claude","label":"agent"},"preview":"你好，我是测试用的 agent","time":{"createdAt":{"at":1792529064420,"ago":"刚刚","full":"10/21 04:44:24","until":"1 分钟内","past":true}}},"unread":true,"mine":true,"lastActiveAt":1792529064420,"station":"01M5DGXKV9S6M382F9X64C8V7T/88a5ce0cf215b1e3267a98a057c8b17394922e982d6b46cbfea0dedd6df10706","stationName":"studio","time":{"lastActiveAt":{"at":1792529064420,"ago":"刚刚","full":"10/21 04:44:24","until":"1 分钟内","past":true}},"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"peopleText":"你 发起","clientKey":"new:chat-f109494dda205412bd","pinned":false,"tone":"done"}]}],"trouble":null,"members":1,"leading":"agents","glyph":{"online":1,"dim":0,"connecting":0,"failing":0,"working":0,"summary":"studio","label":"1 台 station，1 台在线"},"note":{"reading":false,"text":null,"failing":[],"empty":false}}},"w":1792529107358.399}
  #|{"in":{"id":8,"value":{"workspaces":{"01M5DGXKV9S6M382F9X64C8V7T":{"alert":0,"unread":1,"tone":"done","label":"1 个有新消息","badge":0,"items":[],"mineTone":"done"}},"badge":0,"badgeCounts":"attention","badgeKinds":{"on":true,"wait":true,"failed":true,"done":false,"message":false}}},"w":1792529107358.444}
  #|{"in":{"id":9,"value":{"items":[]}},"w":1792529107358.455}
  #|{"in":{"id":10,"ok":null},"w":1792529107358.496}
  #|{"in":{"id":11,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792529107358.514}
  #|{"in":{"id":12,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792529107358.524}
  #|{"out":{"id":13,"subscribe":{"topic":"longJobs","scope":"01M5DGXKV9S6M382F9X64C8V7T"},"keyed":true},"w":1792529107358.595}
  #|{"out":{"id":14,"call":"notify.permission","params":{"state":"unknown"}},"w":1792529107364.501}
  #|{"in":{"id":13,"value":{"groups":[]}},"w":1792529107374.403}
  #|{"in":{"id":14,"ok":null},"w":1792529107374.434}
  #|{"step":"answered notify.permission","w":1792529107377.78}
  #|{"step":"tap icon:settings","w":1792529107391.675}
  #|{"step":"tap icon:settings","acted":true,"w":1792529107408.377}
  #|{"out":{"id":15,"subscribe":{"topic":"workspace","workspace":"01M5DGXKV9S6M382F9X64C8V7T"},"keyed":true},"w":1792529107425.468}
  #|{"out":{"id":16,"subscribe":{"topic":"stations","scope":"01M5DGXKV9S6M382F9X64C8V7T"},"keyed":true},"w":1792529107425.511}
  #|{"out":{"id":17,"subscribe":{"topic":"connects","scope":"01M5DGXKV9S6M382F9X64C8V7T","mine":false},"keyed":true},"w":1792529107425.531}
  #|{"out":{"id":18,"subscribe":{"topic":"vaults","workspace":"01M5DGXKV9S6M382F9X64C8V7T"},"keyed":true},"w":1792529107425.538}
  #|{"out":{"id":19,"subscribe":{"topic":"doing"},"keyed":true},"w":1792529107434.317}
  #|{"step":"wait 300","w":1792529107435.752}
  #|{"in":{"id":15,"value":{"id":"01M5DGXKV9S6M382F9X64C8V7T","name":"Dev","role":"owner","created_at":1792529059,"members":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":"https://example.test/p.png","role":"owner","added_at":1792529059}],"stations":[{"id":"88a5ce0cf215b1e3267a98a057c8b17394922e982d6b46cbfea0dedd6df10706","name":"studio","emoji":null,"icon":null,"enrolled_at":1792529060,"enrolled_by":"alice","last_seen":1792529076,"version":"0.1.0","time":{"last_seen":{"past":true,"at":1792529076000,"ago":"刚刚","full":"10/21 04:44:36","until":"1 分钟内"}}}],"invitations":[],"added":[],"relays":[],"lock":null,"lock_requests":0,"time":{"created_at":{"past":true,"at":1792529059000,"ago":"1 分钟前","full":"10/21 04:44:19","until":"1 分钟内"}}}},"w":1792529107441.037}
  #|{"in":{"id":16,"value":[{"station":"01M5DGXKV9S6M382F9X64C8V7T/88a5ce0cf215b1e3267a98a057c8b17394922e982d6b46cbfea0dedd6df10706","id":"88a5ce0cf215b1e3267a98a057c8b17394922e982d6b46cbfea0dedd6df10706","name":"studio","summary":"正在连接","face":"idle","line":"在线","online":true,"reconnecting":true,"lastSeen":1792529076,"version":"0.1.0","link":{"state":"connecting"},"runtimes":[{"runtime":"claude","models":["claude-sonnet-5-5"]}],"models":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792529064201,"time":{"checkedAt":{"at":1792529064201,"ago":"刚刚","full":"10/21 04:44:24","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"overview":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null,"summaryText":"最近 7 天检查了 0 个 chat","changeText":null}},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","email":"alice@example.test","name":"Name of alice","sub":"alice","role":"owner","workspace":"01M5DGXKV9S6M382F9X64C8V7T","device":"00cb202f6dec0b293d76bd23f73e0dd619123df8213927bcdfc8d75821088da2"},"connects":[],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792529064008,"time":{"checkedAt":{"at":1792529064008,"ago":"刚刚","full":"10/21 04:44:24","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792529064201,"time":{"checkedAt":{"at":1792529064201,"ago":"刚刚","full":"10/21 04:44:24","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]}],"processes":[],"counts":{"sessions":1,"running":0,"warm":1},"mesh":{"state":"running","origin":"http://127.0.0.1:18900","station":"88a5ce0cf215b1e3267a98a057c8b17394922e982d6b46cbfea0dedd6df10706","workspace":"Dev","workspaceId":"01M5DGXKV9S6M382F9X64C8V7T","name":"studio"},"slackUsers":[],"slackTeams":[],"slackApps":[],"feishuRegistrations":[],"disk":{"freeBytes":62537682944,"totalBytes":245107195904},"logins":[],"machineLogins":[],"sharing":true,"consoleSignIn":true,"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"google","name":"Google Gemini","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xai","name":"xAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"mistral","name":"Mistral","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"deepseek","name":"DeepSeek","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen","name":"Qwen","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai","name":"Kimi","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai","name":"Z.ai","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax","name":"MiniMax","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ant-ling","name":"Ant Ling","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"jev","name":"Jev","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen-cn","name":"Qwen (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"openrouter","name":"OpenRouter","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"opencode","name":"OpenCode Zen","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"groq","name":"Groq","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"together","name":"Together AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"fireworks","name":"Fireworks","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cerebras","name":"Cerebras","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"huggingface","name":"Hugging Face","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"nvidia","name":"NVIDIA","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"baseten","name":"Baseten","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ollama","name":"Ollama","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"custom","name":"Custom","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""}],"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792529061706},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.304","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792529061706},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792529061706},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792529061706},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","latest":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792529061706}],"processesText":"没有运行中的 agent 进程","agentEnv":[],"drive":{"roots":[],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false}},"betaOffered":false,"time":{"lastSeen":{"at":1792529076000,"ago":"刚刚","full":"10/21 04:44:36","until":"1 分钟内","past":true}},"joined":false}]},"w":1792529107441.256}
  #|{"in":{"id":17,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"items":[],"wait":{"reading":false,"text":null,"failing":[],"empty":true}}},"w":1792529107441.4}
  #|{"in":{"id":18,"value":{"available":true,"locked":false,"canSign":false,"setUp":false,"vaults":[],"requests":[],"refused":[],"plain":true}},"w":1792529107441.41}
  #|{"in":{"id":19,"value":{"doing":[]}},"w":1792529107441.416}
  #|{"step":"now tap =Station","w":1792529107741.493}
  #|{"step":"now tap =Station","acted":true,"w":1792529107758.184}
  #|{"step":"wait 300","w":1792529107779.083}
  #|{"step":"now tap =studio","w":1792529108091.663}
  #|{"step":"now tap =studio","acted":true,"w":1792529108108.209}
  #|{"out":{"id":20,"subscribe":{"topic":"screens","station":"01M5DGXKV9S6M382F9X64C8V7T/88a5ce0cf215b1e3267a98a057c8b17394922e982d6b46cbfea0dedd6df10706"},"keyed":true},"w":1792529108125.58}
  #|{"out":{"id":21,"subscribe":{"topic":"memberships","station":"01M5DGXKV9S6M382F9X64C8V7T/88a5ce0cf215b1e3267a98a057c8b17394922e982d6b46cbfea0dedd6df10706"},"keyed":true},"w":1792529108125.626}
  #|{"out":{"id":22,"subscribe":{"topic":"adbShare"},"keyed":true},"w":1792529108126.331}
  #|{"step":"wait 300","w":1792529108127.137}
  #|{"in":{"id":20,"value":{"screens":[],"outdated":false,"control":true,"known":false}},"w":1792529108140.981}
  #|{"in":{"id":21,"value":{"manages":true,"loading":true,"canJoin":false,"workspaces":[]}},"w":1792529108141.013}
  #|{"in":{"id":22,"value":{"sharing":false,"phase":"off","tunnels":0}},"w":1792529108141.023}
  #|{"step":"now tap icon:more","w":1792529108441.228}
  #|{"step":"now tap icon:more","acted":true,"w":1792529108457.83}
  #|{"step":"rest","w":1792529108476.04}
  #|{"in":{"id":5,"value":{"state":"slow","text":"正在连接 studio · 2 秒 · 共 2 项","items":[{"state":"slow","text":"正在连接 studio","detail":"已等待 2 秒"},{"state":"slow","text":"studio 打开实时更新","detail":"已等待 2 秒，尚未收到数据"}]}},"w":1792529109324.458}
  #|{"in":{"id":9,"value":{"state":"slow","text":"正在连接 studio · 2 秒 · 共 2 项","items":[{"state":"slow","text":"正在连接 studio","detail":"已等待 2 秒"},{"state":"slow","text":"studio 打开实时更新","detail":"已等待 2 秒，尚未收到数据"}]}},"w":1792529109324.496}
  #|{"step":"now tap 重命名","w":1792529109908.324}
  #|{"step":"now tap 重命名","acted":true,"w":1792529109924.96}
  #|{"step":"rest","w":1792529109941.612}
  #|{"in":{"id":5,"value":{"state":"slow","text":"studio 打开实时更新 ×2 · 3 秒 · 共 2 项 · 283 B/s","items":[{"state":"slow","text":"studio 打开实时更新 ×2","detail":"已等待 3 秒，尚未收到数据"}]}},"w":1792529110158.682}
  #|{"in":{"id":9,"value":{"state":"slow","text":"studio 打开实时更新 ×2 · 3 秒 · 共 2 项 · 283 B/s","items":[{"state":"slow","text":"studio 打开实时更新 ×2","detail":"已等待 3 秒，尚未收到数据"}]}},"w":1792529110158.711}
  #|{"in":{"id":18,"delta":[{"path":["refused"],"append":[{"station":"88a5ce0cf215b1e3267a98a057c8b17394922e982d6b46cbfea0dedd6df10706","name":"studio","code":"vault_needs_lock"}]},{"path":["vaults"],"key":["id"],"put":{"id":"plain","name":"个人","owner":"alice","ownerName":"Name of alice","mine":true,"members":[{"sub":"alice","name":"Name of alice"}],"station":"88a5ce0cf215b1e3267a98a057c8b17394922e982d6b46cbfea0dedd6df10706","stationName":"studio","items":0,"devices":0,"open":true,"keyed":true,"missing":0,"recoverable":false},"before":null}]},"w":1792529110158.722}
  #|{"in":{"id":21,"value":{"manages":true,"loading":false,"canJoin":true,"workspaces":[{"workspace":"01M5DGXKV9S6M382F9X64C8V7T","name":"Dev","stationName":"studio","home":true,"here":true,"line":"主 workspace"}]}},"w":1792529110158.741}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792529110224.3}
  #|{"in":{"id":9,"value":{"items":[]}},"w":1792529110224.329}
  #|{"in":{"id":20,"value":{"screens":[{"id":"desktop","kind":"desktop","title":"3720-Mac-mini-1","width":0,"height":0,"viewers":[],"controlledBy":[],"access":{"capture":false,"control":false,"message":"此 station 版本不含屏幕助手（stillfail-screen），请更新 station"},"clipboard":[],"drop":{"folder":"/tmp/mbe2e-C/home","reveal":true},"peek":false,"line":"此 station 版本不含屏幕助手（stillfail-screen），请更新 station","link":"/w/01M5DGXKV9S6M382F9X64C8V7T/s/88a5ce0cf215b1e3267a98a057c8b17394922e982d6b46cbfea0dedd6df10706/screen/desktop"}],"outdated":false,"control":true,"known":true}},"w":1792529110224.351}
  #|{"in":{"id":7,"delta":[{"path":["days"],"key":["daysAgo"],"patch":0,"ops":[{"path":["items"],"key":["station","id"],"patch":["01M5DGXKV9S6M382F9X64C8V7T/88a5ce0cf215b1e3267a98a057c8b17394922e982d6b46cbfea0dedd6df10706","ember:c-45483a50d8"],"ops":[{"path":["agents",0,"process"],"set":"cold"},{"path":["last","time","createdAt","ago"],"set":"1 分钟前"},{"path":["time","lastActiveAt","ago"],"set":"1 分钟前"},{"path":["clientKey"],"remove":true}]}]}]},"w":1792529110224.383}
  #|{"in":{"id":16,"delta":[{"path":[0,"link","state"],"set":"online"},{"path":[0,"models",0,"accounts","claude",0,"quota","time","checkedAt","ago"],"set":"1 分钟前"},{"path":[0,"overview","counts","warm"],"set":0},{"path":[0,"overview","disk","freeBytes"],"set":62366453760},{"path":[0,"overview","profiles",0,"check","checkedAt"],"set":1792529110035},{"path":[0,"overview","profiles",0,"check","time","checkedAt","at"],"set":1792529110035},{"path":[0,"overview","profiles",0,"check","time","checkedAt","full"],"set":"10/21 04:45:10"},{"path":[0,"overview","profiles",0,"quota","time","checkedAt","ago"],"set":"1 分钟前"},{"path":[0,"overview","updates",0,"checkedAt"],"set":1792529107650},{"path":[0,"overview","updates",1,"checkedAt"],"set":1792529107650},{"path":[0,"overview","updates",2,"checkedAt"],"set":1792529107650},{"path":[0,"overview","updates",3,"checkedAt"],"set":1792529107650},{"path":[0,"overview","updates",4,"checkedAt"],"set":1792529107650},{"path":[0,"reconnecting"],"set":false}]},"w":1792529110224.435}
  #|{"in":{"id":16,"delta":[{"path":[0,"host"],"set":{"hostname":"3720-Mac-mini-1","os":"macOS 27.0.1","arch":"arm64","cpus":10,"cpuModel":"Apple M4","load":1.27,"cpuBusy":0.84,"uptimeSec":8472,"memory":{"totalBytes":17179869184,"usedBytes":12408258560,"swapUsedBytes":341961605},"disk":{"path":"/tmp/mbe2e-C/data","totalBytes":245107195904,"freeBytes":62366265344},"emberRssBytes":141193984,"checkedAt":1792529110234,"summary":"10 核 · 16 GB","line":"macOS 27.0.1 · 10 核 · 16 GB · 已运行 0 天","facts":["3720-Mac-mini-1","macOS 27.0.1","arm64 · 10 核","已运行 2 小时"],"meters":[{"label":"CPU","short":"CPU","percent":84,"left":16,"level":"amber","value":"84%","remaining":"空闲 16%","big":"16","unit":"%","title":"CPU 空闲","total":"负载 12.7","note":"负载 12.7 · Apple M4"},{"label":"内存","short":"内存","percent":72,"left":28,"level":"ok","value":"11.6 GB / 16.0 GB","remaining":"剩 4.4 G","big":"4.4","unit":"GB","title":"内存剩","total":"共 16 GB","note":"swap 0.3 GB"},{"label":"磁盘","short":"磁盘","percent":75,"left":25,"level":"amber","value":"剩余 58.1 GB / 228 GB","remaining":"剩 58.1 G","big":"58.1","unit":"GB","title":"磁盘剩","total":"共 228 GB"}],"identity":"Apple M4 · 16 GB · macOS 27.0.1","details":[{"label":"主机名","value":"3720-Mac-mini-1"},{"label":"芯片","value":"Apple M4 · 10 核 · arm64"},{"label":"已运行","value":"2 小时"},{"label":"still.fail","value":"进程占用 135 MB"}],"usage":"内存 11.6 GB / 16.0 GB · 磁盘 剩余 58.1 GB / 228 GB","emberText":"still.fail 135 MB"}},{"path":[0,"line"],"set":"Apple M4"},{"path":[0,"summary"],"set":"空闲 · Apple M4 · 16 GB · macOS 27.0.1"}]},"w":1792529110540.979}
  #|{"step":"now clear","w":1792529111291.305}
  #|{"step":"now clear","acted":true,"w":1792529111291.325}
  #|{"step":"type e2e-not-082939","w":1792529111308.653}
  #|{"step":"type e2e-not-082939","acted":true,"w":1792529111308.663}
  #|{"step":"tapxy 195 60","w":1792529111324.815}
  #|{"step":"tapxy 195 60","acted":true,"w":1792529111324.823}
  #|{"step":"tapxy -60 -330","w":1792529111341.556}
  #|{"step":"tapxy -60 -330","acted":true,"w":1792529111341.57}
  #|{"step":"tapxy -60 -300","w":1792529111359.719}
  #|{"step":"tapxy -60 -300","acted":true,"w":1792529111359.73}
  #|{"step":"tapxy -60 -270","w":1792529111376.337}
  #|{"step":"tapxy -60 -270","acted":true,"w":1792529111376.347}
  #|{"step":"tapxy -60 -240","w":1792529111391.353}
  #|{"step":"tapxy -60 -240","acted":true,"w":1792529111391.367}
  #|{"step":"rest","w":1792529111407.951}
  #|{"in":{"id":16,"delta":[{"path":[0,"way"],"set":{"path":"直连","via":"direct"}}]},"w":1792529112074.276}
  #|{"step":"now gone station 名称","w":1792529112774.392}
  #|{"step":"until =studio","w":1792529112774.403}
  #|{"step":"rest","w":1792529112774.413}
  #|{"step":"","w":1792529112807.749}
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
  #|{"textrec":{"ib":["fdb526ba00f881f4",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["a7ccae3554fe46cf",3232,64],"r":[28,28,28,28]}}
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
  #|{"textrec":{"s":[15,400,0,"密钥"],"r":[0,1,14.883268482490273,177,1,1,14.883268482490273,178]}}
  #|{"textrec":{"s":[14,400,0,"1/1 在线"],"r":[0,1,6.34375,175,1,1,4.115234375,179,2,1,6.34375,175,3,1,3.787109375,-1,4,1,13.891050583657588,180,5,1,13.891050583657588,181]}}
  #|{"textrec":{"s":[14,400,0,"0 个"],"r":[0,1,8.66796875,182,1,1,3.787109375,-1,2,1,13.891050583657588,183]}}
  #|{"textrec":{"s":[14,400,0,"1 个"],"r":[0,1,6.34375,175,1,1,3.787109375,-1,2,1,13.891050583657588,183]}}
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
  #|{"textrec":{"g":177,"r":[1012,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":178,"r":[1029,0,16,16,-1,-13,0]}}
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
  #|{"textrec":{"g":179,"r":[1771,0,7,16,-1,-12,0]}}
  #|{"textrec":{"g":180,"r":[1779,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":181,"r":[1795,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":120,"r":[1812,0,16,15,-1,-12,0]}}
  #|{"textrec":{"g":121,"r":[1829,0,15,16,0,-13,0]}}
  #|{"textrec":{"g":122,"r":[1845,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":123,"r":[1861,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":176,"r":[1878,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":182,"r":[1895,0,10,14,-1,-12,0]}}
  #|{"textrec":{"g":183,"r":[1906,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":126,"r":[1923,0,9,13,0,-12,0]}}
  #|{"textrec":{"g":127,"r":[1933,0,16,16,-1,-13,0]}}
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
  #|{"textrec":{"g":186,"r":[1950,0,19,18,-1,-15,0]}}
  #|{"textrec":{"g":187,"r":[1970,0,18,17,-1,-14,0]}}
  #|{"textrec":{"ib":["b7b1dc2c98725280",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"g":194,"r":[1989,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":195,"r":[2001,0,8,14,-1,-12,0]}}
  #|{"textrec":{"g":196,"r":[2010,0,10,12,0,-10,0]}}
  #|{"textrec":{"g":197,"r":[2021,0,12,15,-1,-13,0]}}
  #|{"textrec":{"g":0,"r":[0,32,14,13,-1,-11,0]}}
  #|{"textrec":{"g":1,"r":[15,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":198,"r":[30,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":199,"r":[46,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":184,"r":[62,32,12,15,-1,-13,0]}}
  #|{"textrec":{"g":44,"r":[75,32,11,12,-1,-10,0]}}
  #|{"textrec":{"g":185,"r":[87,32,5,15,0,-14,0]}}
  #|{"textrec":{"g":47,"r":[93,32,10,11,0,-10,0]}}
  #|{"textrec":{"g":188,"r":[104,32,14,12,-1,-10,0]}}
  #|{"textrec":{"g":189,"r":[119,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":190,"r":[134,32,14,13,-1,-11,0]}}
  #|{"textrec":{"g":191,"r":[149,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":192,"r":[164,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":193,"r":[179,32,14,14,-1,-11,0]}}
  #|{"textrec":{"ib":["56cdacf263ae288e",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["536c426c0236d661",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["365bf49de4f5d505",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["2bb63fc1d380f765",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["3a089f86e58e836f",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["d199cb74c5a62786",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["9e48044fa6815e02",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["5018c6b0c428bd67",656,64],"r":[12,12,12,12]}}
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
  #|{"textrec":{"ib":["0ac9db1649fc9777",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"g":212,"r":[194,32,12,16,-1,-14,0]}}
  #|{"textrec":{"g":213,"r":[207,32,8,15,-1,-13,0]}}
  #|{"textrec":{"g":214,"r":[216,32,11,13,-1,-11,0]}}
  #|{"textrec":{"g":215,"r":[228,32,5,15,0,-14,0]}}
  #|{"textrec":{"g":216,"r":[234,32,12,13,-1,-11,0]}}
  #|{"textrec":{"g":217,"r":[247,32,10,12,0,-11,0]}}
  #|{"textrec":{"g":218,"r":[258,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":149,"r":[274,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":219,"r":[289,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":220,"r":[305,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":221,"r":[321,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":5,"r":[335,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":222,"r":[349,32,9,12,-1,-8,0]}}
  #|{"textrec":{"g":223,"r":[359,32,8,9,0,-8,0]}}
  #|{"textrec":{"g":224,"r":[368,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":225,"r":[384,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":226,"r":[400,32,16,17,-1,-14,0]}}
  #|{"textrec":{"g":227,"r":[417,32,10,12,-1,-10,0]}}
  #|{"textrec":{"g":228,"r":[428,32,8,13,-1,-11,0]}}
  #|{"textrec":{"g":229,"r":[437,32,10,12,-1,-10,0]}}
  #|{"textrec":{"g":230,"r":[448,32,6,14,-1,-13,0]}}
  #|{"textrec":{"g":231,"r":[455,32,11,12,-1,-10,0]}}
  #|{"textrec":{"g":232,"r":[467,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":233,"r":[484,32,16,17,-1,-14,0]}}
  #|{"textrec":{"g":234,"r":[501,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":235,"r":[518,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":236,"r":[535,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":238,"r":[553,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":239,"r":[571,32,16,17,-1,-14,0]}}
  #|{"textrec":{"g":240,"r":[588,32,13,13,-1,-12,0]}}
  #|{"textrec":{"g":241,"r":[602,32,11,14,-1,-10,0]}}
  #|{"textrec":{"g":242,"r":[614,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":243,"r":[632,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":244,"r":[650,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":245,"r":[668,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":246,"r":[685,32,15,17,0,-14,0]}}
  #|{"textrec":{"g":247,"r":[701,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":248,"r":[718,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":249,"r":[736,32,16,17,-1,-14,0]}}
  #|{"textrec":{"g":250,"r":[753,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":251,"r":[771,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":252,"r":[789,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":253,"r":[806,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":254,"r":[824,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":255,"r":[842,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":256,"r":[860,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":6,"r":[877,32,12,9,-1,-8,0]}}
  #|{"textrec":{"g":7,"r":[890,32,9,10,-1,-8,0]}}
  #|{"textrec":{"g":8,"r":[900,32,6,9,0,-8,0]}}
  #|{"textrec":{"g":9,"r":[907,32,8,12,0,-11,0]}}
  #|{"textrec":{"g":140,"r":[916,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":257,"r":[932,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":258,"r":[947,32,15,14,-1,-12,0]}}
  #|{"textrec":{"g":259,"r":[963,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":260,"r":[978,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":261,"r":[994,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":262,"r":[1009,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":263,"r":[1024,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":141,"r":[1040,32,6,6,0,-3,0]}}
  #|{"textrec":{"g":264,"r":[1047,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":152,"r":[1063,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":265,"r":[1079,32,11,14,1,-11,0]}}
  #|{"textrec":{"g":266,"r":[1091,32,14,14,-1,-11,0]}}
  #|{"textrec":{"ib":["dc2a7c23677cea3f",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["0b44c3b15eb4e72a",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"g":210,"r":[1106,32,10,12,0,-10,0]}}
  #|{"textrec":{"g":211,"r":[1117,32,11,15,-1,-13,0]}}
  #|{"textrec":{"ib":["a32136b675dfede6",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"g":237,"r":[1129,32,16,16,-1,-13,0]}}
  #|{"textrec":{"ib":["80471d92f205f03a",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["21d27b298626ff58",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["ddfdc2820df8a676",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"ib":["f50dcfc8e7b09e13",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["d2ccd5cf9373640b",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["a84714a0d118c5eb",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["3e89fb0d7a2d2be5",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"s":[17,700,0,"studio"],"r":[0,1,9.176513671875,274,1,1,6.561767578125,275,2,1,10.230712890625,276,3,1,10.6416015625,277,4,1,4.44921875,278,5,1,10.10205078125,279]}}
  #|{"textrec":{"m":[17,700,0],"r":[16.435546875,3.5859375,24]}}
  #|{"textrec":{"s":[15,400,0,"重命名"],"r":[0,1,14.883268482490273,280,1,1,14.883268482490273,281,2,1,14.883268482490273,282]}}
  #|{"textrec":{"s":[15,400,0,"图标"],"r":[0,1,14.883268482490273,283,1,1,14.883268482490273,284]}}
  #|{"textrec":{"s":[15,400,0,"从 workspace 移除"],"r":[0,1,14.883268482490273,285,1,1,3.984375,-1,2,1,11.2353515625,286,3,1,8.4814453125,88,4,1,5.478515625,89,5,1,7.763671875,90,6,1,7.470703125,91,7,1,8.920898437500007,92,8,1,8.0419921875,93,9,1,8.1591796875,94,10,1,8.3349609375,95,11,1,3.984375,-1,12,1,14.88326848249028,287,13,1,14.88326848249028,288]}}
  #|{"textrec":{"g":274,"r":[1146,32,11,13,-1,-11,0]}}
  #|{"textrec":{"g":275,"r":[1158,32,9,15,-1,-13,0]}}
  #|{"textrec":{"g":276,"r":[1168,32,11,13,0,-11,0]}}
  #|{"textrec":{"g":277,"r":[1180,32,12,16,-1,-14,0]}}
  #|{"textrec":{"g":278,"r":[1193,32,5,16,0,-15,0]}}
  #|{"textrec":{"g":279,"r":[1199,32,12,13,-1,-11,0]}}
  #|{"textrec":{"g":280,"r":[1212,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":281,"r":[1229,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":282,"r":[1246,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":283,"r":[1262,32,15,16,0,-13,0]}}
  #|{"textrec":{"g":284,"r":[1278,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":285,"r":[1295,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":286,"r":[1313,32,14,10,-1,-9,0]}}
  #|{"textrec":{"g":287,"r":[1328,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":288,"r":[1345,32,16,16,0,-13,0]}}
  #|{"textrec":{"ib":["abd519d291ad649c",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["550a89fdd3627b9e",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["8a3f7c664f10bd54",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["bc56d3e0d751880c",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["8702d89573d5efdf",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["70da3a129cd335a2",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["831523b197f71e32",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"s":[17,700,0,"station 名称"],"r":[0,1,9.176513671875,274,1,1,6.561767578125,275,2,1,9.591552734375,289,3,1,6.58251953125,275,4,1,4.44921875,278,5,1,10.10205078125,279,6,1,10.230712890625,290,7,1,3.951171875,-1,8,1,16.851167315175104,291,9,1,16.851167315175104,292]}}
  #|{"textrec":{"s":[14,600,0,"取消"],"r":[0,1,13.891050583657588,293,1,1,13.891050583657588,294]}}
  #|{"textrec":{"m":[14,600,0],"r":[13.53515625,2.953125,20]}}
  #|{"textrec":{"s":[14,600,0,"保存"],"r":[0,1,13.891050583657588,295,1,1,13.891050583657588,296]}}
  #|{"textrec":{"s":[15,400,0,"studio"],"r":[0,1,7.58056640625,91,1,1,5.17822265625,101,2,1,8.51806640625,163,3,1,8.9794921875,297,4,1,3.4716796875,102,5,1,8.6279296875,88]}}
  #|{"textrec":{"g":289,"r":[1362,32,11,13,-1,-11,0]}}
  #|{"textrec":{"g":290,"r":[1374,32,11,12,0,-11,0]}}
  #|{"textrec":{"g":291,"r":[1386,32,17,18,-1,-15,0]}}
  #|{"textrec":{"g":292,"r":[1404,32,19,18,-1,-15,0]}}
  #|{"textrec":{"g":163,"r":[1424,32,9,11,0,-9,0]}}
  #|{"textrec":{"g":297,"r":[1434,32,10,15,-1,-13,0]}}
  #|{"textrec":{"g":293,"r":[1445,32,16,15,-1,-12,0]}}
  #|{"textrec":{"g":294,"r":[1462,32,15,16,-1,-13,0]}}
  #|{"textrec":{"g":295,"r":[1478,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":296,"r":[1495,32,16,16,-1,-13,0]}}
  #|{"textrec":{"s":[11,400,0,"在线"],"r":[0,1,10.93579766536965,298,1,1,10.93579766536965,299]}}
  #|{"textrec":{"m":[11,400,0],"r":[10.634765625,2.3203125,16]}}
  #|{"textrec":{"s":[15,600,0,"屏幕"],"r":[0,1,14.883268482490273,300,1,1,14.883268482490273,301]}}
  #|{"textrec":{"s":[15,400,0,"3720-Mac-mini-1"],"r":[0,1,9.169921875,302,1,1,8.3056640625,303,2,1,8.818359375,304,3,1,9.2138671875,164,4,1,6.8408203125,305,5,1,12.8759765625,306,6,1,8.0419921875,93,7,1,8.1591796875,94,8,1,6.8408203125,305,9,1,12.8173828125,161,10,1,3.4716796875,102,11,1,8.51806640625,103,12,1,3.4716796875,102,13,1,6.8408203125,305,14,1,6.7236328125,165]}}
  #|{"textrec":{"s":[13,400,0,"此 station 版本不含屏幕助手（stillfail-screen），请更新 station"],"r":[0,1,12.898832684824903,307,1,1,3.580078125,-1,2,1,6.69677734375,10,3,1,4.61474609375,82,4,1,7.0966796875,12,5,1,4.646484375,82,6,1,3.1357421875,77,7,1,7.6044921875,7,8,1,7.50927734375,223,9,1,3.580078125,-1,10,1,12.898832684824903,308,11,1,12.89883268482491,309,12,1,12.898832684824896,310,13,1,12.898832684824896,311,14,1,12.898832684824896,312,15,1,12.898832684824896,313,16,1,12.898832684824896,314,17,1,19.398832684824896,315,18,1,4.071984435797674,316,19,1,6.69677734375,10,20,1,4.61474609375,82,21,1,3.1357421875,77,22,1,3.2119140625,76,23,1,3.2119140625,76,24,1,4.5322265625,317,25,1,7.00146484375,12,26,1,3.1357421875,77,27,1,3.2119140625,76,28,1,6.0556640625,318,29,1,6.728515625,10,30,1,7.1982421875,13,31,1,4.77978515625,8,32,1,7.25537109375,14,33,1,7.3505859375,14,34,1,7.50927734375,223,35,1,5.456712062256827,319,36,1,13.075875486381335,320,37,1,12.898832684824924,321,38,1,12.898832684824924,322,39,1,12.898832684824924,150,40,1,3.580078125,-1,41,1,6.69677734375,10,42,1,4.61474609375,82,43,1,7.0966796875,12,44,1,4.646484375,82,45,1,3.1357421875,77,46,1,7.6044921875,7,47,1,7.50927734375,223]}}
  #|{"textrec":{"g":298,"r":[1512,32,13,13,-1,-10,0]}}
  #|{"textrec":{"g":299,"r":[1526,32,13,13,-1,-10,0]}}
  #|{"textrec":{"g":300,"r":[1540,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":301,"r":[1557,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":302,"r":[1575,32,10,14,0,-12,0]}}
  #|{"textrec":{"g":303,"r":[1586,32,10,13,-1,-12,0]}}
  #|{"textrec":{"g":304,"r":[1597,32,10,13,0,-12,0]}}
  #|{"textrec":{"g":164,"r":[1608,32,11,14,-1,-12,0]}}
  #|{"textrec":{"g":305,"r":[1620,32,7,4,0,-6,0]}}
  #|{"textrec":{"g":306,"r":[1628,32,13,13,0,-12,0]}}
  #|{"textrec":{"g":161,"r":[1642,32,13,11,0,-10,0]}}
  #|{"textrec":{"g":165,"r":[1656,32,8,13,-1,-12,0]}}
  #|{"textrec":{"g":307,"r":[1665,32,15,14,-1,-12,0]}}
  #|{"textrec":{"g":308,"r":[1681,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":309,"r":[1697,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":310,"r":[1713,32,15,14,-1,-11,0]}}
  #|{"textrec":{"g":311,"r":[1729,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":312,"r":[1745,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":313,"r":[1760,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":314,"r":[1776,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":315,"r":[1791,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":316,"r":[1807,32,5,15,-1.16666666666667,-12,0]}}
  #|{"textrec":{"g":317,"r":[1813,32,7,12,-1,-11,0]}}
  #|{"textrec":{"g":318,"r":[1821,32,8,4,-1,-6,0]}}
  #|{"textrec":{"g":319,"r":[1830,32,6,15,-1,-12,0]}}
  #|{"textrec":{"g":320,"r":[1837,32,5,7,0,-3,0]}}
  #|{"textrec":{"g":321,"r":[1843,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":322,"r":[1859,32,15,14,-1,-11,0]}}
  #|{"textrec":{"g":150,"r":[1875,32,15,15,-1,-12,0]}}
  #|{"textrec":{"ib":["dfa0b3408acf8bc7",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"s":[11,400,0,"Apple M4 · 16 GB · macOS 27.0.1"],"r":[0,1,7.4765625,323,1,1,6.7783203125,324,2,1,6.7783203125,324,3,1,2.8466796875,325,4,1,6.3486328125,326,5,1,3.158203125,-1,6,1,9.6787109375,327,7,1,7.1435546875,328,8,1,3.158203125,-1,9,1,5.2804038549793475,329,10,1,3.158203125,-1,11,1,5.166992187499993,330,12,1,7.068359375,331,13,1,3.158203125,-1,14,1,8.27685546875,332,15,1,7.2939453125,333,16,1,3.158203125,-1,17,1,5.28040385497934,329,18,1,3.158203125,-1,19,1,9.6357421875,334,20,1,6.1337890625,335,21,1,6.2197265625,336,22,1,8.55078125,337,23,1,7.07373046875,338,24,1,3.158203125,-1,25,1,6.703125,339,26,1,5.736328125,340,27,1,2.5244140625,341,28,1,6.5634765625,342,29,1,2.9541015625,341,30,1,5.005859375,330]}}
  #|{"textrec":{"s":[28,600,0,"16"],"r":[0,1,13.446255683898926,343,1,1,18.283138751983643,344]}}
  #|{"textrec":{"m":[28,600,0],"r":[27.0703125,5.90625,40]}}
  #|{"textrec":{"s":[15,500,0,"%"],"r":[0,1,14.252007007598877,345]}}
  #|{"textrec":{"m":[15,500,0],"r":[14.501953125,3.1640625,21]}}
  #|{"textrec":{"s":[13,500,0,"CPU 空闲"],"r":[0,1,9.350531578063965,346,1,1,8.364851832389832,347,2,1,9.618190050125122,348,3,1,3.4683494567871094,-1,4,1,12.898832684824903,349,5,1,12.898832684824903,350]}}
  #|{"textrec":{"s":[12,400,0,"负载 12.7"],"r":[0,1,11.918287937743191,351,1,1,11.918287937743191,352,2,1,3.375,-1,3,1,5.56640625,353,4,1,7.154296875,354,5,1,3.26953125,355,6,1,6.626953125,356]}}
  #|{"textrec":{"s":[28,600,0,"4.4"],"r":[0,1,18.070533752441406,357,1,1,6.943917274475098,358,2,1,18.15711784362793,357]}}
  #|{"textrec":{"s":[15,500,0,"GB"],"r":[0,1,11.039557456970215,359,1,1,9.822771549224854,360]}}
  #|{"textrec":{"s":[13,500,0,"内存剩"],"r":[0,1,12.898832684824903,361,1,1,12.898832684824903,362,2,1,12.898832684824903,363]}}
  #|{"textrec":{"s":[12,400,0,"共 16 GB"],"r":[0,1,11.918287937743191,364,1,1,3.375,-1,2,1,5.56640625,353,3,1,7.640625,365,4,1,3.375,-1,5,1,8.958984374999996,366,6,1,7.88671875,367]}}
  #|{"textrec":{"s":[28,600,0,"58.1"],"r":[0,1,17.471708297729492,368,1,1,17.90623426437378,369,2,1,6.170318126678467,358,3,1,12.899380683898926,343]}}
  #|{"textrec":{"s":[13,500,0,"磁盘剩"],"r":[0,1,12.898832684824903,370,1,1,12.898832684824903,371,2,1,12.898832684824903,363]}}
  #|{"textrec":{"s":[12,400,0,"共 228 GB"],"r":[0,1,11.918287937743191,364,1,1,3.375,-1,2,1,7.2421875,354,3,1,7.2421875,354,4,1,7.6640624999999964,372,5,1,3.375,-1,6,1,8.958984375,366,7,1,7.88671875,367]}}
  #|{"textrec":{"s":[13,400,0,"主机名"],"r":[0,1,12.898832684824903,373,1,1,12.898832684824903,374,2,1,12.898832684824903,375]}}
  #|{"textrec":{"s":[13,400,0,"3720-Mac-mini-1"],"r":[0,1,8.07421875,376,1,1,7.3251953125,377,2,1,7.76953125,378,3,1,8.1123046875,379,4,1,6.0556640625,318,5,1,11.2861328125,380,6,1,7.0966796875,12,7,1,7.1982421875,13,8,1,6.0556640625,318,9,1,11.2353515625,80,10,1,3.1357421875,77,11,1,7.50927734375,223,12,1,3.1357421875,77,13,1,6.0556640625,318,14,1,5.9541015625,381]}}
  #|{"textrec":{"s":[13,400,0,"芯片"],"r":[0,1,12.898832684824903,382,1,1,12.898832684824903,273]}}
  #|{"textrec":{"s":[13,400,0,"Apple M4 · 10 核 · arm64"],"r":[0,1,8.68359375,383,1,1,7.8583984375,11,2,1,7.8583984375,11,3,1,3.2119140625,76,4,1,7.3505859375,14,5,1,3.580078125,-1,6,1,11.2861328125,380,7,1,8.2900390625,384,8,1,3.580078125,-1,9,1,6.228545204222115,385,10,1,3.580078125,-1,11,1,5.9541015625,381,12,1,8.1123046875,379,13,1,3.580078125,-1,14,1,12.898832684824896,386,15,1,3.580078125,-1,16,1,6.228545204222115,385,17,1,3.580078125,-1,18,1,7.0966796875,12,19,1,4.9384765625,8,20,1,11.298828125,80,21,1,8.201171875,387,22,1,8.2900390625,384]}}
  #|{"textrec":{"s":[13,400,0,"已运行"],"r":[0,1,12.898832684824903,388,1,1,12.898832684824903,219,2,1,12.898832684824903,220]}}
  #|{"textrec":{"s":[13,400,0,"2 小时"],"r":[0,1,7.76953125,378,1,1,3.580078125,-1,2,1,12.898832684824903,389,3,1,12.898832684824903,153]}}
  #|{"textrec":{"s":[13,400,0,"still.fail"],"r":[0,1,6.69677734375,10,1,1,4.61474609375,82,2,1,3.1357421875,77,3,1,3.2119140625,76,4,1,3.2119140625,76,5,1,3.5927734375,81,6,1,4.341796875,317,7,1,7.00146484375,12,8,1,3.1357421875,77,9,1,3.2119140625,76]}}
  #|{"textrec":{"s":[13,400,0,"进程占用 135 MB"],"r":[0,1,12.898832684824903,224,1,1,12.898832684824903,225,2,1,12.898832684824903,390,3,1,12.898832684824903,391,4,1,3.580078125,-1,5,1,5.9541015625,381,6,1,8.07421875,376,7,1,7.9599609375,392,8,1,3.580078125,-1,9,1,11.2861328125,380,10,1,8.4677734375,393]}}
  #|{"textrec":{"g":323,"r":[1891,32,10,10,-1,-9,0]}}
  #|{"textrec":{"g":324,"r":[1902,32,9,10,-1,-7,0]}}
  #|{"textrec":{"g":325,"r":[1912,32,4,11,-1,-10,0]}}
  #|{"textrec":{"g":326,"r":[1917,32,8,9,-1,-7,0]}}
  #|{"textrec":{"g":327,"r":[1926,32,11,10,-1,-9,0]}}
  #|{"textrec":{"g":328,"r":[1938,32,9,10,-1,-9,0]}}
  #|{"textrec":{"g":329,"r":[1948,32,5,4,0,-6,0]}}
  #|{"textrec":{"g":330,"r":[1954,32,6,10,-1,-9,0]}}
  #|{"textrec":{"g":331,"r":[1961,32,9,11,-1,-9,0]}}
  #|{"textrec":{"g":332,"r":[1971,32,10,11,-1,-9,0]}}
  #|{"textrec":{"g":333,"r":[1982,32,9,10,-1,-9,0]}}
  #|{"textrec":{"g":334,"r":[1992,32,11,8,-1,-7,0]}}
  #|{"textrec":{"g":335,"r":[2004,32,8,9,-1,-7,0]}}
  #|{"textrec":{"g":336,"r":[2013,32,8,9,-1,-7,0]}}
  #|{"textrec":{"g":337,"r":[2022,32,10,11,-1,-9,0]}}
  #|{"textrec":{"g":338,"r":[2033,32,9,11,-1,-9,0]}}
  #|{"textrec":{"g":339,"r":[0,51,8,10,-1,-9,0]}}
  #|{"textrec":{"g":340,"r":[9,51,8,10,-1,-9,0]}}
  #|{"textrec":{"g":341,"r":[18,51,5,5,-1,-3,0]}}
  #|{"textrec":{"g":342,"r":[24,51,9,11,-1,-9,0]}}
  #|{"textrec":{"g":343,"r":[34,51,11,22,0,-21,0]}}
  #|{"textrec":{"g":344,"r":[46,51,18,24,0,-22,0]}}
  #|{"textrec":{"g":345,"r":[65,51,16,14,-1,-12,0]}}
  #|{"textrec":{"g":346,"r":[82,51,11,13,-1,-11,0]}}
  #|{"textrec":{"g":347,"r":[94,51,9,12,0,-11,0]}}
  #|{"textrec":{"g":348,"r":[104,51,10,13,0,-11,0]}}
  #|{"textrec":{"g":349,"r":[115,51,14,14,-1,-12,0]}}
  #|{"textrec":{"g":350,"r":[130,51,13,15,0,-12,0]}}
  #|{"textrec":{"g":351,"r":[144,51,13,14,-1,-11,0]}}
  #|{"textrec":{"g":352,"r":[158,51,14,14,-1,-11,0]}}
  #|{"textrec":{"g":353,"r":[173,51,7,11,-1,-10,0]}}
  #|{"textrec":{"g":354,"r":[181,51,9,11,-1,-10,0]}}
  #|{"textrec":{"g":355,"r":[191,51,4,5,0,-3,0]}}
  #|{"textrec":{"g":356,"r":[196,51,9,11,-1,-10,0]}}
  #|{"textrec":{"g":357,"r":[206,51,18,22,0,-21,0]}}
  #|{"textrec":{"g":358,"r":[225,51,7,7,0,-5,0]}}
  #|{"textrec":{"g":359,"r":[233,51,13,14,-1,-12,0]}}
  #|{"textrec":{"g":360,"r":[247,51,11,13,0,-12,0]}}
  #|{"textrec":{"g":361,"r":[259,51,13,15,0,-12,0]}}
  #|{"textrec":{"g":362,"r":[273,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":363,"r":[289,51,14,15,-1,-12,0]}}
  #|{"textrec":{"g":364,"r":[304,51,14,14,-1,-11,0]}}
  #|{"textrec":{"g":365,"r":[319,51,9,12,-1,-10,0]}}
  #|{"textrec":{"g":366,"r":[329,51,11,12,-1,-10,0]}}
  #|{"textrec":{"g":367,"r":[341,51,9,11,0,-10,0]}}
  #|{"textrec":{"g":368,"r":[351,51,18,23,0,-21,0]}}
  #|{"textrec":{"g":369,"r":[370,51,18,24,0,-22,0]}}
  #|{"textrec":{"g":370,"r":[389,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":371,"r":[405,51,15,14,-1,-12,0]}}
  #|{"textrec":{"g":372,"r":[421,51,9,12,-1,-10,0]}}
  #|{"textrec":{"g":373,"r":[431,51,14,14,-1,-12,0]}}
  #|{"textrec":{"g":374,"r":[446,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":375,"r":[462,51,14,15,-1,-12,0]}}
  #|{"textrec":{"g":376,"r":[477,51,10,13,-1,-11,0]}}
  #|{"textrec":{"g":377,"r":[488,51,9,12,-1,-11,0]}}
  #|{"textrec":{"g":378,"r":[498,51,9,12,-1,-11,0]}}
  #|{"textrec":{"g":379,"r":[508,51,10,13,-1,-11,0]}}
  #|{"textrec":{"g":380,"r":[519,51,12,12,0,-11,0]}}
  #|{"textrec":{"g":381,"r":[532,51,7,12,-1,-11,0]}}
  #|{"textrec":{"g":382,"r":[540,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":273,"r":[556,51,14,15,-1,-12,0]}}
  #|{"textrec":{"g":383,"r":[571,51,11,12,-1,-11,0]}}
  #|{"textrec":{"g":384,"r":[583,51,10,12,-1,-11,0]}}
  #|{"textrec":{"g":385,"r":[594,51,4,5,1,-7,0]}}
  #|{"textrec":{"g":386,"r":[599,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":387,"r":[615,51,10,13,-1,-11,0]}}
  #|{"textrec":{"g":388,"r":[626,51,13,13,0,-11,0]}}
  #|{"textrec":{"g":389,"r":[640,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":153,"r":[656,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":390,"r":[672,51,13,15,0,-12,0]}}
  #|{"textrec":{"g":391,"r":[686,51,14,14,-1,-11,0]}}
  #|{"textrec":{"g":392,"r":[701,51,10,13,-1,-11,0]}}
  #|{"textrec":{"g":393,"r":[712,51,9,12,0,-11,0]}}
  #|{"textrec":{"s":[15,400,0,"例如机器名：studio"],"r":[0,1,14.883268482490273,394,1,1,14.883268482490273,395,2,1,14.883268482490273,132,3,1,14.883268482490273,396,4,1,14.88326848249028,282,5,1,15.08754863813229,397,6,1,7.58056640625,91,7,1,5.17822265625,101,8,1,8.51806640625,163,9,1,8.9794921875,297,10,1,3.4716796875,102,11,1,8.6279296875,88]}}
  #|{"textrec":{"g":394,"r":[722,51,16,17,-1,-14,0]}}
  #|{"textrec":{"g":395,"r":[739,51,16,16,-1,-13,0]}}
  #|{"textrec":{"g":396,"r":[756,51,17,16,-1,-13,0]}}
  #|{"textrec":{"g":397,"r":[774,51,5,10,1,-10,0]}}
  #|{"textrec":{"s":[15,400,0,"e2e-not-082939"],"r":[0,1,8.3349609375,95,1,1,8.78173828125,304,2,1,8.29833984375,95,3,1,6.8408203125,305,4,1,8.51806640625,103,5,1,8.6279296875,88,6,1,5.068359375,101,7,1,6.6943359375,305,8,1,9.2138671875,164,9,1,9.345703125,398,10,1,8.818359375,304,11,1,9.31640625,399,12,1,9.169921875,302,13,1,9.31640625,399]}}
  #|{"textrec":{"g":398,"r":[780,51,11,14,-1,-12,0]}}
  #|{"textrec":{"g":399,"r":[792,51,11,14,-1,-12,0]}}
  #|{"textrec":{"s":[16,600,0,"连接"],"r":[0,1,15.875486381322958,400,1,1,15.875486381322958,401]}}
  #|{"textrec":{"s":[17,400,0,"studio"],"r":[0,1,8.42529296875,402,1,1,5.70263671875,213,2,1,9.48779296875,403,3,1,10.0107421875,404,4,1,3.7685546875,215,5,1,9.6123046875,216]}}
  #|{"textrec":{"s":[15,400,0,"此机器上暂无连接"],"r":[0,1,14.883268482490273,405,1,1,14.883268482490273,132,2,1,14.883268482490273,396,3,1,14.883268482490273,406,4,1,14.88326848249028,246,5,1,14.88326848249028,247,6,1,14.88326848249028,104,7,1,14.88326848249028,105]}}
  #|{"textrec":{"s":[16,600,0,"Profile"],"r":[0,1,10.239953994750977,407,1,1,6.225622177124023,408,2,1,9.327718734741211,34,3,1,5.944116592407227,409,4,1,4.046333312988281,185,5,1,4.159873962402344,410,6,1,9.127458572387695,46]}}
  #|{"textrec":{"s":[15,600,0,"API Key"],"r":[0,1,10.429658889770508,240,1,1,9.65855062007904,411,2,1,4.261693954467773,412,3,1,3.761730194091797,-1,4,1,9.82150912284851,413,5,1,8.214586973190308,85,6,1,8.328588008880615,414]}}
  #|{"textrec":{"s":[15,400,0,"cc"],"r":[0,1,8.1591796875,94,1,1,8.1591796875,94]}}
  #|{"textrec":{"s":[13,400,0,"无法检查 · 自定义环境变量 · 已启用 1 / 1 个模型"],"r":[0,1,12.898832684824903,415,1,1,12.898832684824903,416,2,1,12.898832684824903,417,3,1,12.898832684824903,418,4,1,3.580078125,-1,5,1,6.228545204222122,385,6,1,3.580078124999993,-1,7,1,12.898832684824896,419,8,1,12.898832684824896,420,9,1,12.898832684824896,421,10,1,12.898832684824896,422,11,1,12.898832684824896,423,12,1,12.898832684824896,424,13,1,12.898832684824896,425,14,1,3.580078125,-1,15,1,6.228545204222115,385,16,1,3.580078125,-1,17,1,12.898832684824896,388,18,1,12.898832684824896,426,19,1,12.898832684824896,391,20,1,3.580078125,-1,21,1,5.9541015625,381,22,1,3.580078125,-1,23,1,3.884765625,427,24,1,3.580078125,-1,25,1,5.9541015625,381,26,1,3.580078125,-1,27,1,12.898832684824896,428,28,1,12.898832684824924,429,29,1,12.898832684824924,430]}}
  #|{"textrec":{"g":400,"r":[804,51,17,17,-1,-14,0]}}
  #|{"textrec":{"g":401,"r":[822,51,17,17,-1,-14,0]}}
  #|{"textrec":{"g":402,"r":[840,51,11,13,-1,-11,0]}}
  #|{"textrec":{"g":403,"r":[852,51,10,12,0,-10,0]}}
  #|{"textrec":{"g":404,"r":[863,51,12,16,-1,-14,0]}}
  #|{"textrec":{"g":405,"r":[876,51,16,15,-1,-13,0]}}
  #|{"textrec":{"g":406,"r":[893,51,16,15,-1,-13,0]}}
  #|{"textrec":{"g":415,"r":[910,51,14,14,-1,-11,0]}}
  #|{"textrec":{"g":416,"r":[925,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":417,"r":[941,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":418,"r":[957,51,15,14,-1,-12,0]}}
  #|{"textrec":{"g":419,"r":[973,51,11,15,1,-12,0]}}
  #|{"textrec":{"g":420,"r":[985,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":421,"r":[1001,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":422,"r":[1017,51,15,14,-1,-11,0]}}
  #|{"textrec":{"g":423,"r":[1033,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":424,"r":[1049,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":425,"r":[1065,51,14,14,-1,-12,0]}}
  #|{"textrec":{"g":426,"r":[1080,51,14,15,-1,-12,0]}}
  #|{"textrec":{"g":427,"r":[1095,51,6,15,-1,-11,0]}}
  #|{"textrec":{"g":428,"r":[1102,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":429,"r":[1118,51,15,15,-1,-12,0]}}
  #|{"textrec":{"g":430,"r":[1134,51,14,14,-1,-12,0]}}
  #|{"textrec":{"ib":["d2b320ef40c51d36",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"g":411,"r":[1149,51,11,13,0,-12,0]}}
  #|{"textrec":{"g":412,"r":[1161,51,5,13,0,-12,0]}}
  #|{"textrec":{"g":413,"r":[1167,51,11,13,0,-12,0]}}
  #|{"textrec":{"g":414,"r":[1179,51,11,14,-1,-10,0]}}
  #|{"textrec":{"g":407,"r":[1191,51,11,14,0,-13,0]}}
  #|{"textrec":{"g":408,"r":[1203,51,8,11,0,-10,0]}}
  #|{"textrec":{"g":409,"r":[1212,51,8,14,-1,-13,0]}}
  #|{"textrec":{"g":410,"r":[1221,51,5,14,0,-13,0]}}
  #|{"textrec":{"g":46,"r":[1227,51,11,12,-1,-10,0]}}
