

//reflections polygon
//// SPDX-License-Identifier: MIT
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
import "@openzeppelin/contracts/utils/Address.sol";



interface IUniswapV2Router {
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

/// @title MATIC Reflection Mechanics
/// @author Silvagnum's Founder
/// @notice An abstract contract module that implements the core mechanics for collecting token fees and swapping them for MATIC to fund dividend distributions.
/// @dev This contract is intended to be inherited by the main token contract  Silvagnum. It handles the logic for automatic swaps, fee management, and interaction with a dividend tracker.
abstract contract MATICReflectionMechanics is Ownable {
    using Address for address;

    /// @notice The percentage of each transaction taken as a reflection fee (e.g., a value of 5 means 5%).
    uint256 public reflectionFee = 5;

    
    /// @notice The minimum number of accumulated tokens in the contract required to trigger an automatic swap for MATIC.
    uint256 public swapTokensAtAmount;

    /// @notice The minimum MATIC amount required to trigger a dividend distribution, denominated in wei.
    uint256 public minDistribution = 0.01 ether;
    
    /// @notice The address of the deployed AdvancedDividendTracker contract responsible for distributing the MATIC.
    address public dividendTracker;
    
    
    /// @dev Mapping to store addresses that are excluded from the reflection fee.
    mapping(address => bool) internal _isExcludedFromReflectionFee;
    
    /// @notice Interface for the DEX router (e.g., QuickSwap) used for token swaps.
    IUniswapV2Router public uniswapRouter;


     /// @notice The address of the created DEX liquidity pool pair for this token.
    address public uniswapPair;
    
    /// @dev A re-entrancy guard flag to prevent multiple swaps from occurring simultaneously.
    bool private inSwap;

    /// @notice The timestamp of the last automatic swap.
    uint256 public lastSwapTime;

    
    /// @notice The cooldown period in seconds between automatic swaps.
    uint256 public swapCooldown = 1 hours;

    /// @notice The slippage tolerance for swaps in basis points (e.g., 50 for 0.5%).
    uint256 public slippageBasisPoints = 50; // Padrão: 50 = 0.5%

    /// @notice Emitted when the reflection fee percentage is updated.
    /// @param newFee The new reflection fee percentage.
    event ReflectionFeeUpdated(uint256 newFee);

    /// @notice Emitted when the token threshold for automatic swaps is updated.
    /// @param newThreshold The new minimum token amount.
    event SwapTokensAtAmountUpdated(uint256 newThreshold);

    /// @notice Emitted when collected fees are swapped for MATIC and sent to the dividend tracker.
    /// @param amountMATIC The amount of MATIC distributed.
    event DividendsDistributed(uint256 amountMATIC);

     /// @notice Emitted when an account is excluded from or re-included in reflection fees.
    /// @param account The address of the account.
    /// @param excluded The new exclusion status.
    event ExcludedFromReflectionFee(address indexed account, bool excluded);

    /// @notice Emitted when the dividend tracker contract address is updated.
    /// @param newTracker The new dividend tracker address.
    event DividendTrackerUpdated(address indexed newTracker);

    /// @notice Emitted upon a successful dividend distribution call to the tracker.
    /// @param tracker The address of the dividend tracker.
    /// @param amount The amount of MATIC sent.
    /// @param success The status of the call.
    event DividendDistribution(address indexed tracker, uint256 amount, bool success);
    
      /// @dev Modifier to prevent re-entrant calls to the token swap functions, ensuring only one swap can be active at a time.
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
    
    /// @dev Modifier to enforce a cooldown period between automatic swaps, preventing excessive or manipulative trading.
    modifier cooldown() {
        require(block.timestamp >= lastSwapTime + swapCooldown, "Swap cooldown active");
        _;
        lastSwapTime = block.timestamp;
    }
    
   
    /// @notice Initializes the reflection mechanics module.
    /// @param _swapTokensAtAmount The initial minimum number of tokens required to trigger a swap.
    /// @param routerAddress The address of the UniswapV2Router for the target DEX.
    constructor(uint256 _swapTokensAtAmount, address routerAddress) {
        require(routerAddress != address(0), "Router address cannot be zero");
        swapTokensAtAmount = _swapTokensAtAmount;
        uniswapRouter = IUniswapV2Router(routerAddress);
    }
    

    /// @notice Sets the reflection fee percentage.
    /// @dev Can only be called by the owner. The fee cannot exceed 10%.
    /// @param fee The new reflection fee (e.g., 5 for 5%).
    function setReflectionFee(uint256 fee) external onlyOwner {
        require(fee <= 10, "Fee too high");
        require(fee != reflectionFee, "Same as current fee");
        reflectionFee = fee;
        emit ReflectionFeeUpdated(fee);
    }
    
    /// @notice Sets the minimum number of tokens to accumulate before an automatic swap.
    /// @dev Can only be called by the owner. This is a virtual function intended to be overridden by the main contract.
    /// @param amount The new minimum token amount threshold.
    function setSwapTokensAtAmount(uint256 amount) external  virtual onlyOwner {
        require(amount > 0, "Amount must be > 0");
        swapTokensAtAmount = amount;
        emit SwapTokensAtAmountUpdated(amount);
    }
    
    /// @notice Sets the address of the dividend tracker contract.
    /// @dev Can only be called by the owner. This is a critical link in the rewards mechanism.
    /// @param _tracker The address of the deployed AdvancedDividendTracker contract.
    function setDividendTracker(address _tracker) external onlyOwner {
        require(_tracker != address(0), "Cannot be zero address");
        dividendTracker = _tracker;
        emit DividendTrackerUpdated(_tracker);
    }

    /// @notice Excludes or re-includes an account from the reflection fee.
    /// @dev Can only be called by the owner.
    /// @param account The address of the account to update.
    /// @param excluded The new exclusion status (true to exclude, false to include).
    function excludeFromReflectionFee(address account, bool excluded) external onlyOwner {
        require(_isExcludedFromReflectionFee[account] != excluded, "Already set");
        _isExcludedFromReflectionFee[account] = excluded;
        emit ExcludedFromReflectionFee(account, excluded);
    }
    
     /// @notice Public view function to check if an account is excluded from the reflection fee.
    /// @param account The address to check.
    /// @return True if the account is excluded, false otherwise.
    function isExcludedFromReflectionFee(address account) public view returns (bool) {
        return _isExcludedFromReflectionFee[account];
    }
    
    
    /// @dev Internal view function to calculate the reflection fee amount for a given token amount.
    /// @return The calculated fee amount. Returns at least 1 if amount > 0 to ensure fee is collected.
    function _getReflectionFeeAmount(uint256 amount) internal view returns (uint256) {
        uint256 fee = (amount * reflectionFee) / 100;
        return fee > 0 ? fee : (amount > 0 ? 1 : 0);
    }
    
    /// @dev Internal function called during transfers to handle the collected reflection fees.
    /// @dev It checks if the contract's token balance has reached the `swapTokensAtAmount` threshold
    /// and triggers the automated swap mechanism if conditions are met.
    /// @param sender The original sender of the transaction, used to avoid swap loops from DEX interactions.
    function _handleReflectionFee(address sender) internal {
        uint256 contractTokenBalance = tokenBalanceOf(address(this));
        if (contractTokenBalance >= swapTokensAtAmount && !inSwap && sender != uniswapPair) {
            _swapAndSendDividends(contractTokenBalance);
        }
    }
    
    /// @dev Orchestrates the process of swapping collected tokens for MATIC and distributing them.
    /// @dev Protected by `lockTheSwap` and `cooldown` modifiers to ensure safety and prevent abuse.
    /// @param tokenAmount The amount of tokens to be swapped.
    function _swapAndSendDividends(uint256 tokenAmount) internal lockTheSwap cooldown {
        _swapTokensForMATIC(tokenAmount);
        uint256 maticBalance = address(this).balance;
        if (maticBalance >= minDistribution) {
            _distributeDividends(maticBalance);
            emit DividendsDistributed(maticBalance);
        }
    }
    

    /// @dev Performs the swap of this contract's tokens for MATIC on a DEX.
    /// @dev The resulting MATIC is sent directly to the `dividendTracker` contract to fund the reward pool.
    /// @param tokenAmount The amount of tokens to swap.
    function _swapTokensForMATIC(uint256 tokenAmount) internal {
        require(tokenAmount > 0, "Token amount must be > 0");
        require(tokenAmount <= tokenBalanceOf(address(this)), "Insufficient token balance");
        
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapRouter.WETH(); 
        
        _approveForRouter(address(this), tokenAmount);
        
        uint[] memory amountsOut = uniswapRouter.getAmountsOut(tokenAmount, path);
        uint256 amountOutMin = (amountsOut[1] * (10000 - slippageBasisPoints)) / 10000;
        
        uniswapRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            amountOutMin,
            path,
            address(this),
            block.timestamp
        );
    }


  

    /// @dev Forwards the MATIC funds to the dividend tracker contract.
    /// @dev This is a virtual function to allow for potential custom logic in the inheriting contract.
    /// @param amountMATIC The amount of MATIC to send.
    function _distributeDividends(uint256 amountMATIC) internal virtual {
        if (dividendTracker != address(0)) {
            (bool success, ) = dividendTracker.call{value: amountMATIC}("");
            emit DividendDistribution(dividendTracker, amountMATIC, success);
            require(success, "Dividend distribution failed");

        }
    }
     
     /// @notice Updates the cooldown period between automatic swaps.
    /// @dev Can only be called by the owner. Maximum cooldown is 24 hours.
    /// @param _cooldown The new cooldown period in seconds.
    function setSwapCooldown(uint256 _cooldown) external onlyOwner {
        require(_cooldown <= 24 hours, "Cooldown too long");
        swapCooldown = _cooldown;
    }

    /// @notice Updates the slippage tolerance for swaps.
    /// @dev Can only be called by the owner.
    /// @param _newSlippageInBasisPoints The new slippage in basis points (e.g., 50 for 0.5%).
    function setSlippage(uint256 _newSlippageInBasisPoints) external onlyOwner {
        // Prevents slippage from being 0% or greater than 10% (1000 basis points)
        require(_newSlippageInBasisPoints > 0 && _newSlippageInBasisPoints <= 1000, "Invalid slippage value");
        slippageBasisPoints = _newSlippageInBasisPoints;
    }     
    
    /// @notice Sets or updates the Uniswap pair address.
    /// @dev Can only be called by the owner. This is a critical post-deploy configuration step.
    /// @param _pair The address of the created liquidity pool pair.
    function setUniswapPair(address _pair) external onlyOwner {
        require(_pair != address(0), "Cannot be zero address");
        uniswapPair = _pair;
    }
    
    /// @dev Abstract function that must be implemented by the inheriting contract to approve the router.
    function _approveForRouter(address owner_, uint256 amount) internal virtual;

    /// @dev Abstract function that must be implemented by the inheriting contract to return its own balance.
    function tokenBalanceOf(address account) public view virtual returns (uint256);
    
     /// @dev Abstract receive function that must be implemented by the inheriting contract.
    receive() external payable virtual {}
}
