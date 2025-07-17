// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import 'ks-common-sc/src/libraries/calldata/CalldataDecoder.sol';

/// @title Library for decoding claim data
library ClaimDataDecoder {
  using CalldataDecoder for bytes;

  function decodeClaimRewardsForAccountData(bytes calldata _bytes)
    internal
    pure
    returns (
      bytes32 campaignId,
      address[] calldata tokens,
      uint256[] calldata amounts,
      bytes32[] calldata proof,
      address recipient
    )
  {
    assembly ("memory-safe") {
      campaignId := calldataload(_bytes.offset)
      recipient := calldataload(add(_bytes.offset, 0x80))
    }
    tokens = _bytes.decodeAddressArray(1);
    amounts = _bytes.decodeUint256Array(2);
    proof = _bytes.decodeBytes32Array(3);
  }

  function decodeClaimRewardsForERC721Data(bytes calldata _bytes)
    internal
    pure
    returns (
      bytes32 campaignId,
      address erc721Addr,
      uint256 erc721Id,
      address[] calldata tokens,
      uint256[] calldata amounts,
      bytes32[] calldata proof,
      address recipient
    )
  {
    assembly ("memory-safe") {
      campaignId := calldataload(_bytes.offset)
      erc721Addr := calldataload(add(_bytes.offset, 0x20))
      erc721Id := calldataload(add(_bytes.offset, 0x40))
      recipient := calldataload(add(_bytes.offset, 0xc0))
    }
    tokens = _bytes.decodeAddressArray(3);
    amounts = _bytes.decodeUint256Array(4);
    proof = _bytes.decodeBytes32Array(5);
  }
}
