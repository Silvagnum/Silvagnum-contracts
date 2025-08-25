// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./MockLPToken.sol"; 

contract SimpleTestRouter {
    address public mockLpTokenAddress;

    constructor(address _mockLpTokenAddress) {
        mockLpTokenAddress = _mockLpTokenAddress;
    }

    receive() external payable {}

    function WETH() external pure returns (address) {
        return 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    }

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint, uint,
        address to, 
        uint
    ) external payable returns (uint, uint, uint) {
        if (amountTokenDesired > 0) {
            IERC20(token).transferFrom(msg.sender, address(this), amountTokenDesired);
        }
        
        uint256 liquidity = msg.value + amountTokenDesired;
        
        MockLPToken(mockLpTokenAddress).mint(to, liquidity);

        return (amountTokenDesired, msg.value, liquidity);
    }
    
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint,
        address[] calldata path,
        address to,
        uint
    ) external {
        if (amountIn > 0) {
            IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        }
        uint256 amountOut = amountIn / 2000000;
        require(address(this).balance >= amountOut, "SimpleTestRouter: Not enough ETH");
        (bool success, ) = to.call{value: amountOut}("");
require(success, "SimpleTestRouter: Failed to send MATIC");
    }

    function getAmountsOut(uint amountIn, address[] calldata path) external pure returns (uint[] memory amounts) {
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        amounts[amounts.length-1] = amountIn / 2000000;
    }
}