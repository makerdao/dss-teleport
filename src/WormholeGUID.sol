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

// Standard Maker Wormhole GUID
struct WormholeGUID {
    bytes32 sourceDomain;
    bytes32 targetDomain;
    address receiver;
    address operator;
    uint128 amount;
    uint80 nonce;
    uint48 timestamp;
}

// solhint-disable-next-line func-visibility
function getGUIDHash(WormholeGUID memory wormholeGUID) pure returns (bytes32 guidHash) {
    guidHash = keccak256(abi.encode(
        wormholeGUID.sourceDomain,
        wormholeGUID.targetDomain,
        wormholeGUID.receiver,
        wormholeGUID.operator,
        wormholeGUID.amount,
        wormholeGUID.nonce,
        wormholeGUID.timestamp
    ));
}
