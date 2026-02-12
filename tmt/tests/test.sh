#!/bin/bash
set -euox pipefail

cd ../../ || exit 1

source /etc/os-release
cat /etc/os-release
echo ${ID}-${VERSION_ID}
echo "This is test script!"

exit 0
