About the Silvagnum Test Suite:

This folder contains the complete unit and integration test suite for the smart contracts of the Silvagnum project, developed using Hardhat and TypeScript. These tests cover business logic, security, and interaction scenarios between contracts.

Important Note on Additional Tests (Fuzzing & Scripting with Foundry)
It is important to note that, during the initial development and internal audit phase, an additional and rigorous battery of tests was conducted using the Foundry framework.

These tests, which are not part of this Hardhat suite, included:

Fuzz Tests: Thousands of transactions with random and unexpected inputs were executed against the contracts to uncover edge cases and mathematical vulnerabilities that standard unit tests might not capture.

Script-Based Tests: Complex interaction scenarios and attack simulations were written in Solidity and executed directly to validate the system’s resilience under adverse conditions.

Reason for Exclusion: Since these tests were developed in a different ecosystem (Foundry / Solidity Scripting), they were not migrated to this final test suite in Hardhat / TypeScript in order to maintain cohesion and clarity within this repository.

The existence of these additional tests represents an extra layer of diligence in the security and robustness of the Silvagnum protocol.