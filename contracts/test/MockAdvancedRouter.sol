// packages/hardhat/contracts/test/MockAdvancedRouter.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockAdvancedRouter {
    address public immutable WETH;

    constructor() {
       
        WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    }

    
    function getAmountsOut(uint amountIn, address[] calldata) external pure returns (uint[] memory) {
        uint[] memory amounts = new uint[](2);
        amounts[0] = amountIn;
        
        amounts[1] = amountIn / 200;
        return amounts;
    }

   
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256,
        address[] calldata path,
        address to,
        uint256
    ) external {
       
        require(to != address(0), "MockRouter: Invalid recipient");
        require(path.length >= 2, "MockRouter: Invalid path");
        
        address tokenContract = path[0];
        
        
        IERC20(tokenContract).transferFrom(msg.sender, address(this), amountIn);

        
        uint256 ethToSend = amountIn / 200;
        
        require(address(this).balance >= ethToSend, "MockRouter: Insufficient ETH balance for swap");

        (bool success, ) = payable(to).call{value: ethToSend}("");
        require(success, "MockRouter: ETH transfer failed");
    }

    
    receive() external payable {}
}