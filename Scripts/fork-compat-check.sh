#!/bin/bash
#
# Linux-runnable check for the breaks a weekday upstream merge leaves behind.
# CI runs this before the Mac build. The daily sync agent should run it after
# the merge, before pushing the sync pull request.
#
#   ./Scripts/fork-compat-check.sh
#   ./Scripts/fork-compat-check.sh --fill-placeholders
#
# `--fill-placeholders` copies keys that exist in English and are missing from
# ja, ko, or zh-Hant, using the English line. zh-Hans is not filled. The
# localization check then runs, so a placeholder that does not match English
# still fails.

set -euo pipefail

cd "$(dirname "$0")/.."

status=0
python3 Scripts/fork-compat-check.py "$@" || status=1
./Scripts/check-localization.sh || status=1
exit "$status"
