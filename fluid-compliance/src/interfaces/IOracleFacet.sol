// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibAppStorage} from "../libraries/LibAppStorage.sol";

/// @title IOracleFacet
/// @notice Interface for secure integration with external compliance data providers
interface IOracleFacet {

    event OracleRegistered(
        address indexed oracle,
        LibAppStorage.OracleDataType[] authorizedTypes,
        uint256 timestamp
    );
    event OracleDataUpdated(
        bytes32 indexed updateId,
        LibAppStorage.OracleDataType indexed dataType,
        bytes32 indexed dataKey,
        address oracle,
        uint256 timestamp
    );

    function registerOracle(
        address oracle,
        LibAppStorage.OracleDataType[] calldata authorizedTypes
    ) external;

    function revokeOracle(address oracle) external;

    function submitOracleUpdate(
        LibAppStorage.OracleDataType dataType,
        bytes32 dataKey,
        bytes calldata dataValue,
        bytes calldata signature
    ) external;

    function requestOracleData(
        LibAppStorage.OracleDataType dataType,
        bytes32 dataKey
    ) external returns (bytes32 requestId);

    function isAuthorizedOracle(address oracle) external view returns (bool);

    function getOracleAuthorizations(
        address oracle
    ) external view returns (LibAppStorage.OracleDataType[] memory types);

    function getPendingRequests(
        LibAppStorage.OracleDataType dataType
    ) external view returns (LibAppStorage.OracleRequest[] memory requests);
}
