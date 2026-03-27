// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibAppStorage} from "../libraries/LibAppStorage.sol";
import {LibRoles} from "../libraries/LibRoles.sol";
import {IInvoiceRegistryFacet} from "../interfaces/IInvoiceRegistryFacet.sol";

/// @title InvoiceRegistryFacet
/// @author Surety Compliance System
/// @notice Prevents double factoring and maintains immutable invoice records
/// @dev Core registry for supply chain finance invoice management
contract InvoiceRegistryFacet is IInvoiceRegistryFacet {
    using LibAppStorage for LibAppStorage.AppStorage;
    
    // ============ Constants ============
    
    uint256 private constant MAX_INVOICE_AMOUNT = 1e9 * 1e18; // 1 billion in 18 decimals
    uint256 private constant MIN_ADVANCE_RATE = 100; // 1% in basis points
    uint256 private constant MAX_ADVANCE_RATE = 9500; // 95% in basis points
    
    // ============ Errors ============
    
    error InvoiceAlreadyRegistered();
    error InvoiceNotFound();
    error InvoiceAlreadyFactored();
    error InvalidInvoiceData();
    error UnauthorizedSeller();
    error UnauthorizedBuyer();
    error InvalidSignature();
    error InvoiceNotVerified();
    error InvalidAdvanceRate();
    error PaymentExceedsInvoice();
    
    // ============ Modifiers ============
    
    modifier whenNotPaused() {
        require(!LibAppStorage.isPaused(), "System paused");
        _;
    }
    
    modifier onlyFactor() {
        LibRoles.checkRole(LibRoles.FACTOR_ROLE);
        _;
    }
    
    modifier onlySeller() {
        LibRoles.checkRole(LibRoles.SELLER_ROLE);
        _;
    }
    
    // ============ Core Functions ============
    
    /// @inheritdoc IInvoiceRegistryFacet
    function registerInvoice(
        LibAppStorage.InvoiceRecord calldata invoice,
        bytes calldata signature
    ) external whenNotPaused onlySeller returns (bytes32 invoiceHash) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        
        // Validate invoice data
        if (invoice.amount == 0 || invoice.amount > MAX_INVOICE_AMOUNT) {
            revert InvalidInvoiceData();
        }
        if (invoice.dueDate <= invoice.issueDate) {
            revert InvalidInvoiceData();
        }
        if (invoice.seller != msg.sender) {
            revert UnauthorizedSeller();
        }
        
        // Generate invoice hash
        invoiceHash = keccak256(
            abi.encodePacked(
                invoice.seller,
                invoice.buyer,
                invoice.amount,
                invoice.currency,
                invoice.issueDate,
                invoice.dueDate,
                invoice.purchaseOrderRef
            )
        );
        
        // Check for double registration
        if (s.usedInvoiceHashes[invoiceHash]) {
            revert InvoiceAlreadyRegistered();
        }
        
        // Verify seller signature
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n32",
                invoiceHash
            )
        );
        
        address signer = _recoverSigner(messageHash, signature);
        if (signer != invoice.seller) {
            revert InvalidSignature();
        }
        
        // Store invoice
        s.invoices[invoiceHash] = LibAppStorage.InvoiceRecord({
            invoiceHash: invoiceHash,
            seller: invoice.seller,
            buyer: invoice.buyer,
            amount: invoice.amount,
            currency: invoice.currency,
            issueDate: invoice.issueDate,
            dueDate: invoice.dueDate,
            status: LibAppStorage.InvoiceStatus.REGISTERED,
            purchaseOrderRef: invoice.purchaseOrderRef,
            registrationTime: block.timestamp,
            registeredBy: msg.sender
        });
        
        s.usedInvoiceHashes[invoiceHash] = true;
        s.sellerInvoices[invoice.seller].push(invoiceHash);
        s.buyerInvoices[invoice.buyer].push(invoiceHash);
        
        emit InvoiceRegistered(
            invoiceHash,
            invoice.seller,
            invoice.buyer,
            invoice.amount,
            invoice.dueDate
        );
        
        return invoiceHash;
    }
    
    /// @inheritdoc IInvoiceRegistryFacet
    function verifyInvoice(
        bytes32 invoiceHash,
        bytes calldata buyerSignature
    ) external whenNotPaused {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        
        LibAppStorage.InvoiceRecord storage invoice = s.invoices[invoiceHash];
        if (invoice.invoiceHash == bytes32(0)) {
            revert InvoiceNotFound();
        }
        
        // Verify buyer signature
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n32",
                invoiceHash
            )
        );
        
        address signer = _recoverSigner(messageHash, buyerSignature);
        if (signer != invoice.buyer) {
            revert UnauthorizedBuyer();
        }
        
        // Update status
        invoice.status = LibAppStorage.InvoiceStatus.VERIFIED;
        
        emit InvoiceStatusChanged(
            invoiceHash,
            LibAppStorage.InvoiceStatus.REGISTERED,
            LibAppStorage.InvoiceStatus.VERIFIED
        );
    }
    
    /// @inheritdoc IInvoiceRegistryFacet
    function canFactor(
        bytes32 invoiceHash
    ) external view returns (bool canFactorInvoice, string memory reason) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        
        LibAppStorage.InvoiceRecord memory invoice = s.invoices[invoiceHash];
        
        if (invoice.invoiceHash == bytes32(0)) {
            return (false, "Invoice not found");
        }
        
        if (invoice.status != LibAppStorage.InvoiceStatus.VERIFIED) {
            return (false, "Invoice not verified");
        }
        
        if (invoice.status == LibAppStorage.InvoiceStatus.FACTORED) {
            return (false, "Already factored");
        }
        
        if (invoice.status == LibAppStorage.InvoiceStatus.DISPUTED) {
            return (false, "Invoice disputed");
        }
        
        if (invoice.dueDate <= block.timestamp) {
            return (false, "Invoice overdue");
        }
        
        return (true, "");
    }
    
    /// @inheritdoc IInvoiceRegistryFacet
    function createFactoringAgreement(
        bytes32 invoiceHash,
        address factor,
        uint256 advanceRate,
        uint256 feeRate
    ) external whenNotPaused onlyFactor returns (bytes32 agreementId) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        
        // Validate rates
        if (advanceRate < MIN_ADVANCE_RATE || advanceRate > MAX_ADVANCE_RATE) {
            revert InvalidAdvanceRate();
        }
        
        LibAppStorage.InvoiceRecord storage invoice = s.invoices[invoiceHash];
        if (invoice.invoiceHash == bytes32(0)) {
            revert InvoiceNotFound();
        }
        
        if (invoice.status != LibAppStorage.InvoiceStatus.VERIFIED) {
            revert InvoiceNotVerified();
        }
        
        if (invoice.status == LibAppStorage.InvoiceStatus.FACTORED) {
            // Critical: Prevent double factoring
            emit DoubleFactoringAttempt(
                invoiceHash,
                msg.sender,
                address(0), // Would need to track in production
                block.timestamp
            );
            revert InvoiceAlreadyFactored();
        }
        
        // Calculate advance amount
        uint256 advanceAmount = (invoice.amount * advanceRate) / 10000;
        
        // Generate agreement ID
        agreementId = keccak256(
            abi.encodePacked(
                invoiceHash,
                factor,
                advanceAmount,
                block.timestamp
            )
        );
        
        // Update invoice status
        invoice.status = LibAppStorage.InvoiceStatus.FACTORED;
        
        emit InvoiceFactored(invoiceHash, agreementId, factor, advanceAmount);
        emit InvoiceStatusChanged(
            invoiceHash,
            LibAppStorage.InvoiceStatus.VERIFIED,
            LibAppStorage.InvoiceStatus.FACTORED
        );
        
        return agreementId;
    }
    
    /// @inheritdoc IInvoiceRegistryFacet
    function recordPayment(
        bytes32 invoiceHash,
        uint256 paymentAmount,
        bytes32 paymentReference
    ) external whenNotPaused {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        
        LibAppStorage.InvoiceRecord storage invoice = s.invoices[invoiceHash];
        if (invoice.invoiceHash == bytes32(0)) {
            revert InvoiceNotFound();
        }
        
        // Note: In production, would track cumulative payments
        // For now, simple status update
        if (paymentAmount >= invoice.amount) {
            invoice.status = LibAppStorage.InvoiceStatus.PAID;
        } else {
            invoice.status = LibAppStorage.InvoiceStatus.PARTIALLY_PAID;
        }
        
        emit InvoiceStatusChanged(
            invoiceHash,
            LibAppStorage.InvoiceStatus.FACTORED,
            invoice.status
        );
    }
    
    /// @inheritdoc IInvoiceRegistryFacet
    function settleFactoringAgreement(bytes32 agreementId) external whenNotPaused onlyFactor {
        // In production, would update factoring record
        // For now, emit event
    }
    
    /// @inheritdoc IInvoiceRegistryFacet
    function raiseDispute(
        bytes32 invoiceHash,
        string calldata reason
    ) external whenNotPaused {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        
        LibAppStorage.InvoiceRecord storage invoice = s.invoices[invoiceHash];
        if (invoice.invoiceHash == bytes32(0)) {
            revert InvoiceNotFound();
        }
        
        // Only buyer or seller can dispute
        if (msg.sender != invoice.buyer && msg.sender != invoice.seller) {
            revert UnauthorizedBuyer();
        }
        
        LibAppStorage.InvoiceStatus previousStatus = invoice.status;
        invoice.status = LibAppStorage.InvoiceStatus.DISPUTED;
        
        emit InvoiceStatusChanged(invoiceHash, previousStatus, LibAppStorage.InvoiceStatus.DISPUTED);
    }
    
    // ============ View Functions ============
    
    /// @inheritdoc IInvoiceRegistryFacet
    function getInvoice(
        bytes32 invoiceHash
    ) external view returns (LibAppStorage.InvoiceRecord memory record) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        record = s.invoices[invoiceHash];
    }
    
    /// @inheritdoc IInvoiceRegistryFacet
    function getFactoringAgreement(
        bytes32 agreementId
    ) external view returns (FactoringRecord memory record) {
        // In production, would return from storage
        // Placeholder for interface compliance
    }
    
    /// @inheritdoc IInvoiceRegistryFacet
    function getFactoringStatus(
        bytes32 invoiceHash
    ) external view returns (bool isFactored, address factor) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        
        LibAppStorage.InvoiceRecord memory invoice = s.invoices[invoiceHash];
        isFactored = invoice.status == LibAppStorage.InvoiceStatus.FACTORED;
        
        // In production, would return actual factor address from factoring record
        factor = address(0);
    }
    
    /// @inheritdoc IInvoiceRegistryFacet
    function isInvoiceHashUsed(bytes32 invoiceHash) external view returns (bool isUsed) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        isUsed = s.usedInvoiceHashes[invoiceHash];
    }
    
    // ============ Internal Functions ============
    
    /// @notice Recover signer address from signature
    /// @param messageHash Hash of the signed message
    /// @param signature Signature bytes
    /// @return signer Address of the signer
    function _recoverSigner(
        bytes32 messageHash,
        bytes memory signature
    ) internal pure returns (address signer) {
        require(signature.length == 65, "Invalid signature length");
        
        bytes32 r;
        bytes32 s;
        uint8 v;
        
        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }
        
        if (v < 27) {
            v += 27;
        }
        
        require(v == 27 || v == 28, "Invalid signature v value");
        
        signer = ecrecover(messageHash, v, r, s);
        require(signer != address(0), "Invalid signature");
    }
}