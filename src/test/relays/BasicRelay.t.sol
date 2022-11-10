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

import "src/TeleportGUID.sol";
import "src/relays/BasicRelay.sol";

import "../mocks/VatMock.sol";
import "../mocks/DaiMock.sol";
import "../mocks/DaiJoinMock.sol";

interface Hevm {
    function warp(uint) external;
    function addr(uint) external returns (address);
    function sign(uint, bytes32) external returns (uint8, bytes32, bytes32);
}

contract TeleportJoinMock {

    mapping (bytes32 => TeleportStatus) public teleports;

    DaiMock public dai;
    uint256 public maxMint;

    struct TeleportStatus {
        bool    blessed;
        uint248 pending;
    }

    constructor(DaiMock _dai) {
        dai = _dai;
    }

    function setMaxMint(uint256 amt) external {
        maxMint = amt;
    }

    function requestMint(
        TeleportGUID calldata teleportGUID,
        uint256,
        uint256 operatorFee
    ) external returns (uint256 postFeeAmount, uint256 totalFee) {
        bytes32 hashGUID = getGUIDHash(teleportGUID);

        // Take 1%
        uint256 amount = teleportGUID.amount;
        if (amount > maxMint) amount = maxMint;
        uint256 fee = amount * 1 / 100;
        uint256 remainder = amount - fee;

        teleports[hashGUID].blessed = true;
        teleports[hashGUID].pending = uint248(teleportGUID.amount - amount);

        // Mint the DAI and send it to receiver/operator
        dai.mint(bytes32ToAddress(teleportGUID.receiver), remainder - operatorFee);
        dai.mint(bytes32ToAddress(teleportGUID.operator), operatorFee);

        return (remainder - operatorFee, fee + operatorFee);
    }
}

contract TeleportOracleAuthMock {

    TeleportJoinMock public join;

    constructor(TeleportJoinMock _join) {
        join = _join;
    }

    function requestMint(
        TeleportGUID calldata teleportGUID,
        bytes calldata,
        uint256 maxFeePercentage,
        uint256 operatorFee
    ) external returns (uint256 postFeeAmount, uint256 totalFee) {
        return join.requestMint(teleportGUID, maxFeePercentage, operatorFee);
    }

    function teleportJoin() external view returns (address) {
        return address(join);
    }
}

contract BasicRelayTest is DSTest {

    uint256 internal constant WAD = 10**18;

    Hevm internal hevm = Hevm(HEVM_ADDRESS);

    BasicRelay internal relay;
    VatMock internal vat;
    DaiMock internal dai;
    DaiJoinMock internal daiJoin;
    TeleportJoinMock internal join;
    TeleportOracleAuthMock internal oracleAuth;

    function getSignHash(
        TeleportGUID memory teleportGUID,
        uint256 maxFeePercentage,
        uint256 gasFee,
        uint256 expiry
    ) internal pure returns (bytes32 signHash) {
        signHash = keccak256(abi.encodePacked(
            "\x19Ethereum Signed Message:\n32", 
            keccak256(abi.encode(getGUIDHash(teleportGUID), maxFeePercentage, gasFee, expiry))
        ));
    }

    function setUp() public {
        vat = new VatMock();
        dai = new DaiMock();
        daiJoin = new DaiJoinMock(address(vat), address(dai));
        join = new TeleportJoinMock(dai);
        oracleAuth = new TeleportOracleAuthMock(join);
        relay = new BasicRelay(address(oracleAuth), address(daiJoin));
        join.setMaxMint(100 ether);
    }

    function _tryRely(address usr) internal returns (bool ok) {
        (ok,) = address(relay).call(abi.encodeWithSignature("rely(address)", usr));
    }

    function _tryDeny(address usr) internal returns (bool ok) {
        (ok,) = address(relay).call(abi.encodeWithSignature("deny(address)", usr));
    }

    function _whitelistThis() internal {
        address[] memory relayers = new address[](1);
        relayers[0] = address(this);
        relay.addRelayers(relayers);
    }

    function test_constructor_args() public {
        assertEq(relay.wards(address(this)), 1);
        assertEq(address(relay.daiJoin()), address(daiJoin));
        assertEq(address(relay.dai()), address(dai));
        assertEq(address(relay.oracleAuth()), address(oracleAuth));
        assertEq(address(relay.teleportJoin()), address(join));
    }

    function testRelyDeny() public {
        assertEq(relay.wards(address(456)), 0);
        assertTrue(_tryRely(address(456)));
        assertEq(relay.wards(address(456)), 1);
        assertTrue(_tryDeny(address(456)));
        assertEq(relay.wards(address(456)), 0);

        relay.deny(address(this));

        assertTrue(!_tryRely(address(456)));
        assertTrue(!_tryDeny(address(456)));
    }

    function testAddRemoveRelayers() public {
        address[] memory relayers = new address[](3);
        for(uint i; i < relayers.length; i++) {
            relayers[i] = address(uint160(i));
            assertEq(relay.relayers(address(uint160(i))), 0);
        }

        relay.addRelayers(relayers);

        for(uint i; i < relayers.length; i++) {
            assertEq(relay.relayers(address(uint160(i))), 1);
        }

        relay.removeRelayers(relayers);

        for(uint i; i < relayers.length; i++) {
            assertEq(relay.relayers(address(uint160(i))), 0);
        }
    }

    function test_relay() public {
        _whitelistThis();
        uint256 sk = uint(keccak256(abi.encode(8)));
        address receiver = hevm.addr(sk);
        TeleportGUID memory guid = TeleportGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(receiver),
            operator: addressToBytes32(address(relay)),
            amount: 100 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });
        uint256 maxFeePercentage = WAD * 1 / 100;   // 1%
        uint256 gasFee = WAD;                       // 1 DAI of gas
        uint256 expiry = block.timestamp;
        bytes32 signHash = getSignHash(
            guid,
            maxFeePercentage,
            gasFee,
            expiry
        );

        (uint8 v, bytes32 r, bytes32 s) = hevm.sign(sk, signHash);

        assertEq(dai.balanceOf(receiver), 0);
        assertEq(dai.balanceOf(address(this)), 0);

        bytes memory relayData = abi.encodeWithSelector(relay.relay.selector, 
            guid,
            "",     // Not testing OracleAuth signatures here
            maxFeePercentage,
            gasFee,
            expiry,
            v,
            r,
            s
        );
        address feeCollector = address(0xf33C0113c702);
        (bool success,) = address(relay).call(abi.encodePacked(relayData, feeCollector));
        assertTrue(success);

        // Should get 100 DAI - 1% teleport fee - 1 DAI gas fee
        assertEq(dai.balanceOf(receiver), 98 ether);
        assertEq(dai.balanceOf(feeCollector), 1 ether);
    }

    function testFail_relay_expired() public {
        _whitelistThis();
        uint256 sk = uint(keccak256(abi.encode(8)));
        address receiver = hevm.addr(sk);
        TeleportGUID memory guid = TeleportGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(receiver),
            operator: addressToBytes32(address(relay)),
            amount: 100 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });
        uint256 maxFeePercentage = WAD * 1 / 100;   // 1%
        uint256 gasFee = WAD;                       // 1 DAI of gas
        uint256 expiry = block.timestamp;
        bytes32 signHash = getSignHash(
            guid,
            maxFeePercentage,
            gasFee,
            expiry
        );

        (uint8 v, bytes32 r, bytes32 s) = hevm.sign(sk, signHash);

        hevm.warp(block.timestamp + 1);

        relay.relay(
            guid,
            "",     // Not testing OracleAuth signatures here
            maxFeePercentage,
            gasFee,
            expiry,
            v,
            r,
            s
        );
    }

    function testFail_relay_bad_signature() public {
        _whitelistThis();
        uint256 sk = uint(keccak256(abi.encode(8)));
        address receiver = hevm.addr(sk);
        TeleportGUID memory guid = TeleportGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(receiver),
            operator: addressToBytes32(address(relay)),
            amount: 100 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });
        uint256 maxFeePercentage = WAD * 1 / 100;   // 1%
        uint256 gasFee = WAD;                       // 1 DAI of gas
        uint256 expiry = block.timestamp;
        bytes32 signHash = getSignHash(
            guid,
            maxFeePercentage + 1,
            gasFee,
            expiry
        );

        (uint8 v, bytes32 r, bytes32 s) = hevm.sign(sk, signHash);

        relay.relay(
            guid,
            "",     // Not testing OracleAuth signatures here
            maxFeePercentage,
            gasFee,
            expiry,
            v,
            r,
            s
        );
    }

    function testFail_relay_partial_mint() public {
        join.setMaxMint(50 ether);

        _whitelistThis();
        uint256 sk = uint256(keccak256(abi.encode(8)));
        address receiver = hevm.addr(sk);
        TeleportGUID memory guid = TeleportGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(receiver),
            operator: addressToBytes32(address(relay)),
            amount: 100 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });
        uint256 maxFeePercentage = WAD * 1 / 100;   // 1%
        uint256 gasFee = WAD;                       // 1 DAI of gas
        uint256 expiry = block.timestamp;
        bytes32 signHash = getSignHash(
            guid,
            maxFeePercentage,
            gasFee,
            expiry
        );

        (uint8 v, bytes32 r, bytes32 s) = hevm.sign(sk, signHash);

        relay.relay(
            guid,
            "",     // Not testing OracleAuth signatures here
            maxFeePercentage,
            gasFee,
            expiry,
            v,
            r,
            s
        );
    }

    function testFail_relayer_not_whitelisted() public {
        uint256 sk = uint(keccak256(abi.encode(8)));
        address receiver = hevm.addr(sk);
        TeleportGUID memory guid = TeleportGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(receiver),
            operator: addressToBytes32(address(relay)),
            amount: 100 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });
        uint256 maxFeePercentage = WAD * 1 / 100;   // 1%
        uint256 gasFee = WAD;                       // 1 DAI of gas
        uint256 expiry = block.timestamp;
        bytes32 signHash = getSignHash(
            guid,
            maxFeePercentage,
            gasFee,
            expiry
        );

        (uint8 v, bytes32 r, bytes32 s) = hevm.sign(sk, signHash);

        relay.relay(
            guid,
            "",     // Not testing OracleAuth signatures here
            maxFeePercentage,
            gasFee,
            expiry,
            v,
            r,
            s
        );
    }
}
