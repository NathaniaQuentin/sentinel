# Demo video plan (max 5 min, mp4)

## Tooling — verified 19 Nov 2026

- `ffmpeg` present (`/usr/bin/ffmpeg`). `playwright-core` 1.49.1 installed in
  `video/`; cached Chromium 1148 launches and screenshots local pages fine.
- **Chromium cannot reach external sites from this VM** (proxy is a Unix
  socket; Chromium reports `ERR_TUNNEL_CONNECTION_FAILED` /
  `ERR_NO_SUPPORTED_PROXIES`). `curl` reaches the explorers fine (HTTP 200).
  Consequence: explorer proof shots must be rendered locally (see below).
- Playwright `recordVideo` works headless — use it to capture the real
  frontend session; no xvfb screen-capture needed.

## Assembly (ffmpeg)

1. **Title card (5s):** static PNG (rendered HTML or PIL) — "Sentinel — autonomous
   stop-loss & take-profit (Reactive Omni Buildathon, Track 1)".
2. **Frontend session (Playwright `recordVideo`, ~2 min):** local server
   (`python3 -m http.server` in `frontend/`), injected EIP-1193 provider
   backed by the throwaway deployer key: connect → mint mock WETH → open
   order (stop $1,700 / TP1 $1,900 / TP2 $2,000) → order appears as open.
3. **Trigger (terminal capture, ~1 min):** `cast send` to `MockOracle.setPrice`
   below the stop, then `cast call` the vault to show the fill, plus the
   Lasna `ExitRequested` event via `cast logs`. Record the terminal with
   Playwright video of a local terminal page, or `script` + ffmpeg `drawtext`
   frames — whichever is cleaner at the time.
4. **Proof slides (~1 min):** for each key tx/address, fetch REAL data with
   `curl` from the explorer APIs (Blockscout:
   `https://sepolia.uniscan.xyz/api`, Lasna Reactscan API) and render it into
   local HTML cards (tx hash, from/to, status, block, explorer URL as text),
   screenshotted via Playwright from localhost. The data is live and
   verifiable at the printed URLs; only the rendering is local, because this
   VM's Chromium cannot load the explorer sites directly.
5. **Outro (10s):** repo link + contract addresses.

Concat with ffmpeg, H.264 mp4, 1280x720, target < 5:00, check duration with
`ffprobe`. No audio track required (captions carry the narration); add a
voiceover only if a TTS path is available at assembly time.
