# Silvagnum (SVGM) - Smart Contracts

![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)
![Solidity](https://img.shields.io/badge/Solidity-0.8.24-blue)
![Hardhat](https://img.shields.io/badge/Built%20with-Hardhat-orange)

> Official repository containing all smart contracts for the Silvagnum (SVGM) token, a sustainable utility and rewards token on the Polygon network, offering rewards in MATIC (POL), automatic liquidity, and anti-bot mechanisms.

## Overview

Silvagnum is a project focused on creating a sustainable ecosystem of utilities and rewards. This repository contains the heart of the project: the smart contracts that manage tokenomics, reward distribution, liquidity generation, and protocol security.

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
