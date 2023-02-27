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

import "ds-test/test.sol";

import "src/TeleportGUID.sol";
import "src/relays/TrustedRelay.sol";

import "../mocks/VatMock.sol";
import "../mocks/DaiMock.sol";
import "../mocks/DaiJoinMock.sol";

interface Hevm {
    function warp(uint) external;
    function addr(uint) external returns (address);
    function sign(uint, bytes32) external returns (uint8, bytes32, bytes32);
}

contract TeleportJoinMock {

    mapping (bytes32 => TeleportStatus) public teleports;

    DaiMock public dai;
    uint256 public maxMint;

    struct TeleportStatus {
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
        TeleportGUID calldata teleportGUID,
        uint256,
        uint256 operatorFee
    ) external returns (uint256 postFeeAmount, uint256 totalFee) {
        bytes32 hashGUID = getGUIDHash(teleportGUID);

        // Take 1%
        uint256 amount = teleportGUID.amount;
        if (amount > maxMint) amount = maxMint;
        uint256 fee = amount * 1 / 100;
        uint256 remainder = amount - fee;

        teleports[hashGUID].blessed = true;
        teleports[hashGUID].pending = uint248(teleportGUID.amount - amount);

        // Mint the DAI and send it to /operator
        dai.mint(bytes32ToAddress(teleportGUID.receiver), remainder - operatorFee);
        dai.mint(bytes32ToAddress(teleportGUID.operator), operatorFee);

        return (remainder - operatorFee, fee + operatorFee);
    }
}

contract TeleportOracleAuthMock {

    TeleportJoinMock public join;

    constructor(TeleportJoinMock _join) {
        join = _join;
    }

    function requestMint(
        TeleportGUID calldata teleportGUID,
        bytes calldata,
        uint256 maxFeePercentage,
        uint256 operatorFee
    ) external returns (uint256 postFeeAmount, uint256 totalFee) {
        return join.requestMint(teleportGUID, maxFeePercentage, operatorFee);
    }

    function teleportJoin() external view returns (address) {
        return address(join);
    }
}

contract DSValueMock {
    bool    has;
    bytes32 val;
    function peek() public view returns (bytes32, bool) {
        return (val,has);
    }
    function poke(bytes32 wut) public {
        val = wut;
        has = true;
    }
    function void() public {
        has = false;
    }
}

contract TrustedRelayMock is TrustedRelay {
    constructor(address _oracleAuth, address _daiJoin, address _ethPriceOracle) 
        TrustedRelay(_oracleAuth, _daiJoin, _ethPriceOracle) {}

    function gasprice() internal override pure returns (uint256) {
        return 10 * 10**9; // 10 gwei
    }
}

contract TrustedRelayTest is DSTest {

    uint256 internal constant BPS = 10**4;
    uint256 internal constant WAD = 10**18;
    uint256 internal constant GAS_MARGIN = 150 * BPS / 100;
    address internal feeCollector = address(0xf33C0113c702);

    Hevm internal hevm = Hevm(HEVM_ADDRESS);

    TrustedRelayMock internal relay;
    VatMock internal vat;
    DaiMock internal dai;
    DaiJoinMock internal daiJoin;
    TeleportJoinMock internal join;
    TeleportOracleAuthMock internal oracleAuth;
    DSValueMock internal ethPriceOracle;

    function getSignHash(
        TeleportGUID memory teleportGUID,
        uint256 maxFeePercentage,
        uint256 gasFee,
        uint256 expiry
    ) internal pure returns (bytes32 signHash) {
        signHash = keccak256(abi.encodePacked(
            "\x19Ethereum Signed Message:\n32", 
            keccak256(abi.encode(getGUIDHash(teleportGUID), maxFeePercentage, gasFee, expiry))
        ));
    }

    function setUp() public {
        vat = new VatMock();
        dai = new DaiMock();
        daiJoin = new DaiJoinMock(address(vat), address(dai));
        join = new TeleportJoinMock(dai);
        oracleAuth = new TeleportOracleAuthMock(join);
        ethPriceOracle = new DSValueMock();
        ethPriceOracle.poke(bytes32(3000 * WAD));
        relay = new TrustedRelayMock(address(oracleAuth), address(daiJoin), address(ethPriceOracle));
        relay.file("margin", GAS_MARGIN);
        relay.kiss(address(this));
        join.setMaxMint(100 ether);
    }

    function _tryRely(address usr) internal returns (bool ok) {
        (ok,) = address(relay).call(abi.encodeWithSignature("rely(address)", usr));
    }

    function _tryDeny(address usr) internal returns (bool ok) {
        (ok,) = address(relay).call(abi.encodeWithSignature("deny(address)", usr));
    }

    function _tryKiss(address usr) internal returns (bool ok) {
        (ok,) = address(relay).call(abi.encodeWithSignature("kiss(address)", usr));
    }

    function _tryDiss(address usr) internal returns (bool ok) {
        (ok,) = address(relay).call(abi.encodeWithSignature("diss(address)", usr));
    }

    function _tryFile(bytes32 what, uint256 data) internal returns (bool ok) {
        (ok,) = address(relay).call(abi.encodeWithSignature("file(bytes32,uint256)", what, data));
    }

    function _tryAddSigners(address[] memory signers) internal returns (bool ok) {
        (ok,) = address(relay).call(abi.encodeWithSignature("addSigners(address[])", signers));
    }

    function _tryRemoveSigners(address[] memory signers) internal returns (bool ok) {
        (ok,) = address(relay).call(abi.encodeWithSignature("removeSigners(address[])", signers));
    }

    function _tryAddRelayers(address[] memory relayers) internal returns (bool ok) {
        (ok,) = address(relay).call(abi.encodeWithSignature("addRelayers(address[])", relayers));
    }

    function _tryRemoveRelayers(address[] memory relayers) internal returns (bool ok) {
        (ok,) = address(relay).call(abi.encodeWithSignature("removeRelayers(address[])", relayers));
    }

    function _tryRelay(
        TeleportGUID memory teleportGUID,
        bytes memory signatures,
        uint256 maxFeePercentage,
        uint256 gasFee,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal returns (bool ok) {
        bytes memory relayData = abi.encodeWithSelector(relay.relay.selector,
            teleportGUID,
            signatures,
            maxFeePercentage,
            gasFee,
            expiry,
            v,
            r,
            s
        );
        (ok,) = address(relay).call(abi.encodePacked(relayData, feeCollector));
    }

    function _whitelistThis() internal {
        address[] memory relayers = new address[](1);
        relayers[0] = address(this);
        relay.addRelayers(relayers);
    }
    
    function test_constructor_args() public {
        assertEq(address(relay.daiJoin()), address(daiJoin));
        assertEq(address(relay.dai()), address(dai));
        assertEq(address(relay.oracleAuth()), address(oracleAuth));
        assertEq(address(relay.teleportJoin()), address(join));
        assertEq(relay.wards(address(this)), 1);
    }

    function testRelyDeny() public {
        assertEq(relay.wards(address(456)), 0);
        assertTrue(_tryRely(address(456)));
        assertEq(relay.wards(address(456)), 1);
        assertTrue(_tryDeny(address(456)));
        assertEq(relay.wards(address(456)), 0);

        relay.deny(address(this));

        assertTrue(!_tryRely(address(456)));
        assertTrue(!_tryDeny(address(456)));
    }

    function testFileFailsWhenNotAuthed() public {
        assertTrue(_tryFile("margin", 888));
        relay.deny(address(this));
        assertTrue(!_tryFile("margin", 888));
    }

    function testFileNewMargin() public {
        assertEq(relay.gasMargin(), GAS_MARGIN);

        assertTrue(_tryFile("margin", 3));

        assertEq(relay.gasMargin(), 3);
    }

    function testFileInvalidWhat() public {
        assertTrue(!_tryFile("meh", 888));
    }

    function testKissDiss() public {
        assertEq(relay.buds(address(333)), 0);
        assertTrue(_tryKiss(address(333)));
        assertEq(relay.buds(address(333)), 1);
        assertTrue(_tryDiss(address(333)));
        assertEq(relay.buds(address(333)), 0);

        assertEq(relay.buds(address(444)), 0);
        assertTrue(_tryKiss(address(444)));
        assertEq(relay.buds(address(444)), 1);

        relay.deny(address(this));

        assertTrue(!_tryDiss(address(444)));
        assertTrue(!_tryKiss(address(555)));
    }

    function testAddRemoveSigners() public {
        address[] memory signers = new address[](3);
        for(uint i; i < signers.length; i++) {
            signers[i] = address(uint160(i));
            assertEq(relay.signers(address(uint160(i))), 0);
        }
        assertEq(relay.buds(address(this)), 1);

        assertTrue(_tryAddSigners(signers));

        for(uint i; i < signers.length; i++) {
            assertEq(relay.signers(address(uint160(i))), 1);
        }

        assertTrue(_tryRemoveSigners(signers));

        for(uint i; i < signers.length; i++) {
            assertEq(relay.signers(address(uint160(i))), 0);
        }

        assertTrue(_tryDiss(address(this)));

        assertEq(relay.buds(address(this)), 0);

        assertTrue(!_tryAddSigners(signers));
        assertTrue(!_tryRemoveSigners(signers));
    }

    function testAddRemoveRelayers() public {
        address[] memory relayers = new address[](3);
        for(uint i; i < relayers.length; i++) {
            relayers[i] = address(uint160(i));
            assertEq(relay.relayers(address(uint160(i))), 0);
        }

        assertTrue(_tryAddRelayers(relayers));

        for(uint i; i < relayers.length; i++) {
            assertEq(relay.relayers(address(uint160(i))), 1);
        }

        assertTrue(_tryRemoveRelayers(relayers));

        for(uint i; i < relayers.length; i++) {
            assertEq(relay.relayers(address(uint160(i))), 0);
        }

        assertTrue(_tryDeny(address(this)));

        assertEq(relay.wards(address(this)), 0);

        assertTrue(!_tryAddRelayers(relayers));
        assertTrue(!_tryRemoveRelayers(relayers));
    }


    function test_relay_with_trusted_signer() public {
        _whitelistThis();
        uint256 sk = uint256(keccak256(abi.encode(8)));
        address[] memory signers = new address[](1);
        signers[0] = hevm.addr(sk);
        relay.addSigners(signers);
        address receiver = address(123);
        TeleportGUID memory guid = TeleportGUID({
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
        assertTrue(_tryRelay(
            guid,
            "",     // Not testing OracleAuth signatures here
            maxFeePercentage,
            gasFee,
            expiry,
            v,
            r,
            s
        ));

        // Should get 100 DAI - 1% teleport fee - 1 DAI gas fee
        assertEq(dai.balanceOf(receiver), 98 ether);
        assertEq(dai.balanceOf(feeCollector), 1 ether);
    }

    function test_relay_not_whitelisted_no_refund() public {
        uint256 sk = uint256(keccak256(abi.encode(8)));
        address[] memory signers = new address[](1);
        signers[0] = hevm.addr(sk);
        relay.addSigners(signers);
        address receiver = address(123);
        TeleportGUID memory guid = TeleportGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(receiver),
            operator: addressToBytes32(address(relay)),
            amount: 100 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });
        uint256 maxFeePercentage = WAD * 1 / 100;   // 1%
        uint256 gasFee = 0;                         // no refund requested
        uint256 expiry = block.timestamp;
        bytes32 signHash = getSignHash(
            guid,
            maxFeePercentage,
            gasFee,
            expiry
        );

        (uint8 v, bytes32 r, bytes32 s) = hevm.sign(sk, signHash);

        assertEq(dai.balanceOf(receiver), 0);

        // relay() should succeed even without the sender being whitelisted given that gasFee == 0
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

        // Should get 100 DAI - 1% teleport fee
        assertEq(dai.balanceOf(receiver), 99 ether);
    }

    function test_relay_no_fee_collector() public {
        _whitelistThis();
        uint256 sk = uint256(keccak256(abi.encode(8)));
        address receiver = hevm.addr(sk);
        TeleportGUID memory guid = TeleportGUID({
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

        // relay() should succeed even without the appended feeCollector
        // but the fee will be sent to an incorrect address
        relay.relay(
            guid,
            "",
            maxFeePercentage,
            gasFee,
            expiry,
            v,
            r,
            s
        );

        // Should get 100 DAI - 1% teleport fee - 1 DAI gas fee
        assertEq(dai.balanceOf(receiver), 98 ether);
    }


    function test_relay_when_receiver_is_signer() public {
        _whitelistThis();
        uint256 sk = uint256(keccak256(abi.encode(8)));
        address receiver = hevm.addr(sk);
        TeleportGUID memory guid = TeleportGUID({
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
        assertTrue(_tryRelay(
            guid,
            "",     // Not testing OracleAuth signatures here
            maxFeePercentage,
            gasFee,
            expiry,
            v,
            r,
            s
        ));

        // Should get 100 DAI - 1% teleport fee - 1 DAI gas fee
        assertEq(dai.balanceOf(receiver), 98 ether);
        assertEq(dai.balanceOf(feeCollector), 1 ether);  
    }

    function test_relay_with_disabled_oracle() public {
        _whitelistThis();
        (bytes32 prevPrice,) = ethPriceOracle.peek();
        ethPriceOracle.void();

        uint256 sk = uint256(keccak256(abi.encode(8)));
        address[] memory signers = new address[](1);
        signers[0] = hevm.addr(sk);
        relay.addSigners(signers);
        address receiver = address(123);
        TeleportGUID memory guid = TeleportGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(receiver),
            operator: addressToBytes32(address(relay)),
            amount: 100 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });
        uint256 maxFeePercentage = WAD * 1 / 100;   // 1%
        uint256 gasFee = 80 ether;                 // 80 DAI of gas refund (would be excessive if oracle was enabled)
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

        assertTrue(_tryRelay(
            guid,
            "",     // Not testing OracleAuth signatures here
            maxFeePercentage,
            gasFee,
            expiry,
            v,
            r,
            s
        ));

        // Should get 100 DAI - 1% teleport fee - 80 DAI gas fee
        assertEq(dai.balanceOf(receiver), 19 ether);
        assertEq(dai.balanceOf(feeCollector), 80 ether);  

        ethPriceOracle.poke(prevPrice);
    }

    function test_relay_expired() public {
        _whitelistThis();
        uint256 sk = uint256(keccak256(abi.encode(8)));
        address[] memory signers = new address[](1);
        signers[0] = hevm.addr(sk);
        relay.addSigners(signers);
        address receiver = address(123);
        TeleportGUID memory guid = TeleportGUID({
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

        assertTrue(!_tryRelay(
            guid,
            "",     // Not testing OracleAuth signatures here
            maxFeePercentage,
            gasFee,
            expiry,
            v,
            r,
            s
        ));
    }

    function test_relay_bad_signature() public {
        _whitelistThis();
        uint256 sk = uint256(keccak256(abi.encode(8)));
        address[] memory signers = new address[](1);
        signers[0] = hevm.addr(sk);
        relay.addSigners(signers);
        address receiver = address(123);
        TeleportGUID memory guid = TeleportGUID({
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


        assertTrue(!_tryRelay(
            guid,
            "",     // Not testing OracleAuth signatures here
            maxFeePercentage,
            gasFee,
            expiry,
            v,
            r,
            s
        ));
    }

    function test_relay_bad_signer() public {
        _whitelistThis();
        address receiver = address(123);
        TeleportGUID memory guid = TeleportGUID({
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

        uint256 sk = uint256(keccak256(abi.encode(888)));
        (uint8 v, bytes32 r, bytes32 s) = hevm.sign(sk, signHash);

        assertTrue(!_tryRelay(
            guid,
            "",     // Not testing OracleAuth signatures here
            maxFeePercentage,
            gasFee,
            expiry,
            v,
            r,
            s
        ));
    }

    function test_relay_partial_mint() public {
        _whitelistThis();
        join.setMaxMint(50 ether);

        uint256 sk = uint256(keccak256(abi.encode(8)));
        address[] memory signers = new address[](1);
        signers[0] = hevm.addr(sk);
        relay.addSigners(signers);
        address receiver = address(123);
        TeleportGUID memory guid = TeleportGUID({
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

        assertTrue(!_tryRelay(
            guid,
            "",     // Not testing OracleAuth signatures here
            maxFeePercentage,
            gasFee,
            expiry,
            v,
            r,
            s
        ));
    }

    function test_relay_excessive_fee() public {
        _whitelistThis();
        uint256 sk = uint256(keccak256(abi.encode(8)));
        address[] memory signers = new address[](1);
        signers[0] = hevm.addr(sk);
        relay.addSigners(signers);
        address receiver = address(123);
        TeleportGUID memory guid = TeleportGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(receiver),
            operator: addressToBytes32(address(relay)),
            amount: 100 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });
        uint256 maxFeePercentage = WAD * 1 / 100;   // 1%
        uint256 gasFee = 80 * WAD;                  // 80 DAI of gas refund
        uint256 expiry = block.timestamp;
        bytes32 signHash = getSignHash(
            guid,
            maxFeePercentage,
            gasFee,
            expiry
        );

        (uint8 v, bytes32 r, bytes32 s) = hevm.sign(sk, signHash);

        assertTrue(!_tryRelay(
            guid,
            "",     // Not testing OracleAuth signatures here
            maxFeePercentage,
            gasFee,
            expiry,
            v,
            r,
            s
        ));
    }

    function test_relayer_not_whitelisted() public {
        uint256 sk = uint256(keccak256(abi.encode(8)));
        address[] memory signers = new address[](1);
        signers[0] = hevm.addr(sk);
        relay.addSigners(signers);
        address receiver = address(123);
        TeleportGUID memory guid = TeleportGUID({
            sourceDomain: "l2network",
            targetDomain: "ethereum",
            receiver: addressToBytes32(receiver),
            operator: addressToBytes32(address(relay)),
            amount: 100 ether,
            nonce: 5,
            timestamp: uint48(block.timestamp)
        });
        uint256 maxFeePercentage = WAD * 1 / 100;   // 1%
        uint256 gasFee = 1 * WAD;                  // 1 DAI of gas refund
        uint256 expiry = block.timestamp;
        bytes32 signHash = getSignHash(
            guid,
            maxFeePercentage,
            gasFee,
            expiry
        );

        (uint8 v, bytes32 r, bytes32 s) = hevm.sign(sk, signHash);

        assertTrue(!_tryRelay(
            guid,
            "",     // Not testing OracleAuth signatures here
            maxFeePercentage,
            gasFee,
            expiry,
            v,
            r,
            s
        ));
    }
}
