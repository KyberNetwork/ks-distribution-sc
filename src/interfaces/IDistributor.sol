// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {IERC20} from 'openzeppelin-contracts/token/ERC20/IERC20.sol';

interface IDistributor {
  /// @notice Emitted when a new campaign is created
  event CampaignCreated(
    bytes32 indexed campaignId, uint256 startTimestamp, uint256 endTimestamp, bytes metadata
  );

  /// @notice Emitted when the Merkle root of a campaign is updated
  event RootUpdated(bytes32 indexed campaignId, bytes32 oldRoot, bytes32 newRoot);

  /// @notice Emitted when rewards are claimed for an account
  event RewardsClaimedForAccount(
    bytes32 indexed campaignId,
    address indexed account,
    address[] tokens,
    uint256[] amounts,
    address recipient
  );

  /// @notice Emitted when rewards are claimed for an ERC721 token
  event RewardsClaimedForERC721(
    bytes32 indexed campaignId,
    address indexed erc721Addr,
    uint256 indexed erc721Id,
    address claimant,
    address[] tokens,
    uint256[] amounts,
    address recipient
  );

  /// @notice Thrown when the campaign has too short duration
  error TooShortDuration();

  /// @notice Thrown when a campaign already exists
  error CampaignAlreadyExists(bytes32 campaignId);

  /// @notice Thrown when the campaign has not started yet
  error TooEarly();

  /// @notice Thrown when the campaign has ended
  error TooLate();

  /// @notice Thrown when the input lengths are invalid
  error InvalidLengths();

  /// @notice Thrown when the proof is invalid
  error InvalidProof();

  /// @notice Thrown when the claimant is unauthorized
  error UnauthorizedClaimant(address claimant);

  /// @notice Thrown when the selector is invalid
  error InvalidSelector(bytes4 selector);

  struct Campaign {
    uint256 startTimestamp;
    uint256 endTimestamp;
    bytes metadata;
  }

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
    returns (uint256 startTimestamp, uint256 endTimestamp, bytes memory metadata);

  /**
   * @notice Returns the Merkle root of a campaign
   * @param campaignId the unique id of the campaign
   */
  function roots(bytes32 campaignId) external view returns (bytes32);

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
   * @param erc721Addr the address of the ERC721 contract
   * @param erc721Id the campaignId of the ERC721 token
   * @param token the address of the reward token
   */
  function getClaimedAmountForERC721(
    bytes32 campaignId,
    address erc721Addr,
    uint256 erc721Id,
    address token
  ) external view returns (uint256);

  /**
   * @notice Claims rewards for an account in a campaign
   * @param campaignId the unique id of the campaign
   * @param tokens the addresses of the reward tokens
   * @param amounts the cumulative amounts of rewards
   * @param proof the Merkle proof
   * @param recipient the address of the recipient
   */
  function claimRewardsForAccount(
    bytes32 campaignId,
    address[] calldata tokens,
    uint256[] calldata amounts,
    bytes32[] calldata proof,
    address recipient
  ) external;

  /**
   * @notice Claims rewards for an ERC721 token in a campaign
   * @param campaignId the unique id of the campaign
   * @param erc721Addr the address of the ERC721 contract
   * @param erc721Id the campaignId of the ERC721 token
   * @param tokens the addresses of the reward tokens
   * @param amounts the cumulative amounts of rewards
   * @param proof the Merkle proof
   * @param recipient the address of the recipient
   */
  function claimRewardsForERC721(
    bytes32 campaignId,
    address erc721Addr,
    uint256 erc721Id,
    address[] calldata tokens,
    uint256[] calldata amounts,
    bytes32[] calldata proof,
    address recipient
  ) external;

  /**
   * @notice Claims rewards in a batch
   * @param datas the datas to call in order to claim rewards
   */
  function batchClaimRewards(bytes[] calldata datas) external;
}
