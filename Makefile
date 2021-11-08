all     :; dapp --use solc:0.8.9 build
clean   :; dapp clean
test    :; ./test.sh $(match) $(runs)
