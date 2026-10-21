// e2e/traces/drive-zip.trace, made by scripts/trace.py from 02-drive_zip.log: not edited by hand.

///|
/// What the app and its core said in the run, a line each.
pub let trace_drive_zip : String =
  #|{"env":{"MBUI_CLOUD":"http://127.0.0.1:18787","MBUI_CORE_ACCOUNT":"{\"sub\":\"alice\",\"email\":\"alice@example.test\",\"name\":\"Name of alice\",\"picture\":\"\",\"access\":\"-\",\"refresh\":\"-\",\"accessExpires\":1792593342}"}}
  #|{"out":{"id":1,"call":"client.device","params":{"client":"still.fail mbui","app":"desktop","userAgent":"Macintosh; Mac OS X"}},"w":1792593044646.175}
  #|{"in":{"id":1,"ok":null},"w":1792593044728.132}
  #|{"out":{"id":2,"subscribe":{"topic":"accounts"},"keyed":true},"w":1792593044728.158}
  #|{"out":{"id":3,"subscribe":{"topic":"prefs"},"keyed":true},"w":1792593044728.169}
  #|{"step":"# written by scripts/rerecord.sh from its test (src/sfreplay/emit.mbt): not edited by hand","w":1792593044729.507}
  #|{"step":"timeout 90000","w":1792593044729.513}
  #|{"step":"answered client.device","w":1792593044729.516}
  #|{"step":"answered client.focus","w":1792593044755.951}
  #|{"in":{"id":2,"value":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""}]},"w":1792593044821.993}
  #|{"in":{"id":3,"value":{"onlyMine":false,"onlyWatching":false,"onlyDecisions":false,"listFilter":{},"appearance":"system","rowPicture":"auto","absoluteTime":false,"lang":"zh","keys":{},"lastChat":{},"openChat":{},"chatTabs":{},"dropFiles":{},"driveViews":{},"resume":{},"stationUpdatesDismissed":{},"device":{"app":"desktop","phone":false,"handoff":false},"reader":{"size":18,"line":1.7,"margin":22,"face":"sans","indent":true,"paper":"follow"},"rails":{},"bars":{"sets":[["chats","files","profiles","stations"],["decisions","usage","connects","archive"]],"current":0},"barsBy":{},"fonts":{},"faces":{"ui":{"id":"","name":"","mono":false,"family":"","files":[],"bytes":0},"text":{"id":"","name":"","mono":false,"family":"","files":[],"bytes":0},"code":{"id":"","name":"","mono":true,"family":"","files":[],"bytes":0},"list":[{"id":"inter","name":"Inter","mono":false,"family":"SF Inter","css":"http://127.0.0.1:18787/releases/fonts/inter/4.001/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/inter/4.001/var.ttf.gz","bytes":457818,"sha256":"29160a80ff49ddcab2c97711247e08b1fab27a484a329ce8b813d820dc559031"}],"preview":"http://127.0.0.1:18787/releases/fonts/inter/4.001/preview-194fa287.ttf","bytes":457818},{"id":"noto-sans-sc","name":"思源黑体","mono":false,"family":"SF Noto Sans SC","css":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/var.ttf.gz","bytes":11276563,"sha256":"a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da"}],"preview":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/preview-f0494178.ttf","bytes":11276563},{"id":"noto-serif-sc","name":"思源宋体","mono":false,"family":"SF Noto Serif SC","css":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/var.ttf.gz","bytes":15454579,"sha256":"050080d9255a86808f2945bffac582b31ef32bc36411ce29563b4961670c66f9"}],"preview":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/preview-001bbedf.ttf","bytes":15454579},{"id":"lxgw-wenkai","name":"霞鹜文楷","mono":false,"family":"SF LXGW WenKai","css":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/font.css","files":[{"weight":400,"url":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/400.ttf.gz","bytes":12904482,"sha256":"2d73eea94ad808999d90c0000c239a84a33b09d4bc6ab6c5b8bbf1eda8a7fc8b"},{"weight":500,"url":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/500.ttf.gz","bytes":13272430,"sha256":"f4b8a34d1f838fe411540cb7c97b1c384ac9738a876c4104500bc42508b2312a"}],"preview":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/preview-d3505af4.ttf","bytes":26176912},{"id":"jetbrains-mono","name":"JetBrains Mono","mono":true,"family":"SF JetBrains Mono","css":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/var.ttf.gz","bytes":90579,"sha256":"48715a42ec242c21e9f02692891e147d022299a52e48d5e413e1a942193ffeda"}],"preview":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/preview-ee73078f.ttf","bytes":90579},{"id":"fira-code","name":"Fira Code","mono":true,"family":"SF Fira Code","css":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/var.ttf.gz","bytes":137151,"sha256":"9335b082b3c7850d98a64b584f3417f65355f3471278bb5eeb8c6c0e8657aeeb"}],"preview":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/preview-555be27a.ttf","bytes":137151},{"id":"maple-mono","name":"Maple Mono","mono":true,"family":"SF Maple Mono CN","css":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/font.css","files":[{"weight":400,"url":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/400.ttf.gz","bytes":8352545,"sha256":"0fcc5139bfd5ab14ff989bb7dfd5236d0cafc10e60b9828569e6883613ab4085"},{"weight":600,"url":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/600.ttf.gz","bytes":8438132,"sha256":"96ed7ae26ee7c50b02b2d2b2bc0f1a0cbabe45ae5d6e6abf6678e2177c415677"}],"preview":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/preview-cffdf246.ttf","bytes":16790677}]}}},"w":1792593044822.038}
  #|{"out":{"id":4,"subscribe":{"topic":"workspaces"},"keyed":true},"w":1792593044822.089}
  #|{"out":{"id":5,"subscribe":{"topic":"status"},"keyed":true},"w":1792593044822.1}
  #|{"in":{"id":4,"value":[{"account":{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""},"workspaces":[{"id":"01M5FDY2ZE08Q9YFKARA67C0PM","name":"Dev","role":"owner","created_at":1792593038,"stations":1,"members":1,"relays":[],"time":{"created_at":{"past":true,"at":1792593038000,"ago":"刚刚","full":"10/21 22:30:38","until":"1 分钟内"}}}],"invitations":[],"relay_url":"http://127.0.0.1:18740","loaded":true,"beta":true}]},"w":1792593044838.678}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792593044838.696}
  #|{"out":{"id":6,"subscribe":{"topic":"lock","workspace":"01M5FDY2ZE08Q9YFKARA67C0PM"},"keyed":true},"w":1792593044838.737}
  #|{"out":{"id":7,"subscribe":{"topic":"chats","scope":"01M5FDY2ZE08Q9YFKARA67C0PM","mine":false},"keyed":true},"w":1792593044838.755}
  #|{"out":{"id":8,"subscribe":{"topic":"changelog"},"keyed":true},"w":1792593044838.768}
  #|{"out":{"id":9,"subscribe":{"topic":"workspaceMarks","workspace":"01M5FDY2ZE08Q9YFKARA67C0PM"},"keyed":true},"w":1792593044838.9}
  #|{"out":{"id":10,"subscribe":{"topic":"stations","scope":"01M5FDY2ZE08Q9YFKARA67C0PM"},"keyed":true},"w":1792593044838.923}
  #|{"out":{"id":11,"subscribe":{"topic":"workspace","workspace":"01M5FDY2ZE08Q9YFKARA67C0PM"},"keyed":true},"w":1792593044838.927}
  #|{"out":{"id":12,"subscribe":{"topic":"status","workspace":"01M5FDY2ZE08Q9YFKARA67C0PM"},"keyed":true},"w":1792593044838.993}
  #|{"out":{"id":13,"subscribe":{"topic":"lockPrompts"},"keyed":true},"w":1792593044839.023}
  #|{"out":{"id":14,"call":"client.focus","params":{"visible":true,"focused":true,"workspace":"01M5FDY2ZE08Q9YFKARA67C0PM"}},"w":1792593044842.089}
  #|{"out":{"id":15,"subscribe":{"topic":"notify"},"keyed":true},"w":1792593044842.098}
  #|{"out":{"id":16,"subscribe":{"topic":"notify","workspace":"01M5FDY2ZE08Q9YFKARA67C0PM"},"keyed":true},"w":1792593044842.104}
  #|{"in":{"id":6,"value":{"available":true,"locked":false,"notice":true,"role":"owner","manages":true,"owner":true,"canSign":true,"signs":false,"me":{"device":"c6cce24bc88c234a3b545be867668a78365545d5161cce1a0d2261d297aea3b0","code":"64N-S3R","kind":"app","confirmed":false,"waiting":false,"asked":false},"signers":0,"members":[],"stations":[{"id":"8de8ed849656812001ad05576a132ab902dbd33399ea76b81df64c1dd2f46fdc","name":"studio","version":"0.1.0","online":true,"protected":false}],"protected":0,"requests":[],"renew":[],"attention":0}},"w":1792593044856.676}
  #|{"in":{"id":11,"value":{"id":"01M5FDY2ZE08Q9YFKARA67C0PM","name":"Dev","role":"owner","created_at":1792593038,"members":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":"https://example.test/p.png","role":"owner","added_at":1792593038}],"stations":[{"id":"8de8ed849656812001ad05576a132ab902dbd33399ea76b81df64c1dd2f46fdc","name":"studio","emoji":null,"icon":null,"enrolled_at":1792593038,"enrolled_by":"alice","last_seen":1792593042,"version":"0.1.0","time":{"last_seen":{"past":true,"at":1792593042000,"ago":"刚刚","full":"10/21 22:30:42","until":"1 分钟内"}}}],"invitations":[],"added":[],"relays":[],"lock":null,"lock_requests":0,"time":{"created_at":{"past":true,"at":1792593038000,"ago":"刚刚","full":"10/21 22:30:38","until":"1 分钟内"}}}},"w":1792593044856.701}
  #|{"in":{"id":7,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"stations":[{"station":"01M5FDY2ZE08Q9YFKARA67C0PM/8de8ed849656812001ad05576a132ab902dbd33399ea76b81df64c1dd2f46fdc","id":"8de8ed849656812001ad05576a132ab902dbd33399ea76b81df64c1dd2f46fdc","name":"studio","state":"online"}],"loading":false,"days":[{"daysAgo":0,"at":1792593042261,"label":"今天","items":[{"id":"ember:c-2ed2f07c91","session":"ember:c-2ed2f07c91","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","agents":[{"key":"ember:c-2ed2f07c91","runtime":"claude","process":"warm","pending":0,"lastTurn":{"id":"9e26ecad-0864-4ff4-a3da-391814342395","kind":"input","outcome":"completed","declared":"final","ending":"all_done","need":"answered the question that was asked","startedAt":1792593042192,"endedAt":1792593042263},"agentText":"默认模型","statusText":"已完成：answered the question that was asked"}],"last":{"seq":2,"authorKind":"agent","author":"ember:c-2ed2f07c91","text":"你好，我是测试用的 agent","createdAt":1792593042261,"by":{"kind":"agent","name":"agent","mine":false,"runtime":"claude","label":"agent"},"preview":"你好，我是测试用的 agent","time":{"createdAt":{"at":1792593042261,"ago":"刚刚","full":"10/21 22:30:42","until":"1 分钟内","past":true}}},"unread":true,"mine":true,"lastActiveAt":1792593042261,"station":"01M5FDY2ZE08Q9YFKARA67C0PM/8de8ed849656812001ad05576a132ab902dbd33399ea76b81df64c1dd2f46fdc","stationName":"studio","time":{"lastActiveAt":{"at":1792593042261,"ago":"刚刚","full":"10/21 22:30:42","until":"1 分钟内","past":true}},"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"peopleText":"你 发起","clientKey":"new:chat-1cac207ccb61b7c99a","pinned":false,"tone":"done"}]}],"trouble":null,"members":1,"leading":"agents","glyph":{"online":1,"dim":0,"connecting":0,"failing":0,"working":0,"summary":"studio","label":"1 台 station，1 台在线"},"note":{"reading":false,"text":null,"failing":[],"empty":false}}},"w":1792593044856.727}
  #|{"in":{"id":8,"value":{"app":"desktop","tabs":[{"part":"desktop","label":"桌面","days":[]},{"part":"web","label":"网页","days":[]},{"part":"android","label":"安卓","days":[]},{"part":"station","label":"Station","days":[]},{"part":"cloud","label":"云端","days":[]}],"loading":false}},"w":1792593044856.748}
  #|{"in":{"id":9,"value":{"workspaces":{"01M5FDY2ZE08Q9YFKARA67C0PM":{"alert":0,"unread":1,"tone":"done","label":"1 个有新消息","badge":0,"items":[],"mineTone":"done"}},"badge":0,"badgeCounts":"attention","badgeKinds":{"on":true,"wait":true,"failed":true,"done":false,"message":false}}},"w":1792593044856.754}
  #|{"in":{"id":10,"value":[{"station":"01M5FDY2ZE08Q9YFKARA67C0PM/8de8ed849656812001ad05576a132ab902dbd33399ea76b81df64c1dd2f46fdc","id":"8de8ed849656812001ad05576a132ab902dbd33399ea76b81df64c1dd2f46fdc","name":"studio","summary":"空闲 · Apple M4 · 16 GB · macOS 27.0.1","face":"idle","line":"Apple M4","online":true,"reconnecting":false,"lastSeen":1792593042,"version":"0.1.0","link":{"state":"online"},"runtimes":[{"runtime":"claude","models":["claude-sonnet-5-5"]}],"models":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792593042178,"time":{"checkedAt":{"at":1792593042178,"ago":"刚刚","full":"10/21 22:30:42","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"overview":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null,"summaryText":"最近 7 天检查了 0 个 chat","changeText":null}},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","email":"alice@example.test","name":"Name of alice","sub":"alice","role":"owner","workspace":"01M5FDY2ZE08Q9YFKARA67C0PM","device":"c6cce24bc88c234a3b545be867668a78365545d5161cce1a0d2261d297aea3b0"},"connects":[],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792593042059,"time":{"checkedAt":{"at":1792593042059,"ago":"刚刚","full":"10/21 22:30:42","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792593042178,"time":{"checkedAt":{"at":1792593042178,"ago":"刚刚","full":"10/21 22:30:42","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"modelsReading":false,"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]}],"processes":[],"counts":{"sessions":1,"running":0,"warm":1},"mesh":{"state":"running","origin":"http://127.0.0.1:18787","station":"8de8ed849656812001ad05576a132ab902dbd33399ea76b81df64c1dd2f46fdc","workspace":"Dev","workspaceId":"01M5FDY2ZE08Q9YFKARA67C0PM","name":"studio"},"slackUsers":[],"slackTeams":[],"slackApps":[],"feishuRegistrations":[],"disk":{"freeBytes":30688784384,"totalBytes":245107195904},"logins":[],"machineLogins":[],"sharing":true,"consoleSignIn":true,"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"google","name":"Google Gemini","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xai","name":"xAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"mistral","name":"Mistral","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"deepseek","name":"DeepSeek","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen","name":"Qwen","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai","name":"Kimi","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai","name":"Z.ai","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax","name":"MiniMax","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ant-ling","name":"Ant Ling","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"jev","name":"Jev","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen-cn","name":"Qwen (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"openrouter","name":"OpenRouter","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"opencode","name":"OpenCode Zen","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"groq","name":"Groq","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"together","name":"Together AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"fireworks","name":"Fireworks","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cerebras","name":"Cerebras","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"huggingface","name":"Hugging Face","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"nvidia","name":"NVIDIA","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"baseten","name":"Baseten","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ollama","name":"Ollama","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"custom","name":"Custom","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""}],"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792593042062},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.306","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792593042062},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-lockp/apps/e2e-local/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792593042062},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-lockp/apps/e2e-local/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792593042062},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","latest":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-lockp/apps/e2e-local/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792593042062},{"id":"cursor","name":"Cursor","installed":false,"latest":"1.0.40","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792593042062},{"id":"devin","name":"Devin","installed":true,"version":"3000.11.92","latest":"3000.11.92","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-lockp/apps/e2e-local/ember/station/test/fake/devin，不是用 Devin 的安装脚本装的，需在该机器上手动更新","state":"idle","checkedAt":1792593042062}],"processesText":"没有运行中的 agent 进程","agentEnv":[],"drive":{"roots":[{"path":"/tmp/mbe2e-C/home/e2e-105609","name":"e2e-105609","state":"ok"}],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false}},"betaOffered":false,"host":{"hostname":"3720-Mac-mini-1","os":"macOS 27.0.1","arch":"arm64","cpus":10,"cpuModel":"Apple M4","load":0.22,"cpuBusy":0.1,"uptimeSec":72405,"memory":{"totalBytes":17179869184,"usedBytes":9657466880,"swapUsedBytes":250347520},"disk":{"path":"/tmp/mbe2e-C/data","totalBytes":245107195904,"freeBytes":30689107968},"emberRssBytes":157022032,"checkedAt":1792593043732,"summary":"10 核 · 16 GB","line":"macOS 27.0.1 · 10 核 · 16 GB · 已运行 0 天","facts":["3720-Mac-mini-1","macOS 27.0.1","arm64 · 10 核","已运行 20 小时"],"meters":[{"label":"CPU","short":"CPU","percent":10,"left":90,"level":"ok","value":"10%","remaining":"空闲 90%","big":"90","unit":"%","title":"CPU 空闲","total":"负载 2.2","note":"负载 2.2 · Apple M4"},{"label":"内存","short":"内存","percent":56,"left":44,"level":"ok","value":"9.0 GB / 16.0 GB","remaining":"剩 7.0 G","big":"7.0","unit":"GB","title":"内存剩","total":"共 16 GB","note":"swap 0.2 GB"},{"label":"磁盘","short":"磁盘","percent":87,"left":13,"level":"amber","value":"剩余 28.6 GB / 228 GB","remaining":"剩 28.6 G","big":"28.6","unit":"GB","title":"磁盘剩","total":"共 228 GB"}],"identity":"Apple M4 · 16 GB · macOS 27.0.1","details":[{"label":"主机名","value":"3720-Mac-mini-1"},{"label":"芯片","value":"Apple M4 · 10 核 · arm64"},{"label":"已运行","value":"20 小时"},{"label":"still.fail","value":"进程占用 150 MB"}],"usage":"内存 9.0 GB / 16.0 GB · 磁盘 剩余 28.6 GB / 228 GB","emberText":"still.fail 150 MB"},"way":{"path":"直连","via":"direct"},"time":{"lastSeen":{"at":1792593042000,"ago":"刚刚","full":"10/21 22:30:42","until":"1 分钟内","past":true}},"joined":false}]},"w":1792593044856.84}
  #|{"in":{"id":12,"value":{"items":[]}},"w":1792593044856.923}
  #|{"in":{"id":13,"value":{"pairing":[]}},"w":1792593044856.927}
  #|{"in":{"id":14,"ok":null},"w":1792593044856.929}
  #|{"in":{"id":15,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792593044856.935}
  #|{"in":{"id":16,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792593044856.94}
  #|{"out":{"id":17,"subscribe":{"topic":"longJobs","scope":"01M5FDY2ZE08Q9YFKARA67C0PM"},"keyed":true},"w":1792593044856.983}
  #|{"out":{"id":18,"call":"notify.permission","params":{"state":"unknown"}},"w":1792593044859.135}
  #|{"in":{"id":10,"delta":[{"path":[0,"overview","disk","freeBytes"],"set":30688768000}]},"w":1792593044872.004}
  #|{"in":{"id":17,"value":{"groups":[]}},"w":1792593044872.017}
  #|{"in":{"id":18,"ok":null},"w":1792593044872.02}
  #|{"step":"#env MBUI_OPEN_PAGE=files","w":1792593044872.274}
  #|{"step":"answered notify.permission","w":1792593044872.276}
  #|{"step":"wait 299","w":1792593044889.034}
  #|{"step":"now tap =e2e-105609","w":1792593045189.228}
  #|{"step":"now tap =e2e-105609","acted":true,"w":1792593045189.348}
  #|{"out":{"id":19,"subscribe":{"topic":"drive","station":"01M5FDY2ZE08Q9YFKARA67C0PM/8de8ed849656812001ad05576a132ab902dbd33399ea76b81df64c1dd2f46fdc","root":"/tmp/mbe2e-C/home/e2e-105609","path":""},"keyed":true},"w":1792593045205.902}
  #|{"step":"wait 300","w":1792593045212.182}
  #|{"in":{"id":19,"value":{"path":"","entries":[{"name":"子文件夹","dir":true,"size":0,"mtime":1792593042805,"type":"","kind":"folder","sizeText":"","timeText":"22:30"},{"name":"小说-e2e.txt","dir":false,"size":36779,"mtime":1792593042819,"type":"text/plain; charset=utf-8","kind":"text","sizeText":"36 KB","timeText":"22:30"},{"name":"说明.txt","dir":false,"size":43,"mtime":1792593042805,"type":"text/plain; charset=utf-8","kind":"text","sizeText":"43 B","timeText":"22:30"}],"truncated":false,"folders":1,"files":2,"countText":"1 个文件夹 · 2 个文件"}},"w":1792593045238.73}
  #|{"out":{"id":20,"subscribe":{"topic":"drivePlace","station":"01M5FDY2ZE08Q9YFKARA67C0PM/8de8ed849656812001ad05576a132ab902dbd33399ea76b81df64c1dd2f46fdc","root":"/tmp/mbe2e-C/home/e2e-105609","path":"小说-e2e.txt"},"keyed":true},"w":1792593045242.184}
  #|{"out":{"id":21,"subscribe":{"topic":"drivePlace","station":"01M5FDY2ZE08Q9YFKARA67C0PM/8de8ed849656812001ad05576a132ab902dbd33399ea76b81df64c1dd2f46fdc","root":"/tmp/mbe2e-C/home/e2e-105609","path":"说明.txt"},"keyed":true},"w":1792593045242.882}
  #|{"in":{"id":20,"value":null},"w":1792593045255.344}
  #|{"in":{"id":21,"value":null},"w":1792593045255.371}
  #|{"step":"now hold 800 子文件夹","w":1792593045522.789}
  #|{"step":"now hold 800 子文件夹","acted":true,"w":1792593045522.843}
  #|{"step":"until 已选 1 项","w":1792593046356.022}
  #|{"step":"tap icon:more","w":1792593046356.082}
  #|{"step":"tap icon:more","acted":true,"w":1792593046356.121}
  #|{"step":"wait 1408","w":1792593046384.693}
  #|{"step":"now tap 下载为 zip","w":1792593047822.958}
  #|{"step":"now tap 下载为 zip","acted":true,"w":1792593047823.039}
  #|{"out":{"id":22,"call":"drive.zip","params":{"station":"01M5FDY2ZE08Q9YFKARA67C0PM/8de8ed849656812001ad05576a132ab902dbd33399ea76b81df64c1dd2f46fdc","root":"/tmp/mbe2e-C/home/e2e-105609","path":"子文件夹"}},"w":1792593047838.945}
  #|{"step":"answered drive.zip","w":1792593047842.717}
  #|{"in":{"id":22,"ok":{"root":"/var/folders/qf/3z15kk2n73sflr83p7gq5cj80000gn/T/stillfail-zips/3256f42c-3fd5-401c-ab8c-59a10ab89aca","path":"子文件夹.zip","name":"子文件夹.zip","size":277}},"w":1792593047872.02}
  #|{"out":{"id":23,"call":"drive.read","params":{"station":"01M5FDY2ZE08Q9YFKARA67C0PM/8de8ed849656812001ad05576a132ab902dbd33399ea76b81df64c1dd2f46fdc","root":"/var/folders/qf/3z15kk2n73sflr83p7gq5cj80000gn/T/stillfail-zips/3256f42c-3fd5-401c-ab8c-59a10ab89aca","path":"子文件夹.zip","offset":0,"length":4194304}},"w":1792593047873.873}
  #|{"in":{"id":23,"ok":{"type":"application/zip","total":277,"mtime":1792593047856}},"w":1792593047888.687,"b":"504b0304140000080000d5b3555d0000000000000000000000000d000000e5ad90e69687e4bbb6e5a4b92f504b0304140000080000d5b3555dd196a5d31f0000001f00000017000000e5ad90e69687e4bbb6e5a4b92fe9878ce99da22e747874e5ad90e69687e4bbb6e5a4b9e9878ce79a84e4b880e8a18ce5ad97e380820a504b01021e03140000080000d5b3555d0000000000000000000000000d0000000000000000001000ed4100000000e5ad90e69687e4bbb6e5a4b92f504b01021e03140000080000d5b3555dd196a5d31f0000001f000000170000000000000000000000a4812b000000e5ad90e69687e4bbb6e5a4b92fe9878ce99da22e747874504b05060000000002000200800000007f0000000000"}
  #|{"step":"answered drive.read","w":1792593047890.283}
  #|{"step":"until 已保存到「下载」","w":1792593047907.299}
  #|{"step":"wait 1392","w":1792593047907.324}
  #|{"step":"wait 2600","w":1792593049322.955}
  #|{"step":"","w":1792593051940.008}
  #|{"textrec":{"ib":["bfd9b0d6dc602826",12668,64],"r":[56,56,56,56]}}
  #|{"textrec":{"s":[13,400,0,"正在读取你的 workspace"],"r":[0,1,12.898832684824903,0,1,1,12.898832684824903,1,2,1,12.898832684824903,2,3,1,12.898832684824903,3,4,1,12.898832684824896,4,5,1,12.898832684824896,5,6,1,3.580078125,-1,7,1,9.8642578125,6,8,1,7.4775390625,7,9,1,4.875,8,10,1,6.85546875,9,11,1,6.6015625,10,12,1,7.8583984375,11,13,1,7.0966796875,12,14,1,7.1982421875,13,15,1,7.3505859375,14]}}
  #|{"textrec":{"m":[13,400,0],"r":[12.568359375,2.7421875,18,12.568359375,2.7421875,0]}}
  #|{"textrec":{"s":[24,700,0,"Dev"],"r":[0,1,17.075823068618774,15,1,1,13.365240812301636,16,2,1,12.759063005447388,17]}}
  #|{"textrec":{"m":[24,700,0],"r":[23.203125,5.0625,34,20.638916015625,3.361083984375,0]}}
  #|{"textrec":{"s":[16,600,0,"文件"],"r":[0,1,15.875486381322958,18,1,1,15.875486381322958,19]}}
  #|{"textrec":{"m":[16,600,0],"r":[15.46875,3.375,23,15.46875,3.375,0]}}
  #|{"textrec":{"s":[17,400,0,"对话"],"r":[0,1,16.851167315175097,20,1,1,16.851167315175097,21]}}
  #|{"textrec":{"m":[17,400,0],"r":[16.435546875,3.5859375,24,16.435546875,3.5859375,0]}}
  #|{"textrec":{"g":15,"r":[0,0,18,19,0,-18,0]}}
  #|{"textrec":{"g":16,"r":[19,0,15,16,-1,-14,0]}}
  #|{"textrec":{"g":17,"r":[35,0,15,15,-1,-14,0]}}
  #|{"textrec":{"ib":["02698e60df92657e",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"ib":["1d51432b25a425eb",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"s":[15,400,0,"搜索全部内容"],"r":[0,1,14.883268482490273,22,1,1,14.883268482490273,23,2,1,14.883268482490273,24,3,1,14.883268482490273,25,4,1,14.88326848249028,26,5,1,14.88326848249028,27]}}
  #|{"textrec":{"m":[15,400,0],"r":[14.501953125,3.1640625,21,14.501953125,3.1640625,0]}}
  #|{"textrec":{"s":[15,600,0,"今天"],"r":[0,1,14.883268482490273,28,1,1,14.883268482490273,29]}}
  #|{"textrec":{"m":[15,600,0],"r":[14.501953125,3.1640625,21,14.501953125,3.1640625,0]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 post:你好，我是测试用的 agent"],"r":[0,1,15.875486381322958,30,1,1,15.875486381322958,31,2,1,15.875486381322958,30,3,1,15.875486381322958,32,4,1,15.875486381322958,33,5,1,15.875486381322958,34,6,1,15.875486381322958,35,7,1,15.875486381322958,36,8,1,3.95001220703125,-1,9,1,9.824199676513672,37,10,1,9.432537078857422,38,11,1,8.471200942993164,39,12,1,5.973020553588867,40,13,1,4.952056884765625,41,14,1,15.875486381322958,42,15,1,15.875486381322958,43,16,1,16.09338521400778,44,17,1,15.875486381322958,45,18,1,15.875486381322958,46,19,1,15.87548638132293,32,20,1,15.875486381322958,33,21,1,15.875486381322958,47,22,1,15.875486381322958,34,23,1,3.95001220703125,-1,24,1,8.899068832397461,48,25,1,9.801153182983398,49,26,1,9.127458572387695,50,27,1,9.466253280639648,51,28,1,5.999713897705078,40]}}
  #|{"textrec":{"s":[14,400,0,"你好，我是测试用的 agent"],"r":[0,1,13.891050583657588,52,1,1,13.891050583657588,53,2,1,14.081712062256813,54,3,1,13.891050583657588,55,4,1,13.891050583657588,56,5,1,13.891050583657588,57,6,1,13.891050583657588,58,7,1,13.891050583657588,59,8,1,13.891050583657588,60,9,1,3.787109375000014,-1,10,1,7.57421875,61,11,1,8.380859375,62,12,1,7.84765625,63,13,1,8.0185546875,64,14,1,4.935546875,65]}}
  #|{"textrec":{"m":[14,400,0],"r":[13.53515625,2.953125,20,13.53515625,2.953125,0]}}
  #|{"textrec":{"s":[16,600,0,"…"],"r":[0,1,14.076484680175781,66]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 post:你好，我是测试用的…"],"r":[0,1,15.875486381322958,30,1,1,15.875486381322958,31,2,1,15.875486381322958,30,3,1,15.875486381322958,32,4,1,15.875486381322958,33,5,1,15.875486381322958,34,6,1,15.875486381322958,35,7,1,15.875486381322958,36,8,1,3.95001220703125,-1,9,1,9.824199676513672,37,10,1,9.432537078857422,38,11,1,8.471200942993164,39,12,1,5.973020553588867,40,13,1,4.952056884765625,41,14,1,15.875486381322958,42,15,1,15.875486381322958,43,16,1,16.09338521400778,44,17,1,15.875486381322958,45,18,1,15.875486381322958,46,19,1,15.87548638132293,32,20,1,15.875486381322958,33,21,1,15.875486381322958,47,22,1,15.875486381322958,34,23,1,14.076484680175781,66]}}
  #|{"textrec":{"s":[15,600,0,"studio"],"r":[0,1,8.000344634056091,67,1,1,5.658300518989563,68,2,1,8.93320620059967,69,3,1,9.332013130187988,70,4,1,3.8520312309265137,71,5,1,8.901597261428833,72]}}
  #|{"textrec":{"s":[16,400,0,"主目录"],"r":[0,1,15.875486381322958,73,1,1,15.875486381322958,74,2,1,15.875486381322958,75]}}
  #|{"textrec":{"m":[16,400,0],"r":[15.46875,3.375,23,15.46875,3.375,0]}}
  #|{"textrec":{"s":[16,400,0,"e2e-105609"],"r":[0,1,8.828125,76,1,1,9.3046875,77,2,1,8.7890625,76,3,1,7.234375,78,4,1,7.109375,79,5,1,9.765625,80,6,1,9.578125,81,7,1,9.875,82,8,1,9.765625,80,9,1,9.875,83]}}
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
  #|{"textrec":{"g":37,"r":[317,0,11,14,0,-10,0]}}
  #|{"textrec":{"g":38,"r":[329,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":39,"r":[341,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":40,"r":[353,0,8,14,-1,-12,0]}}
  #|{"textrec":{"g":41,"r":[362,0,5,12,0,-10,0]}}
  #|{"textrec":{"g":42,"r":[368,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":43,"r":[386,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":44,"r":[404,0,6,8,0,-4,0]}}
  #|{"textrec":{"g":45,"r":[411,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":46,"r":[430,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":47,"r":[448,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":66,"r":[465,0,14,6,0,-4,0]}}
  #|{"textrec":{"g":52,"r":[480,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":53,"r":[496,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":54,"r":[513,0,5,7,0,-3,0]}}
  #|{"textrec":{"g":55,"r":[519,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":56,"r":[536,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":57,"r":[552,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":58,"r":[568,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":59,"r":[585,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":60,"r":[601,0,14,16,0,-13,0]}}
  #|{"textrec":{"g":61,"r":[616,0,9,11,-1,-9,0]}}
  #|{"textrec":{"g":62,"r":[626,0,10,13,-1,-9,0]}}
  #|{"textrec":{"g":63,"r":[637,0,10,11,-1,-9,0]}}
  #|{"textrec":{"g":64,"r":[648,0,9,10,0,-9,0]}}
  #|{"textrec":{"g":65,"r":[658,0,7,13,-1,-11,0]}}
  #|{"textrec":{"ib":["33d1dfbf90932d3b",1241,64],"r":[17,17,17,17]}}
  #|{"textrec":{"ib":["182b7158e0c0cae1",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["d61ec6305f7d8c8b",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["a1e7be43eb966606",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"g":20,"r":[666,0,18,18,-1,-15,0]}}
  #|{"textrec":{"g":21,"r":[685,0,19,18,-1,-15,0]}}
  #|{"textrec":{"g":67,"r":[705,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":68,"r":[716,0,8,13,-1,-11,0]}}
  #|{"textrec":{"g":69,"r":[725,0,10,12,0,-10,0]}}
  #|{"textrec":{"g":70,"r":[736,0,11,15,-1,-13,0]}}
  #|{"textrec":{"g":71,"r":[748,0,6,14,-1,-13,0]}}
  #|{"textrec":{"g":72,"r":[755,0,11,12,-1,-10,0]}}
  #|{"textrec":{"ib":["4165e1c325ff4b32",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"ib":["7d024a54eca23c07",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"g":73,"r":[767,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":74,"r":[785,0,14,16,1,-13,0]}}
  #|{"textrec":{"g":75,"r":[800,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":76,"r":[818,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":77,"r":[830,0,10,14,0,-13,0]}}
  #|{"textrec":{"g":78,"r":[841,0,8,5,0,-7,0]}}
  #|{"textrec":{"g":79,"r":[850,0,7,14,0,-13,0]}}
  #|{"textrec":{"g":80,"r":[858,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":81,"r":[870,0,10,15,0,-13,0]}}
  #|{"textrec":{"g":82,"r":[881,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":83,"r":[893,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":18,"r":[905,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":19,"r":[924,0,17,17,-1,-14,0]}}
  #|{"textrec":{"ib":["2bb63fc1d380f765",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"s":[17,400,0,"设置"],"r":[0,1,16.851167315175097,84,1,1,16.851167315175097,85]}}
  #|{"textrec":{"s":[16,600,0,"e2e-105609"],"r":[0,1,9.127458572387695,50,1,1,9.717817306518555,86,2,1,9.100765228271484,50,3,1,7.363014221191406,87,4,1,7.594245910644531,88,5,1,10.31976318359375,89,6,1,10.035783767700195,90,7,1,10.3499755859375,91,8,1,10.31976318359375,89,9,1,10.3499755859375,92]}}
  #|{"textrec":{"s":[17,400,0,"文件"],"r":[0,1,16.851167315175097,93,1,1,16.851167315175097,94]}}
  #|{"textrec":{"g":84,"r":[942,0,19,18,-1,-15,0]}}
  #|{"textrec":{"g":85,"r":[962,0,18,17,-1,-14,0]}}
  #|{"textrec":{"s":[13,400,0,"1 个文件夹 · 2 个文件"],"r":[0,1,5.9541015625,95,1,1,3.580078125,-1,2,1,12.898832684824903,96,3,1,12.898832684824903,97,4,1,12.898832684824903,98,5,1,12.898832684824903,99,6,1,3.580078125,-1,7,1,6.228545204222115,100,8,1,3.580078125,-1,9,1,7.76953125,101,10,1,3.580078125,-1,11,1,12.898832684824896,96,12,1,12.898832684824896,97,13,1,12.898832684824896,98]}}
  #|{"textrec":{"s":[15,400,0,"子文件夹"],"r":[0,1,14.883268482490273,102,1,1,14.883268482490273,103,2,1,14.883268482490273,104,3,1,14.883268482490273,105]}}
  #|{"textrec":{"s":[12,400,0,"22:30"],"r":[0,1,7.2421875,106,1,1,7.2421875,106,2,1,3.533203125,107,3,1,7.494140625,108,4,1,7.55859375,109]}}
  #|{"textrec":{"m":[12,400,0],"r":[11.6015625,2.53125,17,11.6015625,2.53125,0]}}
  #|{"textrec":{"s":[15,400,0,"小说-e2e.txt"],"r":[0,1,14.883268482490273,110,1,1,14.883268482490273,111,2,1,6.8408203125,112,3,1,8.3349609375,113,4,1,8.78173828125,114,5,1,8.29833984375,113,6,1,4.072265625,115,7,1,5.068359375,116,8,1,7.6318359375,117,9,1,5.21484375,116]}}
  #|{"textrec":{"s":[12,400,0,"36 KB · 22:30"],"r":[0,1,7.5234375,108,1,1,7.640625,118,2,1,3.375,-1,3,1,7.904296875,119,4,1,7.88671875,120,5,1,3.375,-1,6,1,5.754933455713626,121,7,1,3.375,-1,8,1,7.2421875,106,9,1,7.2421875,106,10,1,3.533203125,107,11,1,7.494140625,108,12,1,7.55859375,109]}}
  #|{"textrec":{"s":[15,400,0,"说明.txt"],"r":[0,1,14.883268482490273,111,1,1,14.883268482490273,122,2,1,4.072265625,115,3,1,5.068359375,116,4,1,7.6318359375,117,5,1,5.21484375,116]}}
  #|{"textrec":{"s":[12,400,0,"43 B · 22:30"],"r":[0,1,7.72265625,123,1,1,7.5234375,108,2,1,3.375,-1,3,1,7.88671875,120,4,1,3.375,-1,5,1,5.754933455713626,121,6,1,3.375,-1,7,1,7.2421875,106,8,1,7.2421875,106,9,1,3.533203125,107,10,1,7.494140625,108,11,1,7.55859375,109]}}
  #|{"textrec":{"g":93,"r":[981,0,18,18,-1,-15,0]}}
  #|{"textrec":{"g":94,"r":[1000,0,18,18,-1,-15,0]}}
  #|{"textrec":{"g":95,"r":[1019,0,7,12,-1,-11,0]}}
  #|{"textrec":{"g":96,"r":[1027,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":97,"r":[1043,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":98,"r":[1059,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":99,"r":[1075,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":100,"r":[1091,0,4,5,1,-7,0]}}
  #|{"textrec":{"g":101,"r":[1096,0,9,12,-1,-11,0]}}
  #|{"textrec":{"ib":["b17c2fa67cbec771",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"ib":["275a1f2a0cb12622",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"g":102,"r":[1106,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":103,"r":[1123,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":104,"r":[1141,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":105,"r":[1158,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":106,"r":[1175,0,9,11,-1,-10,0]}}
  #|{"textrec":{"g":107,"r":[1185,0,4,9,0,-7,0]}}
  #|{"textrec":{"g":108,"r":[1190,0,9,12,-1,-10,0]}}
  #|{"textrec":{"g":109,"r":[1200,0,9,12,-1,-10,0]}}
  #|{"textrec":{"g":110,"r":[1210,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":111,"r":[1228,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":112,"r":[1246,0,7,4,0,-6,0]}}
  #|{"textrec":{"g":113,"r":[1254,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":114,"r":[1265,0,10,13,0,-12,0]}}
  #|{"textrec":{"g":115,"r":[1276,0,5,5,0,-3,0]}}
  #|{"textrec":{"g":116,"r":[1282,0,7,13,-1,-11,0]}}
  #|{"textrec":{"g":117,"r":[1290,0,10,10,-1,-9,0]}}
  #|{"textrec":{"g":118,"r":[1301,0,9,12,-1,-10,0]}}
  #|{"textrec":{"g":119,"r":[1311,0,9,11,0,-10,0]}}
  #|{"textrec":{"g":120,"r":[1321,0,9,11,0,-10,0]}}
  #|{"textrec":{"g":121,"r":[1331,0,5,5,0,-7,0]}}
  #|{"textrec":{"g":122,"r":[1337,0,15,16,0,-13,0]}}
  #|{"textrec":{"g":123,"r":[1353,0,10,11,-1,-10,0]}}
  #|{"textrec":{"g":50,"r":[1364,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":86,"r":[1376,0,11,14,0,-13,0]}}
  #|{"textrec":{"g":87,"r":[1388,0,8,5,0,-7,0]}}
  #|{"textrec":{"g":88,"r":[1397,0,7,14,0,-13,0]}}
  #|{"textrec":{"g":89,"r":[1405,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":90,"r":[1417,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":91,"r":[1429,0,12,15,-1,-13,0]}}
  #|{"textrec":{"g":92,"r":[1442,0,12,15,-1,-13,0]}}
  #|{"textrec":{"ib":["0e910fb4d25445a3",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"ib":["b3685975cd23abc3",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["ddfdc2820df8a676",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"s":[16,600,0,"已选 1 项"],"r":[0,1,15.875486381322958,124,1,1,15.875486381322958,125,2,1,3.95001220703125,-1,3,1,7.594245910644531,88,4,1,3.95001220703125,-1,5,1,15.875486381322958,126]}}
  #|{"textrec":{"s":[17,400,0,"取消"],"r":[0,1,16.851167315175097,127,1,1,16.851167315175097,128]}}
  #|{"textrec":{"s":[15,400,0,"全选"],"r":[0,1,14.883268482490273,24,1,1,14.883268482490273,129]}}
  #|{"textrec":{"g":124,"r":[1455,0,16,17,0,-14,0]}}
  #|{"textrec":{"g":125,"r":[1472,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":126,"r":[1490,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":127,"r":[1509,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":128,"r":[1528,0,18,18,-1,-15,0]}}
  #|{"textrec":{"g":129,"r":[1547,0,16,16,-1,-13,0]}}
  #|{"textrec":{"ib":["d2e044956ae472e7",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"s":[17,700,0,"子文件夹"],"r":[0,1,16.851167315175097,130,1,1,16.851167315175097,131,2,1,16.851167315175097,132,3,1,16.851167315175097,133]}}
  #|{"textrec":{"m":[17,700,0],"r":[16.435546875,3.5859375,24,16.435546875,3.5859375,0]}}
  #|{"textrec":{"s":[15,400,0,"重命名"],"r":[0,1,14.883268482490273,134,1,1,14.883268482490273,135,2,1,14.883268482490273,136]}}
  #|{"textrec":{"s":[15,400,0,"下载为 zip"],"r":[0,1,14.883268482490273,137,1,1,14.883268482490273,138,2,1,14.883268482490273,139,3,1,3.984375,-1,4,1,7.8515625,140,5,1,3.4716796875,141,6,1,8.920898437499993,142]}}
  #|{"textrec":{"s":[15,400,0,"复制路径"],"r":[0,1,14.883268482490273,143,1,1,14.883268482490273,144,2,1,14.883268482490273,145,3,1,14.883268482490273,146]}}
  #|{"textrec":{"s":[15,400,0,"删除"],"r":[0,1,14.883268482490273,147,1,1,14.883268482490273,148]}}
  #|{"textrec":{"g":130,"r":[1564,0,18,18,-1,-15,0]}}
  #|{"textrec":{"g":131,"r":[1583,0,19,18,-1,-15,0]}}
  #|{"textrec":{"g":132,"r":[1603,0,18,18,-1,-15,0]}}
  #|{"textrec":{"g":133,"r":[1622,0,18,18,-1,-15,0]}}
  #|{"textrec":{"g":134,"r":[1641,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":135,"r":[1658,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":136,"r":[1675,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":137,"r":[1691,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":138,"r":[1708,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":139,"r":[1725,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":140,"r":[1741,0,9,10,0,-9,0]}}
  #|{"textrec":{"g":141,"r":[1751,0,5,14,-1,-13,0]}}
  #|{"textrec":{"g":142,"r":[1757,0,10,14,0,-10,0]}}
  #|{"textrec":{"g":143,"r":[1768,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":144,"r":[1785,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":145,"r":[1802,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":146,"r":[1820,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":147,"r":[1838,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":148,"r":[1855,0,16,16,0,-13,0]}}
  #|{"textrec":{"ib":["e51cacbaf3e3367d",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["5586d6bf44ec35db",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["9a47fa114a34d016",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["0c818ea1c0c4e805",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"s":[14,400,0,"正在下载「子文件夹.zip」"],"r":[0,1,13.891050583657588,149,1,1,13.891050583657588,150,2,1,13.891050583657588,151,3,1,20.891050583657588,152,4,1,5.066147859922182,153,5,1,13.891050583657588,154,6,1,13.891050583657588,155,7,1,13.891050583657588,156,8,1,13.891050583657588,157,9,1,4.005859375,158,10,1,7.396484375,159,11,1,3.30859375,160,12,1,8.39453125,161,13,1,7.127107652399474,162]}}
  #|{"textrec":{"s":[11,600,0,"0%"],"r":[0,1,7.374134063720703,163,1,1,11.01141881942749,164]}}
  #|{"textrec":{"m":[11,600,0],"r":[10.634765625,2.3203125,16,10.634765625,2.3203125,0]}}
  #|{"textrec":{"g":163,"r":[1872,0,9,11,-1,-9,0]}}
  #|{"textrec":{"g":164,"r":[1882,0,13,11,-1,-9,0]}}
  #|{"textrec":{"g":149,"r":[1896,0,15,14,-1,-12,0]}}
  #|{"textrec":{"g":150,"r":[1912,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":151,"r":[1928,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":152,"r":[1944,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":153,"r":[1960,0,7,12,-1.333333333333333,-13,0]}}
  #|{"textrec":{"g":154,"r":[1968,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":155,"r":[1984,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":156,"r":[2001,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":157,"r":[2018,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":158,"r":[2034,0,4,5,0,-3,0]}}
  #|{"textrec":{"g":159,"r":[0,20,9,10,-1,-9,0]}}
  #|{"textrec":{"g":160,"r":[10,20,5,13,-1,-12,0]}}
  #|{"textrec":{"g":161,"r":[16,20,9,13,0,-9,0]}}
  #|{"textrec":{"g":162,"r":[26,20,7,11,-1,-8,0]}}
  #|{"textrec":{"s":[14,400,0,"已保存到「下载」"],"r":[0,1,13.891050583657588,165,1,1,13.891050583657588,166,2,1,13.891050583657588,167,3,1,20.891050583657588,168,4,1,5.066147859922182,153,5,1,13.891050583657588,151,6,1,13.891050583657588,152,7,1,7.127107652399474,162]}}
  #|{"textrec":{"g":165,"r":[34,20,14,14,0,-12,0]}}
  #|{"textrec":{"g":166,"r":[49,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":167,"r":[66,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":168,"r":[82,20,15,16,-1,-13,0]}}
