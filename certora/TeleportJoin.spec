// TeleportJoin.spec

using TeleportJoin as join
using FeesMock as fees
using Auxiliar as aux
using VatMock as vat
using DaiMock as dai
using DaiJoinMock as daiJoin

methods {
    cure() returns (uint256) envfree
    daiJoin() returns (address) envfree
    debt(bytes32) returns (int256) envfree
    domain() returns (bytes32) envfree
    ilk() returns (bytes32) envfree
    fees(bytes32) returns (address) envfree
    line(bytes32) returns (uint256) envfree
    vat() returns (address) envfree
    vow() returns (address) envfree
    wards(address) returns (uint256) envfree
    teleports(bytes32) returns (bool, uint248) envfree
    getFee(join.TeleportGUID, uint256, int256, uint256, uint256) => DISPATCHER(true)
    aux.getGUIDHash(join.TeleportGUID) returns (bytes32) envfree
    aux.bytes32ToAddress(bytes32) returns (address) envfree
    vat.can(address, address) returns (uint256) envfree
    vat.dai(address) returns (uint256) envfree
    vat.gem(bytes32, address) returns (uint256) envfree
    vat.live() returns (uint256) envfree
    vat.sin(address) returns (uint256) envfree
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

ghost someDebtChanged() returns bool {
    init_state axiom someDebtChanged() == false;
}

hook Sstore debt[KEY bytes32 a] int256 debtV (int256 old_debtV) STORAGE {
    havoc someDebtChanged assuming someDebtChanged@new() == ((debtV != old_debtV) ? true : someDebtChanged@old());
}

invariant lineCantExceedMaxInt256(bytes32 domain)
to_mathint(line(domain)) <= max_int256()
filtered { f -> !f.isFallback }

// Verify cure value is frozen after the general system is caged
rule cureCantChangeIfVatCaged(method f) filtered { f -> !f.isFallback } {
    env e;

    require(vat.live() == 0);

    uint256 cureBefore = cure();

    calldataarg arg;
    f(e, arg);

    uint256 cureAfter = cure();

    assert(cureAfter == cureBefore);
}

// Verify that any debt will be bounded by the ink
rule inkBoundsDebt(method f, bytes32 d1, bytes32 d2) {
    env e;

    require(d1 != d2);
    require(!someDebtChanged());  // start false to detect an actual change in some debt value

    uint256 inkBefore;
    uint256 artBefore;  // unused
    inkBefore, artBefore = vat.urns(ilk(), currentContract);

    int256 debt1Before = debt(d1);
    int256 debt2Before = debt(d2);

    require(to_mathint(debt1Before) <= to_mathint(inkBefore));
    require(to_mathint(debt2Before) <= to_mathint(inkBefore));
    require(to_mathint(debt1Before) + to_mathint(debt2Before) <= to_mathint(inkBefore));

    calldataarg arg;
    f(e, arg);

    uint256 inkAfter;
    uint256 artAfter;  // unused
    inkAfter, artAfter = vat.urns(ilk(), currentContract);

    int256 debt1After = debt(d1);
    int256 debt2After = debt(d2);

    bool someDebtChanged = someDebtChanged();

    // With debt1After != debt1Before we guarantee that d1 is the domain used in the call
    assert(debt1After != debt1Before => someDebtChanged);
    assert(debt1After != debt1Before => debt2After == debt2Before, "More than once debt was modified");
    assert(debt1After != debt1Before => to_mathint(debt1After) <= to_mathint(inkAfter), "debt1 was increased beyond the ink limit");
    assert(debt1After != debt1Before => to_mathint(debt2After) <= to_mathint(inkAfter), "debt2 was increased beyond the ink limit");
    assert(debt1After != debt1Before => to_mathint(debt1After) + to_mathint(debt2After) <= to_mathint(inkAfter), "debt1+debt2 were increased beyond the ink limit");
    assert(!someDebtChanged => inkBefore == inkAfter);
}

// Verify fallback always reverts
// In this case is pretty important as we are filtering it out from some invariants/rules
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
    returns uint256 = canGenerate && (debt >= 0 || to_uint256(0 - debt) < amtToTake)
                        ?
                            debt < 0
                            ?
                                amtToTake - to_uint256(0 - debt)
                            :
                                amtToTake
                        :
                            0;

definition feeAmt(env e, bool canGenerate, bool vatLive, join.TeleportGUID guid, uint256 line, int256 debt, uint256 pending, uint256 amtToTake)
    returns uint256 = canGenerate && vatLive
                        ?
                            fees.getFee(e, guid, line, debt, pending, amtToTake)
                        :
                            0;

definition operatorFeeAmt(bool canGenerate, uint256 operatorFee)
    returns uint256 = canGenerate
                        ?
                            operatorFee
                        :
                            0;

// Verify that requestMint behaves correctly
rule requestMint(
        join.TeleportGUID guid,
        uint256 maxFeePercentage,
        uint256 operatorFee
    ) {
    env e;

    address receiverAddr = aux.bytes32ToAddress(guid.receiver);
    address operatorAddr = aux.bytes32ToAddress(guid.operator);

    require(fees(guid.sourceDomain) == fees);
    require(vow() != currentContract);
    require(vow() != daiJoin());
    require(vow() != operatorAddr);
    require(operatorAddr != daiJoin());
    require(operatorAddr != currentContract);
    require(operatorAddr != receiverAddr);

    bytes32 hashGUID = aux.getGUIDHash(guid);

    bool vatLive = vat.live() == 1;
    uint256 line = vatLive ? line(guid.sourceDomain): 0;
    int256 debtBefore = debt(guid.sourceDomain);

    bool    blessedBefore;
    uint248 pendingBefore;
    blessedBefore, pendingBefore = teleports(hashGUID);

    bool canGenerate = canGenerate(line, debtBefore, guid.amount);
    uint256 gap = gap(canGenerate, line, debtBefore);
    uint256 amtToTake = amtToTake(canGenerate, gap, guid.amount);
    uint256 amtToGenerate = amtToGenerate(canGenerate, amtToTake, debtBefore);
    uint256 feeAmt = feeAmt(e, canGenerate, vatLive, guid, line, debtBefore, pendingBefore, amtToTake);
    uint256 operatorFeeAmt = operatorFeeAmt(canGenerate, operatorFee);

    uint256 receiverDaiBalanceBefore = dai.balanceOf(receiverAddr);
    uint256 operatorDaiBalanceBefore = dai.balanceOf(operatorAddr);
    uint256 vowVatDaiBalanceBefore = vat.dai(vow());

    uint256 inkBefore;
    uint256 artBefore;
    inkBefore, artBefore = vat.urns(ilk(), currentContract);

    uint256 cureBefore = cure();

    uint256 postFeeAmount;
    uint256 totalFee;
    postFeeAmount, totalFee = requestMint(e, guid, maxFeePercentage, operatorFee);

    int256 debtAfter = debt(guid.sourceDomain);

    bool    blessedAfter;
    uint248 pendingAfter;
    blessedAfter, pendingAfter = teleports(hashGUID);

    uint256 receiverDaiBalanceAfter = dai.balanceOf(receiverAddr);
    uint256 operatorDaiBalanceAfter = dai.balanceOf(operatorAddr);
    uint256 vowVatDaiBalanceAfter = vat.dai(vow());

    uint256 inkAfter;
    uint256 artAfter;
    inkAfter, artAfter = vat.urns(ilk(), currentContract);

    uint256 cureAfter = cure();

    assert(to_mathint(debtAfter) == to_mathint(debtBefore) + to_mathint(amtToTake), "debt has not increased as expected");
    assert(blessedBefore == false, "blessed before call should be false");
    assert(blessedAfter == true, "blessed after call should be true");
    assert(pendingAfter == guid.amount - amtToTake, "pending has not acted as expected");
    assert(receiverDaiBalanceAfter == receiverDaiBalanceBefore + amtToTake - feeAmt - operatorFeeAmt, "balance of receiver did not increase as expected");
    assert(vowVatDaiBalanceAfter == vowVatDaiBalanceBefore + feeAmt * RAY(), "balance of vow did not increase as expected");
    assert(operatorDaiBalanceAfter == operatorDaiBalanceBefore + operatorFeeAmt, "balance of operator did not increase as expected");
    assert(inkAfter == inkBefore + amtToGenerate, "ink has not increased as expected");
    assert(artAfter == artBefore + amtToGenerate, "art has not increased as expected");
    assert(canGenerate && amtToGenerate > 0 => cureAfter == artAfter * RAY(), "cure has not been updated as expected");
    assert(!canGenerate || amtToGenerate == 0 => cureAfter == cureBefore, "cure has not stayed the same as expected");
    assert(postFeeAmount == amtToTake - feeAmt - operatorFeeAmt, "postFeeAmount is not the expected value");
    assert(totalFee == feeAmt + operatorFeeAmt, "totalFee is not the expected value");
}

// Verify revert rules on requestMint
rule requestMint_revert(
        join.TeleportGUID guid,
        uint256 maxFeePercentage,
        uint256 operatorFee
    ) {
    env e;

    requireInvariant lineCantExceedMaxInt256(guid.sourceDomain);

    address receiverAddr = aux.bytes32ToAddress(guid.receiver);
    address operatorAddr = aux.bytes32ToAddress(guid.operator);

    require(vat() == vat);
    require(daiJoin.vat() == vat);
    require(daiJoin.dai() == dai);
    require(fees(guid.sourceDomain) == fees);
    require(vow() != currentContract);
    require(vow() != daiJoin());
    require(vow() != operatorAddr);
    require(operatorAddr != daiJoin());
    require(operatorAddr != currentContract);
    require(operatorAddr != receiverAddr);

    uint256 ward = wards(e.msg.sender);

    bytes32 hashGUID = aux.getGUIDHash(guid);

    bytes32 domain = domain();

    bool vatLive = vat.live() == 1;
    uint256 line = vatLive ? line(guid.sourceDomain): 0;
    int256 debt = debt(guid.sourceDomain);

    bool    blessed;
    uint248 pending;
    blessed, pending = teleports(hashGUID);

    bool canGenerate = canGenerate(line, debt, guid.amount);
    uint256 gap = gap(canGenerate, line, debt);
    uint256 amtToTake = amtToTake(canGenerate, gap, guid.amount);
    uint256 amtToGenerate = amtToGenerate(canGenerate, amtToTake, debt);
    uint256 feeAmt = feeAmt(e, canGenerate, vatLive, guid, line, debt, pending, amtToTake);
    uint256 operatorFeeAmt = operatorFeeAmt(canGenerate, operatorFee);

    uint256 ink;
    uint256 art;
    ink, art = vat.urns(ilk(), currentContract);
    uint256 wormwholeJoinGemBalance = vat.gem(ilk(), currentContract);
    uint256 wormwholeJoinVatDaiBalance = vat.dai(currentContract);
    uint256 daiJoinVatDaiBalance = vat.dai(daiJoin());
    uint256 vowVatDaiBalance = vat.dai(vow());
    uint256 operatorDaiBalance = dai.balanceOf(operatorAddr);
    uint256 receiverDaiBalance = dai.balanceOf(receiverAddr);

    uint256 can = vat.can(currentContract, daiJoin());

    requestMint@withrevert(e, guid, maxFeePercentage, operatorFee);

    bool revert1  = e.msg.value > 0;
    bool revert2  = ward != 1;
    bool revert3  = blessed;
    bool revert4  = guid.targetDomain != domain;
    bool revert5  = canGenerate && (to_mathint(line) - to_mathint(debt)) > max_int256(); // As debt can be negative, (- - == +) can overflow
    bool revert6  = canGenerate && maxFeePercentage * amtToTake > max_uint256;
    bool revert7  = canGenerate && feeAmt > maxFeePercentage * amtToTake / WAD();
    bool revert8  = canGenerate && debt < 0 && to_mathint(debt) == min_int256();
    bool revert9  = canGenerate && to_mathint(debt) + to_mathint(amtToTake) > max_int256();
    bool revert10 = canGenerate && (debt >= 0 || 0 - to_mathint(debt) < to_mathint(amtToTake)) && wormwholeJoinGemBalance + amtToGenerate > max_uint256;
    bool revert11 = canGenerate && (debt >= 0 || 0 - to_mathint(debt) < to_mathint(amtToTake)) && ink + amtToGenerate > max_uint256;
    bool revert12 = canGenerate && (debt >= 0 || 0 - to_mathint(debt) < to_mathint(amtToTake)) && art + amtToGenerate > max_uint256;
    bool revert13 = canGenerate && (debt >= 0 || 0 - to_mathint(debt) < to_mathint(amtToTake)) && amtToGenerate * RAY() > max_int256();
    bool revert14 = canGenerate && (debt >= 0 || 0 - to_mathint(debt) < to_mathint(amtToTake)) && wormwholeJoinVatDaiBalance + amtToGenerate * RAY() > max_uint256;
    bool revert15 = canGenerate && amtToTake < feeAmt;
    bool revert16 = canGenerate && (amtToTake - feeAmt) * RAY() > max_uint256;
    bool revert17 = canGenerate && can != 1;
    bool revert18 = canGenerate && wormwholeJoinVatDaiBalance + amtToGenerate * RAY() < amtToTake * RAY(); // This covers both reverts when paying to the receiver and the fee
    bool revert19 = canGenerate && amtToTake - feeAmt < operatorFeeAmt;
    bool revert20 = canGenerate && daiJoinVatDaiBalance + (amtToTake - feeAmt) * RAY() > max_uint256; // This includes the dai generated for the receiver and the operator
    bool revert21 = canGenerate && receiverDaiBalance + (amtToTake - feeAmt - operatorFeeAmt) > max_uint256;
    bool revert22 = canGenerate && feeAmt * RAY() > max_uint256;
    bool revert23 = canGenerate && vowVatDaiBalance + feeAmt * RAY() > max_uint256;
    bool revert24 = canGenerate && operatorFeeAmt * RAY() > max_uint256;
    bool revert25 = canGenerate && operatorDaiBalance + operatorFeeAmt > max_uint256;

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
    assert(revert23 => lastReverted, "revert23 failed");
    assert(revert24 => lastReverted, "revert24 failed");
    assert(revert25 => lastReverted, "revert25 failed");

    assert(lastReverted => revert1  || revert2  || revert3  ||
                           revert4  || revert5  || revert6  ||
                           revert7  || revert8  || revert9  ||
                           revert10 || revert11 || revert12 ||
                           revert13 || revert14 || revert15 ||
                           revert16 || revert17 || revert18 ||
                           revert19 || revert20 || revert21 ||
                           revert22 || revert23 || revert24 ||
                           revert25, "Revert rules are not covering all the cases");
}

// Verify that mintPending behaves correctly
rule mintPending(
        join.TeleportGUID guid,
        uint256 maxFeePercentage,
        uint256 operatorFee
    ) {
    env e;

    address receiverAddr = aux.bytes32ToAddress(guid.receiver);
    address operatorAddr = aux.bytes32ToAddress(guid.operator);

    require(fees(guid.sourceDomain) == fees);
    require(vow() != currentContract);
    require(vow() != daiJoin());
    require(vow() != operatorAddr);
    require(operatorAddr != daiJoin());
    require(operatorAddr != currentContract);
    require(operatorAddr != receiverAddr);

    bytes32 hashGUID = aux.getGUIDHash(guid);

    bool vatLive = vat.live() == 1;
    uint256 line = vatLive ? line(guid.sourceDomain): 0;
    int256 debtBefore = debt(guid.sourceDomain);

    bool    blessedBefore;
    uint248 pendingBefore;
    blessedBefore, pendingBefore = teleports(hashGUID);

    bool canGenerate = canGenerate(line, debtBefore, pendingBefore);
    uint256 gap = gap(canGenerate, line, debtBefore);
    uint256 amtToTake = amtToTake(canGenerate, gap, pendingBefore);
    uint256 amtToGenerate = amtToGenerate(canGenerate, amtToTake, debtBefore);
    uint256 feeAmt = feeAmt(e, canGenerate, vatLive, guid, line, debtBefore, pendingBefore, amtToTake);
    uint256 operatorFeeAmt = operatorFeeAmt(canGenerate, operatorFee);

    uint256 receiverDaiBalanceBefore = dai.balanceOf(receiverAddr);
    uint256 operatorDaiBalanceBefore = dai.balanceOf(operatorAddr);
    uint256 vowVatDaiBalanceBefore = vat.dai(vow());

    uint256 inkBefore;
    uint256 artBefore;
    inkBefore, artBefore = vat.urns(ilk(), currentContract);

    uint256 cureBefore = cure();

    uint256 postFeeAmount;
    uint256 totalFee;
    postFeeAmount, totalFee = mintPending(e, guid, maxFeePercentage, operatorFee);

    int256 debtAfter = debt(guid.sourceDomain);

    bool    blessedAfter;
    uint248 pendingAfter;
    blessedAfter, pendingAfter = teleports(hashGUID);

    uint256 receiverDaiBalanceAfter = dai.balanceOf(receiverAddr);
    uint256 operatorDaiBalanceAfter = dai.balanceOf(operatorAddr);
    uint256 vowVatDaiBalanceAfter = vat.dai(vow());

    uint256 inkAfter;
    uint256 artAfter;
    inkAfter, artAfter = vat.urns(ilk(), currentContract);

    uint256 cureAfter = cure();

    assert(to_mathint(debtAfter) == to_mathint(debtBefore) + to_mathint(amtToTake), "debt has not increased as expected");
    assert(blessedAfter == blessedBefore, "blessed has changed when it should not happen");
    assert(pendingAfter == pendingBefore - amtToTake, "pending has not decreased as expected");
    assert(receiverDaiBalanceAfter == receiverDaiBalanceBefore + amtToTake - feeAmt - operatorFeeAmt, "balance of receiver did not increase as expected");
    assert(vowVatDaiBalanceAfter == vowVatDaiBalanceBefore + feeAmt * RAY(), "balance of vow did not increase as expected");
    assert(operatorDaiBalanceAfter == operatorDaiBalanceBefore + operatorFeeAmt, "balance of operator did not increase as expected");
    assert(inkAfter == inkBefore + amtToGenerate, "ink has not increased as expected");
    assert(artAfter == artBefore + amtToGenerate, "art has not increased as expected");
    assert(canGenerate && amtToGenerate > 0 => cureAfter == artAfter * RAY(), "cure has not been updated as expected");
    assert(!canGenerate || amtToGenerate == 0 => cureAfter == cureBefore, "cure has not stayed the same as expected");
    assert(postFeeAmount == amtToTake - feeAmt - operatorFeeAmt, "postFeeAmount is not the expected value");
    assert(totalFee == feeAmt + operatorFeeAmt, "totalFee is not the expected value");
}

// Verify revert rules on mintPending
rule mintPending_revert(
        join.TeleportGUID guid,
        uint256 maxFeePercentage,
        uint256 operatorFee
    ) {
    env e;

    requireInvariant lineCantExceedMaxInt256(guid.sourceDomain);

    address receiverAddr = aux.bytes32ToAddress(guid.receiver);
    address operatorAddr = aux.bytes32ToAddress(guid.operator);

    require(vat() == vat);
    require(daiJoin.vat() == vat);
    require(daiJoin.dai() == dai);
    require(fees(guid.sourceDomain) == fees);
    require(vow() != currentContract);
    require(vow() != daiJoin());
    require(vow() != operatorAddr);
    require(operatorAddr != daiJoin());
    require(operatorAddr != currentContract);
    require(operatorAddr != receiverAddr);

    bytes32 hashGUID = aux.getGUIDHash(guid);

    bytes32 domain = domain();

    bool vatLive = vat.live() == 1;
    uint256 line = vatLive ? line(guid.sourceDomain): 0;
    int256 debt = debt(guid.sourceDomain);

    bool    blessed;
    uint248 pending;
    blessed, pending = teleports(hashGUID);

    bool canGenerate = canGenerate(line, debt, pending);
    uint256 gap = gap(canGenerate, line, debt);
    uint256 amtToTake = amtToTake(canGenerate, gap, pending);
    uint256 amtToGenerate = amtToGenerate(canGenerate, amtToTake, debt);
    uint256 feeAmt = feeAmt(e, canGenerate, vatLive, guid, line, debt, pending, amtToTake);
    uint256 operatorFeeAmt = operatorFeeAmt(canGenerate, operatorFee);

    uint256 ink;
    uint256 art;
    ink, art = vat.urns(ilk(), currentContract);
    uint256 wormwholeJoinGemBalance = vat.gem(ilk(), currentContract);
    uint256 wormwholeJoinVatDaiBalance = vat.dai(currentContract);
    uint256 daiJoinVatDaiBalance = vat.dai(daiJoin());
    uint256 vowVatDaiBalance = vat.dai(vow());
    uint256 operatorDaiBalance = dai.balanceOf(operatorAddr);
    uint256 receiverDaiBalance = dai.balanceOf(receiverAddr);

    uint256 can = vat.can(currentContract, daiJoin());

    mintPending@withrevert(e, guid, maxFeePercentage, operatorFee);

    bool revert1  = e.msg.value > 0;
    bool revert2  = e.msg.sender != receiverAddr && e.msg.sender != operatorAddr;
    bool revert3  = guid.targetDomain != domain;
    bool revert4  = canGenerate && (to_mathint(line) - to_mathint(debt)) > max_int256(); // As debt can be negative, (- - == +) can overflow
    bool revert5  = canGenerate && maxFeePercentage * amtToTake > max_uint256;
    bool revert6  = canGenerate && feeAmt > maxFeePercentage * amtToTake / WAD();
    bool revert7  = canGenerate && debt < 0 && to_mathint(debt) == min_int256();
    bool revert8  = canGenerate && to_mathint(debt) + to_mathint(amtToTake) > max_int256();
    bool revert9  = canGenerate && (debt >= 0 || 0 - to_mathint(debt) < to_mathint(amtToTake)) && wormwholeJoinGemBalance + amtToGenerate > max_uint256;
    bool revert10 = canGenerate && (debt >= 0 || 0 - to_mathint(debt) < to_mathint(amtToTake)) && ink + amtToGenerate > max_uint256;
    bool revert11 = canGenerate && (debt >= 0 || 0 - to_mathint(debt) < to_mathint(amtToTake)) && art + amtToGenerate > max_uint256;
    bool revert12 = canGenerate && (debt >= 0 || 0 - to_mathint(debt) < to_mathint(amtToTake)) && amtToGenerate * RAY() > max_int256();
    bool revert13 = canGenerate && (debt >= 0 || 0 - to_mathint(debt) < to_mathint(amtToTake)) && wormwholeJoinVatDaiBalance + amtToGenerate * RAY() > max_uint256;
    bool revert14 = canGenerate && amtToTake < feeAmt;
    bool revert15 = canGenerate && (amtToTake - feeAmt) * RAY() > max_uint256;
    bool revert16 = canGenerate && can != 1;
    bool revert17 = canGenerate && wormwholeJoinVatDaiBalance + amtToGenerate * RAY() < amtToTake * RAY(); // This covers both reverts when paying to the receiver and the fee
    bool revert18 = canGenerate && amtToTake - feeAmt < operatorFeeAmt;
    bool revert19 = canGenerate && daiJoinVatDaiBalance + (amtToTake - feeAmt) * RAY() > max_uint256; // This includes the dai generated for the receiver and the operator
    bool revert20 = canGenerate && receiverDaiBalance + (amtToTake - feeAmt - operatorFeeAmt) > max_uint256;
    bool revert21 = canGenerate && feeAmt * RAY() > max_uint256;
    bool revert22 = canGenerate && vowVatDaiBalance + feeAmt * RAY() > max_uint256;
    bool revert23 = canGenerate && operatorFeeAmt * RAY() > max_uint256;
    bool revert24 = canGenerate && operatorDaiBalance + operatorFeeAmt > max_uint256;

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
    assert(revert23 => lastReverted, "revert23 failed");
    assert(revert24 => lastReverted, "revert24 failed");

    assert(lastReverted => revert1  || revert2  || revert3  ||
                           revert4  || revert5  || revert6  ||
                           revert7  || revert8  || revert9  ||
                           revert10 || revert11 || revert12 ||
                           revert13 || revert14 || revert15 ||
                           revert16 || revert17 || revert18 ||
                           revert19 || revert20 || revert21 ||
                           revert22 || revert23 || revert24, "Revert rules are not covering all the cases");
}

rule settle(bytes32 sourceDomain, uint256 batchedDaiToFlush) {
    env e;

    require(currentContract != vow());

    bool vatLive = vat.live() == 1;
    int256 debtBefore = debt(sourceDomain);

    uint256 inkBefore;
    uint256 artBefore;
    inkBefore, artBefore = vat.urns(ilk(), currentContract);
    require inkBefore >= artBefore;

    uint256 cureBefore = cure();

    uint256 vatDaiJoinBefore = vat.dai(currentContract);

    uint256 amtToPayBack = debtBefore < 0
                            ? 0
                            : to_mathint(batchedDaiToFlush) <= to_mathint(debtBefore)
                                ? batchedDaiToFlush
                                : to_uint256(debtBefore);

    settle(e, sourceDomain, batchedDaiToFlush);

    int256 debtAfter = debt(sourceDomain);

    uint256 inkAfter;
    uint256 artAfter;
    inkAfter, artAfter = vat.urns(ilk(), currentContract);

    uint256 cureAfter = cure();

    uint256 vatDaiJoinAfter = vat.dai(currentContract);

    assert(to_mathint(debtAfter) == to_mathint(debtBefore) - to_mathint(batchedDaiToFlush), "debt has not decreased as expected");
    assert(vatLive => inkAfter == inkBefore - amtToPayBack, "ink has not decreased as expected");
    assert(vatLive => artAfter == inkBefore - amtToPayBack, "art has not decreased as expected");
    assert(!vatLive => inkAfter == inkBefore, "ink has not stayed the same as expected");
    assert(!vatLive => artAfter == artBefore, "art has not stayed the same as expected");
    assert(vatLive => cureAfter == (inkBefore - amtToPayBack) * RAY(), "cure has not been updated as expected");
    assert(!vatLive => cureAfter == cureBefore, "cure has not stayed the same as expected");
    assert(vatLive => vatDaiJoinAfter == vatDaiJoinBefore + (batchedDaiToFlush - amtToPayBack) * RAY(), "join vat dai has not increased as expected 1");
    assert(!vatLive => vatDaiJoinAfter == vatDaiJoinBefore + batchedDaiToFlush * RAY(), "join vat dai has not increased as expected 2");
}

rule settle_revert(bytes32 sourceDomain, uint256 batchedDaiToFlush) {
    env e;

    require(currentContract != vow());
    require(daiJoin != vow());

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

    uint256 amtToPayBack = debt < 0
                            ? 0
                            : to_mathint(batchedDaiToFlush) <= to_mathint(debt)
                                ? batchedDaiToFlush
                                : to_uint256(debt);

    uint256 vatDaiVow = vat.dai(vow());
    uint256 vatSinVow = vat.sin(vow());

    settle@withrevert(e, sourceDomain, batchedDaiToFlush);

    bool revert1  = e.msg.value > 0;
    bool revert2  = batchedDaiToFlush > max_int256();
    bool revert3  = batchedDaiToFlush * RAY() > max_uint256;
    bool revert4  = batchedDaiToFlush * RAY() > vatDaiDaiJoin;
    bool revert5  = vatDaiJoin + batchedDaiToFlush * RAY() > max_uint256;
    bool revert6  = daiBalJoin < batchedDaiToFlush;
    bool revert7  = daiAllJoinDaiJoin < batchedDaiToFlush;
    bool revert8  = vatLive && art < ink && (ink - art) * RAY() > max_int256();
    bool revert9  = vatLive && art < ink && vatSinVow + (ink - art) * RAY() > max_uint256;
    bool revert10 = vatLive && art < ink && vatDaiVow + (ink - art) * RAY() > max_uint256;
    bool revert11 = vatLive && amtToPayBack > 0 && -1 * to_mathint(amtToPayBack) * RAY() < min_int256();
    bool revert12 = vatLive && amtToPayBack > ink;
    bool revert13 = vatLive && vatGemJoin + amtToPayBack > max_uint256;
    bool revert14 = to_mathint(debt) - to_mathint(batchedDaiToFlush) < min_int256();

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

    assert(lastReverted => revert1  || revert2  || revert3  ||
                           revert4  || revert5  || revert6  ||
                           revert7  || revert8  || revert9  ||
                           revert10 || revert11 || revert12 ||
                           revert13 || revert14, "Revert rules are not covering all the cases");
}
