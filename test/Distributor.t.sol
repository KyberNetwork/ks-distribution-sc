// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'src/KSDistributor.sol';

import {ERC721Mock} from './mocks/ERC721Mock.sol';
import './utils/MerkleUtils.sol';

import 'forge-std/Test.sol';
import {ERC20Mock} from 'openzeppelin-contracts/mocks/token/ERC20Mock.sol';

contract KSDistributorTest is Test {
  using MerkleUtils for bytes32[];

  enum RevertType {
    ANY_REASON,
    INVALID_PROOF,
    TOO_EARLY,
    TOO_LATE,
    INVALID_LENGTHS
  }

  uint256 public constant MAX_CAMPAIGN_SIZE = 20;
  uint256 public constant MAX_TIME_DURATION = 1 days;

  KSDistributor public distributor;

  ERC20Mock public token0;
  ERC20Mock public token1;
  ERC721Mock public nft0;
  ERC721Mock public nft1;

  address public owner = makeAddr('owner');
  address public operator = makeAddr('operator');
  address public guardian = makeAddr('guardian');
  address public randomCaller = makeAddr('randomCaller');

  function setUp() public {
    vm.warp(1e18);
    _setUpKSDistributor();
    _setUpTokens();
    _setUpLabels();
  }

  function testOnlyOperatorCanCreateCampaign() public {
    vm.expectPartialRevert(KyberSwapRole.KSRoleNotOperator.selector);
    uint256 startTimestamp = block.timestamp + bound(0, 100, MAX_TIME_DURATION);
    uint256 endTimestamp = startTimestamp + bound(0, 1 hours, MAX_TIME_DURATION);
    string memory metadata = 'metadata';
    vm.prank(randomCaller);
    distributor.createCampaign(startTimestamp, endTimestamp, metadata);
  }

  function testCreateCampaignTooLateShouldRevert() public {
    vm.expectRevert(IKSDistributor.TooLate.selector);
    uint256 startTimestamp = block.timestamp - 100;
    uint256 endTimestamp = startTimestamp + bound(0, 1 hours, MAX_TIME_DURATION);
    string memory metadata = 'metadata';
    vm.prank(operator);
    distributor.createCampaign(startTimestamp, endTimestamp, metadata);
  }

  function testCreateCampaignWithTooShortDurationShouldRevert() public {
    vm.expectRevert(IKSDistributor.TooShortDuration.selector);
    uint256 startTimestamp = block.timestamp + bound(0, 100, MAX_TIME_DURATION);
    uint256 endTimestamp = startTimestamp + 0.5 hours;
    string memory metadata = 'metadata';
    vm.prank(operator);
    distributor.createCampaign(startTimestamp, endTimestamp, metadata);
  }

  function testCreateCampaignShouldEmitsEvent() public {
    vm.expectEmit(false, false, false, false, address(distributor));
    emit IKSDistributor.CampaignCreated(0, 0, 0, '');
    _createCampaign(100);
  }

  function testUpdateRootForNonExistentCampaignShouldRevert() public {
    vm.expectRevert();
    vm.prank(operator);
    distributor.updateRoot(0, 0);
  }

  function testOnlyOperatorCanUpdateRoot() public {
    (bytes32 campaignId,) = _createCampaign(100);
    vm.expectPartialRevert(KyberSwapRole.KSRoleNotOperator.selector);
    vm.prank(randomCaller);
    distributor.updateRoot(campaignId, 0);
  }

  function testUpdateRootTooLateShouldRevert() public {
    (bytes32 campaignId, IKSDistributor.Campaign memory campaign) = _createCampaign(100);
    vm.expectRevert(IKSDistributor.TooLate.selector);
    vm.warp(campaign.endTimestamp + 1);
    vm.prank(operator);
    distributor.updateRoot(campaignId, 0);
  }

  function testUpdateRootShouldEmitsEvent() public {
    (bytes32 campaignId,) = _createCampaign(100);
    vm.startPrank(operator);
    (, bytes32 root) = _setUpRewards(campaignId, 1000 ether, 10, nft0, false);
    vm.expectEmit(address(distributor));
    emit IKSDistributor.RootUpdated(campaignId, 0, root);
    distributor.updateRoot(campaignId, root);

    (, bytes32 newRoot) = _setUpRewards(campaignId, 2000 ether, 10, nft0, false);
    vm.expectEmit(address(distributor));
    emit IKSDistributor.RootUpdated(campaignId, root, newRoot);
    distributor.updateRoot(campaignId, newRoot);
  }

  function testClaimShouldFollowTheMerkleDistribution(uint256 seed, uint256 size) public {
    size = bound(size, 1, MAX_CAMPAIGN_SIZE);
    uint256 amountSeed = bound(seed, 100, type(uint112).max);
    (bytes32 campaignId, IKSDistributor.Campaign memory campaign) = _createCampaign(seed);
    (bytes32[] memory leaves,) = _setUpRewards(campaignId, amountSeed, size, nft0);
    vm.warp(campaign.startTimestamp + 1);
    _claimAndVerifyRewards(campaignId, amountSeed, leaves, nft0);
    vm.warp(campaign.startTimestamp + 10);
    (leaves,) = _setUpRewards(campaignId, amountSeed * 2, size, nft0);
    _claimAndVerifyRewards(campaignId, amountSeed * 2, leaves, nft0);
  }

  function testApprovedOperatorCanClaimRewardsForERC721() public {
    uint256 seed = 1e18;
    uint256 size = 10;
    (bytes32 campaignId, IKSDistributor.Campaign memory campaign) = _createCampaign(seed);
    (bytes32[] memory leaves,) = _setUpRewards(campaignId, seed, size, nft0);
    vm.warp(campaign.startTimestamp + 1);

    uint256 i = 1;
    address account = vm.addr(i + 1);
    address recipient = vm.addr(i * i + 1);
    (address[] memory tokens, uint256[] memory amounts) = _getTokensAndAmounts(seed, i);

    bytes32[] memory proof = leaves.getProof(i);
    uint256 erc721Id = _getErc721Id(campaignId, i);
    uint256[] memory claimable = _verifyClaimedAmountsForERC721(
      campaignId, address(nft0), erc721Id, tokens, amounts, recipient
    );
    vm.prank(account);
    nft0.approve(operator, erc721Id);
    vm.prank(operator);
    vm.expectEmit(address(distributor));
    emit IKSDistributor.RewardsClaimedForERC721(
      campaignId, address(nft0), erc721Id, operator, tokens, claimable, recipient
    );
    distributor.claimRewardsForERC721(
      campaignId, address(nft0), erc721Id, tokens, amounts, proof, recipient
    );
    _verifyClaimedAmountsForERC721(campaignId, address(nft0), erc721Id, tokens, amounts, recipient);
  }

  function testApprovedForAllOperatorCanClaimRewardsForERC721() public {
    uint256 seed = 1e18;
    uint256 size = 10;
    (bytes32 campaignId, IKSDistributor.Campaign memory campaign) = _createCampaign(seed);
    (bytes32[] memory leaves,) = _setUpRewards(campaignId, seed, size, nft0);
    vm.warp(campaign.startTimestamp + 1);

    uint256 i = 1;
    address account = vm.addr(i + 1);
    address recipient = vm.addr(i * i + 1);
    (address[] memory tokens, uint256[] memory amounts) = _getTokensAndAmounts(seed, i);

    bytes32[] memory proof = leaves.getProof(i);
    uint256 erc721Id = _getErc721Id(campaignId, i);
    uint256[] memory claimable = _verifyClaimedAmountsForERC721(
      campaignId, address(nft0), erc721Id, tokens, amounts, recipient
    );
    vm.prank(account);
    nft0.setApprovalForAll(operator, true);
    vm.prank(operator);
    vm.expectEmit(address(distributor));
    emit IKSDistributor.RewardsClaimedForERC721(
      campaignId, address(nft0), erc721Id, operator, tokens, claimable, recipient
    );
    distributor.claimRewardsForERC721(
      campaignId, address(nft0), erc721Id, tokens, amounts, proof, recipient
    );
    _verifyClaimedAmountsForERC721(campaignId, address(nft0), erc721Id, tokens, amounts, recipient);
  }

  function testOnlyAuthorizedAccountCanClaimRewardsForERC721() public {
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
    vm.warp(campaign.startTimestamp + 1);
    _claimAndVerifyRewards(campaignId, amountSeed, leaves, nft0);
    vm.warp(campaign.startTimestamp + 10);
    (leaves,) = _setUpRewards(campaignId, amountSeed / 2, size, nft0);
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

  function testBatchClaim(uint256 seed0, uint256 seed1, uint256 size0, uint256 size1) public {
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
        campaign1.startTimestamp, campaign1.endTimestamp, campaign1.metadata
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
      nft0.approve(account, erc721Id);
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
      nft1.approve(account, erc721Id);
      bytes32[] memory proof = leaves1.getProof(1);
      (address[] memory tokens, uint256[] memory amounts) = _getTokensAndAmounts(amountSeed1, 1);
      datas[3] = abi.encodeCall(
        IKSDistributor.claimRewardsForERC721,
        (campaignId1, address(nft1), erc721Id, tokens, amounts, proof, account)
      );
    }

    vm.warp(campaign0.startTimestamp);
    vm.prank(account);
    vm.expectCall(address(distributor), datas[0]);
    vm.expectCall(address(distributor), datas[1]);
    vm.expectCall(address(distributor), datas[2]);
    vm.expectCall(address(distributor), datas[3]);
    distributor.batchClaimRewards(datas);
  }

  function _setUpKSDistributor() internal {
    address[] memory initialOperators = new address[](1);
    initialOperators[0] = operator;
    address[] memory initialGuardians = new address[](1);
    initialGuardians[0] = guardian;
    distributor = new KSDistributor(owner, initialOperators, initialGuardians);
  }

  function _setUpTokens() internal {
    token0 = new ERC20Mock();
    token1 = new ERC20Mock();
    nft0 = new ERC721Mock();
    nft1 = new ERC721Mock();
    token0.mint(address(distributor), type(uint128).max);
    token1.mint(address(distributor), type(uint128).max);
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
    campaign.endTimestamp = campaign.startTimestamp + bound(seed, 1 hours, MAX_TIME_DURATION);
    campaign.metadata = 'metadata';
    vm.prank(operator);
    campaignId =
      distributor.createCampaign(campaign.startTimestamp, campaign.endTimestamp, campaign.metadata);
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
      distributor.updateRoot(campaignId, root);
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
    ERC721Mock nft
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
        emit IKSDistributor.RewardsClaimedForAccount(
          campaignId, account, tokens, claimable, recipient
        );
        distributor.claimRewardsForAccount(campaignId, tokens, amounts, proof, recipient);
        _verifyClaimedAmountsForAccount(campaignId, account, tokens, amounts, recipient);
      } else {
        uint256 erc721Id = _getErc721Id(campaignId, i);
        uint256[] memory claimable = _verifyClaimedAmountsForERC721(
          campaignId, address(nft), erc721Id, tokens, amounts, recipient
        );
        vm.prank(account);
        vm.expectEmit(address(distributor));
        emit IKSDistributor.RewardsClaimedForERC721(
          campaignId, address(nft), erc721Id, account, tokens, claimable, recipient
        );
        distributor.claimRewardsForERC721(
          campaignId, address(nft), erc721Id, tokens, amounts, proof, recipient
        );
        _verifyClaimedAmountsForERC721(
          campaignId, address(nft), erc721Id, tokens, amounts, recipient
        );
      }

      for (uint256 j = 0; j < tokens.length; j++) {
        assertEq(IERC20(tokens[j]).balanceOf(recipient), amounts[j]);
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
      assertEq(amounts[i] - claimable[i], IERC20(tokens[i]).balanceOf(recipient));
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
      assertEq(amounts[i] - claimable[i], IERC20(tokens[i]).balanceOf(recipient));
    }
  }
}
