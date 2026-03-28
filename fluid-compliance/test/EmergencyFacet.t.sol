// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DiamondTestHelper} from "./helpers/DiamondTestHelper.sol";
import {EmergencyFacet} from "../src/facets/EmergencyFacet.sol";
import {LibAppStorage, SystemPaused} from "../src/libraries/LibAppStorage.sol";

contract EmergencyFacetTest is DiamondTestHelper {

    // ============================================================
    // emergencyPause
    // ============================================================

    function test_emergencyPause_pausesSystem() public {
        vm.prank(pauser);
        EmergencyFacet(diamond).emergencyPause();

        // Any whenNotPaused function should now revert
        vm.prank(seller);
        vm.expectRevert(SystemPaused.selector);
        kyc().initiateKYC(seller, keccak256("id"), LibAppStorage.KYCLevel.BASIC, keccak256("US"));
    }

    function test_emergencyPause_revertsIfNotPauser() public {
        vm.prank(seller);
        vm.expectRevert();
        EmergencyFacet(diamond).emergencyPause();
    }

    function test_emergencyPause_revertsIfAlreadyPaused() public {
        vm.prank(pauser);
        EmergencyFacet(diamond).emergencyPause();

        vm.prank(pauser);
        vm.expectRevert();
        EmergencyFacet(diamond).emergencyPause();
    }

    // ============================================================
    // emergencyUnpause
    // ============================================================

    function test_emergencyUnpause_resumesSystem() public {
        vm.prank(pauser);
        EmergencyFacet(diamond).emergencyPause();

        vm.prank(owner); // owner has EMERGENCY_ADMIN_ROLE from DiamondInit
        EmergencyFacet(diamond).emergencyUnpause();

        // System should work again
        vm.prank(seller);
        kyc().initiateKYC(seller, keccak256("id"), LibAppStorage.KYCLevel.BASIC, keccak256("US"));
    }

    function test_emergencyUnpause_revertsIfNotPaused() public {
        vm.prank(owner);
        vm.expectRevert();
        EmergencyFacet(diamond).emergencyUnpause();
    }

    function test_emergencyUnpause_revertsIfNotEmergencyAdmin() public {
        vm.prank(pauser);
        EmergencyFacet(diamond).emergencyPause();

        vm.prank(seller);
        vm.expectRevert();
        EmergencyFacet(diamond).emergencyUnpause();
    }

    // ============================================================
    // scheduleEmergencyUpgrade
    // ============================================================

    function test_scheduleEmergencyUpgrade_emitsEvent() public {
        vm.expectEmit(false, false, false, false, diamond);
        emit EmergencyFacet.EmergencyUpgradeScheduled(bytes32(0), 0);

        vm.prank(owner);
        EmergencyFacet(diamond).scheduleEmergencyUpgrade(keccak256("upgrade-1"), 24 hours);
    }

    function test_scheduleEmergencyUpgrade_revertsIfTimelockTooShort() public {
        vm.prank(owner);
        vm.expectRevert();
        EmergencyFacet(diamond).scheduleEmergencyUpgrade(keccak256("upgrade"), 1 hours);
    }

    function test_scheduleEmergencyUpgrade_revertsIfNotEmergencyAdmin() public {
        vm.prank(seller);
        vm.expectRevert();
        EmergencyFacet(diamond).scheduleEmergencyUpgrade(keccak256("upgrade"), 24 hours);
    }

    // ============================================================
    // emergencyWithdraw
    // ============================================================

    function test_emergencyWithdraw_ethToTreasury() public {
        vm.deal(diamond, 1 ether);
        uint256 before = treasury.balance;

        vm.prank(owner);
        EmergencyFacet(diamond).emergencyWithdraw(address(0), 1 ether);

        assertEq(treasury.balance, before + 1 ether);
    }
}
