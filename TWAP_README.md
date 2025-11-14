# TWAP Price Provider Implementation

## Overview

This implementation provides a Time-Weighted Average Price (TWAP) oracle using Uniswap V3 pools, along with integration into the existing swap provider for price validation and slippage protection.

## Components

### 1. UniswapV3TWAPOracle

**Location**: `src/UniswapV3TWAPOracle/UniswapV3TWAPOracle.sol`

A contract that fetches manipulation-resistant TWAP prices from Uniswap V3 pools.

**Key Features**:
- ✅ Fetches TWAP prices for predefined token pairs
- ✅ Supports custom TWAP periods (default: 30 minutes)
- ✅ Automatic decimal normalization (all prices returned in 18 decimals)
- ✅ Built-in validation for pool existence and observation cardinality
- ✅ Direct integration with Uniswap V3 pool observations

**Main Functions**:
```solidity
// Get TWAP price using default period (30 min)
function getPrice(address tokenIn, address tokenOut) external view returns (uint256 price);

// Get TWAP price with custom period
function getPriceWithPeriod(address tokenIn, address tokenOut, uint32 twapPeriod) public view returns (uint256 price);

// Get quote for specific amount
function getQuote(address tokenIn, address tokenOut, uint256 amountIn) external view returns (uint256 amountOut);

// Check if pair is supported
function isPairSupported(address token0, address token1) external view returns (bool supported);
```

**Example Usage**:
```solidity
// Deploy oracle
UniswapV3TWAPOracle oracle = new UniswapV3TWAPOracle(
    UNISWAP_V3_FACTORY,
    1800, // 30 minutes
    tokenPairs
);

// Get WETH price in USDC
uint256 price = oracle.getPrice(WETH, USDC);
// Returns: ~3100 * 1e18 (normalized to 18 decimals)

// Get quote for 10 WETH
uint256 quote = oracle.getQuote(WETH, USDC, 10 ether);
// Returns: ~31000 * 1e18
```

### 2. UniswapV3ExchangeProviderWithTWAP

**Location**: `src/UniswapV3ExchangeProvider/UniswapV3ExchangeProviderWithTWAP.sol`

An extended version of the swap provider that integrates TWAP oracle for price validation.

**Key Features**:
- ✅ TWAP-based quote retrieval
- ✅ Automatic slippage protection using TWAP prices
- ✅ Price deviation validation
- ✅ Event emissions for price tracking

**Main Functions**:
```solidity
// Get TWAP-based quote
function getTWAPQuote(address tokenIn, address tokenOut, uint256 amountIn) public view returns (uint256 amountOut);

// Swap with automatic TWAP validation
function swapInputWithTWAPValidation(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 minAmountOut
) external returns (uint256 amountOut);

// Validate price against TWAP
function validatePriceAgainstTWAP(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 expectedAmountOut
) external view returns (bool valid, uint256 deviation);
```

**Example Usage**:
```solidity
// Deploy integrated provider
UniswapV3ExchangeProviderWithTWAP provider = new UniswapV3ExchangeProviderWithTWAP(
    swapRouter,
    poolFee,
    singlehopPairs,
    multihopPairs,
    slippageTolerance,
    address(oracle),
    200 // 2% max price deviation
);

// Execute swap with TWAP protection
uint256 amountOut = provider.swapInputWithTWAPValidation(
    WETH,
    USDC,
    1 ether,
    0 // Auto-calculate minimum using TWAP
);
```

### 3. Configuration

**Location**: `src/UniswapV3TWAPOracle/UniswapV3TWAPOracleConfig.sol`

Centralized configuration for TWAP oracle deployment.

**Supported Pairs** (Ethereum Mainnet):
- WETH/USDC (0.3% fee)
- WBTC/WETH (0.3% fee)
- USDC/USDT (0.05% fee)
- DAI/USDC (0.05% fee)
- LINK/WETH (0.3% fee)
- LINK/USDC (0.3% fee)

## How TWAP Works

### What is TWAP?

TWAP (Time-Weighted Average Price) is a pricing mechanism that calculates the average price of an asset over a specific time period. This makes it highly resistant to price manipulation compared to spot prices.

### Why Use TWAP?

1. **Manipulation Resistance**: Short-term price spikes don't significantly affect TWAP
2. **Fair Pricing**: Reflects actual trading activity over time
3. **DeFi Safety**: Ideal for lending protocols, liquidations, and collateral valuation
4. **No External Dependencies**: Uses on-chain Uniswap V3 data only

### Implementation Details

Uniswap V3 stores cumulative tick data in each pool:
```solidity
// Query historical tick data
uint32[] memory secondsAgos = [period, 0]; // e.g., [1800, 0] for 30-minute TWAP
(int56[] memory tickCumulatives, ) = pool.observe(secondsAgos);

// Calculate time-weighted average tick
int56 tickDelta = tickCumulatives[1] - tickCumulatives[0];
int24 avgTick = int24(tickDelta / int56(uint56(period)));

// Convert tick to price: price = 1.0001^tick
uint160 sqrtPriceX96 = getSqrtRatioAtTick(avgTick);
price = calculatePriceFromSqrtRatio(sqrtPriceX96);
```

### Decimal Normalization

The oracle automatically handles different token decimals:
- WETH: 18 decimals
- USDC: 6 decimals
- WBTC: 8 decimals

All prices are normalized to 18 decimals for consistency:
```solidity
// Example: WETH/USDC price
uint256 price = oracle.getPrice(WETH, USDC);
// Returns: 3100000000000000000000 (3100 * 1e18)
// Meaning: 1 WETH = 3100 USDC
```

## Testing

### Run All TWAP Tests

```bash
# Test TWAP Oracle
forge test --match-contract UniswapV3TWAPOracleTest -vv

# Test Integrated Provider
forge test --match-contract UniswapV3ExchangeProviderWithTWAPTest -vv
```

### Test Results

All tests passing:
- ✅ Price fetching for major pairs (WETH/USDC, WBTC/WETH, LINK/USDC)
- ✅ Custom TWAP periods
- ✅ Quote calculations
- ✅ Pair support validation
- ✅ Error handling (invalid pairs, invalid periods)
- ✅ Stablecoin pair accuracy (USDC/USDT ≈ 1.0)
- ✅ TWAP-based swap validation
- ✅ Price deviation checks
- ✅ Multihop integration

### Example Test Output

```
testGetPriceWETHUSDC:
  WETH/USDC TWAP Price: 3101374473000000000000
  ✅ Price within expected range ($1000-$10000)

testStablecoinPairs:
  USDC/USDT Price: 1000400060004000100
  ✅ Close to 1:1 peg (0.04% deviation)

testSwapWithTWAPValidation:
  TWAP Quote: 3101 USDC per WETH
  Actual received: 3111 USDC
  ✅ Within 2% deviation tolerance
```

## Deployment

### 1. Deploy TWAP Oracle

```bash
forge script src/UniswapV3TWAPOracle/UniswapV3TWAPOracle.s.sol:DeployUniswapV3TWAPOracle --rpc-url $ETH_MAINNET_RPC --broadcast
```

### 2. Deploy Integrated Swap Provider (Optional)

If you want TWAP-validated swaps:

```solidity
UniswapV3ExchangeProviderWithTWAP provider = new UniswapV3ExchangeProviderWithTWAP(
    ISwapRouter(Config.SWAP_ROUTER),
    Config.POOL_FEE,
    Config.getDefaultSinglehopPairs(),
    Config.getDefaultMultihopPairs(),
    Config.SLIPPAGE_TOLERANCE,
    address(oracle), // Your deployed oracle
    200 // 2% max price deviation
);
```

### 3. Integrate with Existing Swap Provider

You can use the TWAP oracle standalone with your existing provider:

```solidity
// Get TWAP quote before swap
uint256 twapQuote = oracle.getQuote(tokenIn, tokenOut, amountIn);

// Calculate minimum with slippage
uint256 minAmount = (twapQuote * 98) / 100; // 2% slippage

// Execute swap with TWAP-based minimum
uint256 amountOut = swapProvider.swapInput(
    tokenIn,
    tokenOut,
    amountIn,
    minAmount
);

// Validate actual price vs TWAP
uint256 actualPrice = (amountOut * 1e18) / amountIn;
uint256 twapPrice = (twapQuote * 1e18) / amountIn;
require(
    actualPrice >= twapPrice * 98 / 100,
    "Price deviated too much from TWAP"
);
```

## Use Cases

### 1. Lending Protocols

Use TWAP for collateral valuation and liquidation pricing:
```solidity
// Get manipulation-resistant collateral value
uint256 collateralValue = oracle.getQuote(collateralToken, usdToken, collateralAmount);

// Safe liquidation threshold
uint256 liquidationPrice = oracle.getPrice(collateralToken, usdToken);
```

### 2. DEX Aggregators

Validate routing quotes against TWAP:
```solidity
// Get quote from aggregator
uint256 routerQuote = getAggregatorQuote(tokenIn, tokenOut, amountIn);

// Validate against TWAP
uint256 twapQuote = oracle.getQuote(tokenIn, tokenOut, amountIn);
require(
    routerQuote >= twapQuote * 95 / 100,
    "Router quote significantly worse than TWAP"
);
```

### 3. Options Protocols

Use TWAP for strike price determination:
```solidity
// Get fair strike price for options
uint256 strikePrice = oracle.getPriceWithPeriod(
    underlying,
    strike,
    7200 // 2-hour TWAP for less volatility
);
```

### 4. Automated Market Makers

Implement TWAP-based fee adjustments:
```solidity
// Compare spot vs TWAP to detect volatility
uint256 spotPrice = getCurrentSpotPrice();
uint256 twapPrice = oracle.getPrice(token0, token1);

uint256 deviation = abs(spotPrice - twapPrice) * 10000 / twapPrice;

// Increase fees during high volatility
if (deviation > 500) { // 5%
    currentFee = baseFee * 2;
}
```

## Important Notes

### Observation Cardinality

Uniswap V3 pools must have sufficient observation cardinality to support TWAP queries. The oracle checks for minimum cardinality and reverts if insufficient.

To increase cardinality (if needed):
```solidity
IUniswapV3Pool(pool).increaseObservationCardinalityNext(100);
```

### TWAP Period Selection

- **Shorter periods** (5-15 min): More responsive, less manipulation-resistant
- **Medium periods** (30-60 min): Good balance (recommended)
- **Longer periods** (2-24 hours): Most manipulation-resistant, less responsive

### Gas Costs

- `getPrice()`: ~100-120k gas
- `getQuote()`: ~100-120k gas
- `getPriceWithPeriod()`: ~100-150k gas

### Decimal Handling

⚠️ **Important**: The oracle returns all prices in 18 decimals, regardless of input token decimals. When using quotes for actual swaps, you may need to convert back to native decimals.

## Security Considerations

1. **Pool Liquidity**: Ensure pools have sufficient liquidity before relying on TWAP
2. **Observation Cardinality**: Check that pools can provide historical data
3. **TWAP Period**: Choose appropriate periods based on your manipulation resistance needs
4. **Price Bounds**: Always implement sanity checks on returned prices
5. **Emergency Oracle**: Consider having a backup oracle for critical operations

## Future Improvements

- [ ] Support for custom fee tiers per query
- [ ] Multiple TWAP period aggregation
- [ ] Chainlink oracle fallback integration
- [ ] Automated pool liquidity checks
- [ ] Gas optimization for batch queries
- [ ] Support for ERC20 tokens without decimals() function

## References

- [Uniswap V3 TWAP Oracle](https://docs.uniswap.org/concepts/protocol/oracle)
- [Uniswap V3 Whitepaper](https://uniswap.org/whitepaper-v3.pdf)
- [Time-Weighted Average Price on Wikipedia](https://en.wikipedia.org/wiki/Time-weighted_average_price)

## License

MIT

