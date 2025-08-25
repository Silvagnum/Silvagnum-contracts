// packages/hardhat/contracts/test/MockSimple-Router.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract MockSimpleRouter {
    function WETH() external pure returns (address) {
        return 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    }

    function addLiquidityETH(address, uint, uint, uint, address, uint) external payable returns (uint, uint, uint) {
        return (0, 0, 0);
    }

    function swapExactTokensForETHSupportingFeeOnTransferTokens(uint, uint, address[] calldata, address, uint) external {}

    function getAmountsOut(uint amountIn, address[] calldata) external pure returns (uint[] memory amounts) {
        amounts = new uint[](2);
        amounts[0] = amountIn;
        amounts[1] = amountIn / 2;
    }
}