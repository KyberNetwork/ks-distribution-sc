// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {IKSDistributorV2ZKActions} from './v2-zk/IKSDistributorV2ZKActions.sol';
import {IKSDistributorV2ZKAdmin} from './v2-zk/IKSDistributorV2ZKAdmin.sol';
import {IKSDistributorV2ZKErrors} from './v2-zk/IKSDistributorV2ZKErrors.sol';
import {IKSDistributorV2ZKEvents} from './v2-zk/IKSDistributorV2ZKEvents.sol';
import {IKSDistributorV2ZKOperations} from './v2-zk/IKSDistributorV2ZKOperations.sol';
import {IKSDistributorV2ZKState} from './v2-zk/IKSDistributorV2ZKState.sol';
import {
  Campaign,
  ERC721Info,
  PendingRoot,
  RewardsInfo,
  ZKProof
} from './v2-zk/IKSDistributorV2ZkStructs.sol';

interface IKSDistributorV2ZK is
  IKSDistributorV2ZKActions,
  IKSDistributorV2ZKAdmin,
  IKSDistributorV2ZKErrors,
  IKSDistributorV2ZKEvents,
  IKSDistributorV2ZKOperations,
  IKSDistributorV2ZKState
{}
