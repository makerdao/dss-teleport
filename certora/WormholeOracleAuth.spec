// WormholeOracleAuth.spec

methods {
    signers(address) returns (uint256) envfree
    threshold() returns (uint256) envfree
    wards(address) returns (uint256) envfree
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

    uint256 length = signers_.length;

    addSigners(e, signers_);

    assert(length >= 1  => signers(signers_[0]) == 1, "addSigners did not set signer as expected");
    assert(length >= 2  => signers(signers_[1]) == 1, "addSigners did not set signer as expected");
    assert(length >= 3  => signers(signers_[2]) == 1, "addSigners did not set signer as expected");
    assert(length >= 4  => signers(signers_[3]) == 1, "addSigners did not set signer as expected");
    assert(length >= 5  => signers(signers_[4]) == 1, "addSigners did not set signer as expected");
    assert(length >= 6  => signers(signers_[5]) == 1, "addSigners did not set signer as expected");
    assert(length >= 7  => signers(signers_[6]) == 1, "addSigners did not set signer as expected");
    assert(length >= 8  => signers(signers_[7]) == 1, "addSigners did not set signer as expected");
    assert(length >= 9  => signers(signers_[8]) == 1, "addSigners did not set signer as expected");
    assert(length >= 10 => signers(signers_[9]) == 1, "addSigners did not set signer as expected");
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

    uint256 length = signers_.length;

    removeSigners(e, signers_);

    assert(length >= 1  => signers(signers_[0]) == 0, "removeSigners did not set signer as expected");
    assert(length >= 2  => signers(signers_[1]) == 0, "removeSigners did not set signer as expected");
    assert(length >= 3  => signers(signers_[2]) == 0, "removeSigners did not set signer as expected");
    assert(length >= 4  => signers(signers_[3]) == 0, "removeSigners did not set signer as expected");
    assert(length >= 5  => signers(signers_[4]) == 0, "removeSigners did not set signer as expected");
    assert(length >= 6  => signers(signers_[5]) == 0, "removeSigners did not set signer as expected");
    assert(length >= 7  => signers(signers_[6]) == 0, "removeSigners did not set signer as expected");
    assert(length >= 8  => signers(signers_[7]) == 0, "removeSigners did not set signer as expected");
    assert(length >= 9  => signers(signers_[8]) == 0, "removeSigners did not set signer as expected");
    assert(length >= 10 => signers(signers_[9]) == 0, "removeSigners did not set signer as expected");
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
