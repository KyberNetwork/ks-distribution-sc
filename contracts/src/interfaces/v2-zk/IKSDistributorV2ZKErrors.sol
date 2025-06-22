// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface IKSDistributorV2ZKErrors {
  /// @notice Thrown when the campaign has too short duration
  error TooShortDuration();

  /// @notice Thrown when a campaign already exists
  error CampaignAlreadyExists(bytes32 campaignId);

  /// @notice Thrown when the pending root effective timestamp is invalid
  error InvalidEffectiveTimestamp();

  /// @notice Thrown when the campaign has not started yet
  error TooEarly();

  /// @notice Thrown when the campaign has ended
  error TooLate();

  /// @notice Thrown when the input lengths are invalid
  error InvalidLengths();

  /// @notice Thrown when the commitment is invalid
  error InvalidCommitment();

  /// @notice Thrown when the proof is invalid
  error InvalidProof();

  /// @notice Thrown when the claimant is not nft's owner
  error UnauthorizedClaimant(address claimant);

  /// @notice Thrown when the selector is invalid
  error InvalidSelector(bytes4 selector);

  /// @notice Throw when the hookData is invalid
  error InvalidHookData(bytes hookData);

  /// @notice Thrown when the hook and its selector is not whitelisted
  error NotWhitelistedHook(address hook, bytes4 selector);
}
