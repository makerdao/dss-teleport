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

pragma solidity 0.8.11;

import "ds-test/test.sol";

import "src/WormholeConstantFee.sol";
import "src/WormholeGUID.sol";

contract WormholeConstantFeeTest is DSTest {
    
    uint256 internal fee = 1 ether / 100;
    uint256 internal ttl = 8 days;

    WormholeConstantFee internal wormholeConstantFee;

    function setUp() public {
        wormholeConstantFee = new WormholeConstantFee(fee, ttl);
    }

    function testConstructor() public {
        assertEq(wormholeConstantFee.fee(), fee);
        assertEq(wormholeConstantFee.ttl(), ttl);
    }

    function testFeeForZeroAmount() public {
        WormholeGUID memory guid = WormholeGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(this)),
            amount: 0,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });

        assertEq(wormholeConstantFee.getFee(guid, 0, 0, 0, 10 ether), 0);
    }
}
