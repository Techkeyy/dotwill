# Willz — On-Chain Inheritance on Polkadot Hub

> **Polkadot Solidity Hackathon 2026** | Track: EVM Smart Contract — AI-powered dApp

[![Live Demo](https://img.shields.io/badge/Live%20Demo-willz.vercel.app-E6007A?style=flat&logo=vercel&logoColor=white)](https://willz.vercel.app)
[![Polkadot Hub](https://img.shields.io/badge/Deployed%20on-Polkadot%20Hub%20TestNet-E6007A?style=flat&logo=polkadot&logoColor=white)](https://blockscout-testnet.polkadot.io/address/0xbB4797c9E49Ce80FF64652aC322ccC8F4C0161C6)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.20-363636?style=flat&logo=solidity)](https://soliditylang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## Live Demo

🌐 **[willz.vercel.app](https://willz.vercel.app)**

> Requires MetaMask. The app automatically adds Polkadot Hub TestNet and prompts for test PAS tokens.
> Get free PAS tokens at [faucet.polkadot.io](https://faucet.polkadot.io/?parachain=1000)

---

## The Problem

An estimated **$140 billion in crypto** is permanently lost every year because owners die without a succession plan. No wallet in the world has solved this cleanly. There is no on-chain way to say *"if I stop responding, send my assets to my family."*

Willz solves this.

---

## What is Willz?

Willz is a decentralized inheritance protocol built with Solidity on Polkadot Hub. It uses a **heartbeat dead man's switch** — you check in regularly to prove you're alive. If you stop, the contract automatically unlocks and your beneficiaries can claim their share.

No lawyers. No banks. No middlemen. Just code.

---

## How It Works

```
Deploy Will → Set Beneficiaries → Fund Vault → Send Heartbeats
                                                      ↓
                                          Miss deadline + grace period
                                                      ↓
                                          Anyone calls trigger()
                                                      ↓
                                          Beneficiaries claim their share
```

1. **Deploy** — Owner deploys their personal `DotWill` contract via the factory. Sets beneficiaries with percentage shares (must total 100%).
2. **Fund** — Owner deposits PAS tokens into the vault.
3. **Heartbeat** — Owner sends a lightweight transaction every N days to reset the countdown.
4. **Trigger** — If the owner misses the interval + grace period, anyone can call `trigger()` to unlock the will.
5. **Claim** — Each beneficiary calls `claim(index)` to receive their share of the vault.
6. **Last Message** — Owner writes a final encrypted message. AES-256-GCM encrypted in the browser, stored on-chain, only readable after the will triggers.

---

## Features

### Smart Contracts
- **DotWillFactory** — Deploys individual `DotWill` contracts per user. One factory, unlimited wills.
- **DotWillV2** — Per-user inheritance contract with:
  - Heartbeat mechanism with configurable interval (1–365 days) and grace period
  - Multi-beneficiary support (up to 10) with basis-point share allocation
  - Native PAS token vault (deposit / withdraw)
  - On-chain encrypted last message storage
  - Emergency revoke with full refund
  - Custom Solidity errors for gas efficiency

### Frontend
- Full dashboard — live vault balance, countdown timer, heartbeat history
- 3-step will setup wizard — beneficiaries, heartbeat settings, deploy
- AI-powered Last Message writer (Gemini API)
- AES-256-GCM message encryption in the browser
- MetaMask integration with auto network switching to Polkadot Hub TestNet
- Fully responsive — desktop, tablet, mobile
- Polkadot official brand colors and Unbounded typeface

### AI Integration
- **AI Last Message** — Write rough notes, AI polishes them into a heartfelt final message for your beneficiaries
- Powered by Google Gemini API

---

## Deployed Contracts

| Contract | Network | Address |
|---|---|---|
| `DotWillFactory` | Polkadot Hub TestNet | [`0x9D2fF9eEeF4E561969841849A06E87Ea4Eba68e6`](https://blockscout-testnet.polkadot.io/address/0x9D2fF9eEeF4E561969841849A06E87Ea4Eba68e6) |
| `DotWillV2` (example) | Polkadot Hub TestNet | [`0xc4a3FAd2e79Bf5B50d1063697A5e8095Ccc829cb`](https://blockscout-testnet.polkadot.io/address/0xc4a3FAd2e79Bf5B50d1063697A5e8095Ccc829cb) |

**Network details:**
- RPC: `https://eth-rpc-testnet.polkadot.io/`
- Chain ID: `420420417`
- Symbol: `PAS`
- Explorer: `https://blockscout-testnet.polkadot.io/`

---

## Tech Stack

| Layer | Technology |
|---|---|
| Smart Contracts | Solidity 0.8.20 |
| Network | Polkadot Hub (PolkaVM) |
| Frontend | HTML, CSS, JavaScript |
| Web3 | ethers.js v6 |
| Wallet | MetaMask |
| AI | Google Gemini API |
| Encryption | Web Crypto API (AES-256-GCM) |
| Deployment | Remix IDE |

---

## Project Structure

```
dotwill/
├── DotWillV2.sol              # Per-user inheritance contract
├── DotWillFactoryCombined.sol # Factory + DotWillV2 in one file (for Remix)
├── dotwill-polkadot.html      # Full frontend application
└── README.md
```

---

## Running Locally

```bash
# Clone the repo
git clone https://github.com/Techkeyy/dotwill
cd dotwill

# Serve locally (requires Node.js)
npx serve .

# Open in browser
# http://localhost:3000/dotwill-polkadot.html
```

> MetaMask required. The app will automatically prompt you to add/switch to Polkadot Hub TestNet.

---

## Smart Contract Architecture

### DotWillFactory
```solidity
function createWill(
    address payable[] memory _beneficiaryWallets,
    uint256[]          memory _shareBps,        // basis points, must sum to 10000
    string[]           memory _labels,
    uint256 _heartbeatInterval,                 // seconds (1 day – 365 days)
    uint256 _gracePeriod                        // seconds (1 day – 30 days)
) external payable returns (address)

function getWill(address user) external view returns (address)
function hasWill(address user) external view returns (bool)
```

### DotWillV2 (core functions)
```solidity
function heartbeat() external                          // Owner proves alive
function trigger() external                            // Anyone calls after deadline
function claim(uint256 index) external                 // Beneficiary claims share
function deposit() external payable                    // Add PAS to vault
function withdraw(uint256 amount) external             // Owner withdraws
function setEncryptedMessage(string calldata) external // Store last message
function getEncryptedMessage() external view           // Read after trigger only
function revoke() external                             // Owner cancels will
function status() external view returns (...)          // Full status snapshot
```

---

## Judging Criteria Checklist

| Criteria | Implementation |
|---|---|
| ✅ Technical Implementation | Two Solidity contracts, factory pattern, deployed on Polkadot Hub |
| ✅ Use of Polkadot Hub Features | Native PAS token, PolkaVM, EVM compatibility via pallet-revive |
| ✅ Innovation & Impact | $140B lost crypto problem, novel dead man's switch solution |
| ✅ UX and Adoption Potential | Full dashboard, mobile responsive, AI features, one-click network setup |
| ✅ AI Integration | Gemini-powered last message writer |

---

## Team

**Techkeyy** — Solo builder
- GitHub: [@Techkeyy](https://github.com/Techkeyy)

---

## License

MIT — see [LICENSE](LICENSE)

---

*Built for the Polkadot Solidity Hackathon 2026 · Powered by PolkaVM · Secured by Solidity*
