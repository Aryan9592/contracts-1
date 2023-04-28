import "@nomicfoundation/hardhat-foundry"
import "@nomicfoundation/hardhat-toolbox"
import "@usum-io/hardhat-package"
import * as dotenv from "dotenv"
import "hardhat-contract-sizer"
import { HardhatUserConfig } from "hardhat/config"
import "hardhat-deploy"
import "tsconfig-paths/register"
import "@nomiclabs/hardhat-ethers"
dotenv.config()

const MNEMONIC_JUNK =
  "test test test test test test test test test test test junk"

const common = {
  accounts: {
    mnemonic: process.env.MNEMONIC || MNEMONIC_JUNK,
    count: 100,
  },
}

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.17",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  defaultNetwork: "anvil",
  networks: {
    hardhat: {
      forking: { url: "https://arb-goerli.g.alchemy.com/v2/TX5yVD-hPv6H9Dy7cuCQqD5I7S0NY-fP", blockNumber: 18064747 },
      chainId: 421613,
      // chainId: 31337,
      tags: ["mockup", "core"],
      allowUnlimitedContractSize: true,
      accounts: {
        ...common.accounts,
        mnemonic: MNEMONIC_JUNK,
      },
    },
    anvil: {
      // localhost anvil
      ...common,
      accounts: {
        ...common.accounts,
        mnemonic: MNEMONIC_JUNK,
      },
      url: "http://127.0.0.1:8545",
      chainId: 31337,
      tags: ["mockup", "core"],
      allowUnlimitedContractSize: true,
    },
    arbitrum_nova: {
      // mainnet AnyTrust chain
      ...common,
      url: "https://nova.arbitrum.io/rpc",
      chainId: 42170,
      tags: ["core"],
    },
    arbitrum_one_goerli: {
      // testnet
      ...common,
      url: "https://goerli-rollup.arbitrum.io/rpc",
      chainId: 421613,
      tags: ["core"],
    },
    arbitrum_one: {
      // mainnet
      ...common,
      url: "https://arb1.arbitrum.io/rpc",
      chainId: 42161,
      tags: ["core"],
    },
  },
  namedAccounts: {
    deployer: {
      default: 0,
    },
    gelato: 50,
  },
  package: {
    packageJson: "package.sdk.json",
  },
}

export default config
