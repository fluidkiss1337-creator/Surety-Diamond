// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DiamondTestHelper} from "./helpers/DiamondTestHelper.sol";
import {LibAppStorage} from "../src/libraries/LibAppStorage.sol";

contract SanctionsFacetTest is DiamondTestHelper {

    bytes32 constant ENTITY_HASH = keccak256("sanctioned-entity");

    // ============================================================
    // screenEntity — no match
    // ============================================================

    function test_screenEntity_noMatch() public {
        vm.prank(officer);
        ISanctionsFacetTestHelper.ScreeningResult memory result = ISanctionsFacetTestHelper(diamond).screenEntity(
            seller, keccak256("clean-entity"), new bytes32[](0)
        );
        assertFalse(result.isMatch);
        assertFalse(result.isPotentialMatch);
    }

    // ============================================================
    // addToSanctionsList + screenEntity — exact match
    // ============================================================

    function test_screenEntity_exactMatch() public {
        LibAppStorage.SanctionsList[] memory lists = new LibAppStorage.SanctionsList[](1);
        lists[0] = LibAppStorage.SanctionsList.OFAC_SDN;

        LibAppStorage.SanctionRecord memory record = LibAppStorage.SanctionRecord({
            entityHash: ENTITY_HASH,
            lists: lists,
            listingDate: block.timestamp,
            lastVerified: block.timestamp,
            programCode: keccak256("SDN"),
            isActive: true
        });

        vm.prank(sanctionsMgr);
        sanctions().addToSanctionsList(ENTITY_HASH, record);

        vm.prank(officer);
        ISanctionsFacetTestHelper.ScreeningResult memory result = ISanctionsFacetTestHelper(diamond).screenEntity(
            seller, ENTITY_HASH, new bytes32[](0)
        );
        assertTrue(result.isMatch);
        assertEq(result.matchScore, 100);
    }

    // ============================================================
    // removeFromSanctionsList
    // ============================================================

    function test_removeFromSanctionsList_clearsEntry() public {
        _addSanctionedEntity(ENTITY_HASH);

        vm.prank(sanctionsMgr);
        sanctions().removeFromSanctionsList(ENTITY_HASH, "False positive");

        LibAppStorage.SanctionRecord memory record = sanctions().getSanctionRecord(ENTITY_HASH);
        assertFalse(record.isActive);
    }

    // ============================================================
    // verifyAgainstList — Merkle proof
    // ============================================================

    function test_verifyAgainstList_emptyRootReturnsFalse() public view {
        assertFalse(sanctions().verifyAgainstList(ENTITY_HASH, LibAppStorage.SanctionsList.UN_SC, new bytes32[](0)));
    }

    function test_verifyAgainstList_singleLeafProof() public {
        vm.prank(oracle);
        sanctions().updateSanctionsList(LibAppStorage.SanctionsList.OFAC_SDN, ENTITY_HASH, 1);

        // Single entry: entity hash IS the root, empty proof should verify
        assertTrue(sanctions().verifyAgainstList(ENTITY_HASH, LibAppStorage.SanctionsList.OFAC_SDN, new bytes32[](0)));
    }

    // ============================================================
    // updateSanctionsList
    // ============================================================

    function test_updateSanctionsList_storesRoot() public {
        bytes32 newRoot = keccak256("new-ofac-root");
        vm.prank(oracle);
        sanctions().updateSanctionsList(LibAppStorage.SanctionsList.OFAC_SDN, newRoot, 500);

        (bytes32 root, uint256 lastUpdate) = sanctions().getSanctionsListRoot(LibAppStorage.SanctionsList.OFAC_SDN);
        assertEq(root, newRoot);
        assertGt(lastUpdate, 0);
    }

    function test_updateSanctionsList_revertsIfNotOracle() public {
        vm.prank(seller);
        vm.expectRevert();
        sanctions().updateSanctionsList(LibAppStorage.SanctionsList.OFAC_SDN, keccak256("root"), 1);
    }

    // ============================================================
    // isSanctioned
    // ============================================================

    function test_isSanctioned_falseWithoutKYC() public view {
        assertFalse(sanctions().isSanctioned(seller));
    }

    function test_isSanctioned_trueAfterAddingIdentityHash() public {
        // Register KYC so entity has an identity hash
        bytes32 idHash = keccak256("sanctioned-seller");
        vm.prank(seller);
        kyc().initiateKYC(seller, idHash, LibAppStorage.KYCLevel.BASIC, keccak256("US"));
        vm.prank(verifier);
        kyc().approveKYC(seller, LibAppStorage.KYCLevel.BASIC, bytes32(0), false, 0);

        _addSanctionedEntity(idHash);

        assertTrue(sanctions().isSanctioned(seller));
    }

    // ============================================================
    // Helpers
    // ============================================================

    function _addSanctionedEntity(bytes32 entityHash) internal {
        LibAppStorage.SanctionsList[] memory lists = new LibAppStorage.SanctionsList[](1);
        lists[0] = LibAppStorage.SanctionsList.OFAC_SDN;
        LibAppStorage.SanctionRecord memory record = LibAppStorage.SanctionRecord({
            entityHash: entityHash,
            lists: lists,
            listingDate: block.timestamp,
            lastVerified: block.timestamp,
            programCode: keccak256("SDN"),
            isActive: true
        });
        vm.prank(sanctionsMgr);
        sanctions().addToSanctionsList(entityHash, record);
    }
}

// Mirror ScreeningResult for use in test assertions
interface ISanctionsFacetTestHelper {
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
