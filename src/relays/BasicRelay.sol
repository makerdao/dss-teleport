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

import "../TeleportGUID.sol";

interface DaiJoinLike {
    function dai() external view returns (TokenLike);
    function exit(address, uint256) external;
    function join(address, uint256) external;
}

interface TokenLike {
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
}

interface TeleportOracleAuthLike {
    function requestMint(
        TeleportGUID calldata teleportGUID,
        bytes calldata signatures,
        uint256 maxFeePercentage,
        uint256 operatorFee
    ) external returns (uint256 postFeeAmount, uint256 totalFee);
    function teleportJoin() external view returns (TeleportJoinLike);
}

interface TeleportJoinLike {
    function teleports(bytes32 hashGUID) external view returns (bool, uint248);
}

// Relay messages automatically on the target domain
// User provides gasFee which is paid to the msg.sender
contract BasicRelay {

    DaiJoinLike            public immutable daiJoin;
    TokenLike              public immutable dai;
    TeleportOracleAuthLike public immutable oracleAuth;
    TeleportJoinLike       public immutable teleportJoin;

    constructor(address _oracleAuth, address _daiJoin) {
        oracleAuth = TeleportOracleAuthLike(_oracleAuth);
        daiJoin = DaiJoinLike(_daiJoin);
        dai = daiJoin.dai();
        teleportJoin = oracleAuth.teleportJoin();
    }

    /**
     * @notice Gasless relay for the Oracle fast path
     * The final signature is ABI-encoded `hashGUID`, `maxFeePercentage`, `gasFee`, `expiry`
     * @param teleportGUID The teleport GUID
     * @param signatures The byte array of concatenated signatures ordered by increasing signer addresses.
     * Each signature is {bytes32 r}{bytes32 s}{uint8 v}
     * @param maxFeePercentage Max percentage of the withdrawn amount (in WAD) to be paid as fee (e.g 1% = 0.01 * WAD)
     * @param gasFee DAI gas fee (in WAD)
     * @param expiry Maximum time for when the query is valid
     * @param v Part of ECDSA signature
     * @param r Part of ECDSA signature
     * @param s Part of ECDSA signature
     */
    function relay(
        TeleportGUID calldata teleportGUID,
        bytes calldata signatures,
        uint256 maxFeePercentage,
        uint256 gasFee,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(block.timestamp <= expiry, "BasicRelay/expired");
        bytes32 signHash = keccak256(abi.encodePacked(
            "\x19Ethereum Signed Message:\n32", 
            keccak256(abi.encode(getGUIDHash(teleportGUID), maxFeePercentage, gasFee, expiry))
        ));
        address recovered = ecrecover(signHash, v, r, s);
        require(bytes32ToAddress(teleportGUID.receiver) == recovered, "BasicRelay/invalid-signature");

        // Initiate mint and mark the teleport as done
        (uint256 postFeeAmount, uint256 totalFee) = oracleAuth.requestMint(teleportGUID, signatures, maxFeePercentage, gasFee);
        require(postFeeAmount + totalFee == teleportGUID.amount, "BasicRelay/partial-mint-disallowed");

        // Send the gas fee to the relayer
        dai.transfer(msg.sender, gasFee);
    }

}
