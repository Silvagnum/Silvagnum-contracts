// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ISilvagnum {
    function processLiquidity() external;
    function transfer(address to, uint256 amount) external returns (bool);
    function liquidityManager() external view returns (address);
}

contract MaliciousLiquidityManager {
    ISilvagnum public immutable silvagnum;
    bool private reentrancyTriggered = false;

    constructor(address _silvagnum) {
        silvagnum = ISilvagnum(_silvagnum);
    }

    function attack() external {
        // I will make this contract the liquidity manager to test re-entrancy
        // This is a conceptual attack to test the guard.
        silvagnum.processLiquidity();
    }

    
    receive() external payable {
        if (!reentrancyTriggered) {
            reentrancyTriggered = true;
            // Attempt to re-enter
            silvagnum.processLiquidity();
        }
    }
}