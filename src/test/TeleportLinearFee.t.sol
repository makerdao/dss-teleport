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

import "ds-test/test.sol";

import "src/TeleportLinearFee.sol";
import "src/TeleportGUID.sol";

interface Hevm {
    function warp(uint) external;
}

contract TeleportLinearFeeTest is DSTest {
    
    Hevm internal hevm = Hevm(HEVM_ADDRESS);
    uint256 internal fee = 1 ether / 10000; // 1 BPS fee
    uint256 internal ttl = 8 days;

    TeleportLinearFee internal teleportLinearFee;

    function setUp() public {
        teleportLinearFee = new TeleportLinearFee(fee, ttl);
    }

    function testConstructor() public {
        assertEq(teleportLinearFee.fee(), fee);
        assertEq(teleportLinearFee.ttl(), ttl);
    }

    function testFeeForNonZeroAmount() public {
        TeleportGUID memory guid = TeleportGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(this)),
            amount: 100 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });

        assertEq(teleportLinearFee.getFee(guid, 0, 0, 0, 100 ether), 0.01 ether);
    }

    function testFeeForSlowMint() public {
        TeleportGUID memory guid = TeleportGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(this)),
            amount: 100 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });
        hevm.warp(block.timestamp + ttl);

        assertEq(teleportLinearFee.getFee(guid, 0, 0, 0, 100 ether), 0);
    }
}
