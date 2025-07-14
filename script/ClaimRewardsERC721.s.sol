// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import '../src/KSDistributor.sol';
import './Base.s.sol';
import 'openzeppelin-contracts/contracts/token/ERC721/ERC721.sol';

contract ClaimRewardsERC721Script is BaseScript {
  using stdJson for string;

  bytes32 campaignId = bytes32(0);
  uint256 idx;

  function run() external {
    require(campaignId != bytes32(0), 'campaignId must be set to a non-zero value');

    uint256 chainId;
    assembly {
      chainId := chainid()
    }

    string memory filePath =
      string.concat('script/output/campaign-', vm.toString(campaignId), '.json');

    (
      address erc721Addr,
      uint256 erc721Id,
      address[] memory tokens,
      uint256[] memory amounts,
      bytes32[] memory proof
    ) = _readClaimingAmounts(filePath, idx);

    console.log('ERC721 Address:', erc721Addr);
    console.log('ERC721 ID:', erc721Id);
    for (uint256 i = 0; i < tokens.length; i++) {
      console.log('\tToken:', tokens[i]);
      console.log('\tAmount:', amounts[i]);
    }

    address payable distributor = payable(_readAddress('script/configs/distributor.json', chainId));
    address claimant = IERC721(erc721Addr).ownerOf(erc721Id);

    vm.startBroadcast(claimant);
    KSDistributor(distributor).claimRewardsForERC721(
      campaignId, erc721Addr, erc721Id, tokens, amounts, proof, claimant
    );
    vm.stopBroadcast();
  }
}
