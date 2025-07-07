// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import '../src/KSDistributor.sol';
import './Base.s.sol';

contract UpdateHooks is BaseScript {
  using stdJson for string;

  address[] hookAddresses;
  bytes4[] hookFuncSelectors;
  bool[] hookStatuses;
  string[] hookNames;

  address[] enableHookAddresses;
  bytes4[] enableHookFuncSelectors;

  address[] disableHookAddresses;
  bytes4[] disableHookFuncSelectors;

  function run() external {
    string memory root = vm.projectRoot();
    uint256 chainId;
    assembly {
      chainId := chainid()
    }

    address initialOwner = _readAddress('script/configs/owner.json', chainId);
    address distributor =
      _readAddress(string(abi.encodePacked(root, '/script/configs/distributor.json')), chainId);

    string memory profile = vm.envString('FOUNDRY_PROFILE');

    if (keccak256(abi.encodePacked((profile))) == keccak256(abi.encodePacked(('pre-release')))) {
      (hookAddresses, hookFuncSelectors, hookStatuses, hookNames) =
        _readHooks(string(abi.encodePacked(root, '/script/configs/hooks-pre.json')), chainId);
    } else {
      (hookAddresses, hookFuncSelectors, hookStatuses, hookNames) =
        _readHooks(string(abi.encodePacked(root, '/script/configs/hooks.json')), chainId);
    }

    (hookAddresses, hookFuncSelectors, hookStatuses, hookNames) =
      _readHooks(string(abi.encodePacked(root, '/script/configs/hooks.json')), chainId);

    vm.startBroadcast(initialOwner);
    KSDistributor newDistributor =
      new KSDistributor(initialOwner, _toArray(initialOwner), _toArray(initialOwner), 86_400);
    distributor = address(newDistributor);

    for (uint256 i = 0; i < hookAddresses.length; i++) {
      bool curStatus =
        KSDistributor(distributor).whitelistedHooks(hookAddresses[i], hookFuncSelectors[i]);

      if (hookStatuses[i] != curStatus) {
        if (hookStatuses[i]) {
          enableHookAddresses.push(hookAddresses[i]);
          enableHookFuncSelectors.push(hookFuncSelectors[i]);
        } else {
          disableHookAddresses.push(hookAddresses[i]);
          disableHookFuncSelectors.push(hookFuncSelectors[i]);
        }
      }
    }

    if (enableHookAddresses.length != 0) {
      console.log('Enabling hooks:');
      for (uint256 i = 0; i < enableHookAddresses.length; i++) {
        console.log('Address:', enableHookAddresses[i]);
        console.logBytes4(enableHookFuncSelectors[i]);
      }
      KSDistributor(distributor).updateWhitelistedHooks(
        enableHookAddresses, enableHookFuncSelectors, true
      );
    }

    if (disableHookAddresses.length != 0) {
      console.log('disabling hooks:');
      for (uint256 i = 0; i < disableHookAddresses.length; i++) {
        console.log('Address:', disableHookAddresses[i]);
        console.logBytes4(disableHookFuncSelectors[i]);
      }
      KSDistributor(distributor).updateWhitelistedHooks(
        disableHookAddresses, disableHookFuncSelectors, false
      );
    }

    vm.stopBroadcast();
  }
}
