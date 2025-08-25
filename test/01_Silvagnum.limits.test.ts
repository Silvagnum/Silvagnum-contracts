import { expect } from "chai";
import { ethers, network } from "hardhat";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { Silvagnum, MockUniswapRouter, EnhancedLiquidityManager } from "../typechain-types";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";

describe("Silvagnum - Anti-Bot & Limits Tests 🛡️", () => {
  let silvagnum: Silvagnum;
  let liquidityManager: EnhancedLiquidityManager;
  let admin: HardhatEthersSigner,
    multisig: HardhatEthersSigner,
    pair: HardhatEthersSigner,
    founder: HardhatEthersSigner,
    user1: HardhatEthersSigner,
    user2: HardhatEthersSigner,
    excludedUser: HardhatEthersSigner;
  let treasuryAddress: string;
  let mockRouter: MockUniswapRouter;

  beforeEach(async () => {
    [admin, multisig, pair, founder, user1, user2, excludedUser] = await ethers.getSigners();
    const wallets = [
      ethers.Wallet.createRandom().address, // marketing
      ethers.Wallet.createRandom().address, // growth
      ethers.Wallet.createRandom().address, // treasury
      ethers.Wallet.createRandom().address, // dao reserve
      ethers.Wallet.createRandom().address, // user incentive
      ethers.Wallet.createRandom().address, // company incentive
    ];

    const MockRouterFactory = await ethers.getContractFactory("MockUniswapRouter");
    mockRouter = await MockRouterFactory.deploy();

    const SilvagnumFactory = await ethers.getContractFactory("Silvagnum", admin);
    silvagnum = await SilvagnumFactory.deploy(
      await mockRouter.getAddress(),
      wallets[0],
      multisig.address,
      wallets[1],
      founder.address,
      wallets[2],
      wallets[3],
      wallets[4],
      wallets[5],
    );

    treasuryAddress = await silvagnum.treasuryWallet();
    const lmAddress = await silvagnum.liquidityManager();
    liquidityManager = await ethers.getContractAt("EnhancedLiquidityManager", lmAddress);

   
    const silvagnumAddress = await silvagnum.getAddress();
    const idoTokensInContract = await silvagnum.balanceOf(silvagnumAddress);

    if (idoTokensInContract > 0) {
      
      const gasMoney = ethers.parseEther("1.0");
      await network.provider.send("hardhat_setBalance", [
        silvagnumAddress,
        "0x" + gasMoney.toString(16), 
      ]);

      
      await network.provider.request({ method: "hardhat_impersonateAccount", params: [silvagnumAddress] });
      const silvagnumSigner = await ethers.getSigner(silvagnumAddress);

      
      await silvagnum.connect(silvagnumSigner).transfer(admin.address, idoTokensInContract);

      
      await network.provider.request({ method: "hardhat_stopImpersonatingAccount", params: [silvagnumAddress] });
    }
    

    await silvagnum.connect(admin).excludeFromLimits(founder.address, true);
    await silvagnum.connect(admin).excludeFromFee(founder.address, true);

    await silvagnum.connect(founder).transfer(user1.address, ethers.parseEther("15000000"));
    await silvagnum.connect(founder).transfer(user2.address, ethers.parseEther("15000000"));
    await silvagnum.connect(founder).transfer(excludedUser.address, ethers.parseEther("15000000"));

    await silvagnum.connect(admin).enableTrading(pair.address);

    await silvagnum.connect(admin).excludeFromLimits(founder.address, false);
    await silvagnum.connect(admin).excludeFromFee(founder.address, false);
  });


  describe("Wallet and Transaction Limits", () => {
    it("should REVERT if a transfer exceeds the max wallet limit", async () => {
      await network.provider.request({ method: "hardhat_impersonateAccount", params: [treasuryAddress] });
      const treasurySigner = await ethers.getSigner(treasuryAddress);
      await admin.sendTransaction({ to: treasuryAddress, value: ethers.parseEther("10") });

      const maxWalletAmount = await silvagnum.maxWalletAmount();
      const user2InitialBalance = await silvagnum.balanceOf(user2.address);
      const amountToSend = maxWalletAmount - user2InitialBalance;

      await silvagnum.connect(treasurySigner).transfer(user2.address, amountToSend);
      expect(await silvagnum.balanceOf(user2.address)).to.equal(maxWalletAmount);

      await expect(silvagnum.connect(user1).transfer(user2.address, ethers.parseEther("1"))).to.be.revertedWith(
        "Wallet limit exceeded",
      );
      await network.provider.request({ method: "hardhat_stopImpersonatingAccount", params: [treasuryAddress] });
    });

    it("should allow an excluded user to bypass wallet and transaction limits", async () => {
      await silvagnum.connect(admin).excludeFromLimits(excludedUser.address, true);
      const maxTxAmount = await silvagnum.maxTxAmount();
      const largeAmount = maxTxAmount + ethers.parseEther("1");
      await expect(silvagnum.connect(excludedUser).transfer(user1.address, largeAmount)).to.not.be.reverted;
    });
  });

  describe("Anti-Bot Mechanics", () => {
    it("should apply snipe, reflection, and liquidity fees sequentially on large sales", async () => {
      const snipeFee = await silvagnum.snipeFee();
      const reflectionFee = await silvagnum.reflectionFee();
      const liquidityFee = await silvagnum.liquidityFee();
      const amountToSell = ethers.parseEther("9000000");
      const snipeFeeAmount = (amountToSell * snipeFee) / 100n;
      let remainingAfterSnipe = amountToSell - snipeFeeAmount;
      const reflectionFeeAmount = (remainingAfterSnipe * reflectionFee) / 100n;
      let remainingAfterReflection = remainingAfterSnipe - reflectionFeeAmount;
      const liquidityFeeAmount = (remainingAfterReflection * liquidityFee) / 100n;
      const finalAmountToPair = remainingAfterReflection - liquidityFeeAmount;
      const totalToMainContract = snipeFeeAmount + reflectionFeeAmount;

      await expect(() => silvagnum.connect(user1).transfer(pair.address, amountToSell)).to.changeTokenBalances(
        silvagnum,
        [user1, pair, silvagnum, liquidityManager],
        [-amountToSell, finalAmountToPair, totalToMainContract, liquidityFeeAmount],
      );
    });

    it("should apply all fees after exceeding max sell count", async () => {
      const maxSells = await silvagnum.maxSellsPerAddress();
      const smallSellAmount = ethers.parseEther("100");
      const userCooldown = await silvagnum.txDelaySeconds();

      for (let i = 0; i < Number(maxSells); i++) {
        await silvagnum.connect(user1).transfer(pair.address, smallSellAmount);
        await time.increase(userCooldown);
      }

      const snipeFee = await silvagnum.snipeFee();
      const reflectionFee = await silvagnum.reflectionFee();
      const liquidityFee = await silvagnum.liquidityFee();
      const snipeFeeAmount = (smallSellAmount * snipeFee) / 100n;
      let remainingAmount = smallSellAmount - snipeFeeAmount;
      const reflectionFeeAmount = (remainingAmount * reflectionFee) / 100n;
      remainingAmount -= reflectionFeeAmount;
      const liquidityFeeAmount = (remainingAmount * liquidityFee) / 100n;
      const finalAmountToPair = remainingAmount - liquidityFeeAmount;
      const totalToMainContract = snipeFeeAmount + reflectionFeeAmount;

      await expect(() => silvagnum.connect(user1).transfer(pair.address, smallSellAmount)).to.changeTokenBalances(
        silvagnum,
        [user1, pair, silvagnum, liquidityManager],
        [-smallSellAmount, finalAmountToPair, totalToMainContract, liquidityFeeAmount],
      );
    });
  });

  describe("Transaction Cooldown (txDelaySeconds)", () => {
    it("should REVERT if a user tries to sell again before the cooldown expires", async () => {
      await silvagnum.connect(user1).transfer(pair.address, ethers.parseEther("1000"));
      await expect(silvagnum.connect(user1).transfer(pair.address, ethers.parseEther("1000"))).to.be.revertedWith(
        "Swap cooldown active",
      );
    });

    it("should allow a sale after the user cooldown period has passed", async () => {
      await silvagnum.connect(user1).transfer(pair.address, ethers.parseEther("1000"));
      const userCooldown = await silvagnum.txDelaySeconds();
      await time.increase(userCooldown);
      await expect(silvagnum.connect(user1).transfer(pair.address, ethers.parseEther("1000"))).to.not.be.reverted;
    });
  });
});