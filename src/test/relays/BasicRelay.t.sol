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

pragma solidity 0.8.9;

import "ds-test/test.sol";

import "src/WormholeGUID.sol";
import "src/relays/BasicRelay.sol";

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

    struct WormholeStatus {
        bool    blessed;
        uint248 pending;
    }

    constructor(DaiMock _dai) {
        dai = _dai;
    }

    function requestMint(
        WormholeGUID calldata wormholeGUID,
        uint256
    ) external returns (uint256 postFeeAmount) {
        bytes32 hashGUID = getGUIDHash(wormholeGUID);
        wormholes[hashGUID].blessed = true;
        wormholes[hashGUID].pending = 0;

        // Take 1%
        uint256 fee = wormholeGUID.amount * 1 / 100;
        uint256 remainder = wormholeGUID.amount - fee;

        // Mint the DAI and send it to receiver
        dai.mint(bytes32ToAddress(wormholeGUID.receiver), remainder);

        return remainder;
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
        uint256 maxFeePercentage
    ) external returns (uint256 postFeeAmount) {
        return join.requestMint(wormholeGUID, maxFeePercentage);
    }

    function wormholeJoin() external view returns (address) {
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
    WormholeJoinMock internal join;
    WormholeOracleAuthMock internal oracleAuth;

    function setUp() public {
        vat = new VatMock();
        dai = new DaiMock();
        daiJoin = new DaiJoinMock(address(vat), address(dai));
        join = new WormholeJoinMock(dai);
        oracleAuth = new WormholeOracleAuthMock(join);
        relay = new BasicRelay(address(oracleAuth), address(daiJoin));
    }

    function test_constructor_args() public {
        assertEq(address(relay.daiJoin()), address(daiJoin));
        assertEq(address(relay.dai()), address(dai));
        assertEq(address(relay.oracleAuth()), address(oracleAuth));
        assertEq(address(relay.wormholeJoin()), address(join));
    }

    function test_relay() public {
        uint256 sk = uint(keccak256(abi.encode(8)));
        address signer = hevm.addr(sk);
        address receiver = address(123);
        WormholeGUID memory guid = WormholeGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(relay)),
            operator: addressToBytes32(signer),
            amount: 100 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });
        bytes32 hashGUID = getGUIDHash(guid);
        uint256 maxFeePercentage = WAD * 1 / 100;   // 1%
        uint256 gasFee = WAD;                       // 1 DAI of gas
        uint256 expiry = block.timestamp;
        bytes32 signHash = keccak256(abi.encode(
            hashGUID,
            receiver,
            maxFeePercentage,
            gasFee,
            expiry
        ));

        (uint8 v, bytes32 r, bytes32 s) = hevm.sign(sk, signHash);

        assertEq(dai.balanceOf(receiver), 0);
        assertEq(dai.balanceOf(address(this)), 0);
        relay.relay(
            guid,
            "",     // Not testing OracleAuth signatures here
            receiver,
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
}
