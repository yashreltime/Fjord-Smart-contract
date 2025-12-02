// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./ICompliance.sol";

/**
 * @title Compliance
 * @dev ERC-3643 compliant Compliance contract for Phase 1 (Soul-bound tokens)
 *
 * Phase 1 Features:
 * - Transfers disabled (soul-bound behavior)
 * - Only minting and burning allowed
 * - Can be upgraded in future phases to enable secondary trading
 *
 * For Phase 2+, this can be extended to include:
 * - Country-based restrictions
 * - Investor limits
 * - Token holding caps
 * - Time-based locks
 */
contract Compliance is ICompliance, Ownable {
    // The token contract this compliance is bound to
    address private _tokenBound;

    // Phase 1 configuration - transfers disabled
    bool public transfersEnabled;

    // Events
    event TokenBound(address indexed token);
    event TokenUnbound(address indexed token);
    event TransfersEnabled(bool enabled);

    constructor(address initialOwner) {
        transfersEnabled = false; // Phase 1: soul-bound tokens
        _transferOwnership(initialOwner);
    }

    /**
     * @dev Modifier to check if caller is the bound token
     */
    modifier onlyToken() {
        require(msg.sender == _tokenBound, "Compliance: caller is not the bound token");
        _;
    }

    /**
     * @dev Check if a transfer is compliant
     * Phase 1: Only minting (from=0) and burning (to=0) are allowed
     * @param from Sender address
     * @param to Recipient address
     * @param amount Amount to transfer
     * @return true if transfer is compliant
     */
    function canTransfer(
        address from,
        address to,
        uint256 amount
    ) external view override returns (bool) {
        // Prevent unused variable warnings
        amount;

        // Phase 1: Soul-bound behavior
        // Allow minting (from == address(0))
        if (from == address(0)) {
            return true;
        }

        // Allow burning (to == address(0))
        if (to == address(0)) {
            return true;
        }

        // Phase 1: Block all other transfers
        if (!transfersEnabled) {
            return false;
        }

        // Future phases: Add additional compliance checks here
        // - Country restrictions
        // - Investor limits
        // - Holding caps
        // - Time locks

        return true;
    }

    /**
     * @dev Called when tokens are transferred
     * @param from Sender address
     * @param to Recipient address
     * @param amount Amount transferred
     */
    function transferred(
        address from,
        address to,
        uint256 amount
    ) external view override onlyToken {
        // Compliance state tracking can be added here
        // For now, just verify the call is from the token
        // Prevent unused variable warnings
        from;
        to;
        amount;
    }

    /**
     * @dev Called when tokens are created/minted
     * @param to Recipient address
     * @param amount Amount minted
     */
    function created(
        address to,
        uint256 amount
    ) external view override onlyToken {
        // Track minting for compliance reporting
        // Prevent unused variable warnings
        to;
        amount;
    }

    /**
     * @dev Called when tokens are destroyed/burned
     * @param from Sender address
     * @param amount Amount burned
     */
    function destroyed(
        address from,
        uint256 amount
    ) external view override onlyToken {
        // Track burning for compliance reporting
        // Prevent unused variable warnings
        from;
        amount;
    }

    /**
     * @dev Returns the token contract address
     * @return The token contract address
     */
    function getTokenBound() external view override returns (address) {
        return _tokenBound;
    }

    /**
     * @dev Binds the compliance contract to a token
     * @param token Token contract address
     */
    function bindToken(address token) external override onlyOwner {
        require(token != address(0), "Compliance: token is zero address");
        require(_tokenBound == address(0), "Compliance: token already bound");

        _tokenBound = token;
        emit TokenBound(token);
    }

    /**
     * @dev Unbinds the compliance contract from the token
     */
    function unbindToken() external override onlyOwner {
        require(_tokenBound != address(0), "Compliance: no token bound");

        address previousToken = _tokenBound;
        _tokenBound = address(0);
        emit TokenUnbound(previousToken);
    }

    /**
     * @dev Enable or disable transfers (for future phases)
     * @param enabled Whether to enable transfers
     */
    function setTransfersEnabled(bool enabled) external onlyOwner {
        transfersEnabled = enabled;
        emit TransfersEnabled(enabled);
    }
}
