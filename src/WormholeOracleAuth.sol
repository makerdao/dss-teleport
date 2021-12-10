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
    function registerWormholeAndWithdraw(WormholeGUID calldata wormholeGUID, uint256 maxFee) external;
}

// WormholeOracleAuth provides user authentication for WormholeJoin, by means of Maker Oracle Attestations
contract WormholeOracleAuth {

    mapping (address => uint256) public wards;   // Auth
    mapping (address => bool)    public signers; // Oracle feeds

    WormholeJoinLike immutable public wormholeJoin;

    uint256 public threshold;

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, bytes32 data);
    event SignersAdded(address[] signers);
    event SignersRemoved(address[] signers);

    modifier auth {
        require(wards[msg.sender] == 1, "WormholeOracleAuth/non-authed");
        _;
    }

    constructor(address wormholeJoin_) {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
        wormholeJoin = WormholeJoinLike(wormholeJoin_);
    }

    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    function file(bytes32 what, bytes32 data) external auth {
        if (what == "threshold") {
            threshold = uint256(data);
        } else {
            revert("WormholeOracleAuth/file-unrecognized-param");
        }
        emit File(what, data);
    }

    function addSigners(address[] calldata signers_) external auth {
        for(uint i; i < signers_.length; i++) {
            signers[signers_[i]] = true;
        }
        emit SignersAdded(signers_);
    }

    function removeSigners(address[] calldata signers_) external auth {
        for(uint i; i < signers_.length; i++) {
            signers[signers_[i]] = false;
        }
        emit SignersRemoved(signers_);
    }

    /**
     * @notice Verify oracle signatures and call WormholeJoin to mint DAI if the signatures are valid
     * @param wormholeGUID The wormhole GUID to register
     * @param signatures The byte array of concatenated signatures ordered by increasing signer addresses.
     * Each signature is {bytes32 r}{bytes32 s}{uint8 v}
     * @param maxFee The maximum amount of fees to pay for the minting of DAI
     */
    function requestMint(WormholeGUID calldata wormholeGUID, bytes calldata signatures, uint256 maxFee) external {
        require(wormholeGUID.operator == msg.sender, "WormholeOracleAuth/not-operator");
        require(isValid(getSignHash(wormholeGUID), signatures, threshold), "WormholeOracleAuth/not-enough-valid-sig");
        wormholeJoin.registerWormholeAndWithdraw(wormholeGUID, maxFee);
    }

    /**
     * @notice Returns true if `signatures` contains at least `threshold_` valid signatures of a given `signHash`
     * @param signHash The signed message hash
     * @param signatures The byte array of concatenated signatures ordered by increasing signer addresses.
     * Each signature is {bytes32 r}{bytes32 s}{uint8 v}
     * @param threshold_ The minimum number of valid signatures required for the method to return true
     */
    function isValid(bytes32 signHash, bytes memory signatures, uint threshold_) public view returns (bool valid) {
        uint256 count = signatures.length / 65;
        require(count >= threshold_, "WormholeOracleAuth/not-enough-sig");

        uint8 v;
        bytes32 r;
        bytes32 s;
        uint256 numValid;
        address lastSigner;
        for (uint256 i; i < count; i++) {
            (v,r,s) = splitSignature(signatures, i);
            address recovered = ecrecover(signHash, v, r, s);
            require(recovered > lastSigner, "WormholeOracleAuth/bad-sig-order"); // make sure signers are different
            lastSigner = recovered;
            if (signers[recovered]) {
                numValid += 1;
                if (numValid >= threshold_) {
                    return true;
                }
            }
        }
    }

    // TODO: this is NOT following the format proposed in 
    // https://clever-salsa-671.notion.site/L2-Fast-Bridge-Architecture-rev-2-wormhole-0ba5074adcf749e791a0576c130d7534
    // Need to confirm with the Oracle CU that the below format is acceptable
    function getSignHash(WormholeGUID memory wormholeGUID) public pure returns (bytes32 signHash) {
        signHash = keccak256(abi.encodePacked(
            "\x19Ethereum Signed Message:\n32",
            getGUIDHash(wormholeGUID)
        ));
    }

    /**
     * @notice Parses the signatures and extract (r, s, v) for a signature at a given index.
     * @param signatures concatenated signatures. Each signature is {bytes32 r}{bytes32 s}{uint8 v}
     * @param index which signature to read (0, 1, 2, ...)
     */
    function splitSignature(bytes memory signatures, uint256 index) internal pure returns (uint8 v, bytes32 r, bytes32 s) {
        // we jump 32 (0x20) as the first slot of bytes contains the length
        // we jump 65 (0x41) per signature
        // for v we load 32 bytes ending with v (the first 31 come from s) then apply a mask
        // solhint-disable-next-line no-inline-assembly
        assembly {
            r := mload(add(signatures, add(0x20, mul(0x41, index))))
            s := mload(add(signatures, add(0x40, mul(0x41, index))))
            v := and(mload(add(signatures, add(0x41, mul(0x41, index)))), 0xff)
        }
        require(v == 27 || v == 28, "WormholeOracleAuth/bad-v");
    }
}
