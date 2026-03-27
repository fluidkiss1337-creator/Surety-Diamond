// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IJurisdictionFacet
/// @notice Interface for multi-jurisdiction compliance rule management
interface IJurisdictionFacet {

    struct JurisdictionRule {
        bytes32 jurisdictionId;
        uint8 minKYCLevel;       // Minimum KYC level required
        uint256 maxTransactionAmount; // 0 = unlimited
        bool requiresPEPCheck;
        bool requiresSourceOfFunds;
        bool isActive;
    }

    event JurisdictionAdded(bytes32 indexed jurisdictionId, string name);
    event JurisdictionRuleUpdated(bytes32 indexed jurisdictionId, JurisdictionRule rule);
    event JurisdictionDisabled(bytes32 indexed jurisdictionId);

    function addJurisdiction(bytes32 jurisdictionId, string calldata name, JurisdictionRule calldata rule) external;
    function updateJurisdictionRule(bytes32 jurisdictionId, JurisdictionRule calldata rule) external;
    function disableJurisdiction(bytes32 jurisdictionId) external;
    function getJurisdictionRule(bytes32 jurisdictionId) external view returns (JurisdictionRule memory rule);
    function isCompliantForJurisdiction(address entity, bytes32 jurisdictionId) external view returns (bool compliant);
    function getActiveJurisdictions() external view returns (bytes32[] memory jurisdictionIds);
}
