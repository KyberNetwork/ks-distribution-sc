import { SimpleMerkleTree } from "@openzeppelin/merkle-tree";
import { HexString } from "@openzeppelin/merkle-tree/dist/bytes";
import { keccak256 } from "@openzeppelin/merkle-tree/dist/hashes";
import { encode } from "@metamask/abi-utils";
import { campaignsData } from "./input/campaigns-data.json";
import * as fs from "node:fs";
import { BigNumber } from "ethers";

interface Leaf {
  account?: string;
  erc721Addr?: string;
  erc721Id?: string;
  tokens: string[];
  amounts: string[];
  [key: string]: any;
}

interface Campaign {
  startTimestamp: string;
  endTimestamp: string;
  metadata: string;
  leaves: Leaf[];
}

function leafHash(campaignId: string, leaf: Leaf): HexString {
  let infoHash: HexString;
  if (leaf.account !== undefined) {
    const types = ["bytes32", "address"];
    const values = [campaignId, leaf.account];
    infoHash = keccak256(encode(types, values));
  } else {
    const types = ["bytes32", "address", "uint256"];
    const values = [campaignId, leaf.erc721Addr, leaf.erc721Id];
    infoHash = keccak256(encode(types, values));
  }
  const types = ["bytes32", "address[]", "uint256[]"];
  const values = [infoHash, leaf.tokens, leaf.amounts];
  return keccak256(keccak256(encode(types, values)));
}

campaignsData.forEach((campaign) => {
  let campaignIdBN = BigNumber.from(campaign.campaignId);
  let campaignId: string;
  if (campaignIdBN.isZero()) {
    campaignId = keccak256(
      encode(
        ["uint256", "uint256", "string", "bytes32"],
        [campaign.startTimestamp, campaign.endTimestamp, campaign.metadata, campaign.salt]
      )
    )
  } else {
    campaignId = campaignIdBN.toHexString();
  }
  console.log("Generating Merkle tree for campaign", campaignId);
  console.log("Number of leaves:", campaign.leaves.length);
  const leafHashes = campaign.leaves.map((leaf) => leafHash(campaignId, leaf));
  const tree = SimpleMerkleTree.of(leafHashes);
  let userDatas: { leaf: Leaf; proof: string[] }[] = [];
  let totalAmounts: { [key: string]: string } = {};
  campaign.leaves.forEach((leaf, index) => {
    const proof = tree.getProof(leafHashes[index]);
    userDatas.push({ leaf, proof });
    leaf.tokens.forEach((token, index) => {
      if (totalAmounts[token] === undefined) {
        totalAmounts[token] = "0";
      }
      // Safely add using string manipulation to avoid BigNumber overflow
      const currentBN = BigNumber.from(totalAmounts[token]);
      const amountBN = BigNumber.from(leaf.amounts[index]);
      totalAmounts[token] = currentBN.add(amountBN).toString();
    });
  });

  fs.writeFileSync(
    "script/output/campaign-" + campaignId + ".json",
    JSON.stringify(
      {
        startTimestamp: campaign.startTimestamp,
        endTimestamp: campaign.endTimestamp,
        metadata: campaign.metadata,
        salt: campaign.salt,
        userDatas,
        tree: tree.dump().tree,
        root: tree.root,
        totalAmounts,
      },
      null,
      2
    )
  );
});
