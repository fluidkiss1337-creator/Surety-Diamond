// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibAppStorage} from "../libraries/LibAppStorage.sol";

/// @title IInvoiceRegistryFacet
/// @notice Interface for on-chain invoice registration and trade finance lifecycle
interface IInvoiceRegistryFacet {

    event InvoiceRegistered(bytes32 indexed invoiceHash, address indexed seller, address indexed buyer, uint256 amount, uint256 dueDate);
    event InvoiceStatusChanged(bytes32 indexed invoiceHash, LibAppStorage.InvoiceStatus previousStatus, LibAppStorage.InvoiceStatus newStatus);
    event DoubleFactoringAttempt(bytes32 indexed invoiceHash, address indexed attacker, address existingFactor, uint256 timestamp);
    event InvoiceFactored(bytes32 indexed invoiceHash, bytes32 indexed agreementId, address indexed factor, uint256 advanceAmount);

    function registerInvoice(
        LibAppStorage.InvoiceRecord calldata invoice,
        bytes calldata signature
    ) external returns (bytes32 invoiceHash);

    function verifyInvoice(bytes32 invoiceHash, bytes calldata buyerSignature) external;

    function canFactor(
        bytes32 invoiceHash
    ) external view returns (bool canFactorInvoice, string memory reason);

    function createFactoringAgreement(
        bytes32 invoiceHash,
        address factor,
        uint256 advanceRate,
        uint256 feeRate
    ) external returns (bytes32 agreementId);

    function recordPayment(bytes32 invoiceHash, uint256 paymentAmount, bytes32 paymentReference) external;

    function raiseDispute(bytes32 invoiceHash, string calldata reason) external;

    function getInvoice(
        bytes32 invoiceHash
    ) external view returns (LibAppStorage.InvoiceRecord memory record);

    function getFactoringStatus(
        bytes32 invoiceHash
    ) external view returns (bool isFactored, address factor);

    function isInvoiceHashUsed(bytes32 invoiceHash) external view returns (bool isUsed);
}
