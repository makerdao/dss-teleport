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

import "forge-std/Test.sol";

import "src/TeleportOracleAuth.sol";

import "./mocks/GatewayMock.sol";

interface Hevm {
    function addr(uint) external returns (address);
    function sign(uint, bytes32) external returns (uint8, bytes32, bytes32);
}

contract TeleportOracleAuthTest is Test {
    TeleportOracleAuth internal auth;
    address internal teleportJoin;

    function setUp() public {
        teleportJoin = address(new GatewayMock());
        auth = new TeleportOracleAuth(teleportJoin);
    }

    function getSignatures(bytes32 signHash) internal returns (bytes memory signatures, address[] memory signers) {
        // seeds chosen s.t. corresponding addresses are in ascending order
        uint8[30] memory seeds = [8,10,6,2,9,15,14,20,7,29,24,13,12,25,16,26,21,22,0,18,17,27,3,28,23,19,4,5,1,11];
        uint numSigners = seeds.length;
        signers = new address[](numSigners);
        for(uint i; i < numSigners; i++) {
            uint sk = uint256(keccak256(abi.encode(seeds[i])));
            signers[i] = vm.addr(sk);
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(sk, signHash);
            signatures = abi.encodePacked(signatures, r, s, v);
        }
        assertEq(signatures.length, numSigners * 65);
    }

    function testConstructor() public {
        assertEq(address(auth.teleportJoin()), teleportJoin);
        assertEq(auth.wards(address(this)), 1);
    }

    function testRelyDeny() public {
        assertEq(auth.wards(address(456)), 0);
        auth.rely(address(456));
        assertEq(auth.wards(address(456)), 1);
        auth.deny(address(456));
        assertEq(auth.wards(address(456)), 0);

        auth.deny(address(this));

        vm.expectRevert("TeleportOracleAuth/not-authorized");
        auth.rely(address(456));
        vm.expectRevert("TeleportOracleAuth/not-authorized");
        auth.deny(address(456));
    }

    function testFileFailsWhenNotAuthed() public {
        auth.file("threshold", 888);
        auth.deny(address(this));
        vm.expectRevert("TeleportOracleAuth/not-authorized");
        auth.file("threshold", 888);
    }

    function testFileNewThreshold() public {
        assertEq(auth.threshold(), 0);

        auth.file("threshold", 3);

        assertEq(auth.threshold(), 3);
    }

    function testFileInvalidWhat() public {
        vm.expectRevert("TeleportOracleAuth/file-unrecognized-param");
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
        auth.isValid(signHash, signatures, signers.length);
    }

    // Since ecrecover silently returns 0 on failure, it's a good idea to make sure
    // the logic can't be fooled by a zero signer address + invalid signature.
    function test_isValid_failed_ecrecover() public {
        bytes32 signHash = keccak256("msg");
        (bytes memory signatures, address[] memory signers) = getSignatures(signHash);

        // corrupt first signature
        unchecked {  // don't care about overflow, just want to change the first byte
            signatures[0] = bytes1(uint8(signatures[0]) + uint8(1));
        }

        // first signer to zero
        signers[0] = address(0);

        auth.addSigners(signers);
        vm.expectRevert("TeleportOracleAuth/bad-sig-order");
        auth.isValid(signHash, signatures, signers.length);
    }

    function test_isValid_notEnoughSig() public {
        bytes32 signHash = keccak256("msg");
        (bytes memory signatures, address[] memory signers) = getSignatures(signHash);
        auth.addSigners(signers);
        vm.expectRevert("TeleportOracleAuth/not-enough-sig");
        auth.isValid(signHash, signatures, signers.length + 1);
    }

    function test_isValid_badSig() public {
        bytes32 signHash = keccak256("msg");
        (bytes memory signatures, address[] memory signers) = getSignatures(signHash);
        auth.addSigners(signers);
        signatures[0] = bytes1(uint8((uint256(uint8(signatures[0])) + 1) % 256));
        vm.expectRevert("TeleportOracleAuth/bad-sig-order");
        auth.isValid(signHash, signatures, signers.length);
    }

    function test_mintByOperator() public {
        TeleportGUID memory guid;
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
        TeleportGUID memory guid;
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
        TeleportGUID memory guid;
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

    function test_mint_notOperatorNorReceiver() public {
        TeleportGUID memory guid;
        guid.operator = addressToBytes32(address(0x123));
        guid.sourceDomain = bytes32("l2network");
        guid.targetDomain = bytes32("ethereum");
        guid.receiver = addressToBytes32(address(0x987));
        guid.amount = 100;

        bytes32 signHash = auth.getSignHash(guid);
        (bytes memory signatures, address[] memory signers) = getSignatures(signHash);
        auth.addSigners(signers);

        uint maxFee = 0;

        vm.expectRevert("TeleportOracleAuth/not-receiver-nor-operator");
        auth.requestMint(guid, signatures, maxFee, 0);
    }

}
