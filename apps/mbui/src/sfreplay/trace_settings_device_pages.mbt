// e2e/traces/settings-device-pages.trace, made by scripts/trace.py from 01-settings_device_pages.log: not edited by hand.

///|
/// What the app and its core said in the run, a line each.
pub let trace_settings_device_pages : String =
  #|{"env":{"MBUI_CLOUD":"http://127.0.0.1:18787","MBUI_CORE_ACCOUNT":"{\"sub\":\"alice\",\"email\":\"alice@example.test\",\"name\":\"Name of alice\",\"picture\":\"\",\"access\":\"-\",\"refresh\":\"-\",\"accessExpires\":1792610226}"}}
  #|{"out":{"id":1,"call":"client.device","params":{"client":"still.fail mbui","app":"desktop","userAgent":"Macintosh; Mac OS X"}},"w":1792609928020.78}
  #|{"in":{"id":1,"ok":null},"w":1792609928100.122}
  #|{"out":{"id":2,"subscribe":{"topic":"accounts"},"keyed":true},"w":1792609928100.144}
  #|{"out":{"id":3,"subscribe":{"topic":"prefs"},"keyed":true},"w":1792609928100.153}
  #|{"step":"# written by scripts/rerecord.sh from its test (src/sfreplay/emit.mbt): not edited by hand","w":1792609928101.696}
  #|{"step":"timeout 90000","w":1792609928101.703}
  #|{"step":"answered client.device","w":1792609928101.705}
  #|{"step":"answered client.focus","w":1792609928119.394}
  #|{"in":{"id":2,"value":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""}]},"w":1792609928185.778}
  #|{"in":{"id":3,"value":{"onlyMine":false,"onlyWatching":false,"onlyDecisions":false,"listFilter":{},"appearance":"system","rowPicture":"auto","absoluteTime":false,"lang":"zh","keys":{},"lastChat":{},"openChat":{},"chatTabs":{},"dropFiles":{},"driveViews":{},"filesTabs":{},"driveFavorites":{},"resume":{},"stationUpdatesDismissed":{},"device":{"app":"desktop","phone":false,"handoff":false},"reader":{"size":18,"line":1.7,"margin":22,"face":"sans","indent":true,"paper":"follow"},"rails":{},"bars":{"sets":[["chats","files","profiles","stations"],["decisions","usage","connects","archive"]],"current":0},"barsBy":{},"fonts":{},"faces":{"ui":{"id":"","name":"","mono":false,"family":"","files":[],"bytes":0},"text":{"id":"","name":"","mono":false,"family":"","files":[],"bytes":0},"code":{"id":"","name":"","mono":true,"family":"","files":[],"bytes":0},"list":[{"id":"inter","name":"Inter","mono":false,"family":"SF Inter","css":"http://127.0.0.1:18787/releases/fonts/inter/4.001/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/inter/4.001/var.ttf.gz","bytes":457818,"sha256":"29160a80ff49ddcab2c97711247e08b1fab27a484a329ce8b813d820dc559031"}],"preview":"http://127.0.0.1:18787/releases/fonts/inter/4.001/preview-194fa287.ttf","bytes":457818},{"id":"noto-sans-sc","name":"思源黑体","mono":false,"family":"SF Noto Sans SC","css":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/var.ttf.gz","bytes":11276563,"sha256":"a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da"}],"preview":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/preview-f0494178.ttf","bytes":11276563},{"id":"noto-serif-sc","name":"思源宋体","mono":false,"family":"SF Noto Serif SC","css":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/var.ttf.gz","bytes":15454579,"sha256":"050080d9255a86808f2945bffac582b31ef32bc36411ce29563b4961670c66f9"}],"preview":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/preview-001bbedf.ttf","bytes":15454579},{"id":"lxgw-wenkai","name":"霞鹜文楷","mono":false,"family":"SF LXGW WenKai","css":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/font.css","files":[{"weight":400,"url":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/400.ttf.gz","bytes":12904482,"sha256":"2d73eea94ad808999d90c0000c239a84a33b09d4bc6ab6c5b8bbf1eda8a7fc8b"},{"weight":500,"url":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/500.ttf.gz","bytes":13272430,"sha256":"f4b8a34d1f838fe411540cb7c97b1c384ac9738a876c4104500bc42508b2312a"}],"preview":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/preview-d3505af4.ttf","bytes":26176912},{"id":"jetbrains-mono","name":"JetBrains Mono","mono":true,"family":"SF JetBrains Mono","css":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/var.ttf.gz","bytes":90579,"sha256":"48715a42ec242c21e9f02692891e147d022299a52e48d5e413e1a942193ffeda"}],"preview":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/preview-ee73078f.ttf","bytes":90579},{"id":"fira-code","name":"Fira Code","mono":true,"family":"SF Fira Code","css":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/var.ttf.gz","bytes":137151,"sha256":"9335b082b3c7850d98a64b584f3417f65355f3471278bb5eeb8c6c0e8657aeeb"}],"preview":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/preview-555be27a.ttf","bytes":137151},{"id":"maple-mono","name":"Maple Mono","mono":true,"family":"SF Maple Mono CN","css":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/font.css","files":[{"weight":400,"url":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/400.ttf.gz","bytes":8352545,"sha256":"0fcc5139bfd5ab14ff989bb7dfd5236d0cafc10e60b9828569e6883613ab4085"},{"weight":600,"url":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/600.ttf.gz","bytes":8438132,"sha256":"96ed7ae26ee7c50b02b2d2b2bc0f1a0cbabe45ae5d6e6abf6678e2177c415677"}],"preview":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/preview-cffdf246.ttf","bytes":16790677}]}}},"w":1792609928185.815}
  #|{"out":{"id":4,"subscribe":{"topic":"workspaces"},"keyed":true},"w":1792609928185.862}
  #|{"out":{"id":5,"subscribe":{"topic":"status"},"keyed":true},"w":1792609928185.871}
  #|{"in":{"id":4,"value":[{"account":{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""},"workspaces":[{"id":"01M5FY1BMWAA22GSZHSE6SRTC0","name":"Dev","role":"owner","created_at":1792609922,"stations":1,"members":1,"relays":[],"time":{"created_at":{"past":true,"at":1792609922000,"ago":"刚刚","full":"10/22 03:12:02","until":"1 分钟内"}}}],"invitations":[],"relay_url":"http://127.0.0.1:18740","loaded":true,"beta":true}]},"w":1792609928202.469}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792609928202.487}
  #|{"out":{"id":6,"subscribe":{"topic":"lock","workspace":"01M5FY1BMWAA22GSZHSE6SRTC0"},"keyed":true},"w":1792609928202.527}
  #|{"out":{"id":7,"subscribe":{"topic":"chats","scope":"01M5FY1BMWAA22GSZHSE6SRTC0","mine":false},"keyed":true},"w":1792609928202.539}
  #|{"out":{"id":8,"subscribe":{"topic":"changelog"},"keyed":true},"w":1792609928202.545}
  #|{"out":{"id":9,"subscribe":{"topic":"workspaceMarks","workspace":"01M5FY1BMWAA22GSZHSE6SRTC0"},"keyed":true},"w":1792609928202.668}
  #|{"out":{"id":10,"subscribe":{"topic":"status","workspace":"01M5FY1BMWAA22GSZHSE6SRTC0"},"keyed":true},"w":1792609928202.708}
  #|{"out":{"id":11,"subscribe":{"topic":"lockPrompts"},"keyed":true},"w":1792609928207.697}
  #|{"out":{"id":12,"call":"client.focus","params":{"visible":true,"focused":true,"workspace":"01M5FY1BMWAA22GSZHSE6SRTC0"}},"w":1792609928210.263}
  #|{"out":{"id":13,"subscribe":{"topic":"notify"},"keyed":true},"w":1792609928210.271}
  #|{"out":{"id":14,"subscribe":{"topic":"notify","workspace":"01M5FY1BMWAA22GSZHSE6SRTC0"},"keyed":true},"w":1792609928210.28}
  #|{"in":{"id":6,"value":{"available":true,"locked":false,"notice":true,"role":"owner","manages":true,"owner":true,"canSign":true,"signs":false,"me":{"device":"cf722c7447914c976b65c4ff0db240c593eb1dd6c90e428a09854d630a16d952","code":"28A-RET","kind":"app","confirmed":false,"waiting":false,"asked":false},"signers":0,"members":[],"stations":[{"id":"60784447a43cf425fa0bf3f95b8e7a6f8c81dd77c68895f940ef0af4dc53c77e","name":"studio","version":"0.1.0","online":true,"protected":false}],"protected":0,"requests":[],"renew":[],"attention":0}},"w":1792609928232.22}
  #|{"in":{"id":7,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"stations":[{"station":"01M5FY1BMWAA22GSZHSE6SRTC0/60784447a43cf425fa0bf3f95b8e7a6f8c81dd77c68895f940ef0af4dc53c77e","id":"60784447a43cf425fa0bf3f95b8e7a6f8c81dd77c68895f940ef0af4dc53c77e","name":"studio","state":"online"}],"loading":false,"days":[{"daysAgo":0,"at":1792609926760,"label":"今天","items":[{"id":"ember:c-c4725f5a4e","session":"ember:c-c4725f5a4e","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","agents":[{"key":"ember:c-c4725f5a4e","runtime":"claude","process":"warm","pending":0,"lastTurn":{"id":"de361ecf-5be5-4051-9c72-d1d3721c7976","kind":"input","outcome":"completed","declared":"final","ending":"all_done","need":"answered the question that was asked","startedAt":1792609926693,"endedAt":1792609926763},"agentText":"默认模型","statusText":"已完成：answered the question that was asked"}],"last":{"seq":2,"authorKind":"agent","author":"ember:c-c4725f5a4e","text":"你好，我是测试用的 agent","createdAt":1792609926760,"by":{"kind":"agent","name":"agent","mine":false,"runtime":"claude","label":"agent"},"preview":"你好，我是测试用的 agent","time":{"createdAt":{"at":1792609926760,"ago":"刚刚","full":"10/22 03:12:06","until":"1 分钟内","past":true}}},"unread":true,"mine":true,"lastActiveAt":1792609926760,"station":"01M5FY1BMWAA22GSZHSE6SRTC0/60784447a43cf425fa0bf3f95b8e7a6f8c81dd77c68895f940ef0af4dc53c77e","stationName":"studio","time":{"lastActiveAt":{"at":1792609926760,"ago":"刚刚","full":"10/22 03:12:06","until":"1 分钟内","past":true}},"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"peopleText":"你 发起","clientKey":"new:chat-0c3540d99ba8e2bbfe","pinned":false,"tone":"done"}]}],"trouble":null,"members":1,"leading":"agents","glyph":{"online":1,"dim":0,"connecting":0,"failing":0,"working":0,"summary":"studio","label":"1 台 station，1 台在线"},"note":{"reading":false,"text":null,"failing":[],"empty":false}}},"w":1792609928232.267}
  #|{"in":{"id":8,"value":{"app":"desktop","tabs":[{"part":"desktop","label":"桌面","days":[]},{"part":"web","label":"网页","days":[]},{"part":"android","label":"安卓","days":[]},{"part":"station","label":"Station","days":[]},{"part":"cloud","label":"云端","days":[]}],"loading":false}},"w":1792609928232.29}
  #|{"in":{"id":9,"value":{"workspaces":{"01M5FY1BMWAA22GSZHSE6SRTC0":{"alert":0,"unread":1,"tone":"done","label":"1 个有新消息","badge":0,"items":[],"mineTone":"done"}},"badge":0,"badgeCounts":"attention","badgeKinds":{"on":true,"wait":true,"failed":true,"done":false,"message":false}}},"w":1792609928232.297}
  #|{"in":{"id":10,"value":{"items":[]}},"w":1792609928232.301}
  #|{"in":{"id":11,"value":{"pairing":[]}},"w":1792609928232.307}
  #|{"in":{"id":12,"ok":null},"w":1792609928232.309}
  #|{"in":{"id":13,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792609928232.315}
  #|{"in":{"id":14,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792609928232.322}
  #|{"out":{"id":15,"subscribe":{"topic":"longJobs","scope":"01M5FY1BMWAA22GSZHSE6SRTC0"},"keyed":true},"w":1792609928232.376}
  #|{"out":{"id":16,"call":"notify.permission","params":{"state":"unknown"}},"w":1792609928234.87}
  #|{"in":{"id":15,"value":{"groups":[]}},"w":1792609928248.87}
  #|{"in":{"id":16,"ok":null},"w":1792609928248.896}
  #|{"step":"answered notify.permission","w":1792609928249.171}
  #|{"step":"tap icon:settings","w":1792609928265.764}
  #|{"step":"tap icon:settings","acted":true,"w":1792609928265.775}
  #|{"out":{"id":17,"subscribe":{"topic":"workspace","workspace":"01M5FY1BMWAA22GSZHSE6SRTC0"},"keyed":true},"w":1792609928282.376}
  #|{"out":{"id":18,"subscribe":{"topic":"stations","scope":"01M5FY1BMWAA22GSZHSE6SRTC0"},"keyed":true},"w":1792609928282.388}
  #|{"out":{"id":19,"subscribe":{"topic":"connects","scope":"01M5FY1BMWAA22GSZHSE6SRTC0","mine":false},"keyed":true},"w":1792609928282.394}
  #|{"out":{"id":20,"subscribe":{"topic":"vaults","workspace":"01M5FY1BMWAA22GSZHSE6SRTC0"},"keyed":true},"w":1792609928282.4}
  #|{"out":{"id":21,"subscribe":{"topic":"doing"},"keyed":true},"w":1792609928285.166}
  #|{"out":{"id":22,"call":"cache.usage","params":{}},"w":1792609928286.047}
  #|{"step":"answered cache.usage","w":1792609928286.255}
  #|{"in":{"id":17,"value":{"id":"01M5FY1BMWAA22GSZHSE6SRTC0","name":"Dev","role":"owner","created_at":1792609922,"members":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":"https://example.test/p.png","role":"owner","added_at":1792609922}],"stations":[{"id":"60784447a43cf425fa0bf3f95b8e7a6f8c81dd77c68895f940ef0af4dc53c77e","name":"studio","emoji":null,"icon":null,"enrolled_at":1792609923,"enrolled_by":"alice","last_seen":1792609926,"version":"0.1.0","time":{"last_seen":{"past":true,"at":1792609926000,"ago":"刚刚","full":"10/22 03:12:06","until":"1 分钟内"}}}],"invitations":[],"added":[],"relays":[],"lock":null,"lock_requests":0,"time":{"created_at":{"past":true,"at":1792609922000,"ago":"刚刚","full":"10/22 03:12:02","until":"1 分钟内"}}}},"w":1792609928298.842}
  #|{"in":{"id":18,"value":[{"station":"01M5FY1BMWAA22GSZHSE6SRTC0/60784447a43cf425fa0bf3f95b8e7a6f8c81dd77c68895f940ef0af4dc53c77e","id":"60784447a43cf425fa0bf3f95b8e7a6f8c81dd77c68895f940ef0af4dc53c77e","name":"studio","summary":"正在连接","face":"idle","line":"在线","online":true,"reconnecting":false,"lastSeen":1792609926,"version":"0.1.0","link":{"state":"online"},"runtimes":[{"runtime":"claude","models":["claude-sonnet-5-5"]}],"models":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792609926675,"time":{"checkedAt":{"at":1792609926675,"ago":"刚刚","full":"10/22 03:12:06","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"overview":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null,"summaryText":"最近 7 天检查了 0 个 chat","changeText":null}},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","email":"alice@example.test","name":"Name of alice","sub":"alice","role":"owner","workspace":"01M5FY1BMWAA22GSZHSE6SRTC0","device":"cf722c7447914c976b65c4ff0db240c593eb1dd6c90e428a09854d630a16d952"},"connects":[],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792609926551,"time":{"checkedAt":{"at":1792609926551,"ago":"刚刚","full":"10/22 03:12:06","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792609926675,"time":{"checkedAt":{"at":1792609926675,"ago":"刚刚","full":"10/22 03:12:06","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"modelsReading":false,"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]}],"processes":[],"counts":{"sessions":1,"running":0,"warm":1},"mesh":{"state":"running","origin":"http://127.0.0.1:18787","station":"60784447a43cf425fa0bf3f95b8e7a6f8c81dd77c68895f940ef0af4dc53c77e","workspace":"Dev","workspaceId":"01M5FY1BMWAA22GSZHSE6SRTC0","name":"studio"},"slackUsers":[],"slackTeams":[],"slackApps":[],"feishuRegistrations":[],"disk":{"freeBytes":28392304640,"totalBytes":245107195904},"logins":[],"machineLogins":[],"sharing":true,"consoleSignIn":true,"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"google","name":"Google Gemini","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xai","name":"xAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"mistral","name":"Mistral","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"deepseek","name":"DeepSeek","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen","name":"Qwen","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai","name":"Kimi","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"kimi-code","name":"Kimi Code","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai","name":"Z.ai","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax","name":"MiniMax","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ant-ling","name":"Ant Ling","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"jev","name":"Jev","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen-cn","name":"Qwen (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"openrouter","name":"OpenRouter","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"opencode","name":"OpenCode Zen","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"groq","name":"Groq","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"together","name":"Together AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"fireworks","name":"Fireworks","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cerebras","name":"Cerebras","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"huggingface","name":"Hugging Face","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"nvidia","name":"NVIDIA","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"baseten","name":"Baseten","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ollama","name":"Ollama","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"custom","name":"Custom","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""}],"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792609924136},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.306","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792609924136},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-icon/apps/e2e-local/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792609924136},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-icon/apps/e2e-local/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792609924136},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","latest":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-icon/apps/e2e-local/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792609924136},{"id":"cursor","name":"Cursor","installed":false,"latest":"1.0.40","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792609924136},{"id":"devin","name":"Devin","installed":true,"version":"3000.11.92","latest":"3000.11.92","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-icon/apps/e2e-local/ember/station/test/fake/devin，不是用 Devin 的安装脚本装的，需在该机器上手动更新","state":"idle","checkedAt":1792609924136}],"processesText":"没有运行中的 agent 进程","agentEnv":[],"drive":{"roots":[],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false}},"betaOffered":false,"way":{"path":"直连","via":"direct"},"time":{"lastSeen":{"at":1792609926000,"ago":"刚刚","full":"10/22 03:12:06","until":"1 分钟内","past":true}},"joined":false}]},"w":1792609928298.953}
  #|{"in":{"id":19,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"items":[],"wait":{"reading":false,"text":null,"failing":[],"empty":true}}},"w":1792609928299.029}
  #|{"in":{"id":20,"value":{"available":true,"locked":false,"canSign":false,"setUp":false,"vaults":[{"id":"plain","name":"个人","owner":"alice","ownerName":"Name of alice","mine":true,"members":[{"sub":"alice","name":"Name of alice"}],"station":"60784447a43cf425fa0bf3f95b8e7a6f8c81dd77c68895f940ef0af4dc53c77e","stationName":"studio","items":0,"devices":0,"open":true,"keyed":true,"missing":0,"recoverable":false}],"requests":[],"refused":[{"station":"60784447a43cf425fa0bf3f95b8e7a6f8c81dd77c68895f940ef0af4dc53c77e","name":"studio","code":"vault_needs_lock"}],"plain":true}},"w":1792609928299.037}
  #|{"in":{"id":21,"value":{"doing":[]}},"w":1792609928299.044}
  #|{"in":{"id":22,"ok":{"chats":[{"station":"01M5FY1BMWAA22GSZHSE6SRTC0/60784447a43cf425fa0bf3f95b8e7a6f8c81dd77c68895f940ef0af4dc53c77e","thread":1,"title":null,"sessions":["ember:c-c4725f5a4e"],"bytes":558}]}},"w":1792609928299.047}
  #|{"step":"wait 299","w":1792609928315.984}
  #|{"in":{"id":18,"delta":[{"path":[0,"host"],"set":{"hostname":"3720-Mac-mini-1","os":"macOS 27.0.1","arch":"arm64","cpus":10,"cpuModel":"Apple M4","load":0.2,"cpuBusy":0.14,"uptimeSec":89290,"memory":{"totalBytes":17179869184,"usedBytes":10135322624,"swapUsedBytes":216793088},"disk":{"path":"/tmp/mbe2e-C/data","totalBytes":245107195904,"freeBytes":28392185856},"emberRssBytes":161791480,"checkedAt":1792609928322,"summary":"10 核 · 16 GB","line":"macOS 27.0.1 · 10 核 · 16 GB · 已运行 1 天","facts":["3720-Mac-mini-1","macOS 27.0.1","arm64 · 10 核","已运行 1 天 0 小时"],"meters":[{"label":"CPU","short":"CPU","percent":14,"left":86,"level":"ok","value":"14%","remaining":"空闲 86%","big":"86","unit":"%","title":"CPU 空闲","total":"负载 2.0","note":"负载 2.0 · Apple M4"},{"label":"内存","short":"内存","percent":59,"left":41,"level":"ok","value":"9.4 GB / 16.0 GB","remaining":"剩 6.6 G","big":"6.6","unit":"GB","title":"内存剩","total":"共 16 GB","note":"swap 0.2 GB"},{"label":"磁盘","short":"磁盘","percent":88,"left":12,"level":"amber","value":"剩余 26.4 GB / 228 GB","remaining":"剩 26.4 G","big":"26.4","unit":"GB","title":"磁盘剩","total":"共 228 GB"}],"identity":"Apple M4 · 16 GB · macOS 27.0.1","details":[{"label":"主机名","value":"3720-Mac-mini-1"},{"label":"芯片","value":"Apple M4 · 10 核 · arm64"},{"label":"已运行","value":"1 天 0 小时"},{"label":"still.fail","value":"进程占用 154 MB"}],"usage":"内存 9.4 GB / 16.0 GB · 磁盘 剩余 26.4 GB / 228 GB","emberText":"still.fail 154 MB"}},{"path":[0,"line"],"set":"Apple M4"},{"path":[0,"summary"],"set":"空闲 · Apple M4 · 16 GB · macOS 27.0.1"}]},"w":1792609928382.242}
  #|{"step":"now wheelat 500 Workspace","w":1792609928616.575}
  #|{"step":"now wheelat 500 Workspace","acted":true,"w":1792609928616.653}
  #|{"step":"wait 900","w":1792609928642.088}
  #|{"step":"now tap =下方栏","w":1792609929549.858}
  #|{"step":"now tap =下方栏","acted":true,"w":1792609929549.937}
  #|{"step":"wait 300","w":1792609929591.721}
  #|{"step":"now until 第 1 栏","w":1792609929920.028}
  #|{"step":"tapxy 345 199","w":1792609929920.097}
  #|{"step":"tapxy 345 199","acted":true,"w":1792609929920.127}
  #|{"out":{"id":23,"call":"prefs.set","params":{"barsBy":{"01M5FY1BMWAA22GSZHSE6SRTC0":{"sets":[["chats","files","profiles"],["decisions","usage","connects","archive"]],"current":0}}}},"w":1792609929935.937}
  #|{"step":"answered prefs.set","w":1792609929936.471}
  #|{"in":{"id":23,"ok":null},"w":1792609929952.338}
  #|{"step":"tap =添加","w":1792609929969.699}
  #|{"step":"tap =添加","acted":true,"w":1792609929969.741}
  #|{"step":"wait 1438","w":1792609929986.599}
  #|{"in":{"id":3,"delta":[{"path":["barsBy","01M5FY1BMWAA22GSZHSE6SRTC0"],"set":{"sets":[["chats","files","profiles"],["decisions","usage","connects","archive"]],"current":0}}]},"w":1792609930118.977}
  #|{"step":"now until 添加到第 1 栏","w":1792609931436.567}
  #|{"step":"tap =用量","w":1792609931436.609}
  #|{"step":"tap =用量","acted":true,"w":1792609931436.635}
  #|{"out":{"id":24,"call":"prefs.set","params":{"barsBy":{"01M5FY1BMWAA22GSZHSE6SRTC0":{"sets":[["chats","files","profiles","usage"],["decisions","usage","connects","archive"]],"current":0}}}},"w":1792609931453.346}
  #|{"step":"answered prefs.set","w":1792609931454.458}
  #|{"in":{"id":24,"ok":null},"w":1792609931469.003}
  #|{"step":"wait 1438","w":1792609931486.799}
  #|{"in":{"id":3,"delta":[{"path":["barsBy","01M5FY1BMWAA22GSZHSE6SRTC0","sets",0],"append":["usage"]}]},"w":1792609931668.94}
  #|{"step":"now back","w":1792609932953.119}
  #|{"step":"now back","acted":true,"w":1792609932953.17}
  #|{"step":"wait 300","w":1792609932970.361}
  #|{"step":"now tap =本机缓存","w":1792609933286.833}
  #|{"step":"now tap =本机缓存","acted":true,"w":1792609933286.903}
  #|{"step":"wait 300","w":1792609933308.73}
  #|{"step":"now until chat #1","w":1792609933619.254}
  #|{"step":"back","w":1792609933619.266}
  #|{"step":"back","acted":true,"w":1792609933619.272}
  #|{"step":"wait 300","w":1792609933635.833}
  #|{"step":"now answered cache.usage","w":1792609933936.206}
  #|{"out":{"id":25,"call":"cache.usage","params":{}},"w":1792609933953.474}
  #|{"in":{"id":25,"ok":{"chats":[{"station":"01M5FY1BMWAA22GSZHSE6SRTC0/60784447a43cf425fa0bf3f95b8e7a6f8c81dd77c68895f940ef0af4dc53c77e","thread":1,"title":null,"sessions":["ember:c-c4725f5a4e"],"bytes":558}]}},"w":1792609933968.958}
  #|{"step":"tap =更新日志","w":1792609933986.516}
  #|{"step":"tap =更新日志","acted":true,"w":1792609933986.567}
  #|{"step":"wait 300","w":1792609934007.778}
  #|{"step":"now back","w":1792609934319.665}
  #|{"step":"now back","acted":true,"w":1792609934319.713}
  #|{"step":"wait 300","w":1792609934336.373}
  #|{"step":"now wheelat -500 =本机缓存","w":1792609934653.758}
  #|{"step":"now wheelat -500 =本机缓存","acted":true,"w":1792609934653.833}
  #|{"step":"wait 900","w":1792609934670.207}
  #|{"step":"now tap =用量","w":1792609935586.559}
  #|{"step":"now tap =用量","acted":true,"w":1792609935586.635}
  #|{"out":{"id":26,"subscribe":{"topic":"usage","scope":"01M5FY1BMWAA22GSZHSE6SRTC0","days":7},"keyed":true},"w":1792609935602.755}
  #|{"step":"wait 300","w":1792609935605.596}
  #|{"in":{"id":26,"value":{"days":7,"wait":{"reading":true,"text":"正在从 studio 读取","failing":[],"empty":false},"empty":true,"tiles":[{"label":"折合费用","value":"$0","sub":"按 API 标准单价估算"},{"label":"模型调用","value":"0 次","sub":"日均 0 次"},{"label":"输入 token","value":"0","sub":"缓存命中 0%"},{"label":"输出 token","value":"0","sub":"平均每次 0"}],"series":[],"daily":[{"day":"2026-10-16","label":"10/16","today":false,"cost":0,"costText":"$0","calls":0,"callsText":"0 次调用","parts":[],"partsText":[]},{"day":"2026-10-17","label":"10/17","today":false,"cost":0,"costText":"$0","calls":0,"callsText":"0 次调用","parts":[],"partsText":[]},{"day":"2026-10-18","label":"10/18","today":false,"cost":0,"costText":"$0","calls":0,"callsText":"0 次调用","parts":[],"partsText":[]},{"day":"2026-10-19","label":"10/19","today":false,"cost":0,"costText":"$0","calls":0,"callsText":"0 次调用","parts":[],"partsText":[]},{"day":"2026-10-20","label":"10/20","today":false,"cost":0,"costText":"$0","calls":0,"callsText":"0 次调用","parts":[],"partsText":[]},{"day":"2026-10-21","label":"10/21","today":false,"cost":0,"costText":"$0","calls":0,"callsText":"0 次调用","parts":[],"partsText":[]},{"day":"2026-10-22","label":"10/22","today":true,"cost":0,"costText":"$0","calls":0,"callsText":"0 次调用","parts":[],"partsText":[]}],"max":0,"lists":[{"key":"people","title":"按人","items":[]},{"key":"chats","title":"按对话","items":[]},{"key":"profiles","title":"按账号","items":[]},{"key":"models","title":"按模型","items":[]}],"notes":[],"basis":"订阅账号不按 token 收费；费用按 API 标准单价估算，不含长上下文和服务等级等加价","prices":[{"station":"studio","note":"station 尚未提供价目表，请更新 station 后查看","rows":[]}]}},"w":1792609935619.009}
  #|{"in":{"id":26,"delta":[{"path":["prices",0,"note"],"set":"美元 / 100 万 token · 各类 token × 单价后相加；Claude fast ×2。GPT 按标准短上下文估算，仅记录输入、缓存读取和输出。GPT 价目核对于 2026-10-02，Claude 沿用 2026-09 价目"},{"path":["wait","empty"],"set":true},{"path":["wait","reading"],"set":false},{"path":["wait","text"],"set":null}]},"w":1792609935818.986}
  #|{"step":"now tap 查看价目表","w":1792609935936.285}
  #|{"step":"now tap 查看价目表","acted":true,"w":1792609935936.359}
  #|{"step":"wait 299","w":1792609935958.993}
  #|{"step":"now until =价目表","w":1792609936269.409}
  #|{"step":"","w":1792609936269.464}
  #|{"textrec":{"m":[15,400,0],"r":[14.501953125,3.1640625,21,14.501953125,3.1640625,0]}}
  #|{"textrec":{"ib":["bfd9b0d6dc602826",12668,64],"r":[56,56,56,56]}}
  #|{"textrec":{"s":[13,400,0,"正在读取你的 workspace"],"r":[0,1,12.898832684824903,0,1,1,12.898832684824903,1,2,1,12.898832684824903,2,3,1,12.898832684824903,3,4,1,12.898832684824896,4,5,1,12.898832684824896,5,6,1,3.580078125,-1,7,1,9.8642578125,6,8,1,7.4775390625,7,9,1,4.875,8,10,1,6.85546875,9,11,1,6.6015625,10,12,1,7.8583984375,11,13,1,7.0966796875,12,14,1,7.1982421875,13,15,1,7.3505859375,14]}}
  #|{"textrec":{"m":[13,400,0],"r":[12.568359375,2.7421875,18,12.568359375,2.7421875,0]}}
  #|{"textrec":{"s":[24,700,0,"Dev"],"r":[0,1,17.075823068618774,15,1,1,13.365240812301636,16,2,1,12.759063005447388,17]}}
  #|{"textrec":{"m":[24,700,0],"r":[23.203125,5.0625,34,20.638916015625,3.361083984375,0]}}
  #|{"textrec":{"g":15,"r":[0,0,18,19,0,-18,0]}}
  #|{"textrec":{"g":16,"r":[19,0,15,16,-1,-14,0]}}
  #|{"textrec":{"g":17,"r":[35,0,15,15,-1,-14,0]}}
  #|{"textrec":{"ib":["02698e60df92657e",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"ib":["bef2954d97ce1d9f",6508,64],"r":[40,40,40,40]}}
  #|{"textrec":{"ib":["fdb526ba00f881f4",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["1d51432b25a425eb",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"ib":["a7ccae3554fe46cf",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["31d8ec32aedeae00",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["c8ac90bf691295f0",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"s":[15,400,0,"搜索全部内容"],"r":[0,1,14.883268482490273,18,1,1,14.883268482490273,19,2,1,14.883268482490273,20,3,1,14.883268482490273,21,4,1,14.88326848249028,22,5,1,14.88326848249028,23]}}
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
  #|{"textrec":{"s":[17,400,0,"会话"],"r":[0,1,16.851167315175097,63,1,1,16.851167315175097,64]}}
  #|{"textrec":{"m":[17,400,0],"r":[16.435546875,3.5859375,24,16.435546875,3.5859375,0]}}
  #|{"textrec":{"s":[32,700,8,"设置"],"r":[0,1,30.345864661654133,65,1,1,30.345864661654133,66]}}
  #|{"textrec":{"m":[32,700,0],"r":[30.9375,6.75,45,27.5185546875,4.4814453125,0]}}
  #|{"textrec":{"s":[16,700,0,"Name of alice"],"r":[0,1,11.9765625,67,1,1,9.12109375,68,2,1,14.6015625,69,3,1,9.30078125,70,4,1,3.8125,-1,5,1,9.6015625,71,6,1,6.21484375,72,7,1,3.8125,-1,8,1,9.12109375,68,9,1,4.40625,73,10,1,4.28125,74,11,1,9.0859375,75,12,1,9.30078125,70]}}
  #|{"textrec":{"m":[16,700,0],"r":[15.46875,3.375,23,15.46875,3.375,0]}}
  #|{"textrec":{"s":[13,400,0,"alice@example.test"],"r":[0,1,7.0966796875,12,1,1,3.2119140625,76,2,1,3.1357421875,77,3,1,7.1982421875,13,4,1,7.3505859375,14,5,1,11.857421875,78,6,1,7.2236328125,14,7,1,6.6142578125,79,8,1,7.0966796875,12,9,1,11.2353515625,80,10,1,7.8583984375,11,11,1,3.2119140625,76,12,1,7.3505859375,14,13,1,3.65625,81,14,1,4.471923828125,82,15,1,7.302978515625,14,16,1,6.69677734375,10,17,1,4.61474609375,82]}}
  #|{"textrec":{"s":[23,600,0,"N"],"r":[0,1,16.576080499507952,83]}}
  #|{"textrec":{"m":[23,600,0],"r":[22.236328125,4.8515625,33,19.778961181640625,3.221038818359375,0]}}
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
  #|{"textrec":{"s":[15,400,0,"服务条款"],"r":[0,1,14.883268482490273,168,1,1,14.883268482490273,169,2,1,14.883268482490273,170,3,1,14.883268482490273,171]}}
  #|{"textrec":{"s":[15,400,0,"隐私政策"],"r":[0,1,14.883268482490273,172,1,1,14.883268482490273,173,2,1,14.883268482490273,174,3,1,14.883268482490273,112]}}
  #|{"textrec":{"s":[15,600,0,"Dev · 你是Owner"],"r":[0,1,10.861195921897888,84,1,1,8.51915180683136,85,2,1,8.18638265132904,86,3,1,3.761730194091797,-1,4,1,7.186782927948599,175,5,1,3.761730194091797,-1,6,1,14.883268482490273,176,7,1,14.883268482490273,177,8,1,13.354362845420837,178,9,1,12.072962522506714,179,10,1,8.93320620059967,180,11,1,8.615586161613464,85,12,1,5.99338173866272,181]}}
  #|{"textrec":{"s":[14,400,0,"1 人"],"r":[0,1,6.34375,182,1,1,3.787109375,-1,2,1,13.891050583657588,183]}}
  #|{"textrec":{"s":[14,400,0,"0 条"],"r":[0,1,8.66796875,184,1,1,3.787109375,-1,2,1,13.891050583657588,185]}}
  #|{"textrec":{"s":[15,400,0,"密钥"],"r":[0,1,14.883268482490273,186,1,1,14.883268482490273,187]}}
  #|{"textrec":{"s":[14,400,0,"1/1 在线"],"r":[0,1,6.34375,182,1,1,4.115234375,188,2,1,6.34375,182,3,1,3.787109375,-1,4,1,13.891050583657588,189,5,1,13.891050583657588,190]}}
  #|{"textrec":{"s":[14,400,0,"0 个"],"r":[0,1,8.66796875,184,1,1,3.787109375,-1,2,1,13.891050583657588,191]}}
  #|{"textrec":{"s":[14,400,0,"1 个"],"r":[0,1,6.34375,182,1,1,3.787109375,-1,2,1,13.891050583657588,191]}}
  #|{"textrec":{"s":[14,400,0,"558 B"],"r":[0,1,8.50390625,192,1,1,8.50390625,192,2,1,8.791015625,193,3,1,3.787109375,-1,4,1,9.05078125,194]}}
  #|{"textrec":{"ib":["504a4df6beac534a",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["a1e7be43eb966606",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"g":63,"r":[666,0,18,18,-1,-15,0]}}
  #|{"textrec":{"g":64,"r":[685,0,19,18,-1,-15,0]}}
  #|{"textrec":{"g":65,"r":[705,0,31,31,0,-26,0]}}
  #|{"textrec":{"g":66,"r":[737,0,30,29,0,-25,0]}}
  #|{"textrec":{"g":84,"r":[768,0,12,13,0,-12,0]}}
  #|{"textrec":{"g":85,"r":[781,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":86,"r":[793,0,11,11,-1,-10,0]}}
  #|{"textrec":{"g":175,"r":[805,0,5,5,1,-8,0]}}
  #|{"textrec":{"g":176,"r":[811,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":177,"r":[828,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":178,"r":[845,0,13,14,-1,-12,0]}}
  #|{"textrec":{"g":179,"r":[859,0,14,11,-1,-10,0]}}
  #|{"textrec":{"g":180,"r":[874,0,10,11,0,-10,0]}}
  #|{"textrec":{"g":181,"r":[885,0,7,11,0,-10,0]}}
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
  #|{"textrec":{"g":186,"r":[1012,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":187,"r":[1029,0,16,16,-1,-13,0]}}
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
  #|{"textrec":{"g":182,"r":[1763,0,7,12,-1,-11,0]}}
  #|{"textrec":{"g":188,"r":[1771,0,7,16,-1,-12,0]}}
  #|{"textrec":{"g":189,"r":[1779,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":190,"r":[1795,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":120,"r":[1812,0,16,15,-1,-12,0]}}
  #|{"textrec":{"g":121,"r":[1829,0,15,16,0,-13,0]}}
  #|{"textrec":{"g":122,"r":[1845,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":123,"r":[1861,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":192,"r":[1878,0,9,13,0,-11,0]}}
  #|{"textrec":{"g":193,"r":[1888,0,11,14,-1,-12,0]}}
  #|{"textrec":{"g":194,"r":[1900,0,10,12,0,-11,0]}}
  #|{"textrec":{"g":183,"r":[1911,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":184,"r":[1928,0,10,14,-1,-12,0]}}
  #|{"textrec":{"g":185,"r":[1939,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":191,"r":[1956,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":126,"r":[1973,0,9,13,0,-12,0]}}
  #|{"textrec":{"g":127,"r":[1983,0,16,16,-1,-13,0]}}
  #|{"textrec":{"ib":["b3685975cd23abc3",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"g":135,"r":[2000,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":136,"r":[2017,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":137,"r":[0,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":138,"r":[16,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":139,"r":[32,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":140,"r":[48,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":141,"r":[64,32,6,6,0,-3,0]}}
  #|{"textrec":{"g":142,"r":[71,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":143,"r":[86,32,15,14,-1,-11,0]}}
  #|{"textrec":{"g":144,"r":[102,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":145,"r":[118,32,15,13,-1,-11,0]}}
  #|{"textrec":{"g":146,"r":[134,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":147,"r":[148,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":148,"r":[164,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":149,"r":[180,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":150,"r":[195,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":151,"r":[211,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":152,"r":[226,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":153,"r":[242,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":154,"r":[258,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":155,"r":[274,32,14,14,-1,-12,0]}}
  #|{"textrec":{"g":4,"r":[289,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":160,"r":[304,32,5,5,0,-3,0]}}
  #|{"textrec":{"g":161,"r":[310,32,13,11,0,-10,0]}}
  #|{"textrec":{"g":162,"r":[324,32,10,15,0,-13,0]}}
  #|{"textrec":{"g":163,"r":[335,32,9,11,0,-9,0]}}
  #|{"textrec":{"g":164,"r":[345,32,11,14,-1,-12,0]}}
  #|{"textrec":{"g":165,"r":[357,32,8,13,-1,-12,0]}}
  #|{"textrec":{"g":156,"r":[366,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":157,"r":[384,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":158,"r":[401,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":159,"r":[419,32,17,17,-1,-14,0]}}
  #|{"textrec":{"g":166,"r":[437,32,12,16,1,-13,0]}}
  #|{"textrec":{"g":167,"r":[450,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":168,"r":[467,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":169,"r":[485,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":170,"r":[503,32,16,17,-1,-14,0]}}
  #|{"textrec":{"g":171,"r":[520,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":172,"r":[538,32,16,17,0,-14,0]}}
  #|{"textrec":{"g":173,"r":[555,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":174,"r":[572,32,17,16,-1,-13,0]}}
  #|{"textrec":{"s":[17,400,0,"设置"],"r":[0,1,16.851167315175097,195,1,1,16.851167315175097,196]}}
  #|{"textrec":{"s":[32,700,8,"下方栏"],"r":[0,1,30.345864661654133,197,1,1,30.345864661654133,198,2,1,30.345864661654133,199]}}
  #|{"textrec":{"s":[13,400,0,"可以设置多栏，每栏最多 4 个位置，底部显示当前栏。有多栏时，在栏上向上滑动可切换。按住图标左右拖动可调整顺序。"],"r":[0,1,12.898832684824903,200,1,1,12.898832684824903,201,2,1,12.898832684824903,202,3,1,12.898832684824903,203,4,1,12.898832684824896,204,5,1,12.898832684824896,205,6,1,13.075875486381321,206,7,1,12.89883268482491,207,8,1,12.898832684824896,205,9,1,12.898832684824896,208,10,1,12.898832684824896,204,11,1,3.580078125,-1,12,1,8.2900390625,209,13,1,3.580078125,-1,14,1,12.898832684824896,210,15,1,12.898832684824896,211,16,1,12.898832684824896,203,17,1,13.075875486381335,206,18,1,12.898832684824896,212,19,1,12.898832684824896,213,20,1,12.898832684824896,214,21,1,12.898832684824896,215,22,1,12.898832684824924,216,23,1,12.898832684824924,217,24,1,12.898832684824924,205,25,1,13.075875486381335,218,26,1,12.898832684824924,149,27,1,12.898832684824924,204,28,1,12.898832684824924,205,29,1,12.898832684824924,153,30,1,13.075875486381335,206,31,1,12.898832684824924,1,32,1,12.898832684824924,205,33,1,12.898832684824924,219,34,1,12.898832684824924,220,35,1,12.898832684824924,219,36,1,12.898832684824924,221,37,1,12.898832684824924,222,38,1,12.898832684824924,200,39,1,12.898832684824924,223,40,1,12.898832684824924,224,41,1,13.075875486381278,218,42,1,12.898832684824924,225,43,1,12.898832684824924,226,44,1,12.898832684824924,227,45,1,12.898832684824924,228,46,1,12.898832684824924,229,47,1,12.898832684824924,230,48,1,12.898832684824924,231,49,1,12.898832684824924,222,50,1,12.898832684824924,200,51,1,12.898832684824924,232,52,1,12.898832684824924,233,53,1,12.898832684824924,234,54,1,12.898832684824924,235,55,1,6.575875486381278,218]}}
  #|{"textrec":{"s":[13,600,0,"第 1 栏"],"r":[0,1,12.898832684824903,236,1,1,3.3871192932128906,-1,2,1,6.348059177398682,237,3,1,3.3871192932128906,-1,4,1,12.898832684824903,238]}}
  #|{"textrec":{"m":[13,600,0],"r":[12.568359375,2.7421875,18,12.568359375,2.7421875,0]}}
  #|{"textrec":{"s":[11,600,0,"当前"],"r":[0,1,10.93579766536965,239,1,1,10.93579766536965,240]}}
  #|{"textrec":{"m":[11,600,0],"r":[10.634765625,2.3203125,16,10.634765625,2.3203125,0]}}
  #|{"textrec":{"s":[13,400,0,"删除"],"r":[0,1,12.898832684824903,241,1,1,12.898832684824903,242]}}
  #|{"textrec":{"s":[12,400,0,"对话"],"r":[0,1,11.918287937743191,243,1,1,11.918287937743191,244]}}
  #|{"textrec":{"m":[12,400,0],"r":[11.6015625,2.53125,17,11.6015625,2.53125,0]}}
  #|{"textrec":{"s":[12,400,0,"文件"],"r":[0,1,11.918287937743191,245,1,1,11.918287937743191,246]}}
  #|{"textrec":{"s":[12,400,0,"Profile"],"r":[0,1,7.623046875,247,1,1,4.482421875,248,2,1,7.001953125,249,3,1,4.341796875,250,4,1,2.96484375,251,5,1,3.03515625,252,6,1,6.85546875,253]}}
  #|{"textrec":{"s":[12,400,0,"Station"],"r":[0,1,7.646484375,254,1,1,4.359375,255,2,1,6.62109375,256,3,1,4.359375,255,4,1,2.96484375,251,5,1,7.08984375,249,6,1,7.001953125,257]}}
  #|{"textrec":{"s":[13,600,0,"第 2 栏"],"r":[0,1,12.898832684824903,236,1,1,3.3871192932128906,-1,2,1,8.095149278640747,258,3,1,3.3871192932128906,-1,4,1,12.898832684824903,238]}}
  #|{"textrec":{"s":[13,400,0,"设为当前"],"r":[0,1,12.898832684824903,202,1,1,12.898832684824903,259,2,1,12.898832684824903,216,3,1,12.898832684824903,217]}}
  #|{"textrec":{"s":[12,400,0,"奏"],"r":[0,1,11.918287937743191,260]}}
  #|{"textrec":{"s":[12,400,0,"用量"],"r":[0,1,11.918287937743191,261,1,1,11.918287937743191,262]}}
  #|{"textrec":{"s":[12,400,0,"连接"],"r":[0,1,11.918287937743191,263,1,1,11.918287937743191,264]}}
  #|{"textrec":{"s":[12,400,0,"已归档"],"r":[0,1,11.918287937743191,265,1,1,11.918287937743191,266,2,1,11.918287937743195,267]}}
  #|{"textrec":{"s":[15,400,0,"新建栏"],"r":[0,1,14.883268482490273,159,1,1,14.883268482490273,268,2,1,14.883268482490273,130]}}
  #|{"textrec":{"s":[13,400,0,"删除到只剩一栏时，无法在栏上向上滑动"],"r":[0,1,12.898832684824903,241,1,1,12.898832684824903,242,2,1,12.898832684824903,269,3,1,12.898832684824903,270,4,1,12.898832684824896,271,5,1,12.898832684824896,272,6,1,12.898832684824896,205,7,1,12.898832684824896,153,8,1,13.075875486381321,206,9,1,12.89883268482491,273,10,1,12.898832684824896,274,11,1,12.898832684824896,1,12,1,12.898832684824896,205,13,1,12.898832684824896,219,14,1,12.898832684824896,220,15,1,12.898832684824896,219,16,1,12.898832684824896,221,17,1,12.898832684824896,222]}}
  #|{"textrec":{"g":195,"r":[590,32,19,18,-1,-15,0]}}
  #|{"textrec":{"g":196,"r":[610,32,18,17,-1,-14,0]}}
  #|{"textrec":{"g":197,"r":[629,32,30,30,0,-25,0]}}
  #|{"textrec":{"g":198,"r":[660,32,30,31,0,-26,0]}}
  #|{"textrec":{"g":199,"r":[691,32,31,31,-1,-26,0]}}
  #|{"textrec":{"g":200,"r":[723,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":201,"r":[738,32,14,15,0,-12,0]}}
  #|{"textrec":{"g":202,"r":[753,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":203,"r":[769,32,15,13,-1,-11,0]}}
  #|{"textrec":{"g":204,"r":[785,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":205,"r":[799,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":206,"r":[815,32,5,7,0,-3,0]}}
  #|{"textrec":{"g":207,"r":[821,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":208,"r":[837,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":209,"r":[852,32,10,12,-1,-11,0]}}
  #|{"textrec":{"g":210,"r":[863,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":211,"r":[879,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":212,"r":[895,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":213,"r":[911,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":214,"r":[926,32,14,13,-1,-11,0]}}
  #|{"textrec":{"g":215,"r":[941,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":216,"r":[956,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":217,"r":[970,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":218,"r":[986,32,6,6,0,-3,0]}}
  #|{"textrec":{"g":1,"r":[993,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":219,"r":[1008,32,14,14,-1,-12,0]}}
  #|{"textrec":{"g":220,"r":[1023,32,13,15,0,-12,0]}}
  #|{"textrec":{"g":221,"r":[1037,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":222,"r":[1052,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":223,"r":[1067,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":224,"r":[1082,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":225,"r":[1098,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":226,"r":[1114,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":227,"r":[1130,32,13,14,0,-11,0]}}
  #|{"textrec":{"g":228,"r":[1144,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":229,"r":[1160,32,14,14,-1,-12,0]}}
  #|{"textrec":{"g":230,"r":[1175,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":231,"r":[1190,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":232,"r":[1206,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":233,"r":[1221,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":234,"r":[1237,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":235,"r":[1253,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":236,"r":[1268,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":237,"r":[1284,32,7,12,-1,-11,0]}}
  #|{"textrec":{"g":238,"r":[1292,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":258,"r":[1308,32,10,12,-1,-11,0]}}
  #|{"textrec":{"g":241,"r":[1319,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":242,"r":[1334,32,14,15,0,-12,0]}}
  #|{"textrec":{"g":269,"r":[1349,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":270,"r":[1364,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":271,"r":[1379,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":272,"r":[1394,32,15,4,-1,-7,0]}}
  #|{"textrec":{"g":273,"r":[1410,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":274,"r":[1425,32,15,15,-1,-12,0]}}
  #|{"textrec":{"ib":["3884ec9f83a49286",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"g":243,"r":[1441,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":244,"r":[1456,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":260,"r":[1471,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":268,"r":[1486,32,16,16,-1,-13,0]}}
  #|{"textrec":{"ib":["56bb520611ebcb9b",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["59d67194788e1d50",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["83b02002cdf98bf6",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"g":239,"r":[1503,32,11,13,0,-10,0]}}
  #|{"textrec":{"g":240,"r":[1515,32,13,13,-1,-10,0]}}
  #|{"textrec":{"g":245,"r":[1529,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":246,"r":[1544,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":261,"r":[1559,32,13,14,-1,-11,0]}}
  #|{"textrec":{"g":262,"r":[1573,32,14,13,-1,-11,0]}}
  #|{"textrec":{"ib":["118284b9121e03f9",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["0e1f660116efa475",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"g":247,"r":[1588,32,8,11,0,-10,0]}}
  #|{"textrec":{"g":248,"r":[1597,32,7,9,-1,-8,0]}}
  #|{"textrec":{"g":249,"r":[1605,32,9,10,-1,-8,0]}}
  #|{"textrec":{"g":250,"r":[1615,32,6,11,-1,-10,0]}}
  #|{"textrec":{"g":251,"r":[1622,32,5,11,-1,-10,0]}}
  #|{"textrec":{"g":252,"r":[1628,32,4,11,0,-10,0]}}
  #|{"textrec":{"g":253,"r":[1633,32,9,10,-1,-8,0]}}
  #|{"textrec":{"g":263,"r":[1643,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":264,"r":[1658,32,14,14,-1,-11,0]}}
  #|{"textrec":{"ib":["1ddbc5816774da4d",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["42d30f74945d8af0",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"g":259,"r":[1673,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":254,"r":[1688,32,9,12,-1,-10,0]}}
  #|{"textrec":{"g":255,"r":[1698,32,6,11,-1,-9,0]}}
  #|{"textrec":{"g":256,"r":[1705,32,8,10,-1,-8,0]}}
  #|{"textrec":{"g":257,"r":[1714,32,9,9,-1,-8,0]}}
  #|{"textrec":{"g":265,"r":[1724,32,13,12,0,-10,0]}}
  #|{"textrec":{"g":266,"r":[1738,32,13,14,-1,-11,0]}}
  #|{"textrec":{"g":267,"r":[1752,32,14,14,-1,-11,0]}}
  #|{"textrec":{"ib":["7b1e099b1a8c58bf",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["a9172ef01835e6be",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"s":[12,400,0,"添加"],"r":[0,1,11.918287937743191,275,1,1,11.918287937743191,276]}}
  #|{"textrec":{"g":275,"r":[1767,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":276,"r":[1782,32,13,14,-1,-11,0]}}
  #|{"textrec":{"ib":["d3afa98d6d4238aa",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"s":[13,400,0,"还可添加 1 个"],"r":[0,1,12.898832684824903,277,1,1,12.898832684824903,200,2,1,12.898832684824903,278,3,1,12.898832684824903,279,4,1,3.580078125,-1,5,1,5.9541015625,280,6,1,3.580078125,-1,7,1,12.898832684824896,210]}}
  #|{"textrec":{"s":[17,700,0,"添加到第 1 栏"],"r":[0,1,16.851167315175097,281,1,1,16.851167315175097,282,2,1,16.851167315175097,283,3,1,16.851167315175097,284,4,1,3.951171875,-1,5,1,8.267578125,285,6,1,3.951171875,-1,7,1,16.851167315175104,286]}}
  #|{"textrec":{"m":[17,700,0],"r":[16.435546875,3.5859375,24,16.435546875,3.5859375,0]}}
  #|{"textrec":{"s":[15,400,0,"对话"],"r":[0,1,14.883268482490273,287,1,1,14.883268482490273,288]}}
  #|{"textrec":{"s":[12,400,0,"已在此栏"],"r":[0,1,11.918287937743191,265,1,1,11.918287937743191,289,2,1,11.918287937743195,290,3,1,11.918287937743187,291]}}
  #|{"textrec":{"s":[15,400,0,"奏"],"r":[0,1,14.883268482490273,292]}}
  #|{"textrec":{"s":[15,400,0,"文件"],"r":[0,1,14.883268482490273,293,1,1,14.883268482490273,294]}}
  #|{"textrec":{"s":[15,400,0,"已归档"],"r":[0,1,14.883268482490273,295,1,1,14.883268482490273,296,2,1,14.883268482490273,297]}}
  #|{"textrec":{"g":281,"r":[1796,32,19,18,-1,-15,0]}}
  #|{"textrec":{"g":282,"r":[1816,32,18,18,-1,-15,0]}}
  #|{"textrec":{"g":283,"r":[1835,32,18,18,-1,-15,0]}}
  #|{"textrec":{"g":284,"r":[1854,32,18,18,-1,-15,0]}}
  #|{"textrec":{"g":285,"r":[1873,32,8,14,0,-13,0]}}
  #|{"textrec":{"g":286,"r":[1882,32,18,18,-1,-15,0]}}
  #|{"textrec":{"g":277,"r":[1901,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":278,"r":[1917,32,15,15,-1,-12,0]}}
  #|{"textrec":{"g":279,"r":[1933,32,14,15,-1,-12,0]}}
  #|{"textrec":{"g":280,"r":[1948,32,7,12,-1,-11,0]}}
  #|{"textrec":{"g":287,"r":[1956,32,16,16,-1,-13,0]}}
  #|{"textrec":{"g":288,"r":[1973,32,17,16,-1,-13,0]}}
  #|{"textrec":{"g":289,"r":[1991,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":290,"r":[2006,32,14,13,-1,-11,0]}}
  #|{"textrec":{"g":291,"r":[2021,32,14,14,-1,-11,0]}}
  #|{"textrec":{"g":292,"r":[0,64,16,17,-1,-14,0]}}
  #|{"textrec":{"g":293,"r":[17,64,17,17,-1,-14,0]}}
  #|{"textrec":{"g":294,"r":[35,64,16,17,-1,-14,0]}}
  #|{"textrec":{"g":295,"r":[52,64,15,16,0,-13,0]}}
  #|{"textrec":{"g":296,"r":[68,64,16,16,-1,-13,0]}}
  #|{"textrec":{"g":297,"r":[85,64,16,16,-1,-13,0]}}
  #|{"textrec":{"s":[13,400,0,"已满"],"r":[0,1,12.898832684824903,298,1,1,12.898832684824903,299]}}
  #|{"textrec":{"g":298,"r":[102,64,13,13,0,-11,0]}}
  #|{"textrec":{"g":299,"r":[116,64,15,15,-1,-12,0]}}
  #|{"textrec":{"s":[32,700,8,"本机缓存"],"r":[0,1,30.345864661654133,300,1,1,30.345864661654133,301,2,1,30.345864661654133,302,3,1,30.345864661654133,303]}}
  #|{"textrec":{"s":[13,400,0,"此设备上缓存的聊天记录和打开过的文件，再次查看时无需重新下载。删除仅影响此设备，station 上的数据不受影响。"],"r":[0,1,12.898832684824903,304,1,1,12.898832684824903,202,2,1,12.898832684824903,305,3,1,12.898832684824903,219,4,1,12.898832684824896,306,5,1,12.898832684824896,307,6,1,12.898832684824896,5,7,1,12.898832684824896,308,8,1,12.898832684824896,309,9,1,12.898832684824896,310,10,1,12.898832684824896,311,11,1,12.898832684824896,312,12,1,12.898832684824896,313,13,1,12.898832684824896,314,14,1,12.898832684824896,315,15,1,12.898832684824896,5,16,1,12.898832684824896,316,17,1,12.898832684824896,317,18,1,13.075875486381335,206,19,1,12.898832684824896,318,20,1,12.898832684824924,319,21,1,12.898832684824924,320,22,1,12.898832684824924,321,23,1,12.898832684824924,153,24,1,12.898832684824924,273,25,1,12.898832684824924,142,26,1,12.898832684824924,322,27,1,12.898832684824924,150,28,1,12.898832684824924,323,29,1,12.898832684824924,324,30,1,13.075875486381335,218,31,1,12.898832684824924,241,32,1,12.898832684824924,242,33,1,12.898832684824924,325,34,1,12.898832684824924,326,35,1,12.898832684824924,327,36,1,12.898832684824924,304,37,1,12.898832684824924,202,38,1,12.898832684824924,305,39,1,11.775875486381267,206,40,1,6.69677734375,10,41,1,4.61474609375,82,42,1,7.0966796875,12,43,1,4.646484375,82,44,1,3.1357421875,77,45,1,7.6044921875,7,46,1,7.50927734375,328,47,1,3.580078125,-1,48,1,12.898832684824924,219,49,1,12.898832684824924,5,50,1,12.898832684824924,329,51,1,12.898832684824924,330,52,1,12.898832684824924,331,53,1,12.898832684824924,332,54,1,12.898832684824924,326,55,1,12.898832684824924,327,56,1,6.575875486381278,218]}}
  #|{"textrec":{"s":[15,600,0,"按 chat"],"r":[0,1,14.883268482490273,333,1,1,3.761730194091797,-1,2,1,8.423570394515991,334,3,1,9.00644838809967,335,4,1,8.40147078037262,336,5,1,5.683325529098511,337]}}
  #|{"textrec":{"s":[13,400,0,"共 558 B"],"r":[0,1,12.898832684824903,338,1,1,3.580078125,-1,2,1,7.9599609375,339,3,1,7.9599609375,339,4,1,8.2265625,340,5,1,3.580078125,-1,6,1,8.4677734375,341]}}
  #|{"textrec":{"s":[15,400,0,"chat #1"],"r":[0,1,8.1591796875,94,1,1,8.59130859375,342,2,1,8.0419921875,93,3,1,5.21484375,101,4,1,3.984375,-1,5,1,9.2138671875,343,6,1,6.7236328125,165]}}
  #|{"textrec":{"s":[13,400,0,"消息 558 B"],"r":[0,1,12.898832684824903,151,1,1,12.898832684824903,152,2,1,3.580078125,-1,3,1,7.9599609375,339,4,1,7.9599609375,339,5,1,8.2265625,340,6,1,3.580078125,-1,7,1,8.4677734375,341]}}
  #|{"textrec":{"s":[15,400,0,"全部清除"],"r":[0,1,14.883268482490273,20,1,1,14.883268482490273,21,2,1,14.883268482490273,344,3,1,14.883268482490273,345]}}
  #|{"textrec":{"g":300,"r":[132,64,32,31,-1,-26,0]}}
  #|{"textrec":{"g":301,"r":[165,64,32,31,-1,-26,0]}}
  #|{"textrec":{"g":302,"r":[198,64,32,31,-1,-26,0]}}
  #|{"textrec":{"g":303,"r":[231,64,31,31,-1,-26,0]}}
  #|{"textrec":{"g":304,"r":[263,64,15,14,-1,-12,0]}}
  #|{"textrec":{"g":305,"r":[279,64,15,15,-1,-12,0]}}
  #|{"textrec":{"g":306,"r":[295,64,15,15,-1,-12,0]}}
  #|{"textrec":{"g":307,"r":[311,64,15,15,-1,-12,0]}}
  #|{"textrec":{"g":5,"r":[327,64,13,15,0,-12,0]}}
  #|{"textrec":{"g":308,"r":[341,64,14,15,-1,-12,0]}}
  #|{"textrec":{"g":309,"r":[356,64,15,14,-1,-11,0]}}
  #|{"textrec":{"g":310,"r":[372,64,15,14,-1,-12,0]}}
  #|{"textrec":{"g":311,"r":[388,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":312,"r":[403,64,14,15,-1,-12,0]}}
  #|{"textrec":{"g":313,"r":[418,64,14,15,-1,-12,0]}}
  #|{"textrec":{"g":314,"r":[433,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":315,"r":[448,64,15,15,-1,-12,0]}}
  #|{"textrec":{"g":316,"r":[464,64,15,15,-1,-12,0]}}
  #|{"textrec":{"g":317,"r":[480,64,15,15,-1,-12,0]}}
  #|{"textrec":{"g":318,"r":[496,64,15,14,-1,-11,0]}}
  #|{"textrec":{"g":319,"r":[512,64,15,15,-1,-12,0]}}
  #|{"textrec":{"g":320,"r":[528,64,15,14,-1,-12,0]}}
  #|{"textrec":{"g":321,"r":[544,64,14,15,-1,-12,0]}}
  #|{"textrec":{"g":322,"r":[559,64,14,14,-1,-12,0]}}
  #|{"textrec":{"g":323,"r":[574,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":324,"r":[589,64,15,15,-1,-12,0]}}
  #|{"textrec":{"g":325,"r":[605,64,15,15,-1,-12,0]}}
  #|{"textrec":{"g":326,"r":[621,64,15,15,-1,-12,0]}}
  #|{"textrec":{"g":327,"r":[637,64,14,15,-1,-12,0]}}
  #|{"textrec":{"g":7,"r":[652,64,9,10,-1,-8,0]}}
  #|{"textrec":{"g":328,"r":[662,64,8,9,0,-8,0]}}
  #|{"textrec":{"g":329,"r":[671,64,15,15,-1,-12,0]}}
  #|{"textrec":{"g":330,"r":[687,64,15,15,-1,-12,0]}}
  #|{"textrec":{"g":331,"r":[703,64,15,14,-1,-11,0]}}
  #|{"textrec":{"g":332,"r":[719,64,14,15,-1,-12,0]}}
  #|{"textrec":{"g":333,"r":[734,64,17,17,-1,-14,0]}}
  #|{"textrec":{"g":334,"r":[752,64,11,12,-1,-10,0]}}
  #|{"textrec":{"g":335,"r":[764,64,10,14,0,-13,0]}}
  #|{"textrec":{"g":336,"r":[775,64,10,12,-1,-10,0]}}
  #|{"textrec":{"g":337,"r":[786,64,8,13,-1,-11,0]}}
  #|{"textrec":{"g":342,"r":[795,64,9,14,0,-13,0]}}
  #|{"textrec":{"g":343,"r":[805,64,12,13,-1,-12,0]}}
  #|{"textrec":{"g":339,"r":[818,64,10,13,-1,-11,0]}}
  #|{"textrec":{"g":340,"r":[829,64,10,13,-1,-11,0]}}
  #|{"textrec":{"g":341,"r":[840,64,9,12,0,-11,0]}}
  #|{"textrec":{"g":344,"r":[850,64,16,16,-1,-13,0]}}
  #|{"textrec":{"g":345,"r":[867,64,16,16,0,-13,0]}}
  #|{"textrec":{"g":338,"r":[884,64,14,15,-1,-12,0]}}
  #|{"textrec":{"s":[32,700,8,"更新日志"],"r":[0,1,30.345864661654133,346,1,1,30.345864661654133,347,2,1,30.345864661654133,348,3,1,30.345864661654133,349]}}
  #|{"textrec":{"s":[14,400,0,"桌面"],"r":[0,1,13.891050583657588,350,1,1,13.891050583657588,351]}}
  #|{"textrec":{"s":[14,400,0,"网页"],"r":[0,1,13.891050583657588,352,1,1,13.891050583657588,353]}}
  #|{"textrec":{"s":[14,400,0,"安卓"],"r":[0,1,13.891050583657588,354,1,1,13.891050583657588,355]}}
  #|{"textrec":{"s":[14,400,0,"Station"],"r":[0,1,8.7705078125,356,1,1,4.935546875,61,2,1,7.57421875,57,3,1,4.935546875,61,4,1,3.30859375,357,5,1,8.12109375,358,6,1,8.0185546875,60]}}
  #|{"textrec":{"s":[14,400,0,"云端"],"r":[0,1,13.891050583657588,359,1,1,13.891050583657588,360]}}
  #|{"textrec":{"s":[14,400,0,"暂无更新记录"],"r":[0,1,13.891050583657588,361,1,1,13.891050583657588,362,2,1,13.891050583657588,363,3,1,13.891050583657588,364,4,1,13.891050583657588,365,5,1,13.891050583657588,366]}}
  #|{"textrec":{"g":346,"r":[899,64,31,30,0,-25,0]}}
  #|{"textrec":{"g":347,"r":[931,64,31,32,-1,-27,0]}}
  #|{"textrec":{"g":348,"r":[963,64,23,30,4,-25,0]}}
  #|{"textrec":{"g":349,"r":[987,64,31,30,0,-26,0]}}
  #|{"textrec":{"g":361,"r":[1019,64,14,16,0,-13,0]}}
  #|{"textrec":{"g":362,"r":[1034,64,15,15,-1,-12,0]}}
  #|{"textrec":{"g":363,"r":[1050,64,16,15,-1,-12,0]}}
  #|{"textrec":{"g":364,"r":[1067,64,16,16,-1,-13,0]}}
  #|{"textrec":{"g":365,"r":[1084,64,16,15,-1,-13,0]}}
  #|{"textrec":{"g":366,"r":[1101,64,15,15,-1,-12,0]}}
  #|{"textrec":{"g":350,"r":[1117,64,15,16,-1,-13,0]}}
  #|{"textrec":{"g":351,"r":[1133,64,15,15,-1,-12,0]}}
  #|{"textrec":{"g":352,"r":[1149,64,14,15,0,-12,0]}}
  #|{"textrec":{"g":353,"r":[1164,64,15,15,-1,-12,0]}}
  #|{"textrec":{"g":354,"r":[1180,64,15,16,-1,-13,0]}}
  #|{"textrec":{"g":355,"r":[1196,64,15,16,-1,-13,0]}}
  #|{"textrec":{"g":356,"r":[1212,64,11,14,-1,-12,0]}}
  #|{"textrec":{"g":357,"r":[1224,64,5,13,-1,-12,0]}}
  #|{"textrec":{"g":358,"r":[1230,64,10,11,-1,-9,0]}}
  #|{"textrec":{"g":359,"r":[1241,64,15,15,-1,-12,0]}}
  #|{"textrec":{"g":360,"r":[1257,64,15,16,-1,-13,0]}}
  #|{"textrec":{"s":[16,600,0,"用量"],"r":[0,1,15.875486381322958,43,1,1,15.875486381322958,367]}}
  #|{"textrec":{"s":[13,400,0,"7 天"],"r":[0,1,7.3251953125,368,1,1,3.580078125,-1,2,1,12.898832684824903,309]}}
  #|{"textrec":{"s":[13,400,0,"30 天"],"r":[0,1,8.07421875,369,1,1,8.1123046875,370,2,1,3.580078125,-1,3,1,12.898832684824903,309]}}
  #|{"textrec":{"s":[12,400,0,"折合费用"],"r":[0,1,11.918287937743191,371,1,1,11.918287937743191,372,2,1,11.918287937743195,373,3,1,11.918287937743187,261]}}
  #|{"textrec":{"s":[22,700,0,"$0"],"r":[0,1,14.22948682308197,374,1,1,14.468548357486725,375]}}
  #|{"textrec":{"m":[22,700,0],"r":[21.26953125,4.640625,31,18.91900634765625,3.08099365234375,0]}}
  #|{"textrec":{"s":[12,400,0,"查看价目表 →"],"r":[0,1,11.918287937743191,376,1,1,11.918287937743191,377,2,1,11.918287937743195,378,3,1,11.918287937743187,379,4,1,11.918287937743187,380,5,1,3.375,-1,6,1,10.869140625,381]}}
  #|{"textrec":{"s":[12,400,0,"模型调用"],"r":[0,1,11.918287937743191,382,1,1,11.918287937743191,383,2,1,11.918287937743195,384,3,1,11.918287937743187,261]}}
  #|{"textrec":{"s":[22,700,0,"0 次"],"r":[0,1,14.468548357486725,375,1,1,4.717369616031647,-1,2,1,20.94548872180451,385]}}
  #|{"textrec":{"s":[12,400,0,"日均 0 次"],"r":[0,1,11.918287937743191,386,1,1,11.918287937743191,387,2,1,3.375,-1,3,1,7.55859375,388,4,1,3.375,-1,5,1,11.918287937743195,389]}}
  #|{"textrec":{"s":[12,400,0,"输入 token"],"r":[0,1,11.918287937743191,390,1,1,11.918287937743191,391,2,1,3.375,-1,3,1,4.3154296875,255,4,1,7.0458984375,249,5,1,6.369140625,392,6,1,6.708984375,253,7,1,7.001953125,257]}}
  #|{"textrec":{"s":[22,700,0,"0"],"r":[0,1,14.468548357486725,375]}}
  #|{"textrec":{"s":[12,400,0,"缓存命中 0%"],"r":[0,1,11.918287937743191,393,1,1,11.918287937743191,394,2,1,11.918287937743195,395,3,1,11.918287937743187,396,4,1,3.375,-1,5,1,7.55859375,388,6,1,11.103515625,397]}}
  #|{"textrec":{"s":[12,400,0,"输出 token"],"r":[0,1,11.918287937743191,390,1,1,11.918287937743191,398,2,1,3.375,-1,3,1,4.3154296875,255,4,1,7.0458984375,249,5,1,6.369140625,392,6,1,6.708984375,253,7,1,7.001953125,257]}}
  #|{"textrec":{"s":[12,400,0,"平均每次 0"],"r":[0,1,11.918287937743191,399,1,1,11.918287937743191,387,2,1,11.918287937743195,400,3,1,11.918287937743187,389,4,1,3.375,-1,5,1,7.55859375,388]}}
  #|{"textrec":{"s":[12,400,0,"订阅账号不按 token 收费；费用按 API 标准单价估算，不含长上下文和服务等级等加价"],"r":[0,1,11.918287937743191,401,1,1,11.918287937743191,402,2,1,11.918287937743195,403,3,1,11.918287937743187,404,4,1,11.918287937743187,405,5,1,11.918287937743187,406,6,1,3.375,-1,7,1,4.3154296875,255,8,1,7.0458984375,249,9,1,6.369140625,392,10,1,6.708984375,253,11,1,7.001953125,257,12,1,3.375,-1,13,1,11.918287937743187,407,14,1,11.918287937743202,373,15,1,12.081712062256798,408,16,1,11.918287937743202,373,17,1,11.918287937743202,261,18,1,11.918287937743202,406,19,1,3.375,-1,20,1,8.0859375,409,21,1,7.623046875,247,22,1,3.2109375,410,23,1,3.375,-1,24,1,11.918287937743202,411,25,1,11.918287937743202,412,26,1,11.918287937743202,413,27,1,11.918287937743202,378,28,1,11.918287937743202,414,29,1,11.918287937743173,415,30,1,12.081712062256827,416,31,1,11.918287937743173,405,32,1,11.918287937743173,417,33,1,11.918287937743173,418,34,1,11.918287937743173,419,35,1,11.918287937743173,420,36,1,11.918287937743173,245,37,1,11.918287937743173,421,38,1,11.918287937743173,422,39,1,11.918287937743173,423,40,1,11.918287937743173,424,41,1,11.918287937743173,425,42,1,11.918287937743173,424,43,1,11.918287937743173,276,44,1,11.918287937743173,378]}}
  #|{"textrec":{"g":371,"r":[1273,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":372,"r":[1288,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":373,"r":[1303,64,13,14,-1,-11,0]}}
  #|{"textrec":{"g":374,"r":[1317,64,15,22,0,-19,0]}}
  #|{"textrec":{"g":375,"r":[1333,64,15,19,0,-17,0]}}
  #|{"textrec":{"g":376,"r":[1349,64,14,13,-1,-11,0]}}
  #|{"textrec":{"g":377,"r":[1364,64,13,14,-1,-11,0]}}
  #|{"textrec":{"g":378,"r":[1378,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":379,"r":[1393,64,11,13,0,-10,0]}}
  #|{"textrec":{"g":380,"r":[1405,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":381,"r":[1420,64,11,10,0,-9,0]}}
  #|{"textrec":{"g":390,"r":[1432,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":391,"r":[1447,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":392,"r":[1462,64,8,11,0,-10,0]}}
  #|{"textrec":{"g":393,"r":[1471,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":394,"r":[1486,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":395,"r":[1501,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":396,"r":[1516,64,12,14,0,-11,0]}}
  #|{"textrec":{"g":388,"r":[1529,64,9,12,-1,-10,0]}}
  #|{"textrec":{"g":397,"r":[1539,64,13,12,-1,-10,0]}}
  #|{"textrec":{"g":401,"r":[1553,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":402,"r":[1568,64,12,14,0,-11,0]}}
  #|{"textrec":{"g":403,"r":[1581,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":404,"r":[1596,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":405,"r":[1611,64,14,13,-1,-10,0]}}
  #|{"textrec":{"g":406,"r":[1626,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":407,"r":[1641,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":408,"r":[1656,64,4,11,1,-9,0]}}
  #|{"textrec":{"g":409,"r":[1661,64,10,11,-1,-10,0]}}
  #|{"textrec":{"g":410,"r":[1672,64,4,11,0,-10,0]}}
  #|{"textrec":{"g":411,"r":[1677,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":412,"r":[1692,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":413,"r":[1707,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":414,"r":[1722,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":415,"r":[1737,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":416,"r":[1752,64,5,6,0,-3,0]}}
  #|{"textrec":{"g":417,"r":[1758,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":418,"r":[1773,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":419,"r":[1788,64,14,13,-1,-11,0]}}
  #|{"textrec":{"g":420,"r":[1803,64,14,13,-1,-10,0]}}
  #|{"textrec":{"g":421,"r":[1818,64,13,14,-1,-11,0]}}
  #|{"textrec":{"g":422,"r":[1832,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":423,"r":[1847,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":424,"r":[1862,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":425,"r":[1877,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":367,"r":[1892,64,17,17,-1,-14,0]}}
  #|{"textrec":{"g":382,"r":[1910,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":383,"r":[1925,64,13,13,-1,-11,0]}}
  #|{"textrec":{"g":384,"r":[1939,64,13,14,-1,-11,0]}}
  #|{"textrec":{"g":385,"r":[1953,64,23,23,-1,-19,0]}}
  #|{"textrec":{"g":386,"r":[1977,64,10,14,1,-11,0]}}
  #|{"textrec":{"g":387,"r":[1988,64,13,14,-1,-11,0]}}
  #|{"textrec":{"g":389,"r":[2002,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":398,"r":[2017,64,12,14,0,-11,0]}}
  #|{"textrec":{"g":399,"r":[2030,64,14,14,-1,-11,0]}}
  #|{"textrec":{"g":400,"r":[0,97,14,14,-1,-11,0]}}
  #|{"textrec":{"g":368,"r":[15,97,9,12,-1,-11,0]}}
  #|{"textrec":{"g":369,"r":[25,97,10,13,-1,-11,0]}}
  #|{"textrec":{"g":370,"r":[36,97,10,13,-1,-11,0]}}
  #|{"textrec":{"s":[14,400,0,"这段时间没有用量"],"r":[0,1,13.891050583657588,426,1,1,13.891050583657588,427,2,1,13.891050583657588,428,3,1,13.891050583657588,429,4,1,13.891050583657588,430,5,1,13.891050583657588,431,6,1,13.891050583657588,55,7,1,13.891050583657588,432]}}
  #|{"textrec":{"s":[13,400,0,"agent 调用模型消耗的 token，按 API 价格折算为费用"],"r":[0,1,7.0966796875,12,1,1,7.845703125,433,2,1,7.3505859375,14,3,1,7.50927734375,328,4,1,4.646484375,82,5,1,3.580078125,-1,6,1,12.898832684824903,232,7,1,12.898832684824903,434,8,1,12.89883268482491,435,9,1,12.898832684824896,436,10,1,12.898832684824896,151,11,1,12.898832684824896,437,12,1,12.898832684824896,5,13,1,3.580078125,-1,14,1,4.598876953125,82,15,1,7.556884765625,7,16,1,6.82373046875,9,17,1,7.19189453125,14,18,1,7.50927734375,328,19,1,13.075875486381335,206,20,1,12.898832684824896,225,21,1,3.580078125,-1,22,1,8.68359375,438,23,1,8.18212890625,439,24,1,3.40234375,440,25,1,3.580078125,-1,26,1,12.898832684824896,441,27,1,12.898832684824896,442,28,1,12.898832684824896,443,29,1,12.898832684824924,444,30,1,12.898832684824924,259,31,1,12.898832684824924,445,32,1,12.898832684824924,434]}}
  #|{"textrec":{"g":426,"r":[47,97,16,16,-1,-13,0]}}
  #|{"textrec":{"g":427,"r":[64,97,16,16,-1,-13,0]}}
  #|{"textrec":{"g":428,"r":[81,97,15,16,0,-13,0]}}
  #|{"textrec":{"g":429,"r":[97,97,14,16,0,-13,0]}}
  #|{"textrec":{"g":430,"r":[112,97,16,15,-1,-12,0]}}
  #|{"textrec":{"g":431,"r":[129,97,15,16,-1,-13,0]}}
  #|{"textrec":{"g":432,"r":[145,97,15,15,-1,-12,0]}}
  #|{"textrec":{"g":433,"r":[161,97,9,12,-1,-8,0]}}
  #|{"textrec":{"g":434,"r":[171,97,14,14,-1,-11,0]}}
  #|{"textrec":{"g":435,"r":[186,97,15,15,-1,-12,0]}}
  #|{"textrec":{"g":436,"r":[202,97,14,14,-1,-12,0]}}
  #|{"textrec":{"g":437,"r":[217,97,15,15,-1,-12,0]}}
  #|{"textrec":{"g":9,"r":[233,97,8,12,0,-11,0]}}
  #|{"textrec":{"g":438,"r":[242,97,11,12,-1,-11,0]}}
  #|{"textrec":{"g":439,"r":[254,97,9,12,0,-11,0]}}
  #|{"textrec":{"g":440,"r":[264,97,4,12,0,-11,0]}}
  #|{"textrec":{"g":441,"r":[269,97,15,15,-1,-12,0]}}
  #|{"textrec":{"g":442,"r":[285,97,15,15,-1,-12,0]}}
  #|{"textrec":{"g":443,"r":[301,97,14,15,-1,-12,0]}}
  #|{"textrec":{"g":444,"r":[316,97,14,15,-1,-12,0]}}
  #|{"textrec":{"g":445,"r":[331,97,14,15,-1,-12,0]}}
  #|{"textrec":{"s":[17,400,0,"用量"],"r":[0,1,16.851167315175097,446,1,1,16.851167315175097,447]}}
  #|{"textrec":{"s":[32,700,8,"价目表"],"r":[0,1,30.345864661654133,448,1,1,30.345864661654133,449,2,1,30.345864661654133,450]}}
  #|{"textrec":{"s":[13,400,0,"当前各台 station 用于折算费用的单价"],"r":[0,1,12.898832684824903,216,1,1,12.898832684824903,217,2,1,12.898832684824903,451,3,1,12.898832684824903,452,4,1,3.580078125,-1,5,1,6.69677734375,10,6,1,4.61474609375,82,7,1,7.0966796875,12,8,1,4.646484375,82,9,1,3.1357421875,77,10,1,7.6044921875,7,11,1,7.50927734375,328,12,1,3.580078125,-1,13,1,12.898832684824896,434,14,1,12.898832684824896,453,15,1,12.898832684824896,443,16,1,12.898832684824896,444,17,1,12.898832684824896,445,18,1,12.898832684824896,434,19,1,12.898832684824896,5,20,1,12.898832684824896,454,21,1,12.898832684824896,441]}}
  #|{"textrec":{"s":[16,600,0,"studio"],"r":[0,1,8.471200942993164,35,1,1,5.973020553588867,36,2,1,9.466253280639648,455,3,1,9.891647338867188,456,4,1,4.046333312988281,457,5,1,9.432537078857422,34]}}
  #|{"textrec":{"s":[12,400,0,"美元 / 100 万 token · 各类 token × 单价后相加；Claude fast ×2。GPT 按标准短上下文估算，仅记录输入、缓存读取和输出。GPT 价目核对于 2026-10-02，Claude 沿用 2026-09 价目"],"r":[0,1,11.918287937743191,458,1,1,11.918287937743191,459,2,1,3.375,-1,3,1,3.65625,460,4,1,3.375,-1,5,1,5.56640625,461,6,1,7.55859375,388,7,1,7.55859375,388,8,1,3.375,-1,9,1,11.918287937743195,462,10,1,3.375,-1,11,1,4.3154296875,255,12,1,7.0458984375,249,13,1,6.369140625,392,14,1,6.708984375,253,15,1,7.001953125,257,16,1,3.375,-1,17,1,5.754933455713626,463,18,1,3.375,-1,19,1,11.918287937743202,464,20,1,11.918287937743202,465,21,1,3.375,-1,22,1,4.3154296875,255,23,1,7.0458984375,249,24,1,6.369140625,392,25,1,6.708984375,253,26,1,7.001953125,257,27,1,3.375,-1,28,1,7.55859375,466,29,1,3.375,-1,30,1,11.918287937743202,413,31,1,11.918287937743202,378,32,1,11.918287937743202,467,33,1,11.918287937743202,468,34,1,11.918287937743202,276,35,1,12.081712062256798,408,36,1,8.58984375,469,37,1,3.03515625,252,38,1,6.62109375,256,39,1,7.001953125,470,40,1,7.37109375,471,41,1,6.85546875,253,42,1,3.375,-1,43,1,4.25390625,250,44,1,6.533203125,256,45,1,6.251953125,472,46,1,4.330078125,255,47,1,3.375,-1,48,1,7.55859375,466,49,1,7.2421875,473,50,1,12.081712062256827,474,51,1,8.958984375,475,52,1,7.623046875,247,53,1,7.60546875,476,54,1,3.375,-1,55,1,11.918287937743173,406,56,1,11.918287937743173,411,57,1,11.918287937743173,412,58,1,11.918287937743173,477,59,1,11.918287937743173,419,60,1,11.918287937743173,420,61,1,11.918287937743173,245,62,1,11.918287937743173,414,63,1,11.918287937743173,415,64,1,12.081712062256827,416,65,1,11.91828793774323,478,66,1,11.91828793774323,479,67,1,11.91828793774323,480,68,1,11.91828793774323,390,69,1,11.91828793774323,391,70,1,12.08171206225677,481,71,1,11.91828793774323,393,72,1,11.91828793774323,394,73,1,11.91828793774323,482,74,1,11.91828793774323,483,75,1,11.91828793774323,421,76,1,11.91828793774323,390,77,1,11.91828793774323,398,78,1,12.08171206225677,474,79,1,8.958984375,475,80,1,7.623046875,247,81,1,7.60546875,476,82,1,3.375,-1,83,1,11.91828793774323,378,84,1,11.91828793774323,379,85,1,11.91828793774323,484,86,1,11.91828793774323,243,87,1,11.91828793774323,485,88,1,3.375,-1,89,1,7.2421875,473,90,1,7.55859375,388,91,1,7.2421875,473,92,1,7.640625,486,93,1,5.66015625,487,94,1,5.56640625,461,95,1,7.55859375,388,96,1,5.66015625,487,97,1,7.55859375,388,98,1,7.2421875,473,99,1,10.881712062256838,416,100,1,8.58984375,469,101,1,3.03515625,252,102,1,6.62109375,256,103,1,7.001953125,470,104,1,7.37109375,471,105,1,6.85546875,253,106,1,3.375,-1,107,1,11.91828793774323,488,108,1,11.91828793774323,261,109,1,3.375,-1,110,1,7.2421875,473,111,1,7.55859375,388,112,1,7.2421875,473,113,1,7.640625,486,114,1,5.66015625,487,115,1,7.55859375,388,116,1,7.640625,489,117,1,3.375,-1,118,1,11.91828793774323,378,119,1,11.91828793774323,379]}}
  #|{"textrec":{"s":[12,400,0,"这段时间没有模型用量"],"r":[0,1,11.918287937743191,490,1,1,11.918287937743191,491,2,1,11.918287937743195,492,3,1,11.918287937743187,493,4,1,11.918287937743187,494,5,1,11.918287937743187,495,6,1,11.918287937743187,382,7,1,11.918287937743187,383,8,1,11.918287937743187,261,9,1,11.918287937743187,262]}}
  #|{"textrec":{"g":446,"r":[346,97,17,17,-1,-14,0]}}
  #|{"textrec":{"g":447,"r":[364,97,18,18,-1,-15,0]}}
  #|{"textrec":{"g":448,"r":[383,97,32,31,-1,-26,0]}}
  #|{"textrec":{"g":449,"r":[416,97,24,30,3,-25,0]}}
  #|{"textrec":{"g":450,"r":[441,97,31,31,-1,-26,0]}}
  #|{"textrec":{"g":451,"r":[473,97,15,15,-1,-12,0]}}
  #|{"textrec":{"g":452,"r":[489,97,13,15,0,-12,0]}}
  #|{"textrec":{"g":453,"r":[503,97,14,14,-1,-11,0]}}
  #|{"textrec":{"g":454,"r":[518,97,14,15,-1,-12,0]}}
  #|{"textrec":{"g":455,"r":[533,97,10,12,0,-10,0]}}
  #|{"textrec":{"g":456,"r":[544,97,11,15,-1,-13,0]}}
  #|{"textrec":{"g":457,"r":[556,97,5,15,0,-14,0]}}
  #|{"textrec":{"g":458,"r":[562,97,14,14,-1,-11,0]}}
  #|{"textrec":{"g":459,"r":[577,97,13,13,-1,-10,0]}}
  #|{"textrec":{"g":460,"r":[591,97,6,14,-1,-10,0]}}
  #|{"textrec":{"g":461,"r":[598,97,7,11,-1,-10,0]}}
  #|{"textrec":{"g":462,"r":[606,97,13,13,-1,-10,0]}}
  #|{"textrec":{"g":463,"r":[620,97,5,5,0,-7,0]}}
  #|{"textrec":{"g":464,"r":[626,97,14,14,-1,-11,0]}}
  #|{"textrec":{"g":465,"r":[641,97,14,14,-1,-11,0]}}
  #|{"textrec":{"g":466,"r":[656,97,8,9,0,-8,0]}}
  #|{"textrec":{"g":467,"r":[665,97,14,14,-1,-11,0]}}
  #|{"textrec":{"g":468,"r":[680,97,13,14,-1,-11,0]}}
  #|{"textrec":{"g":469,"r":[694,97,10,12,-1,-10,0]}}
  #|{"textrec":{"g":470,"r":[705,97,9,10,-1,-8,0]}}
  #|{"textrec":{"g":471,"r":[715,97,9,12,-1,-10,0]}}
  #|{"textrec":{"g":472,"r":[725,97,8,10,-1,-8,0]}}
  #|{"textrec":{"g":473,"r":[734,97,9,11,-1,-10,0]}}
  #|{"textrec":{"g":474,"r":[744,97,6,6,0,-3,0]}}
  #|{"textrec":{"g":475,"r":[751,97,11,12,-1,-10,0]}}
  #|{"textrec":{"g":476,"r":[763,97,10,11,-1,-10,0]}}
  #|{"textrec":{"g":477,"r":[774,97,14,13,-1,-11,0]}}
  #|{"textrec":{"g":478,"r":[789,97,14,14,-1,-11,0]}}
  #|{"textrec":{"g":479,"r":[804,97,14,13,-1,-11,0]}}
  #|{"textrec":{"g":480,"r":[819,97,13,14,-1,-11,0]}}
  #|{"textrec":{"g":481,"r":[833,97,6,6,0,-3,0]}}
  #|{"textrec":{"g":482,"r":[840,97,14,14,-1,-11,0]}}
  #|{"textrec":{"g":483,"r":[855,97,14,14,-1,-11,0]}}
  #|{"textrec":{"g":484,"r":[870,97,14,14,-1,-11,0]}}
  #|{"textrec":{"g":485,"r":[885,97,13,14,-1,-11,0]}}
  #|{"textrec":{"g":486,"r":[899,97,9,12,-1,-10,0]}}
  #|{"textrec":{"g":487,"r":[909,97,7,4,-1,-5,0]}}
  #|{"textrec":{"g":488,"r":[917,97,14,14,-1,-11,0]}}
  #|{"textrec":{"g":489,"r":[932,97,9,12,-1,-10,0]}}
  #|{"textrec":{"g":490,"r":[942,97,14,14,-1,-11,0]}}
  #|{"textrec":{"g":491,"r":[957,97,14,14,-1,-11,0]}}
  #|{"textrec":{"g":492,"r":[972,97,14,14,-1,-11,0]}}
  #|{"textrec":{"g":493,"r":[987,97,12,14,0,-11,0]}}
  #|{"textrec":{"g":494,"r":[1000,97,14,14,-1,-11,0]}}
  #|{"textrec":{"g":495,"r":[1015,97,14,14,-1,-11,0]}}
