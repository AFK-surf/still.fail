// e2e/traces/sheets-sinking.trace, made by scripts/trace.py from 03-sheets_sinking.log: not edited by hand.

///|
/// What the app and its core said in the run, a line each.
pub let trace_sheets_sinking : String =
  #|{"env":{"MBUI_CLOUD":"http://127.0.0.1:18787","MBUI_CORE_ACCOUNT":"{\"sub\":\"alice\",\"email\":\"alice@example.test\",\"name\":\"Name of alice\",\"picture\":\"\",\"access\":\"-\",\"refresh\":\"-\",\"accessExpires\":1792551401}"}}
  #|{"out":{"id":1,"call":"client.device","params":{"client":"still.fail mbui","app":"desktop","userAgent":"Macintosh; Mac OS X"}},"w":1792551105572.059}
  #|{"in":{"id":1,"ok":null},"w":1792551105662.955}
  #|{"out":{"id":2,"subscribe":{"topic":"accounts"},"keyed":true},"w":1792551105662.98}
  #|{"out":{"id":3,"subscribe":{"topic":"prefs"},"keyed":true},"w":1792551105662.99}
  #|{"step":"# written by scripts/rerecord.sh from its test (src/sfreplay/emit.mbt): not edited by hand","w":1792551105664.401}
  #|{"step":"timeout 90000","w":1792551105664.407}
  #|{"step":"answered client.device","w":1792551105664.409}
  #|{"step":"answered client.focus","w":1792551105686.509}
  #|{"in":{"id":2,"value":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""}]},"w":1792551105736.183}
  #|{"in":{"id":3,"value":{"onlyMine":false,"onlyWatching":false,"onlyDecisions":false,"listFilter":{},"appearance":"system","rowPicture":"auto","absoluteTime":false,"lang":"zh","keys":{},"lastChat":{},"openChat":{"01M5E5Y4HC3WQXMJPK0WSETJHC":{"station":"01M5E5Y4HC3WQXMJPK0WSETJHC/1696e83c4f5fdc08a7928a36719e589a2ff2d83aaa4f0858a8e37bf88aa2ad7f","key":"ember:c-6e6e44657d"}},"chatTabs":{},"dropFiles":{},"driveViews":{},"resume":{},"stationUpdatesDismissed":{},"device":{"app":"desktop","phone":false,"handoff":false},"reader":{"size":18,"line":1.7,"margin":22,"face":"sans","indent":true,"paper":"follow"},"rails":{},"bars":{"sets":[["chats","files","profiles","stations"],["decisions","usage","connects","archive"]],"current":0},"barsBy":{},"fonts":{},"faces":{"ui":{"id":"","name":"","mono":false,"family":"","files":[],"bytes":0},"text":{"id":"","name":"","mono":false,"family":"","files":[],"bytes":0},"code":{"id":"","name":"","mono":true,"family":"","files":[],"bytes":0},"list":[{"id":"inter","name":"Inter","mono":false,"family":"SF Inter","css":"http://127.0.0.1:18787/releases/fonts/inter/4.001/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/inter/4.001/var.ttf.gz","bytes":457818,"sha256":"29160a80ff49ddcab2c97711247e08b1fab27a484a329ce8b813d820dc559031"}],"preview":"http://127.0.0.1:18787/releases/fonts/inter/4.001/preview-194fa287.ttf","bytes":457818},{"id":"noto-sans-sc","name":"思源黑体","mono":false,"family":"SF Noto Sans SC","css":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/var.ttf.gz","bytes":11276563,"sha256":"a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da"}],"preview":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/preview-f0494178.ttf","bytes":11276563},{"id":"noto-serif-sc","name":"思源宋体","mono":false,"family":"SF Noto Serif SC","css":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/var.ttf.gz","bytes":15454579,"sha256":"050080d9255a86808f2945bffac582b31ef32bc36411ce29563b4961670c66f9"}],"preview":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/preview-001bbedf.ttf","bytes":15454579},{"id":"lxgw-wenkai","name":"霞鹜文楷","mono":false,"family":"SF LXGW WenKai","css":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/font.css","files":[{"weight":400,"url":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/400.ttf.gz","bytes":12904482,"sha256":"2d73eea94ad808999d90c0000c239a84a33b09d4bc6ab6c5b8bbf1eda8a7fc8b"},{"weight":500,"url":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/500.ttf.gz","bytes":13272430,"sha256":"f4b8a34d1f838fe411540cb7c97b1c384ac9738a876c4104500bc42508b2312a"}],"preview":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/preview-d3505af4.ttf","bytes":26176912},{"id":"jetbrains-mono","name":"JetBrains Mono","mono":true,"family":"SF JetBrains Mono","css":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/var.ttf.gz","bytes":90579,"sha256":"48715a42ec242c21e9f02692891e147d022299a52e48d5e413e1a942193ffeda"}],"preview":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/preview-ee73078f.ttf","bytes":90579},{"id":"fira-code","name":"Fira Code","mono":true,"family":"SF Fira Code","css":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/var.ttf.gz","bytes":137151,"sha256":"9335b082b3c7850d98a64b584f3417f65355f3471278bb5eeb8c6c0e8657aeeb"}],"preview":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/preview-555be27a.ttf","bytes":137151},{"id":"maple-mono","name":"Maple Mono","mono":true,"family":"SF Maple Mono CN","css":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/font.css","files":[{"weight":400,"url":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/400.ttf.gz","bytes":8352545,"sha256":"0fcc5139bfd5ab14ff989bb7dfd5236d0cafc10e60b9828569e6883613ab4085"},{"weight":600,"url":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/600.ttf.gz","bytes":8438132,"sha256":"96ed7ae26ee7c50b02b2d2b2bc0f1a0cbabe45ae5d6e6abf6678e2177c415677"}],"preview":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/preview-cffdf246.ttf","bytes":16790677}]}}},"w":1792551105736.226}
  #|{"out":{"id":4,"subscribe":{"topic":"workspaces"},"keyed":true},"w":1792551105736.276}
  #|{"out":{"id":5,"subscribe":{"topic":"status"},"keyed":true},"w":1792551105736.288}
  #|{"in":{"id":4,"value":[{"account":{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""},"workspaces":[{"id":"01M5E5Y4HC3WQXMJPK0WSETJHC","name":"Dev","role":"owner","created_at":1792551096,"stations":1,"members":1,"relays":[],"time":{"created_at":{"past":true,"at":1792551096000,"ago":"刚刚","full":"10/21 10:51:36","until":"1 分钟内"}}}],"invitations":[],"relay_url":"http://127.0.0.1:18740","loaded":true,"beta":true}]},"w":1792551105752.851}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792551105752.869}
  #|{"out":{"id":6,"subscribe":{"topic":"lock","workspace":"01M5E5Y4HC3WQXMJPK0WSETJHC"},"keyed":true},"w":1792551105752.904}
  #|{"out":{"id":7,"subscribe":{"topic":"chats","scope":"01M5E5Y4HC3WQXMJPK0WSETJHC","mine":false},"keyed":true},"w":1792551105752.916}
  #|{"out":{"id":8,"subscribe":{"topic":"changelog"},"keyed":true},"w":1792551105752.923}
  #|{"out":{"id":9,"subscribe":{"topic":"workspaceMarks","workspace":"01M5E5Y4HC3WQXMJPK0WSETJHC"},"keyed":true},"w":1792551105753.042}
  #|{"out":{"id":10,"subscribe":{"topic":"status","workspace":"01M5E5Y4HC3WQXMJPK0WSETJHC"},"keyed":true},"w":1792551105753.078}
  #|{"out":{"id":11,"call":"client.focus","params":{"visible":true,"focused":true,"workspace":"01M5E5Y4HC3WQXMJPK0WSETJHC"}},"w":1792551105759.902}
  #|{"out":{"id":12,"subscribe":{"topic":"notify"},"keyed":true},"w":1792551105759.918}
  #|{"out":{"id":13,"subscribe":{"topic":"notify","workspace":"01M5E5Y4HC3WQXMJPK0WSETJHC"},"keyed":true},"w":1792551105759.927}
  #|{"in":{"id":6,"value":{"available":true,"locked":false,"notice":true,"role":"owner","manages":true,"owner":true,"canSign":true,"signs":false,"me":{"device":"f21c6a811b2c34d95d0238d9d6c5c19ab50e201b740f6ef95300d85dc242c51e","code":"BRR-UUF","kind":"app","confirmed":false,"waiting":false,"asked":false},"signers":0,"members":[],"stations":[{"id":"1696e83c4f5fdc08a7928a36719e589a2ff2d83aaa4f0858a8e37bf88aa2ad7f","name":"studio","version":"0.1.0","online":true,"protected":false}],"protected":0,"requests":[],"renew":[],"attention":0}},"w":1792551105772.446}
  #|{"in":{"id":7,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"stations":[{"station":"01M5E5Y4HC3WQXMJPK0WSETJHC/1696e83c4f5fdc08a7928a36719e589a2ff2d83aaa4f0858a8e37bf88aa2ad7f","id":"1696e83c4f5fdc08a7928a36719e589a2ff2d83aaa4f0858a8e37bf88aa2ad7f","name":"studio","state":"online"}],"loading":false,"days":[{"daysAgo":0,"at":1792551103147,"label":"今天","items":[{"id":"ember:c-6e6e44657d","session":"ember:c-6e6e44657d","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","agents":[{"key":"ember:c-6e6e44657d","runtime":"claude","process":"warm","pending":0,"lastTurn":{"id":"36256e3e-c73e-48b8-bdce-70d223d9a6fd","kind":"nudge","outcome":"completed","startedAt":1792551103143,"endedAt":1792551103146},"agentText":"默认模型","mark":"failed","statusText":"出错：意外停止","badgeText":"失败，需要处理"}],"last":{"seq":4,"authorKind":"ember","author":"ember","authorName":"still.fail","text":"⚠️ 本轮 agent 未在对话中回复，以下是它最后输出的文字，由 station 代为转发（并非它发布的消息）；回复即可继续：\n\n> Your turn ended without a state, so nobody knows where the chat stands. Only a real unresolved need requires need_human. A factual a","createdAt":1792551103147,"by":{"kind":"ember","name":"still.fail","mine":false,"label":"still.fail"},"preview":"⚠️ 本轮 agent 未在对话中回复，以下是它最后输出的文字，由 station 代为转发（并非它发布的消息）；回复即可继续： Your turn ended without a state, so nobody knows where the chat stands. Only a real unresolved need requires need_human. A factual a","time":{"createdAt":{"at":1792551103147,"ago":"刚刚","full":"10/21 10:51:43","until":"1 分钟内","past":true}}},"unread":false,"mine":true,"lastActiveAt":1792551103147,"station":"01M5E5Y4HC3WQXMJPK0WSETJHC/1696e83c4f5fdc08a7928a36719e589a2ff2d83aaa4f0858a8e37bf88aa2ad7f","stationName":"studio","state":"failed","time":{"lastActiveAt":{"at":1792551103147,"ago":"刚刚","full":"10/21 10:51:43","until":"1 分钟内","past":true}},"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"peopleText":"你 发起","clientKey":"new:chat-2d8a8c87afd522469d","pinned":false,"stateText":"出错：意外停止","tone":"alert"}]}],"trouble":null,"members":1,"leading":"agents","glyph":{"online":1,"dim":0,"connecting":0,"failing":0,"working":0,"summary":"studio","label":"1 台 station，1 台在线"},"note":{"reading":false,"text":null,"failing":[],"empty":false}}},"w":1792551105772.476}
  #|{"in":{"id":8,"value":{"app":"desktop","tabs":[{"part":"desktop","label":"桌面","days":[]},{"part":"web","label":"网页","days":[]},{"part":"android","label":"安卓","days":[]},{"part":"station","label":"Station","days":[]},{"part":"cloud","label":"云端","days":[]}],"loading":false}},"w":1792551105772.496}
  #|{"in":{"id":9,"value":{"workspaces":{"01M5E5Y4HC3WQXMJPK0WSETJHC":{"alert":1,"unread":0,"tone":"alert","label":"1 个出错","chat":{"station":"01M5E5Y4HC3WQXMJPK0WSETJHC/1696e83c4f5fdc08a7928a36719e589a2ff2d83aaa4f0858a8e37bf88aa2ad7f","key":"ember:c-6e6e44657d"},"badge":0,"items":[{"kind":"alert","workspace":"01M5E5Y4HC3WQXMJPK0WSETJHC","workspaceName":"Dev","station":"01M5E5Y4HC3WQXMJPK0WSETJHC/1696e83c4f5fdc08a7928a36719e589a2ff2d83aaa4f0858a8e37bf88aa2ad7f","stationName":"studio","session":"ember:c-6e6e44657d","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","text":"出错：意外停止","seen":true,"at":1792551103147}],"mineTone":"alert"}},"badge":0,"badgeCounts":"attention","badgeKinds":{"on":true,"wait":true,"failed":true,"done":false,"message":false}}},"w":1792551105772.509}
  #|{"in":{"id":10,"value":{"items":[]}},"w":1792551105772.515}
  #|{"in":{"id":11,"ok":null},"w":1792551105772.518}
  #|{"in":{"id":12,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792551105772.528}
  #|{"in":{"id":13,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792551105772.533}
  #|{"out":{"id":14,"subscribe":{"topic":"longJobs","scope":"01M5E5Y4HC3WQXMJPK0WSETJHC"},"keyed":true},"w":1792551105772.558}
  #|{"out":{"id":15,"call":"notify.permission","params":{"state":"unknown"}},"w":1792551105774.83}
  #|{"in":{"id":14,"value":{"groups":[]}},"w":1792551105786.186}
  #|{"in":{"id":15,"ok":null},"w":1792551105786.193}
  #|{"step":"answered notify.permission","w":1792551105786.45}
  #|{"step":"until 端到端测试","w":1792551105803.055}
  #|{"step":"tap =Dev","w":1792551105803.061}
  #|{"step":"tap =Dev","acted":true,"w":1792551105803.07}
  #|{"step":"tapxy 195 120","w":1792551105822.763}
  #|{"step":"tapxy 195 120","acted":true,"w":1792551105822.77}
  #|{"step":"tap icon:folder","w":1792551105836.599}
  #|{"step":"tap icon:folder","acted":true,"w":1792551105836.612}
  #|{"out":{"id":16,"subscribe":{"topic":"stations","scope":"01M5E5Y4HC3WQXMJPK0WSETJHC"},"keyed":true},"w":1792551105852.948}
  #|{"out":{"id":17,"subscribe":{"topic":"workspace","workspace":"01M5E5Y4HC3WQXMJPK0WSETJHC"},"keyed":true},"w":1792551105852.961}
  #|{"step":"until =文件","w":1792551105853.414}
  #|{"step":"gone 切换 workspace","w":1792551105853.421}
  #|{"step":"tap icon:chats","w":1792551105853.425}
  #|{"step":"tap icon:chats","acted":true,"w":1792551105853.433}
  #|{"in":{"id":16,"value":[{"station":"01M5E5Y4HC3WQXMJPK0WSETJHC/1696e83c4f5fdc08a7928a36719e589a2ff2d83aaa4f0858a8e37bf88aa2ad7f","id":"1696e83c4f5fdc08a7928a36719e589a2ff2d83aaa4f0858a8e37bf88aa2ad7f","name":"studio","summary":"空闲 · Apple M4 · 16 GB · macOS 27.0.1","face":"idle","line":"Apple M4","online":true,"reconnecting":false,"lastSeen":1792551100,"version":"0.1.0","link":{"state":"online"},"runtimes":[{"runtime":"claude","models":["claude-sonnet-5-5"]}],"models":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792551100879,"time":{"checkedAt":{"at":1792551100879,"ago":"刚刚","full":"10/21 10:51:40","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"overview":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null,"summaryText":"最近 7 天检查了 0 个 chat","changeText":null}},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","email":"alice@example.test","name":"Name of alice","sub":"alice","role":"owner","workspace":"01M5E5Y4HC3WQXMJPK0WSETJHC","device":"f21c6a811b2c34d95d0238d9d6c5c19ab50e201b740f6ef95300d85dc242c51e"},"connects":[],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792551100756,"time":{"checkedAt":{"at":1792551100756,"ago":"刚刚","full":"10/21 10:51:40","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792551100879,"time":{"checkedAt":{"at":1792551100879,"ago":"刚刚","full":"10/21 10:51:40","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]}],"processes":[],"counts":{"sessions":1,"running":0,"warm":1},"mesh":{"state":"running","origin":"http://127.0.0.1:18787","station":"1696e83c4f5fdc08a7928a36719e589a2ff2d83aaa4f0858a8e37bf88aa2ad7f","workspace":"Dev","workspaceId":"01M5E5Y4HC3WQXMJPK0WSETJHC","name":"studio"},"slackUsers":[],"slackTeams":[],"slackApps":[],"feishuRegistrations":[],"disk":{"freeBytes":44857339904,"totalBytes":245107195904},"logins":[],"machineLogins":[],"sharing":true,"consoleSignIn":true,"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"google","name":"Google Gemini","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xai","name":"xAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"mistral","name":"Mistral","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"deepseek","name":"DeepSeek","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen","name":"Qwen","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai","name":"Kimi","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai","name":"Z.ai","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax","name":"MiniMax","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ant-ling","name":"Ant Ling","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"jev","name":"Jev","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen-cn","name":"Qwen (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"openrouter","name":"OpenRouter","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"opencode","name":"OpenCode Zen","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"groq","name":"Groq","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"together","name":"Together AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"fireworks","name":"Fireworks","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cerebras","name":"Cerebras","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"huggingface","name":"Hugging Face","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"nvidia","name":"NVIDIA","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"baseten","name":"Baseten","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ollama","name":"Ollama","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"custom","name":"Custom","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""}],"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792551098325},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.305","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792551098325},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-news/apps/e2e-local/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792551098325},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-news/apps/e2e-local/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792551098325},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","latest":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-news/apps/e2e-local/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792551098325},{"id":"cursor","name":"Cursor","installed":false,"latest":"1.0.40","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792551098325},{"id":"devin","name":"Devin","installed":true,"version":"3000.11.92","latest":"3000.11.92","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-news/apps/e2e-local/ember/station/test/fake/devin，不是用 Devin 的安装脚本装的，需在该机器上手动更新","state":"idle","checkedAt":1792551098325}],"processesText":"没有运行中的 agent 进程","agentEnv":[],"drive":{"roots":[],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false}},"betaOffered":false,"host":{"hostname":"3720-Mac-mini-1","os":"macOS 27.0.1","arch":"arm64","cpus":10,"cpuModel":"Apple M4","load":0.16,"cpuBusy":0.11,"uptimeSec":30464,"memory":{"totalBytes":17179869184,"usedBytes":9499770880,"swapUsedBytes":300742083},"disk":{"path":"/tmp/mbe2e-C/data","totalBytes":245107195904,"freeBytes":44859523072},"emberRssBytes":159840080,"checkedAt":1792551102530,"summary":"10 核 · 16 GB","line":"macOS 27.0.1 · 10 核 · 16 GB · 已运行 0 天","facts":["3720-Mac-mini-1","macOS 27.0.1","arm64 · 10 核","已运行 8 小时"],"meters":[{"label":"CPU","short":"CPU","percent":11,"left":89,"level":"ok","value":"11%","remaining":"空闲 89%","big":"89","unit":"%","title":"CPU 空闲","total":"负载 1.6","note":"负载 1.6 · Apple M4"},{"label":"内存","short":"内存","percent":55,"left":45,"level":"ok","value":"8.8 GB / 16.0 GB","remaining":"剩 7.2 G","big":"7.2","unit":"GB","title":"内存剩","total":"共 16 GB","note":"swap 0.3 GB"},{"label":"磁盘","short":"磁盘","percent":82,"left":18,"level":"amber","value":"剩余 41.8 GB / 228 GB","remaining":"剩 41.8 G","big":"41.8","unit":"GB","title":"磁盘剩","total":"共 228 GB"}],"identity":"Apple M4 · 16 GB · macOS 27.0.1","details":[{"label":"主机名","value":"3720-Mac-mini-1"},{"label":"芯片","value":"Apple M4 · 10 核 · arm64"},{"label":"已运行","value":"8 小时"},{"label":"still.fail","value":"进程占用 152 MB"}],"usage":"内存 8.8 GB / 16.0 GB · 磁盘 剩余 41.8 GB / 228 GB","emberText":"still.fail 152 MB"},"way":{"path":"直连","via":"direct"},"time":{"lastSeen":{"at":1792551100000,"ago":"刚刚","full":"10/21 10:51:40","until":"1 分钟内","past":true}},"joined":false}]},"w":1792551105869.663}
  #|{"in":{"id":17,"value":{"id":"01M5E5Y4HC3WQXMJPK0WSETJHC","name":"Dev","role":"owner","created_at":1792551096,"members":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":"https://example.test/p.png","role":"owner","added_at":1792551096}],"stations":[{"id":"1696e83c4f5fdc08a7928a36719e589a2ff2d83aaa4f0858a8e37bf88aa2ad7f","name":"studio","emoji":null,"icon":null,"enrolled_at":1792551097,"enrolled_by":"alice","last_seen":1792551100,"version":"0.1.0","time":{"last_seen":{"past":true,"at":1792551100000,"ago":"刚刚","full":"10/21 10:51:40","until":"1 分钟内"}}}],"invitations":[],"added":[],"relays":[],"lock":null,"lock_requests":0,"time":{"created_at":{"past":true,"at":1792551096000,"ago":"刚刚","full":"10/21 10:51:36","until":"1 分钟内"}}}},"w":1792551105869.791}
  #|{"step":"wait 220","w":1792551105871.061}
  #|{"in":{"id":16,"delta":[{"path":[0,"overview","disk","freeBytes"],"set":44857241600}]},"w":1792551105952.847}
  #|{"step":"now tap 端到端测试","w":1792551106104.501}
  #|{"step":"now tap 端到端测试","acted":true,"w":1792551106104.585}
  #|{"out":{"id":18,"subscribe":{"topic":"chat","station":"01M5E5Y4HC3WQXMJPK0WSETJHC/1696e83c4f5fdc08a7928a36719e589a2ff2d83aaa4f0858a8e37bf88aa2ad7f","session":"ember:c-6e6e44657d"},"keyed":true},"w":1792551106120.683}
  #|{"out":{"id":19,"call":"draft.get","params":{"key":"01M5E5Y4HC3WQXMJPK0WSETJHC/1696e83c4f5fdc08a7928a36719e589a2ff2d83aaa4f0858a8e37bf88aa2ad7f:ember:c-6e6e44657d"}},"w":1792551106123.085}
  #|{"step":"answered draft.get","w":1792551106124.182}
  #|{"in":{"id":19,"ok":{"text":"","quotes":[],"files":[],"id":"draft-1fb407c6c7c0870068"}},"w":1792551106136.222}
  #|{"in":{"id":18,"value":{"archived":false,"pinned":false,"me":{"id":"alice@example.test","email":"alice@example.test"},"thread":{"id":1,"surface":"ember","channel":"EMBER","threadTs":"1792551100.836000","createdBy":"alice@example.test","creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"createdAt":1792551100836,"sessions":[{"thread":1,"session":"ember:c-6e6e44657d","connect":"ember","joinedAt":1792551100836}],"last":4,"lastMessage":{"seq":4,"thread":1,"ts":"1792551103.147000","authorKind":"ember","author":"ember","authorName":"still.fail","text":"⚠️ 本轮 agent 未在对话中回复，以下是它最后输出的文字，由 station 代为转发（并非它发布的消息）；回复即可继续：\n\n> Your turn ended without a state, so nobody knows where the chat stands. Only a real unresolved need requires need_human. A factual answer alone does not need a follow-up question; do not invent one. If you still need something after answering a clarification, visibly ask for it; need alone is only a status summary. Cards are optional. Do not reopen a decision the user already made. Decide whether anything in it is still unfinished, then end the turn with exactly one:\n> - all_done: nothing in the chat is left unfinished at all. Post the result with chat_post kind \"all_done\" (or chat_state \"all_done\" if you already posted it), with done: why nothing is left, naming the evidence (a commit, a release, a person's confirmation, the answer given).\n> - need_human: a person has to give, do, decide, confirm or verify something (a card you posted included), or answer a question you asked: kind \"need_human\" with need, what they have to give, do or decide (to verify: where, how and what to look at). If work you started is pending too, mention it after the ask in need.\n> - waiting: only work you started that will bring you back on its own (a background command or agent, a job, a loop watching CI), with nothing asked of anyone, and nothing else you can do meanwhile: chat_state \"waiting\" with seconds, your estimate of how long until it does, and for, what you wait for. Waiting on a person is need_human.\n> - Otherwise: continue the work.","attachments":[],"quotes":[],"createdAt":1792551103147,"time":{"createdAt":{"at":1792551103147,"ago":"刚刚","full":"10/21 10:51:43","until":"1 分钟内","past":true}}},"read":4,"unread":0,"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"firstText":"端到端测试的对话 post:你好，我是测试用的 agent","time":{"createdAt":{"at":1792551100836,"ago":"刚刚","full":"10/21 10:51:40","until":"1 分钟内","past":true}}},"title":"端到端测试的对话 post:你好，我是测试用的 agent","people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"agents":[{"session":{"key":"ember:c-6e6e44657d","connect":"ember","scope":"all","createdBy":"alice@example.test","boundTo":[],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"},"participants":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"}],"runtime":"claude","profile":"cc","profilePinned":false,"runtimeSessionId":"ff15d489-9d9f-4085-b599-91987fba42ef","workspace":"/tmp/mbe2e-C/data/sessions/ember/c-6e6e44657d/workspace","running":false,"createdAt":1792551100835,"lastActiveAt":1792551103146,"process":"warm","turns":4,"pending":0,"firstText":"端到端测试的对话 post:你好，我是测试用的 agent","lastTurn":{"id":"36256e3e-c73e-48b8-bdce-70d223d9a6fd","kind":"nudge","outcome":"completed","startedAt":1792551103143,"endedAt":1792551103146},"statusText":"出错：意外停止","tone":"red","mark":"failed","badgeText":"失败，需要处理","titleText":"端到端测试的对话 post:你好，我是测试用的 agent","agentText":"默认模型","runtimeText":"Claude Code","processText":"保温中","efforts":["low","medium","high","xhigh","max"],"time":{"createdAt":{"at":1792551100835,"ago":"刚刚","full":"10/21 10:51:40","until":"1 分钟内","past":true},"lastActiveAt":{"at":1792551103146,"ago":"刚刚","full":"10/21 10:51:43","until":"1 分钟内","past":true}}},"status":"unexpected","badge":"failed","profile":{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792551100756,"time":{"checkedAt":{"at":1792551100756,"ago":"刚刚","full":"10/21 10:51:40","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792551100879,"time":{"checkedAt":{"at":1792551100879,"ago":"刚刚","full":"10/21 10:51:40","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]},"profiles":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":true,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792551100879,"time":{"checkedAt":{"at":1792551100879,"ago":"刚刚","full":"10/21 10:51:40","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}],"choices":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":true,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792551100879,"time":{"checkedAt":{"at":1792551100879,"ago":"刚刚","full":"10/21 10:51:40","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"account":{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":true,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792551100879,"time":{"checkedAt":{"at":1792551100879,"ago":"刚刚","full":"10/21 10:51:40","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}},"attention":[],"turns":[{"id":"e0a21f8e-8d95-4953-98a0-3820332f7170","kind":"input","outcome":"completed","declared":"final","ending":"all_done","startedAt":1792551100901,"endedAt":1792551100969},{"id":"8f33a195-bb49-4bc1-844c-56c3cd94f13e","kind":"input","startedAt":1792551103130},{"id":"cc7b4414-483f-4bc9-9d3a-d754f3a8d712","kind":"nudge","startedAt":1792551103138},{"id":"36256e3e-c73e-48b8-bdce-70d223d9a6fd","kind":"nudge","outcome":"completed","startedAt":1792551103143,"endedAt":1792551103146}],"threads":[{"id":1,"surface":"ember","channel":"EMBER","threadTs":"1792551100.836000","createdBy":"alice@example.test","creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"},"createdAt":1792551100836,"sessions":[{"thread":1,"session":"ember:c-6e6e44657d","connect":"ember","joinedAt":1792551100836}],"last":4,"lastMessage":{"seq":4,"thread":1,"ts":"1792551103.147000","authorKind":"ember","author":"ember","authorName":"still.fail","text":"⚠️ 本轮 agent 未在对话中回复，以下是它最后输出的文字，由 station 代为转发（并非它发布的消息）；回复即可继续：\n\n> Your turn ended without a state, so nobody knows where the chat stands. Only a real unresolved need requires need_human. A factual answer alone does not need a follow-up question; do not invent one. If you still need something after answering a clarification, visibly ask for it; need alone is only a status summary. Cards are optional. Do not reopen a decision the user already made. Decide whether anything in it is still unfinished, then end the turn with exactly one:\n> - all_done: nothing in the chat is left unfinished at all. Post the result with chat_post kind \"all_done\" (or chat_state \"all_done\" if you already posted it), with done: why nothing is left, naming the evidence (a commit, a release, a person's confirmation, the answer given).\n> - need_human: a person has to give, do, decide, confirm or verify something (a card you posted included), or answer a question you asked: kind \"need_human\" with need, what they have to give, do or decide (to verify: where, how and what to look at). If work you started is pending too, mention it after the ask in need.\n> - waiting: only work you started that will bring you back on its own (a background command or agent, a job, a loop watching CI), with nothing asked of anyone, and nothing else you can do meanwhile: chat_state \"waiting\" with seconds, your estimate of how long until it does, and for, what you wait for. Waiting on a person is need_human.\n> - Otherwise: continue the work.","attachments":[],"quotes":[],"createdAt":1792551103147,"time":{"createdAt":{"at":1792551103147,"ago":"刚刚","full":"10/21 10:51:43","until":"1 分钟内","past":true}}},"read":4,"unread":0,"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"}],"firstText":"端到端测试的对话 post:你好，我是测试用的 agent","time":{"createdAt":{"at":1792551100836,"ago":"刚刚","full":"10/21 10:51:40","until":"1 分钟内","past":true}}}],"jobs":[]}],"messages":[{"seq":1,"thread":1,"ts":"1792551100.888000","authorKind":"person","author":"alice@example.test","authorName":"Name of alice","text":"端到端测试的对话 post:你好，我是测试用的 agent","attachments":[],"quotes":[],"createdAt":1792551100889,"mine":true,"system":false,"by":{"name":"Name of alice","picture":"https://example.test/p.png"},"waiting":false,"time":{"createdAt":{"at":1792551100889,"ago":"刚刚","full":"10/21 10:51:40","until":"1 分钟内","past":true}}},{"seq":2,"thread":1,"ts":"1792551100.967000","authorKind":"agent","author":"ember:c-6e6e44657d","text":"你好，我是测试用的 agent","attachments":[],"quotes":[],"declared":"final","ending":"all_done","createdAt":1792551100967,"mine":false,"system":false,"by":{"name":"默认模型","agent":"ember:c-6e6e44657d","runtime":"claude","here":true},"waiting":false,"time":{"createdAt":{"at":1792551100967,"ago":"刚刚","full":"10/21 10:51:40","until":"1 分钟内","past":true}}},{"seq":3,"thread":1,"ts":"1792551103.127000","authorKind":"person","author":"alice@example.test","authorName":"Name of alice","text":"栏下去时点的 082939","attachments":[],"quotes":[],"createdAt":1792551103127,"mine":true,"system":false,"by":{"name":"Name of alice","picture":"https://example.test/p.png"},"waiting":false,"time":{"createdAt":{"at":1792551103127,"ago":"刚刚","full":"10/21 10:51:43","until":"1 分钟内","past":true}}},{"seq":4,"thread":1,"ts":"1792551103.147000","authorKind":"ember","author":"ember","authorName":"still.fail","text":"⚠️ 本轮 agent 未在对话中回复，以下是它最后输出的文字，由 station 代为转发（并非它发布的消息）；回复即可继续：\n\n> Your turn ended without a state, so nobody knows where the chat stands. Only a real unresolved need requires need_human. A factual answer alone does not need a follow-up question; do not invent one. If you still need something after answering a clarification, visibly ask for it; need alone is only a status summary. Cards are optional. Do not reopen a decision the user already made. Decide whether anything in it is still unfinished, then end the turn with exactly one:\n> - all_done: nothing in the chat is left unfinished at all. Post the result with chat_post kind \"all_done\" (or chat_state \"all_done\" if you already posted it), with done: why nothing is left, naming the evidence (a commit, a release, a person's confirmation, the answer given).\n> - need_human: a person has to give, do, decide, confirm or verify something (a card you posted included), or answer a question you asked: kind \"need_human\" with need, what they have to give, do or decide (to verify: where, how and what to look at). If work you started is pending too, mention it after the ask in need.\n> - waiting: only work you started that will bring you back on its own (a background command or agent, a job, a loop watching CI), with nothing asked of anyone, and nothing else you can do meanwhile: chat_state \"waiting\" with seconds, your estimate of how long until it does, and for, what you wait for. Waiting on a person is need_human.\n> - Otherwise: continue the work.","attachments":[],"quotes":[],"createdAt":1792551103147,"mine":false,"system":true,"reportable":true,"by":{"name":"still.fail"},"waiting":false,"time":{"createdAt":{"at":1792551103147,"ago":"刚刚","full":"10/21 10:51:43","until":"1 分钟内","past":true}}}],"elsewhere":[],"more":false,"newer":false,"caught":4,"unreadAbove":false,"outbox":[],"link":{"state":"online"},"offline":false,"pending":false,"asks":[],"publish":{"may":true,"links":[]}}},"w":1792551106136.594}
  #|{"out":{"id":20,"subscribe":{"topic":"chatJobs","station":"01M5E5Y4HC3WQXMJPK0WSETJHC/1696e83c4f5fdc08a7928a36719e589a2ff2d83aaa4f0858a8e37bf88aa2ad7f","session":"ember:c-6e6e44657d"},"keyed":true},"w":1792551106137.167}
  #|{"out":{"id":21,"call":"picture","params":{"url":"https://example.test/p.png"}},"w":1792551106137.228}
  #|{"out":{"id":22,"call":"client.focus","params":{"chat":{"station":"01M5E5Y4HC3WQXMJPK0WSETJHC/1696e83c4f5fdc08a7928a36719e589a2ff2d83aaa4f0858a8e37bf88aa2ad7f","session":"ember:c-6e6e44657d","thread":1,"end":true}}},"w":1792551106147.586}
  #|{"in":{"id":20,"value":{"jobs":[],"servicesNote":"","jobsNote":"","current":0,"ended":0,"clear":[],"allText":"全部 0 个","clearText":"清除 0 个已结束的","hiddenText":"另有 0 个已停止或结束"}},"w":1792551106152.878}
  #|{"in":{"id":22,"ok":null},"w":1792551106152.935}
  #|{"step":"answered picture","w":1792551106163.783}
  #|{"in":{"id":21,"error":{"code":"picture","message":"无法加载图片：error sending request for url (https://example.test/p.png): client error (Connect): tls handshake eof"}},"w":1792551106352.881}
  #|{"step":"answered client.focus","w":1792551106371.727}
  #|{"step":"wait 300","w":1792551106388.542}
  #|{"step":"now until 发消息","w":1792551106704.216}
  #|{"step":"tap icon:more","w":1792551106704.275}
  #|{"step":"tap icon:more","acted":true,"w":1792551106704.309}
  #|{"step":"until =固定到列表顶部","w":1792551106740.542}
  #|{"step":"tapxy 195 60","w":1792551106838.023}
  #|{"step":"tapxy 195 60","acted":true,"w":1792551106838.055}
  #|{"step":"tapxy 120 -36","w":1792551106855.684}
  #|{"step":"tapxy 120 -36","acted":true,"w":1792551106855.769}
  #|{"step":"type 穿过下去的面板 082939","w":1792551106880.492}
  #|{"step":"type 穿过下去的面板 082939","acted":true,"w":1792551106880.539}
  #|{"out":{"id":23,"call":"session.warm","params":{"station":"01M5E5Y4HC3WQXMJPK0WSETJHC/1696e83c4f5fdc08a7928a36719e589a2ff2d83aaa4f0858a8e37bf88aa2ad7f","key":"ember:c-6e6e44657d"}},"w":1792551106886.556}
  #|{"step":"answered session.warm","w":1792551106890.492}
  #|{"in":{"id":23,"ok":{"ok":true}},"w":1792551106902.889}
  #|{"step":"tap icon:arrow-up","w":1792551106921.703}
  #|{"step":"tap icon:arrow-up","acted":true,"w":1792551106921.745}
  #|{"out":{"id":24,"call":"chat.send","params":{"station":"01M5E5Y4HC3WQXMJPK0WSETJHC/1696e83c4f5fdc08a7928a36719e589a2ff2d83aaa4f0858a8e37bf88aa2ad7f","text":"穿过下去的面板 082939","attachments":[],"quotes":[],"thread":1}},"w":1792551106936.784}
  #|{"step":"answered chat.send","w":1792551106940.058}
  #|{"in":{"id":24,"ok":{"seq":5}},"w":1792551106969.53}
  #|{"step":"wait 600","w":1792551106986.722}
  #|{"in":{"id":18,"delta":[{"path":["agents",0,"session","lastActiveAt"],"set":1792551106963},{"path":["agents",0,"session","lastTurn","endedAt"],"set":1792551106963},{"path":["agents",0,"session","lastTurn","id"],"set":"8b43355e-e090-46ad-beec-dc81ba25a6a7"},{"path":["agents",0,"session","lastTurn","startedAt"],"set":1792551106960},{"path":["agents",0,"session","time","lastActiveAt","at"],"set":1792551106963},{"path":["agents",0,"session","time","lastActiveAt","full"],"set":"10/21 10:51:46"},{"path":["agents",0,"session","turns"],"set":7},{"path":["agents",0,"threads",0,"last"],"set":6},{"path":["agents",0,"threads",0,"lastMessage","createdAt"],"set":1792551106964},{"path":["agents",0,"threads",0,"lastMessage","seq"],"set":6},{"path":["agents",0,"threads",0,"lastMessage","time","createdAt","at"],"set":1792551106964},{"path":["agents",0,"threads",0,"lastMessage","time","createdAt","full"],"set":"10/21 10:51:46"},{"path":["agents",0,"threads",0,"lastMessage","ts"],"set":"1792551106.964000"},{"path":["agents",0,"threads",0,"unread"],"set":1},{"path":["agents",0,"turns"],"append":[{"id":"fec9dfc8-e321-41f7-80c9-95f0b922b3f3","kind":"input","startedAt":1792551106947},{"id":"70630433-612d-4182-9390-38321069f374","kind":"nudge","startedAt":1792551106953},{"id":"8b43355e-e090-46ad-beec-dc81ba25a6a7","kind":"nudge","outcome":"completed","startedAt":1792551106960,"endedAt":1792551106963}]},{"path":["outbox"],"key":["id"],"put":{"id":"out-03994abebd79f87df4","text":"穿过下去的面板 082939","attachments":[],"quotes":[],"createdAt":1792551106938,"state":"sending","seq":5,"time":{"createdAt":{"at":1792551106938,"ago":"刚刚","full":"10/21 10:51:46","until":"1 分钟内","past":true}}},"before":null},{"path":["thread","last"],"set":6},{"path":["thread","lastMessage","createdAt"],"set":1792551106964},{"path":["thread","lastMessage","seq"],"set":6},{"path":["thread","lastMessage","time","createdAt","at"],"set":1792551106964},{"path":["thread","lastMessage","time","createdAt","full"],"set":"10/21 10:51:46"},{"path":["thread","lastMessage","ts"],"set":"1792551106.964000"},{"path":["thread","unread"],"set":1}]},"w":1792551107019.532}
  #|{"in":{"id":9,"delta":[{"path":["badge"],"set":1},{"path":["workspaces","01M5E5Y4HC3WQXMJPK0WSETJHC","badge"],"set":1},{"path":["workspaces","01M5E5Y4HC3WQXMJPK0WSETJHC","items",0,"at"],"set":1792551106964},{"path":["workspaces","01M5E5Y4HC3WQXMJPK0WSETJHC","items",0,"seen"],"set":false}]},"w":1792551107019.609}
  #|{"in":{"id":7,"delta":[{"path":["days"],"key":["daysAgo"],"patch":0,"ops":[{"path":["at"],"set":1792551106964},{"path":["items"],"key":["station","id"],"patch":["01M5E5Y4HC3WQXMJPK0WSETJHC/1696e83c4f5fdc08a7928a36719e589a2ff2d83aaa4f0858a8e37bf88aa2ad7f","ember:c-6e6e44657d"],"ops":[{"path":["agents",0,"lastTurn","endedAt"],"set":1792551106963},{"path":["agents",0,"lastTurn","id"],"set":"8b43355e-e090-46ad-beec-dc81ba25a6a7"},{"path":["agents",0,"lastTurn","startedAt"],"set":1792551106960},{"path":["last","createdAt"],"set":1792551106964},{"path":["last","seq"],"set":6},{"path":["last","time","createdAt","at"],"set":1792551106964},{"path":["last","time","createdAt","full"],"set":"10/21 10:51:46"},{"path":["lastActiveAt"],"set":1792551106964},{"path":["time","lastActiveAt","at"],"set":1792551106964},{"path":["time","lastActiveAt","full"],"set":"10/21 10:51:46"},{"path":["unread"],"set":true}]}]}]},"w":1792551107019.625}
  #|{"in":{"id":16,"delta":[{"path":[0,"overview","disk","freeBytes"],"set":44857204736}]},"w":1792551107019.648}
  #|{"in":{"id":18,"delta":[{"path":["messages"],"key":["seq","outgoing"],"put":{"seq":6,"thread":1,"ts":"1792551106.964000","authorKind":"ember","author":"ember","authorName":"still.fail","text":"⚠️ 本轮 agent 未在对话中回复，以下是它最后输出的文字，由 station 代为转发（并非它发布的消息）；回复即可继续：\n\n> Your turn ended without a state, so nobody knows where the chat stands. Only a real unresolved need requires need_human. A factual answer alone does not need a follow-up question; do not invent one. If you still need something after answering a clarification, visibly ask for it; need alone is only a status summary. Cards are optional. Do not reopen a decision the user already made. Decide whether anything in it is still unfinished, then end the turn with exactly one:\n> - all_done: nothing in the chat is left unfinished at all. Post the result with chat_post kind \"all_done\" (or chat_state \"all_done\" if you already posted it), with done: why nothing is left, naming the evidence (a commit, a release, a person's confirmation, the answer given).\n> - need_human: a person has to give, do, decide, confirm or verify something (a card you posted included), or answer a question you asked: kind \"need_human\" with need, what they have to give, do or decide (to verify: where, how and what to look at). If work you started is pending too, mention it after the ask in need.\n> - waiting: only work you started that will bring you back on its own (a background command or agent, a job, a loop watching CI), with nothing asked of anyone, and nothing else you can do meanwhile: chat_state \"waiting\" with seconds, your estimate of how long until it does, and for, what you wait for. Waiting on a person is need_human.\n> - Otherwise: continue the work.","attachments":[],"quotes":[],"createdAt":1792551106964,"mine":false,"system":true,"reportable":true,"by":{"name":"still.fail"},"waiting":false,"said":true,"time":{"createdAt":{"at":1792551106964,"ago":"刚刚","full":"10/21 10:51:46","until":"1 分钟内","past":true}}},"before":null},{"path":["messages"],"key":["seq","outgoing"],"put":{"outgoing":"out-03994abebd79f87df4","seq":5,"thread":1,"ts":"1792551106.943000","authorKind":"person","author":"alice@example.test","authorName":"Name of alice","text":"穿过下去的面板 082939","attachments":[],"quotes":[],"createdAt":1792551106943,"mine":true,"system":false,"by":{"name":"Name of alice","picture":"https://example.test/p.png"},"waiting":false,"said":true,"time":{"createdAt":{"at":1792551106943,"ago":"刚刚","full":"10/21 10:51:46","until":"1 分钟内","past":true}}},"before":[6,null]},{"path":["outbox"],"key":["id"],"drop":"out-03994abebd79f87df4"}]},"w":1792551107186.215}
  #|{"in":{"id":16,"delta":[{"path":[0,"overview","disk","freeBytes"],"set":44856156160}]},"w":1792551107202.867}
  #|{"in":{"id":18,"delta":[{"path":["agents",0,"threads",0,"read"],"set":6},{"path":["agents",0,"threads",0,"unread"],"set":0},{"path":["thread","read"],"set":6},{"path":["thread","unread"],"set":0}]},"w":1792551107269.562}
  #|{"in":{"id":7,"delta":[{"path":["days"],"key":["daysAgo"],"patch":0,"ops":[{"path":["items"],"key":["station","id"],"patch":["01M5E5Y4HC3WQXMJPK0WSETJHC/1696e83c4f5fdc08a7928a36719e589a2ff2d83aaa4f0858a8e37bf88aa2ad7f","ember:c-6e6e44657d"],"ops":[{"path":["unread"],"set":false}]}]}]},"w":1792551107269.648}
  #|{"in":{"id":9,"delta":[{"path":["badge"],"set":0},{"path":["workspaces","01M5E5Y4HC3WQXMJPK0WSETJHC","badge"],"set":0},{"path":["workspaces","01M5E5Y4HC3WQXMJPK0WSETJHC","items",0,"seen"],"set":true}]},"w":1792551107269.7}
  #|{"step":"now until 穿过下去的面板 082939","w":1792551107587.782}
  #|{"step":"gone 正在发送","w":1792551107587.84}
  #|{"step":"","w":1792551107587.861}
  #|{"textrec":{"ib":["bfd9b0d6dc602826",12668,64],"r":[56,56,56,56]}}
  #|{"textrec":{"s":[13,400,0,"正在读取你的 workspace"],"r":[0,1,12.898832684824903,0,1,1,12.898832684824903,1,2,1,12.898832684824903,2,3,1,12.898832684824903,3,4,1,12.898832684824896,4,5,1,12.898832684824896,5,6,1,3.580078125,-1,7,1,9.8642578125,6,8,1,7.4775390625,7,9,1,4.875,8,10,1,6.85546875,9,11,1,6.6015625,10,12,1,7.8583984375,11,13,1,7.0966796875,12,14,1,7.1982421875,13,15,1,7.3505859375,14]}}
  #|{"textrec":{"m":[13,400,0],"r":[12.568359375,2.7421875,18,12.568359375,2.7421875,0]}}
  #|{"textrec":{"s":[24,700,0,"Dev"],"r":[0,1,17.075823068618774,15,1,1,13.365240812301636,16,2,1,12.759063005447388,17]}}
  #|{"textrec":{"m":[24,700,0],"r":[23.203125,5.0625,34,20.638916015625,3.361083984375,0]}}
  #|{"textrec":{"g":15,"r":[0,0,18,19,0,-18,0]}}
  #|{"textrec":{"g":16,"r":[19,0,15,16,-1,-14,0]}}
  #|{"textrec":{"g":17,"r":[35,0,15,15,-1,-14,0]}}
  #|{"textrec":{"ib":["02698e60df92657e",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"ib":["fdb526ba00f881f4",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["1d51432b25a425eb",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"ib":["bef2954d97ce1d9f",6508,64],"r":[40,40,40,40]}}
  #|{"textrec":{"ib":["a7ccae3554fe46cf",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["c8ac90bf691295f0",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["31d8ec32aedeae00",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"s":[15,400,0,"搜索全部内容"],"r":[0,1,14.883268482490273,18,1,1,14.883268482490273,19,2,1,14.883268482490273,20,3,1,14.883268482490273,21,4,1,14.88326848249028,22,5,1,14.88326848249028,23]}}
  #|{"textrec":{"m":[15,400,0],"r":[14.501953125,3.1640625,21,14.501953125,3.1640625,0]}}
  #|{"textrec":{"s":[15,600,0,"今天"],"r":[0,1,14.883268482490273,24,1,1,14.883268482490273,25]}}
  #|{"textrec":{"m":[15,600,0],"r":[14.501953125,3.1640625,21,14.501953125,3.1640625,0]}}
  #|{"textrec":{"s":[16,400,0,"端到端测试的对话 post:你好，我是测试用的 agent"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,26,3,1,15.875486381322958,28,4,1,15.875486381322958,29,5,1,15.875486381322958,30,6,1,15.875486381322958,31,7,1,15.875486381322958,32,8,1,4.1875,-1,9,1,9.453125,33,10,1,9.140625,34,11,1,8.0234375,35,12,1,5.4609375,36,13,1,4.4375,37,14,1,15.875486381322958,38,15,1,15.875486381322958,39,16,1,16.09338521400778,40,17,1,15.875486381322958,41,18,1,15.875486381322958,42,19,1,15.87548638132293,28,20,1,15.875486381322958,29,21,1,15.875486381322958,43,22,1,15.875486381322958,30,23,1,4.1875,-1,24,1,8.515625,44,25,1,9.4375,45,26,1,8.828125,46,27,1,9.0234375,47,28,1,5.5,36]}}
  #|{"textrec":{"m":[16,400,0],"r":[15.46875,3.375,23,15.46875,3.375,0]}}
  #|{"textrec":{"s":[14,400,0,"出错：意外停止"],"r":[0,1,13.891050583657588,48,1,1,13.891050583657588,49,2,1,14.081712062256813,50,3,1,13.891050583657588,51,4,1,13.891050583657588,52,5,1,13.891050583657588,53,6,1,13.891050583657588,54]}}
  #|{"textrec":{"m":[14,400,0],"r":[13.53515625,2.953125,20,13.53515625,2.953125,0]}}
  #|{"textrec":{"s":[16,400,0,"…"],"r":[0,1,12.5625,55]}}
  #|{"textrec":{"s":[16,400,0,"端到端测试的对话 post:你好，我是测试用的…"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,26,3,1,15.875486381322958,28,4,1,15.875486381322958,29,5,1,15.875486381322958,30,6,1,15.875486381322958,31,7,1,15.875486381322958,32,8,1,4.1875,-1,9,1,9.453125,33,10,1,9.140625,34,11,1,8.0234375,35,12,1,5.4609375,36,13,1,4.4375,37,14,1,15.875486381322958,38,15,1,15.875486381322958,39,16,1,16.09338521400778,40,17,1,15.875486381322958,41,18,1,15.875486381322958,42,19,1,15.87548638132293,28,20,1,15.875486381322958,29,21,1,15.875486381322958,43,22,1,15.875486381322958,30,23,1,12.5625,55]}}
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
  #|{"textrec":{"g":33,"r":[317,0,10,14,0,-10,0]}}
  #|{"textrec":{"g":34,"r":[328,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":35,"r":[340,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":36,"r":[351,0,8,14,-1,-12,0]}}
  #|{"textrec":{"g":37,"r":[360,0,5,11,0,-9,0]}}
  #|{"textrec":{"g":38,"r":[366,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":39,"r":[384,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":40,"r":[402,0,6,7,0,-3,0]}}
  #|{"textrec":{"g":41,"r":[409,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":42,"r":[427,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":43,"r":[445,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":55,"r":[462,0,13,5,0,-3,0]}}
  #|{"textrec":{"g":48,"r":[476,0,14,16,0,-13,0]}}
  #|{"textrec":{"g":49,"r":[491,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":50,"r":[508,0,5,10,1,-10,0]}}
  #|{"textrec":{"g":51,"r":[514,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":52,"r":[531,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":53,"r":[548,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":54,"r":[564,0,15,15,-1,-13,0]}}
  #|{"textrec":{"ib":["33d1dfbf90932d3b",1241,64],"r":[17,17,17,17]}}
  #|{"textrec":{"ib":["182b7158e0c0cae1",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["d61ec6305f7d8c8b",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["8bf9607b651cec61",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"s":[17,700,0,"切换 workspace"],"r":[0,1,16.851167315175097,56,1,1,16.851167315175097,57,2,1,3.951171875,-1,3,1,13.783447265625,58,4,1,9.915283203125,59,5,1,6.96435546875,60,6,1,9.60400390625,61,7,1,9.010498046875,62,8,1,10.56689453125,63,9,1,9.591552734375,64,10,1,9.55419921875,65,11,1,9.782470703125,66]}}
  #|{"textrec":{"m":[17,700,0],"r":[16.435546875,3.5859375,24,16.435546875,3.5859375,0]}}
  #|{"textrec":{"s":[15,400,0,"登录其他账号"],"r":[0,1,14.883268482490273,67,1,1,14.883268482490273,68,2,1,14.883268482490273,69,3,1,14.883268482490273,70,4,1,14.88326848249028,71,5,1,14.88326848249028,72]}}
  #|{"textrec":{"s":[12,400,0,"保留已登录账号，添加另一个账号"],"r":[0,1,11.918287937743191,73,1,1,11.918287937743191,74,2,1,11.918287937743195,75,3,1,11.918287937743187,76,4,1,11.918287937743187,77,5,1,11.918287937743187,78,6,1,11.918287937743187,79,7,1,12.081712062256813,80,8,1,11.918287937743187,81,9,1,11.918287937743187,82,10,1,11.918287937743187,83,11,1,11.918287937743202,84,12,1,11.918287937743202,85,13,1,11.918287937743202,78,14,1,11.918287937743202,79]}}
  #|{"textrec":{"m":[12,400,0],"r":[11.6015625,2.53125,17,11.6015625,2.53125,0]}}
  #|{"textrec":{"s":[15,400,0,"新建 workspace"],"r":[0,1,14.883268482490273,86,1,1,14.883268482490273,87,2,1,3.984375,-1,3,1,11.2353515625,88,4,1,8.4814453125,89,5,1,5.478515625,90,6,1,7.763671875,91,7,1,7.470703125,92,8,1,8.9208984375,93,9,1,8.0419921875,94,10,1,8.1591796875,95,11,1,8.3349609375,96]}}
  #|{"textrec":{"s":[13,400,0,"当前使用"],"r":[0,1,12.898832684824903,97,1,1,12.898832684824903,98,2,1,12.898832684824903,99,3,1,12.898832684824903,100]}}
  #|{"textrec":{"s":[15,400,0,"Dev"],"r":[0,1,10.6640625,101,1,1,8.26171875,96,2,1,7.822265625,102]}}
  #|{"textrec":{"s":[12,400,0,"alice@example.test"],"r":[0,1,6.62109375,103,1,1,3.03515625,104,2,1,2.96484375,105,3,1,6.71484375,106,4,1,6.85546875,107,5,1,11.015625,108,6,1,6.73828125,107,7,1,6.17578125,109,8,1,6.62109375,103,9,1,10.44140625,110,10,1,7.32421875,111,11,1,3.03515625,104,12,1,6.85546875,107,13,1,3.4453125,112,14,1,4.1982421875,113,15,1,6.8115234375,107,16,1,6.251953125,114,17,1,4.330078125,113]}}
  #|{"textrec":{"g":56,"r":[580,0,18,18,-1,-15,0]}}
  #|{"textrec":{"g":57,"r":[599,0,19,18,-1,-15,0]}}
  #|{"textrec":{"g":58,"r":[619,0,16,12,-1,-11,0]}}
  #|{"textrec":{"g":59,"r":[636,0,12,13,-1,-11,0]}}
  #|{"textrec":{"g":60,"r":[649,0,8,12,0,-11,0]}}
  #|{"textrec":{"g":61,"r":[658,0,11,15,0,-14,0]}}
  #|{"textrec":{"g":62,"r":[670,0,11,13,-1,-11,0]}}
  #|{"textrec":{"g":63,"r":[682,0,12,16,0,-11,0]}}
  #|{"textrec":{"g":64,"r":[695,0,11,13,-1,-11,0]}}
  #|{"textrec":{"g":65,"r":[707,0,12,13,-1,-11,0]}}
  #|{"textrec":{"g":66,"r":[720,0,12,13,-1,-11,0]}}
  #|{"textrec":{"g":97,"r":[733,0,13,15,0,-12,0]}}
  #|{"textrec":{"g":98,"r":[747,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":99,"r":[763,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":100,"r":[779,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":101,"r":[794,0,11,13,0,-12,0]}}
  #|{"textrec":{"g":96,"r":[806,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":102,"r":[817,0,10,10,-1,-9,0]}}
  #|{"textrec":{"g":103,"r":[828,0,8,10,-1,-8,0]}}
  #|{"textrec":{"g":104,"r":[837,0,4,11,0,-10,0]}}
  #|{"textrec":{"g":105,"r":[842,0,5,11,-1,-10,0]}}
  #|{"textrec":{"g":106,"r":[848,0,9,10,-1,-8,0]}}
  #|{"textrec":{"g":107,"r":[858,0,9,10,-1,-8,0]}}
  #|{"textrec":{"g":108,"r":[868,0,13,13,-1,-10,0]}}
  #|{"textrec":{"g":109,"r":[882,0,8,9,-1,-8,0]}}
  #|{"textrec":{"g":110,"r":[891,0,12,9,-1,-8,0]}}
  #|{"textrec":{"g":111,"r":[904,0,9,12,-1,-8,0]}}
  #|{"textrec":{"g":112,"r":[914,0,4,5,0,-3,0]}}
  #|{"textrec":{"g":113,"r":[919,0,6,11,-1,-9,0]}}
  #|{"textrec":{"g":114,"r":[926,0,8,10,-1,-8,0]}}
  #|{"textrec":{"g":67,"r":[935,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":68,"r":[953,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":69,"r":[970,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":70,"r":[987,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":71,"r":[1004,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":72,"r":[1022,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":73,"r":[1039,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":74,"r":[1054,0,13,14,-1,-11,0]}}
  #|{"textrec":{"g":75,"r":[1068,0,13,12,0,-10,0]}}
  #|{"textrec":{"g":76,"r":[1082,0,14,13,-1,-11,0]}}
  #|{"textrec":{"g":77,"r":[1097,0,13,14,-1,-11,0]}}
  #|{"textrec":{"g":78,"r":[1111,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":79,"r":[1126,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":80,"r":[1141,0,5,6,0,-3,0]}}
  #|{"textrec":{"g":81,"r":[1147,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":82,"r":[1162,0,13,14,-1,-11,0]}}
  #|{"textrec":{"g":83,"r":[1176,0,13,14,-1,-11,0]}}
  #|{"textrec":{"g":84,"r":[1190,0,14,4,-1,-6,0]}}
  #|{"textrec":{"g":85,"r":[1205,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":86,"r":[1220,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":87,"r":[1238,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":88,"r":[1255,0,14,10,-1,-9,0]}}
  #|{"textrec":{"g":89,"r":[1270,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":90,"r":[1282,0,7,11,0,-10,0]}}
  #|{"textrec":{"g":91,"r":[1290,0,9,14,0,-13,0]}}
  #|{"textrec":{"g":92,"r":[1300,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":93,"r":[1311,0,10,14,0,-10,0]}}
  #|{"textrec":{"g":94,"r":[1322,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":95,"r":[1333,0,10,12,-1,-10,0]}}
  #|{"textrec":{"ib":["e13e77444a4987cd",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["d87c77ac2dcb8d23",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["2bb63fc1d380f765",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"s":[24,700,0,"文件"],"r":[0,1,22.849624060150376,115,1,1,22.849624060150376,116]}}
  #|{"textrec":{"s":[15,600,0,"studio"],"r":[0,1,8.000344634056091,117,1,1,5.658300518989563,118,2,1,8.93320620059967,119,3,1,9.332013130187988,120,4,1,3.8520312309265137,121,5,1,8.901597261428833,122]}}
  #|{"textrec":{"s":[16,400,0,"主目录"],"r":[0,1,15.875486381322958,123,1,1,15.875486381322958,124,2,1,15.875486381322958,125]}}
  #|{"textrec":{"ib":["504a4df6beac534a",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["6727d74824d9e7b3",3698,64],"r":[30,30,30,30]}}
  #|{"textrec":{"ib":["e8253a4a9ea8c5de",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"m":[16,600,0],"r":[15.46875,3.375,23,15.46875,3.375,0]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 post:你好，我是测试用的 agent"],"r":[0,1,15.875486381322958,126,1,1,15.875486381322958,127,2,1,15.875486381322958,126,3,1,15.875486381322958,128,4,1,15.875486381322958,129,5,1,15.875486381322958,130,6,1,15.875486381322958,131,7,1,15.875486381322958,132,8,1,3.95001220703125,-1,9,1,9.824199676513672,133,10,1,9.432537078857422,134,11,1,8.471200942993164,135,12,1,5.973020553588867,136,13,1,4.952056884765625,137,14,1,15.875486381322958,138,15,1,15.875486381322958,139,16,1,16.09338521400778,140,17,1,15.875486381322958,141,18,1,15.875486381322958,142,19,1,15.87548638132293,128,20,1,15.875486381322958,129,21,1,15.875486381322958,143,22,1,15.875486381322958,130,23,1,3.95001220703125,-1,24,1,8.899068832397461,144,25,1,9.801153182983398,145,26,1,9.127458572387695,146,27,1,9.466253280639648,147,28,1,5.999713897705078,136]}}
  #|{"textrec":{"s":[12,400,0,"studio"],"r":[0,1,6.251953125,114,1,1,4.330078125,113,2,1,7.001953125,148,3,1,7.37109375,149,4,1,2.96484375,105,5,1,7.08984375,150]}}
  #|{"textrec":{"s":[8,600,0,"N"],"r":[0,1,6.271738052368164,151]}}
  #|{"textrec":{"m":[8,600,0],"r":[7.734375,1.6875,11,7.734375,1.6875,0]}}
  #|{"textrec":{"s":[15,400,0,"本轮 agent 未在对话中回复，以下是它最后输出的文字，由 station 代为转发（并非它发布的消息）；回复即可继续："],"r":[0,1,14.883268482490273,152,1,1,14.883268482490273,153,2,1,3.984375,-1,3,1,8.0419921875,94,4,1,8.90625,154,5,1,8.3349609375,96,6,1,8.51806640625,155,7,1,5.21484375,156,8,1,3.984375,-1,9,1,14.883268482490266,157,10,1,14.88326848249028,158,11,1,14.88326848249028,159,12,1,14.88326848249028,160,13,1,14.88326848249028,161,14,1,14.88326848249028,162,15,1,14.88326848249028,163,16,1,15.08754863813229,164,17,1,14.88326848249028,165,18,1,14.88326848249028,166,19,1,14.88326848249028,167,20,1,14.88326848249028,168,21,1,14.88326848249028,169,22,1,14.88326848249028,170,23,1,14.88326848249028,171,24,1,14.88326848249028,172,25,1,14.88326848249028,173,26,1,14.88326848249028,174,27,1,14.88326848249028,175,28,1,15.087548638132319,164,29,1,14.88326848249028,176,30,1,3.984375,-1,31,1,7.58056640625,92,32,1,5.17822265625,156,33,1,8.0419921875,94,34,1,5.21484375,156,35,1,3.4716796875,177,36,1,8.6279296875,89,37,1,8.51806640625,155,38,1,3.984375,-1,39,1,14.88326848249028,178,40,1,14.88326848249028,179,41,1,14.88326848249028,180,42,1,22.38326848249028,181,43,1,4.698443579766547,182,44,1,14.88326848249028,183,45,1,14.88326848249028,184,46,1,14.88326848249028,168,47,1,14.88326848249028,181,48,1,14.88326848249028,185,49,1,14.88326848249028,173,50,1,14.88326848249028,186,51,1,14.88326848249028,187,52,1,6.296206225680976,188,53,1,15.087548638132262,189,54,1,14.88326848249028,162,55,1,14.88326848249028,163,56,1,14.88326848249028,190,57,1,14.88326848249028,191,58,1,14.88326848249028,192,59,1,14.88326848249028,193,60,1,7.587548638132262,194]}}
  #|{"textrec":{"s":[15,400,0," · "],"r":[0,1,3.984375,-1,1,1,7.186782927948601,195,2,1,3.984375,-1]}}
  #|{"textrec":{"s":[15,600,0,"上报"],"r":[0,1,14.883268482490273,196,1,1,14.883268482490273,197]}}
  #|{"textrec":{"s":[15,400,0,"…"],"r":[0,1,11.8359375,198]}}
  #|{"textrec":{"s":[15,400,0,"本轮 agent 未在对话中回复，以下是它最后…"],"r":[0,1,14.883268482490273,152,1,1,14.883268482490273,153,2,1,3.984375,-1,3,1,8.0419921875,94,4,1,8.90625,154,5,1,8.3349609375,96,6,1,8.51806640625,155,7,1,5.21484375,156,8,1,3.984375,-1,9,1,14.883268482490266,157,10,1,14.88326848249028,158,11,1,14.88326848249028,159,12,1,14.88326848249028,160,13,1,14.88326848249028,161,14,1,14.88326848249028,162,15,1,14.88326848249028,163,16,1,15.08754863813229,164,17,1,14.88326848249028,165,18,1,14.88326848249028,166,19,1,14.88326848249028,167,20,1,14.88326848249028,168,21,1,14.88326848249028,169,22,1,14.88326848249028,170,23,1,11.8359375,198]}}
  #|{"textrec":{"s":[16,400,0,"栏下去时点的 082939"],"r":[0,1,15.875486381322958,199,1,1,15.875486381322958,200,2,1,15.875486381322958,201,3,1,15.875486381322958,202,4,1,15.875486381322958,203,5,1,15.875486381322958,30,6,1,4.1875,-1,7,1,9.765625,204,8,1,9.90625,205,9,1,9.34375,206,10,1,9.875,207,11,1,9.71875,208,12,1,9.875,207]}}
  #|{"textrec":{"s":[10,400,0,"刚刚"],"r":[0,1,9.941634241245136,209,1,1,9.941634241245136,209]}}
  #|{"textrec":{"m":[10,400,0],"r":[9.66796875,2.109375,14,9.66796875,2.109375,0]}}
  #|{"textrec":{"s":[15,650,0,"默认模型"],"r":[0,1,14.883268482490273,210,1,1,14.883268482490273,211,2,1,14.883268482490273,212,3,1,14.883268482490273,213]}}
  #|{"textrec":{"m":[15,650,0],"r":[14.501953125,3.1640625,21,14.501953125,3.1640625,0]}}
  #|{"textrec":{"s":[15,400,0,"你好，我是测试用的 agent"],"r":[0,1,14.883268482490273,214,1,1,14.883268482490273,215,2,1,15.087548638132297,164,3,1,14.883268482490273,216,4,1,14.883268482490266,167,5,1,14.88326848249028,217,6,1,14.88326848249028,218,7,1,14.88326848249028,219,8,1,14.88326848249028,173,9,1,3.984375,-1,10,1,8.0419921875,94,11,1,8.90625,154,12,1,8.3349609375,96,13,1,8.51806640625,155,14,1,5.21484375,156]}}
  #|{"textrec":{"s":[16,600,0,"…"],"r":[0,1,14.076484680175781,220]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 post:…"],"r":[0,1,15.875486381322958,126,1,1,15.875486381322958,127,2,1,15.875486381322958,126,3,1,15.875486381322958,128,4,1,15.875486381322958,129,5,1,15.875486381322958,130,6,1,15.875486381322958,131,7,1,15.875486381322958,132,8,1,3.95001220703125,-1,9,1,9.824199676513672,133,10,1,9.432537078857422,134,11,1,8.471200942993164,135,12,1,5.973020553588867,136,13,1,4.952056884765625,137,14,1,14.076484680175781,220]}}
  #|{"textrec":{"g":214,"r":[1344,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":215,"r":[1361,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":164,"r":[1378,0,5,7,0,-3,0]}}
  #|{"textrec":{"g":216,"r":[1384,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":167,"r":[1402,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":217,"r":[1419,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":218,"r":[1436,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":219,"r":[1454,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":173,"r":[1470,0,15,17,0,-14,0]}}
  #|{"textrec":{"g":154,"r":[1486,0,10,14,-1,-10,0]}}
  #|{"textrec":{"g":155,"r":[1497,0,9,11,0,-10,0]}}
  #|{"textrec":{"g":156,"r":[1507,0,7,13,-1,-11,0]}}
  #|{"textrec":{"g":152,"r":[1515,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":153,"r":[1533,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":157,"r":[1551,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":158,"r":[1568,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":159,"r":[1585,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":160,"r":[1602,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":161,"r":[1620,0,15,16,0,-13,0]}}
  #|{"textrec":{"g":162,"r":[1636,0,15,16,0,-13,0]}}
  #|{"textrec":{"g":163,"r":[1652,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":165,"r":[1669,0,16,16,0,-13,0]}}
  #|{"textrec":{"g":166,"r":[1686,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":168,"r":[1703,0,15,17,0,-14,0]}}
  #|{"textrec":{"g":169,"r":[1719,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":170,"r":[1736,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":198,"r":[1753,0,12,5,0,-3,0]}}
  #|{"textrec":{"ib":["11ba9484460f477d",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["a1e7be43eb966606",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"ib":["c7a6d30e254a5910",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"g":44,"r":[1766,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":45,"r":[1777,0,11,14,-1,-10,0]}}
  #|{"textrec":{"g":46,"r":[1789,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":47,"r":[1801,0,10,11,0,-10,0]}}
  #|{"textrec":{"g":210,"r":[1812,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":211,"r":[1830,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":212,"r":[1848,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":213,"r":[1866,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":126,"r":[1883,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":127,"r":[1901,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":128,"r":[1919,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":129,"r":[1937,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":130,"r":[1956,0,16,17,0,-14,0]}}
  #|{"textrec":{"g":131,"r":[1973,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":132,"r":[1991,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":133,"r":[2010,0,11,14,0,-10,0]}}
  #|{"textrec":{"g":134,"r":[2022,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":135,"r":[2034,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":136,"r":[0,20,8,14,-1,-12,0]}}
  #|{"textrec":{"g":137,"r":[9,20,5,12,0,-10,0]}}
  #|{"textrec":{"g":220,"r":[15,20,14,6,0,-4,0]}}
  #|{"textrec":{"s":[16,400,0,"发消息"],"r":[0,1,15.875486381322958,221,1,1,15.875486381322958,222,2,1,15.875486381322958,223]}}
  #|{"textrec":{"g":221,"r":[30,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":222,"r":[48,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":223,"r":[66,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":209,"r":[84,20,11,11,-1,-9,0]}}
  #|{"textrec":{"g":199,"r":[96,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":200,"r":[114,20,17,16,-1,-13,0]}}
  #|{"textrec":{"g":201,"r":[132,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":202,"r":[150,20,16,17,0,-14,0]}}
  #|{"textrec":{"g":203,"r":[167,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":204,"r":[185,20,11,15,0,-13,0]}}
  #|{"textrec":{"g":205,"r":[197,20,11,15,0,-13,0]}}
  #|{"textrec":{"g":206,"r":[209,20,10,14,0,-13,0]}}
  #|{"textrec":{"g":207,"r":[220,20,11,15,0,-13,0]}}
  #|{"textrec":{"g":208,"r":[232,20,11,15,0,-13,0]}}
  #|{"textrec":{"g":151,"r":[244,20,8,8,-1,-7,0]}}
  #|{"textrec":{"g":148,"r":[253,20,9,10,-1,-8,0]}}
  #|{"textrec":{"g":149,"r":[263,20,9,12,-1,-10,0]}}
  #|{"textrec":{"g":150,"r":[273,20,9,10,-1,-8,0]}}
  #|{"textrec":{"g":195,"r":[283,20,5,5,1,-8,0]}}
  #|{"textrec":{"g":196,"r":[289,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":197,"r":[306,20,17,16,-1,-13,0]}}
  #|{"textrec":{"ib":["b277602c41d156e7",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"ib":["ddfdc2820df8a676",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"s":[18,700,0,"端到端测试的对话 post:你好，我是测试用的 agent"],"r":[0,1,17.842412451361866,224,1,1,17.842412451361866,225,2,1,17.842412451361866,224,3,1,17.842412451361866,226,4,1,17.842412451361866,227,5,1,17.842412451361866,228,6,1,17.842412451361866,229,7,1,17.842412451361866,230,8,1,4.152015030384064,-1,9,1,11.16209328174591,231,10,1,10.675500869750977,232,11,1,9.692523032426834,233,12,1,6.919372379779816,234,13,1,5.73083621263504,235,14,1,17.842412451361866,236,15,1,17.842412451361866,237,16,1,18.08754863813229,238,17,1,17.842412451361866,239,18,1,17.842412451361838,240,19,1,17.842412451361838,226,20,1,17.842412451361838,227,21,1,17.842412451361838,241,22,1,17.842412451361838,228,23,1,4.152015030384064,-1,24,1,10.138570368289948,242,25,1,11.132530510425568,243,26,1,10.337921261787415,244,27,1,10.808134496212006,245,28,1,6.940345913171768,234]}}
  #|{"textrec":{"m":[18,700,0],"r":[17.40234375,3.796875,26,17.40234375,3.796875,0]}}
  #|{"textrec":{"s":[13,400,0,"你 刚刚发起 · 最新 刚刚"],"r":[0,1,12.898832684824903,4,1,1,3.580078125,-1,2,1,12.898832684824903,246,3,1,12.898832684824903,246,4,1,12.898832684824903,247,5,1,12.898832684824896,248,6,1,3.580078125,-1,7,1,6.228545204222115,249,8,1,3.580078125,-1,9,1,12.898832684824896,250,10,1,12.898832684824896,251,11,1,3.580078125,-1,12,1,12.898832684824896,246,13,1,12.898832684824896,246]}}
  #|{"textrec":{"s":[15,600,0,"默认模型"],"r":[0,1,14.883268482490273,252,1,1,14.883268482490273,253,2,1,14.883268482490273,254,3,1,14.883268482490273,255]}}
  #|{"textrec":{"s":[12,400,0,"出错：意外停止 · 刚刚"],"r":[0,1,11.918287937743191,256,1,1,11.918287937743191,257,2,1,12.081712062256805,258,3,1,11.918287937743187,259,4,1,11.918287937743187,260,5,1,11.918287937743187,261,6,1,11.918287937743187,262,7,1,3.375,-1,8,1,5.754933455713626,263,9,1,3.375,-1,10,1,11.918287937743187,264,11,1,11.918287937743187,264]}}
  #|{"textrec":{"s":[14,400,0,"固定到列表顶部"],"r":[0,1,13.891050583657588,265,1,1,13.891050583657588,266,2,1,13.891050583657588,267,3,1,13.891050583657588,268,4,1,13.891050583657588,269,5,1,13.891050583657588,270,6,1,13.891050583657588,271]}}
  #|{"textrec":{"s":[14,400,0,"复制会话链接"],"r":[0,1,13.891050583657588,272,1,1,13.891050583657588,273,2,1,13.891050583657588,274,3,1,13.891050583657588,275,4,1,13.891050583657588,276,5,1,13.891050583657588,277]}}
  #|{"textrec":{"s":[14,400,0,"归档对话"],"r":[0,1,13.891050583657588,278,1,1,13.891050583657588,279,2,1,13.891050583657588,280,3,1,13.891050583657588,275]}}
  #|{"textrec":{"s":[14,400,0,"公开分享"],"r":[0,1,13.891050583657588,281,1,1,13.891050583657588,282,2,1,13.891050583657588,283,3,1,13.891050583657588,284]}}
  #|{"textrec":{"g":224,"r":[324,20,19,19,-1,-16,0]}}
  #|{"textrec":{"g":225,"r":[344,20,19,19,-1,-16,0]}}
  #|{"textrec":{"g":226,"r":[364,20,19,19,-1,-16,0]}}
  #|{"textrec":{"g":227,"r":[384,20,20,19,-1,-16,0]}}
  #|{"textrec":{"g":228,"r":[405,20,18,19,0,-16,0]}}
  #|{"textrec":{"g":229,"r":[424,20,19,19,-1,-16,0]}}
  #|{"textrec":{"g":230,"r":[444,20,20,19,-1,-16,0]}}
  #|{"textrec":{"g":231,"r":[465,20,12,16,0,-11,0]}}
  #|{"textrec":{"g":232,"r":[478,20,13,13,-1,-11,0]}}
  #|{"textrec":{"g":233,"r":[492,20,12,13,-1,-11,0]}}
  #|{"textrec":{"g":234,"r":[505,20,9,15,-1,-13,0]}}
  #|{"textrec":{"g":235,"r":[515,20,6,13,0,-11,0]}}
  #|{"textrec":{"g":236,"r":[522,20,19,19,-1,-16,0]}}
  #|{"textrec":{"g":237,"r":[542,20,19,19,-1,-16,0]}}
  #|{"textrec":{"g":238,"r":[562,20,7,9,0,-4,0]}}
  #|{"textrec":{"g":239,"r":[570,20,19,19,-1,-16,0]}}
  #|{"textrec":{"g":240,"r":[590,20,19,18,-1,-15,0]}}
  #|{"textrec":{"g":241,"r":[610,20,18,18,-1,-15,0]}}
  #|{"textrec":{"g":242,"r":[629,20,12,13,-1,-11,0]}}
  #|{"textrec":{"g":243,"r":[642,20,13,16,-1,-11,0]}}
  #|{"textrec":{"g":244,"r":[656,20,12,13,-1,-11,0]}}
  #|{"textrec":{"g":245,"r":[669,20,12,12,0,-11,0]}}
  #|{"textrec":{"g":4,"r":[682,20,14,15,-1,-12,0]}}
  #|{"textrec":{"g":246,"r":[697,20,14,15,-1,-12,0]}}
  #|{"textrec":{"g":247,"r":[712,20,14,15,-1,-12,0]}}
  #|{"textrec":{"g":248,"r":[727,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":249,"r":[743,20,4,5,1,-7,0]}}
  #|{"textrec":{"g":250,"r":[748,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":251,"r":[763,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":252,"r":[779,20,17,16,-1,-13,0]}}
  #|{"textrec":{"g":253,"r":[797,20,17,16,-1,-13,0]}}
  #|{"textrec":{"g":254,"r":[815,20,17,16,-1,-13,0]}}
  #|{"textrec":{"g":255,"r":[833,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":256,"r":[850,20,12,14,0,-11,0]}}
  #|{"textrec":{"g":257,"r":[863,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":258,"r":[878,20,4,9,1,-9,0]}}
  #|{"textrec":{"g":259,"r":[883,20,14,13,-1,-11,0]}}
  #|{"textrec":{"g":260,"r":[898,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":261,"r":[913,20,13,14,-1,-11,0]}}
  #|{"textrec":{"g":262,"r":[927,20,14,13,-1,-11,0]}}
  #|{"textrec":{"g":263,"r":[942,20,5,5,0,-7,0]}}
  #|{"textrec":{"g":264,"r":[948,20,13,14,-1,-11,0]}}
  #|{"textrec":{"g":265,"r":[962,20,14,15,0,-12,0]}}
  #|{"textrec":{"g":266,"r":[977,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":267,"r":[993,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":268,"r":[1009,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":269,"r":[1025,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":270,"r":[1041,20,16,15,-1,-12,0]}}
  #|{"textrec":{"g":271,"r":[1058,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":272,"r":[1074,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":273,"r":[1090,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":274,"r":[1106,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":275,"r":[1123,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":276,"r":[1140,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":277,"r":[1157,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":278,"r":[1173,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":279,"r":[1189,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":280,"r":[1205,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":281,"r":[1221,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":282,"r":[1238,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":283,"r":[1254,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":284,"r":[1271,20,16,16,-1,-13,0]}}
  #|{"textrec":{"ib":["92022e9e11aef691",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"ib":["f1276e6323a9ca06",1853,64],"r":[21,21,21,21]}}
  #|{"textrec":{"ib":["030aece180ce0f3c",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"ib":["b3685975cd23abc3",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["b9bedad57f2a5f13",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"ib":["97cc1349f5996766",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"ib":["82d8240109550b08",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"s":[16,400,0,"穿过下去的面板 082939"],"r":[0,1,15.875486381322958,285,1,1,15.875486381322958,286,2,1,15.875486381322958,200,3,1,15.875486381322958,201,4,1,15.875486381322958,30,5,1,15.875486381322958,287,6,1,15.875486381322958,288,7,1,4.1875,-1,8,1,9.765625,204,9,1,9.90625,205,10,1,9.34375,206,11,1,9.875,207,12,1,9.71875,208,13,1,9.875,207]}}
  #|{"textrec":{"g":285,"r":[1288,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":286,"r":[1306,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":287,"r":[1324,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":288,"r":[1342,20,18,17,-1,-14,0]}}
  #|{"textrec":{"ib":["9699dbc96b0fdfd9",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"s":[10,400,0,"正在发送"],"r":[0,1,9.941634241245136,289,1,1,9.941634241245136,290,2,1,9.941634241245136,291,3,1,9.941634241245136,292]}}
  #|{"textrec":{"g":289,"r":[1361,20,12,11,-1,-9,0]}}
  #|{"textrec":{"g":290,"r":[1374,20,12,13,-1,-10,0]}}
  #|{"textrec":{"g":291,"r":[1387,20,12,13,-1,-10,0]}}
  #|{"textrec":{"g":292,"r":[1400,20,12,13,-1,-10,0]}}
