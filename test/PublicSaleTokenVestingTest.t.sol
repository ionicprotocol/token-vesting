// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import {Test, console} from "forge-std/Test.sol";
import "../src/PublicSaleTokenVesting.sol";
import {strings} from "solidity-stringutils/src/strings.sol";
import "../src/MockERC20.sol"; // Import the MockERC20 contract

contract TokenVestingTest is Test {
    using strings for *;

    PublicSaleTokenVesting public publicSaleTokenVesting;
    address alice = vm.addr(1);
    address bob = vm.addr(2);

    MockERC20 public ion;

    struct Vest {
        uint256 total;
        uint256 claimedAmount;
    }

    function setUp() public {
        ion = new MockERC20("Ionic", "ION");
        publicSaleTokenVesting = new PublicSaleTokenVesting(ion);
        ion.transfer(address(publicSaleTokenVesting), 1000000 ether);
    }

    function test_settingVestingAmounts() public {
        address[] memory addresses = new address[](2);
        addresses[0] = alice;
        addresses[1] = bob;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 700;
        amounts[1] = 300;

        vm.prank(publicSaleTokenVesting.owner());

        (bool success,) = address(publicSaleTokenVesting).call(
            abi.encodeWithSignature("setVestingAmounts(uint256,address[],uint256[])", 1000, addresses, amounts)
        );
        require(success, "Setting vesting amounts should pass");

        assertEq(publicSaleTokenVesting.getVestingAmount(alice), 700);
        assertEq(publicSaleTokenVesting.getVestingAmount(bob), 300);
    }

    function test_settingMultipleVestingAmounts() public {
        string memory eof = "";
        string memory line = vm.readLine("generated-points.csv");
        uint256 parsedSum = 0;
        address[] memory addresses = new address[](1000);
        uint256[] memory amounts = new uint256[](1000);
        uint256 index = 0;
        uint256 batchAmountSum = 0;
        while (true) {
            line = vm.readLine("generated-points.csv");
            if (keccak256(bytes(line)) == keccak256(bytes(eof))) {
                break;
            }
            strings.slice memory s = line.toSlice();
            strings.slice memory delim = ",".toSlice();
            string[] memory parts = new string[](2);
            for (uint256 i = 0; i < parts.length; i++) {
                parts[i] = s.split(delim).toString();
            }
            uint256 parsedInt = stringToUint(parts[1]);
            parsedSum += parsedInt;
            addresses[index] = stringToAddress(parts[0]); // this cast does not work correctly
            amounts[index] = parsedInt;
            batchAmountSum += parsedInt;
            if (index == 999) {
                vm.prank(publicSaleTokenVesting.owner());
                publicSaleTokenVesting.setVestingAmounts(batchAmountSum, addresses, amounts);
                index = 0;
                batchAmountSum = 0;
            } else {
                index += 1;
            }
        }
        if (index > 0) {
            address[] memory addressesLastBatch = new address[](index);
            uint256[] memory amountsLastBatch = new uint256[](index);
            for (uint256 i = 0; i < index; i++) {
                addressesLastBatch[i] = addresses[i];
                amountsLastBatch[i] = amounts[i];
            }
            vm.prank(publicSaleTokenVesting.owner());
            publicSaleTokenVesting.setVestingAmounts(batchAmountSum, addressesLastBatch, amountsLastBatch);
        }
        vm.prank(publicSaleTokenVesting.owner());
        assertEq(publicSaleTokenVesting.maxClaimableTokens(), 107991945);
    }

    function testFuzz_nonOwnerSettingVestingAmounts(address addr) public {
        vm.assume(addr != address(this));

        address[] memory addresses = new address[](2);
        addresses[0] = alice;
        addresses[1] = bob;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 700;
        amounts[1] = 300;

        vm.prank(addr);
        (bool success,) = address(publicSaleTokenVesting).call(
            abi.encodeWithSignature("setVestingAmounts(uint256,address[],uint256[])", 1000, addresses, amounts)
        );
        require(!success, "Setting vesting amounts should fail");
    }

    function testFail_totalClaimableSettingVestingAmounts() public {
        address[] memory addresses = new address[](2);
        addresses[0] = alice;
        addresses[1] = bob;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 700;
        amounts[1] = 300;

        vm.prank(publicSaleTokenVesting.owner());
        publicSaleTokenVesting.setVestingAmounts(900, addresses, amounts);
    }

    function test_start() public {
        vm.prank(publicSaleTokenVesting.owner());
        publicSaleTokenVesting.start(block.timestamp);

        assertEq(publicSaleTokenVesting.startTime(), block.timestamp);
    }

    function testFail_nonOwnerStart() public {
        vm.prank(alice);
        publicSaleTokenVesting.start(block.timestamp);
    }

    function testFail_secondCallStart() public {
        vm.prank(publicSaleTokenVesting.owner());
        publicSaleTokenVesting.start(block.timestamp);
        publicSaleTokenVesting.start(block.timestamp);
    }

    function test_claimableBeforeStart() public {
        publicSaleTokenVesting.claimable(alice);
        address[] memory addresses = new address[](2);
        addresses[0] = alice;
        addresses[1] = bob;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 700;
        amounts[1] = 300;

        vm.prank(publicSaleTokenVesting.owner());
        publicSaleTokenVesting.setVestingAmounts(1000, addresses, amounts);

        assertEq(publicSaleTokenVesting.getVestingAmount(alice), 700);
        assertEq(publicSaleTokenVesting.getVestingAmount(bob), 300);

        assertEq(publicSaleTokenVesting.claimable(alice), 0);
    }

    function test_secondClaim() public {
        publicSaleTokenVesting.claimable(alice);
        address[] memory addresses = new address[](2);
        addresses[0] = alice;
        addresses[1] = bob;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 700;
        amounts[1] = 300;

        vm.prank(publicSaleTokenVesting.owner());
        publicSaleTokenVesting.setVestingAmounts(1000, addresses, amounts);
        vm.prank(publicSaleTokenVesting.owner());
        publicSaleTokenVesting.start(block.timestamp);

        assertEq(publicSaleTokenVesting.getVestingAmount(alice), 700);
        assertEq(publicSaleTokenVesting.getVestingAmount(bob), 300);

        vm.prank(alice);
        publicSaleTokenVesting.claim();
        vm.prank(alice);
        publicSaleTokenVesting.claim();
    }

    function testFuzz_claimAfterXSeconds(uint256 secondsElapsed) public {
        vm.assume(secondsElapsed > 0 && secondsElapsed < 90 * 86400);
        vm.startPrank(publicSaleTokenVesting.owner());
        address[] memory addresses = new address[](2);
        addresses[0] = alice;
        addresses[1] = bob;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 700;
        amounts[1] = 300;

        publicSaleTokenVesting.setVestingAmounts(1000, addresses, amounts);
        publicSaleTokenVesting.start(block.timestamp);
        vm.stopPrank();

        vm.warp(secondsElapsed);

        uint256 expectedAliceClaimableAmount = uint256(700) * secondsElapsed / (100 * 86400);
        vm.prank(alice);
        publicSaleTokenVesting.claim();
        assertEq(ion.balanceOf(alice), expectedAliceClaimableAmount);

        uint256 expectedBobClaimableAmount = uint256(300) * secondsElapsed / (100 * 86400);
        vm.prank(bob);
        publicSaleTokenVesting.claim();
        assertEq(ion.balanceOf(bob), expectedBobClaimableAmount);
    }

    function testFuzz_claimableAfterXSeconds(uint256 secondsElapsed) public {
        vm.assume(secondsElapsed > 0 && secondsElapsed < 90 * 86400);

        vm.startPrank(publicSaleTokenVesting.owner());
        address[] memory addresses = new address[](2);
        addresses[0] = alice;
        addresses[1] = bob;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 700;
        amounts[1] = 300;

        publicSaleTokenVesting.setVestingAmounts(1000, addresses, amounts);
        publicSaleTokenVesting.start(block.timestamp);
        vm.stopPrank();

        vm.warp(secondsElapsed);

        uint256 expectedAliceClaimableAmount = uint256(700) * secondsElapsed / (100 * 86400);
        assertEq(publicSaleTokenVesting.claimable(alice), expectedAliceClaimableAmount);
        uint256 expectedBobClaimableAmount = uint256(300) * secondsElapsed / (100 * 86400);
        assertEq(publicSaleTokenVesting.claimable(bob), expectedBobClaimableAmount);
    }

    function testFuzz_nonOwnerWithdraw(address addr) public {
        vm.assume(addr != address(0));

        vm.prank(addr);
        (bool success,) =
            address(publicSaleTokenVesting).call(abi.encodeWithSignature("function withdraw(address)", addr));
        require(!success, "Setting vesting amounts should fail");
    }

    function test_withdraw() public {
        assertEq(ion.balanceOf(publicSaleTokenVesting.owner()), 0);

        publicSaleTokenVesting.withdraw(publicSaleTokenVesting.owner());
        assertEq(ion.balanceOf(publicSaleTokenVesting.owner()), 1000000 ether);
    }

    function stringToUint(string memory s) public pure returns (uint256) {
        bytes memory b = bytes(s);
        uint256 result = 0;
        for (uint256 i = 0; i < b.length; i++) {
            uint256 c = uint256(uint8(b[i]));
            if (c >= 48 && c <= 57) {
                result = result * 10 + (c - 48);
            }
        }
        return result;
    }

    function stringToAddress(string memory str) public pure returns (address) {
        bytes memory strBytes = bytes(str);
        require(strBytes.length == 42, "Invalid address length");
        bytes memory addrBytes = new bytes(20);

        for (uint256 i = 0; i < 20; i++) {
            addrBytes[i] = bytes1(hexCharToByte(strBytes[2 + i * 2]) * 16 + hexCharToByte(strBytes[3 + i * 2]));
        }

        return address(uint160(bytes20(addrBytes)));
    }

    function hexCharToByte(bytes1 char) internal pure returns (uint8) {
        uint8 byteValue = uint8(char);
        if (byteValue >= uint8(bytes1("0")) && byteValue <= uint8(bytes1("9"))) {
            return byteValue - uint8(bytes1("0"));
        } else if (byteValue >= uint8(bytes1("a")) && byteValue <= uint8(bytes1("f"))) {
            return 10 + byteValue - uint8(bytes1("a"));
        } else if (byteValue >= uint8(bytes1("A")) && byteValue <= uint8(bytes1("F"))) {
            return 10 + byteValue - uint8(bytes1("A"));
        }
        revert("Invalid hex character");
    }
}
