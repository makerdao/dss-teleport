pragma solidity 0.8.9;

import "../src/WormholeGUID.sol";

interface OracleLike {
    function signers(address) external view returns (uint256);
}

contract Auxiliar {
    OracleLike public oracle;

    function getGUIDHash(WormholeGUID memory wormholeGUID) external pure returns (bytes32 guidHash) {
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

    function getSignHash(WormholeGUID memory wormholeGUID) public pure returns (bytes32 signHash) {
        signHash = keccak256(abi.encodePacked(
            "\x19Ethereum Signed Message:\n32",
            getGUIDHash(wormholeGUID)
        ));
    }

    function bytes32ToAddress(bytes32 addr) external pure returns (address) {
        return address(uint160(uint256(addr)));
    }

    function callEcrecover(
        bytes32 digest,
        uint256 v,
        bytes32 r,
        bytes32 s
    ) public pure returns (address signer) {
        signer = ecrecover(digest, uint8(v), r, s);
    }

    function splitSignature(bytes calldata signatures, uint256 index) public pure returns (uint8 v, bytes32 r, bytes32 s) {
        uint256 start;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            start := mul(0x41, index)
            r := calldataload(add(signatures.offset, start))
            s := calldataload(add(signatures.offset, add(0x20, start)))
            v := and(calldataload(add(signatures.offset, add(0x21, start))), 0xff)
        }
    }

    function processUpToIndex(
        bytes32 signHash,
        bytes calldata signatures,
        uint256 index
    ) external view returns (
        uint256 numProcessed,
        uint256 numValid
    ) {
        uint8 v;
        bytes32 r;
        bytes32 s;
        address lastSigner;
        for (uint256 i; i < index;) {
            (v, r, s) = splitSignature(signatures, i);
            if (v != 27 && v != 28) break;
            address recovered = ecrecover(signHash, v, r, s);
            if (recovered <= lastSigner) break;
            lastSigner = recovered;
            if (oracle.signers(recovered) == 1) {
                unchecked { numValid += 1; }
            }
            unchecked { i++; }
        }
    }

    function checkMalformedArray(address[] memory) external pure {}
}