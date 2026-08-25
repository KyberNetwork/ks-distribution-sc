// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import '../src/KSDistributor.sol';
import './Base.s.sol';

import {
  TransparentUpgradeableProxy
} from 'openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';

contract DeployScript is BaseDistributorScript {
  string internal _releaseVersion = '250718_2';

  uint256 internal constant DEFAULT_TIME_LOCK = 2 hours;

  /**
   * @dev Deploys a KSDistributor implementation and a TransparentUpgradeableProxy in front of it.
   *
   * Usage:
   *
   * # Multiple chains using chain ids
   * forge script DeployScript \
   *   --sig "run(string[])" \
   *   "[1,42161,8453,56,143,4663]" --broadcast
   */
  function run(string[] memory chainIds) public multiChain(chainIds) {
    _deploy();
  }

  function run() external {
    vm.startBroadcast();
    _deploy();
    vm.stopBroadcast();
  }

  function _deploy() internal {
    if (bytes(_releaseVersion).length == 0) {
      revert('release version is required');
    }

    address initialAdmin = _readAddress('admin');

    (address implementation,) = _createXDeploy(
      keccak256(abi.encodePacked(string.concat('KSDistributorImpl_', _releaseVersion))),
      type(KSDistributor).creationCode
    );
    console.log('implementation:', implementation);
    _writeAddress('distributor-impl', implementation);

    (address[] memory enableHookAddresses, bytes4[] memory enableHookFuncSelectors) =
      _readEnabledHooks();

    bytes memory initData = abi.encodeCall(
      KSDistributor.initialize,
      (
        initialAdmin,
        _readAddressArray('operators'),
        _readAddressArray('guardians'),
        _readAddressArray('rescuers'),
        enableHookAddresses,
        enableHookFuncSelectors,
        DEFAULT_TIME_LOCK
      )
    );

    (address distributor,) = _createXDeploy(
      keccak256(abi.encodePacked(string.concat('KSDistributor_', _releaseVersion))),
      abi.encodePacked(
        type(TransparentUpgradeableProxy).creationCode,
        abi.encode(implementation, initialAdmin, initData)
      )
    );
    console.log('distributor:', distributor);

    _writeAddress('distributor', distributor);
  }
}
