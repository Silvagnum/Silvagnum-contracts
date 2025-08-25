// packages/hardhat/contracts/mocks/GauntletTestRouter.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./MockLPToken.sol";

contract GauntletTestRouter {
    address public lpToken;

    constructor(address _factory, address _weth) {}

    function setLpToken(address _lpToken) external {
        lpToken = _lpToken;
    }

    
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256
    ) external {
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);

        
        uint256 amountOut = amountIn / 2_000_000;

        require(amountOut >= amountOutMin, "GauntletTestRouter: Slippage check failed");
        require(address(this).balance >= amountOut, "GauntletTestRouter: Not enough ETH");

        (bool success, ) = to.call{value: amountOut}("");
        require(success, "GauntletTestRouter: Falha ao enviar MATIC");
    }
    
    function getAmountsOut(uint256 amountIn, address[] calldata path) external pure returns (uint256[] memory amounts) {
        amounts = new uint256[](2);
        amounts[0] = amountIn;
       
        amounts[1] = amountIn / 2_000_000;
    }

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256,
        uint256,
        address to,
        uint256
    ) external payable returns (uint, uint, uint) {
        IERC20(token).transferFrom(msg.sender, address(this), amountTokenDesired);
        uint256 liquidity = msg.value;
        require(lpToken != address(0), "GauntletTestRouter: Endereco do LP Token nao foi configurado");
        MockLPToken(lpToken).mint(to, liquidity);
        return (amountTokenDesired, msg.value, liquidity);
    }

    function WETH() external pure returns (address) {
        return 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    }

    receive() external payable {}
}