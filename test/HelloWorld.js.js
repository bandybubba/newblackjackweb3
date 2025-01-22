// File: test/HelloWorld.js

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("HelloWorld contract", function () {
  it("Should deploy and return the initial message", async function () {
    // Get the ContractFactory
    const HelloWorld = await ethers.getContractFactory("HelloWorld");

    // Deploy the contract with an initial message
    const hello = await HelloWorld.deploy("Initial message");

    // FIX: In Ethers v6, use waitForDeployment() instead of .deployed()
    await hello.waitForDeployment();

    // Check the initial message (public variable "message" in your contract)
    expect(await hello.message()).to.equal("Initial message");

    // Update the message
    const tx = await hello.setMessage("New message");
    await tx.wait();

    // Check the new message
    expect(await hello.message()).to.equal("New message");
  });
});
