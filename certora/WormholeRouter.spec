// WormholeRouter.spec

using WormholeRouter as router
using DaiMock as dai
using WormholeJoinMock as join

methods {
    domainAt(uint256) returns (bytes32) envfree
    domains(address) returns (bytes32) envfree
    gateways(bytes32) returns (address) envfree
    hasDomain(bytes32) returns (bool) envfree
    numDomains() returns (uint256) envfree
    requestMint(join.WormholeGUID, uint256, uint256) returns (uint256, uint256) => DISPATCHER(true)
    settle(bytes32, uint256) => DISPATCHER(true)
    wards(address) returns (uint256) envfree
    dai.allowance(address, address) returns (uint256) envfree
    dai.balanceOf(address) returns (uint256) envfree
    join.wormholeGUID() returns(bytes32, bytes32, bytes32, bytes32, uint128, uint80, uint48) envfree
    join.batchedDaiToFlush() returns (uint256) envfree
    join.maxFeePercentage() returns (uint256) envfree
    join.operatorFee() returns (uint256) envfree
    join.postFeeAmount() returns (uint256) envfree
    join.sourceDomain() returns (bytes32) envfree
    join.totalFee() returns (uint256) envfree
}

definition RAY() returns uint256 = 10^27;

definition min_int256() returns mathint = -1 * 2^255;
definition max_int256() returns mathint = 2^255 - 1;

ghost indexesGhost(bytes32) returns uint256 {
    init_state axiom forall bytes32 x. indexesGhost(x) == 0;
}

hook Sload uint256 v currentContract.allDomains._inner._indexes[KEY bytes32 domain] STORAGE {
    require indexesGhost(domain) == v;
}

hook Sstore currentContract.allDomains._inner._indexes[KEY bytes32 a] uint256 n (uint256 o) STORAGE {
    havoc indexesGhost assuming indexesGhost@new(a) == n
        && (forall bytes32 b. indexesGhost@new(b) == indexesGhost@old(b) || b == a);
}

ghost valuesGhost(uint256) returns bytes32 {
    init_state axiom forall uint256 index. valuesGhost(index) == 0x0000000000000000000000000000000000000000;
}

hook Sload bytes32 domain currentContract.allDomains._inner._values[INDEX uint256 index] STORAGE {
    require valuesGhost(index) == domain;
}

hook Sstore currentContract.allDomains._inner._values[INDEX uint256 index] bytes32 newVal (bytes32 oldVal) STORAGE {
    havoc valuesGhost assuming valuesGhost@new(index) == newVal
        && (forall uint256 idx. valuesGhost@new(idx) == valuesGhost@old(idx) || idx == index);
}

ghost numDomainsHasOverflowed() returns bool {
    init_state axiom numDomainsHasOverflowed() == false;
}

// This ghost is used to prove that the storage slot read to update numDomainsHasOverflowed corresponds to the
// value of numDomains().
ghost numDomainsGhost() returns uint256 {
    init_state axiom numDomainsGhost() == 0;
}

hook Sload uint256 domArrLen currentContract.allDomains.(offset 0) STORAGE {
    require numDomainsGhost() == domArrLen;
}

hook Sstore currentContract.allDomains.(offset 0) uint256 newLen (uint256 oldLen) STORAGE {
    // This is justified by the fact that the only possible effects of an SSTORE to the length of the
    // array are +1 or -1. See rule numDomains_changes_by_at_most_one.
    havoc numDomainsHasOverflowed assuming (oldLen == max_uint256 && newLen == 0 && numDomainsHasOverflowed@new() == true)
        || (oldLen != max_uint256 && newLen != 0 && numDomainsHasOverflowed@new() == numDomainsHasOverflowed@old());

    havoc numDomainsGhost assuming numDomainsGhost@new() == newLen;
}


invariant numDomains_equals_numDomainsGhost()
    numDomains() == numDomainsGhost()
    filtered { f -> !f.isFallback }
    {
        preserved settle(bytes32 a,uint256 b) with (env e) {
            require(gateways(a) != router);
        }
        preserved requestMint(router.WormholeGUID guid, uint256 x, uint256 y) with (env e) {
            require(gateways(guid.targetDomain) != router);
        }
    }

invariant indexes_bounded(bytes32 value)
    indexesGhost(value) <= numDomains()
    filtered { f -> !f.isFallback }
    {
        preserved settle(bytes32 a,uint256 b) with (env e) {
            require(gateways(a) != router);
        }
        preserved requestMint(router.WormholeGUID guid, uint256 x, uint256 y) with (env e) {
            require(gateways(guid.targetDomain) != router);
        }
    }

invariant index_out_of_range_consistency(uint256 zIndex)
    !numDomainsHasOverflowed() => (zIndex >= numDomains() => valuesGhost(zIndex) == 0x0000000000000000000000000000000000000000)
    filtered { f -> !f.isFallback }
    {
        preserved settle(bytes32 a,uint256 b) with (env e) {
            require(gateways(a) != router);
        }
        preserved requestMint(router.WormholeGUID guid, uint256 x, uint256 y) with (env e) {
            require(gateways(guid.targetDomain) != router);
        }
    }

//invariant indexes_are_not_reused()
//    forall bytes32 v1. forall bytes32 v2. indexesGhost(v1) == indexesGhost(v2) => indexesGhost(v1) == 0 || v1 == v2
//    filtered { f -> !f.isFallback }
//    {
//        preserved settle(bytes32 a,uint256 b) with (env e) {
//            require(gateways(a) != router);
//        }
//        preserved requestMint(router.WormholeGUID guid, uint256 x, uint256 y) with (env e) {
//            require(gateways(guid.targetDomain) != router);
//        }
//    }

invariant values_indexes_consistency(uint256 zIndex, bytes32 value)
    zIndex < numDomains() => (indexesGhost(value) == zIndex + 1 <=> valuesGhost(zIndex) == value)
    filtered { f -> !f.isFallback }
    {
        preserved settle(bytes32 a,uint256 b) with (env e) {
            require(gateways(a) != router);
        }
        preserved requestMint(router.WormholeGUID guid, uint256 x, uint256 y) with (env e) {
            require(gateways(guid.targetDomain) != router);
        }
    }

invariant empty_gateway_implies_not_having_domain(bytes32 domain)
    gateways(domain) == 0 => !hasDomain(domain)
    filtered { f -> !f.isFallback }
    {
        preserved settle(bytes32 a,uint256 b) with (env e) {
            require(gateways(a) != router);
        }
        preserved requestMint(router.WormholeGUID guid, uint256 x, uint256 y) with (env e) {
            require(gateways(guid.targetDomain) != router);
        }
    }

rule numDomains_changes_by_at_most_one(method f) {
    uint256 numDomainsBefore = numDomains();
    require(forall bytes32 domain. gateways(domain) != router);
    env e;
    calldataarg arg;
    f@withrevert(e, arg);
    uint256 numDomainsAfter = numDomains();
    assert(numDomainsAfter == numDomainsBefore
        || numDomainsAfter == numDomainsBefore + 1
        || numDomainsAfter == numDomainsBefore - 1);  // conditions structured this way to gracefully handle overflow
}

// Verify that wards behaves correctly on rely
rule rely(address usr) {
    env e;

    address other;
    require(other != usr);
    uint256 wardOther = wards(other);

    rely(e, usr);

    assert(wards(usr) == 1, "rely did not set the wards as expected");
    assert(wards(other) == wardOther, "rely affected other wards which wasn't expected");
}

// Verify revert rules on rely
rule rely_revert(address usr) {
    env e;

    uint256 ward = wards(e.msg.sender);

    rely@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = ward != 1;

    assert(revert1 => lastReverted, "revert1 failed");
    assert(revert2 => lastReverted, "revert2 failed");

    assert(lastReverted => revert1 || revert2, "Revert rules are not covering all the cases");
}

// Verify that wards behaves correctly on deny
rule deny(address usr) {
    env e;

    address other;
    require(other != usr);
    uint256 wardOther = wards(other);

    deny(e, usr);

    assert(wards(usr) == 0, "deny did not set the wards as expected");
    assert(wards(other) == wardOther, "deny affected other wards which wasn't expected");
}

// Verify revert rules on deny
rule deny_revert(address usr) {
    env e;

    uint256 ward = wards(e.msg.sender);

    deny@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = ward != 1;

    assert(revert1 => lastReverted, "revert1 failed");
    assert(revert2 => lastReverted, "revert2 failed");

    assert(lastReverted => revert1 || revert2, "Revert rules are not covering all the cases");
}

// Verify that gateway behaves correctly on file
rule file_domain_address(bytes32 what, bytes32 domain, address data) {
    env e;

    bool dataIsEmpty = data == 0x0000000000000000000000000000000000000000;
    address gatewayBefore = gateways(domain);
    bool gatewayWasEmpty = gatewayBefore == 0x0000000000000000000000000000000000000000;
    uint256 numDomainsBefore = numDomains();
    bool hasDomainBefore = hasDomain(domain);

    file(e, what, domain, data);

    uint256 numDomainsAfter = numDomains();

    assert(
        gateways(domain) == data, "file did not set gateways(domain) as expected"
    );
    assert(
        !dataIsEmpty
        => domains(data) == domain, "file did not set domains(gateway) as expected"
    );
    assert(
        gatewayWasEmpty && !hasDomainBefore && !dataIsEmpty && numDomainsBefore < max_uint256
//        gatewayWasEmpty && !dataIsEmpty && numDomainsBefore < max_uint256
        => numDomainsAfter == numDomainsBefore + 1, "file did not increase allDomains length as expected"
    );
//    bytes32 domainAt = domainAt@withrevert(numDomainsBefore);
//    assert(
//        !lastReverted && gatewayWasEmpty && !dataIsEmpty
//        => domainAt == domain, "file did not modify allDomains as expected"
//    );
//    assert(
//        !gatewayWasEmpty && gatewayBefore != data
//        => domains(gatewayBefore) == 0x0000000000000000000000000000000000000000000000000000000000000000, "file did not set domains(gateway) as expected 2"
//    );
//    assert(
//        !gatewayWasEmpty && hasDomainBefore && dataIsEmpty
//        => numDomainsAfter == numDomainsBefore - 1, "file did not decrease allDomains length as expected"
//    );
}

// Verify revert rules on file
rule file_domain_address_revert(bytes32 what, bytes32 domain, address data) {
    env e;

    bool whatIsGateway = what == 0x6761746577617900000000000000000000000000000000000000000000000000;
    bool dataIsEmpty = data == 0x0000000000000000000000000000000000000000;
    uint256 ward = wards(e.msg.sender);
    address gateway = gateways(domain);
    bool gatewayWasEmpty = gateway == 0x0000000000000000000000000000000000000000;
    uint256 numDomains = numDomains();
    bool hasDomain = hasDomain(domain);
    uint256 pos = indexesGhost(domain);

    file@withrevert(e, what, domain, data);

    bool revert1 = e.msg.value > 0;
    bool revert2 = ward != 1;
    bool revert3 = !whatIsGateway;
    // The two following revert cases are in fact not possible due how the code as a whole works.
    // TODO: see if we can make invariants to remove them.
    bool revert4 = whatIsGateway && !gatewayWasEmpty && dataIsEmpty && hasDomain && numDomains == 0;
    bool revert5 = whatIsGateway && !gatewayWasEmpty && dataIsEmpty && hasDomain && pos > numDomains;

    assert(revert1 => lastReverted, "revert1 failed");
    assert(revert2 => lastReverted, "revert2 failed");
    assert(revert3 => lastReverted, "revert3 failed");
    assert(revert4 => lastReverted, "revert4 failed");
    assert(revert5 => lastReverted, "revert5 failed");

    assert(lastReverted => revert1 || revert2 || revert3 ||
                           revert4 || revert5, "Revert rules are not covering all the cases");
}

// Verify that requestMint behaves correctly
rule requestMint(
        router.WormholeGUID guid,
        uint256 maxFeePercentage,
        uint256 operatorFee
    ) {
    env e;

    require(gateways(guid.targetDomain) == join);

    uint256 postFeeAmount;
    uint256 totalFee;
    postFeeAmount, totalFee = requestMint(e, guid, maxFeePercentage, operatorFee);

    bytes32 sourceDomain;
    bytes32 targetDomain;
    bytes32 receiver;
    bytes32 operator;
    uint128 amount;
    uint80 nonce;
    uint48 timestamp;
    sourceDomain, targetDomain, receiver, operator, amount, nonce, timestamp = join.wormholeGUID();
    assert(sourceDomain == guid.sourceDomain, "guid.sourceDomain was not preserved");
    assert(targetDomain == guid.targetDomain, "guid.targetDomain was not preserved");
    assert(receiver == guid.receiver, "guid.receiver was not preserved");
    assert(operator == guid.operator, "guid.operator was not preserved");
    assert(amount == guid.amount, "guid.amount was not preserved");
    assert(nonce == guid.nonce, "guid.nonce was not preserved");
    assert(timestamp == guid.timestamp, "guid.timestamp was not preserved");
    assert(join.maxFeePercentage() == maxFeePercentage, "maxFeePercentage was not preserved");
    assert(join.operatorFee() == operatorFee, "operatorFee was not preserved");
    assert(join.postFeeAmount() == postFeeAmount, "postFeeAmount was not preserved");
    assert(join.totalFee() == totalFee, "totalFee was not preserved");
}

// Verify revert rules on requestMint
rule requestMint_revert(
        router.WormholeGUID guid,
        uint256 maxFeePercentage,
        uint256 operatorFee
    ) {
    env e;

    require(guid.amount <= max_uint128);
    require(guid.nonce <= 0xffffffffffffffffffff);
    require(guid.timestamp <= 0xffffffffffff);

    address targetGateway = gateways(guid.targetDomain);
    require(targetGateway == join);
    require(currentContract != targetGateway);

    address sourceGateway = gateways(guid.sourceDomain);

    requestMint@withrevert(e, guid, maxFeePercentage, operatorFee);

    bool revert1 = e.msg.value > 0;
    bool revert2 = sourceGateway != e.msg.sender;
    bool revert3 = targetGateway == 0x0000000000000000000000000000000000000000;

    assert(revert1 => lastReverted, "revert1 failed");
    assert(revert2 => lastReverted, "revert2 failed");
    assert(revert3 => lastReverted, "revert3 failed");

    assert(lastReverted => revert1 || revert2 || revert3, "Revert rules are not covering all the cases");
}

// Verify that settle behaves correctly
rule settle(bytes32 targetDomain, uint256 batchedDaiToFlush) {
    env e;

    address targetGateway = gateways(targetDomain);

    require(targetGateway == join);
    require(currentContract != targetGateway);

    uint256 daiSenderBefore = dai.balanceOf(e.msg.sender);
    uint256 daiGatewayBefore = dai.balanceOf(targetGateway);

    settle(e, targetDomain, batchedDaiToFlush);

    uint256 daiSenderAfter = dai.balanceOf(e.msg.sender);
    uint256 daiGatewayAfter = dai.balanceOf(targetGateway);

    assert(join.sourceDomain() == domains(e.msg.sender), "sourceDomain was not preserved");
    assert(join.batchedDaiToFlush() == batchedDaiToFlush, "batchedDaiToFlush was not preserved");
    assert(e.msg.sender != targetGateway => daiSenderAfter == daiSenderBefore - batchedDaiToFlush, "Sender's DAI balance did not decrease as expected");
    assert(e.msg.sender != targetGateway => daiGatewayAfter == daiGatewayBefore + batchedDaiToFlush, "Gateway's DAI balance did not increase as expected");
}

// Verify revert rules on settle
rule settle_revert(bytes32 targetDomain, uint256 batchedDaiToFlush) {
    env e;

    address targetGateway = gateways(targetDomain);
    require(targetGateway == join);
    require(currentContract != targetGateway);

    bytes32 sourceDomain = domains(e.msg.sender);
    uint256 allowance = dai.allowance(e.msg.sender, currentContract);
    uint256 daiSender = dai.balanceOf(e.msg.sender);
    uint256 daiTarget = dai.balanceOf(targetGateway);

    settle@withrevert(e, targetDomain, batchedDaiToFlush);

    bool revert1 = e.msg.value > 0;
    bool revert2 = sourceDomain == 0x0000000000000000000000000000000000000000000000000000000000000000;
    bool revert3 = targetGateway == 0x0000000000000000000000000000000000000000;
    bool revert4 = e.msg.sender != currentContract && allowance < batchedDaiToFlush;
    bool revert5 = daiSender < batchedDaiToFlush;
    bool revert6 = e.msg.sender != targetGateway && daiTarget + batchedDaiToFlush > max_uint256;

    assert(revert1 => lastReverted, "revert1 failed");
    assert(revert2 => lastReverted, "revert2 failed");
    assert(revert3 => lastReverted, "revert3 failed");
    assert(revert4 => lastReverted, "revert4 failed");
    assert(revert5 => lastReverted, "revert5 failed");
    assert(revert6 => lastReverted, "revert6 failed");

    assert(lastReverted => revert1 || revert2 || revert3 ||
                           revert4 || revert5 || revert6, "Revert rules are not covering all the cases");
}
