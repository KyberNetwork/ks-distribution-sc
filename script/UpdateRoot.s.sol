// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import '../src/KSDistributor.sol';
import './Base.s.sol';

contract UpdateRootScript is BaseDistributorScript {
  using stdJson for string;

  // @dev Update root for multiple campaigns on multiple chains

  // Usage:
  // # Update root for multiple campaigns using chainIds, campaignIds, and effectiveTimestamps
  // forge script UpdateRootScript \
  // --sig "run(string[],uint256)" \
  // "[1,42161,8453,56]" \
  // "1770969600" \
  //  --block-gas-limit 20000000000 --broadcast

  function run(string[] memory chainIds, uint256 effectiveTimestamp) public multiChain(chainIds) {
    require(effectiveTimestamp > block.timestamp, 'invalid effectiveTimestamp');

    _loadDistributor();
    bytes32[] memory campaignIds = _readUpdateRootData();

    for (uint256 i = 0; i < campaignIds.length; i++) {
      bytes32 campaignId = campaignIds[i];

      if (!_campaignExists(campaignId)) {
        console.log(
          'CampaignId: %s does not exist on chainId: %s, skipping...',
          vm.toString(campaignId),
          vm.toString(vm.getChainId())
        );
        continue;
      }

      bytes32 root = _readCampaignFile(campaignId).readBytes32('.root');
      _submitAndVerifyRoot(campaignId, root, effectiveTimestamp);
    }
  }
}
