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

import "src/WormholeRouter.sol";

contract WormholeJoinMock {
    function registerWormholeAndWithdraw(WormholeGUID calldata wormholeGUID, uint256 maxFee) external {}
    function settle(bytes32 sourceDomain, uint256 batchedDaiToFlush) external {}
}

contract DaiMock {
    function transferFrom(address _from, address _to, uint256 _value) external returns (bool success) {}
}

contract L1BridgeMock {
    function initiateRequestMint(WormholeGUID calldata wormholeGUID, uint256 maxFee) external {}
    function initiateSettle(bytes32 sourceDomain, uint256 batchedDaiToFlush) external {}
}

contract WormholeRouterTest is DSTest {
    WormholeRouter internal router;

    function setUp() public {
        router = new WormholeRouter("ethereum", address(new DaiMock()), address(new WormholeJoinMock()));
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
        assertTrue(_tryFile("bridge", "dom", address(888)));
        router.deny(address(this));
        assertTrue(!_tryFile("bridge", "dom", address(888)));
    }

    function testFileNewDomains() public {
        bytes32 domain1 = "newdom1";
        address bridge1 = address(111);
        assertEq(router.bridges(domain1), address(0));
        assertEq(router.domains(bridge1), bytes32(0));
        assertEq(router.numActiveDomains(), 0);

        assertTrue(_tryFile("bridge", domain1, bridge1));

        assertEq(router.bridges(domain1), bridge1);
        assertEq(router.domains(bridge1), domain1);
        assertEq(router.numActiveDomains(), 1);
        assertEq(router.allDomains(0), domain1);
        assertEq(router.domainIndices(domain1), 0);

        bytes32 domain2 = "newdom2";
        address bridge2 = address(222);
        assertEq(router.bridges(domain2), address(0));
        assertEq(router.domains(bridge2), bytes32(0));

        assertTrue(_tryFile("bridge", domain2, bridge2));

        assertEq(router.bridges(domain2), bridge2);
        assertEq(router.domains(bridge2), domain2);
        assertEq(router.numActiveDomains(), 2);
        assertEq(router.allDomains(0), domain1);
        assertEq(router.allDomains(1), domain2);
        assertEq(router.domainIndices(domain1), 0);
        assertEq(router.domainIndices(domain2), 1);
    }

    function testFileNewBridgeForExistingDomain() public {
        bytes32 domain = "dom";
        address bridge1 = address(111);
        assertTrue(_tryFile("bridge", domain, bridge1));
        assertEq(router.bridges(domain), bridge1);
        assertEq(router.domains(bridge1), domain);
        assertEq(router.numActiveDomains(), 1);
        assertEq(router.allDomains(0), domain);
        assertEq(router.domainIndices(domain), 0);
        address bridge2 = address(222);
        
        assertTrue(_tryFile("bridge", domain, bridge2));

        assertEq(router.bridges(domain), bridge2);
        assertEq(router.domains(bridge1), bytes32(0));
        assertEq(router.domains(bridge2), domain);
        assertEq(router.numActiveDomains(), 1);
        assertEq(router.allDomains(0), domain);
        assertEq(router.domainIndices(domain), 0);
    }

    function testFileRemoveLastDomain() public {
        bytes32 domain = "dom";
        address bridge = address(111);
        assertTrue(_tryFile("bridge", domain, bridge));
        assertEq(router.bridges(domain), bridge);
        assertEq(router.domains(bridge), domain);
        assertEq(router.numActiveDomains(), 1);
        assertEq(router.allDomains(0), domain);
        assertEq(router.domainIndices(domain), 0);

        // Remove last domain
        assertTrue(_tryFile("bridge", domain, address(0)));

        assertEq(router.bridges(domain), address(0));
        assertEq(router.domains(bridge), bytes32(0));
        assertEq(router.numActiveDomains(), 0);
        assertEq(router.domainIndices(domain), 0);
    }


    function testFileRemoveNotLastDomain() public {
        bytes32 domain1 = "dom1";
        bytes32 domain2 = "dom2";
        address bridge1 = address(111);
        address bridge2 = address(222);
        assertTrue(_tryFile("bridge", domain1, bridge1));
        assertTrue(_tryFile("bridge", domain2, bridge2));
        assertEq(router.bridges(domain1), bridge1);
        assertEq(router.bridges(domain2), bridge2);
        assertEq(router.domains(bridge1), domain1);
        assertEq(router.domains(bridge2), domain2);
        assertEq(router.numActiveDomains(), 2);
        assertEq(router.allDomains(0), domain1);
        assertEq(router.allDomains(1), domain2);
        assertEq(router.domainIndices(domain1), 0);
        assertEq(router.domainIndices(domain2), 1);
        
        // Remove first domain
        assertTrue(_tryFile("bridge", domain1, address(0)));

        assertEq(router.bridges(domain1), address(0));
        assertEq(router.bridges(domain2), bridge2);
        assertEq(router.domains(bridge1), bytes32(0));
        assertEq(router.domains(bridge2), domain2);
        assertEq(router.numActiveDomains(), 1);
        assertEq(router.allDomains(0), domain2);
        assertEq(router.domainIndices(domain1), 0);
        assertEq(router.domainIndices(domain2), 0);

        // Re-add removed domain
        assertTrue(_tryFile("bridge", domain1, bridge1));

        assertEq(router.bridges(domain1), bridge1);
        assertEq(router.bridges(domain2), bridge2);
        assertEq(router.domains(bridge1), domain1);
        assertEq(router.domains(bridge2), domain2);
        assertEq(router.numActiveDomains(), 2);
        assertEq(router.allDomains(0), domain2); // domains have been swapped compared to initial state
        assertEq(router.allDomains(1), domain1);
        assertEq(router.domainIndices(domain1), 1); // indices have been swapped compared to initial state
        assertEq(router.domainIndices(domain2), 0);
    }

    function testFailFileInvalidWhat() public {
        router.file("meh", "aaa", address(888));
    }

    function testFailRequestMintFromNotBridge() public {
        WormholeGUID memory guid = WormholeGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: address(123),
            operator: address(234),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });
        router.file("bridge", "l2network", address(555));

        router.requestMint(guid, 100 ether);
    }

    function testRequestMintTargetingL1() public {
        WormholeGUID memory guid = WormholeGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: address(123),
            operator: address(234),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });
        router.file("bridge", "l2network", address(this));

        router.requestMint(guid, 100 ether);
    }

    function testRequestMintTargetingL2() public {
        WormholeGUID memory guid = WormholeGUID({
            sourceDomain: "l2network",
            targetDomain: "another-l2network",
            receiver: address(123),
            operator: address(234),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });
        router.file("bridge", "l2network", address(this));
        router.file("bridge", "another-l2network", address(new L1BridgeMock()));

        router.requestMint(guid, 100 ether);
    }

    function testFailRequestMintTargetingInvalidDomain() public {
        WormholeGUID memory guid = WormholeGUID({
            sourceDomain: "l2network",
            targetDomain: "invalid-network",
            receiver: address(123),
            operator: address(234),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });
        router.file("bridge", "l2network", address(this));

        router.requestMint(guid, 100 ether);
    }

    function testFailSettleFromNotBridge() public {
        router.file("bridge", "l2network", address(555));

        router.settle("ethereum", 100 ether);
    }

    function testSettleTargetingL1() public {
        router.file("bridge", "l2network", address(this));

        router.settle("ethereum", 100 ether);
    }

    function testSettleTargetingL2() public {
        router.file("bridge", "l2network", address(this));
        router.file("bridge", "another-l2network", address(new L1BridgeMock()));

        router.settle("another-l2network", 100 ether);
    }

    function testFailSettleTargetingInvalidDomain() public {
        router.file("bridge", "l2network", address(this));

        router.settle("invalid-network", 100 ether);
    }
}
