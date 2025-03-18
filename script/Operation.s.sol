// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './Base.s.sol';

contract OperationScript is BaseScript {
  function createCampaign(uint256 startTimestamp, uint256 endTimestamp, string calldata metadata)
    public
  {
    vm.startBroadcast();
    IKSDistributor distributor = _getDistributor();
    bytes32 campaignId = distributor.createCampaign(startTimestamp, endTimestamp, metadata);
    console.log('Campaign %s created with:', vm.toString(campaignId));
    console.log('Start timestamp:', startTimestamp);
    console.log('End timestamp:', endTimestamp);
    console.log('Metadata:', metadata);
  }

  function updateRoot(bytes32 campaignId, bytes32 root) public {
    vm.startBroadcast();
    IKSDistributor distributor = _getDistributor();
    distributor.updateRoot(campaignId, root);
    console.log('Root of campaign %s is updated to %s', vm.toString(campaignId), vm.toString(root));
  }
}
