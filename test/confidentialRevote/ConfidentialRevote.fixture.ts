import { ethers } from "hardhat";

import type { ConfidentialRevote } from "../../types";
import { getSigners } from "../signers";

export async function deployEncryptedRevoteFixture(): Promise<ConfidentialRevote> {
  const signers = await getSigners();

  const contractFactory = await ethers.getContractFactory("ConfidentialRevote");
  const contract = await contractFactory.connect(signers.alice).deploy();
  await contract.waitForDeployment();

  return contract;
}
