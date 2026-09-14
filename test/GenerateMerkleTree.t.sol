// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'src/KSDistributor.sol';

import {ERC721Mock} from './mocks/ERC721Mock.sol';
import {ProxyUtils} from './utils/ProxyUtils.sol';

import 'forge-std/StdJson.sol';
import 'forge-std/Test.sol';
import {ERC20Mock} from 'openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol';

contract GenerateMerkleTreeTest is Test {
  using stdJson for string;

  KSDistributor public distributor;

  ERC20Mock public token;
  ERC721Mock public nft;

  address public owner = makeAddr('owner');
  address public operator = makeAddr('operator');
  address public guardian = makeAddr('guardian');
  address public rescuer = makeAddr('rescuer');

  mapping(address => bool) public etched;

  function setUp() public {
    vm.warp(1e18);
    _setUpKSDistributor();
    _setUpTokens();
  }

  function testGenerateMerkleTree() public {
    string memory datajson = vm.readFile('script/input/campaigns-data.json');
    for (uint256 i = 0;; i++) {
      uint256 startTimestamp = datajson.readUintOr(
        string.concat('.campaignsData[', vm.toString(i), '].startTimestamp'), 0
      );
      if (startTimestamp == 0) {
        break;
      }
      uint256 endTimestamp =
        datajson.readUint(string.concat('.campaignsData[', vm.toString(i), '].endTimestamp'));
      string memory metadata =
        datajson.readString(string.concat('.campaignsData[', vm.toString(i), '].metadata'));
      vm.prank(operator);
      bytes32 salt =
        datajson.readBytes32(string.concat('.campaignsData[', vm.toString(i), '].salt'));
      bytes32 campaignId = distributor.createCampaign(startTimestamp, endTimestamp, metadata, salt);
      string memory outputjson =
        vm.readFile(string.concat('script/output/campaign-', vm.toString(campaignId), '.json'));
      bytes32 root = outputjson.readBytes32('.root');
      vm.prank(operator);
      vm.warp(startTimestamp);
      distributor.submitRoot(campaignId, root, 0);
      vm.warp(startTimestamp + distributor.defaultTimeLock());

      for (uint256 j = 0;; j++) {
        address[] memory tokens = outputjson.readAddressArrayOr(
          string.concat('.userDatas[', vm.toString(j), '].leaf.tokens'), new address[](0)
        );
        if (tokens.length == 0) {
          break;
        }
        for (uint256 k = 0; k < tokens.length; k++) {
          if (!etched[tokens[k]]) {
            etched[tokens[k]] = true;
            vm.etch(tokens[k], address(token).code);
            ERC20Mock(tokens[k]).mint(address(distributor), type(uint128).max);
          }
        }

        uint256[] memory amounts =
          outputjson.readUintArray(string.concat('.userDatas[', vm.toString(j), '].leaf.amounts'));
        bytes32[] memory proof =
          outputjson.readBytes32Array(string.concat('.userDatas[', vm.toString(j), '].proof'));

        address account = outputjson.readAddressOr(
          string.concat('.userDatas[', vm.toString(j), '].leaf.account'), address(0)
        );
        if (account != address(0)) {
          vm.prank(account);
          distributor.claimRewardsForAccount(campaignId, tokens, amounts, proof, account);
        } else {
          account = vm.addr(j);
          address erc721Addr = outputjson.readAddress(
            string.concat('.userDatas[', vm.toString(j), '].leaf.erc721Addr')
          );
          if (!etched[erc721Addr]) {
            etched[erc721Addr] = true;
            vm.etch(erc721Addr, address(nft).code);
          }

          uint256 erc721Id =
            outputjson.readUint(string.concat('.userDatas[', vm.toString(j), '].leaf.erc721Id'));
          ERC721Mock(erc721Addr).mint(account, erc721Id);
          vm.prank(account);
          distributor.claimRewardsForERC721(
            campaignId, erc721Addr, erc721Id, tokens, amounts, proof, account
          );
        }
      }
    }
  }

  function _setUpTokens() internal {
    vm.startPrank(makeAddr('deployer'));
    token = new ERC20Mock();
    nft = new ERC721Mock();
    vm.stopPrank();
  }

  /// @dev Deployed from a dedicated address. campaigns-data.json hardcodes token addresses that
  /// are CREATE addresses of this test contract, and the test etches ERC20 bytecode over them, so
  /// anything this contract deploys itself risks being clobbered mid-test.
  function _setUpKSDistributor() internal {
    vm.startPrank(makeAddr('distributorDeployer'));

    address[] memory initialOperators = new address[](1);
    initialOperators[0] = operator;
    address[] memory initialGuardians = new address[](1);
    initialGuardians[0] = guardian;
    address[] memory initialRescuers = new address[](1);
    initialRescuers[0] = rescuer;
    distributor = KSDistributor(
      ProxyUtils.deployProxy(
        address(new KSDistributor()),
        owner,
        initialOperators,
        initialGuardians,
        initialRescuers,
        new address[](0),
        new bytes4[](0),
        1 hours
      )
    );

    vm.stopPrank();
  }
}
