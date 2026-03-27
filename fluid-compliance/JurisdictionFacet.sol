// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibAppStorage} from "../libraries/LibAppStorage.sol";
import {LibRoles} from "../libraries/LibRoles.sol";
import {IJurisdictionFacet} from "../interfaces/IJurisdictionFacet.sol";

/// @title JurisdictionFacet
/// @author Surety Compliance System
/// @notice Multi-jurisdiction compliance rule management
/// @dev Handles cross-border compliance and jurisdiction-specific requirements
contract JurisdictionFacet is IJurisdictionFacet {
    using LibAppStorage for LibAppStorage.AppStorage;
    
    // ============ Storage Structures ============
    
    struct JurisdictionConfig {
        bytes32 jurisdictionId;
        bytes32 countryCode;
        bool isActive;
        
        // KYC Requirements
        LibAppStorage.KYCLevel minimumKYCLevel;
        uint256 kycExpirationPeriod;
        bool requiresPEPScreening;
        
        // AML Thresholds
        uint256 reportingThreshold;
        uint256 enhancedDueDiligenceThreshold;
        
        // Sanctions
        LibAppStorage.SanctionsList[] applicableSanctionsLists;
        
        // Tax
        bool fatcaApplicable;
        bool crsApplicable;
        uint256 withholdingRate;
        
        // Operational
        bool allowedForFactoring;
        uint256 maxTransactionAmount;
        bytes32[] blockedCounterparties;
    }
    
    struct CrossBorderAssessment {
        bytes32 sourceJurisdiction;
        bytes32 destinationJurisdiction;
        bool isPermitted;
        LibAppStorage.KYCLevel requiredKYCLevel;
        uint256 additionalWithholding;
        bool requiresEnhancedDueDiligence;
        bytes32[] applicableRestrictions;
    }
    
    // ============ Additional Storage ============
    
    mapping(bytes32 => JurisdictionConfig) private jurisdictionConfigs;
    mapping(address => bytes32) private entityJurisdictions;
    mapping(bytes32 => mapping(bytes32 => bool)) private blockedPairs;
    
    // ============ Errors ============
    
    error JurisdictionNotFound();
    error InvalidJurisdiction();
    error TransactionNotPermitted();
    error JurisdictionBlocked();
    error ExceedsTransactionLimit();
    
    // ============ Modifiers ============
    
    modifier whenNotPaused() {
        require(!LibAppStorage.isPaused(), "System paused");
        _;
    }
    
    modifier onlyAdmin() {
        LibRoles.checkRole(LibRoles.DEFAULT_ADMIN_ROLE);
        _;
    }
    
    modifier onlyComplianceOfficer() {
        LibRoles.checkRole(LibRoles.COMPLIANCE_OFFICER_ROLE);
        _;
    }
    
    // ============ Core Functions ============
    
    /// @inheritdoc IJurisdictionFacet
    function configureJurisdiction(
        JurisdictionConfig calldata config
    ) external whenNotPaused onlyAdmin {
        // Validate configuration
        if (config.jurisdictionId == bytes32(0)) {
            revert InvalidJurisdiction();
        }
        
        // Store configuration
        jurisdictionConfigs[config.jurisdictionId] = config;
        
        emit JurisdictionUpdated(config.jurisdictionId, config.isActive, block.timestamp);
    }
    
    /// @inheritdoc IJurisdictionFacet
    function assignEntityJurisdiction(
        address entity,
        bytes32 jurisdictionId
    ) external whenNotPaused onlyComplianceOfficer {
        // Verify jurisdiction exists
        if (!jurisdictionConfigs[jurisdictionId].isActive) {
            revert JurisdictionNotFound();
        }
        
        entityJurisdictions[entity] = jurisdictionId;
        
        emit EntityJurisdictionAssigned(entity, jurisdictionId);
    }
    
    /// @inheritdoc IJurisdictionFacet
    function assessCrossBorder(
        address from,
        address to,
        uint256 amount,
        bytes32 transactionType
    ) external whenNotPaused returns (CrossBorderAssessment memory assessment) {
        bytes32 sourceJurisdiction = entityJurisdictions[from];
        bytes32 destJurisdiction = entityJurisdictions[to];
        
        assessment.sourceJurisdiction = sourceJurisdiction;
        assessment.destinationJurisdiction = destJurisdiction;
        
        // Check if transaction is blocked
        if (blockedPairs[sourceJurisdiction][destJurisdiction]) {
            assessment.isPermitted = false;
            emit CrossBorderAssessed(
                keccak256(abi.encodePacked(from, to, block.timestamp)),
                sourceJurisdiction,
                destJurisdiction,
                false
            );
            revert TransactionNotPermitted();
        }
        
        // Get jurisdiction configs
        JurisdictionConfig memory sourceConfig = jurisdictionConfigs[sourceJurisdiction];
        JurisdictionConfig memory destConfig = jurisdictionConfigs[destJurisdiction];
        
        // Check transaction limits
        if (amount > sourceConfig.maxTransactionAmount || 
            amount > destConfig.maxTransactionAmount) {
            assessment.isPermitted = false;
            revert ExceedsTransactionLimit();
        }
        
        // Determine required KYC level
        assessment.requiredKYCLevel = sourceConfig.minimumKYCLevel > destConfig.minimumKYCLevel 
            ? sourceConfig.minimumKYCLevel 
            : destConfig.minimumKYCLevel;
        
        // Check for enhanced due diligence
        assessment.requiresEnhancedDueDiligence = 
            amount > sourceConfig.enhancedDueDiligenceThreshold ||
            amount > destConfig.enhancedDueDiligenceThreshold;
        
        // Calculate additional withholding
        if (sourceJurisdiction != destJurisdiction) {
            assessment.additionalWithholding = destConfig.withholdingRate;
        }
        
        assessment.isPermitted = true;
        
        emit CrossBorderAssessed(
            keccak256(abi.encodePacked(from, to, block.timestamp)),
            sourceJurisdiction,
            destJurisdiction,
            true
        );
        
        return assessment;
    }
    
    /// @inheritdoc IJurisdictionFacet
    function blockJurisdictionOperation(
        bytes32 jurisdictionId,
        bytes32 operationType
    ) external whenNotPaused onlyAdmin {
        JurisdictionConfig storage config = jurisdictionConfigs[jurisdictionId];
        
        if (operationType == keccak256("FACTORING")) {
            config.allowedForFactoring = false;
        }
        
        emit JurisdictionUpdated(jurisdictionId, config.isActive, block.timestamp);
    }
    
    /// @inheritdoc IJurisdictionFacet
    function blockCounterpartyPair(
        bytes32 jurisdiction1,
        bytes32 jurisdiction2,
        string calldata reason
    ) external whenNotPaused onlyComplianceOfficer {
        blockedPairs[jurisdiction1][jurisdiction2] = true;
        blockedPairs[jurisdiction2][jurisdiction1] = true;
        
        // Log reason in event
        emit CrossBorderAssessed(
            keccak256(abi.encodePacked(jurisdiction1, jurisdiction2, reason)),
            jurisdiction1,
            jurisdiction2,
            false
        );
    }
    
    // ============ View Functions ============
    
    /// @inheritdoc IJurisdictionFacet
    function getJurisdiction(
        bytes32 jurisdictionId
    ) external view returns (JurisdictionConfig memory config) {
        config = jurisdictionConfigs[jurisdictionId];
    }
    
    /// @inheritdoc IJurisdictionFacet
    function getEntityJurisdiction(
        address entity
    ) external view returns (bytes32 jurisdictionId) {
        jurisdictionId = entityJurisdictions[entity];
    }
    
    /// @inheritdoc IJurisdictionFacet
    function isTransactionPermitted(
        bytes32 sourceJurisdiction,
        bytes32 destJurisdiction,
        bytes32 transactionType
    ) external view returns (bool permitted) {
        if (blockedPairs[sourceJurisdiction][destJurisdiction]) {
            return false;
        }
        
        JurisdictionConfig memory sourceConfig = jurisdictionConfigs[sourceJurisdiction];
        JurisdictionConfig memory destConfig = jurisdictionConfigs[destJurisdiction];
        
        permitted = sourceConfig.isActive && destConfig.isActive;
        
        // Check specific transaction type restrictions
        if (transactionType == keccak256("FACTORING")) {
            permitted = permitted && sourceConfig.allowedForFactoring && destConfig.allowedForFactoring;
        }
    }
    
    /// @inheritdoc IJurisdictionFacet
    function getMinimumKYCLevel(
        bytes32 jurisdictionId
    ) external view returns (LibAppStorage.KYCLevel level) {
        level = jurisdictionConfigs[jurisdictionId].minimumKYCLevel;
    }
}