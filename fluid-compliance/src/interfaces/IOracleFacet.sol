// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IOracleFacet
/// @notice Interface for trusted oracle data feeds (exchange rates, sanctions updates)
interface IOracleFacet {

    struct OracleFeed {
        bytes32 feedId;
        uint256 value;
        uint256 lastUpdated;
        address updatedBy;
        bool isActive;
    }

    event OracleFeedUpdated(bytes32 indexed feedId, uint256 newValue, address updatedBy, uint256 timestamp);
    event OracleFeedAdded(bytes32 indexed feedId, string description);
    event OracleFeedDeactivated(bytes32 indexed feedId);

    /// @notice Register a new oracle data feed
    /// @dev Requires ORACLE_ROLE
    function addFeed(bytes32 feedId, string calldata description) external;

    /// @notice Update a feed's value
    /// @dev Requires ORACLE_ROLE
    function updateFeed(bytes32 feedId, uint256 value) external;

    /// @notice Deactivate a feed
    function deactivateFeed(bytes32 feedId) external;

    /// @notice Get current value for a feed
    function getFeedValue(bytes32 feedId) external view returns (uint256 value, uint256 lastUpdated);

    /// @notice Get full feed data
    function getFeed(bytes32 feedId) external view returns (OracleFeed memory feed);

    /// @notice Check if a feed is active and fresh
    function isFeedFresh(bytes32 feedId, uint256 maxAge) external view returns (bool fresh);
}
