// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibRoles} from "../libraries/LibRoles.sol";
import {IRoleManagerFacet} from "../interfaces/IRoleManagerFacet.sol";

contract RoleManagerFacet is IRoleManagerFacet {

    modifier onlyAdmin() {
        LibRoles.checkRole(LibRoles.DEFAULT_ADMIN_ROLE);
        _;
    }

    function grantRole(bytes32 role, address account) external onlyAdmin {
        LibRoles.grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) external onlyAdmin {
        LibRoles.revokeRole(role, account);
    }
}