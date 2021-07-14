# ![SEO Logo](/assets/seo/32x32.png) SEO-token 
SEO token description 

    1. Introduction
SEO token is SEO.MONEY protocol token based on BEP20 standard, which aims to provide rewards for website owners in SEO.MONEY service.
SEO will be allocated to token holders, liquidity pool, reward pool addresses with 5% transaction fee of SEO.


    2. Token basic info
Token name: SEO coin
Token symbol: SEO
Token decimals: 18
Token total supply: 21 trillion
Token contract address:
 - bsc testnet: 
 - bsc mainnet: 
 
Token transaction fee allocation: 2%-token holders, 2%-liquidity pool address, 1%-reward pool address
Token is mintable and pausable.

    3. Token functions
Token is based on BEP 20 standard, and so basic token functions are inherited from BEP20 interface
Inherited BEP20 basic token functions : allowance, balanceOf, approve, transfer, transferFrom, increaseAllowance, decreaseAllowance, mint, pause and unpause

Ownable contract functions:
- transferOwnership(address newOwner)
    It will change owner of SEO token contract to new owner.

Pausable contract functions:
- pause()/unpause()
    It makes token don’t mint.

SEO has additional functions for transaction fee allocation.
- setRate(uint256 rateBNB)
    It can be used to set rate of token vs BNB.
    It is 3 decimal function. So you should set the argument to 500 to set 0.5 rates.
    It is ownable function so only owner can set rate.

- setHolders(address holder)
    It is the function to set holder address to get 2% reward allocated from transaction fee.
    It is also ownable function and so only owner can adjust this function.
    After set holder address, owner can check holders list with getHolders function.

- setLiquidity(address liquidity)
    It is the function to set liquidity address to get 2% reward allocated from transaction fee.
    It is also ownable function and so only owner can set and change liquidtiy address using this function.
    After set liquidity address, owner can check current liquidity address with getLiquidity function.

- setRewardWallet(address liquidity)
    It is the function to set reward wallet address to get 1% reward allocated from transaction fee.
    It is also ownable function and so only owner can set and change reward wallet address using this function.
    After set reward wallet address, owner can check current reward wallet address with getRewardWallet function.

- buyTokens(address payable seller)
    You can buy and sell SEO token with BNB using this function.
    While transfering, rate owner set using setRate function will be used.
    5% transaction fee of SEO buy or sell is allocated to holders and liquidity, reward wallet addresses with its own percentage.

- transferWithReward(address[] _receipent, uint[] _rewardRate)
    RewardPool can transfer to website owners SEO token as reward with some rate.
    msg sender must be the same as rewardPool address.
