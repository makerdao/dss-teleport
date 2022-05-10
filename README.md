# DAI Teleport

DAI Teleport facility allows users to fast teleport DAI between "domains", i.e. different chains that have a settlement mechanism with Ethereum L1. 

If DAI is teleported from L2 -> L1, this is equivalent to "fast withdrawal". First, DAI will be burned on L2, then minted on L1 and sent to the user as soon as the L2 transaction is confirmed. After a while, during a settlement process, DAI will be released from L1 Bridge escrow (to have DAI on L2 in the first place, it had to be put on L1 escrow some time before) and burned. 

If DAI is teleported from L2 -> L2, on the source domain it will be burned and on the destination domain it will be minted, while settlement process on L1 will eventually move DAI from source domain bridge escrow to destination domain bridge escrow.

## Security

Smart contracts stored in this repository are part of the bug bounty. To disclose any vulnerability please refer to the [bug bounty page](https://immunefi.com/bounty/makerdao/).

## Domains, Gateways and Teleport Router

On L1 each Domain must be associated with a Gateway, that is a contract that supports `requestMint()` and `settle()` operations. For any L2 Domain, Gateway is a bridge from L1 -> L2, whereas for the L1 Domain, Gateway is the `TeleportJoin` adapter contract.

Teleport Router keeps track of each Domain's Gateway and routes `requestMint()` or `settle()` requests to the appropriate contracts.

![Domains](./docs/domains.png?raw=true)


## Roles

* **Initiator** - person initiating DAI transfer by calling `initiateTeleport` . They can optionally specify Operator and Receiver 
* **Operator** - person (or specified third party) responsible for initiating minting process on destination domain by providing (in the fast path) Oracle attestations. Can call `requestMint` on `TeleportOracleAuth`
* **Receiver** - person receiving minted DAI on a destination domain

## DAI Teleport L2 → L1 (aka fast withdrawals) 

![FastWithdrawal](./docs/fw.png?raw=true)

## Governance controlled parameters:

* `vat.ilk[teleportJoinIlk].line`- *Teleport Debt Ceiling*. Usually should be a sum of all debt ceilings available for each domain.
* `teleportJoin.line[domain]` - *Domain Debt Ceiling*. How much DAI can be drawn by a particular domain.
* `teleportJoin.fees[domain]` - *Domain Fee Structure*. Given details (TeleportGUID, current utilization etc) calculates how much charge for a mint.
* `teleportJoin.vow` - *Fees Receiver*.
* `TeleportOracleAuth.threshold` - *Feeds Threshold*. How many feeds (oracles) need to attest to be able to mint.
* `TeleportOracleAuth.signers` - *Feeds List*. 
* `TeleportRouter.gateway[domain]` - *Gateways Supported*. 


### Normal (fast) path

To fast withdraw DAI from L2, user:

* Calls `l2bridge.initiateTeleport()` - this burns DAI on L2 and sends `finalizeRegisterTeleport()` L2 -> L1 message to withdraw DAI from L2 bridge. This message, in normal cicumstances, will never be relayed and it will eventually expire in L1 message queue
* Waits for withdrawal attestations to be available and obtains them via Oracle API
* Calls `TeleportOracleAuth.requestMint(TeleportGUID teleportGUID, bytes signatures, uint256 maxFeePercentage, uint256 operatorFee)` which will:
  * Check if `sender` is `operator` or `receiver` 
  *   Check if enough valid attestations (sigs) are provided
  *   Call `TeleportJoin.requestMint(teleportGUID, maxfeePercentage, operatorFee)` which will
        * Check if this teleport hasn't been used before
        * Check if the debt ceiling hasn't been reached
        * Check the current fee via `TeleportFees`
        * `vat.slip`, `vat.frob`, `daiJoin.exit`

### Settlement

Settlement process moves DAI from L1 Bridge to TeleportJoin to clear the debt that accumulates there. It is triggered by keepers.

* On L2 keeper calls `l2bridge.flush()`
* L2 -> L1 message `finalizeFlush()` is sent to `L1Bridge` and relayed by a keeper
* `L1Bridge` upon receiving `finalizeFlush()` calls `TeleportRouter.settle()` which will
    * Transfer `DAI` from bridges' escrow to `TeleportJoin`
    * Call `TeleportJoin.settle()` which will use transfered DAI to clear any outstanding debt by calling `daiJoin.join`, `vat.frob`, `vat.slip`

### Slow (emergency) path

If attestations cannot be obtained (Oracles down or censoring), user needs to wait so that L2 message is confirmed on L1 (on Optimistic Rollups that typically is 7 days, on zkRollups it can be anything between few hours to a day). Once L2->L1 message can be relayed, user:

* Relays `finalizeRegisterTeleport()`  message to `L1Bridge`
* `L1Bridge` upon receiving `finalizeRegisterTeleport()` will call `requestMint()` on `TeleportRouter` which will:
    * Call `TeleportJoin.requestMint(teleportGUID, maxfeePercentage, operatorFee)` which will
        * Check if this teleport hasn't been used before
        * Check if the debt ceiling hasn't been reached
        * Check the current fee via `TeleportFees`
        * `vat.slip`, `vat.frob`, `daiJoin.exit`

## DAI Teleport L2→L2

![Teleport](./docs/l2.png?raw=true)

### Normal (fast) path

Wormholing DAI to another L2 domain is very similar, the only difference is that DAI is minted on a target Domain rather then on L1. For this scheme to work MakerDAO `MCD` sytem needs to be deployed on a target domain. 

### Settlement

Settlement process is very similar, however DAI is transfered from source domain bridge on L1 to target domain bridge on L1 before rather then moved to `L1 MCD` to pay the debt. This DAI, now in target domain bridge will be backing DAI that is minted on L2 target domain.

### Slow (emergency) path

For a slow path, once the L2->L1 message from the source domain is received on L1 and can be relayed, the user can relay the message, which will call `requestMint()` on the target domain `L1Bridge`. This will pass an L1->L2 message to `L2bridge` which will call `requestMint()` on a `TeleportJoin` contract on target domain L2.

## Technical Documenation

Each Teleport is described with the following struct:

```
struct TeleportGUID {
	bytes32 sourceDomain;
	bytes32 targetDomain;
	bytes32 receiver;
	bytes32 operator;
	uint128 amount;
	uint80 nonce;
	uint48 timestamp;
}
```
Source domain implementation must ensure that `keccack(WorkholeGUID)` is unique for each teleport transfer. We use `bytes32` for addresses to support not EVM compliant domains.

### Contracts

**`TeleportRouter`**
* `file(what=="gateway", domain, gateway)` - callable only by Governance, sets the gateway for a domain. If a gateway is already set, replaces it with a new one. 
* `requestMint(TeleportGUID calldata teleportGUID, uint256 maxFeePercentage, uint256 operatorFee)` - callable only by `L1Bridge`, issues a request to mint DAI for the receiver of the teleport. This request is made either directly to the L1 `TeleportJoin` in the case of a fast withdrawal to L1 or indirectly by instructing the target domain's `L1Bridge` to pass an `L1 -> L2` message to the corresponding L2 `TeleportJoin` in the case of a teleport to another L2.
* `function settle(bytes32 targetDomain, uint256 batchedDaiToFlush)` - callable only by the `L1bridge`, handles settlement process by requesting either `TeleportJoin` or target domain `L1 bridge` to settle DAI

**`TeleportOracleAuth`**
* `requestMint(TeleportGUID calldata teleportGUID, bytes calldata signatures, uint256 maxFeePercentage, uint256 operatorFee)` - callable only by the teleport operator or receiver, requests `TeleportJoin` to mint DAI for the receiver of the teleport provided required number of Oracle attestations are given

**`TeleportJoin`**
* `requestMint(TeleportGUID calldata teleportGUID, uint256 maxFeePercentage, uint256 operatorFee)` - callable either by `TeleportOracleAuth` (fast path) or by `TeleportRouter` (slow path), mints and withdraws DAI from the teleport. If debt ceiling is reached, partial amount will be withdrawn and anything pending can be withdrawn using `mintPending()` later
* `mintPending(TeleportGUID calldata teleportGUID, uint256 maxFeePercentage, uint256 operatorFee)` - callable by teleport operator or receiver, withdraws any pending DAI from a teleport
* `settle(bytes32 sourceDomain, uint256 batchedDaiToFlush)` - callable only by `TeleportRouter`, settles DAI debt

**`TeleportFees`**
* `getFee(TeleportGUID calldata teleportGUID) (uint256 fees)` - interface for getting current fee. Various implementations can be provided by the governance with different fee structures

### Authorization
* `TeleportOracleAuth`
  * `requestMint` - operator or receiver (set by the user initiating teleport)
  * `rely`, `deny`, `file`, `addSigners`, `removeSigners` - auth (Governance)
* `TeleportRouter`
  * `rely`, `deny`, `file` - auth (Governance)
  * `requestMint` - L1 Bridge
  * `settle` - L1 Bridge
* `TeleportJoin` 
  * `rely`, `deny`, `file` - auth (Governance)
  * `requestMint` - auth (`TeleportRouter`, `TeleportOracleAuth`)
  * `mintPending` - operator or receiver
  * `settle` - anyone (typically keeper)
* `L1TeleportBridge`
  * `finalizeFlush()` - L2 bridge
  * `finalizeRegisterTeleport()` - L2 bridge
* `L2DAITeleportBridge`
  * `initalizeTeleport` - anyone (typically user)
  * `flush` - anyone (typically keeper)

## Example

Setup: Debt ceiling: 10M DAI

| Operation | Available Debt |
| --- | --- |
| User A inititates teleport for 2M | 10M |
| User A mints 2M on L1 with Oracle's attestations| 8M (10M-2M) |
| User B initiates teleport for 9 M | 8M |
| Keeper flushes 2M (from UserA) and 9M (from UserB) | 8M |
| User C initiates teleport for 5M | 8M |
| User C mints 5M on L1 with Oracle's attestations | 3M (8M - 5M) |
| After 7 days keepers calls finializeFlush() that burns 11M | 14M (3M + 11M) |
| User D inititates teleport for 10M | 14M |
| User D mints 10M on L1 with Oracle's attestations | 4M (14M - 10M) |
| User B wants to withdraw from teleport Ilk 9m using slow withdrawal path. They can withdraw only 4M | 0M (4M - 4M) |
| Keeper flushes 15M (from UserC and UserD) | 0M |
| After 7 days keepers calls finializeFlush() that burns 15M | 15M (0M + 15M) |
| User B can withdraw the rest of the funds (5M) | 10M (15M - 5M) |

## Risks
### Oracle censoring or oracle failure
If user is unable to obtain Oracle's attestations, slow path is taken - no user funds are at risk
### Oracle malfunction (wrong attestations)
If user is able to obtain fraudulant attestation (i.e. attesting that DAI on L2 is burn and withdrawn whereas in reality is not), this will result in bad debt - DAI minted in a teleport will never be settled. This will result in bad debt that eventually will have to be healed through a standard MakerDAO debt healing processes. 
### Source domain compromised
### Target domain compromised 

## Related repositories

* [Optimism Teleport Bridge](https://github.com/makerdao/optimism-dai-bridge/pull/59)
* [Integration tests](https://github.com/makerdao/teleport-integration-tests)

