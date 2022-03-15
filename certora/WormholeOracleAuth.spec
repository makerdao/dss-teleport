// WormholeOracleAuth.spec

using WormholeOracleAuth as oracle
using Auxiliar as aux
using WormholeJoinMock as join

methods {
    signers(address) returns (uint256) envfree
    threshold() returns (uint256) envfree
    wards(address) returns (uint256) envfree
    wormholeJoin() returns (address) envfree
    requestMint(oracle.WormholeGUID, uint256, uint256) returns (uint256) => DISPATCHER(true)
    aux.getSignHash(oracle.WormholeGUID) returns (bytes32) envfree
    aux.bytes32ToAddress(bytes32) returns (address) envfree
    aux.callEcrecover(bytes32, uint256, bytes32, bytes32) returns (address) envfree
    aux.processUpToIndex(bytes32, bytes, uint256) returns (uint256, uint256) envfree
    aux.splitSignature(bytes, uint256) returns (uint8, bytes32, bytes32) envfree
    aux.oracle() returns (address) envfree
    aux.checkMalformedArray(address[]) envfree
    join.wormholeGUID() returns(bytes32, bytes32, bytes32, bytes32, uint128, uint80, uint48) envfree
    join.maxFeePercentage() returns (uint256) envfree
    join.operatorFee() returns (uint256) envfree
    join.postFeeAmount() returns (uint256) envfree
    join.totalFee() returns (uint256) envfree
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

// Verify that threshold behaves correctly on file
rule file_uint256(bytes32 what, uint256 data) {
    env e;

    file(e, what, data);

    assert(threshold() == data, "file did not set threshold as expected");
}

// Verify revert rules on file
rule file_uint256_revert(bytes32 what, uint256 data) {
    env e;

    uint256 ward = wards(e.msg.sender);

    file@withrevert(e, what, data);

    bool revert1 = e.msg.value > 0;
    bool revert2 = ward != 1;
    bool revert3 = what != 0x7468726573686f6c640000000000000000000000000000000000000000000000; // what is not "threshold"

    assert(revert1 => lastReverted, "revert1 failed");
    assert(revert2 => lastReverted, "revert2 failed");
    assert(revert3 => lastReverted, "revert3 failed");

    assert(lastReverted => revert1 || revert2 || revert3, "Revert rules are not covering all the cases");
}

// Verify that addSigners behaves correctly
rule addSigners(address[] signers_) {
    env e;

    uint256 i;
    uint256 length = signers_.length;

    require(i < length);

    addSigners(e, signers_);

    assert(signers(signers_[i]) == 1, "addSigners did not set signer as expected");
}

// Verify revert rules on addSigners
rule addSigners_revert(address[] signers_) {
    env e;

    uint256 ward = wards(e.msg.sender);

    aux.checkMalformedArray@withrevert(signers_);
    bool malformed = lastReverted; // Nasty workaround to catch malformed array revert case

    addSigners@withrevert(e, signers_);

    bool revert1 = e.msg.value > 0;
    bool revert2 = ward != 1;
    bool revert3 = malformed;

    assert(revert1 => lastReverted, "revert1 failed");
    assert(revert2 => lastReverted, "revert2 failed");
    assert(revert3 => lastReverted, "revert3 failed");

    assert(lastReverted => revert1 || revert2 || revert3, "Revert rules are not covering all the cases");
}

// Verify that removeSigners behaves correctly
rule removeSigners(address[] signers_) {
    env e;

    uint256 i;
    uint256 length = signers_.length;

    require(i < length);

    removeSigners(e, signers_);

    assert(signers(signers_[i]) == 0, "addSigners did not set signer as expected");
}

// Verify revert rules on removeSigners
rule removeSigners_revert(address[] signers_) {
    env e;

    uint256 ward = wards(e.msg.sender);

    aux.checkMalformedArray@withrevert(signers_);
    bool malformed = lastReverted; // Nasty workaround to catch malformed array revert case

    removeSigners@withrevert(e, signers_);

    bool revert1 = e.msg.value > 0;
    bool revert2 = ward != 1;
    bool revert3 = malformed;

    assert(revert1 => lastReverted, "revert1 failed");
    assert(revert2 => lastReverted, "revert2 failed");
    assert(revert3 => lastReverted, "revert3 failed");

    assert(lastReverted => revert1 || revert2 || revert3, "Revert rules are not covering all the cases");
}

// Verify that requestMint behaves correctly
rule requestMint(
        oracle.WormholeGUID guid,
        bytes signatures,
        uint256 maxFeePercentage,
        uint256 operatorFee
    ) {
    env e;

    require(wormholeJoin() == join);

    uint256 postFeeAmount;
    uint256 totalFee;
    postFeeAmount, totalFee = requestMint(e, guid, signatures, maxFeePercentage, operatorFee);

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
        oracle.WormholeGUID guid,
        bytes signatures,
        uint256 maxFeePercentage,
        uint256 operatorFee
) {
    env e;

    require(guid.amount <= max_uint128);
    require(guid.nonce <= 0xffffffffffffffffffff);
    require(guid.timestamp <= 0xffffffffffff);

    require(wormholeJoin() == join);
    require(aux.oracle() == currentContract);

    uint256 ward = wards(e.msg.sender);
    address operatorAddr = aux.bytes32ToAddress(guid.operator);
    uint256 threshold = threshold();
    uint256 count = signatures.length / 65;
    uint256 i;
    require(i + 1 < count);
    bytes32 hash = aux.getSignHash(guid);
    uint256 vI;
    bytes32 rI;
    bytes32 sI;
    vI, rI, sI = aux.splitSignature(signatures, i);
    address recoveredI = aux.callEcrecover(hash, vI, rI, sI);
    uint256 vIPlus1;
    bytes32 rIPlus1;
    bytes32 sIPlus1;
    vIPlus1, rIPlus1, sIPlus1 = aux.splitSignature(signatures, i + 1);
    address recoveredIPlus1 = aux.callEcrecover(hash, vIPlus1, rIPlus1, sIPlus1);

    uint256 numProcessedBeforeI;
    uint256 numValidBeforeI;
    numProcessedBeforeI, numValidBeforeI = aux.processUpToIndex(hash, signatures, i);
    uint256 numProcessedBeforeIPlus1;
    uint256 numValidBeforeIPlus1;
    numProcessedBeforeIPlus1, numValidBeforeIPlus1 = aux.processUpToIndex(hash, signatures, i + 1);

    uint256 a;
    uint256 numValid;
    a, numValid = aux.processUpToIndex(hash, signatures, count);

    requestMint@withrevert(e, guid, signatures, maxFeePercentage, operatorFee);

    bool revert1 = e.msg.value > 0;
    bool revert2 = ward != 1;
    bool revert3 = e.msg.sender != operatorAddr;
    bool revert4 = count < threshold;
    bool revert5 = numValid == 0 && threshold == 0;
    bool revert6 = numProcessedBeforeI < i || numValidBeforeI < threshold && vI != 27 && vI != 28;
    bool revert7 = numProcessedBeforeIPlus1 == i && numValidBeforeIPlus1 < threshold && numValidBeforeIPlus1 <= recoveredI;

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
