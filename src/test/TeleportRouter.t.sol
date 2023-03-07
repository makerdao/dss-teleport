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

import "src/TeleportRouter.sol";

import "./mocks/GatewayMock.sol";
import "./mocks/DaiMock.sol";

contract TeleportRouterTest is Test {
    
    TeleportRouter internal router;
    address internal dai;
    address internal teleportJoin;
    bytes32 constant internal domain = "rollup";
    bytes32 constant internal parentDomain = "ethereum";

    uint256 internal constant WAD = 10**18;

    function setUp() public {
        dai = address(new DaiMock());
        teleportJoin = address(new GatewayMock());
        router = new TeleportRouter(dai, domain, parentDomain);
    }

    function testConstructor() public {
        assertEq(address(router.dai()), dai);
        assertEq(router.domain(), domain);
        assertEq(router.parentDomain(), parentDomain);
        assertEq(router.wards(address(this)), 1);
    }

    function testRelyDeny() public {
        assertEq(router.wards(address(456)), 0);
        router.rely(address(456));
        assertEq(router.wards(address(456)), 1);
        router.deny(address(456));
        assertEq(router.wards(address(456)), 0);

        router.deny(address(this));

        vm.expectRevert("TeleportRouter/not-authorized");
        router.rely(address(456));
        vm.expectRevert("TeleportRouter/not-authorized");
        router.deny(address(456));
    }

    function testFileNewDomains() public {
        bytes32 domain1 = "newdom1";
        address gateway1 = address(111);
        assertEq(router.gateways(domain1), address(0));
        assertEq(router.numDomains(), 0);

        router.file("gateway", domain1, gateway1);

        assertEq(router.gateways(domain1), gateway1);
        assertEq(router.numDomains(), 1);
        assertEq(router.domainAt(0), domain1);

        bytes32 domain2 = "newdom2";
        address gateway2 = address(222);
        assertEq(router.gateways(domain2), address(0));

        router.file("gateway", domain2, gateway2);

        assertEq(router.gateways(domain2), gateway2);
        assertEq(router.numDomains(), 2);
        assertEq(router.domainAt(0), domain1);
        assertEq(router.domainAt(1), domain2);
    }

    function testFileNewGatewayForExistingDomain() public {
        bytes32 domain1 = "dom";
        address gateway1 = address(111);
        router.file("gateway", domain1, gateway1);
        assertEq(router.gateways(domain1), gateway1);
        assertEq(router.numDomains(), 1);
        assertEq(router.domainAt(0), domain1);
        address gateway2 = address(222);
        
        router.file("gateway", domain1, gateway2);

        assertEq(router.gateways(domain1), gateway2);
        assertEq(router.numDomains(), 1);
        assertEq(router.domainAt(0), domain1);
    }

    function testFileRemoveLastDomain() public {
        bytes32 domain1 = "dom";
        address gateway = address(111);
        router.file("gateway", domain1, gateway);
        assertEq(router.gateways(domain1), gateway);
        assertEq(router.numDomains(), 1);
        assertEq(router.domainAt(0), domain1);

        // Remove last domain1
        router.file("gateway", domain1, address(0));

        assertEq(router.gateways(domain1), address(0));
        assertTrue(!router.hasDomain(domain1));
        assertEq(router.numDomains(), 0);
    }


    function testFileRemoveNotLastDomain() public {
        bytes32 domain1 = "dom1";
        bytes32 domain2 = "dom2";
        address gateway1 = address(111);
        address gateway2 = address(222);
        router.file("gateway", domain1, gateway1);
        router.file("gateway", domain2, gateway2);
        assertEq(router.gateways(domain1), gateway1);
        assertEq(router.gateways(domain2), gateway2);
        assertEq(router.numDomains(), 2);
        assertEq(router.domainAt(0), domain1);
        assertEq(router.domainAt(1), domain2);
        
        // Remove first domain
        router.file("gateway", domain1, address(0));

        assertEq(router.gateways(domain1), address(0));
        assertEq(router.gateways(domain2), gateway2);
        assertEq(router.numDomains(), 1);
        assertEq(router.domainAt(0), domain2);

        // Re-add removed domain
        router.file("gateway", domain1, gateway1);

        assertEq(router.gateways(domain1), gateway1);
        assertEq(router.gateways(domain2), gateway2);
        assertEq(router.numDomains(), 2);
        assertEq(router.domainAt(0), domain2); // domains have been swapped compared to initial state
        assertEq(router.domainAt(1), domain1);
    }

    function testFileTwoDomainsSameGateway() public {
        bytes32 domain1 = "dom1";
        bytes32 domain2 = "dom2";
        address gateway1 = address(111);
        router.file("gateway", domain1, gateway1);
        router.file("gateway", domain2, gateway1);
        assertEq(router.gateways(domain1), gateway1);
        assertEq(router.gateways(domain2), gateway1);
        assertEq(router.numDomains(), 2);
        assertEq(router.domainAt(0), domain1);
        assertEq(router.domainAt(1), domain2);
    }

    function testFileTwoDomainsSameGatewayRemove1() public {
        bytes32 domain1 = "dom1";
        bytes32 domain2 = "dom2";
        address gateway1 = address(111);
        router.file("gateway", domain1, gateway1);
        router.file("gateway", domain2, gateway1);

        router.file("gateway", domain2, address(0));

        assertEq(router.gateways(domain1), gateway1);
        assertEq(router.gateways(domain2), address(0));
        assertEq(router.numDomains(), 1);
        assertEq(router.domainAt(0), domain1);
    }

    function testFileTwoDomainsSameGatewayRemove2() public {
        bytes32 domain1 = "dom1";
        bytes32 domain2 = "dom2";
        address gateway1 = address(111);
        router.file("gateway", domain1, gateway1);
        router.file("gateway", domain2, gateway1);

        router.file("gateway", domain1, address(0));
        router.file("gateway", domain2, address(0));

        assertEq(router.gateways(domain1), address(0));
        assertEq(router.gateways(domain2), address(0));
        assertEq(router.numDomains(), 0);
    }

    function testFileTwoDomainsSameGatewaySplit() public {
        bytes32 domain1 = "dom1";
        bytes32 domain2 = "dom2";
        address gateway1 = address(111);
        address gateway2 = address(222);
        router.file("gateway", domain1, gateway1);
        router.file("gateway", domain2, gateway1);

        router.file("gateway", domain2, gateway2);

        assertEq(router.gateways(domain1), gateway1);
        assertEq(router.gateways(domain2), gateway2);
        assertEq(router.numDomains(), 2);
        assertEq(router.domainAt(0), domain1);
        assertEq(router.domainAt(1), domain2);
    }

    function testFileTwoDomainsSameGatewaySplitRemove() public {
        bytes32 domain1 = "dom1";
        bytes32 domain2 = "dom2";
        address gateway1 = address(111);
        address gateway2 = address(222);
        router.file("gateway", domain1, gateway1);
        router.file("gateway", domain2, gateway1);

        router.file("gateway", domain2, gateway2);
        router.file("gateway", domain1, address(0));

        assertEq(router.gateways(domain1), address(0));
        assertEq(router.gateways(domain2), gateway2);
        assertEq(router.numDomains(), 1);
        assertEq(router.domainAt(0), domain2);
    }

    function testFile() public {
        assertEq(router.fdust(), 0);
        router.file("fdust", 888);
        assertEq(router.fdust(), 888);
    }

    function testFileInvalidWhat() public {
        vm.expectRevert("TeleportRouter/file-unrecognized-param");
        router.file("meh", "aaa", address(888));
    }

    function testFileFailsWhenNotAuthed() public {
        router.deny(address(this));
        vm.expectRevert("TeleportRouter/not-authorized");
        router.file("gateway", "dom", address(888));
        vm.expectRevert("TeleportRouter/not-authorized");
        router.file("fdust", 1);
    }

    function testRegisterMintFromNotGateway() public {
        TeleportGUID memory guid = TeleportGUID({
            sourceDomain: "l2network",
            targetDomain: domain,
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(234)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });
        router.file("gateway", "l2network", address(555));

        vm.expectRevert("TeleportRouter/sender-not-gateway");
        router.registerMint(guid);
    }

    function testRegisterMintTargetingActualDomain() public {
        TeleportGUID memory guid = TeleportGUID({
            sourceDomain: "l2network",
            targetDomain: domain,
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(234)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });
        router.file("gateway", "l2network", address(this));
        router.file("gateway", domain, teleportJoin);

        router.registerMint(guid);
    }

    function testRegisterMintTargetingSubDomain() public {
        TeleportGUID memory guid = TeleportGUID({
            sourceDomain: "l2network",
            targetDomain: "another-l2network",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(234)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });
        router.file("gateway", "l2network", address(this));
        router.file("gateway", "another-l2network", address(new GatewayMock()));

        router.registerMint(guid);
    }

    function testRegisterMintTargetingInvalidDomain() public {
        TeleportGUID memory guid = TeleportGUID({
            sourceDomain: "l2network",
            targetDomain: "invalid-network",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(234)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });
        router.file("gateway", "l2network", address(this));

        vm.expectRevert("TeleportRouter/unsupported-target-domain");
        router.registerMint(guid);
    }

    function testRegisterMintFromParentGateway() public {
        TeleportGUID memory guid = TeleportGUID({
            sourceDomain: "l2network",
            targetDomain: "another-l2network",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(234)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });
        router.file("gateway", parentDomain, address(this));
        router.file("gateway", "another-l2network", address(new GatewayMock()));

        router.registerMint(guid);
    }

    function testSettleFromNotGateway() public {
        router.file("gateway", "l2network", address(555));
        DaiMock(dai).mint(address(this), 100 ether);
        DaiMock(dai).approve(address(router), 100 ether);

        vm.expectRevert("TeleportRouter/sender-not-gateway");
        router.settle("l2network", domain, 100 ether);
    }

    function testSettleTargetingActualDomain() public {
        router.file("gateway", "l2network", address(this));
        router.file("gateway", domain, teleportJoin);
        DaiMock(dai).mint(address(this), 100 ether);
        DaiMock(dai).approve(address(router), 100 ether);

        router.settle("l2network", domain, 100 ether);
    }

    function testSettleTargetingSubDomain() public {
        router.file("gateway", "l2network", address(this));
        router.file("gateway", "another-l2network", address(new GatewayMock()));
        DaiMock(dai).mint(address(this), 100 ether);
        DaiMock(dai).approve(address(router), 100 ether);

        router.settle("l2network", "another-l2network", 100 ether);
    }

    function testSettleFromParentGateway() public {
        router.file("gateway", parentDomain, address(this));
        router.file("gateway", "another-l2network", address(new GatewayMock()));
        DaiMock(dai).mint(address(this), 100 ether);
        DaiMock(dai).approve(address(router), 100 ether);

        router.settle("l2network", "another-l2network", 100 ether);
    }

    function testSettleTargetingInvalidDomain() public {
        router.file("gateway", "l2network", address(this));

        vm.expectRevert("TeleportRouter/unsupported-target-domain");
        router.settle("l2network", "invalid-network", 100 ether);
    }

    function testInitiateTeleport() public {
        address parentGateway = address(new GatewayMock());
        router.file("gateway", parentDomain, parentGateway);
        DaiMock(dai).mint(address(this), 100_000 ether);
        DaiMock(dai).approve(address(router), 100_000 ether);

        assertEq(DaiMock(dai).balanceOf(address(this)), 100_000 ether);
        assertEq(DaiMock(dai).balanceOf(address(router)), 0);
        assertEq(router.batches(parentDomain), 0);
        assertEq(router.nonce(), 0);

        router.initiateTeleport(parentDomain, address(123), 100_000 ether);

        assertEq(DaiMock(dai).balanceOf(address(this)), 0);
        assertEq(DaiMock(dai).balanceOf(address(router)), 100_000 ether);
        assertEq(router.batches(parentDomain), 100_000 ether);
        assertEq(router.nonce(), 1);
    }

    function testFlush() public {
        address parentGateway = address(new GatewayMock());
        router.file("gateway", parentDomain, parentGateway);
        DaiMock(dai).mint(address(this), 100_000 ether);
        DaiMock(dai).approve(address(router), 100_000 ether);
        router.initiateTeleport(parentDomain, address(123), 100_000 ether);

        assertEq(router.batches(parentDomain), 100_000 ether);
        assertEq(DaiMock(dai).balanceOf(address(router)), 100_000 ether);
        assertEq(DaiMock(dai).balanceOf(parentGateway), 0);

        router.flush(parentDomain);

        assertEq(router.batches(parentDomain), 0);
        assertEq(DaiMock(dai).balanceOf(address(router)), 0);
        assertEq(DaiMock(dai).balanceOf(parentGateway), 100_000 ether);
    }

    function testFlushDust() public {
        address parentGateway = address(new GatewayMock());
        router.file("gateway", parentDomain, parentGateway);
        DaiMock(dai).mint(address(this), 100_000 ether);
        DaiMock(dai).approve(address(router), 100_000 ether);
        router.initiateTeleport(parentDomain, address(123), 100_000 ether);

        assertEq(router.batches(parentDomain), 100_000 ether);
        assertEq(DaiMock(dai).balanceOf(address(router)), 100_000 ether);
        assertEq(DaiMock(dai).balanceOf(parentGateway), 0);

        router.file("fdust", 200_000 ether);
        vm.expectRevert("TeleportRouter/flush-dust");
        router.flush(parentDomain);
    }
}
