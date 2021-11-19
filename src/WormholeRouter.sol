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

contract WormholeRouter {

    bytes32 constant public MAINNET_DOMAIN = bytes32("mainnet");
    WormholdJoinLike immutable public wormholeJoin;

    mapping (bytes32 => address) public bridges; // L1 bridges for each domain
    // TODO: the reverse mapping is not needed if the L1 bridge can pass its own domain id to router.settle()
    mapping (address => bytes32) public domains; // domains for each bridge
    mapping (address => uint256) public wards;   // Auth

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, bytes32 domain, address data);

    modifier auth {
        require(wards[msg.sender] == 1, "WormholeRouter/non-authed");
        _;
    }

    constructor(address wormholeJoin_) {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
        wormholeJoin = WormholdJoinLike(wormholeJoin_);
    }

    function file(bytes32 what, bytes32 domain, address data) external auth {
        if (what == "bridge") {
            address prevBridge = bridges[domain];
            if(prevBridge != address(0)) {
                domains[prevBridge] = bytes32(0);
            }
            bridges[domain] = data;
            domains[data] = domain;
        } else {
            revert("WormholeRouter/file-unrecognized-param");
        }
        emit File(what, domain, data);
    }

    function registerWormhole(WormholeGUID calldata wormholeGUID, uint256 maxFee) external {
        require(msg.sender == bridges[wormholeGUID.sourceDomain], "WormholeRouter/sender-not-bridge");
        // We only support L1 as target for now
        require(wormholeGUID.targetDomain == MAINNET_DOMAIN, "WormholeRouter/unsupported-target-domain");
        wormholeJoin.registerWormholeAndWithdraw(wormholeGUID, maxFee);
    }

    function settle(bytes32 targetDomain, uint256 batchedDaiToFlush) external {
        bytes32 sourceDomain = domains[msg.sender];
        require(sourceDomain != bytes32(0), "WormholeRouter/sender-not-bridge");
        // We only support L1 as target for now
        require(targetDomain == MAINNET_DOMAIN, "WormholeRouter/unsupported-target-domain");
        wormholeJoin.settle(sourceDomain, batchedDaiToFlush);
    }
}
