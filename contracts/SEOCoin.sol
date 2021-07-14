// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.4;

import "./utils/Context.sol";
import "./utils/IUniswapV2Factory.sol";
import "./utils/IUniswapV2Pair.sol";
import "./utils/IUniswapV2Router02.sol";
import "./utils/IERC20.sol";
import "./utils/Ownable.sol";
import "./utils/SafeMath.sol";


/**
 * @notice ERC20 token with cost basis tracking and restricted loss-taking
 */
contract SEOCoin is Context, IERC20, Ownable {
    using SafeMath for uint256;

    address private constant UNISWAP_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address private constant WETH           = 0xc778417E063141139Fce010982780140Aa0cD5Ab;

    mapping (address => uint256) private _rOwned;
    mapping (address => uint256) private _tOwned;
    mapping (address => mapping (address => uint256)) private _allowances;

    mapping(address => uint256) private _basisOf;
    mapping(address => uint256) public cooldownOf;

    mapping (address => bool) private _isExcluded;
    address[] private _excluded;

    string  private _NAME;
    string  private _SYMBOL;
    uint256 private _DECIMALS;
   
    uint256 private _MAX = ~uint256(0);
    uint256 private _DECIMALFACTOR;
    uint256 private _GRANULARITY = 100;
    
    uint256 private _tTotal;
    uint256 private _rTotal;
    
    uint256 private _tFeeTotal;
    uint256 private _tBurnTotal;
    uint256 private _tMarketingFeeTotal;

    uint256 public    _TAX_FEE; // 2%
    uint256 public   _BURN_FEE; // 1%
    uint256 public _MARKET_FEE; // 2%

    // Track original fees to bypass fees for charity account
    uint256 private _maxTeamMintAmount = 1e8 ether;
    uint256 private _currentLiquidity;
    uint256 private _openAt;
    uint256 private _closeAt;
    uint256 private _ath;
    uint256 private _athTimestamp;
    uint256 private _initialBasis;
    uint256 private mintedSupply;


    address private _shoppingCart;
    address private _rewardWallet;
    address private _pair;

    bool private _paused;

    struct LockedAddress {
        uint64 lockedPeriod;
        uint64 endTime;
    }
    
    struct Minting {
        address recipient;
        uint amount;
    }

    mapping(address => address) private _referralOwner;

    mapping(address => LockedAddress) private _lockedList;

    /**
     * @notice deploy
     */
    constructor (string memory _name, string memory _symbol, uint256 _decimals, uint256 _supply) {
		_NAME = _name;
		_SYMBOL = _symbol;
		_DECIMALS = _decimals;
		_DECIMALFACTOR = 10 ** uint256(_DECIMALS);
		_tTotal =_supply * _DECIMALFACTOR;
		_rTotal = (_MAX - (_MAX % _tTotal));

        // setup uniswap pair and store address
        _pair = IUniswapV2Factory(IUniswapV2Router02(UNISWAP_ROUTER).factory())
            .createPair(WETH, address(this));
        _rOwned[address(this)] = _rTotal;
        _excludeAccount(_msgSender());
        _excludeAccount(address(this));
        _excludeAccount(_pair);
        _excludeAccount(UNISWAP_ROUTER);

        // prepare to add liquidity
        _approve(address(this), UNISWAP_ROUTER, _rTotal);
        _approve(_pair, UNISWAP_ROUTER, _rTotal);
        _approve(address(this), owner(), _rTotal);

        // prepare to remove liquidity
        IERC20(_pair).approve(UNISWAP_ROUTER, type(uint256).max);

        _paused = true;
    }

    /**
     * @dev modifier for mint or burn limit
     */
    modifier isNotPaused() {
        require(_paused == false, "ERR: paused already");
        _;
    }

    receive() external payable {}

    function name() public view returns (string memory) {
        return _NAME;
    }

    function symbol() public view returns (string memory) {
        return _SYMBOL;
    }

    function decimals() public view returns (uint256) {
        return _DECIMALS;
    }

    function totalSupply() public view override returns (uint256) {
        return _tTotal;
    }

    function balanceOf(address account) public view override returns (uint256) {
        if (_isExcluded[account]) return _tOwned[account];
        return tokenFromReflection(_rOwned[account]);
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "TOKEN20: transfer amount exceeds allowance"));
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedValue, "TOKEN20: decreased allowance below zero"));
        return true;
    }

    function isExcluded(address account) public view returns (bool) {
        return _isExcluded[account];
    }
    
    function totalFees() public view returns (uint256) {
        return _tFeeTotal;
    }
    
    function totalBurn() public view returns (uint256) {
        return _tBurnTotal;
    }
    
    function totalMarketingFees() public view returns (uint256) {
        return _tMarketingFeeTotal;
    }

    function reflectionFromToken(uint256 tAmount, bool deductTransferFee) public view returns(uint256) {
        require(tAmount <= _tTotal, "Amount must be less than supply");
        if (!deductTransferFee) {
            (uint256 rAmount,,,,,,) = _getValues(tAmount);
            return rAmount;
        } else {
            (,uint256 rTransferAmount,,,,,) = _getValues(tAmount);
            return rTransferAmount;
        }
    }

    function tokenFromReflection(uint256 rAmount) public view returns(uint256) {
        require(rAmount <= _rTotal, "Amount must be less than total reflections");
        uint256 currentRate =  _getRate();
        return rAmount.div(currentRate);
    }

    function excludeAccount(address account) external onlyOwner() {
       _excludeAccount(account);
    }

    function _excludeAccount(address account) private {
        require(!_isExcluded[account], "Account is already excluded");
        if(_rOwned[account] > 0) {
            _tOwned[account] = tokenFromReflection(_rOwned[account]);
        }
        _isExcluded[account] = true;
        _excluded.push(account);
    }

    function includeAccount(address account) external onlyOwner() {
        require(_isExcluded[account], "Account is already excluded");
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_excluded[i] == account) {
                _excluded[i] = _excluded[_excluded.length - 1];
                _tOwned[account] = 0;
                _isExcluded[account] = false;
                _excluded.pop();
                break;
            }
        }
    }

	function _burn(address _who, uint256 _value) internal {
		require(_value <= _rOwned[_who], "ERR: burn amount exceed balance");
		_rOwned[_who] = _rOwned[_who].sub(_value);
		_tTotal = _tTotal.sub(_value);
		emit Transfer(_who, address(0), _value);
	}

    function _mint(address account, uint256 amount) internal {
        _tTotal = _tTotal.add(amount);
        _rOwned[account] = _rOwned[account].add(amount);
        emit Transfer(address(0), account, amount);
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "TOKEN20: approve from the zero address");
        require(spender != address(0), "TOKEN20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function basisOf(address account) public view returns (uint256) {
        uint256 basis = _basisOf[account];

        if (basis == 0 && balanceOf(account) > 0) {
            basis = _initialBasis;
        }
        return basis;
    }

    function addLiquidity (uint liquidityAmount) external onlyOwner isNotPaused {
        uint ethBalance = address(this).balance;
        require(ethBalance > 0, 'ERR: zero ETH balance');

        // add liquidity, set initial cost basis
        uint limitAmount = 5e8 ether;
        require(limitAmount >= _currentLiquidity.add(liquidityAmount), "ERR: liquidity amount must be less than 500,000,000");

        _initialBasis = ((1 ether) * ethBalance / liquidityAmount);

        (uint amountToken, , ) = IUniswapV2Router02(
            UNISWAP_ROUTER
        ).addLiquidityETH{
            value: address(this).balance
        }(
            address(this),
            liquidityAmount,
            0,
            0,
            address(this),
            block.timestamp
        );
        _currentLiquidity = _currentLiquidity.add(amountToken);
        _openAt = block.timestamp;
        _closeAt = 0;
    }

    function removeLiquidity () external onlyOwner isNotPaused {
        require(_openAt > 0, 'ERR: not yet opened');
        require(_closeAt == 0, 'ERR: already closed');
        require(block.timestamp > _openAt + (5 minutes), 'ERR: too soon');

        require(
            block.timestamp > _athTimestamp + (5 minutes),
            'ERR: recent ATH'
        );

        IUniswapV2Router02(
            UNISWAP_ROUTER
        ).removeLiquidityETH(
            address(this),
            IERC20(_pair).balanceOf(address(this)),
            0,
            0,
            address(this),
            block.timestamp
        );

        uint payout = address(this).balance;

        payable(_msgSender()).transfer(payout);

        _closeAt = block.timestamp;
    }

    function setBusinessDev(address walletAddress) external onlyOwner returns (bool) {
        require(walletAddress != address(0), "ERR: zero address");
        _shoppingCart = walletAddress;
        uint256 businessAmount = 5e7 ether;
        _setFees(0, 0, 0);
        _transferFromExcluded(address(this), walletAddress, businessAmount);
        _setFees(300, 300, 0);
        _excludeAccount(walletAddress);
        return true;
    }

    function setRewardAddress(address rewardAddress) external onlyOwner returns (bool) {
        require(rewardAddress != address(0), "ERR: zero address");
        _rewardWallet = rewardAddress;
        uint256 burnAmount = 35 * 1e5 ether;
        _setFees(0, 0, 0);
        _transferFromExcluded(address(this), rewardAddress, burnAmount);
        _setFees(300, 300, 0);
        _approve(rewardAddress, owner(), _MAX);
        _excludeAccount(rewardAddress);
        return true;
    }

    function setReferralOwner(address referralUser, address referralOwner) external returns (bool) {
        require(_referralOwner[referralUser] == address(0), 'ERR: address registered already');
        require(referralUser != address(0), 'ERR: zero address');
        require(referralOwner != address(0), 'ERR: zero address');
        _referralOwner[referralUser] = referralOwner;
        return true;
    }
    
    function mintDev(Minting[] calldata mintings) external onlyOwner returns (bool) {
        require(mintings.length > 0, "ERR: zero address array");
        _setFees(0, 0, 0);       
        for(uint i = 0; i < mintings.length; i++) {
            Minting memory m = mintings[i];
            uint amount = m.amount;
            address recipient = m.recipient;

            mintedSupply += amount;
            require(mintedSupply <= _maxTeamMintAmount, "ERR: exceed max team mint amount");
            _transferFromExcluded(address(this), recipient, amount);
            _lockAddress(recipient, uint64(180 seconds));
        }        
        _setFees(300, 300, 0);
        return true;
    }    
    
    function pausedEnable() external onlyOwner returns (bool) {
        require(_paused == false, "ERR: already pause enabled");
        _paused = true;
        return true;
    }

    function pausedNotEnable() external onlyOwner returns (bool) {
        require(_paused == true, "ERR: already pause disabled");
        _paused = false;
        return true;
    }

    function checkPairAddress()
        external
        view
        returns (address)
    {
        return _pair;
    }

    function checkETHBalance(address payable checkAddress) external view returns (uint) {
        require(checkAddress != address(0), "ERR: check address must not be zero");
        uint balance = checkAddress.balance;
        return balance;
    }

    function checkLockTime(address lockedAddress) external view returns (uint64, uint64) {
        return (_lockedList[lockedAddress].lockedPeriod, _lockedList[lockedAddress].endTime);
    }

    function checkRewardWallet() external view returns (address, uint256) {
        uint256 balance = balanceOf(_rewardWallet);
        return (_rewardWallet, balance);
    }

    function checkMarketPlaceWallet() external view returns (address, uint256) {
        uint256 balance = balanceOf(_shoppingCart);
        return (_shoppingCart, balance);
    }

    function checkReferralOwner(address referralUser) public view returns (address) {
        require(referralUser != address(0), 'ERR: zero address');
        return _referralOwner[referralUser];
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal {
        // ignore minting and burning
        if (from == address(0) || to == address(0)) return;

        // ignore add/remove liquidity
        if (from == address(this) || to == address(this)) return;
        if (from == UNISWAP_ROUTER || to == UNISWAP_ROUTER) return;

        address[] memory path = new address[](2);

        if (from == _pair && !_isExcluded[to]) {
            require(_lockedList[to].endTime < uint64(block.timestamp), "ERR: address is locked(buy)");

            require(
                cooldownOf[to] < block.timestamp /* revert message not returned by Uniswap */
            );
            cooldownOf[to] = block.timestamp + (5 minutes);

            path[0] = WETH;
            path[1] = address(this);

            uint256[] memory amounts =
                IUniswapV2Router02(UNISWAP_ROUTER).getAmountsIn(amount, path);

            uint256 balance = balanceOf(to);
            uint256 fromBasis = ((1 ether) * amounts[0]) / amount;
            _basisOf[to] =
                (fromBasis * amount + basisOf(to) * balance) /
                (amount + balance);

            if (fromBasis > _ath) {
                _ath = fromBasis;
                _athTimestamp = block.timestamp;
            }
        } else if (to == _pair && !_isExcluded[from]) {
            require(_lockedList[from].endTime < uint64(block.timestamp), "ERR: address is locked(sales)");
            
            // blacklist Vitalik Buterin
            require(
                from != 0xAb5801a7D398351b8bE11C439e05C5B3259aeC9B /* revert message not returned by Uniswap */
            );
            require(
                cooldownOf[from] < block.timestamp /* revert message not returned by Uniswap */
            );
            cooldownOf[from] = block.timestamp + (5 minutes);            
        }
    }

    function _transfer(address sender, address recipient, uint256 amount) internal {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");

        _beforeTokenTransfer(sender, recipient, amount);

        _transferWithFee(sender, recipient, amount);

        emit Transfer(sender, recipient, amount);
    }

    function _transferWithFee(
        address sender, address recipient, uint256 amount
    ) private returns (bool) {
        uint liquidityBalance = balanceOf(_pair);

        if(sender == _pair && recipient != address(this) && recipient != owner() && recipient != _shoppingCart && recipient != _rewardWallet) {
            require(amount <= liquidityBalance.div(100), "ERR: Exceed the 1% of current liquidity balance");
            _setFees(300, 300, 0);
        }
        else if(recipient == _pair && sender != address(this) && sender != owner() && sender != _shoppingCart && sender != _rewardWallet) {
            require(amount <= liquidityBalance.mul(100).div(10000), "ERR: Exceed the 1% of current liquidity balance");
            address[] memory path = new address[](2);
            path[0] = address(this);
            path[1] = WETH;
            uint[] memory amounts = IUniswapV2Router02(UNISWAP_ROUTER).getAmountsOut(
                amount,
                path
            );

            if (basisOf(sender) <= (1 ether) * amounts[1] / amount) {
                _setFees(300, 300, 0);
            }
            else {
                _setFees(700, 700, 700);
            }
        }
        else {
            _setFees(0, 0, 0);
        }

        if (_isExcluded[sender] && !_isExcluded[recipient]) {
            _transferFromExcluded(sender, recipient, amount);
        } else if (!_isExcluded[sender] && _isExcluded[recipient]) {
            if(recipient == _pair) {
                _transferToExcludedForSale(sender, recipient, amount);
            }
            else {
                _transferToExcluded(sender, recipient, amount);
            }
        } else if (!_isExcluded[sender] && !_isExcluded[recipient]) {
            _transferStandard(sender, recipient, amount);
        } else if (_isExcluded[sender] && _isExcluded[recipient]) {
            _transferBothExcluded(sender, recipient, amount);
        } else {
            _transferStandard(sender, recipient, amount);
        }        
        _setFees(0, 0, 0);
        return true;
    }

    function _transferStandard(address sender, address recipient, uint256 tAmount) private {
        uint256 currentRate =  _getRate();
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee, uint256 tBurn, uint256 tMarket) = _getValues(tAmount);
        uint256 rBurn =  tBurn.mul(currentRate);
        uint256 rMarket = tMarket.mul(currentRate);     
        _standardTransferContent(sender, recipient, rAmount, rTransferAmount);
        if (tMarket > 0) {
            _sendToMarket(tMarket, sender, recipient);
        }
        if (tBurn > 0) {
            _sendToBurn(tBurn, sender);
        }
        _reflectFee(rFee, rBurn, rMarket, tFee, tBurn, tMarket);
        emit Transfer(sender, recipient, tTransferAmount);
    }
    
    function _standardTransferContent(address sender, address recipient, uint256 rAmount, uint256 rTransferAmount) private {
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
    }
    
    function _transferToExcluded(address sender, address recipient, uint256 tAmount) private {
        uint256 currentRate =  _getRate();
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee, uint256 tBurn, uint256 tMarket) = _getValues(tAmount);
        uint256 rBurn =  tBurn.mul(currentRate);
        uint256 rMarket = tMarket.mul(currentRate);
        _excludedFromTransferContent(sender, recipient, tTransferAmount, rAmount, rTransferAmount);        
        if (tMarket > 0) {
            _sendToMarket(tMarket, sender, recipient);
        }
        if (tBurn > 0) {
            _sendToBurn(tBurn, sender);
        }
        _reflectFee(rFee, rBurn, rMarket, tFee, tBurn, tMarket);
        emit Transfer(sender, recipient, tTransferAmount);
    }
    
    function _excludedFromTransferContent(address sender, address recipient, uint256 tTransferAmount, uint256 rAmount, uint256 rTransferAmount) private {
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);    
    }
    
    function _transferToExcludedForSale(address sender, address recipient, uint256 tAmount) private {
        uint256 currentRate =  _getRate();
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee, uint256 tBurn, uint256 tMarket) = _getValuesForSale(tAmount);
        uint256 rBurn =  tBurn.mul(currentRate);
        uint256 rMarket = tMarket.mul(currentRate);
        _excludedFromTransferContentForSale(sender, recipient, tAmount, rAmount, rTransferAmount);        
        if (tMarket > 0) {
            _sendToMarket(tMarket, sender, recipient);
        }
        if (tBurn > 0) {
            _sendToBurn(tBurn, sender);
        }
        _reflectFee(rFee, rBurn, rMarket, tFee, tBurn, tMarket);
        emit Transfer(sender, recipient, tTransferAmount);
    }
    
    function _excludedFromTransferContentForSale(address sender, address recipient, uint256 tAmount, uint256 rAmount, uint256 rTransferAmount) private {
        _rOwned[sender] = _rOwned[sender].sub(rTransferAmount);
        _tOwned[recipient] = _tOwned[recipient].add(tAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rAmount);    
    }
    

    function _transferFromExcluded(address sender, address recipient, uint256 tAmount) private {
        uint256 currentRate =  _getRate();
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee, uint256 tBurn, uint256 tMarket) = _getValues(tAmount);
        uint256 rBurn =  tBurn.mul(currentRate);
        uint256 rMarket = tMarket.mul(currentRate);
        _excludedToTransferContent(sender, recipient, tAmount, rAmount, rTransferAmount);
        if (tMarket > 0) {
            _sendToMarket(tMarket, sender, recipient);
        }
        if (tBurn > 0) {
            _sendToBurn(tBurn, sender);
        }
        _reflectFee(rFee, rBurn, rMarket, tFee, tBurn, tMarket);
        emit Transfer(sender, recipient, tTransferAmount);
    }
    
    function _excludedToTransferContent(address sender, address recipient, uint256 tAmount, uint256 rAmount, uint256 rTransferAmount) private {
        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);  
    }

    function _transferBothExcluded(address sender, address recipient, uint256 tAmount) private {
        uint256 currentRate =  _getRate();
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee, uint256 tBurn, uint256 tMarket) = _getValues(tAmount);
        uint256 rBurn =  tBurn.mul(currentRate);
        uint256 rMarket = tMarket.mul(currentRate);    
        _bothTransferContent(sender, recipient, tAmount, rAmount, tTransferAmount, rTransferAmount);  
        if (tMarket > 0) {
            _sendToMarket(tMarket, sender, recipient);
        }
        if (tBurn > 0) {
            _sendToBurn(tBurn, sender);
        }
        _reflectFee(rFee, rBurn, rMarket, tFee, tBurn, tMarket);
        emit Transfer(sender, recipient, tTransferAmount);
    }
    
    function _bothTransferContent(address sender, address recipient, uint256 tAmount, uint256 rAmount, uint256 tTransferAmount, uint256 rTransferAmount) private {
        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);  
    }


    function _reflectFee(uint256 rFee, uint256 rBurn, uint256 rMarket, uint256 tFee, uint256 tBurn, uint256 tMarket) private {
        _rTotal = _rTotal.sub(rFee).sub(rBurn).sub(rMarket);
        _tFeeTotal = _tFeeTotal.add(tFee);
        _tBurnTotal = _tBurnTotal.add(tBurn);
        _tMarketingFeeTotal = _tMarketingFeeTotal.add(tMarket);
    }

    function _getValues(uint256 tAmount) private view returns (uint256, uint256, uint256, uint256, uint256, uint256, uint256) {
        (uint256 tFee, uint256 tBurn, uint256 tMarket) = _getTBasics(tAmount, _TAX_FEE, _BURN_FEE, _MARKET_FEE);
        uint256 tTransferAmount = getTTransferAmount(tAmount, tFee, tBurn, tMarket);
        uint256 currentRate =  _getRate();
        (uint256 rAmount, uint256 rFee) = _getRBasics(tAmount, tFee, currentRate);
        uint256 rTransferAmount = _getRTransferAmount(rAmount, rFee, tBurn, tMarket, currentRate);
        return (rAmount, rTransferAmount, rFee, tTransferAmount, tFee, tBurn, tMarket);
    }

    function _getValuesForSale(uint256 tAmount) private view returns (uint256, uint256, uint256, uint256, uint256, uint256, uint256) {
        (uint256 tFee, uint256 tBurn, uint256 tMarket) = _getTBasics(tAmount, _TAX_FEE, _BURN_FEE, _MARKET_FEE);
        uint256 tTransferAmountForSale = getTTransferAmountForSale(tAmount, tFee, tBurn, tMarket);
        uint256 currentRate =  _getRate();
        (uint256 rAmount, uint256 rFee) = _getRBasics(tAmount, tFee, currentRate);
        uint256 rTransferAmountForSale = _getRTransferAmountForSale(rAmount, rFee, tBurn, tMarket, currentRate);
        return (rAmount, rTransferAmountForSale, rFee, tTransferAmountForSale, tFee, tBurn, tMarket);
    }
    
    function _getTBasics(uint256 tAmount, uint256 taxFee, uint256 burnFee, uint256 marketFee) private view returns (uint256, uint256, uint256) {
        uint256 tFee = ((tAmount.mul(taxFee)).div(_GRANULARITY)).div(100);
        uint256 tBurn = ((tAmount.mul(burnFee)).div(_GRANULARITY)).div(100);
        uint256 tMarket = ((tAmount.mul(marketFee)).div(_GRANULARITY)).div(100);
        return (tFee, tBurn, tMarket);
    }
    
    function getTTransferAmount(uint256 tAmount, uint256 tFee, uint256 tBurn, uint256 tMarket) private pure returns (uint256) {
        return tAmount.sub(tFee).sub(tBurn).sub(tMarket);
    }
    function getTTransferAmountForSale(uint256 tAmount, uint256 tFee, uint256 tBurn, uint256 tMarket) private pure returns (uint256) {
        return tAmount.add(tFee).add(tBurn).add(tMarket);
    }
    
    function _getRBasics(uint256 tAmount, uint256 tFee, uint256 currentRate) private pure returns (uint256, uint256) {
        uint256 rAmount = tAmount.mul(currentRate);
        uint256 rFee = tFee.mul(currentRate);
        return (rAmount, rFee);
    }
    
    function _getRTransferAmount(uint256 rAmount, uint256 rFee, uint256 tBurn, uint256 tMarket, uint256 currentRate) private pure returns (uint256) {
        uint256 rBurn = tBurn.mul(currentRate);
        uint256 rMarket = tMarket.mul(currentRate);
        uint256 rTransferAmount = rAmount.sub(rFee).sub(rBurn).sub(rMarket);
        return rTransferAmount;
    }

    function _getRTransferAmountForSale(uint256 rAmount, uint256 rFee, uint256 tBurn, uint256 tMarket, uint256 currentRate) private pure returns (uint256) {
        uint256 rBurn = tBurn.mul(currentRate);
        uint256 rMarket = tMarket.mul(currentRate);
        uint256 rTransferAmountForSale = rAmount.add(rFee).add(rBurn).add(rMarket);
        return rTransferAmountForSale;
    }

    function _getRate() private view returns(uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply.div(tSupply);
    }

    function _getCurrentSupply() private view returns(uint256, uint256) {
        uint256 rSupply = _rTotal;
        uint256 tSupply = _tTotal;      
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_rOwned[_excluded[i]] > rSupply || _tOwned[_excluded[i]] > tSupply) return (_rTotal, _tTotal);
            rSupply = rSupply.sub(_rOwned[_excluded[i]]);
            tSupply = tSupply.sub(_tOwned[_excluded[i]]);
        }
        if (rSupply < _rTotal.div(_tTotal)) return (_rTotal, _tTotal);
        return (rSupply, tSupply);
    }

    function _sendToMarket(uint256 tMarket, address sender, address recipient) private {
        uint256 currentRate = _getRate();
        uint256 rMarket = tMarket.mul(currentRate);
        if(sender == _pair && _referralOwner[recipient] != address(0)) {
            _sendToReferralOwner(tMarket, rMarket, _referralOwner[recipient]);
            emit Transfer(sender,  _referralOwner[recipient], tMarket);
        }
        else {
            _rOwned[_shoppingCart] = _rOwned[_shoppingCart].add(rMarket);
            _tOwned[_shoppingCart] = _tOwned[_shoppingCart].add(tMarket);
            emit Transfer(sender, _shoppingCart, tMarket);
        }
    }

    function _sendToBurn(uint256 tBurn, address sender) private {
        uint256 currentRate = _getRate();
        uint256 rBurn = tBurn.mul(currentRate);
        _rOwned[_rewardWallet] = _rOwned[_rewardWallet].add(rBurn);
        _tOwned[_rewardWallet] = _tOwned[_rewardWallet].add(rBurn);
        emit Transfer(sender, _rewardWallet, tBurn);
    }

    function _sendToReferralOwner(uint256 tMarket, uint256 rMarket, address owner) private {
        if(_isExcluded[owner]) {
            _rOwned[owner] = _rOwned[owner].add(rMarket);
            _tOwned[owner] = _tOwned[owner].add(tMarket);
        }
        else {
            _rOwned[owner] = _rOwned[owner].add(rMarket);
        }
    }

    function _setFees(uint256 tFee, uint256 marketFee, uint256 burnFee) private {
        _TAX_FEE = tFee;
        _BURN_FEE = burnFee;
        _MARKET_FEE = marketFee;
    }

    function _lockAddress(address lockAddress, uint64 lockTime) internal {
        require(lockAddress != address(0), "ERR: zero lock address");
        require(lockTime > 0, "ERR: zero lock period");
        require(_lockedList[lockAddress].endTime == 0, "ERR: already locked");
        if (lockAddress != _pair && lockAddress != UNISWAP_ROUTER &&
            lockAddress != _shoppingCart && lockAddress != address(this) &&
            lockAddress != owner()) {
            _lockedList[lockAddress].lockedPeriod = lockTime;
            _lockedList[lockAddress].endTime = uint64(block.timestamp) + lockTime;
        }
    }
}
