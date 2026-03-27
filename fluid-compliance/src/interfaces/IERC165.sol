// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IERC165
/// @notice ERC-165 standard interface detection
interface IERC165 {
    /// @notice Query if a contract implements an interface
    /// @param interfaceId The interface identifier, as specified in ERC-165
    /// @return `true` if the contract implements `interfaceID`
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}
