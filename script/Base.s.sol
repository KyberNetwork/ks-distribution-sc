// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import 'ks-common-sc-latest/script/Base.s.sol';
import 'openzeppelin-contracts/contracts/utils/Address.sol';

contract BaseDistributorScript is BaseScript {
  using stdJson for string;
  using Address for address;

  struct Hook {
    address contractAddress;
    bytes funcSelector;
    string name;
    bool status;
  }

  mapping(uint256 => address) adminOf;
  mapping(uint256 => address) distributorOf;
  mapping(uint256 => address[]) guardiansOf;
  mapping(uint256 => address[]) operatorsOf;
  mapping(uint256 => address[]) rescuersOf;

  function _loadConfigs(string[] memory _chainIds) internal override {
    for (uint256 i = 0; i < _chainIds.length; i++) {
      uint256 chainId = vm.parseUint(_chainIds[i]);
      adminOf[chainId] = _readAddressByChainId('admin', chainId);
      distributorOf[chainId] = _readAddressByChainId('distributor', chainId);
      guardiansOf[chainId] = _readAddressArrayByChainId('guardians', chainId);
      operatorsOf[chainId] = _readAddressArrayByChainId('operators', chainId);
      rescuersOf[chainId] = _readAddressArrayByChainId('rescuers', chainId);
    }
  }

  function _readClaimingAmounts(string memory path, uint256 idx)
    internal
    view
    returns (
      address erc721Addr,
      uint256 erc721Id,
      address[] memory tokens,
      uint256[] memory amounts,
      bytes32[] memory proofs
    )
  {
    string memory jsonString = vm.readFile(path);

    erc721Addr =
      jsonString.readAddress(string.concat('.userDatas[', vm.toString(idx), '].leaf.erc721Addr'));
    erc721Id =
      jsonString.readUint(string.concat('.userDatas[', vm.toString(idx), '].leaf.erc721Id'));
    tokens =
      jsonString.readAddressArray(string.concat('.userDatas[', vm.toString(idx), '].leaf.tokens'));
    amounts =
      jsonString.readUintArray(string.concat('.userDatas[', vm.toString(idx), '].leaf.amounts'));
    proofs = jsonString.readBytes32Array(string.concat('.userDatas[', vm.toString(idx), '].proof'));
  }

  function _readHooks(string memory key)
    internal
    view
    returns (
      address[] memory addresses,
      bytes4[] memory funcSelectors,
      bool[] memory statuses,
      string[] memory names
    )
  {
    string memory json = _getJsonString(key);
    bytes memory data = json.parseRaw(string.concat('.', vm.toString(vm.getChainId())));
    Hook[] memory hooks = abi.decode(data, (Hook[]));

    addresses = new address[](hooks.length);
    funcSelectors = new bytes4[](hooks.length);
    statuses = new bool[](hooks.length);
    names = new string[](hooks.length);

    for (uint256 i; i < hooks.length; i++) {
      addresses[i] = hooks[i].contractAddress;
      funcSelectors[i] = bytes4(hooks[i].funcSelector);
      statuses[i] = hooks[i].status;
      names[i] = hooks[i].name;
    }
  }

  function _toArray(address addr) internal pure returns (address[] memory) {
    address[] memory arr = new address[](1);
    arr[0] = addr;
    return arr;
  }
}
