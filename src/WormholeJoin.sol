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

import "./WormholeGUID.sol";

interface VatLike {
    function dai(address) external view returns (uint256);
    function live() external view returns (uint256);
    function urns(bytes32, address) external view returns (uint256, uint256);
    function frob(bytes32, address, address, address, int256, int256) external;
    function hope(address) external;
    function move(address, address, uint256) external;
    function nope(address) external;
    function slip(bytes32, address, int256) external;
}

interface DaiJoinLike {
    function dai() external view returns (TokenLike);
    function exit(address, uint256) external;
    function join(address, uint256) external;
}

interface TokenLike {
    function approve(address, uint256) external;
}

interface WormholeFeesLike {
    function getFees(WormholeGUID calldata) external view returns (uint256);
}

// Primary control for extending Wormhole credit
contract WormholeJoin {
    mapping (address => uint256) public wards;  // Auth
    mapping (bytes32 => uint256) public line;   // Debt ceiling per source domain
    mapping (bytes32 =>  int256) public debt;   // Outstanding debt per source domain (can be negative if there is a lot of unclaimed amounts for a long time)
    mapping (bytes32 => uint256) public claim;  // Claimed debt per GUID

    address          public vow;
    DaiJoinLike      public daiJoin;
    WormholeFeesLike public wormholeFees;

    VatLike immutable public vat;
    bytes32 immutable public ilk;
    bytes32 immutable public domain;

    uint256 constant public RAY = 10 ** 27;

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, address data);
    event File(bytes32 indexed what, bytes32 indexed domain, uint256 data);
    event Mint(bytes32 indexed hashGUID, WormholeGUID wormholeGUID, address originalSender, uint256 maxFee);
    event Settle(bytes32 indexed sourceDomain, uint256 batchedDaiToFlush);

    constructor(address vat_, bytes32 ilk_, bytes32 domain_) {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
        vat = VatLike(vat_);
        ilk = ilk_;
        domain = domain_;
    }

    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x <= y ? x : y;
    }

    modifier auth {
        require(wards[msg.sender] == 1, "WormholeJoin/non-authed");
        _;
    }

    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    function file(bytes32 what, address data) external auth {
        if (what == "vow") {
            vow = data;
        }
        else if (what == "daiJoin") {
            vat.nope(address(daiJoin));
            daiJoin = DaiJoinLike(data);
            vat.hope(data);
            daiJoin.dai().approve(data, type(uint256).max);
        }
        else if (what == "wormholeFees") {
            wormholeFees = WormholeFeesLike(data);
        } else {
            revert("WormholeJoin/file-unrecognized-param");
        }
        emit File(what, data);
    }

    function file(bytes32 what, bytes32 domain_, uint256 data) external auth {
        if (what == "line") {
            line[domain_] = data;
        } else {
            revert("WormholeJoin/file-unrecognized-param");
        }
        emit File(what, domain_, data);
    }

    function mint(WormholeGUID calldata wormholeGUID, address originalSender, uint256 maxFee) external auth {
        require(wormholeGUID.targetDomain == domain, "WormholeJoin/incorrect-domain");
        require(wormholeGUID.operator == originalSender, "WormholeJoin/incorrect-operator");
        bool vatLive = vat.live() == 1;
        uint256 fee = vatLive ? wormholeFees.getFees(wormholeGUID) : 0;
        require(fee <= maxFee, "WormholeJoin/max-fee-exceed");

        // TODO: Review if we want to also compare to the ilk line
        // This will only be necessary if the sum of all the sourceDomain ceilings is greater than the ilk line
        // We might also want to potentially check the global Line.
        uint256 line_ = vatLive ? line[wormholeGUID.sourceDomain] : 0;
        int256  debt_ = debt[wormholeGUID.sourceDomain];
        require(line_ <= 2 ** 255, "WormholeJoin/overflow");
        require(int256(line_) > debt_, "WormholeJoin/non-available");
        uint256 available = uint256(int256(line_) - debt_);

        bytes32 hashGUID = keccak256(
            abi.encodePacked(
                wormholeGUID.sourceDomain,
                wormholeGUID.targetDomain,
                wormholeGUID.receiver,
                wormholeGUID.operator,
                wormholeGUID.amount,
                wormholeGUID.nonce,
                wormholeGUID.timestamp
            )
        );
        uint256 amtToTake = min(
                                wormholeGUID.amount - claim[hashGUID],
                                available
                            );
        require(amtToTake <= 2 ** 255 - 1, "WormholeJoin/overflow");

        debt[wormholeGUID.sourceDomain] += int256(amtToTake);
        claim[hashGUID] += amtToTake;

        if (debt_ >= 0 || uint256(-debt_) < amtToTake) {
            uint256 amtToGenerate = debt_ < 0 ? amtToTake - uint256(-debt_) : amtToTake;
            vat.slip(ilk, address(this), int256(amtToGenerate));
            vat.frob(ilk, address(this), address(this), address(this), int256(amtToGenerate), int256(amtToGenerate));
        }
        daiJoin.exit(wormholeGUID.receiver, amtToTake - fee);

        if (fee > 0) {
            vat.move(address(this), vow, fee * RAY);
        }

        emit Mint(hashGUID, wormholeGUID, originalSender, maxFee);
    }

    // TODO: define if we want to change to pull model instead of push
    // (this function expects to have received batchedDaiToFlush erc20 DAI before settle being called)
    function settle(bytes32 sourceDomain, uint256 batchedDaiToFlush) external auth {
        require(batchedDaiToFlush <= 2 ** 255, "WormholeJoin/overflow");
        daiJoin.join(address(this), batchedDaiToFlush);
        if (vat.live() == 1) {
            (, uint256 art) = vat.urns(ilk, address(this)); // rate == RAY => normalized debt == actual debt
            uint256 amtToPayBack = min(batchedDaiToFlush, art);
            vat.frob(ilk, address(this), address(this), address(this), -int256(amtToPayBack), -int256(amtToPayBack));
            vat.slip(ilk, address(this), -int256(amtToPayBack));
        }
        debt[sourceDomain] -= int256(batchedDaiToFlush);
        emit Settle(sourceDomain, batchedDaiToFlush);
    }
}
