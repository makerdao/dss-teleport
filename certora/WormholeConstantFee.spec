// WormholeConstantFee.spec

using WormholeConstantFee as fee

methods {
    fee() returns (uint256) envfree
    ttl() returns (uint256) envfree
}

// Verify fallback always reverts
rule fallback_revert(method f) filtered { f -> f.isFallback } {
    env e;

    calldataarg arg;
    f@withrevert(e, arg);

    assert(lastReverted, "Fallback did not revert");
}

// Verify that fee value behaves correctly on getFee
rule getFee(fee.WormholeGUID guid, uint256 a, int256 b, uint256 c, uint256 amtToTake) {
    env e;

    uint256 feeCalculated = e.block.timestamp >= guid.timestamp + ttl() || guid.amount == 0
                            ? 0
                            : fee() * amtToTake / guid.amount;

    uint256 feeGot = getFee(e, guid, a, b, c, amtToTake);

    assert(feeGot == feeCalculated, "getFee didn't return fee as expected");
}

// Verify revert rules on getFee
rule getFee_revert(fee.WormholeGUID guid, uint256 a, int256 b, uint256 c, uint256 amtToTake) {
    env e;

    require(guid.amount <= max_uint128);
    require(guid.nonce <= 0xffffffffffffffffffff);
    require(guid.timestamp <= 0xffffffffffff);

    uint256 fee = fee();
    uint256 ttl = ttl();

    getFee@withrevert(e, guid, a, b, c, amtToTake);

    bool revert1 = e.msg.value > 0;
    bool revert2 = guid.timestamp + ttl > max_uint256;
    bool revert3 = e.block.timestamp < guid.timestamp + ttl && guid.amount > 0 && fee * amtToTake > max_uint256;

    assert(revert1 => lastReverted, "revert1 failed");
    assert(revert2 => lastReverted, "revert2 failed");
    assert(revert3 => lastReverted, "revert3 failed");

    assert(lastReverted => revert1 || revert2 || revert3, "Revert rules are not covering all the cases");
}
