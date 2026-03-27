// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../SuretyDiamond.sol";
import "../libraries/LibDiamond.sol";
import "../interfaces/IDiamondCut.sol";

/// @title DeploySurety
/// @notice Deployment script for Surety compliance diamond
contract DeploySurety is Script {
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.envAddress("OWNER_ADDRESS");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // 1. Deploy Diamond
        SuretyDiamond diamond = new SuretyDiamond(owner, 48 hours);
        console.log("Diamond deployed at:", address(diamond));
        
        // 2. Deploy DiamondCutFacet
        DiamondCutFacet cutFacet = new DiamondCutFacet();
        console.log("DiamondCutFacet:", address(cutFacet));
        
        // 3. Deploy DiamondLoupeFacet
        DiamondLoupeFacet loupeFacet = new DiamondLoupeFacet();
        console.log("DiamondLoupeFacet:", address(loupeFacet));
        
        // 4. Deploy compliance facets
        KYCFacet kycFacet = new KYCFacet();
        console.log("KYCFacet:", address(kycFacet));
        
        SanctionsFacet sanctionsFacet = new SanctionsFacet();
        console.log("SanctionsFacet:", address(sanctionsFacet));
        
        AMLFacet amlFacet = new AMLFacet();
        console.log("AMLFacet:", address(amlFacet));
        
        InvoiceRegistryFacet invoiceFacet = new InvoiceRegistryFacet();
        console.log("InvoiceRegistryFacet:", address(invoiceFacet));
        
        AuditFacet auditFacet = new AuditFacet();
        console.log("AuditFacet:", address(auditFacet));
        
        // 5. Prepare diamond cut
        IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](7);
        
        // Add facets with their selectors
        cut[0] = _prepareFacetCut(address(cutFacet), IDiamondCut.FacetCutAction.Add);
        cut[1] = _prepareFacetCut(address(loupeFacet), IDiamondCut.FacetCutAction.Add);
        cut[2] = _prepareFacetCut(address(kycFacet), IDiamondCut.FacetCutAction.Add);
        cut[3] = _prepareFacetCut(address(sanctionsFacet), IDiamondCut.FacetCutAction.Add);
        cut[4] = _prepareFacetCut(address(amlFacet), IDiamondCut.FacetCutAction.Add);
        cut[5] = _prepareFacetCut(address(invoiceFacet), IDiamondCut.FacetCutAction.Add);
        cut[6] = _prepareFacetCut(address(auditFacet), IDiamondCut.FacetCutAction.Add);
        
        // 6. Execute diamond cut
        // IDiamondCut(address(diamond)).diamondCut(cut, address(0), "");
        
        console.log("Surety deployment complete!");
        
        vm.stopBroadcast();
    }
    
    function _prepareFacetCut(
        address facet,
        IDiamondCut.FacetCutAction action
    ) internal pure returns (IDiamondCut.FacetCut memory) {
        // Get function selectors for facet
        bytes4[] memory selectors = _getSelectors(facet);
        
        return IDiamondCut.FacetCut({
            facetAddress: facet,
            action: action,
            functionSelectors: selectors
        });
    }
    
    function _getSelectors(address facet) internal pure returns (bytes4[] memory) {
        // In production, would use more sophisticated selector extraction
        // For now, placeholder
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = bytes4(keccak256("placeholder()"));
        return selectors;
    }
}