///|
#borrow(name)
extern "C" fn env(name : String) -> String = "mb_coredemo_env"

///|
/// Opens `url` in a browser ($BROWSER, else `open`): 0 when none could be started.
#borrow(url)
extern "C" fn open_url(url : String) -> Int = "mb_coredemo_open_url"
