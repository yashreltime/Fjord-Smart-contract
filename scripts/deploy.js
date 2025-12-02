/**
 * Deployment script for Fjord RWA ERC-3643 Token Platform
 *
 * Deploys:
 * 1. IdentityRegistry - KYC/AML verification
 * 2. Compliance - Transfer rules enforcement
 * 3. ERC3643Token - Main security token with asset management
 */
async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("=".repeat(60));
  console.log("Deploying Fjord RWA ERC-3643 Platform");
  console.log("=".repeat(60));
  console.log("Deployer address:", deployer.address);
  console.log("Account balance:", (await deployer.getBalance()).toString());
  console.log("");

  // Admin address (use separate multisig in production)
  const admin = deployer.address;

  // Step 1: Deploy IdentityRegistry
  console.log("1. Deploying IdentityRegistry...");
  const IdentityRegistry = await ethers.getContractFactory("IdentityRegistry");
  const identityRegistry = await IdentityRegistry.deploy(admin);
  await identityRegistry.deployed();
  console.log("   ✓ IdentityRegistry deployed to:", identityRegistry.address);
  console.log("");

  // Step 2: Deploy Compliance
  console.log("2. Deploying Compliance contract...");
  const Compliance = await ethers.getContractFactory("Compliance");
  const compliance = await Compliance.deploy(admin);
  await compliance.deployed();
  console.log("   ✓ Compliance deployed to:", compliance.address);
  console.log("");

  // Step 3: Deploy ERC3643Token
  console.log("3. Deploying ERC3643Token...");
  const ERC3643Token = await ethers.getContractFactory("ERC3643Token");
  const token = await ERC3643Token.deploy(
    "Fjord RWA Token",           // Token name
    "FJRWA",                      // Token symbol
    admin,                        // Admin address
    identityRegistry.address,     // Identity Registry
    compliance.address            // Compliance contract
  );
  await token.deployed();
  console.log("   ✓ ERC3643Token deployed to:", token.address);
  console.log("");

  // Step 4: Bind Compliance to Token
  console.log("4. Binding Compliance contract to Token...");
  const bindTx = await compliance.bindToken(token.address);
  await bindTx.wait();
  console.log("   ✓ Compliance bound to token");
  console.log("");

  // Deployment Summary
  console.log("=".repeat(60));
  console.log("DEPLOYMENT SUMMARY");
  console.log("=".repeat(60));
  console.log("Network:", (await ethers.provider.getNetwork()).name);
  console.log("Chain ID:", (await ethers.provider.getNetwork()).chainId);
  console.log("");
  console.log("Contract Addresses:");
  console.log("-------------------");
  console.log("IdentityRegistry:", identityRegistry.address);
  console.log("Compliance:      ", compliance.address);
  console.log("ERC3643Token:    ", token.address);
  console.log("");
  console.log("Admin Address:   ", admin);
  console.log("");
  console.log("=".repeat(60));
  console.log("NEXT STEPS:");
  console.log("=".repeat(60));
  console.log("1. Register verified users in IdentityRegistry");
  console.log("2. Create assets using token.createAsset()");
  console.log("3. Grant MINTER_ROLE to backend service");
  console.log("4. Verify contracts on block explorer");
  console.log("=".repeat(60));

  // Return deployed addresses for verification
  return {
    identityRegistry: identityRegistry.address,
    compliance: compliance.address,
    token: token.address,
    admin: admin
  };
}

// Execute deployment
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
