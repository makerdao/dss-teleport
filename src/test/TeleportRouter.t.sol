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

import "src/TeleportRouter.sol";

import "./mocks/GatewayMock.sol";
import "./mocks/DaiMock.sol";

contract TeleportRouterTest is DSTest {
    
    TeleportRouter internal router;
    address internal dai;
    address internal teleportJoin;
    bytes32 constant internal l1Domain = "ethereum";

    uint256 internal constant WAD = 10**18;

    function setUp() public {
        dai = address(new DaiMock());
        teleportJoin = address(new GatewayMock());
        router = new TeleportRouter(dai);
    }

    function _tryRely(address usr) internal returns (bool ok) {
        (ok,) = address(router).call(abi.encodeWithSignature("rely(address)", usr));
    }

    function _tryDeny(address usr) internal returns (bool ok) {
        (ok,) = address(router).call(abi.encodeWithSignature("deny(address)", usr));
    }

    function _tryFile(bytes32 what, bytes32 domain, address data) internal returns (bool ok) {
        (ok,) = address(router).call(abi.encodeWithSignature("file(bytes32,bytes32,address)", what, domain, data));
    }

    function _tryFile(bytes32 what, address data) internal returns (bool ok) {
        (ok,) = address(router).call(abi.encodeWithSignature("file(bytes32,address)", what, data));
    }

    function testConstructor() public {
        assertEq(address(router.dai()), dai);
        assertEq(router.wards(address(this)), 1);
    }

    function testRelyDeny() public {
        assertEq(router.wards(address(456)), 0);
        assertTrue(_tryRely(address(456)));
        assertEq(router.wards(address(456)), 1);
        assertTrue(_tryDeny(address(456)));
        assertEq(router.wards(address(456)), 0);

        router.deny(address(this));

        assertTrue(!_tryRely(address(456)));
        assertTrue(!_tryDeny(address(456)));
    }

    function testFileFailsWhenNotAuthed() public {
        assertTrue(_tryFile("gateway", "dom", address(888)));
        assertTrue(_tryFile("parent", address(888)));
        router.deny(address(this));
        assertTrue(!_tryFile("gateway", "dom", address(888)));
        assertTrue(!_tryFile("parent", address(888)));
    }

    function testFileNewDomains() public {
        bytes32 domain1 = "newdom1";
        address gateway1 = address(111);
        assertEq(router.gateways(domain1), address(0));
        assertEq(router.numDomains(), 0);

        assertTrue(_tryFile("gateway", domain1, gateway1));

        assertEq(router.gateways(domain1), gateway1);
        assertEq(router.numDomains(), 1);
        assertEq(router.domainAt(0), domain1);

        bytes32 domain2 = "newdom2";
        address gateway2 = address(222);
        assertEq(router.gateways(domain2), address(0));

        assertTrue(_tryFile("gateway", domain2, gateway2));

        assertEq(router.gateways(domain2), gateway2);
        assertEq(router.numDomains(), 2);
        assertEq(router.domainAt(0), domain1);
        assertEq(router.domainAt(1), domain2);
    }

    function testFileNewGatewayForExistingDomain() public {
        bytes32 domain = "dom";
        address gateway1 = address(111);
        assertTrue(_tryFile("gateway", domain, gateway1));
        assertEq(router.gateways(domain), gateway1);
        assertEq(router.numDomains(), 1);
        assertEq(router.domainAt(0), domain);
        address gateway2 = address(222);
        
        assertTrue(_tryFile("gateway", domain, gateway2));

        assertEq(router.gateways(domain), gateway2);
        assertEq(router.numDomains(), 1);
        assertEq(router.domainAt(0), domain);
    }

    function testFileRemoveLastDomain() public {
        bytes32 domain = "dom";
        address gateway = address(111);
        assertTrue(_tryFile("gateway", domain, gateway));
        assertEq(router.gateways(domain), gateway);
        assertEq(router.numDomains(), 1);
        assertEq(router.domainAt(0), domain);

        // Remove last domain
        assertTrue(_tryFile("gateway", domain, address(0)));

        assertEq(router.gateways(domain), address(0));
        assertTrue(!router.hasDomain(domain));
    }


    function testFileRemoveNotLastDomain() public {
        bytes32 domain1 = "dom1";
        bytes32 domain2 = "dom2";
        address gateway1 = address(111);
        address gateway2 = address(222);
        assertTrue(_tryFile("gateway", domain1, gateway1));
        assertTrue(_tryFile("gateway", domain2, gateway2));
        assertEq(router.gateways(domain1), gateway1);
        assertEq(router.gateways(domain2), gateway2);
        assertEq(router.numDomains(), 2);
        assertEq(router.domainAt(0), domain1);
        assertEq(router.domainAt(1), domain2);
        
        // Remove first domain
        assertTrue(_tryFile("gateway", domain1, address(0)));

        assertEq(router.gateways(domain1), address(0));
        assertEq(router.gateways(domain2), gateway2);
        assertEq(router.numDomains(), 1);
        assertEq(router.domainAt(0), domain2);

        // Re-add removed domain
        assertTrue(_tryFile("gateway", domain1, gateway1));

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
        assertTrue(_tryFile("gateway", domain1, gateway1));
        assertTrue(_tryFile("gateway", domain2, gateway1));
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
        assertTrue(_tryFile("gateway", domain1, gateway1));
        assertTrue(_tryFile("gateway", domain2, gateway1));

        assertTrue(_tryFile("gateway", domain2, address(0)));

        assertEq(router.gateways(domain1), gateway1);
        assertEq(router.gateways(domain2), address(0));
        assertEq(router.numDomains(), 1);
        assertEq(router.domainAt(0), domain1);
    }

    function testFileTwoDomainsSameGatewayRemove2() public {
        bytes32 domain1 = "dom1";
        bytes32 domain2 = "dom2";
        address gateway1 = address(111);
        assertTrue(_tryFile("gateway", domain1, gateway1));
        assertTrue(_tryFile("gateway", domain2, gateway1));

        assertTrue(_tryFile("gateway", domain1, address(0)));
        assertTrue(_tryFile("gateway", domain2, address(0)));

        assertEq(router.gateways(domain1), address(0));
        assertEq(router.gateways(domain2), address(0));
        assertEq(router.numDomains(), 0);
    }

    function testFileTwoDomainsSameGatewaySplit() public {
        bytes32 domain1 = "dom1";
        bytes32 domain2 = "dom2";
        address gateway1 = address(111);
        address gateway2 = address(222);
        assertTrue(_tryFile("gateway", domain1, gateway1));
        assertTrue(_tryFile("gateway", domain2, gateway1));

        assertTrue(_tryFile("gateway", domain2, gateway2));

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
        assertTrue(_tryFile("gateway", domain1, gateway1));
        assertTrue(_tryFile("gateway", domain2, gateway1));

        assertTrue(_tryFile("gateway", domain2, gateway2));
        assertTrue(_tryFile("gateway", domain1, address(0)));

        assertEq(router.gateways(domain1), address(0));
        assertEq(router.gateways(domain2), gateway2);
        assertEq(router.numDomains(), 1);
        assertEq(router.domainAt(0), domain2);
    }

    function testFileParent() public {
        assertTrue(_tryFile("parent", address(123)));

        assertEq(router.parent(), address(123));
    }

    function testFileInvalidWhat() public {
        assertTrue(!_tryFile("meh", "aaa", address(888)));
        assertTrue(!_tryFile("meh", address(888)));
    }

    function testFailRequestMintFromNotGateway() public {
        TeleportGUID memory guid = TeleportGUID({
            sourceDomain: "l2network",
            targetDomain: l1Domain,
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(234)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });
        router.file("gateway", "l2network", address(555));

        router.requestMint(guid, 4 * WAD / 10000, 0);
    }

    function testRequestMintTargetingL1() public {
        TeleportGUID memory guid = TeleportGUID({
            sourceDomain: "l2network",
            targetDomain: l1Domain,
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(234)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });
        router.file("gateway", "l2network", address(this));
        router.file("gateway", l1Domain, teleportJoin);

        router.requestMint(guid, 4 * WAD / 10000, 0);
    }

    function testRequestMintTargetingL2() public {
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

        router.requestMint(guid, 4 * WAD / 10000, 0);
    }

    function testFailRequestMintTargetingInvalidDomain() public {
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

        router.requestMint(guid, 4 * WAD / 10000, 0);
    }

    function testRequestMintFromParent() public {
        TeleportGUID memory guid = TeleportGUID({
            sourceDomain: "l2network",
            targetDomain: "another-l2network",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(234)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });
        router.file("parent", address(this));
        router.file("gateway", "another-l2network", address(new GatewayMock()));

        router.requestMint(guid, 4 * WAD / 10000, 0);
    }

    function testFailSettleFromNotGateway() public {
        router.file("gateway", "l2network", address(555));
        DaiMock(dai).mint(address(this), 100 ether);
        DaiMock(dai).approve(address(router), 100 ether);

        router.settle("l2network", l1Domain, 100 ether);
    }

    function testSettleTargetingL1() public {
        router.file("gateway", "l2network", address(this));
        router.file("gateway", l1Domain, teleportJoin);
        DaiMock(dai).mint(address(this), 100 ether);
        DaiMock(dai).approve(address(router), 100 ether);

        router.settle("l2network", l1Domain, 100 ether);
    }

    function testSettleTargetingL2() public {
        router.file("gateway", "l2network", address(this));
        router.file("gateway", "another-l2network", address(new GatewayMock()));
        DaiMock(dai).mint(address(this), 100 ether);
        DaiMock(dai).approve(address(router), 100 ether);

        router.settle("l2network", "another-l2network", 100 ether);
    }

    function testSettleFromParent() public {
        router.file("parent", address(this));
        router.file("gateway", "another-l2network", address(new GatewayMock()));
        DaiMock(dai).mint(address(this), 100 ether);
        DaiMock(dai).approve(address(router), 100 ether);

        router.settle("l2network", "another-l2network", 100 ether);
    }

    function testFailSettleTargetingInvalidDomain() public {
        router.file("gateway", "l2network", address(this));

        router.settle("l2network", "invalid-network", 100 ether);
    }
}
