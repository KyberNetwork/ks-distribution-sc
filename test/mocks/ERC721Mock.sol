// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import 'openzeppelin-contracts/token/ERC721/ERC721.sol';

contract ERC721Mock is ERC721 {
  constructor() ERC721('ERC721Mock', 'E721M') {}

  function mint(address to, uint256 tokenId) public {
    _mint(to, tokenId);
  }

  function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory)
    public
    override
  {
    transferFrom(from, to, tokenId);
  }
}
