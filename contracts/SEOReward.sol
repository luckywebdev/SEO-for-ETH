// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.4;
pragma experimental ABIEncoderV2;

import "./utils/IERC20.sol";
import "./utils/SafeMath.sol";

contract SEOReward is IERC20 {
    using SafeMath for uint256;

    uint256 private _totalPluginAmount;
    address private _rewardToken;

    struct PersonalData {
        uint blocktime;
        uint amount;
        uint lastRewardAmount;
        uint lastRewardTime;
    }

    mapping (address => PersonalData[]) private _rewardData;

    constructor(address rewardToken) {
        _rewardToken = rewardToken;
    }

    function storePluginData(address holderAddress, uint pluginAmount) public returns (bool) {
        require(holderAddress != address(0), 'ERR: zero address');
        require(pluginAmount > 0, 'ERR: zero plugin installed');
        _totalPluginAmount = _totalPluginAmount.add(pluginAmount);
        uint dataCount = _rewardData[holderAddress].length;
        uint holderBalance = IERC20(_rewardToken).balanceOf(holderAddress);
        uint totalHolderPluginAmount = _rewardData[holderAddress][dataCount - 1].pluginAmount.add(pluginAmount);
        uint rewardTokenAmount = ((holderBalance.mul(totalHolderPluginAmount).mul(100)).div(_totalPluginAmount)).div(100);
        if(dataCount == 0) {
            PersonalData memory p;
            p.blocktime = block.timestamp;
            p.amount = totalHolderPluginAmount;
            p.estimatedRewardAmount = 0;
            p.lastRewardTime = block.timestamp;
            _rewardData[holderAddress].push(p);
        }
        else {
            PersonalData memory p;
            p.blocktime = block.timestamp;
            p.amount = totalHolderPluginAmount;
            p.estimatedRewardAmount = rewardTokenAmount;
            p.lastRewardTime = _rewardData[holderAddress][0].lastRewardTime;
            _rewardData[holderAddress].push(p);
        }
    }

    function requestReward(address holderAddress) public returns (bool) {
        require(holderAddress == msg.sender, 'ERR: msg sender must be holder address');
        uint day_diff = ((block.timestamp).sub(_rewardData[holderAddress][0].lastRewardTime)).div(1 days);
        require(day_diff >= 1, 'ERR: much soon');
        uint preRewardAmount = 0;
        uint startBlock = 0;
        uint8 dayCount = 0;
        for(uint i = 1; i <= day_diff; i++) {
            for(uint k = startBlock; k < _rewardData[holderAddress].length; k++) {
                if(_rewardData[holderAddress][k].blocktime < (_rewardData[holderAddress][0].blocktime).add((i).mul(1 days))) {
                    continue;
                }
                else if (_rewardData[holderAddress][k].blocktime < (_rewardData[holderAddress][0].blocktime).add((i + 1).mul(1 days))){
                    preRewardAmount = preRewardAmount.add(_rewardData[holderAddress][k].estimatedRewardAmount);
                    if(dayCount + 1 < i) {
                        uint addAmount = (_rewardData[holderAddress][k-1].estimatedRewardAmount).mul((i.sub(dayCount).sub(1)));
                        preRewardAmount = preRewardAmount.add(addAmount);
                    }
                    dayCount = i;
                    startBlock = k;
                    break;
                }
                else {
                    break;
                }
            }
        }
        if(preRewardAmount > 0) {
            IERC20(_rewardToken).transfer(holderAddress, preRewardAmount);
            uint dataCount = _rewardData[holderAddress].length;
            uint totalHolderPluginAmount = _rewardData[holderAddress][dataCount - 1].pluginAmount;
            PersonalData memory p;
            p.blocktime = block.timestamp;
            p.amount = totalHolderPluginAmount;
            p.estimatedRewardAmount = rewardTokenAmount;
            p.lastRewardTime = _rewardData[holderAddress][0].lastRewardTime;
            _rewardData[holderAddress].push(p);
        }
        return true;
    }
}