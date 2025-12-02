const { expect } = require('chai');
const { ethers } = require('hardhat');

describe('ERC3643Token - Full ERC-3643 Compliance Suite', function () {
  let identityRegistry, compliance, token;
  let owner, admin, minter, agent, alice, bob;
  let MockIdentity;

  beforeEach(async function () {
    [owner, admin, minter, agent, alice, bob] = await ethers.getSigners();

    // Deploy MockIdentity for testing (simple contract that implements IIdentity)
    const MockIdentityFactory = await ethers.getContractFactory('MockIdentity');
    const aliceIdentity = await MockIdentityFactory.deploy();
    const bobIdentity = await MockIdentityFactory.deploy();

    // Deploy IdentityRegistry
    const IdentityRegistry = await ethers.getContractFactory('IdentityRegistry');
    identityRegistry = await IdentityRegistry.deploy(admin.address);
    await identityRegistry.deployed();

    // Deploy Compliance
    const Compliance = await ethers.getContractFactory('Compliance');
    compliance = await Compliance.deploy(admin.address);
    await compliance.deployed();

    // Deploy ERC3643Token
    const ERC3643Token = await ethers.getContractFactory('ERC3643Token');
    token = await ERC3643Token.deploy(
      'Fjord RWA Token',
      'FJRWA',
      admin.address,
      identityRegistry.address,
      compliance.address
    );
    await token.deployed();

    // Bind compliance to token
    await compliance.connect(admin).bindToken(token.address);

    // Grant roles
    await token.connect(admin).grantRole(await token.MINTER_ROLE(), minter.address);
    await token.connect(admin).grantRole(await token.AGENT_ROLE(), agent.address);
    await identityRegistry.connect(admin).grantRole(await identityRegistry.AGENT_ROLE(), agent.address);

    // Register identities for Alice and Bob
    await identityRegistry.connect(agent).registerIdentity(
      alice.address,
      aliceIdentity.address,
      840 // USA country code
    );

    await identityRegistry.connect(agent).registerIdentity(
      bob.address,
      bobIdentity.address,
      784 // UAE country code
    );
  });

  describe('Deployment', function () {
    it('should set correct token name and symbol', async function () {
      expect(await token.name()).to.equal('Fjord RWA Token');
      expect(await token.symbol()).to.equal('FJRWA');
    });

    it('should link to IdentityRegistry and Compliance', async function () {
      expect(await token.identityRegistry()).to.equal(identityRegistry.address);
      expect(await token.compliance()).to.equal(compliance.address);
    });

    it('should grant admin roles correctly', async function () {
      const DEFAULT_ADMIN_ROLE = await token.DEFAULT_ADMIN_ROLE();
      expect(await token.hasRole(DEFAULT_ADMIN_ROLE, admin.address)).to.be.true;
    });
  });

  describe('Identity Registry', function () {
    it('should verify registered identities', async function () {
      expect(await identityRegistry.isVerified(alice.address)).to.be.true;
      expect(await identityRegistry.isVerified(bob.address)).to.be.true;
    });

    it('should return correct country codes', async function () {
      expect(await identityRegistry.investorCountry(alice.address)).to.equal(840);
      expect(await identityRegistry.investorCountry(bob.address)).to.equal(784);
    });

    it('should not verify unregistered addresses', async function () {
      const [, , , , , , unregistered] = await ethers.getSigners();
      expect(await identityRegistry.isVerified(unregistered.address)).to.be.false;
    });

    it('should allow agent to update country', async function () {
      await identityRegistry.connect(agent).updateCountry(alice.address, 826); // UK
      expect(await identityRegistry.investorCountry(alice.address)).to.equal(826);
    });

    it('should allow agent to remove identity', async function () {
      await identityRegistry.connect(agent).deleteIdentity(alice.address);
      expect(await identityRegistry.isVerified(alice.address)).to.be.false;
    });
  });

  describe('Asset Management', function () {
    it('should allow admin to create asset', async function () {
      await token.connect(admin).createAsset(
        'VILLA-001',
        'Luxury Villa Dubai',
        'ipfs://QmVilla001',
        100000, // $1000.00
        367000, // AED equivalent
        100     // max supply
      );

      const asset = await token.getAsset('VILLA-001');
      expect(asset.id).to.equal('VILLA-001');
      expect(asset.name_).to.equal('Luxury Villa Dubai');
      expect(asset.priceUSD).to.equal(100000);
      expect(asset.priceAED).to.equal(367000);
      expect(asset.maxSupply).to.equal(100);
      expect(asset.active).to.be.true;
    });

    it('should prevent duplicate asset creation', async function () {
      await token.connect(admin).createAsset('VILLA-001', 'Villa 1', '', 10000, 36700, 50);
      await expect(
        token.connect(admin).createAsset('VILLA-001', 'Villa 1 Duplicate', '', 10000, 36700, 50)
      ).to.be.revertedWith('ERC3643: asset already exists');
    });

    it('should allow admin to update asset', async function () {
      await token.connect(admin).createAsset('VILLA-002', 'Villa 2', '', 10000, 36700, 50);

      await token.connect(admin).updateAsset(
        'VILLA-002',
        'Updated Villa 2',
        'ipfs://updated',
        20000,
        73400,
        75,
        true
      );

      const asset = await token.getAsset('VILLA-002');
      expect(asset.name_).to.equal('Updated Villa 2');
      expect(asset.priceUSD).to.equal(20000);
      expect(asset.maxSupply).to.equal(75);
    });

    it('should prevent non-admin from creating assets', async function () {
      await expect(
        token.connect(alice).createAsset('VILLA-003', 'Villa 3', '', 10000, 36700, 50)
      ).to.be.reverted;
    });
  });

  describe('Minting (Phase 1)', function () {
    beforeEach(async function () {
      // Create test asset
      await token.connect(admin).createAsset(
        'VILLA-100',
        'Test Villa',
        'ipfs://test',
        50000,  // $500.00
        183500, // AED
        10      // max supply
      );
    });

    it('should allow minter to mint tokens to verified users', async function () {
      await token.connect(minter).mint(alice.address, 5, 'VILLA-100');

      expect(await token.balanceOf(alice.address)).to.equal(5);
      expect(await token.assetBalanceOf(alice.address, 'VILLA-100')).to.equal(5);
    });

    it('should update asset minted supply', async function () {
      await token.connect(minter).mint(alice.address, 3, 'VILLA-100');

      const asset = await token.getAsset('VILLA-100');
      expect(asset.mintedSupply).to.equal(3);
    });

    it('should respect max supply cap', async function () {
      await token.connect(minter).mint(alice.address, 10, 'VILLA-100');

      await expect(
        token.connect(minter).mint(bob.address, 1, 'VILLA-100')
      ).to.be.revertedWith('ERC3643: exceeds max supply');
    });

    it('should prevent minting to unverified addresses', async function () {
      const [, , , , , , unverified] = await ethers.getSigners();

      await expect(
        token.connect(minter).mint(unverified.address, 1, 'VILLA-100')
      ).to.be.revertedWith('ERC3643: recipient not verified');
    });

    it('should prevent minting for inactive assets', async function () {
      await token.connect(admin).updateAsset(
        'VILLA-100',
        'Test Villa',
        'ipfs://test',
        50000,
        183500,
        10,
        false // set to inactive
      );

      await expect(
        token.connect(minter).mint(alice.address, 1, 'VILLA-100')
      ).to.be.revertedWith('ERC3643: asset is not active');
    });

    it('should prevent non-minter from minting', async function () {
      await expect(
        token.connect(bob).mint(alice.address, 1, 'VILLA-100')
      ).to.be.reverted;
    });

    it('should emit TokenIssued event', async function () {
      await expect(token.connect(minter).mint(alice.address, 2, 'VILLA-100'))
        .to.emit(token, 'TokenIssued')
        .withArgs(alice.address, 2, 'VILLA-100', 100000); // 2 * 50000
    });
  });

  describe('Burning', function () {
    beforeEach(async function () {
      await token.connect(admin).createAsset('VILLA-200', 'Burn Test', '', 10000, 36700, 50);
      await token.connect(minter).mint(alice.address, 10, 'VILLA-200');
    });

    it('should allow admin to burn tokens', async function () {
      await token.connect(admin).burn(alice.address, 5, 'VILLA-200', 'Redemption');

      expect(await token.balanceOf(alice.address)).to.equal(5);
      expect(await token.assetBalanceOf(alice.address, 'VILLA-200')).to.equal(5);
    });

    it('should decrement asset minted supply', async function () {
      await token.connect(admin).burn(alice.address, 3, 'VILLA-200', 'Redemption');

      const asset = await token.getAsset('VILLA-200');
      expect(asset.mintedSupply).to.equal(7);
    });

    it('should emit TokenBurned event', async function () {
      await expect(token.connect(admin).burn(alice.address, 2, 'VILLA-200', 'Exit'))
        .to.emit(token, 'TokenBurned')
        .withArgs(alice.address, 2, 'VILLA-200', 'Exit');
    });

    it('should prevent non-admin from burning', async function () {
      await expect(
        token.connect(minter).burn(alice.address, 1, 'VILLA-200', 'Unauthorized')
      ).to.be.reverted;
    });
  });

  describe('Transfer Restrictions (Phase 1 - Soul-bound)', function () {
    beforeEach(async function () {
      await token.connect(admin).createAsset('VILLA-300', 'Transfer Test', '', 10000, 36700, 50);
      await token.connect(minter).mint(alice.address, 10, 'VILLA-300');
    });

    it('should block transfers between users (soul-bound)', async function () {
      await expect(
        token.connect(alice).transfer(bob.address, 5)
      ).to.be.revertedWith('ERC3643: transfer not compliant');
    });

    it('should block transferFrom between users', async function () {
      await token.connect(alice).approve(bob.address, 5);

      await expect(
        token.connect(bob).transferFrom(alice.address, bob.address, 5)
      ).to.be.revertedWith('ERC3643: transfer not compliant');
    });
  });

  describe('Freeze Functionality', function () {
    beforeEach(async function () {
      await token.connect(admin).createAsset('VILLA-400', 'Freeze Test', '', 10000, 36700, 50);
      await token.connect(minter).mint(alice.address, 10, 'VILLA-400');
    });

    it('should allow agent to freeze address', async function () {
      await token.connect(agent).setAddressFrozen(alice.address, true);
      expect(await token.isFrozen(alice.address)).to.be.true;
    });

    it('should prevent frozen address from transferring', async function () {
      await token.connect(agent).setAddressFrozen(alice.address, true);

      // Even though Phase 1 blocks all transfers, this tests the freeze logic
      await expect(
        token.connect(alice).transfer(bob.address, 1)
      ).to.be.revertedWith('ERC3643: sender address is frozen');
    });

    it('should allow agent to freeze partial tokens', async function () {
      await token.connect(agent).freezePartialTokens(alice.address, 3);
      expect(await token.getFrozenTokens(alice.address)).to.equal(3);
    });

    it('should allow agent to unfreeze tokens', async function () {
      await token.connect(agent).freezePartialTokens(alice.address, 5);
      await token.connect(agent).unfreezePartialTokens(alice.address, 2);
      expect(await token.getFrozenTokens(alice.address)).to.equal(3);
    });
  });

  describe('Pause Functionality', function () {
    beforeEach(async function () {
      await token.connect(admin).createAsset('VILLA-500', 'Pause Test', '', 10000, 36700, 50);
    });

    it('should allow admin to pause the contract', async function () {
      await token.connect(admin).pause();
      expect(await token.paused()).to.be.true;
    });

    it('should prevent minting when paused', async function () {
      await token.connect(admin).pause();

      await expect(
        token.connect(minter).mint(alice.address, 1, 'VILLA-500')
      ).to.be.revertedWith('Pausable: paused');
    });

    it('should allow admin to unpause', async function () {
      await token.connect(admin).pause();
      await token.connect(admin).unpause();
      expect(await token.paused()).to.be.false;
    });
  });

  describe('Batch Operations', function () {
    beforeEach(async function () {
      await token.connect(admin).createAsset('VILLA-600', 'Batch Test', '', 10000, 36700, 100);
    });

    it('should allow batch minting', async function () {
      const recipients = [alice.address, bob.address];
      const amounts = [5, 3];
      const assetIds = ['VILLA-600', 'VILLA-600'];

      await token.connect(minter).batchMint(recipients, amounts, assetIds);

      expect(await token.balanceOf(alice.address)).to.equal(5);
      expect(await token.balanceOf(bob.address)).to.equal(3);
    });

    it('should revert batch mint on array length mismatch', async function () {
      await expect(
        token.connect(minter).batchMint(
          [alice.address],
          [5, 3],
          ['VILLA-600']
        )
      ).to.be.revertedWith('ERC3643: array length mismatch');
    });
  });

  describe('ERC-3643 Compliance Integration', function () {
    it('should query compliance contract', async function () {
      expect(await compliance.getTokenBound()).to.equal(token.address);
    });

    it('should allow Phase 1 transfers to be disabled', async function () {
      expect(await compliance.transfersEnabled()).to.be.false;
    });

    it('should allow owner to enable transfers (future phases)', async function () {
      await compliance.connect(admin).setTransfersEnabled(true);
      expect(await compliance.transfersEnabled()).to.be.true;
    });
  });
});

// Mock Identity contract for testing
describe('MockIdentity', function () {});
