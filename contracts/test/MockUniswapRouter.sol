// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;


interface IUniswapV2Router {
    function WETH() external pure returns (address);
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
}

contract MockUniswapRouter is IUniswapV2Router {
    address public immutable WETH_ADDRESS;

    constructor() {
        
        WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    }

    function WETH() external pure override returns (address) {
        return 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    }

   
    function getAmountsOut(uint amountIn, address[] calldata /*path*/) external view override returns (uint[] memory amounts) {
        amounts = new uint[](2);
        amounts[0] = amountIn;
        amounts[1] = amountIn / 2; // Simple mock: returns half the value in "ETH"
    }

   
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint, uint, address[] calldata, address, uint
    ) external override {
        
    }
}