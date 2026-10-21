// e2e/traces/bar-archive.trace, made by scripts/trace.py from 01-bar_archive.log: not edited by hand.

///|
/// What the app and its core said in the run, a line each.
pub let trace_bar_archive : String =
  #|{"start":"base"}
  #|{"step":"drive-seed 085454"}
  #|{"step":"peer create 从栏上归档 085454 post:都弄好了 085454"}
  #|{"step":"wait-chat 从栏上归档 085454"}
  #|{"env":{"MBUI_CLOUD":"http://127.0.0.1:18900","MBUI_CORE_ACCOUNT":"{\"sub\":\"alice\",\"email\":\"alice@example.test\",\"name\":\"Name of alice\",\"picture\":\"\",\"access\":\"-\",\"refresh\":\"-\",\"accessExpires\":1792524827}"}}
  #|{"out":{"id":1,"call":"client.device","params":{"client":"still.fail mbui","app":"desktop","userAgent":"Macintosh; Mac OS X"}},"w":1792524541176.913}
  #|{"in":{"id":1,"ok":null},"w":1792524541268.829}
  #|{"out":{"id":2,"subscribe":{"topic":"accounts"},"keyed":true},"w":1792524541268.854}
  #|{"out":{"id":3,"subscribe":{"topic":"prefs"},"keyed":true},"w":1792524541268.864}
  #|{"step":"# written by scripts/rerecord.sh from its test (src/sfreplay/emit.mbt): not edited by hand","w":1792524541270.308}
  #|{"step":"timeout 90000","w":1792524541270.314}
  #|{"step":"answered client.device","w":1792524541270.316}
  #|{"step":"answered client.focus","w":1792524541293.458}
  #|{"in":{"id":2,"value":[{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""}]},"w":1792524541359.802}
  #|{"in":{"id":3,"value":{"onlyMine":false,"onlyWatching":false,"onlyDecisions":false,"listFilter":{},"appearance":"system","rowPicture":"auto","absoluteTime":false,"lang":"zh","keys":{},"lastChat":{},"openChat":{},"chatTabs":{},"dropFiles":{},"driveViews":{},"resume":{},"stationUpdatesDismissed":{},"device":{"app":"desktop","phone":false,"handoff":false},"reader":{"size":18,"line":1.7,"margin":22,"face":"sans","indent":true,"paper":"follow"},"rails":{},"bars":{"sets":[["chats","files","profiles","stations"],["decisions","usage","connects","archive"]],"current":0},"barsBy":{}}},"w":1792524541359.823}
  #|{"out":{"id":4,"subscribe":{"topic":"workspaces"},"keyed":true},"w":1792524541359.851}
  #|{"out":{"id":5,"subscribe":{"topic":"status"},"keyed":true},"w":1792524541359.865}
  #|{"in":{"id":4,"value":[{"account":{"sub":"alice","email":"alice@example.test","name":"Name of alice","picture":""},"workspaces":[{"id":"01M5DCK6137JQCEQ8B5TFTN6HH","name":"Dev","role":"owner","created_at":1792524523,"stations":1,"members":1,"relays":[],"time":{"created_at":{"past":true,"at":1792524523000,"ago":"刚刚","full":"10/21 03:28:43","until":"1 分钟内"}}}],"invitations":[],"relay_url":"http://127.0.0.1:18940","loaded":true,"beta":true}]},"w":1792524541377.384}
  #|{"in":{"id":5,"value":{"items":[]}},"w":1792524541377.411}
  #|{"out":{"id":6,"subscribe":{"topic":"lock","workspace":"01M5DCK6137JQCEQ8B5TFTN6HH"},"keyed":true},"w":1792524541377.453}
  #|{"out":{"id":7,"subscribe":{"topic":"chats","scope":"01M5DCK6137JQCEQ8B5TFTN6HH","mine":false},"keyed":true},"w":1792524541377.469}
  #|{"out":{"id":8,"subscribe":{"topic":"workspaceMarks","workspace":"01M5DCK6137JQCEQ8B5TFTN6HH"},"keyed":true},"w":1792524541377.596}
  #|{"out":{"id":9,"subscribe":{"topic":"status","workspace":"01M5DCK6137JQCEQ8B5TFTN6HH"},"keyed":true},"w":1792524541377.628}
  #|{"out":{"id":10,"call":"client.focus","params":{"visible":true,"focused":true,"workspace":"01M5DCK6137JQCEQ8B5TFTN6HH"}},"w":1792524541383.241}
  #|{"out":{"id":11,"subscribe":{"topic":"notify"},"keyed":true},"w":1792524541383.25}
  #|{"out":{"id":12,"subscribe":{"topic":"notify","workspace":"01M5DCK6137JQCEQ8B5TFTN6HH"},"keyed":true},"w":1792524541383.262}
  #|{"in":{"id":6,"value":{"available":true,"locked":false,"notice":true,"role":"owner","manages":true,"owner":true,"canSign":true,"signs":false,"me":{"device":"8e4fc976b6aa0f1d91b61c77033ecd1bd14ea6182090ab4d40334114f6a832e7","code":"C8B-UGT","kind":"app","confirmed":false,"waiting":false,"asked":false},"signers":0,"members":[],"stations":[{"id":"cbbf585bd7c84f70e681bea7a8f96d20e97f5dad1fc99faf26031e9a05d4d918","name":"studio","version":"0.1.0","online":true,"protected":false}],"protected":0,"requests":[],"renew":[],"attention":0}},"w":1792524541393.158}
  #|{"in":{"id":7,"value":{"me":{"id":"alice@example.test","email":"alice@example.test"},"stations":[{"station":"01M5DCK6137JQCEQ8B5TFTN6HH/cbbf585bd7c84f70e681bea7a8f96d20e97f5dad1fc99faf26031e9a05d4d918","id":"cbbf585bd7c84f70e681bea7a8f96d20e97f5dad1fc99faf26031e9a05d4d918","name":"studio","state":"online"}],"loading":false,"days":[{"daysAgo":0,"at":1792524541133,"label":"今天","items":[{"id":"ember:c-a572fed18a","session":"ember:c-a572fed18a","thread":2,"title":"从栏上归档 085454 post:都弄好了 085454","agents":[{"key":"ember:c-a572fed18a","runtime":"claude","process":"warm","pending":0,"lastTurn":{"id":"769e3f0b-8afa-4ff0-ae0d-13a0d275c817","kind":"input","outcome":"completed","declared":"final","ending":"all_done","need":"answered the question that was asked","startedAt":1792524541067,"endedAt":1792524541136},"agentText":"默认模型","statusText":"已完成：answered the question that was asked"}],"last":{"seq":2,"authorKind":"agent","author":"ember:c-a572fed18a","text":"都弄好了 085454","createdAt":1792524541133,"by":{"kind":"agent","name":"agent","mine":false,"runtime":"claude","label":"agent"},"preview":"都弄好了 085454","time":{"createdAt":{"at":1792524541133,"ago":"刚刚","full":"10/21 03:29:01","until":"1 分钟内","past":true}}},"unread":true,"mine":true,"lastActiveAt":1792524541133,"station":"01M5DCK6137JQCEQ8B5TFTN6HH/cbbf585bd7c84f70e681bea7a8f96d20e97f5dad1fc99faf26031e9a05d4d918","stationName":"studio","time":{"lastActiveAt":{"at":1792524541133,"ago":"刚刚","full":"10/21 03:29:01","until":"1 分钟内","past":true}},"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"peopleText":"你 发起","clientKey":"new:chat-8893cd22fd2c573def","pinned":false,"tone":"done"},{"id":"ember:c-6c7209ebf6","session":"ember:c-6c7209ebf6","thread":1,"title":"端到端测试的对话 post:你好，我是测试用的 agent","agents":[{"key":"ember:c-6c7209ebf6","runtime":"claude","process":"cold","pending":0,"lastTurn":{"id":"f1ffdbf4-bce1-4621-9515-04cafea332df","kind":"input","outcome":"completed","declared":"final","ending":"all_done","need":"answered the question that was asked","startedAt":1792524527597,"endedAt":1792524527670},"agentText":"默认模型","statusText":"已完成：answered the question that was asked"}],"last":{"seq":2,"authorKind":"agent","author":"ember:c-6c7209ebf6","text":"你好，我是测试用的 agent","createdAt":1792524527668,"by":{"kind":"agent","name":"agent","mine":false,"runtime":"claude","label":"agent"},"preview":"你好，我是测试用的 agent","time":{"createdAt":{"at":1792524527668,"ago":"刚刚","full":"10/21 03:28:47","until":"1 分钟内","past":true}}},"unread":true,"mine":true,"lastActiveAt":1792524527668,"station":"01M5DCK6137JQCEQ8B5TFTN6HH/cbbf585bd7c84f70e681bea7a8f96d20e97f5dad1fc99faf26031e9a05d4d918","stationName":"studio","time":{"lastActiveAt":{"at":1792524527668,"ago":"刚刚","full":"10/21 03:28:47","until":"1 分钟内","past":true}},"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"peopleText":"你 发起","pinned":false,"tone":"done"}]}],"trouble":null,"members":1,"leading":"agents","glyph":{"online":1,"dim":0,"connecting":0,"failing":0,"working":0,"summary":"studio","label":"1 台 station，1 台在线"},"note":{"reading":false,"text":null,"failing":[],"empty":false}}},"w":1792524541393.206}
  #|{"in":{"id":8,"value":{"workspaces":{"01M5DCK6137JQCEQ8B5TFTN6HH":{"alert":0,"unread":2,"tone":"done","label":"2 个有新消息","badge":0,"items":[],"mineTone":"done"}},"badge":0,"badgeCounts":"attention","badgeKinds":{"on":true,"wait":true,"failed":true,"done":false,"message":false}}},"w":1792524541393.238}
  #|{"in":{"id":9,"value":{"items":[]}},"w":1792524541393.248}
  #|{"in":{"id":10,"ok":null},"w":1792524541393.251}
  #|{"in":{"id":11,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792524541393.262}
  #|{"in":{"id":12,"value":{"on":true,"asked":true,"push":true,"kinds":{"wait":true,"failed":true,"done":"away","message":true},"preview":true,"permission":"unknown","show":[]}},"w":1792524541393.267}
  #|{"out":{"id":13,"subscribe":{"topic":"longJobs","scope":"01M5DCK6137JQCEQ8B5TFTN6HH"},"keyed":true},"w":1792524541393.301}
  #|{"out":{"id":14,"call":"notify.permission","params":{"state":"unknown"}},"w":1792524541396.372}
  #|{"in":{"id":13,"value":{"groups":[]}},"w":1792524541409.812}
  #|{"in":{"id":14,"ok":null},"w":1792524541409.818}
  #|{"step":"answered notify.permission","w":1792524541410.094}
  #|{"step":"#before peer create 从栏上归档 085454 post:都弄好了 085454","w":1792524541426.739}
  #|{"step":"#before wait-chat 从栏上归档 085454","w":1792524541426.743}
  #|{"step":"until 从栏上归档 085454","w":1792524541426.745}
  #|{"step":"until 都弄好了 085454","w":1792524541426.751}
  #|{"step":"tap 从栏上归档 085454","w":1792524541426.754}
  #|{"step":"tap 从栏上归档 085454","acted":true,"w":1792524541443.36}
  #|{"out":{"id":15,"subscribe":{"topic":"chat","station":"01M5DCK6137JQCEQ8B5TFTN6HH/cbbf585bd7c84f70e681bea7a8f96d20e97f5dad1fc99faf26031e9a05d4d918","session":"ember:c-a572fed18a"},"keyed":true},"w":1792524541459.894}
  #|{"out":{"id":16,"call":"draft.get","params":{"key":"01M5DCK6137JQCEQ8B5TFTN6HH/cbbf585bd7c84f70e681bea7a8f96d20e97f5dad1fc99faf26031e9a05d4d918:ember:c-a572fed18a"}},"w":1792524541460.308}
  #|{"step":"answered draft.get","w":1792524541460.443}
  #|{"in":{"id":16,"ok":{"text":"","quotes":[],"files":[],"id":"draft-442a176208abe5ce47"}},"w":1792524541476.492}
  #|{"in":{"id":15,"value":{"archived":false,"pinned":false,"me":{"id":"alice@example.test","email":"alice@example.test"},"thread":{"id":2,"surface":"ember","channel":"EMBER","threadTs":"1792524541.002000","createdBy":"alice@example.test","creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}},"createdAt":1792524541002,"sessions":[{"thread":2,"session":"ember:c-a572fed18a","connect":"ember","joinedAt":1792524541002}],"last":2,"lastMessage":{"seq":2,"thread":2,"ts":"1792524541.133000","authorKind":"agent","author":"ember:c-a572fed18a","text":"都弄好了 085454","attachments":[],"quotes":[],"declared":"final","ending":"all_done","createdAt":1792524541133,"time":{"createdAt":{"at":1792524541133,"ago":"刚刚","full":"10/21 03:29:01","until":"1 分钟内","past":true}}},"read":0,"unread":1,"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"firstText":"从栏上归档 085454 post:都弄好了 085454","time":{"createdAt":{"at":1792524541002,"ago":"刚刚","full":"10/21 03:29:01","until":"1 分钟内","past":true}}},"title":"从栏上归档 085454 post:都弄好了 085454","people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud","shown":{"name":"Name of alice","display":"你","picture":"https://example.test/p.png","mine":true}}],"agents":[{"session":{"key":"ember:c-a572fed18a","connect":"ember","scope":"all","createdBy":"alice@example.test","boundTo":[],"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"},"participants":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"}],"runtime":"claude","profile":"cc","profilePinned":false,"runtimeSessionId":"795f9907-2575-418b-9689-27f9ef10286b","workspace":"/tmp/mbe2e-C/data/sessions/ember/c-a572fed18a/workspace","running":false,"createdAt":1792524541000,"lastActiveAt":1792524541136,"process":"warm","turns":1,"pending":0,"firstText":"从栏上归档 085454 post:都弄好了 085454","lastTurn":{"id":"769e3f0b-8afa-4ff0-ae0d-13a0d275c817","kind":"input","outcome":"completed","declared":"final","ending":"all_done","need":"answered the question that was asked","startedAt":1792524541067,"endedAt":1792524541136},"statusText":"已完成：answered the question that was asked","tone":"green","titleText":"从栏上归档 085454 post:都弄好了 085454","agentText":"默认模型","runtimeText":"Claude Code","processText":"保温中","efforts":["low","medium","high","xhigh","max"],"time":{"createdAt":{"at":1792524541000,"ago":"刚刚","full":"10/21 03:29:01","until":"1 分钟内","past":true},"lastActiveAt":{"at":1792524541136,"ago":"刚刚","full":"10/21 03:29:01","until":"1 分钟内","past":true}}},"status":"final","profile":{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792524540930,"time":{"checkedAt":{"at":1792524540930,"ago":"刚刚","full":"10/21 03:29:00","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792524527580,"time":{"checkedAt":{"at":1792524527580,"ago":"刚刚","full":"10/21 03:28:47","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]},"profiles":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":true,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792524527580,"time":{"checkedAt":{"at":1792524527580,"ago":"刚刚","full":"10/21 03:28:47","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}],"choices":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":true,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792524527580,"time":{"checkedAt":{"at":1792524527580,"ago":"刚刚","full":"10/21 03:28:47","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"account":{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":true,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792524527580,"time":{"checkedAt":{"at":1792524527580,"ago":"刚刚","full":"10/21 03:28:47","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}},"attention":[],"turns":[{"id":"769e3f0b-8afa-4ff0-ae0d-13a0d275c817","kind":"input","outcome":"completed","declared":"final","ending":"all_done","startedAt":1792524541067,"endedAt":1792524541136}],"threads":[{"id":2,"surface":"ember","channel":"EMBER","threadTs":"1792524541.002000","createdBy":"alice@example.test","creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"},"createdAt":1792524541002,"sessions":[{"thread":2,"session":"ember:c-a572fed18a","connect":"ember","joinedAt":1792524541002}],"last":2,"lastMessage":{"seq":2,"thread":2,"ts":"1792524541.133000","authorKind":"agent","author":"ember:c-a572fed18a","text":"都弄好了 085454","attachments":[],"quotes":[],"declared":"final","ending":"all_done","createdAt":1792524541133,"time":{"createdAt":{"at":1792524541133,"ago":"刚刚","full":"10/21 03:29:01","until":"1 分钟内","past":true}}},"read":0,"unread":1,"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"}],"firstText":"从栏上归档 085454 post:都弄好了 085454","time":{"createdAt":{"at":1792524541002,"ago":"刚刚","full":"10/21 03:29:01","until":"1 分钟内","past":true}}}],"jobs":[]}],"messages":[{"seq":1,"thread":2,"ts":"1792524541.056000","authorKind":"person","author":"alice@example.test","authorName":"Name of alice","text":"从栏上归档 085454 post:都弄好了 085454","attachments":[],"quotes":[],"createdAt":1792524541056,"mine":true,"system":false,"by":{"name":"Name of alice","picture":"https://example.test/p.png"},"waiting":false,"time":{"createdAt":{"at":1792524541056,"ago":"刚刚","full":"10/21 03:29:01","until":"1 分钟内","past":true}}},{"seq":2,"thread":2,"ts":"1792524541.133000","authorKind":"agent","author":"ember:c-a572fed18a","text":"都弄好了 085454","attachments":[],"quotes":[],"declared":"final","ending":"all_done","createdAt":1792524541133,"mine":false,"system":false,"by":{"name":"默认模型","agent":"ember:c-a572fed18a","runtime":"claude","here":true},"waiting":false,"time":{"createdAt":{"at":1792524541133,"ago":"刚刚","full":"10/21 03:29:01","until":"1 分钟内","past":true}}}],"elsewhere":[],"more":false,"newer":false,"at":1,"caught":2,"unreadLine":2,"unreadAbove":false,"outbox":[],"link":{"state":"online"},"offline":false,"pending":false,"asks":[],"publish":{"may":true,"links":[]}}},"w":1792524541476.61}
  #|{"out":{"id":17,"subscribe":{"topic":"stations","scope":"01M5DCK6137JQCEQ8B5TFTN6HH"},"keyed":true},"w":1792524541476.758}
  #|{"out":{"id":18,"subscribe":{"topic":"chatJobs","station":"01M5DCK6137JQCEQ8B5TFTN6HH/cbbf585bd7c84f70e681bea7a8f96d20e97f5dad1fc99faf26031e9a05d4d918","session":"ember:c-a572fed18a"},"keyed":true},"w":1792524541476.771}
  #|{"out":{"id":19,"call":"picture","params":{"url":"https://example.test/p.png"}},"w":1792524541476.784}
  #|{"out":{"id":20,"call":"client.focus","params":{"chat":{"station":"01M5DCK6137JQCEQ8B5TFTN6HH/cbbf585bd7c84f70e681bea7a8f96d20e97f5dad1fc99faf26031e9a05d4d918","session":"ember:c-a572fed18a","thread":2,"end":true}}},"w":1792524541479.527}
  #|{"in":{"id":17,"value":[{"station":"01M5DCK6137JQCEQ8B5TFTN6HH/cbbf585bd7c84f70e681bea7a8f96d20e97f5dad1fc99faf26031e9a05d4d918","id":"cbbf585bd7c84f70e681bea7a8f96d20e97f5dad1fc99faf26031e9a05d4d918","name":"studio","summary":"正在连接","face":"idle","line":"在线","online":true,"reconnecting":false,"lastSeen":1792524540,"version":"0.1.0","link":{"state":"online"},"runtimes":[{"runtime":"claude","models":["claude-sonnet-5-5"]}],"models":[{"model":"claude-sonnet-5-5","name":"Sonnet 5.5","family":"Sonnet","ids":["claude-sonnet-5-5"],"maker":{"id":"anthropic","name":"Anthropic"},"runtimes":["claude"],"efforts":{"claude":["low","medium","high","xhigh","max"]},"accounts":{"claude":[{"efforts":["low","medium","high","xhigh","max"],"id":"cc","name":"cc","current":false,"kind":"env","runtime":"claude","quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792524527580,"time":{"checkedAt":{"at":1792524527580,"ago":"刚刚","full":"10/21 03:28:47","until":"1 分钟内","past":true}}},"quotaLine":{"text":"自定义环境变量的账号无法查询额度"}}]}}],"overview":{"automaticDecisions":{"canEdit":true,"canReview":true,"settings":{"completion":{"enabled":false,"model":null}},"models":[],"recent":[],"policy":{"text":"agent 说做完了以后，看这个 chat 里用户要的东西现在怎么样了。只按用户实际要的判断：不替用户加要求，用户没要求部署或验证的就不算欠着。agent 说做完了但消息对不上时，以消息为准。看不到的东西（文件、线上状态）不要猜，看不出来就选「看不出来」。","options":[{"id":"answered","name":"已回答","rubric":"用户要的是答案、解释或建议，已经给了，没有要做的事","archive":true,"count":0,"chats":[]},{"id":"landed","name":"已落地","rubric":"要做的改动已经合进 main、已上线或已发版；用户要验证的已经验证","archive":true,"count":0,"chats":[]},{"id":"dropped","name":"不要了","rubric":"用户说不做了、不合了，或者改去别处做了","archive":true,"count":0,"chats":[]},{"id":"agent_work","name":"agent 还有活","rubric":"还有 agent 自己能接着做的事，或者有任务还在跑","archive":false,"count":0,"chats":[]},{"id":"awaiting_review","name":"等人看结果","rubric":"分支、截图、方案等做好了，在等人看或确认","archive":false,"count":0,"chats":[]},{"id":"awaiting_answer","name":"等人回答","rubric":"有没回答的问题，或没做的决定","archive":false,"count":0,"chats":[]},{"id":"awaiting_action","name":"等人去做","rubric":"要人去操作或提供东西，比如 key、权限、真机测试","archive":false,"count":0,"chats":[]},{"id":"uncertain","name":"看不出来","rubric":"消息不够判断还有没有事","archive":false,"count":0,"chats":[]}],"days":7,"checked":0,"failed":0,"edited":false,"change":null,"summaryText":"最近 7 天检查了 0 个 chat","changeText":null}},"archiving":{"days":1,"slackDays":3,"reviewed":false,"canEdit":true},"viewer":{"via":"mesh","email":"alice@example.test","name":"Name of alice","sub":"alice","role":"owner","workspace":"01M5DCK6137JQCEQ8B5TFTN6HH","device":"8e4fc976b6aa0f1d91b61c77033ecd1bd14ea6182090ab4d40334114f6a832e7"},"connects":[],"profiles":[{"id":"cc","name":"cc","runtime":"claude","runtimes":["claude"],"access":{"kind":"env","key":"","login":false},"home":"/tmp/mbe2e-C/data/homes/cc","homeExists":true,"models":["claude-sonnet-5-5"],"env":[],"usedBy":[],"loginCommand":"","machine":false,"backgroundOnMessage":true,"check":{"decision":{"state":"unsupported","detail":"当前登录未提供决策概率接口"},"state":"unknown","detail":"自定义环境变量，still.fail 无法自动检查","checkedAt":1792524540930,"time":{"checkedAt":{"at":1792524540930,"ago":"刚刚","full":"10/21 03:29:00","until":"1 分钟内","past":true}}},"quota":{"state":"unsupported","windows":[],"detail":"自定义环境变量的账号无法查询额度","checkedAt":1792524527580,"time":{"checkedAt":{"at":1792524527580,"ago":"刚刚","full":"10/21 03:28:47","until":"1 分钟内","past":true}}},"checkText":"无法检查","checkTone":"neutral","group":"key","groupTitle":"API Key","makers":{"claude-sonnet-5-5":{"id":"anthropic","name":"Anthropic"}},"names":{"claude-sonnet-5-5":"Sonnet 5.5"},"series":[{"name":"Sonnet","models":["claude-sonnet-5-5"]}],"modelsText":"已启用 1 / 1 个模型","available":["claude-sonnet-5-5"],"uses":["claude"],"usesText":"","canAddModel":false,"decisionOnly":false,"decisionModels":[],"workspaces":[]}],"processes":[],"counts":{"sessions":2,"running":0,"warm":1},"mesh":{"state":"running","origin":"http://127.0.0.1:18900","station":"cbbf585bd7c84f70e681bea7a8f96d20e97f5dad1fc99faf26031e9a05d4d918","workspace":"Dev","workspaceId":"01M5DCK6137JQCEQ8B5TFTN6HH","name":"studio"},"slackUsers":[],"slackTeams":[],"slackApps":[],"feishuRegistrations":[],"disk":{"freeBytes":68129304576,"totalBytes":245107195904},"logins":[],"machineLogins":[],"sharing":true,"consoleSignIn":true,"apiProviders":[{"id":"openai","name":"OpenAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"google","name":"Google Gemini","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xai","name":"xAI","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"mistral","name":"Mistral","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"deepseek","name":"DeepSeek","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen","name":"Qwen","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai","name":"Kimi","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai","name":"Z.ai","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax","name":"MiniMax","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"xiaomi","name":"Xiaomi MiMo","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ant-ling","name":"Ant Ling","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"jev","name":"Jev","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"qwen-cn","name":"Qwen (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"moonshotai-cn","name":"Kimi (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"zai-coding-cn","name":"Z.ai Coding (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"minimax-cn","name":"MiniMax (China)","group":"labs","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"openrouter","name":"OpenRouter","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"vercel-ai-gateway","name":"Vercel AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"opencode","name":"OpenCode Zen","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-ai-gateway","name":"Cloudflare AI Gateway","group":"gateways","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"azure-openai","name":"Azure OpenAI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"groq","name":"Groq","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"together","name":"Together AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"fireworks","name":"Fireworks","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cerebras","name":"Cerebras","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"huggingface","name":"Hugging Face","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"nvidia","name":"NVIDIA","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"baseten","name":"Baseten","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"cloudflare-workers-ai","name":"Cloudflare Workers AI","group":"hosted","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"ollama","name":"Ollama","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""},{"id":"custom","name":"Custom","group":"local","kind":"","hasKey":false,"hasPlan":false,"endpointRequired":false,"protocols":[],"keyOptional":false,"uses":[],"usesText":""}],"updates":[{"id":"station","name":"Station","installed":true,"newer":false,"downgrade":false,"updatable":false,"note":"并非通过安装脚本安装，无法在此更新","state":"idle","checkedAt":1792524538500},{"id":"claude","name":"Claude Code","installed":true,"latest":"2.1.304","newer":false,"downgrade":false,"updatable":true,"state":"idle","checkedAt":1792524538500},{"id":"codex","name":"Codex","installed":true,"latest":"0.163.0","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/codex，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792524538500},{"id":"dsh","name":"DeepSeek Harness","installed":true,"version":"0.2.0","latest":"0.2.1-rc.2","newer":true,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/dsh，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792524538500},{"id":"grok","name":"Grok Build","installed":true,"version":"1.0.62","latest":"1.0.62","newer":false,"downgrade":false,"updatable":false,"note":"安装在 /Users/zuozijian/.stillfail/remote/sessions/ac6b3f73efaa9bf32486b1ec56c103f8b4ed6ffe3291c2c0701fe4c5a9dd0644/work/e2e-C/ember/station/test/fake/grok，并非通过 npm 或 Homebrew 安装，需在该机器上手动更新","state":"idle","checkedAt":1792524538500}],"processesText":"没有运行中的 agent 进程","agentEnv":[],"drive":{"roots":[],"anywhere":true,"home":"/tmp/mbe2e-C/home"},"search":{"files":"spotlight","personal":false}},"betaOffered":false,"way":{"path":"直连","via":"direct"},"time":{"lastSeen":{"at":1792524540000,"ago":"刚刚","full":"10/21 03:29:00","until":"1 分钟内","past":true}},"joined":false}]},"w":1792524541493.244}
  #|{"in":{"id":18,"value":{"jobs":[],"servicesNote":"","jobsNote":"","current":0,"ended":0,"clear":[],"allText":"全部 0 个","clearText":"清除 0 个已结束的","hiddenText":"另有 0 个已停止或结束"}},"w":1792524541493.334}
  #|{"in":{"id":20,"ok":null},"w":1792524541493.339}
  #|{"step":"answered picture","w":1792524541494.262}
  #|{"in":{"id":3,"delta":[{"path":["openChat","01M5DCK6137JQCEQ8B5TFTN6HH"],"set":{"station":"01M5DCK6137JQCEQ8B5TFTN6HH/cbbf585bd7c84f70e681bea7a8f96d20e97f5dad1fc99faf26031e9a05d4d918","key":"ember:c-a572fed18a"}}]},"w":1792524541526.47}
  #|{"in":{"id":8,"delta":[{"path":["workspaces","01M5DCK6137JQCEQ8B5TFTN6HH","chat"],"set":{"station":"01M5DCK6137JQCEQ8B5TFTN6HH/cbbf585bd7c84f70e681bea7a8f96d20e97f5dad1fc99faf26031e9a05d4d918","key":"ember:c-a572fed18a"}}]},"w":1792524541526.485}
  #|{"in":{"id":17,"delta":[{"path":[0,"host"],"set":{"hostname":"3720-Mac-mini-1","os":"macOS 27.0.1","arch":"arm64","cpus":10,"cpuModel":"Apple M4","load":0.59,"cpuBusy":0.08,"uptimeSec":3903,"memory":{"totalBytes":17179869184,"usedBytes":8567668736,"swapUsedBytes":358738821},"disk":{"path":"/tmp/mbe2e-C/data","totalBytes":245107195904,"freeBytes":68129230848},"emberRssBytes":156006224,"checkedAt":1792524541522,"summary":"10 核 · 16 GB","line":"macOS 27.0.1 · 10 核 · 16 GB · 已运行 0 天","facts":["3720-Mac-mini-1","macOS 27.0.1","arm64 · 10 核","已运行 1 小时"],"meters":[{"label":"CPU","short":"CPU","percent":8,"left":92,"level":"ok","value":"8%","remaining":"空闲 92%","big":"92","unit":"%","title":"CPU 空闲","total":"负载 5.9","note":"负载 5.9 · Apple M4"},{"label":"内存","short":"内存","percent":50,"left":50,"level":"ok","value":"8.0 GB / 16.0 GB","remaining":"剩 8.0 G","big":"8.0","unit":"GB","title":"内存剩","total":"共 16 GB","note":"swap 0.3 GB"},{"label":"磁盘","short":"磁盘","percent":72,"left":28,"level":"ok","value":"剩余 63.5 GB / 228 GB","remaining":"剩 63.5 G","big":"63.5","unit":"GB","title":"磁盘剩","total":"共 228 GB"}],"identity":"Apple M4 · 16 GB · macOS 27.0.1","details":[{"label":"主机名","value":"3720-Mac-mini-1"},{"label":"芯片","value":"Apple M4 · 10 核 · arm64"},{"label":"已运行","value":"1 小时"},{"label":"still.fail","value":"进程占用 149 MB"}],"usage":"内存 8.0 GB / 16.0 GB · 磁盘 剩余 63.5 GB / 228 GB","emberText":"still.fail 149 MB"}},{"path":[0,"line"],"set":"Apple M4"},{"path":[0,"summary"],"set":"空闲 · Apple M4 · 16 GB · macOS 27.0.1"}]},"w":1792524541543.147}
  #|{"in":{"id":15,"delta":[{"path":["agents",0,"threads",0,"read"],"set":2},{"path":["agents",0,"threads",0,"unread"],"set":0},{"path":["archivable"],"set":true},{"path":["archiveOffered"],"set":true},{"path":["messages"],"key":["seq","outgoing"],"patch":[2,null],"ops":[{"path":["archive"],"set":true},{"path":["archiveCheck"],"set":{"text":"所有 agent 都做完了","recommended":true,"failed":false}}]},{"path":["thread","read"],"set":2},{"path":["thread","unread"],"set":0}]},"w":1792524541609.813}
  #|{"in":{"id":7,"delta":[{"path":["days"],"key":["daysAgo"],"patch":0,"ops":[{"path":["at"],"set":1792524527668},{"path":["items"],"key":["station","id"],"patch":["01M5DCK6137JQCEQ8B5TFTN6HH/cbbf585bd7c84f70e681bea7a8f96d20e97f5dad1fc99faf26031e9a05d4d918","ember:c-a572fed18a"],"ops":[{"path":["archivable"],"set":true},{"path":["settled"],"set":true},{"path":["stateText"],"set":"已完成：answered the question that was asked"},{"path":["unread"],"set":false},{"path":["tone"],"remove":true}]},{"path":["items"],"key":["station","id"],"move":["01M5DCK6137JQCEQ8B5TFTN6HH/cbbf585bd7c84f70e681bea7a8f96d20e97f5dad1fc99faf26031e9a05d4d918","ember:c-6c7209ebf6"],"before":["01M5DCK6137JQCEQ8B5TFTN6HH/cbbf585bd7c84f70e681bea7a8f96d20e97f5dad1fc99faf26031e9a05d4d918","ember:c-a572fed18a"]}]}]},"w":1792524541609.857}
  #|{"in":{"id":8,"delta":[{"path":["workspaces","01M5DCK6137JQCEQ8B5TFTN6HH","label"],"set":"1 个有新消息"},{"path":["workspaces","01M5DCK6137JQCEQ8B5TFTN6HH","unread"],"set":1}]},"w":1792524541609.881}
  #|{"in":{"id":19,"error":{"code":"picture","message":"无法加载图片：error sending request for url (https://example.test/p.png): client error (Connect): tls handshake eof"}},"w":1792524541659.806}
  #|{"step":"answered client.focus","w":1792524541677.041}
  #|{"step":"wait 300","w":1792524541693.837}
  #|{"step":"now until icon:archive","w":1792524541994.457}
  #|{"step":"tap icon:archive","w":1792524541994.509}
  #|{"step":"tap icon:archive","acted":true,"w":1792524542011.277}
  #|{"out":{"id":21,"call":"chat.archive","params":{"station":"01M5DCK6137JQCEQ8B5TFTN6HH/cbbf585bd7c84f70e681bea7a8f96d20e97f5dad1fc99faf26031e9a05d4d918","session":"ember:c-a572fed18a","archived":true,"thread":2}},"w":1792524542026.812}
  #|{"step":"answered chat.archive","w":1792524542031.587}
  #|{"in":{"id":7,"delta":[{"path":["days"],"key":["daysAgo"],"patch":0,"ops":[{"path":["items"],"key":["station","id"],"drop":["01M5DCK6137JQCEQ8B5TFTN6HH/cbbf585bd7c84f70e681bea7a8f96d20e97f5dad1fc99faf26031e9a05d4d918","ember:c-a572fed18a"]}]}]},"w":1792524542093.158}
  #|{"in":{"id":15,"delta":[{"path":["agents",0,"session","archivedAt"],"set":1792524542033},{"path":["agents",0,"session","process"],"set":"cold"},{"path":["agents",0,"session","processText"],"set":"已释放"},{"path":["agents",0,"session","titleText"],"set":"新对话"},{"path":["agents",0,"session","firstText"],"remove":true},{"path":["archived"],"set":true},{"path":["messages"],"key":["seq","outgoing"],"patch":[2,null],"ops":[{"path":["archive"],"remove":true},{"path":["archiveCheck"],"remove":true}]},{"path":["archivable"],"remove":true},{"path":["archiveOffered"],"remove":true},{"path":["pinned"],"remove":true}]},"w":1792524542093.203}
  #|{"in":{"id":17,"delta":[{"path":[0,"overview","counts","warm"],"set":0},{"path":[0,"overview","disk","freeBytes"],"set":68129124352}]},"w":1792524542093.269}
  #|{"in":{"id":21,"ok":{"id":2,"surface":"ember","channel":"EMBER","threadTs":"1792524541.002000","title":null,"createdBy":"alice@example.test","createdAt":1792524541002,"home":"ember:c-a572fed18a","hiddenAt":1792524542033,"hiddenBy":"manual","sessions":[{"thread":2,"session":"ember:c-a572fed18a","connect":"ember","joinedAt":1792524541002}],"last":2,"lastMessage":{"agentIdentity":{"model":null,"effort":null},"seq":2,"thread":2,"ts":"1792524541.133000","authorKind":"agent","author":"ember:c-a572fed18a","authorName":null,"text":"都弄好了 085454","attachments":[],"quotes":[],"declared":"final","createdAt":1792524541133,"editedAt":null,"ending":"all_done"},"read":2,"unread":0,"people":[{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"}],"firstText":"从栏上归档 085454 post:都弄好了 085454","channelName":null,"creator":{"id":"alice@example.test","name":"Name of alice","email":"alice@example.test","via":"cloud"},"xshare":null}},"w":1792524542093.314}
  #|{"step":"until =已归档","w":1792524542110.69}
  #|{"step":"wait 2600","w":1792524542110.7}
  #|{"out":{"id":22,"call":"client.focus","params":{"left":{"station":"01M5DCK6137JQCEQ8B5TFTN6HH/cbbf585bd7c84f70e681bea7a8f96d20e97f5dad1fc99faf26031e9a05d4d918","session":"ember:c-a572fed18a","thread":2}}},"w":1792524542344.379}
  #|{"out":{"id":23,"call":"chat.place","params":{"station":"01M5DCK6137JQCEQ8B5TFTN6HH/cbbf585bd7c84f70e681bea7a8f96d20e97f5dad1fc99faf26031e9a05d4d918","thread":2}},"w":1792524542344.44}
  #|{"out":{"id":15,"unsubscribe":true},"w":1792524542344.49}
  #|{"in":{"id":22,"ok":null},"w":1792524542359.831}
  #|{"in":{"id":23,"ok":null},"w":1792524542359.88}
  #|{"step":"now answered client.focus","w":1792524544726.846}
  #|{"step":"answered chat.place","w":1792524544743.505}
  #|{"step":"gone 从栏上归档 085454","w":1792524544760.13}
  #|{"step":"rest","w":1792524544760.14}
  #|{"step":"now rest","w":1792524544826.805}
  #|{"step":"","w":1792524544843.431}
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
  #|{"textrec":{"s":[16,600,0,"从栏上归档 085454 post:都弄好了 085454"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,28,3,1,15.875486381322958,29,4,1,15.875486381322958,30,5,1,3.95001220703125,-1,6,1,10.31976318359375,31,7,1,10.465335845947266,32,8,1,10.035783767700195,33,9,1,10.42471694946289,34,10,1,10.035783767700195,33,11,1,10.42471694946289,34,12,1,3.95001220703125,-1,13,1,9.824199676513672,35,14,1,9.432537078857422,36,15,1,8.471200942993164,37,16,1,5.973020553588867,38,17,1,4.952056884765625,39,18,1,15.875486381322958,40,19,1,15.875486381322958,41,20,1,15.875486381322958,42,21,1,15.875486381322958,43,22,1,3.95001220703125,-1,23,1,10.31976318359375,31,24,1,10.465335845947266,32,25,1,10.035783767700195,33,26,1,10.42471694946289,34,27,1,10.035783767700195,33,28,1,10.42471694946289,34]}}
  #|{"textrec":{"m":[16,600,0],"r":[15.46875,3.375,23]}}
  #|{"textrec":{"s":[14,400,0,"都弄好了 085454"],"r":[0,1,13.891050583657588,44,1,1,13.891050583657588,45,2,1,13.891050583657588,46,3,1,13.891050583657588,47,4,1,3.787109375,-1,5,1,8.66796875,48,6,1,8.791015625,49,7,1,8.50390625,50,8,1,8.859375,51,9,1,8.50390625,50,10,1,8.859375,51]}}
  #|{"textrec":{"m":[14,400,0],"r":[13.53515625,2.953125,20]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 post:你好，我是测试用的 agent"],"r":[0,1,15.875486381322958,52,1,1,15.875486381322958,53,2,1,15.875486381322958,52,3,1,15.875486381322958,54,4,1,15.875486381322958,55,5,1,15.875486381322958,56,6,1,15.875486381322958,57,7,1,15.875486381322958,58,8,1,3.95001220703125,-1,9,1,9.824199676513672,35,10,1,9.432537078857422,36,11,1,8.471200942993164,37,12,1,5.973020553588867,38,13,1,4.952056884765625,39,14,1,15.875486381322958,59,15,1,15.875486381322958,42,16,1,16.09338521400778,60,17,1,15.875486381322958,61,18,1,15.875486381322958,62,19,1,15.87548638132293,54,20,1,15.875486381322958,55,21,1,15.875486381322958,63,22,1,15.875486381322958,56,23,1,3.95001220703125,-1,24,1,8.899068832397461,64,25,1,9.801153182983398,65,26,1,9.127458572387695,66,27,1,9.466253280639648,67,28,1,5.999713897705078,38]}}
  #|{"textrec":{"s":[14,400,0,"你好，我是测试用的 agent"],"r":[0,1,13.891050583657588,68,1,1,13.891050583657588,46,2,1,14.081712062256813,69,3,1,13.891050583657588,70,4,1,13.891050583657588,71,5,1,13.891050583657588,72,6,1,13.891050583657588,73,7,1,13.891050583657588,74,8,1,13.891050583657588,75,9,1,3.787109375000014,-1,10,1,7.57421875,76,11,1,8.380859375,77,12,1,7.84765625,78,13,1,8.0185546875,79,14,1,4.935546875,80]}}
  #|{"textrec":{"s":[16,600,0,"…"],"r":[0,1,14.076484680175781,81]}}
  #|{"textrec":{"s":[16,600,0,"端到端测试的对话 post:你好，我是测试用的…"],"r":[0,1,15.875486381322958,52,1,1,15.875486381322958,53,2,1,15.875486381322958,52,3,1,15.875486381322958,54,4,1,15.875486381322958,55,5,1,15.875486381322958,56,6,1,15.875486381322958,57,7,1,15.875486381322958,58,8,1,3.95001220703125,-1,9,1,9.824199676513672,35,10,1,9.432537078857422,36,11,1,8.471200942993164,37,12,1,5.973020553588867,38,13,1,4.952056884765625,39,14,1,15.875486381322958,59,15,1,15.875486381322958,42,16,1,16.09338521400778,60,17,1,15.875486381322958,61,18,1,15.875486381322958,62,19,1,15.87548638132293,54,20,1,15.875486381322958,55,21,1,15.875486381322958,63,22,1,15.875486381322958,56,23,1,14.076484680175781,81]}}
  #|{"textrec":{"g":18,"r":[51,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":19,"r":[69,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":20,"r":[86,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":21,"r":[104,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":22,"r":[121,0,15,16,0,-13,0]}}
  #|{"textrec":{"g":23,"r":[137,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":24,"r":[154,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":25,"r":[172,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":26,"r":[190,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":27,"r":[209,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":28,"r":[227,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":29,"r":[245,0,16,17,0,-14,0]}}
  #|{"textrec":{"g":30,"r":[262,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":31,"r":[280,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":32,"r":[292,0,12,15,-1,-13,0]}}
  #|{"textrec":{"g":33,"r":[305,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":34,"r":[317,0,12,14,-1,-13,0]}}
  #|{"textrec":{"g":35,"r":[330,0,11,14,0,-10,0]}}
  #|{"textrec":{"g":36,"r":[342,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":37,"r":[354,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":38,"r":[366,0,8,14,-1,-12,0]}}
  #|{"textrec":{"g":39,"r":[375,0,5,12,0,-10,0]}}
  #|{"textrec":{"g":40,"r":[381,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":41,"r":[399,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":42,"r":[417,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":43,"r":[435,0,15,16,0,-13,0]}}
  #|{"textrec":{"g":44,"r":[451,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":45,"r":[467,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":46,"r":[483,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":47,"r":[500,0,13,15,0,-12,0]}}
  #|{"textrec":{"g":48,"r":[514,0,10,14,-1,-12,0]}}
  #|{"textrec":{"g":49,"r":[525,0,11,14,-1,-12,0]}}
  #|{"textrec":{"g":50,"r":[537,0,9,13,0,-11,0]}}
  #|{"textrec":{"g":51,"r":[547,0,11,12,-1,-11,0]}}
  #|{"textrec":{"g":52,"r":[559,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":53,"r":[577,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":54,"r":[595,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":55,"r":[613,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":56,"r":[632,0,16,17,0,-14,0]}}
  #|{"textrec":{"g":57,"r":[649,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":58,"r":[667,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":59,"r":[686,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":60,"r":[704,0,6,8,0,-4,0]}}
  #|{"textrec":{"g":61,"r":[711,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":62,"r":[730,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":63,"r":[748,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":81,"r":[765,0,14,6,0,-4,0]}}
  #|{"textrec":{"g":68,"r":[780,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":69,"r":[796,0,5,7,0,-3,0]}}
  #|{"textrec":{"g":70,"r":[802,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":71,"r":[819,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":72,"r":[835,0,15,16,-1,-13,0]}}
  #|{"textrec":{"g":73,"r":[851,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":74,"r":[868,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":75,"r":[884,0,14,16,0,-13,0]}}
  #|{"textrec":{"g":76,"r":[899,0,9,11,-1,-9,0]}}
  #|{"textrec":{"g":77,"r":[909,0,10,13,-1,-9,0]}}
  #|{"textrec":{"g":78,"r":[920,0,10,11,-1,-9,0]}}
  #|{"textrec":{"g":79,"r":[931,0,9,10,0,-9,0]}}
  #|{"textrec":{"g":80,"r":[941,0,7,13,-1,-11,0]}}
  #|{"textrec":{"ib":["33d1dfbf90932d3b",1241,64],"r":[17,17,17,17]}}
  #|{"textrec":{"ib":["182b7158e0c0cae1",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["d61ec6305f7d8c8b",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"ib":["8bf9607b651cec61",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"m":[16,400,0],"r":[15.46875,3.375,23]}}
  #|{"textrec":{"s":[8,600,0,"N"],"r":[0,1,6.271738052368164,82]}}
  #|{"textrec":{"m":[8,600,0],"r":[7.734375,1.6875,11]}}
  #|{"textrec":{"s":[13,500,0,"以下是新消息"],"r":[0,1,12.898832684824903,83,1,1,12.898832684824903,84,2,1,12.898832684824903,85,3,1,12.898832684824903,86,4,1,12.898832684824896,87,5,1,12.898832684824896,88]}}
  #|{"textrec":{"m":[13,500,0],"r":[12.568359375,2.7421875,18]}}
  #|{"textrec":{"s":[15,650,0,"默认模型"],"r":[0,1,14.883268482490273,89,1,1,14.883268482490273,90,2,1,14.883268482490273,91,3,1,14.883268482490273,92]}}
  #|{"textrec":{"m":[15,650,0],"r":[14.501953125,3.1640625,21]}}
  #|{"textrec":{"s":[10,400,0,"刚刚"],"r":[0,1,9.941634241245136,93,1,1,9.941634241245136,93]}}
  #|{"textrec":{"m":[10,400,0],"r":[9.66796875,2.109375,14]}}
  #|{"textrec":{"s":[15,400,0,"都弄好了 085454"],"r":[0,1,14.883268482490273,94,1,1,14.883268482490273,95,2,1,14.883268482490273,96,3,1,14.883268482490273,97,4,1,3.984375,-1,5,1,9.2138671875,98,6,1,9.345703125,99,7,1,9.0380859375,100,8,1,9.4189453125,101,9,1,9.0380859375,100,10,1,9.4189453125,101]}}
  #|{"textrec":{"s":[16,400,0,"从栏上归档 085454 post:都弄好了 085454"],"r":[0,1,15.875486381322958,102,1,1,15.875486381322958,103,2,1,15.875486381322958,104,3,1,15.875486381322958,105,4,1,15.875486381322958,106,5,1,4.1875,-1,6,1,9.765625,107,7,1,9.90625,108,8,1,9.578125,109,9,1,9.984375,110,10,1,9.578125,109,11,1,9.984375,110,12,1,4.1875,-1,13,1,9.453125,111,14,1,9.140625,112,15,1,8.0234375,113,16,1,5.4609375,114,17,1,4.4375,115,18,1,15.875486381322958,116,19,1,15.875486381322958,117,20,1,15.875486381322958,118,21,1,15.875486381322958,119,22,1,4.1875,-1,23,1,9.765625,107,24,1,9.90625,108,25,1,9.578125,109,26,1,9.984375,110,27,1,9.578125,109,28,1,9.984375,110]}}
  #|{"textrec":{"s":[16,600,0,"从栏上归档 085454 post:都…"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,28,3,1,15.875486381322958,29,4,1,15.875486381322958,30,5,1,3.95001220703125,-1,6,1,10.31976318359375,31,7,1,10.465335845947266,32,8,1,10.035783767700195,33,9,1,10.42471694946289,34,10,1,10.035783767700195,33,11,1,10.42471694946289,34,12,1,3.95001220703125,-1,13,1,9.824199676513672,35,14,1,9.432537078857422,36,15,1,8.471200942993164,37,16,1,5.973020553588867,38,17,1,4.952056884765625,39,18,1,15.875486381322958,40,19,1,14.076484680175781,81]}}
  #|{"textrec":{"ib":["504a4df6beac534a",3232,64],"r":[28,28,28,28]}}
  #|{"textrec":{"s":[12,400,0,"studio"],"r":[0,1,6.251953125,120,1,1,4.330078125,121,2,1,7.001953125,122,3,1,7.37109375,123,4,1,2.96484375,124,5,1,7.08984375,125]}}
  #|{"textrec":{"m":[12,400,0],"r":[11.6015625,2.53125,17]}}
  #|{"textrec":{"s":[16,600,0,"从栏上归档 085454 pos…"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,28,3,1,15.875486381322958,29,4,1,15.875486381322958,30,5,1,3.95001220703125,-1,6,1,10.31976318359375,31,7,1,10.465335845947266,32,8,1,10.035783767700195,33,9,1,10.42471694946289,34,10,1,10.035783767700195,33,11,1,10.42471694946289,34,12,1,3.95001220703125,-1,13,1,9.824199676513672,35,14,1,9.432537078857422,36,15,1,8.497894287109375,37,16,1,14.076484680175781,81]}}
  #|{"textrec":{"g":94,"r":[949,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":95,"r":[966,0,16,16,-1,-13,0]}}
  #|{"textrec":{"g":96,"r":[983,0,16,17,-1,-14,0]}}
  #|{"textrec":{"g":97,"r":[1000,0,14,16,0,-13,0]}}
  #|{"textrec":{"g":98,"r":[1015,0,11,14,-1,-12,0]}}
  #|{"textrec":{"g":99,"r":[1027,0,11,14,-1,-12,0]}}
  #|{"textrec":{"g":100,"r":[1039,0,10,14,0,-12,0]}}
  #|{"textrec":{"g":101,"r":[1050,0,11,13,-1,-12,0]}}
  #|{"textrec":{"ib":["11ba9484460f477d",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"ib":["a1e7be43eb966606",2026,64],"r":[22,22,22,22]}}
  #|{"textrec":{"ib":["c7a6d30e254a5910",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"g":102,"r":[1062,0,18,17,-1,-14,0]}}
  #|{"textrec":{"g":103,"r":[1081,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":104,"r":[1099,0,17,16,-1,-14,0]}}
  #|{"textrec":{"g":105,"r":[1117,0,16,17,0,-14,0]}}
  #|{"textrec":{"g":106,"r":[1134,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":107,"r":[1152,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":108,"r":[1164,0,11,15,0,-13,0]}}
  #|{"textrec":{"g":109,"r":[1176,0,10,15,0,-13,0]}}
  #|{"textrec":{"g":110,"r":[1187,0,12,14,-1,-13,0]}}
  #|{"textrec":{"g":111,"r":[1200,0,10,14,0,-10,0]}}
  #|{"textrec":{"g":112,"r":[1211,0,11,12,-1,-10,0]}}
  #|{"textrec":{"g":113,"r":[1223,0,10,12,-1,-10,0]}}
  #|{"textrec":{"g":114,"r":[1234,0,8,14,-1,-12,0]}}
  #|{"textrec":{"g":115,"r":[1243,0,5,11,0,-9,0]}}
  #|{"textrec":{"g":116,"r":[1249,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":117,"r":[1267,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":118,"r":[1285,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":119,"r":[1303,0,15,16,0,-13,0]}}
  #|{"textrec":{"g":89,"r":[1319,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":90,"r":[1337,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":91,"r":[1355,0,17,16,-1,-13,0]}}
  #|{"textrec":{"g":92,"r":[1373,0,16,16,-1,-13,0]}}
  #|{"textrec":{"s":[16,400,0,"发消息"],"r":[0,1,15.875486381322958,126,1,1,15.875486381322958,127,2,1,15.875486381322958,128]}}
  #|{"textrec":{"g":126,"r":[1390,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":127,"r":[1408,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":128,"r":[1426,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":93,"r":[1444,0,11,11,-1,-9,0]}}
  #|{"textrec":{"g":83,"r":[1456,0,14,15,0,-12,0]}}
  #|{"textrec":{"g":84,"r":[1471,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":85,"r":[1486,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":86,"r":[1501,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":87,"r":[1517,0,14,15,-1,-12,0]}}
  #|{"textrec":{"g":88,"r":[1532,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":82,"r":[1548,0,8,8,-1,-7,0]}}
  #|{"textrec":{"s":[12,500,0,"归档"],"r":[0,1,11.918287937743191,129,1,1,11.918287937743191,130]}}
  #|{"textrec":{"m":[12,500,0],"r":[11.6015625,2.53125,17]}}
  #|{"textrec":{"s":[14,400,0,"answered the question that was asked"],"r":[0,1,7.57421875,76,1,1,8.0185546875,79,2,1,7.0751953125,131,3,1,10.4521484375,132,4,1,7.7109375,78,5,1,5.0791015625,133,6,1,7.7451171875,78,7,1,8.44921875,134,8,1,3.787109375,-1,9,1,4.935546875,80,10,1,8.0869140625,135,11,1,7.84765625,78,12,1,3.787109375,-1,13,1,8.380859375,136,14,1,8.0185546875,137,15,1,7.84765625,78,16,1,7.1435546875,131,17,1,4.9013671875,80,18,1,3.30859375,138,19,1,8.12109375,139,20,1,8.0185546875,79,21,1,3.787109375,-1,22,1,4.935546875,80,23,1,8.0869140625,135,24,1,7.57421875,76,25,1,4.935546875,80,26,1,3.787109375,-1,27,1,10.5888671875,132,28,1,7.4716796875,76,29,1,7.177734375,131,30,1,3.787109375,-1,31,1,7.57421875,76,32,1,7.177734375,131,33,1,7.2802734375,140,34,1,7.6767578125,78,35,1,8.44921875,134]}}
  #|{"textrec":{"s":[16,400,0,"…"],"r":[0,1,12.5625,141]}}
  #|{"textrec":{"s":[16,400,0,"从栏上归档 085454 post:都弄好了 085…"],"r":[0,1,15.875486381322958,102,1,1,15.875486381322958,103,2,1,15.875486381322958,104,3,1,15.875486381322958,105,4,1,15.875486381322958,106,5,1,4.1875,-1,6,1,9.765625,107,7,1,9.90625,108,8,1,9.578125,109,9,1,9.984375,110,10,1,9.578125,109,11,1,9.984375,110,12,1,4.1875,-1,13,1,9.453125,111,14,1,9.140625,112,15,1,8.0234375,113,16,1,5.4609375,114,17,1,4.4375,115,18,1,15.875486381322958,116,19,1,15.875486381322958,117,20,1,15.875486381322958,118,21,1,15.875486381322958,119,22,1,4.1875,-1,23,1,9.765625,107,24,1,9.90625,108,25,1,9.3046875,109,26,1,12.2890625,142]}}
  #|{"textrec":{"g":142,"r":[1557,0,13,5,-0.2734375,-3,0]}}
  #|{"textrec":{"g":131,"r":[1571,0,9,11,-1,-9,0]}}
  #|{"textrec":{"g":132,"r":[1581,0,13,10,-1,-9,0]}}
  #|{"textrec":{"g":133,"r":[1595,0,6,10,0,-9,0]}}
  #|{"textrec":{"g":134,"r":[1602,0,10,14,-1,-12,0]}}
  #|{"textrec":{"g":135,"r":[1613,0,9,13,0,-12,0]}}
  #|{"textrec":{"g":136,"r":[1623,0,10,13,-1,-9,0]}}
  #|{"textrec":{"g":137,"r":[1634,0,9,11,0,-9,0]}}
  #|{"textrec":{"g":138,"r":[1644,0,5,13,-1,-12,0]}}
  #|{"textrec":{"g":139,"r":[1650,0,10,11,-1,-9,0]}}
  #|{"textrec":{"g":140,"r":[1661,0,9,13,0,-12,0]}}
  #|{"textrec":{"g":120,"r":[1671,0,8,10,-1,-8,0]}}
  #|{"textrec":{"g":121,"r":[1680,0,6,11,-1,-9,0]}}
  #|{"textrec":{"g":122,"r":[1687,0,9,10,-1,-8,0]}}
  #|{"textrec":{"g":123,"r":[1697,0,9,12,-1,-10,0]}}
  #|{"textrec":{"g":124,"r":[1707,0,5,11,-1,-10,0]}}
  #|{"textrec":{"g":125,"r":[1713,0,9,10,-1,-8,0]}}
  #|{"textrec":{"s":[16,600,0,"从栏上归档 085454 p…"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,28,3,1,15.875486381322958,29,4,1,15.875486381322958,30,5,1,3.95001220703125,-1,6,1,10.31976318359375,31,7,1,10.465335845947266,32,8,1,10.035783767700195,33,9,1,10.42471694946289,34,10,1,10.035783767700195,33,11,1,10.42471694946289,34,12,1,3.95001220703125,-1,13,1,9.721336364746094,35,14,1,13.973621368408203,143]}}
  #|{"textrec":{"g":143,"r":[1723,0,14,6,-0.10286331176757812,-4,0]}}
  #|{"textrec":{"ib":["5011346a34665c45",1688,64],"r":[20,20,20,20]}}
  #|{"textrec":{"s":[16,600,0,"从栏上归档 085454…"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,28,3,1,15.875486381322958,29,4,1,15.875486381322958,30,5,1,3.95001220703125,-1,6,1,10.31976318359375,31,7,1,10.465335845947266,32,8,1,10.035783767700195,33,9,1,10.42471694946289,34,10,1,10.035783767700195,33,11,1,10.237863540649414,34,12,1,13.889631271362305,144]}}
  #|{"textrec":{"g":144,"r":[1738,0,14,6,-0.18685340881347656,-4,0]}}
  #|{"textrec":{"ib":["ddfdc2820df8a676",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"ib":["2b45ffca62dc37ab",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"s":[16,600,0,"从栏上归档 08545…"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,28,3,1,15.875486381322958,29,4,1,15.875486381322958,30,5,1,3.95001220703125,-1,6,1,10.31976318359375,31,7,1,10.465335845947266,32,8,1,10.035783767700195,33,9,1,10.42471694946289,34,10,1,9.737607955932617,33,11,1,13.778308868408203,145]}}
  #|{"textrec":{"g":145,"r":[1753,0,14,6,-0.2981758117675781,-4,0]}}
  #|{"textrec":{"s":[16,400,0,"从栏上归档 085454 post:都弄好了 0…"],"r":[0,1,15.875486381322958,102,1,1,15.875486381322958,103,2,1,15.875486381322958,104,3,1,15.875486381322958,105,4,1,15.875486381322958,106,5,1,4.1875,-1,6,1,9.765625,107,7,1,9.90625,108,8,1,9.578125,109,9,1,9.984375,110,10,1,9.578125,109,11,1,9.984375,110,12,1,4.1875,-1,13,1,9.453125,111,14,1,9.140625,112,15,1,8.0234375,113,16,1,5.4609375,114,17,1,4.4375,115,18,1,15.875486381322958,116,19,1,15.875486381322958,117,20,1,15.875486381322958,118,21,1,15.875486381322958,119,22,1,4.1875,-1,23,1,9.453125,107,24,1,12.25,146]}}
  #|{"textrec":{"ib":["da3b3bab9d01d4f7",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["9c5de0825931e534",866,64],"r":[14,14,14,14]}}
  #|{"textrec":{"ib":["3e89fb0d7a2d2be5",656,64],"r":[12,12,12,12]}}
  #|{"textrec":{"s":[13,400,0,"已归档，还原后才能发送消息。 "],"r":[0,1,12.898832684824903,147,1,1,12.898832684824903,148,2,1,12.898832684824903,149,3,1,13.075875486381321,150,4,1,12.898832684824903,151,5,1,12.89883268482491,152,6,1,12.898832684824896,153,7,1,12.898832684824896,154,8,1,12.898832684824896,155,9,1,12.898832684824896,156,10,1,12.898832684824896,157,11,1,12.898832684824896,158,12,1,12.898832684824896,159,13,1,13.075875486381335,160,14,1,3.580078125,-1]}}
  #|{"textrec":{"s":[13,400,0,"还原对话"],"r":[0,1,12.898832684824903,151,1,1,12.898832684824903,152,2,1,12.898832684824903,161,3,1,12.898832684824903,162]}}
  #|{"textrec":{"s":[14,400,0,"已归档"],"r":[0,1,13.891050583657588,163,1,1,13.891050583657588,164,2,1,13.891050583657588,165]}}
  #|{"textrec":{"g":147,"r":[1768,0,13,13,0,-11,0]}}
  #|{"textrec":{"g":148,"r":[1782,0,14,15,-1,-12,0]}}
  #|{"textrec":{"g":149,"r":[1797,0,14,15,-1,-12,0]}}
  #|{"textrec":{"g":150,"r":[1812,0,5,7,0,-3,0]}}
  #|{"textrec":{"g":151,"r":[1818,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":152,"r":[1834,0,14,14,-1,-11,0]}}
  #|{"textrec":{"g":153,"r":[1849,0,14,15,-1,-12,0]}}
  #|{"textrec":{"g":154,"r":[1864,0,14,15,-1,-12,0]}}
  #|{"textrec":{"g":155,"r":[1879,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":156,"r":[1895,0,14,15,-1,-12,0]}}
  #|{"textrec":{"g":157,"r":[1910,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":158,"r":[1926,0,14,15,-1,-12,0]}}
  #|{"textrec":{"g":159,"r":[1941,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":160,"r":[1957,0,6,6,0,-3,0]}}
  #|{"textrec":{"g":161,"r":[1964,0,15,15,-1,-12,0]}}
  #|{"textrec":{"g":162,"r":[1980,0,15,15,-1,-12,0]}}
  #|{"textrec":{"s":[16,400,0,"还原对话后才能发送"],"r":[0,1,15.875486381322958,166,1,1,15.875486381322958,167,2,1,15.875486381322958,168,3,1,15.875486381322958,169,4,1,15.875486381322958,170,5,1,15.875486381322958,171,6,1,15.875486381322958,172,7,1,15.875486381322958,126,8,1,15.875486381322958,173]}}
  #|{"textrec":{"g":166,"r":[1996,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":167,"r":[2014,0,17,17,-1,-14,0]}}
  #|{"textrec":{"g":168,"r":[0,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":169,"r":[18,20,18,17,-1,-14,0]}}
  #|{"textrec":{"g":170,"r":[37,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":171,"r":[55,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":172,"r":[73,20,17,17,-1,-14,0]}}
  #|{"textrec":{"g":173,"r":[91,20,17,17,-1,-14,0]}}
  #|{"textrec":{"ib":["d47558d7de7986e5",1382,64],"r":[18,18,18,18]}}
  #|{"textrec":{"g":163,"r":[109,20,14,14,0,-12,0]}}
  #|{"textrec":{"g":164,"r":[124,20,15,16,-1,-13,0]}}
  #|{"textrec":{"g":165,"r":[140,20,15,16,-1,-13,0]}}
  #|{"textrec":{"s":[16,600,0,"从栏上归档 085454 po…"],"r":[0,1,15.875486381322958,26,1,1,15.875486381322958,27,2,1,15.875486381322958,28,3,1,15.875486381322958,29,4,1,15.875486381322958,30,5,1,3.95001220703125,-1,6,1,10.31976318359375,31,7,1,10.465335845947266,32,8,1,10.035783767700195,33,9,1,10.42471694946289,34,10,1,10.035783767700195,33,11,1,10.42471694946289,34,12,1,3.95001220703125,-1,13,1,9.824199676513672,35,14,1,9.329673767089844,36,15,1,13.973621368408203,143]}}
