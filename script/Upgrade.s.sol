// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './Base.s.sol';

import {ERC1967Utils} from 'openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Utils.sol';
import {ProxyAdmin} from 'openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol';
import {
  ITransparentUpgradeableProxy
} from 'openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';

contract UpgradeScript is BaseDistributorScript {
  /// @dev Bump to roll out new logic. Matches DeployScript's release version by default, so a
  /// freshly deployed chain is already up to date.
  string internal _releaseVersion = '250718_2';

  uint256 internal constant DEFAULT_TIME_LOCK = 2 hours;

  /**
   * @dev Deploys a KSDistributor implementation and points the proxy at it on specified chains
   *
   *
   * Usage:
   * Upgrade on multiple chains using chain ids
   * forge script UpgradeScript \
   *   --sig "run(string[])" \
   *   "[1,42161,8453,56,143,4663]" --broadcast
   */
  function run(string[] memory chainIds) public multiChain(chainIds) {
    if (bytes(_releaseVersion).length == 0) {
      revert('release version is required');
    }

    address distributor = _readAddress('distributor');
    require(distributor != address(0), 'distributor not deployed on this chain');

    (address implementation,) = _createXDeploy(
      keccak256(abi.encodePacked(string.concat('KSDistributorImpl_', _releaseVersion))),
      _distributorImplCreationCode(DEFAULT_TIME_LOCK)
    );

    address current =
      address(uint160(uint256(vm.load(distributor, ERC1967Utils.IMPLEMENTATION_SLOT))));

    if (current != implementation) {
      console.log('upgrade implementation:', current, '->', implementation);

      address proxyAdmin = address(uint160(uint256(vm.load(distributor, ERC1967Utils.ADMIN_SLOT))));
      ProxyAdmin(proxyAdmin)
        .upgradeAndCall(ITransparentUpgradeableProxy(distributor), implementation, '');
    }

    _writeAddress('distributor-impl', implementation);
  }
}
