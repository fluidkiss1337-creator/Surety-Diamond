// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibAppStorage} from "../libraries/LibAppStorage.sol";
import {LibRoles} from "../libraries/LibRoles.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";

/// @title DiamondInit
/// @notice One-shot initializer called via diamondCut `_init` parameter on first deployment
/// @dev This contract is delegatecalled by the diamond during the initial cut.
///      It runs once and should not be callable again. Storage is the diamond's storage.
contract DiamondInit {

    error AlreadyInitialized();
    error TimelockTooShort();

    struct InitArgs {
        address owner;
        address treasury;
        uint256 timelockDuration;
        uint256 reportingThreshold;
    }

    /// @notice Initialize all compliance system parameters in a single atomic transaction
    /// @param args Packed initialization arguments
    function init(InitArgs calldata args) external {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // Guard against re-initialization
        if (s.timelockDuration != 0) revert AlreadyInitialized();
        if (args.timelockDuration < 48 hours) revert TimelockTooShort();

        // System configuration
        s.timelockDuration     = args.timelockDuration;
        s.treasuryAddress      = args.treasury;
        s.reportingThreshold   = args.reportingThreshold;
        s.lastSystemUpdate     = block.timestamp;

        // Bootstrap admin roles
        LibRoles.grantRole(LibRoles.DEFAULT_ADMIN_ROLE,      args.owner);
        LibRoles.grantRole(LibRoles.EMERGENCY_ADMIN_ROLE,    args.owner);
        LibRoles.grantRole(LibRoles.COMPLIANCE_OFFICER_ROLE, args.owner);

        // ERC165 support
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.supportedInterfaces[0x01ffc9a7] = true; // IERC165
    }
}
