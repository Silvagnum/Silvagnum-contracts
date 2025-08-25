import { expect } from "chai";
import { ethers, network } from "hardhat";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { Silvagnum, MockIdoRouter, MockLPToken, MockLocker, EnhancedLiquidityManager } from "../typechain-types";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";

describe("Silvagnum - IDO Module Tests 🚀", () => {
  let silvagnum: Silvagnum;
  let liquidityManager: EnhancedLiquidityManager;
  let admin: HardhatEthersSigner,
    marketingWallet: HardhatEthersSigner,
    founder: HardhatEthersSigner,
    contributor1: HardhatEthersSigner,
    contributor2: HardhatEthersSigner,
    contributor3: HardhatEthersSigner,
    contributor4: HardhatEthersSigner,
    contributor5: HardhatEthersSigner,
    contributor6: HardhatEthersSigner,
    contributor7: HardhatEthersSigner;

  
  beforeEach(async () => {
   
    [admin, marketingWallet, founder, contributor1, contributor2, contributor3, contributor4, contributor5, contributor6, contributor7] = await ethers.getSigners();
    const wallets = [marketingWallet.address, ethers.Wallet.createRandom().address, ethers.Wallet.createRandom().address, founder.address, ethers.Wallet.createRandom().address, ethers.Wallet.createRandom().address, ethers.Wallet.createRandom().address, ethers.Wallet.createRandom().address];

   
    const MockLPTokenFactory = await ethers.getContractFactory("MockLPToken", admin);
    const mockLPToken = await MockLPTokenFactory.deploy();
    
    const MockIdoRouterFactory = await ethers.getContractFactory("MockIdoRouter", admin);
    
    const mockWethAddress = ethers.Wallet.createRandom().address;
    const mockRouter = await MockIdoRouterFactory.deploy(mockWethAddress, await mockLPToken.getAddress());
    
    const MockLockerFactory = await ethers.getContractFactory("MockLocker", admin);
    const mockLocker = await MockLockerFactory.deploy();

    
    const SilvagnumFactory = await ethers.getContractFactory("Silvagnum", admin);
    silvagnum = await SilvagnumFactory.deploy(
      await mockRouter.getAddress(), ...wallets
    );

   
    await silvagnum.connect(admin).setLiquidityManagerLpToken(await mockLPToken.getAddress());
    await silvagnum.connect(admin).setLiquidityManagerLockerAddress(await mockLocker.getAddress());
  });

  describe("IDO Lifecycle & Happy Path", () => {
    it("should allow starting the IDO only once by an admin", async () => {
      await expect(silvagnum.connect(admin).startIDO()).to.not.be.reverted;
      await expect(silvagnum.connect(admin).startIDO()).to.be.revertedWith("IDO already started");
    });
    
    it("should increase token price as more contributions are made (Bonding Curve)", async () => {
      await silvagnum.connect(admin).startIDO();
      const contributionAmount = ethers.parseEther("1");

      await silvagnum.connect(contributor1).participateInIDO({ value: contributionAmount });
      const tokensForC1 = await silvagnum.idoTokensPurchased(contributor1.address);

      await silvagnum.connect(contributor2).participateInIDO({ value: contributionAmount });
      const tokensForC2 = await silvagnum.idoTokensPurchased(contributor2.address);

      
      expect(tokensForC2).to.be.lt(tokensForC1);
    });

    it("should finalize correctly when soft cap is met, sending funds to marketing and liquidity", async () => {
      await silvagnum.connect(admin).startIDO();
      
      const contributors = [contributor1, contributor2, contributor3, contributor4, contributor5, contributor6, contributor7];
      const maxContribution = await silvagnum.MAX_CONTRIBUTION();
      
     
      for (const contributor of contributors) {
        await silvagnum.connect(contributor).participateInIDO({ value: maxContribution });
      }

      const totalRaised = await silvagnum.idoMaticRaised();
      const expectedMarketingShare = (totalRaised * 30n) / 100n;

      
      await expect(
        () => silvagnum.connect(admin).finalizeIDO()
      ).to.changeEtherBalance(marketingWallet, expectedMarketingShare);

      expect(await silvagnum.idoFinalized()).to.be.true;
      expect(await silvagnum.refundEnabled()).to.be.false;
    });
  });

  describe("IDO Failure & Refunds", () => {
    beforeEach(async () => {
     
      await silvagnum.connect(admin).startIDO();
    });

    it("should enable refunds if soft cap is not met", async () => {
      const contributionAmount = ethers.parseEther("1"); 
      await silvagnum.connect(contributor1).participateInIDO({ value: contributionAmount });
      
      await silvagnum.connect(admin).finalizeIDO();
      expect(await silvagnum.refundEnabled()).to.be.true;
    });

    it("should allow a contributor to claim a refund on a failed IDO", async () => {
      const contributionAmount = ethers.parseEther("1");
      await silvagnum.connect(contributor1).participateInIDO({ value: contributionAmount });
      await silvagnum.connect(admin).finalizeIDO();

      const tokensToReturn = await silvagnum.idoTokensPurchased(contributor1.address);
      const balanceBefore = await silvagnum.balanceOf(contributor1.address);
      
      
      expect(balanceBefore).to.equal(tokensToReturn);
      
      
      await expect(
        () => silvagnum.connect(contributor1).claimRefund()
      ).to.changeEtherBalance(contributor1, contributionAmount);

      
      expect(await silvagnum.balanceOf(contributor1.address)).to.equal(0);
    });

    it("should REVERT if trying to claim refund before finalization or twice", async () => {
      const contributionAmount = ethers.parseEther("1");
      await silvagnum.connect(contributor1).participateInIDO({ value: contributionAmount });
      await expect(silvagnum.connect(contributor1).claimRefund()).to.be.revertedWith("IDO not finalized");
      await silvagnum.connect(admin).finalizeIDO();
      await silvagnum.connect(contributor1).claimRefund();
      await expect(silvagnum.connect(contributor1).claimRefund()).to.be.revertedWith("No contribution found");
    });
  });
});