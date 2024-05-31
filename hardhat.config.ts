import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import { vars } from "hardhat/config";
import '@openzeppelin/hardhat-upgrades';

const ETHERSCAN_API_KEY = vars.get("ETHERSCAN_API_KEY");

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.25",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  networks: {
    bscTestnet: {
      url: "https://bsc-testnet-rpc.publicnode.com",
      chainId: 97,
      accounts: ["0xc4591e64a59ffbfc9cb8761929a0bd74df52ce4f237f11112f729bae1769be16"],
      gas: 2100000,
      gasPrice: 200000000, // 8 Gwei
    },
    sepolia: {
      url: "https://ethereum-sepolia-rpc.publicnode.com",
      chainId: 11155111,
      accounts: ["0xc4591e64a59ffbfc9cb8761929a0bd74df52ce4f237f11112f729bae1769be16"]
    }
  },
  etherscan: {
    apiKey: ETHERSCAN_API_KEY
  }
};

export default config;
