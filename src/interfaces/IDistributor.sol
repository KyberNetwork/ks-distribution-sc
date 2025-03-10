// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {IERC20} from 'openzeppelin-contracts/token/ERC20/IERC20.sol';

interface IDistributor {
  /// @notice Thrown when the input lengths are invalid
  error InvalidLengths();

  /// @notice Thrown when a campaign with the same `id` already exists
  error CampaignAlreadyExists(bytes32 id);

  /// @notice Thrown when the campaign has not started yet
  error TooEarly();

  /// @notice Thrown when the campaign has ended
  error TooLate();

  /// @notice Thrown when the proof is invalid
  error InvalidProof();

  struct Campaign {
    uint256 startTimestamp;
    uint256 endTimestamp;
    bytes metadata;
  }

  /**
   * @notice Returns the information of a campaign
   * @param id the unique id of the campaign
   * @return startTimestamp the timestamp when the campaign starts
   * @return endTimestamp the timestamp when the campaign ends
   * @return metadata the metadata of the campaign
   */
  function campaigns(bytes32 id)
    external
    view
    returns (uint256 startTimestamp, uint256 endTimestamp, bytes memory metadata);

  /**
   * @notice Returns the Merkle root of a campaign
   * @param id the unique id of the campaign
   */
  function roots(bytes32 id) external view returns (bytes32);

  /**
   * @notice Returns the claimed amount for an account in a campaign
   * @param id the unique id of the campaign
   * @param token the address of the reward token
   * @param account the address of the account
   */
  function getClaimedAmountForAccount(bytes32 id, address token, address account)
    external
    view
    returns (uint256);

  /**
   * @notice Returns the claimed amount for an ERC721 token in a campaign
   * @param id the unique id of the campaign
   * @param token the address of the reward token
   * @param erc721Addr the address of the ERC721 contract
   * @param erc721Id the id of the ERC721 token
   */
  function getClaimedAmountForERC721(
    bytes32 id,
    address token,
    address erc721Addr,
    uint256 erc721Id
  ) external view returns (uint256);

  /**
   * @notice Claims rewards for an account in a campaign
   * @param id the unique id of the campaign
   * @param tokens the addresses of the reward tokens
   * @param amounts the cumulative amounts of rewards
   * @param proof the Merkle proof
   * @param recipient the address of the recipient
   */
  function claimRewardsForAccount(
    bytes32 id,
    address[] calldata tokens,
    uint256[] calldata amounts,
    bytes32[] calldata proof,
    address recipient
  ) external;

  /**
   * @notice Claims rewards for an ERC721 token in a campaign
   * @param id the unique id of the campaign
   * @param tokens the addresses of the reward tokens
   * @param amounts the cumulative amounts of rewards
   * @param proof the Merkle proof
   * @param erc721Addr the address of the ERC721 contract
   * @param erc721Id the id of the ERC721 token
   * @param recipient the address of the recipient
   */
  function claimRewardsForERC721(
    bytes32 id,
    address[] calldata tokens,
    uint256[] calldata amounts,
    bytes32[] calldata proof,
    address erc721Addr,
    uint256 erc721Id,
    address recipient
  ) external;
}
