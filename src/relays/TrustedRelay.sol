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

pragma solidity 0.8.13;

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
    function requestMint(
        WormholeGUID calldata wormholeGUID,
        bytes calldata signatures,
        uint256 maxFeePercentage,
        uint256 operatorFee
    ) external returns (uint256 postFeeAmount, uint256 totalFee);
    function wormholeJoin() external view returns (WormholeJoinLike);
}

interface WormholeJoinLike {
    function wormholes(bytes32 hashGUID) external view returns (bool, uint248);
}

interface DsValueLike {
    function peek() external view returns (bytes32, bool);
}

// Relay messages automatically on the target domain
// User provides gasFee which is paid to the msg.sender
// Relay requests are signed by a trusted third-party (typically a backend orchestrating the withdrawal on behalf of the user)
contract TrustedRelay {

    mapping (address => uint256) public wards;   // Auth
    mapping (address => uint256) public signers; // Trusted signers
    
    DaiJoinLike            public immutable daiJoin;
    TokenLike              public immutable dai;
    WormholeOracleAuthLike public immutable oracleAuth;
    WormholeJoinLike       public immutable wormholeJoin;
    DsValueLike            public immutable ethPriceOracle;
    uint256                public immutable gasMargin; // in BPS (e.g 150% = 15000)

    uint256 constant public WAD_BPS = 10 ** 22; // WAD * BPS = 10^18 * 10^4

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event SignersAdded(address[] signers);
    event SignersRemoved(address[] signers);

    modifier auth {
        require(wards[msg.sender] == 1, "TrustedRelay/non-authed");
        _;
    }

    constructor(address _oracleAuth, address _daiJoin, address _ethPriceOracle, uint256 _gasMargin) {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
        oracleAuth = WormholeOracleAuthLike(_oracleAuth);
        daiJoin = DaiJoinLike(_daiJoin);
        dai = daiJoin.dai();
        wormholeJoin = oracleAuth.wormholeJoin();
        ethPriceOracle = DsValueLike(_ethPriceOracle);
        gasMargin = _gasMargin;
    }

    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    function addSigners(address[] calldata signers_) external auth {
        for(uint256 i; i < signers_.length; i++) {
            signers[signers_[i]] = 1;
        }
        emit SignersAdded(signers_);
    }

    function removeSigners(address[] calldata signers_) external auth {
        for(uint256 i; i < signers_.length; i++) {
            signers[signers_[i]] = 0;
        }
        emit SignersRemoved(signers_);
    }

    /**
     * @notice Gasless relay for the Oracle fast path
     * The final signature is ABI-encoded `hashGUID`, `maxFeePercentage`, `gasFee`, `expiry`
     * @param wormholeGUID The wormhole GUID
     * @param signatures The byte array of concatenated signatures ordered by increasing signer addresses.
     * Each signature is {bytes32 r}{bytes32 s}{uint8 v}
     * @param maxFeePercentage Max percentage of the withdrawn amount (in WAD) to be paid as fee (e.g 1% = 0.01 * WAD)
     * @param gasFee DAI gas fee (in WAD)
     * @param expiry Maximum time for when the query is valid
     * @param v Part of ECDSA signature
     * @param r Part of ECDSA signature
     * @param s Part of ECDSA signature
     * @param to (optional) The address of an external contract to call after requesting the L1 DAI (address(0) if unused)
     * @param data (optional) The calldata to use for the call to the aforementionned external contract
     */
    function relay(
        WormholeGUID calldata wormholeGUID,
        bytes calldata signatures,
        uint256 maxFeePercentage,
        uint256 gasFee,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s,
        address to,
        bytes calldata data
    ) external {
        uint256 startGas = gasleft();

        // Withdraw the L1 DAI to the receiver
        requestMint(wormholeGUID, signatures, maxFeePercentage, gasFee, expiry, v, r, s);

        // Send the gas fee to the relayer
        dai.transfer(msg.sender, gasFee);

        // Optionally execute an external call
        if(to != address(0)) {
            (bool success,) = to.call(data);
            if (!success) {
                // solhint-disable-next-line no-inline-assembly
                assembly {
                    returndatacopy(0, 0, returndatasize())
                    revert(0, returndatasize())
                }
            }
        }

        // If the eth price oracle is enabled, use its value to check that gasFee is within an allowable margin
        (bytes32 ethPrice, bool ok) = ethPriceOracle.peek();
        require(!ok || gasFee * WAD_BPS <= uint256(ethPrice) * gasMargin * gasprice() * (startGas - gasleft()), "TrustedRelay/excessive-gas-fee");
    }

    function requestMint(
        WormholeGUID calldata wormholeGUID,
        bytes calldata signatures,
        uint256 maxFeePercentage,
        uint256 gasFee,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal {
        require(block.timestamp <= expiry, "TrustedRelay/expired");
        bytes32 signHash = keccak256(abi.encodePacked(
            "\x19Ethereum Signed Message:\n32", 
            keccak256(abi.encode(getGUIDHash(wormholeGUID), maxFeePercentage, gasFee, expiry))
        ));
        address recovered = ecrecover(signHash, v, r, s);
        require(signers[recovered] == 1 || bytes32ToAddress(wormholeGUID.receiver) == recovered, "TrustedRelay/invalid-signature");

        // Initiate mint and mark the wormhole as done
        (uint256 postFeeAmount, uint256 totalFee) = oracleAuth.requestMint(wormholeGUID, signatures, maxFeePercentage, gasFee);
        require(postFeeAmount + totalFee == wormholeGUID.amount, "TrustedRelay/partial-mint-disallowed");
    }

    function gasprice() internal virtual view returns (uint256) {
        return tx.gasprice;
    }

}
