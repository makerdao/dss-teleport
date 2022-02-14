all     :; dapp --use solc:0.8.9 build
clean   :; dapp clean
test    :; ./test.sh $(match) $(runs)
cov     :; dapp --use solc:0.8.9 test -v --coverage --cov-match "src\/Wormhole"
