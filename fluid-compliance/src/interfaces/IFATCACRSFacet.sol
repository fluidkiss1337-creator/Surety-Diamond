// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibAppStorage} from "../libraries/LibAppStorage.sol";

/// @title IFATCACRSFacet
/// @notice Interface for FATCA/CRS tax compliance reporting
/// @dev All personally identifiable information is stored as keccak256 hashes only - never raw PII
interface IFATCACRSFacet {

    event TaxClassificationUpdated(address indexed entity, uint8 fatcaStatus, uint8 crsType, uint256 timestamp);
    event TaxFormStatusChanged(address indexed entity, bool onFile, uint256 expirationDate);
    event ReportingObligationTriggered(bytes32 indexed obligationId, address indexed entity, bytes32 indexed jurisdiction, uint256 amount);

    function setTaxClassification(
        address entity,
        LibAppStorage.TaxClassification calldata classification
    ) external;

    function recordTaxForm(
        address entity,
        bytes32 formType,
        bytes32 documentHash,
        uint256 expirationDate
    ) external;

    function assessReportingRequirement(
        bytes32 transactionId,
        address from,
        address to,
        uint256 amount,
        bytes32 transactionType
    ) external returns (bool requiresReporting, bytes32[] memory jurisdictions);

    function createReportingObligation(
        address entity,
        bytes32 jurisdiction,
        uint256 amount,
        bytes32 accountType,
        uint256 reportingYear
    ) external returns (bytes32 obligationId);

    function markAsReported(bytes32 obligationId) external;

    function getTaxClassification(
        address entity
    ) external view returns (LibAppStorage.TaxClassification memory classification);

    function checkWithholding(
        address payer,
        address payee,
        bytes32 paymentType
    ) external view returns (bool withhold, uint256 rate);

    function getPendingObligations(
        address entity,
        uint256 year
    ) external view returns (LibAppStorage.ReportingObligation[] memory obligations);
}
