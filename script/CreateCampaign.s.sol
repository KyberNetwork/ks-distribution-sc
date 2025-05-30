// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import '../src/KSDistributor.sol';
import './Base.s.sol';

contract CreateCampaignScript is BaseScript {
  using stdJson for string;

  bytes32 expectedCampaignId = bytes32(0);
  uint256 effectiveTimestamp = 0;

  function run() external {
    require(expectedCampaignId != bytes32(0), 'expectedCampaignId must be set to a non-zero value');

    uint256 chainId;
    assembly {
      chainId := chainid()
    }

    string memory filePath =
      string.concat('script/output/campaign-', vm.toString(expectedCampaignId), '.json');
    string memory jsonString = vm.readFile(filePath);

    uint256 startTimestamp = jsonString.readUint('.startTimestamp');
    uint256 endTimestamp = jsonString.readUint('.endTimestamp');
    string memory metadata = jsonString.readString('.metadata');
    bytes32 salt = jsonString.readBytes32('.salt');
    bytes32 root = jsonString.readBytes32('.root');

    address distributor = _readAddress('script/configs/distributor.json', chainId);

    vm.startBroadcast();
    bytes32 campaignId =
      KSDistributor(distributor).createCampaign(startTimestamp, endTimestamp, metadata, salt);
    console.log('Campaign %s created with:', vm.toString(campaignId));
    require(campaignId == expectedCampaignId, 'Campaign ID does not match the expected value');

    KSDistributor(distributor).submitRoot(campaignId, root, effectiveTimestamp);
    vm.stopBroadcast();

    console.log('Start timestamp:', startTimestamp);
    console.log('End timestamp:', endTimestamp);
    console.log('Metadata:', metadata);

    console.log('Root:', vm.toString(root));
  }
}
