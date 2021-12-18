# DAI Wormhole

DAI Wormhole facility allows users to fast teleport DAI between "domains", i.e. different chains that have a settlement mechanism with Ethereum L1. If DAI is teleported from L2 -> L1, this is equvialent to "fast withdrawal". DAI will be minted on L1 as soon as the transaction is confirmed on L2 and sent to the user, and when transaction eventually settles on L1, DAI will be released from L1 Bridge escrow (to have DAI on L2 in the first place, it had to be put on L1 escrow some time before) and burned. 

If DAI is teleported from L2 -> L2, on the source domain it will be burned and on the destination domain it will be minted, while settlement process on L1 will eventually move DAI from source domain bridge escrow to destination domain bridge escrow.

## Roles

* **Initiator** - person initiating DAI transfer by calling `initiateWormhole` . They can optionally specify Operator and Receiver 
* **Operator** - person (or specified third party) responsible for initiating minting process on destination domain by providing (in the fast path) Oracle attestations. Can call `requestMint` on `WormholeOracleAuth`
* **Receiver** - person receiving minted DAI on a destination domain

## DAI Wormhole L2 → L1 (aka fast withdrawals) 

![FastWithdrawal](./docs/fw.png?raw=true)


### Normal (fast) path

To fast withdraw DAI from L2, user:

* Calls `l2bridge.initiateWormhole()` - this burns DAI on L2 and sends `finalizeRegisterWormhole()` L2 -> L1 message to withdraw DAI from L2 bridge. This message, in normal cicumstances, will never be relayed and it will eventually expire in L1 message queue
* Waits for withdrawal attestations to be available and obtains them via Oracle API
* Calls `WormholeOracleAuth.requestMint(WormholeGUID wormholeGUID, bytes signatures, uint256 maxFee)` which will:
  * Check if `sender` is `operator` 
  *   Check if enough valid attestations (sigs) are provided
  *   Call `WormholeJoin.registerWormholeAndWithdraw(wormholeGUID, maxfee)` which will
        * Check if this wormhole hasn't been used before
        * Check if the debt ceiling hasn't been reached
        * Check the current fee via `WormholeFees`
        * `vat.slip`, `vat.frob`, `daiJoin.exit`

### Settlement

Settlement process moves DAI from L1 Bridge to WormholeJoin to clear the debt that accumulates there. It is triggered by keepers.

* On L2 keeper calls `l2bridge.flush()`
* L2 -> L1 message `finalizeFlush()` is sent to `L1Bridge` and relayed by a keeper
* `L1Bridge` upon receiving `finalizeFlush()` calls `WormholeRouter.settle()` which will
    * Transfer `DAI` from bridges' escrow to `WormholeJoin`
    * Call `WormholeJoin.settle()` which will use transfered DAI to clear any outstanding debt by calling `daiJoin.join`, `vat.frob`, `vat.slip`

### Slow (emergency) path

If attestations cannot be obtained (Oracles down or censoring), user needs to wait so that L2 message is confirmed on L1 (on Optimistic Rollups that typically is 7 days, on zkRollups it can be anything between few hours to a day). Once L2->L1 message can be relayed, user:

* Relays `finalizeRegisterWormhole()`  message to `L1Bridge`
* `L1Bridge` upon receiving `finalizeRegisterWormhole()` will call `requestMint()` on `WormholeRouter` which will:
    * Call `WormholeJoin.registerWormholeAndWithdraw(wormholeGUID, maxfee)` which will
        * Check if this wormhole hasn't been used before
        * Check if the debt ceiling hasn't been reached
        * Check the current fee via `WormholeFees`
        * `vat.slip`, `vat.frob`, `daiJoin.exit`

## DAI Wormhole L2→L2

![Wormhole](./docs/l2.png?raw=true)

### Normal (fast) path

Wormholing DAI to another L2 domain is very similar, the only difference is that DAI is minted on a target Domain rather then on L1. For this scheme to work MakerDAO `MCD` sytem needs to be deployed on a target domain. 

### Settlement

Settlement process is very similar, however DAI is transfered from source domain bridge on L1 to target domain bridge on L1 before rather then moved to `L1 MCD` to pay the debt. This DAI, now in target domain bridge will be backing DAI that is minted on L2 target domain.

### Slow (emergency) path

For a slow path, once L2->L1 message from the source domain is received on L1 and can be relayed, user can relay the message which fill call `finalizeRequestMing()` on the target domain `L1Bridge`. This will pass L1->L2 message to `L2bridge` which will call `registerWormholeAndWithdraw()` on a `WormholeJoin` contract on target domain L2.

## Technical Documenation

Each Wormhole is described with the following struct:

```
struct WormholeGUID {
	bytes32 sourceDomain;
	bytes32 targetDomain;
	address receiver;
	address operator;
	uint128 amount;
	uint80 nonce;
	uint48 timestamp;
}
```

### Contracts

**`WormholeRouter`**
* `requestMint(WormholeGUID calldata wormholeGUID, uint256 maxFee)` - callable only by `L1Bridge`, requests `WormholeJoin` to mint DAI for the receiver of the wormhole
* `function settle(bytes32 targetDomain, uint256 batchedDaiToFlush)` - callable only by the `L1bridge`, handles settlement process by requesting either `WormholeJoin` or target domain `L1 bridge` to settle DAI

**`WormholeOracleAuth`**
* `requestMint(WormholeGUID calldata wormholeGUID, bytes calldata signatures, uint256 maxFee)` - callable only by the wormhole operator, requests `WormholeJoin` to mint DAI for the receiver of the wormhole provided required number of Oracle attestations are given

**`WormholeJoin`**
* `registerWormholeAndWithdraw(WormholeGUID calldata wormholeGUID, uint256 maxFee)` - callable either by `WormholeOracleAuth` (fast path) or by `WormholeRouter` (slow path), mints and withdraws DAI from the wormhole. If debt ceiling is reached, partial amount will be withdrawn and anything pending can be withdrawn using `withdrawPending()` later
* `withdrawPending(WormholeGUID calldata wormholeGUID, uint256 maxFee)` - callable by wormhole operator, withdraws any pending DAI from a wormhole
* `settle(bytes32 sourceDomain, uint256 batchedDaiToFlush)` - callable only by `WormhomeRouter`, settles DAI debt

**`WormholeFees`**
* `getFees(WormholeGUID calldata wormholeGUID) (uint256 fees)` - interface for getting current fee. Various implementations can be provided by the governance with different fee structures

### Authorization
* `WormholeOracleAuth`
  * `RequestMint` - operator (set by the user initiating wormhole)
  * `rely`, `deny`, `file`, `addSigners`, `removeSigners` - auth (Governance)
* `WormholeRouter`
  * `requestMint` - L1 Bridge
  * `settle` - L1 Bridge
* `WormholeJoin` 
  * `rely`, `deny`, `file` - auth (Governance)
  * `registerWormholeAndWithdraw` - auth (`WormholeRouter`, `WormholeOracleAuth`)
  * `withdrawPending` - operator
  * `settle` - anyone (typically keeper)
* `L1WormholeBridge`
  * `finalizeFlush()` - L2 bridge
  * `finalizeRegisterWormhole()` - L2 bridge
* `L2DAIWormholeBridge`
  * `initalizeWormhole` - anyone (typically user)
  * `flush` - anyone (typically keeper)


## Risks
### Oracle censoring or oracle failure
If user is unable to obtain Oracle's attestations, slow path is taken - no user funds are at risk
### Oracle misfunction (wrong attestations)
If user is able to obtain fraudulant attestation (i.e. attesting that DAI on L2 is burn and withdrawn whereas in reality is not), this will result in bad debt - DAI minted in a wormhole will never be settled. This will result in bad debt that eventually will have to be healed through a standard MakerDAO debt healing processes. 
### Source domain compromised
### Target domain compromised 

