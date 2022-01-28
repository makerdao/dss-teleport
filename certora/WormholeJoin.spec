// WormholeJoin.spec

using FeesMock as fees
using Auxiliar as aux
using VatMock as vat
using DaiMock as dai
using DaiJoinMock as daiJoin

methods {
    daiJoin() returns (address) envfree
    debt(bytes32) returns (int256) envfree
    domain() returns (bytes32) envfree
    ilk() returns (bytes32) envfree
    fees(bytes32) returns (address) envfree
    line(bytes32) returns (uint256) envfree
    vat() returns (address) envfree
    vow() returns (address) envfree
    wards(address) returns (uint256) envfree
    wormholes(bytes32) returns (bool, uint248) envfree
    getFee((bytes32, bytes32, bytes32, bytes32, uint128, uint80, uint48), uint256, int256, uint256, uint256) => DISPATCHER(true)
    aux.getGUIDHash(bytes32, bytes32, bytes32, bytes32, uint128, uint80, uint48) returns (bytes32) envfree
    aux.bytes32ToAddress(bytes32) returns (address) envfree
    vat.can(address, address) returns (uint256) envfree
    vat.dai(address) returns (uint256) envfree
    vat.gem(bytes32, address) returns (uint256) envfree
    vat.live() returns (uint256) envfree
    vat.urns(bytes32, address) returns (uint256, uint256) envfree
    dai.allowance(address, address) returns (uint256) envfree
    dai.balanceOf(address) returns (uint256) envfree
    daiJoin.dai() returns (address) envfree
    daiJoin.vat() returns (address) envfree
}

definition WAD() returns uint256 = 10^18;
definition RAY() returns uint256 = 10^27;

definition min_int256() returns mathint = -1 * 2^255;
definition max_int256() returns mathint = 2^255 - 1;

// ghost lineGhost(bytes32) returns mathint {
//     init_state axiom forall bytes32 x. lineGhost(x) == 0;
// }

// hook Sload uint256 v line[KEY bytes32 domain] STORAGE {
//     require lineGhost(domain) == v;
// }

// hook Sstore line[KEY bytes32 a] uint256 n (uint256 o) STORAGE {
//     havoc lineGhost assuming lineGhost@new(a) == n;
// }

// invariant checkLineGhost(bytes32 someKey) line(someKey) == lineGhost(someKey)
// invariant lineCantExceedMaxInt256(bytes32 domain) line(domain) <= max_int256()

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

// Verify that vow behaves correctly on file
rule file_address(bytes32 what, address data) {
    env e;

    file(e, what, data);

    assert(vow() == data, "file did not set vow as expected");
}

// Verify revert rules on file
rule file_address_revert(bytes32 what, address data) {
    env e;

    uint256 ward = wards(e.msg.sender);

    file@withrevert(e, what, data);

    bool revert1 = e.msg.value > 0;
    bool revert2 = ward != 1;
    bool revert3 = what != 0x766f770000000000000000000000000000000000000000000000000000000000; // what is not "vow"

    assert(revert1 => lastReverted, "revert1 failed");
    assert(revert2 => lastReverted, "revert2 failed");
    assert(revert3 => lastReverted, "revert3 failed");

    assert(lastReverted => revert1 || revert2 || revert3, "Revert rules are not covering all the cases");
}

// Verify that fees behaves correctly on file
rule file_domain_address(bytes32 what, bytes32 domain, address data) {
    env e;

    file(e, what, domain, data);

    assert(fees(domain) == data, "file did not set fees as expected");
}

// Verify revert rules on file
rule file_domain_address_revert(bytes32 what, bytes32 domain, address data) {
    env e;

    uint256 ward = wards(e.msg.sender);

    file@withrevert(e, what, domain, data);

    bool revert1 = e.msg.value > 0;
    bool revert2 = ward != 1;
    bool revert3 = what != 0x6665657300000000000000000000000000000000000000000000000000000000; // what is not "fees"

    assert(revert1 => lastReverted, "revert1 failed");
    assert(revert2 => lastReverted, "revert2 failed");
    assert(revert3 => lastReverted, "revert3 failed");

    assert(lastReverted => revert1 || revert2 || revert3, "Revert rules are not covering all the cases");
}

// Verify that line behaves correctly on file
rule file_domain_uint256(bytes32 what, bytes32 domain, uint256 data) {
    env e;

    file(e, what, domain, data);

    assert(line(domain) == data, "file did not set line as expected");
}

// Verify revert rules on file
rule file_domain_uint256_revert(bytes32 what, bytes32 domain, uint256 data) {
    env e;

    uint256 ward = wards(e.msg.sender);

    file@withrevert(e, what, domain, data);

    bool revert1 = e.msg.value > 0;
    bool revert2 = ward != 1;
    bool revert3 = what != 0x6c696e6500000000000000000000000000000000000000000000000000000000; // what is not "line"
    bool revert4 = what == 0x6c696e6500000000000000000000000000000000000000000000000000000000 && data > max_int256();

    assert(revert1 => lastReverted, "revert1 failed");
    assert(revert2 => lastReverted, "revert2 failed");
    assert(revert3 => lastReverted, "revert3 failed");
    assert(revert4 => lastReverted, "revert4 failed");

    assert(lastReverted => revert1 || revert2 || revert3 ||
                           revert4, "Revert rules are not covering all the cases");
}

definition canGenerate(uint256 line, int256 debt, uint248 pending)
    returns bool = to_int256(line) > to_int256(debt) && pending > 0;

definition gap(bool canGenerate, uint256 line, int256 debt)
    returns uint256 = canGenerate
                        ?
                            to_uint256(to_int256(line) - to_int256(debt))
                        :
                            0;

definition amtToTake(bool canGenerate, uint256 gap, uint248 pending)
    returns uint256 = canGenerate
                        ?
                            pending > gap
                            ?
                                gap
                            :
                                pending
                        :
                            0;

definition amtToGenerate(bool canGenerate, uint256 amtToTake, int256 debt)
    returns uint256 = canGenerate
                        ?
                            debt >= 0 || to_uint256(0 - debt) < amtToTake
                            ?
                                debt < 0
                                ?
                                    amtToTake - to_uint256(0 - debt)
                                :
                                    amtToTake
                            :
                                0
                        :
                            0;

definition feeAmt(env e, bool canGenerate, bool vatLive, bytes32 sourceDomain, bytes32 targetDomain, bytes32 receiver, bytes32 operator, uint128 amount, uint80 nonce, uint48 timestamp, uint256 line, int256 debt, uint256 pending, uint256 amtToTake)
    returns uint256 = canGenerate && vatLive
                        ?
                            fees.getFee(e, sourceDomain, targetDomain, receiver, operator, amount, nonce, timestamp, line, debt, pending, amtToTake)
                        :
                            0;

// Verify that requestMint behaves correctly
rule requestMint(
        bytes32 sourceDomain,
        bytes32 targetDomain,
        bytes32 receiver,
        bytes32 operator,
        uint128 amount,
        uint80  nonce,
        uint48  timestamp,
        uint256 maxFeePercentage
    ) {
    env e;

    address receiverAddr = aux.bytes32ToAddress(receiver);
    address operatorAddr = aux.bytes32ToAddress(operator);

    require(fees(sourceDomain) == fees);
    require(vow() != currentContract);
    require(vow() != daiJoin());
    require(vow() != operatorAddr);
    require(operatorAddr != daiJoin());
    require(operatorAddr != currentContract);

    bytes32 hashGUID = aux.getGUIDHash(sourceDomain, targetDomain, receiver, operator, amount, nonce, timestamp);

    bool vatLive = vat.live() == 1;
    uint256 line = vatLive ? line(sourceDomain): 0;
    int256 debtBefore = debt(sourceDomain);

    bool    blessedBefore;
    uint248 pendingBefore;
    blessedBefore, pendingBefore = wormholes(hashGUID);

    bool canGenerate = canGenerate(line, debtBefore, amount);
    uint256 gap = gap(canGenerate, line, debtBefore);
    uint256 amtToTake = amtToTake(canGenerate, gap, amount);
    uint256 amtToGenerate = amtToGenerate(canGenerate, amtToTake, debtBefore);
    uint256 feeAmt = feeAmt(e, canGenerate, vatLive, sourceDomain, targetDomain, receiver, operator, amount, nonce, timestamp, line, debtBefore, pendingBefore, amtToTake);

    uint256 receiverDaiBalanceBefore = dai.balanceOf(receiverAddr);
    uint256 vowVatDaiBalanceBefore = vat.dai(vow());
    uint256 operatorVatDaiBalanceBefore = vat.dai(operatorAddr);

    uint256 inkBefore;
    uint256 artBefore;
    inkBefore, artBefore = vat.urns(ilk(), currentContract);

    uint256 postFeeAmount = requestMint(e, sourceDomain, targetDomain, receiver, operator, amount, nonce, timestamp, maxFeePercentage);

    int256 debtAfter = debt(sourceDomain);

    bool    blessedAfter;
    uint248 pendingAfter;
    blessedAfter, pendingAfter = wormholes(hashGUID);

    uint256 receiverDaiBalanceAfter = dai.balanceOf(receiverAddr);
    uint256 vowVatDaiBalanceAfter = vat.dai(vow());
    uint256 operatorVatDaiBalanceAfter = vat.dai(operatorAddr);

    uint256 inkAfter;
    uint256 artAfter;
    inkAfter, artAfter = vat.urns(ilk(), currentContract);

    assert(to_mathint(debtAfter) == to_mathint(debtBefore) + to_mathint(amtToTake), "debt has not increased as expected");
    assert(blessedBefore == false, "blessed before call should be false");
    assert(blessedAfter == true, "blessed after call should be true");
    assert(pendingAfter == amount - amtToTake, "pending has not acted as expected");
    assert(receiverDaiBalanceAfter == receiverDaiBalanceBefore + amtToTake - feeAmt, "balance of receiver did not increase as expected");
    assert(vowVatDaiBalanceAfter == vowVatDaiBalanceBefore + feeAmt * RAY(), "balance of vow did not increase as expected");
    assert(operatorVatDaiBalanceAfter == operatorVatDaiBalanceBefore, "balance of operator did not increase as expected");
    assert(inkAfter == inkBefore + amtToGenerate, "ink has not increased as expected");
    assert(artAfter == artBefore + amtToGenerate, "art has not increased as expected");
    assert(postFeeAmount == amtToTake - feeAmt, "postFeeAmount is not the value expected");
}

// Verify revert rules on requestMint
rule requestMint_revert(
        bytes32 sourceDomain,
        bytes32 targetDomain,
        bytes32 receiver,
        bytes32 operator,
        uint128 amount,
        uint80  nonce,
        uint48  timestamp,
        uint256 maxFeePercentage
    ) {
    env e;

    address receiverAddr = aux.bytes32ToAddress(receiver);
    address operatorAddr = aux.bytes32ToAddress(operator);

    require(vat() == vat);
    require(daiJoin.vat() == vat);
    require(daiJoin.dai() == dai);
    require(fees(sourceDomain) == fees);
    require(vow() != currentContract);
    require(vow() != daiJoin());
    require(vow() != operatorAddr);
    require(operatorAddr != daiJoin());
    require(operatorAddr != currentContract);

    uint256 ward = wards(e.msg.sender);

    bytes32 hashGUID = aux.getGUIDHash(sourceDomain, targetDomain, receiver, operator, amount, nonce, timestamp);

    bytes32 domain = domain();

    bool vatLive = vat.live() == 1;
    uint256 line = vatLive ? line(sourceDomain): 0;
    require(to_mathint(line) <= max_int256()); // TODO: see to replace with a proper invariant
    int256 debt = debt(sourceDomain);

    bool    blessed;
    uint248 pending;
    blessed, pending = wormholes(hashGUID);

    bool canGenerate = canGenerate(line, debt, amount);
    uint256 gap = gap(canGenerate, line, debt);
    uint256 amtToTake = amtToTake(canGenerate, gap, amount);
    uint256 amtToGenerate = amtToGenerate(canGenerate, amtToTake, debt);
    uint256 feeAmt = feeAmt(e, canGenerate, vatLive, sourceDomain, targetDomain, receiver, operator, amount, nonce, timestamp, line, debt, pending, amtToTake);

    uint256 ink;
    uint256 art;
    ink, art = vat.urns(ilk(), currentContract);
    uint256 gemWormwholeJoin = vat.gem(ilk(), currentContract);
    uint256 vatDaiWormwholeJoin = vat.dai(currentContract);
    uint256 vatDaiDaiJoin = vat.dai(daiJoin());
    uint256 vatDaiVow = vat.dai(vow());
    uint256 vatDaiOperator = vat.dai(operatorAddr);
    uint256 daiReceiver = dai.balanceOf(receiverAddr);

    uint256 can = vat.can(currentContract, daiJoin());

    requestMint@withrevert(e, sourceDomain, targetDomain, receiver, operator, amount, nonce, timestamp, maxFeePercentage);

    bool revert1  = e.msg.value > 0;
    bool revert2  = ward != 1;
    bool revert3  = blessed;
    bool revert4  = targetDomain != domain;
    bool revert5  = canGenerate && (to_mathint(line) - to_mathint(debt)) > max_int256(); // As debt can be negative, (- - == +) can overflow
    bool revert6  = canGenerate && maxFeePercentage * amtToTake > max_uint256;
    bool revert7  = canGenerate && feeAmt > maxFeePercentage * amtToTake / WAD();
    bool revert8  = canGenerate && debt < 0 && to_mathint(debt) == min_int256();
    bool revert9  = canGenerate && to_mathint(debt) + to_mathint(amtToTake) > max_int256();
    bool revert10 = canGenerate && (debt >= 0 || 0 - to_mathint(debt) < to_mathint(amtToTake)) && gemWormwholeJoin + amtToGenerate > max_uint256;
    bool revert11 = canGenerate && (debt >= 0 || 0 - to_mathint(debt) < to_mathint(amtToTake)) && ink + amtToGenerate > max_uint256;
    bool revert12 = canGenerate && (debt >= 0 || 0 - to_mathint(debt) < to_mathint(amtToTake)) && art + amtToGenerate > max_uint256;
    bool revert13 = canGenerate && (debt >= 0 || 0 - to_mathint(debt) < to_mathint(amtToTake)) && amtToGenerate * RAY() > max_int256();
    bool revert14 = canGenerate && (debt >= 0 || 0 - to_mathint(debt) < to_mathint(amtToTake)) && vatDaiWormwholeJoin + amtToGenerate * RAY() > max_uint256;
    bool revert15 = canGenerate && amtToTake < feeAmt;
    bool revert16 = canGenerate && (amtToTake - feeAmt) * RAY() > max_uint256;
    bool revert17 = canGenerate && can != 1;
    bool revert18 = canGenerate && vatDaiWormwholeJoin + amtToGenerate * RAY() < amtToTake * RAY(); // This covers both reverts when paying to the receiver and the fee
    bool revert19 = canGenerate && vatDaiDaiJoin + (amtToTake - feeAmt) * RAY() > max_uint256;
    bool revert20 = canGenerate && daiReceiver + (amtToTake - feeAmt) > max_uint256;
    bool revert21 = canGenerate && feeAmt * RAY() > max_uint256;
    bool revert22 = canGenerate && vatDaiVow + feeAmt * RAY() > max_uint256;

    assert(revert1  => lastReverted, "revert1 failed");
    assert(revert2  => lastReverted, "revert2 failed");
    assert(revert3  => lastReverted, "revert3 failed");
    assert(revert4  => lastReverted, "revert4 failed");
    assert(revert5  => lastReverted, "revert5 failed");
    assert(revert6  => lastReverted, "revert6 failed");
    assert(revert7  => lastReverted, "revert7 failed");
    assert(revert8  => lastReverted, "revert8 failed");
    assert(revert9  => lastReverted, "revert9 failed");
    assert(revert10 => lastReverted, "revert10 failed");
    assert(revert11 => lastReverted, "revert11 failed");
    assert(revert12 => lastReverted, "revert12 failed");
    assert(revert13 => lastReverted, "revert13 failed");
    assert(revert14 => lastReverted, "revert14 failed");
    assert(revert15 => lastReverted, "revert15 failed");
    assert(revert16 => lastReverted, "revert16 failed");
    assert(revert17 => lastReverted, "revert17 failed");
    assert(revert18 => lastReverted, "revert18 failed");
    assert(revert19 => lastReverted, "revert19 failed");
    assert(revert20 => lastReverted, "revert20 failed");
    assert(revert21 => lastReverted, "revert21 failed");
    assert(revert22 => lastReverted, "revert22 failed");

    assert(lastReverted => revert1  || revert2  || revert3  ||
                           revert4  || revert5  || revert6  ||
                           revert7  || revert8  || revert9  ||
                           revert10 || revert11 || revert12 ||
                           revert13 || revert14 || revert15 ||
                           revert16 || revert17 || revert18 ||
                           revert19 || revert20 || revert21 ||
                           revert22, "Revert rules are not covering all the cases");
}

// Verify that mintPending behaves correctly
rule mintPending(
        bytes32 sourceDomain,
        bytes32 targetDomain,
        bytes32 receiver,
        bytes32 operator,
        uint128 amount,
        uint80  nonce,
        uint48  timestamp,
        uint256 maxFeePercentage
    ) {
    env e;

    address receiverAddr = aux.bytes32ToAddress(receiver);
    address operatorAddr = aux.bytes32ToAddress(operator);

    require(fees(sourceDomain) == fees);
    require(vow() != currentContract);
    require(vow() != daiJoin());
    require(vow() != operatorAddr);
    require(operatorAddr != daiJoin());
    require(operatorAddr != currentContract);

    bytes32 hashGUID = aux.getGUIDHash(sourceDomain, targetDomain, receiver, operator, amount, nonce, timestamp);

    bool vatLive = vat.live() == 1;
    uint256 line = vatLive ? line(sourceDomain): 0;
    int256 debtBefore = debt(sourceDomain);

    bool    blessedBefore;
    uint248 pendingBefore;
    blessedBefore, pendingBefore = wormholes(hashGUID);

    bool canGenerate = canGenerate(line, debtBefore, pendingBefore);
    uint256 gap = gap(canGenerate, line, debtBefore);
    uint256 amtToTake = amtToTake(canGenerate, gap, pendingBefore);
    uint256 amtToGenerate = amtToGenerate(canGenerate, amtToTake, debtBefore);
    uint256 feeAmt = feeAmt(e, canGenerate, vatLive, sourceDomain, targetDomain, receiver, operator, amount, nonce, timestamp, line, debtBefore, pendingBefore, amtToTake);

    uint256 receiverDaiBalanceBefore = dai.balanceOf(receiverAddr);
    uint256 vowVatDaiBalanceBefore = vat.dai(vow());
    uint256 operatorVatDaiBalanceBefore = vat.dai(operatorAddr);

    uint256 inkBefore;
    uint256 artBefore;
    inkBefore, artBefore = vat.urns(ilk(), currentContract);

    uint256 postFeeAmount = mintPending(e, sourceDomain, targetDomain, receiver, operator, amount, nonce, timestamp, maxFeePercentage);

    int256 debtAfter = debt(sourceDomain);

    bool    blessedAfter;
    uint248 pendingAfter;
    blessedAfter, pendingAfter = wormholes(hashGUID);

    uint256 receiverDaiBalanceAfter = dai.balanceOf(receiverAddr);
    uint256 vowVatDaiBalanceAfter = vat.dai(vow());
    uint256 operatorVatDaiBalanceAfter = vat.dai(operatorAddr);

    uint256 inkAfter;
    uint256 artAfter;
    inkAfter, artAfter = vat.urns(ilk(), currentContract);

    assert(to_mathint(debtAfter) == to_mathint(debtBefore) + to_mathint(amtToTake), "debt has not increased as expected");
    assert(blessedAfter == blessedBefore, "blessed has changed when it should not happen");
    assert(pendingAfter == pendingBefore - amtToTake, "pending has not decreased as expected");
    assert(receiverDaiBalanceAfter == receiverDaiBalanceBefore + amtToTake - feeAmt, "balance of receiver did not increase as expected");
    assert(vowVatDaiBalanceAfter == vowVatDaiBalanceBefore + feeAmt * RAY(), "balance of vow did not increase as expected");
    assert(inkAfter == inkBefore + amtToGenerate, "ink has not increased as expected");
    assert(artAfter == artBefore + amtToGenerate, "art has not increased as expected");
    assert(postFeeAmount == amtToTake - feeAmt, "postFeeAmount is not the value expected");
}

// Verify revert rules on mintPending
rule mintPending_revert(
        bytes32 sourceDomain,
        bytes32 targetDomain,
        bytes32 receiver,
        bytes32 operator,
        uint128 amount,
        uint80  nonce,
        uint48  timestamp,
        uint256 maxFeePercentage
    ) {
    env e;

    address receiverAddr = aux.bytes32ToAddress(receiver);
    address operatorAddr = aux.bytes32ToAddress(operator);

    require(vat() == vat);
    require(daiJoin.vat() == vat);
    require(daiJoin.dai() == dai);
    require(fees(sourceDomain) == fees);
    require(vow() != currentContract);
    require(vow() != daiJoin());
    require(vow() != operatorAddr);
    require(operatorAddr != daiJoin());
    require(operatorAddr != currentContract);

    bytes32 hashGUID = aux.getGUIDHash(sourceDomain, targetDomain, receiver, operator, amount, nonce, timestamp);

    bytes32 domain = domain();

    bool vatLive = vat.live() == 1;
    uint256 line = vatLive ? line(sourceDomain): 0;
    require(to_mathint(line) <= max_int256()); // TODO: see to replace with a proper invariant
    int256 debt = debt(sourceDomain);

    bool    blessed;
    uint248 pending;
    blessed, pending = wormholes(hashGUID);

    bool canGenerate = canGenerate(line, debt, pending);
    uint256 gap = gap(canGenerate, line, debt);
    uint256 amtToTake = amtToTake(canGenerate, gap, pending);
    uint256 amtToGenerate = amtToGenerate(canGenerate, amtToTake, debt);
    uint256 feeAmt = feeAmt(e, canGenerate, vatLive, sourceDomain, targetDomain, receiver, operator, amount, nonce, timestamp, line, debt, pending, amtToTake);

    uint256 ink;
    uint256 art;
    ink, art = vat.urns(ilk(), currentContract);
    uint256 gemWormwholeJoin = vat.gem(ilk(), currentContract);
    uint256 vatDaiWormwholeJoin = vat.dai(currentContract);
    uint256 vatDaiDaiJoin = vat.dai(daiJoin());
    uint256 vatDaiVow = vat.dai(vow());
    uint256 vatDaiOperator = vat.dai(operatorAddr);
    uint256 daiReceiver = dai.balanceOf(receiverAddr);

    uint256 can = vat.can(currentContract, daiJoin());

    mintPending@withrevert(e, sourceDomain, targetDomain, receiver, operator, amount, nonce, timestamp, maxFeePercentage);

    bool revert1  = e.msg.value > 0;
    bool revert2  = e.msg.sender != receiverAddr && e.msg.sender != operatorAddr;
    bool revert3  = targetDomain != domain;
    bool revert4  = canGenerate && (to_mathint(line) - to_mathint(debt)) > max_int256(); // As debt can be negative, (- - == +) can overflow
    bool revert5  = canGenerate && maxFeePercentage * amtToTake > max_uint256;
    bool revert6  = canGenerate && feeAmt > maxFeePercentage * amtToTake / WAD();
    bool revert7  = canGenerate && debt < 0 && to_mathint(debt) == min_int256();
    bool revert8  = canGenerate && to_mathint(debt) + to_mathint(amtToTake) > max_int256();
    bool revert9  = canGenerate && (debt >= 0 || 0 - to_mathint(debt) < to_mathint(amtToTake)) && gemWormwholeJoin + amtToGenerate > max_uint256;
    bool revert10 = canGenerate && (debt >= 0 || 0 - to_mathint(debt) < to_mathint(amtToTake)) && ink + amtToGenerate > max_uint256;
    bool revert11 = canGenerate && (debt >= 0 || 0 - to_mathint(debt) < to_mathint(amtToTake)) && art + amtToGenerate > max_uint256;
    bool revert12 = canGenerate && (debt >= 0 || 0 - to_mathint(debt) < to_mathint(amtToTake)) && amtToGenerate * RAY() > max_int256();
    bool revert13 = canGenerate && (debt >= 0 || 0 - to_mathint(debt) < to_mathint(amtToTake)) && vatDaiWormwholeJoin + amtToGenerate * RAY() > max_uint256;
    bool revert14 = canGenerate && amtToTake < feeAmt;
    bool revert15 = canGenerate && (amtToTake - feeAmt) * RAY() > max_uint256;
    bool revert16 = canGenerate && can != 1;
    bool revert17 = canGenerate && vatDaiWormwholeJoin + amtToGenerate * RAY() < amtToTake * RAY(); // This covers both reverts when paying to the receiver and the fee
    bool revert18 = canGenerate && vatDaiDaiJoin + (amtToTake - feeAmt) * RAY() > max_uint256;
    bool revert19 = canGenerate && daiReceiver + (amtToTake - feeAmt) > max_uint256;
    bool revert20 = canGenerate && feeAmt * RAY() > max_uint256;
    bool revert21 = canGenerate && vatDaiVow + feeAmt * RAY() > max_uint256;

    assert(revert1  => lastReverted, "revert1 failed");
    assert(revert2  => lastReverted, "revert2 failed");
    assert(revert3  => lastReverted, "revert3 failed");
    assert(revert4  => lastReverted, "revert4 failed");
    assert(revert5  => lastReverted, "revert5 failed");
    assert(revert6  => lastReverted, "revert6 failed");
    assert(revert7  => lastReverted, "revert7 failed");
    assert(revert8  => lastReverted, "revert8 failed");
    assert(revert9  => lastReverted, "revert9 failed");
    assert(revert10 => lastReverted, "revert10 failed");
    assert(revert11 => lastReverted, "revert11 failed");
    assert(revert12 => lastReverted, "revert12 failed");
    assert(revert13 => lastReverted, "revert13 failed");
    assert(revert14 => lastReverted, "revert14 failed");
    assert(revert15 => lastReverted, "revert15 failed");
    assert(revert16 => lastReverted, "revert16 failed");
    assert(revert17 => lastReverted, "revert17 failed");
    assert(revert18 => lastReverted, "revert18 failed");
    assert(revert19 => lastReverted, "revert19 failed");
    assert(revert20 => lastReverted, "revert20 failed");
    assert(revert21 => lastReverted, "revert21 failed");

    assert(lastReverted => revert1  || revert2  || revert3  ||
                           revert4  || revert5  || revert6  ||
                           revert7  || revert8  || revert9  ||
                           revert10 || revert11 || revert12 ||
                           revert13 || revert14 || revert15 ||
                           revert16 || revert17 || revert18 ||
                           revert19 || revert20 || revert21, "Revert rules are not covering all the cases");
}

rule settle(bytes32 sourceDomain, uint256 batchedDaiToFlush) {
    env e;

    bool vatLive = vat.live() == 1;
    int256 debtBefore = debt(sourceDomain);

    uint256 inkBefore;
    uint256 artBefore;
    inkBefore, artBefore = vat.urns(ilk(), currentContract);

    uint256 vatDaiJoinBefore = vat.dai(currentContract);

    uint256 amtToPayBack = batchedDaiToFlush <= artBefore ? batchedDaiToFlush : artBefore;

    settle(e, sourceDomain, batchedDaiToFlush);

    int256 debtAfter = debt(sourceDomain);

    uint256 inkAfter;
    uint256 artAfter;
    inkAfter, artAfter = vat.urns(ilk(), currentContract);

    uint256 vatDaiJoinAfter = vat.dai(currentContract);

    assert(to_mathint(debtAfter) == to_mathint(debtBefore) - to_mathint(batchedDaiToFlush), "debt has not decreased as expected");
    assert(vatLive => inkAfter == inkBefore - amtToPayBack, "ink has not decreased as expected");
    assert(vatLive => artAfter == artBefore - amtToPayBack, "art has not decreased as expected");
    assert(!vatLive => inkAfter == inkBefore, "ink has not stayed the same as expected");
    assert(!vatLive => artAfter == artBefore, "art has not stayed the same as expected");
    assert(vatLive && batchedDaiToFlush > artBefore => vatDaiJoinAfter == vatDaiJoinBefore + (batchedDaiToFlush - artBefore) * RAY(), "join vat dai has not increased as expected 1");
    assert(!vatLive => vatDaiJoinAfter == vatDaiJoinBefore + batchedDaiToFlush * RAY(), "join vat dai has not increased as expected 2");
}

rule settle_revert(bytes32 sourceDomain, uint256 batchedDaiToFlush) {
    env e;

    require(vat() == vat);
    require(daiJoin.vat() == vat);
    require(daiJoin.dai() == dai);

    bool vatLive = vat.live() == 1;

    int256 debt = debt(sourceDomain);

    uint256 vatDaiJoin = vat.dai(currentContract);
    uint256 vatDaiDaiJoin = vat.dai(daiJoin);

    uint256 vatGemJoin = vat.gem(ilk(), currentContract);

    uint256 ink;
    uint256 art;
    ink, art = vat.urns(ilk(), currentContract);

    uint256 daiBalJoin = dai.balanceOf(currentContract);
    uint256 daiAllJoinDaiJoin = dai.allowance(currentContract, daiJoin);

    uint256 amtToPayBack = batchedDaiToFlush <= art ? batchedDaiToFlush : art;

    settle@withrevert(e, sourceDomain, batchedDaiToFlush);

    bool revert1  = e.msg.value > 0;
    bool revert2  = batchedDaiToFlush > max_int256();
    bool revert3  = batchedDaiToFlush * RAY() > max_uint256;
    bool revert4  = batchedDaiToFlush * RAY() > vatDaiDaiJoin;
    bool revert5  = vatDaiJoin + batchedDaiToFlush * RAY() > max_uint256;
    bool revert6  = daiBalJoin < batchedDaiToFlush;
    bool revert7  = daiAllJoinDaiJoin < batchedDaiToFlush;
    bool revert8  = vatLive && amtToPayBack > 0 && -1 * to_mathint(amtToPayBack) * RAY() < min_int256();
    bool revert9  = vatLive && amtToPayBack > ink;
    bool revert10 = vatLive && vatGemJoin + amtToPayBack > max_uint256;
    bool revert11 = to_mathint(debt) - to_mathint(batchedDaiToFlush) < min_int256();

    assert(revert1  => lastReverted, "revert1 failed");
    assert(revert2  => lastReverted, "revert2 failed");
    assert(revert3  => lastReverted, "revert3 failed");
    assert(revert4  => lastReverted, "revert4 failed");
    assert(revert5  => lastReverted, "revert5 failed");
    assert(revert6  => lastReverted, "revert6 failed");
    assert(revert7  => lastReverted, "revert7 failed");
    assert(revert8  => lastReverted, "revert8 failed");
    assert(revert9  => lastReverted, "revert9 failed");
    assert(revert10 => lastReverted, "revert10 failed");
    assert(revert11 => lastReverted, "revert11 failed");

    assert(lastReverted => revert1  || revert2  || revert3  ||
                           revert4  || revert5  || revert6  ||
                           revert7  || revert8  || revert9  ||
                           revert10 || revert11, "Revert rules are not covering all the cases");
}
