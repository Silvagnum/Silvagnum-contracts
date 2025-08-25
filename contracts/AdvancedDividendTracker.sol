// AdvancedDividendTracker.sol

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
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


/// @title Advanced Dividend Tracker for MATIC Rewards
/// @author Silvagnum's Founder
/// @notice Handles the accounting and distribution of MATIC rewards to eligible token holders.
/// @dev Uses magnified arithmetic (2**128) to manage fractional dividend shares without precision loss.
/// This contract is designed to be owned and operated by the main Silvagnum token contract.
contract AdvancedDividendTracker is Ownable, ReentrancyGuard {
     
     using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;
   
    /// @dev Set of all addresses that hold enough tokens to be eligible for dividends.
    EnumerableSet.AddressSet private tokenHolders;

    /// @notice Tracks the last holder processed in the automatic dividend distribution queue.
    uint256 public lastProcessedIndex;
    
    /// @dev Set of all addresses explicitly excluded from receiving dividends.
    EnumerableSet.AddressSet private excludedFromDividendsAddresses;
    
    /// @dev Magnification factor to handle fractional math with integers.
    uint256 internal constant magnitude = 2**128;

     /// @dev The total dividend value per share, magnified by the magnitude factor for precision.
    uint256 public magnifiedDividendPerShare;

    
     /// @notice The minimum amount of withdrawable dividends in wei required to execute a claim.
    uint256 public minimumDividendToClaim = 10**15; // Initial value: 0.001 MATIC
    
    /// @dev Stores correction values for individual accounts to accurately calculate dividends after balance changes.
    mapping(address => int256) public magnifiedDividendCorrections;

     /// @notice Maps an account to its total amount of withdrawn dividends.
    mapping(address => uint256) public withdrawnDividends;

     /// @notice Maps an account to a boolean indicating if it's excluded from dividends.
    mapping(address => bool) public isExcludedFromDividends;

     /// @notice The total amount of MATIC ever distributed through this contract.
    uint256 public totalDividendsDistributed;
    
    /// @notice The cooldown period in seconds an account must wait between dividend claims.
    uint256 public claimWait = 3600;  // 1 hour

    /// @notice Maps an account to the timestamp of its last dividend claim.
    mapping(address => uint256) public lastClaimTimes;

    /// @notice The minimum balance of the main token an account must hold to be eligible for dividends.
    uint256 public minimumTokenBalanceForDividends;

    /// @notice The immutable address of the main token (SVGM) this tracker serves.
    IERC20 public immutable mainToken;

    /// @notice A designated address for recovering other ERC20 tokens accidentally sent to this contract.
    address public backupToken;

    /// @dev Stores the token balances of holders as known by the tracker for dividend calculations.
    mapping(address => uint256) public holderBalances;
    
     /// @notice Emitted when new MATIC is added to the dividend pool.
    /// @param amount The amount of MATIC added.
    event DividendsDistributed(uint256 amount);

    /// @notice Emitted when an account claims their dividends.
    /// @param account The recipient of the dividends.
    /// @param amount The amount of MATIC claimed.
    /// @param automatic True if the claim was triggered by the automated process, false if manually claimed by the user.
    event Claim(address indexed account, uint256 amount, bool automatic);

    /// @notice Emitted when the backup token address is updated.
    /// @param token The new backup token address.
    event BackupTokenUpdated(address indexed token);

    /// @notice Emitted upon emergency withdrawal of an ERC20 token.
    /// @param token The address of the withdrawn token.
    /// @param amount The amount of the token withdrawn.
    event EmergencyWithdrawal(address indexed token, uint256 amount);
 
    /// @notice Emitted when the claim cooldown period is updated.
    /// @param newWait The new cooldown period in seconds.
    event ClaimWaitUpdated(uint256 newWait);

    /// @notice Emitted when the minimum dividend amount for a claim is updated.
    /// @param newMin The new minimum amount in wei.
    event MinimumDividendToClaimUpdated(uint256 newMin);

    /// @notice Emitted when the minimum token balance for dividend eligibility is updated.
    /// @param newMin The new minimum token balance.
    event MinimumTokenBalanceForDividendsUpdated(uint256 newMin);
    
    /// @notice Emitted when an account's dividend eligibility status is changed.
    /// @param account The account being updated.
    /// @param isExcluded True if the account is now excluded, false otherwise.
    event ExcludedFromDividends(address indexed account, bool isExcluded);
  
     /// @notice Emitted for debugging when an account's balance is updated internally.
    event BalanceSet(address indexed account, uint256 oldBal, uint256 newBal, int256 correctionApplied);

    /// @notice Initializes the dividend tracker.
    /// @param _mainToken The address of the main ERC20 token Silvagnum(SVGM).
    /// @param _minimumTokenBalanceForDividends The initial minimum token balance required for dividend eligibility.
    constructor(IERC20 _mainToken, uint256 _minimumTokenBalanceForDividends) {
        require(address(_mainToken) != address(0), "Invalid token");
        mainToken = _mainToken;
        minimumTokenBalanceForDividends = _minimumTokenBalanceForDividends;
    }
    
    /// @notice Accepts MATIC payments and triggers dividend distribution.
    /// @dev This allows the main contract to send MATIC here to be distributed.
    receive() external payable {
        distributeDividends();
    }

    /// @dev Reverts any direct calls to the contract that are not supported.   
    fallback() external payable {
        revert("Unsupported call");
    }
    
    /// @notice Distributes received MATIC among all eligible token holders by increasing the dividend-per-share ratio.
    /// @dev This function is payable and should be called with MATIC to fund the distributions.
    function distributeDividends() public payable {
        require(msg.value > 0, "No MATIC to distribute");
        uint256 totalSupply = mainToken.totalSupply();
        if (totalSupply > 0) {
            magnifiedDividendPerShare += (msg.value * magnitude) / totalSupply;
            totalDividendsDistributed += msg.value;
            emit DividendsDistributed(msg.value);
        }
    }
    
    /// @notice Calculates the amount of MATIC dividends a specific account can withdraw right now.
    /// @param _account The address of the account to check.
    /// @return The pending, withdrawable dividend amount in wei.
    function withdrawableDividendOf(address _account) public view returns (uint256) {
        if (isExcludedFromDividends[_account]) return 0;
        return accumulativeDividendOf(_account) - withdrawnDividends[_account];
    }

    /// @notice Calculates the total dividends an account has ever earned, including what has already been withdrawn.
    /// @dev This shows the gross dividend amount before subtracting previous claims.
    /// @param _account The address of the account to check.
    /// @return The total gross dividend amount earned in wei.
    function accumulativeDividendOf(address _account) public view returns (uint256) {
        if (isExcludedFromDividends[_account]) return 0;
        
        
        uint256 balance = holderBalances[_account]; 
        
        
        uint256 magnifiedDividendUint = balance * magnifiedDividendPerShare;
        
        
        int256 correctedInt = int256(magnifiedDividendUint) + magnifiedDividendCorrections[_account];
        
        
        require(correctedInt >= 0, "Accumulated dividend cannot be negative");

        return uint256(correctedInt) / magnitude;
    }
     
   
    /// @notice Updates an account's token balance for dividend calculations.
    /// @dev This is a critical function called by the main token contract during every transfer. It adjusts an account's
    /// dividend corrections using magnified arithmetic to ensure fairness. It also adds or removes accounts
    /// from the list of eligible holders based on whether they meet the minimum balance requirement.
    /// @param account The address of the holder whose balance is being updated.
    /// @param newBalance The new token balance of the holder.
    function setBalance(address account, uint256 newBalance) public onlyOwnerOrMainToken {
        uint256 oldBalance = holderBalances[account];
        int256 correctionApplied = 0;

        // If the account is excluded, zero out its balance for dividend purposes
        // and apply a final correction based on its old balance.
        if (isExcludedFromDividends[account]) {
            if (oldBalance > 0) {
                uint256 compensation = oldBalance * magnifiedDividendPerShare;
                require(compensation <= uint256(type(int256).max), "Dividend correction overflow (excluded)");
                magnifiedDividendCorrections[account] += SafeCast.toInt256(compensation);
                correctionApplied = SafeCast.toInt256(compensation);
            }

            holderBalances[account] = 0;
            tokenHolders.remove(account);

            emit BalanceSet(account, oldBalance, newBalance, correctionApplied);
            return;
        }

         // If the new balance meets the minimum requirement for dividends.
        if (newBalance >= minimumTokenBalanceForDividends) {
            if (oldBalance == 0) {
                // This is a new holder becoming eligible. Set an initial negative correction.
                uint256 correction = magnifiedDividendPerShare * newBalance;
                require(correction <= uint256(type(int256).max), "Correction overflow (entering)");
                magnifiedDividendCorrections[account] = -SafeCast.toInt256(correction);
                correctionApplied = -SafeCast.toInt256(correction);
            } else {
                // An existing holder's balance has changed. Adjust the correction based on the difference.
                uint256 magnifiedNew = magnifiedDividendPerShare * newBalance;
                uint256 magnifiedOld = magnifiedDividendPerShare * oldBalance;

                require(magnifiedNew <= uint256(type(int256).max), "Overflow: new");
                require(magnifiedOld <= uint256(type(int256).max), "Overflow: old");

                int256 diff = SafeCast.toInt256(magnifiedNew) - SafeCast.toInt256(magnifiedOld);

                unchecked {
                    magnifiedDividendCorrections[account] -= diff;
                }

                correctionApplied = -diff;
            }

            holderBalances[account] = newBalance;
            tokenHolders.add(account);
        } else {
            // The new balance is below the minimum. Remove the holder from the dividend list.
            if (oldBalance > 0) {
                uint256 compensation = oldBalance * magnifiedDividendPerShare;
                require(compensation <= uint256(type(int256).max), "Dividend correction overflow (below minimum)");
                magnifiedDividendCorrections[account] += SafeCast.toInt256(compensation);
                correctionApplied = SafeCast.toInt256(compensation);
            }

            
            holderBalances[account] = 0;
            tokenHolders.remove(account);
        }

        emit BalanceSet(account, oldBalance, newBalance, correctionApplied);
    }



 /// @notice Processes the dividend queue, automatically sending MATIC rewards to multiple eligible holders.
    /// @dev Iterates through the list of holders in a gas-limited loop. Can be called externally to drive distribution.
    /// @param gas The maximum amount of gas the function is allowed to consume in one run.
    /// @return iterations The number of accounts checked in this run.
    /// @return claims The number of successful dividend payments made in this run.
    /// @return lastProcessedIndex The index of the last account processed, for the next run to resume.
function process(uint256 gas) public nonReentrant returns (uint256, uint256, uint256) {
    uint256 numberOfTokenHolders = tokenHolders.length();
    if (numberOfTokenHolders == 0) {
        return (0, 0, lastProcessedIndex);
    }

    uint256 _lastProcessedIndex = lastProcessedIndex;
    uint256 gasUsed = 0;
    uint256 gasLeft = gasleft();
    uint256 iterations = 0;
    uint256 claims = 0;

    while (gasUsed < gas && iterations < numberOfTokenHolders) {
        iterations++;

        _lastProcessedIndex++;
        if (_lastProcessedIndex >= numberOfTokenHolders) {
            _lastProcessedIndex = 0;
        }

        address account = tokenHolders.at(_lastProcessedIndex);

        if (isExcludedFromDividends[account]) {
            continue;
        }

        if (canAutoClaim(lastClaimTimes[account])) {
            if (withdrawableDividendOf(account) >= minimumDividendToClaim) {
                
                lastProcessedIndex = _lastProcessedIndex;

                if (processAccount(account, true)) {
                    claims++;
                }
            }
        }

        uint256 newGasLeft = gasleft();
        if (gasLeft > newGasLeft) {
            gasUsed += gasLeft - newGasLeft;
        }
        gasLeft = newGasLeft;
    }

    
    lastProcessedIndex = _lastProcessedIndex;
    return (iterations, claims, lastProcessedIndex);
}

    /// @dev Internal view function to check if an account's cooldown period has passed.
    function canAutoClaim(uint256 lastClaimTime) internal view returns (bool) {
        if (lastClaimTime > block.timestamp) {
            return false;
        }
        return block.timestamp - lastClaimTime >= claimWait;
    }
    
    /// @notice Updates the cooldown period between dividend claims for all users.
    /// @dev Can only be called by the contract owner.
    /// @param newWait The new cooldown period in seconds. Must be between 300 (5 mins) and 86400 (24 hours).
    function setClaimWait(uint256 newWait) external onlyOwner {
        require(newWait >= 300 && newWait <= 86400, "invalid range");
        claimWait = newWait;
        emit ClaimWaitUpdated(newWait);
    }
    

    /// @notice Excludes or re-includes an account from receiving dividends.
    /// @dev Can only be called by the owner or the main token contract.
    /// Automatically triggers `setBalance` to correctly adjust dividend accounting.
    /// @param account The address to update.
    /// @param excluded True to exclude the account, false to include it.
    function excludeFromDividends(address account, bool excluded) external onlyOwnerOrMainToken {
     
        bool currentlyExcluded = isExcludedFromDividends[account];
        if (currentlyExcluded == excluded) {
            return; // No change in exclusion status
        }

        isExcludedFromDividends[account] = excluded;

        if (excluded) {
            excludedFromDividendsAddresses.add(account);
            // When an address is excluded, call setBalance to adjust the correction and remove from tokenHolders
            setBalance(account, 0); 
        } else {
            excludedFromDividendsAddresses.remove(account);
            // Upon re-inclusion, the balance will be re-evaluated on the next transfer or manual setBalance call.
        }
        emit ExcludedFromDividends(account, excluded);
    }
    
    /// @notice Gets the total number of accounts currently excluded from dividends.
    /// @return The count of excluded addresses.
    function getNumberOfExcludedHolders() external view returns (uint256) {
        return excludedFromDividendsAddresses.length();
    }
    
     /// @notice Retrieves an excluded holder's address by its index.
    /// @param index The index in the set of excluded holders.
    /// @return The address of the excluded holder.
    function getExcludedHolder(uint256 index) external view returns (address) {
        return excludedFromDividendsAddresses.at(index);
    }
    
    /// @dev Internal function that performs the actual dividend payment to a single account.
    /// @return True if the payment was successful, false otherwise.
    function processAccount(address account, bool automatic) internal  returns (bool) {
        if (isExcludedFromDividends[account]) return false;

        uint256 amount = withdrawableDividendOf(account);
        require(amount >= minimumDividendToClaim, "Dividend too small");
        
        if (amount > 0) {
            withdrawnDividends[account] += amount;
            lastClaimTimes[account] = block.timestamp;
            
            (bool success, ) = payable(account).call{value: amount}("");
            require(success, "Dividend transfer failed");
            
            emit Claim(account, amount, automatic);
            return true;
        }
        return false;
    }


   
    /// @notice Allows a user to manually claim their pending MATIC dividends.
    /// @dev The call will fail if the user is excluded, the claim cooldown is active, or there are no dividends to claim.
    function claimDividend() external nonReentrant {
        require(!isExcludedFromDividends[msg.sender], "Account excluded from dividends");
        require(canAutoClaim(lastClaimTimes[msg.sender]), "Wait time not met");
        require(processAccount(msg.sender, false), "No dividend to claim");
}

    /// @notice Sets a backup token address for emergency withdrawals of other ERC20 tokens.
    /// @dev Can only be called by the owner.
    /// @param token The address of the ERC20 token to be used for recovery.
    function setBackupToken(address token) external onlyOwner {
        require(token != address(0), "Invalid token address");
        backupToken = token;
        emit BackupTokenUpdated(token);
    }
    
    /// @notice Allows the owner to withdraw any ERC20 tokens accidentally sent to this contract.
    /// @param token The address of the ERC20 token to withdraw.
    function emergencyWithdraw(address token) external onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance > 0, "No balance to withdraw");
        IERC20(token).safeTransfer(owner(), balance);
        emit EmergencyWithdrawal(token, balance);
    }
    
     /// @notice Allows the owner to withdraw all MATIC from this contract in an emergency.
    /// @dev This function sends MATIC to the caller (which should be the main Silvagnum contract).
    function emergencyWithdrawMATIC() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No MATIC");

        
        (bool success, ) = payable(msg.sender).call{value: balance}("");
        require(success, "Transfer failed");
    }
    
    /// @notice Gets the total number of accounts eligible for dividends.
    /// @return The count of eligible holders.
    function getNumberOfHolders() external view returns (uint256) {
        return tokenHolders.length();
    }
    
     /// @dev Modifier to restrict function access to the owner or the main token contract.
    modifier onlyOwnerOrMainToken() {
        require(msg.sender == owner() || msg.sender == address(mainToken), "Not authorized");
        _;
    }
     
    /// @notice Updates the minimum token balance required for dividend eligibility.
    /// @dev Can only be called by the owner or the main token contract.
    /// @param _newMinimum The new minimum balance (in full token units, e.g., 10000).
    function setMinimumTokenBalanceForDividends(uint256 _newMinimum) external onlyOwnerOrMainToken {
        minimumTokenBalanceForDividends = _newMinimum;
        emit MinimumTokenBalanceForDividendsUpdated(_newMinimum);
    }
   
    /// @notice Sets the minimum withdrawable dividend amount required for a claim.
    /// @dev Can only be called by the owner. Used to adjust for gas costs and UX.
    /// @param amount The new minimum amount in wei (e.g., 1e15 for 0.001 MATIC).
    function setMinimumDividendToClaim(uint256 amount) external onlyOwner {
        minimumDividendToClaim = amount;
        emit MinimumDividendToClaimUpdated(amount);
}
}        