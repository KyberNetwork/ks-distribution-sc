// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {Steel} from 'risc0/steel/Steel.sol';

struct ERC721Info {
  uint256 chainId;
  address erc721Addr;
  uint256 erc721Id;
}

struct RewardsInfo {
  address[] tokens;
  uint256[] amounts;
}

struct Campaign {
  uint256 startTimestamp;
  uint256 endTimestamp;
  string metadata;
}

struct PendingRoot {
  bytes32 root;
  uint256 effectiveTimestamp;
}

struct ZKProof {
  Steel.Commitment commitment;
  bytes seal;
}
