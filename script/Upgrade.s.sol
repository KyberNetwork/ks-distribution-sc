// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import '../src/KSDistributor.sol';
import './Base.s.sol';

import {UnsafeUpgrades, Upgrades} from 'openzeppelin-foundry-upgrades/Upgrades.sol';

contract UpgradeScript is BaseDistributorScript {
  /// @dev Bump to roll out new logic. Matches DeployScript's release version by default, so a
  /// freshly deployed chain is already up to date.
  string internal _releaseVersion = '250718_2';

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
      type(KSDistributor).creationCode
    );

    address current = Upgrades.getImplementationAddress(distributor);

    if (current != implementation) {
      console.log('upgrade implementation:', current, '->', implementation);
      UnsafeUpgrades.upgradeProxy(distributor, implementation, '');
    }

    _writeAddress('distributor-impl', implementation);
  }
}
