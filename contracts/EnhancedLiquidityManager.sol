

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;


/**
 * IMPORTANT NOTE:
 * @notice Developer's Note on MATIC/POL Nomenclature
 * @dev The 'MATIC' nomenclature is intentionally used throughout this contract's logic to align
 * @dev with the canonical address and interface of Wrapped MATIC (WMATIC) on Polygon PoS.
 * @dev
 * @dev As all automated swaps for the native token are routed through the WMATIC liquidity
 * @dev pair, this naming convention ensures direct consistency between the code's identifiers
 * @dev (e.g., '_swapTokensForMATIC') and the on-chain asset being handled in swaps.
 * @dev
 * @dev This is a deliberate design choice for code clarity and long-term maintainability.
 * @dev Functionally, the contract correctly handles the native POL token through `payable` calls.
 * @dev The user-facing front-end uses 'POL' to align with official branding.
 */

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


/// @dev Interface for interacting with an external LP token locker like Unicrypt V2.
interface IUnicryptLocker {
    function lock(
        address _token,
        address _lpToken, 
        uint256 _amount,  
        uint256 _unlockDate,
        address _withdrawer,
        uint256 _referrer,
        bool _fee_in_eth
    ) external payable;

    function lockFee() external view returns (uint256); 
    function unlockedTokens(address _lpToken, address _owner) external view returns(uint256); 
    
}




/// @dev Interface for interacting with a Uniswap V2 compatible router.
interface  IUniswapV2RouterLiquidity {
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
    
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    
    function WETH() external view returns (address);
}

/// @title Enhanced Liquidity Manager
/// @author Silvagnum's Founder
/// @notice Manages automated liquidity provision by swapping collected tokens for MATIC and adding them to a DEX liquidity pool.
/// @dev This contract is deployed by and owned by the main Silvagnum contract. It handles the 'swap and liquify' mechanic and can interact with an external LP locker.
contract EnhancedLiquidityManager is Ownable,  ReentrancyGuard{

    using SafeERC20 for IERC20;
   
   /// @notice The immutable address of the Uniswap V2 compatible router.
   IUniswapV2RouterLiquidity public immutable router;

   /// @notice The immutable address of the main token Silvagnum(SVGM) this contract manages.
    address public immutable token;

     /// @notice The address that receives MATIC from the marketing portion of collected fees.
    address public marketingWallet;
    
    /// @notice The threshold of collected Silvagnum tokens required to trigger an automatic fee processing event.
    uint256 public minTokensBeforeSwap = 500 * 10**18;

    /// @dev A re-entrancy guard flag for swap operations.
    bool private inSwap;

    /// @notice The divisor used to calculate slippage tolerance for swaps (e.g., 200 for 0.5%).
    uint256 public slippageDivisor = 200; 
    
    
    /// @notice The address of the SVGM/MATIC LP token, set after pool creation.
    address public lpToken; 

    /// @notice The address of the external LP locking contract (e.g., Unicrypt).
    address public liquidityLockerAddress; 

     /// @notice Emitted when LP tokens are successfully locked in an external contract.
    /// @param locker The address of the locker contract.
    /// @param liquidityAmount The amount of LP tokens locked.
    /// @param unlockTime The timestamp when the liquidity will be unlocked.
    /// @param withdrawer The address authorized to withdraw the LP tokens after the unlock time.
    event LiquidityLockedExternally(address indexed locker, uint256 liquidityAmount, uint256 unlockTime, address withdrawer);

     /// @notice Emitted after a successful swap-and-liquify operation from collected fees.
    event SwapAndLiquify(uint256 tokensSwappedForMatic, uint256 maticReceived, uint256 tokensAddedToLiquidity);

     /// @notice Emitted when the slippage divisor is updated.
    event SlippageUpdated(uint256 newSlippage);

    /// @notice Emitted when the minimum token threshold for swaps is updated.
    event ThresholdUpdated(uint256 newThreshold);
   

    
    /// @dev Modifier to prevent re-entrancy in swap functions.
    modifier lockTheSwap {
        bool alreadyLocked = inSwap;
        if (!alreadyLocked) {
            inSwap = true;
        }
        _;
        if (!alreadyLocked) {
            inSwap = false;
        }
    }

    /// @notice Initializes the liquidity manager contract.
    /// @param _router The address of the DEX router.
    /// @param _token The address of the main token (Silvagnum).
    /// @param _marketingWallet The address for the marketing wallet.
    constructor(address _router, address _token, address _marketingWallet) {
        router = IUniswapV2RouterLiquidity(_router);
        token = _token;
        marketingWallet = _marketingWallet;
    }
    
    /// @notice Updates the marketing wallet address.
    /// @dev Can only be called by the owner.
    /// @param newWallet The new address for the marketing wallet.
    function setMarketingWallet(address newWallet) external onlyOwner {
        require(newWallet != address(0), "Invalid address");
        marketingWallet = newWallet;
    }
    
    /// @notice Sets the slippage tolerance for DEX swaps.
    /// @dev Can only be called by the owner. A higher divisor means lower slippage. Max 1% slippage allowed.
    /// @param _slippageDivisor The new slippage divisor (e.g., 200 for 0.5%).
    function setSlippage(uint256 _slippageDivisor) external onlyOwner {
        require(_slippageDivisor >= 100, "Slippage too high"); // Max 1%
        slippageDivisor = _slippageDivisor;
        emit SlippageUpdated(_slippageDivisor);
    }
    
    /// @notice Sets the minimum amount of tokens required in this contract to trigger `processFees`.
    /// @dev Can only be called by the owner.
    /// @param _minTokens The new minimum threshold.
    function setMinTokensBeforeSwap(uint256 _minTokens) external onlyOwner {
        require(_minTokens > 0, "Min tokens must be > 0");
        minTokensBeforeSwap = _minTokens;
        emit ThresholdUpdated(_minTokens);
    }
    

     /// @notice Sets the address of the external liquidity locker contract (e.g., Unicrypt).
    /// @dev Can only be called by the owner. This is a critical step for using `addLiquidityAndLock`.
    /// @param _liquidityLockerAddress The address of the locker contract.
    function setLiquidityLockerAddress(address _liquidityLockerAddress) external onlyOwner {
        require(_liquidityLockerAddress != address(0), "Invalid locker address");
        liquidityLockerAddress = _liquidityLockerAddress;
    }
    
     /// @notice Processes accumulated fees from the main token contract.
    /// @dev Swaps 25% of the tokens for MATIC for the marketing wallet and uses the remaining 75% to add liquidity.
    /// @dev Protected against re-entrancy.
    function processFees() external nonReentrant {
    
        require(!inSwap, "Already in swap");
        inSwap = true;

        uint256 totalTokens = IERC20(token).balanceOf(address(this));
        require(totalTokens >= minTokensBeforeSwap, "Insufficient tokens");

    // 25% for marketing, 75% for liquidity
        uint256 marketingTokens = totalTokens / 4;
        uint256 liquidityTokens = totalTokens - marketingTokens;

    // Process marketing share
        if (marketingTokens > 0 && marketingWallet != address(0)) {
            _swapTokensForMATIC(marketingTokens, marketingWallet);
        }

    // Process liquidity share
        if (liquidityTokens > 0) {
            _addLiquidity(liquidityTokens);
        }
    
        inSwap = false;
    }

    
     /// @notice Swaps a specified amount of the contract's token for MATIC.
    /// @dev This private function is the core swap utility. It uses the configured router and includes slippage protection
    /// based on the `slippageDivisor`. It reverts if the DEX price query fails.
    /// @param tokenAmount The amount of tokens to swap.
    /// @param to The recipient address for the resulting MATIC.
    function _swapTokensForMATIC(uint256 tokenAmount, address to) private {
    require(tokenAmount > 0, "Token amount must be > 0");

    address[] memory path = new address[](2);
    path[0] = token;
    path[1] = router.WETH();

    IERC20(token).approve(address(router), tokenAmount);
    
    uint256 amountOutMin;

    // Slippage protection via try-catch on getAmountsOut
    try router.getAmountsOut(tokenAmount, path) returns (uint[] memory amountsOut) {
        amountOutMin = (amountsOut[1] * (slippageDivisor - 1)) / slippageDivisor;
    } catch {
        revert("Router: getAmountsOut failed or pool unstable.");
    }
     
    router.swapExactTokensForETHSupportingFeeOnTransferTokens(
        tokenAmount,
        amountOutMin,
        path,
        to,
        block.timestamp
    );
}
    
    
    /// @dev Internal function to add liquidity to the DEX pair.
    /// @dev It takes a token amount, swaps half for MATIC, and then uses both halves to create new liquidity.
    /// The resulting LP tokens are sent to this contract's owner (the main Silvagnum contract).
    /// @param tokenAmount The total amount of tokens to be used for creating liquidity.
    function _addLiquidity(uint256 tokenAmount) private {
    require(IERC20(token).balanceOf(address(this)) >= tokenAmount, "Insufficient liquidity tokens for addLiquidity");

    
    uint256 tokenAmountToSwapForMatic = tokenAmount / 2; 
    uint256 remainingTokensForLiquidity = tokenAmount - tokenAmountToSwapForMatic; 
    
    // Swap half the tokens to receive MATIC in this contract.
    _swapTokensForMATIC(tokenAmountToSwapForMatic, address(this));

    
    uint256 maticBalance = address(this).balance;

    
    require(maticBalance > 0, "Insufficient MATIC for liquidity");
    
    
    uint256 amountTokenMin = (remainingTokensForLiquidity * (slippageDivisor - 1)) / slippageDivisor;

    
    uint256 amountETHMin = (maticBalance * (slippageDivisor - 1)) / slippageDivisor;

    
    
    IERC20(token).approve(address(router), remainingTokensForLiquidity);
    
    
    router.addLiquidityETH{value: maticBalance}(
        token,
        remainingTokensForLiquidity, 
        amountTokenMin, 
        amountETHMin,   
        owner(), // LP tokens are sent to the owner (Silvagnum contract)
        block.timestamp
    );

    emit SwapAndLiquify(tokenAmount, maticBalance, remainingTokensForLiquidity);
}


  
    
   // FUNCTION TO ADD AND LOCK LIQUIDITY VIA UNICRYPT
   /// @notice Adds liquidity to the DEX and immediately locks the received LP tokens using an external locker service.
/// @dev This is a critical function, designed to be called once by `Silvagnum.finalizeIDO`` to establish and secure the initial liquidity pool. 
/// @dev It uses the Silvagnum(SVGM) tokens passed via `tokenAmount` and the full MATIC portion for liquidity received directly via `msg.value`. It does NOT perform a swap.
/// @param tokenAmount The amount of SVGM tokens to be provided for liquidity, sent from the `Silvagnum` contract.
/// @param unlockTimestamp The UNIX timestamp when the LP tokens will become withdrawable from the locker.

function addLiquidityAndLock(uint256 tokenAmount, uint256 unlockTimestamp) external payable onlyOwner nonReentrant {
    require(unlockTimestamp > block.timestamp, "Unlock time must be in the future");
    require(liquidityLockerAddress != address(0), "Liquidity locker address not set");
    require(lpToken != address(0), "LP token address not set. Call setLpToken first.");
    
    uint256 maticForLiquidity = msg.value;
    require(maticForLiquidity > 0, "MATIC must be provided");

    IERC20(token).safeTransferFrom(msg.sender, address(this), tokenAmount);
    IERC20(token).approve(address(router), tokenAmount);

    
    uint256 amountTokenMin = (tokenAmount * (slippageDivisor - 1)) / slippageDivisor;
    uint256 amountETHMin = (maticForLiquidity * (slippageDivisor - 1)) / slippageDivisor;
    

    (,, uint256 liquidity) = router.addLiquidityETH{value: maticForLiquidity}(
        token,
        tokenAmount,
        amountTokenMin, 
        amountETHMin,   
        address(this),  
        block.timestamp
    );

    uint256 unicryptFee = IUnicryptLocker(liquidityLockerAddress).lockFee();
    require(address(this).balance >= unicryptFee, "Not enough MATIC for fee");

    IERC20(lpToken).approve(liquidityLockerAddress, liquidity);
    
    IUnicryptLocker(liquidityLockerAddress).lock{value: unicryptFee}(
        token,
        lpToken,
        liquidity,
        unlockTimestamp,
        owner(), 
        0,
        true
    );

    emit LiquidityLockedExternally(liquidityLockerAddress, liquidity, unlockTimestamp, owner());
}



    /// @notice Sets the address of the LP token for this liquidity pair.
    /// @dev Can only be called by the owner. This must be done before calling `addLiquidityAndLock`.
    /// @param _lpToken The address of the created SVGM/MATIC LP token.
    function setLpToken(address _lpToken) external onlyOwner {
        require(_lpToken != address(0), "Invalid LP token address");
        lpToken = _lpToken;
    }
    
    
    
    /// @notice Allows the owner to withdraw any other ERC20 token accidentally sent to this contract.
    /// @dev A safety measure to recover stranded assets.
    /// @param _token The address of the ERC20 token to withdraw.
    function emergencyWithdrawTokens(address _token) external onlyOwner nonReentrant{
        IERC20(_token).safeTransfer(owner(), IERC20(_token).balanceOf(address(this)));

    }
    
     /// @notice Allows the contract to receive MATIC, typically from the internal `_swapTokensForMATIC` call.
    receive() external payable {}
}
