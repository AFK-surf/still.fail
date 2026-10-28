# Sourced by mbui's scripts/ios.sh for sffix (MBUI_IOS_HOOK): what asks the person for a told story's vault
# (src/sffix/person.m: LocalAuthentication's prompt, Touch ID or Face ID).
APP_EXTRA="--extra=src/sffix/person.m"
APP_LINK="-framework LocalAuthentication"
