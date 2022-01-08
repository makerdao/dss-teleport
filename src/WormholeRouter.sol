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

interface TokenLike {
  function transferFrom(address _from, address _to, uint256 _value) external returns (bool success);
}

interface GatewayLike {
    function requestMint(WormholeGUID calldata wormholeGUID, uint256 maxFee) external;
    function settle(bytes32 sourceDomain, uint256 batchedDaiToFlush) external;
}

contract WormholeRouter {

    mapping (address => uint256) public wards;          // Auth
    mapping (bytes32 => address) public gateways;       // GatewayLike contracts called by the router for each domain
    mapping (address => bytes32) public domains;        // Domains for each gateway
    mapping (bytes32 => uint256) public domainIndices;  // The domain's position in the active domain array

    bytes32[] public allDomains;  // Array of active domains

    TokenLike immutable public dai; // L1 DAI ERC20 token

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, bytes32 indexed domain, address gateway);

    // --- Errors ---
    error NotAuthorized();
    error FileUnrecognizedParam();
    error SenderNotGateway();
    error UnsupportedTargetDomain();

    modifier auth {
        if (wards[msg.sender] != 1) revert NotAuthorized();
        _;
    }

    constructor(address dai_) {
        dai = TokenLike(dai_);
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

    /**
     * @notice Allows auth to configure the router. The only supported operation is "gateway",
     * which allows adding, replacing or removing a gateway contract for a given domain. The router forwards `settle()` 
     * and `requestMint()` calls to the gateway contract installed for a given domain. Gateway contracts must therefore
     * conform to the GatewayLike interface. Examples of valid gateways include WormholeJoin (for the L1 domain)
     * and L1 bridge contracts (for L2 domains).
     * @dev In addition to updating the mapping `gateways` which maps GatewayLike contracts to domain names and
     * the reverse mapping `domains` which maps domain names to GatewayLike contracts, this method also maintains
     * an array `allDomains` of all active domains as well as a mapping `domainIndices` of the indices of domain names within
     * the `allDomains` array. `domainIndices` is used to allow updating `allDomains` using only O(1) writes.
     * @param what The name of the operation. Only "gateway" is supported.
     * @param domain The domain for which a GatewayLike contract is added, replaced or removed.
     * @param gateway The address of the GatewayLike contract to install for the domain (or address(0) to remove a domain)
     */
    function file(bytes32 what, bytes32 domain, address gateway) external auth {
        if (what == "gateway") {
            address prevGateway = gateways[domain];
            if(prevGateway == address(0)) { 
                // new domain => add it to allDomains
                if(gateway != address(0)) {
                    domainIndices[domain] = allDomains.length;
                    allDomains.push(domain);
                }
            } else { 
                // existing domain 
                domains[prevGateway] = bytes32(0);
                if(gateway == address(0)) {
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

            gateways[domain] = gateway;
            if(gateway != address(0)) {
                domains[gateway] = domain;
            }
        } else {
            revert FileUnrecognizedParam();
        }
        emit File(what, domain, gateway);
    }

    function numActiveDomains() external view returns (uint256) {
        return allDomains.length;
    }

    /**
     * @notice Call a GatewayLike contract to request the minting of DAI. The sender must be a supported gateway
     * @param wormholeGUID The wormhole GUID to register
     * @param maxFee The maximum amount of fees to pay for the minting of DAI
     */
    function requestMint(WormholeGUID calldata wormholeGUID, uint256 maxFee) external {
        if (msg.sender != gateways[wormholeGUID.sourceDomain]) revert SenderNotGateway();
        address gateway = gateways[wormholeGUID.targetDomain];
        if (gateway == address(0)) revert UnsupportedTargetDomain();
        GatewayLike(gateway).requestMint(wormholeGUID, maxFee);
    }

    /**
     * @notice Call a GatewayLike contract to settle a batch of sourceDomain -> targetDomain DAI transfer. 
     * The sender must be a supported gateway
     * @param targetDomain The domain receiving the batch of DAI (only L1 supported for now)
     * @param batchedDaiToFlush The amount of DAI in the batch 
     */
    function settle(bytes32 targetDomain, uint256 batchedDaiToFlush) external {
        bytes32 sourceDomain = domains[msg.sender];
        if (sourceDomain == bytes32(0)) revert SenderNotGateway();
        address gateway = gateways[targetDomain];
        if (gateway == address(0)) revert UnsupportedTargetDomain();
         // Forward the DAI to settle to the gateway contract
        dai.transferFrom(msg.sender, gateway, batchedDaiToFlush);
        GatewayLike(gateway).settle(sourceDomain, batchedDaiToFlush);
    }
}
