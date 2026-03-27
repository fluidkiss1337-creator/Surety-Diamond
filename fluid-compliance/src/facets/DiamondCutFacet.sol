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
    function scheduleDiamondCut(
        FacetCut[] calldata _diamondCut,
        address _init,
        bytes calldata _calldata,
        uint256 _delay
    ) external returns (bytes32 upgradeId) {
        LibDiamond.enforceIsContractOwner();
        require(_delay >= MIN_TIMELOCK, "DiamondCutFacet: delay too short");

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

    /// @notice Execute a previously scheduled upgrade after timelock expires
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

    /// @notice Direct cut - bypasses timelock. Only for initial deployment via DiamondInit.
    function diamondCut(
        FacetCut[] calldata _diamondCut,
        address _init,
        bytes calldata _calldata
    ) external override {
        LibDiamond.enforceIsContractOwner();
        LibDiamond.diamondCut(_diamondCut, _init, _calldata);
    }
}
