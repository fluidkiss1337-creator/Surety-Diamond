// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibAppStorage} from "../libraries/LibAppStorage.sol";

/// @title IInvoiceRegistryFacet
/// @notice Interface for on-chain invoice registration and trade finance lifecycle
interface IInvoiceRegistryFacet {

    event InvoiceRegistered(bytes32 indexed invoiceHash, address indexed seller, address indexed buyer, uint256 amount, uint256 timestamp);
    event InvoiceStatusUpdated(bytes32 indexed invoiceHash, LibAppStorage.InvoiceStatus previousStatus, LibAppStorage.InvoiceStatus newStatus);
    event InvoiceDisputed(bytes32 indexed invoiceHash, address disputedBy, string reason);

    function registerInvoice(LibAppStorage.InvoiceRecord calldata invoice) external returns (bytes32 invoiceHash);
    function verifyInvoice(bytes32 invoiceHash) external;
    function updateInvoiceStatus(bytes32 invoiceHash, LibAppStorage.InvoiceStatus newStatus) external;
    function disputeInvoice(bytes32 invoiceHash, string calldata reason) external;
    function getInvoice(bytes32 invoiceHash) external view returns (LibAppStorage.InvoiceRecord memory invoice);
    function getSellerInvoices(address seller) external view returns (bytes32[] memory invoiceHashes);
    function getBuyerInvoices(address buyer) external view returns (bytes32[] memory invoiceHashes);
    function isInvoiceRegistered(bytes32 invoiceHash) external view returns (bool registered);
}
