// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.6;

import "ds-test/test.sol";

import "./DssWormhole.sol";

contract DssWormholeTest is DSTest {
    DssWormhole wormhole;

    function setUp() public {
        wormhole = new DssWormhole();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
