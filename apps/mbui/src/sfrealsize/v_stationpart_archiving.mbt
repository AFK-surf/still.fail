// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `stationPart archiving` whole on a
// workspace of real size.
///|
fn init {
  let asked =
    #|{"topic":"stationPart","scope":"ws","station":"ws/maple","part":"archiving"}
  let value =
    #|{"days":7,"slackDays":14,"reviewed":true,"canEdit":true,"mode":"reviewed","daysOffered":[1,3,7,30],"slackDaysOffered":[0,3,7,14,30],"daysOfferedText":["1 天","3 天","7 天","30 天"],"slackDaysOfferedText":["不归档","3 天","7 天","14 天","30 天"],"reviewText":"已开启 · Haiku 4.5","stalled":false,"lineText":"按模型判断 · 7 天 · Slack：14 天","modes":[{"mode":"off","label":"不自动归档","days":0,"reviewed":false,"allowed":true},{"mode":"idle","label":"空闲就归档","days":7,"reviewed":false,"allowed":true},{"mode":"reviewed","label":"按模型判断","days":7,"reviewed":true,"allowed":true}],"modeNote":"空闲超过下面的天数，并且归档建议判断为没有后续事项，才归档。"}
  put(asked, value)
}
