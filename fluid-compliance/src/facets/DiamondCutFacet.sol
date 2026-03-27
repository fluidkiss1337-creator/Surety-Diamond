// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibDiamond} from "../libraries/LibDiamond.sol";
import {LibRoles} from "../libraries/LibRoles.sol";
import {IDiamondCut} from "../interfaces/IDiamondCut.sol";

/// @title DiamondCutFacet
/// @notice EIP-2535 facet management with timelock enforcement
/// @dev Handles Add/Replace/Remove operations for facet function selectors.
///      All upgrades must be scheduled through the timelock mechanism.
contract DiamondCutFacet is IDiamondCut {

    uint256 public constant MIN_TIMELOCK = 48 hours;

    error NotContractOwner();
    error TimelockNotExpired(uint256 executeAfter, uint256 currentTime);
    error UpgradeNotScheduled();
    error UpgradeAlreadyExecuted();
    error DelayTooShort(uint256 provided, uint256 minimum);

    struct ScheduledCut {
        FacetCut[] cuts;
        address init;
        bytes initCalldata;
        uint256 executeAfter;
        bool executed;
    }

    mapping(bytes32 => ScheduledCut) public scheduledCuts;

    // ============ Schedule ============

    /// @notice Schedule a diamond upgrade subject to the timelock
    /// @param _diamondCut Array of facet cuts to apply when executed
    /// @param _init Optional initializer address (address(0) to skip)
    /// @param _calldata Calldata for the initializer
    /// @param _delay Seconds to wait before the upgrade can be executed (minimum MIN_TIMELOCK)
    /// @return upgradeId Unique identifier for this scheduled upgrade
    function scheduleDiamondCut(
        FacetCut[] calldata _diamondCut,
        address _init,
        bytes calldata _calldata,
        uint256 _delay
    ) external returns (bytes32 upgradeId) {
        LibDiamond.enforceIsContractOwner();
        if (_delay < MIN_TIMELOCK) revert DelayTooShort(_delay, MIN_TIMELOCK);

        upgradeId = keccak256(abi.encode(_diamondCut, _init, _calldata, block.timestamp));
        ScheduledCut storage sc = scheduledCuts[upgradeId];
        sc.init = _init;
        sc.initCalldata = _calldata;
        sc.executeAfter = block.timestamp + _delay;

        for (uint256 i = 0; i < _diamondCut.length; i++) {
            sc.cuts.push(_diamondCut[i]);
        }
    }

    // ============ Execute ============

    /// @notice Execute a previously scheduled upgrade after the timelock expires
    /// @param upgradeId The identifier returned by scheduleDiamondCut
    function executeDiamondCut(bytes32 upgradeId) external {
        LibDiamond.enforceIsContractOwner();
        ScheduledCut storage sc = scheduledCuts[upgradeId];

        if (sc.executeAfter == 0) revert UpgradeNotScheduled();
        if (sc.executed) revert UpgradeAlreadyExecuted();
        if (block.timestamp < sc.executeAfter) {
            revert TimelockNotExpired(sc.executeAfter, block.timestamp);
        }

        sc.executed = true;
        LibDiamond.diamondCut(sc.cuts, sc.init, sc.initCalldata);
    }

    // ============ IDiamondCut ============

    /// @notice Direct cut — bypasses timelock. Intended for initial deployment only.
    /// @param _diamondCut Array of facet cuts to apply immediately
    /// @param _init Optional initializer address (address(0) to skip)
    /// @param _calldata Calldata for the initializer
    function diamondCut(
        FacetCut[] calldata _diamondCut,
        address _init,
        bytes calldata _calldata
    ) external override {
        LibDiamond.enforceIsContractOwner();
        LibDiamond.diamondCut(_diamondCut, _init, _calldata);
    }
}
