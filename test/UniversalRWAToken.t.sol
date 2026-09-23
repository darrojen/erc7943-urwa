// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/UniversalRWAToken.sol";

contract UniversalRWATokenTest is Test {
    UniversalRWAToken token;

    address admin = address(0xA11CE);
    address alice = address(0xB0B);
    address bob = address(0xC0B);
    address charlie = address(0xD0D);
    address recovery = address(0xE0E);

    uint256 constant SUPPLY = 1_000_000 ether;

    function setUp() public {
        vm.prank(admin);
        token = new UniversalRWAToken("Universal RWA Token", "uRWA", SUPPLY);

        vm.startPrank(admin);
        token.setAllowlist(alice, true);
        token.setAllowlist(bob, true);
        token.setAllowlist(recovery, true);
        token.transfer(alice, 10_000 ether);
        vm.stopPrank();
    }

    function testInitialSupplyAndAdmin() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(admin), SUPPLY - 10_000 ether);
        assertEq(token.admin(), admin);
        assertTrue(token.canSend(admin));
        assertTrue(token.canReceive(admin));
    }

    function testSuccessfulAllowlistedTransfer() public {
        vm.prank(alice);
        bool result = token.transfer(bob, 1_000 ether);

        assertTrue(result);
        assertEq(token.balanceOf(alice), 9_000 ether);
        assertEq(token.balanceOf(bob), 1_000 ether);
        assertTrue(token.canTransfer(alice, bob, 1_000 ether));
    }

    function testApproveAndTransferFrom() public {
        vm.prank(alice);
        token.approve(charlie, 500 ether);

        // ERC-20 spender eligibility is separate from the token's sender/receiver policy.
        vm.prank(charlie);
        assertTrue(token.transferFrom(alice, bob, 500 ether));

        assertEq(token.balanceOf(bob), 500 ether);
        assertEq(token.allowance(alice, charlie), 0);
    }

    function testFreezePreventsTransfer() public {
        vm.prank(admin);
        token.setFrozenTokens(alice, 4_000 ether);

        assertEq(token.getFrozenTokens(alice), 4_000 ether);
        assertFalse(token.canTransfer(alice, bob, 4_001 ether));
        assertTrue(token.canTransfer(alice, bob, 4_000 ether));

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC7943Fungible.ERC7943InsufficientUnfrozenBalance.selector,
                alice,
                4_001 ether,
                6_000 ether
            )
        );
        token.transfer(bob, 4_001 ether);
    }

    function testUnfreezeRestoresTransferability() public {
        vm.startPrank(admin);
        token.setFrozenTokens(alice, 10_000 ether);
        token.setFrozenTokens(alice, 0);
        vm.stopPrank();

        assertEq(token.getFrozenTokens(alice), 0);

        vm.prank(alice);
        assertTrue(token.transfer(bob, 2_000 ether));
        assertEq(token.balanceOf(bob), 2_000 ether);
    }

    function testForcedTransferCanMoveFrozenTokens() public {
        vm.startPrank(admin);
        token.setFrozenTokens(alice, 10_000 ether);
        vm.expectEmit(true, true, false, true);
        emit IERC7943Fungible.Frozen(alice, 9_000 ether);
        vm.expectEmit(true, true, false, true);
        emit IERC7943Fungible.ForcedTransfer(alice, recovery, 1_000 ether);
        assertTrue(token.forcedTransfer(alice, recovery, 1_000 ether));
        vm.stopPrank();

        assertEq(token.balanceOf(alice), 9_000 ether);
        assertEq(token.balanceOf(recovery), 1_000 ether);
        assertEq(token.getFrozenTokens(alice), 9_000 ether);
    }

    function testForcedTransferUnfreezesOnlyAmountMoved() public {
        vm.startPrank(admin);
        token.setFrozenTokens(alice, 4_000 ether);
        token.forcedTransfer(alice, recovery, 5_000 ether);
        vm.stopPrank();

        assertEq(token.balanceOf(alice), 5_000 ether);
        assertEq(token.getFrozenTokens(alice), 0);
    }

    function testAllowlistRestrictionOnSender() public {
        vm.prank(admin);
        token.setAllowlist(alice, false);

        assertFalse(token.canSend(alice));
        assertFalse(token.canTransfer(alice, bob, 1 ether));

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IERC7943Fungible.ERC7943CannotSend.selector, alice)
        );
        token.transfer(bob, 1 ether);
    }

    function testAllowlistRestrictionOnReceiver() public {
        vm.prank(admin);
        token.setAllowlist(bob, false);

        assertFalse(token.canReceive(bob));
        assertFalse(token.canTransfer(alice, bob, 1 ether));

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IERC7943Fungible.ERC7943CannotReceive.selector, bob)
        );
        token.transfer(bob, 1 ether);
    }

    function testNonAdminCannotFreeze() public {
        vm.prank(alice);
        vm.expectRevert(UniversalRWAToken.NotAdmin.selector);
        token.setFrozenTokens(alice, 100 ether);
    }

    function testNonAdminCannotForceTransfer() public {
        vm.prank(alice);
        vm.expectRevert(UniversalRWAToken.NotAdmin.selector);
        token.forcedTransfer(alice, recovery, 100 ether);
    }

    function testNonAdminCannotUpdateAllowlist() public {
        vm.prank(alice);
        vm.expectRevert(UniversalRWAToken.NotAdmin.selector);
        token.setAllowlist(charlie, true);
    }

    function testForceTransferToNonAllowlistedReceiverReverts() public {
        vm.prank(admin);
        token.setAllowlist(recovery, false);

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IERC7943Fungible.ERC7943CannotReceive.selector, recovery)
        );
        token.forcedTransfer(alice, recovery, 100 ether);
    }

    function testTransferExceedingBalanceUsesBaseTokenError() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                UniversalRWAToken.ERC20InsufficientBalance.selector,
                alice,
                10_000 ether,
                10_001 ether
            )
        );
        token.transfer(bob, 10_001 ether);
    }

    function testCanTransferDoesNotFailForBaseBalanceCheck() public view {
        // ERC-7943 says non-permissioned base-token checks such as balance belong to ERC-20.
        assertTrue(token.canTransfer(alice, bob, 10_001 ether));
    }

    function testSupportsERC165AndERC7943() public view {
        assertTrue(token.supportsInterface(0x01ffc9a7));
        assertTrue(token.supportsInterface(0x3edbb4c4));
        assertFalse(token.supportsInterface(0xffffffff));
    }

    function testFrozenCanExceedBalance() public {
        vm.prank(admin);
        token.setFrozenTokens(alice, 50_000 ether);

        assertEq(token.getFrozenTokens(alice), 50_000 ether);
        assertFalse(token.canTransfer(alice, bob, 1 ether));
    }
}
