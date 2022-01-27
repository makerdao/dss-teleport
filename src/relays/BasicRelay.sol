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

import "../WormholeGUID.sol";

interface DaiJoinLike {
    function dai() external view returns (TokenLike);
    function exit(address, uint256) external;
    function join(address, uint256) external;
}

interface TokenLike {
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
}

interface WormholeOracleAuthLike {
    function requestMint(WormholeGUID calldata wormholeGUID, bytes calldata signatures, uint256 maxFeePercentage, uint256 operatorFee) external;
    function wormholeJoin() external view returns (WormholeJoinLike);
}
interface WormholeJoinLike {
    function wormholes(bytes32 hashGUID) external view returns (bool, uint248);
}

// Relay messages automatically on the target domain
// User provides gasFee which is paid to the msg.sender
contract BasicRelay {

    DaiJoinLike            public immutable daiJoin;
    TokenLike              public immutable dai;
    WormholeOracleAuthLike public immutable oracleAuth;
    WormholeJoinLike       public immutable wormholeJoin;

    constructor(address _oracleAuth, address _daiJoin) {
        oracleAuth = WormholeOracleAuthLike(_oracleAuth);
        daiJoin = DaiJoinLike(_daiJoin);
        dai = daiJoin.dai();
        wormholeJoin = oracleAuth.wormholeJoin();
    }

    function relay(
        WormholeGUID calldata wormholeGUID,
        bytes calldata signatures,
        address receiver,
        uint256 maxFeePercentage,
        uint256 gasFee,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(block.timestamp < expiry, "BasicRelay/expired");
        bytes32 hashGUID = getGUIDHash(wormholeGUID);
        bytes32 userHash = keccak256(abi.encode(hashGUID, receiver, maxFeePercentage, gasFee, expiry));
        address recovered = ecrecover(userHash, v, r, s);
        require(bytes32ToAddress(wormholeGUID.operator) == recovered, "BasicRelay/invalid-signature");

        // Initiate mint
        // FIXME This is not great, would prefer requestMint to say how much was sent (minus fee)
        uint256 prevBal = dai.balanceOf(address(this));
        oracleAuth.requestMint(wormholeGUID, signatures, maxFeePercentage, 0);
        (,uint248 pending) = wormholeJoin.wormholes(hashGUID);
        require(pending == 0, "BasicRelay/partial-mint-disallowed");

        // Send the gas fee to the relayer
        dai.transfer(msg.sender, gasFee);

        // Send the rest to the end user
        dai.transfer(recovered, dai.balanceOf(address(this)) - prevBal);
    }

}
