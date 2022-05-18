// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.13;

import "../src/TeleportGUID.sol";

contract TeleportJoinMock {
    TeleportGUID public teleportGUID;
    uint256 public maxFeePercentage;
    uint256 public operatorFee;
    uint256 public postFeeAmount;
    uint256 public totalFee;
    bytes32 public sourceDomain;
    uint256 public batchedDaiToFlush;

    function requestMint(
        TeleportGUID memory teleportGUID_,
        uint256 maxFeePercentage_,
        uint256 operatorFee_
    ) external returns (uint256 postFeeAmount_, uint256 totalFee_) {
        teleportGUID = teleportGUID_;
        maxFeePercentage = maxFeePercentage_;
        operatorFee = operatorFee_;
        postFeeAmount_ = postFeeAmount;
        totalFee_ = totalFee;
    }

    function settle(bytes32 sourceDomain_, uint256 batchedDaiToFlush_) external {
        sourceDomain = sourceDomain_;
        batchedDaiToFlush = batchedDaiToFlush_;
    }
}
