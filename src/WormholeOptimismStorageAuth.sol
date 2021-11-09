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
import "./utils/Lib_SecureMerkleTrie.sol";
import "./utils/Lib_RLPReader.sol";

struct ChainBatchHeader {
    uint256 batchIndex;
    bytes32 batchRoot;
    uint256 batchSize;
    uint256 prevTotalElements;
    bytes extraData;
}

struct ChainInclusionProof {
    uint256 index;
    bytes32[] siblings;
}

struct L2MessageInclusionProof {
    bytes32 stateRoot;
    ChainBatchHeader stateRootBatchHeader;
    ChainInclusionProof stateRootProof;
    bytes stateTrieWitness;
    bytes storageTrieWitness;
}

struct EVMAccount {
    uint256 nonce;
    uint256 balance;
    bytes32 storageRoot;
    bytes32 codeHash;
}

interface WormholeJoinLike {
    function mint(WormholeGUID calldata guid, address sender, uint256 maxFee) external;
}

interface OptimismStateCommitmentChainLike {
    function insideFraudProofWindow(tuple _batchHeader) external view returns (bool);
    function verifyStateCommitment(bytes32 _element, ChainBatchHeader calldata _batchHeader, ChainInclusionProof calldata _proof) external view returns (bool);
}

// Authenticate against Optimism Storage Merkle Root
// Only works after the fraud proof delay
contract WormholeOptimismStorageAuth {

    WormholeJoinLike public immutable join;
    OptimismStateCommitmentChainLike public immutable scc;
    address public immutable l2bridge;

    constructor(address _join, address _scc, address _l2bridge) {
        join = WormholeJoinLike(_join);
        scc = OptimismStateCommitmentChainLike(_scc);
        l2bridge = _l2bridge;
    }

    /**
     * @notice Decodes an RLP-encoded account state into a useful struct.
     * @param _encoded RLP-encoded account state.
     * @return Account state struct.
     */
    function decodeEVMAccount(
        bytes memory _encoded
    )
        internal
        pure
        returns (
            EVMAccount memory
        )
    {
        Lib_RLPReader.RLPItem[] memory accountState = Lib_RLPReader.readList(_encoded);

        return EVMAccount({
            nonce: Lib_RLPReader.readUint256(accountState[0]),
            balance: Lib_RLPReader.readUint256(accountState[1]),
            storageRoot: Lib_RLPReader.readBytes32(accountState[2]),
            codeHash: Lib_RLPReader.readBytes32(accountState[3])
        });
    }

    /**
     * Verifies that the storage proof within an inclusion proof is valid.
     * @param wormholeGUIDHash Encoded message calldata.
     * @param proof Message inclusion proof.
     * @return Whether or not the provided proof is valid.
     */
    function verifyStorageProof(
        bytes32 wormholeGUIDHash,
        L2MessageInclusionProof memory proof
    )
        internal
        view
        returns (
            bool
        )
    {
        // TODO - verify this is correct against l2 bridge storage
        bytes32 storageKey = keccak256(
            abi.encodePacked(
                keccak256(
                    abi.encodePacked(
                        wormholeGUIDHash,
                        l2bridge
                    )
                ),
                uint256(0)
            )
        );

        (
            bool exists,
            bytes memory encodedMessagePassingAccount
        ) = Lib_SecureMerkleTrie.get(
            abi.encodePacked(Lib_PredeployAddresses.L2_TO_L1_MESSAGE_PASSER),
            _proof.stateTrieWitness,
            _proof.stateRoot
        );

        require(
            exists == true,
            "Message passing predeploy has not been initialized or invalid proof provided."
        );

        EVMAccount memory account = decodeEVMAccount(
            encodedMessagePassingAccount
        );

        return Lib_SecureMerkleTrie.verifyInclusionProof(
            abi.encodePacked(storageKey),
            abi.encodePacked(uint8(1)),
            _proof.storageTrieWitness,
            account.storageRoot
        );
    }

    function prove(WormholeGUID calldata guid, uint256 maxFee, L2MessageInclusionProof calldata proof) external {
        // Optimism State Inclusion Proof
        require(
            ovmStateCommitmentChain.insideFraudProofWindow(proof.stateRootBatchHeader) == false
            && ovmStateCommitmentChain.verifyStateCommitment(
                proof.stateRoot,
                proof.stateRootBatchHeader,
                proof.stateRootProof
            )
        , "WormholeOptimismStorageAuth/state-inclusion");

        // Validate storage was set on L2 bridge
        require(
            verifyStorageProof(guid.getHash(), proof)
        , "WormholeOptimismStorageAuth/storage-inclusion");

        join.mint(guid, msg.sender, maxFee);
    }

}
