// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'ks-common-sc/src/libraries/token/TokenHelper.sol';

import 'openzeppelin-contracts/contracts/token/ERC20/ERC20.sol';

contract SwapMock is ERC20 {
  using TokenHelper for address;

  constructor() ERC20('SwapMock', 'SWAPM') {}

  bool public batchExecuted;

  function swap(address[] calldata tokenIns, address recipient) public {
    for (uint256 i = 0; i < tokenIns.length; i++) {
      address tokenIn = tokenIns[i];
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

  receive() external payable {}
}
