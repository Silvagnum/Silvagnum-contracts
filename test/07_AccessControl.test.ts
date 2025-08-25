// packages/hardhat/test/07_AccessControl.test.ts

import { expect } from "chai";
import { ethers, network } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { Silvagnum } from "../typechain-types";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";

describe(" Silvagnum - Access Control & Roles ", () => {
  
  async function deployAccessControlFixture() {
    
    const [admin, marketingWallet, vestingAdmin, nonAdmin, newVestingAdmin, anotherUser] = await ethers.getSigners();
    
   
    const treasuryWalletAddress = ethers.Wallet.createRandom().address;

    
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

    
    const ADMIN_ROLE = await silvagnum.ADMIN_ROLE();
    const DIVIDEND_MANAGER_ROLE = await silvagnum.DIVIDEND_MANAGER_ROLE();
    const LIQUIDITY_MANAGER_ROLE = await silvagnum.LIQUIDITY_MANAGER_ROLE();

    return { 
      silvagnum, admin, vestingAdmin, nonAdmin, newVestingAdmin, anotherUser,
      ADMIN_ROLE, DIVIDEND_MANAGER_ROLE, LIQUIDITY_MANAGER_ROLE,
      treasuryWalletAddress
    };
  }


  describe("Section 1: Role Granting and Administration", () => {
    it("Should allow an ADMIN to grant a role", async () => {
      const { silvagnum, admin, anotherUser, DIVIDEND_MANAGER_ROLE } = await loadFixture(deployAccessControlFixture);
      
      await silvagnum.connect(admin).grantRole(DIVIDEND_MANAGER_ROLE, anotherUser.address);
      
      expect(await silvagnum.hasRole(DIVIDEND_MANAGER_ROLE, anotherUser.address)).to.be.true;
    });

    it("Should REVERT if a non-ADMIN tries to grant a role", async () => {
      const { silvagnum, nonAdmin, anotherUser, ADMIN_ROLE, DIVIDEND_MANAGER_ROLE } = await loadFixture(deployAccessControlFixture);
      
      const expectedRevertMessage = `AccessControl: account ${nonAdmin.address.toLowerCase()} is missing role ${ADMIN_ROLE}`;
      
      await expect(
        silvagnum.connect(nonAdmin).grantRole(DIVIDEND_MANAGER_ROLE, anotherUser.address)
      ).to.be.revertedWith(expectedRevertMessage);
    });

    it("Should grant all operational roles when setVestingWalletAdmin is called", async () => {
      const { silvagnum, admin, newVestingAdmin, ADMIN_ROLE, LIQUIDITY_MANAGER_ROLE, DIVIDEND_MANAGER_ROLE } = await loadFixture(deployAccessControlFixture);

      await silvagnum.connect(admin).setVestingWalletAdmin(newVestingAdmin.address);

      expect(await silvagnum.vestingWalletAdmin()).to.equal(newVestingAdmin.address);
      expect(await silvagnum.hasRole(ADMIN_ROLE, newVestingAdmin.address)).to.be.true;
      expect(await silvagnum.hasRole(LIQUIDITY_MANAGER_ROLE, newVestingAdmin.address)).to.be.true;
      expect(await silvagnum.hasRole(DIVIDEND_MANAGER_ROLE, newVestingAdmin.address)).to.be.true;
    });
  });


  describe("Section 2: 'onlyMultiSigOrAdmin' Modifier Protection", () => {
    const expectedRevertMessage = "Caller is not MultiSig or Admin";

    it("Should protect the updateLimits function", async () => {
      const { silvagnum, admin, nonAdmin } = await loadFixture(deployAccessControlFixture);
      const totalSupply = await silvagnum.totalSupply();
      const validMaxTx = totalSupply / 100n;
      const validMaxWallet = totalSupply / 50n;

      
      await expect(silvagnum.connect(admin).updateLimits(validMaxTx, validMaxWallet, 10)).to.not.be.reverted;

      
      await expect(
        silvagnum.connect(nonAdmin).updateLimits(validMaxTx, validMaxWallet, 10)
      ).to.be.revertedWith(expectedRevertMessage);
    });

    it("Should protect the excludeFromLimits function", async () => {
      const { silvagnum, admin, nonAdmin, anotherUser } = await loadFixture(deployAccessControlFixture);
      
      await expect(silvagnum.connect(admin).excludeFromLimits(anotherUser.address, true)).to.not.be.reverted;
      
      await expect(
        silvagnum.connect(nonAdmin).excludeFromLimits(anotherUser.address, true)
      ).to.be.revertedWith(expectedRevertMessage);
    });
    
    it("Should protect the configureLiquidityManager function", async () => {
        const { silvagnum, admin, nonAdmin } = await loadFixture(deployAccessControlFixture);
        const newMarketingWallet = ethers.Wallet.createRandom().address;

        await expect(silvagnum.connect(admin).configureLiquidityManager(ethers.parseEther("1000"), 200, newMarketingWallet)).to.not.be.reverted;

        await expect(
            silvagnum.connect(nonAdmin).configureLiquidityManager(ethers.parseEther("1000"), 200, newMarketingWallet)
        ).to.be.revertedWith(expectedRevertMessage);
    });
  });

  
  describe("Section 3: Specific Role Protections", () => {

    it("Should only allow DIVIDEND_MANAGER to call manualProcessDividends", async () => {
        const { silvagnum, admin, nonAdmin, DIVIDEND_MANAGER_ROLE } = await loadFixture(deployAccessControlFixture);
        const expectedRevertMessage = `AccessControl: account ${nonAdmin.address.toLowerCase()} is missing role ${DIVIDEND_MANAGER_ROLE}`;

        
        await expect(silvagnum.connect(admin).manualProcessDividends(300000)).to.not.be.reverted;
       
        await expect(
            silvagnum.connect(nonAdmin).manualProcessDividends(300000)
        ).to.be.revertedWith(expectedRevertMessage);
    });

    it("Should only allow LIQUIDITY_MANAGER to call processLiquidity", async () => {
        const { silvagnum, admin, nonAdmin, LIQUIDITY_MANAGER_ROLE, treasuryWalletAddress } = await loadFixture(deployAccessControlFixture);
        const expectedRevertMessage = `AccessControl: account ${nonAdmin.address.toLowerCase()} is missing role ${LIQUIDITY_MANAGER_ROLE}`;

        
        const liquidityManagerAddress = await silvagnum.liquidityManager();
        
       
        await network.provider.send("hardhat_impersonateAccount", [treasuryWalletAddress]);
        const treasurySigner = await ethers.getSigner(treasuryWalletAddress);
        await admin.sendTransaction({ to: treasurySigner.address, value: ethers.parseEther("1")});
        await silvagnum.connect(treasurySigner).transfer(liquidityManagerAddress, ethers.parseEther("1000"));

       
        await expect(silvagnum.connect(admin).processLiquidity()).to.not.be.revertedWith(expectedRevertMessage);

        
        await expect(
            silvagnum.connect(nonAdmin).processLiquidity()
        ).to.be.revertedWith(expectedRevertMessage);
    });
  });
});