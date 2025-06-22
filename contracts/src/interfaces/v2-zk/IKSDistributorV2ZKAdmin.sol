// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface IKSDistributorV2ZKAdmin {
  /**
   * @notice Updates the portal proxy address for a chain
   * @param chainId the chain id
   * @param newPortalProxy the new portal proxy address
   */
  function updatePortalProxy(uint256 chainId, address newPortalProxy) external;

  /**
   * @notice Updates the default time lock for the campaign
   * @param newTimeLock the new default time lock in seconds
   */
  function updateDefaultTimeLock(uint256 newTimeLock) external;

  /**
   * @notice Force apply the Merkle root of a campaign
   * @param campaignId the unique id of the campaign
   * @param newRoot the new Merkle root
   */
  function forceUpdateRoot(bytes32 campaignId, bytes32 newRoot) external;

  /**
   * @notice Grants or revokes a hook whitelisting
   * @param hooks the addresses of the hooks
   * @param selectors the selectors of the hooks
   * @param grantOrRevoke true to grant, false to revoke
   */
  function updateWhitelistedHooks(
    address[] calldata hooks,
    bytes4[] calldata selectors,
    bool grantOrRevoke
  ) external;
}
