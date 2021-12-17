// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2021 Dai Foundation
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity 0.8.9;

import "./WormholeGUID.sol";

interface WormholdJoinLike {
    function registerWormholeAndWithdraw(WormholeGUID calldata wormholeGUID, uint256 maxFee) external;
    function settle(bytes32 sourceDomain, uint256 batchedDaiToFlush) external;
}

interface TokenLike {
  function transferFrom(address _from, address _to, uint256 _value) external returns (bool success);
}

interface L1BridgeLike {
    function initiateRequestMint(WormholeGUID calldata wormholeGUID, uint256 maxFee) external;
    function initiateSettle(bytes32 sourceDomain, uint256 batchedDaiToFlush) external;
}

contract WormholeRouter {

    mapping (address => uint256) public wards;          // Auth
    mapping (bytes32 => address) public bridges;        // L1 bridges for each domain
    // TODO: the reverse mapping is not needed if the L1 bridge can pass its own domain id to router.settle()
    mapping (address => bytes32) public domains;        // Domains for each bridge
    mapping (bytes32 => uint256) public domainIndices; // The domain's position in the active domain array

    bytes32[] public allDomains;  // Array of active domains

    bytes32 immutable public l1Domain; // The id of the L1 domain, e.g. bytes32("ethereum") or bytes32("goerli")
    TokenLike immutable public dai; // L1 DAI ERC20 token
    WormholdJoinLike immutable public wormholeJoin;

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, bytes32 domain, address data);

    modifier auth {
        require(wards[msg.sender] == 1, "WormholeRouter/non-authed");
        _;
    }

    constructor(bytes32 l1Domain_, address dai_, address wormholeJoin_) {
        l1Domain = l1Domain_;
        dai = TokenLike(dai_);
        wormholeJoin = WormholdJoinLike(wormholeJoin_);
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    function file(bytes32 what, bytes32 domain, address bridge) external auth {
        if (what == "bridge") {
            require(domain != l1Domain, "WormholeRouter/invalid-domain");
            address prevBridge = bridges[domain];
            if(prevBridge == address(0)) { 
                // new domain => add it to allDomains
                if(bridge != address(0)) {
                    domainIndices[domain] = allDomains.length;
                    allDomains.push(domain);
                }
            } else { 
                // existing domain 
                domains[prevBridge] = bytes32(0);
                if(bridge == address(0)) {
                    // => remove domain from allDomains
                    uint256 pos = domainIndices[domain];
                    uint256 lastIndex = allDomains.length - 1;
                    if (pos != lastIndex) {
                        bytes32 lastDomain = allDomains[lastIndex];
                        allDomains[pos] = lastDomain;
                        domainIndices[lastDomain] = pos;
                    }
                    allDomains.pop();
                    delete domainIndices[domain];
                }
            }

            if(bridge != address(0)) {
                domains[bridge] = domain;
            }
        } else {
            revert("WormholeRouter/file-unrecognized-param");
        }
        emit File(what, domain, bridge);
    }

    function numActiveDomains() external view returns (uint256) {
        return allDomains.length;
    }

    /**
     * @notice Call WormholeJoin (or a domain's L1 bridge) to request the minting of DAI. The sender must be a supported bridge
     * @param wormholeGUID The wormhole GUID to register
     * @param maxFee The maximum amount of fees to pay for the minting of DAI
     */
    function requestMint(WormholeGUID calldata wormholeGUID, uint256 maxFee) external {
        require(msg.sender == bridges[wormholeGUID.sourceDomain], "WormholeRouter/sender-not-bridge");
        if(wormholeGUID.targetDomain == l1Domain) {
            wormholeJoin.registerWormholeAndWithdraw(wormholeGUID, maxFee);
        } else {
            address targetBridge = bridges[wormholeGUID.targetDomain];
            require(targetBridge != address(0), "WormholeRouter/unsupported-target-domain");
            L1BridgeLike(targetBridge).initiateRequestMint(wormholeGUID, maxFee);
        }
    }

    /**
     * @notice Call WormholeJoin (or a domain's L1 bridge) to settle a batch of sourceDomain -> targetDomain DAI transfer. 
     * The sender must be a supported bridge
     * @param targetDomain The domain receiving the batch of DAI (only L1 supported for now)
     * @param batchedDaiToFlush The amount of DAI in the batch 
     */
    function settle(bytes32 targetDomain, uint256 batchedDaiToFlush) external {
        bytes32 sourceDomain = domains[msg.sender];
        require(sourceDomain != bytes32(0), "WormholeRouter/sender-not-bridge");

        if(targetDomain == l1Domain) {
            // Forward the DAI to settle to wormholeJoin
            dai.transferFrom(msg.sender, address(wormholeJoin), batchedDaiToFlush);
            wormholeJoin.settle(sourceDomain, batchedDaiToFlush);
        } else {
            address targetBridge = bridges[targetDomain];
            require(targetBridge != address(0), "WormholeRouter/unsupported-target-domain");
            // Forward the DAI to settle to the target bridge
            dai.transferFrom(msg.sender, targetBridge, batchedDaiToFlush);
            L1BridgeLike(targetBridge).initiateSettle(sourceDomain, batchedDaiToFlush);
        }
    }
}
