# Silvagnum (SVGM) - Smart Contracts

![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)
![Solidity](https://img.shields.io/badge/Solidity-0.8.24-blue)
![Hardhat](https://img.shields.io/badge/Built%20with-Hardhat-orange)



> Official repository containing all smart contracts for the Silvagnum (SVGM) token, a sustainable utility and rewards token on the Polygon network, offering rewards in MATIC (POL), automatic liquidity, and anti-bot mechanisms.

###  Silvagnum Official Links
* **[🚀 Participate in the IDO](https://silvagnum-dapp-nextjs.vercel.app/)**
* **[📜 Read the Whitepaper](https://silvagnum-whitepaper.vercel.app/)**
* **[💬 Join our Discord Community](https://discord.gg/RSf9mAvUd6)**
  
## Overview

Silvagnum is a project focused on creating a sustainable ecosystem of utilities and rewards. This repository contains the heart of the project: the smart contracts that manage tokenomics, reward distribution, liquidity generation, and protocol security.

### ✅ Verified Smart Contracts

| Contract Role | Address on Polygonscan |
| :--- | :--- |
| **🪙 Main Token (SVGM)** | [0x204Eb...ba72](https://polygonscan.com/address/0x204Eb12374A591f0caf978fC0A6CFF621F93ba72#code) |
| **💧 Liquidity Manager** | [0x86093...13d7](https://polygonscan.com/address/0x860931ADc2bbF0B045f0f1bcd451EC088De613d7#code) |
| **💸 Dividend Distributor**| [0xe9944...5dC9](https://polygonscan.com/address/0xe994481FB30f7d4e8063897AE5dC23d8dBe45dC9#code) |
| **⏳ Vesting Wallet** | [0x3bbBe...1121](https://polygonscan.com/address/0x3bbBe45f60b314B1a045ec372Bf5eeF692Ed1121#code) |
| **🔐 Treasury Lock (2y)** | [0x9cd82...C7CD](https://polygonscan.com/address/0x9cd824c2582D13741f1796D8F4473cE1a19cC7CD#code) |
| **🔐 DAO Lock (1y)** | [0x97C46...B448](https://polygonscan.com/address/0x97C46A0B84d7e32b668bB8d966170BCd926dB448#code) |

---

## Tech Stack & Tools

This project was built with a focus on security and industry best practices.

* **Language:** Solidity `v0.8.24`
* **Main Framework:** `Hardhat` – Used for compilation, testing, and project management.
* **Base Library:** `OpenZeppelin Contracts v4.9.5` – Used as the foundation for ERC20 and security components, in a specific version to ensure stability.
* **Additional Testing:** `Foundry` – Used during the development phase for fuzzing tests and advanced scripting, providing an extra layer of robustness and security. (See the note in `test/README.md` for more details).

## Local Development & Testing

To interact with the project locally, follow the steps below.

### Prerequisites

* Node.js (v18 or higher)
* Yarn

### Running the Tests

1.  **Clone the repository:**
    ```bash
    git clone [https://github.com/Silvagnum/Silvagnum-contracts.git](https://github.com/Silvagnum/Silvagnum-contracts.git)
    cd Silvagnum-contracts
    ```

2.  **Install dependencies:**
    ```bash
    yarn install
    ```

3.  **Compile the contracts:**
    ```bash
    npx hardhat compile
    ```

4.  **Run the full test suite:**
    ```bash
    yarn hardhat test --network hardhat 
    ```


## License

This project is licensed under the **MIT License**. See the `LICENSE` file for more details.
