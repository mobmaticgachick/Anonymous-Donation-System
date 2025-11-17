# 🕶️ Anonymous Donation System

A privacy-preserving donation platform built on the Stacks blockchain using Clarity smart contracts. Send funds where donor identity is hidden but donations remain provably valid.

## ✨ Features

- 🎭 **Anonymous Donations**: Donor identity remains private through cryptographic commitments
- 🏪 **Recipient Registration**: Organizations can register to receive donations
- 💰 **Secure Withdrawals**: Recipients can withdraw their donations securely
- 🔐 **Commitment Scheme**: Two-phase donation process for enhanced privacy
- 📊 **Transparent Tracking**: Total donations and recipient balances are publicly visible
- 💸 **Fee System**: Configurable contract fees for sustainability

## 🚀 Quick Start

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet) installed
- [Node.js](https://nodejs.org/) (for testing)

### Installation

```bash
git clone <repository-url>
cd Anonymous-Donation-System
clarinet console
```

## 📋 Usage Guide

### For Recipients

#### 1️⃣ Register as a Recipient
```clarity
(contract-call? .anonymous-donation-system register-recipient "Charity Name" "Helping communities worldwide")
```

#### 2️⃣ Check Your Balance
```clarity
(contract-call? .anonymous-donation-system get-available-balance u1)
```

#### 3️⃣ Withdraw Donations
```clarity
(contract-call? .anonymous-donation-system withdraw-donations u1 u1000000)
```

### For Donors

#### Method 1: Commit-Reveal Donation 🔒

**Step 1: Create Commitment**
```clarity
;; Create a hash: sha256(nonce + amount + sender)
(contract-call? .anonymous-donation-system commit-donation 0x1234567890abcdef... u1)
```

**Step 2: Reveal and Donate**
```clarity
(contract-call? .anonymous-donation-system reveal-and-donate u1 u123456 u1000000)
```

#### Method 2: Anonymous Balance Donation 🎭

**Step 1: Deposit to Anonymous Balance**
```clarity
(contract-call? .anonymous-donation-system deposit-anonymous 0xabcdef1234567890... u2000000)
```

**Step 2: Make Anonymous Donation**
```clarity
(contract-call? .anonymous-donation-system anonymous-donate 0xabcdef1234567890... u1 u1000000 u789012)
```

## 🔧 Contract Functions

### 📖 Read-Only Functions

| Function | Description |
|----------|-------------|
| `get-recipient` | Get recipient details by ID |
| `get-recipient-by-owner` | Get recipient by owner principal |
| `get-total-donations` | Get total donations processed |
| `get-contract-fee-rate` | Get current fee rate (basis points) |
| `get-commitment` | Get commitment details by ID |
| `get-anonymous-balance` | Get balance for commitment hash |
| `calculate-fee` | Calculate fee for given amount |
| `get-available-balance` | Get available balance for recipient |

### ✍️ Write Functions

| Function | Description |
|----------|-------------|
| `register-recipient` | Register as a donation recipient |
| `update-recipient-status` | Enable/disable recipient |
| `commit-donation` | Create donation commitment |
| `reveal-and-donate` | Reveal commitment and donate |
| `deposit-anonymous` | Deposit to anonymous balance |
| `anonymous-donate` | Donate from anonymous balance |
| `withdraw-donations` | Withdraw donations (recipients only) |
| `withdraw-anonymous-balance` | Withdraw from anonymous balance |
| `set-fee-rate` | Set fee rate (owner only) |
| `collect-fees` | Collect contract fees (owner only) |

## 🔒 Privacy Mechanism

The system uses a **commitment-reveal scheme** to ensure donor privacy:

1. **Commitment Phase**: Donors create a cryptographic commitment (hash) containing:
   - Random nonce
   - Donation amount
   - Sender address (for validation)

2. **Reveal Phase**: Donors reveal the original values to complete the donation
   - The contract validates the hash matches
   - Only the recipient receives the funds
   - Donor identity remains private on-chain

## 💰 Fee Structure

- Default fee rate: **2.5%** (250 basis points)
- Fees are deducted from donations
- Contract owner can adjust fee rate (max 10%)
- Recipients receive net amount after fees

## 🧪 Testing

Run the test suite:
```bash
clarinet test
```

## 📊 Example Scenarios

### Scenario 1: Simple Anonymous Donation
```clarity
;; 1. Charity registers
(contract-call? .anonymous-donation-system register-recipient "Local Food Bank" "Feeding families in need")

;; 2. Donor creates commitment hash for 10 STX donation
;; Hash = sha256("123456" + "10000000" + "donor-address")
(contract-call? .anonymous-donation-system commit-donation 0xabc123... u1)

;; 3. Donor reveals and completes donation
(contract-call? .anonymous-donation-system reveal-and-donate u1 u123456 u10000000)

;; 4. Charity withdraws funds
(contract-call? .anonymous-donation-system withdraw-donations u1 u9750000)
```

### Scenario 2: Anonymous Balance Method
```clarity
;; 1. Donor deposits to anonymous balance
(contract-call? .anonymous-donation-system deposit-anonymous 0xdef456... u20000000)

;; 2. Donor makes anonymous donation
(contract-call? .anonymous-donation-system anonymous-donate 0xdef456... u1 u10000000 u654321)
```

## 🔐 Security Features

- ✅ **Access Control**: Only recipients can withdraw their funds
- ✅ **Validation**: All donations require valid commitments
- ✅ **Time Limits**: Commitments expire after 100 blocks
- ✅ **Balance Checks**: Prevents overdraft scenarios
- ✅ **Fee Protection**: Owner can't set excessive fees

## 🌟 Contract Architecture

```
┌─────────────────┐    ┌──────────────────┐
│     Donors      │    │    Recipients    │
└─────────┬───────┘    └────────┬─────────┘
          │                     │
          ▼                     ▼
┌─────────────────────────────────────────┐
│        Anonymous Donation System        │
├─────────────────────────────────────────┤
│ • Commitment Storage                    │
│ • Anonymous Balances                    │
│ • Recipient Registry                    │
│ • Fee Management                        │
└─────────────────────────────────────────┘
```

## 📄 Error Codes

| Code | Error | Description |
|------|-------|-------------|
| u100 | `err-owner-only` | Only contract owner can perform this action |
| u101 | `err-invalid-amount` | Amount must be greater than 0 |
| u102 | `err-recipient-not-found` | Recipient does not exist |
| u103 | `err-insufficient-balance` | Insufficient balance for operation |
| u104 | `err-transfer-failed` | STX transfer failed |
| u105 | `err-already-registered` | Principal already registered |
| u106 | `err-invalid-commitment` | Invalid commitment data |
| u107 | `err-commitment-not-found` | Commitment does not exist |
| u108 | `err-already-revealed` | Commitment already revealed |
| u109 | `err-invalid-reveal` | Reveal data doesn't match commitment |
| u110 | `err-reveal-period-ended` | Reveal period has expired |

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📝 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙏 Acknowledgments

- Stacks Foundation for the blockchain platform
- Clarity language documentation and community
- Privacy-preserving cryptography research

---

Made with ❤️ for anonymous giving and blockchain privacy
