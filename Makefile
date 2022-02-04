all     :; dapp --use solc:0.8.9 build
clean   :; dapp clean
test    :; ./test.sh $(match) $(runs)
cov     :; dapp --use solc:0.8.9 test -v --coverage --cov-match "Wormhole.*\.t\.sol"
snap    :; dapp --use solc:0.8.9 snapshot