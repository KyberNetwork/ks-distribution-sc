import { BigNumber, ethers } from "ethers";
import * as fs from "node:fs";

interface Leaf {
  account?: string;
  erc721Addr?: string;
  erc721Id?: string;
  tokens: string[];
  amounts: string[];
}

interface UserData {
  leaf: Leaf;
  proof: string[];
}

interface CampaignData {
  startTimestamp: string;
  endTimestamp: string;
  metadata: string;
  salt: string;
  userDatas: UserData[];
  tree: string[];
  root: string;
  totalAmounts: { [token: string]: string };
}

function getPositionIdentifier(leaf: Leaf): string {
  if (leaf.account) {
    return `account:${leaf.account.toLowerCase()}`;
  } else {
    return `erc721:${leaf.erc721Addr?.toLowerCase()}:${leaf.erc721Id}`;
  }
}

function createPositionMap(userDatas: UserData[]): Map<string, Leaf> {
  const map = new Map<string, Leaf>();
  for (const userData of userDatas) {
    const identifier = getPositionIdentifier(userData.leaf);
    map.set(identifier, userData.leaf);
  }
  return map;
}

function formatAmount(amount: string): string {
  return amount;
}

// Try raw call approach since ABI decoding is failing
const getPoolAndPositionInfoSelector = "0x7ba03aad"; // getPoolAndPositionInfo(uint256)

// Global cache for position info to avoid duplicate RPC calls
const positionCache = new Map<string, { currency0: string; currency1: string; fee: number } | null>();

async function getPoolDistribution(campaign: CampaignData, rpcUrl: string): Promise<{ [poolKey: string]: { [token: string]: string } }> {
  const poolDistribution: { [poolKey: string]: { [token: string]: string } } = {};

  // Create single provider instance
  const provider = new ethers.providers.JsonRpcProvider(rpcUrl);

  // Group positions by manager and collect unique calls needed
  const positionCalls: Array<{
    managerAddr: string;
    tokenId: string;
    userData: UserData;
    cacheKey: string;
  }> = [];

  for (const userData of campaign.userDatas) {
    const leaf = userData.leaf;

    // Only process ERC721 positions
    if (leaf.erc721Addr && leaf.erc721Id) {
      const cacheKey = `${leaf.erc721Addr}:${leaf.erc721Id}`;
      positionCalls.push({
        managerAddr: leaf.erc721Addr,
        tokenId: leaf.erc721Id,
        userData,
        cacheKey
      });
    }
  }

  // Batch size for concurrent calls
  const BATCH_SIZE = 25;
  const batches: typeof positionCalls[] = [];

  for (let i = 0; i < positionCalls.length; i += BATCH_SIZE) {
    batches.push(positionCalls.slice(i, i + BATCH_SIZE));
  }

  console.log(`Processing ${positionCalls.length} positions in ${batches.length} batches...`);

  // Process batches concurrently
  for (let batchIndex = 0; batchIndex < batches.length; batchIndex++) {
    const batch = batches[batchIndex];

    const batchPromises = batch.map(async (call) => {
      // Check cache first
      if (positionCache.has(call.cacheKey)) {
        const cached = positionCache.get(call.cacheKey);
        return { call, poolInfo: cached };
      }

      try {
        // Make raw call to getPoolAndPositionInfo
        const callData = getPoolAndPositionInfoSelector + BigNumber.from(call.tokenId).toHexString().slice(2).padStart(64, '0');
        const result = await provider.call({
          to: call.managerAddr,
          data: callData
        });

        // Decode the return data manually
        if (result.length >= 322) {
          const currency0 = "0x" + result.slice(26, 66);
          const currency1 = "0x" + result.slice(90, 130);
          const fee = parseInt(result.slice(130, 194), 16);

          const poolInfo = { currency0, currency1, fee };
          positionCache.set(call.cacheKey, poolInfo);
          return { call, poolInfo };
        } else {
          positionCache.set(call.cacheKey, null);
          return { call, poolInfo: null };
        }
      } catch (error) {
        console.error(`Error getting pool info for tokenId ${call.tokenId}: ${error.message}`);
        positionCache.set(call.cacheKey, null);
        return { call, poolInfo: null };
      }
    });

    const batchResults = await Promise.all(batchPromises);

    // Process results
    for (const { call, poolInfo } of batchResults) {
      if (poolInfo) {
        const poolKeyString = `${poolInfo.currency0.toLowerCase()}-${poolInfo.currency1.toLowerCase()}-${poolInfo.fee}`;

        if (!poolDistribution[poolKeyString]) {
          poolDistribution[poolKeyString] = {};
        }

        // Add token amounts to this pool
        const leaf = call.userData.leaf;
        for (let i = 0; i < leaf.tokens.length; i++) {
          const token = leaf.tokens[i].toLowerCase();
          const amount = leaf.amounts[i];

          if (!poolDistribution[poolKeyString][token]) {
            poolDistribution[poolKeyString][token] = "0";
          }

          const currentAmount = BigNumber.from(poolDistribution[poolKeyString][token]);
          const addAmount = BigNumber.from(amount);
          poolDistribution[poolKeyString][token] = currentAmount.add(addAmount).toString();
        }
      }
    }

    console.log(`Completed batch ${batchIndex + 1}/${batches.length}`);
  }

  return poolDistribution;
}


function comparePoolDistributions(
  oldDistribution: { [poolKey: string]: { [token: string]: string } },
  newDistribution: { [poolKey: string]: { [token: string]: string } }
) {
  console.log("🏊 POOL DISTRIBUTION COMPARISON");
  console.log("-".repeat(40));

  const allPools = new Set([...Object.keys(oldDistribution), ...Object.keys(newDistribution)]);
  const allPoolsArray = Array.from(allPools);

  if (allPoolsArray.length === 0) {
    console.log("No pool distributions to compare.");
    return;
  }

  let poolsWithChanges = 0;

  for (let i = 0; i < allPoolsArray.length; i++) {
    const poolKey = allPoolsArray[i];
    const oldPool = oldDistribution[poolKey] || {};
    const newPool = newDistribution[poolKey] || {};

    const allTokens = new Set([...Object.keys(oldPool), ...Object.keys(newPool)]);
    const allTokensArray = Array.from(allTokens);

    let poolHasChanges = false;
    let poolChangeDetails: string[] = [];

    for (let j = 0; j < allTokensArray.length; j++) {
      const token = allTokensArray[j];
      const oldAmount = BigNumber.from(oldPool[token] || "0");
      const newAmount = BigNumber.from(newPool[token] || "0");
      const change = newAmount.sub(oldAmount);

      if (!change.isZero()) {
        poolHasChanges = true;
        let status = "➖";
        if (change.gt(0)) status = "✅";
        else if (change.lt(0)) status = "❌";

        poolChangeDetails.push(`    ${status} ${token}: ${formatAmount(oldAmount.toString())} → ${formatAmount(newAmount.toString())} (${formatAmount(change.toString())})`);
      }
    }

    if (poolHasChanges) {
      poolsWithChanges++;
      console.log(`Pool: ${poolKey}`);
      for (const detail of poolChangeDetails) {
        console.log(detail);
      }
      console.log();
    }
  }

  if (poolsWithChanges === 0) {
    console.log("No changes in pool distributions.");
  } else {
    console.log(`Summary: ${poolsWithChanges} pools with distribution changes.`);
  }
  console.log();
}

function compareCampaigns(oldCampaignPath: string, newCampaignPath: string) {
  const newCampaign: CampaignData = JSON.parse(fs.readFileSync(newCampaignPath, 'utf8'));

  // Check if this is single campaign mode (empty old campaign path)
  const isSingleMode = !oldCampaignPath || oldCampaignPath === '';

  let oldCampaign: CampaignData | null = null;
  let oldPositions: Map<string, Leaf> | null = null;

  if (!isSingleMode) {
    oldCampaign = JSON.parse(fs.readFileSync(oldCampaignPath, 'utf8'));
    oldPositions = createPositionMap(oldCampaign.userDatas);
  }

  const newPositionsMap = createPositionMap(newCampaign.userDatas);

  console.log("=".repeat(80));
  console.log(isSingleMode ? "CAMPAIGN REPORT" : "CAMPAIGN COMPARISON REPORT");
  console.log("=".repeat(80));
  if (!isSingleMode) {
    console.log(`Old Campaign: ${oldCampaignPath}`);
  }
  console.log(`${isSingleMode ? "Campaign" : "New Campaign"}: ${newCampaignPath}`);
  console.log();

  // Check total token amounts
  console.log(`💰 TOTAL TOKEN ${isSingleMode ? "AMOUNTS" : "CHANGES"}`);
  console.log("-".repeat(40));
  let allTokensNonDecreased = true;

  // Helper function to aggregate amounts by lowercase token address
  const aggregateTokenAmounts = (totalAmounts: { [token: string]: string }): { [token: string]: string } => {
    const aggregated: { [token: string]: string } = {};
    for (const [token, amount] of Object.entries(totalAmounts)) {
      const lowercaseToken = token.toLowerCase();
      if (!aggregated[lowercaseToken]) {
        aggregated[lowercaseToken] = "0";
      }
      aggregated[lowercaseToken] = BigNumber.from(aggregated[lowercaseToken]).add(BigNumber.from(amount)).toString();
    }
    return aggregated;
  };

  const newTotalAmounts = aggregateTokenAmounts(newCampaign.totalAmounts);
  const oldTotalAmounts = isSingleMode ? {} : aggregateTokenAmounts(oldCampaign!.totalAmounts);

  const allTokens = isSingleMode
    ? Object.keys(newTotalAmounts)
    : Array.from(new Set([...Object.keys(oldTotalAmounts), ...Object.keys(newTotalAmounts)]));

  for (let i = 0; i < allTokens.length; i++) {
    const token = allTokens[i];
    const oldTotal = isSingleMode ? BigNumber.from("0") : BigNumber.from(oldTotalAmounts[token] || "0");
    const newTotal = BigNumber.from(newTotalAmounts[token] || "0");
    const change = newTotal.sub(oldTotal);

    if (isSingleMode) {
      console.log(`Token: ${token}`);
      console.log(`   Amount: ${formatAmount(newTotal.toString())}`);
      console.log();
    } else {
      let status = "➖";
      if (change.gt(0)) status = "✅";
      else if (change.lt(0)) {
        status = "❌";
        allTokensNonDecreased = false;
      }

      console.log(`${status} Token: ${token}`);
      console.log(`   Old: ${formatAmount(oldTotal.toString())}`);
      console.log(`   New: ${formatAmount(newTotal.toString())}`);
      console.log(`   Change: ${formatAmount(change.toString())}`);
      console.log();
    }
  }

  let allPositionsNonDecreased = true;
  let newPositions = 0;
  let updatedPositions = 0;
  let unchangedPositions = 0;
  let removedPositions = 0;
  let decreasedPositions = 0;

  if (isSingleMode) {
    console.log("📈 POSITION SUMMARY");
    console.log("-".repeat(40));
    console.log(`Total Positions: ${newCampaign.userDatas.length}`);
    console.log();
  } else {
    // Check positions
    console.log("📈 POSITION CHANGES");
    console.log("-".repeat(40));

    const allPositionKeys = Array.from(new Set([...Array.from(oldPositions!.keys()), ...Array.from(newPositionsMap.keys())]));

    for (let i = 0; i < allPositionKeys.length; i++) {
      const identifier = allPositionKeys[i];
      const oldLeaf = oldPositions!.get(identifier);
      const newLeaf = newPositionsMap.get(identifier);

      if (!newLeaf) {
        // Position removed
        removedPositions++;
        allPositionsNonDecreased = false;
        console.log(`❌ REMOVED: ${identifier}`);
        continue;
      }

      if (!oldLeaf) {
        // New position
        newPositions++;
        continue;
      }

      // Compare existing position
      let positionDecreased = false;
      let positionChanged = false;

      const oldTokenMap: { [token: string]: string } = {};
      const newTokenMap: { [token: string]: string } = {};

      for (let i = 0; i < oldLeaf.tokens.length; i++) {
        oldTokenMap[oldLeaf.tokens[i].toLowerCase()] = oldLeaf.amounts[i];
      }

      for (let i = 0; i < newLeaf.tokens.length; i++) {
        newTokenMap[newLeaf.tokens[i].toLowerCase()] = newLeaf.amounts[i];
      }

      const positionTokens = Array.from(new Set([...oldLeaf.tokens.map(t => t.toLowerCase()), ...newLeaf.tokens.map(t => t.toLowerCase())]));

      for (let j = 0; j < positionTokens.length; j++) {
        const token = positionTokens[j];
        const oldAmount = BigNumber.from(oldTokenMap[token] || "0");
        const newAmount = BigNumber.from(newTokenMap[token] || "0");
        const change = newAmount.sub(oldAmount);

        if (!change.isZero()) {
          positionChanged = true;
        }

        if (change.lt(0)) {
          if (!positionDecreased) {
            console.log(`❌ DECREASED: ${identifier}`);
            positionDecreased = true;
            decreasedPositions++;
            allPositionsNonDecreased = false;
          }
          console.log(`   ${token}: ${formatAmount(oldAmount.toString())} → ${formatAmount(newAmount.toString())}`);
        }
      }

      if (positionChanged) {
        updatedPositions++;
      } else {
        unchangedPositions++;
      }
    }

    if (removedPositions === 0 && decreasedPositions === 0) {
      console.log("No positions removed or decreased.");
    }
    console.log();
  }

  // Summary
  console.log("📊 SUMMARY");
  console.log("-".repeat(40));

  if (isSingleMode) {
    console.log(`Total Positions: ${newCampaign.userDatas.length}`);
  } else {
    console.log(`Total Positions: ${oldCampaign!.userDatas.length} → ${newCampaign.userDatas.length}`);
    console.log(`New Positions: ${newPositions}`);
    console.log(`Updated Positions: ${updatedPositions}`);
    console.log(`Unchanged Positions: ${unchangedPositions}`);
    console.log(`Removed Positions: ${removedPositions}`);
    console.log(`Positions with Decreases: ${decreasedPositions}`);
    console.log(`All Positions Non-Decreased: ${allPositionsNonDecreased ? "✅ YES" : "❌ NO"}`);
    console.log(`All Tokens Non-Decreased: ${allTokensNonDecreased ? "✅ YES" : "❌ NO"}`);
  }
  console.log("=".repeat(80));
}

async function main() {
  const args = process.argv.slice(2);

  if (args.length < 1 || args.length > 3) {
    console.error("Usage: yarn ts-node script/compare-campaigns.ts <new-campaign-path> [rpc-url]");
    console.error("   OR: yarn ts-node script/compare-campaigns.ts <old-campaign-path> <new-campaign-path> [rpc-url]");
    console.error("Example (single mode): yarn ts-node script/compare-campaigns.ts script/output/250701/campaign-0x0b1d1d.json");
    console.error("Example (compare mode): yarn ts-node script/compare-campaigns.ts script/output/250618/campaign-0x0b1d1d.json script/output/250701/campaign-0x0b1d1d.json");
    console.error("With pool report: yarn ts-node script/compare-campaigns.ts script/output/250618/campaign-0x0b1d1d.json script/output/250701/campaign-0x0b1d1d.json https://rpc.url");
    process.exit(1);
  }

  let oldCampaignPath: string;
  let newCampaignPath: string;
  let rpcUrl: string | undefined;

  if (args.length === 1) {
    // Single campaign mode
    oldCampaignPath = '';
    newCampaignPath = args[0];
    rpcUrl = undefined;
  } else if (args.length === 2) {
    // Check if second arg is RPC URL (starts with http) or campaign path
    if (args[1].startsWith('http')) {
      // Single campaign mode with RPC URL
      oldCampaignPath = '';
      newCampaignPath = args[0];
      rpcUrl = args[1];
    } else {
      // Compare mode without RPC URL
      oldCampaignPath = args[0];
      newCampaignPath = args[1];
      rpcUrl = undefined;
    }
  } else {
    // Compare mode with RPC URL
    oldCampaignPath = args[0];
    newCampaignPath = args[1];
    rpcUrl = args[2];
  }

  // Validate files
  if (oldCampaignPath && !fs.existsSync(oldCampaignPath)) {
    console.error(`Error: Old campaign file not found: ${oldCampaignPath}`);
    process.exit(1);
  }

  if (!fs.existsSync(newCampaignPath)) {
    console.error(`Error: New campaign file not found: ${newCampaignPath}`);
    process.exit(1);
  }

  try {
    compareCampaigns(oldCampaignPath, newCampaignPath);

    // If RPC URL is provided, generate pool distribution reports and comparison
    if (rpcUrl) {
      const newCampaign: CampaignData = JSON.parse(fs.readFileSync(newCampaignPath, 'utf8'));

      console.log("\n");

      if (oldCampaignPath) {
        const oldCampaign: CampaignData = JSON.parse(fs.readFileSync(oldCampaignPath, 'utf8'));
        const oldPoolDistribution = await getPoolDistribution(oldCampaign, rpcUrl);
        const newPoolDistribution = await getPoolDistribution(newCampaign, rpcUrl);

        // Compare pool distributions
        comparePoolDistributions(oldPoolDistribution, newPoolDistribution);
      } else {
        // Single campaign mode - just show pool distribution
        const newPoolDistribution = await getPoolDistribution(newCampaign, rpcUrl);
        console.log("🏊 POOL DISTRIBUTION REPORT");
        console.log("-".repeat(40));

        for (const [poolKey, tokens] of Object.entries(newPoolDistribution)) {
          console.log(`Pool: ${poolKey}`);
          for (const [token, amount] of Object.entries(tokens)) {
            console.log(`    ${token}: ${formatAmount(amount)}`);
          }
          console.log();
        }
      }
    }
  } catch (error) {
    console.error("Error comparing campaigns:", error);
    process.exit(1);
  }
}

if (require.main === module) {
  main();
}