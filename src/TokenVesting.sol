// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol"; // Use OpenZeppelin's IERC20 interface

contract TokenVesting is Ownable {
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

    constructor(IERC20 _ion) Ownable(msg.sender) {
        ion = _ion;
    }

    function setVestingAmounts(uint256 _totalClaimable, address[] memory _receivers, uint256[] memory _amounts)
        external
        onlyOwner
    {
        require(_receivers.length == _amounts.length);
        uint256 _claimable;
        for (uint256 i = 0; i < _receivers.length; i++) {
            require(vests[_receivers[i]].total == 0);
            _claimable += _amounts[i];
            vests[_receivers[i]].total = _amounts[i];
        }
        require(_claimable == _totalClaimable);
        maxClaimedTokens += _claimable;
    }

    function start() external onlyOwner {
        require(startTime == 0);
        startTime = block.timestamp;
    }

    function getVestingAmount(address _user) external view returns (uint256) {
        return vests[_user].total;
    }

    function claimable(address _claimer) external view returns (uint256) {
        if (startTime == 0) return 0;
        Vest storage v = vests[_claimer];
        uint256 elapsedTime = block.timestamp - startTime;
        uint256 _claimable;
        if (elapsedTime > duration) {
            _claimable = v.total;
        } else {
            uint256 m = v.total * 90 / 100 - v.total * 25 / 100;
            _claimable = v.total * 25 / 100 + m * elapsedTime / duration;
        }
        return _claimable;
    }

    function claim() external {
        require(startTime != 0);
        Vest storage v = vests[msg.sender];
        require(!v.isClaimed, "User already claimed.");
        uint256 elapsedTime = block.timestamp - startTime;
        uint256 _claimable;
        if (elapsedTime > duration) {
            _claimable = v.total;
        } else {
            uint256 m = v.total * 90 / 100 - v.total * 25 / 100;
            _claimable = v.total * 25 / 100 + m * elapsedTime / duration;
        }
        v.claimedAmount = _claimable;
        claimedTokens += _claimable;
        require(v.total - _claimable >= 0);
        maxClaimedTokens -= (v.total - _claimable);
        require(claimedTokens <= maxClaimedTokens);
        ion.transfer(msg.sender, _claimable);
    }

    function withdraw(address _walletAddress) external onlyOwner {
        uint256 amount = IERC20(ion).balanceOf(address(this));
        bool success = IERC20(ion).transfer(_walletAddress, amount);
        require(success, "Withdrawal failed");
    }
}
