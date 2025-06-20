# CrossForge BTC 🪙

CrossForge BTC is a decentralized smart contract on the Stacks blockchain that allows users to wrap their Bitcoin (sBTC) into a yield-generating, multi-signature-secured, and time-locked asset. The protocol enhances security, liquidity, and usability for Bitcoin holders who wish to participate in the Stacks ecosystem.

## 🔐 Key Features

- **Bitcoin Wrapping:** Wrap native BTC into a Stacks-compatible wrapped token (sBTC) for on-chain use.
- **Yield Generation:** Automatically earn a base yield on wrapped BTC, with bonus yield for time-locked deposits.
- **Time-Locked Deposits:** Lock your sBTC for a specified duration and earn enhanced yield after unlocking.
- **Multi-Signature Unwrapping:** Initiate unwrap requests that require M-of-N authorized signers to execute.
- **Fully On-Chain Auditable Logic:** All user states, yield data, and unwrap requests are stored and verifiable on-chain.
- **Pause & Admin Controls:** Ability to pause the contract or update configuration via contract owner.

---

## 📦 Contract Structure

| Component | Description |
|----------|-------------|
| `wrap-bitcoin` | Wraps BTC and credits user balance |
| `create-time-locked-deposit` | Locks user’s sBTC for set block duration |
| `claim-yield` | Allows user to claim passive yield based on holding duration |
| `claim-time-locked-yield` | Bonus yield claim for time-locked deposits |
| `request-unwrap` | Initiates an unwrap request with specified BTC address |
| `sign-unwrap-request` | Adds a signature from an authorized signer |
| `execute-unwrap` | Executes unwrap if enough signatures are present |

---

## 🔐 Multi-Sig Unwrapping

- Admins can manage a list of `authorized-signers`.
- Users initiate unwrap requests that must be signed by a threshold number of signers (e.g., 2 of 3).
- Once enough valid, unique signatures are collected, the unwrap can be executed.

---

## 📈 Yield Mechanics

- **Base Yield Rate:** Set in basis points (e.g., `500 = 5% APY`).
- **Block-Based Yield:** Calculated based on block time held since last claim.
- **Bonus Yield:** 50% extra yield for deposits that are time-locked and held till maturity.

---

## 🛠 Admin Functions

Only the contract owner can:

- Add/Remove authorized signers
- Set the yield rate (max 20%)
- Set required multisig threshold (1 to 10)
- Toggle contract pause for emergencies

---

## 📊 Read-Only Functions

- `get-user-balance`
- `get-total-wrapped-btc`
- `get-contract-info`
- `get-user-yield-info`
- `get-time-locked-deposit`
- `get-unwrap-request`
- `calculate-pending-yield`

---

## 🧪 Example Use Case Flow

1. User wraps BTC using `wrap-bitcoin`
2. They optionally create a `time-locked-deposit`
3. Over time, user claims yield via `claim-yield` or `claim-time-locked-yield`
4. To redeem sBTC back to BTC, user initiates a `request-unwrap`
5. Authorized signers sign using `sign-unwrap-request`
6. Upon reaching the signature threshold, one of them executes `execute-unwrap`

---

## 🔐 Security Assumptions

- Yield is minted and added to wrapped BTC total, simulating interest.
- Unwrapping is escrowed and governed via M-of-N multisig.
- Only contract owner can change critical parameters.
- No external oracles required; purely on-chain logic.

---

## 🤝 Contributions

We welcome community contributions and audits. Feel free to fork, test, and propose improvements.
