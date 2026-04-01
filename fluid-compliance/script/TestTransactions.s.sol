// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";

import {RoleManagerFacet} from "../src/facets/RoleManagerFacet.sol";
import {DiamondCutFacet} from "../src/facets/DiamondCutFacet.sol";
import {LibRoles} from "../src/libraries/LibRoles.sol";
import {IDiamondCut} from "../src/interfaces/IDiamondCut.sol";
import {IKYCFacet} from "../src/interfaces/IKYCFacet.sol";
import {IAMLFacet} from "../src/interfaces/IAMLFacet.sol";
import {ISanctionsFacet} from "../src/interfaces/ISanctionsFacet.sol";
import {IInvoiceRegistryFacet} from "../src/interfaces/IInvoiceRegistryFacet.sol";
import {IJurisdictionFacet} from "../src/interfaces/IJurisdictionFacet.sol";
import {IFATCACRSFacet} from "../src/interfaces/IFATCACRSFacet.sol";

contract TestTransactions is Script {

    address constant DIAMOND = 0x12f587121591c300cf91ebb82e01249535c6e8cb;
    address constant OWNER = 0xF45975C34c454CB73eE6d74d056391dc004c88f1;
    address constant TEST_ENTITY = 0x742d35Cc6634C0532925a3b9B0eE4d7F6b8c4E8f; // Test address

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);

        // Deploy RoleManagerFacet
        RoleManagerFacet roleFacet = new RoleManagerFacet();

        // Add RoleManagerFacet to diamond
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](1);
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = RoleManagerFacet.grantRole.selector;
        selectors[1] = RoleManagerFacet.revokeRole.selector;
        cuts[0] = IDiamondCut.FacetCut({
            facetAddress: address(roleFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: selectors
        });

        DiamondCutFacet(DIAMOND).diamondCut(cuts, address(0), "");

        // Grant roles to owner
        RoleManagerFacet(DIAMOND).grantRole(LibRoles.KYC_VERIFIER_ROLE, OWNER);
        RoleManagerFacet(DIAMOND).grantRole(LibRoles.AML_ANALYST_ROLE, OWNER);
        RoleManagerFacet(DIAMOND).grantRole(LibRoles.SANCTIONS_MANAGER_ROLE, OWNER);
        RoleManagerFacet(DIAMOND).grantRole(LibRoles.ORACLE_ROLE, OWNER);
        RoleManagerFacet(DIAMOND).grantRole(LibRoles.TAX_OFFICER_ROLE, OWNER);
        RoleManagerFacet(DIAMOND).grantRole(LibRoles.AUDITOR_ROLE, OWNER);
        RoleManagerFacet(DIAMOND).grantRole(LibRoles.FACTOR_ROLE, OWNER);
        RoleManagerFacet(DIAMOND).grantRole(LibRoles.SELLER_ROLE, OWNER);
        RoleManagerFacet(DIAMOND).grantRole(LibRoles.BUYER_ROLE, OWNER);
        RoleManagerFacet(DIAMOND).grantRole(LibRoles.SECURITY_ADMIN_ROLE, OWNER);

        console.log("Roles granted to owner:", OWNER);

        // Test KYC processes
        IKYCFacet(DIAMOND).initiateKYC(TEST_ENTITY, "Test Entity", 1); // PEP_LEVEL_NONE
        IKYCFacet(DIAMOND).approveKYC(TEST_ENTITY);
        bool kycCompliant = IKYCFacet(DIAMOND).isKYCCompliant(TEST_ENTITY);
        console.log("KYC compliant for test entity:", kycCompliant);

        // Test AML assessment
        IAMLFacet(DIAMOND).setEntityRiskScore(TEST_ENTITY, 100); // Low risk
        IAMLFacet(DIAMOND).assessTransaction(TEST_ENTITY, 1000e18); // 1000 USDT
        bool highRisk = IAMLFacet(DIAMOND).isHighRisk(TEST_ENTITY);
        console.log("High risk for test entity:", highRisk);

        // Test Sanctions screening
        ISanctionsFacet(DIAMOND).screenEntity(TEST_ENTITY);
        bool sanctioned = ISanctionsFacet(DIAMOND).isSanctioned(TEST_ENTITY);
        console.log("Sanctioned for test entity:", sanctioned);

        // Test Invoice registration
        bytes32 invoiceHash = keccak256(abi.encodePacked("invoice1"));
        IInvoiceRegistryFacet(DIAMOND).registerInvoice(invoiceHash, TEST_ENTITY, OWNER, 1000e18, block.timestamp + 30 days);
        bool canFactor = IInvoiceRegistryFacet(DIAMOND).canFactor(invoiceHash);
        console.log("Can factor invoice:", canFactor);

        // Test Jurisdiction
        IJurisdictionFacet(DIAMOND).configureJurisdiction("US", true, 1000e18, 1); // KYC_LEVEL_BASIC
        IJurisdictionFacet(DIAMOND).assignEntityJurisdiction(TEST_ENTITY, "US");
        uint256 minKYC = IJurisdictionFacet(DIAMOND).getMinimumKYCLevel("US");
        console.log("Min KYC level for US:", minKYC);

        // Test FATCA/CRS
        IFATCACRSFacet(DIAMOND).setTaxClassification(TEST_ENTITY, 1); // US_PERSON
        uint256 classification = IFATCACRSFacet(DIAMOND).getTaxClassification(TEST_ENTITY);
        console.log("Tax classification:", classification);

        console.log("All test transactions completed.");

        vm.stopBroadcast();
    }
}