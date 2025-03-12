// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './interfaces/IDistributor.sol';

import 'ks-growth-utils-sc/KSRescueV2.sol';
import 'openzeppelin-contracts/utils/cryptography/MerkleProof.sol';

contract Distributor is IDistributor, KSRescueV2 {
  using SafeERC20 for IERC20;

  /// @inheritdoc IDistributor
  mapping(bytes32 campaignId => Campaign) public campaigns;

  /// @inheritdoc IDistributor
  mapping(bytes32 campaignId => bytes32) public roots;

  /// @notice The claimed amount for each `infoHash` in each campaign
  mapping(bytes32 infoHash => mapping(address => uint256)) internal claimed;

  /// @notice Restricts a function to be called before a certain timestamp
  modifier onlyBefore(uint256 timestamp) {
    require(block.timestamp < timestamp, TooLate());
    _;
  }

  /// @notice Restricts a function to be called between two timestamps
  modifier onlyBetween(uint256 startTimestamp, uint256 endTimestamp) {
    require(block.timestamp >= startTimestamp, TooEarly());
    require(block.timestamp < endTimestamp, TooLate());
    _;
  }

  constructor(
    address initialOwner,
    address[] memory initialOperators,
    address[] memory initialGuardians
  ) Ownable(initialOwner) {
    for (uint256 i = 0; i < initialOperators.length; i++) {
      operators[initialOperators[i]] = true;

      emit UpdateOperator(initialOperators[i], true);
    }
    for (uint256 i = 0; i < initialGuardians.length; i++) {
      guardians[initialGuardians[i]] = true;

      emit UpdateGuardian(initialGuardians[i], true);
    }
  }

  /**
   * @notice Creates a new campaign
   * @param startTimestamp the start timestamp of the campaign
   * @param endTimestamp the end timestamp of the campaign
   * @param metadata the metadata of the campaign
   * @return campaignId the unique id of the campaign
   */
  function createCampaign(uint256 startTimestamp, uint256 endTimestamp, bytes calldata metadata)
    external
    onlyOperator
    onlyBefore(startTimestamp)
    returns (bytes32 campaignId)
  {
    campaignId = keccak256(abi.encodePacked(startTimestamp, endTimestamp, metadata));
    require(campaigns[campaignId].startTimestamp == 0, CampaignAlreadyExists(campaignId));
    campaigns[campaignId] = Campaign(startTimestamp, endTimestamp, metadata);

    emit CampaignCreated(campaignId, startTimestamp, endTimestamp, metadata);
  }

  /**
   * @notice Updates the Merkle root of a campaign
   * @param campaignId the unique id of the campaign
   * @param newRoot the new Merkle root
   */
  function updateRoot(bytes32 campaignId, bytes32 newRoot)
    external
    onlyOperator
    onlyBefore(campaigns[campaignId].endTimestamp)
  {
    bytes32 oldRoot = roots[campaignId];
    roots[campaignId] = newRoot;

    emit RootUpdated(campaignId, oldRoot, newRoot);
  }

  /// @inheritdoc IDistributor
  function getClaimedAmountForAccount(bytes32 campaignId, address account, address token)
    external
    view
    returns (uint256)
  {
    bytes32 infoHash = keccak256(abi.encodePacked(campaignId, account));
    return claimed[infoHash][token];
  }

  /// @inheritdoc IDistributor
  function getClaimedAmountForERC721(
    bytes32 campaignId,
    address erc721Addr,
    uint256 erc721Id,
    address token
  ) external view returns (uint256) {
    bytes32 infoHash = keccak256(abi.encodePacked(campaignId, erc721Addr, erc721Id));
    return claimed[infoHash][token];
  }

  /// @inheritdoc IDistributor
  function claimRewardsForAccount(
    bytes32 campaignId,
    address[] calldata tokens,
    uint256[] calldata amounts,
    bytes32[] calldata proof,
    address recipient
  )
    external
    onlyBetween(campaigns[campaignId].startTimestamp, campaigns[campaignId].endTimestamp)
    whenNotPaused
  {
    require(tokens.length == amounts.length, InvalidLengths());

    bytes32 infoHash = keccak256(abi.encodePacked(campaignId, _msgSender()));
    require(
      MerkleProof.verifyCalldata(
        proof, roots[campaignId], keccak256(abi.encodePacked(infoHash, tokens, amounts))
      ),
      InvalidProof()
    );

    uint256[] memory claimedAmounts = _transferRewards(infoHash, tokens, amounts, recipient);
    emit RewardsClaimedForAccount(campaignId, _msgSender(), tokens, claimedAmounts, recipient);
  }

  /// @inheritdoc IDistributor
  function claimRewardsForERC721(
    bytes32 campaignId,
    address erc721Addr,
    uint256 erc721Id,
    address[] calldata tokens,
    uint256[] calldata amounts,
    bytes32[] calldata proof,
    address recipient
  )
    external
    onlyBetween(campaigns[campaignId].startTimestamp, campaigns[campaignId].endTimestamp)
    whenNotPaused
  {
    require(tokens.length == amounts.length, InvalidLengths());

    IERC721 nft = IERC721(erc721Addr);
    address nftOwner = nft.ownerOf(erc721Id);
    address msgSender = _msgSender();
    require(
      nftOwner == msgSender || nft.getApproved(erc721Id) == msgSender
        || nft.isApprovedForAll(nftOwner, msgSender),
      UnauthorizedClaimant(msgSender)
    );

    bytes32 infoHash = keccak256(abi.encodePacked(campaignId, erc721Addr, erc721Id));
    require(
      MerkleProof.verifyCalldata(
        proof, roots[campaignId], keccak256(abi.encodePacked(infoHash, tokens, amounts))
      ),
      InvalidProof()
    );

    uint256[] memory claimedAmounts = _transferRewards(infoHash, tokens, amounts, recipient);
    emit RewardsClaimedForERC721(
      campaignId, erc721Addr, erc721Id, msgSender, tokens, claimedAmounts, recipient
    );
  }

  /// @notice Transfers the rewards to the recipient
  function _transferRewards(
    bytes32 infoHash,
    address[] calldata tokens,
    uint256[] calldata amounts,
    address recipient
  ) internal returns (uint256[] memory claimedAmounts) {
    claimedAmounts = new uint256[](tokens.length);
    for (uint256 i = 0; i < tokens.length; i++) {
      address token = tokens[i];
      uint256 claimable = amounts[i] - claimed[infoHash][token];
      if (claimable > 0) {
        claimed[infoHash][token] += claimable;
        IERC20(token).safeTransfer(recipient, claimable);
        claimedAmounts[i] = claimable;
      }
    }
  }
}
