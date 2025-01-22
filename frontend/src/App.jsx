// File: src/App.jsx
import React, { useState } from "react";
import { ethers } from "ethers";

// Minimal ABIs for your CasinoChips & BlackjackShoeVRF contracts
const CHIPS_ABI = [
  "function name() view returns (string)",
  "function symbol() view returns (string)",
  "function balanceOf(address) view returns (uint256)",
  "function allowance(address, address) view returns (uint256)",
  "function approve(address spender, uint256 amount) returns (bool)",
  "function transferFrom(address from, address to, uint256 amount) returns (bool)"
];

const SHOE_ABI = [
  "function startGame(uint256 betAmount) external",
  "function finishGame(uint256 cardsUsed, bytes32 subDeckHash, bool playerWon) external",
  "function requestNewRandomSeed() external",
  "function commitShoe(bytes32 _shoeCommit, uint256 _shoeSize) external",
  "function shoePointer() view returns (uint256)",
  "function shoeActive() view returns (bool)",
  "function gameInProgress() view returns (bool)"
];

export default function App() {
  // State for wallet & contracts
  const [currentAccount, setCurrentAccount] = useState("");
  const [walletConnected, setWalletConnected] = useState(false);

  // Replace with your actual addresses
  const [chipsAddress] = useState("0xYOUR_CHIPS_CONTRACT");
  const [shoeAddress] = useState("0xYOUR_SHOE_CONTRACT");

  const [chipsContract, setChipsContract] = useState(null);
  const [shoeContract, setShoeContract] = useState(null);

  const [balance, setBalance] = useState("0");
  const [betAmount, setBetAmount] = useState("0");

  // For finishing a game
  const [cardsUsed, setCardsUsed] = useState("5");
  const [subDeckHash, setSubDeckHash] = useState("0x1111111111111111111111111111111111111111111111111111111111111111");
  const [playerWon, setPlayerWon] = useState(false);

  // For commit shoe
  const [deckCommit, setDeckCommit] = useState("");
  const [deckSize, setDeckSize] = useState("416");

  async function connectWallet() {
    if (!window.ethereum) {
      alert("No Metamask found!");
      return;
    }
    try {
      const provider = new ethers.BrowserProvider(window.ethereum);
      const accounts = await provider.send("eth_requestAccounts", []);
      if (accounts.length === 0) return;

      const account = accounts[0];
      setCurrentAccount(account);
      setWalletConnected(true);

      const signer = await provider.getSigner();
      const chips = new ethers.Contract(chipsAddress, CHIPS_ABI, signer);
      const shoe = new ethers.Contract(shoeAddress, SHOE_ABI, signer);

      setChipsContract(chips);
      setShoeContract(shoe);

      // get balance
      const bal = await chips.balanceOf(account);
      setBalance(ethers.formatUnits(bal, 18));
    } catch (err) {
      console.error(err);
      alert("Error connecting wallet");
    }
  }

  async function refreshBalance() {
    if (!chipsContract || !currentAccount) return;
    try {
      const bal = await chipsContract.balanceOf(currentAccount);
      setBalance(ethers.formatUnits(bal, 18));
    } catch (err) {
      console.error(err);
      alert("refreshBalance error");
    }
  }

  async function handleStartGame() {
    if (!chipsContract || !shoeContract) return;
    try {
      const weiBet = ethers.parseUnits(betAmount, 18);
      const allowance = await chipsContract.allowance(currentAccount, shoeAddress);
      if (allowance < weiBet) {
        const tx1 = await chipsContract.approve(shoeAddress, weiBet);
        await tx1.wait();
      }
      const tx2 = await shoeContract.startGame(weiBet);
      await tx2.wait();
      alert("Game started!");
      refreshBalance();
    } catch (err) {
      console.error(err);
      alert("handleStartGame error");
    }
  }

  async function handleFinishGame() {
    if (!shoeContract) return;
    try {
      const used = parseInt(cardsUsed);
      const tx = await shoeContract.finishGame(used, subDeckHash, playerWon);
      await tx.wait();
      alert("Game finished!");
      refreshBalance();
    } catch (err) {
      console.error(err);
      alert("handleFinishGame error");
    }
  }

  async function handleRequestNewSeed() {
    if (!shoeContract) return;
    try {
      const tx = await shoeContract.requestNewRandomSeed();
      await tx.wait();
      alert("Requested new seed");
    } catch (err) {
      console.error(err);
      alert("handleRequestNewSeed error");
    }
  }

  async function handleCommitShoe() {
    if (!shoeContract) return;
    try {
      const sizeNum = parseInt(deckSize);
      const tx = await shoeContract.commitShoe(deckCommit, sizeNum);
      await tx.wait();
      alert("Shoe committed!");
    } catch (err) {
      console.error(err);
      alert("handleCommitShoe error");
    }
  }

  return (
    <div style={{ padding: 20 }}>
      <h1>Vite React Blackjack</h1>

      {!walletConnected ? (
        <button onClick={connectWallet}>Connect Wallet</button>
      ) : (
        <div>
          <p>Account: {currentAccount}</p>
          <p>CHIPS Balance: {balance}</p>
          <button onClick={refreshBalance}>Refresh Balance</button>
        </div>
      )}

      <hr />
      <h2>Start Game</h2>
      <div>
        Bet Amount: 
        <input
          type="text"
          value={betAmount}
          onChange={(e) => setBetAmount(e.target.value)}
        />
        <button onClick={handleStartGame}>Start</button>
      </div>

      <hr />
      <h2>Finish Game</h2>
      <div>
        Cards Used:
        <input
          type="text"
          value={cardsUsed}
          onChange={(e) => setCardsUsed(e.target.value)}
        />
      </div>
      <div>
        SubDeckHash:
        <input
          type="text"
          value={subDeckHash}
          onChange={(e) => setSubDeckHash(e.target.value)}
        />
      </div>
      <div>
        <input
          type="checkbox"
          checked={playerWon}
          onChange={(e) => setPlayerWon(e.target.checked)}
        />
        <label> Player Won?</label>
      </div>
      <button onClick={handleFinishGame}>Finish</button>

      <hr />
      <h2>Admin VRF / Shoe</h2>
      <button onClick={handleRequestNewSeed}>Request New Random Seed</button>
      <div>
        Deck Commit:
        <input
          type="text"
          value={deckCommit}
          onChange={(e) => setDeckCommit(e.target.value)}
        />
      </div>
      <div>
        Deck Size:
        <input
          type="text"
          value={deckSize}
          onChange={(e) => setDeckSize(e.target.value)}
        />
      </div>
      <button onClick={handleCommitShoe}>Commit Shoe</button>
    </div>
  );
}
