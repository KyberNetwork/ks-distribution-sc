// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.28;

import {IKSDistributor} from './interfaces/IKSDistributor.sol';
import {ClaimDataDecoder} from './libraries/ClaimDataDecoder.sol';

import {ManagementBase} from 'ks-common-sc/src/base/ManagementBase.sol';
import {ManagementPausable} from 'ks-common-sc/src/base/ManagementPausable.sol';
import {ManagementRescuable} from 'ks-common-sc/src/base/ManagementRescuable.sol';

import {KSRoles} from 'ks-common-sc/src/libraries/KSRoles.sol';
import {TokenHelper} from 'ks-common-sc/src/libraries/token/TokenHelper.sol';

import {Address} from 'openzeppelin-contracts/contracts/utils/Address.sol';
import {ReentrancyGuardTransient} from
  'openzeppelin-contracts/contracts/utils/ReentrancyGuardTransient.sol';
import {SlotDerivation} from 'openzeppelin-contracts/contracts/utils/SlotDerivation.sol';
import {TransientSlot} from 'openzeppelin-contracts/contracts/utils/TransientSlot.sol';
import {MerkleProof} from 'openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol';

import {IERC721} from 'openzeppelin-contracts/contracts/token/ERC721/IERC721.sol';

contract KSDistributor is
  IKSDistributor,
  ReentrancyGuardTransient,
  ManagementPausable,
  ManagementRescuable
{
  using TokenHelper for address;
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

  modifier campaignExists(bytes32 campaignId) {
    require(campaigns[campaignId].startTimestamp != 0, CampaignDoesNotExist(campaignId));
    _;
  }

  constructor(
    address initialAdmin,
    address[] memory initialOperators,
    address[] memory initialGuardians,
    address[] memory initialRescuers,
    address[] memory initialWhitelistedHooks,
    bytes4[] memory initialWhitelistedSelectors,
    uint256 initDefaultTimeLock
  ) ManagementBase(0, initialAdmin) {
    _batchGrantRole(KSRoles.OPERATOR_ROLE, initialOperators);
    _batchGrantRole(KSRoles.GUARDIAN_ROLE, initialGuardians);
    _batchGrantRole(KSRoles.RESCUER_ROLE, initialRescuers);

    _updateWhitelistedHooks(initialWhitelistedHooks, initialWhitelistedSelectors, true);
    _updateDefaultTimeLock(initDefaultTimeLock);
  }

  receive() external payable {}

  /// @inheritdoc IKSDistributor
  function updateDefaultTimeLock(uint256 newDefaultTimeLock) public onlyRole(DEFAULT_ADMIN_ROLE) {
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
  )
    public
    onlyRole(KSRoles.OPERATOR_ROLE)
    onlyBefore(initEndTimestamp)
    returns (bytes32 campaignId)
  {
    require(initStartTimestamp + MIN_CAMPAIGN_DURATION <= initEndTimestamp, TooShortDuration());
    campaignId = keccak256(abi.encode(initStartTimestamp, initEndTimestamp, initMetadata, salt));
    require(campaigns[campaignId].startTimestamp == 0, CampaignAlreadyExists(campaignId));
    campaigns[campaignId] = Campaign(initStartTimestamp, initEndTimestamp, initMetadata);

    emit CampaignCreated(campaignId, initStartTimestamp, initEndTimestamp, initMetadata);
  }

  /// @inheritdoc IKSDistributor
  function submitRoot(bytes32 campaignId, bytes32 newRoot, uint256 effectiveTimestamp)
    public
    onlyRole(KSRoles.OPERATOR_ROLE)
    campaignExists(campaignId)
  {
    if (effectiveTimestamp == 0) {
      effectiveTimestamp = block.timestamp + defaultTimeLock;
    }
    require(
      effectiveTimestamp >= block.timestamp + defaultTimeLock
        && effectiveTimestamp < campaigns[campaignId].endTimestamp,
      InvalidEffectiveTimestamp()
    );
    _getLatestRoot(campaignId);
    pendingRoots[campaignId] = PendingRoot(newRoot, effectiveTimestamp);

    emit RootSubmitted(campaignId, newRoot, effectiveTimestamp);
  }

  /// @inheritdoc IKSDistributor
  function forceUpdateRoot(bytes32 campaignId, bytes32 newRoot)
    public
    onlyRole(DEFAULT_ADMIN_ROLE)
    campaignExists(campaignId)
  {
    _applyRoot(campaignId, newRoot);
  }

  /// @inheritdoc IKSDistributor
  function updateStartTimestamp(bytes32 campaignId, uint256 startTimestamp)
    public
    onlyRole(KSRoles.OPERATOR_ROLE)
    campaignExists(campaignId)
  {
    require(
      startTimestamp + MIN_CAMPAIGN_DURATION <= campaigns[campaignId].endTimestamp,
      TooShortDuration()
    );
    uint256 oldStartTimestamp = campaigns[campaignId].startTimestamp;
    campaigns[campaignId].startTimestamp = startTimestamp;

    emit StartTimestampUpdated(campaignId, oldStartTimestamp, startTimestamp);
  }

  /// @inheritdoc IKSDistributor
  function updateEndTimestamp(bytes32 campaignId, uint256 endTimestamp)
    public
    onlyRole(KSRoles.OPERATOR_ROLE)
    campaignExists(campaignId)
  {
    require(
      campaigns[campaignId].startTimestamp + MIN_CAMPAIGN_DURATION <= endTimestamp,
      TooShortDuration()
    );
    uint256 oldEndTimestamp = campaigns[campaignId].endTimestamp;
    campaigns[campaignId].endTimestamp = endTimestamp;

    emit EndTimestampUpdated(campaignId, oldEndTimestamp, endTimestamp);
  }

  /// @inheritdoc IKSDistributor
  function updateMetadata(bytes32 campaignId, string calldata metadata)
    public
    onlyRole(KSRoles.OPERATOR_ROLE)
    campaignExists(campaignId)
  {
    string memory oldMetadata = campaigns[campaignId].metadata;
    campaigns[campaignId].metadata = metadata;

    emit MetadataUpdated(campaignId, oldMetadata, metadata);
  }

  /// @inheritdoc IKSDistributor
  function updateWhitelistedHooks(
    address[] calldata hooks,
    bytes4[] calldata selectors,
    bool grantOrRevoke
  ) public onlyRole(DEFAULT_ADMIN_ROLE) {
    _updateWhitelistedHooks(hooks, selectors, grantOrRevoke);
  }

  function _updateWhitelistedHooks(
    address[] memory hooks,
    bytes4[] memory selectors,
    bool grantOrRevoke
  ) internal {
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

    bytes32 root = _getLatestRoot(campaignId);
    bytes32 infoHash = keccak256(abi.encode(campaignId, msg.sender));
    require(
      MerkleProof.verifyCalldata(
        proof, root, keccak256(bytes.concat(keccak256(abi.encode(infoHash, tokens, amounts))))
      ),
      InvalidProof()
    );

    uint256[] memory claimedAmounts = directTransfer
      ? _transferRewards(infoHash, tokens, amounts, recipient)
      : _creditRewards(infoHash, tokens, amounts, recipient);

    emit RewardsClaimedForAccount(campaignId, msg.sender, root, tokens, claimedAmounts, recipient);
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

    bytes32 root = _getLatestRoot(campaignId);
    require(msg.sender == IERC721(erc721Addr).ownerOf(erc721Id), UnauthorizedClaimant(msg.sender));

    bytes32 infoHash = keccak256(abi.encode(campaignId, erc721Addr, erc721Id));
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
      campaignId, erc721Addr, erc721Id, msg.sender, root, tokens, claimedAmounts, recipient
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

  function _getLatestRoot(bytes32 campaignId) internal returns (bytes32) {
    bytes32 pendingRoot = pendingRoots[campaignId].root;
    if (pendingRoot != bytes32(0)) {
      if (pendingRoots[campaignId].effectiveTimestamp <= block.timestamp) {
        _applyRoot(campaignId, pendingRoot);

        return pendingRoot;
      }
    }

    return roots[campaignId];
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

        token.safeTransfer(recipient, claimable);
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
        token.safeTransfer(recipient, amount);
      }
    }
  }
}
