// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DiamondTestHelper} from "./helpers/DiamondTestHelper.sol";
import {EmergencyFacet} from "../src/facets/EmergencyFacet.sol";
import {LibAppStorage} from "../src/libraries/LibAppStorage.sol";

/// @notice End-to-end integration test for the core supply chain finance compliance flow:
///   KYC → AML Risk Assessment → Sanctions Screening → Invoice Registration →
///   Buyer Verification → Factoring → Audit Trail
contract IntegrationTest is DiamondTestHelper {

    uint256 internal sellerPk;
    uint256 internal buyerPk;

    function setUp() public override {
        super.setUp();
        (, sellerPk) = makeAddrAndKey("seller");
        (, buyerPk)  = makeAddrAndKey("buyer");
    }

    // ============================================================
    // Full happy-path flow
    // ============================================================

    function test_fullComplianceFlow() public {
        // ---- Step 1: KYC both parties ----
        bytes32 sellerIdHash = keccak256("seller-passport");
        bytes32 buyerIdHash  = keccak256("buyer-passport");

        vm.prank(seller);
        kyc().initiateKYC(seller, sellerIdHash, LibAppStorage.KYCLevel.STANDARD, keccak256("US"));
        vm.prank(verifier);
        kyc().approveKYC(seller, LibAppStorage.KYCLevel.STANDARD, bytes32(0), false, 150);

        vm.prank(buyer);
        kyc().initiateKYC(buyer, buyerIdHash, LibAppStorage.KYCLevel.STANDARD, keccak256("DE"));
        vm.prank(verifier);
        kyc().approveKYC(buyer, LibAppStorage.KYCLevel.STANDARD, bytes32(0), false, 100);

        // Verify KYC compliance
        assertTrue(kyc().isKYCCompliant(seller, LibAppStorage.KYCLevel.BASIC));
        assertTrue(kyc().isKYCCompliant(buyer, LibAppStorage.KYCLevel.BASIC));

        // ---- Step 2: AML screening ----
        vm.prank(analyst);
        (, bool canProceed) = aml().assessTransaction(
            keccak256("tx-kyc-check"), seller, buyer, 100_000 * 1e18, keccak256("USD"), keccak256("INVOICE")
        );
        assertTrue(canProceed);

        // ---- Step 3: Sanctions screening ----
        vm.prank(officer);
        // Both clean entities — no match expected
        ISanctionsScreener(diamond).screenEntity(seller, sellerIdHash, new bytes32[](0));
        ISanctionsScreener(diamond).screenEntity(buyer, buyerIdHash, new bytes32[](0));
        assertFalse(sanctions().isSanctioned(seller));
        assertFalse(sanctions().isSanctioned(buyer));

        // ---- Step 4: Register invoice ----
        LibAppStorage.InvoiceRecord memory inv = _buildInvoice(seller, buyer, 200_000 * 1e18);
        bytes32 invoiceHash = keccak256(abi.encodePacked(
            inv.seller, inv.buyer, inv.amount, inv.currency, inv.issueDate, inv.dueDate, inv.purchaseOrderRef
        ));
        bytes memory sellerSig = _signAs("seller", invoiceHash);
        vm.prank(seller);
        invoice().registerInvoice(inv, sellerSig);
        assertTrue(invoice().isInvoiceHashUsed(invoiceHash));

        // ---- Step 5: Buyer verification ----
        bytes memory buyerSig = _signAs("buyer", invoiceHash);
        vm.prank(buyer);
        invoice().verifyInvoice(invoiceHash, buyerSig);

        LibAppStorage.InvoiceRecord memory rec = invoice().getInvoice(invoiceHash);
        assertEq(uint8(rec.status), uint8(LibAppStorage.InvoiceStatus.VERIFIED));

        // ---- Step 6: Factor invoice ----
        (bool ok,) = invoice().canFactor(invoiceHash);
        assertTrue(ok);

        vm.prank(factor);
        bytes32 agreementId = invoice().createFactoringAgreement(invoiceHash, factor, 8000, 200);
        assertNotEq(agreementId, bytes32(0));

        rec = invoice().getInvoice(invoiceHash);
        assertEq(uint8(rec.status), uint8(LibAppStorage.InvoiceStatus.FACTORED));

        // ---- Step 7: Double-factoring prevention ----
        vm.prank(factor);
        vm.expectRevert();
        invoice().createFactoringAgreement(invoiceHash, factor, 7500, 150);

        // ---- Step 8: Audit trail ----
        vm.prank(auditor);
        bytes32 entryId = audit().logAudit(
            LibAppStorage.AuditEventType.INVOICE_FACTORED, seller, invoiceHash
        );
        assertNotEq(entryId, bytes32(0));

        LibAppStorage.AuditEntry[] memory entries = audit().getEntityAuditTrail(
            seller, LibAppStorage.AuditEventType.INVOICE_FACTORED, 0, 0
        );
        assertEq(entries.length, 1);
        assertEq(entries[0].dataHash, invoiceHash);
    }

    // ============================================================
    // Emergency pause interrupts flow
    // ============================================================

    function test_emergencyPause_blocksAllFacets() public {
        // KYC works before pause
        vm.prank(seller);
        kyc().initiateKYC(seller, keccak256("id"), LibAppStorage.KYCLevel.BASIC, keccak256("US"));

        // Pause
        vm.prank(pauser);
        EmergencyFacet(diamond).emergencyPause();

        // KYC registration now blocked
        vm.prank(buyer);
        vm.expectRevert("System paused");
        kyc().initiateKYC(buyer, keccak256("buyer-id"), LibAppStorage.KYCLevel.BASIC, keccak256("US"));

        // AML blocked
        vm.prank(analyst);
        vm.expectRevert("System paused");
        aml().assessTransaction(
            keccak256("tx"), seller, buyer, 1000 * 1e18, keccak256("USD"), keccak256("TEST")
        );

        // Unpause restores functionality
        vm.prank(owner);
        EmergencyFacet(diamond).emergencyUnpause();

        vm.prank(buyer);
        kyc().initiateKYC(buyer, keccak256("buyer-id-2"), LibAppStorage.KYCLevel.BASIC, keccak256("US"));
    }

    // ============================================================
    // Sanctions block flow
    // ============================================================

    function test_sanctionedEntity_blocksDirectly() public {
        bytes32 sellerIdHash = keccak256("seller-id-sanctions");
        vm.prank(seller);
        kyc().initiateKYC(seller, sellerIdHash, LibAppStorage.KYCLevel.BASIC, keccak256("US"));
        vm.prank(verifier);
        kyc().approveKYC(seller, LibAppStorage.KYCLevel.BASIC, bytes32(0), false, 0);

        // Add seller to sanctions list
        LibAppStorage.SanctionsList[] memory lists = new LibAppStorage.SanctionsList[](1);
        lists[0] = LibAppStorage.SanctionsList.OFAC_SDN;
        vm.prank(sanctionsMgr);
        sanctions().addToSanctionsList(sellerIdHash, LibAppStorage.SanctionRecord({
            entityHash: sellerIdHash,
            lists: lists,
            listingDate: block.timestamp,
            lastVerified: block.timestamp,
            programCode: keccak256("SDN"),
            isActive: true
        }));

        assertTrue(sanctions().isSanctioned(seller));
    }
}

interface ISanctionsScreener {
    struct ScreeningResult {
        bool isMatch;
        bool isPotentialMatch;
        uint256 matchScore;
        LibAppStorage.SanctionsList[] matchedLists;
        bytes32 matchedEntityHash;
    }
    function screenEntity(address entity, bytes32 identityHash, bytes32[] calldata nameVariants)
        external returns (ScreeningResult memory result);
}
