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
    mapping (bytes32 => uint256) public batches;        // Pending DAI to flush per target domain

    EnumerableSet.Bytes32Set private allDomains;
    address public defaultGateway;
    uint80  public nonce;
    uint256 public fdust;   // The minimum amount of DAI to be flushed per target domain (prevent spam)

    TokenLike immutable public dai;
    bytes32   immutable public domain;

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, bytes32 indexed domain, address data);
    event File(bytes32 indexed what, address data);
    event File(bytes32 indexed what, uint256 data);
    event InitiateTeleport(TeleportGUID teleport);
    event Flush(bytes32 indexed targetDomain, uint256 dai);

    modifier auth {
        require(wards[msg.sender] == 1, "TeleportRouter/not-authorized");
        _;
    }

    constructor(address dai_, bytes32 domain_) {
        dai = TokenLike(dai_);
        domain = domain_;
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
     * @param _domain The domain for which a GatewayLike contract is added, replaced or removed.
     * @param data The address of the GatewayLike contract to install for the domain (or address(0) to remove a domain)
     */
    function file(bytes32 what, bytes32 _domain, address data) external auth {
        if (what == "gateway") {
            address prevGateway = gateways[_domain];
            if(prevGateway == address(0)) { 
                // new domain => add it to allDomains
                if(data != address(0)) {
                    allDomains.add(_domain);
                }
            } else { 
                // existing domain
                if(data == address(0)) {
                    // => remove domain from allDomains
                    allDomains.remove(_domain);
                }
            }

            gateways[_domain] = data;
            if (data != address(0)) {
                dai.approve(data, type(uint256).max);
            }
        } else {
            revert("TeleportRouter/file-unrecognized-param");
        }
        emit File(what, _domain, data);
    }

    /**
     * @notice Allows auth to configure the router. The only supported operation is "defaultGateway",
     * which sets the fallback address if no specific domain is matched.
     * @param what The name of the operation. Only "defaultGateway" is supported.
     * @param data Set the fallback gateway or address(0) to disable the fallback.
     */
    function file(bytes32 what, address data) external auth {
        if (what == "defaultGateway") {
            defaultGateway = data;
            dai.approve(data, type(uint256).max);
        } else {
            revert("TeleportRouter/file-unrecognized-param");
        }
        emit File(what, data);
    }
    
    function file(bytes32 what, uint256 data) external auth {
        if (what == "fdust") {
            fdust = data;
        } else {
            revert("TeleportJoin/file-unrecognized-param");
        }
        emit File(what, data);
    }

    function numDomains() external view returns (uint256) {
        return allDomains.length();
    }
    function domainAt(uint256 index) external view returns (bytes32) {
        return allDomains.at(index);
    }
    function hasDomain(bytes32 _domain) external view returns (bool) {
        return allDomains.contains(_domain);
    }

    /**
     * @notice Call a GatewayLike contract to register the minting of DAI. The sender must be a supported gateway
     * @param teleportGUID The teleport GUID to register
     */
    function registerMint(TeleportGUID calldata teleportGUID) external {
        // We trust the defaultGateway gateway with any sourceDomain as a compromised defaultGateway implies compromised child
        // Otherwise we restrict passing messages only from the actual source domain
        require(msg.sender == defaultGateway || msg.sender == gateways[teleportGUID.sourceDomain], "TeleportRouter/sender-not-gateway");
        
        _registerMint(teleportGUID);
    }

    function _registerMint(TeleportGUID memory teleportGUID) internal {
        address gateway = gateways[teleportGUID.targetDomain];
        // Use fallback if no gateway is configured for the target domain
        if (gateway == address(0)) gateway = defaultGateway;
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
        // We trust the defaultGateway gateway with any sourceDomain as a compromised defaultGateway implies compromised child
        // Otherwise we restrict passing messages only from the actual source domain
        require(msg.sender == defaultGateway || msg.sender == gateways[sourceDomain], "TeleportRouter/sender-not-gateway");
        
        _settle(msg.sender, sourceDomain, targetDomain, amount);
    }

    function _settle(address from, bytes32 sourceDomain, bytes32 targetDomain, uint256 amount) internal {
        address gateway = gateways[targetDomain];
        // Use fallback if no gateway is configured for the target domain
        if (gateway == address(0)) gateway = defaultGateway;
        require(gateway != address(0), "TeleportRouter/unsupported-target-domain");
        // Forward the DAI to settle to the gateway contract
        dai.transferFrom(from, gateway, amount);
        GatewayLike(gateway).settle(sourceDomain, targetDomain, amount);
    }

    /**
    * @notice Initiate Maker teleport
    * @dev Will fire a teleport event, burn the dai and initiate a censorship-resistant slow-path message
    * @param targetDomain The target domain to teleport to
    * @param receiver The receiver address of the DAI on the target domain
    * @param amount The amount of DAI to teleport
    **/
    function initiateTeleport(
        bytes32 targetDomain,
        address receiver,
        uint128 amount
    ) external {
        initiateTeleport(
            targetDomain,
            addressToBytes32(receiver),
            amount,
            0
        );
    }

    /**
    * @notice Initiate Maker teleport
    * @dev Will fire a teleport event, burn the dai and initiate a censorship-resistant slow-path message
    * @param targetDomain The target domain to teleport to
    * @param receiver The receiver address of the DAI on the target domain
    * @param amount The amount of DAI to teleport
    * @param operator An optional address that can be used to mint the DAI at the destination domain (useful for automated relays)
    **/
    function initiateTeleport(
        bytes32 targetDomain,
        address receiver,
        uint128 amount,
        address operator
    ) external {
        initiateTeleport(
            targetDomain,
            addressToBytes32(receiver),
            amount,
            addressToBytes32(operator)
        );
    }

    /**
    * @notice Initiate Maker teleport
    * @dev Will fire a teleport event, burn the dai and initiate a censorship-resistant slow-path message
    * @param targetDomain The target domain to teleport to
    * @param receiver The receiver address of the DAI on the target domain
    * @param amount The amount of DAI to teleport
    * @param operator An optional address that can be used to mint the DAI at the destination domain (useful for automated relays)
    **/
    function initiateTeleport(
        bytes32 targetDomain,
        bytes32 receiver,
        uint128 amount,
        bytes32 operator
    ) public {
        TeleportGUID memory teleport = TeleportGUID({
            sourceDomain: domain,
            targetDomain: targetDomain,
            receiver: receiver,
            operator: operator,
            amount: amount,
            nonce: nonce++,
            timestamp: uint48(block.timestamp)
        });

        batches[targetDomain] += amount;
        require(dai.transferFrom(msg.sender, address(this), amount), "DomainHost/transfer-failed");
        
        // Initiate the censorship-resistant slow-path
        _registerMint(teleport);
        
        // Oracle listens to this event for the fast-path
        emit InitiateTeleport(teleport);
    }

    /**
    * @notice Flush batched DAI to the target domain
    * @dev Will initiate a settle operation along the secure, slow routing path
    * @param targetDomain The target domain to settle
    **/
    function flush(bytes32 targetDomain) external {
        uint256 daiToFlush = batches[targetDomain];
        require(daiToFlush > fdust, "DomainGuest/flush-dust");

        batches[targetDomain] = 0;

        _settle(address(this), domain, targetDomain, daiToFlush);

        emit Flush(targetDomain, daiToFlush);
    }
}
