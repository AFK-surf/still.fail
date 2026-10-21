// e2e/traces/settings-run-settings.trace, made by scripts/trace.py from 02-settings_run_settings.log: not edited by hand.

///|
/// What the app and its core said in the run, a line each.
pub let trace_settings_run_settings : String =
  #|{"env":{"MBUI_CLOUD":"http://127.0.0.1:18787","MBUI_CORE_ACCOUNT":"{\"sub\":\"alice\",\"email\":\"alice@example.test\",\"name\":\"Name of alice\",\"picture\":\"\",\"access\":\"-\",\"refresh\":\"-\",\"accessExpires\":1792544331}"}}
  #|{"out":{"id":1,"call":"client.device","params":{"client":"still.fail mbui","app":"desktop","userAgent":"Macintosh; Mac OS X"}},"w":1792544037084.484}
  #|{"in":{"id":1,"ok":null},"w":1792544037174.546}
  #|{"out":{"id":2,"subscribe":{"topic":"accounts"},"keyed":true},"w":1792544037174.573}
  #|{"out":{"id":3,"subscribe":{"topic":"prefs"},"keyed":true},"w":1792544037174.583}
  #|{"step":"# written by scripts/rerecord.sh from its test (src/sfreplay/emit.mbt): not edited by hand","w":1792544037176.032}
  #|{"step":"timeout 90000","w":1792544037176.038}
  #|{"step":"answered client.device","w":1792544037176.04}
  #|{"step":"answered client.focus","w":1792544037197.542}
  #|{"in":{"id":2,"value":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""}]},"w":1792544037263.837}
  #|{"in":{"id":3,"value":{"onlyMine":false,"onlyWatching":false,"onlyDecisions":false,"listFilter":{},"appearance":"system","rowPicture":"auto","absoluteTime":false,"lang":"zh","keys":{},"lastChat":{},"openChat":{"01M5DZ6CKCGSJNJ2JVN896150A":{"station":"01M5DZ6CKCGSJNJ2JVN896150A/b21cd79ef56404b65ff8cf06f243fdbcc3b3989336f6bdd4b4a201f04793192e","key":"ember:c-192380e096"}},"chatTabs":{},"dropFiles":{},"driveViews":{},"resume":{},"stationUpdatesDismissed":{},"device":{"app":"desktop","phone":false,"handoff":false},"reader":{"size":18,"line":1.7,"margin":22,"face":"sans","indent":true,"paper":"follow"},"rails":{},"bars":{"sets":[["chats","files","profiles","stations"],["decisions","usage","connects","archive"]],"current":0},"barsBy":{},"fonts":{},"faces":{"ui":{"id":"","name":"","mono":false,"family":"","files":[],"bytes":0},"text":{"id":"","name":"","mono":false,"family":"","files":[],"bytes":0},"code":{"id":"","name":"","mono":true,"family":"","files":[],"bytes":0},"list":[{"id":"inter","name":"Inter","mono":false,"family":"SF Inter","css":"http://127.0.0.1:18787/releases/fonts/inter/4.001/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/inter/4.001/var.ttf.gz","bytes":457818,"sha256":"29160a80ff49ddcab2c97711247e08b1fab27a484a329ce8b813d820dc559031"}],"preview":"http://127.0.0.1:18787/releases/fonts/inter/4.001/preview-194fa287.ttf","bytes":457818},{"id":"noto-sans-sc","name":"思源黑体","mono":false,"family":"SF Noto Sans SC","css":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/var.ttf.gz","bytes":11276563,"sha256":"a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da"}],"preview":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/preview-f0494178.ttf","bytes":11276563},{"id":"noto-serif-sc","name":"思源宋体","mono":false,"family":"SF Noto Serif SC","css":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/var.ttf.gz","bytes":15454579,"sha256":"050080d9255a86808f2945bffac582b31ef32bc36411ce29563b4961670c66f9"}],"preview":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/preview-001bbedf.ttf","bytes":15454579},{"id":"lxgw-wenkai","name":"霞鹜文楷","mono":false,"family":"SF LXGW WenKai","css":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/font.css","files":[{"weight":400,"url":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/400.ttf.gz","bytes":12904482,"sha256":"2d73eea94ad808999d90c0000c239a84a33b09d4bc6ab6c5b8bbf1eda8a7fc8b"},{"weight":500,"url":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/500.ttf.gz","bytes":13272430,"sha256":"f4b8a34d1f838fe411540cb7c97b1c384ac9738a876c4104500bc42508b2312a"}],"preview":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/preview-d3505af4.ttf","bytes":26176912},{"id":"jetbrains-mono","name":"JetBrains Mono","mono":true,"family":"SF JetBrains Mono","css":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/var.ttf.gz","bytes":90579,"sha256":"48715a42ec242c21e9f02692891e147d022299a52e48d5e413e1a942193ffeda"}],"preview":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/preview-ee73078f.ttf","bytes":90579},{"id":"fira-code","name":"Fira Code","mono":true,"family":"SF Fira Code","css":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/var.ttf.gz","bytes":137151,"sha256":"9335b082b3c7850d98a64b584f3417f65355f3471278bb5eeb8c6c0e8657aeeb"}],"preview":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/preview-555be27a.ttf","bytes":137151},{"id":"maple-mono","name":"Maple Mono","mono":true,"family":"SF Maple Mono CN","css":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/font.css","files":[{"weight":400,"url":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/400.ttf.gz","bytes":8352545,"sha256":"0fcc5139bfd5ab14ff989bb7dfd5236d0cafc10e60b9828569e6883613ab4085"},{"weight":600,"url":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/600.ttf.gz","bytes":8438132,"sha256":"96ed7ae26ee7c50b02b2d2b2bc0f1a0cbabe45ae5d6e6abf6678e2177c415677"}],"preview":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/preview-cffdf246.ttf","bytes":16790677}]}}},"w":1792544037263.881}
  #|{"out":{"id":4,"subscribe":{"topic":"workspaces"},"keyed":true},"w":1792544037263.938}
  #|{"out":{"id":5,"subscribe":{"topic":"status"},"keyed":true},"w":1792544037263.948}
  #|{"in":{"id":4,"value":[{"account":{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""},"workspaces":[{"id":"01M5DZ6CKCGSJNJ2JVN896150A","name":"Dev","role":"owner","created_at":1792544027,"stations":1,"members":1,"relays":[],"time":{"created_at":{"past":true,"at":1792544027000,"ago":"刚刚","full":"10/21 08:53:47","until":"1 分钟内"}}}],"invitations":[],"relay_url":"http://127.0.0.1:18740","loaded":true,"beta":true}]},"w":1792544037282.374}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792544037282.417}
  #|{"out":{"id":6,"subscribe":{"topic":"lock","workspace":"01M5DZ6CKCGSJNJ2JVN896150A"},"keyed":true},"w":1792544037282.48}
  #|{"out":{"id":7,"subscribe":{"topic":"chats","scope":"01M5DZ6CKCGSJNJ2JVN896150A","mine":false},"keyed":true},"w":1792544037282.514}
  #|{"out":{"id":8,"subscribe":{"topic":"workspaceMarks","workspace":"01M5DZ6CKCGSJNJ2JVN896150A"},"keyed":true},"w":1792544037282.783}
  #|{"out":{"id":9,"subscribe":{"topic":"status","workspace":"01M5DZ6CKCGSJNJ2JVN896150A"},"keyed":true},"w":1792544037282.847}
  #|{"out":{"id":10,"call":"client.focus","params":{"visible":true,"focused":true,"workspace":"01M5DZ6CKCGSJNJ2JVN896150A"}},"w":1792544037290.313}
  #|{"out":{"id":11,"subscribe":{"topic":"notify"},"keyed":true},"w":1792544037290.324}
  #|{"out":{"id":12,"subscribe":{"topic":"notify","workspace":"01M5DZ6CKCGSJNJ2JVN896150A"},"keyed":true},"w":1792544037290.332}
  #|{"in":{"id":6,"value":{"available":true,"locked":false,"notice":true,"role":"owner","manages":true,"owner":true,"canSign":true,"signs":false,"me":{"device":"d04eb47ccb2d79d748196f5156b859c29e19d3c991964ad5019abc369f96de5c","code":"36M-ZKC","kind":"app","confirmed":false,"waiting":false,"asked":false},"signers":0,"members":[],"stations":[{"id":"b21cd79ef56404b65ff8cf06f243fdbcc3b3989336f6bdd4b4a201f04793192e","name":"studio","version":"0.1.0","online":true,"protected":false}],"protected":0,"requests":[],"renew":[],"attention":0}},"w":1792544037297.173}
  #|{"in":{"id":7,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"stations":[{"station":"01M5DZ6CKCGSJNJ2JVN896150A/b21cd79ef56404b65ff8cf06f243fdbcc3b3989336f6bdd4b4a201f04793192e","id":"b21cd79ef56404b65ff8cf06f243fdbcc3b3989336f6bdd4b4a201f04793192e","name":"studio","state":"online"}],"loading":false,"days":[{"daysAgo":0,"at":1792544035432,"label":"今天","items":[{"id":"ember:c-192380e096","session":"ember:c-192380e096","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","agents":[{"key":"ember:c-192380e096","runtime":"claude","process":"warm","pending":0,"lastTurn":{"id":"9e5cfb63-a629-412f-8c0a-74ff65cefbe6","kind":"input","outcome":"completed","declared":"final","ending":"all_done","need":"answered the question that was asked","startedAt":1792544035389,"endedAt":1792544035434},"agentText":"默认模型","statusText":"已完成：answered the question that was asked"}],"last":{"seq":4,"authorKind":"agent","author":"ember:c-192380e096","text":"文档目录看过了 083209","createdAt":1792544035432,"by":{"kind":"agent","name":"agent","mine":false,"runtime":"claude","label":"agent"},"preview":"文档目录看过了 083209","time":{"createdAt":{"at":1792544035432,"ago":"刚刚","full":"10/21 08:53:55","until":"1 分钟内","past":true}}},"unread":false,"mine":true,"lastActiveAt":1792544035432,"station":"01M5DZ6CKCGSJNJ2JVN896150A/b21cd79ef56404b65ff8cf06f243fdbcc3b3989336f6bdd4b4a201f04793192e","stationName":"studio","time":{"lastActiveAt":{"at":1792544035432,"ago":"刚刚","full":"10/21 08:53:55","until":"1 分钟内","past":true}},"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"peopleText":"你 发起","clientKey":"new:chat-828448ccfecfa337ab","pinned":false,"settled":true,"archivable":true,"stateText":"已完成：answered the question that was asked"}]}],"trouble":null,"members":1,"leading":"agents","glyph":{"online":1,"dim":0,"connecting":0,"failing":0,"working":0,"summary":"studio","label":"1 台 station，1 台在线"},"note":{"reading":false,"text":null,"failing":[],"empty":false}}},"w":1792544037297.209}
  #|{"in":{"id":8,"value":{"workspaces":{"01M5DZ6CKCGSJNJ2JVN896150A":{"alert":0,"unread":0,"chat":{"station":"01M5DZ6CKCGSJNJ2JVN896150A/b21cd79ef56404b65ff8cf06f243fdbcc3b3989336f6bdd4b4a201f04793192e","key":"ember:c-192380e096"},"badge":0,"items":[]}},"badge":0,"badgeCounts":"attention","badgeKinds":{"on":true,"wait":true,"failed":true,"done":false,"message":false}}},"w":1792544037297.234}
  #|{"in":{"id":9,"value":{"items":[]}},"w":1792544037297.238}
  #|{"in":{"id":10,"ok":null},"w":1792544037297.241}
  #|{"in":{"id":11,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792544037297.248}
  #|{"in":{"id":12,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792544037297.252}
  #|{"out":{"id":13,"subscribe":{"topic":"longJobs","scope":"01M5DZ6CKCGSJNJ2JVN896150A"},"keyed":true},"w":1792544037297.285}
  #|{"out":{"id":14,"call":"notify.permission","params":{"state":"unknown"}},"w":1792544037300.713}
  #|{"in":{"id":13,"value":{"groups":[]}},"w":1792544037313.832}
  #|{"in":{"id":14,"ok":null},"w":1792544037313.847}
  #|{"step":"answered notify.permission","w":1792544037314.255}
  #|{"step":"tap 端到端测试","w":1792544037330.912}
  #|{"step":"tap 端到端测试","acted":true,"w":1792544037330.93}
  #|{"out":{"id":15,"subscribe":{"topic":"chat","station":"01M5DZ6CKCGSJNJ2JVN896150A/b21cd79ef56404b65ff8cf06f243fdbcc3b3989336f6bdd4b4a201f04793192e","session":"ember:c-192380e096"},"keyed":true},"w":1792544037347.278}
  #|{"out":{"id":16,"call":"draft.get","params":{"key":"01M5DZ6CKCGSJNJ2JVN896150A/b21cd79ef56404b65ff8cf06f243fdbcc3b3989336f6bdd4b4a201f04793192e:ember:c-192380e096"}},"w":1792544037347.669}
  #|{"step":"answered draft.get","w":1792544037347.797}
  #|{"in":{"id":16,"ok":{"text":"","quotes":[],"files":[],"id":"draft-c8b960bd8fd7e23db8"}},"w":1792544037363.836}
  #|{"in":{"id":15,"value":{"archived":false,"pinned":false,"me":{"id":"alice@example.test","email":"alice@example.test"},"thread":{"id":1,"surface":"ember","channel":"EMBER","threadTs":"1792544031.661000","createdBy":"alice@example.test","creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"createdAt":1792544031661,"sessions":[{"thread":1,"session":"ember:c-192380e096","connect":"ember","joinedAt":1792544031661}],"last":4,"lastMessage":{"seq":4,"thread":1,"ts":"1792544035.432000","authorKind":"agent","author":"ember:c-192380e096","text":"文档目录看过了 083209","attachments":[],"quotes":[],"declared":"final","ending":"all_done","createdAt":1792544035432,"time":{"createdAt":{"at":1792544035432,"ago":"刚刚","full":"10/21 08:53:55","until":"1 分钟内","past":true}}},"read":4,"unread":0,"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"firstText":"端到端测试的对话 post:你好，我是测试用的 agent","time":{"createdAt":{"at":1792544031661,"ago":"刚刚","full":"10/21 08:53:51","until":"1 分钟内","past":true}}},"title":"端到端测试的对话 post:你好，我是测试用的 agent","people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"agents":[{"session":{"key":"ember:c-192380e096","connect":"ember","scope":"all","createdBy":"alice@example.test","boundTo":[],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"},"participants":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"}],"runtime":"claude","profile":"cc","profilePinned":false,"runtimeSessionId":"59d77441-3b24-4a5b-93b2-d2fe2f6650d7","workspace":"/tmp/mbe2e-C/data/sessions/ember/c-192380e096/workspace","running":false,"createdAt":1792544031660,"lastActiveAt":1792544035434,"process":"warm","turns":2,"pending":0,"firstText":"端到端测试的对话 post:你好，我是测试用的 agent","lastTurn":{"id":"9e5cfb63-a629-412f-8c0a-74ff65cefbe6","kind":"input","outcome":"completed","declared":"final","ending":"all_done","need":"answered the question that was asked","startedAt":1792544035389,"endedAt":1792544035434},"statusText":"已完成：answered the question that was asked","tone":"green","titleText":"端到端测试的对话 post:你好，我是测试用的 agent","agentText":"默认模型","runtimeText":"Claude Code","processText":"保温中","efforts":["low","medium","high","xhigh","max"],"time":{"createdAt":{"at":1792544031660,"ago":"刚刚","full":"10/21 08:53:51","until":"1 分钟内","past":true},"lastActiveAt":{"at":1792544035434,"ago":"刚刚","full":"10/21 08:53:55","until":"1 分钟内","past":true}}},"status":"final","profile":{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792544031578,"time":{"checkedAt":{"at":1792544031578,"ago":"刚刚","full":"10/21 08:53:51","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792544031700,"time":{"checkedAt":{"at":1792544031700,"ago":"刚刚","full":"10/21 08:53:51","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]},"profiles":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":true,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792544031700,"time":{"checkedAt":{"at":1792544031700,"ago":"刚刚","full":"10/21 08:53:51","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}],"choices":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":true,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792544031700,"time":{"checkedAt":{"at":1792544031700,"ago":"刚刚","full":"10/21 08:53:51","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"account":{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":true,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792544031700,"time":{"checkedAt":{"at":1792544031700,"ago":"刚刚","full":"10/21 08:53:51","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}},"attention":[],"turns":[{"id":"d93699a3-f13a-44dd-8cff-d2ff72ef2449","kind":"input","outcome":"completed","declared":"final","ending":"all_done","startedAt":1792544031723,"endedAt":1792544031792},{"id":"9e5cfb63-a629-412f-8c0a-74ff65cefbe6","kind":"input","outcome":"completed","declared":"final","ending":"all_done","startedAt":1792544035389,"endedAt":1792544035434}],"threads":[{"id":1,"surface":"ember","channel":"EMBER","threadTs":"1792544031.661000","createdBy":"alice@example.test","creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"},"createdAt":1792544031661,"sessions":[{"thread":1,"session":"ember:c-192380e096","connect":"ember","joinedAt":1792544031661}],"last":4,"lastMessage":{"seq":4,"thread":1,"ts":"1792544035.432000","authorKind":"agent","author":"ember:c-192380e096","text":"文档目录看过了 083209","attachments":[],"quotes":[],"declared":"final","ending":"all_done","createdAt":1792544035432,"time":{"createdAt":{"at":1792544035432,"ago":"刚刚","full":"10/21 08:53:55","until":"1 分钟内","past":true}}},"read":4,"unread":0,"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"}],"firstText":"端到端测试的对话 post:你好，我是测试用的 agent","time":{"createdAt":{"at":1792544031661,"ago":"刚刚","full":"10/21 08:53:51","until":"1 分钟内","past":true}}}],"jobs":[]}],"messages":[{"seq":1,"thread":1,"ts":"1792544031.711000","authorKind":"person","author":"alice@example.test","authorName":"Name of alice","text":"端到端测试的对话 post:你好，我是测试用的 agent","attachments":[],"quotes":[],"createdAt":1792544031711,"mine":true,"system":false,"by":{"name":"Name of alice","picture":"https://example.test/p.png"},"waiting":false,"time":{"createdAt":{"at":1792544031711,"ago":"刚刚","full":"10/21 08:53:51","until":"1 分钟内","past":true}}},{"seq":2,"thread":1,"ts":"1792544031.790000","authorKind":"agent","author":"ember:c-192380e096","text":"你好，我是测试用的 agent","attachments":[],"quotes":[],"declared":"final","ending":"all_done","createdAt":1792544031790,"mine":false,"system":false,"by":{"name":"默认模型","agent":"ember:c-192380e096","runtime":"claude","here":true},"waiting":false,"time":{"createdAt":{"at":1792544031790,"ago":"刚刚","full":"10/21 08:53:51","until":"1 分钟内","past":true}}},{"seq":3,"thread":1,"ts":"1792544035.386000","authorKind":"person","author":"alice@example.test","authorName":"Name of alice","text":"看看文档 083209 steps:文档目录看过了 083209","attachments":[],"quotes":[],"createdAt":1792544035386,"mine":true,"system":false,"by":{"name":"Name of alice","picture":"https://example.test/p.png"},"waiting":false,"time":{"createdAt":{"at":1792544035386,"ago":"刚刚","full":"10/21 08:53:55","until":"1 分钟内","past":true}}},{"seq":4,"thread":1,"ts":"1792544035.432000","authorKind":"agent","author":"ember:c-192380e096","text":"文档目录看过了 083209","attachments":[],"quotes":[],"declared":"final","ending":"all_done","createdAt":1792544035432,"mine":false,"system":false,"by":{"name":"默认模型","agent":"ember:c-192380e096","runtime":"claude","here":true},"waiting":false,"time":{"createdAt":{"at":1792544035432,"ago":"刚刚","full":"10/21 08:53:55","until":"1 分钟内","past":true}}}],"elsewhere":[],"more":false,"newer":false,"caught":4,"unreadAbove":false,"outbox":[],"link":{"state":"online"},"offline":false,"pending":false,"asks":[],"archivable":true,"publish":{"may":true,"links":[]}}},"w":1792544037363.929}
  #|{"out":{"id":17,"subscribe":{"topic":"stations","scope":"01M5DZ6CKCGSJNJ2JVN896150A"},"keyed":true},"w":1792544037364.057}
  #|{"out":{"id":18,"subscribe":{"topic":"chatJobs","station":"01M5DZ6CKCGSJNJ2JVN896150A/b21cd79ef56404b65ff8cf06f243fdbcc3b3989336f6bdd4b4a201f04793192e","session":"ember:c-192380e096"},"keyed":true},"w":1792544037364.067}
  #|{"out":{"id":19,"call":"picture","params":{"url":"https://example.test/p.png"}},"w":1792544037364.079}
  #|{"out":{"id":20,"call":"client.focus","params":{"chat":{"station":"01M5DZ6CKCGSJNJ2JVN896150A/b21cd79ef56404b65ff8cf06f243fdbcc3b3989336f6bdd4b4a201f04793192e","session":"ember:c-192380e096","thread":1,"end":true}}},"w":1792544037366.339}
  #|{"in":{"id":17,"value":[{"station":"01M5DZ6CKCGSJNJ2JVN896150A/b21cd79ef56404b65ff8cf06f243fdbcc3b3989336f6bdd4b4a201f04793192e","id":"b21cd79ef56404b65ff8cf06f243fdbcc3b3989336f6bdd4b4a201f04793192e","name":"studio","summary":"空闲 · Apple M4 · 16 GB · macOS 27.0.1","face":"idle","line":"Apple M4","online":true,"reconnecting":false,"lastSeen":1792544031,"version":"0.1.0","link":{"state":"online"},"runtimes":[{"runtime":"claude","models":["claude-sonnet-5-5"]}],"models":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792544031700,"time":{"checkedAt":{"at":1792544031700,"ago":"刚刚","full":"10/21 08:53:51","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"overview":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null,"summaryText":"最近 7 天检查了 0 个 chat","changeText":null}},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","email":"alice@example.test","name":"Name of alice","sub":"alice","role":"owner","workspace":"01M5DZ6CKCGSJNJ2JVN896150A","device":"d04eb47ccb2d79d748196f5156b859c29e19d3c991964ad5019abc369f96de5c"},"connects":[],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792544031578,"time":{"checkedAt":{"at":1792544031578,"ago":"刚刚","full":"10/21 08:53:51","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792544031700,"time":{"checkedAt":{"at":1792544031700,"ago":"刚刚","full":"10/21 08:53:51","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]}],"processes":[],"counts":{"sessions":1,"running":0,"warm":1},"mesh":{"state":"running","origin":"http://127.0.0.1:18787","station":"b21cd79ef56404b65ff8cf06f243fdbcc3b3989336f6bdd4b4a201f04793192e","workspace":"Dev","workspaceId":"01M5DZ6CKCGSJNJ2JVN896150A","name":"studio"},"slackUsers":[],"slackTeams":[],"slackApps":[],"feishuRegistrations":[],"disk":{"freeBytes":53605838848,"totalBytes":245107195904},"logins":[],"machineLogins":[],"sharing":true,"consoleSignIn":true,"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"google","name":"Google Gemini","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xai","name":"xAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"mistral","name":"Mistral","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"deepseek","name":"DeepSeek","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen","name":"Qwen","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai","name":"Kimi","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai","name":"Z.ai","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax","name":"MiniMax","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ant-ling","name":"Ant Ling","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"jev","name":"Jev","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen-cn","name":"Qwen (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"openrouter","name":"OpenRouter","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"opencode","name":"OpenCode Zen","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"groq","name":"Groq","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"together","name":"Together AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"fireworks","name":"Fireworks","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cerebras","name":"Cerebras","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"huggingface","name":"Hugging Face","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"nvidia","name":"NVIDIA","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"baseten","name":"Baseten","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ollama","name":"Ollama","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"custom","name":"Custom","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""}],"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792544029118},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.305","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792544029118},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-publish/apps/e2e-local/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792544029118},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-publish/apps/e2e-local/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792544029118},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","latest":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-publish/apps/e2e-local/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792544029118},{"id":"cursor","name":"Cursor","installed":false,"latest":"1.0.40","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792544029118},{"id":"devin","name":"Devin","installed":true,"version":"3000.11.92","latest":"3000.11.92","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-publish/apps/e2e-local/ember/station/test/fake/devin，不是用 Devin 的安装脚本装的，需在该机器上手动更新","state":"idle","checkedAt":1792544029118}],"processesText":"没有运行中的 agent 进程","agentEnv":[],"drive":{"roots":[],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false}},"betaOffered":false,"host":{"hostname":"3720-Mac-mini-1","os":"macOS 27.0.1","arch":"arm64","cpus":10,"cpuModel":"Apple M4","load":0.79,"cpuBusy":0.15,"uptimeSec":23396,"memory":{"totalBytes":17179869184,"usedBytes":9193979904,"swapUsedBytes":309130691},"disk":{"path":"/tmp/mbe2e-C/data","totalBytes":245107195904,"freeBytes":53621567488},"emberRssBytes":157071256,"checkedAt":1792544034773,"summary":"10 核 · 16 GB","line":"macOS 27.0.1 · 10 核 · 16 GB · 已运行 0 天","facts":["3720-Mac-mini-1","macOS 27.0.1","arm64 · 10 核","已运行 6 小时"],"meters":[{"label":"CPU","short":"CPU","percent":15,"left":85,"level":"ok","value":"15%","remaining":"空闲 85%","big":"85","unit":"%","title":"CPU 空闲","total":"负载 7.9","note":"负载 7.9 · Apple M4"},{"label":"内存","short":"内存","percent":54,"left":46,"level":"ok","value":"8.6 GB / 16.0 GB","remaining":"剩 7.4 G","big":"7.4","unit":"GB","title":"内存剩","total":"共 16 GB","note":"swap 0.3 GB"},{"label":"磁盘","short":"磁盘","percent":78,"left":22,"level":"amber","value":"剩余 49.9 GB / 228 GB","remaining":"剩 49.9 G","big":"49.9","unit":"GB","title":"磁盘剩","total":"共 228 GB"}],"identity":"Apple M4 · 16 GB · macOS 27.0.1","details":[{"label":"主机名","value":"3720-Mac-mini-1"},{"label":"芯片","value":"Apple M4 · 10 核 · arm64"},{"label":"已运行","value":"6 小时"},{"label":"still.fail","value":"进程占用 150 MB"}],"usage":"内存 8.6 GB / 16.0 GB · 磁盘 剩余 49.9 GB / 228 GB","emberText":"still.fail 150 MB"},"way":{"path":"直连","via":"direct"},"time":{"lastSeen":{"at":1792544031000,"ago":"刚刚","full":"10/21 08:53:51","until":"1 分钟内","past":true}},"joined":false}]},"w":1792544037380.611}
  #|{"in":{"id":18,"value":{"jobs":[],"servicesNote":"","jobsNote":"","current":0,"ended":0,"clear":[],"allText":"全部 0 个","clearText":"清除 0 个已结束的","hiddenText":"另有 0 个已停止或结束"}},"w":1792544037380.699}
  #|{"in":{"id":20,"ok":null},"w":1792544037380.704}
  #|{"step":"answered picture","w":1792544037381.629}
  #|{"in":{"id":17,"delta":[{"path":[0,"overview","disk","freeBytes"],"set":53605736448}]},"w":1792544037480.501}
  #|{"in":{"id":19,"error":{"code":"picture","message":"无法加载图片：error sending request for url (https://example.test/p.png): client error (Connect): tls handshake eof"}},"w":1792544037563.871}
  #|{"step":"answered client.focus","w":1792544037582.813}
  #|{"step":"until =studio","w":1792544037599.779}
  #|{"step":"tap icon:more","w":1792544037599.807}
  #|{"step":"tap icon:more","acted":true,"w":1792544037599.845}
  #|{"step":"tap1 icon:chevron-right","w":1792544037636.675}
  #|{"step":"tap1 icon:chevron-right","acted":true,"w":1792544037699.164}
  #|{"step":"tap =历史","w":1792544037716.034}
  #|{"out":{"id":21,"subscribe":{"topic":"agentCard","station":"01M5DZ6CKCGSJNJ2JVN896150A/b21cd79ef56404b65ff8cf06f243fdbcc3b3989336f6bdd4b4a201f04793192e","key":"ember:c-192380e096"},"keyed":true},"w":1792544037730.984}
  #|{"step":"tap =历史","acted":true,"w":1792544037742.032}
  #|{"in":{"id":21,"value":{"work":"2 轮","latest":[{"key":"1","text":"列出 docs 目录"},{"key":"3","text":"编辑 notes.md"},{"key":"5","text":"看过了，改好了。"}],"attention":[]}},"w":1792544037747.22}
  #|{"out":{"id":22,"subscribe":{"topic":"history","station":"01M5DZ6CKCGSJNJ2JVN896150A/b21cd79ef56404b65ff8cf06f243fdbcc3b3989336f6bdd4b4a201f04793192e","key":"ember:c-192380e096"},"keyed":true},"w":1792544037750.395}
  #|{"step":"tap =详情","w":1792544037754.943}
  #|{"in":{"id":22,"value":{"items":[{"key":"e0","entries":[0,0],"body":{"kind":"received","content":{"tasks":[],"messages":[{"key":"1792544035.386000","from":{"name":"Name of alice","bound":false},"text":"看看文档 083209 steps:文档目录看过了 083209","place":{"name":"端到端测试的对话 post:你好，我是测试用的 agent","surface":"ember","session":"ember:c-192380e096"}}]}},"turn":{"at":1792544035392,"time":"08:53","text":"2 步 · 未发消息"}},{"key":"e1","entries":[1,4],"body":{"kind":"group","content":{"summary":"编辑 notes.md · 共 2 项","title":"运行 1 条命令、编辑 1 个文件","failures":0,"pending":0,"rows":[{"kind":"step","content":{"said":"列出 docs 目录","name":"Bash","hint":"ls docs","meta":"1ms","failed":false,"call":"{\n  \"command\": \"ls docs\",\n  \"description\": \"列出 docs 目录\"\n}","result":"stillfail-port.md\nstillfail-android-map.md","entries":[1,2],"brief":false}},{"kind":"step","content":{"name":"Edit","hint":"/tmp/e2e/notes.md","meta":"0ms","failed":false,"call":"{\n  \"file_path\": \"/tmp/e2e/notes.md\",\n  \"old_string\": \"旧的一行\",\n  \"new_string\": \"新的一行\"\n}","result":"The file /tmp/e2e/notes.md has been updated.","entries":[3,4],"brief":false}}]}}},{"key":"e5","entries":[5,5],"body":{"kind":"text","content":{"text":"看过了，改好了。","md":[["p",["看过了，改好了。"]]],"subagent":false}}}],"live":[],"usage":[{"label":"模型调用","value":"0 次"},{"label":"输入","value":"0"},{"label":"其中缓存","value":"0"},{"label":"输出","value":"0"},{"label":"缓存命中率","value":"未报告"}],"usageLine":"调用 0 次 · 输入 0 · 输出 0","edge":"已到会话开头","empty":false,"loaded":true,"more":false}},"w":1792544037780.52}
  #|{"in":{"id":17,"delta":[{"path":[0,"overview","disk","freeBytes"],"set":53605937152}]},"w":1792544037780.551}
  #|{"step":"tap =详情","acted":true,"w":1792544037949.394}
  #|{"out":{"id":23,"subscribe":{"topic":"host","station":"01M5DZ6CKCGSJNJ2JVN896150A/b21cd79ef56404b65ff8cf06f243fdbcc3b3989336f6bdd4b4a201f04793192e"},"keyed":true},"w":1792544037964.401}
  #|{"step":"tap icon:chevron-down","w":1792544037984.262}
  #|{"step":"tap icon:chevron-down","acted":true,"w":1792544037984.303}
  #|{"in":{"id":23,"value":{"hostname":"3720-Mac-mini-1","os":"macOS 27.0.1","arch":"arm64","cpus":10,"cpuModel":"Apple M4","load":0.79,"cpuBusy":0.15,"uptimeSec":23396,"memory":{"totalBytes":17179869184,"usedBytes":9193979904,"swapUsedBytes":309130691},"disk":{"path":"/tmp/mbe2e-C/data","totalBytes":245107195904,"freeBytes":53621567488},"emberRssBytes":157071256,"checkedAt":1792544034773,"summary":"10 核 · 16 GB","line":"macOS 27.0.1 · 10 核 · 16 GB · 已运行 0 天","facts":["3720-Mac-mini-1","macOS 27.0.1","arm64 · 10 核","已运行 6 小时"],"meters":[{"label":"CPU","short":"CPU","percent":15,"left":85,"level":"ok","value":"15%","remaining":"空闲 85%","big":"85","unit":"%","title":"CPU 空闲","total":"负载 7.9","note":"负载 7.9 · Apple M4"},{"label":"内存","short":"内存","percent":54,"left":46,"level":"ok","value":"8.6 GB / 16.0 GB","remaining":"剩 7.4 G","big":"7.4","unit":"GB","title":"内存剩","total":"共 16 GB","note":"swap 0.3 GB"},{"label":"磁盘","short":"磁盘","percent":78,"left":22,"level":"amber","value":"剩余 49.9 GB / 228 GB","remaining":"剩 49.9 G","big":"49.9","unit":"GB","title":"磁盘剩","total":"共 228 GB"}],"identity":"Apple M4 · 16 GB · macOS 27.0.1","details":[{"label":"主机名","value":"3720-Mac-mini-1"},{"label":"芯片","value":"Apple M4 · 10 核 · arm64"},{"label":"已运行","value":"6 小时"},{"label":"still.fail","value":"进程占用 150 MB"}],"usage":"内存 8.6 GB / 16.0 GB · 磁盘 剩余 49.9 GB / 228 GB","emberText":"still.fail 150 MB"}},"w":1792544037984.53}
  #|{"out":{"id":24,"subscribe":{"topic":"pick","station":"01M5DZ6CKCGSJNJ2JVN896150A/b21cd79ef56404b65ff8cf06f243fdbcc3b3989336f6bdd4b4a201f04793192e","of":"session:ember:c-192380e096"},"keyed":true},"w":1792544037986.127}
  #|{"out":{"id":25,"call":"pick.set","params":{"station":"01M5DZ6CKCGSJNJ2JVN896150A/b21cd79ef56404b65ff8cf06f243fdbcc3b3989336f6bdd4b4a201f04793192e","of":"session:ember:c-192380e096","open":true}},"w":1792544037986.171}
  #|{"step":"answered pick.set","w":1792544037992.503}
  #|{"in":{"id":25,"ok":null},"w":1792544037997.175}
  #|{"in":{"id":24,"value":{"fastAvailable":false,"options":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":true,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792544031700,"time":{"checkedAt":{"at":1792544031700,"ago":"刚刚","full":"10/21 08:53:51","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]},"availability":"here"}],"runtimeFixed":true,"value":{"runtime":"claude"},"account":{"text":"自动 · cc","auto":true,"profile":{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":true,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792544031700,"time":{"checkedAt":{"at":1792544031700,"ago":"刚刚","full":"10/21 08:53:51","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}},"draft":{"runtime":"claude"},"runtimes":[],"efforts":["low","medium","high","xhigh","max"],"accounts":[],"who":"账号","autoNote":"当前：cc","changed":false,"was":["默认模型","默认深度","自动 · cc"],"becomes":["默认模型","默认深度","自动分配"],"modelText":"选择模型","accountText":"自动分配","accountNote":"额度用完或登录失效时自动切换","accountWarn":false,"saveText":"无变更"}},"w":1792544037997.329}
  #|{"out":{"id":26,"subscribe":{"topic":"doing"},"keyed":true},"w":1792544037997.621}
  #|{"in":{"id":26,"value":{"doing":[]}},"w":1792544038013.848}
  #|{"step":"until 思考深度","w":1792544038014.879}
  #|{"step":"tap =high","w":1792544038053.797}
  #|{"step":"tap =high","acted":true,"w":1792544038115.704}
  #|{"out":{"id":27,"call":"pick.set","params":{"station":"01M5DZ6CKCGSJNJ2JVN896150A/b21cd79ef56404b65ff8cf06f243fdbcc3b3989336f6bdd4b4a201f04793192e","of":"session:ember:c-192380e096","effort":"high"}},"w":1792544038131.419}
  #|{"step":"tap =选择模型","w":1792544038132.867}
  #|{"step":"tap =选择模型","acted":true,"w":1792544038132.932}
  #|{"in":{"id":27,"ok":null},"w":1792544038147.214}
  #|{"step":"tap Sonnet","w":1792544038149.204}
  #|{"step":"tap Sonnet","acted":true,"w":1792544038171.297}
  #|{"out":{"id":28,"call":"pick.set","params":{"station":"01M5DZ6CKCGSJNJ2JVN896150A/b21cd79ef56404b65ff8cf06f243fdbcc3b3989336f6bdd4b4a201f04793192e","of":"session:ember:c-192380e096","model":"claude-sonnet-5-5"}},"w":1792544038181.255}
  #|{"step":"until 改成","w":1792544038181.992}
  #|{"in":{"id":28,"ok":null},"w":1792544038197.218}
  #|{"in":{"id":24,"delta":[{"path":["accounts"],"append":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":true,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792544031700,"time":{"checkedAt":{"at":1792544031700,"ago":"刚刚","full":"10/21 08:53:51","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]},{"path":["becomes",0],"set":"Sonnet 5.5"},{"path":["becomes",1],"set":"high"},{"path":["becomes",2],"set":"自动 · cc"},{"path":["changed"],"set":true},{"path":["draft","effort"],"set":"high"},{"path":["draft","model"],"set":"claude-sonnet-5-5"},{"path":["maker"],"set":{"id":"anthropic","name":"Anthropic"}},{"path":["modelText"],"set":"Sonnet 5.5"},{"path":["option"],"set":"claude-sonnet-5-5"},{"path":["saveText"],"set":"改成 Sonnet 5.5 · high · 自动分配"}]},"w":1792544038197.359}
  #|{"step":"tap 改成","w":1792544038207.73}
  #|{"step":"tap 改成","acted":true,"w":1792544038207.772}
  #|{"out":{"id":29,"call":"pick.save","params":{"station":"01M5DZ6CKCGSJNJ2JVN896150A/b21cd79ef56404b65ff8cf06f243fdbcc3b3989336f6bdd4b4a201f04793192e","of":"session:ember:c-192380e096"}},"w":1792544038214.234}
  #|{"step":"until 已更改，下一轮起生效","w":1792544038216.108}
  #|{"in":{"id":29,"ok":{"saved":true}},"w":1792544038280.512}
  #|{"in":{"id":24,"delta":[{"path":["changed"],"set":false},{"path":["saveText"],"set":"无变更"},{"path":["value","effort"],"set":"high"},{"path":["value","model"],"set":"claude-sonnet-5-5"},{"path":["valueOption"],"set":{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":true,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792544031700,"time":{"checkedAt":{"at":1792544031700,"ago":"刚刚","full":"10/21 08:53:51","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]},"availability":"here"}},{"path":["was",0],"set":"Sonnet 5.5"},{"path":["was",1],"set":"high"}]},"w":1792544038280.569}
  #|{"in":{"id":15,"delta":[{"path":["agents",0,"session","agentText"],"set":"Sonnet 5.5 · high"},{"path":["agents",0,"session","effort"],"set":"high"},{"path":["agents",0,"session","maker"],"set":{"id":"anthropic","name":"Anthropic"}},{"path":["agents",0,"session","model"],"set":"claude-sonnet-5-5"},{"path":["agents",0,"session","modelName"],"set":"Sonnet 5.5"},{"path":["agents",0,"session","process"],"set":"cold"},{"path":["agents",0,"session","processText"],"set":"已释放"},{"path":["messages"],"key":["seq","outgoing"],"patch":[4,null],"ops":[{"path":["by","maker"],"set":{"id":"anthropic","name":"Anthropic"}},{"path":["by","name"],"set":"Sonnet 5.5 · high"}]},{"path":["messages"],"key":["seq","outgoing"],"patch":[2,null],"ops":[{"path":["by","maker"],"set":{"id":"anthropic","name":"Anthropic"}},{"path":["by","name"],"set":"Sonnet 5.5 · high"}]}]},"w":1792544038280.626}
  #|{"in":{"id":7,"delta":[{"path":["days"],"key":["daysAgo"],"patch":0,"ops":[{"path":["items"],"key":["station","id"],"patch":["01M5DZ6CKCGSJNJ2JVN896150A/b21cd79ef56404b65ff8cf06f243fdbcc3b3989336f6bdd4b4a201f04793192e","ember:c-192380e096"],"ops":[{"path":["agents",0,"agentText"],"set":"Sonnet 5.5 · high"},{"path":["agents",0,"effort"],"set":"high"},{"path":["agents",0,"maker"],"set":{"id":"anthropic","name":"Anthropic"}},{"path":["agents",0,"model"],"set":"claude-sonnet-5-5"},{"path":["agents",0,"process"],"set":"cold"},{"path":["last","by","label"],"set":"Sonnet 5.5"},{"path":["last","by","maker"],"set":{"id":"anthropic","name":"Anthropic"}},{"path":["last","by","model"],"set":"claude-sonnet-5-5"},{"path":["last","by","name"],"set":"Sonnet 5.5"}]}]}]},"w":1792544038280.694}
  #|{"in":{"id":17,"delta":[{"path":[0,"overview","counts","warm"],"set":0},{"path":[0,"overview","disk","freeBytes"],"set":53605814272}]},"w":1792544038280.729}
  #|{"step":"wait 2600","w":1792544038282.964}
  #|{"step":"","w":1792544040898.702}
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
  #|{"textrec":{"ib":["a7ccae3554fe46cf",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["c8ac90bf691295f0",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"ib":["31d8ec32aedeae00",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"s":[15,400,0,"搜索全部内容"],"r":[0,1,14.883268482490273,18,1,1,14.883268482490273,19,2,1,14.883268482490273,20,3,1,14.883268482490273,21,4,1,14.88326848249028,22,5,1,14.88326848249028,23]}}
  #|{"textrec":{"m":[15,400,0],"r":[14.501953125,3.1640625,21,14.501953125,3.1640625,0]}}
  #|{"textrec":{"s":[15,600,0,"今天"],"r":[0,1,14.883268482490273,24,1,1,14.883268482490273,25]}}
  #|{"textrec":{"m":[15,600,0],"r":[14.501953125,3.1640625,21,14.501953125,3.1640625,0]}}
  #|{"textrec":{"s":[12,500,0,"归档"],"r":[0,1,11.918287937743191,26,1,1,11.918287937743191,27]}}
  #|{"textrec":{"m":[12,500,0],"r":[11.6015625,2.53125,17,11.6015625,2.53125,0]}}
  #|{"textrec":{"s":[16,400,0,"端到端测试的对话 post:你好，我是测试用的 agent"],"r":[0,1,15.875486381322958,28,1,1,15.875486381322958,29,2,1,15.875486381322958,28,3,1,15.875486381322958,30,4,1,15.875486381322958,31,5,1,15.875486381322958,32,6,1,15.875486381322958,33,7,1,15.875486381322958,34,8,1,4.1875,-1,9,1,9.453125,35,10,1,9.140625,36,11,1,8.0234375,37,12,1,5.4609375,38,13,1,4.4375,39,14,1,15.875486381322958,40,15,1,15.875486381322958,41,16,1,16.09338521400778,42,17,1,15.875486381322958,43,18,1,15.875486381322958,44,19,1,15.87548638132293,30,20,1,15.875486381322958,31,21,1,15.875486381322958,45,22,1,15.875486381322958,32,23,1,4.1875,-1,24,1,8.515625,46,25,1,9.4375,47,26,1,8.828125,48,27,1,9.0234375,49,28,1,5.5,38]}}
  #|{"textrec":{"m":[16,400,0],"r":[15.46875,3.375,23,15.46875,3.375,0]}}
  #|{"textrec":{"s":[14,400,0,"answered the question that was asked"],"r":[0,1,7.57421875,50,1,1,8.0185546875,51,2,1,7.0751953125,52,3,1,10.4521484375,53,4,1,7.7109375,54,5,1,5.0791015625,55,6,1,7.7451171875,54,7,1,8.44921875,56,8,1,3.787109375,-1,9,1,4.935546875,57,10,1,8.0869140625,58,11,1,7.84765625,54,12,1,3.787109375,-1,13,1,8.380859375,59,14,1,8.0185546875,60,15,1,7.84765625,54,16,1,7.1435546875,52,17,1,4.9013671875,57,18,1,3.30859375,61,19,1,8.12109375,62,20,1,8.0185546875,51,21,1,3.787109375,-1,22,1,4.935546875,57,23,1,8.0869140625,58,24,1,7.57421875,50,25,1,4.935546875,57,26,1,3.787109375,-1,27,1,10.5888671875,53,28,1,7.4716796875,50,29,1,7.177734375,52,30,1,3.787109375,-1,31,1,7.57421875,50,32,1,7.177734375,52,33,1,7.2802734375,63,34,1,7.6767578125,54,35,1,8.44921875,56]}}
  #|{"textrec":{"m":[14,400,0],"r":[13.53515625,2.953125,20,13.53515625,2.953125,0]}}
  #|{"textrec":{"s":[16,400,0,"…"],"r":[0,1,12.5625,64]}}
  #|{"textrec":{"s":[16,400,0,"端到端测试的对话 post:你好，我是测试…"],"r":[0,1,15.875486381322958,28,1,1,15.875486381322958,29,2,1,15.875486381322958,28,3,1,15.875486381322958,30,4,1,15.875486381322958,31,5,1,15.875486381322958,32,6,1,15.875486381322958,33,7,1,15.875486381322958,34,8,1,4.1875,-1,9,1,9.453125,35,10,1,9.140625,36,11,1,8.0234375,37,12,1,5.4609375,38,13,1,4.4375,39,14,1,15.875486381322958,40,15,1,15.875486381322958,41,16,1,16.09338521400778,42,17,1,15.875486381322958,43,18,1,15.875486381322958,44,19,1,15.87548638132293,30,20,1,15.875486381322958,31,21,1,12.5625,64]}}
  #|{"textrec":{"g":18,"r":[51,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":19,"r":[69,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":20,"r":[86,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":21,"r":[104,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":22,"r":[121,0,15,16,0,-13,0]}}
  #|{"textrec":{"g":23,"r":[137,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":24,"r":[154,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":25,"r":[172,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":26,"r":[190,0,13,14,-1,-11,0]}}
  #|{"textrec":{"g":27,"r":[204,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":28,"r":[219,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":29,"r":[237,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":30,"r":[255,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":31,"r":[273,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":32,"r":[292,0,16,17,0,-14,0]}}
  #|{"textrec":{"g":33,"r":[309,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":34,"r":[327,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":35,"r":[346,0,10,14,0,-10,0]}}
  #|{"textrec":{"g":36,"r":[357,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":37,"r":[369,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":38,"r":[380,0,8,14,-1,-12,0]}}
  #|{"textrec":{"g":39,"r":[389,0,5,11,0,-9,0]}}
  #|{"textrec":{"g":40,"r":[395,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":41,"r":[413,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":42,"r":[431,0,6,7,0,-3,0]}}
  #|{"textrec":{"g":43,"r":[438,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":44,"r":[456,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":64,"r":[474,0,13,5,0,-3,0]}}
  #|{"textrec":{"g":50,"r":[488,0,9,11,-1,-9,0]}}
  #|{"textrec":{"g":51,"r":[498,0,9,10,0,-9,0]}}
  #|{"textrec":{"g":52,"r":[508,0,9,11,-1,-9,0]}}
  #|{"textrec":{"g":53,"r":[518,0,13,10,-1,-9,0]}}
  #|{"textrec":{"g":54,"r":[532,0,10,11,-1,-9,0]}}
  #|{"textrec":{"g":55,"r":[543,0,6,10,0,-9,0]}}
  #|{"textrec":{"g":56,"r":[550,0,10,14,-1,-12,0]}}
  #|{"textrec":{"g":57,"r":[561,0,7,13,-1,-11,0]}}
  #|{"textrec":{"g":58,"r":[569,0,9,13,0,-12,0]}}
  #|{"textrec":{"g":59,"r":[579,0,10,13,-1,-9,0]}}
  #|{"textrec":{"g":60,"r":[590,0,9,11,0,-9,0]}}
  #|{"textrec":{"g":61,"r":[600,0,5,13,-1,-12,0]}}
  #|{"textrec":{"g":62,"r":[606,0,10,11,-1,-9,0]}}
  #|{"textrec":{"g":63,"r":[617,0,9,13,0,-12,0]}}
  #|{"textrec":{"ib":["33d1dfbf90932d3b",1241,64],"r":[17,17,17,17]}}
  #|{"textrec":{"ib":["fa5cd9c3d11340b0",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["182b7158e0c0cae1",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["d61ec6305f7d8c8b",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["8bf9607b651cec61",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"m":[16,600,0],"r":[15.46875,3.375,23,15.46875,3.375,0]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 post:你好，我是测试用的 agent"],"r":[0,1,15.875486381322958,65,1,1,15.875486381322958,66,2,1,15.875486381322958,65,3,1,15.875486381322958,67,4,1,15.875486381322958,68,5,1,15.875486381322958,69,6,1,15.875486381322958,70,7,1,15.875486381322958,71,8,1,3.95001220703125,-1,9,1,9.824199676513672,72,10,1,9.432537078857422,73,11,1,8.471200942993164,74,12,1,5.973020553588867,75,13,1,4.952056884765625,76,14,1,15.875486381322958,77,15,1,15.875486381322958,78,16,1,16.09338521400778,79,17,1,15.875486381322958,80,18,1,15.875486381322958,81,19,1,15.87548638132293,67,20,1,15.875486381322958,68,21,1,15.875486381322958,82,22,1,15.875486381322958,69,23,1,3.95001220703125,-1,24,1,8.899068832397461,83,25,1,9.801153182983398,84,26,1,9.127458572387695,85,27,1,9.466253280639648,86,28,1,5.999713897705078,75]}}
  #|{"textrec":{"s":[8,600,0,"N"],"r":[0,1,6.271738052368164,87]}}
  #|{"textrec":{"m":[8,600,0],"r":[7.734375,1.6875,11,7.734375,1.6875,0]}}
  #|{"textrec":{"s":[15,650,0,"默认模型"],"r":[0,1,14.883268482490273,88,1,1,14.883268482490273,89,2,1,14.883268482490273,90,3,1,14.883268482490273,91]}}
  #|{"textrec":{"m":[15,650,0],"r":[14.501953125,3.1640625,21,14.501953125,3.1640625,0]}}
  #|{"textrec":{"s":[10,400,0,"刚刚"],"r":[0,1,9.941634241245136,92,1,1,9.941634241245136,92]}}
  #|{"textrec":{"m":[10,400,0],"r":[9.66796875,2.109375,14,9.66796875,2.109375,0]}}
  #|{"textrec":{"s":[15,400,0,"文档目录看过了 083209"],"r":[0,1,14.883268482490273,93,1,1,14.883268482490273,94,2,1,14.883268482490273,95,3,1,14.883268482490273,96,4,1,14.88326848249028,97,5,1,14.88326848249028,98,6,1,14.88326848249028,99,7,1,3.984375,-1,8,1,9.2138671875,100,9,1,9.345703125,101,10,1,9.169921875,102,11,1,8.818359375,103,12,1,9.2138671875,100,13,1,9.31640625,104]}}
  #|{"textrec":{"s":[16,400,0,"看看文档 083209 steps:文档目录看过了 083209"],"r":[0,1,15.875486381322958,105,1,1,15.875486381322958,105,2,1,15.875486381322958,106,3,1,15.875486381322958,107,4,1,4.1875,-1,5,1,9.765625,108,6,1,9.90625,109,7,1,9.71875,110,8,1,9.34375,111,9,1,9.765625,108,10,1,9.875,112,11,1,4.1875,-1,12,1,8.0234375,37,13,1,5.40234375,38,14,1,8.76953125,48,15,1,9.453125,35,16,1,8.0625,37,17,1,4.4375,39,18,1,15.875486381322958,106,19,1,15.875486381322958,107,20,1,15.875486381322958,113,21,1,15.875486381322958,114,22,1,15.875486381322958,105,23,1,15.875486381322958,115,24,1,15.875486381322958,116,25,1,4.1875,-1,26,1,9.765625,108,27,1,9.90625,109,28,1,9.71875,110,29,1,9.34375,111,30,1,9.765625,108,31,1,9.875,112]}}
  #|{"textrec":{"s":[15,400,0,"你好，我是测试用的 agent"],"r":[0,1,14.883268482490273,117,1,1,14.883268482490273,118,2,1,15.087548638132297,119,3,1,14.883268482490273,120,4,1,14.883268482490266,121,5,1,14.88326848249028,122,6,1,14.88326848249028,123,7,1,14.88326848249028,124,8,1,14.88326848249028,125,9,1,3.984375,-1,10,1,8.0419921875,126,11,1,8.90625,127,12,1,8.3349609375,128,13,1,8.51806640625,129,14,1,5.21484375,130]}}
  #|{"textrec":{"s":[16,600,0,"…"],"r":[0,1,14.076484680175781,131]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 post:…"],"r":[0,1,15.875486381322958,65,1,1,15.875486381322958,66,2,1,15.875486381322958,65,3,1,15.875486381322958,67,4,1,15.875486381322958,68,5,1,15.875486381322958,69,6,1,15.875486381322958,70,7,1,15.875486381322958,71,8,1,3.95001220703125,-1,9,1,9.824199676513672,72,10,1,9.432537078857422,73,11,1,8.471200942993164,74,12,1,5.973020553588867,75,13,1,4.952056884765625,76,14,1,14.076484680175781,131]}}
  #|{"textrec":{"ib":["504a4df6beac534a",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"s":[12,400,0,"studio"],"r":[0,1,6.251953125,132,1,1,4.330078125,133,2,1,7.001953125,134,3,1,7.37109375,135,4,1,2.96484375,136,5,1,7.08984375,137]}}
  #|{"textrec":{"m":[12,400,0],"r":[11.6015625,2.53125,17,11.6015625,2.53125,0]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 p…"],"r":[0,1,15.875486381322958,65,1,1,15.875486381322958,66,2,1,15.875486381322958,65,3,1,15.875486381322958,67,4,1,15.875486381322958,68,5,1,15.875486381322958,69,6,1,15.875486381322958,70,7,1,15.875486381322958,71,8,1,3.95001220703125,-1,9,1,9.721336364746094,72,10,1,13.973621368408203,138]}}
  #|{"textrec":{"g":117,"r":[627,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":118,"r":[644,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":119,"r":[661,0,5,7,0,-3,0]}}
  #|{"textrec":{"g":120,"r":[667,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":121,"r":[685,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":122,"r":[702,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":123,"r":[719,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":124,"r":[737,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":125,"r":[753,0,15,17,0,-14,0]}}
  #|{"textrec":{"g":126,"r":[769,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":127,"r":[780,0,10,14,-1,-10,0]}}
  #|{"textrec":{"g":128,"r":[791,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":129,"r":[802,0,9,11,0,-10,0]}}
  #|{"textrec":{"g":130,"r":[812,0,7,13,-1,-11,0]}}
  #|{"textrec":{"g":93,"r":[820,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":94,"r":[838,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":95,"r":[855,0,13,16,1,-13,0]}}
  #|{"textrec":{"g":96,"r":[869,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":97,"r":[886,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":98,"r":[903,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":99,"r":[921,0,14,16,0,-13,0]}}
  #|{"textrec":{"g":100,"r":[936,0,11,14,-1,-12,0]}}
  #|{"textrec":{"g":101,"r":[948,0,11,14,-1,-12,0]}}
  #|{"textrec":{"g":102,"r":[960,0,10,14,0,-12,0]}}
  #|{"textrec":{"g":103,"r":[971,0,10,13,0,-12,0]}}
  #|{"textrec":{"g":104,"r":[982,0,11,14,-1,-12,0]}}
  #|{"textrec":{"ib":["11ba9484460f477d",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["a1e7be43eb966606",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"ib":["c7a6d30e254a5910",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"g":45,"r":[994,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":46,"r":[1011,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":47,"r":[1022,0,11,14,-1,-10,0]}}
  #|{"textrec":{"g":48,"r":[1034,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":49,"r":[1046,0,10,11,0,-10,0]}}
  #|{"textrec":{"g":88,"r":[1057,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":89,"r":[1075,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":90,"r":[1093,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":91,"r":[1111,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":65,"r":[1128,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":66,"r":[1146,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":67,"r":[1164,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":68,"r":[1182,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":69,"r":[1201,0,16,17,0,-14,0]}}
  #|{"textrec":{"g":70,"r":[1218,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":71,"r":[1236,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":72,"r":[1255,0,11,14,0,-10,0]}}
  #|{"textrec":{"g":138,"r":[1267,0,14,6,-0.10286331176757812,-4,0]}}
  #|{"textrec":{"s":[16,400,0,"发消息"],"r":[0,1,15.875486381322958,139,1,1,15.875486381322958,140,2,1,15.875486381322958,141]}}
  #|{"textrec":{"g":139,"r":[1282,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":140,"r":[1300,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":141,"r":[1318,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":92,"r":[1336,0,11,11,-1,-9,0]}}
  #|{"textrec":{"g":105,"r":[1348,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":106,"r":[1366,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":107,"r":[1384,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":108,"r":[1402,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":109,"r":[1414,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":110,"r":[1426,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":111,"r":[1438,0,10,14,0,-13,0]}}
  #|{"textrec":{"g":112,"r":[1449,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":113,"r":[1461,0,14,16,1,-13,0]}}
  #|{"textrec":{"g":114,"r":[1476,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":115,"r":[1494,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":116,"r":[1512,0,15,16,0,-13,0]}}
  #|{"textrec":{"g":87,"r":[1528,0,8,8,-1,-7,0]}}
  #|{"textrec":{"g":132,"r":[1537,0,8,10,-1,-8,0]}}
  #|{"textrec":{"g":133,"r":[1546,0,6,11,-1,-9,0]}}
  #|{"textrec":{"g":134,"r":[1553,0,9,10,-1,-8,0]}}
  #|{"textrec":{"g":135,"r":[1563,0,9,12,-1,-10,0]}}
  #|{"textrec":{"g":136,"r":[1573,0,5,11,-1,-10,0]}}
  #|{"textrec":{"g":137,"r":[1579,0,9,10,-1,-8,0]}}
  #|{"textrec":{"ib":["5011346a34665c45",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["ddfdc2820df8a676",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"ib":["b277602c41d156e7",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"s":[18,700,0,"端到端测试的对话 post:你好，我是测试用的 agent"],"r":[0,1,17.842412451361866,142,1,1,17.842412451361866,143,2,1,17.842412451361866,142,3,1,17.842412451361866,144,4,1,17.842412451361866,145,5,1,17.842412451361866,146,6,1,17.842412451361866,147,7,1,17.842412451361866,148,8,1,4.152015030384064,-1,9,1,11.16209328174591,149,10,1,10.675500869750977,150,11,1,9.692523032426834,151,12,1,6.919372379779816,152,13,1,5.73083621263504,153,14,1,17.842412451361866,154,15,1,17.842412451361866,155,16,1,18.08754863813229,156,17,1,17.842412451361866,157,18,1,17.842412451361838,158,19,1,17.842412451361838,144,20,1,17.842412451361838,145,21,1,17.842412451361838,159,22,1,17.842412451361838,146,23,1,4.152015030384064,-1,24,1,10.138570368289948,160,25,1,11.132530510425568,161,26,1,10.337921261787415,162,27,1,10.808134496212006,163,28,1,6.940345913171768,152]}}
  #|{"textrec":{"m":[18,700,0],"r":[17.40234375,3.796875,26,17.40234375,3.796875,0]}}
  #|{"textrec":{"s":[13,400,0,"你 刚刚发起 · 最新 刚刚"],"r":[0,1,12.898832684824903,4,1,1,3.580078125,-1,2,1,12.898832684824903,164,3,1,12.898832684824903,164,4,1,12.898832684824903,165,5,1,12.898832684824896,166,6,1,3.580078125,-1,7,1,6.228545204222115,167,8,1,3.580078125,-1,9,1,12.898832684824896,168,10,1,12.898832684824896,169,11,1,3.580078125,-1,12,1,12.898832684824896,164,13,1,12.898832684824896,164]}}
  #|{"textrec":{"s":[15,600,0,"默认模型"],"r":[0,1,14.883268482490273,170,1,1,14.883268482490273,171,2,1,14.883268482490273,172,3,1,14.883268482490273,173]}}
  #|{"textrec":{"s":[12,400,0,"已完成：answered the question that was asked · 刚刚"],"r":[0,1,11.918287937743191,174,1,1,11.918287937743191,175,2,1,11.918287937743195,176,3,1,12.081712062256813,177,4,1,6.62109375,178,5,1,7.001953125,179,6,1,6.193359375,132,7,1,9.087890625,180,8,1,6.73828125,181,9,1,4.482421875,182,10,1,6.767578125,181,11,1,7.37109375,135,12,1,3.375,-1,13,1,4.359375,133,14,1,7.060546875,183,15,1,6.85546875,181,16,1,3.375,-1,17,1,7.312500000000014,184,18,1,7.001953125,134,19,1,6.85546875,181,20,1,6.251953125,132,21,1,4.330078125,133,22,1,2.96484375,136,23,1,7.08984375,137,24,1,7.001953125,179,25,1,3.375,-1,26,1,4.359375,133,27,1,7.060546875,183,28,1,6.62109375,178,29,1,4.359375,133,30,1,3.375,-1,31,1,9.205078125,180,32,1,6.533203125,178,33,1,6.28125,132,34,1,3.375,-1,35,1,6.62109375,178,36,1,6.28125,132,37,1,6.369140625,185,38,1,6.708984375,181,39,1,7.37109375,135,40,1,3.375,-1,41,1,5.754933455713626,186,42,1,3.375,-1,43,1,11.918287937743173,187,44,1,11.918287937743173,187]}}
  #|{"textrec":{"s":[14,400,0,"固定到列表顶部"],"r":[0,1,13.891050583657588,188,1,1,13.891050583657588,189,2,1,13.891050583657588,190,3,1,13.891050583657588,191,4,1,13.891050583657588,192,5,1,13.891050583657588,193,6,1,13.891050583657588,194]}}
  #|{"textrec":{"s":[14,400,0,"复制会话链接"],"r":[0,1,13.891050583657588,195,1,1,13.891050583657588,196,2,1,13.891050583657588,197,3,1,13.891050583657588,198,4,1,13.891050583657588,199,5,1,13.891050583657588,200]}}
  #|{"textrec":{"s":[14,400,0,"归档对话"],"r":[0,1,13.891050583657588,201,1,1,13.891050583657588,202,2,1,13.891050583657588,203,3,1,13.891050583657588,198]}}
  #|{"textrec":{"s":[14,400,0,"公开分享"],"r":[0,1,13.891050583657588,204,1,1,13.891050583657588,205,2,1,13.891050583657588,206,3,1,13.891050583657588,207]}}
  #|{"textrec":{"s":[12,400,0,"…"],"r":[0,1,9.65625,208]}}
  #|{"textrec":{"s":[12,400,0,"已完成：answered the question that was ask…"],"r":[0,1,11.918287937743191,174,1,1,11.918287937743191,175,2,1,11.918287937743195,176,3,1,12.081712062256813,177,4,1,6.62109375,178,5,1,7.001953125,179,6,1,6.193359375,132,7,1,9.087890625,180,8,1,6.73828125,181,9,1,4.482421875,182,10,1,6.767578125,181,11,1,7.37109375,135,12,1,3.375,-1,13,1,4.359375,133,14,1,7.060546875,183,15,1,6.85546875,181,16,1,3.375,-1,17,1,7.312500000000014,184,18,1,7.001953125,134,19,1,6.85546875,181,20,1,6.251953125,132,21,1,4.330078125,133,22,1,2.96484375,136,23,1,7.08984375,137,24,1,7.001953125,179,25,1,3.375,-1,26,1,4.359375,133,27,1,7.060546875,183,28,1,6.62109375,178,29,1,4.359375,133,30,1,3.375,-1,31,1,9.205078125,180,32,1,6.533203125,178,33,1,6.28125,132,34,1,3.375,-1,35,1,6.62109375,178,36,1,6.28125,132,37,1,6.515625,185,38,1,9.65625,208]}}
  #|{"textrec":{"g":142,"r":[1589,0,19,19,-1,-16,0]}}
  #|{"textrec":{"g":143,"r":[1609,0,19,19,-1,-16,0]}}
  #|{"textrec":{"g":144,"r":[1629,0,19,19,-1,-16,0]}}
  #|{"textrec":{"g":145,"r":[1649,0,20,19,-1,-16,0]}}
  #|{"textrec":{"g":146,"r":[1670,0,18,19,0,-16,0]}}
  #|{"textrec":{"g":147,"r":[1689,0,19,19,-1,-16,0]}}
  #|{"textrec":{"g":148,"r":[1709,0,20,19,-1,-16,0]}}
  #|{"textrec":{"g":149,"r":[1730,0,12,16,0,-11,0]}}
  #|{"textrec":{"g":150,"r":[1743,0,13,13,-1,-11,0]}}
  #|{"textrec":{"g":151,"r":[1757,0,12,13,-1,-11,0]}}
  #|{"textrec":{"g":152,"r":[1770,0,9,15,-1,-13,0]}}
  #|{"textrec":{"g":153,"r":[1780,0,6,13,0,-11,0]}}
  #|{"textrec":{"g":154,"r":[1787,0,19,19,-1,-16,0]}}
  #|{"textrec":{"g":155,"r":[1807,0,19,19,-1,-16,0]}}
  #|{"textrec":{"g":156,"r":[1827,0,7,9,0,-4,0]}}
  #|{"textrec":{"g":157,"r":[1835,0,19,19,-1,-16,0]}}
  #|{"textrec":{"g":158,"r":[1855,0,19,18,-1,-15,0]}}
  #|{"textrec":{"g":159,"r":[1875,0,18,18,-1,-15,0]}}
  #|{"textrec":{"g":160,"r":[1894,0,12,13,-1,-11,0]}}
  #|{"textrec":{"g":161,"r":[1907,0,13,16,-1,-11,0]}}
  #|{"textrec":{"g":162,"r":[1921,0,12,13,-1,-11,0]}}
  #|{"textrec":{"g":163,"r":[1934,0,12,12,0,-11,0]}}
  #|{"textrec":{"g":4,"r":[1947,0,14,15,-1,-12,0]}}
  #|{"textrec":{"g":164,"r":[1962,0,14,15,-1,-12,0]}}
  #|{"textrec":{"g":165,"r":[1977,0,14,15,-1,-12,0]}}
  #|{"textrec":{"g":166,"r":[1992,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":167,"r":[2008,0,4,5,1,-7,0]}}
  #|{"textrec":{"g":168,"r":[2013,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":169,"r":[2028,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":170,"r":[0,20,17,16,-1,-13,0]}}
  #|{"textrec":{"g":171,"r":[18,20,17,16,-1,-13,0]}}
  #|{"textrec":{"g":172,"r":[36,20,17,16,-1,-13,0]}}
  #|{"textrec":{"g":173,"r":[54,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":174,"r":[71,20,13,12,0,-10,0]}}
  #|{"textrec":{"g":175,"r":[85,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":176,"r":[100,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":177,"r":[115,20,4,9,1,-9,0]}}
  #|{"textrec":{"g":178,"r":[120,20,8,10,-1,-8,0]}}
  #|{"textrec":{"g":179,"r":[129,20,9,9,-1,-8,0]}}
  #|{"textrec":{"g":180,"r":[139,20,11,9,-1,-8,0]}}
  #|{"textrec":{"g":181,"r":[151,20,9,10,-1,-8,0]}}
  #|{"textrec":{"g":182,"r":[161,20,7,9,-1,-8,0]}}
  #|{"textrec":{"g":183,"r":[169,20,8,11,0,-10,0]}}
  #|{"textrec":{"g":184,"r":[178,20,9,12,-1,-8,0]}}
  #|{"textrec":{"g":185,"r":[188,20,8,11,0,-10,0]}}
  #|{"textrec":{"g":208,"r":[197,20,10,5,0,-3,0]}}
  #|{"textrec":{"g":188,"r":[208,20,14,15,0,-12,0]}}
  #|{"textrec":{"g":189,"r":[223,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":190,"r":[239,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":191,"r":[255,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":192,"r":[271,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":193,"r":[287,20,16,15,-1,-12,0]}}
  #|{"textrec":{"g":194,"r":[304,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":195,"r":[320,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":196,"r":[336,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":197,"r":[352,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":198,"r":[369,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":199,"r":[386,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":200,"r":[403,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":201,"r":[419,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":202,"r":[435,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":203,"r":[451,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":204,"r":[467,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":205,"r":[484,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":206,"r":[500,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":207,"r":[517,20,16,16,-1,-13,0]}}
  #|{"textrec":{"ib":["92022e9e11aef691",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"ib":["f1276e6323a9ca06",1853,64],"r":[21,21,21,21]}}
  #|{"textrec":{"ib":["b3685975cd23abc3",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["030aece180ce0f3c",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"ib":["b9bedad57f2a5f13",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"ib":["97cc1349f5996766",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"ib":["82d8240109550b08",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"s":[17,700,0,"默认模型"],"r":[0,1,16.851167315175097,209,1,1,16.851167315175097,210,2,1,16.851167315175097,211,3,1,16.851167315175097,212]}}
  #|{"textrec":{"m":[17,700,0],"r":[16.435546875,3.5859375,24,16.435546875,3.5859375,0]}}
  #|{"textrec":{"s":[13,400,0,"已完成：answered the question that was asked"],"r":[0,1,12.898832684824903,213,1,1,12.898832684824903,214,2,1,12.898832684824903,215,3,1,13.075875486381321,216,4,1,7.0966796875,12,5,1,7.509277343749993,217,6,1,6.63330078125,10,7,1,9.76904296875,6,8,1,7.2236328125,14,9,1,4.77978515625,8,10,1,7.25537109375,14,11,1,7.9091796875,218,12,1,3.580078125,-1,13,1,4.646484375,219,14,1,7.57275390625,220,15,1,7.3505859375,14,16,1,3.580078125,-1,17,1,7.845703125,221,18,1,7.50927734375,222,19,1,7.3505859375,14,20,1,6.69677734375,10,21,1,4.61474609375,219,22,1,3.1357421875,223,23,1,7.6044921875,7,24,1,7.50927734375,217,25,1,3.580078125,-1,26,1,4.646484375,219,27,1,7.57275390625,220,28,1,7.0966796875,12,29,1,4.646484375,219,30,1,3.580078125,-1,31,1,9.89599609375,6,32,1,7.00146484375,12,33,1,6.728515625,10,34,1,3.580078125,-1,35,1,7.0966796875,12,36,1,6.728515625000028,10,37,1,6.82373046875,9,38,1,7.19189453125,14,39,1,7.9091796875,218]}}
  #|{"textrec":{"s":[13,400,0," · 刚刚"],"r":[0,1,3.580078125,-1,1,1,6.228545204222119,167,2,1,3.580078125,-1,3,1,12.898832684824903,164,4,1,12.8988326848249,164]}}
  #|{"textrec":{"s":[14,400,0,"Station"],"r":[0,1,8.7705078125,224,1,1,4.935546875,57,2,1,7.57421875,50,3,1,4.935546875,57,4,1,3.30859375,61,5,1,8.12109375,62,6,1,8.0185546875,51]}}
  #|{"textrec":{"s":[14,400,0,"studio"],"r":[0,1,7.1435546875,52,1,1,4.9013671875,57,2,1,8.0185546875,60,3,1,8.44921875,56,4,1,3.30859375,61,5,1,8.12109375,62]}}
  #|{"textrec":{"s":[14,400,0,"账号"],"r":[0,1,13.891050583657588,225,1,1,13.891050583657588,226]}}
  #|{"textrec":{"s":[14,400,0,"cc · 自动"],"r":[0,1,7.68359375,227,1,1,7.68359375,227,2,1,3.787109375,-1,3,1,6.707664066085361,228,4,1,3.787109375,-1,5,1,13.891050583657584,229,6,1,13.891050583657588,230]}}
  #|{"textrec":{"s":[14,400,0,"历史"],"r":[0,1,13.891050583657588,231,1,1,13.891050583657588,232]}}
  #|{"textrec":{"s":[14,400,0,"尚未运行"],"r":[0,1,13.891050583657588,233,1,1,13.891050583657588,234,2,1,13.891050583657588,235,3,1,13.891050583657588,236]}}
  #|{"textrec":{"g":209,"r":[534,20,19,18,-1,-15,0]}}
  #|{"textrec":{"g":210,"r":[554,20,19,18,-1,-15,0]}}
  #|{"textrec":{"g":211,"r":[574,20,18,18,-1,-15,0]}}
  #|{"textrec":{"g":212,"r":[593,20,18,18,-1,-15,0]}}
  #|{"textrec":{"g":213,"r":[612,20,13,13,0,-11,0]}}
  #|{"textrec":{"g":214,"r":[626,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":215,"r":[642,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":216,"r":[658,20,4,9,1,-9,0]}}
  #|{"textrec":{"g":12,"r":[663,20,9,10,-1,-8,0]}}
  #|{"textrec":{"g":217,"r":[673,20,8,9,0,-8,0]}}
  #|{"textrec":{"g":10,"r":[682,20,9,10,-1,-8,0]}}
  #|{"textrec":{"g":6,"r":[692,20,12,9,-1,-8,0]}}
  #|{"textrec":{"g":14,"r":[705,20,9,10,-1,-8,0]}}
  #|{"textrec":{"g":8,"r":[715,20,6,9,0,-8,0]}}
  #|{"textrec":{"g":218,"r":[722,20,9,13,-1,-11,0]}}
  #|{"textrec":{"g":219,"r":[732,20,7,12,-1,-10,0]}}
  #|{"textrec":{"g":220,"r":[740,20,8,12,0,-11,0]}}
  #|{"textrec":{"g":221,"r":[749,20,9,12,-1,-8,0]}}
  #|{"textrec":{"g":222,"r":[759,20,9,10,-1,-8,0]}}
  #|{"textrec":{"g":223,"r":[769,20,5,12,-1,-11,0]}}
  #|{"textrec":{"g":7,"r":[775,20,9,10,-1,-8,0]}}
  #|{"textrec":{"g":9,"r":[785,20,8,12,0,-11,0]}}
  #|{"textrec":{"g":224,"r":[794,20,11,14,-1,-12,0]}}
  #|{"textrec":{"g":225,"r":[806,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":226,"r":[823,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":227,"r":[839,20,10,11,-1,-9,0]}}
  #|{"textrec":{"g":228,"r":[850,20,5,4,1,-7,0]}}
  #|{"textrec":{"g":229,"r":[856,20,12,16,1,-13,0]}}
  #|{"textrec":{"g":230,"r":[869,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":231,"r":[885,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":232,"r":[901,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":233,"r":[917,20,14,16,0,-13,0]}}
  #|{"textrec":{"g":234,"r":[932,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":235,"r":[948,20,16,15,-1,-12,0]}}
  #|{"textrec":{"g":236,"r":[965,20,15,16,-1,-13,0]}}
  #|{"textrec":{"ib":["0e6dfc8705c682a0",2207,64],"r":[23,23,23,23]}}
  #|{"textrec":{"s":[13,400,0,"列出 docs 目录"],"r":[0,1,12.898832684824903,237,1,1,12.898832684824903,238,2,1,3.580078125,-1,3,1,7.9091796875,218,4,1,7.6044921875,7,5,1,7.1982421875,13,6,1,6.728515625,10,7,1,3.580078125,-1,8,1,12.89883268482491,239,9,1,12.898832684824896,240]}}
  #|{"textrec":{"s":[13,400,0,"编辑 notes.md"],"r":[0,1,12.898832684824903,241,1,1,12.898832684824903,242,2,1,3.580078125,-1,3,1,7.50927734375,217,4,1,7.6044921875,7,5,1,4.598876953125,219,6,1,7.302978515625,14,7,1,6.728515625,10,8,1,3.783203125,243,9,1,11.2353515625,244,10,1,7.9091796875,218]}}
  #|{"textrec":{"s":[13,400,0,"看过了，改好了。"],"r":[0,1,12.898832684824903,245,1,1,12.898832684824903,246,2,1,12.898832684824903,247,3,1,13.075875486381321,248,4,1,12.898832684824903,249,5,1,12.89883268482491,250,6,1,12.898832684824896,247,7,1,6.575875486381321,251]}}
  #|{"textrec":{"s":[14,400,0,"2 轮"],"r":[0,1,8.298828125,252,1,1,3.787109375,-1,2,1,13.891050583657588,253]}}
  #|{"textrec":{"s":[16,600,0,"执行历史"],"r":[0,1,15.875486381322958,254,1,1,15.875486381322958,255,2,1,15.875486381322958,256,3,1,15.875486381322958,257]}}
  #|{"textrec":{"s":[13,400,0,"步骤"],"r":[0,1,12.898832684824903,258,1,1,12.898832684824903,259]}}
  #|{"textrec":{"s":[13,400,0,"详情"],"r":[0,1,12.898832684824903,260,1,1,12.898832684824903,261]}}
  #|{"textrec":{"s":[16,700,0,"默认模型"],"r":[0,1,15.875486381322958,262,1,1,15.875486381322958,263,2,1,15.875486381322958,264,3,1,15.875486381322958,265]}}
  #|{"textrec":{"m":[16,700,0],"r":[15.46875,3.375,23,15.46875,3.375,0]}}
  #|{"textrec":{"s":[17,400,0,"返回"],"r":[0,1,16.851167315175097,266,1,1,16.851167315175097,267]}}
  #|{"textrec":{"m":[17,400,0],"r":[16.435546875,3.5859375,24,16.435546875,3.5859375,0]}}
  #|{"textrec":{"g":237,"r":[981,20,14,15,-1,-12,0]}}
  #|{"textrec":{"g":238,"r":[996,20,13,15,0,-12,0]}}
  #|{"textrec":{"g":13,"r":[1010,20,9,10,-1,-8,0]}}
  #|{"textrec":{"g":239,"r":[1020,20,11,14,1,-11,0]}}
  #|{"textrec":{"g":240,"r":[1032,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":241,"r":[1047,20,14,15,-1,-12,0]}}
  #|{"textrec":{"g":242,"r":[1062,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":243,"r":[1078,20,4,5,0,-3,0]}}
  #|{"textrec":{"g":244,"r":[1083,20,12,9,0,-8,0]}}
  #|{"textrec":{"g":245,"r":[1096,20,14,15,-1,-12,0]}}
  #|{"textrec":{"g":246,"r":[1111,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":247,"r":[1127,20,13,14,0,-11,0]}}
  #|{"textrec":{"g":248,"r":[1141,20,5,7,0,-3,0]}}
  #|{"textrec":{"g":249,"r":[1147,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":250,"r":[1163,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":251,"r":[1179,20,6,6,0,-3,0]}}
  #|{"textrec":{"g":252,"r":[1186,20,9,13,0,-12,0]}}
  #|{"textrec":{"g":253,"r":[1196,20,16,16,-1,-13,0]}}
  #|{"textrec":{"s":[14,400,0,"看过了，改好了。"],"r":[0,1,13.891050583657588,268,1,1,13.891050583657588,269,2,1,13.891050583657588,270,3,1,14.081712062256813,271,4,1,13.891050583657588,272,5,1,13.891050583657588,273,6,1,13.891050583657588,270,7,1,7.081712062256813,274]}}
  #|{"textrec":{"s":[14,400,0,"编辑 notes.md · 共 2 项"],"r":[0,1,13.891050583657588,275,1,1,13.891050583657588,276,2,1,3.787109375,-1,3,1,8.0185546875,51,4,1,8.12109375,62,5,1,4.88427734375,57,6,1,7.79638671875,54,7,1,7.177734375,52,8,1,4.005859375,277,9,1,12.03125,278,10,1,8.44921875,56,11,1,3.787109375,-1,12,1,6.707664066085357,228,13,1,3.787109375,-1,14,1,13.891050583657588,279,15,1,3.787109375,-1,16,1,8.298828125000014,252,17,1,3.787109375,-1,18,1,13.891050583657602,280]}}
  #|{"textrec":{"s":[13,400,0,"收到来自 "],"r":[0,1,12.898832684824903,281,1,1,12.898832684824903,282,2,1,12.898832684824903,283,3,1,12.898832684824903,284,4,1,3.580078125,-1]}}
  #|{"textrec":{"s":[13,600,0,"Name of alice"],"r":[0,1,9.785324335098267,285,1,1,7.408227801322937,286,2,1,11.745888471603394,287,3,1,7.593794465065002,288,4,1,3.3871192932128906,-1,5,1,7.841670751571655,289,6,1,5.007329106330872,290,7,1,3.3871192932128906,-1,8,1,7.408227801322937,286,9,1,3.5576319694519043,291,10,1,3.4653801918029785,292,11,1,7.427380800247192,293,12,1,7.593794465065002,288]}}
  #|{"textrec":{"m":[13,600,0],"r":[12.568359375,2.7421875,18,12.568359375,2.7421875,0]}}
  #|{"textrec":{"s":[13,400,0," 的消息"],"r":[0,1,3.580078125,-1,1,1,12.898832684824903,5,2,1,12.898832684824903,294,3,1,12.898832684824903,295]}}
  #|{"textrec":{"s":[13,400,0," · "],"r":[0,1,3.580078125,-1,1,1,6.228545204222119,167,2,1,3.580078125,-1]}}
  #|{"textrec":{"s":[13,600,0,"端到端测试的对话 post:你好，我是测试用的 agent"],"r":[0,1,12.898832684824903,296,1,1,12.898832684824903,297,2,1,12.898832684824903,296,3,1,12.898832684824903,298,4,1,12.898832684824896,299,5,1,12.898832684824896,300,6,1,12.898832684824896,301,7,1,12.898832684824896,302,8,1,3.3871192932128906,-1,9,1,8.159896612167358,303,10,1,7.841670751571655,289,11,1,7.060585141181946,304,12,1,5.030813574790955,305,13,1,4.20128059387207,306,14,1,12.898832684824896,307,15,1,12.898832684824896,308,16,1,13.075875486381335,309,17,1,12.898832684824896,310,18,1,12.898832684824896,311,19,1,12.898832684824896,298,20,1,12.898832684824896,299,21,1,12.898832684824896,312,22,1,12.898832684824896,300,23,1,3.387119293212919,-1,24,1,7.408227801322937,286,25,1,8.141171336174011,313,26,1,7.593794465065002,288,27,1,7.869065165519714,314,28,1,5.052501916885376,305]}}
  #|{"textrec":{"s":[14,400,0,"看看文档 083209 steps:文档目录看过了 083209"],"r":[0,1,13.891050583657588,268,1,1,13.891050583657588,268,2,1,13.891050583657588,315,3,1,13.891050583657588,202,4,1,3.787109375,-1,5,1,8.66796875,316,6,1,8.791015625,317,7,1,8.626953125,318,8,1,8.298828125,252,9,1,8.66796875,316,10,1,8.763671875,319,11,1,3.787109375,-1,12,1,7.1435546875,52,13,1,4.85009765625,57,14,1,7.79638671875,54,15,1,8.39453125,320,16,1,7.177734375,52,17,1,4.005859375,321,18,1,13.891050583657602,315,19,1,13.891050583657602,202,20,1,13.891050583657602,322,21,1,13.891050583657602,323,22,1,13.891050583657602,268,23,1,13.891050583657602,269,24,1,13.891050583657602,270,25,1,3.787109375,-1,26,1,8.66796875,316,27,1,8.791015625,317,28,1,8.626953125,318,29,1,8.298828125,252,30,1,8.66796875,316,31,1,8.763671875,319]}}
  #|{"textrec":{"s":[12,400,0,"已到会话开头"],"r":[0,1,11.918287937743191,174,1,1,11.918287937743191,324,2,1,11.918287937743195,325,3,1,11.918287937743187,326,4,1,11.918287937743187,327,5,1,11.918287937743187,328]}}
  #|{"textrec":{"g":266,"r":[1213,20,18,18,-1,-15,0]}}
  #|{"textrec":{"g":267,"r":[1232,20,16,17,0,-14,0]}}
  #|{"textrec":{"g":324,"r":[1249,20,13,14,-1,-11,0]}}
  #|{"textrec":{"g":325,"r":[1263,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":326,"r":[1278,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":327,"r":[1293,20,14,13,-1,-10,0]}}
  #|{"textrec":{"g":328,"r":[1308,20,13,14,-1,-11,0]}}
  #|{"textrec":{"g":268,"r":[1322,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":315,"r":[1338,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":316,"r":[1355,20,10,14,-1,-12,0]}}
  #|{"textrec":{"g":317,"r":[1366,20,11,14,-1,-12,0]}}
  #|{"textrec":{"g":318,"r":[1378,20,10,14,-1,-12,0]}}
  #|{"textrec":{"g":319,"r":[1389,20,11,14,-1,-12,0]}}
  #|{"textrec":{"g":320,"r":[1401,20,9,13,0,-9,0]}}
  #|{"textrec":{"g":321,"r":[1411,20,4,10,0,-8,0]}}
  #|{"textrec":{"g":322,"r":[1416,20,12,15,1,-12,0]}}
  #|{"textrec":{"g":323,"r":[1429,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":269,"r":[1445,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":270,"r":[1462,20,13,15,0,-12,0]}}
  #|{"textrec":{"g":271,"r":[1476,20,5,7,0,-3,0]}}
  #|{"textrec":{"g":272,"r":[1482,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":273,"r":[1499,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":274,"r":[1516,20,6,6,0,-3,0]}}
  #|{"textrec":{"ib":["b7bb1080b4377070",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["82c2071e3017b0de",757,64],"r":[13,13,13,13]}}
  #|{"textrec":{"g":262,"r":[1523,20,18,17,-1,-14,0]}}
  #|{"textrec":{"g":263,"r":[1542,20,18,17,-1,-14,0]}}
  #|{"textrec":{"g":264,"r":[1561,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":265,"r":[1579,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":281,"r":[1597,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":282,"r":[1613,20,14,15,-1,-12,0]}}
  #|{"textrec":{"g":283,"r":[1628,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":284,"r":[1644,20,11,15,1,-12,0]}}
  #|{"textrec":{"g":285,"r":[1656,20,10,12,0,-11,0]}}
  #|{"textrec":{"g":286,"r":[1667,20,9,11,-1,-9,0]}}
  #|{"textrec":{"g":287,"r":[1677,20,13,10,-1,-9,0]}}
  #|{"textrec":{"g":288,"r":[1691,20,10,11,-1,-9,0]}}
  #|{"textrec":{"g":289,"r":[1702,20,10,11,-1,-9,0]}}
  #|{"textrec":{"g":290,"r":[1713,20,7,12,-1,-11,0]}}
  #|{"textrec":{"g":291,"r":[1721,20,4,12,0,-11,0]}}
  #|{"textrec":{"g":292,"r":[1726,20,5,12,-1,-11,0]}}
  #|{"textrec":{"g":293,"r":[1732,20,9,11,-1,-9,0]}}
  #|{"textrec":{"g":5,"r":[1742,20,13,15,0,-12,0]}}
  #|{"textrec":{"g":294,"r":[1756,20,14,15,-1,-12,0]}}
  #|{"textrec":{"g":295,"r":[1771,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":296,"r":[1787,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":297,"r":[1803,20,14,15,-1,-12,0]}}
  #|{"textrec":{"g":298,"r":[1818,20,14,15,-1,-12,0]}}
  #|{"textrec":{"g":299,"r":[1833,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":300,"r":[1849,20,14,15,-1,-12,0]}}
  #|{"textrec":{"g":301,"r":[1864,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":302,"r":[1880,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":303,"r":[1896,20,10,13,-1,-9,0]}}
  #|{"textrec":{"g":304,"r":[1907,20,9,11,-1,-9,0]}}
  #|{"textrec":{"g":305,"r":[1917,20,7,12,-1,-10,0]}}
  #|{"textrec":{"g":306,"r":[1925,20,5,10,0,-8,0]}}
  #|{"textrec":{"g":307,"r":[1931,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":308,"r":[1947,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":309,"r":[1963,20,5,7,0,-3,0]}}
  #|{"textrec":{"g":310,"r":[1969,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":311,"r":[1985,20,14,15,-1,-12,0]}}
  #|{"textrec":{"g":312,"r":[2000,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":313,"r":[2015,20,10,13,-1,-9,0]}}
  #|{"textrec":{"g":314,"r":[2026,20,10,10,-1,-9,0]}}
  #|{"textrec":{"g":275,"r":[0,39,15,16,-1,-13,0]}}
  #|{"textrec":{"g":276,"r":[16,39,16,16,-1,-13,0]}}
  #|{"textrec":{"g":277,"r":[33,39,4,5,0,-3,0]}}
  #|{"textrec":{"g":278,"r":[38,39,13,10,0,-9,0]}}
  #|{"textrec":{"g":279,"r":[52,39,15,16,-1,-13,0]}}
  #|{"textrec":{"g":280,"r":[68,39,16,15,-1,-12,0]}}
  #|{"textrec":{"g":254,"r":[85,39,18,17,-1,-14,0]}}
  #|{"textrec":{"g":255,"r":[104,39,17,17,-1,-14,0]}}
  #|{"textrec":{"g":256,"r":[122,39,17,17,-1,-14,0]}}
  #|{"textrec":{"g":257,"r":[140,39,17,17,-1,-14,0]}}
  #|{"textrec":{"ib":["5e7fcd0c8367a3ab",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"g":258,"r":[158,39,14,15,-1,-12,0]}}
  #|{"textrec":{"g":259,"r":[173,39,15,14,-1,-11,0]}}
  #|{"textrec":{"g":260,"r":[189,39,15,15,-1,-12,0]}}
  #|{"textrec":{"g":261,"r":[205,39,15,15,-1,-12,0]}}
  #|{"textrec":{"ib":["ee44219918426000",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"s":[14,400,0,"选择模型"],"r":[0,1,13.891050583657588,329,1,1,13.891050583657588,330,2,1,13.891050583657588,331,3,1,13.891050583657588,332]}}
  #|{"textrec":{"s":[14,400,0," · 默认深度 · 自动 · cc"],"r":[0,1,3.787109375,-1,1,1,6.707664066085361,228,2,1,3.787109375,-1,3,1,13.891050583657588,333,4,1,13.891050583657584,334,5,1,13.891050583657588,335,6,1,13.891050583657588,336,7,1,3.787109375,-1,8,1,6.707664066085357,228,9,1,3.787109375,-1,10,1,13.891050583657588,229,11,1,13.891050583657588,230,12,1,3.787109375,-1,13,1,6.707664066085357,228,14,1,3.787109375,-1,15,1,7.68359375,227,16,1,7.68359375,227]}}
  #|{"textrec":{"s":[14,400,0,"运行时"],"r":[0,1,13.891050583657588,235,1,1,13.891050583657588,236,2,1,13.891050583657588,337]}}
  #|{"textrec":{"s":[14,400,0,"Claude Code"],"r":[0,1,9.87109375,338,1,1,3.390625,339,2,1,7.57421875,50,3,1,8.0185546875,60,4,1,8.44921875,56,5,1,7.84765625,54,6,1,3.787109375,-1,7,1,9.87109375,338,8,1,8.12109375,62,9,1,8.44921875,56,10,1,7.84765625,54]}}
  #|{"textrec":{"s":[14,400,0,"进程"],"r":[0,1,13.891050583657588,340,1,1,13.891050583657588,341]}}
  #|{"textrec":{"s":[14,400,0,"保温中"],"r":[0,1,13.891050583657588,342,1,1,13.891050583657588,343,2,1,13.891050583657588,344]}}
  #|{"textrec":{"s":[14,400,0,"轮次"],"r":[0,1,13.891050583657588,253,1,1,13.891050583657588,345]}}
  #|{"textrec":{"s":[13,400,0,"用量"],"r":[0,1,12.898832684824903,346,1,1,12.898832684824903,347]}}
  #|{"textrec":{"s":[14,400,0,"模型调用"],"r":[0,1,13.891050583657588,331,1,1,13.891050583657588,332,2,1,13.891050583657588,348,3,1,13.891050583657588,349]}}
  #|{"textrec":{"s":[14,400,0,"0 次"],"r":[0,1,8.66796875,316,1,1,3.787109375,-1,2,1,13.891050583657588,345]}}
  #|{"textrec":{"s":[14,400,0,"输入"],"r":[0,1,13.891050583657588,350,1,1,13.891050583657588,351]}}
  #|{"textrec":{"s":[14,400,0,"0"],"r":[0,1,8.66796875,316]}}
  #|{"textrec":{"s":[14,400,0,"其中缓存"],"r":[0,1,13.891050583657588,352,1,1,13.891050583657588,344,2,1,13.891050583657588,353,3,1,13.891050583657588,354]}}
  #|{"textrec":{"s":[14,400,0,"输出"],"r":[0,1,13.891050583657588,350,1,1,13.891050583657588,355]}}
  #|{"textrec":{"s":[14,400,0,"缓存命中率"],"r":[0,1,13.891050583657588,353,1,1,13.891050583657588,354,2,1,13.891050583657588,356,3,1,13.891050583657588,344,4,1,13.891050583657588,357]}}
  #|{"textrec":{"s":[14,400,0,"未报告"],"r":[0,1,13.891050583657588,234,1,1,13.891050583657588,358,2,1,13.891050583657588,359]}}
  #|{"textrec":{"s":[13,400,0,"Station"],"r":[0,1,8.20751953125,360,1,1,4.646484375,219,2,1,7.0966796875,12,3,1,4.646484375,219,4,1,3.1357421875,223,5,1,7.6044921875,7,6,1,7.50927734375,217]}}
  #|{"textrec":{"s":[14,400,0,"名称"],"r":[0,1,13.891050583657588,361,1,1,13.891050583657588,362]}}
  #|{"textrec":{"g":329,"r":[221,39,16,16,-1,-13,0]}}
  #|{"textrec":{"g":330,"r":[238,39,16,16,-1,-13,0]}}
  #|{"textrec":{"g":331,"r":[255,39,16,16,-1,-13,0]}}
  #|{"textrec":{"g":332,"r":[272,39,15,15,-1,-12,0]}}
  #|{"textrec":{"g":333,"r":[288,39,16,16,-1,-13,0]}}
  #|{"textrec":{"g":334,"r":[305,39,16,16,-1,-13,0]}}
  #|{"textrec":{"g":335,"r":[322,39,16,15,-1,-12,0]}}
  #|{"textrec":{"g":336,"r":[339,39,16,16,-1,-13,0]}}
  #|{"textrec":{"g":337,"r":[356,39,15,16,0,-13,0]}}
  #|{"textrec":{"g":338,"r":[372,39,12,14,-1,-12,0]}}
  #|{"textrec":{"g":339,"r":[385,39,4,13,0,-12,0]}}
  #|{"textrec":{"g":340,"r":[390,39,16,16,-1,-13,0]}}
  #|{"textrec":{"g":341,"r":[407,39,15,16,-1,-13,0]}}
  #|{"textrec":{"g":342,"r":[423,39,16,16,-1,-13,0]}}
  #|{"textrec":{"g":343,"r":[440,39,16,15,-1,-12,0]}}
  #|{"textrec":{"g":344,"r":[457,39,14,16,0,-13,0]}}
  #|{"textrec":{"g":345,"r":[472,39,16,16,-1,-13,0]}}
  #|{"textrec":{"g":346,"r":[489,39,14,14,-1,-11,0]}}
  #|{"textrec":{"g":347,"r":[504,39,14,14,-1,-12,0]}}
  #|{"textrec":{"g":348,"r":[519,39,15,15,-1,-12,0]}}
  #|{"textrec":{"g":349,"r":[535,39,15,15,-1,-12,0]}}
  #|{"textrec":{"g":350,"r":[551,39,16,16,-1,-13,0]}}
  #|{"textrec":{"g":351,"r":[568,39,16,16,-1,-13,0]}}
  #|{"textrec":{"g":352,"r":[585,39,15,16,-1,-13,0]}}
  #|{"textrec":{"g":353,"r":[601,39,16,16,-1,-13,0]}}
  #|{"textrec":{"g":354,"r":[618,39,15,16,-1,-13,0]}}
  #|{"textrec":{"g":355,"r":[634,39,14,16,0,-13,0]}}
  #|{"textrec":{"g":356,"r":[649,39,16,16,-1,-13,0]}}
  #|{"textrec":{"g":357,"r":[666,39,15,16,-1,-13,0]}}
  #|{"textrec":{"g":358,"r":[682,39,16,16,-1,-13,0]}}
  #|{"textrec":{"g":359,"r":[699,39,15,16,-1,-13,0]}}
  #|{"textrec":{"g":360,"r":[715,39,10,13,-1,-11,0]}}
  #|{"textrec":{"g":361,"r":[726,39,14,16,-1,-13,0]}}
  #|{"textrec":{"g":362,"r":[741,39,16,16,-1,-13,0]}}
  #|{"textrec":{"ib":["54f6f25c61b411ff",983,64],"r":[15,15,15,15]}}
  #|{"textrec":{"ib":["e733bc7eab8087ba",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"s":[14,400,0,"机器"],"r":[0,1,13.891050583657588,363,1,1,13.891050583657588,364]}}
  #|{"textrec":{"s":[14,400,0,"Apple M4 · 16 GB · macOS 27.0.1"],"r":[0,1,9.283203125,365,1,1,8.39453125,320,2,1,8.39453125,320,3,1,3.390625,339,4,1,7.84765625,54,5,1,3.787109375,-1,6,1,12.0859375,366,7,1,8.859375,367,8,1,3.787109375,-1,9,1,6.707664066085357,228,10,1,3.787109375,-1,11,1,6.34375,368,12,1,8.763671875,369,13,1,3.787109375,-1,14,1,10.3017578125,370,15,1,9.05078125,371,16,1,3.787109375,-1,17,1,6.707664066085357,228,18,1,3.787109375,-1,19,1,12.03125,278,20,1,7.57421875,50,21,1,7.68359375,227,22,1,10.650390625,372,23,1,8.7705078125,224,24,1,3.787109375,-1,25,1,8.298828125,252,26,1,7.068359375,373,27,1,2.98046875,277,28,1,8.12109375,316,29,1,3.52734375,277,30,1,6.138671875,368]}}
  #|{"textrec":{"s":[16,600,0,"更换模型"],"r":[0,1,15.875486381322958,374,1,1,15.875486381322958,375,2,1,15.875486381322958,376,3,1,15.875486381322958,377]}}
  #|{"textrec":{"g":363,"r":[758,39,16,16,-1,-13,0]}}
  #|{"textrec":{"g":364,"r":[775,39,16,15,-1,-12,0]}}
  #|{"textrec":{"g":365,"r":[792,39,11,12,-1,-11,0]}}
  #|{"textrec":{"g":366,"r":[804,39,12,12,0,-11,0]}}
  #|{"textrec":{"g":367,"r":[817,39,11,12,-1,-11,0]}}
  #|{"textrec":{"g":368,"r":[829,39,7,12,-1,-11,0]}}
  #|{"textrec":{"g":369,"r":[837,39,11,14,-1,-12,0]}}
  #|{"textrec":{"g":370,"r":[849,39,12,14,-1,-12,0]}}
  #|{"textrec":{"g":371,"r":[862,39,10,12,0,-11,0]}}
  #|{"textrec":{"g":372,"r":[873,39,12,14,-1,-12,0]}}
  #|{"textrec":{"g":373,"r":[886,39,10,12,-1,-11,0]}}
  #|{"textrec":{"s":[15,600,0,"无变更"],"r":[0,1,14.883268482490273,378,1,1,14.883268482490273,379,2,1,14.883268482490273,380]}}
  #|{"textrec":{"s":[14,400,0,"默认模型"],"r":[0,1,13.891050583657588,333,1,1,13.891050583657588,334,2,1,13.891050583657588,331,3,1,13.891050583657588,332]}}
  #|{"textrec":{"s":[13,400,0,"模型"],"r":[0,1,12.898832684824903,381,1,1,12.898832684824903,382]}}
  #|{"textrec":{"s":[14,400,0,"默认深度"],"r":[0,1,13.891050583657588,333,1,1,13.891050583657588,334,2,1,13.891050583657588,335,3,1,13.891050583657588,336]}}
  #|{"textrec":{"s":[13,400,0,"深度"],"r":[0,1,12.898832684824903,383,1,1,12.898832684824903,384]}}
  #|{"textrec":{"s":[14,400,0,"自动 · cc"],"r":[0,1,13.891050583657588,229,1,1,13.891050583657588,230,2,1,3.787109375,-1,3,1,6.707664066085357,228,4,1,3.787109375,-1,5,1,7.68359375,227,6,1,7.68359375,227]}}
  #|{"textrec":{"s":[13,400,0,"账号"],"r":[0,1,12.898832684824903,385,1,1,12.898832684824903,386]}}
  #|{"textrec":{"s":[14,600,0,"自动分配"],"r":[0,1,13.891050583657588,387,1,1,13.891050583657588,388,2,1,13.891050583657588,389,3,1,13.891050583657588,390]}}
  #|{"textrec":{"m":[14,600,0],"r":[13.53515625,2.953125,20,13.53515625,2.953125,0]}}
  #|{"textrec":{"s":[12,400,0,"更改将从下一轮开始生效。"],"r":[0,1,11.918287937743191,391,1,1,11.918287937743191,392,2,1,11.918287937743195,393,3,1,11.918287937743187,394,4,1,11.918287937743187,395,5,1,11.918287937743187,396,6,1,11.918287937743187,397,7,1,11.918287937743187,327,8,1,11.918287937743187,398,9,1,11.918287937743187,399,10,1,11.918287937743187,400,11,1,6.081712062256798,401]}}
  #|{"textrec":{"s":[15,400,0,"选择模型"],"r":[0,1,14.883268482490273,402,1,1,14.883268482490273,403,2,1,14.883268482490273,404,3,1,14.883268482490273,405]}}
  #|{"textrec":{"s":[13,400,0,"思考深度"],"r":[0,1,12.898832684824903,406,1,1,12.898832684824903,407,2,1,12.898832684824903,383,3,1,12.898832684824903,384]}}
  #|{"textrec":{"s":[12,400,0,"深度越高，速度越慢，消耗的额度也越多。"],"r":[0,1,11.918287937743191,408,1,1,11.918287937743191,409,2,1,11.918287937743195,410,3,1,11.918287937743187,411,4,1,12.081712062256813,412,5,1,11.918287937743187,413,6,1,11.918287937743187,409,7,1,11.918287937743187,410,8,1,11.918287937743187,414,9,1,12.081712062256813,412,10,1,11.918287937743187,415,11,1,11.918287937743202,416,12,1,11.918287937743202,417,13,1,11.918287937743202,418,14,1,11.918287937743202,409,15,1,11.918287937743202,419,16,1,11.918287937743202,410,17,1,11.918287937743202,420,18,1,6.081712062256798,401]}}
  #|{"textrec":{"s":[14,400,0,"low"],"r":[0,1,3.390625,339,1,1,7.984375,62,2,1,10.5546875,53]}}
  #|{"textrec":{"s":[14,400,0,"medium"],"r":[0,1,12.03125,278,1,1,7.84765625,54,2,1,8.44921875,56,3,1,3.30859375,61,4,1,8.0185546875,60,5,1,12.03125,278]}}
  #|{"textrec":{"s":[14,400,0,"high"],"r":[0,1,8.0869140625,58,1,1,3.30859375,61,2,1,8.380859375,421,3,1,8.0869140625,58]}}
  #|{"textrec":{"s":[14,400,0,"xhigh"],"r":[0,1,7.19140625,422,1,1,8.0869140625,58,2,1,3.30859375,61,3,1,8.380859375,421,4,1,8.0869140625,58]}}
  #|{"textrec":{"s":[14,400,0,"max"],"r":[0,1,12.03125,278,1,1,7.57421875,50,2,1,7.19140625,422]}}
  #|{"textrec":{"s":[14,400,0,"…"],"r":[0,1,11.115234375,423]}}
  #|{"textrec":{"s":[14,400,0,"默认…"],"r":[0,1,13.891050583657588,333,1,1,13.891050583657588,334,2,1,11.115234375,423]}}
  #|{"textrec":{"s":[14,400,0,"me…"],"r":[0,1,12.03125,278,1,1,7.84765625,54,2,1,11.115234375,423]}}
  #|{"textrec":{"s":[14,400,0,"x…"],"r":[0,1,7.19140625,422,1,1,11.115234375,423]}}
  #|{"textrec":{"s":[15,400,0,"自动分配"],"r":[0,1,14.883268482490273,424,1,1,14.883268482490273,425,2,1,14.883268482490273,426,3,1,14.883268482490273,427]}}
  #|{"textrec":{"s":[12,400,0,"额度用完或登录失效时自动切换"],"r":[0,1,11.918287937743191,418,1,1,11.918287937743191,409,2,1,11.918287937743195,428,3,1,11.918287937743187,175,4,1,11.918287937743187,429,5,1,11.918287937743187,430,6,1,11.918287937743187,431,7,1,11.918287937743187,432,8,1,11.918287937743187,400,9,1,11.918287937743187,433,10,1,11.918287937743187,434,11,1,11.918287937743202,435,12,1,11.918287937743202,436,13,1,11.918287937743202,437]}}
  #|{"textrec":{"g":381,"r":[897,39,15,15,-1,-12,0]}}
  #|{"textrec":{"g":382,"r":[913,39,14,14,-1,-12,0]}}
  #|{"textrec":{"g":406,"r":[928,39,15,14,-1,-11,0]}}
  #|{"textrec":{"g":407,"r":[944,39,14,15,-1,-12,0]}}
  #|{"textrec":{"g":383,"r":[959,39,15,15,-1,-12,0]}}
  #|{"textrec":{"g":384,"r":[975,39,15,15,-1,-12,0]}}
  #|{"textrec":{"g":408,"r":[991,39,14,14,-1,-11,0]}}
  #|{"textrec":{"g":409,"r":[1006,39,14,14,-1,-11,0]}}
  #|{"textrec":{"g":410,"r":[1021,39,14,14,-1,-11,0]}}
  #|{"textrec":{"g":411,"r":[1036,39,13,14,-1,-11,0]}}
  #|{"textrec":{"g":412,"r":[1050,39,5,6,0,-3,0]}}
  #|{"textrec":{"g":413,"r":[1056,39,14,14,-1,-11,0]}}
  #|{"textrec":{"g":414,"r":[1071,39,14,14,-1,-11,0]}}
  #|{"textrec":{"g":415,"r":[1086,39,13,14,-1,-11,0]}}
  #|{"textrec":{"g":416,"r":[1100,39,14,14,-1,-11,0]}}
  #|{"textrec":{"g":417,"r":[1115,39,13,14,-1,-11,0]}}
  #|{"textrec":{"g":418,"r":[1129,39,14,14,-1,-11,0]}}
  #|{"textrec":{"g":419,"r":[1144,39,14,13,-1,-11,0]}}
  #|{"textrec":{"g":420,"r":[1159,39,12,14,0,-11,0]}}
  #|{"textrec":{"g":401,"r":[1172,39,6,6,0,-3,0]}}
  #|{"textrec":{"g":385,"r":[1179,39,15,15,-1,-12,0]}}
  #|{"textrec":{"g":386,"r":[1195,39,15,14,-1,-11,0]}}
  #|{"textrec":{"g":391,"r":[1211,39,14,14,-1,-11,0]}}
  #|{"textrec":{"g":392,"r":[1226,39,14,14,-1,-11,0]}}
  #|{"textrec":{"g":393,"r":[1241,39,14,14,-1,-11,0]}}
  #|{"textrec":{"g":394,"r":[1256,39,14,14,-1,-11,0]}}
  #|{"textrec":{"g":395,"r":[1271,39,14,13,-1,-10,0]}}
  #|{"textrec":{"g":396,"r":[1286,39,14,4,-1,-6,0]}}
  #|{"textrec":{"g":397,"r":[1301,39,14,14,-1,-11,0]}}
  #|{"textrec":{"g":398,"r":[1316,39,14,14,-1,-11,0]}}
  #|{"textrec":{"g":399,"r":[1331,39,14,13,-1,-11,0]}}
  #|{"textrec":{"g":400,"r":[1346,39,14,14,-1,-11,0]}}
  #|{"textrec":{"g":423,"r":[1361,39,12,5,0,-3,0]}}
  #|{"textrec":{"g":424,"r":[1374,39,13,16,1,-13,0]}}
  #|{"textrec":{"g":425,"r":[1388,39,16,16,-1,-13,0]}}
  #|{"textrec":{"g":426,"r":[1405,39,16,16,-1,-13,0]}}
  #|{"textrec":{"g":427,"r":[1422,39,16,16,-1,-13,0]}}
  #|{"textrec":{"g":428,"r":[1439,39,13,14,-1,-11,0]}}
  #|{"textrec":{"g":429,"r":[1453,39,14,14,-1,-11,0]}}
  #|{"textrec":{"g":430,"r":[1468,39,14,13,-1,-11,0]}}
  #|{"textrec":{"g":431,"r":[1483,39,13,14,-1,-11,0]}}
  #|{"textrec":{"g":432,"r":[1497,39,14,14,-1,-11,0]}}
  #|{"textrec":{"g":433,"r":[1512,39,14,14,-1,-11,0]}}
  #|{"textrec":{"g":434,"r":[1527,39,11,14,0,-11,0]}}
  #|{"textrec":{"g":435,"r":[1539,39,13,14,-1,-11,0]}}
  #|{"textrec":{"g":436,"r":[1553,39,13,14,-1,-11,0]}}
  #|{"textrec":{"g":437,"r":[1567,39,14,14,-1,-11,0]}}
  #|{"textrec":{"ib":["7e9322e1e57d8f14",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"g":402,"r":[1582,39,16,16,-1,-13,0]}}
  #|{"textrec":{"g":403,"r":[1599,39,17,16,-1,-13,0]}}
  #|{"textrec":{"g":404,"r":[1617,39,17,16,-1,-13,0]}}
  #|{"textrec":{"g":405,"r":[1635,39,16,16,-1,-13,0]}}
  #|{"textrec":{"g":374,"r":[1652,39,18,17,-1,-14,0]}}
  #|{"textrec":{"g":375,"r":[1671,39,18,17,-1,-14,0]}}
  #|{"textrec":{"g":376,"r":[1690,39,17,17,-1,-14,0]}}
  #|{"textrec":{"g":377,"r":[1708,39,17,17,-1,-14,0]}}
  #|{"textrec":{"g":387,"r":[1726,39,12,16,1,-13,0]}}
  #|{"textrec":{"g":388,"r":[1739,39,15,16,-1,-13,0]}}
  #|{"textrec":{"g":389,"r":[1755,39,16,16,-1,-13,0]}}
  #|{"textrec":{"g":390,"r":[1772,39,16,15,-1,-12,0]}}
  #|{"textrec":{"ib":["fcc12d57cc8a9841",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"g":378,"r":[1789,39,16,16,-1,-13,0]}}
  #|{"textrec":{"g":379,"r":[1806,39,17,17,-1,-14,0]}}
  #|{"textrec":{"g":380,"r":[1824,39,17,16,-1,-13,0]}}
  #|{"textrec":{"g":422,"r":[1842,39,9,10,-1,-9,0]}}
  #|{"textrec":{"s":[17,400,0,"更换模型"],"r":[0,1,16.851167315175097,438,1,1,16.851167315175097,439,2,1,16.851167315175097,440,3,1,16.851167315175097,441]}}
  #|{"textrec":{"s":[17,600,0,"选择模型"],"r":[0,1,16.851167315175097,442,1,1,16.851167315175097,443,2,1,16.851167315175097,444,3,1,16.851167315175097,445]}}
  #|{"textrec":{"m":[17,600,0],"r":[16.435546875,3.5859375,24,16.435546875,3.5859375,0]}}
  #|{"textrec":{"s":[15,400,0,"Sonnet 5.5"],"r":[0,1,9.32373046875,446,1,1,8.6279296875,447,2,1,8.51806640625,129,3,1,8.51806640625,129,4,1,8.3349609375,128,5,1,5.21484375,130,6,1,3.984375,-1,7,1,8.78173828125,448,8,1,3.724365234375,449,9,1,8.800048828125,448]}}
  #|{"textrec":{"g":438,"r":[1852,39,18,17,-1,-14,0]}}
  #|{"textrec":{"g":439,"r":[1871,39,19,18,-1,-15,0]}}
  #|{"textrec":{"g":440,"r":[1891,39,18,18,-1,-15,0]}}
  #|{"textrec":{"g":441,"r":[1910,39,18,18,-1,-15,0]}}
  #|{"textrec":{"g":442,"r":[1929,39,18,18,-1,-15,0]}}
  #|{"textrec":{"g":443,"r":[1948,39,19,18,-1,-15,0]}}
  #|{"textrec":{"g":444,"r":[1968,39,18,18,-1,-15,0]}}
  #|{"textrec":{"g":445,"r":[1987,39,18,18,-1,-15,0]}}
  #|{"textrec":{"g":446,"r":[2006,39,11,14,-1,-12,0]}}
  #|{"textrec":{"g":447,"r":[2018,39,11,12,-1,-10,0]}}
  #|{"textrec":{"g":448,"r":[2030,39,10,14,0,-12,0]}}
  #|{"textrec":{"g":449,"r":[2041,39,5,5,0,-3,0]}}
  #|{"textrec":{"s":[15,600,0,"改成 Sonnet 5.5 · high · 自动分配"],"r":[0,1,14.883268482490273,450,1,1,14.883268482490273,451,2,1,3.761730194091797,-1,3,1,9.68320906162262,452,4,1,8.901597261428833,453,5,1,8.93320620059967,454,6,1,8.93320620059967,454,7,1,8.615586161613464,455,8,1,5.683325529098511,456,9,1,3.761730194091797,-1,10,1,9.187601208686829,457,11,1,4.189368188381195,458,12,1,9.23490196466446,457,13,1,3.761730194091797,-1,14,1,7.186782927948599,459,15,1,3.761730194091797,-1,16,1,9.006448388099656,460,17,1,3.8520312309265137,461,18,1,9.247174859046936,462,19,1,9.00644838809967,460,20,1,3.761730194091797,-1,21,1,7.186782927948599,459,22,1,3.761730194091797,-1,23,1,14.88326848249028,463,24,1,14.88326848249028,464,25,1,14.88326848249028,465,26,1,14.88326848249028,466]}}
  #|{"textrec":{"s":[14,600,0,"Sonnet 5.5"],"r":[0,1,9.106021165847778,467,1,1,8.376516819000244,468,2,1,8.406018495559692,469,3,1,8.406018495559692,469,4,1,8.109573125839233,470,5,1,5.372796535491943,471,6,1,3.5793075561523438,-1,7,1,8.64345383644104,472,8,1,3.9784363508224487,473,9,1,8.687601208686829,472]}}
  #|{"textrec":{"s":[14,600,0,"high"],"r":[0,1,8.474377870559692,474,1,1,3.663588523864746,475,2,1,8.699055910110474,476,3,1,8.474377870559692,474]}}
  #|{"textrec":{"g":467,"r":[0,58,11,14,-1,-12,0]}}
  #|{"textrec":{"g":468,"r":[12,58,10,11,-1,-9,0]}}
  #|{"textrec":{"g":469,"r":[23,58,9,10,0,-9,0]}}
  #|{"textrec":{"g":470,"r":[33,58,10,11,-1,-9,0]}}
  #|{"textrec":{"g":471,"r":[44,58,7,13,-1,-11,0]}}
  #|{"textrec":{"g":472,"r":[52,58,10,13,0,-11,0]}}
  #|{"textrec":{"g":473,"r":[63,58,5,6,0,-4,0]}}
  #|{"textrec":{"g":474,"r":[69,58,9,13,0,-12,0]}}
  #|{"textrec":{"g":475,"r":[79,58,5,13,-1,-12,0]}}
  #|{"textrec":{"g":476,"r":[85,58,10,13,-1,-9,0]}}
  #|{"textrec":{"g":450,"r":[96,58,17,16,-1,-13,0]}}
  #|{"textrec":{"g":451,"r":[114,58,17,17,-1,-14,0]}}
  #|{"textrec":{"g":452,"r":[132,58,12,14,-1,-12,0]}}
  #|{"textrec":{"g":453,"r":[145,58,11,12,-1,-10,0]}}
  #|{"textrec":{"g":454,"r":[157,58,10,11,0,-10,0]}}
  #|{"textrec":{"g":455,"r":[168,58,11,12,-1,-10,0]}}
  #|{"textrec":{"g":456,"r":[180,58,8,13,-1,-11,0]}}
  #|{"textrec":{"g":457,"r":[189,58,10,14,0,-12,0]}}
  #|{"textrec":{"g":458,"r":[200,58,5,6,0,-4,0]}}
  #|{"textrec":{"g":459,"r":[206,58,5,5,1,-8,0]}}
  #|{"textrec":{"g":460,"r":[212,58,10,14,0,-13,0]}}
  #|{"textrec":{"g":461,"r":[223,58,6,14,-1,-13,0]}}
  #|{"textrec":{"g":462,"r":[230,58,11,14,-1,-10,0]}}
  #|{"textrec":{"g":463,"r":[242,58,13,17,1,-14,0]}}
  #|{"textrec":{"g":464,"r":[256,58,16,17,-1,-14,0]}}
  #|{"textrec":{"g":465,"r":[273,58,16,16,-1,-13,0]}}
  #|{"textrec":{"g":466,"r":[290,58,17,16,-1,-13,0]}}
  #|{"textrec":{"s":[16,700,0,"Sonnet 5.5 · high"],"r":[0,1,10.48828125,477,1,1,9.6015625,478,2,1,9.72265625,479,3,1,9.72265625,479,4,1,9.30078125,480,5,1,6.2890625,481,6,1,3.8125,-1,7,1,9.98828125,482,8,1,4.693359375,483,9,1,10.056640625,482,10,1,3.8125,-1,11,1,7.665901789811841,484,12,1,3.8125,-1,13,1,9.80078125,485,14,1,4.28125,486,15,1,10.01171875,487,16,1,9.80078125,485]}}
  #|{"textrec":{"s":[17,700,0,"Sonnet 5.5 · high"],"r":[0,1,11.044189453125,488,1,1,10.10205078125,489,2,1,10.230712890625,490,3,1,10.230712890625,490,4,1,9.782470703125,491,5,1,6.58251953125,492,6,1,3.951171875,-1,7,1,10.512939453125,493,8,1,4.8870849609375,494,9,1,10.5855712890625,493,10,1,3.951171875,-1,11,1,8.137218907755852,495,12,1,3.951171875,-1,13,1,10.313720703125,496,14,1,4.44921875,497,15,1,10.537841796875,498,16,1,10.313720703125,496]}}
  #|{"textrec":{"s":[14,400,0,"已更改，下一轮起生效"],"r":[0,1,13.891050583657588,499,1,1,13.891050583657588,500,2,1,13.891050583657588,272,3,1,14.081712062256813,271,4,1,13.891050583657588,501,5,1,13.891050583657588,502,6,1,13.891050583657588,253,7,1,13.891050583657588,503,8,1,13.891050583657588,504,9,1,13.891050583657588,505]}}
  #|{"textrec":{"s":[14,400,0,"Sonnet 5.5"],"r":[0,1,8.7705078125,224,1,1,8.12109375,62,2,1,8.0185546875,51,3,1,8.0185546875,51,4,1,7.84765625,54,5,1,4.935546875,57,6,1,3.787109375,-1,7,1,8.2646484375,506,8,1,3.54443359375,277,9,1,8.28173828125,506]}}
  #|{"textrec":{"s":[14,400,0," · high · 自动 · cc"],"r":[0,1,3.787109375,-1,1,1,6.707664066085361,228,2,1,3.787109375,-1,3,1,8.0869140625,58,4,1,3.30859375,61,5,1,8.380859374999996,421,6,1,8.0869140625,58,7,1,3.787109375,-1,8,1,6.707664066085357,228,9,1,3.787109375,-1,10,1,13.891050583657588,229,11,1,13.891050583657588,230,12,1,3.787109375,-1,13,1,6.707664066085357,228,14,1,3.787109375,-1,15,1,7.68359375,227,16,1,7.68359375,227]}}
  #|{"textrec":{"s":[14,400,0,"已释放"],"r":[0,1,13.891050583657588,499,1,1,13.891050583657588,507,2,1,13.891050583657588,508]}}
  #|{"textrec":{"g":421,"r":[308,58,10,13,-1,-9,0]}}
  #|{"textrec":{"g":499,"r":[319,58,14,14,0,-12,0]}}
  #|{"textrec":{"g":507,"r":[334,58,16,16,-1,-13,0]}}
  #|{"textrec":{"g":508,"r":[351,58,16,16,-1,-13,0]}}
  #|{"textrec":{"g":506,"r":[368,58,9,13,0,-11,0]}}
  #|{"textrec":{"g":488,"r":[378,58,13,16,-1,-14,0]}}
  #|{"textrec":{"g":489,"r":[392,58,12,13,-1,-11,0]}}
  #|{"textrec":{"g":490,"r":[405,58,11,12,0,-11,0]}}
  #|{"textrec":{"g":491,"r":[417,58,12,13,-1,-11,0]}}
  #|{"textrec":{"g":492,"r":[430,58,9,15,-1,-13,0]}}
  #|{"textrec":{"g":493,"r":[440,58,12,15,0,-13,0]}}
  #|{"textrec":{"g":494,"r":[453,58,6,6,0,-4,0]}}
  #|{"textrec":{"g":495,"r":[460,58,6,6,1,-9,0]}}
  #|{"textrec":{"g":496,"r":[467,58,11,15,0,-14,0]}}
  #|{"textrec":{"g":497,"r":[479,58,5,16,0,-15,0]}}
  #|{"textrec":{"g":498,"r":[485,58,12,16,-1,-11,0]}}
  #|{"textrec":{"g":477,"r":[498,58,12,15,-1,-13,0]}}
  #|{"textrec":{"g":478,"r":[511,58,12,12,-1,-10,0]}}
  #|{"textrec":{"g":479,"r":[524,58,10,11,0,-10,0]}}
  #|{"textrec":{"g":480,"r":[535,58,11,12,-1,-10,0]}}
  #|{"textrec":{"g":481,"r":[547,58,8,14,-1,-12,0]}}
  #|{"textrec":{"g":482,"r":[556,58,11,15,0,-13,0]}}
  #|{"textrec":{"g":483,"r":[568,58,6,6,0,-4,0]}}
  #|{"textrec":{"g":484,"r":[575,58,5,5,1,-8,0]}}
  #|{"textrec":{"g":485,"r":[581,58,11,14,0,-13,0]}}
  #|{"textrec":{"g":486,"r":[593,58,5,15,0,-14,0]}}
  #|{"textrec":{"g":487,"r":[599,58,12,15,-1,-10,0]}}
  #|{"textrec":{"g":500,"r":[612,58,16,15,-1,-12,0]}}
  #|{"textrec":{"g":501,"r":[629,58,15,15,-1,-12,0]}}
  #|{"textrec":{"g":502,"r":[645,58,15,4,-1,-7,0]}}
  #|{"textrec":{"g":503,"r":[661,58,16,16,-1,-13,0]}}
  #|{"textrec":{"g":504,"r":[678,58,15,15,-1,-13,0]}}
  #|{"textrec":{"g":505,"r":[694,58,16,16,-1,-13,0]}}
