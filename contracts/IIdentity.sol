// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IIdentity
 * @dev Minimal interface for ONCHAINID Identity contract
 * In production, use the full ONCHAINID implementation
 */
interface IIdentity {
    /**
     * @dev Returns a claim by ID
     * @param claimId The claim ID to query
     * @return topic The claim topic
     * @return scheme The signature scheme
     * @return issuer The claim issuer address
     * @return signature The claim signature
     * @return data The claim data
     * @return uri The claim URI
     */
    function getClaim(bytes32 claimId) external view returns (
        uint256 topic,
        uint256 scheme,
        address issuer,
        bytes memory signature,
        bytes memory data,
        string memory uri
    );

    /**
     * @dev Returns claim IDs by topic
     * @param topic The claim topic
     * @return claimIds Array of claim IDs
     */
    function getClaimIdsByTopic(uint256 topic) external view returns (bytes32[] memory claimIds);
}
