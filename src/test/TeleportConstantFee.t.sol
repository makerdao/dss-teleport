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

import "src/TeleportConstantFee.sol";
import "src/TeleportGUID.sol";

interface Hevm {
    function warp(uint) external;
}

contract TeleportConstantFeeTest is DSTest {

    Hevm internal hevm = Hevm(HEVM_ADDRESS);
    uint256 internal fee = 1 ether / 100;
    uint256 internal ttl = 8 days;

    TeleportConstantFee internal teleportConstantFee;

    function setUp() public {
        teleportConstantFee = new TeleportConstantFee(fee, ttl);
    }

    function testConstructor() public {
        assertEq(teleportConstantFee.fee(), fee);
        assertEq(teleportConstantFee.ttl(), ttl);
    }

    function testFeeForZeroAmount() public {
        TeleportGUID memory guid = TeleportGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(this)),
            amount: 0,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });

        assertEq(teleportConstantFee.getFee(guid, 0, 0, 0, 10 ether), 0);
    }

    function testFeeForNonZeroTotalAmount() public {
        TeleportGUID memory guid = TeleportGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(this)),
            amount: 100 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });

        assertEq(teleportConstantFee.getFee(guid, 0, 0, 0, 100 ether), fee);
    }

    function testFeeForNonZeroPartialAmount() public {
        TeleportGUID memory guid = TeleportGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(this)),
            amount: 100 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });

        assertEq(teleportConstantFee.getFee(guid, 0, 0, 0, 60 ether), fee * 60 / 100);
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

        assertEq(teleportConstantFee.getFee(guid, 0, 0, 0, 100 ether), 0);
    }
}
