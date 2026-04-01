// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IRoleManagerFacet {
    function grantRole(bytes32 role, address account) external;
    function revokeRole(bytes32 role, address account) external;
}