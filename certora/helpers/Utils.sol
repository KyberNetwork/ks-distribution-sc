// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {IERC20} from
  '../../lib/ks-growth-utils-sc/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';

contract Utils {
  function balanceOf(address reward, address user) external view returns (uint256) {
    return IERC20(reward).balanceOf(user);
  }
}
