// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibAppStorage} from "../libraries/LibAppStorage.sol";

/// @title ISanctionsFacet
/// @notice Interface for OFAC/UN/EU sanctions screening operations
interface ISanctionsFacet {

    struct ScreeningResult {
        bool isMatch;
        bool isPotentialMatch;
        uint256 matchScore;
        LibAppStorage.SanctionsList[] matchedLists;
        bytes32 matchedEntityHash;
    }

    event SanctionsMatchFound(address indexed entity, LibAppStorage.SanctionsList[] lists, bytes32 entityHash, uint256 timestamp);
    event EntityScreened(address indexed entity, bytes32 identityHash, bool isMatch, uint256 matchScore);
    event SanctionsListUpdated(LibAppStorage.SanctionsList indexed listType, bytes32 newRoot, uint256 entryCount, uint256 timestamp);
    event EntityCleared(address indexed entity, uint256 timestamp, address clearedBy);

    function screenEntity(address entity, bytes32 identityHash, bytes32[] calldata nameVariants) external returns (ScreeningResult memory result);
    function verifyAgainstList(bytes32 entityHash, LibAppStorage.SanctionsList listType, bytes32[] calldata proof) external view returns (bool isListed);
    function updateSanctionsList(LibAppStorage.SanctionsList listType, bytes32 newRoot, uint256 entryCount) external;
    function addToSanctionsList(bytes32 entityHash, LibAppStorage.SanctionRecord calldata record) external;
    function removeFromSanctionsList(bytes32 entityHash, string calldata reason) external;
    function clearFalsePositive(address entity, bytes32 identityHash, string calldata clearanceReason) external;
    function isSanctioned(address entity) external view returns (bool);
    function getSanctionRecord(bytes32 entityHash) external view returns (LibAppStorage.SanctionRecord memory record);
    function getSanctionsListRoot(LibAppStorage.SanctionsList listType) external view returns (bytes32 root, uint256 lastUpdate);
}
