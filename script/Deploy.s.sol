// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import '../src/KSDistributor.sol';
import './Base.s.sol';

contract DeployScript is BaseDistributorScript {
  address[] enableHookAddresses;
  bytes4[] enableHookFuncSelectors;

  string internal _contractName = 'KSDistributor';
  string internal _releaseVersion;

  function run() external {
    require(bytes(_releaseVersion).length > 0, 'Release version not set');

    address initialAdmin = _readAddress('script/configs/admin.json');
    address[] memory initialOperators = _readAddressArray('script/configs/operators.json');
    address[] memory initialGuardians = _readAddressArray('script/configs/guardians.json');
    address[] memory initialRescuers = _readAddressArray('script/configs/rescuers.json');
    (address[] memory hookAddresses, bytes4[] memory hookFuncSelectors, bool[] memory hookStatuses,)
    = _readHooks('script/configs/hooks.json');

    for (uint256 i = 0; i < hookAddresses.length; i++) {
      if (hookStatuses[i]) {
        enableHookAddresses.push(hookAddresses[i]);
        enableHookFuncSelectors.push(hookFuncSelectors[i]);
      }
    }

    vm.startBroadcast();
    bytes32 salt = keccak256(bytes(string.concat(_contractName, '_', _releaseVersion)));
    bytes memory bytecode = abi.encodePacked(
      vm.getCode(_contractName),
      abi.encode(
        initialAdmin,
        initialOperators,
        initialGuardians,
        initialRescuers,
        enableHookAddresses,
        enableHookFuncSelectors,
        2 hours
      )
    );

    address distributor = _create3Deploy(salt, bytecode);

    _writeAddress('script/configs/distributor.json', distributor);
    vm.stopBroadcast();
  }
}
