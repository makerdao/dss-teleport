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

import "src/WormholeOracleAuth.sol";

interface Hevm {
    function addr(uint) external returns (address);
    function sign(uint, bytes32) external returns (uint8, bytes32, bytes32);
}

contract GatewayMock {
    function requestMint(WormholeGUID calldata, uint256, uint256) external returns (uint256 postFeeAmount) {
        return 0;
    }
    function settle(bytes32 sourceDomain, uint256 batchedDaiToFlush) external {}
}

contract WormholeOracleAuthTest is DSTest {

    Hevm hevm = Hevm(HEVM_ADDRESS);
    WormholeOracleAuth internal auth;
    address internal wormholeJoin;

    function setUp() public {
        wormholeJoin = address(new GatewayMock());
        auth = new WormholeOracleAuth(wormholeJoin);
    }

    function _tryRely(address usr) internal returns (bool ok) {
        (ok,) = address(auth).call(abi.encodeWithSignature("rely(address)", usr));
    }

    function _tryDeny(address usr) internal returns (bool ok) {
        (ok,) = address(auth).call(abi.encodeWithSignature("deny(address)", usr));
    }

    function _tryFile(bytes32 what, uint256 data) internal returns (bool ok) {
        (ok,) = address(auth).call(abi.encodeWithSignature("file(bytes32,uint256)", what, data));
    }

    function getSignatures(bytes32 signHash) internal returns (bytes memory signatures, address[] memory signers) {
        // seeds chosen s.t. corresponding addresses are in ascending order
        uint8[30] memory seeds = [8,10,6,2,9,15,14,20,7,29,24,13,12,25,16,26,21,22,0,18,17,27,3,28,23,19,4,5,1,11];
        uint numSigners = seeds.length;
        signers = new address[](numSigners);
        for(uint i; i < numSigners; i++) {
            uint sk = uint(keccak256(abi.encode(seeds[i])));
            signers[i] = hevm.addr(sk);
            (uint8 v, bytes32 r, bytes32 s) = hevm.sign(sk, signHash);
            signatures = abi.encodePacked(signatures, r, s, v);
        }
        assertEq(signatures.length, numSigners * 65);
    }

    function testConstructor() public {
        assertEq(address(auth.wormholeJoin()), wormholeJoin);
        assertEq(auth.wards(address(this)), 1);
    }

    function testRelyDeny() public {
        assertEq(auth.wards(address(456)), 0);
        assertTrue(_tryRely(address(456)));
        assertEq(auth.wards(address(456)), 1);
        assertTrue(_tryDeny(address(456)));
        assertEq(auth.wards(address(456)), 0);

        auth.deny(address(this));

        assertTrue(!_tryRely(address(456)));
        assertTrue(!_tryDeny(address(456)));
    }

    function testFileFailsWhenNotAuthed() public {
        assertTrue(_tryFile("threshold", 888));
        auth.deny(address(this));
        assertTrue(!_tryFile("threshold", 888));
    }

    function testFileNewThreshold() public {
        assertEq(auth.threshold(), 0);

        assertTrue(_tryFile("threshold", 3));

        assertEq(auth.threshold(), 3);
    }

    function testFailFileInvalidWhat() public {
        auth.file("meh", 888);
    }

    function testAddRemoveSigners() public {
        address[] memory signers = new address[](3);
        for(uint i; i < signers.length; i++) {
            signers[i] = address(uint160(i));
            assertEq(auth.signers(address(uint160(i))), 0);
        }

        auth.addSigners(signers);

        for(uint i; i < signers.length; i++) {
            assertEq(auth.signers(address(uint160(i))), 1);
        }

        auth.removeSigners(signers);

        for(uint i; i < signers.length; i++) {
            assertEq(auth.signers(address(uint160(i))), 0);
        }
    }

    function test_isValid() public {
        bytes32 signHash = keccak256("msg");
        (bytes memory signatures, address[] memory signers) = getSignatures(signHash);
        auth.addSigners(signers);
        assertTrue(auth.isValid(signHash, signatures, signers.length));
    }

    function testFail_isValid_notEnoughSig() public {
        bytes32 signHash = keccak256("msg");
        (bytes memory signatures, address[] memory signers) = getSignatures(signHash);
        auth.addSigners(signers);
        assertTrue(auth.isValid(signHash, signatures, signers.length + 1));
    }

    function testFail_isValid_badSig() public {
        bytes32 signHash = keccak256("msg");
        (bytes memory signatures, address[] memory signers) = getSignatures(signHash);
        auth.addSigners(signers);
        signatures[0] = bytes1(uint8((uint256(uint8(signatures[0])) + 1) % 256));
        assertTrue(auth.isValid(signHash, signatures, signers.length));
    }

    function test_mintByOperator() public {
        WormholeGUID memory guid;
        guid.operator = addressToBytes32(address(this));
        guid.sourceDomain = bytes32("l2network");
        guid.targetDomain = bytes32("ethereum");
        guid.receiver = addressToBytes32(address(this));
        guid.amount = 100;

        bytes32 signHash = auth.getSignHash(guid);
        (bytes memory signatures, address[] memory signers) = getSignatures(signHash);
        auth.addSigners(signers);

        uint maxFee = 0;

        auth.requestMint(guid, signatures, maxFee, 0);
    }

    function test_mintByOperatorNotReceiver() public {
        WormholeGUID memory guid;
        guid.operator = addressToBytes32(address(this));
        guid.sourceDomain = bytes32("l2network");
        guid.targetDomain = bytes32("ethereum");
        guid.receiver = addressToBytes32(address(0x123));
        guid.amount = 100;

        bytes32 signHash = auth.getSignHash(guid);
        (bytes memory signatures, address[] memory signers) = getSignatures(signHash);
        auth.addSigners(signers);

        uint maxFee = 0;

        auth.requestMint(guid, signatures, maxFee, 0);
    }

    function test_mintByReceiver() public {
        WormholeGUID memory guid;
        guid.operator = addressToBytes32(address(0x000));
        guid.sourceDomain = bytes32("l2network");
        guid.targetDomain = bytes32("ethereum");
        guid.receiver = addressToBytes32(address(this));
        guid.amount = 100;

        bytes32 signHash = auth.getSignHash(guid);
        (bytes memory signatures, address[] memory signers) = getSignatures(signHash);
        auth.addSigners(signers);

        uint maxFee = 0;

        auth.requestMint(guid, signatures, maxFee, 0);
    }

    function testFail_mint_notOperatorNorReceiver() public {
        WormholeGUID memory guid;
        guid.operator = addressToBytes32(address(0x123));
        guid.sourceDomain = bytes32("l2network");
        guid.targetDomain = bytes32("ethereum");
        guid.receiver = addressToBytes32(address(0x987));
        guid.amount = 100;

        bytes32 signHash = auth.getSignHash(guid);
        (bytes memory signatures, address[] memory signers) = getSignatures(signHash);
        auth.addSigners(signers);

        uint maxFee = 0;

        auth.requestMint(guid, signatures, maxFee, 0);
    }

}
