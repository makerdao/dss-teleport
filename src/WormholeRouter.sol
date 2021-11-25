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

contract WormholeRouter {

    mapping (address => uint256) public wards;   // Auth
    mapping (bytes32 => address) public bridges; // L1 bridges for each domain
    // TODO: the reverse mapping is not needed if the L1 bridge can pass its own domain id to router.settle()
    mapping (address => bytes32) public domains; // domains for each bridge
    
    bytes32 constant public L1_DOMAIN = bytes32("ethereum");

    TokenLike immutable public dai; // L1 DAI ERC20 token
    address immutable public escrow; // L1 DAI Escrow
    WormholdJoinLike immutable public wormholeJoin;

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, bytes32 domain, address data);

    modifier auth {
        require(wards[msg.sender] == 1, "WormholeRouter/non-authed");
        _;
    }

    constructor(address dai_, address escrow_, address wormholeJoin_) {
        dai = TokenLike(dai_);
        escrow = escrow_;
        wormholeJoin = WormholdJoinLike(wormholeJoin_);
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
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

    /**
     * @notice Call WormholeJoin to mint DAI. The sender must be a supported bridge
     * @param wormholeGUID The wormhole GUID to register
     * @param maxFee The maximum amount of fees to pay for the minting of DAI
     */
    function mint(WormholeGUID calldata wormholeGUID, uint256 maxFee) external {
        require(msg.sender == bridges[wormholeGUID.sourceDomain], "WormholeRouter/sender-not-bridge");
        // We only support L1 as target for now
        require(wormholeGUID.targetDomain == L1_DOMAIN, "WormholeRouter/unsupported-target-domain");
        wormholeJoin.registerWormholeAndWithdraw(wormholeGUID, maxFee);
    }

    /**
     * @notice Call WormholeJoin to settle a batch of L2 -> L1 DAI withdrawals. The sender must be a supported bridge
     * @param targetDomain The domain receiving the batch of DAI (only L1 supported for now)
     * @param batchedDaiToFlush The amount of DAI in the batch 
     */
    function settle(bytes32 targetDomain, uint256 batchedDaiToFlush) external {
        bytes32 sourceDomain = domains[msg.sender];
        require(sourceDomain != bytes32(0), "WormholeRouter/sender-not-bridge");
        // We only support L1 as target for now
        require(targetDomain == L1_DOMAIN, "WormholeRouter/unsupported-target-domain");
        // Push the DAI to settle to wormholeJoin (TODO: to be changed if wormholeJoin pulls DAI directly from the escrow)
        dai.transferFrom(escrow, address(wormholeJoin), batchedDaiToFlush);
        wormholeJoin.settle(sourceDomain, batchedDaiToFlush);
    }
}
