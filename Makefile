include .env

healthcheck:
	source .env && \
	echo "RPC_PROVIDER_URL: $(RPC_PROVIDER_URL)";

UniswapV3ExchangeProvider.deploy-local:
		source .env && \
		forge script src/UniswapV3ExchangeProvider/UniswapV3ExchangeProvider.s.sol:DeployUniswapV3ExchangeProvider --rpc-url $(RPC_PROVIDER_URL) --private-key $(PRIVATE_KEY) --broadcast -vvvv;

UniswapV3ExchangeProvider.deploy:
		source .env && \
		forge script src/UniswapV3ExchangeProvider/UniswapV3ExchangeProvider.s.sol:DeployUniswapV3ExchangeProvider --rpc-url $(RPC_PROVIDER_URL) --private-key $(PRIVATE_KEY) --etherscan-api-key $(ETHERSCAN_API_KEY) --verify --broadcast -vvvv;

