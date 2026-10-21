// e2e/traces/service-page.trace, made by scripts/trace.py from 01-service_page.log: not edited by hand.

///|
/// What the app and its core said in the run, a line each.
pub let trace_service_page : String =
  #|{"env":{"MBUI_CLOUD":"http://127.0.0.1:18787","MBUI_CORE_ACCOUNT":"{\"sub\":\"alice\",\"email\":\"alice@example.test\",\"name\":\"Name of alice\",\"picture\":\"\",\"access\":\"-\",\"refresh\":\"-\",\"accessExpires\":1792556710}"}}
  #|{"out":{"id":1,"call":"client.device","params":{"client":"still.fail mbui","app":"desktop","userAgent":"Macintosh; Mac OS X"}},"w":1792556412107.893}
  #|{"in":{"id":1,"ok":null},"w":1792556412200.263}
  #|{"out":{"id":2,"subscribe":{"topic":"accounts"},"keyed":true},"w":1792556412200.29}
  #|{"out":{"id":3,"subscribe":{"topic":"prefs"},"keyed":true},"w":1792556412200.299}
  #|{"step":"# written by scripts/rerecord.sh from its test (src/sfreplay/emit.mbt): not edited by hand","w":1792556412201.749}
  #|{"step":"timeout 90000","w":1792556412201.757}
  #|{"step":"answered client.device","w":1792556412201.76}
  #|{"step":"answered client.focus","w":1792556412217.197}
  #|{"in":{"id":2,"value":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""}]},"w":1792556412283.582}
  #|{"in":{"id":3,"value":{"onlyMine":false,"onlyWatching":false,"onlyDecisions":false,"listFilter":{},"appearance":"system","rowPicture":"auto","absoluteTime":false,"lang":"zh","keys":{},"lastChat":{},"openChat":{},"chatTabs":{},"dropFiles":{},"driveViews":{},"resume":{},"stationUpdatesDismissed":{},"device":{"app":"desktop","phone":false,"handoff":false},"reader":{"size":18,"line":1.7,"margin":22,"face":"sans","indent":true,"paper":"follow"},"rails":{},"bars":{"sets":[["chats","files","profiles","stations"],["decisions","usage","connects","archive"]],"current":0},"barsBy":{},"fonts":{},"faces":{"ui":{"id":"","name":"","mono":false,"family":"","files":[],"bytes":0},"text":{"id":"","name":"","mono":false,"family":"","files":[],"bytes":0},"code":{"id":"","name":"","mono":true,"family":"","files":[],"bytes":0},"list":[{"id":"inter","name":"Inter","mono":false,"family":"SF Inter","css":"http://127.0.0.1:18787/releases/fonts/inter/4.001/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/inter/4.001/var.ttf.gz","bytes":457818,"sha256":"29160a80ff49ddcab2c97711247e08b1fab27a484a329ce8b813d820dc559031"}],"preview":"http://127.0.0.1:18787/releases/fonts/inter/4.001/preview-194fa287.ttf","bytes":457818},{"id":"noto-sans-sc","name":"思源黑体","mono":false,"family":"SF Noto Sans SC","css":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/var.ttf.gz","bytes":11276563,"sha256":"a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da"}],"preview":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/preview-f0494178.ttf","bytes":11276563},{"id":"noto-serif-sc","name":"思源宋体","mono":false,"family":"SF Noto Serif SC","css":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/var.ttf.gz","bytes":15454579,"sha256":"050080d9255a86808f2945bffac582b31ef32bc36411ce29563b4961670c66f9"}],"preview":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/preview-001bbedf.ttf","bytes":15454579},{"id":"lxgw-wenkai","name":"霞鹜文楷","mono":false,"family":"SF LXGW WenKai","css":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/font.css","files":[{"weight":400,"url":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/400.ttf.gz","bytes":12904482,"sha256":"2d73eea94ad808999d90c0000c239a84a33b09d4bc6ab6c5b8bbf1eda8a7fc8b"},{"weight":500,"url":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/500.ttf.gz","bytes":13272430,"sha256":"f4b8a34d1f838fe411540cb7c97b1c384ac9738a876c4104500bc42508b2312a"}],"preview":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/preview-d3505af4.ttf","bytes":26176912},{"id":"jetbrains-mono","name":"JetBrains Mono","mono":true,"family":"SF JetBrains Mono","css":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/var.ttf.gz","bytes":90579,"sha256":"48715a42ec242c21e9f02692891e147d022299a52e48d5e413e1a942193ffeda"}],"preview":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/preview-ee73078f.ttf","bytes":90579},{"id":"fira-code","name":"Fira Code","mono":true,"family":"SF Fira Code","css":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/var.ttf.gz","bytes":137151,"sha256":"9335b082b3c7850d98a64b584f3417f65355f3471278bb5eeb8c6c0e8657aeeb"}],"preview":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/preview-555be27a.ttf","bytes":137151},{"id":"maple-mono","name":"Maple Mono","mono":true,"family":"SF Maple Mono CN","css":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/font.css","files":[{"weight":400,"url":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/400.ttf.gz","bytes":8352545,"sha256":"0fcc5139bfd5ab14ff989bb7dfd5236d0cafc10e60b9828569e6883613ab4085"},{"weight":600,"url":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/600.ttf.gz","bytes":8438132,"sha256":"96ed7ae26ee7c50b02b2d2b2bc0f1a0cbabe45ae5d6e6abf6678e2177c415677"}],"preview":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/preview-cffdf246.ttf","bytes":16790677}]}}},"w":1792556412283.627}
  #|{"out":{"id":4,"subscribe":{"topic":"workspaces"},"keyed":true},"w":1792556412283.676}
  #|{"out":{"id":5,"subscribe":{"topic":"status"},"keyed":true},"w":1792556412283.687}
  #|{"in":{"id":4,"value":[{"account":{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""},"workspaces":[{"id":"01M5EB05ZRXYS7E7C5Q0KPJEF5","name":"Dev","role":"owner","created_at":1792556406,"stations":1,"members":1,"relays":[],"time":{"created_at":{"past":true,"at":1792556406000,"ago":"刚刚","full":"10/21 12:20:06","until":"1 分钟内"}}}],"invitations":[],"relay_url":"http://127.0.0.1:18740","loaded":true,"beta":true}]},"w":1792556412301.184}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792556412301.201}
  #|{"out":{"id":6,"subscribe":{"topic":"lock","workspace":"01M5EB05ZRXYS7E7C5Q0KPJEF5"},"keyed":true},"w":1792556412301.241}
  #|{"out":{"id":7,"subscribe":{"topic":"chats","scope":"01M5EB05ZRXYS7E7C5Q0KPJEF5","mine":false},"keyed":true},"w":1792556412301.26}
  #|{"out":{"id":8,"subscribe":{"topic":"changelog"},"keyed":true},"w":1792556412301.268}
  #|{"out":{"id":9,"subscribe":{"topic":"workspaceMarks","workspace":"01M5EB05ZRXYS7E7C5Q0KPJEF5"},"keyed":true},"w":1792556412301.393}
  #|{"out":{"id":10,"subscribe":{"topic":"status","workspace":"01M5EB05ZRXYS7E7C5Q0KPJEF5"},"keyed":true},"w":1792556412301.427}
  #|{"out":{"id":11,"call":"client.focus","params":{"visible":true,"focused":true,"workspace":"01M5EB05ZRXYS7E7C5Q0KPJEF5"}},"w":1792556412308.484}
  #|{"out":{"id":12,"subscribe":{"topic":"notify"},"keyed":true},"w":1792556412308.494}
  #|{"out":{"id":13,"subscribe":{"topic":"notify","workspace":"01M5EB05ZRXYS7E7C5Q0KPJEF5"},"keyed":true},"w":1792556412308.503}
  #|{"in":{"id":6,"value":{"available":true,"locked":false,"notice":true,"role":"owner","manages":true,"owner":true,"canSign":true,"signs":false,"me":{"device":"b6e2b3bb8b3a04d934457005bdbecae3249b590ee034333aa93dae1fbd5ce69f","code":"EKV-9PP","kind":"app","confirmed":false,"waiting":false,"asked":false},"signers":0,"members":[],"stations":[{"id":"c20e11ed024f55b3f01f975d298bd3f8a2f81f9a8c364c121865a0829fa7c07f","name":"studio","version":"0.1.0","online":true,"protected":false}],"protected":0,"requests":[],"renew":[],"attention":0}},"w":1792556412316.929}
  #|{"in":{"id":7,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"stations":[{"station":"01M5EB05ZRXYS7E7C5Q0KPJEF5/c20e11ed024f55b3f01f975d298bd3f8a2f81f9a8c364c121865a0829fa7c07f","id":"c20e11ed024f55b3f01f975d298bd3f8a2f81f9a8c364c121865a0829fa7c07f","name":"studio","state":"online"}],"loading":false,"days":[{"daysAgo":0,"at":1792556410884,"label":"今天","items":[{"id":"ember:c-7445964f07","session":"ember:c-7445964f07","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","agents":[{"key":"ember:c-7445964f07","runtime":"claude","process":"warm","pending":0,"lastTurn":{"id":"b29986cd-a40f-4b35-8456-940da3db5f1f","kind":"input","outcome":"completed","declared":"final","ending":"all_done","need":"answered the question that was asked","startedAt":1792556410822,"endedAt":1792556410887},"agentText":"默认模型","statusText":"已完成：answered the question that was asked"}],"last":{"seq":2,"authorKind":"agent","author":"ember:c-7445964f07","text":"你好，我是测试用的 agent","createdAt":1792556410884,"by":{"kind":"agent","name":"agent","mine":false,"runtime":"claude","label":"agent"},"preview":"你好，我是测试用的 agent","time":{"createdAt":{"at":1792556410884,"ago":"刚刚","full":"10/21 12:20:10","until":"1 分钟内","past":true}}},"unread":true,"mine":true,"lastActiveAt":1792556410884,"station":"01M5EB05ZRXYS7E7C5Q0KPJEF5/c20e11ed024f55b3f01f975d298bd3f8a2f81f9a8c364c121865a0829fa7c07f","stationName":"studio","time":{"lastActiveAt":{"at":1792556410884,"ago":"刚刚","full":"10/21 12:20:10","until":"1 分钟内","past":true}},"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"peopleText":"你 发起","clientKey":"new:chat-bf51adf8b3b403981c","pinned":false,"tone":"done"}]}],"trouble":null,"members":1,"leading":"agents","glyph":{"online":1,"dim":0,"connecting":0,"failing":0,"working":0,"summary":"studio","label":"1 台 station，1 台在线"},"note":{"reading":false,"text":null,"failing":[],"empty":false}}},"w":1792556412316.963}
  #|{"in":{"id":8,"value":{"app":"desktop","tabs":[{"part":"desktop","label":"桌面","days":[]},{"part":"web","label":"网页","days":[]},{"part":"android","label":"安卓","days":[]},{"part":"station","label":"Station","days":[]},{"part":"cloud","label":"云端","days":[]}],"loading":false}},"w":1792556412316.99}
  #|{"in":{"id":9,"value":{"workspaces":{"01M5EB05ZRXYS7E7C5Q0KPJEF5":{"alert":0,"unread":1,"tone":"done","label":"1 个有新消息","badge":0,"items":[],"mineTone":"done"}},"badge":0,"badgeCounts":"attention","badgeKinds":{"on":true,"wait":true,"failed":true,"done":false,"message":false}}},"w":1792556412316.998}
  #|{"in":{"id":10,"value":{"items":[]}},"w":1792556412317.007}
  #|{"in":{"id":11,"ok":null},"w":1792556412317.01}
  #|{"in":{"id":12,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792556412317.015}
  #|{"in":{"id":13,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792556412317.02}
  #|{"out":{"id":14,"subscribe":{"topic":"longJobs","scope":"01M5EB05ZRXYS7E7C5Q0KPJEF5"},"keyed":true},"w":1792556412317.053}
  #|{"out":{"id":15,"call":"notify.permission","params":{"state":"unknown"}},"w":1792556412319.615}
  #|{"in":{"id":14,"value":{"groups":[]}},"w":1792556412333.587}
  #|{"in":{"id":15,"ok":null},"w":1792556412333.597}
  #|{"step":"answered notify.permission","w":1792556412333.867}
  #|{"step":"tap 端到端测试","w":1792556412350.463}
  #|{"step":"tap 端到端测试","acted":true,"w":1792556412350.48}
  #|{"out":{"id":16,"subscribe":{"topic":"chat","station":"01M5EB05ZRXYS7E7C5Q0KPJEF5/c20e11ed024f55b3f01f975d298bd3f8a2f81f9a8c364c121865a0829fa7c07f","session":"ember:c-7445964f07"},"keyed":true},"w":1792556412367.048}
  #|{"out":{"id":17,"call":"draft.get","params":{"key":"01M5EB05ZRXYS7E7C5Q0KPJEF5/c20e11ed024f55b3f01f975d298bd3f8a2f81f9a8c364c121865a0829fa7c07f:ember:c-7445964f07"}},"w":1792556412367.466}
  #|{"step":"answered draft.get","w":1792556412367.598}
  #|{"in":{"id":17,"ok":{"text":"","quotes":[],"files":[],"id":"draft-f4ad01dad0bf1f730c"}},"w":1792556412383.59}
  #|{"in":{"id":16,"value":{"archived":false,"pinned":false,"me":{"id":"alice@example.test","email":"alice@example.test"},"thread":{"id":1,"surface":"ember","channel":"EMBER","threadTs":"1792556410.759000","createdBy":"alice@example.test","creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"createdAt":1792556410759,"sessions":[{"thread":1,"session":"ember:c-7445964f07","connect":"ember","joinedAt":1792556410759}],"last":2,"lastMessage":{"seq":2,"thread":1,"ts":"1792556410.884000","authorKind":"agent","author":"ember:c-7445964f07","text":"你好，我是测试用的 agent","attachments":[],"quotes":[],"declared":"final","ending":"all_done","createdAt":1792556410884,"time":{"createdAt":{"at":1792556410884,"ago":"刚刚","full":"10/21 12:20:10","until":"1 分钟内","past":true}}},"read":0,"unread":1,"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"firstText":"端到端测试的对话 post:你好，我是测试用的 agent","time":{"createdAt":{"at":1792556410759,"ago":"刚刚","full":"10/21 12:20:10","until":"1 分钟内","past":true}}},"title":"端到端测试的对话 post:你好，我是测试用的 agent","people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"agents":[{"session":{"key":"ember:c-7445964f07","connect":"ember","scope":"all","createdBy":"alice@example.test","boundTo":[],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"},"participants":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"}],"runtime":"claude","profile":"cc","profilePinned":false,"runtimeSessionId":"1b73a695-da8d-47b2-83aa-ec0dd82e6b53","workspace":"/tmp/mbe2e-C/data/sessions/ember/c-7445964f07/workspace","running":false,"createdAt":1792556410757,"lastActiveAt":1792556410886,"process":"warm","turns":1,"pending":0,"firstText":"端到端测试的对话 post:你好，我是测试用的 agent","lastTurn":{"id":"b29986cd-a40f-4b35-8456-940da3db5f1f","kind":"input","outcome":"completed","declared":"final","ending":"all_done","need":"answered the question that was asked","startedAt":1792556410822,"endedAt":1792556410887},"statusText":"已完成：answered the question that was asked","tone":"green","titleText":"端到端测试的对话 post:你好，我是测试用的 agent","agentText":"默认模型","runtimeText":"Claude Code","processText":"保温中","efforts":["low","medium","high","xhigh","max"],"time":{"createdAt":{"at":1792556410757,"ago":"刚刚","full":"10/21 12:20:10","until":"1 分钟内","past":true},"lastActiveAt":{"at":1792556410886,"ago":"刚刚","full":"10/21 12:20:10","until":"1 分钟内","past":true}}},"status":"final","profile":{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792556410682,"time":{"checkedAt":{"at":1792556410682,"ago":"刚刚","full":"10/21 12:20:10","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792556410802,"time":{"checkedAt":{"at":1792556410802,"ago":"刚刚","full":"10/21 12:20:10","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]},"profiles":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":true,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792556410802,"time":{"checkedAt":{"at":1792556410802,"ago":"刚刚","full":"10/21 12:20:10","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}],"choices":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":true,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792556410802,"time":{"checkedAt":{"at":1792556410802,"ago":"刚刚","full":"10/21 12:20:10","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"account":{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":true,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792556410802,"time":{"checkedAt":{"at":1792556410802,"ago":"刚刚","full":"10/21 12:20:10","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}},"attention":[],"turns":[{"id":"b29986cd-a40f-4b35-8456-940da3db5f1f","kind":"input","outcome":"completed","declared":"final","ending":"all_done","startedAt":1792556410822,"endedAt":1792556410887}],"threads":[{"id":1,"surface":"ember","channel":"EMBER","threadTs":"1792556410.759000","createdBy":"alice@example.test","creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"},"createdAt":1792556410759,"sessions":[{"thread":1,"session":"ember:c-7445964f07","connect":"ember","joinedAt":1792556410759}],"last":2,"lastMessage":{"seq":2,"thread":1,"ts":"1792556410.884000","authorKind":"agent","author":"ember:c-7445964f07","text":"你好，我是测试用的 agent","attachments":[],"quotes":[],"declared":"final","ending":"all_done","createdAt":1792556410884,"time":{"createdAt":{"at":1792556410884,"ago":"刚刚","full":"10/21 12:20:10","until":"1 分钟内","past":true}}},"read":0,"unread":1,"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"}],"firstText":"端到端测试的对话 post:你好，我是测试用的 agent","time":{"createdAt":{"at":1792556410759,"ago":"刚刚","full":"10/21 12:20:10","until":"1 分钟内","past":true}}}],"jobs":[]}],"messages":[{"seq":1,"thread":1,"ts":"1792556410.809000","authorKind":"person","author":"alice@example.test","authorName":"Name of alice","text":"端到端测试的对话 post:你好，我是测试用的 agent","attachments":[],"quotes":[],"createdAt":1792556410810,"mine":true,"system":false,"by":{"name":"Name of alice","picture":"https://example.test/p.png"},"waiting":false,"time":{"createdAt":{"at":1792556410810,"ago":"刚刚","full":"10/21 12:20:10","until":"1 分钟内","past":true}}},{"seq":2,"thread":1,"ts":"1792556410.884000","authorKind":"agent","author":"ember:c-7445964f07","text":"你好，我是测试用的 agent","attachments":[],"quotes":[],"declared":"final","ending":"all_done","createdAt":1792556410884,"mine":false,"system":false,"by":{"name":"默认模型","agent":"ember:c-7445964f07","runtime":"claude","here":true},"waiting":false,"time":{"createdAt":{"at":1792556410884,"ago":"刚刚","full":"10/21 12:20:10","until":"1 分钟内","past":true}}}],"elsewhere":[],"more":false,"newer":false,"at":1,"caught":2,"unreadLine":2,"unreadAbove":false,"outbox":[],"link":{"state":"online"},"offline":false,"pending":false,"asks":[],"publish":{"may":true,"links":[]}}},"w":1792556412383.687}
  #|{"out":{"id":18,"subscribe":{"topic":"stations","scope":"01M5EB05ZRXYS7E7C5Q0KPJEF5"},"keyed":true},"w":1792556412383.809}
  #|{"out":{"id":19,"subscribe":{"topic":"chatJobs","station":"01M5EB05ZRXYS7E7C5Q0KPJEF5/c20e11ed024f55b3f01f975d298bd3f8a2f81f9a8c364c121865a0829fa7c07f","session":"ember:c-7445964f07"},"keyed":true},"w":1792556412383.819}
  #|{"out":{"id":20,"call":"picture","params":{"url":"https://example.test/p.png"}},"w":1792556412383.832}
  #|{"out":{"id":21,"call":"client.focus","params":{"chat":{"station":"01M5EB05ZRXYS7E7C5Q0KPJEF5/c20e11ed024f55b3f01f975d298bd3f8a2f81f9a8c364c121865a0829fa7c07f","session":"ember:c-7445964f07","thread":1,"end":true}}},"w":1792556412386.432}
  #|{"in":{"id":18,"value":[{"station":"01M5EB05ZRXYS7E7C5Q0KPJEF5/c20e11ed024f55b3f01f975d298bd3f8a2f81f9a8c364c121865a0829fa7c07f","id":"c20e11ed024f55b3f01f975d298bd3f8a2f81f9a8c364c121865a0829fa7c07f","name":"studio","summary":"正在连接","face":"idle","line":"在线","online":true,"reconnecting":false,"lastSeen":1792556410,"version":"0.1.0","link":{"state":"online"},"runtimes":[{"runtime":"claude","models":["claude-sonnet-5-5"]}],"models":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792556410802,"time":{"checkedAt":{"at":1792556410802,"ago":"刚刚","full":"10/21 12:20:10","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"overview":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null,"summaryText":"最近 7 天检查了 0 个 chat","changeText":null}},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","email":"alice@example.test","name":"Name of alice","sub":"alice","role":"owner","workspace":"01M5EB05ZRXYS7E7C5Q0KPJEF5","device":"b6e2b3bb8b3a04d934457005bdbecae3249b590ee034333aa93dae1fbd5ce69f"},"connects":[],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792556410682,"time":{"checkedAt":{"at":1792556410682,"ago":"刚刚","full":"10/21 12:20:10","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792556410802,"time":{"checkedAt":{"at":1792556410802,"ago":"刚刚","full":"10/21 12:20:10","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]}],"processes":[],"counts":{"sessions":1,"running":0,"warm":1},"mesh":{"state":"running","origin":"http://127.0.0.1:18787","station":"c20e11ed024f55b3f01f975d298bd3f8a2f81f9a8c364c121865a0829fa7c07f","workspace":"Dev","workspaceId":"01M5EB05ZRXYS7E7C5Q0KPJEF5","name":"studio"},"slackUsers":[],"slackTeams":[],"slackApps":[],"feishuRegistrations":[],"disk":{"freeBytes":40509898752,"totalBytes":245107195904},"logins":[],"machineLogins":[],"sharing":true,"consoleSignIn":true,"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"google","name":"Google Gemini","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xai","name":"xAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"mistral","name":"Mistral","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"deepseek","name":"DeepSeek","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen","name":"Qwen","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai","name":"Kimi","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai","name":"Z.ai","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax","name":"MiniMax","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ant-ling","name":"Ant Ling","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"jev","name":"Jev","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen-cn","name":"Qwen (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"openrouter","name":"OpenRouter","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"opencode","name":"OpenCode Zen","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"groq","name":"Groq","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"together","name":"Together AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"fireworks","name":"Fireworks","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cerebras","name":"Cerebras","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"huggingface","name":"Hugging Face","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"nvidia","name":"NVIDIA","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"baseten","name":"Baseten","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ollama","name":"Ollama","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"custom","name":"Custom","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""}],"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792556408335},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.306","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792556408335},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-news/apps/e2e-local/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792556408335},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-news/apps/e2e-local/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792556408335},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","latest":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-news/apps/e2e-local/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792556408335},{"id":"cursor","name":"Cursor","installed":false,"latest":"1.0.40","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792556408335},{"id":"devin","name":"Devin","installed":true,"version":"3000.11.92","latest":"3000.11.92","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/61edb1e36469ce593c7abd6fcefcd2f202762a225c94afebae72c82db5245391/work/sf-news/apps/e2e-local/ember/station/test/fake/devin，不是用 Devin 的安装脚本装的，需在该机器上手动更新","state":"idle","checkedAt":1792556408335}],"processesText":"没有运行中的 agent 进程","agentEnv":[],"drive":{"roots":[],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false}},"betaOffered":false,"way":{"path":"直连","via":"direct"},"time":{"lastSeen":{"at":1792556410000,"ago":"刚刚","full":"10/21 12:20:10","until":"1 分钟内","past":true}},"joined":false}]},"w":1792556412400.358}
  #|{"in":{"id":19,"value":{"jobs":[],"servicesNote":"","jobsNote":"","current":0,"ended":0,"clear":[],"allText":"全部 0 个","clearText":"清除 0 个已结束的","hiddenText":"另有 0 个已停止或结束"}},"w":1792556412400.445}
  #|{"in":{"id":21,"ok":null},"w":1792556412400.452}
  #|{"step":"answered picture","w":1792556412401.454}
  #|{"in":{"id":3,"delta":[{"path":["openChat","01M5EB05ZRXYS7E7C5Q0KPJEF5"],"set":{"station":"01M5EB05ZRXYS7E7C5Q0KPJEF5/c20e11ed024f55b3f01f975d298bd3f8a2f81f9a8c364c121865a0829fa7c07f","key":"ember:c-7445964f07"}}]},"w":1792556412433.593}
  #|{"in":{"id":9,"delta":[{"path":["workspaces","01M5EB05ZRXYS7E7C5Q0KPJEF5","chat"],"set":{"station":"01M5EB05ZRXYS7E7C5Q0KPJEF5/c20e11ed024f55b3f01f975d298bd3f8a2f81f9a8c364c121865a0829fa7c07f","key":"ember:c-7445964f07"}}]},"w":1792556412433.611}
  #|{"in":{"id":16,"delta":[{"path":["agents",0,"threads",0,"read"],"set":2},{"path":["agents",0,"threads",0,"unread"],"set":0},{"path":["archivable"],"set":true},{"path":["thread","read"],"set":2},{"path":["thread","unread"],"set":0}]},"w":1792556412450.253}
  #|{"in":{"id":7,"delta":[{"path":["days"],"key":["daysAgo"],"patch":0,"ops":[{"path":["items"],"key":["station","id"],"patch":["01M5EB05ZRXYS7E7C5Q0KPJEF5/c20e11ed024f55b3f01f975d298bd3f8a2f81f9a8c364c121865a0829fa7c07f","ember:c-7445964f07"],"ops":[{"path":["archivable"],"set":true},{"path":["settled"],"set":true},{"path":["stateText"],"set":"已完成：answered the question that was asked"},{"path":["unread"],"set":false},{"path":["tone"],"remove":true}]}]}]},"w":1792556412450.28}
  #|{"in":{"id":9,"delta":[{"path":["workspaces","01M5EB05ZRXYS7E7C5Q0KPJEF5","unread"],"set":0},{"path":["workspaces","01M5EB05ZRXYS7E7C5Q0KPJEF5","label"],"remove":true},{"path":["workspaces","01M5EB05ZRXYS7E7C5Q0KPJEF5","mineTone"],"remove":true},{"path":["workspaces","01M5EB05ZRXYS7E7C5Q0KPJEF5","tone"],"remove":true}]},"w":1792556412450.3}
  #|{"in":{"id":18,"delta":[{"path":[0,"host"],"set":{"hostname":"3720-Mac-mini-1","os":"macOS 27.0.1","arch":"arm64","cpus":10,"cpuModel":"Apple M4","load":0.19,"cpuBusy":0.11,"uptimeSec":35774,"memory":{"totalBytes":17179869184,"usedBytes":9047916544,"swapUsedBytes":300742083},"disk":{"path":"/tmp/mbe2e-C/data","totalBytes":245107195904,"freeBytes":40509874176},"emberRssBytes":157185920,"checkedAt":1792556412426,"summary":"10 核 · 16 GB","line":"macOS 27.0.1 · 10 核 · 16 GB · 已运行 0 天","facts":["3720-Mac-mini-1","macOS 27.0.1","arm64 · 10 核","已运行 9 小时"],"meters":[{"label":"CPU","short":"CPU","percent":11,"left":89,"level":"ok","value":"11%","remaining":"空闲 89%","big":"89","unit":"%","title":"CPU 空闲","total":"负载 1.9","note":"负载 1.9 · Apple M4"},{"label":"内存","short":"内存","percent":53,"left":47,"level":"ok","value":"8.4 GB / 16.0 GB","remaining":"剩 7.6 G","big":"7.6","unit":"GB","title":"内存剩","total":"共 16 GB","note":"swap 0.3 GB"},{"label":"磁盘","short":"磁盘","percent":83,"left":17,"level":"amber","value":"剩余 37.7 GB / 228 GB","remaining":"剩 37.7 G","big":"37.7","unit":"GB","title":"磁盘剩","total":"共 228 GB"}],"identity":"Apple M4 · 16 GB · macOS 27.0.1","details":[{"label":"主机名","value":"3720-Mac-mini-1"},{"label":"芯片","value":"Apple M4 · 10 核 · arm64"},{"label":"已运行","value":"9 小时"},{"label":"still.fail","value":"进程占用 150 MB"}],"usage":"内存 8.4 GB / 16.0 GB · 磁盘 剩余 37.7 GB / 228 GB","emberText":"still.fail 150 MB"}},{"path":[0,"line"],"set":"Apple M4"},{"path":[0,"summary"],"set":"空闲 · Apple M4 · 16 GB · macOS 27.0.1"}]},"w":1792556412450.325}
  #|{"in":{"id":20,"error":{"code":"picture","message":"无法加载图片：error sending request for url (https://example.test/p.png): client error (Connect): tls handshake eof"}},"w":1792556412583.583}
  #|{"step":"answered client.focus","w":1792556412600.77}
  #|{"step":"wait 300","w":1792556412617.459}
  #|{"step":"now until =studio","w":1792556412918.268}
  #|{"step":"tap 发消息","w":1792556412918.32}
  #|{"step":"tap 发消息","acted":true,"w":1792556412918.383}
  #|{"step":"type 开个网页 201409 serve:e2e-web|19107|网页开好了 201409","w":1792556412944.035}
  #|{"step":"type 开个网页 201409 serve:e2e-web|19107|网页开好了 201409","acted":true,"w":1792556412944.113}
  #|{"out":{"id":22,"call":"session.warm","params":{"station":"01M5EB05ZRXYS7E7C5Q0KPJEF5/c20e11ed024f55b3f01f975d298bd3f8a2f81f9a8c364c121865a0829fa7c07f","key":"ember:c-7445964f07"}},"w":1792556412950.566}
  #|{"step":"tap icon:arrow-up","w":1792556412956.665}
  #|{"step":"tap icon:arrow-up","acted":true,"w":1792556412956.713}
  #|{"in":{"id":22,"ok":{"ok":true}},"w":1792556412966.949}
  #|{"out":{"id":23,"call":"chat.send","params":{"station":"01M5EB05ZRXYS7E7C5Q0KPJEF5/c20e11ed024f55b3f01f975d298bd3f8a2f81f9a8c364c121865a0829fa7c07f","text":"开个网页 201409 serve:e2e-web|19107|网页开好了 201409","attachments":[],"quotes":[],"thread":1}},"w":1792556412967.335}
  #|{"step":"answered chat.send","w":1792556412969.278}
  #|{"in":{"id":23,"ok":{"seq":3}},"w":1792556413016.927}
  #|{"step":"wait 600","w":1792556413034.045}
  #|{"in":{"id":16,"delta":[{"path":["agents",0,"jobs"],"append":[{"id":"job_e7712619","session":"ember:c-7445964f07","name":"e2e-web","state":"running","port":19107,"startedAt":1792556413023,"command":"cd '/private/tmp/mbe2e-C/data/sessions/ember/c-7445964f07/workspace/e2e-site-19107' && exec python3 -m http.server 19107 --bind 127.0.0.1","restarts":0,"notices":[],"watch":false,"tone":"up","service":true,"open":true,"ended":false,"current":true,"word":"在线","meta":[{"text":"在线","kind":"word"},{"text":" · 0 秒"}],"detail":"在线 · 0 秒","age":"0 秒"}]},{"path":["agents",0,"session","lastActiveAt"],"set":1792556413030},{"path":["agents",0,"session","lastTurn","endedAt"],"set":1792556413030},{"path":["agents",0,"session","lastTurn","id"],"set":"f32f5aeb-3923-4431-b319-4bcbef0b2bac"},{"path":["agents",0,"session","lastTurn","need"],"set":"started the service that was asked for"},{"path":["agents",0,"session","lastTurn","startedAt"],"set":1792556412975},{"path":["agents",0,"session","statusText"],"set":"已完成：started the service that was asked for"},{"path":["agents",0,"session","time","lastActiveAt","at"],"set":1792556413030},{"path":["agents",0,"session","time","lastActiveAt","full"],"set":"10/21 12:20:13"},{"path":["agents",0,"session","turns"],"set":2},{"path":["agents",0,"threads",0,"last"],"set":4},{"path":["agents",0,"threads",0,"lastMessage","createdAt"],"set":1792556413028},{"path":["agents",0,"threads",0,"lastMessage","seq"],"set":4},{"path":["agents",0,"threads",0,"lastMessage","text"],"set":"网页开好了 201409"},{"path":["agents",0,"threads",0,"lastMessage","time","createdAt","at"],"set":1792556413028},{"path":["agents",0,"threads",0,"lastMessage","time","createdAt","full"],"set":"10/21 12:20:13"},{"path":["agents",0,"threads",0,"lastMessage","ts"],"set":"1792556413.028000"},{"path":["agents",0,"threads",0,"unread"],"set":1},{"path":["agents",0,"turns"],"append":[{"id":"f32f5aeb-3923-4431-b319-4bcbef0b2bac","kind":"input","outcome":"completed","declared":"final","ending":"all_done","startedAt":1792556412975,"endedAt":1792556413030}]},{"path":["outbox"],"key":["id"],"put":{"id":"out-c31fdecfde6734e1ca","text":"开个网页 201409 serve:e2e-web|19107|网页开好了 201409","attachments":[],"quotes":[],"createdAt":1792556412968,"state":"sending","seq":3,"time":{"createdAt":{"at":1792556412968,"ago":"刚刚","full":"10/21 12:20:12","until":"1 分钟内","past":true}}},"before":null},{"path":["thread","last"],"set":4},{"path":["thread","lastMessage","createdAt"],"set":1792556413028},{"path":["thread","lastMessage","seq"],"set":4},{"path":["thread","lastMessage","text"],"set":"网页开好了 201409"},{"path":["thread","lastMessage","time","createdAt","at"],"set":1792556413028},{"path":["thread","lastMessage","time","createdAt","full"],"set":"10/21 12:20:13"},{"path":["thread","lastMessage","ts"],"set":"1792556413.028000"},{"path":["thread","unread"],"set":1},{"path":["archivable"],"remove":true}]},"w":1792556413068.488}
  #|{"in":{"id":9,"delta":[{"path":["workspaces","01M5EB05ZRXYS7E7C5Q0KPJEF5","label"],"set":"1 个有新消息"},{"path":["workspaces","01M5EB05ZRXYS7E7C5Q0KPJEF5","mineTone"],"set":"done"},{"path":["workspaces","01M5EB05ZRXYS7E7C5Q0KPJEF5","tone"],"set":"done"},{"path":["workspaces","01M5EB05ZRXYS7E7C5Q0KPJEF5","unread"],"set":1}]},"w":1792556413068.642}
  #|{"in":{"id":7,"delta":[{"path":["days"],"key":["daysAgo"],"patch":0,"ops":[{"path":["at"],"set":1792556413028},{"path":["items"],"key":["station","id"],"patch":["01M5EB05ZRXYS7E7C5Q0KPJEF5/c20e11ed024f55b3f01f975d298bd3f8a2f81f9a8c364c121865a0829fa7c07f","ember:c-7445964f07"],"ops":[{"path":["agents",0,"lastTurn","endedAt"],"set":1792556413030},{"path":["agents",0,"lastTurn","id"],"set":"f32f5aeb-3923-4431-b319-4bcbef0b2bac"},{"path":["agents",0,"lastTurn","need"],"set":"started the service that was asked for"},{"path":["agents",0,"lastTurn","startedAt"],"set":1792556412975},{"path":["agents",0,"statusText"],"set":"已完成：started the service that was asked for"},{"path":["last","createdAt"],"set":1792556413028},{"path":["last","preview"],"set":"网页开好了 201409"},{"path":["last","seq"],"set":4},{"path":["last","text"],"set":"网页开好了 201409"},{"path":["last","time","createdAt","at"],"set":1792556413028},{"path":["last","time","createdAt","full"],"set":"10/21 12:20:13"},{"path":["lastActiveAt"],"set":1792556413028},{"path":["time","lastActiveAt","at"],"set":1792556413028},{"path":["time","lastActiveAt","full"],"set":"10/21 12:20:13"},{"path":["tone"],"set":"done"},{"path":["unread"],"set":true},{"path":["archivable"],"remove":true},{"path":["settled"],"remove":true},{"path":["stateText"],"remove":true}]}]}]},"w":1792556413068.677}
  #|{"in":{"id":18,"delta":[{"path":[0,"overview","disk","freeBytes"],"set":40508510208}]},"w":1792556413068.74}
  #|{"in":{"id":19,"delta":[{"path":["allText"],"set":"全部 1 个"},{"path":["current"],"set":1},{"path":["jobs"],"append":[{"id":"job_e7712619","session":"ember:c-7445964f07","name":"e2e-web","state":"running","port":19107,"startedAt":1792556413023,"command":"cd '/private/tmp/mbe2e-C/data/sessions/ember/c-7445964f07/workspace/e2e-site-19107' && exec python3 -m http.server 19107 --bind 127.0.0.1","restarts":0,"notices":[],"watch":false,"tone":"up","service":true,"open":true,"ended":false,"current":true,"word":"在线","meta":[{"text":"在线","kind":"word"},{"text":" · 0 秒"}],"detail":"在线 · 0 秒","age":"0 秒"}]},{"path":["servicesNote"],"set":"1 个在线"}]},"w":1792556413233.62}
  #|{"in":{"id":16,"delta":[{"path":["messages"],"key":["seq","outgoing"],"put":{"seq":4,"thread":1,"ts":"1792556413.028000","authorKind":"agent","author":"ember:c-7445964f07","text":"网页开好了 201409","attachments":[],"quotes":[],"declared":"final","ending":"all_done","createdAt":1792556413028,"mine":false,"system":false,"by":{"name":"默认模型","agent":"ember:c-7445964f07","runtime":"claude","here":true},"waiting":false,"said":true,"time":{"createdAt":{"at":1792556413028,"ago":"刚刚","full":"10/21 12:20:13","until":"1 分钟内","past":true}}},"before":null},{"path":["messages"],"key":["seq","outgoing"],"put":{"outgoing":"out-c31fdecfde6734e1ca","seq":3,"thread":1,"ts":"1792556412.972000","authorKind":"person","author":"alice@example.test","authorName":"Name of alice","text":"开个网页 201409 serve:e2e-web|19107|网页开好了 201409","attachments":[],"quotes":[],"createdAt":1792556412972,"mine":true,"system":false,"by":{"name":"Name of alice","picture":"https://example.test/p.png"},"waiting":false,"said":true,"time":{"createdAt":{"at":1792556412972,"ago":"刚刚","full":"10/21 12:20:12","until":"1 分钟内","past":true}}},"before":[4,null]},{"path":["outbox"],"key":["id"],"drop":"out-c31fdecfde6734e1ca"}]},"w":1792556413233.694}
  #|{"in":{"id":16,"delta":[{"path":["agents",0,"threads",0,"read"],"set":4},{"path":["agents",0,"threads",0,"unread"],"set":0},{"path":["archivable"],"set":true},{"path":["thread","read"],"set":4},{"path":["thread","unread"],"set":0}]},"w":1792556413383.628}
  #|{"in":{"id":7,"delta":[{"path":["days"],"key":["daysAgo"],"patch":0,"ops":[{"path":["items"],"key":["station","id"],"patch":["01M5EB05ZRXYS7E7C5Q0KPJEF5/c20e11ed024f55b3f01f975d298bd3f8a2f81f9a8c364c121865a0829fa7c07f","ember:c-7445964f07"],"ops":[{"path":["archivable"],"set":true},{"path":["settled"],"set":true},{"path":["stateText"],"set":"已完成：started the service that was asked for"},{"path":["unread"],"set":false},{"path":["tone"],"remove":true}]}]}]},"w":1792556413383.724}
  #|{"in":{"id":9,"delta":[{"path":["workspaces","01M5EB05ZRXYS7E7C5Q0KPJEF5","unread"],"set":0},{"path":["workspaces","01M5EB05ZRXYS7E7C5Q0KPJEF5","label"],"remove":true},{"path":["workspaces","01M5EB05ZRXYS7E7C5Q0KPJEF5","mineTone"],"remove":true},{"path":["workspaces","01M5EB05ZRXYS7E7C5Q0KPJEF5","tone"],"remove":true}]},"w":1792556413384.084}
  #|{"step":"now gone 正在发送","w":1792556413635.32}
  #|{"step":"untiln 2 网页开好了 201409","w":1792556413635.361}
  #|{"step":"tap icon:web","w":1792556413635.388}
  #|{"step":"tap icon:web","acted":true,"w":1792556413635.42}
  #|{"step":"until 服务","w":1792556413666.034}
  #|{"step":"tap 在线","w":1792556413685.255}
  #|{"step":"tap 在线","acted":true,"w":1792556413719.406}
  #|{"out":{"id":24,"subscribe":{"topic":"job","station":"01M5EB05ZRXYS7E7C5Q0KPJEF5/c20e11ed024f55b3f01f975d298bd3f8a2f81f9a8c364c121865a0829fa7c07f","id":"job_e7712619"},"keyed":true},"w":1792556413735.161}
  #|{"step":"until 自适应","w":1792556413739.525}
  #|{"in":{"id":19,"delta":[{"path":["jobs",0,"age"],"set":"1 秒"},{"path":["jobs",0,"detail"],"set":"在线 · 1 秒"},{"path":["jobs",0,"meta",1,"text"],"set":" · 1 秒"}]},"w":1792556413750.302}
  #|{"in":{"id":24,"value":{"id":"job_e7712619","session":"ember:c-7445964f07","name":"e2e-web","state":"running","port":19107,"startedAt":1792556413023,"command":"cd '/private/tmp/mbe2e-C/data/sessions/ember/c-7445964f07/workspace/e2e-site-19107' && exec python3 -m http.server 19107 --bind 127.0.0.1","restarts":0,"notices":[],"watch":false,"tone":"up","service":true,"open":true,"ended":false,"current":true,"word":"在线","meta":[{"text":"在线","kind":"word"},{"text":" · 1 秒"}],"detail":"在线 · 1 秒","age":"1 秒"}},"w":1792556413750.398}
  #|{"out":{"id":25,"subscribe":{"topic":"previewLoad","station":"01M5EB05ZRXYS7E7C5Q0KPJEF5/c20e11ed024f55b3f01f975d298bd3f8a2f81f9a8c364c121865a0829fa7c07f","port":19107},"keyed":true},"w":1792556413828.68}
  #|{"info":{"view":1,"state":0,"at":[-1,0,0,0,0,0,0,0,0,0]},"w":1792556413831.22}
  #|{"sitestate":{"view":1,"state":{"path":"/","loading":true,"title":"","forward":false,"back":false}},"w":1792556413831.263}
  #|{"in":{"id":25,"value":{"percent":0,"total":0,"finished":0,"failed":0,"resources":[]}},"w":1792556413833.605}
  #|{"step":"answered station.preview","w":1792556413845.576}
  #|{"site":{"view":1,"event":{"req":1,"path":"/","method":"GET","headers":[["User-Agent","Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)"],["Upgrade-Insecure-Requests","1"],["Accept","text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"]],"page":true}},"w":1792556413901.072}
  #|{"out":{"id":26,"call":"station.preview","params":{"station":"01M5EB05ZRXYS7E7C5Q0KPJEF5/c20e11ed024f55b3f01f975d298bd3f8a2f81f9a8c364c121865a0829fa7c07f","port":19107,"method":"GET","path":"/","headers":[["User-Agent","Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)"],["Upgrade-Insecure-Requests","1"],["Accept","text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"]],"stream":true}},"w":1792556413901.092}
  #|{"in":{"id":26,"value":{"head":{"status":200,"headers":[["server","SimpleHTTP/0.6 Python/3.14.5"],["date","Wed, 21 Oct 2026 04:20:13 GMT"],["content-type","text/html"],["content-length","457"],["last-modified","Wed, 21 Oct 2026 04:20:12 GMT"],["stillfail-idempotent","1"]]}}},"w":1792556413916.948}
  #|{"in":{"id":26,"value":{"chunk":true}},"w":1792556413917.113,"b":"3c21646f63747970652068746d6c3e3c68746d6c3e3c686561643e3c6d65746120636861727365743d227574662d38223e3c6d657461206e616d653d2276696577706f72742220636f6e74656e743d2277696474683d6465766963652d77696474682c696e697469616c2d7363616c653d31223e0a3c7469746c653ee7abafe588b0e7abafe6b58be8af95e69c8de58aa13c2f7469746c653e3c6c696e6b2072656c3d227374796c6573686565742220687265663d227374796c652e637373223e3c2f686561643e3c626f64793e3c68313ee7abafe588b0e7abafe6b58be8af95e69c8de58aa13c2f68313e0a3c702069643d226e223ee8849ae69cace8bf98e6b2a1e69c89e8bf90e8a18c3c2f703e3c703e3c6120687265663d22622e68746d6c223ee58ebbe7acace4ba8ce9a1b53c2f613e3c2f703e0a3c7363726970743e66657463682827646174612e6a736f6e27292e7468656e28723d3e722e6a736f6e2829292e7468656e28643d3e7b646f63756d656e742e676574456c656d656e744279496428276e27292e74657874436f6e74656e743d27e8849ae69cace5b7b2e8bf90e8a18cefbc9a272b642e6e7d293c2f7363726970743e3c2f626f64793e3c2f68746d6c3e"}
  #|{"in":{"id":26,"ok":null},"w":1792556413917.138}
  #|{"site":{"view":1,"event":{"req":2,"path":"/_stillfail/page.js","method":"GET","headers":[["User-Agent","Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)"],["Accept","*/*"]],"page":false}},"w":1792556413934.086}
  #|{"site":{"view":1,"event":{"req":3,"path":"/style.css","method":"GET","headers":[["User-Agent","Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)"],["Accept","text/css,*/*;q=0.1"]],"page":false}},"w":1792556413934.512}
  #|{"out":{"id":27,"call":"station.preview","params":{"station":"01M5EB05ZRXYS7E7C5Q0KPJEF5/c20e11ed024f55b3f01f975d298bd3f8a2f81f9a8c364c121865a0829fa7c07f","port":19107,"method":"GET","path":"/style.css","headers":[["User-Agent","Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)"],["Accept","text/css,*/*;q=0.1"]],"stream":true}},"w":1792556413934.528}
  #|{"step":"answered station.preview","w":1792556413934.766}
  #|{"in":{"id":27,"value":{"head":{"status":200,"headers":[["server","SimpleHTTP/0.6 Python/3.14.5"],["date","Wed, 21 Oct 2026 04:20:13 GMT"],["content-type","text/css"],["content-length","110"],["last-modified","Wed, 21 Oct 2026 04:20:12 GMT"],["stillfail-idempotent","1"]]}}},"w":1792556413950.283}
  #|{"in":{"id":27,"value":{"chunk":true}},"w":1792556413950.425,"b":"626f64797b6d617267696e3a303b70616464696e673a323470783b666f6e742d66616d696c793a73797374656d2d75692c73616e732d73657269663b6261636b67726f756e643a236662653664633b636f6c6f723a233234323732627d68317b636f6c6f723a236239343731667d"}
  #|{"in":{"id":27,"ok":null},"w":1792556413950.438}
  #|{"site":{"view":1,"event":{"said":"{\"p\":\"page\"}"}},"w":1792556413951.006}
  #|{"sitestate":{"view":1,"state":{"path":"/","loading":true,"title":"端到端测试服务","forward":false,"back":false}},"w":1792556413951.239}
  #|{"info":{"view":1,"state":1,"at":[-1,0,0,0,0,0,1,0,0,0]},"w":1792556413966.916}
  #|{"site":{"view":1,"event":{"req":4,"path":"/data.json","method":"GET","headers":[["Referer","stillfail-preview://svc/"],["Accept","*/*"],["User-Agent","Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)"]],"page":false}},"w":1792556413967.611}
  #|{"out":{"id":28,"call":"station.preview","params":{"station":"01M5EB05ZRXYS7E7C5Q0KPJEF5/c20e11ed024f55b3f01f975d298bd3f8a2f81f9a8c364c121865a0829fa7c07f","port":19107,"method":"GET","path":"/data.json","headers":[["Referer","stillfail-preview://svc/"],["Accept","*/*"],["User-Agent","Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)"]],"stream":true}},"w":1792556413967.667}
  #|{"sitestate":{"view":1,"state":{"path":"/","loading":false,"title":"端到端测试服务","forward":false,"back":false}},"w":1792556413967.737}
  #|{"step":"answered station.preview","w":1792556413968.086}
  #|{"in":{"id":25,"value":{"percent":66,"total":3,"finished":2,"failed":0,"resources":[{"id":1,"method":"GET","path":"/","since":1792556413901.22,"status":200,"ended":1792556413905.674,"error":null},{"id":2,"method":"GET","path":"/style.css","since":1792556413934.634,"status":200,"ended":1792556413936.933,"error":null},{"id":3,"method":"GET","path":"/data.json","since":1792556413967.941,"status":null,"ended":null,"error":null}]}},"w":1792556413983.597}
  #|{"in":{"id":28,"value":{"head":{"status":200,"headers":[["server","SimpleHTTP/0.6 Python/3.14.5"],["date","Wed, 21 Oct 2026 04:20:13 GMT"],["content-type","application/json"],["content-length","8"],["last-modified","Wed, 21 Oct 2026 04:20:12 GMT"],["stillfail-idempotent","1"]]}}},"w":1792556413983.614}
  #|{"in":{"id":28,"value":{"chunk":true}},"w":1792556413983.693,"b":"7b226e223a34327d"}
  #|{"in":{"id":28,"ok":null},"w":1792556413983.712}
  #|{"step":"tap icon:web","w":1792556414000.857}
  #|{"step":"tap icon:web","acted":true,"w":1792556414000.876}
  #|{"step":"field /","w":1792556414017.557}
  #|{"step":"clear","w":1792556414017.563}
  #|{"step":"clear","acted":true,"w":1792556414017.573}
  #|{"step":"type /b.html","w":1792556414034.062}
  #|{"step":"type /b.html","acted":true,"w":1792556414034.069}
  #|{"step":"enter","w":1792556414050.922}
  #|{"step":"enter","acted":true,"w":1792556414050.933}
  #|{"sitestate":{"view":1,"state":{"path":"/b.html","loading":true,"title":"端到端测试服务","forward":false,"back":false}},"w":1792556414067.309}
  #|{"step":"answered station.preview","w":1792556414067.431}
  #|{"in":{"id":25,"delta":[{"path":["finished"],"set":3},{"path":["percent"],"set":100},{"path":["resources",2,"ended"],"set":1792556413972.113},{"path":["resources",2,"status"],"set":200}]},"w":1792556414083.596}
  #|{"site":{"view":1,"event":{"req":5,"path":"/b.html","method":"GET","headers":[["User-Agent","Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)"],["Upgrade-Insecure-Requests","1"],["Accept","text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"]],"page":true}},"w":1792556414083.954}
  #|{"out":{"id":29,"call":"station.preview","params":{"station":"01M5EB05ZRXYS7E7C5Q0KPJEF5/c20e11ed024f55b3f01f975d298bd3f8a2f81f9a8c364c121865a0829fa7c07f","port":19107,"method":"GET","path":"/b.html","headers":[["User-Agent","Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)"],["Upgrade-Insecure-Requests","1"],["Accept","text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"]],"stream":true}},"w":1792556414083.976}
  #|{"in":{"id":29,"value":{"head":{"status":200,"headers":[["server","SimpleHTTP/0.6 Python/3.14.5"],["date","Wed, 21 Oct 2026 04:20:14 GMT"],["content-type","text/html"],["content-length","165"],["last-modified","Wed, 21 Oct 2026 04:20:12 GMT"],["stillfail-idempotent","1"]]}}},"w":1792556414100.275}
  #|{"in":{"id":29,"value":{"chunk":true}},"w":1792556414100.41,"b":"3c21646f63747970652068746d6c3e3c68746d6c3e3c686561643e3c6d65746120636861727365743d227574662d38223e3c7469746c653ee7acace4ba8ce9a1b53c2f7469746c653e3c6c696e6b2072656c3d227374796c6573686565742220687265663d227374796c652e637373223e3c2f686561643e0a3c626f64793e3c68313ee8bf99e698afe7acace4ba8ce9a1b53c2f68313e3c2f626f64793e3c2f68746d6c3e"}
  #|{"in":{"id":29,"ok":null},"w":1792556414100.429}
  #|{"site":{"view":1,"event":{"req":6,"path":"/_stillfail/page.js","method":"GET","headers":[["User-Agent","Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)"],["Accept","*/*"]],"page":false}},"w":1792556414117.117}
  #|{"sitestate":{"view":1,"state":{"path":"/b.html","loading":true,"title":"","forward":false,"back":true}},"w":1792556414117.36}
  #|{"step":"tap icon:arrow-left","w":1792556414117.491}
  #|{"step":"tap icon:arrow-left","acted":true,"w":1792556414117.501}
  #|{"site":{"view":1,"event":{"said":"{\"p\":\"page\"}"}},"w":1792556414133.803}
  #|{"sitestate":{"view":1,"state":{"path":"/b.html","loading":false,"title":"第二页","forward":false,"back":true}},"w":1792556414133.834}
  #|{"step":"gone /b.html","w":1792556414133.953}
  #|{"step":"tap 手机","w":1792556414133.961}
  #|{"step":"tap 手机","acted":true,"w":1792556414133.975}
  #|{"step":"back","w":1792556414151.852}
  #|{"step":"back","acted":true,"w":1792556414151.859}
  #|{"step":"until 网页开好了 201409","w":1792556414167.918}
  #|{"step":"","w":1792556414236.547}
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
  #|{"textrec":{"ib":["d61ec6305f7d8c8b",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["182b7158e0c0cae1",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["8bf9607b651cec61",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"m":[16,400,0],"r":[15.46875,3.375,23,15.46875,3.375,0]}}
  #|{"textrec":{"s":[8,600,0,"N"],"r":[0,1,6.271738052368164,63]}}
  #|{"textrec":{"m":[8,600,0],"r":[7.734375,1.6875,11,7.734375,1.6875,0]}}
  #|{"textrec":{"s":[13,500,0,"以下是新消息"],"r":[0,1,12.898832684824903,64,1,1,12.898832684824903,65,2,1,12.898832684824903,66,3,1,12.898832684824903,67,4,1,12.898832684824896,68,5,1,12.898832684824896,69]}}
  #|{"textrec":{"m":[13,500,0],"r":[12.568359375,2.7421875,18,12.568359375,2.7421875,0]}}
  #|{"textrec":{"s":[15,650,0,"默认模型"],"r":[0,1,14.883268482490273,70,1,1,14.883268482490273,71,2,1,14.883268482490273,72,3,1,14.883268482490273,73]}}
  #|{"textrec":{"m":[15,650,0],"r":[14.501953125,3.1640625,21,14.501953125,3.1640625,0]}}
  #|{"textrec":{"s":[10,400,0,"刚刚"],"r":[0,1,9.941634241245136,74,1,1,9.941634241245136,74]}}
  #|{"textrec":{"m":[10,400,0],"r":[9.66796875,2.109375,14,9.66796875,2.109375,0]}}
  #|{"textrec":{"s":[15,400,0,"你好，我是测试用的 agent"],"r":[0,1,14.883268482490273,75,1,1,14.883268482490273,76,2,1,15.087548638132297,77,3,1,14.883268482490273,78,4,1,14.883268482490266,79,5,1,14.88326848249028,80,6,1,14.88326848249028,81,7,1,14.88326848249028,82,8,1,14.88326848249028,83,9,1,3.984375,-1,10,1,8.0419921875,84,11,1,8.90625,85,12,1,8.3349609375,86,13,1,8.51806640625,87,14,1,5.21484375,88]}}
  #|{"textrec":{"s":[16,400,0,"端到端测试的对话 post:你好，我是测试用的 agent"],"r":[0,1,15.875486381322958,89,1,1,15.875486381322958,90,2,1,15.875486381322958,89,3,1,15.875486381322958,91,4,1,15.875486381322958,92,5,1,15.875486381322958,93,6,1,15.875486381322958,94,7,1,15.875486381322958,95,8,1,4.1875,-1,9,1,9.453125,96,10,1,9.140625,97,11,1,8.0234375,98,12,1,5.4609375,99,13,1,4.4375,100,14,1,15.875486381322958,101,15,1,15.875486381322958,102,16,1,16.09338521400778,103,17,1,15.875486381322958,104,18,1,15.875486381322958,105,19,1,15.87548638132293,91,20,1,15.875486381322958,92,21,1,15.875486381322958,106,22,1,15.875486381322958,93,23,1,4.1875,-1,24,1,8.515625,107,25,1,9.4375,108,26,1,8.828125,109,27,1,9.0234375,110,28,1,5.5,99]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 post:你好…"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,26,3,1,15.875486381322958,28,4,1,15.875486381322958,29,5,1,15.875486381322958,30,6,1,15.875486381322958,31,7,1,15.875486381322958,32,8,1,3.95001220703125,-1,9,1,9.824199676513672,33,10,1,9.432537078857422,34,11,1,8.471200942993164,35,12,1,5.973020553588867,36,13,1,4.952056884765625,37,14,1,15.875486381322958,38,15,1,15.875486381322958,39,16,1,14.076484680175781,62]}}
  #|{"textrec":{"ib":["504a4df6beac534a",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"s":[12,400,0,"studio"],"r":[0,1,6.251953125,111,1,1,4.330078125,112,2,1,7.001953125,113,3,1,7.37109375,114,4,1,2.96484375,115,5,1,7.08984375,116]}}
  #|{"textrec":{"m":[12,400,0],"r":[11.6015625,2.53125,17,11.6015625,2.53125,0]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 post:…"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,26,3,1,15.875486381322958,28,4,1,15.875486381322958,29,5,1,15.875486381322958,30,6,1,15.875486381322958,31,7,1,15.875486381322958,32,8,1,3.95001220703125,-1,9,1,9.824199676513672,33,10,1,9.432537078857422,34,11,1,8.471200942993164,35,12,1,5.973020553588867,36,13,1,4.952056884765625,37,14,1,14.076484680175781,62]}}
  #|{"textrec":{"g":75,"r":[666,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":76,"r":[683,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":77,"r":[700,0,5,7,0,-3,0]}}
  #|{"textrec":{"g":78,"r":[706,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":79,"r":[724,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":80,"r":[741,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":81,"r":[758,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":82,"r":[776,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":83,"r":[792,0,15,17,0,-14,0]}}
  #|{"textrec":{"g":84,"r":[808,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":85,"r":[819,0,10,14,-1,-10,0]}}
  #|{"textrec":{"g":86,"r":[830,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":87,"r":[841,0,9,11,0,-10,0]}}
  #|{"textrec":{"g":88,"r":[851,0,7,13,-1,-11,0]}}
  #|{"textrec":{"ib":["a1e7be43eb966606",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"ib":["11ba9484460f477d",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["c7a6d30e254a5910",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"g":89,"r":[859,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":90,"r":[877,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":91,"r":[895,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":92,"r":[913,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":93,"r":[932,0,16,17,0,-14,0]}}
  #|{"textrec":{"g":94,"r":[949,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":95,"r":[967,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":96,"r":[986,0,10,14,0,-10,0]}}
  #|{"textrec":{"g":97,"r":[997,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":98,"r":[1009,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":99,"r":[1020,0,8,14,-1,-12,0]}}
  #|{"textrec":{"g":100,"r":[1029,0,5,11,0,-9,0]}}
  #|{"textrec":{"g":101,"r":[1035,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":102,"r":[1053,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":103,"r":[1071,0,6,7,0,-3,0]}}
  #|{"textrec":{"g":104,"r":[1078,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":105,"r":[1096,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":106,"r":[1114,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":107,"r":[1131,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":108,"r":[1142,0,11,14,-1,-10,0]}}
  #|{"textrec":{"g":109,"r":[1154,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":110,"r":[1166,0,10,11,0,-10,0]}}
  #|{"textrec":{"g":70,"r":[1177,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":71,"r":[1195,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":72,"r":[1213,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":73,"r":[1231,0,16,16,-1,-13,0]}}
  #|{"textrec":{"s":[16,400,0,"发消息"],"r":[0,1,15.875486381322958,117,1,1,15.875486381322958,118,2,1,15.875486381322958,119]}}
  #|{"textrec":{"g":117,"r":[1248,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":118,"r":[1266,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":119,"r":[1284,0,17,17,-1,-14,0]}}
  #|{"textrec":{"s":[12,500,0,"归档"],"r":[0,1,11.918287937743191,120,1,1,11.918287937743191,121]}}
  #|{"textrec":{"m":[12,500,0],"r":[11.6015625,2.53125,17,11.6015625,2.53125,0]}}
  #|{"textrec":{"s":[14,400,0,"answered the question that was asked"],"r":[0,1,7.57421875,57,1,1,8.0185546875,60,2,1,7.0751953125,122,3,1,10.4521484375,123,4,1,7.7109375,59,5,1,5.0791015625,124,6,1,7.7451171875,59,7,1,8.44921875,125,8,1,3.787109375,-1,9,1,4.935546875,61,10,1,8.0869140625,126,11,1,7.84765625,59,12,1,3.787109375,-1,13,1,8.380859375,127,14,1,8.0185546875,128,15,1,7.84765625,59,16,1,7.1435546875,122,17,1,4.9013671875,61,18,1,3.30859375,129,19,1,8.12109375,130,20,1,8.0185546875,60,21,1,3.787109375,-1,22,1,4.935546875,61,23,1,8.0869140625,126,24,1,7.57421875,57,25,1,4.935546875,61,26,1,3.787109375,-1,27,1,10.5888671875,123,28,1,7.4716796875,57,29,1,7.177734375,122,30,1,3.787109375,-1,31,1,7.57421875,57,32,1,7.177734375,122,33,1,7.2802734375,131,34,1,7.6767578125,59,35,1,8.44921875,125]}}
  #|{"textrec":{"s":[16,400,0,"…"],"r":[0,1,12.5625,132]}}
  #|{"textrec":{"s":[16,400,0,"端到端测试的对话 post:你好，我是测试…"],"r":[0,1,15.875486381322958,89,1,1,15.875486381322958,90,2,1,15.875486381322958,89,3,1,15.875486381322958,91,4,1,15.875486381322958,92,5,1,15.875486381322958,93,6,1,15.875486381322958,94,7,1,15.875486381322958,95,8,1,4.1875,-1,9,1,9.453125,96,10,1,9.140625,97,11,1,8.0234375,98,12,1,5.4609375,99,13,1,4.4375,100,14,1,15.875486381322958,101,15,1,15.875486381322958,102,16,1,16.09338521400778,103,17,1,15.875486381322958,104,18,1,15.875486381322958,105,19,1,15.87548638132293,91,20,1,15.875486381322958,92,21,1,12.5625,132]}}
  #|{"textrec":{"g":132,"r":[1302,0,13,5,0,-3,0]}}
  #|{"textrec":{"g":122,"r":[1316,0,9,11,-1,-9,0]}}
  #|{"textrec":{"g":123,"r":[1326,0,13,10,-1,-9,0]}}
  #|{"textrec":{"g":124,"r":[1340,0,6,10,0,-9,0]}}
  #|{"textrec":{"g":125,"r":[1347,0,10,14,-1,-12,0]}}
  #|{"textrec":{"g":126,"r":[1358,0,9,13,0,-12,0]}}
  #|{"textrec":{"g":127,"r":[1368,0,10,13,-1,-9,0]}}
  #|{"textrec":{"g":128,"r":[1379,0,9,11,0,-9,0]}}
  #|{"textrec":{"g":129,"r":[1389,0,5,13,-1,-12,0]}}
  #|{"textrec":{"g":130,"r":[1395,0,10,11,-1,-9,0]}}
  #|{"textrec":{"g":131,"r":[1406,0,9,13,0,-12,0]}}
  #|{"textrec":{"g":74,"r":[1416,0,11,11,-1,-9,0]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 post…"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,26,3,1,15.875486381322958,28,4,1,15.875486381322958,29,5,1,15.875486381322958,30,6,1,15.875486381322958,31,7,1,15.875486381322958,32,8,1,3.95001220703125,-1,9,1,9.824199676513672,33,10,1,9.432537078857422,34,11,1,8.471200942993164,35,12,1,5.973020553588867,36,13,1,14.076484680175781,62]}}
  #|{"textrec":{"g":64,"r":[1428,0,14,15,0,-12,0]}}
  #|{"textrec":{"g":65,"r":[1443,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":66,"r":[1458,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":67,"r":[1473,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":68,"r":[1489,0,14,15,-1,-12,0]}}
  #|{"textrec":{"g":69,"r":[1504,0,15,15,-1,-12,0]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 pos…"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,26,3,1,15.875486381322958,28,4,1,15.875486381322958,29,5,1,15.875486381322958,30,6,1,15.875486381322958,31,7,1,15.875486381322958,32,8,1,3.95001220703125,-1,9,1,9.824199676513672,33,10,1,9.432537078857422,34,11,1,8.497894287109375,35,12,1,14.076484680175781,62]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 po…"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,26,3,1,15.875486381322958,28,4,1,15.875486381322958,29,5,1,15.875486381322958,30,6,1,15.875486381322958,31,7,1,15.875486381322958,32,8,1,3.95001220703125,-1,9,1,9.824199676513672,33,10,1,9.329673767089844,34,11,1,13.973621368408203,133]}}
  #|{"textrec":{"g":133,"r":[1520,0,14,6,-0.10286331176757812,-4,0]}}
  #|{"textrec":{"g":63,"r":[1535,0,8,8,-1,-7,0]}}
  #|{"textrec":{"g":111,"r":[1544,0,8,10,-1,-8,0]}}
  #|{"textrec":{"g":112,"r":[1553,0,6,11,-1,-9,0]}}
  #|{"textrec":{"g":113,"r":[1560,0,9,10,-1,-8,0]}}
  #|{"textrec":{"g":114,"r":[1570,0,9,12,-1,-10,0]}}
  #|{"textrec":{"g":115,"r":[1580,0,5,11,-1,-10,0]}}
  #|{"textrec":{"g":116,"r":[1586,0,9,10,-1,-8,0]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 p…"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,26,3,1,15.875486381322958,28,4,1,15.875486381322958,29,5,1,15.875486381322958,30,6,1,15.875486381322958,31,7,1,15.875486381322958,32,8,1,3.95001220703125,-1,9,1,9.721336364746094,33,10,1,13.973621368408203,133]}}
  #|{"textrec":{"ib":["5011346a34665c45",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["b277602c41d156e7",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"ib":["ddfdc2820df8a676",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"s":[16,400,0,"开个网页 201409 serve:e2e-web|19107|网页开好了 201409"],"r":[0,1,15.875486381322958,134,1,1,15.875486381322958,135,2,1,15.875486381322958,136,3,1,15.875486381322958,137,4,1,4.1875,-1,5,1,9.34375,138,6,1,9.765625,139,7,1,7.109375,140,8,1,9.984375,141,9,1,9.765625,139,10,1,9.875,142,11,1,4.1875,-1,12,1,8.0625,98,13,1,8.828125,109,14,1,5.8203125,143,15,1,8.2421875,144,16,1,8.671875,109,17,1,4.4375,100,18,1,8.828125,109,19,1,9.3046875,138,20,1,8.7890625,109,21,1,7.15625,145,22,1,11.84375,146,23,1,8.671875,109,24,1,9.515625,147,25,1,3.828125,148,26,1,7.109375,140,27,1,9.875,142,28,1,7.109375,140,29,1,9.609375,139,30,1,8.640625,149,31,1,5.828125,148,32,1,15.875486381322958,136,33,1,15.875486381322958,137,34,1,15.875486381322958,134,35,1,15.875486381322958,102,36,1,15.875486381322958,150,37,1,4.1875,-1,38,1,9.34375,138,39,1,9.765625,139,40,1,7.109375,140,41,1,9.984375,141,42,1,9.765625,139,43,1,9.875,142]}}
  #|{"textrec":{"g":134,"r":[1596,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":135,"r":[1614,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":136,"r":[1633,0,16,17,0,-14,0]}}
  #|{"textrec":{"g":137,"r":[1650,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":138,"r":[1668,0,10,14,0,-13,0]}}
  #|{"textrec":{"g":139,"r":[1679,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":140,"r":[1691,0,7,14,0,-13,0]}}
  #|{"textrec":{"g":141,"r":[1699,0,12,14,-1,-13,0]}}
  #|{"textrec":{"g":142,"r":[1712,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":143,"r":[1724,0,7,11,0,-10,0]}}
  #|{"textrec":{"g":144,"r":[1732,0,11,11,-1,-10,0]}}
  #|{"textrec":{"g":145,"r":[1744,0,8,5,0,-7,0]}}
  #|{"textrec":{"g":146,"r":[1753,0,14,11,-1,-10,0]}}
  #|{"textrec":{"g":147,"r":[1768,0,10,15,0,-13,0]}}
  #|{"textrec":{"g":148,"r":[1779,0,4,17,0,-13,0]}}
  #|{"textrec":{"g":149,"r":[1784,0,11,14,-1,-13,0]}}
  #|{"textrec":{"g":150,"r":[1796,0,15,16,0,-13,0]}}
  #|{"textrec":{"ib":["9699dbc96b0fdfd9",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"s":[10,400,0,"正在发送"],"r":[0,1,9.941634241245136,151,1,1,9.941634241245136,152,2,1,9.941634241245136,153,3,1,9.941634241245136,154]}}
  #|{"textrec":{"g":151,"r":[1812,0,12,11,-1,-9,0]}}
  #|{"textrec":{"g":152,"r":[1825,0,12,13,-1,-10,0]}}
  #|{"textrec":{"g":153,"r":[1838,0,12,13,-1,-10,0]}}
  #|{"textrec":{"g":154,"r":[1851,0,12,13,-1,-10,0]}}
  #|{"textrec":{"s":[15,400,0,"网页开好了 201409"],"r":[0,1,14.883268482490273,155,1,1,14.883268482490273,156,2,1,14.883268482490273,157,3,1,14.883268482490273,76,4,1,14.88326848249028,158,5,1,3.984375,-1,6,1,8.818359375,159,7,1,9.2138671875,160,8,1,6.7236328125,161,9,1,9.4189453125,162,10,1,9.2138671875,160,11,1,9.31640625,163]}}
  #|{"textrec":{"g":155,"r":[1864,0,15,16,0,-13,0]}}
  #|{"textrec":{"g":156,"r":[1880,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":157,"r":[1897,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":158,"r":[1914,0,14,16,0,-13,0]}}
  #|{"textrec":{"g":159,"r":[1929,0,10,13,0,-12,0]}}
  #|{"textrec":{"g":160,"r":[1940,0,11,14,-1,-12,0]}}
  #|{"textrec":{"g":161,"r":[1952,0,8,13,-1,-12,0]}}
  #|{"textrec":{"g":162,"r":[1961,0,11,13,-1,-12,0]}}
  #|{"textrec":{"g":163,"r":[1973,0,11,14,-1,-12,0]}}
  #|{"textrec":{"ib":["6edfe1df9cdd87a7",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话…"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,26,3,1,15.875486381322958,28,4,1,15.875486381322958,29,5,1,15.875486381322958,30,6,1,15.875486381322958,31,7,1,15.875486381322958,32,8,1,14.076484680175781,62]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对…"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,26,3,1,15.875486381322958,28,4,1,15.875486381322958,29,5,1,15.875486381322958,30,6,1,15.875486381322958,31,7,1,14.076484680175781,62]}}
  #|{"textrec":{"s":[17,700,0,"服务和后台任务"],"r":[0,1,16.851167315175097,164,1,1,16.851167315175097,165,2,1,16.851167315175097,166,3,1,16.851167315175097,167,4,1,16.851167315175104,168,5,1,16.851167315175104,169,6,1,16.851167315175104,165]}}
  #|{"textrec":{"m":[17,700,0],"r":[16.435546875,3.5859375,24,16.435546875,3.5859375,0]}}
  #|{"textrec":{"s":[13,400,0,"服务 · 1 个在线"],"r":[0,1,12.898832684824903,170,1,1,12.898832684824903,171,2,1,3.580078125,-1,3,1,6.228545204222122,172,4,1,3.580078125,-1,5,1,5.9541015625,173,6,1,3.580078125,-1,7,1,12.898832684824903,174,8,1,12.898832684824896,1,9,1,12.898832684824896,175]}}
  #|{"textrec":{"s":[15,500,0,"e2e-web"],"r":[0,1,8.497450947761536,176,1,1,9.006001353263855,177,2,1,8.467544317245483,176,3,1,6.817265152931213,178,4,1,11.535433530807495,179,5,1,8.344252109527588,176,6,1,9.183611869812012,180]}}
  #|{"textrec":{"m":[15,500,0],"r":[14.501953125,3.1640625,21,14.501953125,3.1640625,0]}}
  #|{"textrec":{"m":[12.5,400,0],"r":[12.0849609375,2.63671875,18,12.0849609375,2.63671875,0]}}
  #|{"textrec":{"s":[12.5,400,0,"在线"],"r":[0,1,12.40272373540856,181,1,1,12.40272373540856,182]}}
  #|{"textrec":{"s":[12.5,400,0," · 0 秒"],"r":[0,1,3.47900390625,-1,1,1,5.988985773290501,183,2,1,3.47900390625,-1,3,1,7.8369140625,184,4,1,3.47900390625,-1,5,1,12.402723735408564,185]}}
  #|{"textrec":{"g":164,"r":[1985,0,19,18,-1,-15,0]}}
  #|{"textrec":{"g":165,"r":[2005,0,18,18,-1,-15,0]}}
  #|{"textrec":{"g":166,"r":[2024,0,18,18,-1,-15,0]}}
  #|{"textrec":{"g":167,"r":[0,20,18,18,-1,-15,0]}}
  #|{"textrec":{"g":168,"r":[19,20,17,18,0,-15,0]}}
  #|{"textrec":{"g":169,"r":[37,20,18,18,-1,-15,0]}}
  #|{"textrec":{"g":170,"r":[56,20,15,14,-1,-11,0]}}
  #|{"textrec":{"g":171,"r":[72,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":172,"r":[88,20,4,5,1,-7,0]}}
  #|{"textrec":{"g":173,"r":[93,20,7,12,-1,-11,0]}}
  #|{"textrec":{"g":174,"r":[101,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":1,"r":[117,20,14,15,-1,-12,0]}}
  #|{"textrec":{"g":175,"r":[132,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":176,"r":[148,20,10,12,-1,-10,0]}}
  #|{"textrec":{"g":177,"r":[159,20,10,13,0,-12,0]}}
  #|{"textrec":{"g":178,"r":[170,20,8,4,0,-6,0]}}
  #|{"textrec":{"g":179,"r":[179,20,14,10,-1,-9,0]}}
  #|{"textrec":{"g":180,"r":[194,20,10,15,0,-13,0]}}
  #|{"textrec":{"g":181,"r":[205,20,14,15,-1,-12,0]}}
  #|{"textrec":{"g":182,"r":[220,20,14,15,-1,-12,0]}}
  #|{"textrec":{"g":183,"r":[235,20,4,5,1,-7,0]}}
  #|{"textrec":{"g":184,"r":[240,20,10,13,-1,-11,0]}}
  #|{"textrec":{"g":185,"r":[251,20,14,14,-1,-11,0]}}
  #|{"textrec":{"ib":["b3685975cd23abc3",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"s":[11,400,0,"studio"],"r":[0,1,5.79541015625,186,1,1,4.03369140625,187,2,1,6.48291015625,188,3,1,6.8212890625,189,4,1,2.7822265625,190,5,1,6.5634765625,191]}}
  #|{"textrec":{"m":[11,400,0],"r":[10.634765625,2.3203125,16,10.634765625,2.3203125,0]}}
  #|{"textrec":{"s":[16,600,0,"服务"],"r":[0,1,15.875486381322958,192,1,1,15.875486381322958,193]}}
  #|{"textrec":{"s":[17,400,0,"对话"],"r":[0,1,16.851167315175097,194,1,1,16.851167315175097,195]}}
  #|{"textrec":{"m":[17,400,0],"r":[16.435546875,3.5859375,24,16.435546875,3.5859375,0]}}
  #|{"textrec":{"s":[16,600,0,"e2e-web"],"r":[0,1,9.127458572387695,46,1,1,9.717817306518555,196,2,1,9.100765228271484,46,3,1,7.247781753540039,197,4,1,12.531475067138672,198,5,1,8.958839416503906,46,6,1,9.891647338867188,199]}}
  #|{"textrec":{"s":[13,500,0,"e2e-web"],"r":[0,1,7.491410613059998,200,1,1,7.932154297828674,201,2,1,7.465491533279419,200,3,1,6.035249590873718,202,4,1,10.124328851699829,203,5,1,7.358638286590576,200,6,1,8.08608341217041,204]}}
  #|{"textrec":{"s":[13,600,0,"自适应"],"r":[0,1,12.898832684824903,205,1,1,12.898832684824903,206,2,1,12.898832684824903,207]}}
  #|{"textrec":{"m":[13,600,0],"r":[12.568359375,2.7421875,18,12.568359375,2.7421875,0]}}
  #|{"textrec":{"s":[13,400,0,"手机"],"r":[0,1,12.898832684824903,208,1,1,12.898832684824903,209]}}
  #|{"textrec":{"s":[13,400,0,"平板"],"r":[0,1,12.898832684824903,210,1,1,12.898832684824903,211]}}
  #|{"textrec":{"s":[13,400,0,"笔记本"],"r":[0,1,12.898832684824903,212,1,1,12.898832684824903,213,2,1,12.898832684824903,214]}}
  #|{"textrec":{"s":[13,400,0,"桌面"],"r":[0,1,12.898832684824903,215,1,1,12.898832684824903,216]}}
  #|{"textrec":{"s":[13,400,0,"自定义"],"r":[0,1,12.898832684824903,217,1,1,12.898832684824903,218,2,1,12.898832684824903,219]}}
  #|{"textrec":{"s":[16,400,0,"/"],"r":[0,1,4.5625,220]}}
  #|{"textrec":{"s":[12.5,400,0," · 1 秒"],"r":[0,1,3.47900390625,-1,1,1,5.988985773290501,183,2,1,3.47900390625,-1,3,1,5.76171875,221,4,1,3.47900390625,-1,5,1,12.402723735408564,185]}}
  #|{"textrec":{"g":221,"r":[266,20,7,11,-1,-10,0]}}
  #|{"textrec":{"g":46,"r":[274,20,11,12,-1,-10,0]}}
  #|{"textrec":{"g":196,"r":[286,20,11,14,0,-13,0]}}
  #|{"textrec":{"g":197,"r":[298,20,8,5,0,-7,0]}}
  #|{"textrec":{"g":198,"r":[307,20,15,11,-1,-10,0]}}
  #|{"textrec":{"g":199,"r":[323,20,11,15,0,-13,0]}}
  #|{"textrec":{"g":186,"r":[335,20,8,9,-1,-7,0]}}
  #|{"textrec":{"g":187,"r":[344,20,6,11,-1,-9,0]}}
  #|{"textrec":{"g":188,"r":[351,20,8,9,-1,-7,0]}}
  #|{"textrec":{"g":189,"r":[360,20,8,12,-1,-10,0]}}
  #|{"textrec":{"g":190,"r":[369,20,5,11,-1,-10,0]}}
  #|{"textrec":{"g":191,"r":[375,20,8,9,-1,-7,0]}}
  #|{"textrec":{"g":194,"r":[384,20,18,18,-1,-15,0]}}
  #|{"textrec":{"g":195,"r":[403,20,19,18,-1,-15,0]}}
  #|{"textrec":{"g":200,"r":[423,20,9,11,-1,-9,0]}}
  #|{"textrec":{"g":201,"r":[433,20,10,12,-1,-11,0]}}
  #|{"textrec":{"g":202,"r":[444,20,8,4,-1,-6,0]}}
  #|{"textrec":{"g":203,"r":[453,20,13,9,-1,-8,0]}}
  #|{"textrec":{"g":204,"r":[467,20,9,13,0,-11,0]}}
  #|{"textrec":{"g":205,"r":[477,20,12,15,0,-12,0]}}
  #|{"textrec":{"g":206,"r":[490,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":207,"r":[506,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":208,"r":[522,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":209,"r":[538,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":210,"r":[554,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":211,"r":[569,20,15,15,-1,-12,0]}}
  #|{"textrec":{"ib":["b5d30579041c3280",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["cb913616959f7700",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["18cb49857ec03d14",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["5077571ba5bd9ad5",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["419419fdf3c303b7",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"g":212,"r":[585,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":213,"r":[601,20,15,14,-1,-12,0]}}
  #|{"textrec":{"g":214,"r":[617,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":220,"r":[633,20,7,17,-1,-13,0]}}
  #|{"textrec":{"g":215,"r":[641,20,14,15,-1,-12,0]}}
  #|{"textrec":{"g":216,"r":[656,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":217,"r":[671,20,11,15,1,-12,0]}}
  #|{"textrec":{"g":218,"r":[683,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":219,"r":[699,20,15,15,-1,-12,0]}}
  #|{"textrec":{"ib":["9f030d95a75df3b2",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["30f231ef687ac989",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"s":[16,400,0,"/b.html"],"r":[0,1,4.5625,220,1,1,9.4375,147,2,1,4.359375,222,3,1,9.1015625,223,4,1,5.5,99,5,1,13.609375,224,6,1,3.734375,225]}}
  #|{"textrec":{"g":222,"r":[715,20,5,5,0,-3,0]}}
  #|{"textrec":{"g":223,"r":[721,20,10,14,0,-13,0]}}
  #|{"textrec":{"g":224,"r":[732,20,14,11,0,-10,0]}}
  #|{"textrec":{"g":225,"r":[747,20,4,14,0,-13,0]}}
  #|{"textrec":{"ib":["ec7bb93d33f53ea1",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"s":[13,400,0,"自适应"],"r":[0,1,12.898832684824903,217,1,1,12.898832684824903,226,2,1,12.898832684824903,227]}}
  #|{"textrec":{"s":[13,600,0,"手机"],"r":[0,1,12.898832684824903,228,1,1,12.898832684824903,229]}}
  #|{"textrec":{"g":226,"r":[752,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":227,"r":[768,20,14,15,-1,-12,0]}}
  #|{"textrec":{"g":228,"r":[783,20,15,15,-1,-12,0]}}
  #|{"textrec":{"g":229,"r":[799,20,15,15,-1,-12,0]}}
  #|{"textrec":{"ib":["6d13d1d27ea32084",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"ib":["a40f31224443e023",1382,64],"r":[18,18,18,18]}}
