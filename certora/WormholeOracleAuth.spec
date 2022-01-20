// WormholeOracleAuth.spec

using Auxiliar as aux
using WormholeJoinMock as join

methods {
    getSignHash( bytes32, bytes32, bytes32, bytes32, uint128, uint80, uint48) returns (bytes32) envfree
    signers(address) returns (uint256) envfree
    threshold() returns (uint256) envfree
    wards(address) returns (uint256) envfree
    wormholeJoin() returns (address) envfree
    requestMint((bytes32, bytes32, bytes32, bytes32, uint128, uint80, uint48), uint256) => DISPATCHER(true)
    aux.bytes32ToAddress(bytes32) returns (address) envfree
    aux.callEcrecover(bytes32, uint256, bytes32, bytes32) returns (address) envfree
    aux.getNumValid(address, bytes32, bytes) returns (uint256) envfree
}

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

    addSigners@withrevert(e, signers_);

    bool revert1 = e.msg.value > 0;
    bool revert2 = ward != 1;

    assert(revert1 => lastReverted, "revert1 failed");
    assert(revert2 => lastReverted, "revert2 failed");

    assert(lastReverted => revert1 || revert2, "Revert rules are not covering all the cases");
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

    removeSigners@withrevert(e, signers_);

    bool revert1 = e.msg.value > 0;
    bool revert2 = ward != 1;

    assert(revert1 => lastReverted, "revert1 failed");
    assert(revert2 => lastReverted, "revert2 failed");

    assert(lastReverted => revert1 || revert2, "Revert rules are not covering all the cases");
}

rule requestMint_revert(
        bytes32 sourceDomain,
        bytes32 targetDomain,
        bytes32 receiver,
        bytes32 operator,
        uint128 amount,
        uint80 nonce,
        uint48 timestamp,
        bytes signatures,
        uint256 maxFeePercentage
) {
    env e;

    require(wormholeJoin() == join);

    uint256 ward = wards(e.msg.sender);
    address operatorAddr = aux.bytes32ToAddress(operator);
    uint256 threshold = threshold();
    uint256 count = signatures.length / 65;
    // require(i + 1 < count);
    bytes32 hash = getSignHash(sourceDomain, targetDomain, receiver, operator, amount, nonce, timestamp);
    // uint256 vI;
    // bytes32 rI;
    // bytes32 sI;
    // vI, rI, sI = aux.splitSignature(signatures, i);
    // address recoveredI = aux.callEcrecover(hash, vI, rI, sI);
    // uint256 vIPlus1;
    // bytes32 rIPlus1;
    // bytes32 sIPlus1;
    // vIPlus1, rIPlus1, sIPlus1 = aux.splitSignature(signatures, i + 1);
    // address recoveredIPlus1 = aux.callEcrecover(hash, vIPlus1, rIPlus1, sIPlus1);

    // uint256 numValidBeforeI = aux.numValidBeforeIndex(currentContract, hash, signatures, i);
    // uint256 numValidBeforeIPlus1 = aux.numValidBeforeIndex(currentContract, hash, signatures, i + 1);

    // uint256 numValidBeforeI = aux.numValidBeforeIndex(currentContract, hash, signatures, i);
    // uint256 vI = aux.returnV(signatures, i);
    // bool revert5 = forall uint256 i. i < count => numValidBeforeI < threshold && vI != 27 && vI != 28;

    // uint256 numValid = aux.getNumValid(currentContract, hash, signatures);
    bool isValid = isValid(e, hash, signatures, threshold());

    requestMint@withrevert(e, sourceDomain, targetDomain, receiver, operator, amount, nonce, timestamp, signatures, maxFeePercentage);

    bool revert1 = e.msg.value > 0;
    bool revert2 = ward != 1;
    bool revert3 = e.msg.sender != operatorAddr;
    // bool revert4 = numValid < threshold;
    bool revert4 = !isValid;

    assert(revert1 => lastReverted, "revert1 failed");
    assert(revert2 => lastReverted, "revert2 failed");
    assert(revert3 => lastReverted, "revert3 failed");
    assert(revert4 => lastReverted, "revert4 failed");
    // assert(revert5 => lastReverted, "revert5 failed");
    // assert(revert6 => lastReverted, "revert6 failed");

    assert(lastReverted => revert1 || revert2 || revert3 ||
                           revert4, "Revert rules are not covering all the cases");
}
