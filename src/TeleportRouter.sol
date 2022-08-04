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

pragma solidity 0.8.15;

import "./TeleportGUID.sol";
import "./utils/EnumerableSet.sol";

interface TokenLike {
    function approve(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
}

interface GatewayLike {
    function registerMint(TeleportGUID calldata teleportGUID) external;
    function settle(bytes32 sourceDomain, bytes32 targetDomain, uint256 amount) external;
}

contract TeleportRouter {

    using EnumerableSet for EnumerableSet.Bytes32Set;

    mapping (address => uint256) public wards;          // Auth
    mapping (bytes32 => address) public gateways;       // GatewayLike contracts called by the router for each domain

    EnumerableSet.Bytes32Set private allDomains;
    address public parent;

    TokenLike immutable public dai; // L1 DAI ERC20 token

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, bytes32 indexed domain, address data);
    event File(bytes32 indexed what, address data);

    modifier auth {
        require(wards[msg.sender] == 1, "TeleportRouter/not-authorized");
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
     * and `registerMint()` calls to the gateway contract installed for a given domain. Gateway contracts must therefore
     * conform to the GatewayLike interface. Examples of valid gateways include TeleportJoin (for the L1 domain)
     * and L1 bridge contracts (for L2 domains).
     * @dev In addition to updating the mapping `gateways` which maps GatewayLike contracts to domain names this method
     * also maintains the enumerable set `allDomains`.
     * @param what The name of the operation. Only "gateway" is supported.
     * @param domain The domain for which a GatewayLike contract is added, replaced or removed.
     * @param data The address of the GatewayLike contract to install for the domain (or address(0) to remove a domain)
     */
    function file(bytes32 what, bytes32 domain, address data) external auth {
        if (what == "gateway") {
            address prevGateway = gateways[domain];
            if(prevGateway == address(0)) { 
                // new domain => add it to allDomains
                if(data != address(0)) {
                    allDomains.add(domain);
                }
            } else { 
                // existing domain
                if(data == address(0)) {
                    // => remove domain from allDomains
                    allDomains.remove(domain);
                }
            }

            gateways[domain] = data;
        } else {
            revert("TeleportRouter/file-unrecognized-param");
        }
        emit File(what, domain, data);
    }

    /**
     * @notice Allows auth to configure the router. The only supported operation is "parent",
     * which sets the fallback address if no specific domain is matched.
     * @param what The name of the operation. Only "parent" is supported.
     * @param data Set the fallback gateway or address(0) to disable the fallback.
     */
    function file(bytes32 what, address data) external auth {
        if (what == "parent") {
            parent = data;
        } else {
            revert("TeleportRouter/file-unrecognized-param");
        }
        emit File(what, data);
    }

    function numDomains() external view returns (uint256) {
        return allDomains.length();
    }
    function domainAt(uint256 index) external view returns (bytes32) {
        return allDomains.at(index);
    }
    function hasDomain(bytes32 domain) external view returns (bool) {
        return allDomains.contains(domain);
    }

    /**
     * @notice Call a GatewayLike contract to register the minting of DAI. The sender must be a supported gateway
     * @param teleportGUID The teleport GUID to register
     */
    function registerMint(TeleportGUID calldata teleportGUID) external {
        // We trust the parent gateway with any sourceDomain as a compromised parent implies compromised child
        // Otherwise we restrict passing messages only from the actual source domain
        require(msg.sender == parent || msg.sender == gateways[teleportGUID.sourceDomain], "TeleportRouter/sender-not-gateway");
        address gateway = gateways[teleportGUID.targetDomain];
        // Use fallback if no gateway is configured for the target domain
        if (gateway == address(0)) gateway = parent;
        require(gateway != address(0), "TeleportRouter/unsupported-target-domain");
        GatewayLike(gateway).registerMint(teleportGUID);
    }

    /**
     * @notice Call a GatewayLike contract to settle a batch of sourceDomain -> targetDomain DAI transfer. 
     * The sender must be a supported gateway
     * @param sourceDomain The domain sending the batch of DAI
     * @param targetDomain The domain receiving the batch of DAI
     * @param amount The amount of DAI in the batch 
     */
    function settle(bytes32 sourceDomain, bytes32 targetDomain, uint256 amount) external {
        // We trust the parent gateway with any sourceDomain as a compromised parent implies compromised child
        // Otherwise we restrict passing messages only from the actual source domain
        require(msg.sender == parent || msg.sender == gateways[sourceDomain], "TeleportRouter/sender-not-gateway");
        address gateway = gateways[targetDomain];
        // Use fallback if no gateway is configured for the target domain
        if (gateway == address(0)) gateway = parent;
        require(gateway != address(0), "TeleportRouter/unsupported-target-domain");
        // Forward the DAI to settle to the gateway contract
        dai.transferFrom(msg.sender, address(this), amount);
        dai.approve(gateway, amount);
        GatewayLike(gateway).settle(sourceDomain, targetDomain, amount);
    }
}
