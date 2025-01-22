// File: test/CasinoChipsTest.js

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("CasinoChips", function () {
  let Chips, chips, owner, addr1;

  beforeEach(async function () {
    [owner, addr1] = await ethers.getSigners();
    Chips = await ethers.getContractFactory("CasinoChips");
    chips = await Chips.deploy();
    await chips.waitForDeployment(); // Ethers v6 usage
  });

  it("Should have correct name and symbol", async function () {
    expect(await chips.name()).to.equal("CasinoChips");
    expect(await chips.symbol()).to.equal("CHIPS");
  });

  it("Should assign initial supply to owner", async function () {
    const ownerBalance = await chips.balanceOf(owner.address);
    // 1,000,000 tokens with 18 decimals => parseUnits("1000000", 18)
    const expected = ethers.parseUnits("1000000", 18);
    expect(ownerBalance).to.equal(expected);
  });

  it("Owner can mint new tokens", async function () {
    const mintAmount = ethers.parseUnits("500", 18);
    await chips.connect(owner).mint(addr1.address, mintAmount);

    const addr1Balance = await chips.balanceOf(addr1.address);
    expect(addr1Balance).to.equal(mintAmount);
  });

  it("Non-owner cannot mint", async function () {
    const mintAmount = ethers.parseUnits("100", 18);
    // In OpenZeppelin 5.x, Ownable uses a custom error: "OwnableUnauthorizedAccount"
    await expect(
      chips.connect(addr1).mint(addr1.address, mintAmount)
    ).to.be.revertedWithCustomError(chips, "OwnableUnauthorizedAccount")
      .withArgs(addr1.address);
  });
});
