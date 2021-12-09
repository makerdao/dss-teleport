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

import "src/WormholeJoin.sol";
import "src/WormholeConstantFee.sol";

interface Hevm {
    function addr(uint) external returns (address);
    function sign(uint, bytes32) external returns (uint8, bytes32, bytes32);
}

contract VatMock {
    uint256 constant RAY = 10 ** 27;
    uint256 public live = 1;

    struct Urn {
        uint256 ink;   // Locked Collateral  [wad]
        uint256 art;   // Normalised Debt    [wad]
    }

    mapping (bytes32 => mapping (address => Urn )) public urns;
    mapping (bytes32 => mapping (address => uint)) public gem;  // [wad]
    mapping (address => uint256)                   public dai;  // [rad]

    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x);
    }
    function add(uint256 x, int256 y) internal pure returns (uint256 z) {
        z = x + uint256(y);
        require(y >= 0 || z <= x);
        require(y <= 0 || z >= x);
    }
    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x);
    }
    function sub(uint256 x, int256 y) internal pure returns (uint256 z) {
        z = x - uint256(y);
        require(y <= 0 || z <= x);
        require(y >= 0 || z >= x);
    }
    function mul(uint256 x, int256 y) internal pure returns (int256 z) {
        z = int256(x) * y;
        require(int256(x) >= 0);
        require(y == 0 || z / y == int256(x));
    }

    function hope(address) external {}

    function cage() external {
        live = 0;
    }

    function frob(bytes32 i, address u, address v, address w, int dink, int dart) external {
        Urn memory urn = urns[i][u];

        urn.ink = add(urn.ink, dink);
        urn.art = add(urn.art, dart);

        int dtab = mul(RAY, dart);

        gem[i][v] = sub(gem[i][v], dink);
        dai[w]    = add(dai[w],    dtab);

        urns[i][u] = urn;
    }

    function move(address src, address dst, uint256 rad) external {
        dai[src] = sub(dai[src], rad);
        dai[dst] = add(dai[dst], rad);
    }

    function slip(bytes32 ilk, address usr, int256 wad) external {
        gem[ilk][usr] = add(gem[ilk][usr], wad);
    }
}

contract DaiMock {
    mapping (address => uint)                      public balanceOf;
    mapping (address => mapping (address => uint)) public allowance;

    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x);
    }
    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x);
    }
    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    function transfer(address dst, uint256 wad) external returns (bool) {
        return transferFrom(msg.sender, dst, wad);
    }
    function transferFrom(address src, address dst, uint256 wad)
        public returns (bool)
    {
        require(balanceOf[src] >= wad, "Dai/insufficient-balance");
        if (src != msg.sender && allowance[src][msg.sender] != type(uint256).max) {
            require(allowance[src][msg.sender] >= wad, "Dai/insufficient-allowance");
            allowance[src][msg.sender] = sub(allowance[src][msg.sender], wad);
        }
        balanceOf[src] = sub(balanceOf[src], wad);
        balanceOf[dst] = add(balanceOf[dst], wad);
        return true;
    }
    function mint(address usr, uint256 wad) external  {
        balanceOf[usr] = add(balanceOf[usr], wad);
    }
    function burn(address usr, uint256 wad) external {
        require(balanceOf[usr] >= wad, "Dai/insufficient-balance");
        if (usr != msg.sender && allowance[usr][msg.sender] != type(uint256).max) {
            require(allowance[usr][msg.sender] >= wad, "Dai/insufficient-allowance");
            allowance[usr][msg.sender] = sub(allowance[usr][msg.sender], wad);
        }
        balanceOf[usr] = sub(balanceOf[usr], wad);
    }
    function approve(address usr, uint256 wad) external returns (bool) {
        allowance[msg.sender][usr] = wad;
        return true;
    }
}

contract DaiJoinMock {
    VatMock public vat;
    DaiMock public dai;

    constructor(address vat_, address dai_) {
        vat = VatMock(vat_);
        dai = DaiMock(dai_);
    }
    uint256 constant RAY = 10 ** 27;
    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x);
    }
    function join(address usr, uint256 wad) external {
        vat.move(address(this), usr, mul(RAY, wad));
        dai.burn(msg.sender, wad);
    }
    function exit(address usr, uint256 wad) external {
        vat.move(msg.sender, address(this), mul(RAY, wad));
        dai.mint(usr, wad);
    }
}

contract WormholeJoinTest is DSTest {

    Hevm hevm = Hevm(HEVM_ADDRESS);
    WormholeJoin join;
    VatMock vat;
    DaiMock dai;
    DaiJoinMock daiJoin;
    address vow = address(111);

    function setUp() public {
        vat = new VatMock();
        dai = new DaiMock();
        daiJoin = new DaiJoinMock(address(vat), address(dai));
        join = new WormholeJoin(address(vat), address(daiJoin), "L2DAI", "ETHEREUM");
        join.file("line", "L2", 1_000_000 ether);
        join.file("vow", vow);
        join.file("fees", "L2", address(new WormholeConstantFee(0)));
    }

    function testRegisterAndWithdrawAll() public {
        WormholeGUID memory guid = WormholeGUID({
            sourceDomain: "L2",
            targetDomain: bytes32("ETHEREUM"),
            receiver: address(123),
            operator: address(123),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint64(block.timestamp)
        });

        assertEq(dai.balanceOf(address(123)), 0);
        bytes32 hashGUID = getGUIDHash(guid);
        (bool blessed, uint248 pending) = join.wormholes(hashGUID);
        assertTrue(!blessed);
        assertEq(pending, 0);

        join.registerWormholeAndWithdraw(guid, 0);

        assertEq(dai.balanceOf(address(123)), 250_000 ether);
        (blessed, pending) = join.wormholes(hashGUID);
        assertTrue(blessed);
        assertEq(pending, 0);
    }

    function testRegisterAndWithdrawPartial() public {
        WormholeGUID memory guid = WormholeGUID({
            sourceDomain: "L2",
            targetDomain: bytes32("ETHEREUM"),
            receiver: address(123),
            operator: address(123),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint64(block.timestamp)
        });

        bytes32 hashGUID = getGUIDHash(guid);

        join.file("line", "L2", 200_000 ether);
        join.registerWormholeAndWithdraw(guid, 0);

        assertEq(dai.balanceOf(address(123)), 200_000 ether);
        (bool blessed, uint248 pending) = join.wormholes(hashGUID);
        assertTrue(blessed);
        assertEq(pending, 50_000 ether);
    }

    function testRegisterAndWithdrawNothing() public {
        WormholeGUID memory guid = WormholeGUID({
            sourceDomain: "L2",
            targetDomain: bytes32("ETHEREUM"),
            receiver: address(123),
            operator: address(123),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint64(block.timestamp)
        });

        bytes32 hashGUID = getGUIDHash(guid);

        join.file("line", "L2", 0);
        join.registerWormholeAndWithdraw(guid, 0);

        assertEq(dai.balanceOf(address(123)), 0 ether);
        (bool blessed, uint248 pending) = join.wormholes(hashGUID);
        assertTrue(blessed);
        assertEq(pending, 250_000 ether);
    }
}
