// DssDirectDepositAaveDai.spec

using DaiMock as dai
using WormholeJoinMock as join

methods {
    allDomains(uint256) returns (bytes32) envfree
    domains(address) returns (bytes32) envfree
    domainIndices(bytes32) returns (uint256) envfree
    gateways(bytes32) returns (address) envfree
    numActiveDomains() returns (uint256) envfree
    requestMint((bytes32, bytes32, address, address, uint128, uint80, uint48), uint256) => DISPATCHER(true)
    settle(bytes32, uint256) => DISPATCHER(true)
    wards(address) returns (uint256) envfree
    dai.allowance(address, address) returns (uint256) envfree
    dai.balanceOf(address) returns (uint256) envfree
}

definition RAY() returns uint256 = 10^27;

definition min_int256() returns mathint = -1 * 2^255;
definition max_int256() returns mathint = 2^255 - 1;

// Verify that wards behaves correctly on rely
rule rely(address usr) {
    env e;

    rely(e, usr);

    assert(wards(usr) == 1, "rely did not set the wards as expected");
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

    deny(e, usr);

    assert(wards(usr) == 0, "deny did not set the wards as expected");
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

    address gatewayBefore = gateways(domain);
    uint256 numActiveDomainsBefore = numActiveDomains();
    uint256 pos = domainIndices(domain);
    bytes32 lastDomain = allDomains(numActiveDomainsBefore - 1);

    file(e, what, domain, data);

    uint256 numActiveDomainsAfter = numActiveDomains();

    assert(
        what == 0x6761746577617900000000000000000000000000000000000000000000000000 // what is "gateway"
        => gateways(domain) == data, "file did not set gateways(domain) as expected"
    );
    assert(
        what == 0x6761746577617900000000000000000000000000000000000000000000000000 &&
        data != 0x0000000000000000000000000000000000000000
        => domains(data) == domain, "file did not set domains(gateway) as expected"
    );
    assert(
        what == 0x6761746577617900000000000000000000000000000000000000000000000000 &&
        gatewayBefore == 0x0000000000000000000000000000000000000000 &&
        data != 0x0000000000000000000000000000000000000000
        => numActiveDomainsAfter == numActiveDomainsBefore + 1, "file did not set allDomains length as expected");
    assert(
        what == 0x6761746577617900000000000000000000000000000000000000000000000000 &&
        gatewayBefore == 0x0000000000000000000000000000000000000000 &&
        data != 0x0000000000000000000000000000000000000000
        => allDomains(numActiveDomainsBefore) == domain, "file did not set allDomains as expected");
    assert(
        what == 0x6761746577617900000000000000000000000000000000000000000000000000 &&
        gatewayBefore == 0x0000000000000000000000000000000000000000 &&
        data != 0x0000000000000000000000000000000000000000
        => domainIndices(domain) == numActiveDomainsBefore, "file did not set domainIndices as expected");
    assert(
        what == 0x6761746577617900000000000000000000000000000000000000000000000000 &&
        gatewayBefore != 0x0000000000000000000000000000000000000000
        => domains(gatewayBefore) == 0x0000000000000000000000000000000000000000000000000000000000000000, "file did not set domains(gateway) as expected 2");
    assert(
        what == 0x6761746577617900000000000000000000000000000000000000000000000000 &&
        gatewayBefore != 0x0000000000000000000000000000000000000000 &&
        data == 0x0000000000000000000000000000000000000000
        => numActiveDomainsAfter == numActiveDomainsBefore - 1, "file did not set allDomains length as expected 2");
    assert(
        what == 0x6761746577617900000000000000000000000000000000000000000000000000 &&
        gatewayBefore != 0x0000000000000000000000000000000000000000 &&
        data == 0x0000000000000000000000000000000000000000
        => domainIndices(domain) == 0, "file did not set domainIndices as expected 2");
    assert(
        what == 0x6761746577617900000000000000000000000000000000000000000000000000 &&
        gatewayBefore != 0x0000000000000000000000000000000000000000 &&
        data == 0x0000000000000000000000000000000000000000 &&
        pos != numActiveDomainsBefore - 1
        => allDomains(pos) == lastDomain, "file did not set allDomains as expected 2");
    assert(
        what == 0x6761746577617900000000000000000000000000000000000000000000000000 &&
        gatewayBefore != 0x0000000000000000000000000000000000000000 &&
        data == 0x0000000000000000000000000000000000000000 &&
        pos != numActiveDomainsBefore - 1
        => domainIndices(lastDomain) == pos, "file did not set domainIndices as expected 3");
}

// Verify revert rules on file
rule file_domain_address_revert(bytes32 what, bytes32 domain, address data) {
    env e;

    uint256 ward = wards(e.msg.sender);
    address gateway = gateways(domain);
    uint256 numActiveDomains = numActiveDomains();
    uint256 pos = domainIndices(domain);

    file@withrevert(e, what, domain, data);

    bool revert1 = e.msg.value > 0;
    bool revert2 = ward != 1;
    bool revert3 = what != 0x6761746577617900000000000000000000000000000000000000000000000000; // what is not "gateway"
    bool revert4 = what == 0x6761746577617900000000000000000000000000000000000000000000000000 &&
                   gateway == 0x0000000000000000000000000000000000000000 &&
                   data != 0x0000000000000000000000000000000000000000 &&
                   numActiveDomains == max_uint256;
    // The two following revert cases are in fact not possible due how the code as as a whole works.
    // TODO: see if we can make invariants to remove them.
    bool revert5 = what == 0x6761746577617900000000000000000000000000000000000000000000000000 &&
                   gateway != 0x0000000000000000000000000000000000000000 &&
                   data == 0x0000000000000000000000000000000000000000 &&
                   numActiveDomains == 0;
    bool revert6 = what == 0x6761746577617900000000000000000000000000000000000000000000000000 &&
                   gateway != 0x0000000000000000000000000000000000000000 &&
                   data == 0x0000000000000000000000000000000000000000 &&
                   pos >= numActiveDomains;

    assert(revert1 => lastReverted, "revert1 failed");
    assert(revert2 => lastReverted, "revert2 failed");
    assert(revert3 => lastReverted, "revert3 failed");
    assert(revert4 => lastReverted, "revert4 failed");
    assert(revert5 => lastReverted, "revert5 failed");
    assert(revert6 => lastReverted, "revert6 failed");

    assert(lastReverted => revert1 || revert2 || revert3 ||
                           revert4 || revert5 || revert6, "Revert rules are not covering all the cases");
}

// Verify revert rules on requestMint
rule requestMint_revert(
        bytes32 sourceDomain,
        bytes32 targetDomain,
        address receiver,
        address operator,
        uint128 amount,
        uint80 nonce,
        uint48 timestamp,
        uint256 maxFee
    ) {
    env e;

    address targetGateway = gateways(targetDomain);
    require(targetGateway == join);
    require(currentContract != targetGateway);

    address sourceGateway = gateways(sourceDomain);

    requestMint@withrevert(e, sourceDomain, targetDomain, receiver, operator, amount, nonce, timestamp, maxFee);

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
