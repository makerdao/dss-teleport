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
}
