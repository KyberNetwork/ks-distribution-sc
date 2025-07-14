// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface IKSDistributor {
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
    address indexed erc721Addr,
    uint256 indexed erc721Id,
    address claimant,
    bytes32 root,
    address[] tokens,
    uint256[] amounts,
    address recipient
  );

  /// @notice Thrown when the campaign has too short duration
  error TooShortDuration();

  /// @notice Thrown when the campaign does not exist
  error CampaignDoesNotExist(bytes32 campaignId);

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

  struct Campaign {
    uint256 startTimestamp;
    uint256 endTimestamp;
    string metadata;
  }

  struct PendingRoot {
    bytes32 root;
    uint256 effectiveTimestamp;
  }

  /**
   * @notice Returns the default time lock for the campaign
   */
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
   * @notice Updates the default time lock for the campaign
   * @param newTimeLock the new default time lock in seconds
   */
  function updateDefaultTimeLock(uint256 newTimeLock) external;

  /**
   * @notice Creates a new campaign
   * @param startTimestamp the start timestamp of the campaign
   * @param endTimestamp the end timestamp of the campaign
   * @param metadata the metadata of the campaign
   * @param salt the salt for campaignId creation
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
   * @notice Force apply the Merkle root of a campaign
   * @param campaignId the unique id of the campaign
   * @param newRoot the new Merkle root
   */
  function forceUpdateRoot(bytes32 campaignId, bytes32 newRoot) external;

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

  /**
   * @notice Returns whether a hook and its selector is whitelisted
   * @param hook the address of the hook
   * @param selector the selector of the hook
   */
  function whitelistedHooks(address hook, bytes4 selector) external view returns (bool);

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
   * @notice Claims rewards for an account in a campaign with a hook
   * @param campaignId the unique id of the campaign
   * @param tokens the addresses of the reward tokens
   * @param amounts the cumulative amounts of rewards
   * @param proof the Merkle proof
   * @param recipient the address of the recipient
   * @param hook the address of the hook
   * @param hookData the data to pass to the hook
   */
  function claimRewardsForAccountWithHook(
    bytes32 campaignId,
    address[] calldata tokens,
    uint256[] calldata amounts,
    bytes32[] calldata proof,
    address recipient,
    address hook,
    bytes calldata hookData
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
   * @notice Claims rewards for an ERC721 token in a campaign with a hook
   * @param campaignId the unique id of the campaign
   * @param erc721Addr the address of the ERC721 contract
   * @param erc721Id the campaignId of the ERC721 token
   * @param tokens the addresses of the reward tokens
   * @param amounts the cumulative amounts of rewards
   * @param proof the Merkle proof
   * @param recipient the address of the recipient
   * @param hook the address of the hook
   * @param hookData the data to pass to the hook
   */
  function claimRewardsForERC721WithHook(
    bytes32 campaignId,
    address erc721Addr,
    uint256 erc721Id,
    address[] calldata tokens,
    uint256[] calldata amounts,
    bytes32[] calldata proof,
    address recipient,
    address hook,
    bytes calldata hookData
  ) external;

  /**
   * @notice Claims rewards in a batch
   * @param datas the datas to call in order to claim rewards
   */
  function batchClaimRewards(bytes[] calldata datas) external;

  /**
   * @notice Claims rewards in a batch with a hook
   * @param datas the datas to call in order to claim rewards
   * @param hook the address of the hook
   * @param hookData the data to pass to the hook
   */
  function batchClaimRewardsWithHook(bytes[] calldata datas, address hook, bytes calldata hookData)
    external;
}
