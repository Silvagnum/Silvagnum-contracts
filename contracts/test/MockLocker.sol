// packages/hardhat/contracts/mocks/MockLocker.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockLocker {
    struct Lock {
        uint256 amount;
        uint256 unlockDate;
        address withdrawer;
    }

    // Mapping from LP token address to its lock details
    mapping(address => Lock) public lockDetails;

   
    function lockFee() external pure returns (uint256) {
        return 0; 
    }

    function lock(
        address, // _token
        address _lpToken,
        uint256 _amount,
        uint256 _unlockDate,
        address _withdrawer,
        uint256, // _referrer
        bool // _fee_in_eth
    ) external payable {
        IERC20(_lpToken).transferFrom(msg.sender, address(this), _amount);
        lockDetails[_lpToken] = Lock({amount: _amount, unlockDate: _unlockDate, withdrawer: _withdrawer});
    }

    function getLockedAmount(address _lpToken) external view returns (uint256) {
        return lockDetails[_lpToken].amount;
    }

    function getLockDetails(address _lpToken) external view returns (Lock memory) {
        return lockDetails[_lpToken];
    }
}