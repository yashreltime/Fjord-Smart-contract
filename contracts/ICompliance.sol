// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ICompliance
 * @dev Interface for ERC-3643 Compliance contract
 */
interface ICompliance {
    /**
     * @dev Checks if a transfer is compliant
     * @param from Sender address
     * @param to Recipient address
     * @param amount Amount to transfer
     * @return true if transfer is compliant
     */
    function canTransfer(address from, address to, uint256 amount) external view returns (bool);

    /**
     * @dev Called when tokens are transferred
     * @param from Sender address
     * @param to Recipient address
     * @param amount Amount transferred
     */
    function transferred(address from, address to, uint256 amount) external view;

    /**
     * @dev Called when tokens are created/minted
     * @param to Recipient address
     * @param amount Amount minted
     */
    function created(address to, uint256 amount) external view;

    /**
     * @dev Called when tokens are destroyed/burned
     * @param from Sender address
     * @param amount Amount burned
     */
    function destroyed(address from, uint256 amount) external view;

    /**
     * @dev Returns the token contract address
     */
    function getTokenBound() external view returns (address);

    /**
     * @dev Binds the compliance contract to a token
     * @param token Token contract address
     */
    function bindToken(address token) external;

    /**
     * @dev Unbinds the compliance contract from the token
     */
    function unbindToken() external;
}
