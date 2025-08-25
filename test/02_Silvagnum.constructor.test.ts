import { expect } from "chai";
import { ethers } from "hardhat";
import { Silvagnum } from "../typechain-types";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";

describe("Silvagnum - Constructor & Deployment 💎", () => {
 
  let SilvagnumFactory: any;
  let deployer: HardhatEthersSigner,
    router: HardhatEthersSigner,
    marketing: HardhatEthersSigner,
    vestingAdmin: HardhatEthersSigner,
    growth: HardhatEthersSigner,
    founder: HardhatEthersSigner,
    treasury: HardhatEthersSigner,
    dao: HardhatEthersSigner,
    userIncentive: HardhatEthersSigner,
    companyIncentive: HardhatEthersSigner;

  
  before(async () => {
    [
      deployer,
      router,
      marketing,
      vestingAdmin,
      growth,
      founder,
      treasury,
      dao,
      userIncentive,
      companyIncentive,
    ] = await ethers.getSigners();
    SilvagnumFactory = await ethers.getContractFactory("Silvagnum", deployer);
  });

  it("should correctly mint and distribute the initial token supply", async () => {
    
    const silvagnum = await SilvagnumFactory.deploy(
      router.address, marketing.address, vestingAdmin.address,
      growth.address, founder.address, treasury.address,
      dao.address, userIncentive.address, companyIncentive.address
    );

   
    const DECIMALS = 10n ** 18n;
    const founderTokens = 100_000_000n * DECIMALS;
    const vestedTokens = 900_000_000n * DECIMALS;
    const growthTokens = 500_000_000n * DECIMALS;
    const treasuryTokens = 3_500_000_000n * DECIMALS;
    const daoTokens = 800_000_000n * DECIMALS;
    const userIncentives = 100_000_000n * DECIMALS;
    const companyIncentives = 100_000_000n * DECIMALS;
    const idoTokens = 1_200_000_000n * DECIMALS;

    const expectedTotalSupply = founderTokens + vestedTokens + growthTokens + treasuryTokens +
                                daoTokens + userIncentives + companyIncentives + idoTokens;

    
    expect(await silvagnum.balanceOf(founder.address)).to.equal(founderTokens);
    const vestingContractAddress = await silvagnum.silvagnumVesting();
    expect(await silvagnum.balanceOf(vestingContractAddress)).to.equal(vestedTokens);
    expect(await silvagnum.balanceOf(growth.address)).to.equal(growthTokens);
    expect(await silvagnum.balanceOf(treasury.address)).to.equal(treasuryTokens);
    expect(await silvagnum.balanceOf(dao.address)).to.equal(daoTokens);
    expect(await silvagnum.balanceOf(userIncentive.address)).to.equal(userIncentives);
    expect(await silvagnum.balanceOf(companyIncentive.address)).to.equal(companyIncentives);
    expect(await silvagnum.balanceOf(await silvagnum.getAddress())).to.equal(idoTokens);

   
    expect(await silvagnum.balanceOf(deployer.address)).to.equal(0);

    
    expect(await silvagnum.totalSupply()).to.equal(expectedTotalSupply);
  });

  it("should emit all necessary events during deployment", async () => {
    
    const DECIMALS = 10n ** 18n;
    const founderTokens = 100_000_000n * DECIMALS;
    const treasuryTokens = 3_500_000_000n * DECIMALS;
    const daoTokens = 800_000_000n * DECIMALS;
    const userIncentives = 100_000_000n * DECIMALS;
    const companyIncentives = 100_000_000n * DECIMALS;

    const totalAllocated = 7_200_000_000n * DECIMALS;
    const initialTotalSupply = 12_000_000_000n * DECIMALS;
    const expectedBurnAmount = initialTotalSupply - totalAllocated;

    
    const silvagnum = await SilvagnumFactory.deploy(
      router.address, marketing.address, vestingAdmin.address,
      growth.address, founder.address, treasury.address,
      dao.address, userIncentive.address, companyIncentive.address
    );
   
    await silvagnum.waitForDeployment();

    
    await expect(silvagnum.deploymentTransaction())
      .to.emit(silvagnum, "FounderTokensAllocated").withArgs(founder.address, founderTokens)
      .and.to.emit(silvagnum, "TreasuryAllocated").withArgs(treasury.address, treasuryTokens)
      .and.to.emit(silvagnum, "DAOTokensReserved").withArgs(dao.address, daoTokens)
      .and.to.emit(silvagnum, "UserIncentiveFunded").withArgs(userIncentive.address, userIncentives)
      .and.to.emit(silvagnum, "CompanyIncentiveFunded").withArgs(companyIncentive.address, companyIncentives)
      .and.to.emit(silvagnum, "TokensBurned").withArgs(expectedBurnAmount);
  });
});