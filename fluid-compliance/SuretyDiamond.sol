// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibDiamond} from "./libraries/LibDiamond.sol";
import {LibAppStorage} from "./libraries/LibAppStorage.sol";
import {LibRoles} from "./libraries/LibRoles.sol";
import {IDiamondCut} from "./interfaces/IDiamondCut.sol";

/// @title SuretyDiamond
/// @author Surety Compliance System
/// @notice Main diamond proxy contract for compliance operations
/// @dev Implements EIP-2535 Diamond Standard with timelock for upgrades
contract SuretyDiamond {
    
    // ============ Events ============
    
    event DiamondUpgradeScheduled(bytes32 indexed upgradeId, uint256 executeAfter);
    event DiamondUpgradeExecuted(bytes32 indexed upgradeId);
    event DiamondUpgradeCancelled(bytes32 indexed upgradeId);
    
    // ============ Errors ============
    
    error FunctionDoesNotExist();
    error UpgradeNotReady();
    error UpgradeAlreadyExecuted();
    
    // ============ State Variables ============
    
    struct ScheduledUpgrade {
        IDiamondCut.FacetCut[] facetCuts;
        address init;
        bytes initData;
        uint256 executeAfter;
        bool executed;
    }
    
    mapping(bytes32 => ScheduledUpgrade) public scheduledUpgrades;
    
    // ============ Constructor ============
    
    /// @notice Initialize the diamond with core facets
    /// @param _owner Initial owner address
    /// @param _timelockDuration Timelock duration in seconds (min 48 hours)
    constructor(address _owner, uint256 _timelockDuration) {
        require(_timelockDuration >= 48 hours, "Timelock too short");
        
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        s.timelockDuration = _timelockDuration;
        
        // Grant initial admin role
        LibRoles.grantRole(LibRoles.DEFAULT_ADMIN_ROLE, _owner);
        
        // Initialize diamond storage
        LibDiamond.setContractOwner(_owner);
        
        // Add ERC165 support
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.supportedInterfaces[type(IERC165).interfaceId] = true;
    }
    
    // ============ Fallback Function ============
    
    /// @notice Find facet for function call and execute
    /// @dev Delegates execution to facet via delegatecall
    fallback() external payable {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        address facet = ds.selectorToFacetAndPosition[msg.sig].facetAddress;
        
        if (facet == address(0)) {
            revert FunctionDoesNotExist();
        }
        
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            
            switch result
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }
    
    receive() external payable {}
}