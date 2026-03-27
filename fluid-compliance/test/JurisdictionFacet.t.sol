// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DiamondTestHelper} from "./helpers/DiamondTestHelper.sol";
import {LibAppStorage} from "../src/libraries/LibAppStorage.sol";

contract JurisdictionFacetTest is DiamondTestHelper {

    bytes32 constant US = keccak256("US");
    bytes32 constant EU = keccak256("EU");
    bytes32 constant IR = keccak256("IR"); // Iran - blocked

    function setUp() public override {
        super.setUp();
        _configureJurisdictions();
    }

    // ============================================================
    // configureJurisdiction
    // ============================================================

    function test_configureJurisdiction_storesConfig() public {
        LibAppStorage.JurisdictionConfig memory config = jurisdiction().getJurisdiction(US);
        assertTrue(config.isActive);
        assertEq(config.countryCode, keccak256("US"));
    }

    function test_configureJurisdiction_revertsIfNotAdmin() public {
        vm.prank(seller);
        vm.expectRevert();
        jurisdiction().configureJurisdiction(_buildJurisdiction(keccak256("CN"), true));
    }

    function test_configureJurisdiction_revertsForZeroId() public {
        LibAppStorage.JurisdictionConfig memory bad = _buildJurisdiction(bytes32(0), true);
        bad.jurisdictionId = bytes32(0);
        vm.prank(owner);
        vm.expectRevert();
        jurisdiction().configureJurisdiction(bad);
    }

    // ============================================================
    // assignEntityJurisdiction
    // ============================================================

    function test_assignEntityJurisdiction_stores() public {
        vm.prank(officer);
        jurisdiction().assignEntityJurisdiction(seller, US);
        assertEq(jurisdiction().getEntityJurisdiction(seller), US);
    }

    function test_assignEntityJurisdiction_revertsForInactiveJurisdiction() public {
        vm.prank(officer);
        vm.expectRevert();
        jurisdiction().assignEntityJurisdiction(seller, keccak256("NONEXISTENT"));
    }

    // ============================================================
    // assessCrossBorder
    // ============================================================

    function test_assessCrossBorder_permittedBetweenActiveJurisdictions() public {
        vm.prank(officer);
        jurisdiction().assignEntityJurisdiction(seller, US);
        vm.prank(officer);
        jurisdiction().assignEntityJurisdiction(buyer, EU);

        vm.prank(officer);
        LibAppStorage.CrossBorderAssessment memory assessment = jurisdiction().assessCrossBorder(
            seller, buyer, 50_000 * 1e18, keccak256("INVOICE")
        );
        assertTrue(assessment.isPermitted);
        assertEq(assessment.sourceJurisdiction, US);
        assertEq(assessment.destinationJurisdiction, EU);
    }

    function test_assessCrossBorder_blockedPairReverts() public {
        vm.prank(officer);
        jurisdiction().assignEntityJurisdiction(seller, US);
        vm.prank(officer);
        jurisdiction().assignEntityJurisdiction(buyer, IR);

        vm.prank(officer);
        jurisdiction().blockCounterpartyPair(US, IR, "OFAC sanctions");

        vm.prank(officer);
        vm.expectRevert();
        jurisdiction().assessCrossBorder(seller, buyer, 1000 * 1e18, keccak256("INVOICE"));
    }

    function test_assessCrossBorder_exceedingLimitReverts() public {
        // US has maxTransactionAmount = 1_000_000 * 1e18 in helper
        vm.prank(officer);
        jurisdiction().assignEntityJurisdiction(seller, US);
        vm.prank(officer);
        jurisdiction().assignEntityJurisdiction(buyer, US);

        vm.prank(officer);
        vm.expectRevert();
        jurisdiction().assessCrossBorder(seller, buyer, 2_000_000 * 1e18, keccak256("INVOICE"));
    }

    // ============================================================
    // isTransactionPermitted
    // ============================================================

    function test_isTransactionPermitted_trueForActiveJurisdictions() public view {
        assertTrue(jurisdiction().isTransactionPermitted(US, EU, keccak256("TRANSFER")));
    }

    function test_isTransactionPermitted_falseForBlockedPair() public {
        vm.prank(officer);
        jurisdiction().blockCounterpartyPair(US, IR, "Sanctions");
        assertFalse(jurisdiction().isTransactionPermitted(US, IR, keccak256("TRANSFER")));
    }

    // ============================================================
    // blockJurisdictionOperation
    // ============================================================

    function test_blockJurisdictionOperation_disablesFactoring() public {
        vm.prank(owner);
        jurisdiction().blockJurisdictionOperation(US, keccak256("FACTORING"));

        LibAppStorage.JurisdictionConfig memory config = jurisdiction().getJurisdiction(US);
        assertFalse(config.allowedForFactoring);
    }

    // ============================================================
    // Helpers
    // ============================================================

    function _configureJurisdictions() internal {
        vm.startPrank(owner);
        jurisdiction().configureJurisdiction(_buildJurisdiction(US, true));
        jurisdiction().configureJurisdiction(_buildJurisdiction(EU, true));
        jurisdiction().configureJurisdiction(_buildJurisdiction(IR, true));
        vm.stopPrank();
    }

    function _buildJurisdiction(
        bytes32 countryCode,
        bool active
    ) internal pure returns (LibAppStorage.JurisdictionConfig memory) {
        LibAppStorage.SanctionsList[] memory lists = new LibAppStorage.SanctionsList[](1);
        lists[0] = LibAppStorage.SanctionsList.OFAC_SDN;
        return LibAppStorage.JurisdictionConfig({
            jurisdictionId:              countryCode,
            countryCode:                 countryCode,
            isActive:                    active,
            minimumKYCLevel:             LibAppStorage.KYCLevel.STANDARD,
            kycExpirationPeriod:         365 days,
            requiresPEPScreening:        true,
            reportingThreshold:          10_000 * 1e18,
            enhancedDueDiligenceThreshold: 100_000 * 1e18,
            applicableSanctionsLists:    lists,
            fatcaApplicable:             countryCode == keccak256("US"),
            crsApplicable:               true,
            withholdingRate:             3000,
            allowedForFactoring:         true,
            maxTransactionAmount:        1_000_000 * 1e18,
            blockedCounterparties:       new bytes32[](0)
        });
    }
}
