import { expect } from "chai";
import { ethers, network } from "hardhat";
import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { Silvagnum, AdvancedDividendTracker, EnhancedLiquidityManager } from "../typechain-types";

/**
 * @title Full Reflection & Dividend Ecosystem Test (This is one of the most important tests in the entire project)
 * @dev This test suite simulates a complete end-to-end scenario for the token's core mechanics.
 * It involves multiple holders with varying balances to ensure that fees, swaps, and dividend
 * distributions work correctly and proportionally in a dynamic environment.
 */
describe("Full Reflection & Dividend Ecosystem Test 🧪", () => {

  // Our world-building function. It sets up a realistic post-launch state.
  async function deployLiveEcosystemFixture() {
    // We need more signers to act as contributors.
    const signers = await ethers.getSigners();
    const [admin, marketingWallet, founder, vestingAdmin, holder1, holder2, whale, anotherWallet, ...contributors] = signers;

// --- Deploy Mocks ---
    const MockLockerFactory = await ethers.getContractFactory("MockLocker");
    const mockLocker = await MockLockerFactory.deploy();

    const MockLPTokenFactory = await ethers.getContractFactory("MockLPToken");
    const mockLpToken = await MockLPTokenFactory.deploy();

   
    const SimpleTestRouterFactory = await ethers.getContractFactory("SimpleTestRouter");
    const testRouter = await SimpleTestRouterFactory.deploy(await mockLpToken.getAddress());
    
    // Using random wallets for non-critical roles.
    const growthReserveWallet = ethers.Wallet.createRandom().address;
    const treasuryWallet = ethers.Wallet.createRandom().address;
    const futureDAOReserve = ethers.Wallet.createRandom().address;
    const userIncentiveWallet = ethers.Wallet.createRandom().address;
    const companyIncentiveWallet = ethers.Wallet.createRandom().address;

    // --- Deploy Silvagnum ---
    const SilvagnumFactory = await ethers.getContractFactory("Silvagnum");
    const silvagnum = await SilvagnumFactory.deploy(
      await testRouter.getAddress(),
      marketingWallet.address,
      vestingAdmin.address,
      growthReserveWallet,
      founder.address,
      treasuryWallet,
      futureDAOReserve,
      userIncentiveWallet,
      companyIncentiveWallet
    );

    const managerAddress = await silvagnum.liquidityManager();
    const manager = await ethers.getContractAt("EnhancedLiquidityManager", managerAddress);
    const dividendTrackerAddress = await silvagnum.advancedDividendTracker();
    const dividendTracker = await ethers.getContractAt("AdvancedDividendTracker", dividendTrackerAddress);
    
    // --- Simulate IDO Lifecycle (THE RIGHT WAY) ---
    await silvagnum.connect(admin).startIDO();
    
    // Get IDO parameters from the contract.
    const softCap = await silvagnum.IDO_SOFT_CAP();
    const maxContribution = await silvagnum.MAX_CONTRIBUTION();
    
    // Calculate how many contributors we need to reach the soft cap.
    // Math.ceil(10 / 1.5) = 7 contributors.
    const contributorCount = Math.ceil(Number(ethers.formatEther(softCap)) / Number(ethers.formatEther(maxContribution)));
    
    if (contributors.length < contributorCount) {
        throw new Error(`Not enough signers for the IDO. Need ${contributorCount}, but only have ${contributors.length}.`);
    }

    // Loop through the contributors and have each one participate.
    for (let i = 0; i < contributorCount; i++) {
        await silvagnum.connect(contributors[i]).participateInIDO({ value: maxContribution });
    }
    
    await silvagnum.connect(admin).setLiquidityManagerLpToken(await mockLpToken.getAddress());
    await silvagnum.connect(admin).setLiquidityManagerLockerAddress(await mockLocker.getAddress());
    await silvagnum.connect(admin).finalizeIDO();

    // --- Distribute Tokens to Holders ---
    await network.provider.send("hardhat_impersonateAccount", [treasuryWallet]);
    const treasurySigner = await ethers.getSigner(treasuryWallet);
    await admin.sendTransaction({ to: treasurySigner.address, value: ethers.parseEther("1") });

    const holder1Amount = ethers.parseEther("1000000"); // 1 Million
    const holder2Amount = ethers.parseEther("5000000"); // 5 Million
    const whaleAmount = ethers.parseEther("20000000");   // 20 Million
    await silvagnum.connect(treasurySigner).transfer(holder1.address, holder1Amount);
    await silvagnum.connect(treasurySigner).transfer(holder2.address, holder2Amount);
    await silvagnum.connect(treasurySigner).transfer(whale.address, whaleAmount);
    await network.provider.send("hardhat_stopImpersonatingAccount", [treasuryWallet]);

    // --- Final Setup for Live Trading ---
    const pairAddress = await testRouter.getAddress();
    await silvagnum.connect(admin).enableTrading(pairAddress);
    await silvagnum.connect(admin).adminExcludeFromDividends(pairAddress, true);

    
    const remainingTokens = await silvagnum.balanceOf(await silvagnum.getAddress());
    if (remainingTokens > 0) {
      await silvagnum.connect(admin).withdrawUnallocatedTokens();
    }
    
    await admin.sendTransaction({ to: await testRouter.getAddress(), value: ethers.parseEther("200") });

     return { silvagnum, dividendTracker, admin, holder1, holder2, whale, anotherWallet, founder, contributors, marketingWallet };
  }

  

it("should correctly trigger a swap and distribute dividends proportionally after a large trade", async () => {
    
    const { silvagnum, dividendTracker, admin, holder1, holder2, whale, anotherWallet } = await loadFixture(deployLiveEcosystemFixture);

   
    const swapTriggerAmount = ethers.parseEther("500000");
    await silvagnum.connect(admin).setSwapTokensAtAmount(swapTriggerAmount);
    const antiBotPeriod = await silvagnum.antiBotPeriod();
    await time.increase(Number(antiBotPeriod) + 1);
    const initialTrackerBalance = await ethers.provider.getBalance(await dividendTracker.getAddress());
    const whaleTransferAmount = ethers.parseEther("10000000");

   
    await silvagnum.connect(whale).transfer(anotherWallet.address, whaleTransferAmount);

    
    const finalTrackerBalance = await ethers.provider.getBalance(await dividendTracker.getAddress());
    const totalDividendsAdded = finalTrackerBalance - initialTrackerBalance;
    const totalSupply = await silvagnum.totalSupply();

    

    const holder1Balance = await silvagnum.balanceOf(holder1.address);
    const expectedHolder1Share = (holder1Balance * totalDividendsAdded) / totalSupply; 

    const finalHolder1Dividends = await dividendTracker.withdrawableDividendOf(holder1.address);
    
   // I increased the precision to make sure small numerical errors don’t cause failures.
    const precisionDelta = ethers.parseUnits("0.00001", "ether"); //Margin of error in MATIC/ETH
    
    expect(finalHolder1Dividends).to.be.closeTo(expectedHolder1Share, precisionDelta, "Holder 1 dividends are incorrect");

    
    const holder2Balance = await silvagnum.balanceOf(holder2.address);
    const expectedHolder2Share = (holder2Balance * totalDividendsAdded) / totalSupply; 
    const finalHolder2Dividends = await dividendTracker.withdrawableDividendOf(holder2.address);
    expect(finalHolder2Dividends).to.be.closeTo(expectedHolder2Share, precisionDelta, "Holder 2 dividends are incorrect");
});
});