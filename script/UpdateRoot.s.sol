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
  // --sig "run(string[],bytes32[],uint256[])" \
  // "[1,8453,8453]" \
  // "[0x4620df13f805b0f4948a11733c325a2befb35115bb121a359f5ecdaa111bfc4c,0x6b0c58c3c5d752b7ebba28c104e012c932fcc21683efa3b1559b4c76f1d2e0a3,0x9385788dc841a66c2845a4b1384c116519aef01e25433e7930ee5aec2edac6ba]" \
  // "[1770204199,1770204199,1770204199]" \
  //  --broadcast

  function run(
    string[] memory chainIds,
    bytes32[] memory campaignIds,
    uint256[] memory effectiveTimestamps
  ) public multiChain(chainIds) {
    require(
      chainIds.length == campaignIds.length && campaignIds.length == effectiveTimestamps.length,
      'length mismatch'
    );

    distributor = KSDistributor(payable(distributorOf[vm.getChainId()]));

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

        _updateRoot(campaignId, root, effectiveTimestamps[i]);
        _verifyRoot(campaignId, root, effectiveTimestamps[i]);
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
