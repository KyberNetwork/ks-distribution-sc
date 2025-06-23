// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {ERC721Info, RewardsInfo, ZKProof} from './IKSDistributorV2ZkStructs.sol';

interface IKSDistributorV2ZKActions {
  /**
   * @notice Claims rewards for an account in a campaign with a hook
   * @param campaignId the unique id of the campaign
   * @param rewardsInfo the information of the rewards
   * @param proof the Merkle proof
   * @param recipient the address of the recipient
   * @param hook the address of the hook
   * @param hookData the data to pass to the hook
   */
  function claimRewardsForAccount(
    bytes32 campaignId,
    RewardsInfo calldata rewardsInfo,
    bytes32[] calldata proof,
    address recipient,
    address hook,
    bytes calldata hookData
  ) external;

  /**
   * @notice Claims rewards for an ERC721 token in a campaign with a hook
   * @param campaignId the unique id of the campaign
   * @param erc721Info the information of the ERC721 token
   * @param rewardsInfo the information of the rewards
   * @param proof the Merkle proof
   * @param recipient the address of the recipient
   * @param hook the address of the hook
   * @param hookData the data to pass to the hook
   */
  function claimRewardsForERC721(
    bytes32 campaignId,
    ERC721Info calldata erc721Info,
    ZKProof calldata zkProof,
    RewardsInfo calldata rewardsInfo,
    bytes32[] calldata proof,
    address recipient,
    address hook,
    bytes calldata hookData
  ) external;

  /**
   * @notice Claims rewards in a batch
   * @param datas the datas to call in order to claim rewards
   * @param hook the address of the hook
   * @param hookData the data to pass to the hook
   */
  function batchClaimRewards(bytes[] calldata datas, address hook, bytes calldata hookData)
    external;

  /**
   * @notice Verifies a ZK proof of ownership for an ERC721 token
   * @param erc721Info the information of the ERC721 token
   * @param zkProof the ZK proof
   */
  function verifyERC721Ownership(ERC721Info calldata erc721Info, ZKProof calldata zkProof)
    external
    view
    returns (bool);
}
