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

pragma solidity 0.8.13;

import "ds-test/test.sol";

import "src/WormholeGUID.sol";
import "src/relays/TrustedRelay.sol";

import "../mocks/VatMock.sol";
import "../mocks/DaiMock.sol";
import "../mocks/DaiJoinMock.sol";

interface Hevm {
    function warp(uint) external;
    function addr(uint) external returns (address);
    function sign(uint, bytes32) external returns (uint8, bytes32, bytes32);
}

contract WormholeJoinMock {

    mapping (bytes32 => WormholeStatus) public wormholes;

    DaiMock public dai;
    uint256 public maxMint;

    struct WormholeStatus {
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
        WormholeGUID calldata wormholeGUID,
        uint256,
        uint256 operatorFee
    ) external returns (uint256 postFeeAmount, uint256 totalFee) {
        bytes32 hashGUID = getGUIDHash(wormholeGUID);

        // Take 1%
        uint256 amount = wormholeGUID.amount;
        if (amount > maxMint) amount = maxMint;
        uint256 fee = amount * 1 / 100;
        uint256 remainder = amount - fee;

        wormholes[hashGUID].blessed = true;
        wormholes[hashGUID].pending = uint248(wormholeGUID.amount - amount);

        // Mint the DAI and send it to /operator
        dai.mint(bytes32ToAddress(wormholeGUID.receiver), remainder - operatorFee);
        dai.mint(bytes32ToAddress(wormholeGUID.operator), operatorFee);

        return (remainder - operatorFee, fee + operatorFee);
    }
}

contract WormholeOracleAuthMock {

    WormholeJoinMock public join;

    constructor(WormholeJoinMock _join) {
        join = _join;
    }

    function requestMint(
        WormholeGUID calldata wormholeGUID,
        bytes calldata,
        uint256 maxFeePercentage,
        uint256 operatorFee
    ) external returns (uint256 postFeeAmount, uint256 totalFee) {
        return join.requestMint(wormholeGUID, maxFeePercentage, operatorFee);
    }

    function wormholeJoin() external view returns (address) {
        return address(join);
    }
}

contract TrustedRelayTest is DSTest {

    uint256 internal constant WAD = 10**18;

    Hevm internal hevm = Hevm(HEVM_ADDRESS);

    TrustedRelay internal relay;
    VatMock internal vat;
    DaiMock internal dai;
    DaiJoinMock internal daiJoin;
    WormholeJoinMock internal join;
    WormholeOracleAuthMock internal oracleAuth;

    function getSignHash(
        WormholeGUID memory wormholeGUID,
        uint256 maxFeePercentage,
        uint256 gasFee,
        uint256 expiry
    ) internal pure returns (bytes32 signHash) {
        signHash = keccak256(abi.encodePacked(
            "\x19Ethereum Signed Message:\n32", 
            keccak256(abi.encode(getGUIDHash(wormholeGUID), maxFeePercentage, gasFee, expiry))
        ));
    }

    function setUp() public {
        vat = new VatMock();
        dai = new DaiMock();
        daiJoin = new DaiJoinMock(address(vat), address(dai));
        join = new WormholeJoinMock(dai);
        oracleAuth = new WormholeOracleAuthMock(join);
        relay = new TrustedRelay(address(oracleAuth), address(daiJoin));
        join.setMaxMint(100 ether);
    }

    function test_constructor_args() public {
        assertEq(address(relay.daiJoin()), address(daiJoin));
        assertEq(address(relay.dai()), address(dai));
        assertEq(address(relay.oracleAuth()), address(oracleAuth));
        assertEq(address(relay.wormholeJoin()), address(join));
    }

    function testAddRemoveSigners() public {
        address[] memory signers = new address[](3);
        for(uint i; i < signers.length; i++) {
            signers[i] = address(uint160(i));
            assertEq(relay.signers(address(uint160(i))), 0);
        }

        relay.addSigners(signers);

        for(uint i; i < signers.length; i++) {
            assertEq(relay.signers(address(uint160(i))), 1);
        }

        relay.removeSigners(signers);

        for(uint i; i < signers.length; i++) {
            assertEq(relay.signers(address(uint160(i))), 0);
        }
    }

    function test_relay() public {
        uint256 sk = uint(keccak256(abi.encode(8)));
        address[] memory signers = new address[](1);
        signers[0] = hevm.addr(sk);
        relay.addSigners(signers);
        address receiver = address(123);
        WormholeGUID memory guid = WormholeGUID({
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
        // Should get 100 DAI - 1% wormhole fee - 1 DAI gas fee
        assertEq(dai.balanceOf(receiver), 98 ether);
        assertEq(dai.balanceOf(address(this)), 1 ether);
    }

    function testFail_relay_expired() public {
        uint256 sk = uint(keccak256(abi.encode(8)));
        address[] memory signers = new address[](1);
        signers[0] = hevm.addr(sk);
        relay.addSigners(signers);
        address receiver = address(123);
        WormholeGUID memory guid = WormholeGUID({
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
        uint256 sk = uint(keccak256(abi.encode(8)));
        address[] memory signers = new address[](1);
        signers[0] = hevm.addr(sk);
        relay.addSigners(signers);
        address receiver = address(123);
        WormholeGUID memory guid = WormholeGUID({
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

    function testFail_relay_bad_signer() public {
        address receiver = address(123);
        WormholeGUID memory guid = WormholeGUID({
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

        uint256 sk = uint(keccak256(abi.encode(888)));
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

        uint256 sk = uint(keccak256(abi.encode(8)));
        address[] memory signers = new address[](1);
        signers[0] = hevm.addr(sk);
        relay.addSigners(signers);
        address receiver = address(123);
        WormholeGUID memory guid = WormholeGUID({
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
