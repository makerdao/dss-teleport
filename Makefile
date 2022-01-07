all     		:; dapp --use solc:0.8.9 build
clean   		:; dapp clean
test    		:; ./test.sh $(match) $(runs)
certora-join 	:; certoraRun --solc ~/.solc-select/artifacts/solc-0.8.9 certora/WormholeJoin.sol certora/FeesMock.sol certora/Auxiliar.sol src/test/mocks/VatMock.sol src/test/mocks/DaiMock.sol src/test/mocks/DaiJoinMock.sol --link WormholeJoin:vat=VatMock WormholeJoin:daiJoin=DaiJoinMock DaiJoinMock:vat=VatMock DaiJoinMock:dai=DaiMock --verify WormholeJoin:certora/WormholeJoin.spec --rule_sanity $(if $(rule),--rule $(rule),) --multi_assert_check
certora-router 	:; certoraRun --solc ~/.solc-select/artifacts/solc-0.8.9 certora/WormholeRouter.sol certora/WormholeJoinMock.sol src/test/mocks/DaiMock.sol --link WormholeRouter:dai=DaiMock --verify WormholeRouter:certora/WormholeRouter.spec --rule_sanity $(if $(rule),--rule $(rule),) --multi_assert_check
