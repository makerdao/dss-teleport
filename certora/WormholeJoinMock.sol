// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.9;

import "../src/WormholeGUID.sol";

contract WormholeJoinMock {
    function requestMint(WormholeGUID memory wormholeGUID, uint256 maxFee) external {
    }

    function settle(bytes32 sourceDomain, uint256 batchedDaiToFlush) external {
    }
}
