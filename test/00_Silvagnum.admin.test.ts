import { expect } from "chai";
import { ethers } from "hardhat";
import {
  Silvagnum,
  EnhancedLiquidityManager,
  MockUniswapRouter,
  SilvagnumVestingWallet, 
  AdvancedDividendTracker, 
} from "../typechain-types";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";

describe("Silvagnum - Admin & Configuration Tests 🧪", () => {

  let silvagnum: Silvagnum;
  let liquidityManager: EnhancedLiquidityManager;
  let mockRouter: MockUniswapRouter;


  let admin: HardhatEthersSigner; 
  let multisig: HardhatEthersSigner;
  let user: HardhatEthersSigner;
  let pair: HardhatEthersSigner; 
  let marketingWallet: HardhatEthersSigner;
  let growthReserve: HardhatEthersSigner;
  let founder: HardhatEthersSigner;
  let treasury: HardhatEthersSigner;
  let futureDAOReserve: HardhatEthersSigner;
  let userIncentive: HardhatEthersSigner;
  let companyIncentive: HardhatEthersSigner;
  let otherAccount: HardhatEthersSigner;

  beforeEach(async () => {
    
    [
      admin,
      multisig,
      user,
      pair,
      marketingWallet,
      growthReserve,
      founder,
      treasury,
      futureDAOReserve,
      userIncentive,
      companyIncentive,
      otherAccount,
    ] = await ethers.getSigners();

    //  Deploy the Mock Router
    const MockRouterFactory = await ethers.getContractFactory("MockUniswapRouter");
    mockRouter = await MockRouterFactory.deploy();

    // Deploy the main Silvagnum contract
    const SilvagnumFactory = await ethers.getContractFactory("Silvagnum", admin);
    silvagnum = await SilvagnumFactory.deploy(
      await mockRouter.getAddress(),
      await marketingWallet.getAddress(),
      await multisig.getAddress(), // This is the vestingWalletAdmin in the constructor
      await growthReserve.getAddress(),
      await founder.getAddress(),
      await treasury.getAddress(),
      await futureDAOReserve.getAddress(),
      await userIncentive.getAddress(),
      await companyIncentive.getAddress(),
    );

    
    const liquidityManagerAddress = await silvagnum.liquidityManager();
    liquidityManager = await ethers.getContractAt("EnhancedLiquidityManager", liquidityManagerAddress);

    
    await silvagnum.connect(admin).setVestingWalletAdmin(multisig.address);
  });

  describe("Core Trading Controls", () => {
    it("✅ Should allow the admin to enable trading", async () => {
   
      await silvagnum.connect(admin).enableTrading(pair.address);

    
      expect(await silvagnum.tradingActive()).to.be.true;
      expect(await silvagnum.uniswapPair()).to.equal(pair.address);
    });
  });

  describe("Security Limits & Fees", () => {
    it("✅ Should allow multisig to update limits correctly", async () => {
    
      const newMaxTx = ethers.parseEther("12000000"); // 12M tokens
      const newMaxWallet = ethers.parseEther("120000000"); // 120M tokens
      const newDelay = 45;

     
      await silvagnum.connect(multisig).updateLimits(newMaxTx, newMaxWallet, newDelay);

      
      expect(await silvagnum.maxTxAmount()).to.equal(newMaxTx);
      expect(await silvagnum.maxWalletAmount()).to.equal(newMaxWallet);
      expect(await silvagnum.txDelaySeconds()).to.equal(newDelay);
    });

    it("❌ Should REVERT if maxTxAmount is set too low", async () => {
      
      const invalidTxLimit = ethers.parseEther("10000"); 
      const validWalletLimit = ethers.parseEther("120000000");

      
      await expect(
        silvagnum.connect(multisig).updateLimits(invalidTxLimit, validWalletLimit, 30),
      ).to.be.revertedWith("Max transaction amount too low");
    });

    it("❌ Should REVERT if maxWalletAmount is set too low", async () => {
     
      const validTxLimit = ethers.parseEther("12000000");
      const invalidWalletLimit = ethers.parseEther("100000"); 

      
      await expect(
        silvagnum.connect(multisig).updateLimits(validTxLimit, invalidWalletLimit, 30),
      ).to.be.revertedWith("Max wallet size too low");
    });

    it("✅ Should allow multisig to exclude an address from fees", async () => {
     
      expect(await silvagnum.isExcludedFromReflectionFee(user.address)).to.be.false;

      
      await silvagnum.connect(multisig).excludeFromFee(user.address, true);
     
      expect(await silvagnum.isExcludedFromReflectionFee(user.address)).to.be.true;

     
      await silvagnum.connect(multisig).excludeFromFee(user.address, false);
      
      expect(await silvagnum.isExcludedFromReflectionFee(user.address)).to.be.false;
    });
  });

  describe("Anti-Bot Configuration", () => {
    it("✅ Should allow multisig to set anti-bot config", async () => {
     
      const newDuration = 3600; // 1 hour in seconds
      const newFee = 10;
      const newThreshold = 20;

     
      await silvagnum.connect(multisig).setAntiBotConfig(newDuration, newFee, newThreshold);

    
      expect(await silvagnum.antiBotPeriod()).to.equal(newDuration);
      expect(await silvagnum.snipeFee()).to.equal(newFee);
      expect(await silvagnum.snipeThreshold()).to.equal(newThreshold);
    });

    it("❌ Should REVERT if snipe fee is set above 30%", async () => {
      
      await expect(silvagnum.connect(multisig).setAntiBotConfig(3600, 31, 20)).to.be.revertedWith(
        "Maximum fee is 30%",
      );
    });
  });

  describe("Liquidity Manager Configuration", () => {
    it("✅ Should allow multisig to configure the liquidity manager", async () => {
      
      const newMinTokens = ethers.parseEther("1000");
      const newSlippage = 150;
      const newMarketingWallet = otherAccount;

     
      await silvagnum
        .connect(multisig)
        .configureLiquidityManager(newMinTokens, newSlippage, newMarketingWallet.address);

    
      expect(await liquidityManager.minTokensBeforeSwap()).to.equal(newMinTokens);
      expect(await liquidityManager.slippageDivisor()).to.equal(newSlippage);
      expect(await liquidityManager.marketingWallet()).to.equal(newMarketingWallet.address);
    });

    it("❌ Should REVERT configuring liquidity manager with an invalid wallet", async () => {
      
      await expect(
        silvagnum.connect(multisig).configureLiquidityManager(ethers.parseEther("1000"), 150, ethers.ZeroAddress),
      ).to.be.revertedWith("Silvagnum: Invalid marketing wallet");
    });

    it("❌ Should REVERT configuring liquidity manager with invalid slippage", async () => {
     
      await expect(
        silvagnum.connect(multisig).configureLiquidityManager(ethers.parseEther("1000"), 50, otherAccount.address),
      ).to.be.revertedWith("Silvagnum: Slippage too high");
    });
  });
});