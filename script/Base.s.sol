// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import '../src/KSDistributor.sol';
import 'ks-common-sc/script/Base.s.sol';
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

  /// @notice The distributor on the chain currently selected, set by {_loadDistributor}
  KSDistributor distributor;

  /// @dev Points {distributor} at the current chain's deployment. Call once per chain, inside a
  /// multiChain body.
  function _loadDistributor() internal {
    distributor = KSDistributor(payable(distributorOf[vm.getChainId()]));
    require(address(distributor) != address(0), 'distributor not deployed on this chain');
  }

  /// @dev Reads a campaign's generated merkle file. Only valid before the cycle's output is
  /// archived into script/output/YYMMDD/.
  function _readCampaignFile(bytes32 campaignId) internal view returns (string memory) {
    return vm.readFile(string.concat('script/output/campaign-', vm.toString(campaignId), '.json'));
  }

  /// @dev A zero startTimestamp is how the distributor marks a campaign as non-existent.
  function _campaignExists(bytes32 campaignId) internal view returns (bool) {
    (uint256 startTimestamp,,) = distributor.campaigns(campaignId);
    return startTimestamp != 0;
  }

  /// @dev Submits a root and reads it back, so a submission that silently did nothing cannot pass
  /// for success. `effectiveTimestamp` must be resolved by the caller: submitRoot treats 0 as
  /// "now + defaultTimeLock", which would then not match what we verify against.
  ///
  /// A submission that would change nothing is skipped, so re-running any script that calls this
  /// is free. Note that submitRoot is not otherwise a no-op — it applies any pending root that has
  /// become effective before storing the new one — so the skip has to be exact:
  ///   - the same root already pending at the same effective timestamp, or
  ///   - the root already active with no pending root that resubmitting would displace.
  function _submitAndVerifyRoot(bytes32 campaignId, bytes32 root, uint256 effectiveTimestamp)
    internal
  {
    require(root != bytes32(0), 'root is empty');
    require(effectiveTimestamp != 0, 'effectiveTimestamp is required');

    (bytes32 pendingRoot, uint256 pendingEffectiveTimestamp) = distributor.pendingRoots(campaignId);
    bool alreadyPending = pendingRoot == root && pendingEffectiveTimestamp == effectiveTimestamp;
    bool alreadyActive = pendingRoot == bytes32(0) && distributor.roots(campaignId) == root;

    if (alreadyPending || alreadyActive) {
      console.log(
        'Root for campaignId: %s is already set on chainId: %s, skipping...',
        vm.toString(campaignId),
        vm.toString(vm.getChainId())
      );
      return;
    }

    console.log(
      'Submitting root for campaignId: %s on chainId: %s',
      vm.toString(campaignId),
      vm.toString(vm.getChainId())
    );
    console.log('  root:', vm.toString(root));
    console.log('  effectiveTimestamp:', effectiveTimestamp);

    distributor.submitRoot(campaignId, root, effectiveTimestamp);

    (bytes32 newRoot, uint256 newEffectiveTimestamp) = distributor.pendingRoots(campaignId);
    require(newRoot == root, 'root mismatch');
    require(newEffectiveTimestamp == effectiveTimestamp, 'effectiveTimestamp mismatch');

    console.log('  root submitted and verified');
  }

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

  /// @dev Built fresh per chain — accumulating into storage arrays would leak one chain's hooks
  /// into the next chain's constructor args.
  function _readEnabledHooks()
    internal
    returns (address[] memory addresses, bytes4[] memory funcSelectors)
  {
    (
      address[] memory hookAddresses,
      bytes4[] memory hookFuncSelectors,
      bool[] memory hookStatuses,
    ) = _readHooks('hooks');

    uint256 enabledCount;
    for (uint256 i = 0; i < hookAddresses.length; i++) {
      if (hookStatuses[i]) enabledCount++;
    }

    addresses = new address[](enabledCount);
    funcSelectors = new bytes4[](enabledCount);

    uint256 j;
    for (uint256 i = 0; i < hookAddresses.length; i++) {
      if (hookStatuses[i]) {
        addresses[j] = hookAddresses[i];
        funcSelectors[j] = hookFuncSelectors[i];
        j++;
      }
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

  /// @dev Reads the current chain's campaign ids from `script/<fileName>`, a JSON object keyed by
  /// chain id. Chains absent from the file yield an empty list rather than reverting, so a run can
  /// span chains that have nothing to do.
  function _readCampaignIds(string memory fileName)
    internal
    view
    returns (bytes32[] memory campaignIds)
  {
    string memory jsonString = vm.readFile(string.concat('script/', fileName));
    string memory key = string.concat('.', vm.toString(vm.getChainId()));

    if (!vm.keyExistsJson(jsonString, key)) {
      return new bytes32[](0);
    }
    campaignIds = abi.decode(jsonString.parseRaw(key), (bytes32[]));
  }

  function _readUpdateRootData() internal view returns (bytes32[] memory campaignIds) {
    return _readCampaignIds('campaigns-to-update-root.json');
  }

  function _toArray(address addr) internal pure returns (address[] memory) {
    address[] memory arr = new address[](1);
    arr[0] = addr;
    return arr;
  }
}
