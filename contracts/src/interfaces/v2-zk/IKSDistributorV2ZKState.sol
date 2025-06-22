// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {ERC721Info} from './IKSDistributorV2ZkStructs.sol';

interface IKSDistributorV2ZKState {
  /// @notice Returns the default time lock for the campaign
  function defaultTimeLock() external view returns (uint256);

  /**
   * @notice Returns the information of a campaign
   * @param campaignId the unique id of the campaign
   * @return startTimestamp the timestamp when the campaign starts
   * @return endTimestamp the timestamp when the campaign ends
   * @return metadata the metadata of the campaign
   */
  function campaigns(bytes32 campaignId)
    external
    view
    returns (uint256 startTimestamp, uint256 endTimestamp, string memory metadata);

  /**
   * @notice Returns the Merkle root of a campaign
   * @param campaignId the unique id of the campaign
   */
  function roots(bytes32 campaignId) external view returns (bytes32);

  /**
   * @notice Returns the pending Merkle root of a campaign
   * @param campaignId the unique id of the campaign
   * @return root the pending Merkle root
   * @return effectiveTimestamp the timestamp when the pending root will be effective
   */
  function pendingRoots(bytes32 campaignId)
    external
    view
    returns (bytes32 root, uint256 effectiveTimestamp);

  /**
   * @notice Returns whether a hook and its selector is whitelisted
   * @param hook the address of the hook
   * @param selector the selector of the hook
   */
  function whitelistedHooks(address hook, bytes4 selector) external view returns (bool);

  /**
   * @notice Returns the claimed amount for an account in a campaign
   * @param campaignId the unique id of the campaign
   * @param account the address of the account
   * @param token the address of the reward token
   */
  function getClaimedAmountForAccount(bytes32 campaignId, address account, address token)
    external
    view
    returns (uint256);

  /**
   * @notice Returns the claimed amount for an ERC721 token in a campaign
   * @param campaignId the unique id of the campaign
   * @param erc721Info the information of the ERC721 token
   * @param token the address of the reward token
   */
  function getClaimedAmountForERC721(
    bytes32 campaignId,
    ERC721Info calldata erc721Info,
    address token
  ) external view returns (uint256);
}
