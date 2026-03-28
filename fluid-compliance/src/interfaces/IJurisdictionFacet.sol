// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibAppStorage} from "../libraries/LibAppStorage.sol";

/// @title IJurisdictionFacet
/// @notice Interface for multi-jurisdiction compliance rule management
interface IJurisdictionFacet {

    event JurisdictionUpdated(bytes32 indexed jurisdictionId, bool isActive, uint256 timestamp);
    event EntityJurisdictionAssigned(address indexed entity, bytes32 indexed jurisdictionId);
    event CrossBorderAssessed(bytes32 indexed assessmentId, bytes32 indexed sourceJurisdiction, bytes32 indexed destJurisdiction, bool isPermitted);

    function configureJurisdiction(LibAppStorage.JurisdictionConfig calldata config) external;

    function assignEntityJurisdiction(address entity, bytes32 jurisdictionId) external;

    function assessCrossBorder(
        address from,
        address to,
        uint256 amount,
        bytes32 transactionType
    ) external returns (LibAppStorage.CrossBorderAssessment memory assessment);

    function blockJurisdictionOperation(bytes32 jurisdictionId, bytes32 operationType) external;

    function blockCounterpartyPair(
        bytes32 jurisdiction1,
        bytes32 jurisdiction2,
        string calldata reason
    ) external;

    function getJurisdiction(
        bytes32 jurisdictionId
    ) external view returns (LibAppStorage.JurisdictionConfig memory config);

    function getEntityJurisdiction(address entity) external view returns (bytes32 jurisdictionId);

    function isTransactionPermitted(
        bytes32 sourceJurisdiction,
        bytes32 destJurisdiction,
        bytes32 transactionType
    ) external view returns (bool permitted);

    function getMinimumKYCLevel(bytes32 jurisdictionId) external view returns (LibAppStorage.KYCLevel level);
}
