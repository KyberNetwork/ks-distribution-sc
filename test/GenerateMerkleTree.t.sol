// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'src/KSDistributor.sol';

import {ERC721Mock} from './mocks/ERC721Mock.sol';

import 'forge-std/StdJson.sol';
import 'forge-std/Test.sol';
import {ERC20Mock} from 'openzeppelin-contracts/mocks/token/ERC20Mock.sol';

contract GenerateMerkleTreeTest is Test {
  using stdJson for string;

  KSDistributor public distributor;

  ERC20Mock public token;
  ERC721Mock public nft;

  address public owner = makeAddr('owner');
  address public operator = makeAddr('operator');
  address public guardian = makeAddr('guardian');

  function setUp() public {
    vm.warp(1e18);
    _setUpKSDistributor();
    _setUpTokens();
  }

  function testGenerateMerkleTree() public {
    IKSDistributor.Campaign memory campaign = IKSDistributor.Campaign({
      startTimestamp: block.timestamp + 100,
      endTimestamp: block.timestamp + 2 hours,
      metadata: ''
    });
    vm.prank(operator);
    bytes32 campaignId =
      distributor.createCampaign(campaign.startTimestamp, campaign.endTimestamp, campaign.metadata);

    string memory json = vm.readFile(
      'script/output/campaign-0x16b707e108b118d5c22a8672bc4a6c5c0e4274c2311bbd4fb849030214db9582.json'
    );
    bytes32 root = json.readBytes32('.root');
    vm.prank(operator);
    distributor.updateRoot(campaignId, root);

    vm.warp(campaign.startTimestamp + 1);
    for (uint256 i = 0; i < 18; i++) {
      address account = json.readAddressOr(
        string.concat('.userDatas[', vm.toString(i), '].leaf.account'), address(0)
      );
      address[] memory tokens =
        json.readAddressArray(string.concat('.userDatas[', vm.toString(i), '].leaf.tokens'));
      uint256[] memory amounts =
        json.readUintArray(string.concat('.userDatas[', vm.toString(i), '].leaf.amounts'));
      bytes32[] memory proof =
        json.readBytes32Array(string.concat('.userDatas[', vm.toString(i), '].proof'));

      if (account != address(0)) {
        vm.prank(account);
        distributor.claimRewardsForAccount(campaignId, tokens, amounts, proof, account);
      } else {
        account = vm.addr(i);
        address erc721Addr =
          json.readAddress(string.concat('.userDatas[', vm.toString(i), '].leaf.erc721Addr'));
        uint256 erc721Id =
          json.readUint(string.concat('.userDatas[', vm.toString(i), '].leaf.erc721Id'));
        ERC721Mock(erc721Addr).mint(account, erc721Id);
        vm.prank(account);
        distributor.claimRewardsForERC721(
          campaignId, erc721Addr, erc721Id, tokens, amounts, proof, account
        );
      }
    }
  }

  function _setUpTokens() internal {
    vm.startPrank(makeAddr('deployer'));
    token = new ERC20Mock();
    nft = new ERC721Mock();
    vm.stopPrank();

    vm.etch(0x2e234DAe75C793f67A35089C9d99245E1C58470b, address(token).code);
    vm.etch(0xF62849F9A0B5Bf2913b396098F7c7019b51A820a, address(token).code);
    vm.etch(0x5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A9, address(nft).code);
    ERC20Mock(0x2e234DAe75C793f67A35089C9d99245E1C58470b).mint(
      address(distributor), type(uint128).max
    );
    ERC20Mock(0xF62849F9A0B5Bf2913b396098F7c7019b51A820a).mint(
      address(distributor), type(uint128).max
    );
  }

  function _setUpKSDistributor() internal {
    address[] memory initialOperators = new address[](1);
    initialOperators[0] = operator;
    address[] memory initialGuardians = new address[](1);
    initialGuardians[0] = guardian;
    distributor = new KSDistributor(owner, initialOperators, initialGuardians);
  }
}
