// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibAppStorage} from "../libraries/LibAppStorage.sol";

/// @title IAMLFacet
/// @notice Interface for Anti-Money Laundering risk scoring and transaction monitoring
interface IAMLFacet {

    event RiskScoreUpdated(address indexed entity, uint256 newScore, LibAppStorage.RiskLevel riskLevel, uint256 timestamp);
    event TransactionFlagged(bytes32 indexed transactionId, address indexed entity, uint256 riskScore, string reason);
    event SuspiciousActivityReported(address indexed entity, uint256 activityCount, uint256 timestamp);

    function calculateRiskScore(address entity, LibAppStorage.TransactionRecord calldata transaction) external returns (uint256 score);
    function updateRiskProfile(address entity, uint256 newScore, bytes32[] calldata riskFactors) external;
    function flagTransaction(bytes32 transactionId, address entity, string calldata reason) external;
    function recordTransaction(address entity, LibAppStorage.TransactionRecord calldata transaction) external;
    function getRiskScore(address entity) external view returns (LibAppStorage.RiskScore memory score);
    function getTransactionHistory(address entity) external view returns (LibAppStorage.TransactionRecord[] memory history);
    function isBelowRiskThreshold(address entity, LibAppStorage.RiskLevel maxLevel) external view returns (bool compliant);
}
