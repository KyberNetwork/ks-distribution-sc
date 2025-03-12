// SPDX-License-Identifier: GPL-3.0-or-later

methods {
    function isEmpty(bytes32) external returns(bool) envfree;
    function isWellFormed(bytes32) external returns(bool) envfree;

    function _.mint(address to, uint256 tokenId) external => DISPATCHER(true);
}

invariant zeroIsEmpty() isEmpty(to_bytes32(0));

invariant wellFormed(bytes32 id) isWellFormed(id) {
    preserved {
        requireInvariant zeroIsEmpty();
    }
}