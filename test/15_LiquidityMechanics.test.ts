// test/15_LiquidityMechanics.test.ts

import { expect } from "chai";
import { ethers, network } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { Silvagnum, EnhancedLiquidityManager, LiquidityTestRouter , MockLocker, MockLPToken } from "../typechain-types";

describe("💧 Silvagnum - Liquidity Mechanics 💧", () => {
  async function deploySystemFixture() {
    const [admin, marketingWallet, vestingAdmin, user1, user2, ...contributors] = await ethers.getSigners();
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
    const LiquidityTestRouterFactory = await ethers.getContractFactory("LiquidityTestRouter");
const router = (await LiquidityTestRouterFactory.deploy(
  ethers.Wallet.createRandom().address,
  await mockLpToken.getAddress(),
)) as LiquidityTestRouter;
    await admin.sendTransaction({ to: await router.getAddress(), value: ethers.parseEther("2000") });
    const MockLockerFactory = await ethers.getContractFactory("MockLocker");
    const mockLocker = await MockLockerFactory.deploy();
    const SilvagnumFactory = await ethers.getContractFactory("Silvagnum");
    const silvagnum = await SilvagnumFactory.deploy(
      await router.getAddress(), marketingWallet.address, vestingAdmin.address, otherWallets.growth,
      otherWallets.founder, treasuryWalletAddress, otherWallets.dao, otherWallets.userIncentive,
      otherWallets.companyIncentive
    );
    await silvagnum.waitForDeployment();
    const liquidityManagerAddress = await silvagnum.liquidityManager();
    const liquidityManager = await ethers.getContractAt("EnhancedLiquidityManager", liquidityManagerAddress);
    await silvagnum.connect(admin).startIDO();
    const softCap = await silvagnum.IDO_SOFT_CAP();
    const contribution = ethers.parseEther("1.5");
    const contributorCount = BigInt(Math.ceil(Number(ethers.formatUnits(softCap)) / Number(ethers.formatUnits(contribution))));
    for (let i = 0; i < contributorCount; i++) {
      await silvagnum.connect(contributors[i]).participateInIDO({ value: contribution });
    }
    await silvagnum.connect(admin).setLiquidityManagerLpToken(await mockLpToken.getAddress());
    await silvagnum.connect(admin).setLiquidityManagerLockerAddress(await mockLocker.getAddress());
    await silvagnum.connect(admin).finalizeIDO();
    await network.provider.send("hardhat_impersonateAccount", [treasuryWalletAddress]);
    const treasurySigner = await ethers.getSigner(treasuryWalletAddress);
    await admin.sendTransaction({ to: treasurySigner.address, value: ethers.parseEther("10") });
    await silvagnum.connect(treasurySigner).transfer(user1.address, ethers.parseEther("5000000"));
    await silvagnum.connect(treasurySigner).transfer(user2.address, ethers.parseEther("5000000"));
    await silvagnum.connect(admin).enableTrading(await mockLpToken.getAddress());
    return { silvagnum, liquidityManager, router, mockLocker, mockLpToken, admin, marketingWallet, user1, user2 };
  }

  async function deployPreFinalizedFixture() {
    const [admin, marketingWallet, vestingAdmin, ...contributors] = await ethers.getSigners();
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
    const LiquidityTestRouterFactory = await ethers.getContractFactory("LiquidityTestRouter");
const router = await LiquidityTestRouterFactory.deploy(ethers.Wallet.createRandom().address, await mockLpToken.getAddress());
    const MockLockerFactory = await ethers.getContractFactory("MockLocker");
    const mockLocker = await MockLockerFactory.deploy();
    const SilvagnumFactory = await ethers.getContractFactory("Silvagnum");
    const silvagnum = await SilvagnumFactory.deploy(
      await router.getAddress(), marketingWallet.address, vestingAdmin.address, otherWallets.growth,
      otherWallets.founder, treasuryWalletAddress, otherWallets.dao, otherWallets.userIncentive,
      otherWallets.companyIncentive
    );
    await silvagnum.connect(admin).startIDO();
    const softCap = await silvagnum.IDO_SOFT_CAP();
    const contribution = ethers.parseEther("1.5");
    const contributorCount = BigInt(Math.ceil(Number(ethers.formatUnits(softCap)) / Number(ethers.formatUnits(contribution))));
    for (let i = 0; i < contributorCount; i++) {
      await silvagnum.connect(contributors[i]).participateInIDO({ value: contribution });
    }
    await silvagnum.connect(admin).setLiquidityManagerLpToken(await mockLpToken.getAddress());
    await silvagnum.connect(admin).setLiquidityManagerLockerAddress(await mockLocker.getAddress());
    return { silvagnum, admin, marketingWallet, mockLocker, mockLpToken };
  }

  describe("Section 1: Initial Liquidity & Locking", () => {
    it("Should correctly send 70% of IDO funds to the Liquidity Manager for liquidity", async () => {
      const { silvagnum, mockLocker, mockLpToken, admin } = await loadFixture(deployPreFinalizedFixture);
      await silvagnum.connect(admin).finalizeIDO();
      const lpLocked = await mockLocker.getLockedAmount(await mockLpToken.getAddress());
      expect(lpLocked).to.be.gt(0);
    });
    
    it("Should lock the received LP tokens in the designated locker contract", async () => {
      const { silvagnum, mockLocker, mockLpToken, admin } = await loadFixture(deployPreFinalizedFixture);
      await silvagnum.connect(admin).finalizeIDO();
      const lockedDetails = await mockLocker.getLockDetails(await mockLpToken.getAddress());
      expect(lockedDetails.amount).to.be.gt(0);
      expect(lockedDetails.withdrawer).to.equal(await silvagnum.getAddress());
    });
    
    it("Should send the remaining 30% of IDO funds to the marketing wallet", async () => {
        const { silvagnum, admin, marketingWallet } = await loadFixture(deployPreFinalizedFixture);
        const idoMaticRaised = await silvagnum.idoMaticRaised();
        const expectedMarketingFunds = (idoMaticRaised * 30n) / 100n;
        await expect(silvagnum.connect(admin).finalizeIDO()).to.changeEtherBalance(
            marketingWallet,
            expectedMarketingFunds,
        );
    });
  });

  describe("Section 2: Automated Liquidity Generation", () => {
    it("Should collect liquidity fees on transfers and hold them in the Liquidity Manager", async () => {
      const { silvagnum, liquidityManager, user1, user2, admin } = await loadFixture(deploySystemFixture);
      await silvagnum.connect(admin).withdrawUnallocatedTokens();

      const grossAmount = ethers.parseEther("100000");
      const reflectionFeePercent = await silvagnum.reflectionFee();
      const liquidityFeePercent = await silvagnum.liquidityFee();

      
      const reflectionAmount = (grossAmount * reflectionFeePercent) / 100n;
      const amountAfterReflection = grossAmount - reflectionAmount;
      const expectedLiquidityFee = (amountAfterReflection * liquidityFeePercent) / 100n;

      const balanceBefore = await silvagnum.balanceOf(liquidityManager);
      await silvagnum.connect(user1).transfer(user2.address, grossAmount);
      const balanceAfter = await silvagnum.balanceOf(liquidityManager);

      expect(balanceAfter - balanceBefore).to.equal(expectedLiquidityFee);
    });

    it("Should REVERT processLiquidity if token balance is below the threshold", async () => {
      const { silvagnum, admin, user1, user2 } = await loadFixture(deploySystemFixture);
      await silvagnum.connect(admin).configureLiquidityManager(ethers.parseEther("10000000"), 200, admin.address);
      await silvagnum.connect(admin).withdrawUnallocatedTokens();
      await silvagnum.connect(user1).transfer(user2.address, ethers.parseEther("10000"));
      await expect(silvagnum.connect(admin).processLiquidity()).to.be.revertedWith("Silvagnum: Insufficient tokens to process");
    });

    it("Should execute swap-and-liquify when threshold is met", async () => {
        const { silvagnum, liquidityManager, marketingWallet, admin, user1, user2, mockLpToken } = await loadFixture(deploySystemFixture);
        const threshold = ethers.parseEther("100000");
        await silvagnum.connect(admin).configureLiquidityManager(threshold, 200, marketingWallet.address);
        await silvagnum.connect(admin).withdrawUnallocatedTokens();
  
        
        await silvagnum.connect(user1).transfer(user2.address, ethers.parseEther("3000000"));

        
        const managerBalance = await silvagnum.balanceOf(liquidityManager);
        expect(managerBalance).to.be.gte(threshold);
        
        const marketingBalanceBefore = await ethers.provider.getBalance(marketingWallet);
        const ownerLpBalanceBefore = await mockLpToken.balanceOf(await silvagnum.getAddress());
  
        await silvagnum.connect(admin).processLiquidity();
  
        const marketingBalanceAfter = await ethers.provider.getBalance(marketingWallet);
        const ownerLpBalanceAfter = await mockLpToken.balanceOf(await silvagnum.getAddress());
  
        expect(marketingBalanceAfter).to.be.gt(marketingBalanceBefore);
        expect(ownerLpBalanceAfter).to.be.gt(ownerLpBalanceBefore);
    });
  });

  describe("Section 3: Price Protection & Configuration", () => {
    it("Should REVERT the swap if slippage is too high", async () => {
      const { silvagnum, router, admin, user1, user2 } = await loadFixture(deploySystemFixture);
      await router.setPriceManipulation(true);
      const threshold = ethers.parseEther("10000");
      await silvagnum.connect(admin).configureLiquidityManager(threshold, 200, admin.address);
      await silvagnum.connect(admin).withdrawUnallocatedTokens();

    
      await silvagnum.connect(user1).transfer(user2.address, ethers.parseEther("300000"));

      await expect(silvagnum.connect(admin).processLiquidity()).to.be.reverted;
    });

    it("Should allow admin to update liquidity parameters via configureLiquidityManager", async () => {
        const { silvagnum, liquidityManager, admin, user2 } = await loadFixture(deploySystemFixture);
        const newThreshold = ethers.parseEther("99999");
        const newSlippage = 300;
        const newMarketingWallet = user2.address;
        await silvagnum.connect(admin).configureLiquidityManager(newThreshold, newSlippage, newMarketingWallet);
        expect(await liquidityManager.minTokensBeforeSwap()).to.equal(newThreshold);
        expect(await liquidityManager.slippageDivisor()).to.equal(newSlippage);
        expect(await liquidityManager.marketingWallet()).to.equal(newMarketingWallet);
    });

    it("Should REVERT if a non-admin tries to update liquidity parameters", async () => {
      const { silvagnum, user1 } = await loadFixture(deploySystemFixture);
      await expect(
        silvagnum.connect(user1).configureLiquidityManager(1, 1, user1.address),
      ).to.be.revertedWith("Caller is not MultiSig or Admin");
    });
  });
});