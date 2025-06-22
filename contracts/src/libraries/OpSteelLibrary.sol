// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {
  Encoding,
  GameStatus,
  IDisputeGame,
  IDisputeGameFactory,
  IOptimismPortal2,
  Steel
} from 'risc0/steel/OpSteel.sol';

/// @notice Validate an OP L2 block commitment, enabling verification on L1 of Steel queries against L2 state.
library OpSteelLibrary {
  /// @notice Validates a Steel commitment.
  /// @param commitment The commitment to validate.
  /// @return True if the commitment is valid, false otherwise.
  function validateCommitment(IOptimismPortal2 optimismPortal, Steel.Commitment memory commitment)
    internal
    view
    returns (bool)
  {
    (uint240 blockID, uint16 version) = Encoding.decodeVersionedID(commitment.id);
    if (version == 0x100) {
      return validateDisputeGameCommitment(optimismPortal, blockID, commitment.digest);
    } else {
      return Steel.validateCommitment(commitment);
    }
  }

  /// @notice Validates a Dispute Game commitment.
  /// @param gameIndex The index of the game in the DisputeGameFactory.
  /// @param rootClaim The root claim of the dispute game.
  /// @return True if the commitment is valid, false otherwise.
  function validateDisputeGameCommitment(
    IOptimismPortal2 optimismPortal,
    uint256 gameIndex,
    bytes32 rootClaim
  ) internal view returns (bool) {
    IDisputeGameFactory factory = optimismPortal.disputeGameFactory();

    // Retrieve game information from the factory.
    (uint32 gameType, uint64 createdAt, IDisputeGame game) = factory.gameAtIndex(gameIndex);

    // The game type of the dispute game must be the respected game type.
    if (gameType != optimismPortal.respectedGameType()) return false;
    // The game must have been created after `respectedGameTypeUpdatedAt`.
    if (createdAt < optimismPortal.respectedGameTypeUpdatedAt()) return false;
    // The game must be resolved in favor of the root claim (the output proposal).
    if (game.status() != GameStatus.DEFENDER_WINS) return false;
    // The game must have been resolved for at least `proofMaturityDelaySeconds`.
    if (block.timestamp - game.resolvedAt() <= optimismPortal.proofMaturityDelaySeconds()) {
      return false;
    }
    // The game must not be blacklisted.
    if (optimismPortal.disputeGameBlacklist(game)) return false;

    // Finally, verify that the provided root claim matches the game's root claim.
    return game.rootClaim() == rootClaim;
  }
}
