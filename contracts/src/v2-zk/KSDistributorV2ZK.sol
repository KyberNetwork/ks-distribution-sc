// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.28;

import '../interfaces/IKSDistributorV2ZK.sol';

import {ClaimDataDecoderV2ZK} from '../libraries/ClaimDataDecoderV2ZK.sol';
import {IOptimismPortal2, OpSteelLibrary, Steel} from '../libraries/OpSteelLibrary.sol';

import {ImageID} from './ImageID.sol';

import {Management} from 'ks-common-sc/base/Management.sol';
import {Rescuable} from 'ks-common-sc/base/Rescuable.sol';
import {KSRoles} from 'ks-common-sc/libraries/KSRoles.sol';
import {TokenHelper} from 'ks-common-sc/libraries/token/TokenHelper.sol';

import {Address} from 'openzeppelin-contracts/contracts/utils/Address.sol';
import {ReentrancyGuard} from 'openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol';

import {SlotDerivation} from 'openzeppelin-contracts/contracts/utils/SlotDerivation.sol';
import {TransientSlot} from 'openzeppelin-contracts/contracts/utils/TransientSlot.sol';

import {MerkleProof} from 'openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol';
import {SignatureChecker} from
  'openzeppelin-contracts/contracts/utils/cryptography/SignatureChecker.sol';

import {IERC721} from 'openzeppelin-contracts/contracts/token/ERC721/IERC721.sol';

import {IRiscZeroVerifier} from 'risc0/IRiscZeroVerifier.sol';

contract KSDistributorV2ZK is IKSDistributorV2ZK, ReentrancyGuard, Management, Rescuable {
  using Address for address;
  using SlotDerivation for bytes32;
  using TransientSlot for *;
  using TokenHelper for address;

  struct Journal {
    Steel.Commitment commitment;
    address tokenAddress;
    uint256 tokenId;
    address account;
  }

  uint256 public constant MIN_CAMPAIGN_DURATION = 1 hours;

  // keccak256(abi.encode(uint256(keccak256('ks-distributor.storage.PendingRewards')) - 1)) & ~bytes32(uint256(0xff))
  bytes32 internal constant PENDING_REWARDS_STORAGE =
    0x667c036918e8dbe38a4ec9003830d89d321fbfffacba5bdecb14c1bbca99be00;

  IRiscZeroVerifier public immutable verifier;

  /// @notice The L2 portal proxy address for each chain
  mapping(uint256 chainId => address portalProxy) internal portalProxies;

  /// @inheritdoc IKSDistributorV2ZKState
  uint256 public defaultTimeLock;

  /// @inheritdoc IKSDistributorV2ZKState
  mapping(bytes32 campaignId => Campaign) public campaigns;

  /// @inheritdoc IKSDistributorV2ZKState
  mapping(bytes32 campaignId => bytes32) public roots;

  /// @inheritdoc IKSDistributorV2ZKState
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

  modifier validateRewardsInfo(RewardsInfo calldata rewardsInfo) {
    require(rewardsInfo.tokens.length == rewardsInfo.amounts.length, InvalidLengths());
    _;
  }

  modifier callHook(address hook, bytes calldata hookData) {
    _;
    if (hook != address(0)) {
      require(hookData.length >= 4, InvalidHookData(hookData));
      bytes4 selector = bytes4(hookData);
      require(whitelistedHooks[hook][selector], NotWhitelistedHook(hook, selector));
      hook.functionCall(hookData);
    }
  }

  constructor(
    address initialAdmin,
    address[] memory initialOperators,
    address[] memory initialGuardians,
    address initVerifier,
    uint256[] memory initChainIds,
    address[] memory initPortalProxies,
    uint256 initDefaultTimeLock
  ) Management(initialAdmin) {
    for (uint256 i = 0; i < initialOperators.length; i++) {
      _grantRole(KSRoles.OPERATOR_ROLE, initialOperators[i]);
    }
    for (uint256 i = 0; i < initialGuardians.length; i++) {
      _grantRole(KSRoles.GUARDIAN_ROLE, initialGuardians[i]);
    }

    verifier = IRiscZeroVerifier(initVerifier);

    for (uint256 i = 0; i < initChainIds.length; i++) {
      _updatePortalProxy(initChainIds[i], initPortalProxies[i]);
    }

    _updateDefaultTimeLock(initDefaultTimeLock);
  }

  /// @inheritdoc IKSDistributorV2ZKAdmin
  function updatePortalProxy(uint256 chainId, address newPortalProxy)
    public
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    _updatePortalProxy(chainId, newPortalProxy);
  }

  function _updatePortalProxy(uint256 chainId, address newPortalProxy) internal {
    address oldPortalProxy = portalProxies[chainId];
    portalProxies[chainId] = newPortalProxy;

    emit PortalProxyUpdated(chainId, oldPortalProxy, newPortalProxy);
  }

  /// @inheritdoc IKSDistributorV2ZKAdmin
  function updateDefaultTimeLock(uint256 newDefaultTimeLock) public onlyRole(DEFAULT_ADMIN_ROLE) {
    _updateDefaultTimeLock(newDefaultTimeLock);
  }

  function _updateDefaultTimeLock(uint256 newDefaultTimeLock) internal {
    uint256 oldDefaultTimeLock = defaultTimeLock;
    defaultTimeLock = newDefaultTimeLock;

    emit DefaultTimeLockUpdated(oldDefaultTimeLock, newDefaultTimeLock);
  }

  /// @inheritdoc IKSDistributorV2ZKOperations
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

  /// @inheritdoc IKSDistributorV2ZKOperations
  function submitRoot(bytes32 campaignId, bytes32 newRoot, uint256 effectiveTimestamp)
    public
    onlyRole(KSRoles.OPERATOR_ROLE)
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

  /// @inheritdoc IKSDistributorV2ZKAdmin
  function forceUpdateRoot(bytes32 campaignId, bytes32 newRoot) public onlyRole(DEFAULT_ADMIN_ROLE) {
    _applyRoot(campaignId, newRoot);
  }

  /// @inheritdoc IKSDistributorV2ZKOperations
  function updateStartTimestamp(bytes32 campaignId, uint256 startTimestamp)
    public
    onlyRole(KSRoles.OPERATOR_ROLE)
  {
    uint256 oldStartTimestamp = campaigns[campaignId].startTimestamp;
    campaigns[campaignId].startTimestamp = startTimestamp;

    emit StartTimestampUpdated(campaignId, oldStartTimestamp, startTimestamp);
  }

  /// @inheritdoc IKSDistributorV2ZKOperations
  function updateEndTimestamp(bytes32 campaignId, uint256 endTimestamp)
    public
    onlyRole(KSRoles.OPERATOR_ROLE)
  {
    uint256 oldEndTimestamp = campaigns[campaignId].endTimestamp;
    campaigns[campaignId].startTimestamp = endTimestamp;

    emit EndTimestampUpdated(campaignId, oldEndTimestamp, endTimestamp);
  }

  /// @inheritdoc IKSDistributorV2ZKOperations
  function updateMetadata(bytes32 campaignId, string calldata metadata)
    public
    onlyRole(KSRoles.OPERATOR_ROLE)
  {
    string memory oldMetadata = campaigns[campaignId].metadata;
    campaigns[campaignId].metadata = metadata;

    emit MetadataUpdated(campaignId, oldMetadata, metadata);
  }

  /// @inheritdoc IKSDistributorV2ZKAdmin
  function updateWhitelistedHooks(
    address[] calldata hooks,
    bytes4[] calldata selectors,
    bool grantOrRevoke
  ) public onlyRole(DEFAULT_ADMIN_ROLE) {
    require(hooks.length == selectors.length, InvalidLengths());
    for (uint256 i = 0; i < hooks.length; i++) {
      whitelistedHooks[hooks[i]][selectors[i]] = grantOrRevoke;

      emit WhitelistedHookUpdated(hooks[i], selectors[i], grantOrRevoke);
    }
  }

  /// @inheritdoc IKSDistributorV2ZKState
  function getClaimedAmountForAccount(bytes32 campaignId, address account, address token)
    public
    view
    returns (uint256)
  {
    bytes32 infoHash = keccak256(abi.encode(campaignId, account));
    return claimed[infoHash][token];
  }

  /// @inheritdoc IKSDistributorV2ZKState
  function getClaimedAmountForERC721(
    bytes32 campaignId,
    ERC721Info calldata erc721Info,
    address token
  ) public view returns (uint256) {
    bytes32 infoHash = keccak256(abi.encode(campaignId, erc721Info));
    return claimed[infoHash][token];
  }

  /// @inheritdoc IKSDistributorV2ZKActions
  function claimRewardsForAccount(
    bytes32 campaignId,
    RewardsInfo calldata rewardsInfo,
    bytes32[] calldata proof,
    address recipient,
    address hook,
    bytes calldata hookData
  ) public nonReentrant whenNotPaused callHook(hook, hookData) {
    _claimRewardsForAccount(campaignId, rewardsInfo, proof, recipient, true);
  }

  function _claimRewardsForAccount(
    bytes32 campaignId,
    RewardsInfo calldata rewardsInfo,
    bytes32[] calldata proof,
    address recipient,
    bool directTransfer
  )
    internal
    onlyBetween(campaigns[campaignId].startTimestamp, campaigns[campaignId].endTimestamp)
    validateRewardsInfo(rewardsInfo)
  {
    _checkPendingRoot(campaignId);

    bytes32 infoHash = keccak256(abi.encode(campaignId, _msgSender()));
    bytes32 leafHash = keccak256(bytes.concat(keccak256(abi.encode(infoHash, rewardsInfo))));
    bytes32 root = roots[campaignId];
    require(MerkleProof.verifyCalldata(proof, root, leafHash), InvalidProof());

    uint256[] memory claimedAmounts = directTransfer
      ? _transferRewards(infoHash, rewardsInfo, recipient)
      : _creditRewards(infoHash, rewardsInfo, recipient);

    emit RewardsClaimedForAccount(
      campaignId, _msgSender(), root, rewardsInfo.tokens, claimedAmounts, recipient
    );
  }

  /// @inheritdoc IKSDistributorV2ZKActions
  function claimRewardsForERC721(
    bytes32 campaignId,
    ERC721Info calldata erc721Info,
    ZKProof calldata zkProof,
    RewardsInfo calldata rewardsInfo,
    bytes32[] calldata proof,
    address recipient,
    address hook,
    bytes calldata hookData
  ) public nonReentrant whenNotPaused callHook(hook, hookData) {
    _claimRewardsForERC721(campaignId, erc721Info, zkProof, rewardsInfo, proof, recipient, true);
  }

  function _claimRewardsForERC721(
    bytes32 campaignId,
    ERC721Info calldata erc721Info,
    ZKProof calldata zkProof,
    RewardsInfo calldata rewardsInfo,
    bytes32[] calldata proof,
    address recipient,
    bool directTransfer
  )
    internal
    onlyBetween(campaigns[campaignId].startTimestamp, campaigns[campaignId].endTimestamp)
    validateRewardsInfo(rewardsInfo)
  {
    _checkPendingRoot(campaignId);

    _verifyZKProof(erc721Info, zkProof);

    bytes32 infoHash = keccak256(abi.encode(campaignId, erc721Info));
    bytes32 leafHash = keccak256(bytes.concat(keccak256(abi.encode(infoHash, rewardsInfo))));
    bytes32 root = roots[campaignId];
    require(MerkleProof.verifyCalldata(proof, root, leafHash), InvalidProof());

    uint256[] memory claimedAmounts = directTransfer
      ? _transferRewards(infoHash, rewardsInfo, recipient)
      : _creditRewards(infoHash, rewardsInfo, recipient);

    emit RewardsClaimedForERC721(
      campaignId, erc721Info, _msgSender(), root, rewardsInfo.tokens, claimedAmounts, recipient
    );
  }

  function _verifyZKProof(ERC721Info calldata erc721Info, ZKProof calldata zkProof) internal view {
    Journal memory journal = Journal({
      commitment: zkProof.commitment,
      tokenAddress: erc721Info.erc721Addr,
      tokenId: erc721Info.erc721Id,
      account: _msgSender()
    });

    IOptimismPortal2 portal = IOptimismPortal2(portalProxies[erc721Info.chainId]);
    require(OpSteelLibrary.validateCommitment(portal, zkProof.commitment), InvalidCommitment());

    verifier.verify(zkProof.seal, ImageID.NFT_OWNERSHIP_ID, sha256(abi.encode(journal)));
  }

  /// @inheritdoc IKSDistributorV2ZKActions
  function batchClaimRewards(bytes[] calldata datas, address hook, bytes calldata hookData)
    public
    nonReentrant
    whenNotPaused
    callHook(hook, hookData)
  {
    _batchClaimRewards(datas);
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
          RewardsInfo calldata rewardsInfo,
          bytes32[] calldata proof,
          address recipient
        ) = ClaimDataDecoderV2ZK.decodeClaimRewardsForAccountData(datas[i][4:]);
        _claimRewardsForAccount(campaignId, rewardsInfo, proof, recipient, false);
      } else if (selector == this.claimRewardsForERC721.selector) {
        (
          bytes32 campaignId,
          ERC721Info calldata erc721Info,
          ZKProof calldata zkProof,
          RewardsInfo calldata rewardsInfo,
          bytes32[] calldata proof,
          address recipient
        ) = ClaimDataDecoderV2ZK.decodeClaimRewardsForERC721Data(datas[i][4:]);
        _claimRewardsForERC721(
          campaignId, erc721Info, zkProof, rewardsInfo, proof, recipient, false
        );
      } else {
        revert InvalidSelector(selector);
      }
    }

    _transferPendingRewards();
  }

  /// @notice Transfers the rewards to the recipient
  function _transferRewards(bytes32 infoHash, RewardsInfo calldata rewardsInfo, address recipient)
    internal
    returns (uint256[] memory claimedAmounts)
  {
    address[] calldata tokens = rewardsInfo.tokens;
    uint256[] calldata amounts = rewardsInfo.amounts;

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

  function _creditRewards(bytes32 infoHash, RewardsInfo calldata rewardsInfo, address recipient)
    internal
    returns (uint256[] memory claimedAmounts)
  {
    address[] calldata tokens = rewardsInfo.tokens;
    uint256[] calldata amounts = rewardsInfo.amounts;

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
