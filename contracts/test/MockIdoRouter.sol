// contracts/mocks/MockIdoRouter.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./MockLPToken.sol";

contract MockIdoRouter {
    address public immutable WETH_ADDRESS;
    address public immutable LP_TOKEN_ADDRESS;
    bool public manipulatePrice = false;

    constructor(address _weth, address _lpToken) {
        WETH_ADDRESS = _weth;
        LP_TOKEN_ADDRESS = _lpToken;
    }

    function WETH() external view returns (address) {
        return WETH_ADDRESS;
    }

    function setPriceManipulation(bool _manipulate) external {
        manipulatePrice = _manipulate;
    }

    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts) {
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
       
        amounts[path.length - 1] = manipulatePrice ? 1000 : 0.1 ether;
        return amounts;
    }

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256, 
        uint256, 
        address to,
        uint256 
    ) external payable returns (uint256, uint256, uint256) {
        require(msg.value > 0, "MockRouter: No ETH sent");
        IERC20(token).transferFrom(msg.sender, address(this), amountTokenDesired);
        uint256 lpToMint = msg.value + amountTokenDesired;
        MockLPToken(LP_TOKEN_ADDRESS).mint(to, lpToMint);
        return (amountTokenDesired, msg.value, lpToMint);
    }

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 
    ) external {
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        
       
        uint256 actualAmountOut = manipulatePrice ? 1 : amountIn / 1_000_000_000;
        
        
        require(actualAmountOut >= amountOutMin, "UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT");
        
        
        require(address(this).balance >= actualAmountOut, "MockRouter: Insufficient balance to complete swap");
        
         (bool success, ) = payable(to).call{value: actualAmountOut}("");
        require(success, "MockRouter: ETH transfer failed");
    }

    receive() external payable {}
}