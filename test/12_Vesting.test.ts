import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers";
import { Silvagnum, SilvagnumVestingWallet } from "../typechain-types";

/**
 * @title Logic Tests for the SilvagnumVestingWallet
 * @dev This test suite validates the vesting mechanism, including the cliff period,
 * linear token release, access permissions, and vesting progress.
 */
describe("Silvagnum Vesting Wallet Logic ⏳", () => {
  // --- CONSTANTS ---
  // Values are taken directly from the contracts to ensure consistency.
  const VESTED_AMOUNT = ethers.parseEther("900000000"); // 900 Million
  const CLIFF_DURATION = 365 * 24 * 60 * 60; // 1 year in seconds
  const TOTAL_DURATION = 4 * 365 * 24 * 60 * 60; // 4 years in seconds

  /**
   * @dev Fixture to deploy the Silvagnum ecosystem and isolate the vesting components.
   * This creates a clean and consistent state for each test.
   */
  async function deployVestingFixture() {
    const [admin, vestingAdmin, unauthorizedUser] = await ethers.getSigners();

    
    const MockLPTokenFactory = await ethers.getContractFactory("MockLPToken");
    const mockLpToken = await MockLPTokenFactory.deploy();
    
    
    const MockRouterFactory = await ethers.getContractFactory("SimpleTestRouter");
    const mockRouter = await MockRouterFactory.deploy(await mockLpToken.getAddress());

    
    const marketingWallet = ethers.Wallet.createRandom().address;
    const growthReserveWallet = ethers.Wallet.createRandom().address;
    const founderWallet = ethers.Wallet.createRandom().address;
    const treasuryWallet = ethers.Wallet.createRandom().address;
    const futureDAOReserve = ethers.Wallet.createRandom().address;
    const userIncentiveWallet = ethers.Wallet.createRandom().address;
    const companyIncentiveWallet = ethers.Wallet.createRandom().address;

    
    const SilvagnumFactory = await ethers.getContractFactory("Silvagnum");
    const silvagnum = await SilvagnumFactory.deploy(
      await mockRouter.getAddress(),
      marketingWallet,
      vestingAdmin.address,
      growthReserveWallet,
      founderWallet,
      treasuryWallet,
      futureDAOReserve,
      userIncentiveWallet,
      companyIncentiveWallet
    );

    
    const vestingAddress = await silvagnum.silvagnumVesting();
    const vesting = await ethers.getContractAt("SilvagnumVestingWallet", vestingAddress);

    return {
      silvagnum,
      vesting,
      admin,
      vestingAdmin,
      unauthorizedUser,
    };
  }

  

  it("should have the correct initial amount of tokens locked in the vesting contract", async () => {
    const { silvagnum, vesting } = await loadFixture(deployVestingFixture);
    const vestingContractBalance = await silvagnum.balanceOf(await vesting.getAddress());

    expect(vestingContractBalance).to.equal(VESTED_AMOUNT);
  });

  it("should fail to release tokens before the cliff period ends", async () => {
    const { silvagnum, vestingAdmin } = await loadFixture(deployVestingFixture);

    // Attempting to release tokens immediately should fail due to the cliff.
    await expect(silvagnum.connect(vestingAdmin).releaseVestedTokens())
      .to.be.revertedWith("Cliff not reached");
  });

  it("should allow token release just after the cliff ends", async () => {
    const { silvagnum, vesting, vestingAdmin } = await loadFixture(deployVestingFixture);

    // Advance the blockchain time to just after the cliff ends.
    await time.increase(CLIFF_DURATION + 1);

    
    const releasableAmount = await vesting["releasable(address)"](await silvagnum.getAddress());
    expect(releasableAmount).to.be.gt(0, "Should have releasable tokens after cliff");

    const balanceBefore = await silvagnum.balanceOf(vestingAdmin.address);
    await silvagnum.connect(vestingAdmin).releaseVestedTokens();
    const balanceAfter = await silvagnum.balanceOf(vestingAdmin.address);

    expect(balanceAfter).to.be.gt(balanceBefore, "Beneficiary balance should increase after release");
  });

  it("should release tokens proportionally halfway through the total duration", async () => {
    const { silvagnum, vesting } = await loadFixture(deployVestingFixture);
    
    // Advance time by 2 years (half of the 4-year total duration).
    const twoYears = 2 * 365 * 24 * 60 * 60;
    await time.increase(twoYears);

    
    const releasableAmount = await vesting["releasable(address)"](await silvagnum.getAddress());
    const expectedAmount = VESTED_AMOUNT / 2n; // 50% of the total.

    // I use 'closeTo' to handle minor rounding inaccuracies with seconds.
    expect(releasableAmount).to.be.closeTo(expectedAmount, ethers.parseEther("1"));
  });

  it("should allow the full amount to be released after the total duration", async () => {
    const { silvagnum, vesting, vestingAdmin } = await loadFixture(deployVestingFixture);

    // Advance time to the end of the vesting period.
    await time.increase(TOTAL_DURATION + 1);

    
    const releasableAmount = await vesting["releasable(address)"](await silvagnum.getAddress());
    expect(releasableAmount).to.equal(VESTED_AMOUNT, "All tokens should be releasable");

    await silvagnum.connect(vestingAdmin).releaseVestedTokens();
    const finalBalance = await silvagnum.balanceOf(vestingAdmin.address);

    expect(finalBalance).to.equal(VESTED_AMOUNT, "Beneficiary should have received all vested tokens");
  });

  it("should return correct values from the vestingProgress function", async () => {
    const { silvagnum, vesting } = await loadFixture(deployVestingFixture);
    
    // Advance to a specific point in time: 18 months (12 for cliff + 6 for vesting).
    const eighteenMonths = 18 * 30 * 24 * 60 * 60; // Approximation.
    const startTime = await vesting.start();
    await time.setNextBlockTimestamp(startTime + BigInt(eighteenMonths));

    const [released, releasable, totalVested] = await vesting.vestingProgress(await silvagnum.getAddress());

    // Calculate the expected value using the OpenZeppelin formula.
    const currentTime = await time.latest();
    const expectedTotal = (VESTED_AMOUNT * (BigInt(currentTime) - startTime)) / BigInt(TOTAL_DURATION);
    
    expect(totalVested).to.be.closeTo(expectedTotal, ethers.parseEther("1"), "Total vested amount is incorrect");
    expect(totalVested).to.equal(released + releasable, "Progress calculation is inconsistent");
  });

  it("should only allow the vesting admin (or contract admin) to trigger the release", async () => {
    const { silvagnum, vestingAdmin, unauthorizedUser } = await loadFixture(deployVestingFixture);

    await time.increase(CLIFF_DURATION + 1);

    // Attempt with an unauthorized user should fail.
    await expect(silvagnum.connect(unauthorizedUser).releaseVestedTokens())
      .to.be.revertedWith("Caller is not MultiSig or Admin");

    // Attempt with the vesting admin should succeed.
    await expect(silvagnum.connect(vestingAdmin).releaseVestedTokens())
      .to.not.be.reverted;
  });

  it("should not release more tokens than available in a second immediate call", async () => {
    const { silvagnum, vestingAdmin } = await loadFixture(deployVestingFixture);
    
    await time.increase(CLIFF_DURATION + 1);

    // The first call releases the available tokens.
    await silvagnum.connect(vestingAdmin).releaseVestedTokens();
    const balanceAfterFirstCall = await silvagnum.balanceOf(vestingAdmin.address);
    expect(balanceAfterFirstCall).to.be.gt(0);

    // The second immediate call should release nothing new.
    await silvagnum.connect(vestingAdmin).releaseVestedTokens();
    const balanceAfterSecondCall = await silvagnum.balanceOf(vestingAdmin.address);

   expect(balanceAfterSecondCall).to.be.closeTo(balanceAfterFirstCall, ethers.parseEther("10"));
  });
});