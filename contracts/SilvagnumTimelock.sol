// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title Silvagnum Timelock (Hardened)
 * @notice This contract acts as a digital safe that locks a specific amount of tokens until a predefined date.
 * @dev It ensures that vested tokens for the ecosystem or other allocations cannot be moved or sold before the agreed-upon time,
 * providing transparency and security to all investors. It is based on OpenZeppelin's battle-tested standards
 * and includes additional hardening features for maximum safety.
 */
contract SilvagnumTimelock is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // --- State Variables ---
    IERC20 public immutable token;
    address public immutable beneficiary;
    uint256 public immutable releaseTime;

    // --- Events ---
    event TokensReleased(address indexed token, address indexed to, uint256 amount);

    // --- Constructor ---
    constructor(
        address _token,
        address _beneficiary,
        uint256 _releaseTime
    ) {
        // Security Check: Ensures the contract is set up correctly and prevents tokens 
        // from being permanently lost or burned by mistake during deployment.
        require(_token != address(0), "Timelock: token is the zero address");
        require(_beneficiary != address(0), "Timelock: beneficiary is the zero address");
        require(_releaseTime > block.timestamp, "Timelock: release time must be in the future");

        token = IERC20(_token);
        beneficiary = _beneficiary;
        releaseTime = _releaseTime;
    }

    // --- Functions ---

    /**
     * @notice Allows the designated beneficiary to withdraw the full balance of locked tokens, 
     * but only after the lock-in period has expired.
     * @dev Protected against a common type of smart contract attack (re-entrancy) as an extra layer of defense.
     */
    function release() public nonReentrant {
        // The Time Gate: This check ensures that the withdrawal can only happen ON or AFTER the specified release time.
        require(block.timestamp >= releaseTime, "Timelock: current time is before release time");
        
        // The Owner Gate: This check ensures that ONLY the designated beneficiary address can call this function.
        require(msg.sender == beneficiary, "Timelock: caller is not the beneficiary");

        uint256 amount = token.balanceOf(address(this));
        require(amount > 0, "Timelock: no tokens to release");

        token.safeTransfer(beneficiary, amount);

        // Records the successful withdrawal on the blockchain for full transparency.
        emit TokensReleased(address(token), beneficiary, amount);
    }

    // --- UX Helper View Functions ---

    /**
     * @notice A public view function to check if the lock-in period has ended.
     * @return Returns `true` if the tokens are available for withdrawal, `false` otherwise.
     */
    function isUnlocked() public view returns (bool) {
        return block.timestamp >= releaseTime;
    }

    /**
     * @notice A public view function to check the remaining time until the tokens can be withdrawn.
     * @return Returns the number of seconds left until the unlock date. Returns 0 if the time has already passed.
     */
    function secondsLeft() public view returns (uint256) {
        if (block.timestamp >= releaseTime) {
            return 0;
        }
        return releaseTime - block.timestamp;
    }
}