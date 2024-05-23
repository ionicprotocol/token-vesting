// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import {Test, console} from "forge-std/Test.sol";
import "../src/TokenVesting.sol";
import {strings} from "solidity-stringutils/src/strings.sol";

contract TokenVestingTest is Test {
    using strings for *;

    TokenVesting public tokenVesting;
    address alice = vm.addr(1);
    address bob = vm.addr(2);
    
    struct Vest {
        uint256 total;
        uint256 claimedAmount;
        bool isClaimed;
    }

    function setUp() public {
        tokenVesting = new TokenVesting();
    }

    function test_settingVestingAmounts() public {
        address[] memory addresses = new address[](2);
        addresses[0] = alice;
        addresses[1] = bob;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 700;
        amounts[1] = 300;

        vm.prank(tokenVesting.owner()); 
        tokenVesting.setVestingAmounts(1000, addresses, amounts);

        assertEq(tokenVesting.getVestingAmount(alice), 700);
        assertEq(tokenVesting.getVestingAmount(bob), 300);
    }

    function test_settingMultipleVestingAmounts() public {
        string memory eof = "";
        string memory line = vm.readLine("generated-points.csv");
        uint256 parsedSum = 0;
        address[] memory addresses = new address[](10000);
        uint256[] memory amounts = new uint256[](10000);
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
            for (uint i = 0; i < parts.length; i++) {
                parts[i] = s.split(delim).toString();
            }
            uint256 parsedInt = stringToUint(parts[1]);
            parsedSum += parsedInt;
            addresses[index] = stringToAddress(parts[0]); // this cast does not work correctly
            amounts[index] = parsedInt;
            batchAmountSum += parsedInt;
            if (index == 9999) {
                vm.prank(tokenVesting.owner()); 
                tokenVesting.setVestingAmounts(batchAmountSum, addresses, amounts);
                index = 0;
                batchAmountSum = 0;
            }
            else index +=1;
        }
        if (index > 0) {
            address[] memory addressesLastBatch = new address[](index);
            uint256[] memory amountsLastBatch = new uint256[](index);
            for(uint i=0;i<index;i++) {
                addressesLastBatch[i] = addresses[i];
                amountsLastBatch[i] = amounts[i];
            }
            vm.prank(tokenVesting.owner()); 
            tokenVesting.setVestingAmounts(batchAmountSum, addressesLastBatch, amountsLastBatch);
        }
        vm.prank(tokenVesting.owner()); 
        assertEq(tokenVesting.maxClaimedTokens(), 107991945);
    }

    function testFail_nonOwnerSettingVestingAmounts() public {
        address[] memory addresses = new address[](2);
        addresses[0] = alice;
        addresses[1] = bob;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 700;
        amounts[1] = 300;

        vm.prank(alice); 
        tokenVesting.setVestingAmounts(1000, addresses, amounts);
    }

    function testFail_totalClaimableSettingVestingAmounts() public {
        address[] memory addresses = new address[](2);
        addresses[0] = alice;
        addresses[1] = bob;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 700;
        amounts[1] = 300;

        vm.prank(tokenVesting.owner()); 
        tokenVesting.setVestingAmounts(900, addresses, amounts);
    }

    function test_start() public {
        vm.prank(tokenVesting.owner()); 
        tokenVesting.start();

        assertEq(tokenVesting.startTime(), block.timestamp);
    }

    function testFail_nonOwnerStart() public {
        vm.prank(alice); 
        tokenVesting.start();
    }

    function testFail_secondCallStart() public {
        vm.prank(tokenVesting.owner()); 
        tokenVesting.start();
        tokenVesting.start();
    }

    function test_claimableBeforeStart() public {
        tokenVesting.claimable(alice);
        address[] memory addresses = new address[](2);
        addresses[0] = alice;
        addresses[1] = bob;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 700;
        amounts[1] = 300;

        vm.prank(tokenVesting.owner()); 
        tokenVesting.setVestingAmounts(1000, addresses, amounts);

        assertEq(tokenVesting.getVestingAmount(alice), 700);
        assertEq(tokenVesting.getVestingAmount(bob), 300);

        assertEq(tokenVesting.claimable(alice), 0);
    }

    function test_claimableAfter1Day() public {
    	vm.startPrank(tokenVesting.owner()); 
    	address[] memory addresses = new address[](2);
        addresses[0] = alice;
        addresses[1] = bob;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 700;
        amounts[1] = 300;

        tokenVesting.setVestingAmounts(1000, addresses, amounts);
        tokenVesting.start();
        vm.stopPrank(); 

        vm.warp(86400);

        uint256 m = uint256(700)*90/100-uint256(700)*25/100;
        uint256 expectedAliceClaimableAmount = uint256(700)*25/100+m*1*86400/(90*86400);
        assertEq(tokenVesting.claimable(alice), expectedAliceClaimableAmount);
        uint256 mBob = uint256(300)*90/100-uint256(300)*25/100;
        uint256 expectedBobClaimableAmount = uint256(300)*25/100+mBob*1*86400/(90*86400);
        assertEq(tokenVesting.claimable(bob), expectedBobClaimableAmount);
    }

    function test_claimableAfter50Days() public {
    	vm.startPrank(tokenVesting.owner()); 
    	address[] memory addresses = new address[](2);
        addresses[0] = alice;
        addresses[1] = bob;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 700;
        amounts[1] = 300;

        tokenVesting.setVestingAmounts(1000, addresses, amounts);
        tokenVesting.start();
        vm.stopPrank(); 

        vm.warp(50*86400);

        uint256 m = uint256(700)*90/100-uint256(700)*25/100;
        uint256 expectedAliceClaimableAmount = uint256(700)*25/100+m*50*86400/(90*86400);
        assertEq(tokenVesting.claimable(alice), expectedAliceClaimableAmount);

        uint256 mBob = uint256(300)*90/100-uint256(300)*25/100;
        uint256 expectedBobClaimableAmount = uint256(300)*25/100+mBob*50*86400/(90*86400);
        assertEq(tokenVesting.claimable(bob), expectedBobClaimableAmount);
    }

    function test_claimableAfter90Days() public {
    	vm.startPrank(tokenVesting.owner()); 
    	address[] memory addresses = new address[](2);
        addresses[0] = alice;
        addresses[1] = bob;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 700;
        amounts[1] = 300;

        tokenVesting.setVestingAmounts(1000, addresses, amounts);
        tokenVesting.start();
        vm.stopPrank(); 

        vm.warp(10000000);

        uint256 expectedAliceClaimableAmount = 700;
        uint256 expectedBobClaimableAmount = 300;
        assertEq(tokenVesting.claimable(alice), expectedAliceClaimableAmount);
        assertEq(tokenVesting.claimable(bob), expectedBobClaimableAmount);
    }

    function stringToUint(string memory s) public pure returns (uint) {
        bytes memory b = bytes(s);
        uint result = 0;
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

        for (uint i = 0; i < 20; i++) {
            addrBytes[i] = bytes1(hexCharToByte(strBytes[2 + i * 2]) * 16 + hexCharToByte(strBytes[3 + i * 2]));
        }

        return address(uint160(bytes20(addrBytes)));
    }

    function hexCharToByte(bytes1 char) internal pure returns (uint8) {
        uint8 byteValue = uint8(char);
        if (byteValue >= uint8(bytes1('0')) && byteValue <= uint8(bytes1('9'))) {
            return byteValue - uint8(bytes1('0'));
        } else if (byteValue >= uint8(bytes1('a')) && byteValue <= uint8(bytes1('f'))) {
            return 10 + byteValue - uint8(bytes1('a'));
        } else if (byteValue >= uint8(bytes1('A')) && byteValue <= uint8(bytes1('F'))) {
            return 10 + byteValue - uint8(bytes1('A'));
        }
        revert("Invalid hex character");
    }
    // TODO: Add tests for function claim()
}
