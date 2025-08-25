// packages/hardhat/test/06_ReflectionAndDividends.test.ts

import { expect } from "chai";
import { ethers, network } from "hardhat";
import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers";
import { Silvagnum, AdvancedDividendTracker, MockIdoRouter } from "../typechain-types";

describe("🪙 Silvagnum - Reflection & Dividend System 🪙", () => {
  async function deploySystemFixture() {
    
    const [admin, marketingWallet, vestingAdmin, user1, user2, user3, drainWallet, ...contributors] = await ethers.getSigners();
    const treasuryWalletAddress = ethers.Wallet.createRandom().address;
    const otherWallets = {
        growth: ethers.Wallet.createRandom().address,
        founder: ethers.Wallet.createRandom().address,
        dao: ethers.Wallet.createRandom().address,
        userIncentive: ethers.Wallet.createRandom().address,
        companyIncentive: ethers.Wallet.createRandom().address,
    };

  
    const MockLPTokenFactory = await ethers.getContractFactory("MockLPToken");
    const mockLpToken = await MockLPTokenFactory.deploy();
    
    const MockRouterFactory = await ethers.getContractFactory("ReflectionDividendTestRouter");
     const router = await MockRouterFactory.deploy(ethers.Wallet.createRandom().address, await mockLpToken.getAddress());
  
    await admin.sendTransaction({ to: await router.getAddress(), value: ethers.parseEther("1000") });

    const MockLockerFactory = await ethers.getContractFactory("MockLocker");
    const mockLocker = await MockLockerFactory.deploy();
    
   
    const SilvagnumFactory = await ethers.getContractFactory("Silvagnum");
    const silvagnum = await SilvagnumFactory.deploy(
        await router.getAddress(), marketingWallet.address, vestingAdmin.address, otherWallets.growth,
        otherWallets.founder, treasuryWalletAddress, otherWallets.dao, otherWallets.userIncentive,
        otherWallets.companyIncentive
    );
    await silvagnum.waitForDeployment();
    const trackerAddress = await silvagnum.advancedDividendTracker();
    const tracker = await ethers.getContractAt("AdvancedDividendTracker", trackerAddress);

    
    await silvagnum.connect(admin).startIDO();
    const softCap = await silvagnum.IDO_SOFT_CAP();
    const maxContribution = await silvagnum.MAX_CONTRIBUTION();
    const contributorCount = Math.ceil(Number(ethers.formatUnits(softCap, "ether")) / Number(ethers.formatUnits(maxContribution, "ether")));
    for (let i = 0; i < contributorCount && i < contributors.length; i++) {
      await silvagnum.connect(contributors[i]).participateInIDO({ value: maxContribution });
    }
    await silvagnum.connect(admin).setLiquidityManagerLpToken(await mockLpToken.getAddress());
    await silvagnum.connect(admin).setLiquidityManagerLockerAddress(await mockLocker.getAddress());
    await silvagnum.connect(admin).finalizeIDO();
    await silvagnum.connect(admin).withdrawUnallocatedTokens();
    
    
    await silvagnum.connect(admin).updateMinimumDividendBalance(0);
    
   
    await network.provider.send("hardhat_impersonateAccount", [treasuryWalletAddress]);
    const treasurySigner = await ethers.getSigner(treasuryWalletAddress);
    await admin.sendTransaction({ to: treasurySigner.address, value: ethers.parseEther("10") });
    
    await silvagnum.connect(treasurySigner).transfer(user1.address, ethers.parseEther("100000"));
    await silvagnum.connect(treasurySigner).transfer(user2.address, ethers.parseEther("300000"));
    
   
    await silvagnum.connect(admin).enableTrading(await mockLpToken.getAddress());
    await silvagnum.connect(admin).setSwapCooldown(0); 

    return { silvagnum, tracker, admin, user1, user2, user3, treasurySigner };
  }

  
  describe("Section 1: Fee Collection & Swap Trigger", () => {
    it("Should collect reflection fees on transfers", async () => {
      const { silvagnum, user1, user2 } = await loadFixture(deploySystemFixture);
      const reflectionFee = await silvagnum.reflectionFee();
      const amount = ethers.parseEther("10000");
      const expectedFee = (amount * reflectionFee) / 100n;
      await expect(silvagnum.connect(user1).transfer(user2.address, amount))
        .to.changeTokenBalance(silvagnum, await silvagnum.getAddress(), expectedFee);
    });

    it("Should NOT trigger swap if collected amount is below threshold", async () => {
      const { silvagnum, tracker, admin, user1, user2 } = await loadFixture(deploySystemFixture);
      await silvagnum.connect(admin).setSwapTokensAtAmount(ethers.parseEther("1000"));
      const trackerBalanceBefore = await ethers.provider.getBalance(await tracker.getAddress());
      await silvagnum.connect(user1).transfer(user2.address, ethers.parseEther("1000"));
      const trackerBalanceAfter = await ethers.provider.getBalance(await tracker.getAddress());
      expect(trackerBalanceAfter).to.equal(trackerBalanceBefore);
    });

    it("Should trigger swap & distribution when threshold is met", async () => {
      const { silvagnum, tracker, admin, user1, user2 } = await loadFixture(deploySystemFixture);
      const threshold = ethers.parseEther("500");
      await silvagnum.connect(admin).setSwapTokensAtAmount(threshold);
      const trackerBalanceBefore = await ethers.provider.getBalance(await tracker.getAddress());
      await silvagnum.connect(user1).transfer(user2.address, ethers.parseEther("10000"));
      const trackerBalanceAfter = await ethers.provider.getBalance(await tracker.getAddress());
      expect(trackerBalanceAfter).to.be.gt(trackerBalanceBefore);
    });
  });


  describe("Section 2: Dividend Calculation & Accuracy", () => {
    it("Should distribute dividends proportionally to token holders", async () => {
        const { silvagnum, tracker, admin, user1, user2 } = await loadFixture(deploySystemFixture);
        const totalDividends = ethers.parseEther("10");
        await admin.sendTransaction({ to: await tracker.getAddress(), value: totalDividends });
        
        const totalTokenSupply = await silvagnum.totalSupply();
        const balanceUser1 = await silvagnum.balanceOf(user1.address);
        const balanceUser2 = await silvagnum.balanceOf(user2.address);
        const expectedDividendsUser1 = (totalDividends * balanceUser1) / totalTokenSupply;
        const expectedDividendsUser2 = (totalDividends * balanceUser2) / totalTokenSupply;
        const actualDividendsUser1 = await tracker.withdrawableDividendOf(user1.address);
        const actualDividendsUser2 = await tracker.withdrawableDividendOf(user2.address);
        const tolerance = ethers.parseUnits("1", "gwei");
        
        expect(actualDividendsUser1).to.be.closeTo(expectedDividendsUser1, tolerance);
        expect(actualDividendsUser2).to.be.closeTo(expectedDividendsUser2, tolerance);
    });

    it("Should stop dividends for users who fall below the minimum balance", async () => {
        const { silvagnum, tracker, admin, user1, user2 } = await loadFixture(deploySystemFixture);
        
        
       
        await admin.sendTransaction({ to: await tracker.getAddress(), value: ethers.parseEther("10") });
        const user1DividendsBefore = await tracker.withdrawableDividendOf(user1.address);
        expect(user1DividendsBefore).to.be.gt(0);

        
        await silvagnum.connect(admin).updateMinimumDividendBalance(ethers.parseEther("150000"));
        
        await silvagnum.connect(user2).transfer(user1.address, ethers.parseEther("1"));

        await admin.sendTransaction({ to: await tracker.getAddress(), value: ethers.parseEther("10") });

        const user1DividendsAfter = await tracker.withdrawableDividendOf(user1.address);
        expect(user1DividendsAfter).to.equal(user1DividendsBefore);
    });
  });

  
  describe("Section 3: Claiming Logic & Restrictions", () => {
    async function fixtureWithDividends() {
    const base = await loadFixture(deploySystemFixture);
    
    await base.silvagnum.connect(base.admin).adminSetMinimumDividendToClaim(0);

    
    const totalDividends = ethers.parseEther("10");
    await base.admin.sendTransaction({ to: await base.tracker.getAddress(), value: totalDividends });
    return base;
  }

    it("Should allow a user to claim their due dividends", async () => {
        const { tracker, user1 } = await fixtureWithDividends();
        const withdrawable = await tracker.withdrawableDividendOf(user1.address);
        expect(withdrawable).to.be.gt(0);
        await expect(tracker.connect(user1).claimDividend()).to.changeEtherBalance(user1, withdrawable);
        expect(await tracker.withdrawableDividendOf(user1.address)).to.equal(0);
    });

    it("Should REVERT if a user tries to claim before the cooldown period", async () => {
        const { tracker, admin, user1 } = await fixtureWithDividends();
        await tracker.connect(user1).claimDividend();
        
        
        await admin.sendTransaction({ to: await tracker.getAddress(), value: ethers.parseEther("5")});
        
        
        await expect(tracker.connect(user1).claimDividend()).to.be.revertedWith("Wait time not met");
    });
    
    it("Should allow claiming again after the cooldown period has passed", async () => {
        const { tracker, admin, user1 } = await fixtureWithDividends();
        await tracker.connect(user1).claimDividend();

        const newDividends = ethers.parseEther("5");
        await admin.sendTransaction({ to: await tracker.getAddress(), value: newDividends });

        const claimWait = await tracker.claimWait();
        await time.increase(claimWait + 1n);

        const withdrawable = await tracker.withdrawableDividendOf(user1.address);
        expect(withdrawable).to.be.gt(0);
        await expect(tracker.connect(user1).claimDividend()).to.changeEtherBalance(user1, withdrawable);
    });
  });
});