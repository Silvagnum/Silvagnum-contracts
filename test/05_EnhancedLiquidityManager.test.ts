import { expect } from "chai";
import { ethers, network } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { Silvagnum, EnhancedLiquidityManager } from "../typechain-types";

describe("EnhancedLiquidityManager", () => {
  async function deployFixture() {
    const signers = await ethers.getSigners();
    const [admin, marketingWallet, founder, nonOwner, vestingAdmin, ...contributors] = signers;
    const wallets = [marketingWallet.address, ethers.Wallet.createRandom().address, ethers.Wallet.createRandom().address, founder.address, ethers.Wallet.createRandom().address, ethers.Wallet.createRandom().address, ethers.Wallet.createRandom().address, ethers.Wallet.createRandom().address];

    const ManagerTestRouterFactory = await ethers.getContractFactory("ManagerTestRouter");
    const testRouter = await ManagerTestRouterFactory.deploy();

    const MockLockerFactory = await ethers.getContractFactory("MockLocker");
    const mockLocker = await MockLockerFactory.deploy();

    const MockLPTokenFactory = await ethers.getContractFactory("MockLPToken");
    const mockLpToken = await MockLPTokenFactory.deploy();

    const SilvagnumFactory = await ethers.getContractFactory("Silvagnum");
    const silvagnum = await SilvagnumFactory.deploy(
      await testRouter.getAddress(), marketingWallet.address, vestingAdmin.address,
      wallets[1], founder.address, wallets[2], wallets[3], wallets[4], wallets[0]
    );

    const managerAddress = await silvagnum.liquidityManager();
    const manager = await ethers.getContractAt("EnhancedLiquidityManager", managerAddress) as EnhancedLiquidityManager;

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

    await silvagnum.connect(admin).excludeFromLimits(founder.address, true);
    await silvagnum.connect(admin).excludeFromFee(founder.address, true);
    await silvagnum.connect(founder).transfer(await manager.getAddress(), ethers.parseEther("1000"));
    await silvagnum.connect(admin).excludeFromLimits(founder.address, false);
    await silvagnum.connect(admin).excludeFromFee(founder.address, false);

    const silvagnumAddress = await silvagnum.getAddress();
    await network.provider.request({ method: "hardhat_impersonateAccount", params: [silvagnumAddress] });
    const ownerSigner = await ethers.getSigner(silvagnumAddress);
    
    
    const balanceHex = "0x" + ethers.parseEther("10").toString(16);
    await network.provider.send("hardhat_setBalance", [
      ownerSigner.address,
      balanceHex,
    ]);
   
    
   await admin.sendTransaction({ to: await testRouter.getAddress(), value: ethers.parseEther("500") });

    return { silvagnum, manager, ownerSigner, admin, marketingWallet, nonOwner, mockLpToken };
  }

  describe("Admin & Configuration", () => {
    it("should allow the owner to change settings", async () => {
      const { manager, ownerSigner } = await loadFixture(deployFixture);
      const newWallet = ethers.Wallet.createRandom().address;
      await manager.connect(ownerSigner).setSlippage(150);
      await manager.connect(ownerSigner).setMarketingWallet(newWallet);
      expect(await manager.slippageDivisor()).to.equal(150);
      expect(await manager.marketingWallet()).to.equal(newWallet);
    });

    it("should REVERT if a non-owner tries to call admin functions", async () => {
      const { manager, nonOwner } = await loadFixture(deployFixture);
      await expect(manager.connect(nonOwner).setSlippage(150)).to.be.revertedWith("Ownable: caller is not the owner");
    });
  });

  describe("Core Logic: processFees", () => {
    it("should split funds (75%/25%), swap for MATIC, and add liquidity", async () => {
      const { silvagnum, manager, ownerSigner, marketingWallet } = await loadFixture(deployFixture);
      const initialTokensInManager = await silvagnum.balanceOf(await manager.getAddress());
      const expectedMarketingETH = (initialTokensInManager * 25n / 100n) / 2n;

      await expect(manager.connect(ownerSigner).processFees())
        .to.changeEtherBalance(marketingWallet, expectedMarketingETH);
      expect(await silvagnum.balanceOf(await manager.getAddress())).to.equal(0);
    });

    it("should revert if token balance is below the minimum threshold", async () => {
      const { manager, ownerSigner } = await loadFixture(deployFixture);
      await manager.connect(ownerSigner).setMinTokensBeforeSwap(ethers.parseEther("2000"));
      await expect(manager.connect(ownerSigner).processFees()).to.be.revertedWith("Insufficient tokens");
    });
  });

  describe("Security", () => {
    it("should allow the owner to withdraw rogue ERC20 tokens", async () => {
        const { manager, ownerSigner, silvagnum } = await loadFixture(deployFixture);
        const MockTokenFactory = await ethers.getContractFactory("MockLPToken");
        const rogueToken = await MockTokenFactory.deploy();
        const amount = ethers.parseEther("123");
        await rogueToken.mint(await manager.getAddress(), amount);
        await manager.connect(ownerSigner).emergencyWithdrawTokens(await rogueToken.getAddress());
        expect(await rogueToken.balanceOf(await silvagnum.getAddress())).to.equal(amount);
    });
  });
});