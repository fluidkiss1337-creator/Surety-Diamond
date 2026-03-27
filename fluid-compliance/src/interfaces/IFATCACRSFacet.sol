// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IFATCACRSFacet
/// @notice Interface for FATCA/CRS tax compliance reporting
/// @dev All personally identifiable information is stored as keccak256 hashes only - never raw PII
interface IFATCACRSFacet {

    enum ReportingStatus { PENDING, SUBMITTED, ACCEPTED, REJECTED }

    struct FATCARecord {
        bytes32 entityHash;       // keccak256 of entity identifier - NO raw PII on-chain
        bytes32 tinHash;          // keccak256 of Tax Identification Number
        bytes32 jurisdictionId;   // Country of tax residency
        bool isUSPerson;          // FATCA classification
        bool isCRSReportable;     // CRS reportable status
        ReportingStatus status;
        uint256 lastReported;
    }

    event FATCARecordCreated(bytes32 indexed entityHash, bytes32 jurisdictionId, bool isUSPerson);
    event CRSReportSubmitted(bytes32 indexed entityHash, bytes32 jurisdictionId, uint256 reportingYear);
    event ReportingStatusUpdated(bytes32 indexed entityHash, ReportingStatus newStatus);

    function createFATCARecord(bytes32 entityHash, bytes32 tinHash, bytes32 jurisdictionId, bool isUSPerson) external;
    function updateCRSStatus(bytes32 entityHash, bool isCRSReportable) external;
    function submitCRSReport(bytes32 entityHash, uint256 reportingYear) external;
    function getFATCARecord(bytes32 entityHash) external view returns (FATCARecord memory record);
    function isReportableEntity(bytes32 entityHash) external view returns (bool reportable);
}
