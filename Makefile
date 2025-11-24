include .env

healthcheck:
	source .env && \
	echo "RPC_PROVIDER_URL: $(RPC_PROVIDER_URL)";

deploy:
	make AaveV3LendingProvider.deploy
	make UniswapV3ExchangeProvider.deploy
	make UniswapV3TWAPOracle.deploy

deploy-local:
	make AaveV3LendingProvider.deploy-local
	make UniswapV3ExchangeProvider.deploy-local
	make UniswapV3TWAPOracle.deploy-local

AaveV3LendingProvider.deploy-local:
		source .env && \
		forge script src/AaveV3LendingProvider/AaveV3LendingProvider.s.sol:DeployAaveV3LendingProvider --rpc-url $(RPC_PROVIDER_URL) --private-key $(PRIVATE_KEY) --broadcast -vvvv;

AaveV3LendingProvider.deploy:
		source .env && \
		forge script src/AaveV3LendingProvider/AaveV3LendingProvider.s.sol:DeployAaveV3LendingProvider --rpc-url $(RPC_PROVIDER_URL) --private-key $(PRIVATE_KEY) --etherscan-api-key $(ETHERSCAN_API_KEY) --verify --broadcast -vvvv;

UniswapV3TWAPOracle.deploy-local:
		source .env && \
		forge script src/UniswapV3TWAPOracle/UniswapV3TWAPOracle.s.sol:DeployUniswapV3TWAPOracle --rpc-url $(RPC_PROVIDER_URL) --private-key $(PRIVATE_KEY) --broadcast -vvvv;

UniswapV3TWAPOracle.deploy:
		source .env && \
		forge script src/UniswapV3TWAPOracle/UniswapV3TWAPOracle.s.sol:DeployUniswapV3TWAPOracle --rpc-url $(RPC_PROVIDER_URL) --private-key $(PRIVATE_KEY) --etherscan-api-key $(ETHERSCAN_API_KEY) --verify --broadcast -vvvv;

UniswapV3ExchangeProvider.deploy-local:
		source .env && \
		forge script src/UniswapV3ExchangeProvider/UniswapV3ExchangeProvider.s.sol:DeployUniswapV3ExchangeProvider --rpc-url $(RPC_PROVIDER_URL) --private-key $(PRIVATE_KEY) --broadcast -vvvv;

UniswapV3ExchangeProvider.deploy:
		source .env && \
		forge script src/UniswapV3ExchangeProvider/UniswapV3ExchangeProvider.s.sol:DeployUniswapV3ExchangeProvider --rpc-url $(RPC_PROVIDER_URL) --private-key $(PRIVATE_KEY) --etherscan-api-key $(ETHERSCAN_API_KEY) --verify --broadcast -vvvv;

