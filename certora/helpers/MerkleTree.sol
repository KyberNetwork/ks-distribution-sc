// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {Hashes} from
  '../../lib/ks-growth-utils-sc/lib/openzeppelin-contracts/contracts/utils/cryptography/Hashes.sol';
import 'test/mocks/ERC721Mock.sol';

contract MerkleTree {
  struct AccountLeaf {
    bytes32 campaignId;
    address account;
    address[] tokens;
    uint256[] amounts;
  }

  struct ERC721Leaf {
    bytes32 campaignId;
    address account;
    address erc721Addr;
    uint256 erc721Id;
    address[] tokens;
    uint256[] amounts;
  }

  struct InternalNode {
    bytes32 id;
    bytes32 left;
    bytes32 right;
  }

  struct Node {
    bytes32 left;
    bytes32 right;
    bytes32 campaignId;
    address account;
    address erc721Addr;
    uint256 erc721Id;
    address[] tokens;
    uint256[] amounts;
    bytes32 hashValue;
  }

  uint256 public constant MAX_TOKENS = 4;

  mapping(bytes32 => Node) internal tree;

  function newAccountLeaf(AccountLeaf memory leaf) public {
    bytes32 id = keccak256(abi.encode(leaf.campaignId, leaf.account));
    Node storage node = tree[id];
    require(leaf.tokens.length == leaf.amounts.length, 'Invalid lengths');
    require(leaf.tokens.length <= MAX_TOKENS, 'Too many tokens');
    require(isEmpty(node), 'Node already exists');

    node.campaignId = leaf.campaignId;
    node.account = leaf.account;
    node.tokens = leaf.tokens;
    node.amounts = leaf.amounts;
    bytes32 infoHash = keccak256(abi.encode(leaf.campaignId, leaf.account));
    node.hashValue = keccak256(abi.encode(infoHash, leaf.tokens, leaf.amounts));
  }

  function newERC721Leaf(ERC721Leaf memory leaf) public {
    bytes32 id = keccak256(abi.encode(leaf.campaignId, leaf.erc721Addr, leaf.erc721Id));
    Node storage node = tree[id];
    require(leaf.tokens.length == leaf.amounts.length, 'Invalid lengths');
    require(leaf.tokens.length <= MAX_TOKENS, 'Too many tokens');
    require(isEmpty(node), 'Node already exists');
    ERC721Mock(leaf.erc721Addr).mint(leaf.account, leaf.erc721Id);

    node.campaignId = leaf.campaignId;
    node.account = leaf.account;
    node.erc721Addr = leaf.erc721Addr;
    node.erc721Id = leaf.erc721Id;
    node.tokens = leaf.tokens;
    node.amounts = leaf.amounts;
    bytes32 infoHash = keccak256(abi.encode(leaf.campaignId, leaf.erc721Addr, leaf.erc721Id));
    node.hashValue = keccak256(abi.encode(infoHash, leaf.tokens, leaf.amounts));
  }

  function newInternalNode(InternalNode memory internalNode) public {
    Node storage node = tree[internalNode.id];
    Node storage leftNode = tree[internalNode.left];
    Node storage rightNode = tree[internalNode.right];
    require(internalNode.id != 0, 'Invalid ID');
    require(isEmpty(node), 'Node already exists');
    require(!isEmpty(leftNode), 'Left node does not exist');
    require(!isEmpty(rightNode) || internalNode.right == 0, 'Empty right node has non-zero ID');
    require(
      internalNode.right == 0 || leftNode.campaignId == rightNode.campaignId,
      'Campaign IDs do not match'
    );

    node.left = internalNode.left;
    node.right = internalNode.right;
    node.campaignId = leftNode.campaignId;
    node.hashValue = Hashes.commutativeKeccak256(leftNode.hashValue, rightNode.hashValue);
  }

  function getHashValue(bytes32 id) public view returns (bytes32) {
    return tree[id].hashValue;
  }

  function isEmpty(Node memory node) public pure returns (bool) {
    return node.left == 0 && node.right == 0 && node.campaignId == 0 && node.account == address(0)
      && node.erc721Addr == address(0) && node.erc721Id == 0 && node.tokens.length == 0
      && node.amounts.length == 0 && node.hashValue == 0;
  }

  function isEmpty(bytes32 id) public view returns (bool) {
    return isEmpty(tree[id]);
  }

  function isWellFormed(bytes32 id) public view returns (bool) {
    Node storage node = tree[id];

    if (isEmpty(node)) {
      return true;
    }

    Node storage leftNode = tree[node.left];
    Node storage rightNode = tree[node.right];

    if (isEmpty(leftNode)) {
      if (
        node.left != 0 || node.right != 0 || node.tokens.length != node.amounts.length
          || node.tokens.length > MAX_TOKENS
      ) {
        return false;
      }

      bool isAccountLeaf = node.erc721Addr == address(0);
      bytes32 infoHash;
      if (isAccountLeaf) {
        infoHash = keccak256(abi.encode(node.campaignId, node.account));
      } else {
        infoHash = keccak256(abi.encode(node.campaignId, node.erc721Addr, node.erc721Id));
      }

      bytes32 expectedHashValue = keccak256(abi.encode(infoHash, node.tokens, node.amounts));
      return id == infoHash && node.hashValue == expectedHashValue;
    }

    if (isEmpty(rightNode) && node.right != 0) {
      return false;
    }
    if (!isEmpty(rightNode) && leftNode.campaignId != rightNode.campaignId) {
      return false;
    }
    
    bytes32 expectedHashValue = Hashes.commutativeKeccak256(leftNode.hashValue, rightNode.hashValue);
    return !isEmpty(leftNode) && node.hashValue == expectedHashValue;
  }
}
