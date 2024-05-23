// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";


contract TokenVesting is OwnableUpgradeable {
    uint256 public startTime;
    uint256 public constant duration = 86400 * 90;
    uint256 public maxClaimedTokens;
    uint256 public claimedTokens;
    IERC20 public ion;

    struct Vest {
        uint256 total;
        uint256 claimedAmount;
        bool isClaimed;
    }

    mapping(address => Vest) public vests;

    function initialize(IERC20 _ion) external initializer {
        ion = _ion;
    }

    function setVestingAmounts(
        uint256 _totalClaimable,
        address[] memory _receivers,
        uint256[] memory _amounts
    ) onlyOwner external {
        require(_receivers.length == _amounts.length);
        uint256 claimable;
        for (uint256 i = 0; i < _receivers.length; i++) {
            require(vests[_receivers[i]].total == 0);
            claimable += _amounts[i];
            vests[_receivers[i]].total = _amounts[i];
        }
        require(claimable == _totalClaimable);
        maxClaimedTokens += claimable;
    }

    function start() onlyOwner external {
        require(startTime == 0);
        startTime = block.timestamp;
    }

    function getVestingAmount(address _user) external returns (uint256) {
      return vests[_user].total;
    }

    function claimable(address _claimer) external view returns (uint256) {
        if (startTime == 0) return 0;
        Vest storage v = vests[_claimer];
        uint256 elapsedTime = block.timestamp - startTime;
        uint256 claimable;
        if (elapsedTime > duration) claimable = v.total;
        else {
            uint256 m = v.total * 90 / 100 - v.total * 25 / 100;
            claimable = v.total * 25 / 100 + m * elapsedTime / duration;
        }
        return claimable;
    }

    function claim(address _receiver) external {
        require(startTime != 0);
        Vest storage v = vests[msg.sender];
        require(!v.isClaimed, "User already claimed.");
        uint256 elapsedTime = block.timestamp - startTime;
        uint256 claimable;
        if (elapsedTime > duration) claimable = v.total;
        else {
            uint256 m = v.total * 90 / 100 - v.total * 25 / 100;
            claimable = v.total * 25 / 100 + m * elapsedTime / duration;
        }
        v.claimedAmount = claimable;
        claimedTokens += claimable;
        require(v.total - claimable >= 0);
        maxClaimedTokens -= (v.total - claimable);
        require(claimedTokens <= maxClaimedTokens);
        ion.transfer(msg.sender, claimable);
    }
}