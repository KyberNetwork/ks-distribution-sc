// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import '../src/KSDistributor.sol';
import './Base.s.sol';

contract DeployScript is BaseScript {
  function run() external {
    uint256 chainId;
    assembly {
      chainId := chainid()
    }
    address initialOwner = _readAddress('script/configs/owner.json', chainId);
    address[] memory initialOperators = _readAddressArray('script/configs/operators.json', chainId);
    address[] memory initialGuardians = _readAddressArray('script/configs/guardians.json', chainId);

    vm.startBroadcast();
    KSDistributor distributor = new KSDistributor(initialOwner, initialOperators, initialGuardians);
    _writeAddress('script/deployedAddresses/', chainId, 'distributor', address(distributor));
    vm.stopBroadcast();
  }
}
