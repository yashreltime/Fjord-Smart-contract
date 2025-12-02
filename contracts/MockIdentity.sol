// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IIdentity.sol";

/**
 * @title MockIdentity
 * @dev Mock implementation of IIdentity for testing purposes
 * In production, use the full ONCHAINID implementation
 */
contract MockIdentity is IIdentity {
    mapping(bytes32 => Claim) private claims;
    mapping(uint256 => bytes32[]) private claimsByTopic;

    struct Claim {
        uint256 topic;
        uint256 scheme;
        address issuer;
        bytes signature;
        bytes data;
        string uri;
    }

    /**
     * @dev Add a claim for testing
     */
    function addClaim(
        uint256 topic,
        uint256 scheme,
        address issuer,
        bytes memory signature,
        bytes memory data,
        string memory uri
    ) external returns (bytes32) {
        bytes32 claimId = keccak256(abi.encode(issuer, topic));

        claims[claimId] = Claim({
            topic: topic,
            scheme: scheme,
            issuer: issuer,
            signature: signature,
            data: data,
            uri: uri
        });

        claimsByTopic[topic].push(claimId);

        return claimId;
    }

    /**
     * @dev Get claim by ID
     */
    function getClaim(bytes32 claimId) external view override returns (
        uint256 topic,
        uint256 scheme,
        address issuer,
        bytes memory signature,
        bytes memory data,
        string memory uri
    ) {
        Claim storage claim = claims[claimId];
        return (
            claim.topic,
            claim.scheme,
            claim.issuer,
            claim.signature,
            claim.data,
            claim.uri
        );
    }

    /**
     * @dev Get claim IDs by topic
     */
    function getClaimIdsByTopic(uint256 topic) external view override returns (bytes32[] memory) {
        return claimsByTopic[topic];
    }
}
