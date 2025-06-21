// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'openzeppelin-contracts/contracts/token/ERC20/ERC20.sol';
import 'openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';

contract SwapMock is ERC20 {
  using SafeERC20 for IERC20;

  constructor() ERC20('SwapMock', 'SWAPM') {}

  bool public batchExecuted;

  function swap(IERC20[] calldata tokenIns, address recipient) public {
    for (uint256 i = 0; i < tokenIns.length; i++) {
      IERC20 tokenIn = tokenIns[i];
      uint256 amountIn = tokenIn.balanceOf(address(this));
      require(amountIn > 0, 'SwapMock: INSUFFICIENT_BALANCE');

      tokenIn.safeTransfer(recipient, amountIn);
      if (i == 0) {
        _mint(recipient, amountIn);
      }
    }
  }

  function batch() public {
    batchExecuted = true;
  }
}
