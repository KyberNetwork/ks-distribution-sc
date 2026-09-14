// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import '../src/KSDistributor.sol';
import './Base.s.sol';

contract CreateCampaignScript is BaseDistributorScript {
  using stdJson for string;

  // @dev Create campaigns and submit their initial roots on multiple chains.

  // Usage:
  // # Create every campaign listed in script/campaigns-to-create.json, using each campaign's own
  // # startTimestamp as the root's effective timestamp
  // forge script CreateCampaignScript \
  // --sig "run(string[],uint256)" \
  // "[1,42161,8453,56,143,4663]" \
  // "0" \
  // --block-gas-limit 20000000000 --gas-estimate-multiplier 200 --broadcast

  function run(string[] memory chainIds, uint256 effectiveTimestamp) public multiChain(chainIds) {
    _loadDistributor();

    bytes32[] memory campaignIds = _readCampaignIds('campaigns-to-create.json');

    for (uint256 i = 0; i < campaignIds.length; i++) {
      bytes32 campaignId = campaignIds[i];
      string memory jsonString = _readCampaignFile(campaignId);

      _createCampaign(campaignId, jsonString);
      _submitRoot(campaignId, jsonString, effectiveTimestamp);
    }
  }

  function _createCampaign(bytes32 expectedCampaignId, string memory jsonString) internal {
    if (_campaignExists(expectedCampaignId)) {
      console.log(
        'CampaignId: %s already exists on chainId: %s, skipping creation...',
        vm.toString(expectedCampaignId),
        vm.toString(vm.getChainId())
      );
      return;
    }

    uint256 startTimestamp = jsonString.readUint('.startTimestamp');
    uint256 endTimestamp = jsonString.readUint('.endTimestamp');
    string memory metadata = jsonString.readString('.metadata');
    bytes32 salt = jsonString.readBytes32('.salt');

    console.log(
      'Creating campaignId: %s on chainId: %s',
      vm.toString(expectedCampaignId),
      vm.toString(vm.getChainId())
    );
    console.log('  startTimestamp:', startTimestamp);
    console.log('  endTimestamp:', endTimestamp);
    console.log('  metadata:', metadata);

    bytes32 campaignId = distributor.createCampaign(startTimestamp, endTimestamp, metadata, salt);
    require(campaignId == expectedCampaignId, 'campaignId does not match the campaign file');
  }

  function _submitRoot(bytes32 campaignId, string memory jsonString, uint256 effectiveTimestamp)
    internal
  {
    // A campaign's startTimestamp is the cycle's effective timestamp, so it is the right default.
    // submitRoot itself rejects anything earlier than block.timestamp + defaultTimeLock.
    uint256 rootEffectiveTimestamp =
      effectiveTimestamp != 0 ? effectiveTimestamp : jsonString.readUint('.startTimestamp');

    _submitAndVerifyRoot(campaignId, jsonString.readBytes32('.root'), rootEffectiveTimestamp);
  }
}
