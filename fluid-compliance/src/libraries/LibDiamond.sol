// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDiamondCut} from "../interfaces/IDiamondCut.sol";

/// @title LibDiamond
/// @notice Core EIP-2535 Diamond Standard storage and routing
/// @dev Manages facet selector routing and diamond ownership.
///      Implementation follows the mudgen diamond-3 reference.
library LibDiamond {

    bytes32 constant DIAMOND_STORAGE_POSITION = keccak256("diamond.standard.diamond.storage");

    // ============================================================
    // Errors
    // ============================================================

    error NotContractOwner(address sender, address owner);
    error NoSelectorsInFacet();
    error ZeroAddressFacet();
    error FunctionAlreadyExists(bytes4 selector);
    error FunctionDoesNotExist(bytes4 selector);
    error CannotReplaceSameFunction(bytes4 selector);
    error IncorrectFacetCutAction();
    error InitAddressHasNoCode(address init);
    error InitFunctionReverted();
    error FacetHasNoCode(address facet);
    error RemoveFacetMustBeZeroAddress();

    // ============================================================
    // Storage
    // ============================================================

    struct FacetAddressAndPosition {
        address facetAddress;
        uint96 functionSelectorPosition; // position in facetFunctionSelectors.functionSelectors array
    }

    struct FacetFunctionSelectors {
        bytes4[] functionSelectors;
        uint256 facetAddressPosition; // position in facetAddresses array
    }

    struct DiamondStorage {
        // Maps function selector => facet address + position in selector array
        mapping(bytes4 => FacetAddressAndPosition) selectorToFacetAndPosition;
        // Maps facet address => selectors it owns
        mapping(address => FacetFunctionSelectors) facetFunctionSelectors;
        // Ordered list of all facet addresses
        address[] facetAddresses;
        // ERC-165 interface support flags
        mapping(bytes4 => bool) supportedInterfaces;
        // Diamond owner
        address contractOwner;
    }

    // ============================================================

    /// @notice Returns the DiamondStorage pointer at the deterministic slot
    /// @return ds The DiamondStorage struct reference
    function diamondStorage() internal pure returns (DiamondStorage storage ds) {
        bytes32 position = DIAMOND_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    // ============================================================

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event DiamondCut(IDiamondCut.FacetCut[] _diamondCut, address _init, bytes _calldata);

    // ============================================================
    // Ownership helpers
    // ============================================================

    /// @notice Set the contract owner, emitting an OwnershipTransferred event
    /// @param _newOwner Address of the new owner
    function setContractOwner(address _newOwner) internal {
        DiamondStorage storage ds = diamondStorage();
        address previousOwner = ds.contractOwner;
        ds.contractOwner = _newOwner;
        emit OwnershipTransferred(previousOwner, _newOwner);
    }

    /// @notice Return the current contract owner
    /// @return contractOwner_ The current owner address
    function contractOwner() internal view returns (address contractOwner_) {
        contractOwner_ = diamondStorage().contractOwner;
    }

    /// @notice Revert if the caller is not the contract owner
    function enforceIsContractOwner() internal view {
        if (msg.sender != diamondStorage().contractOwner) {
            revert NotContractOwner(msg.sender, diamondStorage().contractOwner);
        }
    }

    // ============================================================
    // diamondCut — EIP-2535 full implementation
    // ============================================================

    /// @notice Add/replace/remove facet functions
    /// @param _diamondCut Array of facet cuts to apply
    /// @param _init Optional initializer contract address (address(0) to skip)
    /// @param _calldata Calldata for the initializer
    function diamondCut(
        IDiamondCut.FacetCut[] memory _diamondCut,
        address _init,
        bytes memory _calldata
    ) internal {
        for (uint256 facetIndex; facetIndex < _diamondCut.length; facetIndex++) {
            IDiamondCut.FacetCutAction action = _diamondCut[facetIndex].action;
            if (action == IDiamondCut.FacetCutAction.Add) {
                addFunctions(_diamondCut[facetIndex].facetAddress, _diamondCut[facetIndex].functionSelectors);
            } else if (action == IDiamondCut.FacetCutAction.Replace) {
                replaceFunctions(_diamondCut[facetIndex].facetAddress, _diamondCut[facetIndex].functionSelectors);
            } else if (action == IDiamondCut.FacetCutAction.Remove) {
                removeFunctions(_diamondCut[facetIndex].facetAddress, _diamondCut[facetIndex].functionSelectors);
            } else {
                revert IncorrectFacetCutAction();
            }
        }
        emit DiamondCut(_diamondCut, _init, _calldata);
        initializeDiamondCut(_init, _calldata);
    }

    // ============================================================
    // Internal cut helpers
    // ============================================================

    /// @notice Register new function selectors pointing to a facet
    /// @param _facetAddress The facet contract address
    /// @param _functionSelectors Selectors to register
    function addFunctions(address _facetAddress, bytes4[] memory _functionSelectors) internal {
        if (_functionSelectors.length == 0) revert NoSelectorsInFacet();
        if (_facetAddress == address(0)) revert ZeroAddressFacet();
        DiamondStorage storage ds = diamondStorage();
        uint96 selectorPosition = uint96(ds.facetFunctionSelectors[_facetAddress].functionSelectors.length);
        if (selectorPosition == 0) {
            addFacet(ds, _facetAddress);
        }
        for (uint256 selectorIndex; selectorIndex < _functionSelectors.length; selectorIndex++) {
            bytes4 selector = _functionSelectors[selectorIndex];
            address oldFacetAddress = ds.selectorToFacetAndPosition[selector].facetAddress;
            if (oldFacetAddress != address(0)) revert FunctionAlreadyExists(selector);
            addFunction(ds, selector, selectorPosition, _facetAddress);
            selectorPosition++;
        }
    }

    /// @notice Replace existing function selectors with a new facet implementation
    /// @param _facetAddress The new facet contract address
    /// @param _functionSelectors Selectors to replace
    function replaceFunctions(address _facetAddress, bytes4[] memory _functionSelectors) internal {
        if (_functionSelectors.length == 0) revert NoSelectorsInFacet();
        if (_facetAddress == address(0)) revert ZeroAddressFacet();
        DiamondStorage storage ds = diamondStorage();
        uint96 selectorPosition = uint96(ds.facetFunctionSelectors[_facetAddress].functionSelectors.length);
        if (selectorPosition == 0) {
            addFacet(ds, _facetAddress);
        }
        for (uint256 selectorIndex; selectorIndex < _functionSelectors.length; selectorIndex++) {
            bytes4 selector = _functionSelectors[selectorIndex];
            address oldFacetAddress = ds.selectorToFacetAndPosition[selector].facetAddress;
            if (oldFacetAddress == _facetAddress) revert CannotReplaceSameFunction(selector);
            removeFunction(ds, oldFacetAddress, selector);
            addFunction(ds, selector, selectorPosition, _facetAddress);
            selectorPosition++;
        }
    }

    /// @notice Remove function selectors from the diamond
    /// @param _facetAddress Must be address(0) per EIP-2535 remove convention
    /// @param _functionSelectors Selectors to remove
    function removeFunctions(address _facetAddress, bytes4[] memory _functionSelectors) internal {
        if (_functionSelectors.length == 0) revert NoSelectorsInFacet();
        if (_facetAddress != address(0)) revert RemoveFacetMustBeZeroAddress();
        DiamondStorage storage ds = diamondStorage();
        for (uint256 selectorIndex; selectorIndex < _functionSelectors.length; selectorIndex++) {
            bytes4 selector = _functionSelectors[selectorIndex];
            address oldFacetAddress = ds.selectorToFacetAndPosition[selector].facetAddress;
            removeFunction(ds, oldFacetAddress, selector);
        }
    }

    /// @notice Add a new facet address to the diamond's facet list
    /// @param ds DiamondStorage reference
    /// @param _facetAddress Facet contract address (must have code)
    function addFacet(DiamondStorage storage ds, address _facetAddress) internal {
        enforceHasContractCode(_facetAddress);
        ds.facetFunctionSelectors[_facetAddress].facetAddressPosition = ds.facetAddresses.length;
        ds.facetAddresses.push(_facetAddress);
    }

    /// @notice Register a single function selector in the diamond routing table
    /// @param ds DiamondStorage reference
    /// @param _selector The 4-byte function selector
    /// @param _selectorPosition Position in the facet's selector array
    /// @param _facetAddress The facet this selector maps to
    function addFunction(
        DiamondStorage storage ds,
        bytes4 _selector,
        uint96 _selectorPosition,
        address _facetAddress
    ) internal {
        ds.selectorToFacetAndPosition[_selector].functionSelectorPosition = _selectorPosition;
        ds.facetFunctionSelectors[_facetAddress].functionSelectors.push(_selector);
        ds.selectorToFacetAndPosition[_selector].facetAddress = _facetAddress;
    }

    /// @notice Remove a single function selector from the diamond routing table
    /// @param ds DiamondStorage reference
    /// @param _facetAddress The facet currently owning the selector
    /// @param _selector The 4-byte function selector to remove
    function removeFunction(
        DiamondStorage storage ds,
        address _facetAddress,
        bytes4 _selector
    ) internal {
        if (_facetAddress == address(0)) revert FunctionDoesNotExist(_selector);
        uint256 selectorPosition = ds.selectorToFacetAndPosition[_selector].functionSelectorPosition;
        uint256 lastSelectorPosition = ds.facetFunctionSelectors[_facetAddress].functionSelectors.length - 1;
        if (selectorPosition != lastSelectorPosition) {
            bytes4 lastSelector = ds.facetFunctionSelectors[_facetAddress].functionSelectors[lastSelectorPosition];
            ds.facetFunctionSelectors[_facetAddress].functionSelectors[selectorPosition] = lastSelector;
            ds.selectorToFacetAndPosition[lastSelector].functionSelectorPosition = uint96(selectorPosition);
        }
        ds.facetFunctionSelectors[_facetAddress].functionSelectors.pop();
        delete ds.selectorToFacetAndPosition[_selector];

        if (lastSelectorPosition == 0) {
            uint256 facetAddressPosition = ds.facetFunctionSelectors[_facetAddress].facetAddressPosition;
            uint256 lastFacetAddressPosition = ds.facetAddresses.length - 1;
            if (facetAddressPosition != lastFacetAddressPosition) {
                address lastFacetAddress = ds.facetAddresses[lastFacetAddressPosition];
                ds.facetAddresses[facetAddressPosition] = lastFacetAddress;
                ds.facetFunctionSelectors[lastFacetAddress].facetAddressPosition = facetAddressPosition;
            }
            ds.facetAddresses.pop();
            delete ds.facetFunctionSelectors[_facetAddress];
        }
    }

    /// @notice Delegatecall an optional initializer after a diamond cut
    /// @param _init Initializer contract (address(0) to skip)
    /// @param _calldata Calldata forwarded to the initializer
    function initializeDiamondCut(address _init, bytes memory _calldata) internal {
        if (_init == address(0)) {
            return;
        }
        enforceHasContractCode(_init);
        (bool success, bytes memory error) = _init.delegatecall(_calldata);
        if (!success) {
            if (error.length > 0) {
                assembly {
                    let returndata_size := mload(error)
                    revert(add(32, error), returndata_size)
                }
            } else {
                revert InitFunctionReverted();
            }
        }
    }

    /// @notice Revert if the given address has no deployed bytecode
    /// @param _contract Address to check
    function enforceHasContractCode(address _contract) internal view {
        uint256 contractSize;
        assembly {
            contractSize := extcodesize(_contract)
        }
        if (contractSize == 0) revert FacetHasNoCode(_contract);
    }
}
