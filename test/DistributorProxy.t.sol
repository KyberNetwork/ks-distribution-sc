// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import '../src/KSDistributor.sol';

import 'forge-std/Test.sol';

import {ERC1967Utils} from 'openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Utils.sol';
import {ProxyAdmin} from 'openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol';
import {
  ITransparentUpgradeableProxy,
  TransparentUpgradeableProxy
} from 'openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import {Initializable} from 'openzeppelin-contracts/contracts/proxy/utils/Initializable.sol';
import {UnsafeUpgrades, Upgrades} from 'openzeppelin-foundry-upgrades/Upgrades.sol';

/// @notice Proves KSDistributor is correctly configured when deployed behind a
/// TransparentUpgradeableProxy, the way script/Deploy.s.sol deploys it.
contract KSDistributorProxyTest is Test {
  KSDistributor internal implementation;
  KSDistributor internal distributor;

  address internal admin = makeAddr('admin');
  address internal operator = makeAddr('operator');
  address internal guardian = makeAddr('guardian');
  address internal rescuer = makeAddr('rescuer');
  address internal hook = makeAddr('hook');

  bytes4 internal constant HOOK_SELECTOR = bytes4(keccak256('someHook(uint256)'));
  uint256 internal constant TIME_LOCK = 2 hours;

  function setUp() public {
    vm.warp(1e18);

    // The implementation takes no constructor args; all config lives in initialize().
    implementation = new KSDistributor();

    bytes memory initData = abi.encodeCall(
      KSDistributor.initialize,
      (admin, _arr(operator), _arr(guardian), _arr(rescuer), _arr(hook), _sel(), TIME_LOCK)
    );

    distributor = KSDistributor(
      payable(new TransparentUpgradeableProxy(address(implementation), admin, initData))
    );
  }

  function testProxyIsInitialized() public view {
    assertEq(distributor.defaultTimeLock(), TIME_LOCK, 'defaultTimeLock');
    assertTrue(distributor.hasRole(distributor.DEFAULT_ADMIN_ROLE(), admin), 'admin');
    assertTrue(distributor.hasRole(KSRoles.OPERATOR_ROLE, operator), 'operator');
    assertTrue(distributor.hasRole(KSRoles.GUARDIAN_ROLE, guardian), 'guardian');
    assertTrue(distributor.hasRole(KSRoles.RESCUER_ROLE, rescuer), 'rescuer');
    assertTrue(distributor.whitelistedHooks(hook, HOOK_SELECTOR), 'hook whitelisted');
    assertEq(distributor.defaultAdmin(), admin, 'defaultAdmin');
  }

  /// @dev The whole point of the initializer: proxy storage must be live, not the implementation's.
  function testProxyStorageIsSeparateFromImplementation() public {
    vm.prank(operator);
    bytes32 campaignId =
      distributor.createCampaign(block.timestamp + 1 days, block.timestamp + 30 days, 'eg', 0);

    (uint256 startTimestamp,,) = distributor.campaigns(campaignId);
    assertTrue(startTimestamp != 0, 'campaign exists on proxy');

    (uint256 implStartTimestamp,,) = implementation.campaigns(campaignId);
    assertEq(implStartTimestamp, 0, 'implementation storage untouched');
  }

  function testProxyCannotBeInitializedTwice() public {
    vm.expectRevert(Initializable.InvalidInitialization.selector);
    distributor.initialize(
      admin, _arr(operator), _arr(guardian), _arr(rescuer), _arr(hook), _sel(), TIME_LOCK
    );
  }

  /// @dev The constructor calls _disableInitializers, so the implementation can never be seized.
  function testImplementationCannotBeInitialized() public {
    vm.expectRevert(Initializable.InvalidInitialization.selector);
    implementation.initialize(
      address(this), _arr(operator), _arr(guardian), _arr(rescuer), _arr(hook), _sel(), TIME_LOCK
    );
  }

  /// @dev Mirrors UpgradeScript exactly: read the current implementation with Upgrades, install an
  /// independently deployed one with UnsafeUpgrades, and confirm the proxy keeps its address and
  /// storage while the logic changes. tryCaller stands in for the script's --sender.
  function testUpgradePreservesAddressAndStorage() public {
    vm.prank(operator);
    bytes32 campaignId =
      distributor.createCampaign(block.timestamp + 1 days, block.timestamp + 30 days, 'eg', 0);

    KSDistributor newImplementation = new KSDistributor();

    address current = Upgrades.getImplementationAddress(address(distributor));
    assertEq(current, address(implementation), 'implementation slot before');

    UnsafeUpgrades.upgradeProxy(address(distributor), address(newImplementation), '', admin);

    address upgraded = Upgrades.getImplementationAddress(address(distributor));
    assertEq(upgraded, address(newImplementation), 'implementation slot after');

    // Storage and configuration survive the upgrade.
    (uint256 startTimestamp,,) = distributor.campaigns(campaignId);
    assertTrue(startTimestamp != 0, 'campaign survives upgrade');
    assertEq(distributor.defaultTimeLock(), TIME_LOCK, 'timeLock survives upgrade');
    assertTrue(distributor.hasRole(KSRoles.OPERATOR_ROLE, operator), 'operator survives upgrade');
  }

  function testOnlyProxyAdminOwnerCanUpgrade() public {
    KSDistributor newImplementation = new KSDistributor();
    address proxyAdmin =
      address(uint160(uint256(vm.load(address(distributor), ERC1967Utils.ADMIN_SLOT))));

    vm.prank(makeAddr('attacker'));
    vm.expectRevert();
    ProxyAdmin(proxyAdmin)
      .upgradeAndCall(
        ITransparentUpgradeableProxy(address(distributor)), address(newImplementation), ''
      );
  }

  function testInitializeRejectsZeroAdmin() public {
    KSDistributor freshImpl = new KSDistributor();
    bytes memory initData = abi.encodeCall(
      KSDistributor.initialize,
      (address(0), _arr(operator), _arr(guardian), _arr(rescuer), _arr(hook), _sel(), TIME_LOCK)
    );
    vm.expectRevert();
    new TransparentUpgradeableProxy(address(freshImpl), admin, initData);
  }

  function _arr(address value) internal pure returns (address[] memory result) {
    result = new address[](1);
    result[0] = value;
  }

  function _sel() internal pure returns (bytes4[] memory result) {
    result = new bytes4[](1);
    result[0] = HOOK_SELECTOR;
  }
}
