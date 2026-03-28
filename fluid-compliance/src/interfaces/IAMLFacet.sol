// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibAppStorage} from "../libraries/LibAppStorage.sol";

/// @title IAMLFacet
/// @notice Interface for Anti-Money Laundering risk scoring and transaction monitoring
interface IAMLFacet {

    event SARFiled(bytes32 indexed transactionId, address indexed entity, uint256 riskScore, uint256 timestamp);
    event TransactionAssessed(bytes32 indexed transactionId, address indexed from, address indexed to, uint256 amount, uint256 riskScore, bool canProceed);
    event RiskScoreUpdated(address indexed entity, uint256 newScore, address indexed updatedBy, string rationale);
    event SuspiciousActivityFlagged(address indexed entity, bytes32 indexed transactionId, string reason, uint256 timestamp);

    function assessTransaction(
        bytes32 transactionId,
        address from,
        address to,
        uint256 amount,
        bytes32 currency,
        bytes32 transactionType
    ) external returns (LibAppStorage.RiskScore memory score, bool canProceed);

    function setEntityRiskScore(address entity, uint256 riskScore, string calldata rationale) external;

    function flagSuspiciousActivity(address entity, bytes32 transactionId, string calldata reason) external;

    function fileSAR(address entity, bytes32 transactionId, uint256 riskScore, string calldata narrative) external;

    function getEntityRiskProfile(
        address entity
    ) external view returns (uint256 riskScore, bool isPEP, LibAppStorage.KYCStatus status);

    function isHighRisk(address entity) external view returns (bool);
}
