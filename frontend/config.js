// Sentinel deployment config — filled in by script/deploy.sh after deployment.
// Until then the addresses are zero and the frontend shows "not deployed yet".
window.SENTINEL_CONFIG = {
  chainId: 1301, // Unichain Sepolia
  lasnaChainId: 5318007,
  rpcUnichain: "https://sepolia.unichain.org",
  rpcLasna: "https://lasna-rpc.rnk.dev/",
  mockWeth: "0xDf93e3Aa8aA3A6CfE9e99CB83e1B89131D18c3C1",
  mockUsdc: "0xccf6e4bdd4d75d9981e06a20149918016911f042",
  mockOracle: "0xEfA5040162745690335ED0abC7eFE7fcAc6Bbf52",
  realFeed: "0xd9c93081210dFc33326B2af4C2c11848095E6a9a",
  vault: "0x7c821a4af880fAb37751B0f376CFA726FC575c23",
  reactive: "0xDf93e3Aa8aA3A6CfE9e99CB83e1B89131D18c3C1",
  systemLasna: "0x8888888888888888888888888888888888888888"
};
