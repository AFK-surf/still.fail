// e2e/traces/places.trace, made by scripts/trace.py from 01-places.log: not edited by hand.

///|
/// What the app and its core said in the run, a line each.
pub let trace_places : String =
  #|{"env":{"MBUI_CLOUD":"http://127.0.0.1:18787","MBUI_CORE_ACCOUNT":"{\"sub\":\"alice\",\"email\":\"alice@example.test\",\"name\":\"Name of alice\",\"picture\":\"\",\"access\":\"-\",\"refresh\":\"-\",\"accessExpires\":1792593721}"}}
  #|{"out":{"id":1,"call":"client.device","params":{"client":"still.fail mbui","app":"desktop","userAgent":"Macintosh; Mac OS X"}},"w":1792593426853.674}
  #|{"in":{"id":1,"ok":null},"w":1792593427108.282}
  #|{"out":{"id":2,"subscribe":{"topic":"accounts"},"keyed":true},"w":1792593427108.331}
  #|{"out":{"id":3,"subscribe":{"topic":"prefs"},"keyed":true},"w":1792593427108.35}
  #|{"step":"# written by scripts/rerecord.sh from its test (src/sfreplay/emit.mbt): not edited by hand","w":1792593427111.215}
  #|{"step":"timeout 90000","w":1792593427111.227}
  #|{"step":"answered client.device","w":1792593427111.231}
  #|{"step":"answered client.focus","w":1792593427123.232}
  #|{"in":{"id":2,"value":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""}]},"w":1792593427289.024}
  #|{"in":{"id":3,"value":{"onlyMine":false,"onlyWatching":false,"onlyDecisions":false,"listFilter":{},"appearance":"system","rowPicture":"auto","absoluteTime":false,"lang":"zh","keys":{},"lastChat":{},"openChat":{},"chatTabs":{},"dropFiles":{},"driveViews":{},"resume":{},"stationUpdatesDismissed":{},"device":{"app":"desktop","phone":false,"handoff":false},"reader":{"size":18,"line":1.7,"margin":22,"face":"sans","indent":true,"paper":"follow"},"rails":{},"bars":{"sets":[["chats","files","profiles","stations"],["decisions","usage","connects","archive"]],"current":0},"barsBy":{},"fonts":{},"faces":{"ui":{"id":"","name":"","mono":false,"family":"","files":[],"bytes":0},"text":{"id":"","name":"","mono":false,"family":"","files":[],"bytes":0},"code":{"id":"","name":"","mono":true,"family":"","files":[],"bytes":0},"list":[{"id":"inter","name":"Inter","mono":false,"family":"SF Inter","css":"http://127.0.0.1:18787/releases/fonts/inter/4.001/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/inter/4.001/var.ttf.gz","bytes":457818,"sha256":"29160a80ff49ddcab2c97711247e08b1fab27a484a329ce8b813d820dc559031"}],"preview":"http://127.0.0.1:18787/releases/fonts/inter/4.001/preview-194fa287.ttf","bytes":457818},{"id":"noto-sans-sc","name":"思源黑体","mono":false,"family":"SF Noto Sans SC","css":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/var.ttf.gz","bytes":11276563,"sha256":"a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da"}],"preview":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/preview-f0494178.ttf","bytes":11276563},{"id":"noto-serif-sc","name":"思源宋体","mono":false,"family":"SF Noto Serif SC","css":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/var.ttf.gz","bytes":15454579,"sha256":"050080d9255a86808f2945bffac582b31ef32bc36411ce29563b4961670c66f9"}],"preview":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/preview-001bbedf.ttf","bytes":15454579},{"id":"lxgw-wenkai","name":"霞鹜文楷","mono":false,"family":"SF LXGW WenKai","css":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/font.css","files":[{"weight":400,"url":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/400.ttf.gz","bytes":12904482,"sha256":"2d73eea94ad808999d90c0000c239a84a33b09d4bc6ab6c5b8bbf1eda8a7fc8b"},{"weight":500,"url":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/500.ttf.gz","bytes":13272430,"sha256":"f4b8a34d1f838fe411540cb7c97b1c384ac9738a876c4104500bc42508b2312a"}],"preview":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/preview-d3505af4.ttf","bytes":26176912},{"id":"jetbrains-mono","name":"JetBrains Mono","mono":true,"family":"SF JetBrains Mono","css":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/var.ttf.gz","bytes":90579,"sha256":"48715a42ec242c21e9f02692891e147d022299a52e48d5e413e1a942193ffeda"}],"preview":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/preview-ee73078f.ttf","bytes":90579},{"id":"fira-code","name":"Fira Code","mono":true,"family":"SF Fira Code","css":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/var.ttf.gz","bytes":137151,"sha256":"9335b082b3c7850d98a64b584f3417f65355f3471278bb5eeb8c6c0e8657aeeb"}],"preview":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/preview-555be27a.ttf","bytes":137151},{"id":"maple-mono","name":"Maple Mono","mono":true,"family":"SF Maple Mono CN","css":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/font.css","files":[{"weight":400,"url":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/400.ttf.gz","bytes":8352545,"sha256":"0fcc5139bfd5ab14ff989bb7dfd5236d0cafc10e60b9828569e6883613ab4085"},{"weight":600,"url":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/600.ttf.gz","bytes":8438132,"sha256":"96ed7ae26ee7c50b02b2d2b2bc0f1a0cbabe45ae5d6e6abf6678e2177c415677"}],"preview":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/preview-cffdf246.ttf","bytes":16790677}]}}},"w":1792593427289.108}
  #|{"out":{"id":4,"subscribe":{"topic":"workspaces"},"keyed":true},"w":1792593427289.2}
  #|{"out":{"id":5,"subscribe":{"topic":"status"},"keyed":true},"w":1792593427289.222}
  #|{"in":{"id":4,"value":[{"account":{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""},"workspaces":[{"id":"01M5FE9JEJ89HAAYVTYW4VZAMA","name":"Dev","role":"owner","created_at":1792593414,"stations":1,"members":1,"relays":[],"time":{"created_at":{"past":true,"at":1792593414000,"ago":"刚刚","full":"10/21 22:36:54","until":"1 分钟内"}}}],"invitations":[],"relay_url":"http://127.0.0.1:18740","loaded":true,"beta":true}]},"w":1792593427305.688}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792593427305.725}
  #|{"out":{"id":6,"subscribe":{"topic":"lock","workspace":"01M5FE9JEJ89HAAYVTYW4VZAMA"},"keyed":true},"w":1792593427305.797}
  #|{"out":{"id":7,"subscribe":{"topic":"chats","scope":"01M5FE9JEJ89HAAYVTYW4VZAMA","mine":false},"keyed":true},"w":1792593427305.829}
  #|{"out":{"id":8,"subscribe":{"topic":"changelog"},"keyed":true},"w":1792593427305.844}
  #|{"out":{"id":9,"subscribe":{"topic":"workspaceMarks","workspace":"01M5FE9JEJ89HAAYVTYW4VZAMA"},"keyed":true},"w":1792593427306.045}
  #|{"out":{"id":10,"subscribe":{"topic":"status","workspace":"01M5FE9JEJ89HAAYVTYW4VZAMA"},"keyed":true},"w":1792593427306.094}
  #|{"out":{"id":11,"subscribe":{"topic":"lockPrompts"},"keyed":true},"w":1792593427313.738}
  #|{"out":{"id":12,"call":"client.focus","params":{"visible":true,"focused":true,"workspace":"01M5FE9JEJ89HAAYVTYW4VZAMA"}},"w":1792593427474.433}
  #|{"out":{"id":13,"subscribe":{"topic":"notify"},"keyed":true},"w":1792593427474.517}
  #|{"out":{"id":14,"subscribe":{"topic":"notify","workspace":"01M5FE9JEJ89HAAYVTYW4VZAMA"},"keyed":true},"w":1792593427474.542}
  #|{"in":{"id":12,"ok":null},"w":1792593427599.876}
  #|{"in":{"id":6,"value":{"available":true,"locked":false,"notice":true,"role":"owner","manages":true,"owner":true,"canSign":true,"signs":false,"me":{"device":"06d5e9c7c36cbd263c8859c64d02f508b2bf036c38223c4107fa0bdcff77a16f","code":"WNF-78L","kind":"app","confirmed":false,"waiting":false,"asked":false},"signers":0,"members":[],"stations":[{"id":"37e9fed9a0ddebe868bf7a66bfdcd9f5c3c7afa3aae8041a40e7c08ca9cf3c0f","name":"studio","version":"0.1.0","online":true,"protected":false}],"protected":0,"requests":[],"renew":[],"attention":0}},"w":1792593427599.922}
  #|{"in":{"id":7,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"stations":[{"station":"01M5FE9JEJ89HAAYVTYW4VZAMA/37e9fed9a0ddebe868bf7a66bfdcd9f5c3c7afa3aae8041a40e7c08ca9cf3c0f","id":"37e9fed9a0ddebe868bf7a66bfdcd9f5c3c7afa3aae8041a40e7c08ca9cf3c0f","name":"studio","state":"online"}],"loading":false,"days":[{"daysAgo":0,"at":1792593421611,"label":"今天","items":[{"id":"ember:c-e2fbcd1fcc","session":"ember:c-e2fbcd1fcc","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","agents":[{"key":"ember:c-e2fbcd1fcc","runtime":"claude","process":"warm","pending":0,"lastTurn":{"id":"7c117343-f110-4e53-b9d3-331c5e970ecc","kind":"input","outcome":"completed","declared":"final","ending":"all_done","need":"answered the question that was asked","startedAt":1792593421174,"endedAt":1792593421615},"agentText":"默认模型","statusText":"已完成：answered the question that was asked"}],"last":{"seq":2,"authorKind":"agent","author":"ember:c-e2fbcd1fcc","text":"你好，我是测试用的 agent","createdAt":1792593421611,"by":{"kind":"agent","name":"agent","mine":false,"runtime":"claude","label":"agent"},"preview":"你好，我是测试用的 agent","time":{"createdAt":{"at":1792593421611,"ago":"刚刚","full":"10/21 22:37:01","until":"1 分钟内","past":true}}},"unread":true,"mine":true,"lastActiveAt":1792593421611,"station":"01M5FE9JEJ89HAAYVTYW4VZAMA/37e9fed9a0ddebe868bf7a66bfdcd9f5c3c7afa3aae8041a40e7c08ca9cf3c0f","stationName":"studio","time":{"lastActiveAt":{"at":1792593421611,"ago":"刚刚","full":"10/21 22:37:01","until":"1 分钟内","past":true}},"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"peopleText":"你 发起","clientKey":"new:chat-6ef9720be577e37b39","pinned":false,"tone":"done"}]}],"trouble":null,"members":1,"leading":"agents","glyph":{"online":1,"dim":0,"connecting":0,"failing":0,"working":0,"summary":"studio","label":"1 台 station，1 台在线"},"note":{"reading":false,"text":null,"failing":[],"empty":false}}},"w":1792593427599.999}
  #|{"in":{"id":8,"value":{"app":"desktop","tabs":[{"part":"desktop","label":"桌面","days":[]},{"part":"web","label":"网页","days":[]},{"part":"android","label":"安卓","days":[]},{"part":"station","label":"Station","days":[]},{"part":"cloud","label":"云端","days":[]}],"loading":false}},"w":1792593427600.039}
  #|{"in":{"id":9,"value":{"workspaces":{"01M5FE9JEJ89HAAYVTYW4VZAMA":{"alert":0,"unread":1,"tone":"done","label":"1 个有新消息","badge":0,"items":[],"mineTone":"done"}},"badge":0,"badgeCounts":"attention","badgeKinds":{"on":true,"wait":true,"failed":true,"done":false,"message":false}}},"w":1792593427600.055}
  #|{"in":{"id":10,"value":{"items":[]}},"w":1792593427600.064}
  #|{"in":{"id":11,"value":{"pairing":[]}},"w":1792593427600.151}
  #|{"in":{"id":13,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792593427600.305}
  #|{"in":{"id":14,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792593427600.321}
  #|{"out":{"id":15,"subscribe":{"topic":"longJobs","scope":"01M5FE9JEJ89HAAYVTYW4VZAMA"},"keyed":true},"w":1792593427600.732}
  #|{"out":{"id":16,"call":"notify.permission","params":{"state":"unknown"}},"w":1792593427628.268}
  #|{"in":{"id":15,"value":{"groups":[]}},"w":1792593427640.826}
  #|{"in":{"id":16,"ok":null},"w":1792593427640.838}
  #|{"step":"answered notify.permission","w":1792593427644.631}
  #|{"step":"until 端到端测试","w":1792593427656.213}
  #|{"step":"tap icon:folder","w":1792593427656.222}
  #|{"step":"tap icon:folder","acted":true,"w":1792593427656.241}
  #|{"out":{"id":17,"subscribe":{"topic":"stations","scope":"01M5FE9JEJ89HAAYVTYW4VZAMA"},"keyed":true},"w":1792593427672.653}
  #|{"out":{"id":18,"subscribe":{"topic":"workspace","workspace":"01M5FE9JEJ89HAAYVTYW4VZAMA"},"keyed":true},"w":1792593427672.68}
  #|{"step":"wait 220","w":1792593427673.49}
  #|{"in":{"id":17,"value":[{"station":"01M5FE9JEJ89HAAYVTYW4VZAMA/37e9fed9a0ddebe868bf7a66bfdcd9f5c3c7afa3aae8041a40e7c08ca9cf3c0f","id":"37e9fed9a0ddebe868bf7a66bfdcd9f5c3c7afa3aae8041a40e7c08ca9cf3c0f","name":"studio","summary":"正在连接","face":"idle","line":"在线","online":true,"reconnecting":false,"lastSeen":1792593419,"version":"0.1.0","link":{"state":"online"},"runtimes":[{"runtime":"claude","models":["claude-sonnet-5-5"]}],"models":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792593421047,"time":{"checkedAt":{"at":1792593421047,"ago":"刚刚","full":"10/21 22:37:01","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"overview":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null,"summaryText":"最近 7 天检查了 0 个 chat","changeText":null}},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","email":"alice@example.test","name":"Name of alice","sub":"alice","role":"owner","workspace":"01M5FE9JEJ89HAAYVTYW4VZAMA","device":"06d5e9c7c36cbd263c8859c64d02f508b2bf036c38223c4107fa0bdcff77a16f"},"connects":[],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792593419322,"time":{"checkedAt":{"at":1792593419322,"ago":"刚刚","full":"10/21 22:36:59","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792593421047,"time":{"checkedAt":{"at":1792593421047,"ago":"刚刚","full":"10/21 22:37:01","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"modelsReading":false,"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]}],"processes":[],"counts":{"sessions":1,"running":0,"warm":1},"mesh":{"state":"running","origin":"http://127.0.0.1:18787","station":"37e9fed9a0ddebe868bf7a66bfdcd9f5c3c7afa3aae8041a40e7c08ca9cf3c0f","workspace":"Dev","workspaceId":"01M5FE9JEJ89HAAYVTYW4VZAMA","name":"studio"},"slackUsers":[],"slackTeams":[],"slackApps":[],"feishuRegistrations":[],"disk":{"freeBytes":29137027072,"totalBytes":245107195904},"logins":[],"machineLogins":[],"sharing":true,"consoleSignIn":true,"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"google","name":"Google Gemini","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xai","name":"xAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"mistral","name":"Mistral","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"deepseek","name":"DeepSeek","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen","name":"Qwen","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai","name":"Kimi","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai","name":"Z.ai","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax","name":"MiniMax","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ant-ling","name":"Ant Ling","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"jev","name":"Jev","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen-cn","name":"Qwen (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"openrouter","name":"OpenRouter","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"opencode","name":"OpenCode Zen","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"groq","name":"Groq","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"together","name":"Together AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"fireworks","name":"Fireworks","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cerebras","name":"Cerebras","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"huggingface","name":"Hugging Face","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"nvidia","name":"NVIDIA","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"baseten","name":"Baseten","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ollama","name":"Ollama","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"custom","name":"Custom","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""}],"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792593417806},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.306","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792593417806},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-lockp/apps/e2e-local/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792593417806},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-lockp/apps/e2e-local/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792593417806},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","latest":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-lockp/apps/e2e-local/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792593417806},{"id":"cursor","name":"Cursor","installed":false,"latest":"1.0.40","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792593417806},{"id":"devin","name":"Devin","installed":true,"version":"3000.11.92","latest":"3000.11.92","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-lockp/apps/e2e-local/ember/station/test/fake/devin，不是用 Devin 的安装脚本装的，需在该机器上手动更新","state":"idle","checkedAt":1792593417806}],"processesText":"没有运行中的 agent 进程","agentEnv":[],"drive":{"roots":[],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false}},"betaOffered":false,"way":{"path":"直连","via":"direct"},"time":{"lastSeen":{"at":1792593419000,"ago":"刚刚","full":"10/21 22:36:59","until":"1 分钟内","past":true}},"joined":false}]},"w":1792593427689.204}
  #|{"in":{"id":18,"value":{"id":"01M5FE9JEJ89HAAYVTYW4VZAMA","name":"Dev","role":"owner","created_at":1792593414,"members":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":"https://example.test/p.png","role":"owner","added_at":1792593414}],"stations":[{"id":"37e9fed9a0ddebe868bf7a66bfdcd9f5c3c7afa3aae8041a40e7c08ca9cf3c0f","name":"studio","emoji":null,"icon":null,"enrolled_at":1792593415,"enrolled_by":"alice","last_seen":1792593419,"version":"0.1.0","time":{"last_seen":{"past":true,"at":1792593419000,"ago":"刚刚","full":"10/21 22:36:59","until":"1 分钟内"}}}],"invitations":[],"added":[],"relays":[],"lock":null,"lock_requests":0,"time":{"created_at":{"past":true,"at":1792593414000,"ago":"刚刚","full":"10/21 22:36:54","until":"1 分钟内"}}}},"w":1792593427689.407}
  #|{"in":{"id":17,"delta":[{"path":[0,"host"],"set":{"hostname":"3720-Mac-mini-1","os":"macOS 27.0.1","arch":"arm64","cpus":10,"cpuModel":"Apple M4","load":1.43,"cpuBusy":0.93,"uptimeSec":72789,"memory":{"totalBytes":17179869184,"usedBytes":12538757120,"swapUsedBytes":250347520},"disk":{"path":"/tmp/mbe2e-C/data","totalBytes":245107195904,"freeBytes":29136924672},"emberRssBytes":159938576,"checkedAt":1792593427752,"summary":"10 核 · 16 GB","line":"macOS 27.0.1 · 10 核 · 16 GB · 已运行 0 天","facts":["3720-Mac-mini-1","macOS 27.0.1","arm64 · 10 核","已运行 20 小时"],"meters":[{"label":"CPU","short":"CPU","percent":93,"left":7,"level":"red","value":"93%","remaining":"空闲 7%","big":"7","unit":"%","title":"CPU 空闲","total":"负载 14.3","note":"负载 14.3 · Apple M4"},{"label":"内存","short":"内存","percent":73,"left":27,"level":"ok","value":"11.7 GB / 16.0 GB","remaining":"剩 4.3 G","big":"4.3","unit":"GB","title":"内存剩","total":"共 16 GB","note":"swap 0.2 GB"},{"label":"磁盘","short":"磁盘","percent":88,"left":12,"level":"amber","value":"剩余 27.1 GB / 228 GB","remaining":"剩 27.1 G","big":"27.1","unit":"GB","title":"磁盘剩","total":"共 228 GB"}],"identity":"Apple M4 · 16 GB · macOS 27.0.1","details":[{"label":"主机名","value":"3720-Mac-mini-1"},{"label":"芯片","value":"Apple M4 · 10 核 · arm64"},{"label":"已运行","value":"20 小时"},{"label":"still.fail","value":"进程占用 153 MB"}],"usage":"内存 11.7 GB / 16.0 GB · 磁盘 剩余 27.1 GB / 228 GB","emberText":"still.fail 153 MB"}},{"path":[0,"line"],"set":"Apple M4"},{"path":[0,"summary"],"set":"空闲 · Apple M4 · 16 GB · macOS 27.0.1"}]},"w":1792593427772.382}
  #|{"step":"now until =文件","w":1792593427906.263}
  #|{"step":"gone 端到端测试","w":1792593427906.282}
  #|{"step":"tap icon:chats","w":1792593427906.288}
  #|{"step":"tap icon:chats","acted":true,"w":1792593427906.305}
  #|{"step":"wait 220","w":1792593427923.202}
  #|{"step":"now until 端到端测试","w":1792593428156.229}
  #|{"step":"dragon 0 -64 960 icon:chats","w":1792593428156.24}
  #|{"step":"dragon 0 -64 960 icon:chats","acted":true,"w":1792593428156.295}
  #|{"out":{"id":19,"call":"prefs.set","params":{"barsBy":{"01M5FE9JEJ89HAAYVTYW4VZAMA":{"sets":[["chats","files","profiles","stations"],["decisions","usage","connects","archive"]],"current":1}}}},"w":1792593429179.366}
  #|{"out":{"id":20,"subscribe":{"topic":"decisions","workspace":"01M5FE9JEJ89HAAYVTYW4VZAMA"},"keyed":true},"w":1792593429189.895}
  #|{"step":"answered prefs.set","w":1792593429191.441}
  #|{"in":{"id":19,"ok":null},"w":1792593429215.86}
  #|{"in":{"id":3,"delta":[{"path":["barsBy","01M5FE9JEJ89HAAYVTYW4VZAMA"],"set":{"sets":[["chats","files","profiles","stations"],["decisions","usage","connects","archive"]],"current":1}}]},"w":1792593429215.874}
  #|{"in":{"id":20,"value":{"items":[],"count":0,"wait":{"reading":false,"text":null,"failing":[],"empty":true},"answered":[],"working":[],"today":{"count":0,"working":0}}},"w":1792593429215.884}
  #|{"step":"wait 180","w":1792593429318.257}
  #|{"step":"now until =奏","w":1792593429472.752}
  #|{"step":"tap icon:chart","w":1792593429472.764}
  #|{"step":"tap icon:chart","acted":true,"w":1792593429472.777}
  #|{"out":{"id":21,"subscribe":{"topic":"usage","scope":"01M5FE9JEJ89HAAYVTYW4VZAMA","days":7},"keyed":true},"w":1792593429489.801}
  #|{"step":"wait 220","w":1792593429497.298}
  #|{"in":{"id":21,"value":{"days":7,"wait":{"reading":true,"text":"正在从 studio 读取","failing":[],"empty":false},"empty":true,"tiles":[{"label":"折合费用","value":"$0","sub":"按 API 标准单价估算"},{"label":"模型调用","value":"0 次","sub":"日均 0 次"},{"label":"输入 token","value":"0","sub":"缓存命中 0%"},{"label":"输出 token","value":"0","sub":"平均每次 0"}],"series":[],"daily":[{"day":"2026-10-15","label":"10/15","today":false,"cost":0,"costText":"$0","calls":0,"callsText":"0 次调用","parts":[],"partsText":[]},{"day":"2026-10-16","label":"10/16","today":false,"cost":0,"costText":"$0","calls":0,"callsText":"0 次调用","parts":[],"partsText":[]},{"day":"2026-10-17","label":"10/17","today":false,"cost":0,"costText":"$0","calls":0,"callsText":"0 次调用","parts":[],"partsText":[]},{"day":"2026-10-18","label":"10/18","today":false,"cost":0,"costText":"$0","calls":0,"callsText":"0 次调用","parts":[],"partsText":[]},{"day":"2026-10-19","label":"10/19","today":false,"cost":0,"costText":"$0","calls":0,"callsText":"0 次调用","parts":[],"partsText":[]},{"day":"2026-10-20","label":"10/20","today":false,"cost":0,"costText":"$0","calls":0,"callsText":"0 次调用","parts":[],"partsText":[]},{"day":"2026-10-21","label":"10/21","today":true,"cost":0,"costText":"$0","calls":0,"callsText":"0 次调用","parts":[],"partsText":[]}],"max":0,"lists":[{"key":"people","title":"按人","items":[]},{"key":"chats","title":"按对话","items":[]},{"key":"profiles","title":"按账号","items":[]},{"key":"models","title":"按模型","items":[]}],"notes":[],"basis":"订阅账号不按 token 收费；费用按 API 标准单价估算，不含长上下文和服务等级等加价","prices":[{"station":"studio","note":"station 尚未提供价目表，请更新 station 后查看","rows":[]}]}},"w":1792593429528.387}
  #|{"in":{"id":21,"delta":[{"path":["prices",0,"note"],"set":"美元 / 100 万 token · 各类 token × 单价后相加；Claude fast ×2。GPT 按标准短上下文估算，仅记录输入、缓存读取和输出。GPT 价目核对于 2026-10-02，Claude 沿用 2026-09 价目"},{"path":["wait","empty"],"set":true},{"path":["wait","reading"],"set":false},{"path":["wait","text"],"set":null}]},"w":1792593429666.694}
  #|{"step":"now until =用量","w":1792593429726.642}
  #|{"step":"dragon 0 -64 960 icon:zou","w":1792593429726.661}
  #|{"step":"dragon 0 -64 960 icon:zou","acted":true,"w":1792593429726.675}
  #|{"out":{"id":22,"call":"prefs.set","params":{"barsBy":{"01M5FE9JEJ89HAAYVTYW4VZAMA":{"sets":[["chats","files","profiles","stations"],["decisions","usage","connects","archive"]],"current":0}}}},"w":1792593430749.146}
  #|{"step":"answered prefs.set","w":1792593430750.275}
  #|{"in":{"id":22,"ok":null},"w":1792593430772.383}
  #|{"step":"wait 180","w":1792593430837.569}
  #|{"in":{"id":3,"delta":[{"path":["barsBy","01M5FE9JEJ89HAAYVTYW4VZAMA","current"],"set":0}]},"w":1792593430928.101}
  #|{"step":"now until 端到端测试","w":1792593431026.153}
  #|{"step":"wait 1173","w":1792593431026.183}
  #|{"step":"","w":1792593432223.025}
  #|{"textrec":{"ib":["bfd9b0d6dc602826",12668,64],"r":[56,56,56,56]}}
  #|{"textrec":{"s":[13,400,0,"正在读取你的 workspace"],"r":[0,1,12.898832684824903,0,1,1,12.898832684824903,1,2,1,12.898832684824903,2,3,1,12.898832684824903,3,4,1,12.898832684824896,4,5,1,12.898832684824896,5,6,1,3.580078125,-1,7,1,9.8642578125,6,8,1,7.4775390625,7,9,1,4.875,8,10,1,6.85546875,9,11,1,6.6015625,10,12,1,7.8583984375,11,13,1,7.0966796875,12,14,1,7.1982421875,13,15,1,7.3505859375,14]}}
  #|{"textrec":{"m":[13,400,0],"r":[12.568359375,2.7421875,18,12.568359375,2.7421875,0]}}
  #|{"textrec":{"s":[24,700,0,"Dev"],"r":[0,1,17.075823068618774,15,1,1,13.365240812301636,16,2,1,12.759063005447388,17]}}
  #|{"textrec":{"m":[24,700,0],"r":[23.203125,5.0625,34,20.638916015625,3.361083984375,0]}}
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
  #|{"textrec":{"m":[15,400,0],"r":[14.501953125,3.1640625,21,14.501953125,3.1640625,0]}}
  #|{"textrec":{"s":[15,600,0,"今天"],"r":[0,1,14.883268482490273,24,1,1,14.883268482490273,25]}}
  #|{"textrec":{"m":[15,600,0],"r":[14.501953125,3.1640625,21,14.501953125,3.1640625,0]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 post:你好，我是测试用的 agent"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,26,3,1,15.875486381322958,28,4,1,15.875486381322958,29,5,1,15.875486381322958,30,6,1,15.875486381322958,31,7,1,15.875486381322958,32,8,1,3.95001220703125,-1,9,1,9.824199676513672,33,10,1,9.432537078857422,34,11,1,8.471200942993164,35,12,1,5.973020553588867,36,13,1,4.952056884765625,37,14,1,15.875486381322958,38,15,1,15.875486381322958,39,16,1,16.09338521400778,40,17,1,15.875486381322958,41,18,1,15.875486381322958,42,19,1,15.87548638132293,28,20,1,15.875486381322958,29,21,1,15.875486381322958,43,22,1,15.875486381322958,30,23,1,3.95001220703125,-1,24,1,8.899068832397461,44,25,1,9.801153182983398,45,26,1,9.127458572387695,46,27,1,9.466253280639648,47,28,1,5.999713897705078,36]}}
  #|{"textrec":{"m":[16,600,0],"r":[15.46875,3.375,23,15.46875,3.375,0]}}
  #|{"textrec":{"s":[14,400,0,"你好，我是测试用的 agent"],"r":[0,1,13.891050583657588,48,1,1,13.891050583657588,49,2,1,14.081712062256813,50,3,1,13.891050583657588,51,4,1,13.891050583657588,52,5,1,13.891050583657588,53,6,1,13.891050583657588,54,7,1,13.891050583657588,55,8,1,13.891050583657588,56,9,1,3.787109375000014,-1,10,1,7.57421875,57,11,1,8.380859375,58,12,1,7.84765625,59,13,1,8.0185546875,60,14,1,4.935546875,61]}}
  #|{"textrec":{"m":[14,400,0],"r":[13.53515625,2.953125,20,13.53515625,2.953125,0]}}
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
  #|{"textrec":{"s":[24,700,0,"文件"],"r":[0,1,22.849624060150376,63,1,1,22.849624060150376,64]}}
  #|{"textrec":{"s":[15,600,0,"studio"],"r":[0,1,8.000344634056091,65,1,1,5.658300518989563,66,2,1,8.93320620059967,67,3,1,9.332013130187988,68,4,1,3.8520312309265137,69,5,1,8.901597261428833,70]}}
  #|{"textrec":{"s":[16,400,0,"主目录"],"r":[0,1,15.875486381322958,71,1,1,15.875486381322958,72,2,1,15.875486381322958,73]}}
  #|{"textrec":{"m":[16,400,0],"r":[15.46875,3.375,23,15.46875,3.375,0]}}
  #|{"textrec":{"g":65,"r":[666,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":66,"r":[677,0,8,13,-1,-11,0]}}
  #|{"textrec":{"g":67,"r":[686,0,10,12,0,-10,0]}}
  #|{"textrec":{"g":68,"r":[697,0,11,15,-1,-13,0]}}
  #|{"textrec":{"g":69,"r":[709,0,6,14,-1,-13,0]}}
  #|{"textrec":{"g":70,"r":[716,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":71,"r":[728,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":72,"r":[746,0,14,16,1,-13,0]}}
  #|{"textrec":{"g":73,"r":[761,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":63,"r":[779,0,24,24,-1,-20,0]}}
  #|{"textrec":{"g":64,"r":[804,0,24,24,-1,-20,0]}}
  #|{"textrec":{"ib":["4165e1c325ff4b32",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"ib":["e8253a4a9ea8c5de",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["6727d74824d9e7b3",3698,64],"r":[30,30,30,30]}}
  #|{"textrec":{"ib":["504a4df6beac534a",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["97b77fa0f0dd96d2",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["12cc7192b4afc345",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["c47579b7fc0c87b0",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["c93f780c0dd4d77c",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"s":[24,700,0,"奏"],"r":[0,1,22.849624060150376,74]}}
  #|{"textrec":{"ib":["59350c7ca2fa3439",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"s":[17,600,0,"奏折已全部批完"],"r":[0,1,16.851167315175097,75,1,1,16.851167315175097,76,2,1,16.851167315175097,77,3,1,16.851167315175097,78,4,1,16.851167315175104,79,5,1,16.851167315175104,80,6,1,16.851167315175104,81]}}
  #|{"textrec":{"m":[17,600,0],"r":[16.435546875,3.5859375,24,16.435546875,3.5859375,0]}}
  #|{"textrec":{"s":[14,400,0,"新的奏折会显示在这里"],"r":[0,1,13.891050583657588,82,1,1,13.891050583657588,56,2,1,13.891050583657588,83,3,1,13.891050583657588,84,4,1,13.891050583657588,85,5,1,13.891050583657588,86,6,1,13.891050583657588,87,7,1,13.891050583657588,88,8,1,13.891050583657588,89,9,1,13.891050583657588,90]}}
  #|{"textrec":{"s":[20,600,0,"0"],"r":[0,1,12.71425393410027,91]}}
  #|{"textrec":{"m":[20,600,0],"r":[19.3359375,4.21875,28,17.1990966796875,2.8009033203125,0]}}
  #|{"textrec":{"s":[12,400,0,"今日已批"],"r":[0,1,11.918287937743191,92,1,1,11.918287937743191,93,2,1,11.918287937743195,94,3,1,11.918287937743187,95]}}
  #|{"textrec":{"m":[12,400,0],"r":[11.6015625,2.53125,17,11.6015625,2.53125,0]}}
  #|{"textrec":{"s":[12,400,0,"办理中"],"r":[0,1,11.918287937743191,96,1,1,11.918287937743191,97,2,1,11.918287937743195,98]}}
  #|{"textrec":{"g":74,"r":[829,0,24,24,-1,-20,0]}}
  #|{"textrec":{"g":75,"r":[854,0,18,18,-1,-15,0]}}
  #|{"textrec":{"g":76,"r":[873,0,18,18,-1,-15,0]}}
  #|{"textrec":{"g":77,"r":[892,0,17,17,0,-14,0]}}
  #|{"textrec":{"g":78,"r":[910,0,19,18,-1,-15,0]}}
  #|{"textrec":{"g":79,"r":[930,0,18,18,-1,-15,0]}}
  #|{"textrec":{"g":80,"r":[949,0,18,18,-1,-15,0]}}
  #|{"textrec":{"g":81,"r":[968,0,18,18,-1,-15,0]}}
  #|{"textrec":{"g":82,"r":[987,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":83,"r":[1004,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":84,"r":[1021,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":85,"r":[1037,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":86,"r":[1054,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":87,"r":[1070,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":88,"r":[1086,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":89,"r":[1102,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":90,"r":[1119,0,15,14,-1,-12,0]}}
  #|{"textrec":{"g":91,"r":[1135,0,13,18,0,-16,0]}}
  #|{"textrec":{"g":92,"r":[1149,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":93,"r":[1164,0,10,14,1,-11,0]}}
  #|{"textrec":{"g":94,"r":[1175,0,13,12,0,-10,0]}}
  #|{"textrec":{"g":95,"r":[1189,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":96,"r":[1204,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":97,"r":[1219,0,14,13,-1,-11,0]}}
  #|{"textrec":{"g":98,"r":[1234,0,12,14,0,-11,0]}}
  #|{"textrec":{"ib":["cfb613d15c0b52af",20876,128],"r":[72,72,72,72]}}
  #|{"textrec":{"s":[24,700,0,"用量"],"r":[0,1,22.849624060150376,99,1,1,22.849624060150376,100]}}
  #|{"textrec":{"s":[13,400,0,"7 天"],"r":[0,1,7.3251953125,101,1,1,3.580078125,-1,2,1,12.898832684824903,102]}}
  #|{"textrec":{"s":[13,400,0,"30 天"],"r":[0,1,8.07421875,103,1,1,8.1123046875,104,2,1,3.580078125,-1,3,1,12.898832684824903,102]}}
  #|{"textrec":{"ib":["5102d8899b34cdaf",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"s":[12,400,0,"折合费用"],"r":[0,1,11.918287937743191,105,1,1,11.918287937743191,106,2,1,11.918287937743195,107,3,1,11.918287937743187,108]}}
  #|{"textrec":{"s":[22,700,0,"$0"],"r":[0,1,14.22948682308197,109,1,1,14.468548357486725,110]}}
  #|{"textrec":{"m":[22,700,0],"r":[21.26953125,4.640625,31,18.91900634765625,3.08099365234375,0]}}
  #|{"textrec":{"s":[12,400,0,"查看价目表 →"],"r":[0,1,11.918287937743191,111,1,1,11.918287937743191,112,2,1,11.918287937743195,113,3,1,11.918287937743187,114,4,1,11.918287937743187,115,5,1,3.375,-1,6,1,10.869140625,116]}}
  #|{"textrec":{"s":[12,400,0,"模型调用"],"r":[0,1,11.918287937743191,117,1,1,11.918287937743191,118,2,1,11.918287937743195,119,3,1,11.918287937743187,108]}}
  #|{"textrec":{"s":[22,700,0,"0 次"],"r":[0,1,14.468548357486725,110,1,1,4.717369616031647,-1,2,1,20.94548872180451,120]}}
  #|{"textrec":{"s":[12,400,0,"日均 0 次"],"r":[0,1,11.918287937743191,93,1,1,11.918287937743191,121,2,1,3.375,-1,3,1,7.55859375,122,4,1,3.375,-1,5,1,11.918287937743195,123]}}
  #|{"textrec":{"s":[12,400,0,"输入 token"],"r":[0,1,11.918287937743191,124,1,1,11.918287937743191,125,2,1,3.375,-1,3,1,4.3154296875,126,4,1,7.0458984375,127,5,1,6.369140625,128,6,1,6.708984375,129,7,1,7.001953125,130]}}
  #|{"textrec":{"s":[22,700,0,"0"],"r":[0,1,14.468548357486725,110]}}
  #|{"textrec":{"s":[12,400,0,"缓存命中 0%"],"r":[0,1,11.918287937743191,131,1,1,11.918287937743191,132,2,1,11.918287937743195,133,3,1,11.918287937743187,98,4,1,3.375,-1,5,1,7.55859375,122,6,1,11.103515625,134]}}
  #|{"textrec":{"s":[12,400,0,"输出 token"],"r":[0,1,11.918287937743191,124,1,1,11.918287937743191,135,2,1,3.375,-1,3,1,4.3154296875,126,4,1,7.0458984375,127,5,1,6.369140625,128,6,1,6.708984375,129,7,1,7.001953125,130]}}
  #|{"textrec":{"s":[12,400,0,"平均每次 0"],"r":[0,1,11.918287937743191,136,1,1,11.918287937743191,121,2,1,11.918287937743195,137,3,1,11.918287937743187,123,4,1,3.375,-1,5,1,7.55859375,122]}}
  #|{"textrec":{"s":[12,400,0,"订阅账号不按 token 收费；费用按 API 标准单价估算，不含长上下文和服务等级等加价"],"r":[0,1,11.918287937743191,138,1,1,11.918287937743191,139,2,1,11.918287937743195,140,3,1,11.918287937743187,141,4,1,11.918287937743187,142,5,1,11.918287937743187,143,6,1,3.375,-1,7,1,4.3154296875,126,8,1,7.0458984375,127,9,1,6.369140625,128,10,1,6.708984375,129,11,1,7.001953125,130,12,1,3.375,-1,13,1,11.918287937743187,144,14,1,11.918287937743202,107,15,1,12.081712062256798,145,16,1,11.918287937743202,107,17,1,11.918287937743202,108,18,1,11.918287937743202,143,19,1,3.375,-1,20,1,8.0859375,146,21,1,7.623046875,147,22,1,3.2109375,148,23,1,3.375,-1,24,1,11.918287937743202,149,25,1,11.918287937743202,150,26,1,11.918287937743202,151,27,1,11.918287937743202,113,28,1,11.918287937743202,152,29,1,11.918287937743173,153,30,1,12.081712062256827,154,31,1,11.918287937743173,142,32,1,11.918287937743173,155,33,1,11.918287937743173,156,34,1,11.918287937743173,157,35,1,11.918287937743173,158,36,1,11.918287937743173,159,37,1,11.918287937743173,160,38,1,11.918287937743173,161,39,1,11.918287937743173,162,40,1,11.918287937743173,163,41,1,11.918287937743173,164,42,1,11.918287937743173,163,43,1,11.918287937743173,165,44,1,11.918287937743173,113]}}
  #|{"textrec":{"g":99,"r":[1247,0,23,23,-1,-19,0]}}
  #|{"textrec":{"g":100,"r":[1271,0,23,23,0,-20,0]}}
  #|{"textrec":{"g":101,"r":[1295,0,9,12,-1,-11,0]}}
  #|{"textrec":{"g":102,"r":[1305,0,15,14,-1,-11,0]}}
  #|{"textrec":{"g":103,"r":[1321,0,10,13,-1,-11,0]}}
  #|{"textrec":{"g":104,"r":[1332,0,10,13,-1,-11,0]}}
  #|{"textrec":{"g":105,"r":[1343,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":106,"r":[1358,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":107,"r":[1373,0,13,14,-1,-11,0]}}
  #|{"textrec":{"g":108,"r":[1387,0,13,14,-1,-11,0]}}
  #|{"textrec":{"g":109,"r":[1401,0,15,22,0,-19,0]}}
  #|{"textrec":{"g":110,"r":[1417,0,15,19,0,-17,0]}}
  #|{"textrec":{"g":111,"r":[1433,0,14,13,-1,-11,0]}}
  #|{"textrec":{"g":112,"r":[1448,0,13,14,-1,-11,0]}}
  #|{"textrec":{"g":113,"r":[1462,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":114,"r":[1477,0,11,13,0,-10,0]}}
  #|{"textrec":{"g":115,"r":[1489,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":116,"r":[1504,0,11,10,0,-9,0]}}
  #|{"textrec":{"g":117,"r":[1516,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":118,"r":[1531,0,13,13,-1,-11,0]}}
  #|{"textrec":{"g":119,"r":[1545,0,13,14,-1,-11,0]}}
  #|{"textrec":{"g":120,"r":[1559,0,23,23,-1,-19,0]}}
  #|{"textrec":{"g":121,"r":[1583,0,13,14,-1,-11,0]}}
  #|{"textrec":{"g":122,"r":[1597,0,9,12,-1,-10,0]}}
  #|{"textrec":{"g":123,"r":[1607,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":124,"r":[1622,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":125,"r":[1637,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":126,"r":[1652,0,6,11,-1,-9,0]}}
  #|{"textrec":{"g":127,"r":[1659,0,9,10,-1,-8,0]}}
  #|{"textrec":{"g":128,"r":[1669,0,8,11,0,-10,0]}}
  #|{"textrec":{"g":129,"r":[1678,0,9,10,-1,-8,0]}}
  #|{"textrec":{"g":130,"r":[1688,0,9,9,-1,-8,0]}}
  #|{"textrec":{"g":131,"r":[1698,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":132,"r":[1713,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":133,"r":[1728,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":134,"r":[1743,0,13,12,-1,-10,0]}}
  #|{"textrec":{"g":135,"r":[1757,0,12,14,0,-11,0]}}
  #|{"textrec":{"g":136,"r":[1770,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":137,"r":[1785,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":138,"r":[1800,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":139,"r":[1815,0,12,14,0,-11,0]}}
  #|{"textrec":{"g":140,"r":[1828,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":141,"r":[1843,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":142,"r":[1858,0,14,13,-1,-10,0]}}
  #|{"textrec":{"g":143,"r":[1873,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":144,"r":[1888,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":145,"r":[1903,0,4,11,1,-9,0]}}
  #|{"textrec":{"g":146,"r":[1908,0,10,11,-1,-10,0]}}
  #|{"textrec":{"g":147,"r":[1919,0,8,11,0,-10,0]}}
  #|{"textrec":{"g":148,"r":[1928,0,4,11,0,-10,0]}}
  #|{"textrec":{"g":149,"r":[1933,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":150,"r":[1948,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":151,"r":[1963,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":152,"r":[1978,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":153,"r":[1993,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":154,"r":[2008,0,5,6,0,-3,0]}}
  #|{"textrec":{"g":155,"r":[2014,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":156,"r":[2029,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":157,"r":[0,25,14,13,-1,-11,0]}}
  #|{"textrec":{"g":158,"r":[15,25,14,13,-1,-10,0]}}
  #|{"textrec":{"g":159,"r":[30,25,14,14,-1,-11,0]}}
  #|{"textrec":{"g":160,"r":[45,25,13,14,-1,-11,0]}}
  #|{"textrec":{"g":161,"r":[59,25,14,14,-1,-11,0]}}
  #|{"textrec":{"g":162,"r":[74,25,14,14,-1,-11,0]}}
  #|{"textrec":{"g":163,"r":[89,25,14,14,-1,-11,0]}}
  #|{"textrec":{"g":164,"r":[104,25,14,14,-1,-11,0]}}
  #|{"textrec":{"g":165,"r":[119,25,13,14,-1,-11,0]}}
  #|{"textrec":{"s":[14,400,0,"这段时间没有用量"],"r":[0,1,13.891050583657588,89,1,1,13.891050583657588,166,2,1,13.891050583657588,167,3,1,13.891050583657588,168,4,1,13.891050583657588,169,5,1,13.891050583657588,170,6,1,13.891050583657588,55,7,1,13.891050583657588,171]}}
  #|{"textrec":{"s":[13,400,0,"agent 调用模型消耗的 token，按 API 价格折算为费用"],"r":[0,1,7.0966796875,12,1,1,7.845703125,172,2,1,7.3505859375,14,3,1,7.50927734375,173,4,1,4.646484375,174,5,1,3.580078125,-1,6,1,12.898832684824903,175,7,1,12.898832684824903,176,8,1,12.89883268482491,177,9,1,12.898832684824896,178,10,1,12.898832684824896,179,11,1,12.898832684824896,180,12,1,12.898832684824896,5,13,1,3.580078125,-1,14,1,4.598876953125,174,15,1,7.556884765625,7,16,1,6.82373046875,9,17,1,7.19189453125,14,18,1,7.50927734375,173,19,1,13.075875486381335,181,20,1,12.898832684824896,182,21,1,3.580078125,-1,22,1,8.68359375,183,23,1,8.18212890625,184,24,1,3.40234375,185,25,1,3.580078125,-1,26,1,12.898832684824896,186,27,1,12.898832684824896,187,28,1,12.898832684824896,188,29,1,12.898832684824924,189,30,1,12.898832684824924,190,31,1,12.898832684824924,191,32,1,12.898832684824924,176]}}
  #|{"textrec":{"g":166,"r":[133,25,16,16,-1,-13,0]}}
  #|{"textrec":{"g":167,"r":[150,25,15,16,0,-13,0]}}
  #|{"textrec":{"g":168,"r":[166,25,14,16,0,-13,0]}}
  #|{"textrec":{"g":169,"r":[181,25,16,15,-1,-12,0]}}
  #|{"textrec":{"g":170,"r":[198,25,15,16,-1,-13,0]}}
  #|{"textrec":{"g":171,"r":[214,25,15,15,-1,-12,0]}}
  #|{"textrec":{"g":12,"r":[230,25,9,10,-1,-8,0]}}
  #|{"textrec":{"g":172,"r":[240,25,9,12,-1,-8,0]}}
  #|{"textrec":{"g":14,"r":[250,25,9,10,-1,-8,0]}}
  #|{"textrec":{"g":173,"r":[260,25,8,9,0,-8,0]}}
  #|{"textrec":{"g":174,"r":[269,25,7,12,-1,-10,0]}}
  #|{"textrec":{"g":175,"r":[277,25,14,15,-1,-12,0]}}
  #|{"textrec":{"g":176,"r":[292,25,14,14,-1,-11,0]}}
  #|{"textrec":{"g":177,"r":[307,25,15,15,-1,-12,0]}}
  #|{"textrec":{"g":178,"r":[323,25,14,14,-1,-12,0]}}
  #|{"textrec":{"g":179,"r":[338,25,14,15,-1,-12,0]}}
  #|{"textrec":{"g":180,"r":[353,25,15,15,-1,-12,0]}}
  #|{"textrec":{"g":5,"r":[369,25,13,15,0,-12,0]}}
  #|{"textrec":{"g":7,"r":[383,25,9,10,-1,-8,0]}}
  #|{"textrec":{"g":9,"r":[393,25,8,12,0,-11,0]}}
  #|{"textrec":{"g":181,"r":[402,25,5,7,0,-3,0]}}
  #|{"textrec":{"g":182,"r":[408,25,15,15,-1,-12,0]}}
  #|{"textrec":{"g":183,"r":[424,25,11,12,-1,-11,0]}}
  #|{"textrec":{"g":184,"r":[436,25,9,12,0,-11,0]}}
  #|{"textrec":{"g":185,"r":[446,25,4,12,0,-11,0]}}
  #|{"textrec":{"g":186,"r":[451,25,15,15,-1,-12,0]}}
  #|{"textrec":{"g":187,"r":[467,25,15,15,-1,-12,0]}}
  #|{"textrec":{"g":188,"r":[483,25,14,15,-1,-12,0]}}
  #|{"textrec":{"g":189,"r":[498,25,14,15,-1,-12,0]}}
  #|{"textrec":{"g":190,"r":[513,25,14,15,-1,-12,0]}}
  #|{"textrec":{"g":191,"r":[528,25,14,15,-1,-12,0]}}
