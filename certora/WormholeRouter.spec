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
    requestMint(join.WormholeGUID, uint256, uint256) returns (uint256) => DISPATCHER(true)
    settle(bytes32, uint256) => DISPATCHER(true)
    wards(address) returns (uint256) envfree
    dai.allowance(address, address) returns (uint256) envfree
    dai.balanceOf(address) returns (uint256) envfree
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
    havoc indexesGhost assuming indexesGhost@new(a) == n;
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

    bool whatIsGateway = what == 0x6761746577617900000000000000000000000000000000000000000000000000;
    bool dataIsEmpty = data == 0x0000000000000000000000000000000000000000;
    address gatewayBefore = gateways(domain);
    bool gatewayWasEmpty = gatewayBefore == 0x0000000000000000000000000000000000000000;
    uint256 numDomainsBefore = numDomains();
    bool hasDomainBefore = hasDomain(domain);

    file(e, what, domain, data);

    uint256 numDomainsAfter = numDomains();

    assert(
        whatIsGateway => gateways(domain) == data, "file did not set gateways(domain) as expected"
    );
    assert(
        whatIsGateway && !dataIsEmpty
        => domains(data) == domain, "file did not set domains(gateway) as expected"
    );
    assert(
        whatIsGateway && gatewayWasEmpty && !dataIsEmpty && !hasDomainBefore && numDomainsBefore < max_uint256
        => numDomainsAfter == numDomainsBefore + 1, "file did not increase allDomains length as expected");
    assert(
        whatIsGateway && gatewayWasEmpty && !dataIsEmpty
        => domainAt(numDomainsBefore) == domain, "file did not set allDomains as expected");
    assert(
        whatIsGateway && !gatewayWasEmpty
        => domains(gatewayBefore) == 0x0000000000000000000000000000000000000000000000000000000000000000, "file did not set domains(gateway) as expected 2");
    assert(
        whatIsGateway && !gatewayWasEmpty && dataIsEmpty
        => numDomainsAfter == numDomainsBefore - 1, "file did not decrease allDomains length as expected");
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

    assert(e.msg.sender != targetGateway => daiSenderAfter == daiSenderBefore - batchedDaiToFlush);
    assert(e.msg.sender != targetGateway => daiGatewayAfter == daiGatewayBefore + batchedDaiToFlush);
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
