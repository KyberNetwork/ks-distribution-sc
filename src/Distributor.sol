// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './interfaces/IDistributor.sol';

import 'ks-growth-utils-sc/KSRescueV2.sol';
import 'openzeppelin-contracts/utils/cryptography/MerkleProof.sol';

contract Distributor is IDistributor, KSRescueV2 {
  using SafeERC20 for IERC20;

  /// @inheritdoc IDistributor
  mapping(bytes32 id => Campaign) public campaigns;

  /// @inheritdoc IDistributor
  mapping(bytes32 id => bytes32) public roots;

  /// @notice The claimed amount for each `infoHash` in each campaign
  mapping(bytes32 infoHash => uint256) internal claimed;

  constructor() Ownable(msg.sender) {}

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

  /**
   * @notice Creates a new campaign
   * @param startTimestamp the start timestamp of the campaign
   * @param endTimestamp the end timestamp of the campaign
   * @param metadata the metadata of the campaign
   */
  function createCampaign(uint256 startTimestamp, uint256 endTimestamp, bytes calldata metadata)
    external
    onlyOwner
    onlyBefore(startTimestamp)
  {
    bytes32 id = keccak256(abi.encodePacked(startTimestamp, endTimestamp, metadata));
    require(campaigns[id].startTimestamp == 0, CampaignAlreadyExists(id));
    campaigns[id] = Campaign(startTimestamp, endTimestamp, metadata);
  }

  /**
   * @notice Updates the Merkle root of a campaign
   * @param id the unique id of the campaign
   * @param newRoot the new Merkle root
   */
  function updateRoot(bytes32 id, bytes32 newRoot) external onlyOwner {
    roots[id] = newRoot;
  }

  /// @inheritdoc IDistributor
  function getClaimedAmountForAccount(bytes32 id, address token, address account)
    external
    view
    returns (uint256)
  {
    bytes32 preHash = keccak256(abi.encodePacked(id, account));
    bytes32 infoHash = keccak256(abi.encodePacked(preHash, token));
    return claimed[infoHash];
  }

  /// @inheritdoc IDistributor
  function getClaimedAmountForERC721(
    bytes32 id,
    address token,
    address erc721Addr,
    uint256 erc721Id
  ) external view returns (uint256) {
    bytes32 preHash = keccak256(abi.encodePacked(id, erc721Addr, erc721Id));
    bytes32 infoHash = keccak256(abi.encodePacked(preHash, token));
    return claimed[infoHash];
  }

  /// @inheritdoc IDistributor
  function claimRewardsForAccount(
    bytes32 id,
    address[] calldata tokens,
    uint256[] calldata amounts,
    bytes32[] calldata proof,
    address recipient
  ) external onlyBetween(campaigns[id].startTimestamp, campaigns[id].endTimestamp) {
    require(tokens.length == amounts.length, InvalidLengths());

    bytes32 preHash = keccak256(abi.encodePacked(id, _msgSender()));

    require(
      MerkleProof.verifyCalldata(proof, roots[id], keccak256(abi.encodePacked(preHash, tokens)))
    );

    _transferRewards(preHash, tokens, amounts, recipient);
  }

  /// @inheritdoc IDistributor
  function claimRewardsForERC721(
    bytes32 id,
    address[] calldata tokens,
    uint256[] calldata amounts,
    bytes32[] calldata proof,
    address erc721Addr,
    uint256 erc721Id,
    address recipient
  ) external onlyBetween(campaigns[id].startTimestamp, campaigns[id].endTimestamp) {
    require(tokens.length == amounts.length, InvalidLengths());
    require(IERC721(erc721Addr).ownerOf(erc721Id) == _msgSender());

    bytes32 preHash = keccak256(abi.encodePacked(id, erc721Addr, erc721Id));

    require(
      MerkleProof.verifyCalldata(proof, roots[id], keccak256(abi.encodePacked(preHash, tokens)))
    );

    _transferRewards(preHash, tokens, amounts, recipient);
  }

  /// @notice Transfers the rewards to the recipient
  function _transferRewards(
    bytes32 preHash,
    address[] calldata tokens,
    uint256[] calldata amounts,
    address recipient
  ) internal {
    for (uint256 i = 0; i < tokens.length; i++) {
      bytes32 infoHash = keccak256(abi.encodePacked(preHash, tokens[i]));
      uint256 claimable = amounts[i] - claimed[infoHash];
      claimed[infoHash] += claimable;
      IERC20(tokens[i]).safeTransfer(recipient, claimable);
    }
  }
}
