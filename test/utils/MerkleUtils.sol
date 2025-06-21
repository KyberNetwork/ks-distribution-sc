// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {Hashes} from 'openzeppelin-contracts/contracts/utils/cryptography/Hashes.sol';

library MerkleUtils {
  function getRoot(bytes32[] memory leaves) internal pure returns (bytes32) {
    while (leaves.length > 1) {
      leaves = combine(leaves);
    }
    return leaves[0];
  }

  function getProof(bytes32[] memory leaves, uint256 node)
    internal
    pure
    returns (bytes32[] memory proof)
  {
    unchecked {
      proof = new bytes32[](log2Up(leaves.length));
      for (uint256 i = 0; i < proof.length; i++) {
        if (node & 1 == 1) {
          proof[i] = leaves[node - 1];
        } else if (node + 1 < leaves.length) {
          proof[i] = leaves[node + 1];
        }
        node >>= 1;
        leaves = combine(leaves);
      }
    }
  }

  function combine(bytes32[] memory leaves) internal pure returns (bytes32[] memory combined) {
    unchecked {
      uint256 length = leaves.length;
      if (length & 1 == 1) {
        combined = new bytes32[](length / 2 + 1);
        combined[length / 2] = Hashes.commutativeKeccak256(leaves[length - 1], 0);
      } else {
        combined = new bytes32[](length / 2);
      }
      for (uint256 node = 0; node + 1 < length; node += 2) {
        combined[node / 2] = Hashes.commutativeKeccak256(leaves[node], leaves[node + 1]);
      }
    }
  }

  /// @dev Returns the log2 of `x`.
  /// Equivalent to computing the index of the most significant bit (MSB) of `x`.
  /// Returns 0 if `x` is zero.
  function log2(uint256 x) internal pure returns (uint256 r) {
    /// @solidity memory-safe-assembly
    assembly {
      r := shl(7, lt(0xffffffffffffffffffffffffffffffff, x))
      r := or(r, shl(6, lt(0xffffffffffffffff, shr(r, x))))
      r := or(r, shl(5, lt(0xffffffff, shr(r, x))))
      r := or(r, shl(4, lt(0xffff, shr(r, x))))
      r := or(r, shl(3, lt(0xff, shr(r, x))))
      // forgefmt: disable-next-item
      r := or(r, byte(and(0x1f, shr(shr(r, x), 0x8421084210842108cc6318c6db6d54be)),
                0x0706060506020504060203020504030106050205030304010505030400000000))
    }
  }

  /// @dev Returns the log2 of `x`, rounded up.
  /// Returns 0 if `x` is zero.
  function log2Up(uint256 x) internal pure returns (uint256 r) {
    r = log2(x);
    /// @solidity memory-safe-assembly
    assembly {
      r := add(r, lt(shl(r, 1), x))
    }
  }
}
