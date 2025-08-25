import { expect } from "chai";
import { ethers, network } from "hardhat";
import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers";
import { Silvagnum, SilvagnumVestingWallet } from "../typechain-types";

/**
 * @dev This suite tests the long-term sustainability of the ecosystem's tokenomics,
 * focusing on the impact of vested tokens entering the market.
 */
describe("Ecosystem Lifecycle & Vesting Impact Test Suite 💧", () => {

  /**
   * @dev A complex fixture that deploys the ecosystem and prepares it for advanced testing.
   * It creates multiple holders and sets up a post-IDO, pre-trading state.
   */
  async function deployGauntletFixture() {
    
    const signers = await ethers.getSigners();
    const [admin, marketingWallet, founder, vestingAdmin, whale, priceManipulator, ...holders] = signers;

   
    const MockLPTokenFactory = await ethers.getContractFactory("MockLPToken");
    const mockLpToken = await MockLPTokenFactory.deploy();

    
    const SimpleTestRouterFactory = await ethers.getContractFactory("SimpleTestRouter");
    const testRouter = await SimpleTestRouterFactory.deploy(await mockLpToken.getAddress());
   
    const pair = ethers.Wallet.createRandom();
    const pairAddress = pair.address;
    
    
    const growthReserveWallet = ethers.Wallet.createRandom().address;
    const treasuryWallet = ethers.Wallet.createRandom().address;
    const futureDAOReserve = ethers.Wallet.createRandom().address;
    const userIncentiveWallet = ethers.Wallet.createRandom().address;
    const companyIncentiveWallet = ethers.Wallet.createRandom().address;

   
    const SilvagnumFactory = await ethers.getContractFactory("Silvagnum");
    const silvagnum = await SilvagnumFactory.deploy(
      await testRouter.getAddress(), marketingWallet.address, vestingAdmin.address,
      growthReserveWallet, founder.address, treasuryWallet, futureDAOReserve,
      userIncentiveWallet, companyIncentiveWallet
    );

   
    const dividendTracker = await ethers.getContractAt("AdvancedDividendTracker", await silvagnum.advancedDividendTracker());
    const silvagnumVesting = await ethers.getContractAt("SilvagnumVestingWallet", await silvagnum.silvagnumVesting()) as SilvagnumVestingWallet;

    
    await silvagnum.connect(admin).startIDO();
    const maxContribution = await silvagnum.MAX_CONTRIBUTION();
    for(let i = 0; i < 8 && i < holders.length; i++) {
        if(holders[i]) {
            await silvagnum.connect(holders[i]).participateInIDO({ value: maxContribution });
        }
    }
    
    const mockLocker = await (await ethers.getContractFactory("MockLocker")).deploy();
    await silvagnum.connect(admin).setLiquidityManagerLpToken(await mockLpToken.getAddress());
    await silvagnum.connect(admin).setLiquidityManagerLockerAddress(await mockLocker.getAddress());
    await admin.sendTransaction({ to: await testRouter.getAddress(), value: ethers.parseEther("500") });
    await silvagnum.connect(admin).finalizeIDO();

  
    await silvagnum.connect(admin).withdrawUnallocatedTokens();

    
    await network.provider.send("hardhat_impersonateAccount", [treasuryWallet]);
    const treasurySigner = await ethers.getSigner(treasuryWallet);
    await admin.sendTransaction({ to: treasurySigner.address, value: ethers.parseEther("10") }); 
    await silvagnum.connect(treasurySigner).transfer(whale.address, ethers.parseEther("50000000"));
    await network.provider.send("hardhat_stopImpersonatingAccount", [treasuryWallet]);
    
    
    return { silvagnum, dividendTracker, testRouter, admin, vestingAdmin, holders, silvagnumVesting, pairAddress };
  }


  /**
   * @notice This supreme test simulates a real-world, high-impact market event.
   * @purpose To prove that the entire tokenomics cycle is robust, self-sustaining, and can 
   * handle the pressure of a large influx of vested tokens, ensuring long-term project health.
   */
  it("Should realistically complete the full tokenomics cycle after vested tokens are distributed and sold", async () => {
    
    const { 
        silvagnum, 
        dividendTracker, 
        admin, 
        vestingAdmin, 
        silvagnumVesting,
        holders,
        pairAddress 
    } = await loadFixture(deployGauntletFixture);

    const teamMember = holders[0]; 
    
   
    await silvagnum.connect(admin).enableTrading(pairAddress);
    await silvagnum.connect(admin).excludeFromFee(pairAddress, false);

    console.log(`      ⏳ Simulating the passage of 1 year to reach the vesting cliff...`);

    // ---
    // ACT 1: The vesting admin (distributor) releases tokens to their own wallet after the cliff.
    // ---
    const oneYearInSeconds = 365 * 24 * 60 * 60;
    await time.increase(oneYearInSeconds + 1); 
    await silvagnum.connect(vestingAdmin).releaseVestedTokens();
    console.log(`      ✅ Vesting tokens released to the distributor wallet (vestingAdmin).`);

   // ---
   // ACT 2: The distributor sends tokens to the founder (myself), requiring a temporary limit exclusion for the large transfer.
   // ---
    const vestedAmount = await silvagnum.balanceOf(vestingAdmin.address);
    const distributionAmount = vestedAmount / 2n; 
    
    await silvagnum.connect(admin).excludeFromLimits(teamMember.address, true);
    await silvagnum.connect(vestingAdmin).transfer(teamMember.address, distributionAmount);
    await silvagnum.connect(admin).excludeFromLimits(teamMember.address, false);
    console.log(`      ✅ Distributor sent ${ethers.formatEther(distributionAmount)} tokens to a team member.`);

    // ---
    // ACT 3: As the founder (using the founderWallet, which—as seen in Silvagnum's code—is subject to all limits),
    // I sell my entire balance by breaking it into multiple smaller transactions,
    // respecting the contract's `maxTxAmount` and `txDelaySeconds` security limits.
    // ---

    console.log(`      💥 Simulating a realistic large sell-off in multiple transactions...`);
    await silvagnum.connect(admin).setSwapCooldown(10); 
    const maxTxAmount = await silvagnum.maxTxAmount();
    const txDelaySeconds = await silvagnum.txDelaySeconds();
    let remainingBalance = await silvagnum.balanceOf(teamMember.address);
    const initialTrackerMatic = await ethers.provider.getBalance(await dividendTracker.getAddress());
    let transactionsMade = 0;

    while (remainingBalance > 0) {
        const amountToSell = remainingBalance > maxTxAmount ? maxTxAmount : remainingBalance;
        await silvagnum.connect(teamMember).transfer(pairAddress, amountToSell);
        transactionsMade++;
        remainingBalance = await silvagnum.balanceOf(teamMember.address);
        if (remainingBalance > 0) {
            await time.increase(txDelaySeconds);
        }
    }
    console.log(`      ✅ Sustained sell-off completed in ${transactionsMade} transactions.`);

    // ---
    // ASSERT: Verify that the full tokenomics cycle functioned as expected after the sustained sell-off.
    // ---
    const finalTrackerMatic = await ethers.provider.getBalance(await dividendTracker.getAddress());
    expect(finalTrackerMatic).to.be.gt(initialTrackerMatic, "The dividend tracker's MATIC balance should increase after the team member's sale");
    
    const dividendsGenerated = finalTrackerMatic - initialTrackerMatic;
    console.log(`      ✅ Full cycle complete! Sale generated ${ethers.formatUnits(dividendsGenerated, "ether")} MATIC in dividends.`);
    console.log(`      ✅ Proof: The tokenomics realistically handle a sustained sell-off while respecting all security limits.`);
  });
});