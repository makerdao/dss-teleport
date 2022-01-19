pragma solidity 0.8.9;

contract Auxiliar {
    function getGUIDHash(
        bytes32 sourceDomain,
        bytes32 targetDomain,
        bytes32 receiver,
        bytes32 operator,
        uint128 amount,
        uint80 nonce,
        uint48 timestamp
    ) external pure returns (bytes32 guidHash) {
        guidHash = keccak256(abi.encode(
            sourceDomain,
            targetDomain,
            receiver,
            operator,
            amount,
            nonce,
            timestamp
        ));
    }

    // solhint-disable-next-line func-visibility
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

    function splitSignature(bytes memory signatures, uint256 index) internal pure returns (uint8 v, bytes32 r, bytes32 s) {
        assembly {
            r := mload(add(signatures, add(0x20, mul(0x41, index))))
            s := mload(add(signatures, add(0x40, mul(0x41, index))))
            v := and(mload(add(signatures, add(0x41, mul(0x41, index)))), 0xff)
        }
    }

    function getNumValid(address target, bytes32 signHash, bytes memory signatures) external view returns (uint256 numValid) {
        uint256 count = signatures.length / 65;

        uint8 v;
        bytes32 r;
        bytes32 s;
        address lastSigner;
        for (uint256 i; i < count;) {
            (v, r, s) = splitSignature(signatures, i);
            if (v != 27 && v != 28) break;
            address recovered = ecrecover(signHash, v, r, s);
            if (recovered <= lastSigner) break;
            lastSigner = recovered;
            if (OracleLike(target).signers(recovered) == 1) {
                unchecked { numValid += 1; }
            }
            unchecked { i++; }
        }
    }
}

interface OracleLike {
    function signers(address) external view returns (uint256);
}
