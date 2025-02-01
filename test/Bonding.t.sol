// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import "src/bonding-curve/Bonding.sol";
import "src/bonding-curve/BFactory.sol";
import "src/bonding-curve/BRouter.sol";
import "src/agent/AgentFactory.sol";

import "src/pool/IUniswapV2Router02.sol";
import "src/pool/IUniswapV2Pair.sol";

import "src/agent/AgentNFT.sol";
import "src/agent/AgentToken.sol";
import "src/agent/AgentVeToken.sol";

import "test/MockDen.sol";

contract BondingTest is Test {
    Bonding public bondingImplementation;
    BFactory public factoryImplementation;
    BRouter public routerImplementation;
    AgentFactory public agentFactoryImplementation;
    MockDen public denToken;

    AgentToken public agentTokenImplementation;
    AgentNFT public agentNFTImplementation;
    AgentVeToken public agentVeTokenImplementation;

    ProxyAdmin public proxyAdmin;

    TransparentUpgradeableProxy public factoryProxy;
    TransparentUpgradeableProxy public routerProxy;
    TransparentUpgradeableProxy public bondingProxy;
    TransparentUpgradeableProxy public agentFactoryProxy;
    TransparentUpgradeableProxy public agentNFTProxy;

    Bonding public bondingInstance;
    BFactory public factoryInstance;
    BRouter public routerInstance;
    AgentFactory public agentFactoryInstance;
    AgentNFT public agentNFTInstance;

    // balancer contracts
    IUniswapV2Router02 public uniswapRouter;

    address public feeReceiver;
    address public taxVault;
    address public creator;

    address public user1;
    address public user2;

    uint256 public startingSupply;
    uint256 public expectedStartingAssetReserve;
    uint256 public k; // constant product

    function setUp() public {
        feeReceiver = vm.addr(10);
        taxVault = vm.addr(11);
        creator = vm.addr(12);
        user1 = vm.addr(1);
        user2 = vm.addr(2);

        startingSupply = 1000000000;

        denToken = new MockDen();

        // deploy contract implementations
        factoryImplementation = new BFactory();
        routerImplementation = new BRouter();
        bondingImplementation = new Bonding();
        agentFactoryImplementation = new AgentFactory();
        agentTokenImplementation = new AgentToken();
        agentNFTImplementation = new AgentNFT();
        agentVeTokenImplementation = new AgentVeToken();

        // set balancer contracts
        uniswapRouter = IUniswapV2Router02(0x406846114B2A9b65a8A2Ab702C2C57d27784dBA2);

        // deploy proxies
        factoryProxy = new TransparentUpgradeableProxy(address(factoryImplementation), address(this), "");
        routerProxy = new TransparentUpgradeableProxy(address(routerImplementation), address(this), "");
        bondingProxy = new TransparentUpgradeableProxy(address(bondingImplementation), address(this), "");
        agentFactoryProxy = new TransparentUpgradeableProxy(address(agentFactoryImplementation), address(this), "");
        agentNFTProxy = new TransparentUpgradeableProxy(address(agentNFTImplementation), address(this), "");

        // set instances
        factoryInstance = BFactory(address(factoryProxy));
        routerInstance = BRouter(address(routerProxy));
        bondingInstance = Bonding(address(bondingProxy));
        agentFactoryInstance = AgentFactory(address(agentFactoryProxy));
        agentNFTInstance = AgentNFT(address(agentNFTProxy));

        // initialize
        factoryInstance.initialize(taxVault, address(routerInstance), 1, 1); // 1% tax on buy/sell
        routerInstance.initialize(address(factoryInstance), address(denToken));
        bondingInstance.initialize(
            address(factoryInstance),
            address(routerInstance),
            feeReceiver,
            address(agentFactoryInstance),
            100e18,
            startingSupply,
            240,
            100,
            200000000e18
        );
        agentFactoryInstance.initialize(
            address(agentTokenImplementation),
            address(agentVeTokenImplementation),
            address(denToken),
            address(agentNFTInstance),
            2000e18,
            1
        );
        agentNFTInstance.initialize();
        agentFactoryInstance.setTokenAdmin(address(this));
        agentFactoryInstance.setTokenSupplyParams(1000000000, 1000000000, 0, address(0));
        agentFactoryInstance.setTokenTaxParams(100, 100, 1, taxVault);
        agentFactoryInstance.setUniswapRouter(address(uniswapRouter));
        agentFactoryInstance.setStakingPeriod(1 days);

        // assign roles
        factoryInstance.grantRole(factoryInstance.CREATOR_ROLE(), address(bondingInstance));
        routerInstance.grantRole(routerInstance.EXECUTOR_ROLE(), address(bondingInstance));
        agentFactoryInstance.grantRole(agentFactoryInstance.BONDING_ROLE(), address(bondingInstance));
        agentNFTInstance.grantRole(agentNFTImplementation.MINTER_ROLE(), address(agentFactoryInstance));

        // mint creator, user1, and user2 500 den tokens
        denToken.mint(creator, 4000000e18);
        denToken.mint(user1, 500e18);
        denToken.mint(user2, 500e18);
        assertEq(denToken.balanceOf(creator), 4000000e18);
        assertEq(denToken.balanceOf(user1), 500e18);
        assertEq(denToken.balanceOf(user2), 500e18);

        // set expected asset pool reserve and constant product
        expectedStartingAssetReserve =
            (bondingInstance.K() * 10000 / bondingInstance.assetRate()) * 10000e18 / startingSupply / 10000;
        k = expectedStartingAssetReserve * startingSupply * 1e18;
        console.logUint(k);
    }

    function testCreateToken() public returns (address, address) {
        vm.startPrank(creator);
        denToken.approve(address(bondingInstance), 100e18);

        // create token with no additional purchase
        (address bondingToken, address pair, uint256 id) = bondingInstance.createAgent("test", "test", 100e18);

        uint256 startingLiquidity = bondingInstance.computeInitialLiquidity(startingSupply * 1e18);

        // get pair info
        BPair bPair = BPair(pair);
        BPair.Pool memory pool = bPair.getPoolInfo();

        // check mappings
        address[] memory tokens = bondingInstance.getUserTokens(creator);
        assertEq(tokens[0], bondingToken);

        (
            address tokenCreator,
            address _token,
            address _pair,
            address agentToken,
            bool bonding,
            bool trading,
            Bonding.Data memory data
        ) = bondingInstance.tokenInfo(bondingToken);

        assertEq(tokenCreator, creator);
        assertEq(_token, bondingToken);
        assertEq(_pair, pair);
        assertEq(agentToken, address(0));
        assertEq(bonding, true);
        assertEq(trading, false);

        assertEq(data.token, bondingToken);
        assertEq(data.tokenName, "den fun test");
        assertEq(data._name, "test");
        assertEq(data.ticker, "test");
        assertEq(data.supply, startingSupply * 1e18);
        assertEq(data.price, startingSupply * 1e18 / startingLiquidity);
        assertEq(data.marketCap, startingLiquidity);
        assertEq(data.volume, 0);
        assertEq(data.volume24H, 0);
        assertEq(data.prevPrice, startingSupply * 1e18 / startingLiquidity);
        assertEq(data.lastUpdated, block.timestamp);

        return (bondingToken, pair);
    }

    function testCreateWithPurchase() public {
        vm.startPrank(creator);
        denToken.approve(address(bondingInstance), 4000000e18);

        // create token with additional purchase of 400 den
        (address bondingToken, address pair, uint256 id) = bondingInstance.createAgent("test", "test", 1700100e18);
        uint256 startingLiquidity = bondingInstance.computeInitialLiquidity(startingSupply * 1e18);
        uint256 buyTaxFee = 1700000e18 * factoryInstance.buyTax() / 100;
        uint256 buyAmountAfterFee = 1700000e18 - buyTaxFee;

        // check creator, tax vault, and pool den balance after
        // assertEq(denToken.balanceOf(creator), 0);
        assertEq(denToken.balanceOf(pair), buyAmountAfterFee);
        assertEq(denToken.balanceOf(taxVault), buyTaxFee);

        // get pair info
        BPair bPair = BPair(pair);
        BPair.Pool memory pool = bPair.getPoolInfo();

        // check mappings
        address[] memory tokens = bondingInstance.getUserTokens(creator);
        assertEq(tokens[0], bondingToken);

        // calculate expected pool reserves and check that creator received bonding tokens
        uint256 newReserveB = expectedStartingAssetReserve + buyAmountAfterFee;
        uint256 newReserveA = k / newReserveB;
        uint256 amountOut = startingSupply * 1e18 - newReserveA;
        assertEq(BERC20(bondingToken).balanceOf(creator), amountOut);
        console.log(BERC20(bondingToken).balanceOf(creator));
        assertEq(pool.k, k);
        assertEq(pool.reserve0, newReserveA);
        assertEq(pool.reserve1, newReserveB);

        (,,,, bool bonding, bool trading,) = bondingInstance.tokenInfo(bondingToken);
        console.log(bonding, trading);
    }

    function testBuy() public returns (address, address) {
        // create bonding token
        (address bondingToken, address pair) = testCreateToken();

        // retrieve current pool reserves
        BPair bPair = BPair(pair);
        BPair.Pool memory currentPoolInfo = bPair.getPoolInfo();

        // user1 buys 300 den worth of bonding tokens
        vm.startPrank(user1);
        denToken.approve(address(routerInstance), 300e18);
        bondingInstance.buyBonding(300e18, bondingToken);

        uint256 taxAmount = 300e18 * factoryInstance.buyTax() / 100;
        uint256 buyAmountAfterTax = 300e18 - taxAmount;

        uint256 newReserveB = currentPoolInfo.reserve1 + buyAmountAfterTax;
        uint256 newReserveA = k / newReserveB;
        uint256 amountOut = currentPoolInfo.reserve0 - newReserveA;

        BPair.Pool memory newPoolInfo = bPair.getPoolInfo();
        assertEq(newPoolInfo.reserve0, newReserveA);
        assertEq(newPoolInfo.reserve1, newReserveB);
        assertEq(newPoolInfo.lastUpdated, block.timestamp);

        assertEq(denToken.balanceOf(user1), 200e18);
        assertEq(denToken.balanceOf(pair), buyAmountAfterTax);
        assertEq(denToken.balanceOf(taxVault), taxAmount);
        assertEq(BERC20(bondingToken).balanceOf(user1), amountOut);
        assertEq(BERC20(bondingToken).balanceOf(pair), currentPoolInfo.reserve0 - amountOut);

        // check token data updated
        (,,,,,, Bonding.Data memory data) = bondingInstance.tokenInfo(bondingToken);

        assertEq(data.price, newReserveA / newReserveB);
        assertEq(data.marketCap, startingSupply * 1e18 * newReserveB / newReserveA);
        assertEq(data.liquidity, newReserveB * 2);
        assertEq(data.volume, buyAmountAfterTax);
        assertEq(data.volume24H, buyAmountAfterTax);
        assertEq(data.prevPrice, currentPoolInfo.reserve0 / currentPoolInfo.reserve1);

        return (bondingToken, pair);
    }

    function testSell() public {
        // create bonding token and purchase tokens
        (address bondingToken, address pair) = testBuy();

        // retrieve current pool reserves and token data
        BPair.Pool memory currentPoolInfo = BPair(pair).getPoolInfo();
        (,,,,,, Bonding.Data memory currentData) = bondingInstance.tokenInfo(bondingToken);

        // retrieve user1 and vault den balance before sale
        uint256 user1denBalanceBeforeSale = denToken.balanceOf(user1);
        uint256 vaultdenBalanceBeforeSale = denToken.balanceOf(taxVault);
        uint256 pairdenBalanceBeforeSale = denToken.balanceOf(pair);

        // user1 sells all bonding tokens owned
        uint256 sellAmount = BERC20(bondingToken).balanceOf(user1);
        vm.startPrank(user1);
        BERC20(bondingToken).approve(address(routerInstance), sellAmount);
        bondingInstance.sellBonding(sellAmount, bondingToken);

        uint256 newReserveA = currentPoolInfo.reserve0 + sellAmount;
        uint256 newReserveB = k / newReserveA;
        uint256 amountOut = currentPoolInfo.reserve1 - newReserveB;

        uint256 taxAmount = amountOut * factoryInstance.sellTax() / 100;

        BPair.Pool memory newPoolInfo = BPair(pair).getPoolInfo();
        assertEq(newPoolInfo.reserve0, newReserveA);
        assertEq(newPoolInfo.reserve1, newReserveB);
        assertEq(newPoolInfo.lastUpdated, block.timestamp);

        assertEq(denToken.balanceOf(user1), user1denBalanceBeforeSale + amountOut - taxAmount);
        assertEq(denToken.balanceOf(pair), pairdenBalanceBeforeSale - amountOut);
        assertEq(denToken.balanceOf(taxVault), vaultdenBalanceBeforeSale + taxAmount);
        assertEq(BERC20(bondingToken).balanceOf(user1), 0);
        assertEq(BERC20(bondingToken).balanceOf(pair), currentPoolInfo.reserve0 + sellAmount);

        // check token data updated
        (,,,,,, Bonding.Data memory data) = bondingInstance.tokenInfo(bondingToken);

        assertEq(data.price, newReserveA / newReserveB);
        assertEq(data.marketCap, startingSupply * 1e18 * newReserveB / newReserveA);
        assertEq(data.liquidity, newReserveB * 2);
        assertEq(data.volume, currentData.volume + amountOut);
        assertEq(data.volume24H, currentData.volume24H + amountOut);
    }

    function testLaunch() public returns (address, address) {
        // create token and pair
        (address bondingToken, address pair_) = testCreateToken();

        uint256 purchaseAmount =
            (k / bondingInstance.launchThreshold() - BPair(pair_).getPoolInfo().reserve1) * 110 / 100; // additional to cover tax

        vm.startPrank(user1);
        denToken.mint(user1, purchaseAmount);
        denToken.approve(address(routerInstance), purchaseAmount);
        bondingInstance.buyBonding(purchaseAmount, bondingToken);

        // retrieve newly created agent token and perform checks
        address agentToken = agentFactoryInstance.deployedAgentTokens(0);

        // check bonding and trading states
        (,,, address agentToken_, bool bonding, bool trading,) = bondingInstance.tokenInfo(bondingToken);
        assertEq(bonding, false);
        assertEq(trading, true);
        assertEq(agentToken_, agentToken);
        assertEq(agentNFTInstance.ownerOf(1), creator);

        // get agentInfo and verify LP setup
        AgentNFT.AgentInfo memory agentInfo = agentNFTInstance.getAgentInfo(1);
        assertEq(agentInfo.agentToken, agentToken);
        assertEq(agentInfo.creator, creator);

        // confirm that liquidity was added
        IUniswapV2Pair uniPair = IUniswapV2Pair(agentInfo.lp);
        uint256 lpSupply = uniPair.totalSupply();
        (uint256 reserve0, uint256 reserve1,) = uniPair.getReserves();
        assertNotEq(reserve0, 0);
        assertNotEq(reserve1, 0);
        assertNotEq(lpSupply, 0);

        // verify LP staking
        AgentVeToken veToken = AgentVeToken(agentFactoryInstance.deployedVeTokens(0));
        assertApproxEqAbs(lpSupply, IERC20(agentInfo.lp).balanceOf(address(veToken)), 1e18);
        assertApproxEqAbs(lpSupply, veToken.initialLock(), 1e18);
        assertEq(veToken.unlockAt(), block.timestamp + agentFactoryInstance.stakingPeriod());
        assertApproxEqAbs(veToken.balanceOf(creator), lpSupply, 1e18);

        return (agentToken, bondingToken);
    }

    // test redemption
    function testRedemption() public {
        // launch agent token
        testLaunch();

        // retrieve bondingToken
        address[] memory tokens = bondingInstance.getUserTokens(creator);
        address bondingToken = tokens[0];
        // retrieve newly created agent token
        address agentToken = agentFactoryInstance.deployedAgentTokens(0);

        uint256 creatorBondingBalance = BERC20(bondingToken).balanceOf(user1);

        address[] memory a = new address[](1);
        a[0] = user1;

        vm.startPrank(user1);
        AgentNFT.AgentInfo memory agentInfo = agentNFTInstance.getAgentInfo(1);

        BERC20(bondingToken).approve(address(bondingInstance), creatorBondingBalance);
        uint256 approvalAmount =
            AgentToken(payable(agentToken)).allowance(AgentToken(payable(agentToken)).vault(), address(bondingInstance));
        console.log(approvalAmount);
        bondingInstance.exchangeForAgentTokens(bondingToken, a);

        uint256 newBondingBalance = BERC20(bondingToken).balanceOf(user1);
        uint256 agentTokenBalance = AgentToken(payable(agentToken)).balanceOf(user1);

        assertEq(creatorBondingBalance, agentTokenBalance);
        assertEq(newBondingBalance, 0);

        console.log(creatorBondingBalance);
        console.log(agentTokenBalance);
    }

    function testRevertBondingContract() public {
        // create token and pair
        (address token, address pair) = testCreateToken();

        vm.startPrank(user1);
        vm.expectRevert();
        bondingInstance.setInitialSupply(startingSupply * 1e18);

        vm.expectRevert();
        bondingInstance.setLaunchThreshold(1);

        vm.expectRevert();
        bondingInstance.setFeeAmount(1);

        vm.expectRevert();
        bondingInstance.setFeeReceiver(user1);

        vm.expectRevert();
        bondingInstance.setMaxTxAmount(1);

        vm.expectRevert();
        bondingInstance.setAssetRate(1);

        BERC20 bondingToken = BERC20(token);

        vm.expectRevert();
        bondingToken.updateMaxTx(1);

        vm.expectRevert();
        bondingToken.excludeFromMaxTx(user1);

        vm.expectRevert();
        bondingToken.burnFrom(user2, 1);
    }

    function testRevertTokenContract() public {
        // create token and pair
        (address token, address pair) = testCreateToken();

        BERC20 bondingToken = BERC20(token);

        vm.expectRevert();
        bondingToken.updateMaxTx(1);

        vm.expectRevert();
        bondingToken.excludeFromMaxTx(user1);

        vm.expectRevert();
        bondingToken.burnFrom(user2, 1);
    }

    function testRevertPairContract() public {
        // create token and pair
        (address token, address pair_) = testCreateToken();

        vm.startPrank(user1);
        BPair pair = BPair(pair_);
        vm.expectRevert();
        pair.mint(1, 1);

        vm.expectRevert();
        pair.swap(1, 1, 1, 1);

        vm.expectRevert();
        pair.approval(user1, token, 1);

        vm.expectRevert();
        pair.transferAsset(user1, 1);

        vm.expectRevert();
        pair.transferTo(user1, 1);
    }

    function testRevertFactoryContract() public {
        vm.startPrank(user1);
        vm.expectRevert();
        factoryInstance.createPair(vm.addr(5), vm.addr(6));

        vm.expectRevert();
        factoryInstance.setTaxVault(vm.addr(5));

        vm.expectRevert();
        factoryInstance.setSellTax(1);

        vm.expectRevert();
        factoryInstance.setBuyTax(1);

        vm.expectRevert();
        factoryInstance.setRouter(vm.addr(5));
    }

    function testRevertRouterContract() public {
        vm.startPrank(user1);

        vm.expectRevert();
        routerInstance.addInitialLiquidity(vm.addr(5), 1, 1);

        vm.expectRevert();
        routerInstance.sell(1, vm.addr(5), vm.addr(6));

        vm.expectRevert();
        routerInstance.buy(1, vm.addr(5), vm.addr(6));

        vm.expectRevert();
        routerInstance.launch(vm.addr(5));

        vm.expectRevert();
        routerInstance.approval(vm.addr(5), vm.addr(6), vm.addr(7), 1);
    }

    function testTaxesOnUniswap() public {
        (address agentToken, address bondingToken) = testLaunch();

        vm.startPrank(user1);
        address[] memory accounts = new address[](1);
        accounts[0] = user1;
        bondingInstance.exchangeForAgentTokens(bondingToken, accounts);

        // current taxes are 1%
        uint256 sellAmount = 10000000e18;
        uint256 expectedTaxAmount = sellAmount * 100 / 10000;
        uint256 amountAfterTaxes = sellAmount - expectedTaxAmount;

        uint256 user1AgentTokenBalanceBeforeSale = IERC20(agentToken).balanceOf(user1);
        uint256 contractTaxBalanceBeforeSale = IERC20(agentToken).balanceOf(agentToken);
        IUniswapV2Pair pair = IUniswapV2Pair(agentNFTInstance.getAgentInfo(1).lp);
        uint112 initialReserve1;
        {
            (, initialReserve1,) = pair.getReserves();
        }

        address[] memory path = new address[](2);
        path[0] = agentToken;
        path[1] = address(denToken);
        IERC20(agentToken).approve(address(uniswapRouter), sellAmount);
        uniswapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            sellAmount, 0, path, user1, block.timestamp + 300
        );

        // get new reserves
        (, uint112 newReserve1,) = pair.getReserves();

        assertEq(IERC20(agentToken).balanceOf(agentToken), contractTaxBalanceBeforeSale + expectedTaxAmount);
        assertEq(newReserve1, initialReserve1 + amountAfterTaxes);
        assertEq(IERC20(agentToken).balanceOf(user1), user1AgentTokenBalanceBeforeSale - sellAmount);
    }

    function testSwapTaxes() public {
        (address agentToken, address bondingToken) = testLaunch();

        vm.startPrank(user1);
        address[] memory accounts = new address[](1);
        accounts[0] = user1;
        bondingInstance.exchangeForAgentTokens(bondingToken, accounts);

        // swap threshold is 100k tokens
        // transfer 110k to agent token contract
        IERC20(agentToken).transfer(agentToken, 110000e18);

        uint256 agentTokenTaxBalanceBeforeSwap = IERC20(agentToken).balanceOf(agentToken);
        // sell a small amount to test if tax swap triggers
        address[] memory path = new address[](2);
        path[0] = agentToken;
        path[1] = address(denToken);
        IERC20(agentToken).approve(address(uniswapRouter), 1e18);
        uniswapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(1e18, 0, path, user1, block.timestamp + 300);

        assertApproxEqAbs(IERC20(agentToken).balanceOf(agentToken), agentTokenTaxBalanceBeforeSwap - 110000e18, 10e18);
        assertNotEq(denToken.balanceOf(taxVault), 0);
    }
}
