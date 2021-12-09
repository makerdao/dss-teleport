# DAI Wormhole

DAI Wormhole facility allows users to fast teleport DAI between "domains", i.e. different chains that have a settlement mechanism with Ethereum L1. If DAI is teleported from L2 -> L1, this is equvialent to "fast withdrawal". DAI will be minted on L1 as soon as the transaction is confirmed on L2 and sent to the user, and when transaction eventually settles on L1, DAI will be released from L1Gateway escrow (to have DAI on L2 in the frist place, it had to be put on L1 escrow some time before) and burned. 

If DAI is teleported from L2 -> L2, on the source domain it will be burned and on the destination domain it will be minted, while settlement process on L1 will eventually move DAI from source domain escrow to destination domain escrow.

Each Wormhole is described with the following struct:

```
struct WormholeGUID {
	bytes32 sourceDomain;
	bytes32 targetDomain;
	address receiver;
	address operator;
	uint128 amount;
	uint64 nonce;
	uint64 timestamp;
}
```


To fast withdraw DAI from L2, user:

1. Calls `l2bridge.initiateWormhole()` - this burns DAI on L2, sends `finalizeRegisterWormwhole()` L2 -> L1 message
2. Wait for withdrawal attestations to be available and obtains them via Oracle API
3. Calls `WormholeOracleAuth.requestMint(WormholeGUID wormholeGUID, bytes signatures, uint256 maxFee)` which will:
    1. Check if `sender` is `operator` 
    2. Check if enough valid attestations (sigs) are provided
    3.  Call `wormoholeJoin.registerWormholeAndWithdraw(wormholeGUID, maxfee)` which will
        1. Check if this wormhole hasn't been used before
        2. Check if the debt ceiling hasn't been reached
        3. Check the current fee via `WormholeFees`
        4. `vat.slip`, `vat.frob`, `daiJoin.exit`

If attestations cannot be obtained (Oracles down or censoring), user needs to wait so that L2 message is confirmed on L1 (on Optimistic Rollups that typically is 7 days, on zkRollups it can be anything between few hours to a day). Once message is confirmed, it will:

1. Relayer will relay L2->L1 message which will call `finalizeRegisterWormwhole()` method` on `L1Bridge`
2. This will call `WormholeRouter.requestMint()` which will:
    1. Call `wormholeJoin.registerWormholeAndWithdraw(wormholeGUID, maxfee) and follow the logic above


