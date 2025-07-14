// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.28;

import 'src/KSDistributor.sol';

contract KSDistributorHarness is KSDistributor {
  constructor(
    address initialAdmin,
    address[] memory initialOperators,
    address[] memory initialGuardians,
    address[] memory initialWhitelistedHooks,
    bytes4[] memory initialWhitelistedSelectors,
    uint256 initDefaultTimeLock
  )
    KSDistributor(
      initialAdmin,
      initialOperators,
      initialGuardians,
      initialWhitelistedHooks,
      initialWhitelistedSelectors,
      initDefaultTimeLock
    )
  {}

  function addPendingReward(address recipient, address token, uint256 amount) public {
    _addPendingReward(recipient, token, amount);
  }

  function transferPendingRewards() public {
    _transferPendingRewards();
  }
}
