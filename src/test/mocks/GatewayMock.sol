// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import "src/TeleportGUID.sol";

contract GatewayMock {
    function registerMint(TeleportGUID calldata) external {}
    function requestMint(TeleportGUID calldata, uint256, uint256) external pure returns (uint256 postFeeAmount, uint256 totalFee) {}
    function settle(bytes32, bytes32, uint256) external {}
}
