// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/console.sol";

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";

import "./BFactory.sol";
import "./IBPair.sol";
import "./BRouter.sol";
import "./BERC20.sol";
import "../agent/IAgentFactory.sol";

contract Bonding is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    address private feeReceiver;

    BFactory public factory;
    BRouter public router;
    uint256 public initialSupply;
    uint256 public fee;
    uint256 public constant K = 3_000_000_000_000;
    uint256 public assetRate;
    uint256 public launchThreshold;
    uint256 public maxTx;
    address public agentFactory;

    struct UserProfile {
        address user;
        address[] tokens;
    }

    struct Token {
        address creator;
        address token;
        address pair;
        address agentToken;
        bool bonding;
        bool trading;
        Data data;
    }

    struct Data {
        address token;
        string tokenName;
        string _name;
        string ticker;
        uint256 supply;
        uint256 price;
        uint256 marketCap;
        uint256 liquidity;
        uint256 volume;
        uint256 volume24H;
        uint256 prevPrice;
        uint256 lastUpdated;
    }

    mapping(address => UserProfile) public userProfile;
    address[] public userProfiles;

    mapping(address => Token) public tokenInfo;
    address[] public tokenInfos;

    event Created(address indexed bondingToken, address indexed pair, uint256 id);
    event AgentLaunched(address indexed token, address agentToken);

    error InvalidAmount();
    error ZeroAddressUnallowed();
    error UserProfileNotCreated();
    error TokenNotBonding();
    error InsufficientBalance();
    error TradingLiveAlready();
    error TokenNotTrading();
    error TokenUnapproved();

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address factory_,
        address router_,
        address feeReceiver_,
        address agentFactory_,
        uint256 fee_,
        uint256 initialSupply_,
        uint256 assetRate_,
        uint256 maxTx_,
        uint256 launchThreshold_
    ) external initializer {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();

        if (
            factory_ == address(0) || router_ == address(0) || feeReceiver_ == address(0) || agentFactory_ == address(0)
        ) revert ZeroAddressUnallowed();

        factory = BFactory(factory_);
        router = BRouter(router_);
        feeReceiver = feeReceiver_;
        fee = fee_;
        initialSupply = initialSupply_;
        assetRate = assetRate_;
        maxTx = maxTx_;
        agentFactory = agentFactory_;
        launchThreshold = launchThreshold_;
    }

    function _createUserProfile(address _user) internal returns (bool) {
        address[] memory _tokens;

        UserProfile memory _profile = UserProfile({user: _user, tokens: _tokens});

        userProfile[_user] = _profile;

        userProfiles.push(_user);

        return true;
    }

    function _checkIfUserProfileExists(address _user) internal view returns (bool) {
        return userProfile[_user].user == _user;
    }

    function _approval(address _spender, address _token, uint256 amount) internal returns (bool) {
        IERC20(_token).forceApprove(_spender, amount);

        return true;
    }

    function setInitialSupply(uint256 newInitialSupply) public onlyOwner {
        if (newInitialSupply == 0) revert InvalidAmount();
        initialSupply = newInitialSupply;
    }

    function setLaunchThreshold(uint256 newLaunchThreshold) public onlyOwner {
        launchThreshold = newLaunchThreshold;
    }

    function setFeeAmount(uint256 newFee) public onlyOwner {
        fee = newFee;
    }

    function setFeeReceiver(address newFeeReceiver) public onlyOwner {
        if (newFeeReceiver == address(0)) revert ZeroAddressUnallowed();
        feeReceiver = newFeeReceiver;
    }

    function setMaxTxAmount(uint256 newMaxTxAmount) public onlyOwner {
        if (newMaxTxAmount == 0) revert InvalidAmount();
        maxTx = newMaxTxAmount;
    }

    function setAssetRate(uint256 newAssetRate) public onlyOwner {
        if (newAssetRate == 0) revert InvalidAmount();
        assetRate = newAssetRate;
    }

    function getUserTokens(address user) public view returns (address[] memory) {
        if (!_checkIfUserProfileExists(user)) revert UserProfileNotCreated();
        return userProfile[user].tokens;
    }

    function createAgent(string memory _name, string memory _ticker, uint256 purchaseAmount)
        external
        nonReentrant
        returns (address, address, uint256)
    {
        if (purchaseAmount < fee) revert InvalidAmount();
        address assetToken = router.assetToken();
        if (IERC20(assetToken).balanceOf(msg.sender) < purchaseAmount) revert InsufficientBalance();
        uint256 initialPurchase = purchaseAmount - fee;
        IERC20(assetToken).safeTransferFrom(msg.sender, feeReceiver, fee);
        IERC20(assetToken).safeTransferFrom(msg.sender, address(this), initialPurchase);

        BERC20 bondingToken = new BERC20(string.concat("den fun ", _name), _ticker, initialSupply, maxTx);
        uint256 supply = BERC20(bondingToken).totalSupply();

        address _pair = factory.createPair(address(bondingToken), assetToken);

        if (!_approval(address(router), address(bondingToken), supply)) revert TokenUnapproved();

        uint256 liquidity = computeInitialLiquidity(supply);
        router.addInitialLiquidity(address(bondingToken), supply, liquidity);

        _setupTokenData(address(bondingToken), _pair, _name, _ticker, supply, liquidity);
        _addTokenToUserProfile(msg.sender, address(bondingToken));

        uint256 numTokensCreated = tokenInfos.length;

        emit Created(address(bondingToken), _pair, numTokensCreated);

        // execute initial purchase
        if (initialPurchase != 0) {
            IERC20(assetToken).forceApprove(address(router), initialPurchase);
            router.buy(initialPurchase, address(bondingToken), address(this));
            bondingToken.transfer(msg.sender, bondingToken.balanceOf(address(this)));
        }

        return (address(bondingToken), _pair, numTokensCreated);
    }

    function sellBonding(uint256 amountIn, address bondingToken) external nonReentrant returns (bool) {
        Token storage token = tokenInfo[bondingToken];
        if (!token.bonding) revert TokenNotBonding();

        IBPair pair = IBPair(token.pair);

        (uint256 reserveA, uint256 reserveB) = pair.getReserves();

        (uint256 amount0In, uint256 amount1Out) = router.sell(amountIn, bondingToken, msg.sender);

        uint256 newReserveA = reserveA + amount0In;
        uint256 newReserveB = reserveB - amount1Out;

        Data storage data = token.data;
        bool isNewDay = (block.timestamp - token.data.lastUpdated) > 86400;

        uint256 price = newReserveA / newReserveB;
        data.price = price;
        data.marketCap = (data.supply * newReserveB) / newReserveA;
        data.liquidity = newReserveB * 2;
        data.volume += amount1Out;
        data.volume24H = isNewDay ? amount1Out : data.volume24H + amount1Out;
        data.prevPrice = isNewDay ? data.price : data.prevPrice;

        if (isNewDay) {
            token.data.lastUpdated = block.timestamp;
        }

        return true;
    }

    function buyBonding(uint256 amountIn, address bondingToken) external payable nonReentrant returns (bool) {
        Token storage token = tokenInfo[bondingToken];
        if (!token.bonding) revert TokenNotBonding();

        IBPair pair = IBPair(token.pair);

        (uint256 reserveA, uint256 reserveB) = pair.getReserves();

        (uint256 amount1In, uint256 amount0Out) = router.buy(amountIn, bondingToken, msg.sender);

        uint256 newReserveA = reserveA - amount0Out;
        uint256 newReserveB = reserveB + amount1In;

        Data storage data = token.data;
        bool isNewDay = (block.timestamp - data.lastUpdated) > 86400;

        uint256 price = newReserveA / newReserveB;

        data.price = price;

        data.marketCap = data.supply * newReserveB / newReserveA;
        data.liquidity = newReserveB * 2;
        data.volume += amount1In;
        data.volume24H = isNewDay ? amount1In : data.volume24H + amount1In;
        data.prevPrice = isNewDay ? data.price : data.prevPrice;

        if (isNewDay) {
            token.data.lastUpdated = block.timestamp;
        }

        if (newReserveA <= launchThreshold && token.bonding) {
            _openTrading(bondingToken);
        }

        return true;
    }

    function _openTrading(address bondingToken) private {
        BERC20 bondingToken_ = BERC20(bondingToken);

        Token storage _token = tokenInfo[bondingToken];

        if (!_token.bonding && _token.trading) revert TradingLiveAlready();

        _token.bonding = false;
        _token.trading = true;

        address pairAddress = factory.getPair(bondingToken, router.assetToken());

        IBPair pair = IBPair(pairAddress);

        uint256 assetTokenBalance = pair.assetBalance();
        uint256 bondingTokenBalance = pair.balance();

        router.launch(bondingToken);

        IERC20(router.assetToken()).forceApprove(agentFactory, assetTokenBalance);
        uint256 agentId = IAgentFactory(agentFactory).initFromCurve(
            string.concat(_token.data._name, " by Den"), _token.data.ticker, _token.creator, assetTokenBalance
        );

        address agentToken = IAgentFactory(agentFactory).executeCurveProposal(
            agentId,
            _token.data.supply / (10 ** bondingToken_.decimals()),
            bondingTokenBalance / (10 ** bondingToken_.decimals()),
            pairAddress
        );

        _token.agentToken = agentToken;

        router.approval(pairAddress, agentToken, address(this), IERC20(agentToken).balanceOf(pairAddress));

        bondingToken_.burnFrom(pairAddress, bondingTokenBalance);

        emit AgentLaunched(bondingToken, agentToken);
    }

    function exchangeForAgentTokens(address bondingToken, address[] memory accounts) public nonReentrant {
        if (accounts.length == 0) revert InvalidAmount();
        Token memory info = tokenInfo[bondingToken];
        if (!info.trading) revert TokenNotTrading();

        BERC20 token = BERC20(bondingToken);
        IERC20 agentToken = IERC20(info.agentToken);
        address pairAddress = factory.getPair(bondingToken, router.assetToken());
        for (uint256 i = 0; i < accounts.length; i++) {
            address acc = accounts[i];
            uint256 balance = token.balanceOf(acc);
            if (balance > 0) {
                token.burnFrom(acc, balance);
                agentToken.transferFrom(pairAddress, acc, balance);
            }
        }
    }

    function computeInitialLiquidity(uint256 supply) public view returns (uint256) {
        uint256 k = ((K * 10000) / assetRate);
        return (((k * 10000 ether) / supply) * 1 ether) / 10000;
    }

    function _setupTokenData(
        address bondingToken,
        address _pair,
        string memory _name,
        string memory _ticker,
        uint256 supply,
        uint256 liquidity
    ) private {
        Data memory _data = Data({
            token: bondingToken,
            tokenName: string.concat("den fun ", _name),
            _name: _name,
            ticker: _ticker,
            supply: supply,
            price: supply / liquidity,
            marketCap: liquidity,
            liquidity: liquidity * 2,
            volume: 0,
            volume24H: 0,
            prevPrice: supply / liquidity,
            lastUpdated: block.timestamp
        });

        tokenInfo[address(bondingToken)] = Token({
            creator: msg.sender,
            token: bondingToken,
            pair: _pair,
            agentToken: address(0),
            bonding: true,
            trading: false,
            data: _data
        });

        tokenInfos.push(address(bondingToken));
    }

    function _addTokenToUserProfile(address user, address bondingToken) private {
        if (user == address(0) || bondingToken == address(0)) revert ZeroAddressUnallowed();
        bool exists = _checkIfUserProfileExists(user);
        if (exists) {
            UserProfile storage _userProfile = userProfile[user];
            _userProfile.tokens.push(address(bondingToken));
        } else {
            bool created = _createUserProfile(user);
            if (created) {
                UserProfile storage _userProfile = userProfile[user];
                _userProfile.tokens.push(address(bondingToken));
            }
        }
    }
}
