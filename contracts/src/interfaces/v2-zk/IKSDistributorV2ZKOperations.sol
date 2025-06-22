// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface IKSDistributorV2ZKOperations {
  /**
   * @notice Creates a new campaign
   * @param startTimestamp the start timestamp of the campaign
   * @param endTimestamp the end timestamp of the campaign
   * @param metadata the metadata of the campaign
   * @return campaignId the unique id of the campaign
   */
  function createCampaign(
    uint256 startTimestamp,
    uint256 endTimestamp,
    string calldata metadata,
    bytes32 salt
  ) external returns (bytes32 campaignId);

  /**
   * @notice Submit the Merkle root of a campaign
   * @param campaignId the unique id of the campaign
   * @param newRoot the new Merkle root
   * @param effectiveTimestamp the timestamp when the new root will be effective
   */
  function submitRoot(bytes32 campaignId, bytes32 newRoot, uint256 effectiveTimestamp) external;

  /**
   * @notice Updates startTimestamp of a campaign
   * @param campaignId the unique id of the campaign
   * @param startTimestamp the new startTimestamp
   */
  function updateStartTimestamp(bytes32 campaignId, uint256 startTimestamp) external;

  /**
   * @notice Updates endTimestamp of a campaign
   * @param campaignId the unique id of the campaign
   * @param endTimestamp the new endTimestamp
   */
  function updateEndTimestamp(bytes32 campaignId, uint256 endTimestamp) external;

  /**
   * @notice Updates metadata of a campaign
   * @param campaignId the unique id of the campaign
   * @param metadata the new metadata
   */
  function updateMetadata(bytes32 campaignId, string calldata metadata) external;
}
