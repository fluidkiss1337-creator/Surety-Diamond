// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DiamondTestHelper} from "./helpers/DiamondTestHelper.sol";
import {LibAppStorage} from "../src/libraries/LibAppStorage.sol";

contract KYCFacetTest is DiamondTestHelper {

    // ============================================================
    // Initiate KYC
    // ============================================================

    function test_initiateKYC_storesPendingRecord() public {
        bytes32 identityHash = keccak256("alice-identity");
        vm.prank(seller);
        kyc().initiateKYC(seller, identityHash, LibAppStorage.KYCLevel.STANDARD, keccak256("US"));

        LibAppStorage.KYCRecord memory record = kyc().getKYCRecord(seller);
        assertEq(record.identityHash, identityHash);
        assertEq(uint8(record.status), uint8(LibAppStorage.KYCStatus.PENDING));
    }

    function test_initiateKYC_revertsIfAlreadyApproved() public {
        bytes32 idHash = keccak256("alice-identity");
        vm.prank(seller);
        kyc().initiateKYC(seller, idHash, LibAppStorage.KYCLevel.BASIC, keccak256("US"));

        vm.prank(verifier);
        kyc().approveKYC(seller, LibAppStorage.KYCLevel.BASIC, keccak256("docroot"), false, 100);

        vm.prank(seller);
        vm.expectRevert();
        kyc().initiateKYC(seller, keccak256("new-id"), LibAppStorage.KYCLevel.BASIC, keccak256("US"));
    }

    // ============================================================
    // Approve KYC
    // ============================================================

    function test_approveKYC_setsApprovedStatus() public {
        bytes32 idHash = keccak256("bob-identity");
        vm.prank(buyer);
        kyc().initiateKYC(buyer, idHash, LibAppStorage.KYCLevel.STANDARD, keccak256("US"));

        vm.prank(verifier);
        kyc().approveKYC(buyer, LibAppStorage.KYCLevel.STANDARD, keccak256("docroot"), false, 200);

        LibAppStorage.KYCRecord memory record = kyc().getKYCRecord(buyer);
        assertEq(uint8(record.status), uint8(LibAppStorage.KYCStatus.APPROVED));
        assertEq(uint8(record.level),  uint8(LibAppStorage.KYCLevel.STANDARD));
        assertGt(record.expirationDate, block.timestamp);
    }

    function test_approveKYC_revertsIfNotVerifier() public {
        bytes32 idHash = keccak256("bob-identity");
        vm.prank(buyer);
        kyc().initiateKYC(buyer, idHash, LibAppStorage.KYCLevel.BASIC, keccak256("US"));

        vm.prank(buyer);
        vm.expectRevert();
        kyc().approveKYC(buyer, LibAppStorage.KYCLevel.BASIC, bytes32(0), false, 0);
    }

    function test_approveKYC_pepFlag() public {
        bytes32 idHash = keccak256("pep-identity");
        vm.prank(seller);
        kyc().initiateKYC(seller, idHash, LibAppStorage.KYCLevel.ENHANCED, keccak256("US"));

        vm.prank(verifier);
        kyc().approveKYC(seller, LibAppStorage.KYCLevel.ENHANCED, keccak256("docroot"), true, 600);

        LibAppStorage.KYCRecord memory record = kyc().getKYCRecord(seller);
        assertTrue(record.isPEP);
        assertEq(record.riskScore, 600);
    }

    // ============================================================
    // Reject KYC
    // ============================================================

    function test_rejectKYC_setsRejectedStatus() public {
        bytes32 idHash = keccak256("rejected-entity");
        vm.prank(seller);
        kyc().initiateKYC(seller, idHash, LibAppStorage.KYCLevel.BASIC, keccak256("US"));

        vm.prank(verifier);
        kyc().rejectKYC(seller, "Failed document verification");

        LibAppStorage.KYCRecord memory record = kyc().getKYCRecord(seller);
        assertEq(uint8(record.status), uint8(LibAppStorage.KYCStatus.REJECTED));
    }

    // ============================================================
    // isKYCCompliant
    // ============================================================

    function test_isKYCCompliant_falseForUnapproved() public view {
        assertFalse(kyc().isKYCCompliant(seller, LibAppStorage.KYCLevel.BASIC));
    }

    function test_isKYCCompliant_trueForApprovedAtOrAboveLevel() public {
        bytes32 idHash = keccak256("compliant-id");
        vm.prank(seller);
        kyc().initiateKYC(seller, idHash, LibAppStorage.KYCLevel.STANDARD, keccak256("US"));
        vm.prank(verifier);
        kyc().approveKYC(seller, LibAppStorage.KYCLevel.STANDARD, bytes32(0), false, 0);

        assertTrue(kyc().isKYCCompliant(seller, LibAppStorage.KYCLevel.BASIC));
        assertTrue(kyc().isKYCCompliant(seller, LibAppStorage.KYCLevel.STANDARD));
        assertFalse(kyc().isKYCCompliant(seller, LibAppStorage.KYCLevel.ENHANCED));
    }

    // ============================================================
    // Merkle document verification
    // ============================================================

    function test_verifyDocument_singleLeaf() public {
        bytes32 leaf = keccak256("document-content");
        vm.prank(seller);
        kyc().initiateKYC(seller, keccak256("id"), LibAppStorage.KYCLevel.BASIC, keccak256("US"));
        vm.prank(verifier);
        kyc().approveKYC(seller, LibAppStorage.KYCLevel.BASIC, leaf, false, 0);

        bytes32[] memory emptyProof = new bytes32[](0);
        assertTrue(kyc().verifyDocument(seller, leaf, emptyProof));
    }

    function test_verifyDocument_invalidProof() public {
        bytes32 leaf = keccak256("document-content");
        vm.prank(seller);
        kyc().initiateKYC(seller, keccak256("id"), LibAppStorage.KYCLevel.BASIC, keccak256("US"));
        vm.prank(verifier);
        kyc().approveKYC(seller, LibAppStorage.KYCLevel.BASIC, leaf, false, 0);

        bytes32[] memory emptyProof = new bytes32[](0);
        assertFalse(kyc().verifyDocument(seller, keccak256("wrong-doc"), emptyProof));
    }
}
