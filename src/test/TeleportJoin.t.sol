// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2021 Dai Foundation
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity 0.8.15;

import "ds-test/test.sol";

import "src/TeleportJoin.sol";
import "src/TeleportConstantFee.sol";

import "./mocks/VatMock.sol";
import "./mocks/DaiMock.sol";
import "./mocks/DaiJoinMock.sol";

interface Hevm {
    function warp(uint) external;
    function addr(uint) external returns (address);
    function sign(uint, bytes32) external returns (uint8, bytes32, bytes32);
    function store(address, bytes32, bytes32) external;
}

contract TeleportJoinTest is DSTest {

    Hevm internal hevm = Hevm(HEVM_ADDRESS);
    bytes32 constant internal ilk = "L2DAI";
    bytes32 constant internal domain = "ethereum";
    TeleportJoin internal join;
    VatMock internal vat;
    DaiMock internal dai;
    DaiJoinMock internal daiJoin;
    address internal vow = address(111);

    uint256 internal constant WAD = 10**18;
    uint256 internal constant RAD = 10**45;
    uint256 internal constant TTL = 8 days;

    function setUp() public {
        vat = new VatMock();
        dai = new DaiMock();
        daiJoin = new DaiJoinMock(address(vat), address(dai));
        join = new TeleportJoin(address(vat), address(daiJoin), ilk, domain);
        join.file("line", "l2network", 1_000_000 ether);
        join.file("vow", vow);
        join.file("fees", "l2network", address(new TeleportConstantFee(0, TTL)));
        vat.hope(address(daiJoin));
    }

    function _ink() internal view returns (uint256 ink_) {
        (ink_,) = vat.urns(join.ilk(), address(join));
    }

    function _art() internal view returns (uint256 art_) {
        (, art_) = vat.urns(join.ilk(), address(join));
    }

    function _blessed(TeleportGUID memory guid) internal view returns (bool blessed_) {
        (blessed_, ) = join.teleports(getGUIDHash(guid));
    }

    function _pending(TeleportGUID memory guid) internal view returns (uint248 pending_) {
        (, pending_) = join.teleports(getGUIDHash(guid));
    }

    function _tryRely(address usr) internal returns (bool ok) {
        (ok,) = address(join).call(abi.encodeWithSignature("rely(address)", usr));
    }

    function _tryDeny(address usr) internal returns (bool ok) {
        (ok,) = address(join).call(abi.encodeWithSignature("deny(address)", usr));
    }

    function _tryFile(bytes32 what, address data) internal returns (bool ok) {
        (ok,) = address(join).call(abi.encodeWithSignature("file(bytes32,address)", what, data));
    }

    function _tryFile(bytes32 what, bytes32 domain_, address data) internal returns (bool ok) {
        (ok,) = address(join).call(abi.encodeWithSignature("file(bytes32,bytes32,address)", what, domain_, data));
    }

    function _tryFile(bytes32 what, bytes32 domain_, uint256 data) internal returns (bool ok) {
        (ok,) = address(join).call(abi.encodeWithSignature("file(bytes32,bytes32,uint256)", what, domain_, data));
    }

    function _tryRequestMint(
        TeleportGUID memory teleportGUID,
        uint256 maxFeePercentage,
        uint256 operatorFee
    ) internal returns (bool ok) {
        (ok,) = address(join).call(abi.encodeWithSignature(
            "requestMint((bytes32,bytes32,bytes32,bytes32,uint128,uint80,uint48),uint256,uint256)",
            teleportGUID,
            maxFeePercentage,
            operatorFee
        ));
    }

    function _tryMintPending(
        TeleportGUID memory teleportGUID,
        uint256 maxFeePercentage,
        uint256 operatorFee
    ) internal returns (bool ok) {
        (ok,) = address(join).call(abi.encodeWithSignature(
            "mintPending((bytes32,bytes32,bytes32,bytes32,uint128,uint80,uint48),uint256,uint256)",
            teleportGUID,
            maxFeePercentage,
            operatorFee
        ));
    }

    function testConstructor() public {
        assertEq(address(join.vat()), address(vat));
        assertEq(address(join.daiJoin()), address(daiJoin));
        assertEq(join.ilk(), ilk);
        assertEq(join.domain(), domain);
        assertEq(join.wards(address(this)), 1);
    }

    function testRelyDeny() public {
        assertEq(join.wards(address(456)), 0);
        assertTrue(_tryRely(address(456)));
        assertEq(join.wards(address(456)), 1);
        assertTrue(_tryDeny(address(456)));
        assertEq(join.wards(address(456)), 0);

        join.deny(address(this));

        assertTrue(!_tryRely(address(456)));
        assertTrue(!_tryDeny(address(456)));
    }

    function testFile() public {
        assertEq(join.vow(), vow);
        assertTrue(_tryFile("vow", address(888)));
        assertEq(join.vow(), address(888));

        assertEq(join.fees("aaa"), address(0));
        assertTrue(_tryFile("fees", "aaa", address(888)));
        assertEq(join.fees("aaa"), address(888));

        assertEq(join.line("aaa"), 0);
        uint256 maxInt256 = uint256(type(int256).max);
        assertTrue(_tryFile("line", "aaa", maxInt256));
        assertEq(join.line("aaa"), maxInt256);

        assertTrue(!_tryFile("line", "aaa", maxInt256 + 1));

        join.deny(address(this));

        assertTrue(!_tryFile("vow", address(888)));
        assertTrue(!_tryFile("fees", "aaa", address(888)));
        assertTrue(!_tryFile("line", "aaa", 10));
    }

    function testInvalidWhat() public {
       assertTrue(!_tryFile("meh", address(888)));
       assertTrue(!_tryFile("meh", domain, address(888)));
       assertTrue(!_tryFile("meh", domain, 888));
    }

    function testRegisterAndWithdrawAll() public {
        TeleportGUID memory guid = TeleportGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(this)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });

        assertEq(dai.balanceOf(address(123)), 0);
        assertTrue(!_blessed(guid));
        assertEq(_pending(guid), 0);
        assertEq(_ink(), 0);
        assertEq(_art(), 0);

        (uint256 daiSent, uint256 totalFee) = join.requestMint(guid, 0, 0);

        assertEq(dai.balanceOf(address(123)), 250_000 ether);
        assertTrue(_blessed(guid));
        assertEq(_pending(guid), 0);
        assertEq(_ink(), 250_000 ether);
        assertEq(_art(), 250_000 ether);
        assertEq(join.cure(), 250_000 * RAD);
        assertEq(daiSent, 250_000 * WAD);
        assertEq(totalFee, 0);
    }

    function testRegisterAndWithdrawPartial() public {
        TeleportGUID memory guid = TeleportGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(this)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });

        join.file("line", "l2network", 200_000 ether);
        (uint256 daiSent, uint256 totalFee) = join.requestMint(guid, 0, 0);

        assertEq(dai.balanceOf(address(123)), 200_000 ether);
        assertTrue(_blessed(guid));
        assertEq(_pending(guid), 50_000 ether);
        assertEq(_ink(), 200_000 ether);
        assertEq(_art(), 200_000 ether);
        assertEq(join.cure(), 200_000 * RAD);
        assertEq(daiSent, 200_000 * WAD);
        assertEq(totalFee, 0);
    }

    function testRegisterAndWithdrawNothing() public {
        TeleportGUID memory guid = TeleportGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(this)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });

        join.file("line", "l2network", 0);
        (uint256 daiSent, uint256 totalFee) = join.requestMint(guid, 0, 0);

        assertEq(dai.balanceOf(address(123)), 0);
        assertTrue(_blessed(guid));
        assertEq(_pending(guid), 250_000 ether);
        assertEq(_ink(), 0);
        assertEq(_art(), 0);
        assertEq(join.cure(), 0);
        assertEq(daiSent, 0);
        assertEq(totalFee, 0);
    }


    function testRegisterAlreadyRegistered() public {
        TeleportGUID memory guid = TeleportGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(this)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });
        assertTrue(_tryRequestMint(guid, 0, 0));
        assertTrue(!_tryRequestMint(guid, 0, 0));
    }

    function testRegisterWrongDomain() public {
        TeleportGUID memory guid = TeleportGUID({
            sourceDomain: "l2network",
            targetDomain: "etherium",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(this)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });
        assertTrue(!_tryRequestMint(guid, 0, 0));
    }

    function testRegisterAndWithdrawPayingFee() public {
        TeleportGUID memory guid = TeleportGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(this)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });
        assertEq(vat.dai(vow), 0);
        TeleportConstantFee fees = new TeleportConstantFee(100 ether, TTL);
        assertEq(fees.fee(), 100 ether);

        join.file("fees", "l2network", address(fees));
        (uint256 daiSent, uint256 totalFee) = join.requestMint(guid, 4 * WAD / 10000, 0); // 0.04% * 250K = 100 (just enough)

        assertEq(vat.dai(vow), 100 * RAD);
        assertEq(dai.balanceOf(address(123)), 249_900 ether);
        assertEq(_pending(guid), 0);
        assertEq(_ink(), 250_000 ether);
        assertEq(_art(), 250_000 ether);
        assertEq(join.cure(), 250_000 * RAD);
        assertEq(daiSent, 249_900 * WAD);
        assertEq(totalFee, 100 ether);
    }

    function testRegisterAndWithdrawPayingInsufficientFee() public {
        TeleportGUID memory guid = TeleportGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(this)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });

        join.file("fees", "l2network", address(new TeleportConstantFee(100 ether, TTL)));
        assertTrue(!_tryRequestMint(guid, 3 * WAD / 10000, 0)); // 0.03% * 250K < 100 (not enough)
    }

    function testRegisterAndWithdrawFeeTTLExpires() public {
        TeleportGUID memory guid = TeleportGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(this)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });
        assertEq(vat.dai(vow), 0);
        TeleportConstantFee fees = new TeleportConstantFee(100 ether, TTL);
        assertEq(fees.fee(), 100 ether);

        join.file("fees", "l2network", address(fees));
        hevm.warp(block.timestamp + TTL + 1 days);    // Over ttl - you don't pay fees
        assertTrue(_tryRequestMint(guid, 0, 0));

        assertEq(vat.dai(vow), 0);
        assertEq(dai.balanceOf(address(123)), 250_000 ether);
        assertEq(_pending(guid), 0);
        assertEq(_ink(), 250_000 ether);
        assertEq(_art(), 250_000 ether);
        assertEq(join.cure(), 250_000 * RAD);
    }

    function testRegisterAndWithdrawPartialPayingFee() public {
        TeleportGUID memory guid = TeleportGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(this)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });

        assertEq(vat.dai(vow), 0);

        join.file("line", "l2network", 200_000 ether);
        join.file("fees", "l2network", address(new TeleportConstantFee(100 ether, TTL)));
        assertTrue(_tryRequestMint(guid, 4 * WAD / 10000, 0)); // 0.04% * 200K = 80 (just enough as fee is also proportional)

        assertEq(vat.dai(vow), 80 * RAD);
        assertEq(dai.balanceOf(address(123)), 199_920 ether);
        assertTrue(_blessed(guid));
        assertEq(_pending(guid), 50_000 ether);
        assertEq(_ink(), 200_000 ether);
        assertEq(_art(), 200_000 ether);
        assertEq(join.cure(), 200_000 * RAD);

        join.file("line", "l2network", 250_000 ether);

        assertTrue(_tryMintPending(guid, 4 * WAD / 10000, 0)); // 0.04% * 50 = 20 (just enough as fee is also proportional)

        assertEq(vat.dai(vow), 100 * RAD);
        assertEq(dai.balanceOf(address(123)), 249_900 ether);
        assertEq(_pending(guid), 0);
        assertEq(_ink(), 250_000 ether);
        assertEq(_art(), 250_000 ether);
        assertEq(join.cure(), 250_000 * RAD);
    }

    function testRegisterAndWithdrawPartialPayingInsufficientFee() public {
        TeleportGUID memory guid = TeleportGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(this)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });

        assertEq(vat.dai(vow), 0);

        join.file("line", "l2network", 200_000 ether);
        join.file("fees", "l2network", address(new TeleportConstantFee(100 ether, TTL)));
        assertTrue(!_tryRequestMint(guid, 3 * WAD / 10000, 0)); // 0.03% * 200K < 80 (not enough)
    }

    function testRegisterAndWithdrawPartialPayingFee2() public {
        TeleportGUID memory guid = TeleportGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(this)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });

        assertEq(vat.dai(vow), 0);

        join.file("line", "l2network", 200_000 ether);
        join.file("fees", "l2network", address(new TeleportConstantFee(100 ether, TTL)));
        assertTrue(_tryRequestMint(guid, 4 * WAD / 10000, 0));

        join.file("line", "l2network", 250_000 ether);

        assertTrue(!_tryMintPending(guid, 3 * WAD / 10000, 0)); // 0.03% * 50 < 20 (not enough)
    }

    function testMintPendingByOperator() public {
        TeleportGUID memory guid = TeleportGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(this)),
            operator: addressToBytes32(address(this)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });

        join.file("line", "l2network", 200_000 ether);
        assertTrue(_tryRequestMint(guid, 0, 0));

        assertEq(dai.balanceOf(address(this)), 200_000 ether);
        assertTrue(_blessed(guid));
        assertEq(_pending(guid), 50_000 ether);

        join.file("line", "l2network", 225_000 ether);
        assertTrue(_tryMintPending(guid, 0, 0));

        assertEq(dai.balanceOf(address(this)), 225_000 ether);
        assertEq(_pending(guid), 25_000 ether);
    }

    function testMintPendingByOperatorNotReceiver() public {
        TeleportGUID memory guid = TeleportGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(this)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });

        join.file("line", "l2network", 200_000 ether);
        assertTrue(_tryRequestMint(guid, 0, 0));

        assertEq(dai.balanceOf(address(123)), 200_000 ether);
        assertTrue(_blessed(guid));
        assertEq(_pending(guid), 50_000 ether);

        join.file("line", "l2network", 225_000 ether);
        assertTrue(_tryMintPending(guid, 0, 0));

        assertEq(dai.balanceOf(address(123)), 225_000 ether);
        assertEq(_pending(guid), 25_000 ether);
    }

    function testMintPendingByReceiver() public {
        TeleportGUID memory guid = TeleportGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(this)),
            operator: addressToBytes32(address(0x123)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });

        join.file("line", "l2network", 200_000 ether);
        assertTrue(_tryRequestMint(guid, 0, 0));

        assertEq(dai.balanceOf(address(this)), 200_000 ether);
        assertTrue(_blessed(guid));
        assertEq(_pending(guid), 50_000 ether);

        join.file("line", "l2network", 225_000 ether);
        assertTrue(_tryMintPending(guid, 0, 0));

        assertEq(dai.balanceOf(address(this)), 225_000 ether);
        assertEq(_pending(guid), 25_000 ether);
    }

    function testMintPendingWrongOperator() public {
        TeleportGUID memory guid = TeleportGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(654)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });

        join.file("line", "l2network", 200_000 ether);
        assertTrue(_tryRequestMint(guid, 0, 0));

        join.file("line", "l2network", 225_000 ether);
        assertTrue(!_tryMintPending(guid, 0, 0));
    }

    function testSettle() public {
        assertEq(join.debt("l2network"), 0);

        vat.suck(address(0), address(this), 100_000 * RAD);
        daiJoin.exit(address(join), 100_000 ether);

        join.settle("l2network", 100_000 ether);

        assertEq(join.debt("l2network"), -100_000 ether);
        assertEq(join.cure(), 0);
    }

    function testWithdrawNegativeDebt() public {
        vat.suck(address(0), address(this), 100_000 * RAD);
        daiJoin.exit(address(join), 100_000 ether);

        join.settle("l2network", 100_000 ether);

        assertEq(join.debt("l2network"), -100_000 ether);
        assertEq(join.cure(), 0);

        TeleportGUID memory guid = TeleportGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(654)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });

        assertTrue(_tryRequestMint(guid, 0, 0));

        assertEq(dai.balanceOf(address(123)), 250_000 ether);
        assertEq(_ink(), 150_000 ether);
        assertEq(_art(), 150_000 ether);
        assertEq(join.cure(), 150_000 * RAD);
    }

    function testWithdrawPartialNegativeDebt() public {
        vat.suck(address(0), address(this), 100_000 * RAD);
        daiJoin.exit(address(join), 100_000 ether);

        join.settle("l2network", 100_000 ether);

        assertEq(join.debt("l2network"), -100_000 ether);
        assertEq(join.cure(), 0);

        TeleportGUID memory guid = TeleportGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(654)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });

        join.file("line", "l2network", 100_000 ether);
        assertTrue(_tryRequestMint(guid, 0, 0));

        assertEq(dai.balanceOf(address(123)), 200_000 ether);
        assertEq(_pending(guid), 50_000 ether);
        assertEq(_ink(), 100_000 ether);
        assertEq(_art(), 100_000 ether);
        assertEq(join.cure(), 100_000 * RAD);
    }

    function testWithdrawVatCaged() public {
        vat.suck(address(0), address(this), 100_000 * RAD);
        daiJoin.exit(address(join), 100_000 ether);

        join.settle("l2network", 100_000 ether);

        assertEq(join.debt("l2network"), -100_000 ether);
        assertEq(join.cure(), 0);

        TeleportGUID memory guid = TeleportGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(654)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });

        vat.cage();
        assertEq(vat.live(), 0);

        join.file("fees", "l2network", address(new TeleportConstantFee(100 ether, TTL)));
        assertTrue(_tryRequestMint(guid, 0, 0));

        assertEq(dai.balanceOf(address(123)), 100_000 ether); // Can't pay more than DAI is already in the join
        assertEq(_pending(guid), 150_000 ether);
        assertEq(_ink(), 0);
        assertEq(_art(), 0);
        assertEq(vat.dai(vow), 0); // No fees regardless the contract set
        assertEq(join.cure(), 0);
    }

    function testSettleVatCaged() public {
        TeleportGUID memory guid = TeleportGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(654)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });

        assertTrue(_tryRequestMint(guid, 0, 0));

        assertEq(join.debt("l2network"), 250_000 ether);
        assertEq(_ink(), 250_000 ether);
        assertEq(_art(), 250_000 ether);
        assertEq(join.cure(), 250_000 * RAD);

        vat.cage();

        vat.suck(address(0), address(this), 250_000 * RAD);
        daiJoin.exit(address(join), 250_000 ether);

        join.settle("l2network", 250_000 ether);

        assertEq(join.debt("l2network"), 0);
        assertEq(_ink(), 250_000 ether);
        assertEq(_art(), 250_000 ether);
        assertEq(join.cure(), 250_000 * RAD);
    }

    function testRegisterAndWithdrawPayingOperatorFee() public {
        TeleportGUID memory guid = TeleportGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(this)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });
        assertEq(dai.balanceOf(address(this)), 0);
        (uint256 daiSent, uint256 totalFee) = join.requestMint(guid, 0, 250 ether);

        assertEq(dai.balanceOf(address(this)), 250 ether);
        assertEq(dai.balanceOf(address(123)), 249_750 ether);
        assertEq(_pending(guid), 0);
        assertEq(_ink(), 250_000 ether);
        assertEq(_art(), 250_000 ether);
        assertEq(daiSent, 249_750 * WAD);
        assertEq(totalFee, 250 ether);
    }

    function testOperatorFeeTooHigh() public {
        TeleportGUID memory guid = TeleportGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(this)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });
        assertTrue(!_tryRequestMint(guid, 0, 250_001 ether));   // Slightly over the amount
    }

    function testRegisterAndWithdrawPartialPayingOperatorFee() public {
        TeleportGUID memory guid = TeleportGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(this)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });

        join.file("line", "l2network", 200_000 ether);
        assertTrue(_tryRequestMint(guid, 0, 200 ether));

        assertEq(dai.balanceOf(address(this)), 200 ether);
        assertEq(dai.balanceOf(address(123)), 199_800 ether);
        assertTrue(_blessed(guid));
        assertEq(_pending(guid), 50_000 ether);
        assertEq(_ink(), 200_000 ether);
        assertEq(_art(), 200_000 ether);

        join.file("line", "l2network", 250_000 ether);
        assertTrue(_tryMintPending(guid, 0, 5 ether));

        assertEq(dai.balanceOf(address(this)), 205 ether);
        assertEq(dai.balanceOf(address(123)), 249_795 ether);
        assertEq(_pending(guid), 0);
        assertEq(_ink(), 250_000 ether);
        assertEq(_art(), 250_000 ether);
    }

    function testRegisterAndWithdrawPayingTwoFees() public {
        TeleportGUID memory guid = TeleportGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(this)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });
        assertEq(dai.balanceOf(address(this)), 0);
        join.file("fees", "l2network", address(new TeleportConstantFee(1000 ether, TTL)));
        assertTrue(_tryRequestMint(guid, 40 ether / 10000, 249 ether));
        assertEq(dai.balanceOf(address(this)), 249 ether);
        assertEq(vat.dai(vow), 1000 * RAD);
        assertEq(dai.balanceOf(address(123)), 248_751 ether);
        assertEq(_pending(guid), 0);
        assertEq(_ink(), 250_000 ether);
        assertEq(_art(), 250_000 ether);
    }

    function testRegisterAndWithdrawOperatorFeeTooHigh() public {
        TeleportGUID memory guid = TeleportGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(this)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });
        join.file("fees", "l2network", address(new TeleportConstantFee(1000 ether, TTL)));
        assertTrue(!_tryRequestMint(guid, 40 ether / 10000, 249_001 ether));    // Too many fees
    }

    function testTotalDebtSeveralDomains() public {
        join.file("line", "l2network_2", 1_000_000 ether);
        join.file("fees", "l2network_2", address(new TeleportConstantFee(0, TTL)));
        join.file("line", "l2network_3", 1_000_000 ether);
        join.file("fees", "l2network_3", address(new TeleportConstantFee(0, TTL)));

        vat.suck(address(0), address(this), 100_000 * RAD);
        daiJoin.exit(address(join), 100_000 ether);
        join.settle("l2network", 100_000 ether);

        TeleportGUID memory guid = TeleportGUID({
            sourceDomain: "l2network_2",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(654)),
            amount: 150_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });
        assertTrue(_tryRequestMint(guid, 0, 0));

        guid = TeleportGUID({
            sourceDomain: "l2network_3",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(654)),
            amount: 50_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });
        assertTrue(_tryRequestMint(guid, 0, 0));

        assertEq(join.debt("l2network"), -100_000 ether);
        assertEq(join.debt("l2network_2"), 150_000 ether);
        assertEq(join.debt("l2network_3"), 50_000 ether);
        assertEq(join.cure(), 200_000 * RAD);

        guid = TeleportGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(654)),
            amount: 50_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });
        assertTrue(_tryRequestMint(guid, 0, 0));

        assertEq(join.debt("l2network"), -50_000 ether);
        assertEq(join.debt("l2network_2"), 150_000 ether);
        assertEq(join.debt("l2network_3"), 50_000 ether);
        assertEq(join.cure(), 200_000 * RAD);

        vat.suck(address(0), address(this), 10_000 * RAD);
        daiJoin.exit(address(join), 10_000 ether);
        join.settle("l2network_3", 10_000 ether);

        assertEq(join.debt("l2network"), -50_000 ether);
        assertEq(join.debt("l2network_2"), 150_000 ether);
        assertEq(join.debt("l2network_3"), 40_000 ether);
        assertEq(join.cure(), 190_000 * RAD);
    }

    function testCureAfterPositionBeingManipulated() public {
        TeleportGUID memory guid = TeleportGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(this)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });

        assertTrue(_tryRequestMint(guid, 0, 0));

        assertEq(_ink(), 250_000 ether);
        assertEq(_art(), 250_000 ether);
        assertEq(join.cure(), 250_000 * RAD);

        // Emulate removal of position debt (third party repayment or position being skimmed)
        hevm.store(
            address(vat),
            bytes32(uint256(keccak256(abi.encode(address(join), keccak256(abi.encode(bytes32(ilk), uint256(2)))))) + 1),
            bytes32(0)
        );
        assertEq(_art(), 0);
        assertEq(join.cure(), 250_000 * RAD);

        // In case of not caged, then debt can keep changing which will reload cure to the new value
        guid = TeleportGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(this)),
            amount: 100_000 ether,
            nonce: 6,
            timestamp: uint48(block.timestamp)
        });

        assertTrue(_tryRequestMint(guid, 0, 0));

        assertEq(_ink(), 350_000 ether);
        assertEq(_art(), 100_000 ether);
        assertEq(join.cure(), 100_000 * RAD);
    }

    function testSettleSurplusThenWithdraw() public {
        join.file("line", "l2network_2", 1_000_000 ether);
        join.file("fees", "l2network_2", address(new TeleportConstantFee(0, TTL)));
        assertEq(dai.balanceOf(address(123)), 0);

        TeleportGUID memory guid = TeleportGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(654)),
            amount: 100_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });
        join.requestMint(guid, 0, 0);

        assertEq(dai.balanceOf(address(123)), 100_000 ether);
        assertEq(join.debt("l2network"), 100_000 ether);
        assertEq(join.debt("l2network_2"), 0 ether);
        assertEq(_ink(), 100_000 ether);
        assertEq(_art(), 100_000 ether);
        assertEq(join.cure(), 100_000 * RAD);

        vat.suck(address(0), address(this), 100_000 * RAD);
        daiJoin.exit(address(join), 100_000 ether);
        join.settle("l2network_2", 100_000 ether); // settle DAI as negative debt

        assertEq(join.debt("l2network"), 100_000 ether);
        assertEq(join.debt("l2network_2"), -100_000 ether);
        assertEq(_ink(), 100_000 ether);
        assertEq(_art(), 100_000 ether);
        assertEq(join.cure(), 100_000 * RAD);

        guid = TeleportGUID({
            sourceDomain: "l2network_2",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(654)),
            amount: 100_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });
        join.requestMint(guid, 0, 0);

        assertEq(dai.balanceOf(address(123)), 200_000 ether);
        assertEq(join.debt("l2network"), 100_000 ether);
        assertEq(join.debt("l2network_2"), 0 ether);
        assertEq(_ink(), 100_000 ether);
        assertEq(_art(), 100_000 ether);
        assertEq(join.cure(), 100_000 * RAD);
    }

    function testSettleAfterPermissionlessRepay() public {
        TeleportGUID memory guid = TeleportGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(654)),
            amount: 100_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });
        join.requestMint(guid, 0, 0);

        assertEq(join.debt("l2network"), 100_000 ether);
        assertEq(_ink(), 100_000 ether);
        assertEq(_art(), 100_000 ether);
        assertEq(vat.dai(vow), 0);
        assertEq(vat.sin(vow), 0);

        // repay part of the ilk debt
        vat.suck(address(0), address(this), 20_000 * RAD);
        vat.frob(ilk, address(join), address(this), address(this), 0, -20_000 ether);
        assertEq(_ink(), 100_000 ether);
        assertEq(_art(), 80_000 ether);

        // settle the previous mint
        vat.suck(address(0), address(this), 100_000 * RAD);
        daiJoin.exit(address(join), 100_000 ether);
        join.settle("l2network", 100_000 ether);

        assertEq(join.debt("l2network"), 0);
        assertEq(_ink(), 0);
        assertEq(_art(), 0);
        assertEq(vat.dai(vow), 20_000 * RAD);
        assertEq(vat.sin(vow), 0);
    }
}
