// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibAppStorage} from "../libraries/LibAppStorage.sol";
import {LibRoles} from "../libraries/LibRoles.sol";
import {IOracleFacet} from "../interfaces/IOracleFacet.sol";

/// @title OracleFacet
/// @author Surety Compliance System
/// @notice Secure integration with external compliance data providers
/// @dev Manages oracle registration and data validation for real-time compliance
contract OracleFacet is IOracleFacet {
    using LibAppStorage for LibAppStorage.AppStorage;
    
    // ============ Constants ============
    
    uint256 private constant ORACLE_DATA_EXPIRY = 24 hours;
    uint256 private constant MAX_ORACLES_PER_TYPE = 5;
    
    // ============ Storage ============
    
    mapping(address => OracleDataType[]) private oracleAuthorizations;
    mapping(bytes32 => OracleRequest) private oracleRequests;
    mapping(OracleDataType => address[]) private typeToOracles;
    mapping(OracleDataType => mapping(bytes32 => bytes)) private cachedData;
    mapping(OracleDataType => mapping(bytes32 => uint256)) private dataTimestamps;
    
    uint256 private requestNonce;
    
    // ============ Enums ============
    
    enum OracleDataType {
        SANCTIONS_LIST,
        PEP_LIST,
        EXCHANGE_RATE,
        RISK_SCORE,
        KYC_VERIFICATION,
        CREDIT_SCORE
    }
    
    struct OracleRequest {
        bytes32 requestId;
        OracleDataType dataType;
        bytes32 dataKey;
        uint256 requestTimestamp;
        uint256 expirationTimestamp;
        address requester;
        bool fulfilled;
    }
    
    // ============ Errors ============
    
    error UnauthorizedOracle();
    error OracleAlreadyRegistered();
    error InvalidDataType();
    error DataExpired();
    error RequestNotFound();
    error InvalidSignature();
    error TooManyOracles();
    
    // ============ Modifiers ============
    
    modifier whenNotPaused() {
        require(!LibAppStorage.isPaused(), "System paused");
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
    
    // ============ Core Functions ============
    
    /// @inheritdoc IOracleFacet
    function registerOracle(
        address oracle,
        OracleDataType[] calldata authorizedTypes
    ) external whenNotPaused onlyAdmin {
        // Check if already registered
        if (oracleAuthorizations[oracle].length > 0) {
            revert OracleAlreadyRegistered();
        }
        
        // Grant oracle role
        LibRoles.grantRole(LibRoles.ORACLE_ROLE, oracle);
        
        // Store authorizations
        oracleAuthorizations[oracle] = authorizedTypes;
        
        // Add to type mappings
        for (uint256 i = 0; i < authorizedTypes.length; i++) {
            address[] storage oracles = typeToOracles[authorizedTypes[i]];
            if (oracles.length >= MAX_ORACLES_PER_TYPE) {
                revert TooManyOracles();
            }
            oracles.push(oracle);
        }
        
        emit OracleRegistered(oracle, authorizedTypes, block.timestamp);
    }
    
    /// @inheritdoc IOracleFacet
    function revokeOracle(address oracle) external whenNotPaused onlyAdmin {
        OracleDataType[] memory types = oracleAuthorizations[oracle];
        
        // Remove from type mappings
        for (uint256 i = 0; i < types.length; i++) {
            address[] storage oracles = typeToOracles[types[i]];
            for (uint256 j = 0; j < oracles.length; j++) {
                if (oracles[j] == oracle) {
                    oracles[j] = oracles[oracles.length - 1];
                    oracles.pop();
                    break;
                }
            }
        }
        
        // Revoke role
        LibRoles.revokeRole(LibRoles.ORACLE_ROLE, oracle);
        
        // Clear authorizations
        delete oracleAuthorizations[oracle];
    }
    
    /// @inheritdoc IOracleFacet
    function submitOracleUpdate(
        OracleDataType dataType,
        bytes32 dataKey,
        bytes calldata dataValue,
        bytes calldata signature
    ) external whenNotPaused onlyOracle {
        // Verify oracle is authorized for this data type
        bool authorized = false;
        OracleDataType[] memory types = oracleAuthorizations[msg.sender];
        for (uint256 i = 0; i < types.length; i++) {
            if (types[i] == dataType) {
                authorized = true;
                break;
            }
        }
        
        if (!authorized) {
            revert UnauthorizedOracle();
        }
        
        // Verify signature
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                dataType,
                dataKey,
                dataValue,
                block.timestamp
            )
        );
        
        if (!_verifySignature(messageHash, signature, msg.sender)) {
            revert InvalidSignature();
        }
        
        // Cache data
        cachedData[dataType][dataKey] = dataValue;
        dataTimestamps[dataType][dataKey] = block.timestamp;
        
        // Process based on data type
        if (dataType == OracleDataType.SANCTIONS_LIST) {
            _processSanctionsUpdate(dataKey, dataValue);
        } else if (dataType == OracleDataType.EXCHANGE_RATE) {
            _processExchangeRateUpdate(dataKey, dataValue);
        }
        
        emit OracleDataUpdated(
            keccak256(abi.encodePacked(dataType, dataKey, block.timestamp)),
            dataType,
            dataKey,
            msg.sender,
            block.timestamp
        );
    }
    
    /// @inheritdoc IOracleFacet
    function requestOracleData(
        OracleDataType dataType,
        bytes32 dataKey
    ) external whenNotPaused returns (bytes32 requestId) {
        requestNonce++;
        requestId = keccak256(
            abi.encodePacked(
                dataType,
                dataKey,
                msg.sender,
                requestNonce,
                block.timestamp
            )
        );
        
        oracleRequests[requestId] = OracleRequest({
            requestId: requestId,
            dataType: dataType,
            dataKey: dataKey,
            requestTimestamp: block.timestamp,
            expirationTimestamp: block.timestamp + 1 hours,
            requester: msg.sender,
            fulfilled: false
        });
        
        // Emit event for off-chain oracles
        emit OracleDataUpdated(requestId, dataType, dataKey, msg.sender, block.timestamp);
        
        return requestId;
    }
    
    // ============ View Functions ============
    
    /// @inheritdoc IOracleFacet
    function isAuthorizedOracle(address oracle) external view returns (bool) {
        return oracleAuthorizations[oracle].length > 0;
    }
    
    /// @inheritdoc IOracleFacet
    function getOracleAuthorizations(
        address oracle
    ) external view returns (OracleDataType[] memory types) {
        types = oracleAuthorizations[oracle];
    }
    
    /// @inheritdoc IOracleFacet
    function getPendingRequests(
        OracleDataType dataType
    ) external view returns (OracleRequest[] memory requests) {
        // In production, would implement efficient query
        // For now, return empty array
        requests = new OracleRequest[](0);
    }
    
    // ============ Internal Functions ============
    
    /// @notice Process sanctions list update
    function _processSanctionsUpdate(bytes32 dataKey, bytes memory dataValue) internal {
        LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();
        
        // Decode Merkle root from data
        bytes32 newRoot = abi.decode(dataValue, (bytes32));
        
        // Update sanctions list root
        LibAppStorage.SanctionsList listType = LibAppStorage.SanctionsList(uint256(dataKey));
        s.sanctionsListRoots[listType] = newRoot;
        s.lastSanctionsUpdate[listType] = block.timestamp;
    }
    
    /// @notice Process exchange rate update
    function _processExchangeRateUpdate(bytes32 dataKey, bytes memory dataValue) internal {
        // In production, would update exchange rates
        // Used for currency conversion in reporting
    }
    
    /// @notice Verify oracle signature
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
        bytes32 s;
        uint8 v;
        
        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }
        
        if (v < 27) v += 27;
        
        address signer = ecrecover(ethSignedMessageHash, v, r, s);
        return signer == expectedSigner;
    }
}