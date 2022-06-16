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

pragma solidity 0.8.14;

import "ds-test/test.sol";

import {TeleportJoin} from "src/TeleportJoin.sol";
import "src/TeleportGUID.sol";
import "src/TeleportConstantFee.sol";

interface Hevm {
    function warp(uint) external;
    function store(address, bytes32, bytes32) external;
}

interface ChainlogLike {
    function getAddress(bytes32) external view returns (address);
}

interface AuthLike {
    function wards(address) external view returns (uint256);
}

interface VatLike {
    function wards(address) external view returns (uint256);
    function rely(address) external;
    function init(bytes32) external;
    function file(bytes32 ilk, bytes32 what, uint data) external;
    function dai(address) external view returns (uint256);
    function debt() external view returns (uint256);
}

interface EndLike {
    function wait() external view returns (uint256);
    function debt() external view returns (uint256);
    function cage() external;
    function thaw() external;
}

interface CureLike {
    function tell() external view returns (uint256);
    function lift(address) external;
    function load(address) external;
}

interface TokenLike {
  function transfer(address _to, uint256 _value) external returns (bool success);
}

contract TeleportJoinIntegrationTest is DSTest {

    Hevm internal hevm = Hevm(HEVM_ADDRESS);

    bytes32 constant internal ILK = "TELEPORT-ETHEREUM-MASTER-1";
    bytes32 constant internal MASTER_DOMAIN = "ETHEREUM-MASTER-1";
    bytes32 constant internal SLAVE_DOMAIN = "L2NETWORK-SLAVE-1";

    ChainlogLike internal chainlog = ChainlogLike(0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F);
    EndLike internal end = EndLike(chainlog.getAddress("MCD_END"));
    CureLike internal cure = CureLike(chainlog.getAddress("MCD_CURE"));
    VatLike internal vat = VatLike(chainlog.getAddress("MCD_VAT"));
    TokenLike internal dai = TokenLike(chainlog.getAddress("MCD_DAI"));
    address internal vow = chainlog.getAddress("MCD_VOW");

    TeleportJoin internal teleportJoin;

    uint256 internal constant RAD = 10**45;
    uint256 internal constant RAY = 10**27;
    uint256 internal constant TTL = 8 days;

    function getAuthFor(address auth) internal {
        hevm.store(
            auth,
            keccak256(abi.encode(address(this), 0)),
            bytes32(uint256(1))
        );
        assertEq(AuthLike(auth).wards(address(this)), 1);
    }

    function setUp() public {
        // setup teleportJoin
        teleportJoin = new TeleportJoin(address(vat), chainlog.getAddress("MCD_JOIN_DAI"), ILK, MASTER_DOMAIN);
        teleportJoin.file(bytes32("vow"), vow);
        teleportJoin.file("line", SLAVE_DOMAIN, 1_000_000 ether);
        teleportJoin.file("fees", SLAVE_DOMAIN, address(new TeleportConstantFee(0, TTL)));

        // setup ILK in vat
        getAuthFor(address(vat));
        vat.rely(address(teleportJoin));
        vat.init(ILK);
        vat.file(ILK, bytes32("spot"), RAY);
        vat.file(ILK, bytes32("line"), 10000000000 * RAD);

        // setup cure
        getAuthFor(address(cure));
        cure.lift(address(teleportJoin));
    }

    function testEmergencyShutdown() public {
        // perform teleport

        assertEq(teleportJoin.cure(), 0);
        uint256 debtBeforeTeleport = vat.debt(); 
        uint256 teleportAmount = 250_000 ether;
        TeleportGUID memory guid = TeleportGUID({
            sourceDomain: SLAVE_DOMAIN,
            targetDomain: MASTER_DOMAIN,
            receiver: addressToBytes32(address(this)),
            operator: addressToBytes32(address(654)),
            amount: uint128(teleportAmount),
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });

        teleportJoin.requestMint(guid, 0, 0);

        assertEq(vat.debt(), debtBeforeTeleport + teleportAmount * RAY);
        assertEq(teleportJoin.cure(), teleportAmount * RAY);

        // cage the end

        getAuthFor(address(end));

        end.cage();

        // attempt to settle the dai debt

        assertEq(vat.dai(address(teleportJoin)), 0);
        dai.transfer(address(teleportJoin), teleportAmount);

        teleportJoin.settle(SLAVE_DOMAIN, teleportAmount);

        assertEq(vat.dai(address(teleportJoin)), teleportAmount * RAY); // the dai is now locked in teleportJoin
        assertEq(teleportJoin.cure(), teleportAmount * RAY); // the debt was not actually settled

        // load the cure 

        cure.load(address(teleportJoin));

        assertEq(cure.tell(), teleportAmount * RAY);

        // thaw the end

        uint256 vatDebt = vat.debt();
        hevm.warp(block.timestamp + end.wait());
        hevm.store(address(vat), keccak256(abi.encode(vow, 5)), bytes32(0)); // emulate clearing of vow dai
        assertEq(vat.dai(vow), 0);

        end.thaw();

        assertEq(end.debt(), vatDebt - teleportAmount * RAY);
    }
}
