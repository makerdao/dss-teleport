// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import "../src/TeleportGUID.sol";

contract GatewayMock {
    TeleportGUID public teleportGUID;
    bytes32 public sourceDomain;
    bytes32 public targetDomain;
    uint256 public amount;

    function registerMint(
        TeleportGUID memory teleportGUID_
    ) external {
        teleportGUID = teleportGUID_;
    }

    function settle(bytes32 sourceDomain_, bytes32 targetDomain_, uint256 amount_) external {
        sourceDomain = sourceDomain_;
        targetDomain = targetDomain_;
        amount = amount_;
    }
}
