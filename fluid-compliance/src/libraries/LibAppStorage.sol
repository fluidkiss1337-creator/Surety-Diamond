// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title LibAppStorage
/// @author Surety Compliance System
/// @notice Central storage management for the Surety compliance diamond
/// @dev All facets share this storage layout via delegatecall
library LibAppStorage {
    bytes32 constant STORAGE_POSITION = keccak256("surety.compliance.diamond.storage");

    // ============ Data Structures ============

    /// @notice KYC verification levels aligned with FATF recommendations
    enum KYCLevel {
        NONE,          // 0: Not verified
        BASIC,         // 1: Name, DOB, Address
        STANDARD,      // 2: Basic + Government ID
        ENHANCED,      // 3: Standard + Source of funds, PEP check
        INSTITUTIONAL  // 4: Enhanced + Corporate structure, UBO verification
    }

    /// @notice KYC verification status
    enum KYCStatus {
        PENDING,      // 0: Awaiting verification
        APPROVED,     // 1: Verified and active
        REJECTED,     // 2: Failed verification
        EXPIRED,      // 3: Needs renewal
        SUSPENDED,    // 4: Temporarily inactive
        UNDER_REVIEW  // 5: Re-verification in progress
    }

    /// @notice Core KYC record
    struct KYCRecord {
        bytes32 identityHash;    // Hash of identity documents
        KYCLevel level;          // Verification level achieved
        KYCStatus status;        // Current status
        uint256 verificationDate; // Timestamp of verification
        uint256 expirationDate;  // When renewal needed
        bytes32 jurisdictionId;  // Applicable jurisdiction
        address verifier;        // Who verified
        bytes32 documentRoot;    // Merkle root of documents
        bool isPEP;              // Politically Exposed Person
        uint256 riskScore;       // 0-1000 scale
    }

    /// @notice AML risk levels
    enum RiskLevel {
        LOW,       // 0: Normal processing
        MEDIUM,    // 1: Enhanced monitoring
        HIGH,      // 2: Manual review required
        PROHIBITED // 3: Block all transactions
    }

    /// @notice Risk assessment record
    struct RiskScore {
        uint256 score;           // 0-1000 scale
        RiskLevel level;         // Categorized risk
        uint256 calculationDate; // When assessed
        bytes32[] riskFactors;   // Contributing factors
        bool requiresReview;     // Manual review flag
    }

    /// @notice Transaction monitoring record
    struct TransactionRecord {
        bytes32 transactionId;   // Unique identifier
        address from;            // Sender
        address to;              // Recipient
        uint256 amount;          // Value transferred
        bytes32 currency;        // Currency code
        uint256 timestamp;       // When occurred
        bytes32 transactionType; // Category
        RiskScore riskAssessment; // Risk evaluation
        bool flagged;            // Suspicious flag
    }

    /// @notice Sanctions list types
    enum SanctionsList {
        OFAC_SDN,  // 0: US SDN List
        OFAC_CONS, // 1: US Consolidated
        UN_SC,     // 2: UN Security Council
        EU_CONS,   // 3: EU Consolidated
        UK_HMT,    // 4: UK Treasury
        CUSTOM     // 5: Internal list
    }

    /// @notice Sanction record
    struct SanctionRecord {
        bytes32 entityHash;    // Identity hash
        SanctionsList[] lists; // Which lists
        uint256 listingDate;   // When added
        uint256 lastVerified;  // Last check
        bytes32 programCode;   // Sanction program
        bool isActive;         // Current status
    }

    /// @notice Invoice lifecycle status
    enum InvoiceStatus {
        REGISTERED,     // 0: Initial registration
        VERIFIED,       // 1: Buyer confirmed
        FACTORED,       // 2: Financing arranged
        PARTIALLY_PAID, // 3: Partial payment
        PAID,           // 4: Fully settled
        DISPUTED,       // 5: Under dispute
        CANCELLED       // 6: Cancelled
    }

    /// @notice Invoice record
    struct InvoiceRecord {
        bytes32 invoiceHash;      // Document hash
        address seller;           // Vendor
        address buyer;            // Purchaser
        uint256 amount;           // Invoice value
        bytes32 currency;         // Currency code
        uint256 issueDate;        // Creation date
        uint256 dueDate;          // Payment due
        InvoiceStatus status;     // Current state
        bytes32 purchaseOrderRef; // PO reference
        uint256 registrationTime; // When registered
        address registeredBy;     // Who registered
    }

    /// @notice Main storage struct
    struct AppStorage {
        // ===== KYC Storage =====
        mapping(address => KYCRecord) kycRecords;
        mapping(bytes32 => bool) verifiedIdentities;
        mapping(address => KYCStatus) entityStatus;

        // ===== AML Storage =====
        mapping(address => RiskScore) riskScores;
        mapping(address => TransactionRecord[]) transactionHistory;
        mapping(address => uint256) suspiciousActivityCount;
        uint256 reportingThreshold;

        // ===== Sanctions Storage =====
        mapping(bytes32 => bool) sanctionedEntities;
        mapping(bytes32 => SanctionRecord) sanctionDetails;
        mapping(SanctionsList => bytes32) sanctionsListRoots;
        mapping(SanctionsList => uint256) lastSanctionsUpdate;

        // ===== Invoice Registry =====
        mapping(bytes32 => InvoiceRecord) invoices;
        mapping(bytes32 => bool) usedInvoiceHashes;
        mapping(address => bytes32[]) sellerInvoices;
        mapping(address => bytes32[]) buyerInvoices;

        // ===== Access Control =====
        mapping(bytes32 => mapping(address => bool)) roleMembers;
        mapping(bytes32 => bytes32) roleAdmins;

        // ===== System State =====
        bool systemPaused;
        uint256 lastSystemUpdate;
        address treasuryAddress;
        uint256 timelockDuration;

        // ===== Audit Trail =====
        bytes32 latestAuditHash;
        uint256 totalAuditEntries;
        mapping(bytes32 => bytes32) auditChain; // entryHash => nextEntryHash
    }

    /// @notice Get the storage pointer
    /// @return s Storage struct pointer
    function appStorage() internal pure returns (AppStorage storage s) {
        bytes32 position = STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }

    /// @notice Check if system is paused
    /// @return paused Whether system is paused
    function isPaused() internal view returns (bool paused) {
        return appStorage().systemPaused;
    }
}
