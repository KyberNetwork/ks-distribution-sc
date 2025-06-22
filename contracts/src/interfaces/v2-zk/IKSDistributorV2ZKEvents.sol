// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {ERC721Info} from './IKSDistributorV2ZkStructs.sol';

interface IKSDistributorV2ZKEvents {
  /// @notice Emitted when a new campaign is created
  event CampaignCreated(
    bytes32 indexed campaignId, uint256 startTimestamp, uint256 endTimestamp, string metadata
  );

  /// @notice Emitted when the Merkle root of a campaign is applied
  event RootApplied(bytes32 indexed campaignId, bytes32 oldRoot, bytes32 newRoot);

  /// @notice Emitted when a pending Merkle root of a campaign is submitted
  event RootSubmitted(bytes32 indexed campaignId, bytes32 pendingRoot, uint256 effectiveTimestamp);

  /// @notice Emitted when the default time lock is updated
  event DefaultTimeLockUpdated(uint256 oldTime, uint256 newTime);

  /// @notice Emitted when the portal proxy address for a chain is updated
  event PortalProxyUpdated(uint256 indexed chainId, address oldProxy, address newProxy);

  /// @notice Emitted when startTimestamp of a campaign is updated
  event StartTimestampUpdated(bytes32 indexed campaignId, uint256 oldTime, uint256 newTime);

  /// @notice Emitted when endTimestamp of a campaign is updated
  event EndTimestampUpdated(bytes32 indexed campaignId, uint256 oldTime, uint256 newTime);

  /// @notice Emitted when metadata of a campaign is updated
  event MetadataUpdated(bytes32 indexed campaignId, string oldMetadata, string newMetadata);

  /// @notice Emitted when a hook and its selector is whitelisted
  event WhitelistedHookUpdated(address indexed hook, bytes4 indexed selector, bool grantOrRevoke);

  /// @notice Emitted when rewards are claimed for an account
  event RewardsClaimedForAccount(
    bytes32 indexed campaignId,
    address indexed account,
    bytes32 root,
    address[] tokens,
    uint256[] amounts,
    address recipient
  );

  /// @notice Emitted when rewards are claimed for an ERC721 token
  event RewardsClaimedForERC721(
    bytes32 indexed campaignId,
    ERC721Info erc721Info,
    address indexed claimant,
    bytes32 root,
    address[] tokens,
    uint256[] amounts,
    address recipient
  );
}
