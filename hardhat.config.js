const dotenv = require("dotenv");
dotenv.config();

/* global ethers task */
require('@nomiclabs/hardhat-waffle')
require("@nomiclabs/hardhat-etherscan");
require("@nomiclabs/hardhat-ethers");
require("hardhat-gas-reporter");
/** @type import('hardhat/config').HardhatUserConfig */
const { PRIVATE_KEY_PARTHENON } = process.env;

module.exports = {
  networks: {
    localhost: {
      url: "http://127.0.0.1:8545",
    },
    hardhat: {},
    bscTestnet: {
      chainId: 97,
      url: "https://data-seed-prebsc-2-s1.bnbchain.org:8545",
      accounts: [`0x${PRIVATE_KEY_PARTHENON}`],
    },
    atheneParthenon: {
      chainId: 281123,
      url: "https://rpc.parthenon.athenescan.io",
      accounts: [`0x${PRIVATE_KEY_PARTHENON}`],
    },
  },
  solidity: {
    compilers: [
      {
        version: "0.8.27",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      }
    ]
  },
  etherscan: {
    apiKey: {
      bscTestnet: process.env.API_BSC_SCAN,
      atheneParthenon: process.env.API_ATHENE_TESTNET_SCAN,
    },
    customChains: [
      {
        network: "atheneParthenon",
        chainId: 281123,
        urls: {
          apiURL: "https://parthenon.athenescan.io/api?",
          browserURL: "https://parthenon.athenescan.io/",
        },
      },
    ],
  },

};
