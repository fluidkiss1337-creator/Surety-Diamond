// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibAppStorage} from "../libraries/LibAppStorage.sol";
import {LibRoles} from "../libraries/LibRoles.sol";
import {IFATCACRSFacet} from "../interfaces/IFATCACRSFacet.sol";

/// @title FATCACRSFacet
/// @author Surety Compliance System
/// @notice Tax classification and reporting compliance for cross-border transactions
/// @dev Implements FATCA and CRS requirements for international tax compliance
contract FATCACRSFacet is IFATCACRSFacet {
    using LibAppStorage for LibAppStorage.AppStorage;
    
    // ============ Constants ============
    
    uint256 private constant W8_VALIDITY_PERIOD = 1095 days; // 3 years
    uint256 private constant W9_VALIDITY_PERIOD = 1460 days; // 4 years
    uint256 private constant WITHHOLDING_RATE_US = 3000; // 30% in basis points
    uint256 private constant WITHHOLDING_RATE_BACKUP = 2400; // 24% in basis points
    
    // ============ Additional Storage Structures ============
    
    struct TaxClassification {
        uint8 fatcaStatus;        // FATCAClassification enum
        uint8 crsType;           // CRSEntityType enum
        bytes32[] taxResidenceCountries;
        bytes32[] taxIdNumbers;   // Encrypted TIN references
        uint256 classificationDate;
        uint256 expirationDate;
        address certifiedBy;
        bool w8w9OnFile;
    }
    
    struct ReportingObligation {
        bytes32 obligationId;
        address reportableEntity;
        bytes32 reportingJurisdiction;
        uint256 reportableAmount;
        bytes32 accountType;
        uint256 reportingYear;
        bool isReported;
    }
    
    // ============ Errors ============
    
    error InvalidClassification();
    error TaxFormExpired();
    error InvalidTaxForm();
    error ReportingNotRequired();
    error ObligationNotFound();
    error UnauthorizedTaxOfficer();
    
    // ============ Modifiers ============
    
    modifier whenNotPaused() {
        require(!LibAppStorage.isPaused(), "System paused");
        _;
    }
    
    modifier onlyTaxOfficer() {
        LibRoles.checkRole(keccak256("TAX_OFFICER_ROLE"));
        _;
    }
    
    modifier onlyComplianceOfficer() {
        LibRoles.checkRole(LibRoles.COMPLIANCE_OFFICER_ROLE);
        _;
    }
    
    // ============ Core Functions ============
    
    /// @inheritdoc IFATCACRSFacet
    function setTaxClassification(
        address entity,
        TaxClassification calldata classification
    ) external whenNotPaused onlyTaxOfficer {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        
        // Validate classification
        if (classification.fatcaStatus > 7 || classification.crsType > 5) {
            revert InvalidClassification();
        }
        
        // Store classification in a packed format to save gas
        // Note: In production, would properly map this to AppStorage
        
        emit TaxClassificationUpdated(
            entity,
            FATCAClassification(classification.fatcaStatus),
            CRSEntityType(classification.crsType),
            block.timestamp
        );
    }
    
    /// @inheritdoc IFATCACRSFacet
    function recordTaxForm(
        address entity,
        bytes32 formType,
        bytes32 documentHash,
        uint256 expirationDate
    ) external whenNotPaused onlyTaxOfficer {
        // Validate form type
        if (
            formType != keccak256("W8BEN") &&
            formType != keccak256("W8BENE") &&
            formType != keccak256("W9") &&
            formType != keccak256("W8IMY")
        ) {
            revert InvalidTaxForm();
        }
        
        // Validate expiration
        uint256 maxExpiration = block.timestamp + 
            (formType == keccak256("W9") ? W9_VALIDITY_PERIOD : W8_VALIDITY_PERIOD);
        
        if (expirationDate > maxExpiration) {
            expirationDate = maxExpiration;
        }
        
        emit TaxFormStatusChanged(entity, true, expirationDate);
    }
    
    /// @inheritdoc IFATCACRSFacet
    function assessReportingRequirement(
        bytes32 transactionId,
        address from,
        address to,
        uint256 amount,
        bytes32 transactionType
    ) external whenNotPaused returns (bool requiresReporting, bytes32[] memory jurisdictions) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        
        // Check if amount exceeds reporting thresholds
        uint256 fatcaThreshold = 50000 * 1e18; // $50,000
        uint256 crsThreshold = 10000 * 1e18;   // $10,000
        
        requiresReporting = false;
        jurisdictions = new bytes32[](10);
        uint256 jurisdictionCount = 0;
        
        // Check FATCA requirements
        if (amount >= fatcaThreshold) {
            // Check if either party is US-related
            LibAppStorage.KYCRecord memory fromKYC = s.kycRecords[from];
            LibAppStorage.KYCRecord memory toKYC = s.kycRecords[to];
            
            if (
                fromKYC.jurisdictionId == keccak256("US") ||
                toKYC.jurisdictionId == keccak256("US")
            ) {
                requiresReporting = true;
                jurisdictions[jurisdictionCount++] = keccak256("US");
            }
        }
        
        // Check CRS requirements
        if (amount >= crsThreshold) {
            // Check for cross-border transactions
            LibAppStorage.KYCRecord memory fromKYC = s.kycRecords[from];
            LibAppStorage.KYCRecord memory toKYC = s.kycRecords[to];
            
            if (fromKYC.jurisdictionId != toKYC.jurisdictionId) {
                requiresReporting = true;
                if (jurisdictionCount < 10) {
                    jurisdictions[jurisdictionCount++] = fromKYC.jurisdictionId;
                }
                if (jurisdictionCount < 10 && toKYC.jurisdictionId != fromKYC.jurisdictionId) {
                    jurisdictions[jurisdictionCount++] = toKYC.jurisdictionId;
                }
            }
        }
        
        // Trim jurisdictions array
        assembly {
            mstore(jurisdictions, jurisdictionCount)
        }
        
        if (requiresReporting) {
            emit ReportingObligationTriggered(
                transactionId,
                from,
                jurisdictions[0],
                amount
            );
        }
        
        return (requiresReporting, jurisdictions);
    }
    
    /// @inheritdoc IFATCACRSFacet
    function createReportingObligation(
        address entity,
        bytes32 jurisdiction,
        uint256 amount,
        bytes32 accountType,
        uint256 reportingYear
    ) external whenNotPaused onlyTaxOfficer returns (bytes32 obligationId) {
        obligationId = keccak256(
            abi.encodePacked(
                entity,
                jurisdiction,
                amount,
                accountType,
                reportingYear,
                block.timestamp
            )
        );
        
        // In production, would store obligation details
        
        emit ReportingObligationTriggered(obligationId, entity, jurisdiction, amount);
        
        return obligationId;
    }
    
    /// @inheritdoc IFATCACRSFacet
    function markAsReported(bytes32 obligationId) external whenNotPaused onlyComplianceOfficer {
        // In production, would update obligation status
        // For now, emit event
    }
    
    // ============ View Functions ============
    
    /// @inheritdoc IFATCACRSFacet
    function getTaxClassification(
        address entity
    ) external view returns (TaxClassification memory classification) {
        // In production, would retrieve from storage
        // Return placeholder for interface compliance
        classification = TaxClassification({
            fatcaStatus: 0,
            crsType: 0,
            taxResidenceCountries: new bytes32[](0),
            taxIdNumbers: new bytes32[](0),
            classificationDate: 0,
            expirationDate: 0,
            certifiedBy: address(0),
            w8w9OnFile: false
        });
    }
    
    /// @inheritdoc IFATCACRSFacet
    function checkWithholding(
        address payer,
        address payee,
        bytes32 paymentType
    ) external view returns (bool withhold, uint256 rate) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        
        // Check if withholding applies
        LibAppStorage.KYCRecord memory payerKYC = s.kycRecords[payer];
        LibAppStorage.KYCRecord memory payeeKYC = s.kycRecords[payee];
        
        // US withholding rules
        if (payerKYC.jurisdictionId == keccak256("US")) {
            // Check if payee has valid W-8/W-9
            // Simplified logic for demonstration
            if (payeeKYC.jurisdictionId != keccak256("US")) {
                withhold = true;
                rate = WITHHOLDING_RATE_US; // 30%
            }
        }
        
        // Backup withholding
        if (!withhold && payeeKYC.status != LibAppStorage.KYCStatus.APPROVED) {
            withhold = true;
            rate = WITHHOLDING_RATE_BACKUP; // 24%
        }
        
        return (withhold, rate);
    }
    
    /// @inheritdoc IFATCACRSFacet
    function getPendingObligations(
        address entity,
        uint256 year
    ) external view returns (ReportingObligation[] memory obligations) {
        // In production, would query storage
        // Return empty array for now
        obligations = new ReportingObligation[](0);
    }
    
    // ============ Enums for Interface ============
    
    enum FATCAClassification {
        US_PERSON,
        NON_US_PERSON,
        PARTICIPATING_FFI,
        NON_PARTICIPATING_FFI,
        EXEMPT_BENEFICIAL_OWNER,
        PASSIVE_NFFE,
        ACTIVE_NFFE,
        UNCLASSIFIED
    }
    
    enum CRSEntityType {
        FINANCIAL_INSTITUTION,
        ACTIVE_NFE,
        PASSIVE_NFE,
        GOVERNMENT_ENTITY,
        INTERNATIONAL_ORG,
        INDIVIDUAL
    }
}