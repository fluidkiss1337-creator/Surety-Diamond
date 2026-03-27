// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// NOTE: This is the EIP-2535 core storage library.
// Full implementation: https://github.com/mudgen/diamond-3-hardhat
// TODO: Integrate mudgen/diamond-3 LibDiamond or equivalent before deployment.

import {IDiamondCut} from "../interfaces/IDiamondCut.sol";

/// @title LibDiamond
/// @notice Core EIP-2535 Diamond Standard storage and routing
/// @dev Manages facet selector routing and diamond ownership
library LibDiamond {

    bytes32 constant DIAMOND_STORAGE_POSITION = keccak256("diamond.standard.diamond.storage");

    struct FacetAddressAndPosition {
        address facetAddress;
        uint96 functionSelectorPosition;
    }

    struct FacetFunctionSelectors {
        bytes4[] functionSelectors;
        uint256 facetAddressPosition;
    }

    struct DiamondStorage {
        // Maps function selector => facet address + position
        mapping(bytes4 => FacetAddressAndPosition) selectorToFacetAndPosition;
        // Maps facet address => selectors it owns
        mapping(address => FacetFunctionSelectors) facetFunctionSelectors;
        // Ordered list of facet addresses
        address[] facetAddresses;
        // ERC165 interface support
        mapping(bytes4 => bool) supportedInterfaces;
        // Diamond owner
        address contractOwner;
    }

    function diamondStorage() internal pure returns (DiamondStorage storage ds) {
        bytes32 position = DIAMOND_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function setContractOwner(address _newOwner) internal {
        DiamondStorage storage ds = diamondStorage();
        address previousOwner = ds.contractOwner;
        ds.contractOwner = _newOwner;
        emit OwnershipTransferred(previousOwner, _newOwner);
    }

    function contractOwner() internal view returns (address contractOwner_) {
        contractOwner_ = diamondStorage().contractOwner;
    }

    function enforceIsContractOwner() internal view {
        require(msg.sender == diamondStorage().contractOwner, "LibDiamond: Must be contract owner");
    }

    event DiamondCut(IDiamondCut.FacetCut[] _diamondCut, address _init, bytes _calldata);

    /// @notice Add/replace/remove facet functions
    /// @dev Full implementation to be integrated from mudgen/diamond-3
    function diamondCut(
        IDiamondCut.FacetCut[] memory _diamondCut,
        address _init,
        bytes memory _calldata
    ) internal {
        // TODO: implement addFunctions, replaceFunctions, removeFunctions
        emit DiamondCut(_diamondCut, _init, _calldata);
    }
}
