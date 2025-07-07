// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import '../src/KSDistributor.sol';
import './Base.s.sol';

contract DeployScript is BaseScript {
  address[] enableHookAddresses;
  bytes4[] enableHookFuncSelectors;

  function run() external {
    uint256 chainId;
    assembly {
      chainId := chainid()
    }
    address initialOwner = _readAddress('script/configs/owner.json', chainId);
    address[] memory initialOperators = _readAddressArray('script/configs/operators.json', chainId);
    address[] memory initialGuardians = _readAddressArray('script/configs/guardians.json', chainId);
    (address[] memory hookAddresses, bytes4[] memory hookFuncSelectors, bool[] memory hookStatuses,)
    = _readHooks('script/configs/hooks.json', chainId);

    for (uint256 i = 0; i < hookAddresses.length; i++) {
      if (hookStatuses[i]) {
        enableHookAddresses.push(hookAddresses[i]);
        enableHookFuncSelectors.push(hookFuncSelectors[i]);
      }
    }
    vm.startBroadcast();
    KSDistributor distributor = new KSDistributor(
      initialOwner,
      initialOperators,
      initialGuardians,
      enableHookAddresses,
      enableHookFuncSelectors,
      1 days
    );
    _writeAddress('script/configs/distributor.json', chainId, address(distributor));
    vm.stopBroadcast();
  }
}
