// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'certora/helpers/MerkleTree.sol';
import {ERC20Mock} from 'openzeppelin-contracts/mocks/token/ERC20Mock.sol';

import 'forge-std/Test.sol';

contract MerkleTreeTest is Test {
  MerkleTree tree;

  ERC20Mock token0;
  ERC20Mock token1;

  function setUp() public {
    tree = new MerkleTree();
    token0 = new ERC20Mock();
    token1 = new ERC20Mock();
  }

  function testMerkleTree() public {
    MerkleTree.AccountLeaf memory leaf;
    leaf.campaignId = bytes32(0);
    leaf.account = address(0x1);
    leaf.tokens = new address[](2);
    leaf.tokens[0] = address(token0);
    leaf.tokens[1] = address(token1);
    leaf.amounts = new uint256[](2);
    leaf.amounts[0] = 100;
    leaf.amounts[1] = 200;

    tree.newAccountLeaf(leaf);
    bytes32 id = keccak256(abi.encode(leaf.account));
    assertTrue(tree.isWellFormed(id));
  }
}
