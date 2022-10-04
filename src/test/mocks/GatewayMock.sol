// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import "src/TeleportGUID.sol";

contract GatewayMock {
    function bridgeMint(TeleportGUID calldata) external {}
    function bridgeSettle(bytes32, bytes32, uint256) external {}
}
