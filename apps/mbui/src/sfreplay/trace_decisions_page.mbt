// e2e/traces/decisions-page.trace, made by scripts/trace.py from 01-decisions_page.log: not edited by hand.

///|
/// What the app and its core said in the run, a line each.
pub let trace_decisions_page : String =
  #|{"env":{"MBUI_CLOUD":"http://127.0.0.1:18787","MBUI_CORE_ACCOUNT":"{\"sub\":\"alice\",\"email\":\"alice@example.test\",\"name\":\"Name of alice\",\"picture\":\"\",\"access\":\"-\",\"refresh\":\"-\",\"accessExpires\":1792597496}"}}
  #|{"out":{"id":1,"call":"client.device","params":{"client":"still.fail mbui","app":"desktop","userAgent":"Macintosh; Mac OS X"}},"w":1792597207209.845}
  #|{"in":{"id":1,"ok":null},"w":1792597207305.25}
  #|{"out":{"id":2,"subscribe":{"topic":"accounts"},"keyed":true},"w":1792597207305.27}
  #|{"out":{"id":3,"subscribe":{"topic":"prefs"},"keyed":true},"w":1792597207305.279}
  #|{"step":"# written by scripts/rerecord.sh from its test (src/sfreplay/emit.mbt): not edited by hand","w":1792597207306.738}
  #|{"step":"timeout 90000","w":1792597207306.745}
  #|{"step":"answered client.device","w":1792597207306.747}
  #|{"step":"#env MBUI_OPEN_PAGE=decisions","w":1792597207319.374}
  #|{"step":"log do: peer send 还有一个问题 085454 card:发布到哪里 085454|测试版 085454*|正式版 085454","w":1792597207319.377}
  #|{"step":"peer send 还有一个问题 085454 card:发布到哪里 085454|测试版 085454*|正式版 085454"}
  #|{"step":"done 1-peer","w":1792597207319.382}
  #|{"in":{"id":2,"value":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""}]},"w":1792597207385.216}
  #|{"in":{"id":3,"value":{"onlyMine":false,"onlyWatching":false,"onlyDecisions":false,"listFilter":{},"appearance":"system","rowPicture":"auto","absoluteTime":false,"lang":"zh","keys":{},"lastChat":{},"openChat":{},"chatTabs":{},"dropFiles":{},"driveViews":{},"filesTabs":{},"driveFavorites":{},"resume":{},"stationUpdatesDismissed":{},"device":{"app":"desktop","phone":false,"handoff":false},"reader":{"size":18,"line":1.7,"margin":22,"face":"sans","indent":true,"paper":"follow"},"rails":{},"bars":{"sets":[["chats","files","profiles","stations"],["decisions","usage","connects","archive"]],"current":0},"barsBy":{},"fonts":{},"faces":{"ui":{"id":"","name":"","mono":false,"family":"","files":[],"bytes":0},"text":{"id":"","name":"","mono":false,"family":"","files":[],"bytes":0},"code":{"id":"","name":"","mono":true,"family":"","files":[],"bytes":0},"list":[{"id":"inter","name":"Inter","mono":false,"family":"SF Inter","css":"http://127.0.0.1:18787/releases/fonts/inter/4.001/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/inter/4.001/var.ttf.gz","bytes":457818,"sha256":"29160a80ff49ddcab2c97711247e08b1fab27a484a329ce8b813d820dc559031"}],"preview":"http://127.0.0.1:18787/releases/fonts/inter/4.001/preview-194fa287.ttf","bytes":457818},{"id":"noto-sans-sc","name":"思源黑体","mono":false,"family":"SF Noto Sans SC","css":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/var.ttf.gz","bytes":11276563,"sha256":"a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da"}],"preview":"http://127.0.0.1:18787/releases/fonts/noto-sans-sc/2.004/preview-f0494178.ttf","bytes":11276563},{"id":"noto-serif-sc","name":"思源宋体","mono":false,"family":"SF Noto Serif SC","css":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/var.ttf.gz","bytes":15454579,"sha256":"050080d9255a86808f2945bffac582b31ef32bc36411ce29563b4961670c66f9"}],"preview":"http://127.0.0.1:18787/releases/fonts/noto-serif-sc/2.003/preview-001bbedf.ttf","bytes":15454579},{"id":"lxgw-wenkai","name":"霞鹜文楷","mono":false,"family":"SF LXGW WenKai","css":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/font.css","files":[{"weight":400,"url":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/400.ttf.gz","bytes":12904482,"sha256":"2d73eea94ad808999d90c0000c239a84a33b09d4bc6ab6c5b8bbf1eda8a7fc8b"},{"weight":500,"url":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/500.ttf.gz","bytes":13272430,"sha256":"f4b8a34d1f838fe411540cb7c97b1c384ac9738a876c4104500bc42508b2312a"}],"preview":"http://127.0.0.1:18787/releases/fonts/lxgw-wenkai/1.530/preview-d3505af4.ttf","bytes":26176912},{"id":"jetbrains-mono","name":"JetBrains Mono","mono":true,"family":"SF JetBrains Mono","css":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/var.ttf.gz","bytes":90579,"sha256":"48715a42ec242c21e9f02692891e147d022299a52e48d5e413e1a942193ffeda"}],"preview":"http://127.0.0.1:18787/releases/fonts/jetbrains-mono/2.211/preview-ee73078f.ttf","bytes":90579},{"id":"fira-code","name":"Fira Code","mono":true,"family":"SF Fira Code","css":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/font.css","files":[{"weight":0,"url":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/var.ttf.gz","bytes":137151,"sha256":"9335b082b3c7850d98a64b584f3417f65355f3471278bb5eeb8c6c0e8657aeeb"}],"preview":"http://127.0.0.1:18787/releases/fonts/fira-code/5.002/preview-555be27a.ttf","bytes":137151},{"id":"maple-mono","name":"Maple Mono","mono":true,"family":"SF Maple Mono CN","css":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/font.css","files":[{"weight":400,"url":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/400.ttf.gz","bytes":8352545,"sha256":"0fcc5139bfd5ab14ff989bb7dfd5236d0cafc10e60b9828569e6883613ab4085"},{"weight":600,"url":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/600.ttf.gz","bytes":8438132,"sha256":"96ed7ae26ee7c50b02b2d2b2bc0f1a0cbabe45ae5d6e6abf6678e2177c415677"}],"preview":"http://127.0.0.1:18787/releases/fonts/maple-mono/7.9/preview-cffdf246.ttf","bytes":16790677}]}}},"w":1792597207385.263}
  #|{"out":{"id":4,"subscribe":{"topic":"workspaces"},"keyed":true},"w":1792597207385.318}
  #|{"out":{"id":5,"subscribe":{"topic":"status"},"keyed":true},"w":1792597207385.329}
  #|{"in":{"id":4,"value":[{"account":{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""},"workspaces":[{"id":"01M5FHWV567143351E8AAY63WF","name":"Dev","role":"owner","created_at":1792597191,"stations":1,"members":1,"relays":[],"time":{"created_at":{"past":true,"at":1792597191000,"ago":"刚刚","full":"10/21 23:39:51","until":"1 分钟内"}}}],"invitations":[],"relay_url":"http://127.0.0.1:18740","loaded":true,"beta":true}]},"w":1792597207404.731}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792597207404.752}
  #|{"out":{"id":6,"subscribe":{"topic":"lock","workspace":"01M5FHWV567143351E8AAY63WF"},"keyed":true},"w":1792597207404.791}
  #|{"out":{"id":7,"subscribe":{"topic":"chats","scope":"01M5FHWV567143351E8AAY63WF","mine":false},"keyed":true},"w":1792597207404.813}
  #|{"out":{"id":8,"subscribe":{"topic":"changelog"},"keyed":true},"w":1792597207404.82}
  #|{"out":{"id":9,"subscribe":{"topic":"workspaceMarks","workspace":"01M5FHWV567143351E8AAY63WF"},"keyed":true},"w":1792597207404.942}
  #|{"out":{"id":10,"subscribe":{"topic":"decisions","workspace":"01M5FHWV567143351E8AAY63WF"},"keyed":true},"w":1792597207404.975}
  #|{"out":{"id":11,"subscribe":{"topic":"status","workspace":"01M5FHWV567143351E8AAY63WF"},"keyed":true},"w":1792597207405.044}
  #|{"out":{"id":12,"subscribe":{"topic":"lockPrompts"},"keyed":true},"w":1792597207405.075}
  #|{"out":{"id":13,"call":"client.focus","params":{"visible":true,"focused":true,"workspace":"01M5FHWV567143351E8AAY63WF"}},"w":1792597207408.422}
  #|{"out":{"id":14,"subscribe":{"topic":"notify"},"keyed":true},"w":1792597207408.433}
  #|{"out":{"id":15,"subscribe":{"topic":"notify","workspace":"01M5FHWV567143351E8AAY63WF"},"keyed":true},"w":1792597207408.439}
  #|{"in":{"id":6,"value":{"available":true,"locked":false,"notice":true,"role":"owner","manages":true,"owner":true,"canSign":true,"signs":false,"me":{"device":"64945649f8bc8a08478a024c9af95506d15b6a4471bd2d17c9a1f3addb41e932","code":"XW8-WFV","kind":"app","confirmed":false,"waiting":false,"asked":false},"signers":0,"members":[],"stations":[{"id":"de47e929ab75ceab38abcb4f6728129e595b3c816b507ec13bec654d94d5a1bd","name":"studio","version":"0.1.0","online":true,"protected":false}],"protected":0,"requests":[],"renew":[],"attention":0}},"w":1792597207418.539}
  #|{"in":{"id":7,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"stations":[{"station":"01M5FHWV567143351E8AAY63WF/de47e929ab75ceab38abcb4f6728129e595b3c816b507ec13bec654d94d5a1bd","id":"de47e929ab75ceab38abcb4f6728129e595b3c816b507ec13bec654d94d5a1bd","name":"studio","state":"online"}],"loading":false,"days":[{"daysAgo":0,"at":1792597196354,"label":"今天","items":[{"id":"ember:c-d17fa82bd2","session":"ember:c-d17fa82bd2","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","agents":[{"key":"ember:c-d17fa82bd2","runtime":"claude","process":"warm","pending":0,"lastTurn":{"id":"f1821e10-2489-46a6-b77d-9249ce5ce6c0","kind":"input","outcome":"completed","declared":"final","ending":"all_done","need":"answered the question that was asked","startedAt":1792597196283,"endedAt":1792597196356},"agentText":"默认模型","statusText":"已完成：answered the question that was asked"}],"last":{"seq":2,"authorKind":"agent","author":"ember:c-d17fa82bd2","text":"你好，我是测试用的 agent","createdAt":1792597196354,"by":{"kind":"agent","name":"agent","mine":false,"runtime":"claude","label":"agent"},"preview":"你好，我是测试用的 agent","time":{"createdAt":{"at":1792597196354,"ago":"刚刚","full":"10/21 23:39:56","until":"1 分钟内","past":true}}},"unread":true,"mine":true,"lastActiveAt":1792597196354,"station":"01M5FHWV567143351E8AAY63WF/de47e929ab75ceab38abcb4f6728129e595b3c816b507ec13bec654d94d5a1bd","stationName":"studio","time":{"lastActiveAt":{"at":1792597196354,"ago":"刚刚","full":"10/21 23:39:56","until":"1 分钟内","past":true}},"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"peopleText":"你 发起","clientKey":"new:chat-ec1fed1dee439764d5","pinned":false,"tone":"done"}]}],"trouble":null,"members":1,"leading":"agents","glyph":{"online":1,"dim":0,"connecting":0,"failing":0,"working":0,"summary":"studio","label":"1 台 station，1 台在线"},"note":{"reading":false,"text":null,"failing":[],"empty":false}}},"w":1792597207418.568}
  #|{"in":{"id":8,"value":{"app":"desktop","tabs":[{"part":"desktop","label":"桌面","days":[]},{"part":"web","label":"网页","days":[]},{"part":"android","label":"安卓","days":[]},{"part":"station","label":"Station","days":[]},{"part":"cloud","label":"云端","days":[]}],"loading":false}},"w":1792597207418.589}
  #|{"in":{"id":9,"value":{"workspaces":{"01M5FHWV567143351E8AAY63WF":{"alert":0,"unread":1,"tone":"done","label":"1 个有新消息","badge":0,"items":[],"mineTone":"done"}},"badge":0,"badgeCounts":"attention","badgeKinds":{"on":true,"wait":true,"failed":true,"done":false,"message":false}}},"w":1792597207418.595}
  #|{"in":{"id":10,"value":{"items":[],"count":0,"wait":{"reading":false,"text":null,"failing":[],"empty":true},"answered":[],"working":[],"today":{"count":0,"working":0}}},"w":1792597207418.6}
  #|{"in":{"id":11,"value":{"items":[]}},"w":1792597207418.603}
  #|{"in":{"id":12,"value":{"pairing":[]}},"w":1792597207418.606}
  #|{"in":{"id":13,"ok":null},"w":1792597207418.608}
  #|{"in":{"id":14,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792597207418.621}
  #|{"in":{"id":15,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792597207418.625}
  #|{"out":{"id":16,"subscribe":{"topic":"longJobs","scope":"01M5FHWV567143351E8AAY63WF"},"keyed":true},"w":1792597207418.656}
  #|{"out":{"id":17,"call":"notify.permission","params":{"state":"unknown"}},"w":1792597207421.294}
  #|{"in":{"id":16,"value":{"groups":[]}},"w":1792597207435.202}
  #|{"in":{"id":17,"ok":null},"w":1792597207435.207}
  #|{"step":"until =测试版 085454","w":1792597208218.84}
  #|{"in":{"id":7,"delta":[{"path":["days"],"key":["daysAgo"],"patch":0,"ops":[{"path":["at"],"set":1792597208204},{"path":["items"],"key":["station","id"],"patch":["01M5FHWV567143351E8AAY63WF/de47e929ab75ceab38abcb4f6728129e595b3c816b507ec13bec654d94d5a1bd","ember:c-d17fa82bd2"],"ops":[{"path":["agents",0,"badgeText"],"set":"agent 已暂停，等待处理"},{"path":["agents",0,"lastTurn","about"],"set":{"thread":1,"seq":4,"ts":"1792597208.204000"}},{"path":["agents",0,"lastTurn","declared"],"set":"block"},{"path":["agents",0,"lastTurn","endedAt"],"set":1792597208206},{"path":["agents",0,"lastTurn","ending"],"set":"need_help"},{"path":["agents",0,"lastTurn","id"],"set":"e9f09cd6-fd1a-4e03-9475-ff3df0127589"},{"path":["agents",0,"lastTurn","need"],"set":"发布到哪里 085454"},{"path":["agents",0,"lastTurn","startedAt"],"set":1792597208181},{"path":["agents",0,"mark"],"set":"block"},{"path":["agents",0,"statusText"],"set":"需要你处理：发布到哪里 085454"},{"path":["decision"],"set":{"seq":4,"options":[{"label":"正式版 085454"},{"label":"测试版 085454","recommended":true}],"card":{"type":"options","options":[{"label":"正式版 085454"},{"label":"测试版 085454","recommended":true}]},"text":"奏 · 发布到哪里 085454"}},{"path":["last","by","label"],"set":"agent（agent 已暂停，等待处理）"},{"path":["last","by","state"],"set":"block"},{"path":["last","createdAt"],"set":1792597208204},{"path":["last","preview"],"set":"发布到哪里 085454"},{"path":["last","seq"],"set":4},{"path":["last","text"],"set":"发布到哪里 085454"},{"path":["last","time","createdAt","at"],"set":1792597208204},{"path":["last","time","createdAt","full"],"set":"10/21 23:40:08"},{"path":["lastActiveAt"],"set":1792597208204},{"path":["state"],"set":"block"},{"path":["stateText"],"set":"需要你处理：发布到哪里 085454"},{"path":["time","lastActiveAt","at"],"set":1792597208204},{"path":["time","lastActiveAt","full"],"set":"10/21 23:40:08"},{"path":["tone"],"set":"wait"}]}]}]},"w":1792597208318.586}
  #|{"in":{"id":10,"delta":[{"path":["count"],"set":1},{"path":["items"],"key":["station","session","seq"],"put":{"station":"01M5FHWV567143351E8AAY63WF/de47e929ab75ceab38abcb4f6728129e595b3c816b507ec13bec654d94d5a1bd","stationName":"studio","session":"ember:c-d17fa82bd2","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","seq":4,"message":{"seq":4,"thread":1,"ts":"1792597208.204000","authorKind":"agent","author":"ember:c-d17fa82bd2","text":"发布到哪里 085454","attachments":[],"quotes":[],"declared":"block","ending":"need_help","createdAt":1792597208204,"mine":false,"system":false,"by":{"name":"默认模型","agent":"ember:c-d17fa82bd2","runtime":"claude"},"waiting":false,"time":{"createdAt":{"at":1792597208204,"ago":"刚刚","full":"10/21 23:40:08","until":"1 分钟内","past":true}},"options":[{"label":"正式版 085454"},{"label":"测试版 085454","recommended":true}],"card":{"assigneeText":"待你决策","type":"options","options":[{"label":"正式版 085454"},{"label":"测试版 085454","recommended":true}]},"decision":{"resolved":false}},"before":[{"seq":2,"thread":1,"ts":"1792597196.354000","authorKind":"agent","author":"ember:c-d17fa82bd2","text":"你好，我是测试用的 agent","attachments":[],"quotes":[],"declared":"final","ending":"all_done","createdAt":1792597196354,"mine":false,"system":false,"by":{"name":"默认模型","agent":"ember:c-d17fa82bd2","runtime":"claude"},"waiting":false,"time":{"createdAt":{"at":1792597196354,"ago":"刚刚","full":"10/21 23:39:56","until":"1 分钟内","past":true}}},{"seq":3,"thread":1,"ts":"1792597208.180000","authorKind":"person","author":"alice@example.test","authorName":"Name of alice","text":"还有一个问题 085454 card:发布到哪里 085454|测试版 085454*|正式版 085454","attachments":[],"quotes":[],"createdAt":1792597208180,"mine":true,"system":false,"by":{"name":"Name of alice","picture":"https://example.test/p.png"},"waiting":false,"time":{"createdAt":{"at":1792597208180,"ago":"刚刚","full":"10/21 23:40:08","until":"1 分钟内","past":true}}}],"options":[{"label":"正式版 085454"},{"label":"测试版 085454","recommended":true}],"card":{"assigneeText":"待你决策","type":"options","options":[{"label":"正式版 085454"},{"label":"测试版 085454","recommended":true}]},"text":"奏 · 发布到哪里 085454","question":"发布到哪里 085454"},"before":null},{"path":["wait","empty"],"set":false}]},"w":1792597208318.704}
  #|{"in":{"id":9,"value":{"workspaces":{"01M5FHWV567143351E8AAY63WF":{"alert":0,"unread":0,"wait":1,"decisions":1,"tone":"wait","label":"1 个待你处理","badge":1,"items":[{"kind":"wait","workspace":"01M5FHWV567143351E8AAY63WF","workspaceName":"Dev","station":"01M5FHWV567143351E8AAY63WF/de47e929ab75ceab38abcb4f6728129e595b3c816b507ec13bec654d94d5a1bd","stationName":"studio","session":"ember:c-d17fa82bd2","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","text":"需要你处理：发布到哪里 085454","seq":4,"seen":false,"at":1792597208204}],"elsewhere":1,"mineTone":"wait"}},"badge":1,"badgeCounts":"attention","badgeKinds":{"on":true,"wait":true,"failed":true,"done":false,"message":false}}},"w":1792597208318.743}
  #|{"in":{"id":14,"delta":[{"path":["show"],"append":[{"id":"n-bc24178362c021037b","kind":"wait","station":"01M5FHWV567143351E8AAY63WF/de47e929ab75ceab38abcb4f6728129e595b3c816b507ec13bec654d94d5a1bd","workspace":"01M5FHWV567143351E8AAY63WF","stationId":"de47e929ab75ceab38abcb4f6728129e595b3c816b507ec13bec654d94d5a1bd","session":"ember:c-d17fa82bd2","thread":1,"seq":4,"title":"端到端测试的对话 post:你好，我是测试用的 agent","body":"待你决定 · 发布到哪里 085454","tag":"01M5FHWV567143351E8AAY63WF/de47e929ab75ceab38abcb4f6728129e595b3c816b507ec13bec654d94d5a1bd/ember:c-d17fa82bd2","url":"/o/01M5FHWV567143351E8AAY63WF/de47e929ab75ceab38abcb4f6728129e595b3c816b507ec13bec654d94d5a1bd/ember%3Ac-d17fa82bd2?message=4","at":1792597208244}]}]},"w":1792597208318.759}
  #|{"in":{"id":15,"delta":[{"path":["show"],"append":[{"id":"n-bc24178362c021037b","kind":"wait","station":"01M5FHWV567143351E8AAY63WF/de47e929ab75ceab38abcb4f6728129e595b3c816b507ec13bec654d94d5a1bd","workspace":"01M5FHWV567143351E8AAY63WF","stationId":"de47e929ab75ceab38abcb4f6728129e595b3c816b507ec13bec654d94d5a1bd","session":"ember:c-d17fa82bd2","thread":1,"seq":4,"title":"端到端测试的对话 post:你好，我是测试用的 agent","body":"待你决定 · 发布到哪里 085454","tag":"01M5FHWV567143351E8AAY63WF/de47e929ab75ceab38abcb4f6728129e595b3c816b507ec13bec654d94d5a1bd/ember:c-d17fa82bd2","url":"/o/01M5FHWV567143351E8AAY63WF/de47e929ab75ceab38abcb4f6728129e595b3c816b507ec13bec654d94d5a1bd/ember%3Ac-d17fa82bd2?message=4","at":1792597208244}]}]},"w":1792597208318.771}
  #|{"out":{"id":18,"call":"notice.claim","params":{"id":"n-bc24178362c021037b"}},"w":1792597208324.2}
  #|{"out":{"id":19,"call":"draft.get","params":{"key":"decision:01M5FHWV567143351E8AAY63WF/de47e929ab75ceab38abcb4f6728129e595b3c816b507ec13bec654d94d5a1bd:1:4"}},"w":1792597208324.226}
  #|{"step":"tap =测试版 085454","w":1792597208334.843}
  #|{"step":"tap =测试版 085454","acted":true,"w":1792597208334.866}
  #|{"in":{"id":18,"ok":{"show":true}},"w":1792597208335.205}
  #|{"in":{"id":19,"ok":{"text":"","quotes":[],"files":[],"id":"draft-85afdf5097d475351d"}},"w":1792597208335.239}
  #|{"out":{"id":20,"call":"decision.answer","params":{"station":"01M5FHWV567143351E8AAY63WF/de47e929ab75ceab38abcb4f6728129e595b3c816b507ec13bec654d94d5a1bd","thread":1,"seq":4,"option":"测试版 085454"}},"w":1792597208335.374}
  #|{"step":"answered client.focus","w":1792597208335.635}
  #|{"in":{"id":20,"ok":{"seq":5}},"w":1792597208351.873}
  #|{"step":"answered notify.permission","w":1792597208352.975}
  #|{"step":"answered draft.get","w":1792597208369.437}
  #|{"step":"answered notice.claim","w":1792597208386.147}
  #|{"in":{"id":14,"delta":[{"path":["show",0,"at"],"set":1792597208396},{"path":["show",0,"body"],"set":"出错 · 本轮 agent 未在对话中回复，以下是它最后输出的文字，由 station 代为转发（并非它发布的消息）；回复即可继续： Your turn ended without a state, so nobody knows where the chat stands. …"},{"path":["show",0,"id"],"set":"n-36ba37c9ff7493fcdc"},{"path":["show",0,"kind"],"set":"failed"},{"path":["show",0,"seq"],"set":6},{"path":["show",0,"url"],"set":"/o/01M5FHWV567143351E8AAY63WF/de47e929ab75ceab38abcb4f6728129e595b3c816b507ec13bec654d94d5a1bd/ember%3Ac-d17fa82bd2?message=6"}]},"w":1792597208401.876}
  #|{"in":{"id":15,"delta":[{"path":["show",0,"at"],"set":1792597208396},{"path":["show",0,"body"],"set":"出错 · 本轮 agent 未在对话中回复，以下是它最后输出的文字，由 station 代为转发（并非它发布的消息）；回复即可继续： Your turn ended without a state, so nobody knows where the chat stands. …"},{"path":["show",0,"id"],"set":"n-36ba37c9ff7493fcdc"},{"path":["show",0,"kind"],"set":"failed"},{"path":["show",0,"seq"],"set":6},{"path":["show",0,"url"],"set":"/o/01M5FHWV567143351E8AAY63WF/de47e929ab75ceab38abcb4f6728129e595b3c816b507ec13bec654d94d5a1bd/ember%3Ac-d17fa82bd2?message=6"}]},"w":1792597208401.915}
  #|{"in":{"id":9,"value":{"workspaces":{"01M5FHWV567143351E8AAY63WF":{"alert":1,"unread":0,"tone":"alert","label":"1 个出错","badge":1,"items":[{"kind":"alert","workspace":"01M5FHWV567143351E8AAY63WF","workspaceName":"Dev","station":"01M5FHWV567143351E8AAY63WF/de47e929ab75ceab38abcb4f6728129e595b3c816b507ec13bec654d94d5a1bd","stationName":"studio","session":"ember:c-d17fa82bd2","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","text":"出错：意外停止","seen":false,"at":1792597208341}],"mineTone":"alert"}},"badge":1,"badgeCounts":"attention","badgeKinds":{"on":true,"wait":true,"failed":true,"done":false,"message":false}}},"w":1792597208401.939}
  #|{"in":{"id":10,"delta":[{"path":["answered"],"append":[{"station":"01M5FHWV567143351E8AAY63WF/de47e929ab75ceab38abcb4f6728129e595b3c816b507ec13bec654d94d5a1bd","stationName":"studio","session":"ember:c-d17fa82bd2","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","seq":4,"text":"发布到哪里 085454","answer":"选择了「测试版 085454」","clock":"23:40"}]},{"path":["count"],"set":0},{"path":["items"],"key":["station","session","seq"],"drop":["01M5FHWV567143351E8AAY63WF/de47e929ab75ceab38abcb4f6728129e595b3c816b507ec13bec654d94d5a1bd","ember:c-d17fa82bd2",4]},{"path":["today","count"],"set":1},{"path":["today","waited"],"set":"不足 1 分钟"},{"path":["wait","empty"],"set":true}]},"w":1792597208401.96}
  #|{"in":{"id":7,"delta":[{"path":["days"],"key":["daysAgo"],"patch":0,"ops":[{"path":["at"],"set":1792597208341},{"path":["items"],"key":["station","id"],"patch":["01M5FHWV567143351E8AAY63WF/de47e929ab75ceab38abcb4f6728129e595b3c816b507ec13bec654d94d5a1bd","ember:c-d17fa82bd2"],"ops":[{"path":["agents",0,"badgeText"],"set":"失败，需要处理"},{"path":["agents",0,"lastTurn","endedAt"],"set":1792597208341},{"path":["agents",0,"lastTurn","id"],"set":"aee85a8f-8277-4491-942d-dfc6d1f4d84e"},{"path":["agents",0,"lastTurn","kind"],"set":"nudge"},{"path":["agents",0,"lastTurn","startedAt"],"set":1792597208340},{"path":["agents",0,"lastTurn","about"],"remove":true},{"path":["agents",0,"lastTurn","declared"],"remove":true},{"path":["agents",0,"lastTurn","ending"],"remove":true},{"path":["agents",0,"lastTurn","need"],"remove":true},{"path":["agents",0,"mark"],"set":"failed"},{"path":["agents",0,"statusText"],"set":"出错：意外停止"},{"path":["last","author"],"set":"ember"},{"path":["last","authorKind"],"set":"ember"},{"path":["last","authorName"],"set":"still.fail"},{"path":["last","by","kind"],"set":"ember"},{"path":["last","by","label"],"set":"still.fail"},{"path":["last","by","name"],"set":"still.fail"},{"path":["last","by","runtime"],"remove":true},{"path":["last","by","state"],"remove":true},{"path":["last","createdAt"],"set":1792597208341},{"path":["last","preview"],"set":"⚠️ 本轮 agent 未在对话中回复，以下是它最后输出的文字，由 station 代为转发（并非它发布的消息）；回复即可继续： Your turn ended without a state, so nobody knows where the chat stands. Only a real unresolved need requires need_human. A factual a"},{"path":["last","seq"],"set":6},{"path":["last","text"],"set":"⚠️ 本轮 agent 未在对话中回复，以下是它最后输出的文字，由 station 代为转发（并非它发布的消息）；回复即可继续：\n\n> Your turn ended without a state, so nobody knows where the chat stands. Only a real unresolved need requires need_human. A factual a"},{"path":["last","time","createdAt","at"],"set":1792597208341},{"path":["lastActiveAt"],"set":1792597208341},{"path":["state"],"set":"failed"},{"path":["stateText"],"set":"出错：意外停止"},{"path":["time","lastActiveAt","at"],"set":1792597208341},{"path":["tone"],"set":"alert"},{"path":["decision"],"remove":true}]}]}]},"w":1792597208402.018}
  #|{"out":{"id":21,"call":"notice.claim","params":{"id":"n-36ba37c9ff7493fcdc"}},"w":1792597208405.488}
  #|{"step":"answered decision.answer","w":1792597208406.765}
  #|{"in":{"id":21,"ok":{"show":true}},"w":1792597208418.535}
  #|{"step":"answered notice.claim","w":1792597208419.66}
  #|{"step":"wait 360","w":1792597208436.307}
  #|{"in":{"id":14,"delta":[{"path":["show"],"set":[]}]},"w":1792597208518.539}
  #|{"in":{"id":15,"delta":[{"path":["show"],"set":[]}]},"w":1792597208518.554}
  #|{"step":"now until 奏折已全部批完","w":1792597208819.408}
  #|{"step":"","w":1792597208819.474}
  #|{"textrec":{"m":[15,400,0],"r":[14.501953125,3.1640625,21,14.501953125,3.1640625,0]}}
  #|{"textrec":{"ib":["bfd9b0d6dc602826",12668,64],"r":[56,56,56,56]}}
  #|{"textrec":{"s":[13,400,0,"正在读取你的 workspace"],"r":[0,1,12.898832684824903,0,1,1,12.898832684824903,1,2,1,12.898832684824903,2,3,1,12.898832684824903,3,4,1,12.898832684824896,4,5,1,12.898832684824896,5,6,1,3.580078125,-1,7,1,9.8642578125,6,8,1,7.4775390625,7,9,1,4.875,8,10,1,6.85546875,9,11,1,6.6015625,10,12,1,7.8583984375,11,13,1,7.0966796875,12,14,1,7.1982421875,13,15,1,7.3505859375,14]}}
  #|{"textrec":{"m":[13,400,0],"r":[12.568359375,2.7421875,18,12.568359375,2.7421875,0]}}
  #|{"textrec":{"s":[24,700,0,"Dev"],"r":[0,1,17.075823068618774,15,1,1,13.365240812301636,16,2,1,12.759063005447388,17]}}
  #|{"textrec":{"m":[24,700,0],"r":[23.203125,5.0625,34,20.638916015625,3.361083984375,0]}}
  #|{"textrec":{"s":[16,600,0,"奏"],"r":[0,1,15.875486381322958,18]}}
  #|{"textrec":{"m":[16,600,0],"r":[15.46875,3.375,23,15.46875,3.375,0]}}
  #|{"textrec":{"s":[17,400,0,"对话"],"r":[0,1,16.851167315175097,19,1,1,16.851167315175097,20]}}
  #|{"textrec":{"m":[17,400,0],"r":[16.435546875,3.5859375,24,16.435546875,3.5859375,0]}}
  #|{"textrec":{"g":15,"r":[0,0,18,19,0,-18,0]}}
  #|{"textrec":{"g":16,"r":[19,0,15,16,-1,-14,0]}}
  #|{"textrec":{"g":17,"r":[35,0,15,15,-1,-14,0]}}
  #|{"textrec":{"ib":["1d51432b25a425eb",1108,64],"r":[16,16,16,16]}}
  #|{"textrec":{"ib":["02698e60df92657e",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"s":[15,400,0,"搜索全部内容"],"r":[0,1,14.883268482490273,21,1,1,14.883268482490273,22,2,1,14.883268482490273,23,3,1,14.883268482490273,24,4,1,14.88326848249028,25,5,1,14.88326848249028,26]}}
  #|{"textrec":{"s":[15,600,0,"今天"],"r":[0,1,14.883268482490273,27,1,1,14.883268482490273,28]}}
  #|{"textrec":{"m":[15,600,0],"r":[14.501953125,3.1640625,21,14.501953125,3.1640625,0]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 post:你好，我是测试用的 agent"],"r":[0,1,15.875486381322958,29,1,1,15.875486381322958,30,2,1,15.875486381322958,29,3,1,15.875486381322958,31,4,1,15.875486381322958,32,5,1,15.875486381322958,33,6,1,15.875486381322958,34,7,1,15.875486381322958,35,8,1,3.95001220703125,-1,9,1,9.824199676513672,36,10,1,9.432537078857422,37,11,1,8.471200942993164,38,12,1,5.973020553588867,39,13,1,4.952056884765625,40,14,1,15.875486381322958,41,15,1,15.875486381322958,42,16,1,16.09338521400778,43,17,1,15.875486381322958,44,18,1,15.875486381322958,45,19,1,15.87548638132293,31,20,1,15.875486381322958,32,21,1,15.875486381322958,46,22,1,15.875486381322958,33,23,1,3.95001220703125,-1,24,1,8.899068832397461,47,25,1,9.801153182983398,48,26,1,9.127458572387695,49,27,1,9.466253280639648,50,28,1,5.999713897705078,39]}}
  #|{"textrec":{"s":[14,400,0,"你好，我是测试用的 agent"],"r":[0,1,13.891050583657588,51,1,1,13.891050583657588,52,2,1,14.081712062256813,53,3,1,13.891050583657588,54,4,1,13.891050583657588,55,5,1,13.891050583657588,56,6,1,13.891050583657588,57,7,1,13.891050583657588,58,8,1,13.891050583657588,59,9,1,3.787109375000014,-1,10,1,7.57421875,60,11,1,8.380859375,61,12,1,7.84765625,62,13,1,8.0185546875,63,14,1,4.935546875,64]}}
  #|{"textrec":{"m":[14,400,0],"r":[13.53515625,2.953125,20,13.53515625,2.953125,0]}}
  #|{"textrec":{"s":[16,600,0,"…"],"r":[0,1,14.076484680175781,65]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 post:你好，我是测试用的…"],"r":[0,1,15.875486381322958,29,1,1,15.875486381322958,30,2,1,15.875486381322958,29,3,1,15.875486381322958,31,4,1,15.875486381322958,32,5,1,15.875486381322958,33,6,1,15.875486381322958,34,7,1,15.875486381322958,35,8,1,3.95001220703125,-1,9,1,9.824199676513672,36,10,1,9.432537078857422,37,11,1,8.471200942993164,38,12,1,5.973020553588867,39,13,1,4.952056884765625,40,14,1,15.875486381322958,41,15,1,15.875486381322958,42,16,1,16.09338521400778,43,17,1,15.875486381322958,44,18,1,15.875486381322958,45,19,1,15.87548638132293,31,20,1,15.875486381322958,32,21,1,15.875486381322958,46,22,1,15.875486381322958,33,23,1,14.076484680175781,65]}}
  #|{"textrec":{"s":[17,600,0,"奏折已全部批完"],"r":[0,1,16.851167315175097,66,1,1,16.851167315175097,67,2,1,16.851167315175097,68,3,1,16.851167315175097,69,4,1,16.851167315175104,70,5,1,16.851167315175104,71,6,1,16.851167315175104,72]}}
  #|{"textrec":{"m":[17,600,0],"r":[16.435546875,3.5859375,24,16.435546875,3.5859375,0]}}
  #|{"textrec":{"s":[14,400,0,"新的奏折会显示在这里"],"r":[0,1,13.891050583657588,73,1,1,13.891050583657588,59,2,1,13.891050583657588,74,3,1,13.891050583657588,75,4,1,13.891050583657588,76,5,1,13.891050583657588,77,6,1,13.891050583657588,78,7,1,13.891050583657588,79,8,1,13.891050583657588,80,9,1,13.891050583657588,81]}}
  #|{"textrec":{"s":[20,600,0,"0"],"r":[0,1,12.71425393410027,82]}}
  #|{"textrec":{"m":[20,600,0],"r":[19.3359375,4.21875,28,17.1990966796875,2.8009033203125,0]}}
  #|{"textrec":{"s":[12,400,0,"今日已批"],"r":[0,1,11.918287937743191,83,1,1,11.918287937743191,84,2,1,11.918287937743195,85,3,1,11.918287937743187,86]}}
  #|{"textrec":{"m":[12,400,0],"r":[11.6015625,2.53125,17,11.6015625,2.53125,0]}}
  #|{"textrec":{"s":[12,400,0,"办理中"],"r":[0,1,11.918287937743191,87,1,1,11.918287937743191,88,2,1,11.918287937743195,89]}}
  #|{"textrec":{"g":21,"r":[51,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":22,"r":[69,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":23,"r":[86,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":24,"r":[104,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":25,"r":[121,0,15,16,0,-13,0]}}
  #|{"textrec":{"g":26,"r":[137,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":27,"r":[154,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":28,"r":[172,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":29,"r":[190,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":30,"r":[208,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":31,"r":[226,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":32,"r":[244,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":33,"r":[263,0,16,17,0,-14,0]}}
  #|{"textrec":{"g":34,"r":[280,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":35,"r":[298,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":36,"r":[317,0,11,14,0,-10,0]}}
  #|{"textrec":{"g":37,"r":[329,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":38,"r":[341,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":39,"r":[353,0,8,14,-1,-12,0]}}
  #|{"textrec":{"g":40,"r":[362,0,5,12,0,-10,0]}}
  #|{"textrec":{"g":41,"r":[368,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":42,"r":[386,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":43,"r":[404,0,6,8,0,-4,0]}}
  #|{"textrec":{"g":44,"r":[411,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":45,"r":[430,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":46,"r":[448,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":65,"r":[465,0,14,6,0,-4,0]}}
  #|{"textrec":{"g":51,"r":[480,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":52,"r":[496,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":53,"r":[513,0,5,7,0,-3,0]}}
  #|{"textrec":{"g":54,"r":[519,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":55,"r":[536,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":56,"r":[552,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":57,"r":[568,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":58,"r":[585,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":59,"r":[601,0,14,16,0,-13,0]}}
  #|{"textrec":{"g":60,"r":[616,0,9,11,-1,-9,0]}}
  #|{"textrec":{"g":61,"r":[626,0,10,13,-1,-9,0]}}
  #|{"textrec":{"g":62,"r":[637,0,10,11,-1,-9,0]}}
  #|{"textrec":{"g":63,"r":[648,0,9,10,0,-9,0]}}
  #|{"textrec":{"g":64,"r":[658,0,7,13,-1,-11,0]}}
  #|{"textrec":{"ib":["33d1dfbf90932d3b",1241,64],"r":[17,17,17,17]}}
  #|{"textrec":{"ib":["182b7158e0c0cae1",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["d61ec6305f7d8c8b",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["a1e7be43eb966606",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"g":19,"r":[666,0,18,18,-1,-15,0]}}
  #|{"textrec":{"g":20,"r":[685,0,19,18,-1,-15,0]}}
  #|{"textrec":{"g":66,"r":[705,0,18,18,-1,-15,0]}}
  #|{"textrec":{"g":67,"r":[724,0,18,18,-1,-15,0]}}
  #|{"textrec":{"g":68,"r":[743,0,17,17,0,-14,0]}}
  #|{"textrec":{"g":69,"r":[761,0,19,18,-1,-15,0]}}
  #|{"textrec":{"g":70,"r":[781,0,18,18,-1,-15,0]}}
  #|{"textrec":{"g":71,"r":[800,0,18,18,-1,-15,0]}}
  #|{"textrec":{"g":72,"r":[819,0,18,18,-1,-15,0]}}
  #|{"textrec":{"g":73,"r":[838,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":74,"r":[855,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":75,"r":[872,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":76,"r":[888,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":77,"r":[905,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":78,"r":[921,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":79,"r":[937,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":80,"r":[953,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":81,"r":[970,0,15,14,-1,-12,0]}}
  #|{"textrec":{"g":82,"r":[986,0,13,18,0,-16,0]}}
  #|{"textrec":{"g":83,"r":[1000,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":84,"r":[1015,0,10,14,1,-11,0]}}
  #|{"textrec":{"g":85,"r":[1026,0,13,12,0,-10,0]}}
  #|{"textrec":{"g":86,"r":[1040,0,14,14,-1,-11,0]}}
  #|{"textrec":{"ib":["cfb613d15c0b52af",20876,128],"r":[72,72,72,72]}}
  #|{"textrec":{"g":18,"r":[1055,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":87,"r":[1073,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":88,"r":[1088,0,14,13,-1,-11,0]}}
  #|{"textrec":{"g":89,"r":[1103,0,12,14,0,-11,0]}}
  #|{"textrec":{"m":[16,400,0],"r":[15.46875,3.375,23,15.46875,3.375,0]}}
  #|{"textrec":{"s":[12,400,0,"1 / 1"],"r":[0,1,5.56640625,90,1,1,3.375,-1,2,1,3.65625,91,3,1,3.375,-1,4,1,5.56640625,90]}}
  #|{"textrec":{"s":[12,400,0,"← 待定　不再提醒 →"],"r":[0,1,10.869140625,92,1,1,3.375,-1,2,1,11.918287937743191,93,3,1,11.918287937743191,94,4,1,11.918287937743195,95,5,1,11.918287937743187,96,6,1,11.918287937743187,97,7,1,11.918287937743187,98,8,1,11.918287937743187,99,9,1,3.375,-1,10,1,10.869140625,100]}}
  #|{"textrec":{"s":[13,400,0,"端到端测试的对话 post:你好，我是测试用的 agent"],"r":[0,1,12.898832684824903,101,1,1,12.898832684824903,102,2,1,12.898832684824903,101,3,1,12.898832684824903,103,4,1,12.898832684824896,104,5,1,12.898832684824896,5,6,1,12.898832684824896,105,7,1,12.898832684824896,106,8,1,3.580078125,-1,9,1,7.8583984375,11,10,1,7.6044921875,7,11,1,6.69677734375,10,12,1,4.61474609375,107,13,1,3.783203125,108,14,1,12.898832684824896,4,15,1,12.898832684824896,109,16,1,13.075875486381335,110,17,1,12.898832684824896,111,18,1,12.898832684824896,112,19,1,12.898832684824896,103,20,1,12.898832684824896,104,21,1,12.898832684824896,113,22,1,12.898832684824896,5,23,1,3.5800781250000284,-1,24,1,7.0966796875,12,25,1,7.845703125,114,26,1,7.3505859375,14,27,1,7.50927734375,115,28,1,4.646484375,107]}}
  #|{"textrec":{"s":[13,400,0,"待你决策"],"r":[0,1,12.898832684824903,116,1,1,12.898832684824903,4,2,1,12.898832684824903,117,3,1,12.898832684824903,118]}}
  #|{"textrec":{"s":[15,650,0,"默认模型"],"r":[0,1,14.883268482490273,119,1,1,14.883268482490273,120,2,1,14.883268482490273,121,3,1,14.883268482490273,122]}}
  #|{"textrec":{"m":[15,650,0],"r":[14.501953125,3.1640625,21,14.501953125,3.1640625,0]}}
  #|{"textrec":{"s":[10,400,0,"刚刚"],"r":[0,1,9.941634241245136,123,1,1,9.941634241245136,123]}}
  #|{"textrec":{"m":[10,400,0],"r":[9.66796875,2.109375,14,9.66796875,2.109375,0]}}
  #|{"textrec":{"s":[15,400,0,"你好，我是测试用的 agent"],"r":[0,1,14.883268482490273,124,1,1,14.883268482490273,125,2,1,15.087548638132297,126,3,1,14.883268482490273,127,4,1,14.883268482490266,128,5,1,14.88326848249028,129,6,1,14.88326848249028,130,7,1,14.88326848249028,131,8,1,14.88326848249028,132,9,1,3.984375,-1,10,1,8.0419921875,133,11,1,8.90625,134,12,1,8.3349609375,135,13,1,8.51806640625,136,14,1,5.21484375,137]}}
  #|{"textrec":{"s":[16,400,0,"还有一个问题 085454 card:发布到哪里 085454|测试版 085454*|正式版 085454"],"r":[0,1,15.875486381322958,138,1,1,15.875486381322958,139,2,1,15.875486381322958,140,3,1,15.875486381322958,141,4,1,15.875486381322958,142,5,1,15.875486381322958,143,6,1,4.1875,-1,7,1,9.765625,144,8,1,9.90625,145,9,1,9.578125,146,10,1,9.984375,147,11,1,9.578125,146,12,1,9.984375,147,13,1,4.1875,-1,14,1,8.640625,148,15,1,8.515625,149,16,1,5.6640625,150,17,1,9.3984375,151,18,1,4.4375,152,19,1,15.875486381322958,153,20,1,15.875486381322958,154,21,1,15.875486381322958,155,22,1,15.875486381322958,156,23,1,15.875486381322958,157,24,1,4.1875,-1,25,1,9.765625,144,26,1,9.90625,145,27,1,9.578125,146,28,1,9.984375,147,29,1,9.578125,146,30,1,9.984375,147,31,1,5.828125,158,32,1,15.875486381322958,159,33,1,15.875486381322958,160,34,1,15.875486381322958,161,35,1,4.1875,-1,36,1,9.765625,144,37,1,9.90625,145,38,1,9.578125,146,39,1,9.984375,147,40,1,9.578125,146,41,1,9.90625,147,42,1,7.15625,162,43,1,5.828125,158,44,1,15.875486381322958,163,45,1,15.875486381322958,164,46,1,15.875486381322958,161,47,1,4.1875,-1,48,1,9.765625,144,49,1,9.90625,145,50,1,9.578125,146,51,1,9.984375,147,52,1,9.578125,146,53,1,9.984375,147]}}
  #|{"textrec":{"s":[15,400,0,"发布到哪里 085454"],"r":[0,1,14.883268482490273,165,1,1,14.883268482490273,166,2,1,14.883268482490273,167,3,1,14.883268482490273,168,4,1,14.88326848249028,169,5,1,3.984375,-1,6,1,9.2138671875,170,7,1,9.345703125,171,8,1,9.0380859375,172,9,1,9.4189453125,173,10,1,9.0380859375,172,11,1,9.4189453125,173]}}
  #|{"textrec":{"s":[15,500,0,"正式版 085454"],"r":[0,1,14.883268482490273,174,1,1,14.883268482490273,175,2,1,14.883268482490273,176,3,1,3.855457305908203,-1,4,1,9.51467514038086,177,5,1,9.649196863174431,178,6,1,9.286521077156067,179,7,1,9.65798020362854,180,8,1,9.286521077156067,179,9,1,9.65798020362854,180]}}
  #|{"textrec":{"m":[15,500,0],"r":[14.501953125,3.1640625,21,14.501953125,3.1640625,0]}}
  #|{"textrec":{"s":[15,500,0,"测试版 085454"],"r":[0,1,14.883268482490273,181,1,1,14.883268482490273,182,2,1,14.883268482490273,176,3,1,3.855457305908203,-1,4,1,9.51467514038086,177,5,1,9.649196863174431,178,6,1,9.286521077156067,179,7,1,9.65798020362854,180,8,1,9.286521077156067,179,9,1,9.65798020362854,180]}}
  #|{"textrec":{"g":101,"r":[1116,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":102,"r":[1132,0,14,15,-1,-12,0]}}
  #|{"textrec":{"g":103,"r":[1147,0,14,15,-1,-12,0]}}
  #|{"textrec":{"g":104,"r":[1162,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":5,"r":[1178,0,13,15,0,-12,0]}}
  #|{"textrec":{"g":105,"r":[1192,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":106,"r":[1208,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":11,"r":[1224,0,9,12,0,-8,0]}}
  #|{"textrec":{"g":7,"r":[1234,0,9,10,-1,-8,0]}}
  #|{"textrec":{"g":10,"r":[1244,0,9,10,-1,-8,0]}}
  #|{"textrec":{"g":107,"r":[1254,0,7,12,-1,-10,0]}}
  #|{"textrec":{"g":108,"r":[1262,0,4,10,0,-8,0]}}
  #|{"textrec":{"g":4,"r":[1267,0,14,15,-1,-12,0]}}
  #|{"textrec":{"g":109,"r":[1282,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":110,"r":[1298,0,5,7,0,-3,0]}}
  #|{"textrec":{"g":111,"r":[1304,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":112,"r":[1320,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":113,"r":[1335,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":12,"r":[1350,0,9,10,-1,-8,0]}}
  #|{"textrec":{"g":114,"r":[1360,0,9,12,-1,-8,0]}}
  #|{"textrec":{"g":14,"r":[1370,0,9,10,-1,-8,0]}}
  #|{"textrec":{"g":115,"r":[1380,0,8,9,0,-8,0]}}
  #|{"textrec":{"g":116,"r":[1389,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":117,"r":[1405,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":118,"r":[1421,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":119,"r":[1437,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":120,"r":[1455,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":121,"r":[1473,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":122,"r":[1491,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":123,"r":[1508,0,11,11,-1,-9,0]}}
  #|{"textrec":{"g":124,"r":[1520,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":125,"r":[1537,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":126,"r":[1554,0,5,7,0,-3,0]}}
  #|{"textrec":{"g":127,"r":[1560,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":128,"r":[1578,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":129,"r":[1595,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":130,"r":[1612,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":131,"r":[1630,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":132,"r":[1646,0,15,17,0,-14,0]}}
  #|{"textrec":{"g":133,"r":[1662,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":134,"r":[1673,0,10,14,-1,-10,0]}}
  #|{"textrec":{"g":135,"r":[1684,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":136,"r":[1695,0,9,11,0,-10,0]}}
  #|{"textrec":{"g":137,"r":[1705,0,7,13,-1,-11,0]}}
  #|{"textrec":{"g":138,"r":[1713,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":139,"r":[1731,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":140,"r":[1749,0,17,4,-1,-8,0]}}
  #|{"textrec":{"g":141,"r":[1767,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":142,"r":[1786,0,16,17,0,-14,0]}}
  #|{"textrec":{"g":143,"r":[1803,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":144,"r":[1821,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":145,"r":[1833,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":146,"r":[1845,0,10,15,0,-13,0]}}
  #|{"textrec":{"g":147,"r":[1856,0,12,14,-1,-13,0]}}
  #|{"textrec":{"g":148,"r":[1869,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":149,"r":[1881,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":150,"r":[1892,0,7,11,0,-10,0]}}
  #|{"textrec":{"g":151,"r":[1900,0,11,15,-1,-13,0]}}
  #|{"textrec":{"g":152,"r":[1912,0,5,11,0,-9,0]}}
  #|{"textrec":{"g":153,"r":[1918,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":154,"r":[1936,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":155,"r":[1954,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":156,"r":[1972,0,16,17,0,-14,0]}}
  #|{"textrec":{"g":157,"r":[1989,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":158,"r":[2007,0,4,17,0,-13,0]}}
  #|{"textrec":{"g":159,"r":[2012,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":160,"r":[0,20,18,17,-1,-14,0]}}
  #|{"textrec":{"g":161,"r":[19,20,18,17,-1,-14,0]}}
  #|{"textrec":{"g":162,"r":[38,20,8,9,0,-13,0]}}
  #|{"textrec":{"g":163,"r":[47,20,17,15,-1,-13,0]}}
  #|{"textrec":{"g":164,"r":[65,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":165,"r":[83,20,16,17,-1,-14,0]}}
  #|{"textrec":{"g":166,"r":[100,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":167,"r":[117,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":168,"r":[134,20,15,16,0,-13,0]}}
  #|{"textrec":{"g":169,"r":[150,20,16,15,-1,-13,0]}}
  #|{"textrec":{"g":170,"r":[167,20,11,14,-1,-12,0]}}
  #|{"textrec":{"g":171,"r":[179,20,11,14,-1,-12,0]}}
  #|{"textrec":{"g":172,"r":[191,20,10,14,0,-12,0]}}
  #|{"textrec":{"g":173,"r":[202,20,11,13,-1,-12,0]}}
  #|{"textrec":{"g":174,"r":[214,20,16,15,-1,-13,0]}}
  #|{"textrec":{"g":175,"r":[231,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":176,"r":[248,20,17,16,-1,-13,0]}}
  #|{"textrec":{"g":177,"r":[266,20,11,14,-1,-12,0]}}
  #|{"textrec":{"g":178,"r":[278,20,11,14,-1,-12,0]}}
  #|{"textrec":{"g":179,"r":[290,20,10,14,0,-12,0]}}
  #|{"textrec":{"g":180,"r":[301,20,12,13,-1,-12,0]}}
  #|{"textrec":{"g":181,"r":[314,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":182,"r":[331,20,17,16,-1,-13,0]}}
  #|{"textrec":{"s":[16,400,0,"发消息"],"r":[0,1,15.875486381322958,153,1,1,15.875486381322958,183,2,1,15.875486381322958,184]}}
  #|{"textrec":{"g":183,"r":[349,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":184,"r":[367,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":92,"r":[385,20,11,10,0,-9,0]}}
  #|{"textrec":{"g":93,"r":[397,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":94,"r":[412,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":95,"r":[427,20,14,17,-1,-13,0]}}
  #|{"textrec":{"g":96,"r":[442,20,14,13,-1,-10,0]}}
  #|{"textrec":{"g":97,"r":[457,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":98,"r":[472,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":99,"r":[487,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":100,"r":[502,20,11,10,0,-9,0]}}
  #|{"textrec":{"g":90,"r":[514,20,7,11,-1,-10,0]}}
  #|{"textrec":{"g":91,"r":[522,20,6,14,-1,-10,0]}}
  #|{"textrec":{"ib":["b3685975cd23abc3",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["11ba9484460f477d",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["bd8d9582330c77a7",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"ib":["3daaf3271f648d0b",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"ib":["c7a6d30e254a5910",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"ib":["b277602c41d156e7",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"s":[20,600,0,"1"],"r":[0,1,9.303665617480874,185]}}
  #|{"textrec":{"s":[20,600,0,"不足 1 分钟"],"r":[0,1,19.154135338345863,186,1,1,19.154135338345863,187,2,1,4.567122841253877,-1,3,1,9.303665617480874,185,4,1,4.567122841253877,-1,5,1,19.15413533834586,188,6,1,19.154135338345867,189]}}
  #|{"textrec":{"s":[12,400,0,"平均等待"],"r":[0,1,11.918287937743191,190,1,1,11.918287937743191,191,2,1,11.918287937743195,192,3,1,11.918287937743187,93]}}
  #|{"textrec":{"s":[12,500,0,"今日已批阅"],"r":[0,1,11.918287937743191,193,1,1,11.918287937743191,194,2,1,11.918287937743195,195,3,1,11.918287937743187,196,4,1,11.918287937743187,197]}}
  #|{"textrec":{"m":[12,500,0],"r":[11.6015625,2.53125,17,11.6015625,2.53125,0]}}
  #|{"textrec":{"s":[12,400,0,"23:40"],"r":[0,1,7.2421875,198,1,1,7.5234375,199,2,1,3.5625,200,3,1,7.72265625,201,4,1,7.55859375,202]}}
  #|{"textrec":{"s":[15,500,0,"发布到哪里 085454"],"r":[0,1,14.883268482490273,203,1,1,14.883268482490273,204,2,1,14.883268482490273,205,3,1,14.883268482490273,206,4,1,14.88326848249028,207,5,1,3.855457305908203,-1,6,1,9.51467514038086,177,7,1,9.649196863174438,178,8,1,9.286521077156067,179,9,1,9.65798020362854,180,10,1,9.286521077156067,179,11,1,9.65798020362854,180]}}
  #|{"textrec":{"s":[13,400,0,"端到端测试的对话 post:你好，我是测试用的 agent · 选择了「测试版 085454」"],"r":[0,1,12.898832684824903,101,1,1,12.898832684824903,102,2,1,12.898832684824903,101,3,1,12.898832684824903,103,4,1,12.898832684824896,104,5,1,12.898832684824896,5,6,1,12.898832684824896,105,7,1,12.898832684824896,106,8,1,3.580078125,-1,9,1,7.8583984375,11,10,1,7.6044921875,7,11,1,6.69677734375,10,12,1,4.61474609375,107,13,1,3.783203125,108,14,1,12.898832684824896,4,15,1,12.898832684824896,109,16,1,13.075875486381335,110,17,1,12.898832684824896,111,18,1,12.898832684824896,112,19,1,12.898832684824896,103,20,1,12.898832684824896,104,21,1,12.898832684824896,113,22,1,12.898832684824896,5,23,1,3.5800781250000284,-1,24,1,7.0966796875,12,25,1,7.845703125,114,26,1,7.3505859375,14,27,1,7.50927734375,115,28,1,4.646484375,107,29,1,3.580078125,-1,30,1,6.228545204222144,208,31,1,3.580078125,-1,32,1,12.898832684824924,209,33,1,12.898832684824924,210,34,1,19.398832684824924,211,35,1,4.704280155642039,212,36,1,12.898832684824924,103,37,1,12.898832684824924,104,38,1,12.898832684824924,213,39,1,3.580078125,-1,40,1,8.1123046875,214,41,1,8.2265625,215,42,1,7.9599609375,216,43,1,8.2900390625,217,44,1,7.9599609375,216,45,1,8.2900390625,217,46,1,6.6180285343709215,218]}}
  #|{"textrec":{"s":[13,400,0,"…"],"r":[0,1,10.384765625,219]}}
  #|{"textrec":{"s":[13,400,0,"端到端测试的对话 post:你好，我是测试用的…"],"r":[0,1,12.898832684824903,101,1,1,12.898832684824903,102,2,1,12.898832684824903,101,3,1,12.898832684824903,103,4,1,12.898832684824896,104,5,1,12.898832684824896,5,6,1,12.898832684824896,105,7,1,12.898832684824896,106,8,1,3.580078125,-1,9,1,7.8583984375,11,10,1,7.6044921875,7,11,1,6.69677734375,10,12,1,4.61474609375,107,13,1,3.783203125,108,14,1,12.898832684824896,4,15,1,12.898832684824896,109,16,1,13.075875486381335,110,17,1,12.898832684824896,111,18,1,12.898832684824896,112,19,1,12.898832684824896,103,20,1,12.898832684824896,104,21,1,12.898832684824896,113,22,1,12.898832684824896,5,23,1,10.384765625000028,219]}}
  #|{"textrec":{"g":185,"r":[529,20,9,17,0,-16,0]}}
  #|{"textrec":{"g":186,"r":[539,20,21,20,-1,-16,0]}}
  #|{"textrec":{"g":187,"r":[561,20,20,20,-1,-16,0]}}
  #|{"textrec":{"g":188,"r":[582,20,21,21,-1,-17,0]}}
  #|{"textrec":{"g":189,"r":[604,20,20,20,-1,-17,0]}}
  #|{"textrec":{"g":190,"r":[625,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":191,"r":[640,20,13,14,-1,-11,0]}}
  #|{"textrec":{"g":192,"r":[654,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":193,"r":[669,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":194,"r":[684,20,10,14,1,-11,0]}}
  #|{"textrec":{"g":195,"r":[695,20,13,12,0,-10,0]}}
  #|{"textrec":{"g":196,"r":[709,20,14,14,-1,-11,0]}}
  #|{"textrec":{"g":197,"r":[724,20,13,14,-1,-11,0]}}
  #|{"textrec":{"g":203,"r":[738,20,16,17,-1,-14,0]}}
  #|{"textrec":{"g":204,"r":[755,20,16,17,-1,-14,0]}}
  #|{"textrec":{"g":205,"r":[772,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":206,"r":[789,20,15,16,0,-13,0]}}
  #|{"textrec":{"g":207,"r":[805,20,16,16,-1,-13,0]}}
  #|{"textrec":{"g":219,"r":[822,20,11,5,0,-3,0]}}
  #|{"textrec":{"g":198,"r":[834,20,9,11,-1,-10,0]}}
  #|{"textrec":{"g":199,"r":[844,20,9,12,-1,-10,0]}}
  #|{"textrec":{"g":200,"r":[854,20,4,9,0,-7,0]}}
  #|{"textrec":{"g":201,"r":[859,20,10,11,-1,-10,0]}}
  #|{"textrec":{"g":202,"r":[870,20,9,12,-1,-10,0]}}
