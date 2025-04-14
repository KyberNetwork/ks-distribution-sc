// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import '../src/KSDistributor.sol';
import './Base.s.sol';

contract CreateCampaignScript is BaseScript {
  uint256 startTimestamp = 0;
  uint256 endTimestamp = 0;
  string metadata = 'test';
  bytes32 salt = bytes32(0);

  bytes32 expectedCampaignId = bytes32(0);
  bytes32 root = bytes32(0);

  function run() external {
    require(startTimestamp != 0 && endTimestamp != 0, 'Start and end timestamps must be set');
    require(root != bytes32(0), 'Root must be set');

    uint256 chainId;
    assembly {
      chainId := chainid()
    }

    address distributor = _readAddress('script/deployedAddresses/distributor.json', chainId);

    vm.startBroadcast();
    bytes32 campaignId =
      KSDistributor(distributor).createCampaign(startTimestamp, endTimestamp, metadata, salt);
    console.log('Campaign %s created with:', vm.toString(campaignId));
    require(campaignId == expectedCampaignId, 'Campaign ID does not match the expected value');

    KSDistributor(distributor).updateRoot(campaignId, root);
    vm.stopBroadcast();

    console.log('Start timestamp:', startTimestamp);
    console.log('End timestamp:', endTimestamp);
    console.log('Metadata:', metadata);
  }
}
