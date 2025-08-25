import { expect } from "chai";
import { ethers, network } from "hardhat";
import { Silvagnum, EnhancedLiquidityManager } from "../typechain-types";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";


const MockIdoRouterFactory = ethers.getContractFactory("MockIdoRouter");
const MockLPTokenFactory = ethers.getContractFactory("MockLPToken");
const MockLockerFactory = ethers.getContractFactory("MockLocker");

describe("Silvagnum - Transaction & Wallet Limits 📏", () => {
  let silvagnum: Silvagnum;
  let liquidityManager: EnhancedLiquidityManager;
  let admin: HardhatEthersSigner,
    founder: HardhatEthersSigner,
    user1: HardhatEthersSigner,
    user2: HardhatEthersSigner;

  beforeEach(async () => {
    const signers = await ethers.getSigners();
    [admin, founder, user1, user2] = signers.slice(0, 4);

    const mockLPToken = await (await MockLPTokenFactory).connect(admin).deploy();
    const mockRouter = await (await MockIdoRouterFactory).connect(admin).deploy(ethers.Wallet.createRandom().address, await mockLPToken.getAddress());
    const mockLocker = await (await MockLockerFactory).connect(admin).deploy();

    const marketingWallet = ethers.Wallet.createRandom().address;
    const vestingAdmin = ethers.Wallet.createRandom().address;
    const growthWallet = ethers.Wallet.createRandom().address;
    const treasuryWallet = ethers.Wallet.createRandom().address;
    const daoWallet = ethers.Wallet.createRandom().address;
    const userIncentiveWallet = ethers.Wallet.createRandom().address;
    const companyIncentiveWallet = ethers.Wallet.createRandom().address;
    
    const SilvagnumFactory = await ethers.getContractFactory("Silvagnum", admin);
    silvagnum = await SilvagnumFactory.deploy(
      await mockRouter.getAddress(), marketingWallet, vestingAdmin, growthWallet,
      founder.address, treasuryWallet, daoWallet, userIncentiveWallet, companyIncentiveWallet
    );
    const lmAddress = await silvagnum.liquidityManager();
    liquidityManager = await ethers.getContractAt("EnhancedLiquidityManager", lmAddress);
    
   
    await silvagnum.connect(admin).startIDO();
    const softCap = await silvagnum.IDO_SOFT_CAP();
    const maxContribution = await silvagnum.MAX_CONTRIBUTION();
    const contributorCount = Math.ceil(Number(ethers.formatEther(softCap)) / Number(ethers.formatEther(maxContribution))) + 1;
    for (let i = 0; i < contributorCount; i++) {
        if (signers.length > 5 + i) {
            await silvagnum.connect(signers[5 + i]).participateInIDO({ value: maxContribution });
        }
    }
    await silvagnum.connect(admin).setLiquidityManagerLpToken(await mockLPToken.getAddress());
    await silvagnum.connect(admin).setLiquidityManagerLockerAddress(await mockLocker.getAddress());
    await silvagnum.connect(admin).finalizeIDO();
    
  
    await silvagnum.connect(admin).withdrawUnallocatedTokens();
  
    await silvagnum.connect(admin).excludeFromLimits(founder.address, true);
    await silvagnum.connect(admin).excludeFromLimits(user1.address, true);
    await silvagnum.connect(admin).excludeFromFee(founder.address, true);
    
    await silvagnum.connect(founder).transfer(user1.address, ethers.parseEther("90000000"));
    await silvagnum.connect(founder).transfer(user2.address, ethers.parseEther("10000"));
    
    await silvagnum.connect(admin).excludeFromLimits(founder.address, false);
    await silvagnum.connect(admin).excludeFromLimits(user1.address, false); 
    await silvagnum.connect(admin).excludeFromFee(founder.address, false);

    await silvagnum.connect(admin).enableTrading(ethers.Wallet.createRandom().address);
  });


  describe("Testing updateLimits() Functionality", () => {
    it("should allow an admin to update the limits and emit an event", async () => {
        const newMaxTx = (await silvagnum.totalSupply()) / 1000n;
        const newMaxWallet = (await silvagnum.totalSupply()) / 100n;
      const newDelay = 60;
      await expect(silvagnum.connect(admin).updateLimits(newMaxTx, newMaxWallet, newDelay))
        .to.emit(silvagnum, "LimitsUpdated")
        .withArgs(newMaxTx, newMaxWallet, newDelay);
      expect(await silvagnum.maxTxAmount()).to.equal(newMaxTx);
      expect(await silvagnum.maxWalletAmount()).to.equal(newMaxWallet);
      expect(await silvagnum.txDelaySeconds()).to.equal(newDelay);
    });

    it("should REVERT if a non-admin tries to update the limits", async () => {
        const newMaxTx = (await silvagnum.totalSupply()) / 1000n;
        const newMaxWallet = (await silvagnum.totalSupply()) / 100n;
      await expect(
        silvagnum.connect(user1).updateLimits(newMaxTx, newMaxWallet, 60)
      ).to.be.revertedWith("Caller is not MultiSig or Admin");
    });
  });

  describe("Testing Limit Enforcement", () => {
    it("should allow a transfer EXACTLY at the maxTxAmount limit", async () => {
      const maxTx = await silvagnum.maxTxAmount();
      const reflectionFee = await silvagnum.reflectionFee();
      const liquidityFee = await silvagnum.liquidityFee();

      const reflectionAmount = (maxTx * reflectionFee) / 100n;
      const amountAfterReflection = maxTx - reflectionAmount;
      const liquidityAmount = (amountAfterReflection * liquidityFee) / 100n;
      const finalAmountTransferred = amountAfterReflection - liquidityAmount;
      
      await expect(() => silvagnum.connect(user1).transfer(user2.address, maxTx))
        .to.changeTokenBalances(
          silvagnum,
          [user1, user2, silvagnum, liquidityManager],
          [-maxTx, finalAmountTransferred, reflectionAmount, liquidityAmount]
        );
    });

    it("should REVERT a transfer ONE WEI over the maxTxAmount limit", async () => {
      const maxTx = await silvagnum.maxTxAmount();
      const overLimit = maxTx + 1n;
      await expect(silvagnum.connect(user1).transfer(user2.address, overLimit))
        .to.be.revertedWith("Transaction limit exceeded (gross amount)");
    });

    it("should REVERT if a transfer causes the recipient to exceed maxWalletAmount", async () => {
      const maxWallet = await silvagnum.maxWalletAmount();
      const user2Balance = await silvagnum.balanceOf(user2.address);
      const amountToReachLimit = maxWallet - user2Balance;

      const treasuryAddr = await silvagnum.treasuryWallet();
      await admin.sendTransaction({ to: treasuryAddr, value: ethers.parseEther("1.0") });
      await network.provider.request({ method: "hardhat_impersonateAccount", params: [treasuryAddr] });
      const treasurySigner = await ethers.getSigner(treasuryAddr);
      
      await silvagnum.connect(admin).excludeFromLimits(user2.address, true);
      await silvagnum.connect(treasurySigner).transfer(user2.address, amountToReachLimit);
      await silvagnum.connect(admin).excludeFromLimits(user2.address, false);
      
      await network.provider.request({ method: "hardhat_stopImpersonatingAccount", params: [treasuryAddr] });
      
      expect(await silvagnum.balanceOf(user2.address)).to.equal(maxWallet);

      await expect(silvagnum.connect(user1).transfer(user2.address, 1))
        .to.be.revertedWith("Wallet limit exceeded");
    });
  });
});