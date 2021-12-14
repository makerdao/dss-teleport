pragma solidity 0.8.9;

contract Auxiliar {
    function getGUIDHash(
        bytes32 sourceDomain,
        bytes32 targetDomain,
        address receiver,
        address operator,
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
}
