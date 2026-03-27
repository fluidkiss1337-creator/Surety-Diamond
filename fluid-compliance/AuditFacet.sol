// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibAppStorage} from "../libraries/LibAppStorage.sol";
import {LibRoles} from "../libraries/LibRoles.sol";
import {IAuditFacet} from "../interfaces/IAuditFacet.sol";

/// @title AuditFacet
/// @author Surety Compliance System
/// @notice Immutable audit logging for regulatory compliance
/// @dev Implements hash-chained audit trail with tamper detection
contract AuditFacet is IAuditFacet {
    using LibAppStorage for LibAppStorage.AppStorage;
    
    // ============ Events (defined in interface) ============
    
    // ============ Errors ============
    
    error InvalidAuditEntry();
    error AuditChainBroken();
    error UnauthorizedAuditor();
    
    // ============ Modifiers ============
    
    modifier onlyAuditor() {
        LibRoles.checkRole(LibRoles.AUDITOR_ROLE);
        _;
    }
    
    modifier onlyInternal() {
        // Only allow calls from other facets (via delegatecall)
        require(address(this) == msg.sender, "Internal only");
        _;
    }
    
    // ============ Core Functions ============
    
    /// @inheritdoc IAuditFacet
    function logAudit(
        AuditEventType eventType,
        address subject,
        bytes32 dataHash
    ) external onlyInternal returns (bytes32 entryId) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        
        // Generate entry ID
        entryId = keccak256(
            abi.encodePacked(
                eventType,
                msg.sender,
                subject,
                dataHash,
                block.timestamp,
                s.totalAuditEntries
            )
        );
        
        // Create hash chain
        bytes32 previousHash = s.latestAuditHash;
        bytes32 newHash = keccak256(
            abi.encodePacked(
                entryId,
                previousHash,
                block.timestamp
            )
        );
        
        // Update storage
        s.auditChain[previousHash] = newHash;
        s.latestAuditHash = newHash;
        s.totalAuditEntries++;
        
        emit AuditLogged(
            entryId,
            eventType,
            msg.sender,
            subject,
            dataHash,
            block.timestamp
        );
        
        return entryId;
    }
    
    /// @inheritdoc IAuditFacet
    function verifyAuditChain(
        bytes32 startEntry,
        bytes32 endEntry
    ) external view returns (bool isValid) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        
        bytes32 current = startEntry;
        uint256 maxIterations = 1000; // Prevent infinite loop
        uint256 iterations = 0;
        
        while (current != endEntry && iterations < maxIterations) {
            bytes32 next = s.auditChain[current];
            if (next == bytes32(0)) {
                return false; // Chain broken
            }
            current = next;
            iterations++;
        }
        
        return current == endEntry;
    }
    
    // ============ View Functions ============
    
    /// @inheritdoc IAuditFacet
    function getAuditEntry(bytes32 entryId) external view returns (AuditEntry memory entry) {
        // In production, would store and retrieve full entries
        // For now, return placeholder
        entry = AuditEntry({
            entryId: entryId,
            eventType: AuditEventType.KYC_INITIATED,
            actor: address(0),
            subject: address(0),
            dataHash: bytes32(0),
            timestamp: block.timestamp,
            previousEntryHash: bytes32(0)
        });
    }
    
    /// @inheritdoc IAuditFacet
    function getEntityAuditTrail(
        address entity,
        AuditEventType eventType,
        uint256 fromTimestamp,
        uint256 toTimestamp
    ) external view returns (AuditEntry[] memory entries) {
        // In production, would implement efficient storage and retrieval
        // For now, return empty array
        entries = new AuditEntry[](0);
    }
    
    /// @inheritdoc IAuditFacet
    function getLatestAuditHash() external view returns (bytes32 hash) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        hash = s.latestAuditHash;
    }
    
    /// @inheritdoc IAuditFacet
    function getAuditStats(
        AuditEventType eventType,
        uint256 period
    ) external view returns (uint256 count) {
        // In production, would track stats
        // For now, return total count
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        count = s.totalAuditEntries;
    }
    
    // ============ Public Logging Functions ============
    
    /// @notice Log KYC event
    /// @param entity Entity address
    /// @param eventType KYC event type
    /// @param dataHash Event data hash
    function logKYCEvent(
        address entity,
        AuditEventType eventType,
        bytes32 dataHash
    ) external {
        _requireKYCEventType(eventType);
        _logAuditInternal(eventType, entity, dataHash);
    }
    
    /// @notice Log AML event
    /// @param entity Entity address
    /// @param eventType AML event type
    /// @param dataHash Event data hash
    function logAMLEvent(
        address entity,
        AuditEventType eventType,
        bytes32 dataHash
    ) external {
        _requireAMLEventType(eventType);
        _logAuditInternal(eventType, entity, dataHash);
    }
    
    /// @notice Log sanctions event
    /// @param entity Entity address
    /// @param eventType Sanctions event type
    /// @param dataHash Event data hash
    function logSanctionsEvent(
        address entity,
        AuditEventType eventType,
        bytes32 dataHash
    ) external {
        _requireSanctionsEventType(eventType);
        _logAuditInternal(eventType, entity, dataHash);
    }
    
    // ============ Internal Functions ============
    
    /// @notice Internal audit logging
    /// @param eventType Event type
    /// @param subject Subject address
    /// @param dataHash Data hash
    function _logAuditInternal(
        AuditEventType eventType,
        address subject,
        bytes32 dataHash
    ) internal {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        
        bytes32 entryId = keccak256(
            abi.encodePacked(
                eventType,
                msg.sender,
                subject,
                dataHash,
                block.timestamp,
                s.totalAuditEntries
            )
        );
        
        bytes32 previousHash = s.latestAuditHash;
        bytes32 newHash = keccak256(
            abi.encodePacked(
                entryId,
                previousHash,
                block.timestamp
            )
        );
        
        s.auditChain[previousHash] = newHash;
        s.latestAuditHash = newHash;
        s.totalAuditEntries++;
        
        emit AuditLogged(
            entryId,
            eventType,
            msg.sender,
            subject,
            dataHash,
            block.timestamp
        );
    }
    
    /// @notice Validate KYC event type
    function _requireKYCEventType(AuditEventType eventType) internal pure {
        require(
            eventType == AuditEventType.KYC_INITIATED ||
            eventType == AuditEventType.KYC_APPROVED ||
            eventType == AuditEventType.KYC_REJECTED ||
            eventType == AuditEventType.KYC_EXPIRED,
            "Invalid KYC event"
        );
    }
    
    /// @notice Validate AML event type
    function _requireAMLEventType(AuditEventType eventType) internal pure {
        require(
            eventType == AuditEventType.TRANSACTION_ASSESSED ||
            eventType == AuditEventType.TRANSACTION_BLOCKED ||
            eventType == AuditEventType.SAR_FILED,
            "Invalid AML event"
        );
    }
    
    /// @notice Validate sanctions event type
    function _requireSanctionsEventType(AuditEventType eventType) internal pure {
        require(
            eventType == AuditEventType.SANCTIONS_SCREENED ||
            eventType == AuditEventType.SANCTIONS_MATCH ||
            eventType == AuditEventType.SANCTIONS_CLEARED,
            "Invalid sanctions event"
        );
    }
}