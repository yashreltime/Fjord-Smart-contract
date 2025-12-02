// Hardhat config for Fjord RWA ERC-3643 Platform
// Compatible with Hyperledger Besu private chains
require("@nomiclabs/hardhat-ethers");
require("@nomiclabs/hardhat-waffle");

module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200  // Optimize for deployment size and moderate gas usage
      },
      // EVM version compatible with Hyperledger Besu
      evmVersion: "london"  // Besu supports London and later EVM versions
    }
  },
  networks: {
    // Local Hardhat network for testing
    hardhat: {
      chainId: 31337
    },

    // Hyperledger Besu - Local Development Node
    fjordLocal: {
      url: process.env.FJORD_RPC_URL || "http://127.0.0.1:8545",
      chainId: parseInt(process.env.FJORD_CHAIN_ID) || 1337,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      gas: "auto",
      gasPrice: "auto",
      timeout: 60000,  // 60 seconds
    },

    // Hyperledger Besu - Private Network (IBFT 2.0 / QBFT)
    fjordPrivate: {
      url: process.env.FJORD_PRIVATE_RPC_URL || "http://127.0.0.1:8545",
      chainId: parseInt(process.env.FJORD_PRIVATE_CHAIN_ID) || 2024,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      gas: "auto",
      gasPrice: 0,  // Private chains often have zero gas price
      timeout: 120000,  // 2 minutes for consensus
    },
  },
  // Mocha test configuration
  mocha: {
    timeout: 120000  // 2 minutes for Besu consensus in tests
  }
};
