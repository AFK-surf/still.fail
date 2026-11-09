# Sourced by the upload and distribution scripts: the same identity from TestFlight through App Store.
# monoid's numeric App Store Connect ID is configured after its app record is created in Apple's console.
RELEASE_PRODUCT=${RELEASE_PRODUCT:-stillfail}
case $RELEASE_PRODUCT in
  stillfail)
    IOS_BUNDLE_ID=fail.still.iphone
    IOS_APP_NAME=still.fail
    IOS_EXPECTED_APP_GROUP=group.fail.still.iphone
    IOS_ASC_APP_ID=6818750243
    ;;
  monoid)
    IOS_BUNDLE_ID=build.monoid.iphone
    IOS_APP_NAME=monoid
    IOS_EXPECTED_APP_GROUP=group.build.monoid.iphone
    IOS_ASC_APP_ID=${MONOID_ASC_APP_ID:-}
    ;;
  *) echo 'testflight: product must be stillfail or monoid' >&2; exit 1 ;;
esac
