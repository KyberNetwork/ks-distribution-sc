// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IKSZapRouter {
  struct ZapDescription {
    uint16 zapFlags;
    bytes srcInfo;
    bytes zapInfo;
    bytes extraData;
  }

  struct ZapExecutionData {
    address validator;
    address executor;
    uint32 deadline;
    bytes executorData;
    bytes clientData;
  }

  struct DelegatecallData {
    address helper;
    bytes4 funcSelector;
  }

  struct ERC20SrcInfo {
    address[] tokens;
    uint256[] amounts;
  }

  struct ERC721SrcInfo {
    address[] tokens;
    uint256[] ids;
  }

  struct ERC1155SrcInfo {
    address[] tokens;
    uint256[] ids;
    uint256[] amounts;
    bytes[] datas;
  }

  function zap(ZapDescription calldata desc, ZapExecutionData calldata exe)
    external
    payable
    returns (bytes memory zapResults);
}
