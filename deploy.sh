#!/usr/bin/env bash
# Sentinel deployment — TESTNETS ONLY, no real money.
# Prereqs (do these first, see RESUME.md):
#   - deployer funded with >= 0.1 Sepolia ETH (for lREACT) and >= 0.05 Unichain Sepolia ETH
#   - key file at ~/workspace/hackathons/reactive/.deployer.key.json (mode 600, NEVER in the repo)
# Usage: ./deploy.sh   (writes deployments.json + updates frontend/config.js)
set -euo pipefail
export PATH="$HOME/.foundry/bin:$PATH"
cd "$(dirname "$0")"

KEY_FILE="$HOME/workspace/hackathons/reactive/.deployer.key.json"
KEY=$(python3 -c "import json;print(json.load(open('$KEY_FILE'))['data'][0]['private_key'])")
DEPLOYER=$(python3 -c "import json;print(json.load(open('$KEY_FILE'))['data'][0]['address'])")
ETH_SEPOLIA="https://ethereum-sepolia-rpc.publicnode.com"
UNICHAIN="https://sepolia.unichain.org"
LASNA="https://lasna-rpc.rnk.dev/"
REAL_FEED="0xd9c93081210dFc33326B2af4C2c11848095E6a9a"
UNICHAIN_PROXY="0x775c9B990ADe401060B78D0e98684eEf8d2466C1"
LREACT_FAUCET="0x9b9BB25f1A81078C544C829c5EB7822d747Cf434"

echo "Deployer: $DEPLOYER"
echo "Sepolia ETH: $(cast balance $DEPLOYER --rpc-url $ETH_SEPOLIA)"
echo "Unichain ETH: $(cast balance $DEPLOYER --rpc-url $UNICHAIN)"
echo "Lasna lREACT: $(cast balance $DEPLOYER --rpc-url $LASNA)"

# --- 1. lREACT via the Sepolia faucet contract: 0.1 ETH -> 10 lREACT on Lasna ---
echo "== Requesting lREACT (0.1 Sepolia ETH) =="
cast send $LREACT_FAUCET "request(address)" $DEPLOYER --value 0.1ether \
  --rpc-url $ETH_SEPOLIA --private-key $KEY >/dev/null || \
  cast send $LREACT_FAUCET --value 0.1ether --rpc-url $ETH_SEPOLIA --private-key $KEY >/dev/null
echo "Waiting 60s for lREACT to land on Lasna..."
sleep 60
echo "Lasna lREACT now: $(cast balance $DEPLOYER --rpc-url $LASNA)"

# --- 2. Current ETH price from the real Chainlink feed (mock oracle seed) ---
PRICE_HEX=$(cast call $REAL_FEED "latestRoundData()" --rpc-url $UNICHAIN | awk '{print $2}')
PRICE_DEC=$(cast --to-dec $PRICE_HEX)
echo "Real ETH/USD now: $PRICE_DEC (8dp)"

# --- 3. Deploy mocks + vault contracts on Unichain Sepolia ---
echo "== Deploying mocks on Unichain Sepolia =="
WETH=$(forge create src/MockERC20.sol:MockERC20 --rpc-url $UNICHAIN --private-key $KEY --broadcast --json --constructor-args "Mock WETH" "mWETH" 18 | python3 -c "import json,sys;print(json.load(sys.stdin)['deployedTo'])")
USDC=$(forge create src/MockERC20.sol:MockERC20 --rpc-url $UNICHAIN --private-key $KEY --broadcast --json --constructor-args "Mock USDC" "mUSDC" 18 | python3 -c "import json,sys;print(json.load(sys.stdin)['deployedTo'])")
ORACLE=$(forge create src/MockOracle.sol:MockOracle --rpc-url $UNICHAIN --private-key $KEY --broadcast --json --constructor-args $PRICE_DEC | python3 -c "import json,sys;print(json.load(sys.stdin)['deployedTo'])")
echo "MockWETH: $WETH"; echo "MockUSDC: $USDC"; echo "MockOracle: $ORACLE"

# --- 4. Deploy SentinelReactive on Lasna (pre-funded with 2 lREACT) ---
echo "== Deploying SentinelReactive on Lasna =="
REACTIVE=$(forge create src/SentinelReactive.sol:SentinelReactive --rpc-url $LASNA --private-key $KEY --value 2ether --broadcast --json --constructor-args $ORACLE $REAL_FEED | python3 -c "import json,sys;print(json.load(sys.stdin)['deployedTo'])")
echo "SentinelReactive: $REACTIVE"

# --- 5. Deploy SentinelVault on Unichain Sepolia ---
echo "== Deploying SentinelVault on Unichain Sepolia =="
VAULT=$(forge create src/SentinelVault.sol:SentinelVault --rpc-url $UNICHAIN --private-key $KEY --broadcast --json --constructor-args $UNICHAIN_PROXY $REACTIVE $WETH $USDC | python3 -c "import json,sys;print(json.load(sys.stdin)['deployedTo'])")
echo "SentinelVault: $VAULT"

# --- 6. Wire the reactive contract to the vault ---
echo "== setVault on reactive =="
cast send $REACTIVE "setVault(address)" $VAULT --rpc-url $LASNA --private-key $KEY >/dev/null

# --- 7. Fund both contracts for operation ---
echo "== Funding contracts =="
# NOTE (19 Nov, deploy session): only 0.045 ETH was bridged to Unichain
# Sepolia (Sepolia budget is 0.15 total: 0.1 for lREACT + bridge + gas), so
# the vault is funded with 0.04 ETH instead of 0.05. Unichain gas is
# ~0.001 gwei, so 0.04 ETH still funds thousands of callbacks.
cast send $VAULT --value 0.04ether --rpc-url $UNICHAIN --private-key $KEY >/dev/null   # callback gas
cast send $REACTIVE --value 3ether --rpc-url $LASNA --private-key $KEY >/dev/null      # reactive gas
cast send $USDC "mint(address,uint256)" $VAULT 100000ether --rpc-url $UNICHAIN --private-key $KEY >/dev/null  # USDC reserve
echo "Vault ETH: $(cast balance $VAULT --rpc-url $UNICHAIN)"
echo "Reactive lREACT: $(cast balance $REACTIVE --rpc-url $LASNA)"
echo "Vault mUSDC reserve: $(cast call $USDC "balanceOf(address)" $VAULT --rpc-url $UNICHAIN)"

# --- 8. Sourcify verification ---
echo "== Verifying on Sourcify =="
forge verify-contract --verifier sourcify --chain-id 5318007 $REACTIVE src/SentinelReactive.sol:SentinelReactive || echo "reactive verify failed (retry manually)"
forge verify-contract --verifier sourcify --chain-id 1301 $VAULT src/SentinelVault.sol:SentinelVault || echo "vault verify failed (retry manually)"
forge verify-contract --verifier sourcify --chain-id 1301 $WETH src/MockERC20.sol:MockERC20 || true
forge verify-contract --verifier sourcify --chain-id 1301 $USDC src/MockERC20.sol:MockERC20 || true
forge verify-contract --verifier sourcify --chain-id 1301 $ORACLE src/MockOracle.sol:MockOracle || true

# --- 9. Record + wire the frontend ---
python3 - "$WETH" "$USDC" "$ORACLE" "$VAULT" "$REACTIVE" <<'EOF'
import json, sys, re
weth, usdc, oracle, vault, reactive = sys.argv[1:6]
data = {
  "mockWeth": weth, "mockUsdc": usdc, "mockOracle": oracle,
  "realFeed": "0xd9c93081210dFc33326B2af4C2c11848095E6a9a",
  "vault": vault, "reactive": reactive,
  "unichainSepolia": 1301, "lasna": 5318007,
  "unichainProxy": "0x775c9B990ADe401060B78D0e98684eEf8d2466C1",
  "lasnaExplorer": "https://lasna.reactscan.net/",
  "unichainExplorer": "https://sepolia.uniscan.xyz/",
}
json.dump(data, open("deployments.json", "w"), indent=2)
cfg = open("frontend/config.js").read()
for k, v in data.items():
    if k in ("mockWeth", "mockUsdc", "mockOracle", "vault", "reactive"):
        cfg = re.sub(rf'{k}: "0x[0-9a-fA-F]*"', f'{k}: "{v}"', cfg)
open("frontend/config.js", "w").write(cfg)
print("deployments.json + frontend/config.js updated")
EOF

echo "== DONE =="
echo "MockWETH: $WETH"
echo "MockUSDC: $USDC"
echo "MockOracle: $ORACLE"
echo "SentinelReactive (Lasna): $REACTIVE"
echo "SentinelVault (Unichain Sepolia): $VAULT"
