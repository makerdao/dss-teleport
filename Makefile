all     :; DAPP_BUILD_OPTIMIZE=1 DAPP_BUILD_OPTIMIZE_RUNS=200 dapp --use solc:0.8.13 build
clean   :; dapp clean
test    :; ./test.sh $(match) $(runs)
cov     :; DAPP_BUILD_OPTIMIZE=1 DAPP_BUILD_OPTIMIZE_RUNS=200 dapp --use solc:0.8.13 test -v --coverage --cov-match "src\/Wormhole"
