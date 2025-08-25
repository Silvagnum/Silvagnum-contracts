// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract MockUnicryptLocker{
    
    function lockFee() external pure returns(uint256){
        return 0;
    }

   
    function lock(
        address, // _token
        address, // _lpToken
        uint256, // _amount
        uint256, // _unlockDate
        address, // _withdrawer
        uint256, // _referrer
        bool     // _fee_in_eth
    ) external payable{
       
    }
}
