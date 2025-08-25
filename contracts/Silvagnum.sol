
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


import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./MATICReflectionMechanics.sol"; 
import "./AdvancedDividendTracker.sol";  
import "./EnhancedLiquidityManager.sol"; 
import "./SilvagnumVestingWallet.sol";


error UnauthorizedMaticDeposit(); 

/// @title Silvagnum - A Sustainable Utility & Rewards Token
/// @notice The core contract for the Silvagnum ecosystem, managing tokenomics, rewards, and governance.
/// @dev Inherits from OpenZeppelin's ERC20, Ownable, and AccessControl for robust security.
/// @dev Integrates custom mechanics for MATIC dividends, automated liquidity, and team vesting.
contract Silvagnum is ERC20, Ownable, AccessControl, MATICReflectionMechanics, ReentrancyGuard {
    /// @notice The total initial supply of Silvagnum (SVGM) tokens (12 Billion).
    uint256 public constant INITIAL_SUPPLY = 12_000_000_000 * 10 ** 18;
    
    /// @notice The contract responsible for tracking and distributing MATIC dividends to holders.
    AdvancedDividendTracker public advancedDividendTracker;
   
    /// @notice The contract responsible for managing automated liquidity additions.
    EnhancedLiquidityManager public liquidityManager;
    
    /// @notice Address for receiving marketing funds. Expected to be a multisig wallet.
    address public marketingWallet;
    
    /// @notice The admin address for the vesting contract, typically a multisig for security.
    address public vestingWalletAdmin;
    
   /// @notice Immutable address for the founder's initial token allocation, ensuring transparency.
    address public immutable founderWallet;

    /// @notice Address holding 3.5B tokens for institutional treasury purposes. Expected to be a Gnosis Safe multisig.
    address public immutable treasuryWallet;

   /// @notice Address holding 800M tokens for future DAO or incentive programs. Expected to be a Gnosis Safe multisig.
    address public immutable futureDAOReserve;

    /// @notice DAO reward wallet used for user participation incentives (e.g., NFTs).(Read the Whitepaper for better understanding)
    address public immutable userIncentiveWallet;

    /// @notice Reward wallet for corporate environmental incentives.(Read the Whitepaper for better understanding)
    address public immutable companyIncentiveWallet;



    
    /// @notice Address for ecosystem growth, CEX listings, and strategic partnerships. Expected to be a multisig wallet.
    address public growthReserveWallet;

    
    // Roles
    /// @notice Role for top-level administrative functions. Can grant/revoke other roles.
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
 
    /// @notice Role for managing the dividend distribution mechanics.
    bytes32 public constant DIVIDEND_MANAGER_ROLE = keccak256("DIVIDEND_MANAGER_ROLE");

    /// @notice Role for managing the automated liquidity mechanics.
    bytes32 public constant LIQUIDITY_MANAGER_ROLE = keccak256("LIQUIDITY_MANAGER_ROLE");

    // --- Security Controls ---
    /// @notice The maximum number of tokens allowed in a single transaction.
    uint256 public maxTxAmount;

    /// @notice The maximum number of tokens an individual wallet can hold.
    uint256 public maxWalletAmount;

     /// @notice The cooldown period in seconds required between transactions for an address.
    uint256 public txDelaySeconds = 30;

    /// @notice Flag indicating if public trading is active on the DEX.
    bool public tradingActive;
    
    // Anti-Bot
    /// @notice The duration (in seconds) of the anti-bot mechanism after trading is enabled.
    uint256 public antiBotPeriod = 3 hours;

     /// @notice The timestamp when trading was enabled.
    uint256 public launchTime;

     /// @notice The extra fee (in %) applied to transactions identified as snipes (only during the anti-bot period).
    uint256 public snipeFee = 25;

     /// @notice The percentage of maxTxAmount that triggers the snipe fee.
    uint256 public snipeThreshold = 30;
  

    // Fees
     /// @notice The percentage of each transaction automatically sent to the liquidity pool.
    uint256 public liquidityFee = 4;
    
    //  Sell Control   
    mapping(address => uint256) private _sellCount;
  
    /// @notice The maximum number of sell transactions an address can make during the anti-bot period.
    uint256 public maxSellsPerAddress = 3;
      
    // Vesting

    /// @notice The contract that manages the vesting schedule for the founder.(Read the Whitepaper for better understanding)
    SilvagnumVestingWallet public silvagnumVesting;
    
    /// @notice Mapping to exclude specific addresses from transaction limits.
    mapping(address => bool) public isExcludedFromLimits;

     /// @notice Mapping to track the last transaction timestamp for each address to enforce cooldown.
    mapping(address => uint256) public lastTxTimestamp;
     
    //  Events 
    /// @notice Emitted when the trading status is changed (enabled/disabled).
    event TradingStatusChanged(bool status);

    /// @notice Emitted when an account is excluded from or included in transaction limits.
    event LimitsExcluded(address indexed account, bool excluded);

     /// @notice Emitted when transaction limits are updated.
    event LimitsUpdated(uint256 maxTx, uint256 maxWallet, uint256 delay);

     /// @notice Emitted when a seller hits the maximum sell limit during the anti-bot period.
    event SellLimitHit(address indexed seller, uint256 sellCount);
   
    /// @notice Emitted when a bot-like transaction is detected and penalized.(only during the anti-bot period).
    event BotCaught(address indexed bot, uint256 amount);
    
    /// @notice Emitted when the IDO is successfully finalized and funds are distributed.
    event IDOFinalized(uint256 liquidityAmount, uint256 projectAmount);
  
   /// @notice Emitted when the initial tokens are allocated to the founder.
    event FounderTokensAllocated(address indexed founder, uint256 amount);

      /// @notice Emitted when tokens are allocated to the treasury wallet.
    event TreasuryAllocated(address indexed treasury, uint256 amount);

     /// @notice Emitted when tokens are reserved for the future DAO.
    event DAOTokensReserved(address indexed daoReserve, uint256 amount);

    /// @notice Emitted when the user incentive wallet is funded.
    event UserIncentiveFunded(address indexed wallet, uint256 amount);

     /// @notice Emitted when the company incentive wallet is funded.
    event CompanyIncentiveFunded(address indexed wallet, uint256 amount);

     /// @notice Emitted when an external incentive contract is configured with special permissions.
    event IncentiveContractConfigured(address indexed contractAddress);
    
      /// @notice Emitted when tokens are burned.
    event TokensBurned(uint256 amount);


    

    /// @notice Emitted when the EnhancedLiquidityManager contract is configured.
    event LiquidityManagerConfigured(address indexed liquidityManager);

     //  IDO State Variables 
    /// @notice The total number of tokens allocated for the Initial DEX Offering (IDO).
    uint256 public constant IDO_TOKENS_ALLOCATED = 1_200_000_000 * 10 ** 18;
  
     /// @notice The number of tokens sold so far in the IDO.
    uint256 public idoTokensSold;

    /// @notice The amount of MATIC raised so far in the IDO.
    uint256 public idoMaticRaised;



    //  IDO Bonding Curve Parameters 
    /// @notice The base price for the first token sold in the IDO, denominated in wei.
    uint256 public constant BASE_PRICE = 540_540_540_540;  

    /// @notice The incremental value added to the price for each full token sold, defining the curve's slope.
    uint256 public constant PRICE_SLOPE = 10; 

    /// @notice The precision factor used for fixed-point math in price calculations.
    uint256 public constant PRICE_PRECISION = 1e18;

    //  IDO Limits 
    /// @notice The minimum amount of MATIC to be raised for the IDO to be considered successful (500 MATIC).
    /// @dev If not reached, refunds will be enabled.
    uint256 public constant IDO_SOFT_CAP = 500 ether;

     /// @notice The maximum amount of MATIC that can be raised in the IDO (~660 MATIC).
    uint256 public constant IDO_HARD_CAP = 660 ether;

    /// @notice The minimum contribution amount in MATIC that a single address can make.
    uint256 public constant MIN_CONTRIBUTION = 2 ether;

    /// @notice The maximum total contribution amount in MATIC that a single address can make.
    uint256 public constant MAX_CONTRIBUTION = 20 ether;
    
   // IDO Mappings
   /// @notice Mapping of contributor addresses to their total MATIC contribution.
    mapping(address => uint256) public idoContributions;

     /// @notice Mapping of contributor addresses to the amount of Silvagnum (SVGM) tokens they purchased in the IDO.
    mapping(address => uint256) public idoTokensPurchased; 
    
     /// @notice Flag indicating if the IDO is currently active.
    bool public idoActive;

     /// @notice Flag indicating if the IDO has been finalized.
    bool public idoFinalized;

    /// @notice Flag indicating if refunds are enabled (in case the soft cap is not met).
    bool public refundEnabled; 
    
    // IDO Events
    /// @notice Emitted when the IDO is started by an admin.
    event IDOStarted(uint256 timestamp);

    /// @notice Emitted when a user successfully contributes to the IDO.
    event IDOContribution(address indexed contributor, uint256 maticAmount, uint256 tokensReceived, uint256 price);

    /// @notice Emitted when a user successfully claims a refund after a failed IDO.
    event IDORefund(address indexed contributor, uint256 maticRefunded, uint256 tokensReturned);

    /// @notice Emitted when an admin performs an emergency withdrawal of IDO funds.
    event EmergencyWithdraw(address indexed admin, uint256 amount);


    /// @notice Contract constructor to initialize Silvagnum.
    /// @dev Sets up all core parameters, wallets, initial token distribution, and deploys sub-contracts.
    /// @param router The address of the DEX router (e.g., Uniswap, QuickSwap).
    /// @param _marketingWallet The address for receiving marketing funds.
    /// @param _vestingWalletAdmin The admin address for the vesting contract.
    /// @param _growthReserveWallet The address for the ecosystem growth reserve.
    /// @param _founderWallet The immutable address for the founder's token allocation.
    /// @param _treasuryWallet The immutable address for the treasury.
    /// @param _futureDAOReserve The immutable address for the future DAO reserve.
    /// @param _userIncentiveWallet The immutable address for user incentives.
    /// @param _companyIncentiveWallet The immutable address for company incentives.
    constructor(
    address router,
     address _marketingWallet, 
     address _vestingWalletAdmin,
     address _growthReserveWallet,
     address _founderWallet,
     address _treasuryWallet,        
    address _futureDAOReserve,
    address _userIncentiveWallet,        
    address _companyIncentiveWallet    )
       
        ERC20("Silvagnum", "SVGM")
        MATICReflectionMechanics(1_000_000 * 10 ** 18, router)

    {   /// @dev Validates that critical wallet addresses are not the zero address.
        require(_marketingWallet != address(0), "Invalid marketing wallet");
        require(_vestingWalletAdmin != address(0), "Invalid vesting wallet admin");
        require(_growthReserveWallet != address(0), "Invalid growth wallet");
        require(_founderWallet != address(0), "Invalid founder wallet");
        require(_treasuryWallet != address(0), "Invalid treasury wallet");
        require(_futureDAOReserve != address(0), "Invalid DAO reserve");
        require(_userIncentiveWallet != address(0), "Invalid user incentive wallet");
        require(_companyIncentiveWallet != address(0), "Invalid company incentive wallet");
        
        /// @dev Assigns wallet addresses to state variables.
        marketingWallet = _marketingWallet;
        vestingWalletAdmin = _vestingWalletAdmin;
        growthReserveWallet = _growthReserveWallet;
        founderWallet = _founderWallet;
        treasuryWallet = _treasuryWallet;
        futureDAOReserve = _futureDAOReserve;
        userIncentiveWallet = _userIncentiveWallet;
        companyIncentiveWallet = _companyIncentiveWallet;
        
   
        /// @dev Configures which addresses are exempt from transaction limits (maxTxAmount, maxWalletAmount,txDelaySeconds).
        isExcludedFromLimits[_marketingWallet] = true;
        isExcludedFromLimits[_vestingWalletAdmin] = true;
        isExcludedFromLimits[_growthReserveWallet] = true;

        /// @notice Ensures the founder's wallet is subject to all trading limitations.
        /// @dev The founderWallet is not excluded from transaction size limits, wallet size limits, or transaction cooldowns.
        /// This line explicitly sets `isExcludedFromLimits[founderWallet] = false`, meaning:
       ///
       /// 1. The founder (contract deployer or project owner) is treated like any regular token holder.
       /// 2. The founder's wallet will respect the same `maxTxAmount`, `maxWalletAmount`, and `txDelaySeconds` restrictions.
       /// 3. This promotes fairness, transparency, and trust among the community and investors.
       /// 4. No administrative privilege is used to bypass standard transfer rules for the founder.
        isExcludedFromLimits[founderWallet] = false;
        
        isExcludedFromLimits[treasuryWallet] = true;
        isExcludedFromLimits[futureDAOReserve] = true;
        isExcludedFromLimits[userIncentiveWallet] = true;
        isExcludedFromLimits[companyIncentiveWallet] = true;
        isExcludedFromLimits[address(this)] = true;
        isExcludedFromLimits[msg.sender] = true;
        isExcludedFromLimits[address(uniswapRouter)] = true;
        isExcludedFromLimits[address(0)] = true;
        

        /// @dev Configures which addresses are exempt from the reflection fee.
        _excludeFromReflectionFee(_marketingWallet, true);
        _excludeFromReflectionFee(_vestingWalletAdmin, true);
        _excludeFromReflectionFee(_growthReserveWallet, true);
        
       // Founder wallet is intentionally not excluded from fees to ensure fairness.
        _excludeFromReflectionFee(founderWallet, false);
        _excludeFromReflectionFee(treasuryWallet, true);
        _excludeFromReflectionFee(futureDAOReserve, true);
        _excludeFromReflectionFee(userIncentiveWallet, true);
        _excludeFromReflectionFee(companyIncentiveWallet, true);
        _excludeFromReflectionFee(address(this), true);
        _excludeFromReflectionFee(msg.sender, true);
        _excludeFromReflectionFee(address(uniswapRouter), true);
        
        _excludeFromReflectionFee(address(0), true);

        
        
        /// @dev Defines the initial token allocations for various ecosystem purposes.
        uint256 founderAllocation = 100_000_000 * 10 ** 18;
        uint256 vested = 900_000_000 * 10 ** 18;   
        uint256 idoTokens = IDO_TOKENS_ALLOCATED;   
        uint256 growthReserve = 500_000_000 * 10 ** 18; 
      
        uint256 treasury  = 3_500_000_000 * 10 ** 18;   
        uint256 daoReserve   = 800_000_000 * 10 ** 18;    
        uint256 userIncentives = 100_000_000 * 10 ** 18;
        uint256 companyIncentives = 100_000_000 * 10 ** 18;


        
        /// @dev Verifies that total allocations do not exceed the initial supply.
        require(
                founderAllocation + vested + idoTokens + growthReserve + treasury + daoReserve + userIncentives + companyIncentives <= INITIAL_SUPPLY,
                "Allocation overflow"
                );
        

        /// @dev Sets initial transaction and wallet limits for anti-dumping.
        maxTxAmount = INITIAL_SUPPLY / 1200;// Approx. 0.083% of total supply
        maxWalletAmount = INITIAL_SUPPLY / 100;// 1% of total supply
      
      
        /// @dev Deploys and configures the AdvancedDividendTracker contract.
        advancedDividendTracker = new AdvancedDividendTracker(
            IERC20(address(this)),
            312_500 * 10 ** 18  
        );
        
        
        isExcludedFromLimits[address(advancedDividendTracker)] = true;
        _excludeFromReflectionFee(address(advancedDividendTracker), true);
        dividendTracker = address(advancedDividendTracker);
        advancedDividendTracker.excludeFromDividends(address(this), true);
        advancedDividendTracker.excludeFromDividends(msg.sender, true);
         
         /// @dev Mints the total supply to the deployer before distribution.
        _mint(msg.sender, INITIAL_SUPPLY);
        


        /// @dev Deploys and configures the EnhancedLiquidityManager contract.
        liquidityManager = new EnhancedLiquidityManager(
            address(uniswapRouter),
            address(this),
            _marketingWallet
        );
        
        
        liquidityManager.setMinTokensBeforeSwap(500 * 10**18);
        liquidityManager.setSlippage(200);
        liquidityManager.transferOwnership(address(this));
        require(liquidityManager.owner() == address(this), "Ownership transfer failed");
        emit LiquidityManagerConfigured(address(liquidityManager));

        isExcludedFromLimits[address(liquidityManager)] = true;
        _excludeFromReflectionFee(address(liquidityManager), true);

        /// @dev Deploys and configures the SilvagnumVestingWallet.
        silvagnumVesting = new SilvagnumVestingWallet(
            _vestingWalletAdmin,
            uint64(block.timestamp),
            365 days
        );
        isExcludedFromLimits[address(silvagnumVesting)] = true;
        _excludeFromReflectionFee(address(silvagnumVesting), true);
       
        
        /// @dev Configures which special wallets are excluded from receiving dividends.
        advancedDividendTracker.excludeFromDividends(address(silvagnumVesting), true);
        advancedDividendTracker.excludeFromDividends(address(liquidityManager), true);
        advancedDividendTracker.excludeFromDividends(growthReserveWallet, true); 
        advancedDividendTracker.excludeFromDividends(founderWallet, false); // Founder wallet is eligible for dividends.
        advancedDividendTracker.excludeFromDividends(treasuryWallet, true);
        advancedDividendTracker.excludeFromDividends(futureDAOReserve, true);
        advancedDividendTracker.excludeFromDividends(userIncentiveWallet, true);
        advancedDividendTracker.excludeFromDividends(companyIncentiveWallet, true);
        advancedDividendTracker.excludeFromDividends(_marketingWallet, true);
        

        /// @dev Distributes the allocated tokens from the deployer to the respective wallets.
       super._transfer(msg.sender, founderWallet, founderAllocation);
       emit FounderTokensAllocated(founderWallet, founderAllocation);
        
        super._transfer(msg.sender, address(silvagnumVesting), vested);
       
        super._transfer(msg.sender, growthReserveWallet, growthReserve);
        super._transfer(msg.sender, treasuryWallet, treasury);             
        emit TreasuryAllocated(treasuryWallet, treasury);
        super._transfer(msg.sender, futureDAOReserve, daoReserve);         
        emit DAOTokensReserved(futureDAOReserve, daoReserve);
        super._transfer(msg.sender, userIncentiveWallet, userIncentives);
        emit UserIncentiveFunded(userIncentiveWallet, userIncentives);
        super._transfer(msg.sender, companyIncentiveWallet, companyIncentives);
        emit CompanyIncentiveFunded(companyIncentiveWallet, companyIncentives);
       // Transfers the IDO allocation to this contract to hold for the sale.
        super._transfer(msg.sender, address(this), idoTokens);
        
        /// @dev Initializes trading as inactive. It must be enabled manually by an admin.
        tradingActive = false;

        
         /// @dev Burns any remaining tokens from the deployer's wallet to ensure fair distribution.
        uint256 remaining = balanceOf(msg.sender);
        if (remaining > 0) {
           _burn(msg.sender, remaining);
           emit TokensBurned(remaining);
        }

           

       /// @dev Grants the master admin role (DEFAULT_ADMIN_ROLE) to the deployer.
       /// @dev This account is now the "super admin" and can manage all other roles.(After the deployment, the deployer will transfer this role to a multisig wallet for security).
       _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

       /// @dev Grants the operational roles to the deployer for direct access to all functions.
       _grantRole(ADMIN_ROLE, msg.sender);
       _grantRole(DIVIDEND_MANAGER_ROLE, msg.sender);
       _grantRole(LIQUIDITY_MANAGER_ROLE, msg.sender);

       /// @dev Sets ADMIN_ROLE as the manager for the dividend and liquidity roles.
       /// @dev This allows for flexible role management by any account holding the ADMIN_ROLE.
       _setRoleAdmin(DIVIDEND_MANAGER_ROLE, ADMIN_ROLE);
       _setRoleAdmin(LIQUIDITY_MANAGER_ROLE, ADMIN_ROLE);

      /// @dev Grants the liquidity manager role to the contract itself to handle automated fees.
      _grantRole(LIQUIDITY_MANAGER_ROLE, address(this));

     /// @dev Grants all operational roles to the designated vesting/multisig admin for security and governance.
     /// @dev The check prevents redundant grants if the vesting admin is also the deployer.
    if (_vestingWalletAdmin != address(0) && _vestingWalletAdmin != msg.sender) {
        _grantRole(ADMIN_ROLE, _vestingWalletAdmin);
        _grantRole(DIVIDEND_MANAGER_ROLE, _vestingWalletAdmin);
        _grantRole(LIQUIDITY_MANAGER_ROLE, _vestingWalletAdmin);
    }
        
}

    // IDO FUNCTIONS 
    
    /// @notice Calculates the current price per token based on the number of tokens already sold.
    /// @dev Implements a linear bonding curve where the price increases with each token sold.
    /// @return The current price of one full token in wei.
    function getCurrentPrice() public view returns (uint256) {
        if (idoTokensSold == 0) {
            return BASE_PRICE;
        }
        
        // Calculate price based on tokens sold
        uint256 tokensInEther = idoTokensSold / PRICE_PRECISION;
        uint256 priceIncrease = PRICE_SLOPE * tokensInEther;
        
        // Overflow check
        require(BASE_PRICE <= type(uint256).max - priceIncrease, "Price overflow");
        
        return BASE_PRICE + priceIncrease;
    }
    
    /// @notice Calculates how many Silvagnum tokens will be received for a given amount of MATIC at the current price.
    /// @param maticAmount The amount of MATIC to be contributed.
    /// @return The corresponding amount of Silvagnum (SVGM) tokens that will be purchased.
    function calculateTokensForMatic(uint256 maticAmount) public view returns (uint256) {
        require(maticAmount > 0, "Invalid MATIC amount");
        
        uint256 currentPrice = getCurrentPrice();
        
        
        uint256 tokens = (maticAmount * PRICE_PRECISION) / currentPrice;
        
        return tokens;
    }
    
    /// @notice Returns a summary of the current state of the IDO.
    /// @return tokensAllocated The total tokens available for the IDO.
    /// @return tokensSold The amount of tokens sold so far.
    /// @return maticRaised The amount of MATIC raised so far.
    /// @return currentPrice The current price per token in wei.
    /// @return remainingTokens The number of tokens still available for sale.
    /// @return active Whether the IDO is currently active.
    /// @return finalized Whether the IDO has been finalized.
    function getIDOInfo() external view returns (
        uint256 tokensAllocated,
        uint256 tokensSold,
        uint256 maticRaised,
        uint256 currentPrice,
        uint256 remainingTokens,
        bool active,
        bool finalized
    ) {
        return (
            IDO_TOKENS_ALLOCATED,
            idoTokensSold,
            idoMaticRaised,
            getCurrentPrice(),
            IDO_TOKENS_ALLOCATED - idoTokensSold,
            idoActive,
            idoFinalized
        );
    }
    
    /// @notice Starts the IDO, allowing users to begin contributing.
    /// @dev Can only be called by an address with ADMIN_ROLE.
    function startIDO() external onlyRole(ADMIN_ROLE) {
        require(!idoActive, "IDO already started");
        require(!idoFinalized, "IDO already finalized");
        require(balanceOf(address(this)) >= IDO_TOKENS_ALLOCATED, "Insufficient tokens in contract");
        
        idoActive = true;
        emit IDOStarted(block.timestamp);
    }
    
    /// @notice Allows a user to participate in the IDO by sending MATIC.
    /// @dev This is a payable function. The sent MATIC is used to purchase Silvagnum (SVGM) tokens.
    /// @dev Reverts if the IDO is not active, contribution limits are violated, or the hard cap is reached.
    function participateInIDO() external payable nonReentrant {
        require(idoActive, "IDO not active");
        require(!idoFinalized, "IDO already finalized");
        require(msg.value >= MIN_CONTRIBUTION, "Contribution too low");
        require(idoContributions[msg.sender] + msg.value <= MAX_CONTRIBUTION, "User contribution limit exceeded");
        require(idoMaticRaised + msg.value <= IDO_HARD_CAP, "Hard cap reached");

        uint256 tokensToReceive = calculateTokensForMatic(msg.value);
        require(idoTokensSold + tokensToReceive <= IDO_TOKENS_ALLOCATED, "Not enough IDO tokens available");
        require(balanceOf(address(this)) >= tokensToReceive, "Contract has insufficient tokens");

        // Update state
        idoTokensSold += tokensToReceive;
        idoMaticRaised += msg.value;
        idoContributions[msg.sender] += msg.value;
        idoTokensPurchased[msg.sender] += tokensToReceive;

        // Transfer tokens
        super._transfer(address(this), msg.sender, tokensToReceive);
        _updateDividendTrackerBalance(msg.sender); 

        emit IDOContribution(msg.sender, msg.value, tokensToReceive, getCurrentPrice());
    }
    
    /// @notice Finalizes the IDO after it has been started.
    /// @dev Can only be called by an address with ADMIN_ROLE.
    /// @dev If the soft cap is met, it distributes funds (70% to liquidity, 30% to marketing) and locks the liquidity.
    /// @dev If the soft cap is not met, it enables refunds for all contributors.
    function finalizeIDO() external onlyRole(ADMIN_ROLE) nonReentrant {
        require(idoActive, "IDO not active");
        require(!idoFinalized, "IDO already finalized");
        
        idoActive = false;
        idoFinalized = true;

        if (idoMaticRaised >= IDO_SOFT_CAP) {
            // Soft cap reached - distribute funds
            uint256 liquidityAmount = (idoMaticRaised * 70) / 100;
            uint256 projectAmount = idoMaticRaised - liquidityAmount;

            // Transfer project's share
            if (projectAmount > 0) {
                payable(marketingWallet).transfer(projectAmount);
            }

            // Add and lock liquidity
            if (liquidityAmount > 0 && balanceOf(address(this)) > 0) {
                uint256 currentPrice = getCurrentPrice();
                uint256 tokensForLiquidity = (liquidityAmount * PRICE_PRECISION) / currentPrice;
                
                
                uint256 availableTokens = balanceOf(address(this));
                if (tokensForLiquidity > availableTokens) {
                    tokensForLiquidity = availableTokens;
                }

                if (tokensForLiquidity > 0) {
                    _approve(address(this), address(liquidityManager), tokensForLiquidity);
                    liquidityManager.addLiquidityAndLock{value: liquidityAmount}(
                        tokensForLiquidity, 
                        block.timestamp + 365 days // 1 year lock
                    );
                }
            }

            emit IDOFinalized(liquidityAmount, projectAmount);
        } else {
            // Soft cap not reached - enable refunds
            refundEnabled = true;
        }
    }

      /// @notice Allows a contributor to claim a refund if the IDO failed to meet its soft cap.
    /// @dev To claim a refund, the user must hold all the tokens they purchased during the IDO. This prevents abuse.
    function claimRefund() external nonReentrant {
        require(idoFinalized, "IDO not finalized");
        require(refundEnabled, "Refund not available");
        require(idoContributions[msg.sender] > 0, "No contribution found");

        uint256 maticToRefund = idoContributions[msg.sender];
        uint256 tokensToReturn = idoTokensPurchased[msg.sender];

        
        require(
            balanceOf(msg.sender) >= tokensToReturn,
            "You must return all IDO tokens to claim a refund"
        );

        // Transfer tokens back to the contract
        super._transfer(msg.sender, address(this), tokensToReturn);

       // Clear state to prevent multiple claims
        idoContributions[msg.sender] = 0;
        idoTokensPurchased[msg.sender] = 0;

        // Securely transfer MATIC back to the contributor
        (bool success, ) = payable(msg.sender).call{value: maticToRefund}("");
        require(success, "Failed to transfer MATIC");

        emit IDORefund(msg.sender, maticToRefund, tokensToReturn);
    }


    /// @notice Allows an admin to withdraw any remaining MATIC from the contract after a finalized or failed IDO.
    /// @dev A safety function to retrieve funds. Sends MATIC to the marketing wallet.
    function emergencyWithdraw() external onlyRole(ADMIN_ROLE) nonReentrant {
        require(idoFinalized || !idoActive, "IDO is still active");
        
        uint256 contractBalance = address(this).balance;
        if (contractBalance > 0) {
            payable(marketingWallet).transfer(contractBalance);
            emit EmergencyWithdraw(msg.sender, contractBalance);
        }
    }
    
    /// @notice Allows an admin to withdraw any unallocated Silvagnum tokens from this contract after the IDO is finalized.
    /// @dev Primarily for sweeping any leftover tokens that were not sold or used for liquidity.
    function withdrawUnallocatedTokens() external onlyRole(ADMIN_ROLE) {
        require(idoFinalized, "IDO not finalized");
        
        uint256 remainingTokens = balanceOf(address(this));
        if (remainingTokens > 0) {
            super._transfer(address(this), marketingWallet, remainingTokens);
        }
    }

    /// @notice Allows an admin to withdraw all MATIC from the dividend tracker contract in an emergency.
    /// @dev This is a critical security function that moves funds from the tracker to the main contract owner.
    function emergencyWithdrawTrackerMATIC() external onlyRole(ADMIN_ROLE) nonReentrant {
        require(address(advancedDividendTracker) != address(0), "Tracker not deployed");

        uint256 balanceBeforeWithdraw = address(advancedDividendTracker).balance; 

        // Call the tracker's emergency function
        advancedDividendTracker.emergencyWithdrawMATIC();

        // Forward the received MATIC to the contract owner
        (bool success, ) = payable(owner()).call{value: balanceBeforeWithdraw}("");
        require(success, "Silvagnum: Failed to send MATIC to owner"); 
}



   //  CORE ADMINISTRATIVE & TRADING FUNCTIONS 
   /// @notice Sets a new admin address for the vesting contract and grants it all governance roles.
    /// @dev Can only be called by an address with ADMIN_ROLE. This function is critical for transferring administrative power,
    /// for example, to a multisig wallet after initial setup.
    /// @param _vestingWalletAdmin The address of the new vesting admin.
    function setVestingWalletAdmin(address _vestingWalletAdmin) external onlyRole(ADMIN_ROLE) {
        require(_vestingWalletAdmin != address(0), "Invalid address");
        vestingWalletAdmin = _vestingWalletAdmin;
        _grantRole(ADMIN_ROLE, _vestingWalletAdmin);
        _grantRole(DIVIDEND_MANAGER_ROLE, _vestingWalletAdmin);
        _grantRole(LIQUIDITY_MANAGER_ROLE, _vestingWalletAdmin);
    }
   
   /// @dev Modifier that restricts access to a function to either the `vestingWalletAdmin` or an address with the `ADMIN_ROLE`.
    /// @dev This provides a flexible governance model, allowing both a primary admin and a designated multisig to perform critical operations.
    modifier onlyMultiSigOrAdmin() {
        require(
            msg.sender == vestingWalletAdmin || hasRole(ADMIN_ROLE, msg.sender),
            "Caller is not MultiSig or Admin"
        );
        _;
    }
    
     /// @notice Enables public trading on the DEX.
    /// @dev Can only be called once by an ADMIN_ROLE. It sets the Uniswap pair address,
    /// excludes the pair from limits, activates the `tradingActive` flag, and records the `launchTime`.
    /// @param _uniswapPair The address of the created SVGM/MATIC liquidity pool pair.
    function enableTrading(address _uniswapPair) external onlyRole(ADMIN_ROLE) {
        require(!tradingActive, "Trading already enabled");
        _setUniswapPair(_uniswapPair);
        isExcludedFromLimits[_uniswapPair] = true;
        tradingActive = true;
        launchTime = block.timestamp;
        emit TradingStatusChanged(true);
    }
    
    /// @notice Updates the anti-dump security limits for transactions.
    /// @dev Can only be called by an admin or the designated multisig.
    /// @param _maxTxAmount The new maximum transaction amount.
    /// @param _maxWalletAmount The new maximum wallet holding amount.
    /// @param _txDelaySeconds The new cooldown period between transactions for an address.
    function updateLimits(
        uint256 _maxTxAmount, 
        uint256 _maxWalletAmount,
        uint256 _txDelaySeconds
    ) external onlyMultiSigOrAdmin {
        require(_maxTxAmount >= totalSupply() / 1000, "Max transaction amount too low");
        require(_maxWalletAmount >= totalSupply() / 100, "Max wallet size too low");
        
        maxTxAmount = _maxTxAmount;
        maxWalletAmount = _maxWalletAmount;
        txDelaySeconds = _txDelaySeconds;
        
        emit LimitsUpdated(_maxTxAmount, _maxWalletAmount, _txDelaySeconds);
    }
    
     /// @notice Configures the parameters for the anti-snipe bot mechanism.
    /// @dev Can only be called by an admin or the designated multisig.
    /// @param _duration The new duration for the anti-bot period in seconds.
    /// @param _fee The new penalty fee percentage for bot-flagged transactions.
    /// @param _threshold The new transaction amount threshold (as a % of maxTxAmount) to trigger bot detection.
    function setAntiBotConfig(
         uint256 _duration, 
         uint256 _fee, 
         uint256 _threshold
     ) external onlyMultiSigOrAdmin {
         require(_fee <= 30, "Maximum fee is 30%");
         antiBotPeriod = _duration;
         snipeFee = _fee;
         snipeThreshold = _threshold;
    }
     
     /// @notice Excludes an account from all transaction limits (maxTxAmount, maxWalletAmount, txDelay).
    /// @dev Can only be called by an admin or the designated multisig.
    /// @param account The address of the account to exclude or include.
    /// @param excluded The boolean status (true to exclude, false to include).
    function excludeFromLimits(address account, bool excluded) external onlyMultiSigOrAdmin {
        isExcludedFromLimits[account] = excluded;
        emit LimitsExcluded(account, excluded);
    }
  
  /// @notice The core token transfer function, overriding the standard ERC20._transfer.
    /// @dev This function incorporates all custom logic, including security checks, anti-bot measures, and fee collection
    /// before executing the final token transfer. The logic is applied sequentially.
  function _transfer(address from, address to, uint256 amount) internal override {
    require(from != address(0), "ERC20: transfer from zero");
    require(to != address(0), "ERC20: transfer to zero");

    /// @dev Initial security checks are performed on the gross transfer amount, before any fees are taken.
    if (from != address(this) && to != address(this) && msg.sender != address(this)) {
        if (!isExcludedFromLimits[from] && !isExcludedFromLimits[to]) {
            require(tradingActive, "Trading is disabled");
        }
        if (!isExcludedFromLimits[from]) {
            require(amount <= maxTxAmount, "Transaction limit exceeded (gross amount)");
        }
    }

    /// @dev Applies anti-bot/snipe fees for sales made within the configured anti-bot period after launch.
    if (block.timestamp < launchTime + antiBotPeriod && tradingActive) {
        if (to == uniswapPair) {
            _sellCount[from]++;
            if (_sellCount[from] > maxSellsPerAddress) {
                emit SellLimitHit(from, _sellCount[from]);
            }

            
            if (amount > (maxTxAmount * snipeThreshold) / 100 || _sellCount[from] > maxSellsPerAddress) {
                uint256 snipeFeeAmount = (amount * snipeFee) / 100;
                if (snipeFeeAmount > 0 && amount > snipeFeeAmount) {
                    super._transfer(from, address(this), snipeFeeAmount);
                    amount -= snipeFeeAmount;
                } else {
                    revert("Transfer: snipe fee exceeds amount");
                }
                emit BotCaught(from, amount);
            }
        }
    }

    if (amount == 0) {
        super._transfer(from, to, 0);
        return;
    }
    /// @dev Determines if fees should be applied based on the sender/receiver exclusion status.
    bool takeFee = !(isExcludedFromReflectionFee(from) || isExcludedFromReflectionFee(to));
    
    /// @dev If fees are applicable, collects and transfers reflection and liquidity fees.
    if (takeFee) {
        uint256 reflectionAmount = _getReflectionFeeAmount(amount);
        if (reflectionAmount > 0 && amount > reflectionAmount) {
            super._transfer(from, address(this), reflectionAmount);
            amount -= reflectionAmount;
            _handleReflectionFee(from); // This may trigger a swap to MATIC.
        }

        uint256 liquidityAmount = (amount * liquidityFee) / 100;
        if (liquidityAmount > 0 && amount > liquidityAmount) {
            super._transfer(from, address(liquidityManager), liquidityAmount);
            amount -= liquidityAmount;
        }
    }

    /// @dev Final security checks are performed on the net transfer amount, after fees are deducted.
        // Wallet holding limit check.
    if (!isExcludedFromLimits[to] && to != address(this)) {
        require(balanceOf(to) + amount <= maxWalletAmount, "Wallet limit exceeded");
    }

    // Transaction cooldown for sales to the DEX.
    if (!isExcludedFromLimits[from] && to == uniswapPair && from != address(this) && msg.sender != address(this)) {
        require(
            block.timestamp >= lastTxTimestamp[from] + txDelaySeconds,
            "Swap cooldown active"
        );
        lastTxTimestamp[from] = block.timestamp;
    }
    /// @dev Executes the final transfer and updates dividend tracker balances for both sender and receiver.
    super._transfer(from, to, amount);
    _updateDividendTrackerBalance(from);
    _updateDividendTrackerBalance(to);
}

/// @dev Standard OpenZeppelin hook executed before any token transfer. Can be used for future logic.
 function _beforeTokenTransfer(
    address from,
    address to,
    uint256 amount
) internal virtual override {
    super._beforeTokenTransfer(from, to, amount);
}

/// @dev Private helper function to update an account's balance in the dividend tracker.
    /// @dev This ensures the dividend calculations are always based on the most current token balance.
    /// @param account The address of the user to update.
    function _updateDividendTrackerBalance(address account) private {
    if (
        address(advancedDividendTracker) != address(0) &&
        !advancedDividendTracker.isExcludedFromDividends(account)
    ) {
        advancedDividendTracker.setBalance(account, balanceOf(account));
    }
}

    /// @dev Internal function to approve the Uniswap router to spend tokens on behalf of an owner.
    /// @dev This is an override required by the MATICReflectionMechanics abstract contract.
    function _approveForRouter(address owner_, uint256 amount) internal override {
        _approve(owner_, address(uniswapRouter), amount);
    }
    
     /// @notice A simple wrapper for the standard `balanceOf` function to comply with an interface.
    /// @param account The address to query the balance of.
    /// @return The token balance of the specified account.
    function tokenBalanceOf(address account) public view override returns (uint256) {
        return balanceOf(account);
    }
    
    /// @notice Sets the Uniswap V2 pair address after it has been created.
    /// @dev Can only be called by an admin or the designated multisig. Excludes the pair from transaction limits.
    /// @param pair The address of the SVGM/MATIC liquidity pool pair.
    function setPairAddress(address pair) external onlyMultiSigOrAdmin {
        _setUniswapPair(pair);
        isExcludedFromLimits[pair] = true;
    }
    
    /// @notice Sets the minimum number of tokens to be accumulated in the contract before an automatic swap and liquify event is triggered.
    /// @dev Can only be called by an admin or the designated multisig. This is an override from MATICReflectionMechanics.
    /// @param amount The new threshold in token units (including decimals).
    function setSwapTokensAtAmount(uint256 amount) external override onlyMultiSigOrAdmin {
        require(amount > 0, "Amount must be greater than 0");
        require(amount <= totalSupply() / 100, "Amount too high"); // Cannot be more than 1% of total supply
        swapTokensAtAmount = amount;
    }

   
    
 /// @notice Allows an admin to set the LP token address in the liquidity manager contract.
/// @dev This is a critical step after creating the liquidity pool on the DEX.
/// @param _lpToken The address of the SVGM/MATIC LP token.
function setLiquidityManagerLpToken(address _lpToken) external onlyRole(ADMIN_ROLE) {
    require(_lpToken != address(0), "LP token address cannot be zero");
    liquidityManager.setLpToken(_lpToken);
}

 /// @notice Allows an admin to set the external liquidity locker contract address (e.g., Unicrypt).
    /// @dev This address is used by the liquidity manager to lock LP tokens.
    /// @param _lockerAddress The address of the third-party locker service.
function setLiquidityManagerLockerAddress(address _lockerAddress) external onlyRole(ADMIN_ROLE) {
    require(_lockerAddress != address(0), "Locker address cannot be zero");
    liquidityManager.setLiquidityLockerAddress(_lockerAddress);
}

   /// @notice Configures an external contract (e.g., NFT staking, DAO) to be exempt from fees and limits.
    /// @dev Can only be called by an admin. This is essential for ecosystem interoperability.
    /// @param incentiveContract The address of the contract to be configured.
    function configureIncentiveContract(address incentiveContract) external onlyRole(ADMIN_ROLE) {
        require(incentiveContract != address(0), "Incentive contract: zero address");

        isExcludedFromLimits[incentiveContract] = true;
        _excludeFromReflectionFee(incentiveContract, true);
        advancedDividendTracker.excludeFromDividends(incentiveContract, true);

        emit IncentiveContractConfigured(incentiveContract);
    }
  
    
    /// @notice Returns the amount of tokens that are currently available to be released from the vesting contract.
    /// @return The amount of releasable tokens.
    function vestedBalanceAvailable() external view returns (uint256) {
        return silvagnumVesting.releasable(address(this));
    }
    
     /// @notice Triggers the release of available vested tokens from the vesting wallet to this contract.
    /// @dev Can only be called by an admin or the designated multisig. Protected against re-entrancy.
    function releaseVestedTokens() external onlyMultiSigOrAdmin nonReentrant {
        silvagnumVesting.release(address(this));
    }
    
    /// @notice Sets the maximum number of sell transactions an address can perform during the anti-bot period.
    /// @dev Can only be called by an admin.
    /// @param _max The new maximum number of sells (must be between 1 and 10).
    function setMaxSellsPerAddress(uint256 _max) external onlyRole(ADMIN_ROLE) {
        require(_max >= 1 && _max <= 10, "Must be between 1 and 10 sells");
        maxSellsPerAddress = _max;
    }
    
    /// @notice Updates the minimum token balance required for an account to be eligible for dividends.
    /// @dev Can only be called by an admin or multisig. Proxies the call to the AdvancedDividendTracker contract.
    /// @param newMinBalance The new minimum balance (e.g., for 10,000 tokens, pass 10000).
    function updateMinimumDividendBalance(uint256 newMinBalance) external onlyMultiSigOrAdmin {
        advancedDividendTracker.setMinimumTokenBalanceForDividends(newMinBalance * 10 ** 18);
    }
    
    /// @notice Manually triggers the dividend processing mechanism for a specific amount of gas.
    /// @dev Can only be called by an address with the DIVIDEND_MANAGER_ROLE.
    /// @param gas The amount of gas to be consumed by the processing loop.
    function manualProcessDividends(uint256 gas) external onlyRole(DIVIDEND_MANAGER_ROLE) {
        advancedDividendTracker.process(gas);
    }
    
     /// @notice [ADMIN] Sets the claim cooldown on the AdvancedDividendTracker.
     /// @dev Proxies the call through the main contract to respect ownership.
     /// @param newWait The new cooldown period in seconds.
    function adminSetClaimWait(uint256 newWait) external onlyRole(ADMIN_ROLE) {
        require(address(advancedDividendTracker) != address(0), "Tracker not set");
        advancedDividendTracker.setClaimWait(newWait);
    }

    /// @notice [ADMIN] Sets the minimum dividend amount to claim on the AdvancedDividendTracker.
    /// @dev Proxies the call through the main contract.
    /// @param amount The new minimum amount in wei.
    function adminSetMinimumDividendToClaim(uint256 amount) external onlyRole(ADMIN_ROLE) {
        require(address(advancedDividendTracker) != address(0), "Tracker not set");
        advancedDividendTracker.setMinimumDividendToClaim(amount);
    }

    /// @notice [ADMIN] Excludes or includes an account from dividend distribution.
    /// @dev Proxies the call to the AdvancedDividendTracker, protected by ADMIN_ROLE.
    /// @param account The address of the user to update.
    /// @param excluded The new exclusion status.
    function adminExcludeFromDividends(address account, bool excluded) external onlyRole(ADMIN_ROLE) {
        require(address(advancedDividendTracker) != address(0), "Tracker not set");
        advancedDividendTracker.excludeFromDividends(account, excluded);
    }

     /// @notice Excludes an account from reflection fees.
    /// @dev Can only be called by an admin or the designated multisig.
    /// @param account The address of the account to exclude or include.
    /// @param excluded The boolean status (true to exclude, false to include).
    function excludeFromFee(address account, bool excluded) external onlyMultiSigOrAdmin {
        _excludeFromReflectionFee(account, excluded);
    }
    
    /// @notice Manually triggers the processing of accumulated fees for liquidity.
    /// @dev Can only be called by an address with the LIQUIDITY_MANAGER_ROLE.
    /// @dev Proxies the call to `processFees` on the EnhancedLiquidityManager contract.
    function processLiquidity() external onlyRole(LIQUIDITY_MANAGER_ROLE) nonReentrant {
        require(
            IERC20(address(this)).balanceOf(address(liquidityManager)) >= liquidityManager.minTokensBeforeSwap(),
            "Silvagnum: Insufficient tokens to process"
        );
        liquidityManager.processFees();
    }
    
    /// @notice Configures multiple parameters on the liquidity manager contract at once.
    /// @dev Can only be called by an admin or the designated multisig.
    /// @param _minTokens The new minimum tokens threshold for swaps.
    /// @param _slippageDivisor The new slippage divisor (e.g., 200 for 0.5%).
    /// @param _marketingWallet The new marketing wallet address.
    function configureLiquidityManager(
        uint256 _minTokens,
        uint256 _slippageDivisor,
        address _marketingWallet
    ) external onlyMultiSigOrAdmin {
        require(_minTokens > 0, "Silvagnum: Min tokens must be > 0");
        require(_slippageDivisor >= 100, "Silvagnum: Slippage too high");
        require(_marketingWallet != address(0), "Silvagnum: Invalid marketing wallet");
        liquidityManager.setMinTokensBeforeSwap(_minTokens);
        liquidityManager.setSlippage(_slippageDivisor);
        liquidityManager.setMarketingWallet(_marketingWallet);
    }
    
     /// @dev Internal implementation for excluding an account from reflection fees.
    function _excludeFromReflectionFee(address account, bool excluded) internal {
        _isExcludedFromReflectionFee[account] = excluded;
        emit ExcludedFromReflectionFee(account, excluded);
}
    
    /// @notice Public view function to check if an account is excluded from transaction limits.
    /// @param account The address to check.
    /// @return True if the account is excluded, false otherwise.
    function isExcludedFromLimit(address account) external view returns (bool) {
         return isExcludedFromLimits[account];
}

     /// @dev Internal function to set the Uniswap pair address.
    function _setUniswapPair(address _pair) internal {
        require(_pair != address(0), "Cannot be zero address");
        uniswapPair = _pair;
    }

    
   /// @notice The contract's receive function to accept MATIC payments.
    /// @dev It only accepts MATIC from whitelisted system contracts (like the router or vesting wallet) to prevent
    /// users from accidentally sending MATIC directly to the token contract and locking their funds.
   receive() external payable override {
    if (
        msg.sender == address(silvagnumVesting) ||
        msg.sender == address(uniswapRouter) ||
        msg.sender == address(liquidityManager) ||
        msg.sender == address(advancedDividendTracker) ||
        msg.sender == address(uniswapPair) 
    ) {
        return;
    }
     revert UnauthorizedMaticDeposit(); 
}
}