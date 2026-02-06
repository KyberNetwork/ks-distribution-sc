// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import '../src/KSDistributor.sol';
import './Base.s.sol';

contract UpdateRootScript is BaseDistributorScript {
  using stdJson for string;

  KSDistributor distributor;

  // @dev Update root for multiple campaigns on multiple chains

  // Usage:
  // # Update root for multiple campaigns using chainIds, campaignIds, and effectiveTimestamps
  // forge script UpdateRootScript \
  // --sig "run(string[],uint256)" \
  // "[1,8453]" \
  // "1770204199" \
  //  --broadcast

  function run(string[] memory chainIds, uint256 effectiveTimestamp) public multiChain(chainIds) {
    require(effectiveTimestamp > block.timestamp, 'invalid effectiveTimestamp');

    distributor = KSDistributor(payable(distributorOf[vm.getChainId()]));
    bytes32[] memory campaignIds = _readUpdateRootData();

    for (uint256 i = 0; i < campaignIds.length; i++) {
      bytes32 campaignId = campaignIds[i];
      (uint256 startTimestamp,,) = IKSDistributor(distributor).campaigns(campaignId);

      //this means the campaign exists on this chain, start updating
      if (startTimestamp != 0) {
        string memory filePath =
          string.concat('script/output/campaign-', vm.toString(campaignId), '.json');
        string memory jsonString = vm.readFile(filePath);
        bytes32 root = jsonString.readBytes32('.root');

        require(root != bytes32(0), 'root is empty');

        // this for test runs only
        // vm.stopBroadcast();
        // vm.startBroadcast(operatorsOf[vm.getChainId()][0]);

        _updateRoot(campaignId, root, effectiveTimestamp);
        _verifyRoot(campaignId, root, effectiveTimestamp);
      } else {
        console.log(
          'CampaignId: %s does not exist on chainId: %s, skipping...',
          vm.toString(campaignId),
          vm.toString(vm.getChainId())
        );
      }
    }
  }

  function _updateRoot(bytes32 campaignId, bytes32 root, uint256 effectiveTimestamp) internal {
    console.log(
      'Updating campaignId: %s on chainId: %s',
      vm.toString(campaignId),
      vm.toString(vm.getChainId())
    );
    console.log('Root:', vm.toString(root));
    console.log('effectiveTimestamp:', effectiveTimestamp);

    KSDistributor(distributor).submitRoot(campaignId, root, effectiveTimestamp);

    console.log('Root updated successfully');
  }

  function _verifyRoot(bytes32 campaignId, bytes32 root, uint256 effectiveTimestamp) internal {
    (bytes32 newRoot, uint256 newEffectiveTimestamp) =
      IKSDistributor(distributor).pendingRoots(campaignId);

    require(newRoot == root, 'root mismatch');
    require(newEffectiveTimestamp == effectiveTimestamp, 'effectiveTimestamp mismatch');

    console.log('Root verified successfully');
  }
}
