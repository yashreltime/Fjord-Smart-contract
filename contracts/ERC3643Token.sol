// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./IdentityRegistry.sol";
import "./ICompliance.sol";

/**
 * @title ERC3643Token
 * @dev ERC-3643 compliant security token for Real World Assets (RWA)
 *
 * Features:
 * - Full ERC-3643 T-REX protocol compliance
 * - Identity-based KYC/AML verification via IdentityRegistry
 * - Compliance-enforced transfers via Compliance contract
 * - On-chain asset registry with pricing (USD/AED)
 * - Supply tracking and caps per asset
 * - Admin-controlled minting and burning
 * - Phase 1: Soul-bound behavior (transfers disabled)
 * - Pausable for emergency stops
 * - Comprehensive event emissions for transparency
 *
 * Roles:
 * - DEFAULT_ADMIN_ROLE: Full admin privileges
 * - AGENT_ROLE: Can manage identities and freeze addresses
 * - MINTER_ROLE: Can mint tokens after payment verification
 *
 * IMPORTANT: This contract requires security audit before production use
 */
contract ERC3643Token is ERC20, AccessControl, Pausable {
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    // ERC-3643 compliance components
    IdentityRegistry private _identityRegistry;
    ICompliance private _compliance;

    // Frozen addresses (cannot send or receive tokens)
    mapping(address => bool) private _frozen;

    // Frozen token amounts per address (partial freeze)
    mapping(address => uint256) private _frozenTokens;

    // Asset management - Supports ANY type of Real World Asset
    struct Asset {
        string assetId;       // External identifier (e.g., "PROP-001", "GOLD-100G", "ART-MONA", "BOND-2025")
        string name;          // Human-readable name
        string metadataURI;   // Off-chain metadata pointer (IPFS/URL)
        uint256 priceUSD;     // Reference price in USD cents (e.g., $10.00 => 1000) - for transparency only
        uint256 priceAED;     // Reference price in AED fils - for transparency only
        uint256 mintedSupply; // Total minted for this asset
        uint256 maxSupply;    // Maximum supply cap
        bool active;          // Whether asset is active
    }

    // assetId => Asset
    mapping(string => Asset) private _assets;

    // Token holder => assetId => amount held
    mapping(address => mapping(string => uint256)) private _assetBalances;

    // ERC-3643 Events
    event IdentityRegistryAdded(address indexed identityRegistry);
    event ComplianceAdded(address indexed compliance);
    event AddressFrozen(address indexed addr, bool frozen, address indexed by);
    event TokensFrozen(address indexed addr, uint256 amount);
    event TokensUnfrozen(address indexed addr, uint256 amount);
    event RecoverySuccess(address indexed lostWallet, address indexed newWallet, address indexed by);

    // Asset Management Events
    event AssetCreated(
        string indexed assetId,
        string name,
        uint256 priceUSD,
        uint256 priceAED,
        uint256 maxSupply
    );
    event AssetUpdated(
        string indexed assetId,
        string name,
        uint256 priceUSD,
        uint256 priceAED,
        uint256 maxSupply,
        bool active
    );
    event TokenIssued(
        address indexed to,
        uint256 amount,
        string assetId,
        uint256 totalPrice
    );
    event TokenBurned(
        address indexed from,
        uint256 amount,
        string assetId,
        string reason
    );

    constructor(
        string memory name_,
        string memory symbol_,
        address admin,
        address identityRegistry_,
        address compliance_
    ) ERC20(name_, symbol_) {
        require(admin != address(0), "ERC3643: admin is zero address");
        require(identityRegistry_ != address(0), "ERC3643: identity registry is zero address");
        require(compliance_ != address(0), "ERC3643: compliance is zero address");

        _setupRole(DEFAULT_ADMIN_ROLE, admin);
        _setupRole(AGENT_ROLE, admin);
        _setupRole(MINTER_ROLE, admin);

        _identityRegistry = IdentityRegistry(identityRegistry_);
        _compliance = ICompliance(compliance_);

        emit IdentityRegistryAdded(identityRegistry_);
        emit ComplianceAdded(compliance_);
    }

    // ==================== Asset Management ====================

    /**
     * @dev Create a new asset
     * @param assetId Unique asset identifier
     * @param name_ Asset name
     * @param metadataURI Metadata URI (IPFS/URL)
     * @param priceUSD Price in USD cents
     * @param priceAED Price in AED fils
     * @param maxSupply Maximum supply cap
     */
    function createAsset(
        string calldata assetId,
        string calldata name_,
        string calldata metadataURI,
        uint256 priceUSD,
        uint256 priceAED,
        uint256 maxSupply
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(bytes(assetId).length > 0, "ERC3643: assetId is empty");
        require(_assets[assetId].maxSupply == 0, "ERC3643: asset already exists");
        require(maxSupply > 0, "ERC3643: maxSupply must be greater than 0");

        _assets[assetId] = Asset({
            assetId: assetId,
            name: name_,
            metadataURI: metadataURI,
            priceUSD: priceUSD,
            priceAED: priceAED,
            mintedSupply: 0,
            maxSupply: maxSupply,
            active: true
        });

        emit AssetCreated(assetId, name_, priceUSD, priceAED, maxSupply);
    }

    /**
     * @dev Update an existing asset
     * @param assetId Asset identifier
     * @param name_ New asset name
     * @param metadataURI New metadata URI
     * @param priceUSD New price in USD cents
     * @param priceAED New price in AED fils
     * @param maxSupply New maximum supply (must be >= current minted supply)
     * @param active Whether asset is active
     */
    function updateAsset(
        string calldata assetId,
        string calldata name_,
        string calldata metadataURI,
        uint256 priceUSD,
        uint256 priceAED,
        uint256 maxSupply,
        bool active
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(bytes(assetId).length > 0, "ERC3643: assetId is empty");
        Asset storage asset = _assets[assetId];
        require(asset.maxSupply != 0, "ERC3643: asset does not exist");
        require(maxSupply == 0 || maxSupply >= asset.mintedSupply, "ERC3643: maxSupply too low");

        asset.name = name_;
        asset.metadataURI = metadataURI;
        asset.priceUSD = priceUSD;
        asset.priceAED = priceAED;
        if (maxSupply != 0) {
            asset.maxSupply = maxSupply;
        }
        asset.active = active;

        emit AssetUpdated(assetId, name_, priceUSD, priceAED, asset.maxSupply, active);
    }

    /**
     * @dev Get asset details
     * @param assetId Asset identifier
     * @return id Asset ID
     * @return name_ Asset name
     * @return metadataURI Metadata URI
     * @return priceUSD Price in USD cents
     * @return priceAED Price in AED fils
     * @return mintedSupply Minted supply
     * @return maxSupply Maximum supply
     * @return active Whether asset is active
     */
    function getAsset(string calldata assetId) external view returns (
        string memory id,
        string memory name_,
        string memory metadataURI,
        uint256 priceUSD,
        uint256 priceAED,
        uint256 mintedSupply,
        uint256 maxSupply,
        bool active
    ) {
        Asset storage asset = _assets[assetId];
        require(asset.maxSupply != 0, "ERC3643: asset does not exist");

        return (
            asset.assetId,
            asset.name,
            asset.metadataURI,
            asset.priceUSD,
            asset.priceAED,
            asset.mintedSupply,
            asset.maxSupply,
            asset.active
        );
    }

    /**
     * @dev Get asset balance for an address
     * @param account Address to query
     * @param assetId Asset identifier
     * @return Balance of the asset
     */
    function assetBalanceOf(address account, string calldata assetId) external view returns (uint256) {
        return _assetBalances[account][assetId];
    }

    // ==================== Minting & Burning ====================

    /**
     * @dev Mint tokens to a verified user for a specific asset
     *
     * IMPORTANT: This function does NOT enforce payment verification.
     * Backend MUST verify fiat payment BEFORE calling this function.
     * On-chain prices are reference values for transparency/audit trail.
     *
     * @param to Recipient address (must be verified in IdentityRegistry)
     * @param amount Amount of tokens to mint
     * @param assetId Asset identifier
     * @return true if minting successful
     */
    /**
     * @dev Internal function to mint tokens (called by mint and batchMint)
     * @param to Recipient address
     * @param amount Amount to mint
     * @param assetId Asset identifier
     */
    function _mintToken(
        address to,
        uint256 amount,
        string memory assetId
    ) internal {
        require(to != address(0), "ERC3643: mint to zero address");
        require(amount > 0, "ERC3643: mint amount is zero");

        // Check identity verification
        require(_identityRegistry.isVerified(to), "ERC3643: recipient not verified");

        // Check asset exists and is active
        Asset storage asset = _assets[assetId];
        require(asset.maxSupply != 0, "ERC3643: asset does not exist");
        require(asset.active, "ERC3643: asset is not active");

        // Check supply cap
        require(asset.mintedSupply + amount <= asset.maxSupply, "ERC3643: exceeds max supply");

        // Mint tokens
        _mint(to, amount);

        // Update asset supply and balances
        asset.mintedSupply += amount;
        _assetBalances[to][assetId] += amount;

        // Notify compliance contract
        _compliance.created(to, amount);

        // Calculate total price for transparency
        uint256 totalPriceUSD = asset.priceUSD * amount;

        emit TokenIssued(to, amount, assetId, totalPriceUSD);
    }

    function mint(
        address to,
        uint256 amount,
        string calldata assetId
    ) external onlyRole(MINTER_ROLE) whenNotPaused returns (bool) {
        _mintToken(to, amount, assetId);
        return true;
    }

    /**
     * @dev Batch mint tokens to multiple addresses
     * @param toList Array of recipient addresses
     * @param amounts Array of amounts to mint
     * @param assetIds Array of asset identifiers
     * @return true if batch minting successful
     */
    function batchMint(
        address[] calldata toList,
        uint256[] calldata amounts,
        string[] calldata assetIds
    ) external onlyRole(MINTER_ROLE) whenNotPaused returns (bool) {
        require(
            toList.length == amounts.length && toList.length == assetIds.length,
            "ERC3643: array length mismatch"
        );

        for (uint256 i = 0; i < toList.length; i++) {
            _mintToken(toList[i], amounts[i], assetIds[i]);
        }

        return true;
    }

    /**
     * @dev Burn tokens from an address for a specific asset
     * @param from Address to burn from
     * @param amount Amount to burn
     * @param assetId Asset identifier
     * @param reason Reason for burning
     * @return true if burning successful
     */
    function burn(
        address from,
        uint256 amount,
        string calldata assetId,
        string calldata reason
    ) external onlyRole(DEFAULT_ADMIN_ROLE) returns (bool) {
        require(from != address(0), "ERC3643: burn from zero address");
        require(amount > 0, "ERC3643: burn amount is zero");
        require(_assetBalances[from][assetId] >= amount, "ERC3643: insufficient asset balance");

        // Burn tokens
        _burn(from, amount);

        // Update asset supply and balances
        Asset storage asset = _assets[assetId];
        if (asset.maxSupply != 0 && asset.mintedSupply >= amount) {
            asset.mintedSupply -= amount;
        }
        _assetBalances[from][assetId] -= amount;

        // Notify compliance contract
        _compliance.destroyed(from, amount);

        emit TokenBurned(from, amount, assetId, reason);

        return true;
    }

    // ==================== ERC-3643 Transfer Logic ====================

    /**
     * @dev Override transfer to include ERC-3643 compliance checks
     */
    function transfer(address to, uint256 amount) public virtual override whenNotPaused returns (bool) {
        address from = _msgSender();

        // ERC-3643 compliance checks
        require(!_frozen[from], "ERC3643: sender address is frozen");
        require(!_frozen[to], "ERC3643: recipient address is frozen");
        require(balanceOf(from) - _frozenTokens[from] >= amount, "ERC3643: insufficient unfrozen balance");
        require(_identityRegistry.isVerified(to), "ERC3643: recipient not verified");
        require(_compliance.canTransfer(from, to, amount), "ERC3643: transfer not compliant");

        // Execute transfer
        bool success = super.transfer(to, amount);

        // Notify compliance contract
        if (success) {
            _compliance.transferred(from, to, amount);
        }

        return success;
    }

    /**
     * @dev Override transferFrom to include ERC-3643 compliance checks
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override whenNotPaused returns (bool) {
        // ERC-3643 compliance checks
        require(!_frozen[from], "ERC3643: sender address is frozen");
        require(!_frozen[to], "ERC3643: recipient address is frozen");
        require(balanceOf(from) - _frozenTokens[from] >= amount, "ERC3643: insufficient unfrozen balance");
        require(_identityRegistry.isVerified(to), "ERC3643: recipient not verified");
        require(_compliance.canTransfer(from, to, amount), "ERC3643: transfer not compliant");

        // Execute transfer
        bool success = super.transferFrom(from, to, amount);

        // Notify compliance contract
        if (success) {
            _compliance.transferred(from, to, amount);
        }

        return success;
    }

    /**
     * @dev Forced transfer by admin (bypasses compliance for recovery)
     * @param from Source address
     * @param to Destination address
     * @param amount Amount to transfer
     * @return true if transfer successful
     */
    function forcedTransfer(
        address from,
        address to,
        uint256 amount
    ) external onlyRole(AGENT_ROLE) returns (bool) {
        require(to != address(0), "ERC3643: transfer to zero address");
        require(balanceOf(from) >= amount, "ERC3643: insufficient balance");

        _transfer(from, to, amount);

        emit RecoverySuccess(from, to, _msgSender());

        return true;
    }

    // ==================== Freeze Functionality ====================

    /**
     * @dev Freeze or unfreeze an address
     * @param addr Address to freeze/unfreeze
     * @param freeze true to freeze, false to unfreeze
     */
    function setAddressFrozen(address addr, bool freeze) external onlyRole(AGENT_ROLE) {
        require(addr != address(0), "ERC3643: cannot freeze zero address");

        _frozen[addr] = freeze;
        emit AddressFrozen(addr, freeze, _msgSender());
    }

    /**
     * @dev Freeze a specific amount of tokens for an address
     * @param addr Address to freeze tokens for
     * @param amount Amount to freeze
     */
    function freezePartialTokens(address addr, uint256 amount) external onlyRole(AGENT_ROLE) {
        require(balanceOf(addr) >= _frozenTokens[addr] + amount, "ERC3643: amount exceeds balance");

        _frozenTokens[addr] += amount;
        emit TokensFrozen(addr, amount);
    }

    /**
     * @dev Unfreeze tokens for an address
     * @param addr Address to unfreeze tokens for
     * @param amount Amount to unfreeze
     */
    function unfreezePartialTokens(address addr, uint256 amount) external onlyRole(AGENT_ROLE) {
        require(_frozenTokens[addr] >= amount, "ERC3643: amount exceeds frozen balance");

        _frozenTokens[addr] -= amount;
        emit TokensUnfrozen(addr, amount);
    }

    /**
     * @dev Get frozen token amount for an address
     * @param addr Address to query
     * @return Frozen token amount
     */
    function getFrozenTokens(address addr) external view returns (uint256) {
        return _frozenTokens[addr];
    }

    /**
     * @dev Check if an address is frozen
     * @param addr Address to check
     * @return true if address is frozen
     */
    function isFrozen(address addr) external view returns (bool) {
        return _frozen[addr];
    }

    // ==================== Pause Functionality ====================

    /**
     * @dev Pause all token transfers
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @dev Unpause all token transfers
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    // ==================== ERC-3643 Getters ====================

    /**
     * @dev Get the identity registry address
     * @return Identity registry address
     */
    function identityRegistry() external view returns (address) {
        return address(_identityRegistry);
    }

    /**
     * @dev Get the compliance contract address
     * @return Compliance contract address
     */
    function compliance() external view returns (address) {
        return address(_compliance);
    }

    /**
     * @dev Set new identity registry (admin only)
     * @param identityRegistry_ New identity registry address
     */
    function setIdentityRegistry(address identityRegistry_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(identityRegistry_ != address(0), "ERC3643: identity registry is zero address");

        _identityRegistry = IdentityRegistry(identityRegistry_);
        emit IdentityRegistryAdded(identityRegistry_);
    }

    /**
     * @dev Set new compliance contract (admin only)
     * @param compliance_ New compliance contract address
     */
    function setCompliance(address compliance_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(compliance_ != address(0), "ERC3643: compliance is zero address");

        _compliance = ICompliance(compliance_);
        emit ComplianceAdded(compliance_);
    }

    // ==================== Interface Support ====================

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
