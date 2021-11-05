all     :; dapp --use solc:0.6.12 build
clean   :; dapp clean
test    :; ./test.sh $(match) $(runs)
