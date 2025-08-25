// packages/hardhat/test/09_TransactionLimits.test.ts

import { expect } from "chai";
import { ethers, network } from "hardhat";
import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers";
import { Silvagnum } from "../typechain-types";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";

describe("Transactional Limits (maxTxAmount & maxWalletAmount)", () => {

  async function deployLimitsFixture() {
   
    const [admin, marketingWallet, vestingAdmin, user, anotherUser, founder, treasury] = await ethers.getSigners();

   
    const otherWallets = {
      growth: ethers.Wallet.createRandom().address,
      founder: founder.address, 
      treasury: treasury.address, 
      dao: ethers.Wallet.createRandom().address,
      userIncentive: ethers.Wallet.createRandom().address,
      companyIncentive: ethers.Wallet.createRandom().address,
    };

    
    const MockRouterFactory = await ethers.getContractFactory("MockUniswapRouter");
    const router = await MockRouterFactory.deploy();
    const SilvagnumFactory = await ethers.getContractFactory("Silvagnum");
    const silvagnum = await SilvagnumFactory.deploy(
      await router.getAddress(), marketingWallet.address, vestingAdmin.address, otherWallets.growth,
      otherWallets.founder, otherWallets.treasury, otherWallets.dao, otherWallets.userIncentive,
      otherWallets.companyIncentive
    );
    await silvagnum.waitForDeployment();

    await silvagnum.connect(admin).enableTrading(ethers.Wallet.createRandom().address);

    
    return { silvagnum, admin, user, anotherUser, treasurySigner: treasury, founderSigner: founder };
  }
  
  async function fundAccount(
    silvagnum: Silvagnum, 
    funder: HardhatEthersSigner, 
    recipient: HardhatEthersSigner, 
    amount: bigint
  ) {
    const currentBalance = await silvagnum.balanceOf(recipient.address);
    if (currentBalance < amount) {
      await silvagnum.connect(funder).transfer(recipient.address, amount - currentBalance);
    } else if (currentBalance > amount) {
      await silvagnum.connect(recipient).transfer(funder.address, currentBalance - amount);
    }
  }

  describe("Section 1: Max Transaction Amount (maxTxAmount)", () => {
    it("Should allow a non-excluded user to SEND exactly maxTxAmount", async () => {
      const { silvagnum, user, anotherUser, treasurySigner } = await loadFixture(deployLimitsFixture);
      const maxTxAmount = await silvagnum.maxTxAmount();

     
      await fundAccount(silvagnum, treasurySigner, user, maxTxAmount);

      await expect(
        silvagnum.connect(user).transfer(anotherUser.address, maxTxAmount)
      ).to.not.be.reverted;
    });
    
    it("Should REVERT if a non-excluded user tries to SEND more than maxTxAmount", async () => {
      const { silvagnum, user, anotherUser, treasurySigner } = await loadFixture(deployLimitsFixture);
      const maxTxAmount = await silvagnum.maxTxAmount();
      const excessiveAmount = maxTxAmount + 1n;
      
      await fundAccount(silvagnum, treasurySigner, user, excessiveAmount);

      await expect(
        silvagnum.connect(user).transfer(anotherUser.address, excessiveAmount)
      ).to.be.revertedWith("Transaction limit exceeded (gross amount)");
    });

  });


  describe("Section 2: Max Wallet Amount (maxWalletAmount)", () => {
    it("Should allow a user's balance to become exactly maxWalletAmount", async () => {
      const { silvagnum, user, treasurySigner } = await loadFixture(deployLimitsFixture);
      const maxWalletAmount = await silvagnum.maxWalletAmount();
      
      await fundAccount(silvagnum, treasurySigner, user, maxWalletAmount);

      expect(await silvagnum.balanceOf(user.address)).to.equal(maxWalletAmount);
    });

    it("Should REVERT if a transfer would push a user's balance over maxWalletAmount", async () => {
      const { silvagnum, user, treasurySigner } = await loadFixture(deployLimitsFixture);
      const maxWalletAmount = await silvagnum.maxWalletAmount();

      
      await fundAccount(silvagnum, treasurySigner, user, maxWalletAmount);
      expect(await silvagnum.balanceOf(user.address)).to.equal(maxWalletAmount);

    
      await expect(
        silvagnum.connect(treasurySigner).transfer(user.address, 1)
      ).to.be.revertedWith("Wallet limit exceeded");
    });
    
    it("Should allow a non-excluded user to RECEIVE more than maxTxAmount from an excluded address", async () => {
     
      const { silvagnum, user, treasurySigner } = await loadFixture(deployLimitsFixture);
      const maxTxAmount = await silvagnum.maxTxAmount();
      const excessiveAmount = maxTxAmount + 1n;
      
      
      await expect(
        silvagnum.connect(treasurySigner).transfer(user.address, excessiveAmount)
      ).to.not.be.reverted;
      
      expect(await silvagnum.balanceOf(user.address)).to.equal(excessiveAmount);
    });
  });
});