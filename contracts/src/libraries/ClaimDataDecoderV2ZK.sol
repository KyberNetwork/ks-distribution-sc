// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC721Info, RewardsInfo, ZKProof} from '../interfaces/v2-zk/IKSDistributorV2ZkStructs.sol';
import {CalldataDecoder} from 'ks-common-sc/libraries/calldata/CalldataDecoder.sol';

/// @title Library for abi decoding in calldata
library ClaimDataDecoderV2ZK {
  using CalldataDecoder for bytes;

  function decodeClaimRewardsForAccountData(bytes calldata _bytes)
    internal
    pure
    returns (
      bytes32 campaignId,
      RewardsInfo calldata rewardsInfo,
      bytes32[] calldata proof,
      address recipient
    )
  {
    assembly ("memory-safe") {
      campaignId := calldataload(_bytes.offset)
      rewardsInfo := add(_bytes.offset, calldataload(add(_bytes.offset, 0x20)))
      recipient := calldataload(add(_bytes.offset, mul(0x20, 3)))
    }
    proof = _bytes.decodeBytes32Array(2);
  }

  function decodeClaimRewardsForERC721Data(bytes calldata _bytes)
    internal
    pure
    returns (
      bytes32 campaignId,
      ERC721Info calldata erc721Info,
      ZKProof calldata zkProof,
      RewardsInfo calldata rewardsInfo,
      bytes32[] calldata proof,
      address recipient
    )
  {
    assembly ("memory-safe") {
      campaignId := calldataload(_bytes.offset)
      erc721Info := add(_bytes.offset, 0x20)
      zkProof := add(_bytes.offset, calldataload(add(_bytes.offset, mul(0x20, 4))))
      rewardsInfo := add(_bytes.offset, calldataload(add(_bytes.offset, mul(0x20, 5))))
      recipient := calldataload(add(_bytes.offset, mul(0x20, 7)))
    }
    proof = _bytes.decodeBytes32Array(3);
  }
}
