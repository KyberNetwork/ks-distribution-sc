// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.28;

import 'src/KSDistributor.sol';

contract KSDistributorHarness is KSDistributor {
  constructor(
    address initialOwner,
    address[] memory initialOperators,
    address[] memory initialGuardians,
    uint256 initDefaultTimeLock
  ) KSDistributor(initialOwner, initialOperators, initialGuardians, initDefaultTimeLock) {}

  function addPendingReward(address recipient, address token, uint256 amount) public {
    _addPendingReward(recipient, token, amount);
  }

  function transferPendingRewards() public {
    _transferPendingRewards();
  }
}
