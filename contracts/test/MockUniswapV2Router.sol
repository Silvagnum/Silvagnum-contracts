// Arquivo: packages/hardhat/contracts/test/MockUniswapV2Router.sol

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockUniswapV2Router{
    address private immutable _WETH;

    constructor(){
        _WETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    }

  
    receive() external payable {}
   
    function WETH() external view returns(address){
        return _WETH;
    }

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint,uint,address,uint
    ) external payable returns(uint amountToken,uint amountETH,uint liquidity){
        if(amountTokenDesired>0){
            IERC20(token).transferFrom(msg.sender,address(this),amountTokenDesired);
        }
        return (amountTokenDesired,msg.value,100*1e18);
    }

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint,
        address[] calldata path,
        address to,
        uint
    ) external{
        if(amountIn>0){
            IERC20(path[0]).transferFrom(msg.sender,address(this),amountIn);
        }
        (bool success,)=payable(to).call{value:0.1 ether}("");
        require(success,"MockRouter: Failed to send MATIC");
    }

    function getAmountsOut(uint amountIn,address[] calldata path) external pure returns(uint[] memory amounts){
        amounts=new uint[](path.length);
        amounts[0]=amountIn;
        amounts[amounts.length-1]=0.1 ether;
    }
}
