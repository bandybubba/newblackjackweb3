// File: test/AdvancedBlackjackTest.js
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("AdvancedBlackjack", function () {
  let ChipsFactory, chips;
  let BlackjackFactory, blackjack;
  let owner, addr1;

  beforeEach(async function () {
    [owner, addr1] = await ethers.getSigners();

    // Deploy CasinoChips
    ChipsFactory = await ethers.getContractFactory("CasinoChips");
    chips = await ChipsFactory.deploy();
    await chips.waitForDeployment();

    // Deploy AdvancedBlackjack
    BlackjackFactory = await ethers.getContractFactory("AdvancedBlackjack");
    blackjack = await BlackjackFactory.deploy(
      await chips.getAddress(),
      owner.address, // mock VRF
      "0x000000000000000000000000000000000000000000000000000000000000abcd",
      1234
    );
    await blackjack.waitForDeployment();

    // Mint chips for addr1
    await chips.connect(owner).mint(addr1.address, ethers.parseUnits("100000", 18));

    // Approve
    await chips.connect(addr1).approve(await blackjack.getAddress(), ethers.parseUnits("100000", 18));
  });

  it("Should create a shoe slot, start a game, finish a game", async function () {
    // createShoeSlot
    let deckCommit = "0xabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdef1234";
    await blackjack.connect(owner).createShoeSlot(deckCommit, 52, 999999);

    // startGame
    await blackjack.connect(addr1).startGame(0, ethers.parseUnits("100", 18));
    // gameId == 1
    let gameInfo = await blackjack.getGame(1);
    expect(gameInfo[0]).to.equal(addr1.address);

    // finishGame
    await blackjack.connect(addr1).finishGame(1, 5, true); 
    // playerWon => gets double
    let finalBal = await chips.balanceOf(addr1.address);
    // started with 100000, bet 100 => 99900 left in contract, if they won => +200 => 100100
    // must do bigints carefully
    expect(finalBal).to.equal(ethers.parseUnits("100100", 18));
  });
});
