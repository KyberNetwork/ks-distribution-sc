// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.28;

import 'src/KSDistributor.sol';

import {
  TransparentUpgradeableProxy
} from 'openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';

/// @notice KSDistributor has a minimal constructor and is only usable behind a proxy, so tests
/// deploy it the same way script/Deploy.s.sol does: implementation, then a proxy initialized
/// during construction.
library ProxyUtils {
  function deployProxy(
    address implementation,
    address initialAdmin,
    address[] memory initialOperators,
    address[] memory initialGuardians,
    address[] memory initialRescuers,
    address[] memory initialWhitelistedHooks,
    bytes4[] memory initialWhitelistedSelectors,
    uint256 initDefaultTimeLock
  ) internal returns (address payable) {
    bytes memory initData = abi.encodeCall(
      KSDistributor.initialize,
      (
        initialAdmin,
        initialOperators,
        initialGuardians,
        initialRescuers,
        initialWhitelistedHooks,
        initialWhitelistedSelectors,
        initDefaultTimeLock
      )
    );

    return payable(address(new TransparentUpgradeableProxy(implementation, initialAdmin, initData)));
  }
}
