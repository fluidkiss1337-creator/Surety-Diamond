// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DiamondTestHelper} from "../helpers/DiamondTestHelper.sol";
import {LibAppStorage} from "../../src/libraries/LibAppStorage.sol";

contract FuzzAMLFacetTest is DiamondTestHelper {

    uint256 private constant MAX_RISK_SCORE = 1000;
    uint256 private constant HIGH_RISK_THRESHOLD = 750;

    // ============================================================
    // assessTransaction — risk score always bounded [0, 1000]
    // ============================================================

    function testFuzz_assessTransaction_riskScoreBounded(uint256 amount) public {
        amount = bound(amount, 1, type(uint128).max);

        _approveKYC(seller, 0);
        _approveKYC(buyer, 0);

        vm.prank(analyst);
        (LibAppStorage.RiskScore memory score,) = aml().assessTransaction(
            keccak256(abi.encodePacked("fuzz-tx", amount)),
            seller,
            buyer,
            amount,
            keccak256("USD"),
            keccak256("PAYMENT")
        );

        assertLe(score.score, MAX_RISK_SCORE);
    }

    // ============================================================
    // setEntityRiskScore — capped at 1000, reverts above
    // ============================================================

    function testFuzz_setEntityRiskScore_capped(uint256 score) public {
        if (score > MAX_RISK_SCORE) {
            vm.prank(analyst);
            vm.expectRevert();
            aml().setEntityRiskScore(seller, score, "Fuzz");
        } else {
            vm.prank(analyst);
            aml().setEntityRiskScore(seller, score, "Fuzz");

            (uint256 stored,,) = aml().getEntityRiskProfile(seller);
            assertEq(stored, score);
        }
    }

    // ============================================================
    // flagSuspiciousActivity — escalation never exceeds 1000
    // ============================================================

    function testFuzz_flagSuspicious_escalation(uint256 currentScore) public {
        currentScore = bound(currentScore, 0, MAX_RISK_SCORE);

        _approveKYC(seller, currentScore);

        vm.prank(analyst);
        aml().flagSuspiciousActivity(seller, keccak256("fuzz-flag"), "Fuzz escalation");

        (uint256 escalated,,) = aml().getEntityRiskProfile(seller);
        assertLe(escalated, MAX_RISK_SCORE);

        uint256 expected = currentScore + 200 > MAX_RISK_SCORE ? MAX_RISK_SCORE : currentScore + 200;
        assertEq(escalated, expected);
    }

    // ============================================================
    // Helpers
    // ============================================================

    function _approveKYC(address entity, uint256 risk) internal {
        bytes32 idHash = keccak256(abi.encodePacked("id-", entity));
        vm.prank(entity);
        kyc().initiateKYC(entity, idHash, LibAppStorage.KYCLevel.STANDARD, keccak256("US"));
        vm.prank(verifier);
        kyc().approveKYC(entity, LibAppStorage.KYCLevel.STANDARD, bytes32(0), false, risk);
    }
}
