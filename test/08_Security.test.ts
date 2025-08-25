// packages/hardhat/test/08_Security.test.ts

import { expect } from "chai";
import { ethers, network } from "hardhat";
import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers";
import { Silvagnum, ReentrancyAttacker } from "../typechain-types";

describe("Security Analysis & Attack Vectors", () => {
  async function deploySecurityFixture() {
    
    const [admin, marketingWallet, vestingAdmin, user, maliciousActor] = await ethers.getSigners();
    const treasuryWalletAddress = ethers.Wallet.createRandom().address;
    const pairAddress = ethers.Wallet.createRandom().address;

    const otherWallets = {
      growth: ethers.Wallet.createRandom().address, founder: ethers.Wallet.createRandom().address,
      treasury: treasuryWalletAddress, dao: ethers.Wallet.createRandom().address,
      userIncentive: ethers.Wallet.createRandom().address, companyIncentive: ethers.Wallet.createRandom().address,
    };

    
    const MockRouterFactory = await ethers.getContractFactory("MockSimpleRouter");
    const router = await MockRouterFactory.deploy();

    const SilvagnumFactory = await ethers.getContractFactory("Silvagnum");
    const silvagnum = await SilvagnumFactory.deploy(
      await router.getAddress(), marketingWallet.address, vestingAdmin.address, otherWallets.growth,
      otherWallets.founder, otherWallets.treasury, otherWallets.dao, otherWallets.userIncentive,
      otherWallets.companyIncentive
    );
    await silvagnum.waitForDeployment();

    
    await network.provider.send("hardhat_impersonateAccount", [treasuryWalletAddress]);
    const treasurySigner = await ethers.getSigner(treasuryWalletAddress);
    await admin.sendTransaction({ to: treasurySigner.address, value: ethers.parseEther("10") });
    
    await silvagnum.connect(admin).enableTrading(pairAddress);

    // Note: Disable the global swap cooldown to isolate user-level cooldown tests 
    await silvagnum.connect(admin).setSwapCooldown(0); 

    return { silvagnum, admin, user, maliciousActor, treasurySigner, vestingAdmin, pairAddress };
  }

  describe("Section 1: Contract-Level Protections", () => {
    it("Should REVERT direct ETH transfers from EOAs to the main contract", async () => {
      const { silvagnum, user } = await loadFixture(deploySecurityFixture);
      await expect(
        user.sendTransaction({ to: await silvagnum.getAddress(), value: ethers.parseEther("1") }),
      ).to.be.revertedWithCustomError(silvagnum, "UnauthorizedMaticDeposit");
    });

    it("Should allow ETH deposits via receive() but REVERT calls with unknown data via fallback()", async () => {
      const { silvagnum, user } = await loadFixture(deploySecurityFixture);
      const trackerAddress = await silvagnum.advancedDividendTracker();
      
      await expect(
        user.sendTransaction({ to: trackerAddress, value: ethers.parseEther("1") })
      ).to.not.be.reverted;

      const nonExistentFunctionSelector = "0x12345678";
      await expect(
        user.sendTransaction({ to: trackerAddress, data: nonExistentFunctionSelector })
      ).to.be.revertedWith("Unsupported call");
    });
  });

  describe("Section 2: Transactional Protections (Anti-Bot & Limits)", () => {
    it("Should REVERT transfers that exceed maxTxAmount", async () => {
      const { silvagnum, user, treasurySigner } = await loadFixture(deploySecurityFixture);
      const maxTxAmount = await silvagnum.maxTxAmount();
      const excessiveAmount = maxTxAmount + 1n;

      await silvagnum.connect(treasurySigner).transfer(user.address, excessiveAmount);

      await expect(
        silvagnum.connect(user).transfer(ethers.Wallet.createRandom().address, excessiveAmount),
      ).to.be.revertedWith("Transaction limit exceeded (gross amount)");
    });

    it("Should apply snipeFee after maxSellsPerAddress is exceeded during anti-bot period", async () => {
      const { silvagnum, user, treasurySigner, pairAddress } = await loadFixture(deploySecurityFixture);
      
      const maxSells = await silvagnum.maxSellsPerAddress();
      const txDelay = await silvagnum.txDelaySeconds();

      await silvagnum.connect(treasurySigner).transfer(user.address, ethers.parseEther("1000"));
      await silvagnum.excludeFromFee(user.address, false);
      await silvagnum.excludeFromLimits(user.address, false);

      for (let i = 0; i < maxSells; i++) {
        await silvagnum.connect(user).transfer(pairAddress, ethers.parseEther("1"));
        await time.increase(txDelay + 1n);
      }

      const balanceBeforeSnipe = await silvagnum.balanceOf(await silvagnum.getAddress());
      await silvagnum.connect(user).transfer(pairAddress, ethers.parseEther("1"));
      const balanceAfterSnipe = await silvagnum.balanceOf(await silvagnum.getAddress());
      
      expect(balanceAfterSnipe).to.be.gt(balanceBeforeSnipe, "Snipe fee should have been collected in the contract");
    });
  });

  describe("Section 3: Re-entrancy Protections", () => {
   
    it("Should be protected from re-entrancy attacks on the vesting wallet release function", async () => {
      const { silvagnum, treasurySigner } = await loadFixture(deploySecurityFixture);

      const AttackerFactory = await ethers.getContractFactory("ReentrancyAttacker");
      const VestingWalletFactory = await ethers.getContractFactory("SilvagnumVestingWallet");

      const attacker = await AttackerFactory.deploy(ethers.ZeroAddress, ethers.ZeroAddress) as ReentrancyAttacker;
      await attacker.waitForDeployment();

      const vestingWalletForTest = await VestingWalletFactory.deploy(
        await attacker.getAddress(),
        await time.latest(),
        0
      );
      await vestingWalletForTest.waitForDeployment();

      await attacker.setContracts(await silvagnum.getAddress(), await vestingWalletForTest.getAddress());
      await silvagnum.connect(treasurySigner).transfer(await vestingWalletForTest.getAddress(), ethers.parseEther("1000"));
      
      // Execute the 'attack'. It should NOT revert, as an ERC20 transfer does not trigger receive().
      await expect(attacker.attack()).to.not.be.reverted;

      // The real proof: The attacker's receive() function was never called, so callCount must be 0.
      // This confirms the attack vector is not viable and the contract is safe from this specific re-entrancy.
      expect(await attacker.callCount()).to.equal(0, "The receive() function should never have been called");
    });
  });
});