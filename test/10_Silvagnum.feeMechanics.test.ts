import { expect } from "chai";
import { ethers, network } from "hardhat";
import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { Silvagnum, EnhancedLiquidityManager } from "../typechain-types";

describe("Silvagnum - Fee & Cooldown Mechanics ⚙️", () => {
  
 async function deployAndSetupFixture() {
    const signers = await ethers.getSigners();
    const [admin, marketingWallet, founder, user1, user2, vestingAdmin, ...contributors] = signers;
    const wallets = [marketingWallet.address, ethers.Wallet.createRandom().address, ethers.Wallet.createRandom().address, founder.address, ethers.Wallet.createRandom().address, ethers.Wallet.createRandom().address, ethers.Wallet.createRandom().address, ethers.Wallet.createRandom().address];


    const MockLockerFactory = await ethers.getContractFactory("MockLocker");
    const mockLocker = await MockLockerFactory.deploy();

    const MockLPTokenFactory = await ethers.getContractFactory("MockLPToken");
    const mockLpToken = await MockLPTokenFactory.deploy();

   
    const SimpleTestRouterFactory = await ethers.getContractFactory("SimpleTestRouter");
    const testRouter = await SimpleTestRouterFactory.deploy(await mockLpToken.getAddress());

    
    const SilvagnumFactory = await ethers.getContractFactory("Silvagnum");
    const silvagnum = await SilvagnumFactory.deploy(
      await testRouter.getAddress(), marketingWallet.address, vestingAdmin.address,
      wallets[1], founder.address, wallets[2], wallets[3], wallets[4], wallets[0]
    );

   
    const managerAddress = await silvagnum.liquidityManager();
    const manager = await ethers.getContractAt("EnhancedLiquidityManager", managerAddress);
    const dividendTrackerAddress = await silvagnum.advancedDividendTracker(); 
    const dividendTracker = await ethers.getContractAt("AdvancedDividendTracker", dividendTrackerAddress);

   
    await admin.sendTransaction({
        to: await dividendTracker.getAddress(),
        value: ethers.parseEther("1.0") 
    });
    
    await silvagnum.connect(admin).startIDO();
    const softCap = await silvagnum.IDO_SOFT_CAP();
    const maxContribution = await silvagnum.MAX_CONTRIBUTION();
    
    const requiredMatic = Number(ethers.formatEther(softCap));
    const contributionAmt = Number(ethers.formatEther(maxContribution));
    const contributorCount = Math.ceil(requiredMatic / contributionAmt);

    if (contributors.length < contributorCount) {
        throw new Error("Não há signers suficientes para atingir o soft cap");
    }

    const testContributors = contributors.slice(0, contributorCount);
    for (const contributor of testContributors) {
        await silvagnum.connect(contributor).participateInIDO({ value: maxContribution });
    }

    await silvagnum.connect(admin).setLiquidityManagerLpToken(await mockLpToken.getAddress());
    await silvagnum.connect(admin).setLiquidityManagerLockerAddress(await mockLocker.getAddress());
    
    await silvagnum.connect(admin).finalizeIDO();

   
    await silvagnum.connect(admin).excludeFromLimits(founder.address, true);
    await silvagnum.connect(admin).excludeFromFee(founder.address, true);
    
    const founderBalance = await silvagnum.balanceOf(founder.address);
    const requiredBalance = ethers.parseEther("20000000");
    if (founderBalance < requiredBalance) {
      const treasuryWalletAddress = await silvagnum.treasuryWallet();
      await network.provider.send("hardhat_impersonateAccount", [treasuryWalletAddress]);
      const treasurySigner = await ethers.getSigner(treasuryWalletAddress);
      await admin.sendTransaction({ to: treasurySigner.address, value: ethers.parseEther("1")});
      await silvagnum.connect(treasurySigner).transfer(founder.address, requiredBalance);
      await network.provider.send("hardhat_stopImpersonatingAccount", [treasuryWalletAddress]);
    }
    
    await silvagnum.connect(founder).transfer(user1.address, ethers.parseEther("10000000"));
    await silvagnum.connect(founder).transfer(user2.address, ethers.parseEther("10000000"));
    
    
    const pairAddress = await testRouter.getAddress(); 
    await silvagnum.connect(admin).enableTrading(pairAddress);

    await silvagnum.connect(admin).excludeFromLimits(founder.address, false);
    await silvagnum.connect(admin).excludeFromFee(founder.address, false);

    const remainingTokens = await silvagnum.balanceOf(await silvagnum.getAddress());
if (remainingTokens > 0) {
   
    await silvagnum.connect(admin).withdrawUnallocatedTokens();
}

    await admin.sendTransaction({ to: await testRouter.getAddress(), value: ethers.parseEther("100") });
    
    
    return { silvagnum, manager, admin, user1, user2 };
  }

  describe("Fee Distribution on Transfers", () => {
   
    it("should correctly split and send reflection and liquidity fees on a transfer", async () => {
      
      const { silvagnum, manager, admin, user1, user2 } = await loadFixture(deployAndSetupFixture);

      
      const antiBotPeriod = await silvagnum.antiBotPeriod();
      await time.increase(Number(antiBotPeriod) + 1);

     
      const totalSupply = await silvagnum.totalSupply();
      const maxAllowedThreshold = totalSupply / 100n;
      await silvagnum.connect(admin).setSwapTokensAtAmount(maxAllowedThreshold);
     

      const amount = ethers.parseEther("100000");
      const reflectionFee = await silvagnum.reflectionFee();
      const liquidityFee = await silvagnum.liquidityFee();

     
      const reflectionFeeAmount = (amount * reflectionFee) / 100n;
      const remainingAfterReflection = amount - reflectionFeeAmount;
      const liquidityFeeAmount = (remainingAfterReflection * liquidityFee) / 100n;
      const finalAmountToRecipient = remainingAfterReflection - liquidityFeeAmount;

      
      await expect(silvagnum.connect(user1).transfer(user2.address, amount))
        .to.changeTokenBalances(
          silvagnum,
         
          [user1, user2, await silvagnum.getAddress(), await manager.getAddress()],
        
          [-amount, finalAmountToRecipient, reflectionFeeAmount, liquidityFeeAmount]
        );
    });
 
  });

  describe("Automatic Swap Cooldown", () => {
    it("should enforce the global swap cooldown between automatic fee processing events", async () => {
      const { silvagnum, admin, user1, user2 } = await loadFixture(deployAndSetupFixture);
      const antiBotPeriod = await silvagnum.antiBotPeriod();
      await time.increase(antiBotPeriod);
      
      
      await silvagnum.connect(admin).setSwapTokensAtAmount(1);
      const cooldownSeconds = 600; //10 minutes  only for testing purposes
      await silvagnum.connect(admin).setSwapCooldown(cooldownSeconds);

      
      await expect(silvagnum.connect(user1).transfer(user2.address, ethers.parseEther("1000"))).to.not.be.reverted;
      
     
      await expect(
        silvagnum.connect(user1).transfer(user2.address, ethers.parseEther("1000"))
      ).to.be.revertedWith("Swap cooldown active");

   
      await time.increase(cooldownSeconds);

      
      await expect(silvagnum.connect(user1).transfer(user2.address, ethers.parseEther("1000"))).to.not.be.reverted;
    });
  });

  describe("Manual Function Calls", () => {
    it("should allow admin to manually process liquidity and dividends", async () => {
        const { silvagnum, manager, admin, user1, user2 } = await loadFixture(deployAndSetupFixture);
        const antiBotPeriod = await silvagnum.antiBotPeriod();
        await time.increase(antiBotPeriod);

       
        await silvagnum.connect(user1).transfer(user2.address, ethers.parseEther("1000000")); 

        
        const managerBalance = await silvagnum.balanceOf(await manager.getAddress());
        expect(managerBalance).to.be.gt(0);
        
        
        await expect(silvagnum.connect(admin).processLiquidity()).to.not.be.reverted;

        
        await expect(silvagnum.connect(admin).manualProcessDividends(300000)).to.not.be.reverted;
    });
  });
});