// packages/hardhat/contracts/mocks/ManagerTestRouter.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ManagerTestRouter {
    
    constructor() {}

    
    function WETH() external pure returns (address) {
        return 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // Mainnet WETH
    }

   
    function getAmountsOut(uint256 amountIn, address[] calldata path) external pure returns (uint256[] memory amounts) {
        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountIn / 2; // 2:1 swap rate
    }

    
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256
    ) external {
       
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);

        
        uint256 amountOut = amountIn / 2;
        require(amountOut >= amountOutMin, "MockRouter: Slippage check failed");
        require(address(this).balance >= amountOut, "MockRouter: Not enough ETH");

        
        payable(to).transfer(amountOut);
    }

   
    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256,
        uint256,
        address,
        uint256
    ) external payable returns (uint, uint, uint) {
        
        IERC20(token).transferFrom(msg.sender, address(this), amountTokenDesired);
        
        return (amountTokenDesired, msg.value, 0);
    }

    
    receive() external payable {}
}