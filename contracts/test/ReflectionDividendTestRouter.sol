// contracts/mocks/ReflectionDividendTestRouter.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./MockLPToken.sol";

contract ReflectionDividendTestRouter {
    address public immutable WETH_ADDRESS;
    address public immutable LP_TOKEN_ADDRESS;

    
    constructor(address _weth, address _lpToken) {
        WETH_ADDRESS = _weth;
        LP_TOKEN_ADDRESS = _lpToken;
    }

    function WETH() external view returns (address) { return WETH_ADDRESS; }

    function getAmountsOut(uint256 amountIn, address[] calldata path) external pure returns (uint256[] memory amounts) {
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
       
        amounts[path.length - 1] = 0.1 ether;
        return amounts;
    }

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256
    ) external {
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        
        
        uint256 actualAmountOut = 0.1 ether;
        
        require(actualAmountOut >= amountOutMin, "UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT");
        require(address(this).balance >= actualAmountOut, "MockRouter: Insufficient balance");
        
        (bool success, ) = payable(to).call{value: actualAmountOut}("");
        require(success, "MockRouter: ETH transfer failed");
    }

   
    function addLiquidityETH(address,uint256,uint256,uint256,address,uint256) external payable returns (uint256, uint256, uint256) {
         return (0,0,0);
    }
    function setPriceManipulation(bool) external {}

    receive() external payable {}
}