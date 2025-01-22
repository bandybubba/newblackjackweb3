// File: test/BlackjackShoeVRFTest.js

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("BlackjackShoeVRF", function () {
  let ChipsFactory, chips;
  let ShoeFactory, shoe;
  let owner, addr1, vrfCoordinatorMock;

  beforeEach(async function () {
    [owner, addr1] = await ethers.getSigners();

    // 1) Deploy CasinoChips
    ChipsFactory = await ethers.getContractFactory("CasinoChips");
    chips = await ChipsFactory.deploy();
    await chips.waitForDeployment();

    // 2) We'll mock the VRF coordinator address for local tests
    vrfCoordinatorMock = owner.address; // just use 'owner' as a dummy coordinator

    // 3) Deploy the BlackjackShoeVRF contract
    ShoeFactory = await ethers.getContractFactory("BlackjackShoeVRF");
    shoe = await ShoeFactory.deploy(
      await chips.getAddress(),
      vrfCoordinatorMock,
      "0x000000000000000000000000000000000000000000000000000000000000abcd", // placeholder keyHash
      1234 // subscriptionId
    );
    await shoe.waitForDeployment();

    // 4) Owner mints tokens for addr1 to test
    const oneMillion = ethers.parseUnits("1000000", 18);
    await chips.connect(owner).mint(addr1.address, oneMillion);

    // 5) addr1 approves the shoe contract
    await chips.connect(addr1).approve(await shoe.getAddress(), oneMillion);
  });

  it("Should set up VRF config", async function () {
    // Just a sanity test that we can call setVRFConfig with no revert
    await shoe.connect(owner).setVRFConfig(
      "0x111111111111111111111111111111111111111111111111111111111111aaaa",
      9999, // new sub ID
      500000,
      5
    );
    // no revert => success
  });

  it("Should commit a shoe after we have a randomSeed", async function () {
    // *** Use mockFulfillRandomWords instead of fulfillRandomWords
    await shoe.connect(owner).mockFulfillRandomWords(1, [123456]);
    // now randomSeed == 123456

    // commit a new shoe
    const deckCommit = "0xabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdef1234";
    await shoe.connect(owner).commitShoe(deckCommit, 416);

    expect(await shoe.shoeCommit()).to.equal(deckCommit);
    expect(await shoe.shoeSize()).to.equal(416n);
    expect(await shoe.shoePointer()).to.equal(0n);
    expect(await shoe.shoeActive()).to.equal(true);
  });

  it("Should let a user start and finish a minimal game", async function () {
    // set randomSeed so we can commit a shoe
    await shoe.connect(owner).mockFulfillRandomWords(1, [999999]);

    // commit shoe
    const deckCommit = "0xbeefbeefbeefbeefbeefbeefbeefbeefbeefbeefbeefbeefbeefbeefbeef1234";
    await shoe.connect(owner).commitShoe(deckCommit, 416);

    // user (addr1) starts a game with 100 chips
    await shoe.connect(addr1).startGame(ethers.parseUnits("100", 18));

    // check that the contract now holds those chips
    const contractBalance = await chips.balanceOf(await shoe.getAddress());
    expect(contractBalance).to.equal(ethers.parseUnits("100", 18));

    // game state
    expect(await shoe.gameInProgress()).to.equal(true);
    expect(await shoe.currentPlayer()).to.equal(addr1.address);

    // user finishes the game, claims they lost (playerWon=false)
    await shoe.connect(addr1).finishGame(
      5, // used 5 cards
      "0x1111111111111111111111111111111111111111111111111111111111111111",
      false // playerWon
    );

    // game over, contract keeps the bet
    const finalContractBalance = await chips.balanceOf(await shoe.getAddress());
    expect(finalContractBalance).to.equal(ethers.parseUnits("100", 18)); // no payout

    // gameInProgress should now be false
    expect(await shoe.gameInProgress()).to.equal(false);

    // pointer moved by 5
    expect(await shoe.shoePointer()).to.equal(5n);
  });
});
