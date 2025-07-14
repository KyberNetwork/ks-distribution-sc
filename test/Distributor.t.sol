// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './harnesses/KSDistributorHarness.sol';

import './mocks/ERC721Mock.sol';
import {SwapMock} from './mocks/SwapMock.sol';
import './utils/MerkleUtils.sol';

import 'forge-std/Test.sol';

import 'openzeppelin-contracts/contracts/access/IAccessControl.sol';
import 'openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol';

contract KSDistributorTest is Test {
  using MerkleUtils for bytes32[];
  using TokenHelper for address;

  enum RevertType {
    ANY_REASON,
    INVALID_PROOF,
    TOO_EARLY,
    TOO_LATE,
    INVALID_LENGTHS,
    NOT_WHITELISTED_HOOK,
    INVALID_HOOK_DATA
  }

  uint256 public constant MAX_CAMPAIGN_SIZE = 20;
  uint256 public constant MAX_TIME_DURATION = 1 days;

  KSDistributorHarness public distributor;

  address public token0;
  address public token1;
  ERC721Mock public nft0;
  ERC721Mock public nft1;
  address swapHook;

  address public admin = makeAddr('admin');
  address public operator = makeAddr('operator');
  address public guardian = makeAddr('guardian');
  address public randomCaller = makeAddr('randomCaller');

  mapping(address => mapping(address => uint256)) public pendingRewards;

  function setUp() public {
    vm.warp(1e18);
    _setUpKSDistributor();
    _setUpTokens();
    _setUpLabels();
  }

  function testOnlyOperatorCanCreateCampaign() public {
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        randomCaller,
        KSRoles.OPERATOR_ROLE
      )
    );
    uint256 startTimestamp = block.timestamp + bound(0, 100, MAX_TIME_DURATION);
    uint256 endTimestamp = startTimestamp + bound(0, 1 hours, MAX_TIME_DURATION);
    string memory metadata = 'metadata';

    vm.prank(randomCaller);

    distributor.createCampaign(startTimestamp, endTimestamp, metadata, bytes32(0));
  }

  function testCreateCampaignTooLateShouldRevert() public {
    vm.expectRevert(IKSDistributor.TooLate.selector);
    uint256 startTimestamp = block.timestamp - bound(100, 1 hours, MAX_TIME_DURATION);
    uint256 endTimestamp = startTimestamp - 100;
    string memory metadata = 'metadata';
    vm.prank(operator);

    distributor.createCampaign(startTimestamp, endTimestamp, metadata, bytes32(0));
  }

  function testCreateCampaignWithTooShortDurationShouldRevert() public {
    vm.expectRevert(IKSDistributor.TooShortDuration.selector);
    uint256 startTimestamp = block.timestamp + bound(0, 100, MAX_TIME_DURATION);
    uint256 endTimestamp = startTimestamp + 0.5 hours;
    string memory metadata = 'metadata';
    vm.prank(operator);

    distributor.createCampaign(startTimestamp, endTimestamp, metadata, bytes32(0));
  }

  function testCreateCampaignExactMinDuration() public {
    uint256 startTimestamp = block.timestamp + bound(0, 100, MAX_TIME_DURATION);
    uint256 endTimestamp = startTimestamp + 1 hours;
    string memory metadata = 'metadata';
    vm.startPrank(operator);

    distributor.createCampaign(startTimestamp, endTimestamp, metadata, bytes32(0));
  }

  function testCreateCampaignAlreadyExist() public {
    uint256 startTimestamp = block.timestamp + bound(0, 100, MAX_TIME_DURATION);
    uint256 endTimestamp = startTimestamp + 1 hours;
    string memory metadata = 'metadata';

    vm.startPrank(operator);

    bytes32 _campaignId =
      distributor.createCampaign(startTimestamp, endTimestamp, metadata, bytes32(0));

    vm.startPrank(operator);
    vm.expectRevert(
      abi.encodeWithSelector(IKSDistributor.CampaignAlreadyExists.selector, _campaignId)
    );
    distributor.createCampaign(startTimestamp, endTimestamp, metadata, bytes32(0));
  }

  function testCreateCampaignShouldEmitsEvent() public {
    vm.expectEmit(false, false, false, false, address(distributor));
    emit IKSDistributor.CampaignCreated(0, 0, 0, '');
    _createCampaign(100);
  }

  function testSubmitRootForNonExistentCampaignShouldRevert() public {
    vm.expectRevert();
    vm.prank(operator);
    distributor.submitRoot(0, 0, 0);
  }

  function testOnlyOperatorCanSubmitRoot() public {
    (bytes32 campaignId,) = _createCampaign(100);
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        randomCaller,
        KSRoles.OPERATOR_ROLE
      )
    );
    vm.prank(randomCaller);
    distributor.submitRoot(campaignId, 0, 0);
  }

  function testSubmitRootTooLateShouldRevert() public {
    (bytes32 campaignId, IKSDistributor.Campaign memory campaign) = _createCampaign(100);
    vm.warp(campaign.endTimestamp - distributor.defaultTimeLock());
    vm.expectRevert(IKSDistributor.InvalidEffectiveTimestamp.selector);
    vm.prank(operator);
    distributor.submitRoot(campaignId, 0, 0);
  }

  function testSubmitRootShouldEmitsEvent() public {
    (bytes32 campaignId, IKSDistributor.Campaign memory campaign) = _createCampaign(100);
    vm.startPrank(operator);
    (, bytes32 root) = _setUpRewards(campaignId, 1000 ether, 10, nft0, false);
    vm.expectEmit(address(distributor));
    emit IKSDistributor.RootSubmitted(
      campaignId, root, block.timestamp + distributor.defaultTimeLock()
    );
    distributor.submitRoot(campaignId, root, 0);

    (, bytes32 newRoot) = _setUpRewards(campaignId, 2000 ether, 10, nft0, false);
    vm.expectEmit(address(distributor));
    emit IKSDistributor.RootSubmitted(campaignId, newRoot, campaign.endTimestamp - 1);
    distributor.submitRoot(campaignId, newRoot, campaign.endTimestamp - 1);
  }

  function testOnlyOperatorCanUpdateStartTimestamp() public {
    (bytes32 campaignId,) = _createCampaign(100);
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        randomCaller,
        KSRoles.OPERATOR_ROLE
      )
    );
    vm.prank(randomCaller);
    distributor.updateStartTimestamp(campaignId, 0);
  }

  function testUpdateStartTimestampShouldEmitsEvent() public {
    (bytes32 campaignId, IKSDistributor.Campaign memory campaign) = _createCampaign(100);
    vm.startPrank(operator);
    vm.expectEmit(address(distributor));
    emit IKSDistributor.StartTimestampUpdated(campaignId, campaign.startTimestamp, 0);
    distributor.updateStartTimestamp(campaignId, 0);
  }

  function testOnlyOperatorCanUpdateEndTimestamp() public {
    (bytes32 campaignId,) = _createCampaign(100);
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        randomCaller,
        KSRoles.OPERATOR_ROLE
      )
    );
    vm.prank(randomCaller);
    distributor.updateEndTimestamp(campaignId, 0);
  }

  function testUpdateEndTimestampShouldEmitsEvent() public {
    (bytes32 campaignId, IKSDistributor.Campaign memory campaign) = _createCampaign(100);
    uint256 newEndTimestamp = campaign.startTimestamp + 2 hours; // Valid end timestamp
    vm.startPrank(operator);
    vm.expectEmit(address(distributor));
    emit IKSDistributor.EndTimestampUpdated(campaignId, campaign.endTimestamp, newEndTimestamp);
    distributor.updateEndTimestamp(campaignId, newEndTimestamp);
  }

  function testOnlyOperatorCanUpdateMetadata() public {
    (bytes32 campaignId,) = _createCampaign(100);
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        randomCaller,
        KSRoles.OPERATOR_ROLE
      )
    );
    vm.prank(randomCaller);
    distributor.updateMetadata(campaignId, 'newMetadata');
  }

  function testUpdateMetadataShouldEmitsEvent() public {
    (bytes32 campaignId,) = _createCampaign(100);
    vm.startPrank(operator);
    vm.expectEmit(address(distributor));
    emit IKSDistributor.MetadataUpdated(campaignId, 'metadata', 'newMetaData');
    distributor.updateMetadata(campaignId, 'newMetaData');
  }

  function testOnlyAdminCanUpdateWhitelistedHooks() public {
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        randomCaller,
        distributor.DEFAULT_ADMIN_ROLE()
      )
    );
    vm.prank(randomCaller);
    address[] memory hooks = new address[](1);
    bytes4[] memory selectors = new bytes4[](1);
    hooks[0] = makeAddr('hook');
    distributor.updateWhitelistedHooks(hooks, selectors, true);
  }

  function testUpdateWhitelistedHooksShouldEmitsEvent(bool grantOrRevoke) public {
    vm.startPrank(admin);
    address[] memory hooks = new address[](2);
    bytes4[] memory selectors = new bytes4[](2);
    hooks[0] = makeAddr('hook0');
    hooks[1] = makeAddr('hook1');
    selectors[0] = SwapMock.swap.selector;
    selectors[1] = SwapMock.batch.selector;
    vm.expectEmit(true, false, false, true, address(distributor));
    emit IKSDistributor.WhitelistedHookUpdated(hooks[0], selectors[0], grantOrRevoke);
    vm.expectEmit(true, false, false, true, address(distributor));
    emit IKSDistributor.WhitelistedHookUpdated(hooks[1], selectors[1], grantOrRevoke);
    distributor.updateWhitelistedHooks(hooks, selectors, grantOrRevoke);
    for (uint256 i = 0; i < hooks.length; i++) {
      assertEq(distributor.whitelistedHooks(hooks[i], selectors[i]), grantOrRevoke);
    }
  }

  function testClaimWithHook(uint256 seed, uint256 size) public {
    size = bound(size, 1, MAX_CAMPAIGN_SIZE);
    uint256 amountSeed = bound(seed, 100, type(uint112).max);
    (bytes32 campaignId, IKSDistributor.Campaign memory campaign) = _createCampaign(seed);
    (bytes32[] memory leaves,) = _setUpRewards(campaignId, amountSeed, size, nft0);
    vm.warp(campaign.startTimestamp + distributor.defaultTimeLock());
    _claimAndVerifyRewards(campaignId, amountSeed, leaves, nft0, true);
  }

  function testClaimNotWhitelistedHook(uint256 seed, uint256 size, bool validData) public {
    size = bound(size, 1, MAX_CAMPAIGN_SIZE);
    uint256 amountSeed = bound(seed, 100, type(uint112).max);
    (bytes32 campaignId, IKSDistributor.Campaign memory campaign) = _createCampaign(seed);
    (bytes32[] memory leaves,) = _setUpRewards(campaignId, amountSeed, size, nft0);
    vm.warp(campaign.startTimestamp + distributor.defaultTimeLock());
    _claimRewardsWithRevert(
      campaignId,
      amountSeed,
      leaves,
      nft0,
      validData ? RevertType.NOT_WHITELISTED_HOOK : RevertType.INVALID_HOOK_DATA
    );
  }

  function testClaimShouldFollowTheMerkleDistribution(uint256 seed, uint256 size) public {
    size = bound(size, 1, MAX_CAMPAIGN_SIZE);
    uint256 amountSeed = bound(seed, 100, type(uint112).max);
    (bytes32 campaignId, IKSDistributor.Campaign memory campaign) = _createCampaign(seed);
    (bytes32[] memory leaves,) = _setUpRewards(campaignId, amountSeed, size, nft0);
    vm.warp(campaign.startTimestamp + distributor.defaultTimeLock() + 1);
    _claimAndVerifyRewards(campaignId, amountSeed, leaves, nft0, false);
    vm.warp(campaign.startTimestamp + distributor.defaultTimeLock() + 10);
    (leaves,) = _setUpRewards(campaignId, amountSeed * 2, size, nft0);
    vm.warp(block.timestamp + distributor.defaultTimeLock());
    _claimAndVerifyRewards(campaignId, amountSeed * 2, leaves, nft0, false);
  }

  function testOnlyERC721OwnerCanClaimRewardsForERC721() public {
    uint256 seed = 1e18;
    uint256 size = 10;
    (bytes32 campaignId, IKSDistributor.Campaign memory campaign) = _createCampaign(seed);
    (bytes32[] memory leaves,) = _setUpRewards(campaignId, seed, size, nft0);
    vm.warp(campaign.startTimestamp + 1);

    uint256 i = 1;
    address recipient = vm.addr(i * i + 1);
    (address[] memory tokens, uint256[] memory amounts) = _getTokensAndAmounts(seed, i);

    bytes32[] memory proof = leaves.getProof(i);
    uint256 erc721Id = _getErc721Id(campaignId, i);
    vm.expectRevert(
      abi.encodeWithSelector(IKSDistributor.UnauthorizedClaimant.selector, randomCaller)
    );
    vm.prank(randomCaller);
    distributor.claimRewardsForERC721(
      campaignId, address(nft0), erc721Id, tokens, amounts, proof, recipient
    );
  }

  function testClaimWithMisconfiguredRootShouldRevert(uint256 seed, uint256 size) public {
    size = bound(size, 1, MAX_CAMPAIGN_SIZE);
    uint256 amountSeed = bound(seed, 100, type(uint112).max);
    (bytes32 campaignId, IKSDistributor.Campaign memory campaign) = _createCampaign(seed);
    (bytes32[] memory leaves,) = _setUpRewards(campaignId, amountSeed, size, nft0);
    vm.warp(campaign.startTimestamp + distributor.defaultTimeLock() + 1);
    _claimAndVerifyRewards(campaignId, amountSeed, leaves, nft0, false);
    vm.warp(campaign.startTimestamp + distributor.defaultTimeLock() + 10);
    (leaves,) = _setUpRewards(campaignId, amountSeed / 2, size, nft0);
    vm.warp(block.timestamp + distributor.defaultTimeLock());
    _claimRewardsWithRevert(campaignId, amountSeed / 2, leaves, nft0, RevertType.ANY_REASON);
  }

  function testClaimWithInvalidProofShouldRevert() public {
    uint256 seed = 1e18;
    uint256 size = 10;
    (bytes32 campaignId, IKSDistributor.Campaign memory campaign) = _createCampaign(seed);
    (bytes32[] memory leaves,) = _setUpRewards(campaignId, seed, size, nft0);
    vm.warp(campaign.startTimestamp + 1);
    _claimRewardsWithRevert(campaignId, seed, leaves, nft0, RevertType.INVALID_PROOF);
  }

  function testClaimTooEarlyShouldRevert() public {
    uint256 seed = 1e18;
    uint256 size = 10;
    (bytes32 campaignId, IKSDistributor.Campaign memory campaign) = _createCampaign(seed);
    (bytes32[] memory leaves,) = _setUpRewards(campaignId, seed, size, nft0);
    vm.warp(campaign.startTimestamp - 1);
    _claimRewardsWithRevert(campaignId, seed, leaves, nft0, RevertType.TOO_EARLY);
  }

  function testClaimTooLateShouldRevert() public {
    uint256 seed = 1e18;
    uint256 size = 10;
    (bytes32 campaignId, IKSDistributor.Campaign memory campaign) = _createCampaign(seed);
    (bytes32[] memory leaves,) = _setUpRewards(campaignId, seed, size, nft0);
    vm.warp(campaign.endTimestamp + 1);
    _claimRewardsWithRevert(campaignId, seed, leaves, nft0, RevertType.TOO_LATE);
  }

  function testClaimWithInvalidLengthsShouldRevert() public {
    uint256 seed = 1e18;
    uint256 size = 10;
    (bytes32 campaignId, IKSDistributor.Campaign memory campaign) = _createCampaign(seed);
    (bytes32[] memory leaves,) = _setUpRewards(campaignId, seed, size, nft0);
    vm.warp(campaign.startTimestamp + 1);
    _claimRewardsWithRevert(campaignId, seed, leaves, nft0, RevertType.INVALID_LENGTHS);
  }

  function testClaimWithEmptyArrayShouldRevert() public {
    uint256 seed = 1e18;
    uint256 size = 10;
    (bytes32 campaignId, IKSDistributor.Campaign memory campaign) = _createCampaign(seed);
    (bytes32[] memory leaves,) = _setUpRewards(campaignId, seed, size, nft0);

    vm.warp(campaign.startTimestamp + 1);
    for (uint256 i = 0; i < size; i++) {
      address account = vm.addr(i + 1);
      address recipient = vm.addr(i * i + 1);
      bytes32[] memory proof = leaves.getProof(i);
      address[] memory tokens = new address[](0);
      uint256[] memory amounts = new uint256[](0);

      if (i & 1 == 0) {
        vm.expectRevert(IKSDistributor.InvalidProof.selector);
        distributor.claimRewardsForAccount(campaignId, tokens, amounts, proof, recipient);
      } else {
        uint256 erc721Id = _getErc721Id(campaignId, i);

        vm.prank(account);
        vm.expectRevert(IKSDistributor.InvalidProof.selector);
        distributor.claimRewardsForERC721(
          campaignId, address(nft0), erc721Id, tokens, amounts, proof, recipient
        );
      }
    }
  }

  function testClaimInvalidCampaignIdShouldRevert() public {
    uint256 seed = 1e18;
    uint256 size = 10;
    (bytes32 campaignId, IKSDistributor.Campaign memory campaign) = _createCampaign(seed);
    (bytes32[] memory leaves,) = _setUpRewards(campaignId, seed, size, nft0);
    vm.warp(campaign.startTimestamp + 1);
    _claimRewardsWithRevert('', seed, leaves, nft0, RevertType.TOO_LATE);
  }

  function testClaimHaveYetToEffectShouldRevert(uint256 seed, uint256 size) public {
    size = bound(size, 1, MAX_CAMPAIGN_SIZE);
    uint256 amountSeed = bound(seed, 100, type(uint112).max);
    (bytes32 campaignId, IKSDistributor.Campaign memory campaign) = _createCampaign(seed);
    (bytes32[] memory leaves,) = _setUpRewards(campaignId, amountSeed, size, nft0);
    vm.warp(campaign.startTimestamp + distributor.defaultTimeLock() + 1);
    _claimAndVerifyRewards(campaignId, amountSeed, leaves, nft0, false);
    vm.warp(campaign.startTimestamp + distributor.defaultTimeLock() + 10);
    (leaves,) = _setUpRewards(campaignId, amountSeed * 2, size, nft0);
    vm.warp(block.timestamp + 1);
    _claimRewardsWithRevert(campaignId, amountSeed * 2, leaves, nft0, RevertType.ANY_REASON);
  }

  function testClaimPendingRootCanceledShouldRevert(uint256 seed, uint256 size) public {
    size = bound(size, 1, MAX_CAMPAIGN_SIZE);
    uint256 amountSeed = bound(seed, 100, type(uint112).max);
    (bytes32 campaignId, IKSDistributor.Campaign memory campaign) = _createCampaign(seed);
    (bytes32[] memory leaves,) = _setUpRewards(campaignId, amountSeed, size, nft0);
    vm.warp(campaign.startTimestamp + distributor.defaultTimeLock() + 1);
    _claimAndVerifyRewards(campaignId, amountSeed, leaves, nft0, false);
    vm.warp(campaign.startTimestamp + distributor.defaultTimeLock() + 10);

    (leaves,) = _setUpRewards(campaignId, amountSeed * 2, size, nft0);
    vm.warp(block.timestamp + distributor.defaultTimeLock());
    vm.prank(admin);
    distributor.forceUpdateRoot(campaignId, bytes32(0));
    _claimRewardsWithRevert(campaignId, amountSeed * 2, leaves, nft0, RevertType.ANY_REASON);
  }

  function testClaimWithERC721AdminChanged() public {
    uint256 seed = 1e18;
    uint256 size = 10;
    (bytes32 campaignId, IKSDistributor.Campaign memory campaign) = _createCampaign(seed);
    (bytes32[] memory leaves,) = _setUpRewards(campaignId, seed, size, nft0);

    vm.warp(campaign.startTimestamp + 1);
    for (uint256 i = 0; i < size; i++) {
      if (i & 1 == 0) continue;

      address account = vm.addr(i + 1);
      address newAccount = vm.addr(99);
      address recipient = vm.addr(i * i + 1);
      (address[] memory tokens, uint256[] memory amounts) = _getTokensAndAmounts(seed, i);

      bytes32[] memory proof = leaves.getProof(i);
      uint256 erc721Id = _getErc721Id(campaignId, i);

      vm.prank(account);
      nft0.safeTransferFrom(account, newAccount, erc721Id);

      vm.prank(account);
      vm.expectRevert(abi.encodeWithSelector(IKSDistributor.UnauthorizedClaimant.selector, account));
      distributor.claimRewardsForERC721(
        campaignId, address(nft0), erc721Id, tokens, amounts, proof, recipient
      );

      vm.prank(newAccount);
      distributor.claimRewardsForERC721(
        campaignId, address(nft0), erc721Id, tokens, amounts, proof, recipient
      );
    }
  }

  function testBatchClaimWithHook(
    uint256 seed0,
    uint256 seed1,
    uint256 size0,
    uint256 size1,
    uint256 seed2
  ) public {
    vm.assume(seed0 != seed1);

    size0 = bound(size0, 2, MAX_CAMPAIGN_SIZE);
    size1 = bound(size1, 2, MAX_CAMPAIGN_SIZE);
    uint256 amountSeed0 = bound(seed0, 100, type(uint112).max);
    uint256 amountSeed1 = bound(seed1, 100, type(uint112).max);

    (bytes32 campaignId0, IKSDistributor.Campaign memory campaign0) = _createCampaign(seed0);
    (bytes32[] memory leaves0,) = _setUpRewards(campaignId0, amountSeed0, size0, nft0);
    // Make two campaigns have common time interval
    bytes32 campaignId1;
    IKSDistributor.Campaign memory campaign1;
    {
      campaign1.startTimestamp = campaign0.startTimestamp;
      campaign1.endTimestamp = campaign0.endTimestamp;
      campaign1.metadata = 'metadata1';
      vm.prank(operator);
      campaignId1 = distributor.createCampaign(
        campaign1.startTimestamp, campaign1.endTimestamp, campaign1.metadata, bytes32(uint256(1))
      );
    }
    (bytes32[] memory leaves1,) = _setUpRewards(campaignId1, amountSeed1, size1, nft1);

    bytes[] memory datas = new bytes[](4);
    address account = vm.addr(1);
    {
      bytes32[] memory proof = leaves0.getProof(0);
      (address[] memory tokens, uint256[] memory amounts) = _getTokensAndAmounts(amountSeed0, 0);
      datas[0] = abi.encodeCall(
        IKSDistributor.claimRewardsForAccount, (campaignId0, tokens, amounts, proof, account)
      );
    }
    {
      bytes32[] memory proof = leaves1.getProof(0);
      (address[] memory tokens, uint256[] memory amounts) = _getTokensAndAmounts(amountSeed1, 0);
      datas[1] = abi.encodeCall(
        IKSDistributor.claimRewardsForAccount, (campaignId1, tokens, amounts, proof, account)
      );
    }
    {
      uint256 erc721Id = _getErc721Id(campaignId0, 1);
      vm.prank(vm.addr(2));
      nft0.transferFrom(vm.addr(2), account, erc721Id);
      bytes32[] memory proof = leaves0.getProof(1);
      (address[] memory tokens, uint256[] memory amounts) = _getTokensAndAmounts(amountSeed0, 1);
      datas[2] = abi.encodeCall(
        IKSDistributor.claimRewardsForERC721,
        (campaignId0, address(nft0), erc721Id, tokens, amounts, proof, account)
      );
    }
    {
      uint256 erc721Id = _getErc721Id(campaignId1, 1);
      vm.prank(vm.addr(2));
      nft1.transferFrom(vm.addr(2), account, erc721Id);
      bytes32[] memory proof = leaves1.getProof(1);
      (address[] memory tokens, uint256[] memory amounts) = _getTokensAndAmounts(amountSeed1, 1);
      datas[3] = abi.encodeCall(
        IKSDistributor.claimRewardsForERC721,
        (campaignId1, address(nft1), erc721Id, tokens, amounts, proof, account)
      );
    }

    vm.warp(campaign0.startTimestamp + distributor.defaultTimeLock());
    vm.prank(account);
    if (seed2 % 4 == 0) {
      distributor.batchClaimRewards(datas);
    } else if (seed2 % 4 == 1) {
      distributor.batchClaimRewardsWithHook(
        datas, swapHook, abi.encodeWithSelector(SwapMock.batch.selector)
      );
      assertEq(SwapMock(payable(swapHook)).batchExecuted(), true);
    } else if (seed2 % 4 == 2) {
      address hook = makeAddr('hook');
      bytes memory hookData = abi.encodeWithSelector(SwapMock.batch.selector);
      vm.expectRevert(
        abi.encodeWithSelector(
          IKSDistributor.NotWhitelistedHook.selector, hook, SwapMock.batch.selector
        )
      );
      distributor.batchClaimRewardsWithHook(datas, hook, hookData);
    } else {
      vm.expectRevert(abi.encodeWithSelector(IKSDistributor.InvalidHookData.selector, ''));
      distributor.batchClaimRewardsWithHook(datas, address(0), '');
    }
  }

  function testBatchClaimMixedValidAndInvalid(
    uint256 seed0,
    uint256 seed1,
    uint256 size0,
    uint256 size1
  ) public {
    vm.assume(seed0 != seed1);

    size0 = bound(size0, 2, MAX_CAMPAIGN_SIZE);
    size1 = bound(size1, 2, MAX_CAMPAIGN_SIZE);
    uint256 amountSeed0 = bound(seed0, 100, type(uint112).max);
    uint256 amountSeed1 = bound(seed1, 100, type(uint112).max);

    (bytes32 campaignId0, IKSDistributor.Campaign memory campaign0) = _createCampaign(seed0);
    (bytes32[] memory leaves0,) = _setUpRewards(campaignId0, amountSeed0, size0, nft0);
    // Make two campaigns have common time interval
    bytes32 campaignId1;
    IKSDistributor.Campaign memory campaign1;
    {
      campaign1.startTimestamp = campaign0.startTimestamp;
      campaign1.endTimestamp = campaign0.endTimestamp;
      campaign1.metadata = 'metadata1';
      vm.prank(operator);
      campaignId1 = distributor.createCampaign(
        campaign1.startTimestamp, campaign1.endTimestamp, campaign1.metadata, bytes32(uint256(1))
      );
    }
    (bytes32[] memory leaves1,) = _setUpRewards(campaignId1, amountSeed1, size1, nft1);

    bytes[] memory datas = new bytes[](4);
    address account = vm.addr(1);
    {
      bytes32[] memory proof = leaves0.getProof(0);
      (address[] memory tokens, uint256[] memory amounts) = _getTokensAndAmounts(amountSeed0, 0);
      datas[0] = abi.encodeCall(
        IKSDistributor.claimRewardsForAccount, (campaignId0, tokens, amounts, proof, account)
      );
    }

    //invalid claim
    {
      bytes32[] memory proof = leaves1.getProof(0);
      address[] memory tokens = new address[](0);
      uint256[] memory amounts = new uint256[](0);
      datas[1] = abi.encodeCall(
        IKSDistributor.claimRewardsForAccount, (campaignId1, tokens, amounts, proof, account)
      );
    }
    {
      uint256 erc721Id = _getErc721Id(campaignId0, 1);
      vm.prank(vm.addr(2));
      nft0.transferFrom(vm.addr(2), account, erc721Id);
      bytes32[] memory proof = leaves0.getProof(1);
      (address[] memory tokens, uint256[] memory amounts) = _getTokensAndAmounts(amountSeed0, 1);
      datas[2] = abi.encodeCall(
        IKSDistributor.claimRewardsForERC721,
        (campaignId0, address(nft0), erc721Id, tokens, amounts, proof, account)
      );
    }
    {
      uint256 erc721Id = _getErc721Id(campaignId1, 1);
      vm.prank(vm.addr(2));
      nft1.transferFrom(vm.addr(2), account, erc721Id);
      bytes32[] memory proof = leaves1.getProof(1);
      address[] memory tokens = new address[](0);
      uint256[] memory amounts = new uint256[](0);
      datas[3] = abi.encodeCall(
        IKSDistributor.claimRewardsForERC721,
        (campaignId1, address(nft1), erc721Id, tokens, amounts, proof, account)
      );
    }

    vm.warp(campaign0.startTimestamp);
    vm.prank(account);
    vm.expectRevert(IKSDistributor.InvalidProof.selector);
    distributor.batchClaimRewards(datas);
  }

  function testFullflow(uint256 seed, uint256 size) public {
    size = bound(size, 1, MAX_CAMPAIGN_SIZE);
    uint256 amountSeed = bound(seed, 100, type(uint112).max);
    (bytes32 campaignId, IKSDistributor.Campaign memory campaign) = _createCampaign(seed);
    (bytes32[] memory leaves,) = _setUpRewards(campaignId, amountSeed, size, nft0);

    uint256 latestTime = campaign.startTimestamp + distributor.defaultTimeLock() + 1;
    for (uint256 i = 0; i < size; i++) {
      latestTime =
        bound(seed, latestTime, campaign.endTimestamp - distributor.defaultTimeLock() - 1);
      vm.warp(latestTime);

      address account = vm.addr(i + 1);
      address recipient = vm.addr(i * i + 1);
      (address[] memory tokens, uint256[] memory amounts) = _getTokensAndAmounts(amountSeed, i);

      bytes32[] memory proof = leaves.getProof(i);
      if (i & 1 == 0) {
        vm.prank(account);
        distributor.claimRewardsForAccount(campaignId, tokens, amounts, proof, recipient);
      } else {
        uint256 erc721Id = _getErc721Id(campaignId, i);
        vm.prank(account);
        distributor.claimRewardsForERC721(
          campaignId, address(nft0), erc721Id, tokens, amounts, proof, recipient
        );
      }

      for (uint256 j = 0; j < tokens.length; j++) {
        assertEq(tokens[j].balanceOf(recipient), amounts[j]);
      }
    }

    //update root for another distribution
    amountSeed = amountSeed * 2;
    (leaves,) = _setUpRewards(campaignId, amountSeed, size, nft0);
    latestTime += distributor.defaultTimeLock();

    for (uint256 i = 0; i < size; i++) {
      latestTime = bound(seed, latestTime, campaign.endTimestamp - 1);
      vm.warp(latestTime);

      address account = vm.addr(i + 1);
      address recipient = vm.addr(i * i + 1);
      (address[] memory tokens, uint256[] memory amounts) = _getTokensAndAmounts(amountSeed, i);

      bytes32[] memory proof = leaves.getProof(i);
      if (i & 1 == 0) {
        vm.prank(account);
        distributor.claimRewardsForAccount(campaignId, tokens, amounts, proof, recipient);
      } else {
        uint256 erc721Id = _getErc721Id(campaignId, i);
        vm.prank(account);
        distributor.claimRewardsForERC721(
          campaignId, address(nft0), erc721Id, tokens, amounts, proof, recipient
        );
      }

      for (uint256 j = 0; j < tokens.length; j++) {
        assertEq(tokens[j].balanceOf(recipient), amounts[j]);
      }
    }

    vm.warp(campaign.endTimestamp);
    for (uint256 i = 0; i < size; i++) {
      address account = vm.addr(i + 1);
      address recipient = vm.addr(i * i + 1);
      (address[] memory tokens, uint256[] memory amounts) = _getTokensAndAmounts(amountSeed, i);

      bytes32[] memory proof = leaves.getProof(i);
      if (i & 1 == 0) {
        vm.prank(account);
        vm.expectRevert(IKSDistributor.TooLate.selector);
        distributor.claimRewardsForAccount(campaignId, tokens, amounts, proof, recipient);
      } else {
        uint256 erc721Id = _getErc721Id(campaignId, i);
        vm.prank(account);
        vm.expectRevert(IKSDistributor.TooLate.selector);
        distributor.claimRewardsForERC721(
          campaignId, address(nft0), erc721Id, tokens, amounts, proof, recipient
        );
      }
    }
  }

  function testPendingRewards(uint256[20] memory seeds) public {
    address[] memory tokens = new address[](3);
    for (uint256 i = 0; i < tokens.length; i++) {
      tokens[i] = address(new ERC20Mock());
      ERC20Mock(tokens[i]).mint(address(distributor), type(uint128).max);
    }

    for (uint256 i = 0; i < seeds.length; i++) {
      uint256 amount = bound(seeds[i], 0, 1e18);
      address recipient = vm.addr(bound(seeds[i] >> 128, 1, 3));
      address token = tokens[bound(uint128(seeds[i]), 0, 2)];
      distributor.addPendingReward(recipient, token, amount);
      pendingRewards[recipient][token] += amount;
    }

    distributor.transferPendingRewards();

    for (uint256 i = 1; i <= 3; i++) {
      address recipient = vm.addr(i);
      for (uint256 j = 0; j <= 2; j++) {
        address token = tokens[j];
        assertEq(token.balanceOf(recipient), pendingRewards[recipient][token]);
      }
    }
  }

  function _setUpKSDistributor() internal {
    address[] memory initialOperators = new address[](1);
    initialOperators[0] = operator;
    address[] memory initialGuardians = new address[](1);
    initialGuardians[0] = guardian;

    swapHook = address(new SwapMock());
    address[] memory hooks = new address[](2);
    bytes4[] memory selectors = new bytes4[](2);
    hooks[0] = swapHook;
    hooks[1] = swapHook;
    selectors[0] = SwapMock.batch.selector;
    selectors[1] = SwapMock.swap.selector;

    distributor =
      new KSDistributorHarness(admin, initialOperators, initialGuardians, hooks, selectors, 3 hours);
  }

  function _setUpHooks() internal {
    swapHook = address(new SwapMock());
    address[] memory hooks = new address[](2);
    bytes4[] memory selectors = new bytes4[](2);
    hooks[0] = swapHook;
    hooks[1] = swapHook;
    selectors[0] = SwapMock.batch.selector;
    selectors[1] = SwapMock.swap.selector;
    vm.prank(admin);
    distributor.updateWhitelistedHooks(hooks, selectors, true);
  }

  function _setUpTokens() internal {
    token0 = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    token1 = address(new ERC20Mock());
    nft0 = new ERC721Mock();
    nft1 = new ERC721Mock();
    deal(address(distributor), type(uint128).max);
    deal(token1, address(distributor), type(uint128).max);
  }

  function _setUpLabels() internal {
    vm.label(address(distributor), 'distributor');
    vm.label(address(token0), 'token0');
    vm.label(address(token1), 'token1');
    vm.label(address(nft0), 'nft0');
    vm.label(address(nft1), 'nft1');
  }

  function _createCampaign(uint256 seed)
    internal
    returns (bytes32 campaignId, KSDistributor.Campaign memory campaign)
  {
    campaign.startTimestamp = block.timestamp + bound(seed, 100, MAX_TIME_DURATION);
    campaign.endTimestamp = campaign.startTimestamp + bound(seed, 1 days, MAX_TIME_DURATION);
    campaign.metadata = 'metadata';
    vm.prank(operator);
    campaignId = distributor.createCampaign(
      campaign.startTimestamp, campaign.endTimestamp, campaign.metadata, bytes32(0)
    );
  }

  function _setUpRewards(
    bytes32 campaignId,
    uint256 amountSeed,
    uint256 size,
    ERC721Mock nft,
    bool doUpdate
  ) internal returns (bytes32[] memory leaves, bytes32 root) {
    leaves = new bytes32[](size);
    for (uint256 i = 0; i < size; i++) {
      bytes32 infoHash;
      address account = vm.addr(i + 1);
      if (i & 1 == 0) {
        infoHash = keccak256(abi.encode(campaignId, account));
      } else {
        uint256 erc721Id = _getErc721Id(campaignId, i);
        infoHash = keccak256(abi.encode(campaignId, nft, erc721Id));
        try nft.mint(account, erc721Id) {} catch {}
      }

      (address[] memory tokens, uint256[] memory amounts) = _getTokensAndAmounts(amountSeed, i);
      leaves[i] = keccak256(bytes.concat(keccak256(abi.encode(infoHash, tokens, amounts))));
    }

    root = leaves.getRoot();
    if (doUpdate) {
      vm.prank(operator);
      distributor.submitRoot(campaignId, root, 0);
    }
  }

  function _setUpRewards(bytes32 campaignId, uint256 amountSeed, uint256 size, ERC721Mock nft)
    internal
    returns (bytes32[] memory leaves, bytes32 root)
  {
    return _setUpRewards(campaignId, amountSeed, size, nft, true);
  }

  function _claimRewardsWithRevert(
    bytes32 campaignId,
    uint256 amountSeed,
    bytes32[] memory leaves,
    ERC721Mock nft,
    RevertType revertType
  ) internal {
    uint256 size = leaves.length;

    for (uint256 i = 0; i < size; i++) {
      address account = vm.addr(i + 1);
      address recipient = vm.addr(i * i + 1);
      (address[] memory tokens, uint256[] memory amounts) = _getTokensAndAmounts(amountSeed, i);

      bytes32[] memory proof = leaves.getProof(i);
      if (i & 1 == 0) {
        if (revertType == RevertType.ANY_REASON) {
          vm.expectRevert();
          distributor.claimRewardsForAccount(campaignId, tokens, amounts, proof, recipient);
          continue;
        } else if (revertType == RevertType.INVALID_PROOF) {
          proof = new bytes32[](proof.length);
          vm.expectRevert(IKSDistributor.InvalidProof.selector);
          distributor.claimRewardsForAccount(campaignId, tokens, amounts, proof, recipient);
          continue;
        } else if (revertType == RevertType.INVALID_LENGTHS) {
          vm.expectRevert(IKSDistributor.InvalidLengths.selector);
          distributor.claimRewardsForAccount(campaignId, tokens, new uint256[](3), proof, recipient);
          continue;
        } else if (revertType == RevertType.NOT_WHITELISTED_HOOK) {
          address hook = makeAddr('hook');
          bytes memory hookData = abi.encodeWithSelector(SwapMock.swap.selector, tokens, recipient);
          vm.expectRevert(
            abi.encodeWithSelector(
              IKSDistributor.NotWhitelistedHook.selector, hook, SwapMock.swap.selector
            )
          );
          vm.prank(account);
          distributor.claimRewardsForAccountWithHook(
            campaignId, tokens, amounts, proof, recipient, hook, hookData
          );
        } else if (revertType == RevertType.INVALID_HOOK_DATA) {
          address hook = makeAddr('hook');
          vm.expectRevert(abi.encodeWithSelector(IKSDistributor.InvalidHookData.selector, ''));
          vm.prank(account);
          distributor.claimRewardsForAccountWithHook(
            campaignId, tokens, amounts, proof, recipient, hook, ''
          );
        } else {
          vm.expectRevert(
            revertType == RevertType.TOO_EARLY
              ? IKSDistributor.TooEarly.selector
              : IKSDistributor.TooLate.selector
          );
          distributor.claimRewardsForAccount(campaignId, tokens, amounts, proof, recipient);
          continue;
        }
      } else {
        uint256 erc721Id = _getErc721Id(campaignId, i);
        if (revertType == RevertType.ANY_REASON) {
          vm.expectRevert();
          vm.prank(account);
          distributor.claimRewardsForERC721(
            campaignId, address(nft), erc721Id, tokens, amounts, proof, recipient
          );
          continue;
        } else if (revertType == RevertType.INVALID_PROOF) {
          proof = new bytes32[](proof.length);
          vm.expectRevert(IKSDistributor.InvalidProof.selector);
          vm.prank(account);
          distributor.claimRewardsForERC721(
            campaignId, address(nft), erc721Id, tokens, amounts, proof, recipient
          );
          continue;
        } else if (revertType == RevertType.INVALID_LENGTHS) {
          vm.expectRevert(IKSDistributor.InvalidLengths.selector);
          vm.prank(account);
          distributor.claimRewardsForERC721(
            campaignId, address(nft), erc721Id, tokens, new uint256[](3), proof, recipient
          );
          continue;
        } else if (revertType == RevertType.NOT_WHITELISTED_HOOK) {
          address hook = makeAddr('hook');
          bytes memory hookData = abi.encodeWithSelector(SwapMock.swap.selector, tokens, recipient);
          vm.expectRevert(
            abi.encodeWithSelector(
              IKSDistributor.NotWhitelistedHook.selector, hook, SwapMock.swap.selector
            )
          );
          vm.prank(account);
          distributor.claimRewardsForERC721WithHook(
            campaignId, address(nft), erc721Id, tokens, amounts, proof, recipient, hook, hookData
          );
        } else if (revertType == RevertType.INVALID_HOOK_DATA) {
          address hook = makeAddr('hook');
          vm.expectRevert(abi.encodeWithSelector(IKSDistributor.InvalidHookData.selector, ''));
          vm.prank(account);
          distributor.claimRewardsForERC721WithHook(
            campaignId, address(nft), erc721Id, tokens, amounts, proof, recipient, hook, ''
          );
        } else {
          vm.expectRevert(
            revertType == RevertType.TOO_EARLY
              ? IKSDistributor.TooEarly.selector
              : IKSDistributor.TooLate.selector
          );
          vm.prank(account);
          distributor.claimRewardsForERC721(
            campaignId, address(nft), erc721Id, tokens, amounts, proof, recipient
          );
          continue;
        }
      }
    }
  }

  function _claimAndVerifyRewards(
    bytes32 campaignId,
    uint256 amountSeed,
    bytes32[] memory leaves,
    ERC721Mock nft,
    bool withHook
  ) internal {
    uint256 size = leaves.length;

    for (uint256 i = 0; i < size; i++) {
      address account = vm.addr(i + 1);
      address recipient = vm.addr(i * i + 1);
      (address[] memory tokens, uint256[] memory amounts) = _getTokensAndAmounts(amountSeed, i);

      bytes32[] memory proof = leaves.getProof(i);
      if (i & 1 == 0) {
        uint256[] memory claimable =
          _verifyClaimedAmountsForAccount(campaignId, account, tokens, amounts, recipient);
        vm.prank(account);
        vm.expectEmit(address(distributor));

        if (withHook) {
          emit IKSDistributor.RewardsClaimedForAccount(
            campaignId, account, leaves.getRoot(), tokens, claimable, swapHook
          );
          distributor.claimRewardsForAccountWithHook(
            campaignId,
            tokens,
            amounts,
            proof,
            swapHook,
            swapHook,
            abi.encodeWithSelector(SwapMock.swap.selector, tokens, recipient)
          );
          assertEq(swapHook.balanceOf(recipient), amounts[0]);
        } else {
          emit IKSDistributor.RewardsClaimedForAccount(
            campaignId, account, leaves.getRoot(), tokens, claimable, recipient
          );
          distributor.claimRewardsForAccount(campaignId, tokens, amounts, proof, recipient);
        }
        _verifyClaimedAmountsForAccount(campaignId, account, tokens, amounts, recipient);
      } else {
        uint256 erc721Id = _getErc721Id(campaignId, i);
        uint256[] memory claimable = _verifyClaimedAmountsForERC721(
          campaignId, address(nft), erc721Id, tokens, amounts, recipient
        );
        vm.prank(account);
        vm.expectEmit(address(distributor));

        if (withHook) {
          emit IKSDistributor.RewardsClaimedForERC721(
            campaignId,
            address(nft),
            erc721Id,
            account,
            leaves.getRoot(),
            tokens,
            claimable,
            swapHook
          );
          distributor.claimRewardsForERC721WithHook(
            campaignId,
            address(nft),
            erc721Id,
            tokens,
            amounts,
            proof,
            swapHook,
            swapHook,
            abi.encodeWithSelector(SwapMock.swap.selector, tokens, recipient)
          );
          assertEq(swapHook.balanceOf(recipient), amounts[0]);
        } else {
          emit IKSDistributor.RewardsClaimedForERC721(
            campaignId,
            address(nft),
            erc721Id,
            account,
            leaves.getRoot(),
            tokens,
            claimable,
            recipient
          );
          distributor.claimRewardsForERC721(
            campaignId, address(nft), erc721Id, tokens, amounts, proof, recipient
          );
        }

        _verifyClaimedAmountsForERC721(
          campaignId, address(nft), erc721Id, tokens, amounts, recipient
        );
      }

      // avoid stack too deep
      recipient = vm.addr(i * i + 1);
      for (uint256 j = 0; j < tokens.length; j++) {
        assertEq(tokens[j].balanceOf(recipient), amounts[j]);
      }
    }
  }

  function _getErc721Id(bytes32 campaignId, uint256 i) internal pure returns (uint256) {
    return uint256(keccak256(abi.encode(campaignId, i)));
  }

  function _getTokensAndAmounts(uint256 amountSeed, uint256 i)
    internal
    view
    returns (address[] memory tokens, uint256[] memory amounts)
  {
    if (i % 3 == 0) {
      tokens = new address[](1);
      tokens[0] = address(token0);
      amounts = new uint256[](1);
      amounts[0] = amountSeed / (i + 1);
    } else if (i % 3 == 1) {
      tokens = new address[](1);
      tokens[0] = address(token1);
      amounts = new uint256[](1);
      amounts[0] = amountSeed / (i + 1);
    } else {
      tokens = new address[](2);
      tokens[0] = address(token0);
      tokens[1] = address(token1);
      amounts = new uint256[](2);
      amounts[0] = amountSeed / (i + 1);
      amounts[1] = amountSeed / (i + 1);
    }
  }

  function _verifyClaimedAmountsForAccount(
    bytes32 campaignId,
    address account,
    address[] memory tokens,
    uint256[] memory amounts,
    address recipient
  ) internal view returns (uint256[] memory claimable) {
    claimable = new uint256[](tokens.length);
    for (uint256 i = 0; i < tokens.length; i++) {
      claimable[i] =
        amounts[i] - distributor.getClaimedAmountForAccount(campaignId, account, tokens[i]);
      assertEq(amounts[i] - claimable[i], tokens[i].balanceOf(recipient));
    }
  }

  function _verifyClaimedAmountsForERC721(
    bytes32 campaignId,
    address erc721Addr,
    uint256 erc721Id,
    address[] memory tokens,
    uint256[] memory amounts,
    address recipient
  ) internal view returns (uint256[] memory claimable) {
    claimable = new uint256[](tokens.length);
    for (uint256 i = 0; i < tokens.length; i++) {
      claimable[i] = amounts[i]
        - distributor.getClaimedAmountForERC721(campaignId, erc721Addr, erc721Id, tokens[i]);
      assertEq(amounts[i] - claimable[i], tokens[i].balanceOf(recipient));
    }
  }

  function testUpdateStartTimestampForNonExistentCampaignShouldRevert() public {
    bytes32 nonExistentCampaignId = bytes32(uint256(0x123456789));
    uint256 newStartTimestamp = block.timestamp + 1 days;

    vm.prank(operator);
    vm.expectRevert(
      abi.encodeWithSelector(IKSDistributor.CampaignDoesNotExist.selector, nonExistentCampaignId)
    );
    distributor.updateStartTimestamp(nonExistentCampaignId, newStartTimestamp);
  }

  function testUpdateEndTimestampForNonExistentCampaignShouldRevert() public {
    bytes32 nonExistentCampaignId = bytes32(uint256(0x987654321));
    uint256 newEndTimestamp = block.timestamp + 2 days;

    vm.prank(operator);
    vm.expectRevert(
      abi.encodeWithSelector(IKSDistributor.CampaignDoesNotExist.selector, nonExistentCampaignId)
    );
    distributor.updateEndTimestamp(nonExistentCampaignId, newEndTimestamp);
  }

  function testUpdateMetadataForNonExistentCampaignShouldRevert() public {
    bytes32 nonExistentCampaignId = bytes32(uint256(0xabcdef123));
    string memory newMetadata = 'updated metadata';

    vm.prank(operator);
    vm.expectRevert(
      abi.encodeWithSelector(IKSDistributor.CampaignDoesNotExist.selector, nonExistentCampaignId)
    );
    distributor.updateMetadata(nonExistentCampaignId, newMetadata);
  }

  function testUpdateCampaignDetailsForExistingCampaignShouldSucceed() public {
    (bytes32 campaignId, IKSDistributor.Campaign memory campaign) = _createCampaign(123);

    // Test update start timestamp
    uint256 newStartTimestamp = block.timestamp + 2 hours;
    vm.prank(operator);
    vm.expectEmit(true, false, false, true);
    emit IKSDistributor.StartTimestampUpdated(
      campaignId, campaign.startTimestamp, newStartTimestamp
    );
    distributor.updateStartTimestamp(campaignId, newStartTimestamp);
    (uint256 actualStartTimestamp,,) = distributor.campaigns(campaignId);
    assertEq(actualStartTimestamp, newStartTimestamp);

    // Test update end timestamp
    uint256 newEndTimestamp = block.timestamp + 3 days;
    vm.prank(operator);
    vm.expectEmit(true, false, false, true);
    emit IKSDistributor.EndTimestampUpdated(campaignId, campaign.endTimestamp, newEndTimestamp);
    distributor.updateEndTimestamp(campaignId, newEndTimestamp);
    (, uint256 actualEndTimestamp,) = distributor.campaigns(campaignId);
    assertEq(actualEndTimestamp, newEndTimestamp);

    // Test update metadata
    string memory newMetadata = 'completely new metadata';
    vm.prank(operator);
    vm.expectEmit(true, false, false, true);
    emit IKSDistributor.MetadataUpdated(campaignId, 'metadata', newMetadata);
    distributor.updateMetadata(campaignId, newMetadata);
    (,, string memory actualMetadata) = distributor.campaigns(campaignId);
    assertEq(actualMetadata, newMetadata);
  }
}
