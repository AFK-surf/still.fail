// e2e/traces/history.trace, made by scripts/trace.py from 06-history.log: not edited by hand.

///|
/// What the app and its core said in the run, a line each.
pub let trace_history : String =
  #|{"env":{"MBUI_CLOUD":"http://127.0.0.1:18787","MBUI_CORE_ACCOUNT":"{\"sub\":\"alice\",\"email\":\"alice@example.test\",\"name\":\"Name of alice\",\"picture\":\"\",\"access\":\"-\",\"refresh\":\"-\",\"accessExpires\":1792548983}"}}
  #|{"out":{"id":1,"call":"client.device","params":{"client":"still.fail mbui","app":"desktop","userAgent":"Macintosh; Mac OS X"}},"w":1792548785740.122}
  #|{"in":{"id":1,"ok":null},"w":1792548785818.002}
  #|{"out":{"id":2,"subscribe":{"topic":"accounts"},"keyed":true},"w":1792548785818.025}
  #|{"out":{"id":3,"subscribe":{"topic":"prefs"},"keyed":true},"w":1792548785818.034}
  #|{"step":"# written by scripts/rerecord.sh from its test (src/sfreplay/emit.mbt): not edited by hand","w":1792548785819.409}
  #|{"step":"timeout 90000","w":1792548785819.415}
  #|{"step":"answered client.device","w":1792548785819.417}
  #|{"step":"answered client.focus","w":1792548785845.881}
  #|{"in":{"id":2,"value":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""}]},"w":1792548785911.908}
  #|{"in":{"id":3,"value":{"onlyMine":false,"onlyWatching":false,"onlyDecisions":false,"listFilter":{},"appearance":"system","rowPicture":"auto","absoluteTime":false,"lang":"zh","keys":{},"lastChat":{},"openChat":{"01M5E3MC1B496BJETXKX7JNGSF":{"station":"01M5E3MC1B496BJETXKX7JNGSF/138ba6116d729e54bf1241baf74a72cecff00ecf0b23bff83d1345178b6cb111","key":"ember:c-4d25e6d2a3"}},"chatTabs":{},"dropFiles":{},"driveViews":{},"resume":{},"stationUpdatesDismissed":{},"device":{"app":"desktop","phone":false,"handoff":false},"reader":{"size":18,"line":1.7,"margin":22,"face":"sans","indent":true,"paper":"follow"},"rails":{},"bars":{"sets":[["chats","files","profiles","stations"],["decisions","usage","connects","archive"]],"current":0},"barsBy":{},"fonts":{},"faces":{"ui":{"id":"","name":"","mono":false,"family":"","files":[],"bytes":0},"text":{"id":"","name":"","mono":false,"family":"","files":[],"bytes":0},"code":{"id":"","name":"","mono":true,"family":"","files":[],"bytes":0},"list":[{"id":"inter","name":"Inter","mono":false,"family":"SF Inter","css":"http://127.0.0.1:18787/releases/fonts/inter/4.001/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/inter/4.001/var.ttf.gz","bytes":457818,"sha256":"29160a80ff49ddcab2c97711247e08b1fab27a484a329ce8b813d820dc559031"}],"preview":"http://127.0.0.1:18787/releases/fonts/inter/4.001/preview-194fa287.ttf","bytes":457818},{"id":"noto-sans-sc","name":"思源黑体","mono":false,"family":"SF Noto Sans SC","css":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/var.ttf.gz","bytes":11276563,"sha256":"a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da"}],"preview":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/preview-f0494178.ttf","bytes":11276563},{"id":"noto-serif-sc","name":"思源宋体","mono":false,"family":"SF Noto Serif SC","css":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/var.ttf.gz","bytes":15454579,"sha256":"050080d9255a86808f2945bffac582b31ef32bc36411ce29563b4961670c66f9"}],"preview":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/preview-001bbedf.ttf","bytes":15454579},{"id":"lxgw-wenkai","name":"霞鹜文楷","mono":false,"family":"SF LXGW WenKai","css":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/font.css","files":[{"weight":400,"url":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/400.ttf.gz","bytes":12904482,"sha256":"2d73eea94ad808999d90c0000c239a84a33b09d4bc6ab6c5b8bbf1eda8a7fc8b"},{"weight":500,"url":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/500.ttf.gz","bytes":13272430,"sha256":"f4b8a34d1f838fe411540cb7c97b1c384ac9738a876c4104500bc42508b2312a"}],"preview":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/preview-d3505af4.ttf","bytes":26176912},{"id":"jetbrains-mono","name":"JetBrains Mono","mono":true,"family":"SF JetBrains Mono","css":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/var.ttf.gz","bytes":90579,"sha256":"48715a42ec242c21e9f02692891e147d022299a52e48d5e413e1a942193ffeda"}],"preview":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/preview-ee73078f.ttf","bytes":90579},{"id":"fira-code","name":"Fira Code","mono":true,"family":"SF Fira Code","css":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/var.ttf.gz","bytes":137151,"sha256":"9335b082b3c7850d98a64b584f3417f65355f3471278bb5eeb8c6c0e8657aeeb"}],"preview":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/preview-555be27a.ttf","bytes":137151},{"id":"maple-mono","name":"Maple Mono","mono":true,"family":"SF Maple Mono CN","css":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/font.css","files":[{"weight":400,"url":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/400.ttf.gz","bytes":8352545,"sha256":"0fcc5139bfd5ab14ff989bb7dfd5236d0cafc10e60b9828569e6883613ab4085"},{"weight":600,"url":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/600.ttf.gz","bytes":8438132,"sha256":"96ed7ae26ee7c50b02b2d2b2bc0f1a0cbabe45ae5d6e6abf6678e2177c415677"}],"preview":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/preview-cffdf246.ttf","bytes":16790677}]}}},"w":1792548785911.949}
  #|{"out":{"id":4,"subscribe":{"topic":"workspaces"},"keyed":true},"w":1792548785911.997}
  #|{"out":{"id":5,"subscribe":{"topic":"status"},"keyed":true},"w":1792548785912.01}
  #|{"in":{"id":4,"value":[{"account":{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""},"workspaces":[{"id":"01M5E3MC1B496BJETXKX7JNGSF","name":"Dev","role":"owner","created_at":1792548679,"stations":1,"members":1,"relays":[],"time":{"created_at":{"past":true,"at":1792548679000,"ago":"2 分钟前","full":"10/21 10:11:19","until":"1 分钟内"}}}],"invitations":[],"relay_url":"http://127.0.0.1:18740","loaded":true,"beta":true}]},"w":1792548785928.582}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792548785928.598}
  #|{"out":{"id":6,"subscribe":{"topic":"lock","workspace":"01M5E3MC1B496BJETXKX7JNGSF"},"keyed":true},"w":1792548785928.63}
  #|{"out":{"id":7,"subscribe":{"topic":"chats","scope":"01M5E3MC1B496BJETXKX7JNGSF","mine":false},"keyed":true},"w":1792548785928.645}
  #|{"out":{"id":8,"subscribe":{"topic":"changelog"},"keyed":true},"w":1792548785928.652}
  #|{"out":{"id":9,"subscribe":{"topic":"workspaceMarks","workspace":"01M5E3MC1B496BJETXKX7JNGSF"},"keyed":true},"w":1792548785928.776}
  #|{"out":{"id":10,"subscribe":{"topic":"status","workspace":"01M5E3MC1B496BJETXKX7JNGSF"},"keyed":true},"w":1792548785928.813}
  #|{"out":{"id":11,"call":"client.focus","params":{"visible":true,"focused":true,"workspace":"01M5E3MC1B496BJETXKX7JNGSF"}},"w":1792548785936.096}
  #|{"out":{"id":12,"subscribe":{"topic":"notify"},"keyed":true},"w":1792548785936.11}
  #|{"out":{"id":13,"subscribe":{"topic":"notify","workspace":"01M5E3MC1B496BJETXKX7JNGSF"},"keyed":true},"w":1792548785936.118}
  #|{"in":{"id":6,"value":{"available":true,"locked":false,"notice":true,"role":"owner","manages":true,"owner":true,"canSign":true,"signs":false,"me":{"device":"a49b9649c51f7154da373b273e5d2ee5f2088787e8f26b3131fbb01f6eed23e8","code":"5SM-5FJ","kind":"app","confirmed":false,"waiting":false,"asked":false},"signers":0,"members":[],"stations":[{"id":"138ba6116d729e54bf1241baf74a72cecff00ecf0b23bff83d1345178b6cb111","name":"studio","version":"0.1.0","online":true,"protected":false}],"protected":0,"requests":[],"renew":[],"attention":0}},"w":1792548785947.366}
  #|{"in":{"id":7,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"stations":[{"station":"01M5E3MC1B496BJETXKX7JNGSF/138ba6116d729e54bf1241baf74a72cecff00ecf0b23bff83d1345178b6cb111","id":"138ba6116d729e54bf1241baf74a72cecff00ecf0b23bff83d1345178b6cb111","name":"studio","state":"online"}],"loading":false,"days":[{"daysAgo":0,"at":1792548784629,"label":"今天","items":[{"id":"ember:c-4d25e6d2a3","session":"ember:c-4d25e6d2a3","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","agents":[{"key":"ember:c-4d25e6d2a3","runtime":"claude","process":"warm","pending":0,"lastTurn":{"id":"46503dc6-afcd-49e5-b55a-d728c889a76c","kind":"input","outcome":"completed","declared":"block","ending":"need_help","need":"先合并哪个分支 083209","about":{"thread":1,"seq":12,"ts":"1792548784.629000"},"startedAt":1792548784621,"endedAt":1792548784634},"agentText":"默认模型","mark":"block","statusText":"需要你处理：先合并哪个分支 083209","badgeText":"agent 已暂停，等待处理"}],"last":{"seq":12,"authorKind":"agent","author":"ember:c-4d25e6d2a3","text":"先合并哪个分支 083209","createdAt":1792548784629,"by":{"kind":"agent","name":"agent","mine":false,"runtime":"claude","state":"block","label":"agent（agent 已暂停，等待处理）"},"preview":"先合并哪个分支 083209","time":{"createdAt":{"at":1792548784629,"ago":"刚刚","full":"10/21 10:13:04","until":"1 分钟内","past":true}}},"unread":false,"mine":true,"lastActiveAt":1792548784629,"station":"01M5E3MC1B496BJETXKX7JNGSF/138ba6116d729e54bf1241baf74a72cecff00ecf0b23bff83d1345178b6cb111","stationName":"studio","time":{"lastActiveAt":{"at":1792548784629,"ago":"刚刚","full":"10/21 10:13:04","until":"1 分钟内","past":true}},"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"peopleText":"你 发起","clientKey":"new:chat-3cc8a26dbd3be52c94","pinned":false,"decision":{"seq":12,"options":[{"label":"先合 A 083209"},{"label":"先合 B 083209"}],"card":{"type":"options","options":[{"label":"先合 A 083209"},{"label":"先合 B 083209"}]},"dismissed":true}},{"id":"ember:c-f77fef823b","session":"ember:c-f77fef823b","thread":2,"title":"要归档的对话 083209 post:归档前的回复 083209","agents":[{"key":"ember:c-f77fef823b","runtime":"claude","process":"cold","pending":0,"lastTurn":{"id":"d84f99f0-2bb3-4c00-8f4c-4769ac06f96e","kind":"input","outcome":"completed","startedAt":1792548777129,"endedAt":1792548777196},"agentText":"默认模型","mark":"failed","statusText":"出错：意外停止","badgeText":"失败，需要处理"}],"last":{"seq":1,"authorKind":"person","author":"alice@example.test","authorName":"Name of alice","text":"要归档的对话 083209 post:归档前的回复 083209","createdAt":1792548777117,"by":{"kind":"person","name":"你","mine":true,"id":"alice@example.test","picture":"https://example.test/p.png","label":"你"},"preview":"要归档的对话 083209 post:归档前的回复 083209","time":{"createdAt":{"at":1792548777117,"ago":"刚刚","full":"10/21 10:12:57","until":"1 分钟内","past":true}}},"unread":false,"mine":true,"lastActiveAt":1792548777117,"station":"01M5E3MC1B496BJETXKX7JNGSF/138ba6116d729e54bf1241baf74a72cecff00ecf0b23bff83d1345178b6cb111","stationName":"studio","state":"failed","time":{"lastActiveAt":{"at":1792548777117,"ago":"刚刚","full":"10/21 10:12:57","until":"1 分钟内","past":true}},"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"peopleText":"你 发起","clientKey":"new:chat-e5c10f1662b3338734","pinned":false,"stateText":"出错：意外停止","tone":"alert"}]}],"trouble":null,"members":1,"leading":"agents","glyph":{"online":1,"dim":0,"connecting":0,"failing":0,"working":0,"summary":"studio","label":"1 台 station，1 台在线"},"note":{"reading":false,"text":null,"failing":[],"empty":false}}},"w":1792548785947.409}
  #|{"in":{"id":8,"value":{"app":"desktop","tabs":[{"part":"desktop","label":"桌面","days":[]},{"part":"web","label":"网页","days":[]},{"part":"android","label":"安卓","days":[]},{"part":"station","label":"Station","days":[]},{"part":"cloud","label":"云端","days":[]}],"loading":false}},"w":1792548785947.438}
  #|{"in":{"id":9,"value":{"workspaces":{"01M5E3MC1B496BJETXKX7JNGSF":{"alert":1,"unread":0,"tone":"alert","label":"1 个出错","chat":{"station":"01M5E3MC1B496BJETXKX7JNGSF/138ba6116d729e54bf1241baf74a72cecff00ecf0b23bff83d1345178b6cb111","key":"ember:c-4d25e6d2a3"},"badge":0,"items":[{"kind":"alert","workspace":"01M5E3MC1B496BJETXKX7JNGSF","workspaceName":"Dev","station":"01M5E3MC1B496BJETXKX7JNGSF/138ba6116d729e54bf1241baf74a72cecff00ecf0b23bff83d1345178b6cb111","stationName":"studio","session":"ember:c-f77fef823b","thread":2,"title":"要归档的对话 083209 post:归档前的回复 083209","text":"出错：意外停止","seen":true,"at":1792548777117}],"mineTone":"alert"}},"badge":0,"badgeCounts":"attention","badgeKinds":{"on":true,"wait":true,"failed":true,"done":false,"message":false}}},"w":1792548785947.447}
  #|{"in":{"id":10,"value":{"items":[]}},"w":1792548785947.454}
  #|{"in":{"id":11,"ok":null},"w":1792548785947.456}
  #|{"in":{"id":12,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792548785947.463}
  #|{"in":{"id":13,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792548785947.467}
  #|{"out":{"id":14,"subscribe":{"topic":"longJobs","scope":"01M5E3MC1B496BJETXKX7JNGSF"},"keyed":true},"w":1792548785947.495}
  #|{"out":{"id":15,"call":"notify.permission","params":{"state":"unknown"}},"w":1792548785950.309}
  #|{"in":{"id":14,"value":{"groups":[]}},"w":1792548785961.906}
  #|{"in":{"id":15,"ok":null},"w":1792548785961.912}
  #|{"step":"answered notify.permission","w":1792548785962.172}
  #|{"step":"tap 端到端测试","w":1792548785978.81}
  #|{"step":"tap 端到端测试","acted":true,"w":1792548785978.824}
  #|{"out":{"id":16,"subscribe":{"topic":"chat","station":"01M5E3MC1B496BJETXKX7JNGSF/138ba6116d729e54bf1241baf74a72cecff00ecf0b23bff83d1345178b6cb111","session":"ember:c-4d25e6d2a3"},"keyed":true},"w":1792548785995.476}
  #|{"out":{"id":17,"call":"draft.get","params":{"key":"01M5E3MC1B496BJETXKX7JNGSF/138ba6116d729e54bf1241baf74a72cecff00ecf0b23bff83d1345178b6cb111:ember:c-4d25e6d2a3"}},"w":1792548785995.868}
  #|{"step":"answered draft.get","w":1792548785996.008}
  #|{"in":{"id":17,"ok":{"text":"","quotes":[],"files":[],"id":"draft-9bf79b33fa58a7f329"}},"w":1792548786011.904}
  #|{"in":{"id":16,"value":{"archived":false,"pinned":false,"me":{"id":"alice@example.test","email":"alice@example.test"},"thread":{"id":1,"surface":"ember","channel":"EMBER","threadTs":"1792548683.757000","createdBy":"alice@example.test","creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"createdAt":1792548683757,"sessions":[{"thread":1,"session":"ember:c-4d25e6d2a3","connect":"ember","joinedAt":1792548683758}],"last":12,"lastMessage":{"seq":12,"thread":1,"ts":"1792548784.629000","authorKind":"agent","author":"ember:c-4d25e6d2a3","text":"先合并哪个分支 083209","attachments":[],"quotes":[],"declared":"block","ending":"need_help","createdAt":1792548784629,"time":{"createdAt":{"at":1792548784629,"ago":"刚刚","full":"10/21 10:13:04","until":"1 分钟内","past":true}}},"read":12,"unread":0,"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"firstText":"端到端测试的对话 post:你好，我是测试用的 agent","time":{"createdAt":{"at":1792548683757,"ago":"2 分钟前","full":"10/21 10:11:23","until":"1 分钟内","past":true}}},"title":"端到端测试的对话 post:你好，我是测试用的 agent","people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"agents":[{"session":{"key":"ember:c-4d25e6d2a3","connect":"ember","scope":"all","createdBy":"alice@example.test","boundTo":[],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"},"participants":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"}],"runtime":"claude","profile":"cc","profilePinned":false,"runtimeSessionId":"4f79397c-57a5-42bd-a726-c4592d5244b1","workspace":"/tmp/mbe2e-C/data/sessions/ember/c-4d25e6d2a3/workspace","running":false,"createdAt":1792548683756,"lastActiveAt":1792548784634,"process":"warm","turns":8,"pending":0,"firstText":"端到端测试的对话 post:你好，我是测试用的 agent","lastTurn":{"id":"46503dc6-afcd-49e5-b55a-d728c889a76c","kind":"input","outcome":"completed","declared":"block","ending":"need_help","need":"先合并哪个分支 083209","about":{"thread":1,"seq":12,"ts":"1792548784.629000"},"startedAt":1792548784621,"endedAt":1792548784634},"statusText":"需要你处理：先合并哪个分支 083209","tone":"blue","mark":"block","badgeText":"agent 已暂停，等待处理","titleText":"端到端测试的对话 post:你好，我是测试用的 agent","agentText":"默认模型","runtimeText":"Claude Code","processText":"保温中","efforts":["low","medium","high","xhigh","max"],"time":{"createdAt":{"at":1792548683756,"ago":"2 分钟前","full":"10/21 10:11:23","until":"1 分钟内","past":true},"lastActiveAt":{"at":1792548784634,"ago":"刚刚","full":"10/21 10:13:04","until":"1 分钟内","past":true}}},"status":"block","badge":"block","profile":{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792548683670,"time":{"checkedAt":{"at":1792548683670,"ago":"2 分钟前","full":"10/21 10:11:23","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792548683804,"time":{"checkedAt":{"at":1792548683804,"ago":"2 分钟前","full":"10/21 10:11:23","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]},"profiles":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":true,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792548683804,"time":{"checkedAt":{"at":1792548683804,"ago":"2 分钟前","full":"10/21 10:11:23","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}],"choices":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":true,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792548683804,"time":{"checkedAt":{"at":1792548683804,"ago":"2 分钟前","full":"10/21 10:11:23","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"account":{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":true,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792548683804,"time":{"checkedAt":{"at":1792548683804,"ago":"2 分钟前","full":"10/21 10:11:23","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}},"attention":[],"turns":[{"id":"843e04df-264e-4454-ba11-320c75cea7e9","kind":"input","outcome":"completed","declared":"final","ending":"all_done","startedAt":1792548683828,"endedAt":1792548683898},{"id":"eb5567a8-8e5c-4726-abb4-c303d3191d0b","kind":"input","outcome":"completed","declared":"block","ending":"need_help","startedAt":1792548774971,"endedAt":1792548775019},{"id":"01cf6b29-7595-4fee-9564-bfd5461549aa","kind":"input","startedAt":1792548775657},{"id":"0a8df1a6-82c6-4c49-9370-efe302b6c6ae","kind":"nudge","startedAt":1792548775664},{"id":"b427f2b7-e967-41eb-bd09-501ca81ae27f","kind":"nudge","outcome":"completed","startedAt":1792548775668,"endedAt":1792548775671},{"id":"9ccd3d55-3730-43f5-9673-f1c79f9ff85a","kind":"input","outcome":"completed","declared":"block","ending":"need_help","startedAt":1792548780939,"endedAt":1792548780954},{"id":"52b14e11-5eb8-435c-b48a-84d36bc0db87","kind":"input","outcome":"completed","declared":"final","ending":"all_done","startedAt":1792548782772,"endedAt":1792548782795},{"id":"46503dc6-afcd-49e5-b55a-d728c889a76c","kind":"input","outcome":"completed","declared":"block","ending":"need_help","startedAt":1792548784621,"endedAt":1792548784634}],"threads":[{"id":1,"surface":"ember","channel":"EMBER","threadTs":"1792548683.757000","createdBy":"alice@example.test","creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"},"createdAt":1792548683757,"sessions":[{"thread":1,"session":"ember:c-4d25e6d2a3","connect":"ember","joinedAt":1792548683758}],"last":12,"lastMessage":{"seq":12,"thread":1,"ts":"1792548784.629000","authorKind":"agent","author":"ember:c-4d25e6d2a3","text":"先合并哪个分支 083209","attachments":[],"quotes":[],"declared":"block","ending":"need_help","createdAt":1792548784629,"time":{"createdAt":{"at":1792548784629,"ago":"刚刚","full":"10/21 10:13:04","until":"1 分钟内","past":true}}},"read":12,"unread":0,"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"}],"firstText":"端到端测试的对话 post:你好，我是测试用的 agent","time":{"createdAt":{"at":1792548683757,"ago":"2 分钟前","full":"10/21 10:11:23","until":"1 分钟内","past":true}}}],"jobs":[]}],"messages":[{"seq":1,"thread":1,"ts":"1792548683.814000","authorKind":"person","author":"alice@example.test","authorName":"Name of alice","text":"端到端测试的对话 post:你好，我是测试用的 agent","attachments":[],"quotes":[],"createdAt":1792548683814,"mine":true,"system":false,"by":{"name":"Name of alice","picture":"https://example.test/p.png"},"waiting":false,"time":{"createdAt":{"at":1792548683814,"ago":"2 分钟前","full":"10/21 10:11:23","until":"1 分钟内","past":true}}},{"seq":2,"thread":1,"ts":"1792548683.896000","authorKind":"agent","author":"ember:c-4d25e6d2a3","text":"你好，我是测试用的 agent","attachments":[],"quotes":[],"declared":"final","ending":"all_done","createdAt":1792548683896,"mine":false,"system":false,"by":{"name":"默认模型","agent":"ember:c-4d25e6d2a3","runtime":"claude","here":true},"waiting":false,"time":{"createdAt":{"at":1792548683896,"ago":"2 分钟前","full":"10/21 10:11:23","until":"1 分钟内","past":true}}},{"seq":3,"thread":1,"ts":"1792548774.968000","authorKind":"person","author":"alice@example.test","authorName":"Name of alice","text":"给我几个选项 083209 card:要不要换图标 083209|先不换 083209|一起换 083209*|不用了 083209!","attachments":[],"quotes":[],"createdAt":1792548774968,"mine":true,"system":false,"by":{"name":"Name of alice","picture":"https://example.test/p.png"},"waiting":false,"time":{"createdAt":{"at":1792548774968,"ago":"刚刚","full":"10/21 10:12:54","until":"1 分钟内","past":true}}},{"seq":4,"thread":1,"ts":"1792548775.017000","authorKind":"agent","author":"ember:c-4d25e6d2a3","text":"要不要换图标 083209","attachments":[],"quotes":[],"declared":"block","ending":"need_help","createdAt":1792548775017,"mine":false,"system":false,"by":{"name":"默认模型","agent":"ember:c-4d25e6d2a3","runtime":"claude","here":true},"waiting":false,"time":{"createdAt":{"at":1792548775017,"ago":"刚刚","full":"10/21 10:12:55","until":"1 分钟内","past":true}},"options":[{"label":"先不换 083209"},{"label":"不用了 083209"},{"label":"一起换 083209","recommended":true}],"card":{"assigneeText":"待你决策","type":"options","options":[{"label":"先不换 083209"},{"label":"不用了 083209"},{"label":"一起换 083209","recommended":true}]},"decision":{"resolved":true,"answeredBy":"你","chosen":"一起换 083209","text":"你 选择了「一起换 083209」"}},{"seq":5,"thread":1,"ts":"1792548775.653000","authorKind":"person","author":"alice@example.test","authorName":"Name of alice","text":"一起换 083209","attachments":[],"quotes":[{"author":"agent","text":"要不要换图标 083209","comment":"","ts":"1792548775.017000","role":"agent"}],"createdAt":1792548775653,"mine":true,"system":false,"by":{"name":"Name of alice","picture":"https://example.test/p.png"},"waiting":false,"time":{"createdAt":{"at":1792548775653,"ago":"刚刚","full":"10/21 10:12:55","until":"1 分钟内","past":true}}},{"seq":6,"thread":1,"ts":"1792548775.672000","authorKind":"ember","author":"ember","authorName":"still.fail","text":"⚠️ 本轮 agent 未在对话中回复，以下是它最后输出的文字，由 station 代为转发（并非它发布的消息）；回复即可继续：\n\n> Your turn ended without a state, so nobody knows where the chat stands. Only a real unresolved need requires need_human. A factual answer alone does not need a follow-up question; do not invent one. If you still need something after answering a clarification, visibly ask for it; need alone is only a status summary. Cards are optional. Do not reopen a decision the user already made. Decide whether anything in it is still unfinished, then end the turn with exactly one:\n> - all_done: nothing in the chat is left unfinished at all. Post the result with chat_post kind \"all_done\" (or chat_state \"all_done\" if you already posted it), with done: why nothing is left, naming the evidence (a commit, a release, a person's confirmation, the answer given).\n> - need_human: a person has to give, do, decide, confirm or verify something (a card you posted included), or answer a question you asked: kind \"need_human\" with need, what they have to give, do or decide (to verify: where, how and what to look at). If work you started is pending too, mention it after the ask in need.\n> - waiting: only work you started that will bring you back on its own (a background command or agent, a job, a loop watching CI), with nothing asked of anyone, and nothing else you can do meanwhile: chat_state \"waiting\" with seconds, your estimate of how long until it does, and for, what you wait for. Waiting on a person is need_human.\n> - Otherwise: continue the work.","attachments":[],"quotes":[],"createdAt":1792548775672,"mine":false,"system":true,"reportable":true,"by":{"name":"still.fail"},"waiting":false,"time":{"createdAt":{"at":1792548775672,"ago":"刚刚","full":"10/21 10:12:55","until":"1 分钟内","past":true}}},{"seq":7,"thread":1,"ts":"1792548780.935000","authorKind":"person","author":"alice@example.test","authorName":"Name of alice","text":"选一个颜色 083209 card:按钮用什么颜色 083209|橙色 083209*|灰色 083209","attachments":[],"quotes":[],"createdAt":1792548780935,"mine":true,"system":false,"by":{"name":"Name of alice","picture":"https://example.test/p.png"},"waiting":false,"time":{"createdAt":{"at":1792548780935,"ago":"刚刚","full":"10/21 10:13:00","until":"1 分钟内","past":true}}},{"seq":8,"thread":1,"ts":"1792548780.950000","authorKind":"agent","author":"ember:c-4d25e6d2a3","text":"按钮用什么颜色 083209","attachments":[],"quotes":[],"declared":"block","ending":"need_help","createdAt":1792548780950,"mine":false,"system":false,"by":{"name":"默认模型","agent":"ember:c-4d25e6d2a3","runtime":"claude","here":true},"waiting":false,"time":{"createdAt":{"at":1792548780950,"ago":"刚刚","full":"10/21 10:13:00","until":"1 分钟内","past":true}},"options":[{"label":"灰色 083209"},{"label":"橙色 083209","recommended":true}],"card":{"assigneeText":"待你决策","type":"options","options":[{"label":"灰色 083209"},{"label":"橙色 083209","recommended":true}]},"decision":{"resolved":true,"answeredBy":"你","text":"你 回复了"}},{"seq":9,"thread":1,"ts":"1792548782.769000","authorKind":"person","author":"alice@example.test","authorName":"Name of alice","text":"部署吗 083209 card:要不要部署 083209|现在部署 083209*|不需要部署 083209!","attachments":[],"quotes":[],"createdAt":1792548782769,"mine":true,"system":false,"by":{"name":"Name of alice","picture":"https://example.test/p.png"},"waiting":false,"time":{"createdAt":{"at":1792548782769,"ago":"刚刚","full":"10/21 10:13:02","until":"1 分钟内","past":true}}},{"seq":10,"thread":1,"ts":"1792548782.785000","authorKind":"agent","author":"ember:c-4d25e6d2a3","text":"要不要部署 083209","attachments":[],"quotes":[],"declared":"block","ending":"need_help","createdAt":1792548782785,"mine":false,"system":false,"by":{"name":"默认模型","agent":"ember:c-4d25e6d2a3","runtime":"claude","here":true},"waiting":false,"time":{"createdAt":{"at":1792548782785,"ago":"刚刚","full":"10/21 10:13:02","until":"1 分钟内","past":true}},"options":[{"label":"不需要部署 083209"},{"label":"现在部署 083209","recommended":true}],"card":{"assigneeText":"待你决策","type":"options","options":[{"label":"不需要部署 083209"},{"label":"现在部署 083209","recommended":true}]},"decision":{"resolved":true,"answeredBy":"你","text":"你 回复了"}},{"seq":11,"thread":1,"ts":"1792548784.618000","authorKind":"person","author":"alice@example.test","authorName":"Name of alice","text":"再问一个 083209 card:先合并哪个分支 083209|先合 A 083209|先合 B 083209","attachments":[],"quotes":[],"createdAt":1792548784618,"mine":true,"system":false,"by":{"name":"Name of alice","picture":"https://example.test/p.png"},"waiting":false,"time":{"createdAt":{"at":1792548784618,"ago":"刚刚","full":"10/21 10:13:04","until":"1 分钟内","past":true}}},{"seq":12,"thread":1,"ts":"1792548784.629000","authorKind":"agent","author":"ember:c-4d25e6d2a3","text":"先合并哪个分支 083209","attachments":[],"quotes":[],"declared":"block","ending":"need_help","createdAt":1792548784629,"mine":false,"system":false,"by":{"name":"默认模型","agent":"ember:c-4d25e6d2a3","runtime":"claude","here":true},"waiting":false,"time":{"createdAt":{"at":1792548784629,"ago":"刚刚","full":"10/21 10:13:04","until":"1 分钟内","past":true}},"options":[{"label":"先合 A 083209"},{"label":"先合 B 083209"}],"card":{"assigneeText":"待你决策","type":"options","options":[{"label":"先合 A 083209"},{"label":"先合 B 083209"}]},"decision":{"resolved":false,"dismissed":true}}],"elsewhere":[],"more":false,"newer":false,"caught":12,"unreadAbove":false,"outbox":[],"link":{"state":"online"},"offline":false,"pending":false,"decision":{"seq":12,"options":[{"label":"先合 A 083209"},{"label":"先合 B 083209"}],"card":{"type":"options","options":[{"label":"先合 A 083209"},{"label":"先合 B 083209"}]},"dismissed":true},"asks":[],"publish":{"may":true,"links":[]}}},"w":1792548786012.053}
  #|{"out":{"id":18,"subscribe":{"topic":"stations","scope":"01M5E3MC1B496BJETXKX7JNGSF"},"keyed":true},"w":1792548786012.237}
  #|{"out":{"id":19,"subscribe":{"topic":"chatJobs","station":"01M5E3MC1B496BJETXKX7JNGSF/138ba6116d729e54bf1241baf74a72cecff00ecf0b23bff83d1345178b6cb111","session":"ember:c-4d25e6d2a3"},"keyed":true},"w":1792548786012.246}
  #|{"out":{"id":20,"call":"picture","params":{"url":"https://example.test/p.png"}},"w":1792548786012.257}
  #|{"out":{"id":21,"call":"client.focus","params":{"chat":{"station":"01M5E3MC1B496BJETXKX7JNGSF/138ba6116d729e54bf1241baf74a72cecff00ecf0b23bff83d1345178b6cb111","session":"ember:c-4d25e6d2a3","thread":1,"end":true}}},"w":1792548786016.845}
  #|{"in":{"id":18,"value":[{"station":"01M5E3MC1B496BJETXKX7JNGSF/138ba6116d729e54bf1241baf74a72cecff00ecf0b23bff83d1345178b6cb111","id":"138ba6116d729e54bf1241baf74a72cecff00ecf0b23bff83d1345178b6cb111","name":"studio","summary":"空闲 · Apple M4 · 16 GB · macOS 27.0.1","face":"idle","line":"Apple M4","online":true,"reconnecting":false,"lastSeen":1792548683,"version":"0.1.0","link":{"state":"online"},"runtimes":[{"runtime":"claude","models":["claude-sonnet-5-5"]}],"models":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792548683804,"time":{"checkedAt":{"at":1792548683804,"ago":"2 分钟前","full":"10/21 10:11:23","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"overview":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null,"summaryText":"最近 7 天检查了 0 个 chat","changeText":null}},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","email":"alice@example.test","name":"Name of alice","sub":"alice","role":"owner","workspace":"01M5E3MC1B496BJETXKX7JNGSF","device":"a49b9649c51f7154da373b273e5d2ee5f2088787e8f26b3131fbb01f6eed23e8"},"connects":[],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792548683670,"time":{"checkedAt":{"at":1792548683670,"ago":"2 分钟前","full":"10/21 10:11:23","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792548683804,"time":{"checkedAt":{"at":1792548683804,"ago":"2 分钟前","full":"10/21 10:11:23","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]}],"processes":[],"counts":{"sessions":2,"running":0,"warm":1},"mesh":{"state":"running","origin":"http://127.0.0.1:18787","station":"138ba6116d729e54bf1241baf74a72cecff00ecf0b23bff83d1345178b6cb111","workspace":"Dev","workspaceId":"01M5E3MC1B496BJETXKX7JNGSF","name":"studio"},"slackUsers":[],"slackTeams":[],"slackApps":[],"feishuRegistrations":[],"disk":{"freeBytes":46397210624,"totalBytes":245107195904},"logins":[],"machineLogins":[{"runtime":"claude","installed":true,"loggedIn":false,"usable":false,"text":"无法读取 Claude Code 的登录信息","offered":false},{"runtime":"codex","installed":true,"loggedIn":false,"usable":false,"text":"Codex 未登录","offered":false}],"sharing":true,"consoleSignIn":true,"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"google","name":"Google Gemini","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xai","name":"xAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"mistral","name":"Mistral","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"deepseek","name":"DeepSeek","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen","name":"Qwen","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai","name":"Kimi","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai","name":"Z.ai","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax","name":"MiniMax","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ant-ling","name":"Ant Ling","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"jev","name":"Jev","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen-cn","name":"Qwen (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"openrouter","name":"OpenRouter","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"opencode","name":"OpenCode Zen","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"groq","name":"Groq","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"together","name":"Together AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"fireworks","name":"Fireworks","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cerebras","name":"Cerebras","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"huggingface","name":"Hugging Face","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"nvidia","name":"NVIDIA","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"baseten","name":"Baseten","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ollama","name":"Ollama","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"custom","name":"Custom","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""}],"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792548681828},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.305","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792548681828},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-news/apps/e2e-local/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792548681828},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-news/apps/e2e-local/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792548681828},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","latest":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-news/apps/e2e-local/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792548681828},{"id":"cursor","name":"Cursor","installed":false,"latest":"1.0.40","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792548681828},{"id":"devin","name":"Devin","installed":true,"version":"3000.11.92","latest":"3000.11.92","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-news/apps/e2e-local/ember/station/test/fake/devin，不是用 Devin 的安装脚本装的，需在该机器上手动更新","state":"idle","checkedAt":1792548681828}],"processesText":"没有运行中的 agent 进程","agentEnv":[],"drive":{"roots":[],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false}},"betaOffered":false,"host":{"hostname":"3720-Mac-mini-1","os":"macOS 27.0.1","arch":"arm64","cpus":10,"cpuModel":"Apple M4","load":0.59,"cpuBusy":0.55,"uptimeSec":28136,"memory":{"totalBytes":17179869184,"usedBytes":9766928384,"swapUsedBytes":300742083},"disk":{"path":"/tmp/mbe2e-C/data","totalBytes":245107195904,"freeBytes":46403612672},"emberRssBytes":125583152,"checkedAt":1792548774387,"summary":"10 核 · 16 GB","line":"macOS 27.0.1 · 10 核 · 16 GB · 已运行 0 天","facts":["3720-Mac-mini-1","macOS 27.0.1","arm64 · 10 核","已运行 7 小时"],"meters":[{"label":"CPU","short":"CPU","percent":55,"left":45,"level":"ok","value":"55%","remaining":"空闲 45%","big":"45","unit":"%","title":"CPU 空闲","total":"负载 5.9","note":"负载 5.9 · Apple M4"},{"label":"内存","short":"内存","percent":57,"left":43,"level":"ok","value":"9.1 GB / 16.0 GB","remaining":"剩 6.9 G","big":"6.9","unit":"GB","title":"内存剩","total":"共 16 GB","note":"swap 0.3 GB"},{"label":"磁盘","short":"磁盘","percent":81,"left":19,"level":"amber","value":"剩余 43.2 GB / 228 GB","remaining":"剩 43.2 G","big":"43.2","unit":"GB","title":"磁盘剩","total":"共 228 GB"}],"identity":"Apple M4 · 16 GB · macOS 27.0.1","details":[{"label":"主机名","value":"3720-Mac-mini-1"},{"label":"芯片","value":"Apple M4 · 10 核 · arm64"},{"label":"已运行","value":"7 小时"},{"label":"still.fail","value":"进程占用 120 MB"}],"usage":"内存 9.1 GB / 16.0 GB · 磁盘 剩余 43.2 GB / 228 GB","emberText":"still.fail 120 MB"},"way":{"path":"直连","via":"direct"},"time":{"lastSeen":{"at":1792548683000,"ago":"2 分钟前","full":"10/21 10:11:23","until":"1 分钟内","past":true}},"joined":false}]},"w":1792548786028.675}
  #|{"in":{"id":19,"value":{"jobs":[],"servicesNote":"","jobsNote":"","current":0,"ended":0,"clear":[],"allText":"全部 0 个","clearText":"清除 0 个已结束的","hiddenText":"另有 0 个已停止或结束"}},"w":1792548786028.753}
  #|{"in":{"id":21,"ok":null},"w":1792548786028.757}
  #|{"step":"answered picture","w":1792548786029.48}
  #|{"in":{"id":18,"delta":[{"path":[0,"host","checkedAt"],"set":1792548784729},{"path":[0,"host","cpuBusy"],"set":0.12},{"path":[0,"host","details",3,"value"],"set":"进程占用 142 MB"},{"path":[0,"host","disk","freeBytes"],"set":46397394944},{"path":[0,"host","emberRssBytes"],"set":148439408},{"path":[0,"host","emberText"],"set":"still.fail 142 MB"},{"path":[0,"host","load"],"set":0.53},{"path":[0,"host","memory","usedBytes"],"set":9846374400},{"path":[0,"host","meters",0,"big"],"set":"88"},{"path":[0,"host","meters",0,"left"],"set":88},{"path":[0,"host","meters",0,"note"],"set":"负载 5.3 · Apple M4"},{"path":[0,"host","meters",0,"percent"],"set":12},{"path":[0,"host","meters",0,"remaining"],"set":"空闲 88%"},{"path":[0,"host","meters",0,"total"],"set":"负载 5.3"},{"path":[0,"host","meters",0,"value"],"set":"12%"},{"path":[0,"host","meters",1,"big"],"set":"6.8"},{"path":[0,"host","meters",1,"remaining"],"set":"剩 6.8 G"},{"path":[0,"host","meters",1,"value"],"set":"9.2 GB / 16.0 GB"},{"path":[0,"host","uptimeSec"],"set":28146},{"path":[0,"host","usage"],"set":"内存 9.2 GB / 16.0 GB · 磁盘 剩余 43.2 GB / 228 GB"},{"path":[0,"overview","disk","freeBytes"],"set":46397186048}]},"w":1792548786161.93}
  #|{"in":{"id":20,"error":{"code":"picture","message":"无法加载图片：error sending request for url (https://example.test/p.png): client error (Connect): tls handshake eof"}},"w":1792548786211.934}
  #|{"step":"answered client.focus","w":1792548786230.515}
  #|{"step":"wait 300","w":1792548786247.536}
  #|{"step":"now until =studio","w":1792548786563.762}
  #|{"step":"tap 发消息","w":1792548786563.816}
  #|{"step":"tap 发消息","acted":true,"w":1792548786563.863}
  #|{"step":"type 看看文档 083209 steps:文档目录看过了 083209","w":1792548786590.005}
  #|{"step":"type 看看文档 083209 steps:文档目录看过了 083209","acted":true,"w":1792548786590.06}
  #|{"out":{"id":22,"call":"session.warm","params":{"station":"01M5E3MC1B496BJETXKX7JNGSF/138ba6116d729e54bf1241baf74a72cecff00ecf0b23bff83d1345178b6cb111","key":"ember:c-4d25e6d2a3"}},"w":1792548786595.593}
  #|{"step":"answered session.warm","w":1792548786601.945}
  #|{"in":{"id":22,"ok":{"ok":true}},"w":1792548786611.931}
  #|{"step":"tap icon:arrow-up","w":1792548786630.645}
  #|{"step":"tap icon:arrow-up","acted":true,"w":1792548786630.687}
  #|{"out":{"id":23,"call":"chat.send","params":{"station":"01M5E3MC1B496BJETXKX7JNGSF/138ba6116d729e54bf1241baf74a72cecff00ecf0b23bff83d1345178b6cb111","text":"看看文档 083209 steps:文档目录看过了 083209","attachments":[],"quotes":[],"thread":1}},"w":1792548786645.756}
  #|{"step":"answered chat.send","w":1792548786649.334}
  #|{"in":{"id":23,"ok":{"seq":13}},"w":1792548786695.251}
  #|{"step":"wait 600","w":1792548786714.619}
  #|{"in":{"id":16,"delta":[{"path":["agents",0,"session","lastActiveAt"],"set":1792548786673},{"path":["agents",0,"session","lastTurn","declared"],"set":"final"},{"path":["agents",0,"session","lastTurn","endedAt"],"set":1792548786673},{"path":["agents",0,"session","lastTurn","ending"],"set":"all_done"},{"path":["agents",0,"session","lastTurn","id"],"set":"fc5a7792-65b4-49b9-bdc8-aa7c46f48ac9"},{"path":["agents",0,"session","lastTurn","need"],"set":"answered the question that was asked"},{"path":["agents",0,"session","lastTurn","startedAt"],"set":1792548786656},{"path":["agents",0,"session","lastTurn","about"],"remove":true},{"path":["agents",0,"session","statusText"],"set":"已完成：answered the question that was asked"},{"path":["agents",0,"session","time","lastActiveAt","at"],"set":1792548786673},{"path":["agents",0,"session","time","lastActiveAt","full"],"set":"10/21 10:13:06"},{"path":["agents",0,"session","tone"],"set":"green"},{"path":["agents",0,"session","turns"],"set":9},{"path":["agents",0,"session","badgeText"],"remove":true},{"path":["agents",0,"session","mark"],"remove":true},{"path":["agents",0,"status"],"set":"final"},{"path":["agents",0,"threads",0,"last"],"set":14},{"path":["agents",0,"threads",0,"lastMessage","createdAt"],"set":1792548786669},{"path":["agents",0,"threads",0,"lastMessage","declared"],"set":"final"},{"path":["agents",0,"threads",0,"lastMessage","ending"],"set":"all_done"},{"path":["agents",0,"threads",0,"lastMessage","seq"],"set":14},{"path":["agents",0,"threads",0,"lastMessage","text"],"set":"文档目录看过了 083209"},{"path":["agents",0,"threads",0,"lastMessage","time","createdAt","at"],"set":1792548786669},{"path":["agents",0,"threads",0,"lastMessage","time","createdAt","full"],"set":"10/21 10:13:06"},{"path":["agents",0,"threads",0,"lastMessage","ts"],"set":"1792548786.669000"},{"path":["agents",0,"threads",0,"unread"],"set":1},{"path":["agents",0,"turns"],"append":[{"id":"fc5a7792-65b4-49b9-bdc8-aa7c46f48ac9","kind":"input","outcome":"completed","declared":"final","ending":"all_done","startedAt":1792548786656,"endedAt":1792548786673}]},{"path":["agents",0,"badge"],"remove":true},{"path":["messages"],"key":["seq","outgoing"],"patch":[12,null],"ops":[{"path":["decision","answeredBy"],"set":"你"},{"path":["decision","resolved"],"set":true},{"path":["decision","text"],"set":"你 回复了"},{"path":["decision","dismissed"],"remove":true}]},{"path":["outbox"],"key":["id"],"put":{"id":"out-707278f5f532592a6c","text":"看看文档 083209 steps:文档目录看过了 083209","attachments":[],"quotes":[],"createdAt":1792548786647,"state":"sending","seq":13,"time":{"createdAt":{"at":1792548786647,"ago":"刚刚","full":"10/21 10:13:06","until":"1 分钟内","past":true}}},"before":null},{"path":["thread","last"],"set":14},{"path":["thread","lastMessage","createdAt"],"set":1792548786669},{"path":["thread","lastMessage","declared"],"set":"final"},{"path":["thread","lastMessage","ending"],"set":"all_done"},{"path":["thread","lastMessage","seq"],"set":14},{"path":["thread","lastMessage","text"],"set":"文档目录看过了 083209"},{"path":["thread","lastMessage","time","createdAt","at"],"set":1792548786669},{"path":["thread","lastMessage","time","createdAt","full"],"set":"10/21 10:13:06"},{"path":["thread","lastMessage","ts"],"set":"1792548786.669000"},{"path":["thread","unread"],"set":1},{"path":["decision"],"remove":true}]},"w":1792548786728.65}
  #|{"in":{"id":9,"delta":[{"path":["workspaces","01M5E3MC1B496BJETXKX7JNGSF","label"],"set":"1 个出错 · 1 个有新消息"},{"path":["workspaces","01M5E3MC1B496BJETXKX7JNGSF","unread"],"set":1}]},"w":1792548786728.769}
  #|{"in":{"id":7,"delta":[{"path":["days"],"key":["daysAgo"],"patch":0,"ops":[{"path":["at"],"set":1792548786669},{"path":["items"],"key":["station","id"],"patch":["01M5E3MC1B496BJETXKX7JNGSF/138ba6116d729e54bf1241baf74a72cecff00ecf0b23bff83d1345178b6cb111","ember:c-4d25e6d2a3"],"ops":[{"path":["agents",0,"lastTurn","declared"],"set":"final"},{"path":["agents",0,"lastTurn","endedAt"],"set":1792548786673},{"path":["agents",0,"lastTurn","ending"],"set":"all_done"},{"path":["agents",0,"lastTurn","id"],"set":"fc5a7792-65b4-49b9-bdc8-aa7c46f48ac9"},{"path":["agents",0,"lastTurn","need"],"set":"answered the question that was asked"},{"path":["agents",0,"lastTurn","startedAt"],"set":1792548786656},{"path":["agents",0,"lastTurn","about"],"remove":true},{"path":["agents",0,"statusText"],"set":"已完成：answered the question that was asked"},{"path":["agents",0,"badgeText"],"remove":true},{"path":["agents",0,"mark"],"remove":true},{"path":["last","by","label"],"set":"agent"},{"path":["last","by","state"],"remove":true},{"path":["last","createdAt"],"set":1792548786669},{"path":["last","preview"],"set":"文档目录看过了 083209"},{"path":["last","seq"],"set":14},{"path":["last","text"],"set":"文档目录看过了 083209"},{"path":["last","time","createdAt","at"],"set":1792548786669},{"path":["last","time","createdAt","full"],"set":"10/21 10:13:06"},{"path":["lastActiveAt"],"set":1792548786669},{"path":["time","lastActiveAt","at"],"set":1792548786669},{"path":["time","lastActiveAt","full"],"set":"10/21 10:13:06"},{"path":["tone"],"set":"done"},{"path":["unread"],"set":true},{"path":["decision"],"remove":true}]}]}]},"w":1792548786728.787}
  #|{"in":{"id":18,"delta":[{"path":[0,"overview","disk","freeBytes"],"set":46397071360}]},"w":1792548786728.833}
  #|{"in":{"id":16,"delta":[{"path":["messages"],"key":["seq","outgoing"],"put":{"seq":14,"thread":1,"ts":"1792548786.669000","authorKind":"agent","author":"ember:c-4d25e6d2a3","text":"文档目录看过了 083209","attachments":[],"quotes":[],"declared":"final","ending":"all_done","createdAt":1792548786669,"mine":false,"system":false,"by":{"name":"默认模型","agent":"ember:c-4d25e6d2a3","runtime":"claude","here":true},"waiting":false,"said":true,"time":{"createdAt":{"at":1792548786669,"ago":"刚刚","full":"10/21 10:13:06","until":"1 分钟内","past":true}}},"before":null},{"path":["messages"],"key":["seq","outgoing"],"put":{"outgoing":"out-707278f5f532592a6c","seq":13,"thread":1,"ts":"1792548786.652000","authorKind":"person","author":"alice@example.test","authorName":"Name of alice","text":"看看文档 083209 steps:文档目录看过了 083209","attachments":[],"quotes":[],"createdAt":1792548786652,"mine":true,"system":false,"by":{"name":"Name of alice","picture":"https://example.test/p.png"},"waiting":false,"said":true,"time":{"createdAt":{"at":1792548786652,"ago":"刚刚","full":"10/21 10:13:06","until":"1 分钟内","past":true}}},"before":[14,null]},{"path":["outbox"],"key":["id"],"drop":"out-707278f5f532592a6c"}]},"w":1792548786795.249}
  #|{"in":{"id":18,"delta":[{"path":[0,"overview","disk","freeBytes"],"set":46397054976}]},"w":1792548786795.276}
  #|{"in":{"id":16,"delta":[{"path":["agents",0,"threads",0,"read"],"set":14},{"path":["agents",0,"threads",0,"unread"],"set":0},{"path":["archivable"],"set":true},{"path":["thread","read"],"set":14},{"path":["thread","unread"],"set":0}]},"w":1792548786978.636}
  #|{"in":{"id":7,"delta":[{"path":["days"],"key":["daysAgo"],"patch":0,"ops":[{"path":["at"],"set":1792548777117},{"path":["items"],"key":["station","id"],"patch":["01M5E3MC1B496BJETXKX7JNGSF/138ba6116d729e54bf1241baf74a72cecff00ecf0b23bff83d1345178b6cb111","ember:c-4d25e6d2a3"],"ops":[{"path":["archivable"],"set":true},{"path":["settled"],"set":true},{"path":["stateText"],"set":"已完成：answered the question that was asked"},{"path":["unread"],"set":false},{"path":["tone"],"remove":true}]},{"path":["items"],"key":["station","id"],"move":["01M5E3MC1B496BJETXKX7JNGSF/138ba6116d729e54bf1241baf74a72cecff00ecf0b23bff83d1345178b6cb111","ember:c-f77fef823b"],"before":["01M5E3MC1B496BJETXKX7JNGSF/138ba6116d729e54bf1241baf74a72cecff00ecf0b23bff83d1345178b6cb111","ember:c-4d25e6d2a3"]}]}]},"w":1792548786978.746}
  #|{"in":{"id":9,"delta":[{"path":["workspaces","01M5E3MC1B496BJETXKX7JNGSF","label"],"set":"1 个出错"},{"path":["workspaces","01M5E3MC1B496BJETXKX7JNGSF","unread"],"set":0}]},"w":1792548786978.815}
  #|{"step":"now gone 正在发送","w":1792548787330.904}
  #|{"step":"untiln 2 文档目录看过了 083209","w":1792548787330.971}
  #|{"step":"tap icon:more","w":1792548787331}
  #|{"step":"tap icon:more","acted":true,"w":1792548787331.038}
  #|{"step":"until 复制会话链接","w":1792548787368.806}
  #|{"step":"tap1 icon:chevron-right","w":1792548787481.653}
  #|{"step":"tap1 icon:chevron-right","acted":true,"w":1792548787481.728}
  #|{"step":"until =历史","w":1792548787498.27}
  #|{"out":{"id":24,"subscribe":{"topic":"agentCard","station":"01M5E3MC1B496BJETXKX7JNGSF/138ba6116d729e54bf1241baf74a72cecff00ecf0b23bff83d1345178b6cb111","key":"ember:c-4d25e6d2a3"},"keyed":true},"w":1792548787512.125}
  #|{"step":"tap =历史","w":1792548787518.507}
  #|{"step":"tap =历史","acted":true,"w":1792548787518.524}
  #|{"in":{"id":24,"value":{"work":"9 轮","latest":[{"key":"5","text":"列出 docs 目录"},{"key":"7","text":"编辑 notes.md"},{"key":"9","text":"看过了，改好了。"}],"attention":[]}},"w":1792548787528.576}
  #|{"out":{"id":25,"subscribe":{"topic":"history","station":"01M5E3MC1B496BJETXKX7JNGSF/138ba6116d729e54bf1241baf74a72cecff00ecf0b23bff83d1345178b6cb111","key":"ember:c-4d25e6d2a3"},"keyed":true},"w":1792548787529.934}
  #|{"step":"wait 300","w":1792548787532.483}
  #|{"in":{"id":25,"value":{"items":[{"key":"e0","entries":[0,0],"body":{"kind":"received","content":{"tasks":[],"messages":[{"key":"1792548774.968000","from":{"name":"Name of alice","bound":false},"text":"给我几个选项 083209 card:要不要换图标 083209|先不换 083209|一起换 083209*|不用了 083209!","place":{"name":"端到端测试的对话 post:你好，我是测试用的 agent","surface":"ember","session":"ember:c-4d25e6d2a3"}}]}},"turn":{"at":1792548774975,"time":"10:12","text":"未发消息"}},{"key":"e1","entries":[1,1],"body":{"kind":"received","content":{"tasks":[],"messages":[{"key":"1792548780.935000","from":{"name":"Name of alice","bound":false},"text":"选一个颜色 083209 card:按钮用什么颜色 083209|橙色 083209*|灰色 083209","place":{"name":"端到端测试的对话 post:你好，我是测试用的 agent","surface":"ember","session":"ember:c-4d25e6d2a3"}}]}},"turn":{"at":1792548780940,"time":"10:13","text":"未发消息"}},{"key":"e2","entries":[2,2],"body":{"kind":"received","content":{"tasks":[],"messages":[{"key":"1792548782.769000","from":{"name":"Name of alice","bound":false},"text":"部署吗 083209 card:要不要部署 083209|现在部署 083209*|不需要部署 083209!","place":{"name":"端到端测试的对话 post:你好，我是测试用的 agent","surface":"ember","session":"ember:c-4d25e6d2a3"}}]}},"turn":{"at":1792548782774,"time":"10:13","text":"未发消息"}},{"key":"e3","entries":[3,3],"body":{"kind":"received","content":{"tasks":[],"messages":[{"key":"1792548784.618000","from":{"name":"Name of alice","bound":false},"text":"再问一个 083209 card:先合并哪个分支 083209|先合 A 083209|先合 B 083209","place":{"name":"端到端测试的对话 post:你好，我是测试用的 agent","surface":"ember","session":"ember:c-4d25e6d2a3"}}]}},"turn":{"at":1792548784623,"time":"10:13","text":"未发消息"}},{"key":"e4","entries":[4,4],"body":{"kind":"received","content":{"tasks":[],"messages":[{"key":"1792548786.652000","from":{"name":"Name of alice","bound":false},"text":"看看文档 083209 steps:文档目录看过了 083209","place":{"name":"端到端测试的对话 post:你好，我是测试用的 agent","surface":"ember","session":"ember:c-4d25e6d2a3"}}]}},"turn":{"at":1792548786657,"time":"10:13","text":"2 步 · 未发消息"}},{"key":"e5","entries":[5,8],"body":{"kind":"group","content":{"summary":"编辑 notes.md · 共 2 项","title":"运行 1 条命令、编辑 1 个文件","failures":0,"pending":0,"rows":[{"kind":"step","content":{"said":"列出 docs 目录","name":"Bash","hint":"ls docs","meta":"1ms","failed":false,"call":"{\n  \"command\": \"ls docs\",\n  \"description\": \"列出 docs 目录\"\n}","result":"stillfail-port.md\nstillfail-android-map.md","entries":[5,6],"brief":false}},{"kind":"step","content":{"name":"Edit","hint":"/tmp/e2e/notes.md","meta":"0ms","failed":false,"call":"{\n  \"file_path\": \"/tmp/e2e/notes.md\",\n  \"old_string\": \"旧的一行\",\n  \"new_string\": \"新的一行\"\n}","result":"The file /tmp/e2e/notes.md has been updated.","entries":[7,8],"brief":false}}]}}},{"key":"e9","entries":[9,9],"body":{"kind":"text","content":{"text":"看过了，改好了。","md":[["p",["看过了，改好了。"]]],"subagent":false}}}],"live":[],"usage":[{"label":"模型调用","value":"0 次"},{"label":"输入","value":"0"},{"label":"其中缓存","value":"0"},{"label":"输出","value":"0"},{"label":"缓存命中率","value":"未报告"}],"usageLine":"调用 0 次 · 输入 0 · 输出 0","edge":"已到会话开头","empty":false,"loaded":true,"more":false}},"w":1792548787545.287}
  #|{"step":"now until 执行历史","w":1792548787845.522}
  #|{"step":"until 文档目录看过了 083209","w":1792548787845.542}
  #|{"step":"tap icon:chevron-right","w":1792548787845.549}
  #|{"step":"tap icon:chevron-right","acted":true,"w":1792548787845.561}
  #|{"step":"until 列出 docs 目录","w":1792548787884.456}
  #|{"step":"tap 列出 docs 目录","w":1792548787884.47}
  #|{"step":"tap 列出 docs 目录","acted":true,"w":1792548787884.482}
  #|{"step":"wait 300","w":1792548787894.625}
  #|{"step":"now until stillfail-port.md","w":1792548788196.621}
  #|{"step":"","w":1792548788196.691}
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
  #|{"textrec":{"ib":["fdb526ba00f881f4",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["bef2954d97ce1d9f",6508,64],"r":[40,40,40,40]}}
  #|{"textrec":{"ib":["31d8ec32aedeae00",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["a7ccae3554fe46cf",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["c8ac90bf691295f0",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"s":[15,400,0,"搜索全部内容"],"r":[0,1,14.883268482490273,18,1,1,14.883268482490273,19,2,1,14.883268482490273,20,3,1,14.883268482490273,21,4,1,14.88326848249028,22,5,1,14.88326848249028,23]}}
  #|{"textrec":{"m":[15,400,0],"r":[14.501953125,3.1640625,21,14.501953125,3.1640625,0]}}
  #|{"textrec":{"s":[15,600,0,"今天"],"r":[0,1,14.883268482490273,24,1,1,14.883268482490273,25]}}
  #|{"textrec":{"m":[15,600,0],"r":[14.501953125,3.1640625,21,14.501953125,3.1640625,0]}}
  #|{"textrec":{"s":[16,400,0,"端到端测试的对话 post:你好，我是测试用的 agent"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,26,3,1,15.875486381322958,28,4,1,15.875486381322958,29,5,1,15.875486381322958,30,6,1,15.875486381322958,31,7,1,15.875486381322958,32,8,1,4.1875,-1,9,1,9.453125,33,10,1,9.140625,34,11,1,8.0234375,35,12,1,5.4609375,36,13,1,4.4375,37,14,1,15.875486381322958,38,15,1,15.875486381322958,39,16,1,16.09338521400778,40,17,1,15.875486381322958,41,18,1,15.875486381322958,42,19,1,15.87548638132293,28,20,1,15.875486381322958,29,21,1,15.875486381322958,43,22,1,15.875486381322958,30,23,1,4.1875,-1,24,1,8.515625,44,25,1,9.4375,45,26,1,8.828125,46,27,1,9.0234375,47,28,1,5.5,36]}}
  #|{"textrec":{"m":[16,400,0],"r":[15.46875,3.375,23,15.46875,3.375,0]}}
  #|{"textrec":{"s":[14,400,0,"先合并哪个分支 083209"],"r":[0,1,13.891050583657588,48,1,1,13.891050583657588,49,2,1,13.891050583657588,50,3,1,13.891050583657588,51,4,1,13.891050583657588,52,5,1,13.891050583657588,53,6,1,13.891050583657588,54,7,1,3.787109375,-1,8,1,8.66796875,55,9,1,8.791015625,56,10,1,8.626953125,57,11,1,8.298828124999986,58,12,1,8.66796875,55,13,1,8.763671875,59]}}
  #|{"textrec":{"m":[14,400,0],"r":[13.53515625,2.953125,20,13.53515625,2.953125,0]}}
  #|{"textrec":{"s":[16,400,0,"…"],"r":[0,1,12.5625,60]}}
  #|{"textrec":{"s":[16,400,0,"端到端测试的对话 post:你好，我是测试用的 ag…"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,26,3,1,15.875486381322958,28,4,1,15.875486381322958,29,5,1,15.875486381322958,30,6,1,15.875486381322958,31,7,1,15.875486381322958,32,8,1,4.1875,-1,9,1,9.453125,33,10,1,9.140625,34,11,1,8.0234375,35,12,1,5.4609375,36,13,1,4.4375,37,14,1,15.875486381322958,38,15,1,15.875486381322958,39,16,1,16.09338521400778,40,17,1,15.875486381322958,41,18,1,15.875486381322958,42,19,1,15.87548638132293,28,20,1,15.875486381322958,29,21,1,15.875486381322958,43,22,1,15.875486381322958,30,23,1,4.1875,-1,24,1,8.515625,44,25,1,9.4375,45,26,1,12.5625,60]}}
  #|{"textrec":{"s":[16,400,0,"要归档的对话 083209 post:归档前的回复 083209"],"r":[0,1,15.875486381322958,61,1,1,15.875486381322958,62,2,1,15.875486381322958,63,3,1,15.875486381322958,30,4,1,15.875486381322958,31,5,1,15.875486381322958,32,6,1,4.1875,-1,7,1,9.765625,64,8,1,9.90625,65,9,1,9.71875,66,10,1,9.34375,67,11,1,9.765625,64,12,1,9.875,68,13,1,4.1875,-1,14,1,9.453125,33,15,1,9.140625,34,16,1,8.0234375,35,17,1,5.4609375,36,18,1,4.4375,37,19,1,15.875486381322958,62,20,1,15.875486381322958,63,21,1,15.875486381322958,69,22,1,15.875486381322958,30,23,1,15.875486381322958,70,24,1,15.875486381322958,71,25,1,4.1875,-1,26,1,9.765625,64,27,1,9.90625,65,28,1,9.71875,66,29,1,9.34375,67,30,1,9.765625,64,31,1,9.875,68]}}
  #|{"textrec":{"s":[14,400,0,"出错：意外停止"],"r":[0,1,13.891050583657588,72,1,1,13.891050583657588,73,2,1,14.081712062256813,74,3,1,13.891050583657588,75,4,1,13.891050583657588,76,5,1,13.891050583657588,77,6,1,13.891050583657588,78]}}
  #|{"textrec":{"s":[16,400,0,"要归档的对话 083209 post:归档前的回复 08…"],"r":[0,1,15.875486381322958,61,1,1,15.875486381322958,62,2,1,15.875486381322958,63,3,1,15.875486381322958,30,4,1,15.875486381322958,31,5,1,15.875486381322958,32,6,1,4.1875,-1,7,1,9.765625,64,8,1,9.90625,65,9,1,9.71875,66,10,1,9.34375,67,11,1,9.765625,64,12,1,9.875,68,13,1,4.1875,-1,14,1,9.453125,33,15,1,9.140625,34,16,1,8.0234375,35,17,1,5.4609375,36,18,1,4.4375,37,19,1,15.875486381322958,62,20,1,15.875486381322958,63,21,1,15.875486381322958,69,22,1,15.875486381322958,30,23,1,15.875486381322958,70,24,1,15.875486381322958,71,25,1,4.1875,-1,26,1,9.765625,64,27,1,9.6328125,65,28,1,12.2890625,79]}}
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
  #|{"textrec":{"g":44,"r":[462,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":45,"r":[473,0,11,14,-1,-10,0]}}
  #|{"textrec":{"g":60,"r":[485,0,13,5,0,-3,0]}}
  #|{"textrec":{"g":48,"r":[499,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":49,"r":[515,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":50,"r":[532,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":51,"r":[548,0,14,15,0,-12,0]}}
  #|{"textrec":{"g":52,"r":[563,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":53,"r":[580,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":54,"r":[597,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":55,"r":[614,0,10,14,-1,-12,0]}}
  #|{"textrec":{"g":56,"r":[625,0,11,14,-1,-12,0]}}
  #|{"textrec":{"g":57,"r":[637,0,10,14,-1,-12,0]}}
  #|{"textrec":{"g":58,"r":[648,0,9,13,0,-12,0]}}
  #|{"textrec":{"g":59,"r":[658,0,11,14,-1,-12,0]}}
  #|{"textrec":{"g":61,"r":[670,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":62,"r":[688,0,16,17,0,-14,0]}}
  #|{"textrec":{"g":63,"r":[705,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":64,"r":[723,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":65,"r":[735,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":66,"r":[747,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":67,"r":[759,0,10,14,0,-13,0]}}
  #|{"textrec":{"g":68,"r":[770,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":69,"r":[782,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":70,"r":[800,0,16,16,0,-13,0]}}
  #|{"textrec":{"g":71,"r":[817,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":79,"r":[835,0,13,5,-0.2734375,-3,0]}}
  #|{"textrec":{"g":72,"r":[849,0,14,16,0,-13,0]}}
  #|{"textrec":{"g":73,"r":[864,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":74,"r":[881,0,5,10,1,-10,0]}}
  #|{"textrec":{"g":75,"r":[887,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":76,"r":[904,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":77,"r":[921,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":78,"r":[937,0,15,15,-1,-13,0]}}
  #|{"textrec":{"ib":["33d1dfbf90932d3b",1241,64],"r":[17,17,17,17]}}
  #|{"textrec":{"ib":["182b7158e0c0cae1",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["d61ec6305f7d8c8b",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["8bf9607b651cec61",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"m":[16,600,0],"r":[15.46875,3.375,23,15.46875,3.375,0]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 post:你好，我是测试用的 agent"],"r":[0,1,15.875486381322958,80,1,1,15.875486381322958,81,2,1,15.875486381322958,80,3,1,15.875486381322958,82,4,1,15.875486381322958,83,5,1,15.875486381322958,84,6,1,15.875486381322958,85,7,1,15.875486381322958,86,8,1,3.95001220703125,-1,9,1,9.824199676513672,87,10,1,9.432537078857422,88,11,1,8.471200942993164,89,12,1,5.973020553588867,90,13,1,4.952056884765625,91,14,1,15.875486381322958,92,15,1,15.875486381322958,93,16,1,16.09338521400778,94,17,1,15.875486381322958,95,18,1,15.875486381322958,96,19,1,15.87548638132293,82,20,1,15.875486381322958,83,21,1,15.875486381322958,97,22,1,15.875486381322958,84,23,1,3.95001220703125,-1,24,1,8.899068832397461,98,25,1,9.801153182983398,99,26,1,9.127458572387695,100,27,1,9.466253280639648,101,28,1,5.999713897705078,90]}}
  #|{"textrec":{"s":[8,600,0,"N"],"r":[0,1,6.271738052368164,102]}}
  #|{"textrec":{"m":[8,600,0],"r":[7.734375,1.6875,11,7.734375,1.6875,0]}}
  #|{"textrec":{"s":[15,650,0,"默认模型"],"r":[0,1,14.883268482490273,103,1,1,14.883268482490273,104,2,1,14.883268482490273,105,3,1,14.883268482490273,106]}}
  #|{"textrec":{"m":[15,650,0],"r":[14.501953125,3.1640625,21,14.501953125,3.1640625,0]}}
  #|{"textrec":{"s":[10,400,0,"刚刚"],"r":[0,1,9.941634241245136,107,1,1,9.941634241245136,107]}}
  #|{"textrec":{"m":[10,400,0],"r":[9.66796875,2.109375,14,9.66796875,2.109375,0]}}
  #|{"textrec":{"s":[15,400,0,"先合并哪个分支 083209"],"r":[0,1,14.883268482490273,108,1,1,14.883268482490273,109,2,1,14.883268482490273,110,3,1,14.883268482490273,111,4,1,14.88326848249028,112,5,1,14.88326848249028,113,6,1,14.88326848249028,114,7,1,3.984375,-1,8,1,9.2138671875,115,9,1,9.345703125,116,10,1,9.169921875,117,11,1,8.818359375,118,12,1,9.2138671875,115,13,1,9.31640625,119]}}
  #|{"textrec":{"s":[16,400,0,"再问一个 083209 card:先合并哪个分支 083209|先合 A 083209|先合 B 083209"],"r":[0,1,15.875486381322958,120,1,1,15.875486381322958,121,2,1,15.875486381322958,122,3,1,15.875486381322958,123,4,1,4.1875,-1,5,1,9.765625,64,6,1,9.90625,65,7,1,9.71875,66,8,1,9.34375,67,9,1,9.765625,64,10,1,9.875,68,11,1,4.1875,-1,12,1,8.640625,124,13,1,8.515625,44,14,1,5.6640625,125,15,1,9.3984375,126,16,1,4.4375,37,17,1,15.875486381322958,127,18,1,15.875486381322958,128,19,1,15.875486381322958,129,20,1,15.875486381322958,130,21,1,15.875486381322958,123,22,1,15.875486381322958,131,23,1,15.875486381322958,132,24,1,4.1875,-1,25,1,9.765625,64,26,1,9.90625,65,27,1,9.71875,66,28,1,9.34375,67,29,1,9.765625,64,30,1,9.875,68,31,1,5.828125,133,32,1,15.875486381322958,127,33,1,15.875486381322958,128,34,1,4.1875,-1,35,1,10.46875,134,36,1,4.1875,-1,37,1,9.765625,64,38,1,9.90625,65,39,1,9.71875,66,40,1,9.34375,67,41,1,9.765625,64,42,1,9.875,68,43,1,5.828125,133,44,1,15.875486381322958,127,45,1,15.875486381322958,128,46,1,4.1875,-1,47,1,10.203125,135,48,1,4.1875,-1,49,1,9.765625,64,50,1,9.90625,65,51,1,9.71875,66,52,1,9.34375,67,53,1,9.765625,64,54,1,9.875,68]}}
  #|{"textrec":{"s":[15,400,0,"要不要部署 083209"],"r":[0,1,14.883268482490273,136,1,1,14.883268482490273,137,2,1,14.883268482490273,136,3,1,14.883268482490273,21,4,1,14.88326848249028,138,5,1,3.984375,-1,6,1,9.2138671875,115,7,1,9.345703125,116,8,1,9.169921875,117,9,1,8.818359375,118,10,1,9.2138671875,115,11,1,9.31640625,119]}}
  #|{"textrec":{"s":[13,400,0,"你 回复了"],"r":[0,1,12.898832684824903,4,1,1,3.580078125,-1,2,1,12.898832684824903,139,3,1,12.898832684824903,140,4,1,12.898832684824903,141]}}
  #|{"textrec":{"s":[16,400,0,"部署吗 083209 card:要不要部署 083209|现在部署 083209*|不需要部署 083209!"],"r":[0,1,15.875486381322958,142,1,1,15.875486381322958,143,2,1,15.875486381322958,144,3,1,4.1875,-1,4,1,9.765625,64,5,1,9.90625,65,6,1,9.71875,66,7,1,9.34375,67,8,1,9.765625,64,9,1,9.875,68,10,1,4.1875,-1,11,1,8.640625,124,12,1,8.515625,44,13,1,5.6640625,125,14,1,9.3984375,126,15,1,4.4375,37,16,1,15.875486381322958,61,17,1,15.875486381322958,145,18,1,15.875486381322958,61,19,1,15.875486381322958,142,20,1,15.875486381322958,143,21,1,4.1875,-1,22,1,9.765625,64,23,1,9.90625,65,24,1,9.71875,66,25,1,9.34375,67,26,1,9.765625,64,27,1,9.875,68,28,1,5.828125,133,29,1,15.875486381322958,146,30,1,15.875486381322958,147,31,1,15.875486381322958,142,32,1,15.875486381322958,143,33,1,4.1875,-1,34,1,9.765625,64,35,1,9.90625,65,36,1,9.71875,66,37,1,9.34375,67,38,1,9.765625,64,39,1,9.796875,68,40,1,7.15625,148,41,1,5.828125,133,42,1,15.875486381322958,145,43,1,15.875486381322958,149,44,1,15.875486381322958,61,45,1,15.875486381322958,142,46,1,15.875486381322958,143,47,1,4.1875,-1,48,1,9.765625,64,49,1,9.90625,65,50,1,9.71875,66,51,1,9.34375,67,52,1,9.765625,64,53,1,9.875,68,54,1,4.6640625,150]}}
  #|{"textrec":{"s":[15,400,0,"按钮用什么颜色 083209"],"r":[0,1,14.883268482490273,151,1,1,14.883268482490273,152,2,1,14.883268482490273,153,3,1,14.883268482490273,154,4,1,14.88326848249028,155,5,1,14.88326848249028,156,6,1,14.88326848249028,157,7,1,3.984375,-1,8,1,9.2138671875,115,9,1,9.345703125,116,10,1,9.169921875,117,11,1,8.818359375,118,12,1,9.2138671875,115,13,1,9.31640625,119]}}
  #|{"textrec":{"s":[16,400,0,"选一个颜色 083209 card:按钮用什么颜色 083209|橙色 083209*|灰色 083209"],"r":[0,1,15.875486381322958,158,1,1,15.875486381322958,122,2,1,15.875486381322958,123,3,1,15.875486381322958,159,4,1,15.875486381322958,160,5,1,4.1875,-1,6,1,9.765625,64,7,1,9.90625,65,8,1,9.71875,66,9,1,9.34375,67,10,1,9.765625,64,11,1,9.875,68,12,1,4.1875,-1,13,1,8.640625,124,14,1,8.515625,44,15,1,5.6640625,125,16,1,9.3984375,126,17,1,4.4375,37,18,1,15.875486381322958,161,19,1,15.875486381322958,162,20,1,15.875486381322958,43,21,1,15.875486381322958,163,22,1,15.875486381322958,164,23,1,15.875486381322958,159,24,1,15.875486381322958,160,25,1,4.1875,-1,26,1,9.765625,64,27,1,9.90625,65,28,1,9.71875,66,29,1,9.34375,67,30,1,9.765625,64,31,1,9.875,68,32,1,5.828125,133,33,1,15.875486381322958,165,34,1,15.875486381322958,160,35,1,4.1875,-1,36,1,9.765625,64,37,1,9.90625,65,38,1,9.71875,66,39,1,9.34375,67,40,1,9.765625,64,41,1,9.796875,68,42,1,7.15625,148,43,1,5.828125,133,44,1,15.875486381322958,166,45,1,15.875486381322958,160,46,1,4.1875,-1,47,1,9.765625,64,48,1,9.90625,65,49,1,9.71875,66,50,1,9.34375,67,51,1,9.765625,64,52,1,9.875,68]}}
  #|{"textrec":{"s":[15,400,0,"本轮 agent 未在对话中回复，以下是它最后输出的文字，由 station 代为转发（并非它发布的消息）；回复即可继续："],"r":[0,1,14.883268482490273,167,1,1,14.883268482490273,168,2,1,3.984375,-1,3,1,8.0419921875,169,4,1,8.90625,170,5,1,8.3349609375,171,6,1,8.51806640625,172,7,1,5.21484375,173,8,1,3.984375,-1,9,1,14.883268482490266,174,10,1,14.88326848249028,175,11,1,14.88326848249028,176,12,1,14.88326848249028,177,13,1,14.88326848249028,178,14,1,14.88326848249028,179,15,1,14.88326848249028,180,16,1,15.08754863813229,181,17,1,14.88326848249028,182,18,1,14.88326848249028,183,19,1,14.88326848249028,184,20,1,14.88326848249028,185,21,1,14.88326848249028,186,22,1,14.88326848249028,187,23,1,14.88326848249028,188,24,1,14.88326848249028,189,25,1,14.88326848249028,190,26,1,14.88326848249028,191,27,1,14.88326848249028,192,28,1,15.087548638132319,181,29,1,14.88326848249028,193,30,1,3.984375,-1,31,1,7.58056640625,194,32,1,5.17822265625,173,33,1,8.0419921875,169,34,1,5.21484375,173,35,1,3.4716796875,195,36,1,8.6279296875,196,37,1,8.51806640625,172,38,1,3.984375,-1,39,1,14.88326848249028,197,40,1,14.88326848249028,198,41,1,14.88326848249028,199,42,1,22.38326848249028,200,43,1,4.698443579766547,201,44,1,14.88326848249028,110,45,1,14.88326848249028,202,46,1,14.88326848249028,185,47,1,14.88326848249028,200,48,1,14.88326848249028,203,49,1,14.88326848249028,190,50,1,14.88326848249028,204,51,1,14.88326848249028,205,52,1,6.296206225680976,206,53,1,15.087548638132262,207,54,1,14.88326848249028,179,55,1,14.88326848249028,180,56,1,14.88326848249028,208,57,1,14.88326848249028,209,58,1,14.88326848249028,210,59,1,14.88326848249028,211,60,1,7.587548638132262,212]}}
  #|{"textrec":{"s":[15,400,0," · "],"r":[0,1,3.984375,-1,1,1,7.186782927948601,213,2,1,3.984375,-1]}}
  #|{"textrec":{"s":[15,600,0,"上报"],"r":[0,1,14.883268482490273,214,1,1,14.883268482490273,215]}}
  #|{"textrec":{"s":[15,400,0,"…"],"r":[0,1,11.8359375,216]}}
  #|{"textrec":{"s":[15,400,0,"本轮 agent 未在对话中回复，以下是它最后…"],"r":[0,1,14.883268482490273,167,1,1,14.883268482490273,168,2,1,3.984375,-1,3,1,8.0419921875,169,4,1,8.90625,170,5,1,8.3349609375,171,6,1,8.51806640625,172,7,1,5.21484375,173,8,1,3.984375,-1,9,1,14.883268482490266,174,10,1,14.88326848249028,175,11,1,14.88326848249028,176,12,1,14.88326848249028,177,13,1,14.88326848249028,178,14,1,14.88326848249028,179,15,1,14.88326848249028,180,16,1,15.08754863813229,181,17,1,14.88326848249028,182,18,1,14.88326848249028,183,19,1,14.88326848249028,184,20,1,14.88326848249028,185,21,1,14.88326848249028,186,22,1,14.88326848249028,187,23,1,11.8359375,216]}}
  #|{"textrec":{"s":[13,500,0,"agent："],"r":[0,1,7.277074933052063,217,1,1,8.016787648200989,218,2,1,7.491410613059998,219,3,1,7.717604756355286,220,4,1,4.881580114364624,221,5,1,6.575875486381321,222]}}
  #|{"textrec":{"m":[13,500,0],"r":[12.568359375,2.7421875,18,12.568359375,2.7421875,0]}}
  #|{"textrec":{"s":[13,400,0,"要不要换图标 083209"],"r":[0,1,12.898832684824903,223,1,1,12.898832684824903,224,2,1,12.898832684824903,223,3,1,12.898832684824903,225,4,1,12.898832684824896,226,5,1,12.898832684824896,227,6,1,3.580078125,-1,7,1,8.1123046875,228,8,1,8.2265625,229,9,1,8.07421875,230,10,1,7.76953125,231,11,1,8.1123046875,228,12,1,8.201171875,232]}}
  #|{"textrec":{"s":[16,400,0,"一起换 083209"],"r":[0,1,15.875486381322958,122,1,1,15.875486381322958,233,2,1,15.875486381322958,234,3,1,4.1875,-1,4,1,9.765625,64,5,1,9.90625,65,6,1,9.71875,66,7,1,9.34375,67,8,1,9.765625,64,9,1,9.875,68]}}
  #|{"textrec":{"s":[16,600,0,"…"],"r":[0,1,14.076484680175781,235]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 post:你好…"],"r":[0,1,15.875486381322958,80,1,1,15.875486381322958,81,2,1,15.875486381322958,80,3,1,15.875486381322958,82,4,1,15.875486381322958,83,5,1,15.875486381322958,84,6,1,15.875486381322958,85,7,1,15.875486381322958,86,8,1,3.95001220703125,-1,9,1,9.824199676513672,87,10,1,9.432537078857422,88,11,1,8.471200942993164,89,12,1,5.973020553588867,90,13,1,4.952056884765625,91,14,1,15.875486381322958,92,15,1,15.875486381322958,93,16,1,14.076484680175781,235]}}
  #|{"textrec":{"ib":["504a4df6beac534a",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"s":[12,400,0,"studio"],"r":[0,1,6.251953125,236,1,1,4.330078125,237,2,1,7.001953125,238,3,1,7.37109375,239,4,1,2.96484375,240,5,1,7.08984375,241]}}
  #|{"textrec":{"m":[12,400,0],"r":[11.6015625,2.53125,17,11.6015625,2.53125,0]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 post:…"],"r":[0,1,15.875486381322958,80,1,1,15.875486381322958,81,2,1,15.875486381322958,80,3,1,15.875486381322958,82,4,1,15.875486381322958,83,5,1,15.875486381322958,84,6,1,15.875486381322958,85,7,1,15.875486381322958,86,8,1,3.95001220703125,-1,9,1,9.824199676513672,87,10,1,9.432537078857422,88,11,1,8.471200942993164,89,12,1,5.973020553588867,90,13,1,4.952056884765625,91,14,1,14.076484680175781,235]}}
  #|{"textrec":{"g":167,"r":[953,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":168,"r":[971,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":169,"r":[989,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":170,"r":[1000,0,10,14,-1,-10,0]}}
  #|{"textrec":{"g":171,"r":[1011,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":172,"r":[1022,0,9,11,0,-10,0]}}
  #|{"textrec":{"g":173,"r":[1032,0,7,13,-1,-11,0]}}
  #|{"textrec":{"g":174,"r":[1040,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":175,"r":[1057,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":176,"r":[1074,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":177,"r":[1091,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":178,"r":[1109,0,15,16,0,-13,0]}}
  #|{"textrec":{"g":179,"r":[1125,0,15,16,0,-13,0]}}
  #|{"textrec":{"g":180,"r":[1141,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":181,"r":[1158,0,5,7,0,-3,0]}}
  #|{"textrec":{"g":182,"r":[1164,0,16,16,0,-13,0]}}
  #|{"textrec":{"g":183,"r":[1181,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":184,"r":[1198,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":185,"r":[1215,0,15,17,0,-14,0]}}
  #|{"textrec":{"g":186,"r":[1231,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":187,"r":[1248,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":216,"r":[1265,0,12,5,0,-3,0]}}
  #|{"textrec":{"g":151,"r":[1278,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":152,"r":[1296,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":153,"r":[1313,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":154,"r":[1329,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":155,"r":[1346,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":156,"r":[1363,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":157,"r":[1380,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":115,"r":[1397,0,11,14,-1,-12,0]}}
  #|{"textrec":{"g":116,"r":[1409,0,11,14,-1,-12,0]}}
  #|{"textrec":{"g":117,"r":[1421,0,10,14,0,-12,0]}}
  #|{"textrec":{"g":118,"r":[1432,0,10,13,0,-12,0]}}
  #|{"textrec":{"g":119,"r":[1443,0,11,14,-1,-12,0]}}
  #|{"textrec":{"g":4,"r":[1455,0,14,15,-1,-12,0]}}
  #|{"textrec":{"g":139,"r":[1470,0,13,14,0,-11,0]}}
  #|{"textrec":{"g":140,"r":[1484,0,14,15,-1,-12,0]}}
  #|{"textrec":{"g":141,"r":[1499,0,13,14,0,-11,0]}}
  #|{"textrec":{"g":136,"r":[1513,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":137,"r":[1530,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":138,"r":[1547,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":108,"r":[1564,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":109,"r":[1581,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":110,"r":[1599,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":111,"r":[1616,0,15,16,0,-13,0]}}
  #|{"textrec":{"g":112,"r":[1632,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":113,"r":[1650,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":114,"r":[1667,0,16,17,-1,-14,0]}}
  #|{"textrec":{"ib":["11ba9484460f477d",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["a1e7be43eb966606",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"ib":["c7a6d30e254a5910",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"g":158,"r":[1684,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":122,"r":[1702,0,17,4,-1,-8,0]}}
  #|{"textrec":{"g":123,"r":[1720,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":159,"r":[1739,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":160,"r":[1757,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":124,"r":[1775,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":125,"r":[1787,0,7,11,0,-10,0]}}
  #|{"textrec":{"g":126,"r":[1795,0,11,15,-1,-13,0]}}
  #|{"textrec":{"g":161,"r":[1807,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":162,"r":[1825,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":163,"r":[1843,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":164,"r":[1861,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":133,"r":[1879,0,4,17,0,-13,0]}}
  #|{"textrec":{"g":165,"r":[1884,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":148,"r":[1903,0,8,9,0,-13,0]}}
  #|{"textrec":{"g":166,"r":[1912,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":103,"r":[1931,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":104,"r":[1949,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":105,"r":[1967,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":106,"r":[1985,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":142,"r":[2002,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":143,"r":[2020,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":144,"r":[0,20,16,17,0,-14,0]}}
  #|{"textrec":{"g":145,"r":[17,20,17,16,-1,-13,0]}}
  #|{"textrec":{"g":146,"r":[35,20,18,17,-1,-14,0]}}
  #|{"textrec":{"g":147,"r":[54,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":149,"r":[72,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":150,"r":[90,20,5,15,0,-13,0]}}
  #|{"textrec":{"g":80,"r":[96,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":81,"r":[114,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":82,"r":[132,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":83,"r":[150,20,18,17,-1,-14,0]}}
  #|{"textrec":{"g":84,"r":[169,20,16,17,0,-14,0]}}
  #|{"textrec":{"g":85,"r":[186,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":86,"r":[204,20,18,17,-1,-14,0]}}
  #|{"textrec":{"g":87,"r":[223,20,11,14,0,-10,0]}}
  #|{"textrec":{"g":88,"r":[235,20,11,12,-1,-10,0]}}
  #|{"textrec":{"g":89,"r":[247,20,11,12,-1,-10,0]}}
  #|{"textrec":{"g":90,"r":[259,20,8,14,-1,-12,0]}}
  #|{"textrec":{"g":91,"r":[268,20,5,12,0,-10,0]}}
  #|{"textrec":{"g":235,"r":[274,20,14,6,0,-4,0]}}
  #|{"textrec":{"s":[16,400,0,"发消息"],"r":[0,1,15.875486381322958,242,1,1,15.875486381322958,243,2,1,15.875486381322958,244]}}
  #|{"textrec":{"g":242,"r":[289,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":243,"r":[307,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":244,"r":[325,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":107,"r":[343,20,11,11,-1,-9,0]}}
  #|{"textrec":{"g":120,"r":[355,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":121,"r":[373,20,16,17,0,-14,0]}}
  #|{"textrec":{"g":127,"r":[390,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":128,"r":[408,20,18,17,-1,-14,0]}}
  #|{"textrec":{"g":129,"r":[427,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":130,"r":[445,20,16,17,0,-14,0]}}
  #|{"textrec":{"g":131,"r":[462,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":132,"r":[480,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":134,"r":[498,20,13,14,-1,-13,0]}}
  #|{"textrec":{"g":135,"r":[512,20,11,14,0,-13,0]}}
  #|{"textrec":{"g":217,"r":[524,20,9,11,-1,-9,0]}}
  #|{"textrec":{"g":218,"r":[534,20,10,13,-1,-9,0]}}
  #|{"textrec":{"g":219,"r":[545,20,9,11,-1,-9,0]}}
  #|{"textrec":{"g":220,"r":[555,20,9,10,-1,-9,0]}}
  #|{"textrec":{"g":221,"r":[565,20,7,12,-1,-10,0]}}
  #|{"textrec":{"g":222,"r":[573,20,5,9,1,-9,0]}}
  #|{"textrec":{"g":223,"r":[579,20,15,14,-1,-11,0]}}
  #|{"textrec":{"g":224,"r":[595,20,15,14,-1,-11,0]}}
  #|{"textrec":{"g":225,"r":[611,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":226,"r":[627,20,13,14,0,-11,0]}}
  #|{"textrec":{"g":227,"r":[641,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":228,"r":[657,20,10,13,-1,-11,0]}}
  #|{"textrec":{"g":229,"r":[668,20,10,13,-1,-11,0]}}
  #|{"textrec":{"g":230,"r":[679,20,10,13,-1,-11,0]}}
  #|{"textrec":{"g":231,"r":[690,20,9,12,-1,-11,0]}}
  #|{"textrec":{"g":232,"r":[700,20,10,13,-1,-11,0]}}
  #|{"textrec":{"ib":["ba3016fbe7c2c39e",563,64],"r":[11,11,11,11]}}
  #|{"textrec":{"g":233,"r":[711,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":234,"r":[729,20,18,17,-1,-14,0]}}
  #|{"textrec":{"g":102,"r":[748,20,8,8,-1,-7,0]}}
  #|{"textrec":{"g":236,"r":[757,20,8,10,-1,-8,0]}}
  #|{"textrec":{"g":237,"r":[766,20,6,11,-1,-9,0]}}
  #|{"textrec":{"g":238,"r":[773,20,9,10,-1,-8,0]}}
  #|{"textrec":{"g":239,"r":[783,20,9,12,-1,-10,0]}}
  #|{"textrec":{"g":240,"r":[793,20,5,11,-1,-10,0]}}
  #|{"textrec":{"g":241,"r":[799,20,9,10,-1,-8,0]}}
  #|{"textrec":{"g":213,"r":[809,20,5,5,1,-8,0]}}
  #|{"textrec":{"g":214,"r":[815,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":215,"r":[832,20,17,16,-1,-13,0]}}
  #|{"textrec":{"ib":["ddfdc2820df8a676",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"ib":["b277602c41d156e7",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"s":[16,400,0,"看看文档 083209 steps:文档目录看过了 083209"],"r":[0,1,15.875486381322958,245,1,1,15.875486381322958,245,2,1,15.875486381322958,246,3,1,15.875486381322958,63,4,1,4.1875,-1,5,1,9.765625,64,6,1,9.90625,65,7,1,9.71875,66,8,1,9.34375,67,9,1,9.765625,64,10,1,9.875,68,11,1,4.1875,-1,12,1,8.0234375,35,13,1,5.40234375,36,14,1,8.76953125,46,15,1,9.453125,33,16,1,8.0625,35,17,1,4.4375,37,18,1,15.875486381322958,246,19,1,15.875486381322958,63,20,1,15.875486381322958,247,21,1,15.875486381322958,248,22,1,15.875486381322958,245,23,1,15.875486381322958,249,24,1,15.875486381322958,250,25,1,4.1875,-1,26,1,9.765625,64,27,1,9.90625,65,28,1,9.71875,66,29,1,9.34375,67,30,1,9.765625,64,31,1,9.875,68]}}
  #|{"textrec":{"g":245,"r":[850,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":246,"r":[868,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":46,"r":[886,20,11,12,-1,-10,0]}}
  #|{"textrec":{"g":247,"r":[898,20,14,16,1,-13,0]}}
  #|{"textrec":{"g":248,"r":[913,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":249,"r":[931,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":250,"r":[949,20,15,16,0,-13,0]}}
  #|{"textrec":{"ib":["9699dbc96b0fdfd9",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"s":[10,400,0,"正在发送"],"r":[0,1,9.941634241245136,251,1,1,9.941634241245136,252,2,1,9.941634241245136,253,3,1,9.941634241245136,254]}}
  #|{"textrec":{"g":251,"r":[965,20,12,11,-1,-9,0]}}
  #|{"textrec":{"g":252,"r":[978,20,12,13,-1,-10,0]}}
  #|{"textrec":{"g":253,"r":[991,20,12,13,-1,-10,0]}}
  #|{"textrec":{"g":254,"r":[1004,20,12,13,-1,-10,0]}}
  #|{"textrec":{"s":[15,400,0,"文档目录看过了 083209"],"r":[0,1,14.883268482490273,191,1,1,14.883268482490273,255,2,1,14.883268482490273,256,3,1,14.883268482490273,257,4,1,14.88326848249028,258,5,1,14.88326848249028,259,6,1,14.88326848249028,260,7,1,3.984375,-1,8,1,9.2138671875,115,9,1,9.345703125,116,10,1,9.169921875,117,11,1,8.818359375,118,12,1,9.2138671875,115,13,1,9.31640625,119]}}
  #|{"textrec":{"g":191,"r":[1017,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":255,"r":[1035,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":256,"r":[1052,20,13,16,1,-13,0]}}
  #|{"textrec":{"g":257,"r":[1066,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":258,"r":[1083,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":259,"r":[1100,20,17,16,-1,-13,0]}}
  #|{"textrec":{"g":260,"r":[1118,20,14,16,0,-13,0]}}
  #|{"textrec":{"ib":["5011346a34665c45",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 post…"],"r":[0,1,15.875486381322958,80,1,1,15.875486381322958,81,2,1,15.875486381322958,80,3,1,15.875486381322958,82,4,1,15.875486381322958,83,5,1,15.875486381322958,84,6,1,15.875486381322958,85,7,1,15.875486381322958,86,8,1,3.95001220703125,-1,9,1,9.824199676513672,87,10,1,9.432537078857422,88,11,1,8.471200942993164,89,12,1,5.973020553588867,90,13,1,14.076484680175781,235]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 pos…"],"r":[0,1,15.875486381322958,80,1,1,15.875486381322958,81,2,1,15.875486381322958,80,3,1,15.875486381322958,82,4,1,15.875486381322958,83,5,1,15.875486381322958,84,6,1,15.875486381322958,85,7,1,15.875486381322958,86,8,1,3.95001220703125,-1,9,1,9.824199676513672,87,10,1,9.432537078857422,88,11,1,8.497894287109375,89,12,1,14.076484680175781,235]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 po…"],"r":[0,1,15.875486381322958,80,1,1,15.875486381322958,81,2,1,15.875486381322958,80,3,1,15.875486381322958,82,4,1,15.875486381322958,83,5,1,15.875486381322958,84,6,1,15.875486381322958,85,7,1,15.875486381322958,86,8,1,3.95001220703125,-1,9,1,9.824199676513672,87,10,1,9.329673767089844,88,11,1,13.973621368408203,261]}}
  #|{"textrec":{"g":261,"r":[1133,20,14,6,-0.10286331176757812,-4,0]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 p…"],"r":[0,1,15.875486381322958,80,1,1,15.875486381322958,81,2,1,15.875486381322958,80,3,1,15.875486381322958,82,4,1,15.875486381322958,83,5,1,15.875486381322958,84,6,1,15.875486381322958,85,7,1,15.875486381322958,86,8,1,3.95001220703125,-1,9,1,9.721336364746094,87,10,1,13.973621368408203,261]}}
  #|{"textrec":{"s":[18,700,0,"端到端测试的对话 post:你好，我是测试用的 agent"],"r":[0,1,17.842412451361866,262,1,1,17.842412451361866,263,2,1,17.842412451361866,262,3,1,17.842412451361866,264,4,1,17.842412451361866,265,5,1,17.842412451361866,266,6,1,17.842412451361866,267,7,1,17.842412451361866,268,8,1,4.152015030384064,-1,9,1,11.16209328174591,269,10,1,10.675500869750977,270,11,1,9.692523032426834,271,12,1,6.919372379779816,272,13,1,5.73083621263504,273,14,1,17.842412451361866,274,15,1,17.842412451361866,275,16,1,18.08754863813229,276,17,1,17.842412451361866,277,18,1,17.842412451361838,278,19,1,17.842412451361838,264,20,1,17.842412451361838,265,21,1,17.842412451361838,279,22,1,17.842412451361838,266,23,1,4.152015030384064,-1,24,1,10.138570368289948,280,25,1,11.132530510425568,281,26,1,10.337921261787415,282,27,1,10.808134496212006,283,28,1,6.940345913171768,272]}}
  #|{"textrec":{"m":[18,700,0],"r":[17.40234375,3.796875,26,17.40234375,3.796875,0]}}
  #|{"textrec":{"s":[13,400,0,"你 2 分钟前发起 · 最新 刚刚"],"r":[0,1,12.898832684824903,4,1,1,3.580078125,-1,2,1,7.76953125,231,3,1,3.580078125,-1,4,1,12.898832684824903,284,5,1,12.898832684824903,285,6,1,12.898832684824903,286,7,1,12.898832684824896,287,8,1,12.898832684824896,288,9,1,3.580078125,-1,10,1,6.228545204222115,289,11,1,3.580078125,-1,12,1,12.898832684824896,290,13,1,12.898832684824896,291,14,1,3.580078125,-1,15,1,12.898832684824896,292,16,1,12.898832684824896,292]}}
  #|{"textrec":{"s":[15,600,0,"默认模型"],"r":[0,1,14.883268482490273,293,1,1,14.883268482490273,294,2,1,14.883268482490273,295,3,1,14.883268482490273,296]}}
  #|{"textrec":{"s":[12,400,0,"已完成：answered the question that was asked · 刚刚"],"r":[0,1,11.918287937743191,297,1,1,11.918287937743191,298,2,1,11.918287937743195,299,3,1,12.081712062256813,300,4,1,6.62109375,301,5,1,7.001953125,302,6,1,6.193359375,236,7,1,9.087890625,303,8,1,6.73828125,304,9,1,4.482421875,305,10,1,6.767578125,304,11,1,7.37109375,239,12,1,3.375,-1,13,1,4.359375,237,14,1,7.060546875,306,15,1,6.85546875,304,16,1,3.375,-1,17,1,7.312500000000014,307,18,1,7.001953125,238,19,1,6.85546875,304,20,1,6.251953125,236,21,1,4.330078125,237,22,1,2.96484375,240,23,1,7.08984375,241,24,1,7.001953125,302,25,1,3.375,-1,26,1,4.359375,237,27,1,7.060546875,306,28,1,6.62109375,301,29,1,4.359375,237,30,1,3.375,-1,31,1,9.205078125,303,32,1,6.533203125,301,33,1,6.28125,236,34,1,3.375,-1,35,1,6.62109375,301,36,1,6.28125,236,37,1,6.369140625,308,38,1,6.708984375,304,39,1,7.37109375,239,40,1,3.375,-1,41,1,5.754933455713626,309,42,1,3.375,-1,43,1,11.918287937743173,310,44,1,11.918287937743173,310]}}
  #|{"textrec":{"s":[14,400,0,"固定到列表顶部"],"r":[0,1,13.891050583657588,311,1,1,13.891050583657588,312,2,1,13.891050583657588,313,3,1,13.891050583657588,314,4,1,13.891050583657588,315,5,1,13.891050583657588,316,6,1,13.891050583657588,317]}}
  #|{"textrec":{"s":[14,400,0,"复制会话链接"],"r":[0,1,13.891050583657588,318,1,1,13.891050583657588,319,2,1,13.891050583657588,320,3,1,13.891050583657588,321,4,1,13.891050583657588,322,5,1,13.891050583657588,323]}}
  #|{"textrec":{"s":[14,400,0,"归档对话"],"r":[0,1,13.891050583657588,324,1,1,13.891050583657588,325,2,1,13.891050583657588,326,3,1,13.891050583657588,321]}}
  #|{"textrec":{"s":[14,400,0,"公开分享"],"r":[0,1,13.891050583657588,327,1,1,13.891050583657588,328,2,1,13.891050583657588,53,3,1,13.891050583657588,329]}}
  #|{"textrec":{"s":[12,400,0,"…"],"r":[0,1,9.65625,330]}}
  #|{"textrec":{"s":[12,400,0,"已完成：answered the question that was ask…"],"r":[0,1,11.918287937743191,297,1,1,11.918287937743191,298,2,1,11.918287937743195,299,3,1,12.081712062256813,300,4,1,6.62109375,301,5,1,7.001953125,302,6,1,6.193359375,236,7,1,9.087890625,303,8,1,6.73828125,304,9,1,4.482421875,305,10,1,6.767578125,304,11,1,7.37109375,239,12,1,3.375,-1,13,1,4.359375,237,14,1,7.060546875,306,15,1,6.85546875,304,16,1,3.375,-1,17,1,7.312500000000014,307,18,1,7.001953125,238,19,1,6.85546875,304,20,1,6.251953125,236,21,1,4.330078125,237,22,1,2.96484375,240,23,1,7.08984375,241,24,1,7.001953125,302,25,1,3.375,-1,26,1,4.359375,237,27,1,7.060546875,306,28,1,6.62109375,301,29,1,4.359375,237,30,1,3.375,-1,31,1,9.205078125,303,32,1,6.533203125,301,33,1,6.28125,236,34,1,3.375,-1,35,1,6.62109375,301,36,1,6.28125,236,37,1,6.515625,308,38,1,9.65625,330]}}
  #|{"textrec":{"g":262,"r":[1148,20,19,19,-1,-16,0]}}
  #|{"textrec":{"g":263,"r":[1168,20,19,19,-1,-16,0]}}
  #|{"textrec":{"g":264,"r":[1188,20,19,19,-1,-16,0]}}
  #|{"textrec":{"g":265,"r":[1208,20,20,19,-1,-16,0]}}
  #|{"textrec":{"g":266,"r":[1229,20,18,19,0,-16,0]}}
  #|{"textrec":{"g":267,"r":[1248,20,19,19,-1,-16,0]}}
  #|{"textrec":{"g":268,"r":[1268,20,20,19,-1,-16,0]}}
  #|{"textrec":{"g":269,"r":[1289,20,12,16,0,-11,0]}}
  #|{"textrec":{"g":270,"r":[1302,20,13,13,-1,-11,0]}}
  #|{"textrec":{"g":271,"r":[1316,20,12,13,-1,-11,0]}}
  #|{"textrec":{"g":272,"r":[1329,20,9,15,-1,-13,0]}}
  #|{"textrec":{"g":273,"r":[1339,20,6,13,0,-11,0]}}
  #|{"textrec":{"g":274,"r":[1346,20,19,19,-1,-16,0]}}
  #|{"textrec":{"g":275,"r":[1366,20,19,19,-1,-16,0]}}
  #|{"textrec":{"g":276,"r":[1386,20,7,9,0,-4,0]}}
  #|{"textrec":{"g":277,"r":[1394,20,19,19,-1,-16,0]}}
  #|{"textrec":{"g":278,"r":[1414,20,19,18,-1,-15,0]}}
  #|{"textrec":{"g":279,"r":[1434,20,18,18,-1,-15,0]}}
  #|{"textrec":{"g":280,"r":[1453,20,12,13,-1,-11,0]}}
  #|{"textrec":{"g":281,"r":[1466,20,13,16,-1,-11,0]}}
  #|{"textrec":{"g":282,"r":[1480,20,12,13,-1,-11,0]}}
  #|{"textrec":{"g":283,"r":[1493,20,12,12,0,-11,0]}}
  #|{"textrec":{"g":284,"r":[1506,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":285,"r":[1522,20,14,15,-1,-12,0]}}
  #|{"textrec":{"g":286,"r":[1537,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":287,"r":[1553,20,14,15,-1,-12,0]}}
  #|{"textrec":{"g":288,"r":[1568,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":289,"r":[1584,20,4,5,1,-7,0]}}
  #|{"textrec":{"g":290,"r":[1589,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":291,"r":[1604,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":292,"r":[1620,20,14,15,-1,-12,0]}}
  #|{"textrec":{"g":293,"r":[1635,20,17,16,-1,-13,0]}}
  #|{"textrec":{"g":294,"r":[1653,20,17,16,-1,-13,0]}}
  #|{"textrec":{"g":295,"r":[1671,20,17,16,-1,-13,0]}}
  #|{"textrec":{"g":296,"r":[1689,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":297,"r":[1706,20,13,12,0,-10,0]}}
  #|{"textrec":{"g":298,"r":[1720,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":299,"r":[1735,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":300,"r":[1750,20,4,9,1,-9,0]}}
  #|{"textrec":{"g":301,"r":[1755,20,8,10,-1,-8,0]}}
  #|{"textrec":{"g":302,"r":[1764,20,9,9,-1,-8,0]}}
  #|{"textrec":{"g":303,"r":[1774,20,11,9,-1,-8,0]}}
  #|{"textrec":{"g":304,"r":[1786,20,9,10,-1,-8,0]}}
  #|{"textrec":{"g":305,"r":[1796,20,7,9,-1,-8,0]}}
  #|{"textrec":{"g":306,"r":[1804,20,8,11,0,-10,0]}}
  #|{"textrec":{"g":307,"r":[1813,20,9,12,-1,-8,0]}}
  #|{"textrec":{"g":308,"r":[1823,20,8,11,0,-10,0]}}
  #|{"textrec":{"g":330,"r":[1832,20,10,5,0,-3,0]}}
  #|{"textrec":{"g":311,"r":[1843,20,14,15,0,-12,0]}}
  #|{"textrec":{"g":312,"r":[1858,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":313,"r":[1874,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":314,"r":[1890,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":315,"r":[1906,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":316,"r":[1922,20,16,15,-1,-12,0]}}
  #|{"textrec":{"g":317,"r":[1939,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":318,"r":[1955,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":319,"r":[1971,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":320,"r":[1987,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":321,"r":[2004,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":322,"r":[2021,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":323,"r":[0,40,15,16,-1,-13,0]}}
  #|{"textrec":{"g":324,"r":[16,40,15,16,-1,-13,0]}}
  #|{"textrec":{"g":325,"r":[32,40,15,16,-1,-13,0]}}
  #|{"textrec":{"g":326,"r":[48,40,15,16,-1,-13,0]}}
  #|{"textrec":{"g":327,"r":[64,40,16,16,-1,-13,0]}}
  #|{"textrec":{"g":328,"r":[81,40,15,15,-1,-12,0]}}
  #|{"textrec":{"g":329,"r":[97,40,16,16,-1,-13,0]}}
  #|{"textrec":{"ib":["92022e9e11aef691",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"ib":["f1276e6323a9ca06",1853,64],"r":[21,21,21,21]}}
  #|{"textrec":{"ib":["030aece180ce0f3c",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"ib":["b3685975cd23abc3",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["b9bedad57f2a5f13",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"ib":["97cc1349f5996766",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"ib":["82d8240109550b08",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"s":[17,700,0,"默认模型"],"r":[0,1,16.851167315175097,331,1,1,16.851167315175097,332,2,1,16.851167315175097,333,3,1,16.851167315175097,334]}}
  #|{"textrec":{"m":[17,700,0],"r":[16.435546875,3.5859375,24,16.435546875,3.5859375,0]}}
  #|{"textrec":{"s":[13,400,0,"已完成：answered the question that was asked"],"r":[0,1,12.898832684824903,335,1,1,12.898832684824903,336,2,1,12.898832684824903,337,3,1,13.075875486381321,338,4,1,7.0966796875,12,5,1,7.509277343749993,339,6,1,6.63330078125,10,7,1,9.76904296875,6,8,1,7.2236328125,14,9,1,4.77978515625,8,10,1,7.25537109375,14,11,1,7.9091796875,340,12,1,3.580078125,-1,13,1,4.646484375,341,14,1,7.57275390625,342,15,1,7.3505859375,14,16,1,3.580078125,-1,17,1,7.845703125,343,18,1,7.50927734375,344,19,1,7.3505859375,14,20,1,6.69677734375,10,21,1,4.61474609375,341,22,1,3.1357421875,345,23,1,7.6044921875,7,24,1,7.50927734375,339,25,1,3.580078125,-1,26,1,4.646484375,341,27,1,7.57275390625,342,28,1,7.0966796875,12,29,1,4.646484375,341,30,1,3.580078125,-1,31,1,9.89599609375,6,32,1,7.00146484375,12,33,1,6.728515625,10,34,1,3.580078125,-1,35,1,7.0966796875,12,36,1,6.728515625000028,10,37,1,6.82373046875,9,38,1,7.19189453125,14,39,1,7.9091796875,340]}}
  #|{"textrec":{"s":[13,400,0," · 刚刚"],"r":[0,1,3.580078125,-1,1,1,6.228545204222119,289,2,1,3.580078125,-1,3,1,12.898832684824903,292,4,1,12.8988326848249,292]}}
  #|{"textrec":{"s":[14,400,0,"Station"],"r":[0,1,8.7705078125,346,1,1,4.935546875,347,2,1,7.57421875,348,3,1,4.935546875,347,4,1,3.30859375,349,5,1,8.12109375,350,6,1,8.0185546875,351]}}
  #|{"textrec":{"s":[14,400,0,"studio"],"r":[0,1,7.1435546875,352,1,1,4.9013671875,347,2,1,8.0185546875,353,3,1,8.44921875,354,4,1,3.30859375,349,5,1,8.12109375,350]}}
  #|{"textrec":{"s":[14,400,0,"账号"],"r":[0,1,13.891050583657588,355,1,1,13.891050583657588,356]}}
  #|{"textrec":{"s":[14,400,0,"cc · 自动"],"r":[0,1,7.68359375,357,1,1,7.68359375,357,2,1,3.787109375,-1,3,1,6.707664066085361,358,4,1,3.787109375,-1,5,1,13.891050583657584,359,6,1,13.891050583657588,360]}}
  #|{"textrec":{"s":[14,400,0,"历史"],"r":[0,1,13.891050583657588,361,1,1,13.891050583657588,362]}}
  #|{"textrec":{"s":[14,400,0,"尚未运行"],"r":[0,1,13.891050583657588,363,1,1,13.891050583657588,364,2,1,13.891050583657588,365,3,1,13.891050583657588,366]}}
  #|{"textrec":{"g":331,"r":[114,40,19,18,-1,-15,0]}}
  #|{"textrec":{"g":332,"r":[134,40,19,18,-1,-15,0]}}
  #|{"textrec":{"g":333,"r":[154,40,18,18,-1,-15,0]}}
  #|{"textrec":{"g":334,"r":[173,40,18,18,-1,-15,0]}}
  #|{"textrec":{"g":335,"r":[192,40,13,13,0,-11,0]}}
  #|{"textrec":{"g":336,"r":[206,40,15,15,-1,-12,0]}}
  #|{"textrec":{"g":337,"r":[222,40,15,15,-1,-12,0]}}
  #|{"textrec":{"g":338,"r":[238,40,4,9,1,-9,0]}}
  #|{"textrec":{"g":12,"r":[243,40,9,10,-1,-8,0]}}
  #|{"textrec":{"g":339,"r":[253,40,8,9,0,-8,0]}}
  #|{"textrec":{"g":10,"r":[262,40,9,10,-1,-8,0]}}
  #|{"textrec":{"g":6,"r":[272,40,12,9,-1,-8,0]}}
  #|{"textrec":{"g":14,"r":[285,40,9,10,-1,-8,0]}}
  #|{"textrec":{"g":8,"r":[295,40,6,9,0,-8,0]}}
  #|{"textrec":{"g":340,"r":[302,40,9,13,-1,-11,0]}}
  #|{"textrec":{"g":341,"r":[312,40,7,12,-1,-10,0]}}
  #|{"textrec":{"g":342,"r":[320,40,8,12,0,-11,0]}}
  #|{"textrec":{"g":343,"r":[329,40,9,12,-1,-8,0]}}
  #|{"textrec":{"g":344,"r":[339,40,9,10,-1,-8,0]}}
  #|{"textrec":{"g":345,"r":[349,40,5,12,-1,-11,0]}}
  #|{"textrec":{"g":7,"r":[355,40,9,10,-1,-8,0]}}
  #|{"textrec":{"g":9,"r":[365,40,8,12,0,-11,0]}}
  #|{"textrec":{"g":346,"r":[374,40,11,14,-1,-12,0]}}
  #|{"textrec":{"g":347,"r":[386,40,7,13,-1,-11,0]}}
  #|{"textrec":{"g":348,"r":[394,40,9,11,-1,-9,0]}}
  #|{"textrec":{"g":349,"r":[404,40,5,13,-1,-12,0]}}
  #|{"textrec":{"g":350,"r":[410,40,10,11,-1,-9,0]}}
  #|{"textrec":{"g":351,"r":[421,40,9,10,0,-9,0]}}
  #|{"textrec":{"g":352,"r":[431,40,9,11,-1,-9,0]}}
  #|{"textrec":{"g":353,"r":[441,40,9,11,0,-9,0]}}
  #|{"textrec":{"g":354,"r":[451,40,10,14,-1,-12,0]}}
  #|{"textrec":{"g":355,"r":[462,40,16,16,-1,-13,0]}}
  #|{"textrec":{"g":356,"r":[479,40,15,15,-1,-12,0]}}
  #|{"textrec":{"g":357,"r":[495,40,10,11,-1,-9,0]}}
  #|{"textrec":{"g":358,"r":[506,40,5,4,1,-7,0]}}
  #|{"textrec":{"g":359,"r":[512,40,12,16,1,-13,0]}}
  #|{"textrec":{"g":360,"r":[525,40,15,16,-1,-13,0]}}
  #|{"textrec":{"g":361,"r":[541,40,15,15,-1,-12,0]}}
  #|{"textrec":{"g":362,"r":[557,40,15,16,-1,-13,0]}}
  #|{"textrec":{"g":363,"r":[573,40,14,16,0,-13,0]}}
  #|{"textrec":{"g":364,"r":[588,40,15,16,-1,-13,0]}}
  #|{"textrec":{"g":365,"r":[604,40,16,15,-1,-12,0]}}
  #|{"textrec":{"g":366,"r":[621,40,15,16,-1,-13,0]}}
  #|{"textrec":{"ib":["0e6dfc8705c682a0",2207,64],"r":[23,23,23,23]}}
  #|{"textrec":{"s":[13,400,0,"列出 docs 目录"],"r":[0,1,12.898832684824903,367,1,1,12.898832684824903,368,2,1,3.580078125,-1,3,1,7.9091796875,340,4,1,7.6044921875,7,5,1,7.1982421875,13,6,1,6.728515625,10,7,1,3.580078125,-1,8,1,12.89883268482491,369,9,1,12.898832684824896,370]}}
  #|{"textrec":{"s":[13,400,0,"编辑 notes.md"],"r":[0,1,12.898832684824903,371,1,1,12.898832684824903,372,2,1,3.580078125,-1,3,1,7.50927734375,339,4,1,7.6044921875,7,5,1,4.598876953125,341,6,1,7.302978515625,14,7,1,6.728515625,10,8,1,3.783203125,373,9,1,11.2353515625,374,10,1,7.9091796875,340]}}
  #|{"textrec":{"s":[13,400,0,"看过了，改好了。"],"r":[0,1,12.898832684824903,375,1,1,12.898832684824903,376,2,1,12.898832684824903,141,3,1,13.075875486381321,377,4,1,12.898832684824903,378,5,1,12.89883268482491,379,6,1,12.898832684824896,141,7,1,6.575875486381321,380]}}
  #|{"textrec":{"s":[14,400,0,"9 轮"],"r":[0,1,8.763671875,59,1,1,3.787109375,-1,2,1,13.891050583657588,381]}}
  #|{"textrec":{"s":[16,600,0,"执行历史"],"r":[0,1,15.875486381322958,382,1,1,15.875486381322958,383,2,1,15.875486381322958,384,3,1,15.875486381322958,385]}}
  #|{"textrec":{"s":[13,400,0,"步骤"],"r":[0,1,12.898832684824903,386,1,1,12.898832684824903,387]}}
  #|{"textrec":{"s":[13,400,0,"详情"],"r":[0,1,12.898832684824903,388,1,1,12.898832684824903,389]}}
  #|{"textrec":{"s":[16,700,0,"默认模型"],"r":[0,1,15.875486381322958,390,1,1,15.875486381322958,391,2,1,15.875486381322958,392,3,1,15.875486381322958,393]}}
  #|{"textrec":{"m":[16,700,0],"r":[15.46875,3.375,23,15.46875,3.375,0]}}
  #|{"textrec":{"s":[17,400,0,"返回"],"r":[0,1,16.851167315175097,394,1,1,16.851167315175097,395]}}
  #|{"textrec":{"m":[17,400,0],"r":[16.435546875,3.5859375,24,16.435546875,3.5859375,0]}}
  #|{"textrec":{"g":367,"r":[637,40,14,15,-1,-12,0]}}
  #|{"textrec":{"g":368,"r":[652,40,13,15,0,-12,0]}}
  #|{"textrec":{"g":13,"r":[666,40,9,10,-1,-8,0]}}
  #|{"textrec":{"g":369,"r":[676,40,11,14,1,-11,0]}}
  #|{"textrec":{"g":370,"r":[688,40,14,14,-1,-11,0]}}
  #|{"textrec":{"g":371,"r":[703,40,14,15,-1,-12,0]}}
  #|{"textrec":{"g":372,"r":[718,40,15,15,-1,-12,0]}}
  #|{"textrec":{"g":373,"r":[734,40,4,5,0,-3,0]}}
  #|{"textrec":{"g":374,"r":[739,40,12,9,0,-8,0]}}
  #|{"textrec":{"g":375,"r":[752,40,14,15,-1,-12,0]}}
  #|{"textrec":{"g":376,"r":[767,40,15,15,-1,-12,0]}}
  #|{"textrec":{"g":377,"r":[783,40,5,7,0,-3,0]}}
  #|{"textrec":{"g":378,"r":[789,40,15,15,-1,-12,0]}}
  #|{"textrec":{"g":379,"r":[805,40,15,15,-1,-12,0]}}
  #|{"textrec":{"g":380,"r":[821,40,6,6,0,-3,0]}}
  #|{"textrec":{"g":381,"r":[828,40,16,16,-1,-13,0]}}
  #|{"textrec":{"s":[14,400,0,"看过了，改好了。"],"r":[0,1,13.891050583657588,396,1,1,13.891050583657588,397,2,1,13.891050583657588,398,3,1,14.081712062256813,399,4,1,13.891050583657588,400,5,1,13.891050583657588,401,6,1,13.891050583657588,398,7,1,7.081712062256813,402]}}
  #|{"textrec":{"s":[14,400,0,"编辑 notes.md · 共 2 项"],"r":[0,1,13.891050583657588,403,1,1,13.891050583657588,404,2,1,3.787109375,-1,3,1,8.0185546875,351,4,1,8.12109375,350,5,1,4.88427734375,347,6,1,7.79638671875,405,7,1,7.177734375,352,8,1,4.005859375,406,9,1,12.03125,407,10,1,8.44921875,354,11,1,3.787109375,-1,12,1,6.707664066085357,358,13,1,3.787109375,-1,14,1,13.891050583657588,408,15,1,3.787109375,-1,16,1,8.298828125000014,58,17,1,3.787109375,-1,18,1,13.891050583657602,409]}}
  #|{"textrec":{"s":[13,400,0,"收到来自 "],"r":[0,1,12.898832684824903,410,1,1,12.898832684824903,411,2,1,12.898832684824903,412,3,1,12.898832684824903,413,4,1,3.580078125,-1]}}
  #|{"textrec":{"s":[13,600,0,"Name of alice"],"r":[0,1,9.785324335098267,414,1,1,7.408227801322937,415,2,1,11.745888471603394,416,3,1,7.593794465065002,417,4,1,3.3871192932128906,-1,5,1,7.841670751571655,418,6,1,5.007329106330872,419,7,1,3.3871192932128906,-1,8,1,7.408227801322937,415,9,1,3.5576319694519043,420,10,1,3.4653801918029785,421,11,1,7.427380800247192,422,12,1,7.593794465065002,417]}}
  #|{"textrec":{"m":[13,600,0],"r":[12.568359375,2.7421875,18,12.568359375,2.7421875,0]}}
  #|{"textrec":{"s":[13,400,0," 的消息"],"r":[0,1,3.580078125,-1,1,1,12.898832684824903,5,2,1,12.898832684824903,423,3,1,12.898832684824903,424]}}
  #|{"textrec":{"s":[13,400,0," · "],"r":[0,1,3.580078125,-1,1,1,6.228545204222119,289,2,1,3.580078125,-1]}}
  #|{"textrec":{"s":[13,600,0,"端到端测试的对话 post:你好，我是测试用的 agent"],"r":[0,1,12.898832684824903,425,1,1,12.898832684824903,426,2,1,12.898832684824903,425,3,1,12.898832684824903,427,4,1,12.898832684824896,428,5,1,12.898832684824896,429,6,1,12.898832684824896,430,7,1,12.898832684824896,431,8,1,3.3871192932128906,-1,9,1,8.159896612167358,432,10,1,7.841670751571655,418,11,1,7.060585141181946,433,12,1,5.030813574790955,434,13,1,4.20128059387207,435,14,1,12.898832684824896,436,15,1,12.898832684824896,437,16,1,13.075875486381335,438,17,1,12.898832684824896,439,18,1,12.898832684824896,440,19,1,12.898832684824896,427,20,1,12.898832684824896,428,21,1,12.898832684824896,441,22,1,12.898832684824896,429,23,1,3.387119293212919,-1,24,1,7.408227801322937,415,25,1,8.141171336174011,442,26,1,7.593794465065002,417,27,1,7.869065165519714,443,28,1,5.052501916885376,434]}}
  #|{"textrec":{"s":[14,400,0,"看看文档 083209 steps:文档目录看过了 083209"],"r":[0,1,13.891050583657588,396,1,1,13.891050583657588,396,2,1,13.891050583657588,444,3,1,13.891050583657588,325,4,1,3.787109375,-1,5,1,8.66796875,55,6,1,8.791015625,56,7,1,8.626953125,57,8,1,8.298828125,58,9,1,8.66796875,55,10,1,8.763671875,59,11,1,3.787109375,-1,12,1,7.1435546875,352,13,1,4.85009765625,347,14,1,7.79638671875,405,15,1,8.39453125,445,16,1,7.177734375,352,17,1,4.005859375,446,18,1,13.891050583657602,444,19,1,13.891050583657602,325,20,1,13.891050583657602,447,21,1,13.891050583657602,448,22,1,13.891050583657602,396,23,1,13.891050583657602,397,24,1,13.891050583657602,398,25,1,3.787109375,-1,26,1,8.66796875,55,27,1,8.791015625,56,28,1,8.626953125,57,29,1,8.298828125,58,30,1,8.66796875,55,31,1,8.763671875,59]}}
  #|{"textrec":{"s":[14,400,0,"再问一个 083209 card:先合并哪个分支 083209|先合 A 083209|先合 B 083209"],"r":[0,1,13.891050583657588,449,1,1,13.891050583657588,450,2,1,13.891050583657588,451,3,1,13.891050583657588,52,4,1,3.787109375,-1,5,1,8.66796875,55,6,1,8.791015625,56,7,1,8.626953125,57,8,1,8.298828125,58,9,1,8.66796875,55,10,1,8.763671875,59,11,1,3.787109375,-1,12,1,7.68359375,357,13,1,7.57421875,348,14,1,5.0791015625,452,15,1,8.3466796875,354,16,1,4.005859375,446,17,1,13.891050583657602,48,18,1,13.891050583657602,49,19,1,13.891050583657602,50,20,1,13.891050583657602,51,21,1,13.891050583657602,52,22,1,13.891050583657602,53,23,1,13.891050583657602,54,24,1,3.787109375,-1,25,1,8.66796875,55,26,1,8.791015625,56,27,1,8.626953125,57,28,1,8.298828125,58,29,1,8.66796875,55,30,1,8.763671875,59,31,1,5.22265625,453,32,1,13.891050583657602,48,33,1,13.891050583657602,49,34,1,3.787109375,-1,35,1,9.283203125,454,36,1,3.787109375,-1,37,1,8.66796875,55,38,1,8.791015625,56,39,1,8.626953125,57,40,1,8.298828125,58,41,1,8.66796875,55,42,1,8.763671875,59,43,1,5.22265625,453,44,1,13.891050583657602,48,45,1,13.891050583657602,49,46,1,3.787109375,-1,47,1,9.05078125,455,48,1,3.787109375,-1,49,1,8.66796875,55,50,1,8.791015625,56,51,1,8.626953125,57,52,1,8.298828125,58,53,1,8.66796875,55,54,1,8.763671875,59]}}
  #|{"textrec":{"s":[14,400,0,"部署吗 083209 card:要不要部署 083209|现在部署 083209*|不需要部署 083209!"],"r":[0,1,13.891050583657588,317,1,1,13.891050583657588,456,2,1,13.891050583657588,457,3,1,3.787109375,-1,4,1,8.66796875,55,5,1,8.791015625,56,6,1,8.626953125,57,7,1,8.298828125,58,8,1,8.66796875,55,9,1,8.763671875,59,10,1,3.787109375,-1,11,1,7.68359375,357,12,1,7.57421875,348,13,1,5.0791015625,452,14,1,8.346679687499986,354,15,1,4.005859375,446,16,1,13.891050583657602,458,17,1,13.891050583657602,459,18,1,13.891050583657602,458,19,1,13.891050583657602,317,20,1,13.891050583657602,456,21,1,3.787109375,-1,22,1,8.66796875,55,23,1,8.791015625,56,24,1,8.626953125,57,25,1,8.298828125,58,26,1,8.66796875,55,27,1,8.763671875,59,28,1,5.22265625,453,29,1,13.891050583657602,460,30,1,13.891050583657602,461,31,1,13.891050583657602,317,32,1,13.891050583657602,456,33,1,3.787109375,-1,34,1,8.66796875,55,35,1,8.791015625,56,36,1,8.626953125,57,37,1,8.298828125,58,38,1,8.66796875,55,39,1,8.6953125,59,40,1,6.384765625,462,41,1,5.22265625,453,42,1,13.891050583657602,459,43,1,13.891050583657602,463,44,1,13.891050583657602,458,45,1,13.891050583657602,317,46,1,13.891050583657602,456,47,1,3.787109375,-1,48,1,8.66796875,55,49,1,8.791015625,56,50,1,8.626953125,57,51,1,8.298828125,58,52,1,8.66796875,55,53,1,8.763671875,59,54,1,4.204101562499943,464]}}
  #|{"textrec":{"s":[14,400,0,"选一个颜色 083209 card:按钮用什么颜色 083209|橙色 083209*|灰色 083209"],"r":[0,1,13.891050583657588,465,1,1,13.891050583657588,451,2,1,13.891050583657588,52,3,1,13.891050583657588,466,4,1,13.891050583657588,467,5,1,3.787109375,-1,6,1,8.66796875,55,7,1,8.791015625,56,8,1,8.626953125,57,9,1,8.298828125,58,10,1,8.66796875,55,11,1,8.763671875,59,12,1,3.787109375000014,-1,13,1,7.68359375,357,14,1,7.57421875,348,15,1,5.0791015625,452,16,1,8.3466796875,354,17,1,4.005859375,446,18,1,13.891050583657602,468,19,1,13.891050583657602,469,20,1,13.891050583657602,470,21,1,13.891050583657602,471,22,1,13.891050583657602,472,23,1,13.891050583657602,466,24,1,13.891050583657602,467,25,1,3.787109375,-1,26,1,8.66796875,55,27,1,8.791015625,56,28,1,8.626953125,57,29,1,8.298828125,58,30,1,8.66796875,55,31,1,8.763671875,59,32,1,5.22265625,453,33,1,13.891050583657602,473,34,1,13.891050583657602,467,35,1,3.787109375,-1,36,1,8.66796875,55,37,1,8.791015625,56,38,1,8.626953125,57,39,1,8.298828125,58,40,1,8.66796875,55,41,1,8.6953125,59,42,1,6.384765625,462,43,1,5.22265625,453,44,1,13.891050583657602,474,45,1,13.891050583657602,467,46,1,3.787109375,-1,47,1,8.66796875,55,48,1,8.791015625,56,49,1,8.626953125,57,50,1,8.298828125,58,51,1,8.66796875,55,52,1,8.763671875,59]}}
  #|{"textrec":{"s":[14,400,0,"给我几个选项 083209 card:要不要换图标 083209|先不换 083209|一起换 083209*|不用了 083209!"],"r":[0,1,13.891050583657588,475,1,1,13.891050583657588,476,2,1,13.891050583657588,477,3,1,13.891050583657588,52,4,1,13.891050583657588,465,5,1,13.891050583657588,409,6,1,3.787109375,-1,7,1,8.66796875,55,8,1,8.791015625,56,9,1,8.626953125,57,10,1,8.298828125,58,11,1,8.66796875,55,12,1,8.763671875,59,13,1,3.787109375,-1,14,1,7.68359375,357,15,1,7.57421875,348,16,1,5.0791015625,452,17,1,8.3466796875,354,18,1,4.005859375,446,19,1,13.891050583657574,458,20,1,13.891050583657602,459,21,1,13.891050583657602,458,22,1,13.891050583657602,478,23,1,13.891050583657602,479,24,1,13.891050583657602,480,25,1,3.787109375,-1,26,1,8.66796875,55,27,1,8.791015625,56,28,1,8.626953125,57,29,1,8.298828125,58,30,1,8.66796875,55,31,1,8.763671875,59,32,1,5.22265625,453,33,1,13.891050583657602,48,34,1,13.891050583657602,459,35,1,13.891050583657602,478,36,1,3.787109375,-1,37,1,8.66796875,55,38,1,8.791015625,56,39,1,8.626953125,57,40,1,8.298828125,58,41,1,8.66796875,55,42,1,8.763671875,59,43,1,5.22265625,453,44,1,13.891050583657602,451,45,1,13.891050583657602,481,46,1,13.891050583657602,478,47,1,3.787109375,-1,48,1,8.66796875,55,49,1,8.791015625,56,50,1,8.626953125,57,51,1,8.298828125,58,52,1,8.66796875,55,53,1,8.6953125,59,54,1,6.384765625,462,55,1,5.22265625,453,56,1,13.891050583657602,459,57,1,13.891050583657602,470,58,1,13.891050583657602,398,59,1,3.787109375,-1,60,1,8.66796875,55,61,1,8.791015625,56,62,1,8.626953125,57,63,1,8.298828125,58,64,1,8.66796875,55,65,1,8.763671875,59,66,1,4.2041015625,464]}}
  #|{"textrec":{"s":[12,400,0,"已到会话开头"],"r":[0,1,11.918287937743191,297,1,1,11.918287937743191,482,2,1,11.918287937743195,483,3,1,11.918287937743187,484,4,1,11.918287937743187,485,5,1,11.918287937743187,486]}}
  #|{"textrec":{"g":394,"r":[845,40,18,18,-1,-15,0]}}
  #|{"textrec":{"g":395,"r":[864,40,16,17,0,-14,0]}}
  #|{"textrec":{"g":482,"r":[881,40,13,14,-1,-11,0]}}
  #|{"textrec":{"g":483,"r":[895,40,14,14,-1,-11,0]}}
  #|{"textrec":{"g":484,"r":[910,40,14,14,-1,-11,0]}}
  #|{"textrec":{"g":485,"r":[925,40,14,13,-1,-10,0]}}
  #|{"textrec":{"g":486,"r":[940,40,13,14,-1,-11,0]}}
  #|{"textrec":{"g":475,"r":[954,40,16,16,-1,-13,0]}}
  #|{"textrec":{"g":476,"r":[971,40,16,16,-1,-13,0]}}
  #|{"textrec":{"g":477,"r":[988,40,16,15,-1,-12,0]}}
  #|{"textrec":{"g":465,"r":[1005,40,16,16,-1,-13,0]}}
  #|{"textrec":{"g":409,"r":[1022,40,16,15,-1,-12,0]}}
  #|{"textrec":{"g":452,"r":[1039,40,6,10,0,-9,0]}}
  #|{"textrec":{"g":446,"r":[1046,40,4,10,0,-8,0]}}
  #|{"textrec":{"g":458,"r":[1051,40,16,15,-1,-12,0]}}
  #|{"textrec":{"g":459,"r":[1068,40,15,15,-1,-12,0]}}
  #|{"textrec":{"g":478,"r":[1084,40,16,16,-1,-13,0]}}
  #|{"textrec":{"g":479,"r":[1101,40,14,15,0,-12,0]}}
  #|{"textrec":{"g":480,"r":[1116,40,16,16,-1,-13,0]}}
  #|{"textrec":{"g":453,"r":[1133,40,4,15,0,-11,0]}}
  #|{"textrec":{"g":451,"r":[1138,40,15,4,-1,-7,0]}}
  #|{"textrec":{"g":481,"r":[1154,40,16,16,-1,-13,0]}}
  #|{"textrec":{"g":462,"r":[1171,40,8,8,-1,-11,0]}}
  #|{"textrec":{"g":470,"r":[1180,40,15,15,-1,-12,0]}}
  #|{"textrec":{"g":398,"r":[1196,40,13,15,0,-12,0]}}
  #|{"textrec":{"g":464,"r":[1210,40,5,13,0,-11,0]}}
  #|{"textrec":{"g":466,"r":[1216,40,16,16,-1,-13,0]}}
  #|{"textrec":{"g":467,"r":[1233,40,15,16,-1,-13,0]}}
  #|{"textrec":{"g":468,"r":[1249,40,16,16,-1,-13,0]}}
  #|{"textrec":{"g":469,"r":[1266,40,16,16,-1,-13,0]}}
  #|{"textrec":{"g":471,"r":[1283,40,15,16,-1,-13,0]}}
  #|{"textrec":{"g":472,"r":[1299,40,15,16,-1,-13,0]}}
  #|{"textrec":{"g":473,"r":[1315,40,16,16,-1,-13,0]}}
  #|{"textrec":{"g":474,"r":[1332,40,16,16,-1,-13,0]}}
  #|{"textrec":{"g":456,"r":[1349,40,15,15,-1,-12,0]}}
  #|{"textrec":{"g":457,"r":[1365,40,14,15,0,-12,0]}}
  #|{"textrec":{"g":460,"r":[1380,40,16,15,-1,-12,0]}}
  #|{"textrec":{"g":461,"r":[1397,40,15,16,-1,-13,0]}}
  #|{"textrec":{"g":463,"r":[1413,40,15,15,-1,-12,0]}}
  #|{"textrec":{"g":449,"r":[1429,40,15,15,-1,-12,0]}}
  #|{"textrec":{"g":450,"r":[1445,40,14,16,0,-13,0]}}
  #|{"textrec":{"g":454,"r":[1460,40,11,12,-1,-11,0]}}
  #|{"textrec":{"g":455,"r":[1472,40,10,12,0,-11,0]}}
  #|{"textrec":{"g":396,"r":[1483,40,15,16,-1,-13,0]}}
  #|{"textrec":{"g":444,"r":[1499,40,16,16,-1,-13,0]}}
  #|{"textrec":{"g":405,"r":[1516,40,10,11,-1,-9,0]}}
  #|{"textrec":{"g":445,"r":[1527,40,9,13,0,-9,0]}}
  #|{"textrec":{"g":447,"r":[1537,40,12,15,1,-12,0]}}
  #|{"textrec":{"g":448,"r":[1550,40,15,15,-1,-12,0]}}
  #|{"textrec":{"g":397,"r":[1566,40,16,16,-1,-13,0]}}
  #|{"textrec":{"g":399,"r":[1583,40,5,7,0,-3,0]}}
  #|{"textrec":{"g":400,"r":[1589,40,16,16,-1,-13,0]}}
  #|{"textrec":{"g":401,"r":[1606,40,16,16,-1,-13,0]}}
  #|{"textrec":{"g":402,"r":[1623,40,6,6,0,-3,0]}}
  #|{"textrec":{"ib":["b7bb1080b4377070",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["82c2071e3017b0de",757,64],"r":[13,13,13,13]}}
  #|{"textrec":{"g":390,"r":[1630,40,18,17,-1,-14,0]}}
  #|{"textrec":{"g":391,"r":[1649,40,18,17,-1,-14,0]}}
  #|{"textrec":{"g":392,"r":[1668,40,17,17,-1,-14,0]}}
  #|{"textrec":{"g":393,"r":[1686,40,17,17,-1,-14,0]}}
  #|{"textrec":{"g":410,"r":[1704,40,15,15,-1,-12,0]}}
  #|{"textrec":{"g":411,"r":[1720,40,14,15,-1,-12,0]}}
  #|{"textrec":{"g":412,"r":[1735,40,15,15,-1,-12,0]}}
  #|{"textrec":{"g":413,"r":[1751,40,11,15,1,-12,0]}}
  #|{"textrec":{"g":414,"r":[1763,40,10,12,0,-11,0]}}
  #|{"textrec":{"g":415,"r":[1774,40,9,11,-1,-9,0]}}
  #|{"textrec":{"g":416,"r":[1784,40,13,10,-1,-9,0]}}
  #|{"textrec":{"g":417,"r":[1798,40,10,11,-1,-9,0]}}
  #|{"textrec":{"g":418,"r":[1809,40,10,11,-1,-9,0]}}
  #|{"textrec":{"g":419,"r":[1820,40,7,12,-1,-11,0]}}
  #|{"textrec":{"g":420,"r":[1828,40,4,12,0,-11,0]}}
  #|{"textrec":{"g":421,"r":[1833,40,5,12,-1,-11,0]}}
  #|{"textrec":{"g":422,"r":[1839,40,9,11,-1,-9,0]}}
  #|{"textrec":{"g":5,"r":[1849,40,13,15,0,-12,0]}}
  #|{"textrec":{"g":423,"r":[1863,40,14,15,-1,-12,0]}}
  #|{"textrec":{"g":424,"r":[1878,40,15,15,-1,-12,0]}}
  #|{"textrec":{"g":403,"r":[1894,40,15,16,-1,-13,0]}}
  #|{"textrec":{"g":404,"r":[1910,40,16,16,-1,-13,0]}}
  #|{"textrec":{"g":406,"r":[1927,40,4,5,0,-3,0]}}
  #|{"textrec":{"g":407,"r":[1932,40,13,10,0,-9,0]}}
  #|{"textrec":{"g":408,"r":[1946,40,15,16,-1,-13,0]}}
  #|{"textrec":{"g":382,"r":[1962,40,18,17,-1,-14,0]}}
  #|{"textrec":{"g":383,"r":[1981,40,17,17,-1,-14,0]}}
  #|{"textrec":{"g":384,"r":[1999,40,17,17,-1,-14,0]}}
  #|{"textrec":{"g":385,"r":[2017,40,17,17,-1,-14,0]}}
  #|{"textrec":{"ib":["8fa5787697961ee2",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"g":425,"r":[0,59,15,15,-1,-12,0]}}
  #|{"textrec":{"g":426,"r":[16,59,14,15,-1,-12,0]}}
  #|{"textrec":{"g":427,"r":[31,59,14,15,-1,-12,0]}}
  #|{"textrec":{"g":428,"r":[46,59,15,15,-1,-12,0]}}
  #|{"textrec":{"g":429,"r":[62,59,14,15,-1,-12,0]}}
  #|{"textrec":{"g":430,"r":[77,59,15,15,-1,-12,0]}}
  #|{"textrec":{"g":431,"r":[93,59,15,15,-1,-12,0]}}
  #|{"textrec":{"g":432,"r":[109,59,10,13,-1,-9,0]}}
  #|{"textrec":{"g":433,"r":[120,59,9,11,-1,-9,0]}}
  #|{"textrec":{"g":434,"r":[130,59,7,12,-1,-10,0]}}
  #|{"textrec":{"g":435,"r":[138,59,5,10,0,-8,0]}}
  #|{"textrec":{"g":436,"r":[144,59,15,15,-1,-12,0]}}
  #|{"textrec":{"g":437,"r":[160,59,15,15,-1,-12,0]}}
  #|{"textrec":{"g":438,"r":[176,59,5,7,0,-3,0]}}
  #|{"textrec":{"g":439,"r":[182,59,15,15,-1,-12,0]}}
  #|{"textrec":{"g":440,"r":[198,59,14,15,-1,-12,0]}}
  #|{"textrec":{"g":441,"r":[213,59,14,14,-1,-11,0]}}
  #|{"textrec":{"g":442,"r":[228,59,10,13,-1,-9,0]}}
  #|{"textrec":{"g":443,"r":[239,59,10,10,-1,-9,0]}}
  #|{"textrec":{"ib":["5e7fcd0c8367a3ab",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"g":386,"r":[250,59,14,15,-1,-12,0]}}
  #|{"textrec":{"g":387,"r":[265,59,15,14,-1,-11,0]}}
  #|{"textrec":{"g":388,"r":[281,59,15,15,-1,-12,0]}}
  #|{"textrec":{"g":389,"r":[297,59,15,15,-1,-12,0]}}
  #|{"textrec":{"ib":["ee44219918426000",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"s":[11,400,0,"1ms"],"r":[0,1,5.1669921875,487,1,1,9.6357421875,488,2,1,5.822265625,489]}}
  #|{"textrec":{"m":[11,400,0],"r":[10.634765625,2.3203125,16,10.634765625,2.3203125,0]}}
  #|{"textrec":{"s":[13,500,0,"Edit"],"r":[0,1,7.792499661445618,490,1,1,8.08608341217041,491,2,1,3.3266119956970215,492,3,1,4.881580114364624,221]}}
  #|{"textrec":{"s":[11,400,0,"0ms"],"r":[0,1,6.9931640625,493,1,1,9.6357421875,488,2,1,5.822265625,489]}}
  #|{"textrec":{"s":[12,400,2,"/tmp/e2e/notes.md"],"r":[0,1,7.2,494,1,1,7.2,495,2,1,7.2,496,3,1,7.2,497,4,1,7.2,494,5,1,7.2,498,6,1,7.2,499,7,1,7.2,498,8,1,7.2,494,9,1,7.2,500,10,1,7.2,501,11,1,7.2,495,12,1,7.2,498,13,1,7.2,502,14,1,7.2,503,15,1,7.2,496,16,1,7.2,504]}}
  #|{"textrec":{"m":[12,400,2],"r":[12.24005126953125,3.60003662109375,17,12.720025777816772,4.080008268356323,0]}}
  #|{"textrec":{"g":487,"r":[313,59,6,10,-1,-9,0]}}
  #|{"textrec":{"g":488,"r":[320,59,11,8,-1,-7,0]}}
  #|{"textrec":{"g":489,"r":[332,59,8,9,-1,-7,0]}}
  #|{"textrec":{"g":490,"r":[341,59,8,12,0,-11,0]}}
  #|{"textrec":{"g":491,"r":[350,59,10,13,-1,-11,0]}}
  #|{"textrec":{"g":492,"r":[361,59,5,12,-1,-11,0]}}
  #|{"textrec":{"g":494,"r":[367,59,9,14,-1,-11,0]}}
  #|{"textrec":{"g":495,"r":[377,59,9,11,-1,-10,0]}}
  #|{"textrec":{"g":496,"r":[387,59,9,9,-1,-8,0]}}
  #|{"textrec":{"g":497,"r":[397,59,8,12,0,-8,0]}}
  #|{"textrec":{"g":498,"r":[406,59,8,10,0,-8,0]}}
  #|{"textrec":{"g":499,"r":[415,59,9,11,-1,-10,0]}}
  #|{"textrec":{"g":500,"r":[425,59,8,9,0,-8,0]}}
  #|{"textrec":{"g":501,"r":[434,59,8,10,0,-8,0]}}
  #|{"textrec":{"g":502,"r":[443,59,8,10,0,-8,0]}}
  #|{"textrec":{"g":503,"r":[452,59,5,5,1,-3,0]}}
  #|{"textrec":{"g":504,"r":[458,59,8,12,0,-10,0]}}
  #|{"textrec":{"g":493,"r":[467,59,9,11,-1,-9,0]}}
  #|{"textrec":{"ib":["ba295b08fbfa6d3a",757,64],"r":[13,13,13,13]}}
  #|{"textrec":{"s":[12,400,2,"ls"],"r":[0,1,7.2,505,1,1,7.2,502]}}
  #|{"textrec":{"s":[12,400,2," "],"r":[0,1,7.2,-1]}}
  #|{"textrec":{"s":[12,400,2,"docs"],"r":[0,1,7.2,504,1,1,7.2,501,2,1,7.2,506,3,1,7.2,502]}}
  #|{"textrec":{"s":[12,400,2,"stillfail-port.md\nstillfail-android-map.md"],"r":[0,1,7.2,502,1,1,7.2,495,2,1,7.200000000000001,507,3,1,7.199999999999999,505,4,1,7.199999999999999,505,5,1,7.200000000000003,508,6,1,7.200000000000003,509,7,1,7.200000000000003,507,8,1,7.200000000000003,505,9,1,7.200000000000003,510,10,1,7.200000000000003,497,11,1,7.200000000000003,501,12,1,7.200000000000003,511,13,1,7.200000000000003,495,14,1,7.200000000000003,503,15,1,7.200000000000003,496,16,1,7.200000000000003,504,17,1,0,-1,18,1,7.199999999999989,502,19,1,7.199999999999989,495,20,1,7.199999999999989,507,21,1,7.199999999999989,505,22,1,7.199999999999989,505,23,1,7.199999999999989,508,24,1,7.199999999999989,509,25,1,7.199999999999989,507,26,1,7.199999999999989,505,27,1,7.199999999999989,510,28,1,7.199999999999989,509,29,1,7.199999999999989,500,30,1,7.199999999999989,504,31,1,7.199999999999989,511,32,1,7.199999999999989,501,33,1,7.199999999999989,507,34,1,7.199999999999989,504,35,1,7.199999999999989,510,36,1,7.199999999999989,496,37,1,7.199999999999989,509,38,1,7.199999999999989,497,39,1,7.199999999999989,503,40,1,7.199999999999989,496,41,1,7.199999999999989,504]}}
  #|{"textrec":{"g":505,"r":[477,59,9,11,-1,-10,0]}}
  #|{"textrec":{"g":506,"r":[487,59,8,10,0,-8,0]}}
  #|{"textrec":{"g":507,"r":[496,59,8,12,0,-11,0]}}
  #|{"textrec":{"g":508,"r":[505,59,9,11,-1,-10,0]}}
  #|{"textrec":{"g":509,"r":[515,59,9,10,-1,-8,0]}}
  #|{"textrec":{"g":510,"r":[525,59,7,4,0,-6,0]}}
  #|{"textrec":{"g":511,"r":[533,59,8,9,0,-8,0]}}
