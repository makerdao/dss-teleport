// TeleportRouter.spec

using TeleportRouter as router
using DaiMock as dai
using GatewayMock as gateway
using Auxiliar as aux

methods {
    batches(bytes32) returns (uint256) envfree
    domain() returns (bytes32) envfree
    domainAt(uint256) returns (bytes32) envfree
    gateways(bytes32) returns (address) envfree
    hasDomain(bytes32) returns (bool) envfree
    fdust() returns (uint256) envfree
    numDomains() returns (uint256) envfree
    nonce() returns (uint80) envfree
    parentDomain() returns (bytes32) envfree
    registerMint(gateway.TeleportGUID) => DISPATCHER(true)
    settle(bytes32, bytes32, uint256) => DISPATCHER(true)
    wards(address) returns (uint256) envfree
    aux.addressToBytes32(address) returns (bytes32) envfree
    aux.bytes32ToAddress(bytes32) returns (address) envfree
    dai.allowance(address, address) returns (uint256) envfree
    dai.balanceOf(address) returns (uint256) envfree
    gateway.teleportGUID() returns(bytes32, bytes32, bytes32, bytes32, uint128, uint80, uint48) envfree
    gateway.sourceDomain() returns(bytes32) envfree
    gateway.targetDomain() returns(bytes32) envfree
    gateway.amount() returns(uint256) envfree
}

definition RAY() returns uint256 = 10^27;

definition max_uint48() returns mathint = 2^48 - 1;
definition max_uint80() returns mathint = 2^80 - 1;
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

// Verify fallback always reverts
rule fallback_revert(method f) filtered { f -> f.isFallback } {
    env e;

    calldataarg arg;
    f@withrevert(e, arg);

    assert(lastReverted, "Fallback did not revert");
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
        gatewayWasEmpty && !hasDomainBefore && !dataIsEmpty && numDomainsBefore < max_uint256
        => numDomainsAfter == numDomainsBefore + 1, "file did not increase allDomains length as expected"
    );
    bytes32 domainAt = domainAt@withrevert(numDomainsBefore);
    assert(
        !lastReverted && gatewayWasEmpty && !dataIsEmpty
        => domainAt == domain, "file did not modify allDomains as expected"
    );
    assert(
        !gatewayWasEmpty && hasDomainBefore && dataIsEmpty
        => numDomainsAfter == numDomainsBefore - 1, "file did not decrease allDomains length as expected"
    );
}

// Verify revert rules on file
rule file_domain_address_revert(bytes32 what, bytes32 domain, address data) {
    env e;

    bool whatIsGateway = what == 0x6761746577617900000000000000000000000000000000000000000000000000;
    bool dataIsEmpty = data == 0x0000000000000000000000000000000000000000;
    uint256 ward = wards(e.msg.sender);
    bool gatewayWasEmpty = gateways(domain) == 0x0000000000000000000000000000000000000000;
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

// Verify that fdust behaves correctly on file
rule file_uint256(bytes32 what, uint256 data) {
    env e;

    file(e, what, data);

    assert(fdust() == data, "file did not set fdust as expected");
}


// Verify revert rules on file
rule file_uint256_revert(bytes32 what, uint256 data) {
    env e;

    uint256 ward = wards(e.msg.sender);

    file@withrevert(e, what, data);

    bool revert1 = e.msg.value > 0;
    bool revert2 = ward != 1;
    bool revert3 = what != 0x6664757374000000000000000000000000000000000000000000000000000000;

    assert(revert1 => lastReverted, "revert1 failed");
    assert(revert2 => lastReverted, "revert2 failed");
    assert(revert3 => lastReverted, "revert3 failed");

    assert(lastReverted => revert1 || revert2 || revert3, "Revert rules are not covering all the cases");
}

// Verify that registerMint behaves correctly
rule registerMint(router.TeleportGUID guid) {
    env e;

    require(gateways(guid.targetDomain) == gateway);

    registerMint(e, guid);

    bytes32 sourceDomain;
    bytes32 targetDomain;
    bytes32 receiver;
    bytes32 operator;
    uint128 amount;
    uint80 nonce;
    uint48 timestamp;
    sourceDomain, targetDomain, receiver, operator, amount, nonce, timestamp = gateway.teleportGUID();
    assert(sourceDomain == guid.sourceDomain, "guid.sourceDomain was not preserved");
    assert(targetDomain == guid.targetDomain, "guid.targetDomain was not preserved");
    assert(receiver == guid.receiver, "guid.receiver was not preserved");
    assert(operator == guid.operator, "guid.operator was not preserved");
    assert(amount == guid.amount, "guid.amount was not preserved");
    assert(nonce == guid.nonce, "guid.nonce was not preserved");
    assert(timestamp == guid.timestamp, "guid.timestamp was not preserved");
}

// Verify revert rules on registerMint
rule registerMint_revert(router.TeleportGUID guid) {
    env e;

    address parentGateway = gateways(parentDomain());
    address sourceGateway = gateways(guid.sourceDomain);
    address targetGateway = gateways(guid.targetDomain) != 0x0000000000000000000000000000000000000000
                            ? gateways(guid.targetDomain)
                            : parentGateway;
    require(targetGateway == gateway);
    require(currentContract != targetGateway);

    registerMint@withrevert(e, guid);

    bool revert1 = e.msg.value > 0;
    bool revert2 = parentGateway != e.msg.sender && sourceGateway != e.msg.sender;
    bool revert3 = targetGateway == 0x0000000000000000000000000000000000000000;

    assert(revert1 => lastReverted, "revert1 failed");
    assert(revert2 => lastReverted, "revert2 failed");
    assert(revert3 => lastReverted, "revert3 failed");

    assert(lastReverted => revert1 || revert2 || revert3, "Revert rules are not covering all the cases");
}

// Verify that settle behaves correctly
rule settle(bytes32 sourceDomain, bytes32 targetDomain, uint256 amount) {
    env e;

    address targetGateway = gateways(targetDomain) != 0x0000000000000000000000000000000000000000
                            ? gateways(targetDomain)
                            : gateways(parentDomain());
    require(targetGateway == gateway);
    require(currentContract != targetGateway);

    uint256 daiSenderBefore = dai.balanceOf(e.msg.sender);
    uint256 daiGatewayBefore = dai.balanceOf(targetGateway);

    settle(e, sourceDomain, targetDomain, amount);

    uint256 daiSenderAfter = dai.balanceOf(e.msg.sender);
    uint256 daiGatewayAfter = dai.balanceOf(targetGateway);

    assert(gateway.sourceDomain() == sourceDomain, "sourceDomain was not preserved");
    assert(gateway.targetDomain() == targetDomain, "targetDomain was not preserved");
    assert(gateway.amount() == amount, "amount was not preserved");
    assert(e.msg.sender != targetGateway => daiSenderAfter == daiSenderBefore - amount, "Sender's DAI balance did not decrease as expected");
    assert(e.msg.sender != targetGateway => daiGatewayAfter == daiGatewayBefore + amount, "Gateway's DAI balance did not increase as expected");
}

// Verify revert rules on settle
rule settle_revert(bytes32 sourceDomain, bytes32 targetDomain, uint256 amount) {
    env e;

    address parentGateway = gateways(parentDomain());
    address sourceGateway = gateways(sourceDomain);
    address targetGateway = gateways(targetDomain) != 0x0000000000000000000000000000000000000000
                            ? gateways(targetDomain)
                            : parentGateway;
    require(targetGateway == gateway);
    require(currentContract != targetGateway);

    uint256 allowance = dai.allowance(e.msg.sender, currentContract);
    uint256 daiSender = dai.balanceOf(e.msg.sender);
    uint256 daiTarget = dai.balanceOf(targetGateway);

    settle@withrevert(e, sourceDomain, targetDomain, amount);

    bool revert1 = e.msg.value > 0;
    bool revert2 = parentGateway != e.msg.sender && sourceGateway != e.msg.sender;
    bool revert3 = targetGateway == 0x0000000000000000000000000000000000000000;
    bool revert4 = e.msg.sender != currentContract && allowance < amount;
    bool revert5 = daiSender < amount;
    bool revert6 = e.msg.sender != targetGateway && daiTarget + amount > max_uint256;

    assert(revert1 => lastReverted, "revert1 failed");
    assert(revert2 => lastReverted, "revert2 failed");
    assert(revert3 => lastReverted, "revert3 failed");
    assert(revert4 => lastReverted, "revert4 failed");
    assert(revert5 => lastReverted, "revert5 failed");
    assert(revert6 => lastReverted, "revert6 failed");

    assert(lastReverted => revert1 || revert2 || revert3 ||
                           revert4 || revert5 || revert6, "Revert rules are not covering all the cases");
}

// Verify that initiateTeleport behaves correctly
rule initiateTeleport(
        bytes32 _targetDomain,
        bytes32 _receiver,
        uint128 _amount,
        bytes32 _operator
    ) {
    env e;

    uint256 option;

    require(e.block.timestamp <= max_uint48());

    bytes32 domain = domain();

    uint256 batchesTargetBefore = batches(_targetDomain);
    uint80  nonceBefore = nonce();
    uint256 daiSenderBefore = dai.balanceOf(e.msg.sender);
    uint256 daiRouterBefore = dai.balanceOf(currentContract);

    require(gateways(_targetDomain) == gateway);

    if (option == 0) {
        initiateTeleport(e, _targetDomain, _receiver, _amount, _operator);
    } else if (option == 1) {
        initiateTeleport(e, _targetDomain, aux.bytes32ToAddress(_receiver), _amount, aux.bytes32ToAddress(_operator));
    } else {
        initiateTeleport(e, _targetDomain, aux.bytes32ToAddress(_receiver), _amount);
    }

    uint256 batchesTargetAfter = batches(_targetDomain);
    uint80  nonceAfter = nonce();
    uint256 daiSenderAfter = dai.balanceOf(e.msg.sender);
    uint256 daiRouterAfter = dai.balanceOf(currentContract);

    bytes32 sourceDomain;
    bytes32 targetDomain;
    bytes32 receiver;
    bytes32 operator;
    uint128 amount;
    uint80  nonce;
    uint48 timestamp;
    sourceDomain, targetDomain, receiver, operator, amount, nonce, timestamp = gateway.teleportGUID();

    assert(batchesTargetAfter == batchesTargetBefore + amount, "batchesTarget did not increase as expected");
    assert(nonceAfter == nonceBefore + 1, "nonce did not increase as expected");
    assert(e.msg.sender != currentContract => daiSenderAfter == daiSenderBefore - amount, "Sender's DAI balance did not decrease as expected");
    assert(e.msg.sender != currentContract => daiRouterAfter == daiRouterBefore + amount, "Router's DAI balance did not increase as expected");
    assert(sourceDomain == domain, "sourceDomain was not preserved");
    assert(targetDomain == _targetDomain, "targetDomain was not preserved");
    if (option == 0) {
        assert(receiver == _receiver, "receiver was not preserved in option 1");
        assert(operator == _operator, "operator was not preserved in option 1");
    } else if (option == 1) {
        assert(receiver == aux.addressToBytes32(aux.bytes32ToAddress(_receiver)), "receiver was not preserved in option 2");
        assert(operator == aux.addressToBytes32(aux.bytes32ToAddress(_operator)), "operator was not preserved in option 2");
    } else {
        assert(receiver == aux.addressToBytes32(aux.bytes32ToAddress(_receiver)), "receiver was not preserved in option 3");
        assert(operator == 0x0000000000000000000000000000000000000000000000000000000000000000, "operator was not preserved in option 3");
    }
    assert(amount == _amount, "amount was not preserved");
    assert(nonce == nonceBefore, "nonce was not preserved");
    assert(timestamp == e.block.timestamp, "timestamp was not preserved");
}

// Verify revert rules on initiateTeleport
rule initiateTeleport_revert(
        bytes32 _targetDomain,
        bytes32 _receiver,
        uint128 _amount,
        bytes32 _operator
    ) {
    env e;

    uint256 option;

    address targetGateway = gateways(_targetDomain) != 0x0000000000000000000000000000000000000000
                            ? gateways(_targetDomain)
                            : gateways(parentDomain());
    require(targetGateway == gateway);
    require(currentContract != targetGateway);

    uint256 batchesTarget = batches(_targetDomain);
    uint80  nonce = nonce();
    uint256 allowance = dai.allowance(e.msg.sender, currentContract);
    uint256 daiSender = dai.balanceOf(e.msg.sender);
    uint256 daiRouter = dai.balanceOf(currentContract);

    if (option == 0) {
        initiateTeleport@withrevert(e, _targetDomain, _receiver, _amount, _operator);
    } else if (option == 1) {
        initiateTeleport@withrevert(e, _targetDomain, aux.bytes32ToAddress(_receiver), _amount, aux.bytes32ToAddress(_operator));
    } else {
        initiateTeleport@withrevert(e, _targetDomain, aux.bytes32ToAddress(_receiver), _amount);
    }

    bool revert1 = e.msg.value > 0;
    bool revert2 = nonce + 1 > max_uint80();
    bool revert3 = batchesTarget + to_uint256(_amount) > max_uint256;
    bool revert4 = e.msg.sender != currentContract && allowance < _amount;
    bool revert5 = daiSender < _amount;
    bool revert6 = e.msg.sender != currentContract && daiRouter + _amount > max_uint256;
    bool revert7 = targetGateway == 0x0000000000000000000000000000000000000000;

    assert(revert1 => lastReverted, "revert1 failed");
    assert(revert2 => lastReverted, "revert2 failed");
    assert(revert3 => lastReverted, "revert3 failed");
    assert(revert4 => lastReverted, "revert4 failed");
    assert(revert5 => lastReverted, "revert5 failed");
    assert(revert6 => lastReverted, "revert6 failed");
    assert(revert7 => lastReverted, "revert7 failed");

    assert(lastReverted => revert1 || revert2 || revert3 ||
                           revert4 || revert5 || revert6 ||
                           revert7, "Revert rules are not covering all the cases");
}

// Verify that flush behaves correctly
rule flush(bytes32 _targetDomain) {
    env e;

    address targetGateway = gateways(_targetDomain) != 0x0000000000000000000000000000000000000000
                            ? gateways(_targetDomain)
                            : gateways(parentDomain());

    bytes32 domain = domain();

    uint256 batchesTargetBefore = batches(_targetDomain);
    uint256 daiRouterBefore = dai.balanceOf(currentContract);
    uint256 daiTargetBefore = dai.balanceOf(targetGateway);

    require(gateways(_targetDomain) == gateway);

    flush(e, _targetDomain);

    uint256 batchesTargetAfter = batches(_targetDomain);
    uint256 daiRouterAfter = dai.balanceOf(currentContract);
    uint256 daiTargetAfter = dai.balanceOf(targetGateway);

    bytes32 sourceDomain = gateway.sourceDomain();
    bytes32 targetDomain = gateway.targetDomain();
    uint256 amount = gateway.amount();

    assert(batchesTargetAfter == 0, "batchesTarget did not decrease to 0");
    assert(targetGateway != currentContract => daiRouterAfter == daiRouterBefore - amount, "Router's DAI balance did not decrease as expected");
    assert(targetGateway != currentContract => daiTargetAfter == daiTargetBefore + amount, "Target's DAI balance did not increase as expected");
    assert(sourceDomain == domain, "sourceDomain was not preserved");
    assert(targetDomain == _targetDomain, "targetDomain was not preserved");
    assert(amount == batchesTargetBefore, "amount was not preserved");
}

// Verify revert rules on flush
rule flush_revert(bytes32 _targetDomain) {
    env e;

    address targetGateway = gateways(_targetDomain) != 0x0000000000000000000000000000000000000000
                            ? gateways(_targetDomain)
                            : gateways(parentDomain());
    require(targetGateway == gateway);
    require(currentContract != targetGateway);

    uint256 batchesTarget = batches(_targetDomain);
    uint256 fdust = fdust();
    uint256 daiRouter = dai.balanceOf(currentContract);
    uint256 daiTarget = dai.balanceOf(targetGateway);

    flush@withrevert(e, _targetDomain);

    bool revert1 = e.msg.value > 0;
    bool revert2 = batchesTarget < fdust;
    bool revert3 = targetGateway == 0x0000000000000000000000000000000000000000;
    bool revert4 = daiRouter < batchesTarget;
    bool revert5 = targetGateway != currentContract && daiTarget + batchesTarget > max_uint256;

    assert(revert1 => lastReverted, "revert1 failed");
    assert(revert2 => lastReverted, "revert2 failed");
    assert(revert3 => lastReverted, "revert3 failed");
    assert(revert4 => lastReverted, "revert4 failed");
    assert(revert5 => lastReverted, "revert5 failed");

    assert(lastReverted => revert1 || revert2 || revert3 ||
                           revert4 || revert5, "Revert rules are not covering all the cases");
}
