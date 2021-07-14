const NewBuff = artifacts.require("NewBuff");

contract('NewBuff', (accounts) => {
  let buffTokenInstance;
  before(async () => {
    buffTokenInstance = await NewBuff.deployed();
  });

  it('should be 0.5 for the rate of token vs BNB', async () => {
    const rateOrigin = await buffTokenInstance.rate();
    assert.equal(rateOrigin.valueOf(), 0, "0 wasn in the first deploying");
    await buffTokenInstance.setRate(500);
    const rateCurrent = await buffTokenInstance.rate();
    assert.equal(rateCurrent, 0.5, "0.5 wasn in rate setting");

  });
  it('should confirm seo token info correctly', async () => {
    const buffTokenOwner = await buffTokenInstance.getOwner.call();

    // Get initial token owner address.
    assert.equal(buffTokenOwner, accounts[0], "SEO token owner wasn't first account correctly");
  });
  it('should be set token holders and lquidity pool, reward wallet correctly', async () => {

    // Set token holders and liquidity, reward wallet.
    await buffTokenInstance.setHolders(0x6EF5A3a808aF1104151F0aE7Af59fA3D691e946c);
    const holders = await buffTokenInstance.getHolders().call({from: account[0]});
    assert.equal(holders[0], "0x6EF5A3a808aF1104151F0aE7Af59fA3D691e946c", "Holders address is not correctly");
 
    await buffTokenInstance.setLiquidity(0x8dDa136Be59c0BaEce2fBdD49A498F78f184E2ef);
    const liquidity = await buffTokenInstance.getLiquidity().call({from: account[0]});
    assert.equal(liquidity, "0x8dDa136Be59c0BaEce2fBdD49A498F78f184E2ef", "liquidity address is not correctly");

    await buffTokenInstance.setRewardWallet(0x25c13Ac1562FB4359F9d227ac42eAcEBfE96bFC9);
    const rewardWallet = await buffTokenInstance.getRewardWallet().call({from: account[0]});
    assert.equal(rewardWallet, "0x25c13Ac1562FB4359F9d227ac42eAcEBfE96bFC9", "reward Wallet address is not correctly");
  });
});
