// packages/hardhat/contracts/test/ReentrancyAttacker.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../SilvagnumVestingWallet.sol";

contract ReentrancyAttacker {
    SilvagnumVestingWallet public vestingWallet;
    address public tokenAddress;
    uint256 public callCount = 0;

   
    constructor(address _token, address _vesting) {}

    function setContracts(address _tokenAddress, address payable _vestingWallet) external {
        tokenAddress = _tokenAddress;
        vestingWallet = SilvagnumVestingWallet(_vestingWallet);
    }

    function attack() external {
        vestingWallet.release(tokenAddress);
    }

    receive() external payable {
        callCount++;
        
        if (callCount < 2) {
            vestingWallet.release(tokenAddress);
        }
    }
}