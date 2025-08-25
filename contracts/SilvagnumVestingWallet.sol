// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;


import "@openzeppelin/contracts/finance/VestingWallet.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";


/// @title Silvagnum Vesting Wallet with Cliff
/// @author Silvagnum's Founder
/// @notice Manages the vesting schedule for team or ecosystem tokens with a cliff period.
/// @dev This contract extends OpenZeppelin's VestingWallet to add a hard cliff mechanism,
/// meaning no tokens can be released before the cliff timestamp is reached.
contract  SilvagnumVestingWallet is VestingWallet,ReentrancyGuard {
     /// @dev The UNIX timestamp marking the end of the cliff period.
    uint64 private immutable _cliff;

    /// @notice Emitted when the initial liquidity is released (example event, can be adapted).
    event InitialLiquidityReleased(address indexed beneficiary, uint256 amount);

    /// @notice Initializes the vesting wallet with a specified beneficiary, start time, and duration.
    /// @dev The total vesting duration is hardcoded to 4 years, with a customizable cliff.
    /// @param beneficiaryAddress The address that will be able to withdraw the vested tokens.
    /// @param startTimestamp The UNIX timestamp marking the beginning of the vesting period (e.g., TGE).
    /// @param cliffDuration The duration of the cliff in seconds from the start time.
    constructor(
        address beneficiaryAddress,
        uint64 startTimestamp,
        uint64 cliffDuration
    )   
        // Total vesting duration is 4 years.
        VestingWallet(beneficiaryAddress, startTimestamp, 4 * 365 days)
    {
        require(beneficiaryAddress != address(0), "Beneficiary cannot be zero");
        require(cliffDuration <= 4 * 365 days, "Cliff exceeds vesting period");
        _cliff = startTimestamp + cliffDuration;

        
     
    }

    /// @notice Releases the vested amount of a specific token to the beneficiary.
    /// @dev Overrides the standard `release` function to enforce that it can only be called after the cliff period has ended.
    /// @dev This function is protected against re-entrancy attacks.
    /// @param token The address of the ERC20 token to be released.
    function release(address token) public override nonReentrant {
        require(block.timestamp >= _cliff, "Cliff not reached");
        super.release(token);
    }

   /// @notice Returns the detailed vesting progress for a specific token.
    /// @param token The address of the ERC20 token to check.
    /// @return _released The amount of tokens already withdrawn by the beneficiary.
    /// @return _releasable The amount of tokens currently available for withdrawal.
    /// @return _total The total amount of tokens that have vested to date (released + releasable).
    function vestingProgress(address token) external view returns (
        uint256 _released,
        uint256 _releasable,
        uint256 _total
) {
    _released = vestedAmount(token, uint64(block.timestamp)) - super.releasable(token);
    _releasable = super.releasable(token);
    _total = _released + _releasable;
}

     /// @notice Returns the UNIX timestamp when the cliff period ends.
    /// @return The cliff end timestamp in seconds.
    function cliffTimestamp() external view returns (uint64) {
        return _cliff;
    }
}