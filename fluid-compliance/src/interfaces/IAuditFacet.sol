// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibAppStorage} from "../libraries/LibAppStorage.sol";

/// @title IAuditFacet
/// @notice Interface for immutable hash-chained on-chain audit trail
interface IAuditFacet {

    event AuditLogged(
        bytes32 indexed entryId,
        LibAppStorage.AuditEventType indexed eventType,
        address indexed actor,
        address subject,
        bytes32 dataHash,
        uint256 timestamp
    );

    function logAudit(
        LibAppStorage.AuditEventType eventType,
        address subject,
        bytes32 dataHash
    ) external returns (bytes32 entryId);

    function verifyAuditChain(
        bytes32 startEntry,
        bytes32 endEntry
    ) external view returns (bool isValid);

    function getAuditEntry(
        bytes32 entryId
    ) external view returns (LibAppStorage.AuditEntry memory entry);

    function getEntityAuditTrail(
        address entity,
        LibAppStorage.AuditEventType eventType,
        uint256 fromTimestamp,
        uint256 toTimestamp
    ) external view returns (LibAppStorage.AuditEntry[] memory entries);

    function getLatestAuditHash() external view returns (bytes32 hash);

    function getAuditStats(
        LibAppStorage.AuditEventType eventType,
        uint256 period
    ) external view returns (uint256 count);

    function logKYCEvent(
        address entity,
        LibAppStorage.AuditEventType eventType,
        bytes32 dataHash
    ) external;

    function logAMLEvent(
        address entity,
        LibAppStorage.AuditEventType eventType,
        bytes32 dataHash
    ) external;

    function logSanctionsEvent(
        address entity,
        LibAppStorage.AuditEventType eventType,
        bytes32 dataHash
    ) external;
}
