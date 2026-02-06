// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import '../src/KSDistributor.sol';
import './Base.s.sol';

contract DeployScript is BaseDistributorScript {
  address[] enableHookAddresses;
  bytes4[] enableHookFuncSelectors;

  string internal _contractName = 'KSDistributor';
  string internal _releaseVersion = '250718_2';

  function run() external {
    require(bytes(_releaseVersion).length > 0, 'Release version not set');

    address initialAdmin = _readAddress('admin');
    address[] memory initialOperators = _readAddressArray('operators');
    address[] memory initialGuardians = _readAddressArray('guardians');
    address[] memory initialRescuers = _readAddressArray('rescuers');
    (address[] memory hookAddresses, bytes4[] memory hookFuncSelectors, bool[] memory hookStatuses,)
    = _readHooks('hooks');

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

    (address distributor,) = _create3Deploy(salt, bytecode);

    _writeAddress('distributor', distributor);
    vm.stopBroadcast();
  }
}
