// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibAppStorage, SystemPaused} from "../libraries/LibAppStorage.sol";
import {LibRoles} from "../libraries/LibRoles.sol";
import {IOracleFacet} from "../interfaces/IOracleFacet.sol";

/// @title OracleFacet
/// @author Surety Compliance System
/// @notice Secure integration with external compliance data providers
/// @dev Manages oracle registration and data validation for real-time compliance.
///      All state is stored in LibAppStorage — never in facet instance variables.
contract OracleFacet is IOracleFacet {

    // ============================================================
    // Constants
    // ============================================================

    uint256 private constant ORACLE_DATA_EXPIRY = 24 hours;
    uint256 private constant MAX_ORACLES_PER_TYPE = 5;

    // ============================================================
    // Errors
    // ============================================================

    error UnauthorizedOracle();
    error OracleAlreadyRegistered();
    error InvalidDataType();
    error DataExpired();
    error RequestNotFound();
    error InvalidSignature();
    error TooManyOracles();
    error OracleNotRegistered();
    error ZeroAddress();

    // ============================================================
    // Modifiers
    // ============================================================

    modifier whenNotPaused() {
        if (LibAppStorage.isPaused()) revert SystemPaused();
        _;
    }

    modifier onlyAdmin() {
        LibRoles.checkRole(LibRoles.DEFAULT_ADMIN_ROLE);
        _;
    }

    modifier onlyOracle() {
        LibRoles.checkRole(LibRoles.ORACLE_ROLE);
        _;
    }

    // ============================================================
    // Core Functions
    // ============================================================

    /// @inheritdoc IOracleFacet
    function registerOracle(
        address oracle,
        LibAppStorage.OracleDataType[] calldata authorizedTypes
    ) external whenNotPaused onlyAdmin {
        if (oracle == address(0)) revert ZeroAddress();
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        if (s.oracleActive[oracle]) revert OracleAlreadyRegistered();

        LibRoles.grantRole(LibRoles.ORACLE_ROLE, oracle);
        s.oracleActive[oracle] = true;
        s.oracleAuthorizedTypes[oracle] = abi.encode(authorizedTypes);

        emit OracleRegistered(oracle, authorizedTypes, block.timestamp);
    }

    /// @inheritdoc IOracleFacet
    function revokeOracle(address oracle) external whenNotPaused onlyAdmin {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        if (!s.oracleActive[oracle]) revert OracleNotRegistered();

        LibRoles.revokeRole(LibRoles.ORACLE_ROLE, oracle);
        s.oracleActive[oracle] = false;
        delete s.oracleAuthorizedTypes[oracle];
    }

    /// @inheritdoc IOracleFacet
    function submitOracleUpdate(
        LibAppStorage.OracleDataType dataType,
        bytes32 dataKey,
        bytes calldata dataValue,
        bytes calldata signature
    ) external whenNotPaused onlyOracle {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

        // Verify oracle is authorised for this data type
        if (!_isAuthorizedForType(s, msg.sender, dataType)) revert UnauthorizedOracle();

        // Verify ECDSA signature over (dataType, dataKey, dataValue, timestamp)
        bytes32 messageHash = keccak256(abi.encodePacked(
            dataType, dataKey, dataValue, block.timestamp
        ));
        if (!_verifySignature(messageHash, signature, msg.sender)) revert InvalidSignature();

        // Cache data keyed by (dataType hash, dataKey)
        bytes32 typeKey = bytes32(uint256(dataType));
        s.oracleCachedData[typeKey][dataKey] = dataValue;
        s.oracleDataTimestamps[typeKey][dataKey] = block.timestamp;

        // Process known update types
        if (dataType == LibAppStorage.OracleDataType.SANCTIONS_LIST) {
            _processSanctionsUpdate(s, dataKey, dataValue);
        }

        bytes32 updateId = keccak256(abi.encodePacked(dataType, dataKey, block.timestamp));
        emit OracleDataUpdated(updateId, dataType, dataKey, msg.sender, block.timestamp);
    }

    /// @inheritdoc IOracleFacet
    function requestOracleData(
        LibAppStorage.OracleDataType dataType,
        bytes32 dataKey
    ) external whenNotPaused returns (bytes32 requestId) {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        s.oracleRequestNonce++;

        requestId = keccak256(abi.encodePacked(
            dataType, dataKey, msg.sender, s.oracleRequestNonce, block.timestamp
        ));

        s.oracleRequests[requestId] = LibAppStorage.OracleRequest({
            requestId: requestId,
            dataType: dataType,
            dataKey: dataKey,
            requestTimestamp: block.timestamp,
            expirationTimestamp: block.timestamp + 1 hours,
            requester: msg.sender,
            fulfilled: false
        });

        emit OracleDataUpdated(requestId, dataType, dataKey, msg.sender, block.timestamp);
        return requestId;
    }

    // ============================================================
    // View Functions
    // ============================================================

    /// @inheritdoc IOracleFacet
    function isAuthorizedOracle(address oracle) external view returns (bool) {
        return LibAppStorage.appStorage().oracleActive[oracle];
    }

    /// @inheritdoc IOracleFacet
    function getOracleAuthorizations(
        address oracle
    ) external view returns (LibAppStorage.OracleDataType[] memory types) {
        bytes memory encoded = LibAppStorage.appStorage().oracleAuthorizedTypes[oracle];
        if (encoded.length == 0) return new LibAppStorage.OracleDataType[](0);
        types = abi.decode(encoded, (LibAppStorage.OracleDataType[]));
    }

    /// @inheritdoc IOracleFacet
    function getPendingRequests(
        LibAppStorage.OracleDataType dataType
    ) external view returns (LibAppStorage.OracleRequest[] memory requests) {
        // Off-chain indexing is the efficient pattern for enumeration.
        // Return empty array — callers should use OracleDataUpdated events to discover requests.
        requests = new LibAppStorage.OracleRequest[](0);
    }

    // ============================================================
    // Internal
    // ============================================================

    /// @notice Check if an oracle is authorised for a specific data type
    /// @param s AppStorage reference
    /// @param oracle The oracle address to check
    /// @param dataType The data type to verify authorisation for
    /// @return True if the oracle is active and authorised for the given data type
    function _isAuthorizedForType(
        LibAppStorage.AppStorage storage s,
        address oracle,
        LibAppStorage.OracleDataType dataType
    ) internal view returns (bool) {
        if (!s.oracleActive[oracle]) return false;
        bytes memory encoded = s.oracleAuthorizedTypes[oracle];
        if (encoded.length == 0) return false;
        LibAppStorage.OracleDataType[] memory types = abi.decode(encoded, (LibAppStorage.OracleDataType[]));
        for (uint256 i = 0; i < types.length; i++) {
            if (types[i] == dataType) return true;
        }
        return false;
    }

    /// @notice Update the Merkle root for a sanctions list via oracle feed
    /// @param s AppStorage reference
    /// @param dataKey Encoded SanctionsList enum value identifying the list to update
    /// @param dataValue ABI-encoded bytes32 Merkle root for the sanctions list
    function _processSanctionsUpdate(
        LibAppStorage.AppStorage storage s,
        bytes32 dataKey,
        bytes memory dataValue
    ) internal {
        bytes32 newRoot = abi.decode(dataValue, (bytes32));
        LibAppStorage.SanctionsList listType = LibAppStorage.SanctionsList(uint256(dataKey));
        s.sanctionsListRoots[listType] = newRoot;
        s.lastSanctionsUpdate[listType] = block.timestamp;
    }

    /// @notice Recover signer from an Ethereum-prefixed message hash
    /// @param messageHash The raw keccak256 hash of the signed data
    /// @param signature 65-byte ECDSA signature (r, s, v)
    /// @param expectedSigner Address expected to have produced the signature
    /// @return True if the recovered signer matches expectedSigner and is non-zero
    function _verifySignature(
        bytes32 messageHash,
        bytes memory signature,
        address expectedSigner
    ) internal pure returns (bool) {
        if (signature.length != 65) return false;

        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );

        bytes32 r;
        bytes32 sig_s;
        uint8 v;
        assembly {
            r     := mload(add(signature, 32))
            sig_s := mload(add(signature, 64))
            v     := byte(0, mload(add(signature, 96)))
        }
        if (v < 27) v += 27;

        address signer = ecrecover(ethSignedMessageHash, v, r, sig_s);
        return signer != address(0) && signer == expectedSigner;
    }
}
