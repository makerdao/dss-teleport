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

// Calculate fees for a given Wormhole GUID
interface WormholeFees {
    /**
    * @dev Return fee for particular wormhole. It should return 0 for wormholes that are being slow withdrawn. 
    * note: We define slow withdrawal as wormhole older than x. x has to be enough to finalize flush (not wormhole itself).
    * @param wormholeGUID Struct which contains the whole wormhole data
    * @param line Debt ceiling
    * @param debt Current debt
    * @param pending Amount left to withdraw
    * @param amtToTake Amount to take. Can be less or equal to wormholeGUID.amount b/c of debt ceiling or because it is pending
    **/
    function getFee(
        WormholeGUID calldata wormholeGUID, uint256 line, int256 debt, uint256 pending, uint256 amtToTake
    ) external view returns (uint256 fees);
}
