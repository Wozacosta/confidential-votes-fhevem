import { expect } from "chai";
import { ethers } from "hardhat";

import { createInstances } from "../instance";
import { getSigners, initSigners } from "../signers";
import { deployEncryptedRevoteFixture } from "./ConfidentialRevote.fixture";

describe("ConfidentialERC20", function () {
  before(async function () {
    await initSigners();
    this.signers = await getSigners();
  });

  beforeEach(async function () {
    const contract = await deployEncryptedRevoteFixture();
    this.contractAddress = await contract.getAddress();
    this.revote = contract;
    this.instances = await createInstances(this.contractAddress, ethers, this.signers);
  });

  it("should create a poll", async function () {
    // ALICE CREATES A POLL
    let polls = await this.revote.getPollsByCreator(this.signers.alice);
    expect(polls.length).to.equal(0);
    const minimumFee = await this.revote.pollCreationFee(); // 5000000000000000n
    console.log({ minimumFee });
    const transaction = await this.revote.createPoll(
      "what's the best layer2?",
      ["arbitrum", "optimism", "starknet"],
      // 60,
      { value: minimumFee },
    );
    await transaction.wait();
    // Call the method
    const token = this.instances.alice.getPublicKey(this.contractAddress) || {
      signature: "",
      publicKey: "",
    };
    polls = await this.revote.getPollsByCreator(this.signers.alice);
    console.log({ polls });
    expect(polls.length).to.equal(1);
    expect(polls[0]).to.equal(0);

    const allPolls = await this.revote.getPolls();
    console.log({ allPolls });

    const POLL_ID = 0;
    const pollById = await this.revote.getPollById(POLL_ID);
    console.log({ pollById });
    const OPTIONS = pollById[1]; //  [ 'arbitrum', 'optimism', 'starknet' ]
    const OPTION_ARBITRUM = 0;
    const OPTION_OPTIMISM = 1;
    const OPTION_STARKNET = 2;

    console.log("BOB VOTES ARBITRUM")
    
    const tokenBob = this.instances.bob.getPublicKey(this.contractAddress)!;
    // let votesByBob = await this.revote.connect(this.signers.bob).getPollIdsVotedOn();
    // expect(votesByBob.length).to.equal(0);

    // const bobErc20 = this.erc20.connect(this.signers.bob);
    console.log("BEFORE VOTE!")


    const encryptedVoteFromBobForArbitrum = this.instances.bob.encrypt8(OPTION_ARBITRUM);
    const transactionVote = await this.revote.connect(this.signers.bob).vote(POLL_ID, encryptedVoteFromBobForArbitrum);
    await transactionVote.wait();
    console.log("AFTER VOTE!")
    // const encryptedVoteFromAliceForArbitrum = this.instances.alice.encrypt32(OPTION_ARBITRUM);
    // const countArbitrum = await this.revote.getVoteCountByPollAndOption(POLL_ID, encryptedVoteFromAliceForArbitrum);
    // console.log({ countArbitrum });

    const results = await this.revote.connect(this.signers.bob).getResults(POLL_ID, tokenBob.publicKey); 
    console.log("---------ENCRYPTED VIEW------------")
    console.log({results})

    console.log("---------DECRYPTED VIEW------------")
    for (var i = 0; i < results.length; i++) {
      // console.log(`Option ${i} result, bob pov: `, this.instances.alice.decrypt(this.contractAddress, results[i]));
      // NOTE: ^ using alice instance here would break with "Error: incorrect key pair for the given ciphertext"
      console.log(`Option ${i} result, bob pov: `, this.instances.bob.decrypt(this.contractAddress, results[i]));
    }
    /*
    const countArbitrumBob = await this.revote.connect(this.signers.bob).getVoteCountByPollAndOption(POLL_ID, encryptedVoteFromBobForArbitrum);
    console.log({ countArbitrumBob });
    
    console.log("BEFORE POLLIDSVOTEDON")
     votesByBob = await this.revote.connect(this.signers.bob).getPollIdsVotedOn(this.signers.bob);
    console.log({votesByBob})
    expect(votesByBob.length).to.equal(1);

    expect(countArbitrumBob).to.equal(1);
    // const voteCounts1 = await this.revote.voteCounts[POLL_ID];
    // const bobVote = await this.revote.votes[POLL_ID][this.signers.bob.address];
    // console.log({ voteCounts1, bobVote });

    console.log("BOB CANNOT VOTE TWICE FOR SAME POLL")

    // const transactionVote2 = await
    try {
      await this.revote.connect(this.signers.bob).vote(POLL_ID, encryptedVoteFromBobForArbitrum);
      // NOTE: cant use proper chai matchers for revertions..
      // await expect(this.revote.connect(this.signers.bob).vote(POLL_ID, OPTION_ARBITRUM)).to.be.reverted;
    } catch (err) {
      expect(err.toString()).to.include("Double voting is not allowed");
    }

    console.log("CAROL VOTES STARKNET")
    const encryptedVoteFromCarolForStarknet = this.instances.carol.encrypt32(OPTION_STARKNET);
    const transactionVoteCarol = await this.revote.connect(this.signers.carol).vote(POLL_ID, encryptedVoteFromCarolForStarknet);
    await transactionVoteCarol.wait();

    let countStarknet = await this.revote.getVoteCountByPollAndOption(POLL_ID, encryptedVoteFromCarolForStarknet);
    console.log({ countStarknet });
    expect(countStarknet).to.equal(1);

    console.log("DAVE VOTES STARKNET")
    const encryptedVoteFromDaveForStarknet = this.instances.carol.encrypt32(OPTION_STARKNET);
    const transactionVoteDave = await this.revote.connect(this.signers.dave).vote(POLL_ID, encryptedVoteFromDaveForStarknet);
    await transactionVoteDave.wait();

    countStarknet = await this.revote.getVoteCountByPollAndOption(POLL_ID, encryptedVoteFromDaveForStarknet);
    console.log({ countStarknet });
    expect(countStarknet).to.equal(2);
    // BOB CHECKS WHAT HE VOTED
    // 
    const bobChecksBob = await this.revote.connect(this.signers.bob).getVoteByPollAndVoter(POLL_ID, this.signers.bob.address)
    console.log({bobChecksBob}) // [ 0n, 0n, true ]

    const bobChecksDave = await this.revote.connect(this.signers.bob).getVoteByPollAndVoter(POLL_ID, this.signers.dave.address)
    console.log({bobChecksDave}) // [ 0n, 2n, true ]

    */
    // CAROL TRIES TO CHECK WHAT BOB VOTED

    // BOB CHECKS OVERALL RESULTS BEFORE VOTE FINISHES

    // CAROL CHECKS OVERALL RESULTS BEFORE VOTE FINISHES

    // ALICE FINISHES VOTE

    // ALICE CHECKS RESULTS BEFORE VOTE FINISHES

    // BOB CHECKS WHAT HE VOTED

    // CAROL TRIES TO CHECK WHAT BOB VOTED

    // BOB CHECKS OVERALL RESULTS BEFORE VOTE FINISHES

    // CAROL CHECKS OVERALL RESULTS BEFORE VOTE FINISHES

    // const encryptedBalance = await this.erc20.balanceOf(this.signers.alice, token.publicKey, token.signature);
    // // Decrypt the balance
    // const balance = this.instances.alice.decrypt(this.contractAddress, encryptedBalance);
    // expect(balance).to.equal(1000);

    // const totalSupply = await this.erc20.totalSupply();
    // // Decrypt the total supply
    // expect(totalSupply).to.equal(1000);
  });
  it.skip("should fetch polls", async function () {
    // const polls = await this.revote.getPollsByCreator(this.signers.alice);
    console.log({ polls2: polls });
  });

  it.skip("should transfer tokens between two users", async function () {
    const transaction = await this.erc20.mint(10000);
    await transaction.wait();

    const encryptedTransferAmount = this.instances.alice.encrypt32(1337);
    const tx = await this.erc20["transfer(address,bytes)"](this.signers.bob.address, encryptedTransferAmount);
    await tx.wait();

    const tokenAlice = this.instances.alice.getPublicKey(this.contractAddress)!;

    const encryptedBalanceAlice = await this.erc20.balanceOf(
      this.signers.alice,
      tokenAlice.publicKey,
      tokenAlice.signature,
    );

    // Decrypt the balance
    const balanceAlice = this.instances.alice.decrypt(this.contractAddress, encryptedBalanceAlice);

    expect(balanceAlice).to.equal(10000 - 1337);

    const bobErc20 = this.erc20.connect(this.signers.bob);

    const tokenBob = this.instances.bob.getPublicKey(this.contractAddress)!;

    const encryptedBalanceBob = await bobErc20.balanceOf(this.signers.bob, tokenBob.publicKey, tokenBob.signature);

    // Decrypt the balance
    const balanceBob = this.instances.bob.decrypt(this.contractAddress, encryptedBalanceBob);

    expect(balanceBob).to.equal(1337);
  });

  it.skip("should not transfer tokens between two users", async function () {
    const transaction = await this.erc20.mint(1000);
    await transaction.wait();

    const encryptedTransferAmount = this.instances.alice.encrypt32(1337);
    const tx = await this.erc20["transfer(address,bytes)"](this.signers.bob.address, encryptedTransferAmount);
    await tx.wait();

    const tokenAlice = this.instances.alice.getPublicKey(this.contractAddress)!;

    const encryptedBalanceAlice = await this.erc20.balanceOf(
      this.signers.alice,
      tokenAlice.publicKey,
      tokenAlice.signature,
    );

    // Decrypt the balance
    const balanceAlice = this.instances.alice.decrypt(this.contractAddress, encryptedBalanceAlice);

    expect(balanceAlice).to.equal(1000);

    const bobErc20 = this.erc20.connect(this.signers.bob);

    const tokenBob = this.instances.bob.getPublicKey(this.contractAddress)!;

    const encryptedBalanceBob = await bobErc20.balanceOf(this.signers.bob, tokenBob.publicKey, tokenBob.signature);

    // Decrypt the balance
    const balanceBob = this.instances.bob.decrypt(this.contractAddress, encryptedBalanceBob);

    expect(balanceBob).to.equal(0);
  });

  it.skip("should be able to transferFrom only if allowance is sufficient", async function () {
    const transaction = await this.erc20.mint(10000);
    await transaction.wait();

    const encryptedAllowanceAmount = this.instances.alice.encrypt32(1337);
    const tx = await this.erc20["approve(address,bytes)"](this.signers.bob.address, encryptedAllowanceAmount);
    await tx.wait();

    const bobErc20 = this.erc20.connect(this.signers.bob);
    const encryptedTransferAmount = this.instances.bob.encrypt32(1338); // above allowance so next tx should actually not send any token
    const tx2 = await bobErc20["transferFrom(address,address,bytes)"](
      this.signers.alice.address,
      this.signers.bob.address,
      encryptedTransferAmount,
    );
    await tx2.wait();

    const tokenAlice = this.instances.alice.getPublicKey(this.contractAddress)!;
    const encryptedBalanceAlice = await this.erc20.balanceOf(
      this.signers.alice,
      tokenAlice.publicKey,
      tokenAlice.signature,
    );

    // Decrypt the balance
    const balanceAlice = this.instances.alice.decrypt(this.contractAddress, encryptedBalanceAlice);
    expect(balanceAlice).to.equal(10000); // check that transfer did not happen, as expected

    const tokenBob = this.instances.bob.getPublicKey(this.contractAddress)!;
    const encryptedBalanceBob = await bobErc20.balanceOf(this.signers.bob, tokenBob.publicKey, tokenBob.signature);
    // Decrypt the balance
    const balanceBob = this.instances.bob.decrypt(this.contractAddress, encryptedBalanceBob);
    expect(balanceBob).to.equal(0); // check that transfer did not happen, as expected

    const encryptedTransferAmount2 = this.instances.bob.encrypt32(1337); // below allowance so next tx should send token
    const tx3 = await bobErc20["transferFrom(address,address,bytes)"](
      this.signers.alice.address,
      this.signers.bob.address,
      encryptedTransferAmount2,
    );
    await tx3.wait();

    const encryptedBalanceAlice2 = await this.erc20.balanceOf(
      this.signers.alice,
      tokenAlice.publicKey,
      tokenAlice.signature,
    );
    // Decrypt the balance
    const balanceAlice2 = this.instances.alice.decrypt(this.contractAddress, encryptedBalanceAlice2);
    expect(balanceAlice2).to.equal(10000 - 1337); // check that transfer did happen this time

    const encryptedBalanceBob2 = await bobErc20.balanceOf(this.signers.bob, tokenBob.publicKey, tokenBob.signature);
    const balanceBob2 = this.instances.bob.decrypt(this.contractAddress, encryptedBalanceBob2);
    expect(balanceBob2).to.equal(1337); // check that transfer did happen this time
  });
});
