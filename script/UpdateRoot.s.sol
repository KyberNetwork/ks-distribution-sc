// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import '../src/KSDistributor.sol';
import './Base.s.sol';

contract UpdateRootScript is BaseScript {
  using stdJson for string;

  bytes32 campaignId = bytes32(0);
  uint256 effectiveTimestamp = type(uint256).max;

  function run() external {
    require(campaignId != bytes32(0), 'campaignId must be set to a non-zero value');
    require(
      effectiveTimestamp != type(uint256).max, 'effectiveTimestamp must be set to a valid value'
    );

    uint256 chainId;
    assembly {
      chainId := chainid()
    }

    string memory filePath =
      string.concat('script/output/campaign-', vm.toString(campaignId), '.json');
    string memory jsonString = vm.readFile(filePath);
    bytes32 root = jsonString.readBytes32('.root');

    address payable distributor = payable(_readAddress('script/configs/distributor.json', chainId));

    vm.startBroadcast();
    console.log('Campaign:', vm.toString(campaignId));
    console.log('Root:', vm.toString(root));
    KSDistributor(distributor).submitRoot(campaignId, root, effectiveTimestamp);
    vm.stopBroadcast();
  }
}
