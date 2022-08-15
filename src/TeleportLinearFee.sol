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

import {TeleportFees} from "./TeleportFees.sol";
import {TeleportGUID} from "./TeleportGUID.sol";

contract TeleportLinearFee is TeleportFees {
    uint256 immutable public fee;
    uint256 immutable public ttl;

    uint256 constant public WAD = 10 ** 18;

    /**
    * @param _fee Fee percentage in WAD (e.g 1% fee = 0.01 * WAD)
    * @param _ttl Time in seconds to finalize flush (not teleport)
    **/
    constructor(uint256 _fee, uint256 _ttl) {
        fee = _fee;
        ttl = _ttl;
    }

    function getFee(TeleportGUID calldata guid, uint256, int256, uint256, uint256 amtToTake) override external view returns (uint256) {
        // is slow withdrawal?
        if (block.timestamp >= uint256(guid.timestamp) + ttl) {
            return 0;
        }

        return fee * amtToTake / WAD;
    }
}
