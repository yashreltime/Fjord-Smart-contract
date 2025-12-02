// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./IIdentity.sol";

/**
 * @title IdentityRegistry
 * @dev ERC-3643 compliant Identity Registry for investor KYC/AML verification
 *
 * Features:
 * - Maps wallet addresses to identity contracts
 * - Tracks verification status for KYC/AML compliance
 * - Stores investor country codes (ISO-3166)
 * - Agent-based management for registration
 * - Batch operations support
 */
contract IdentityRegistry is AccessControl {
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");

    // Wallet address => Identity contract
    mapping(address => IIdentity) private _identities;

    // Wallet address => Verification status
    mapping(address => bool) private _verified;

    // Wallet address => Country code (ISO-3166)
    mapping(address => uint16) private _countries;

    // Events as per ERC-3643
    event IdentityRegistered(address indexed wallet, IIdentity indexed identity);
    event IdentityRemoved(address indexed wallet, IIdentity indexed identity);
    event IdentityUpdated(IIdentity indexed oldIdentity, IIdentity indexed newIdentity);
    event CountryUpdated(address indexed wallet, uint16 indexed country);
    event IdentityVerified(address indexed wallet);
    event IdentityUnverified(address indexed wallet);

    constructor(address admin) {
        require(admin != address(0), "IdentityRegistry: admin is zero address");
        _setupRole(DEFAULT_ADMIN_ROLE, admin);
        _setupRole(AGENT_ROLE, admin);
    }

    /**
     * @dev Register a new identity for a wallet
     * @param wallet The wallet address
     * @param identityContract The identity contract address
     * @param country The investor's country code (ISO-3166)
     */
    function registerIdentity(
        address wallet,
        IIdentity identityContract,
        uint16 country
    ) external onlyRole(AGENT_ROLE) {
        require(wallet != address(0), "IdentityRegistry: wallet is zero");
        require(address(identityContract) != address(0), "IdentityRegistry: identity is zero");
        require(address(_identities[wallet]) == address(0), "IdentityRegistry: identity already exists");

        _identities[wallet] = identityContract;
        _countries[wallet] = country;
        _verified[wallet] = true; // Auto-verify on registration for Phase 1

        emit IdentityRegistered(wallet, identityContract);
        emit CountryUpdated(wallet, country);
        emit IdentityVerified(wallet);
    }

    /**
     * @dev Batch register identities
     * @param wallets Array of wallet addresses
     * @param identities Array of identity contracts
     * @param countries Array of country codes
     */
    function batchRegisterIdentity(
        address[] calldata wallets,
        IIdentity[] calldata identities,
        uint16[] calldata countries
    ) external onlyRole(AGENT_ROLE) {
        require(
            wallets.length == identities.length && wallets.length == countries.length,
            "IdentityRegistry: array length mismatch"
        );

        for (uint256 i = 0; i < wallets.length; i++) {
            if (address(_identities[wallets[i]]) == address(0)) {
                _identities[wallets[i]] = identities[i];
                _countries[wallets[i]] = countries[i];
                _verified[wallets[i]] = true;

                emit IdentityRegistered(wallets[i], identities[i]);
                emit CountryUpdated(wallets[i], countries[i]);
                emit IdentityVerified(wallets[i]);
            }
        }
    }

    /**
     * @dev Update identity for a wallet
     * @param wallet The wallet address
     * @param newIdentity The new identity contract
     */
    function updateIdentity(
        address wallet,
        IIdentity newIdentity
    ) external onlyRole(AGENT_ROLE) {
        require(wallet != address(0), "IdentityRegistry: wallet is zero");
        require(address(_identities[wallet]) != address(0), "IdentityRegistry: identity not registered");
        require(address(newIdentity) != address(0), "IdentityRegistry: new identity is zero");

        IIdentity oldIdentity = _identities[wallet];
        _identities[wallet] = newIdentity;

        emit IdentityUpdated(oldIdentity, newIdentity);
    }

    /**
     * @dev Update country for a wallet
     * @param wallet The wallet address
     * @param country The new country code
     */
    function updateCountry(
        address wallet,
        uint16 country
    ) external onlyRole(AGENT_ROLE) {
        require(address(_identities[wallet]) != address(0), "IdentityRegistry: identity not registered");

        _countries[wallet] = country;
        emit CountryUpdated(wallet, country);
    }

    /**
     * @dev Delete identity for a wallet
     * @param wallet The wallet address
     */
    function deleteIdentity(address wallet) external onlyRole(AGENT_ROLE) {
        require(address(_identities[wallet]) != address(0), "IdentityRegistry: identity not registered");

        IIdentity walletIdentity = _identities[wallet];
        delete _identities[wallet];
        delete _countries[wallet];
        delete _verified[wallet];

        emit IdentityRemoved(wallet, walletIdentity);
    }

    /**
     * @dev Set verification status for a wallet
     * @param wallet The wallet address
     * @param verified The verification status
     */
    function setVerified(address wallet, bool verified) external onlyRole(AGENT_ROLE) {
        require(address(_identities[wallet]) != address(0), "IdentityRegistry: identity not registered");

        _verified[wallet] = verified;

        if (verified) {
            emit IdentityVerified(wallet);
        } else {
            emit IdentityUnverified(wallet);
        }
    }

    /**
     * @dev Check if a wallet is verified
     * @param wallet The wallet address
     * @return true if wallet is verified
     */
    function isVerified(address wallet) external view returns (bool) {
        return _verified[wallet] && address(_identities[wallet]) != address(0);
    }

    /**
     * @dev Get identity contract for a wallet
     * @param wallet The wallet address
     * @return The identity contract
     */
    function identity(address wallet) external view returns (IIdentity) {
        return _identities[wallet];
    }

    /**
     * @dev Get country code for a wallet
     * @param wallet The wallet address
     * @return The country code
     */
    function investorCountry(address wallet) external view returns (uint16) {
        return _countries[wallet];
    }

    /**
     * @dev Check if identity exists for a wallet
     * @param wallet The wallet address
     * @return true if identity exists
     */
    function contains(address wallet) external view returns (bool) {
        return address(_identities[wallet]) != address(0);
    }
}
