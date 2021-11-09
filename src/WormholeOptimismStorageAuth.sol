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

interface WormholeJoinLike {
    function mint(WormholeGUID calldata guid, address sender, uint256 maxFee) external;
}

interface OptimismStorageLike {
    function validate(bytes calldata merkleProof) external view returns (bytes memory);
}

// Authenticate against Optimism Storage Merkle Root
// Only works after the fraud proof delay
contract WormholeOptimismStorageAuth {

    WormholeJoinLike public immutable join;
    OptimismStorageLike public immutable store;

    constructor(address _join, address _store) {
        join = WormholeJoinLike(_join);
        store = OptimismStorageLike(_store);
    }

    function attest(WormholeGUID calldata guid, uint256 maxFee, bytes calldata merkleProof) external {
        // TODO firm up this interface
        store.validate(attestations);

        join.mint(guid, msg.sender, maxFee);
    }

}
