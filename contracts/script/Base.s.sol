// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import 'forge-std/Script.sol';
import 'forge-std/StdJson.sol';

contract BaseScript is Script {
  using stdJson for string;

  function _readAddress(string memory path, uint256 chainId) internal view returns (address) {
    string memory json = vm.readFile(path);
    return json.readAddress(string.concat('.', vm.toString(chainId)));
  }

  function _readBool(string memory path, uint256 chainId) internal view returns (bool) {
    string memory json = vm.readFile(path);
    return json.readBool(string.concat('.', vm.toString(chainId)));
  }

  function _readAddressArray(string memory path, uint256 chainId)
    internal
    view
    returns (address[] memory)
  {
    string memory json = vm.readFile(path);
    return json.readAddressArray(string.concat('.', vm.toString(chainId)));
  }

  function _getJsonString(string memory path) internal view returns (string memory) {
    try vm.readFile(path) returns (string memory json) {
      return json;
    } catch {
      return '{}';
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

  function _writeAddress(string memory path, uint256 chainId, address value) internal {
    if (!vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
      return;
    }
    vm.serializeJson(path, _getJsonString(path));
    vm.writeJson(path.serialize(vm.toString(chainId), value), path);
  }
}
