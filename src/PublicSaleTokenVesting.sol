// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol"; // Use OpenZeppelin's IERC20 interface

contract PublicSaleTokenVesting is Ownable {
    event AdminWithdrawal(address indexed account, uint256 reward);
    event VestingClaimed(address indexed account, uint256 reward);
    event VestingStarted(uint256 startTime);

    uint256 public constant duration = 100 days;
    uint256 public startTime;
    uint256 public maxClaimableTokens;
    uint256 public totalClaimedTokens;
    IERC20 public ion;

    struct Vest {
        uint256 total;
        uint256 claimedAmount;
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
        maxClaimableTokens += _claimable;
    }

    function start(uint256 _startTime) external onlyOwner {
        require(startTime == 0);
        startTime = _startTime;
        emit VestingStarted(startTime);
    }

    function getVestingAmount(address _user) external view returns (uint256) {
        return vests[_user].total;
    }

    function getClaimedAmount(address _user) external view returns (uint256) {
        return vests[_user].claimedAmount;
    }

    function calculateClaimable(uint256 total, uint256 claimedAmount) internal view returns (uint256) {
        uint256 elapsedTime = block.timestamp - startTime;
        uint256 _claimable;
        if (elapsedTime > duration) {
            // If the elapsed time exceeds the vesting duration, all tokens should be fully vested
            // The claimable amount is the total vested amount minus the already claimed amount
            _claimable = total - claimedAmount;
        } else {
            // If the elapsed time is within the vesting duration
            // Calculate the proportional vested amount based on the elapsed time
            _claimable = total * elapsedTime / duration - claimedAmount;
        }
        return _claimable;
    }

    function claimable(address _claimer) external view returns (uint256) {
        if (startTime == 0) return 0;
        Vest storage v = vests[_claimer];
        uint256 _claimable = calculateClaimable(v.total, v.claimedAmount);
        return _claimable;
    }

    function claim() external {
        require(startTime != 0);
        Vest storage v = vests[msg.sender];
        uint256 _claimable = calculateClaimable(v.total, v.claimedAmount);

        v.claimedAmount += _claimable;
        totalClaimedTokens += _claimable;
        require(totalClaimedTokens <= maxClaimableTokens);
        ion.transfer(msg.sender, _claimable);
        emit VestingClaimed(msg.sender, _claimable);
    }

    function withdraw(address _walletAddress) external onlyOwner {
        uint256 amount = IERC20(ion).balanceOf(address(this));
        bool success = IERC20(ion).transfer(_walletAddress, amount);
        require(success, "Withdrawal failed");
        emit AdminWithdrawal(_walletAddress, amount);
    }
}
