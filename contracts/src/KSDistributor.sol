// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.28;

import './interfaces/IKSDistributor.sol';
import './libraries/ClaimDataDecoder.sol';

import {KSRescueV2, Ownable} from 'ks-growth-utils-sc/KSRescueV2.sol';

import 'openzeppelin-contracts/contracts/utils/Address.sol';
import 'openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol';

import 'openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';

import 'openzeppelin-contracts/contracts/token/ERC721/IERC721.sol';
import 'openzeppelin-contracts/contracts/utils/SlotDerivation.sol';
import 'openzeppelin-contracts/contracts/utils/TransientSlot.sol';
import 'openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol';

contract KSDistributor is IKSDistributor, ReentrancyGuard, KSRescueV2 {
  using SafeERC20 for IERC20;
  using Address for address;
  using SlotDerivation for bytes32;
  using TransientSlot for *;

  uint256 public constant MIN_CAMPAIGN_DURATION = 1 hours;

  // keccak256(abi.encode(uint256(keccak256('ks-distributor.storage.PendingRewards')) - 1)) & ~bytes32(uint256(0xff))
  bytes32 internal constant PENDING_REWARDS_STORAGE =
    0x667c036918e8dbe38a4ec9003830d89d321fbfffacba5bdecb14c1bbca99be00;

  /// @inheritdoc IKSDistributor
  uint256 public defaultTimeLock;

  /// @inheritdoc IKSDistributor
  mapping(bytes32 campaignId => Campaign) public campaigns;

  /// @inheritdoc IKSDistributor
  mapping(bytes32 campaignId => bytes32) public roots;

  /// @inheritdoc IKSDistributor
  mapping(bytes32 campaignId => PendingRoot) public pendingRoots;

  /// @notice Whether a hook and a selector is whitelisted
  mapping(address hook => mapping(bytes4 selector => bool)) public whitelistedHooks;

  /// @notice The claimed amount for each `infoHash` in each campaign
  mapping(bytes32 infoHash => mapping(address token => uint256)) internal claimed;

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
    address[] memory initialGuardians,
    uint256 initDefaultTimeLock
  ) Ownable(initialOwner) {
    for (uint256 i = 0; i < initialOperators.length; i++) {
      operators[initialOperators[i]] = true;

      emit UpdateOperator(initialOperators[i], true);
    }
    for (uint256 i = 0; i < initialGuardians.length; i++) {
      guardians[initialGuardians[i]] = true;

      emit UpdateGuardian(initialGuardians[i], true);
    }

    _updateDefaultTimeLock(initDefaultTimeLock);
  }

  /// @inheritdoc IKSDistributor
  function updateDefaultTimeLock(uint256 newDefaultTimeLock) public onlyOwner {
    _updateDefaultTimeLock(newDefaultTimeLock);
  }

  function _updateDefaultTimeLock(uint256 newDefaultTimeLock) internal {
    uint256 oldDefaultTimeLock = defaultTimeLock;
    defaultTimeLock = newDefaultTimeLock;

    emit DefaultTimeLockUpdated(oldDefaultTimeLock, newDefaultTimeLock);
  }

  /// @inheritdoc IKSDistributor
  function createCampaign(
    uint256 initStartTimestamp,
    uint256 initEndTimestamp,
    string calldata initMetadata,
    bytes32 salt
  ) public onlyOperator onlyBefore(initEndTimestamp) returns (bytes32 campaignId) {
    require(initStartTimestamp + MIN_CAMPAIGN_DURATION <= initEndTimestamp, TooShortDuration());
    campaignId = keccak256(abi.encode(initStartTimestamp, initEndTimestamp, initMetadata, salt));
    require(campaigns[campaignId].startTimestamp == 0, CampaignAlreadyExists(campaignId));
    campaigns[campaignId] = Campaign(initStartTimestamp, initEndTimestamp, initMetadata);

    emit CampaignCreated(campaignId, initStartTimestamp, initEndTimestamp, initMetadata);
  }

  /// @inheritdoc IKSDistributor
  function submitRoot(bytes32 campaignId, bytes32 newRoot, uint256 effectiveTimestamp)
    public
    onlyOperator
  {
    if (effectiveTimestamp == 0) {
      effectiveTimestamp = block.timestamp + defaultTimeLock;
    }
    require(
      effectiveTimestamp >= block.timestamp + defaultTimeLock
        && effectiveTimestamp < campaigns[campaignId].endTimestamp,
      InvalidEffectiveTimestamp()
    );
    _checkPendingRoot(campaignId);
    pendingRoots[campaignId] = PendingRoot(newRoot, effectiveTimestamp);

    emit RootSubmitted(campaignId, newRoot, effectiveTimestamp);
  }

  /// @inheritdoc IKSDistributor
  function forceUpdateRoot(bytes32 campaignId, bytes32 newRoot) public onlyOwner {
    _applyRoot(campaignId, newRoot);
  }

  /// @inheritdoc IKSDistributor
  function updateStartTimestamp(bytes32 campaignId, uint256 startTimestamp) public onlyOperator {
    uint256 oldStartTimestamp = campaigns[campaignId].startTimestamp;
    campaigns[campaignId].startTimestamp = startTimestamp;

    emit StartTimestampUpdated(campaignId, oldStartTimestamp, startTimestamp);
  }

  /// @inheritdoc IKSDistributor
  function updateEndTimestamp(bytes32 campaignId, uint256 endTimestamp) public onlyOperator {
    uint256 oldEndTimestamp = campaigns[campaignId].endTimestamp;
    campaigns[campaignId].startTimestamp = endTimestamp;

    emit EndTimestampUpdated(campaignId, oldEndTimestamp, endTimestamp);
  }

  /// @inheritdoc IKSDistributor
  function updateMetadata(bytes32 campaignId, string calldata metadata) public onlyOperator {
    string memory oldMetadata = campaigns[campaignId].metadata;
    campaigns[campaignId].metadata = metadata;

    emit MetadataUpdated(campaignId, oldMetadata, metadata);
  }
  /// @inheritdoc IKSDistributor

  function updateWhitelistedHooks(
    address[] calldata hooks,
    bytes4[] calldata selectors,
    bool grantOrRevoke
  ) public onlyOwner {
    require(hooks.length == selectors.length, InvalidLengths());
    for (uint256 i = 0; i < hooks.length; i++) {
      whitelistedHooks[hooks[i]][selectors[i]] = grantOrRevoke;

      emit WhitelistedHookUpdated(hooks[i], selectors[i], grantOrRevoke);
    }
  }

  /// @inheritdoc IKSDistributor
  function getClaimedAmountForAccount(bytes32 campaignId, address account, address token)
    public
    view
    returns (uint256)
  {
    bytes32 infoHash = keccak256(abi.encode(campaignId, account));
    return claimed[infoHash][token];
  }

  /// @inheritdoc IKSDistributor
  function getClaimedAmountForERC721(
    bytes32 campaignId,
    address erc721Addr,
    uint256 erc721Id,
    address token
  ) public view returns (uint256) {
    bytes32 infoHash = keccak256(abi.encode(campaignId, erc721Addr, erc721Id));
    return claimed[infoHash][token];
  }

  /// @inheritdoc IKSDistributor
  function claimRewardsForAccount(
    bytes32 campaignId,
    address[] calldata tokens,
    uint256[] calldata amounts,
    bytes32[] calldata proof,
    address recipient
  ) public nonReentrant whenNotPaused {
    _claimRewardsForAccount(campaignId, tokens, amounts, proof, recipient, true);
  }

  /// @inheritdoc IKSDistributor
  function claimRewardsForAccountWithHook(
    bytes32 campaignId,
    address[] calldata tokens,
    uint256[] calldata amounts,
    bytes32[] calldata proof,
    address recipient,
    address hook,
    bytes calldata hookData
  ) public nonReentrant whenNotPaused {
    _claimRewardsForAccount(campaignId, tokens, amounts, proof, recipient, true);
    _callHook(hook, hookData);
  }

  function _claimRewardsForAccount(
    bytes32 campaignId,
    address[] calldata tokens,
    uint256[] calldata amounts,
    bytes32[] calldata proof,
    address recipient,
    bool directTransfer
  ) internal onlyBetween(campaigns[campaignId].startTimestamp, campaigns[campaignId].endTimestamp) {
    require(tokens.length == amounts.length, InvalidLengths());
    _checkPendingRoot(campaignId);

    bytes32 infoHash = keccak256(abi.encode(campaignId, _msgSender()));
    bytes32 root = roots[campaignId];
    require(
      MerkleProof.verifyCalldata(
        proof, root, keccak256(bytes.concat(keccak256(abi.encode(infoHash, tokens, amounts))))
      ),
      InvalidProof()
    );

    uint256[] memory claimedAmounts = directTransfer
      ? _transferRewards(infoHash, tokens, amounts, recipient)
      : _creditRewards(infoHash, tokens, amounts, recipient);

    emit RewardsClaimedForAccount(campaignId, _msgSender(), root, tokens, claimedAmounts, recipient);
  }

  /// @inheritdoc IKSDistributor
  function claimRewardsForERC721(
    bytes32 campaignId,
    address erc721Addr,
    uint256 erc721Id,
    address[] calldata tokens,
    uint256[] calldata amounts,
    bytes32[] calldata proof,
    address recipient
  ) public nonReentrant whenNotPaused {
    _claimRewardsForERC721(
      campaignId, erc721Addr, erc721Id, tokens, amounts, proof, recipient, true
    );
  }

  /// @inheritdoc IKSDistributor
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
  ) public nonReentrant whenNotPaused {
    _claimRewardsForERC721(
      campaignId, erc721Addr, erc721Id, tokens, amounts, proof, recipient, true
    );
    _callHook(hook, hookData);
  }

  function _claimRewardsForERC721(
    bytes32 campaignId,
    address erc721Addr,
    uint256 erc721Id,
    address[] calldata tokens,
    uint256[] calldata amounts,
    bytes32[] calldata proof,
    address recipient,
    bool directTransfer
  ) internal onlyBetween(campaigns[campaignId].startTimestamp, campaigns[campaignId].endTimestamp) {
    require(tokens.length == amounts.length, InvalidLengths());
    _checkPendingRoot(campaignId);

    address msgSender = _msgSender();
    require(msgSender == IERC721(erc721Addr).ownerOf(erc721Id), UnauthorizedClaimant(msgSender));

    bytes32 infoHash = keccak256(abi.encode(campaignId, erc721Addr, erc721Id));
    bytes32 root = roots[campaignId];
    require(
      MerkleProof.verifyCalldata(
        proof, root, keccak256(bytes.concat(keccak256(abi.encode(infoHash, tokens, amounts))))
      ),
      InvalidProof()
    );

    uint256[] memory claimedAmounts = directTransfer
      ? _transferRewards(infoHash, tokens, amounts, recipient)
      : _creditRewards(infoHash, tokens, amounts, recipient);

    emit RewardsClaimedForERC721(
      campaignId, erc721Addr, erc721Id, msgSender, root, tokens, claimedAmounts, recipient
    );
  }

  /// @inheritdoc IKSDistributor
  function batchClaimRewards(bytes[] calldata datas) public nonReentrant whenNotPaused {
    _batchClaimRewards(datas);
  }

  /// @inheritdoc IKSDistributor
  function batchClaimRewardsWithHook(bytes[] calldata datas, address hook, bytes calldata hookData)
    public
    nonReentrant
    whenNotPaused
  {
    _batchClaimRewards(datas);
    _callHook(hook, hookData);
  }

  function _checkPendingRoot(bytes32 campaignId) internal {
    bytes32 pendingRoot = pendingRoots[campaignId].root;
    if (pendingRoot != bytes32(0)) {
      if (pendingRoots[campaignId].effectiveTimestamp <= block.timestamp) {
        _applyRoot(campaignId, pendingRoot);
      }
    }
  }

  function _applyRoot(bytes32 campaignId, bytes32 newRoot) internal {
    bytes32 oldRoot = roots[campaignId];
    roots[campaignId] = newRoot;
    delete pendingRoots[campaignId];

    emit RootApplied(campaignId, oldRoot, newRoot);
  }

  function _batchClaimRewards(bytes[] calldata datas) internal {
    for (uint256 i = 0; i < datas.length; i++) {
      bytes4 selector = bytes4(datas[i][:4]);
      if (selector == this.claimRewardsForAccount.selector) {
        (
          bytes32 campaignId,
          address[] calldata tokens,
          uint256[] calldata amounts,
          bytes32[] calldata proof,
          address recipient
        ) = ClaimDataDecoder.decodeClaimRewardsForAccountData(datas[i][4:]);
        _claimRewardsForAccount(campaignId, tokens, amounts, proof, recipient, false);
      } else if (selector == this.claimRewardsForERC721.selector) {
        (
          bytes32 campaignId,
          address erc721Addr,
          uint256 erc721Id,
          address[] calldata tokens,
          uint256[] calldata amounts,
          bytes32[] calldata proof,
          address recipient
        ) = ClaimDataDecoder.decodeClaimRewardsForERC721Data(datas[i][4:]);
        _claimRewardsForERC721(
          campaignId, erc721Addr, erc721Id, tokens, amounts, proof, recipient, false
        );
      } else {
        revert InvalidSelector(selector);
      }
    }

    _transferPendingRewards();
  }

  function _callHook(address hook, bytes calldata hookData) internal {
    require(hookData.length >= 4, InvalidHookData(hookData));
    bytes4 selector = bytes4(hookData[:4]);
    require(whitelistedHooks[hook][selector], NotWhitelistedHook(hook, selector));
    hook.functionCall(hookData);
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
        claimedAmounts[i] = claimable;

        IERC20(token).safeTransfer(recipient, claimable);
      }
    }
  }

  function _creditRewards(
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
        claimedAmounts[i] = claimable;

        _addPendingReward(recipient, token, claimable);
      }
    }
  }

  function _addPendingReward(address recipient, address token, uint256 amount) internal {
    if (amount == 0) {
      return;
    }

    TransientSlot.Uint256Slot amountSlot =
      PENDING_REWARDS_STORAGE.deriveMapping(recipient).deriveMapping(token).asUint256();
    uint256 previousAmount = amountSlot.tload();
    amountSlot.tstore(previousAmount + amount);

    if (previousAmount == 0) {
      TransientSlot.Uint256Slot recipientsLengthSlot = PENDING_REWARDS_STORAGE.offset(1).asUint256();
      uint256 recipientsLength = recipientsLengthSlot.tload();
      recipientsLengthSlot.tstore(recipientsLength + 1);

      bytes32 recipientsSlot = PENDING_REWARDS_STORAGE.offset(1).deriveArray();
      recipientsSlot.offset(recipientsLength).asAddress().tstore(recipient);

      bytes32 tokensSlot = PENDING_REWARDS_STORAGE.offset(2).deriveArray();
      tokensSlot.offset(recipientsLength).asAddress().tstore(token);
    }
  }

  function _transferPendingRewards() internal {
    TransientSlot.Uint256Slot recipientsLengthSlot = PENDING_REWARDS_STORAGE.offset(1).asUint256();
    uint256 recipientsLength = recipientsLengthSlot.tload();
    recipientsLengthSlot.tstore(0);

    bytes32 recipientsSlot = PENDING_REWARDS_STORAGE.offset(1).deriveArray();
    bytes32 tokensSlot = PENDING_REWARDS_STORAGE.offset(2).deriveArray();

    for (uint256 i = 0; i < recipientsLength; i++) {
      address recipient = recipientsSlot.offset(i).asAddress().tload();
      address token = tokensSlot.offset(i).asAddress().tload();

      TransientSlot.Uint256Slot amountSlot =
        PENDING_REWARDS_STORAGE.deriveMapping(recipient).deriveMapping(token).asUint256();
      uint256 amount = amountSlot.tload();
      amountSlot.tstore(0);

      if (amount > 0) {
        IERC20(token).safeTransfer(recipient, amount);
      }
    }
  }
}
