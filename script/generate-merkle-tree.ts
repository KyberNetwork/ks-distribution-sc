import { SimpleMerkleTree } from "@openzeppelin/merkle-tree";
import { HexString } from "@openzeppelin/merkle-tree/dist/bytes";
import { keccak256 } from "@openzeppelin/merkle-tree/dist/hashes";
import { encode } from "@metamask/abi-utils";
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
  campaignId: string;
  startTimestamp: string;
  endTimestamp: string;
  metadata: string;
  salt: string;
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

// Get input file path from command line arguments, default to campaigns-data.json
const inputFilePath = process.argv[2] || "./script/input/campaigns-data.json";

// Check if file exists
if (!fs.existsSync(inputFilePath)) {
  console.error(`Error: Input file ${inputFilePath} does not exist`);
  process.exit(1);
}

// Read and parse the campaigns data
let campaignsData: Campaign[];
try {
  const fileContent = fs.readFileSync(inputFilePath, 'utf-8');
  const parsedData = JSON.parse(fileContent);
  campaignsData = parsedData.campaignsData || parsedData;
} catch (error) {
  console.error(`Error reading or parsing input file: ${error}`);
  process.exit(1);
}

campaignsData.forEach((campaign: Campaign) => {
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
      const normalizedToken = token.toLowerCase();
      if (totalAmounts[normalizedToken] === undefined) {
        totalAmounts[normalizedToken] = "0";
      }
      // Safely add using string manipulation to avoid BigNumber overflow
      const currentBN = BigNumber.from(totalAmounts[normalizedToken]);
      const amountBN = BigNumber.from(leaf.amounts[index]);
      totalAmounts[normalizedToken] = currentBN.add(amountBN).toString();
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
