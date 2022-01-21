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
    function warp(uint) external;
    function addr(uint) external returns (address);
    function sign(uint, bytes32) external returns (uint8, bytes32, bytes32);
}

contract VatMock {
    uint256 internal constant RAY = 10 ** 27;
    uint256 public live = 1;

    struct Urn {
        uint256 ink;   // Locked Collateral  [wad]
        uint256 art;   // Normalised Debt    [wad]
    }

    mapping (address => mapping (address => uint256)) public can;
    mapping (bytes32 => mapping (address => Urn ))    public urns;
    mapping (bytes32 => mapping (address => uint256)) public gem;
    mapping (address => uint256)                      public dai;

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

    function either(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := or(x, y)}
    }

    function wish(address bit, address usr) internal view returns (bool) {
        return either(bit == usr, can[bit][usr] == 1);
    }

    function hope(address usr) external {
        can[msg.sender][usr] = 1;
    }

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
        require(wish(src, msg.sender), "Vat/not-allowed");
        dai[src] = sub(dai[src], rad);
        dai[dst] = add(dai[dst], rad);
    }

    function slip(bytes32 ilk, address usr, int256 wad) external {
        gem[ilk][usr] = add(gem[ilk][usr], wad);
    }

    function suck(address, address v, uint rad) external {
        dai[v] = add(dai[v], rad);
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
    uint256 internal constant RAY = 10 ** 27;
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

    Hevm internal hevm = Hevm(HEVM_ADDRESS);
    bytes32 constant internal ilk = "L2DAI";
    bytes32 constant internal domain = "ethereum";
    WormholeJoin internal join;
    VatMock internal vat;
    DaiMock internal dai;
    DaiJoinMock internal daiJoin;
    address internal vow = address(111);

    uint256 internal constant WAD = 10**18;
    uint256 internal constant RAD = 10**45;
    uint256 internal constant TTL = 8 days;

    function setUp() public {
        vat = new VatMock();
        dai = new DaiMock();
        daiJoin = new DaiJoinMock(address(vat), address(dai));
        join = new WormholeJoin(address(vat), address(daiJoin), ilk, domain);
        join.file("line", "l2network", 1_000_000 ether);
        join.file("vow", vow);
        join.file("fees", "l2network", address(new WormholeConstantFee(0, TTL)));
        vat.hope(address(daiJoin));
    }

    function _ink() internal view returns (uint256 ink_) {
        (ink_,) = vat.urns(join.ilk(), address(join));
    }

    function _art() internal view returns (uint256 art_) {
        (, art_) = vat.urns(join.ilk(), address(join));
    }

    function _blessed(WormholeGUID memory guid) internal view returns (bool blessed_) {
        (blessed_, ) = join.wormholes(getGUIDHash(guid));
    }

    function _pending(WormholeGUID memory guid) internal view returns (uint248 pending_) {
        (, pending_) = join.wormholes(getGUIDHash(guid));
    }

    function _tryRely(address usr) internal returns (bool ok) {
        (ok,) = address(join).call(abi.encodeWithSignature("rely(address)", usr));
    }

    function _tryDeny(address usr) internal returns (bool ok) {
        (ok,) = address(join).call(abi.encodeWithSignature("deny(address)", usr));
    }

    function _tryFile(bytes32 what, address data) internal returns (bool ok) {
        (ok,) = address(join).call(abi.encodeWithSignature("file(bytes32,address)", what, data));
    }

    function _tryFile(bytes32 what, bytes32 domain_, address data) internal returns (bool ok) {
        (ok,) = address(join).call(abi.encodeWithSignature("file(bytes32,bytes32,address)", what, domain_, data));
    }

    function _tryFile(bytes32 what, bytes32 domain_, uint256 data) internal returns (bool ok) {
        (ok,) = address(join).call(abi.encodeWithSignature("file(bytes32,bytes32,uint256)", what, domain_, data));
    }

    function testConstructor() public {
        assertEq(address(join.vat()), address(vat));
        assertEq(address(join.daiJoin()), address(daiJoin));
        assertEq(join.ilk(), ilk);
        assertEq(join.domain(), domain);
        assertEq(join.wards(address(this)), 1);
    }

    function testRelyDeny() public {
        assertEq(join.wards(address(456)), 0);
        assertTrue(_tryRely(address(456)));
        assertEq(join.wards(address(456)), 1);
        assertTrue(_tryDeny(address(456)));
        assertEq(join.wards(address(456)), 0);

        join.deny(address(this));

        assertTrue(!_tryRely(address(456)));
        assertTrue(!_tryDeny(address(456)));
    }

    function testFile() public {
        assertEq(join.vow(), vow);
        assertTrue(_tryFile("vow", address(888)));
        assertEq(join.vow(), address(888));

        assertEq(join.fees("aaa"), address(0));
        assertTrue(_tryFile("fees", "aaa", address(888)));
        assertEq(join.fees("aaa"), address(888));

        assertEq(join.line("aaa"), 0);
        uint256 maxInt256 = uint256(type(int256).max);
        assertTrue(_tryFile("line", "aaa", maxInt256));
        assertEq(join.line("aaa"), maxInt256);

        assertTrue(!_tryFile("line", "aaa", maxInt256 + 1));

        join.deny(address(this));

        assertTrue(!_tryFile("vow", address(888)));
        assertTrue(!_tryFile("fees", "aaa", address(888)));
        assertTrue(!_tryFile("line", "aaa", 10));
    }

    function testInvalidWhat() public {
       assertTrue(!_tryFile("meh", address(888)));
       assertTrue(!_tryFile("meh", domain, address(888)));
       assertTrue(!_tryFile("meh", domain, 888));
    }

    function testRegisterAndWithdrawAll() public {
        WormholeGUID memory guid = WormholeGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(this)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });

        assertEq(dai.balanceOf(address(123)), 0);
        assertTrue(!_blessed(guid));
        assertEq(_pending(guid), 0);
        assertEq(_ink(), 0);
        assertEq(_art(), 0);

        join.requestMint(guid, 0, 0);

        assertEq(dai.balanceOf(address(123)), 250_000 ether);
        assertTrue(_blessed(guid));
        assertEq(_pending(guid), 0);
        assertEq(_ink(), 250_000 ether);
        assertEq(_art(), 250_000 ether);
        assertEq(join.totalDebt(), 250_000 * RAD);
    }

    function testRegisterAndWithdrawPartial() public {
        WormholeGUID memory guid = WormholeGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(this)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });

        join.file("line", "l2network", 200_000 ether);
        join.requestMint(guid, 0, 0);

        assertEq(dai.balanceOf(address(123)), 200_000 ether);
        assertTrue(_blessed(guid));
        assertEq(_pending(guid), 50_000 ether);
        assertEq(_ink(), 200_000 ether);
        assertEq(_art(), 200_000 ether);
        assertEq(join.totalDebt(), 200_000 * RAD);
    }

    function testRegisterAndWithdrawNothing() public {
        WormholeGUID memory guid = WormholeGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(this)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });

        join.file("line", "l2network", 0);
        join.requestMint(guid, 0, 0);

        assertEq(dai.balanceOf(address(123)), 0);
        assertTrue(_blessed(guid));
        assertEq(_pending(guid), 250_000 ether);
        assertEq(_ink(), 0);
        assertEq(_art(), 0);
        assertEq(join.totalDebt(), 0);
    }


    function testFailRegisterAlreadyRegistered() public {
        WormholeGUID memory guid = WormholeGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(this)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });
        join.requestMint(guid, 0, 0);
        join.requestMint(guid, 0, 0);
    }

    function testFailRegisterWrongDomain() public {
        WormholeGUID memory guid = WormholeGUID({
            sourceDomain: "l2network",
            targetDomain: "etherium",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(this)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });
        join.requestMint(guid, 0, 0);
    }

    function testRegisterAndWithdrawPayingFee() public {
        WormholeGUID memory guid = WormholeGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(this)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });
        assertEq(vat.dai(vow), 0);
        WormholeConstantFee fees = new WormholeConstantFee(100 ether, TTL);
        assertEq(fees.fee(), 100 ether);

        join.file("fees", "l2network", address(fees));
        join.requestMint(guid, 4 * WAD / 10000, 0); // 0.04% * 250K = 100 (just enough)

        assertEq(vat.dai(vow), 100 * RAD);
        assertEq(dai.balanceOf(address(123)), 249_900 ether);
        assertEq(_pending(guid), 0);
        assertEq(_ink(), 250_000 ether);
        assertEq(_art(), 250_000 ether);
        assertEq(join.totalDebt(), 250_000 * RAD);
    }

    function testFailRegisterAndWithdrawPayingFee() public {
        WormholeGUID memory guid = WormholeGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(this)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });

        join.file("fees", "l2network", address(new WormholeConstantFee(100 ether, TTL)));
        join.requestMint(guid, 3 * WAD / 10000, 0); // 0.03% * 250K < 100 (not enough)
    }

    function testRegisterAndWithdrawFeeTTLExpires() public {
        WormholeGUID memory guid = WormholeGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(this)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });
        assertEq(vat.dai(vow), 0);
        WormholeConstantFee fees = new WormholeConstantFee(100 ether, TTL);
        assertEq(fees.fee(), 100 ether);

        join.file("fees", "l2network", address(fees));
        hevm.warp(block.timestamp + TTL + 1 days);    // Over ttl - you don't pay fees
        join.requestMint(guid, 0, 0);

        assertEq(vat.dai(vow), 0);
        assertEq(dai.balanceOf(address(123)), 250_000 ether);
        assertEq(_pending(guid), 0);
        assertEq(_ink(), 250_000 ether);
        assertEq(_art(), 250_000 ether);
        assertEq(join.totalDebt(), 250_000 * RAD);
    }

    function testRegisterAndWithdrawPartialPayingFee() public {
        WormholeGUID memory guid = WormholeGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(this)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });

        assertEq(vat.dai(vow), 0);

        join.file("line", "l2network", 200_000 ether);
        join.file("fees", "l2network", address(new WormholeConstantFee(100 ether, TTL)));
        join.requestMint(guid, 4 * WAD / 10000, 0); // 0.04% * 200K = 80 (just enough as fee is also proportional)

        assertEq(vat.dai(vow), 80 * RAD);
        assertEq(dai.balanceOf(address(123)), 199_920 ether);
        assertTrue(_blessed(guid));
        assertEq(_pending(guid), 50_000 ether);
        assertEq(_ink(), 200_000 ether);
        assertEq(_art(), 200_000 ether);
        assertEq(join.totalDebt(), 200_000 * RAD);

        join.file("line", "l2network", 250_000 ether);

        join.mintPending(guid, 4 * WAD / 10000, 0); // 0.04% * 50 = 20 (just enough as fee is also proportional)

        assertEq(vat.dai(vow), 100 * RAD);
        assertEq(dai.balanceOf(address(123)), 249_900 ether);
        assertEq(_pending(guid), 0);
        assertEq(_ink(), 250_000 ether);
        assertEq(_art(), 250_000 ether);
        assertEq(join.totalDebt(), 250_000 * RAD);
    }

    function testFailRegisterAndWithdrawPartialPayingFee() public {
        WormholeGUID memory guid = WormholeGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(this)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });

        assertEq(vat.dai(vow), 0);

        join.file("line", "l2network", 200_000 ether);
        join.file("fees", "l2network", address(new WormholeConstantFee(100 ether, TTL)));
        join.requestMint(guid, 3 * WAD / 10000, 0); // 0.03% * 200K < 80 (not enough)
    }

    function testFailRegisterAndWithdrawPartialPayingFee2() public {
        WormholeGUID memory guid = WormholeGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(this)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });

        assertEq(vat.dai(vow), 0);

        join.file("line", "l2network", 200_000 ether);
        join.file("fees", "l2network", address(new WormholeConstantFee(100 ether, TTL)));
        join.requestMint(guid, 4 * WAD / 10000, 0);

        join.file("line", "l2network", 250_000 ether);

        join.mintPending(guid, 3 * WAD / 10000, 0); // 0.03% * 50 < 20 (not enough)
    }

    function testMintPendingByOperator() public {
        WormholeGUID memory guid = WormholeGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(this)),
            operator: addressToBytes32(address(this)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });

        join.file("line", "l2network", 200_000 ether);
        join.requestMint(guid, 0, 0);

        assertEq(dai.balanceOf(address(this)), 200_000 ether);
        assertTrue(_blessed(guid));
        assertEq(_pending(guid), 50_000 ether);

        join.file("line", "l2network", 225_000 ether);
        join.mintPending(guid, 0, 0);

        assertEq(dai.balanceOf(address(this)), 225_000 ether);
        assertEq(_pending(guid), 25_000 ether);
    }

    function testMintPendingByOperatorNotReceiver() public {
        WormholeGUID memory guid = WormholeGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(this)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });

        join.file("line", "l2network", 200_000 ether);
        join.requestMint(guid, 0, 0);

        assertEq(dai.balanceOf(address(123)), 200_000 ether);
        assertTrue(_blessed(guid));
        assertEq(_pending(guid), 50_000 ether);

        join.file("line", "l2network", 225_000 ether);
        join.mintPending(guid, 0, 0);

        assertEq(dai.balanceOf(address(123)), 225_000 ether);
        assertEq(_pending(guid), 25_000 ether);
    }

    function testMintPendingByReceiver() public {
        WormholeGUID memory guid = WormholeGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(this)),
            operator: addressToBytes32(address(0x123)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });

        join.file("line", "l2network", 200_000 ether);
        join.requestMint(guid, 0, 0);

        assertEq(dai.balanceOf(address(this)), 200_000 ether);
        assertTrue(_blessed(guid));
        assertEq(_pending(guid), 50_000 ether);

        join.file("line", "l2network", 225_000 ether);
        join.mintPending(guid, 0, 0);

        assertEq(dai.balanceOf(address(this)), 225_000 ether);
        assertEq(_pending(guid), 25_000 ether);
    }

    function testFailMintPendingWrongOperator() public {
        WormholeGUID memory guid = WormholeGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(654)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });

        join.file("line", "l2network", 200_000 ether);
        join.requestMint(guid, 0, 0);

        join.file("line", "l2network", 225_000 ether);
        join.mintPending(guid, 0, 0);
    }

    function testSettle() public {
        assertEq(join.debt("l2network"), 0);

        vat.suck(address(0), address(this), 100_000 * RAD);
        daiJoin.exit(address(join), 100_000 ether);

        join.settle("l2network", 100_000 ether);

        assertEq(join.debt("l2network"), -100_000 ether);
        assertEq(join.totalDebt(), 0);
    }

    function testWithdrawNegativeDebt() public {
        vat.suck(address(0), address(this), 100_000 * RAD);
        daiJoin.exit(address(join), 100_000 ether);

        join.settle("l2network", 100_000 ether);

        assertEq(join.debt("l2network"), -100_000 ether);
        assertEq(join.totalDebt(), 0);

        WormholeGUID memory guid = WormholeGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(654)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });

        join.requestMint(guid, 0, 0);

        assertEq(dai.balanceOf(address(123)), 250_000 ether);
        assertEq(_ink(), 150_000 ether);
        assertEq(_art(), 150_000 ether);
        assertEq(join.totalDebt(), 150_000 * RAD);
    }

    function testWithdrawPartialNegativeDebt() public {
        vat.suck(address(0), address(this), 100_000 * RAD);
        daiJoin.exit(address(join), 100_000 ether);

        join.settle("l2network", 100_000 ether);

        assertEq(join.debt("l2network"), -100_000 ether);
        assertEq(join.totalDebt(), 0);

        WormholeGUID memory guid = WormholeGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(654)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });

        join.file("line", "l2network", 100_000 ether);
        join.requestMint(guid, 0, 0);

        assertEq(dai.balanceOf(address(123)), 200_000 ether);
        assertEq(_pending(guid), 50_000 ether);
        assertEq(_ink(), 100_000 ether);
        assertEq(_art(), 100_000 ether);
        assertEq(join.totalDebt(), 100_000 * RAD);
    }

    function testWithdrawVatCaged() public {
        vat.suck(address(0), address(this), 100_000 * RAD);
        daiJoin.exit(address(join), 100_000 ether);

        join.settle("l2network", 100_000 ether);

        assertEq(join.debt("l2network"), -100_000 ether);
        assertEq(join.totalDebt(), 0);

        WormholeGUID memory guid = WormholeGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(654)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });

        vat.cage();
        assertEq(vat.live(), 0);

        join.file("fees", "l2network", address(new WormholeConstantFee(100 ether, TTL)));
        join.requestMint(guid, 0, 0);

        assertEq(dai.balanceOf(address(123)), 100_000 ether); // Can't pay more than DAI is already in the join
        assertEq(_pending(guid), 150_000 ether);
        assertEq(_ink(), 0);
        assertEq(_art(), 0);
        assertEq(vat.dai(vow), 0); // No fees regardless the contract set
        assertEq(join.totalDebt(), 0);
    }

    function testSettleVatCaged() public {
        WormholeGUID memory guid = WormholeGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(654)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });

        join.requestMint(guid, 0, 0);

        assertEq(join.debt("l2network"), 250_000 ether);
        assertEq(_ink(), 250_000 ether);
        assertEq(_art(), 250_000 ether);
        assertEq(join.totalDebt(), 250_000 * RAD);

        vat.cage();

        vat.suck(address(0), address(this), 250_000 * RAD);
        daiJoin.exit(address(join), 250_000 ether);

        join.settle("l2network", 250_000 ether);

        assertEq(join.debt("l2network"), 0);
        assertEq(_ink(), 250_000 ether);
        assertEq(_art(), 250_000 ether);
        assertEq(join.totalDebt(), 250_000 * RAD);
    }

    function testRegisterAndWithdrawPayingOperatorFee() public {
        WormholeGUID memory guid = WormholeGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(this)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });
        assertEq(vat.dai(address(this)), 0);
        join.requestMint(guid, 0, 250 ether);
        assertEq(vat.dai(address(this)), 250 * RAD);
        assertEq(dai.balanceOf(address(123)), 249_750 ether);
        assertEq(_pending(guid), 0);
        assertEq(_ink(), 250_000 ether);
        assertEq(_art(), 250_000 ether);
    }

    function testFailOperatorFeeTooHigh() public {
        WormholeGUID memory guid = WormholeGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(this)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });
        join.requestMint(guid, 0, 250_001 ether);   // Slightly over the amount
    }

    function testRegisterAndWithdrawPartialPayingOperatorFee() public {
        WormholeGUID memory guid = WormholeGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(this)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });

        join.file("line", "l2network", 200_000 ether);
        join.requestMint(guid, 0, 200 ether);

        assertEq(vat.dai(address(this)), 200 * RAD);
        assertEq(dai.balanceOf(address(123)), 199_800 ether);
        assertTrue(_blessed(guid));
        assertEq(_pending(guid), 50_000 ether);
        assertEq(_ink(), 200_000 ether);
        assertEq(_art(), 200_000 ether);

        join.file("line", "l2network", 250_000 ether);
        join.mintPending(guid, 0, 5 ether);

        assertEq(vat.dai(address(this)), 205 * RAD);
        assertEq(dai.balanceOf(address(123)), 249_795 ether);
        assertEq(_pending(guid), 0);
        assertEq(_ink(), 250_000 ether);
        assertEq(_art(), 250_000 ether);
    }

    function testRegisterAndWithdrawPayingTwoFees() public {
        WormholeGUID memory guid = WormholeGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(address(123)),
            operator: addressToBytes32(address(this)),
            amount: 250_000 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });
        assertEq(vat.dai(address(this)), 0);
        join.file("fees", "l2network", address(new WormholeConstantFee(1000 ether, TTL)));
        join.requestMint(guid, 40 ether / 10000, 249 ether);
        assertEq(vat.dai(address(this)), 249 * RAD);
        assertEq(vat.dai(vow), 1000 * RAD);
        assertEq(dai.balanceOf(address(123)), 248_751 ether);
        assertEq(_pending(guid), 0);
        assertEq(_ink(), 250_000 ether);
        assertEq(_art(), 250_000 ether);
    }
}
