// File: contracts/AdvancedBlackjack.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";

/**
 * Final approach:
 *  - Multi-shoe concurrency
 *  - Commit–Reveal approach at shoe-level (not partial for each game):
 *    -> store a hash (deckCommit) for the entire deck
 *    -> optional reveal if suspicious
 *  - VRF logic remains standard (works for 2.0 or 2.5).
 */
contract AdvancedBlackjack is VRFConsumerBaseV2, Ownable {
    // CasinoChips reference
    IERC20 public chipsToken;

    // Chainlink VRF
    VRFCoordinatorV2Interface public COORDINATOR;
    bytes32 public keyHash;
    uint64 public subscriptionId;
    uint32 public callbackGasLimit = 200000;
    uint16 public requestConfirmations = 3;

    // store multiple random seeds if you want
    uint256[] public randomSeeds;

    // --------------------------------------------------
    // ShoeSlot struct & array
    // --------------------------------------------------
    struct ShoeSlot {
        bytes32 deckCommit;   // keccak256 of the entire deck array
        uint256 shoeSize;     // total # of cards (e.g. 416)
        uint256 shoePointer;  // next card index
        bool active;          // is this shoe still active?
        uint256 randomSeed;   // optional
        bool revealed;        // has the full deck been revealed?
    }
    ShoeSlot[] public shoes;

    // --------------------------------------------------
    // Game struct & concurrency
    // --------------------------------------------------
    enum GameState { NONE, IN_PROGRESS, FINISHED }
    struct Game {
        address player;
        uint256 shoeIndex;
        uint256 betAmount;
        bool playerWon;
        GameState state;
    }

    uint256 public nextGameId;
    mapping(uint256 => Game) public games;

    // --------------------------------------------------
    // Events
    // --------------------------------------------------
    event RequestedRandomSeed(uint256 requestId);
    event ReceivedRandomSeed(uint256 randomSeed);
    event ShoeCommitted(uint256 shoeIndex, bytes32 deckCommit, uint256 shoeSize);
    event ShoeRevealed(uint256 shoeIndex, uint256[] fullDeck);
    event GameStarted(uint256 gameId, address player, uint256 shoeIndex, uint256 bet);
    event GameFinished(uint256 gameId, address player, bool playerWon);

    // --------------------------------------------------
    // Constructor
    // --------------------------------------------------
    constructor(
        address chipsTokenAddress,
        address vrfCoordinator,
        bytes32 _keyHash,
        uint64 _subscriptionId
    ) 
        VRFConsumerBaseV2(vrfCoordinator)
        Ownable(msg.sender)
    {
        chipsToken = IERC20(chipsTokenAddress);
        COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
        keyHash = _keyHash;
        subscriptionId = _subscriptionId;
        nextGameId = 1;
    }

    // --------------------------------------------------
    // VRF
    // --------------------------------------------------
    function requestNewRandomSeed() external onlyOwner {
        uint32 numWords = 1;
        uint256 requestId = COORDINATOR.requestRandomWords(
            keyHash,
            subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );
        emit RequestedRandomSeed(requestId);
    }

    function fulfillRandomWords(
        uint256 /* requestId */,
        uint256[] memory randomWords
    ) internal override {
        uint256 seed = randomWords[0];
        randomSeeds.push(seed);
        emit ReceivedRandomSeed(seed);
    }

    function mockFulfillRandomWords(uint256[] calldata randomWords) external onlyOwner {
        uint256 seed = randomWords[0];
        randomSeeds.push(seed);
        emit ReceivedRandomSeed(seed);
    }

    // --------------------------------------------------
    // Shoe Management
    // --------------------------------------------------
    function createShoeSlot(
        bytes32 deckCommit, 
        uint256 shoeSize,
        uint256 randomSeedUsed
    ) external onlyOwner {
        require(shoeSize > 0, "Shoe must have cards");

        ShoeSlot memory slot = ShoeSlot({
            deckCommit: deckCommit,
            shoeSize: shoeSize,
            shoePointer: 0,
            active: true,
            randomSeed: randomSeedUsed,
            revealed: false
        });
        shoes.push(slot);

        uint256 idx = shoes.length - 1;
        emit ShoeCommitted(idx, deckCommit, shoeSize);
    }

    function disableShoeSlot(uint256 shoeIndex) external onlyOwner {
        require(shoeIndex < shoes.length, "Invalid shoeIndex");
        shoes[shoeIndex].active = false;
    }

    /**
     * @dev Reveal the entire deck array for a shoe if needed. 
     *  We check keccak256(fullDeck) == deckCommit.
     *  This is only done if someone is suspicious or at the shoe's end.
     */
    function revealFullDeck(uint256 shoeIndex, uint256[] calldata fullDeck) external onlyOwner {
        require(shoeIndex < shoes.length, "Invalid shoeIndex");
        ShoeSlot storage slot = shoes[shoeIndex];
        require(!slot.revealed, "Already revealed");

        bytes32 checkHash = keccak256(abi.encodePacked(fullDeck));
        require(checkHash == slot.deckCommit, "Deck array mismatch");
        slot.revealed = true;

        emit ShoeRevealed(shoeIndex, fullDeck);
    }

    // --------------------------------------------------
    // Start / Finish Game
    // --------------------------------------------------
    function startGame(uint256 shoeIndex, uint256 betAmount) external {
        require(shoeIndex < shoes.length, "Invalid shoeIndex");
        ShoeSlot storage slot = shoes[shoeIndex];
        require(slot.active, "Shoe not active");
        require(betAmount > 0, "Bet must be > 0");

        bool success = chipsToken.transferFrom(msg.sender, address(this), betAmount);
        require(success, "Transfer failed");

        uint256 gameId = nextGameId;
        nextGameId++;

        games[gameId] = Game({
            player: msg.sender,
            shoeIndex: shoeIndex,
            betAmount: betAmount,
            playerWon: false,
            state: GameState.IN_PROGRESS
        });

        emit GameStarted(gameId, msg.sender, shoeIndex, betAmount);
    }

    function finishGame(uint256 gameId, uint256 cardsUsed, bool playerWon) external {
        Game storage g = games[gameId];
        require(g.state == GameState.IN_PROGRESS, "Not in progress");
        require(msg.sender == g.player, "Not your game");

        ShoeSlot storage slot = shoes[g.shoeIndex];
        require(slot.shoePointer + cardsUsed <= slot.shoeSize, "Not enough cards in shoe");
        slot.shoePointer += cardsUsed;

        if (playerWon) {
            uint256 payout = g.betAmount * 2;
            chipsToken.transfer(g.player, payout);
        }

        g.playerWon = playerWon;
        g.state = GameState.FINISHED;

        emit GameFinished(gameId, g.player, playerWon);
    }

    // --------------------------------------------------
    // Admin / VRF Config
    // --------------------------------------------------
    function withdrawChips(address to, uint256 amount) external onlyOwner {
        chipsToken.transfer(to, amount);
    }

    function setVRFConfig(
        bytes32 _keyHash,
        uint64 _subscriptionId,
        uint32 _callbackGasLimit,
        uint16 _requestConfirmations
    ) external onlyOwner {
        keyHash = _keyHash;
        subscriptionId = _subscriptionId;
        callbackGasLimit = _callbackGasLimit;
        requestConfirmations = _requestConfirmations;
    }

    // --------------------------------------------------
    // Helpers
    // --------------------------------------------------
    function getShoeSlotCount() external view returns (uint256) {
        return shoes.length;
    }

    function getShoeSlotInfo(uint256 shoeIndex) external view returns (
        bytes32 deckCommit,
        uint256 shoeSize,
        uint256 shoePointer,
        bool active,
        uint256 randomSeed,
        bool revealed
    ) {
        ShoeSlot memory s = shoes[shoeIndex];
        return (s.deckCommit, s.shoeSize, s.shoePointer, s.active, s.randomSeed, s.revealed);
    }

    function getGame(uint256 gameId) external view returns (
        address player,
        uint256 shoeIndex,
        uint256 betAmount,
        bool playerWon,
        GameState state
    ) {
        Game memory g = games[gameId];
        return (g.player, g.shoeIndex, g.betAmount, g.playerWon, g.state);
    }
}
