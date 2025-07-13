;; sBTC Cross-Chain Wrapper Contract
;; Features: Time-locked deposits, Multi-sig unwrapping, Yield generation

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u401))
(define-constant ERR_INVALID_AMOUNT (err u402))
(define-constant ERR_INSUFFICIENT_BALANCE (err u403))
(define-constant ERR_TIME_LOCK_ACTIVE (err u404))
(define-constant ERR_INVALID_SIGNATURE (err u405))
(define-constant ERR_ALREADY_SIGNED (err u406))
(define-constant ERR_INSUFFICIENT_SIGNATURES (err u407))
(define-constant ERR_DEPOSIT_NOT_FOUND (err u408))
(define-constant ERR_INVALID_YIELD_RATE (err u409))
(define-constant ERR_YIELD_ALREADY_CLAIMED (err u410))

;; Data Variables
(define-data-var total-wrapped-btc uint u0)
(define-data-var base-yield-rate uint u500) ;; 5% annual yield (500 basis points)
(define-data-var contract-paused bool false)
(define-data-var required-signatures uint u2) ;; Default 2-of-3 multisig

;; Data Maps
(define-map user-balances principal uint)
(define-map time-locked-deposits 
  uint 
  {
    owner: principal,
    amount: uint,
    unlock-height: uint,
    created-at: uint,
    yield-claimed: bool
  }
)

(define-map multisig-unwrap-requests
  uint
  {
    requester: principal,
    amount: uint,
    btc-address: (string-ascii 64),
    signatures: (list 10 principal),
    signature-count: uint,
    executed: bool,
    created-at: uint
  }
)

(define-map authorized-signers principal bool)
(define-map user-yield-info
  principal
  {
    last-claim-height: uint,
    total-earned: uint,
    pending-yield: uint
  }
)

;; Counters
(define-data-var deposit-counter uint u0)
(define-data-var unwrap-request-counter uint u0)

;; Authorization Functions
(define-private (is-contract-owner)
  (is-eq tx-sender CONTRACT_OWNER)
)

(define-private (is-authorized-signer (signer principal))
  (default-to false (map-get? authorized-signers signer))
)

;; Admin Functions
(define-public (add-authorized-signer (signer principal))
  (begin
    (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
    (ok (map-set authorized-signers signer true))
  )
)

(define-public (remove-authorized-signer (signer principal))
  (begin
    (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
    (ok (map-delete authorized-signers signer))
  )
)

(define-public (set-required-signatures (new-requirement uint))
  (begin
    (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
    (asserts! (and (> new-requirement u0) (<= new-requirement u10)) ERR_INVALID_AMOUNT)
    (ok (var-set required-signatures new-requirement))
  )
)

(define-public (set-yield-rate (new-rate uint))
  (begin
    (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
    (asserts! (<= new-rate u2000) ERR_INVALID_YIELD_RATE) ;; Max 20% yield
    (ok (var-set base-yield-rate new-rate))
  )
)

(define-public (toggle-contract-pause)
  (begin
    (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
    (ok (var-set contract-paused (not (var-get contract-paused))))
  )
)

;; Core Wrapping Functions
(define-public (wrap-bitcoin (amount uint) (btc-txid (string-ascii 64)))
  (let (
    (current-balance (default-to u0 (map-get? user-balances tx-sender)))
  )
    (asserts! (not (var-get contract-paused)) ERR_UNAUTHORIZED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    
    ;; Update user balance
    (map-set user-balances tx-sender (+ current-balance amount))
    
    ;; Update total wrapped BTC
    (var-set total-wrapped-btc (+ (var-get total-wrapped-btc) amount))
    
    ;; Initialize yield tracking
    (map-set user-yield-info tx-sender {
      last-claim-height: block-height,
      total-earned: u0,
      pending-yield: u0
    })
    
    (print {
      action: "wrap-bitcoin",
      user: tx-sender,
      amount: amount,
      btc-txid: btc-txid,
      new-balance: (+ current-balance amount)
    })
    
    (ok amount)
  )
)

;; Time-Locked Deposit Functions
(define-public (create-time-locked-deposit (amount uint) (lock-duration uint))
  (let (
    (current-balance (default-to u0 (map-get? user-balances tx-sender)))
    (deposit-id (+ (var-get deposit-counter) u1))
    (unlock-height (+ block-height lock-duration))
  )
    (asserts! (not (var-get contract-paused)) ERR_UNAUTHORIZED)
    (asserts! (>= current-balance amount) ERR_INSUFFICIENT_BALANCE)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (>= lock-duration u144) ERR_INVALID_AMOUNT) ;; Minimum 1 day lock
    
    ;; Deduct from user balance
    (map-set user-balances tx-sender (- current-balance amount))
    
    ;; Create time-locked deposit
    (map-set time-locked-deposits deposit-id {
      owner: tx-sender,
      amount: amount,
      unlock-height: unlock-height,
      created-at: block-height,
      yield-claimed: false
    })
    
    ;; Update counter
    (var-set deposit-counter deposit-id)
    
    (print {
      action: "create-time-locked-deposit",
      deposit-id: deposit-id,
      user: tx-sender,
      amount: amount,
      unlock-height: unlock-height
    })
    
    (ok deposit-id)
  )
)

(define-public (unlock-time-locked-deposit (deposit-id uint))
  (let (
    (deposit-info (unwrap! (map-get? time-locked-deposits deposit-id) ERR_DEPOSIT_NOT_FOUND))
    (current-balance (default-to u0 (map-get? user-balances tx-sender)))
  )
    (asserts! (is-eq tx-sender (get owner deposit-info)) ERR_UNAUTHORIZED)
    (asserts! (>= block-height (get unlock-height deposit-info)) ERR_TIME_LOCK_ACTIVE)
    
    ;; Return funds to user balance
    (map-set user-balances tx-sender (+ current-balance (get amount deposit-info)))
    
    ;; Remove the deposit record
    (map-delete time-locked-deposits deposit-id)
    
    (print {
      action: "unlock-time-locked-deposit",
      deposit-id: deposit-id,
      user: tx-sender,
      amount: (get amount deposit-info)
    })
    
    (ok (get amount deposit-info))
  )
)

;; Yield Generation Functions
(define-private (calculate-yield (principal-amount uint) (blocks-held uint))
  (let (
    (annual-blocks u52560) ;; Approximate blocks per year (10 min avg)
    (yield-rate (var-get base-yield-rate))
  )
    ;; yield = (principal * rate * blocks_held) / (annual_blocks * 10000)
    (/ (* (* principal-amount yield-rate) blocks-held) (* annual-blocks u10000))
  )
)

(define-public (claim-yield)
  (let (
    (user-balance (default-to u0 (map-get? user-balances tx-sender)))
    (yield-info (default-to 
      {last-claim-height: block-height, total-earned: u0, pending-yield: u0}
      (map-get? user-yield-info tx-sender)
    ))
    (blocks-since-claim (- block-height (get last-claim-height yield-info)))
    (earned-yield (calculate-yield user-balance blocks-since-claim))
  )
    (asserts! (> user-balance u0) ERR_INSUFFICIENT_BALANCE)
    (asserts! (> blocks-since-claim u144) ERR_INVALID_AMOUNT) ;; Minimum 1 day between claims
    
    ;; Update user balance with yield
    (map-set user-balances tx-sender (+ user-balance earned-yield))
    
    ;; Update yield tracking
    (map-set user-yield-info tx-sender {
      last-claim-height: block-height,
      total-earned: (+ (get total-earned yield-info) earned-yield),
      pending-yield: u0
    })
    
    ;; Update total wrapped BTC (yield increases total supply)
    (var-set total-wrapped-btc (+ (var-get total-wrapped-btc) earned-yield))
    
    (print {
      action: "claim-yield",
      user: tx-sender,
      yield-earned: earned-yield,
      blocks-held: blocks-since-claim
    })
    
    (ok earned-yield)
  )
)

(define-public (claim-time-locked-yield (deposit-id uint))
  (let (
    (deposit-info (unwrap! (map-get? time-locked-deposits deposit-id) ERR_DEPOSIT_NOT_FOUND))
    (blocks-locked (- block-height (get created-at deposit-info)))
    (bonus-multiplier u150) ;; 50% bonus for time-locked deposits
    (base-yield (calculate-yield (get amount deposit-info) blocks-locked))
    (bonus-yield (/ (* base-yield bonus-multiplier) u100))
    (total-yield (+ base-yield bonus-yield))
    (current-balance (default-to u0 (map-get? user-balances tx-sender)))
  )
    (asserts! (is-eq tx-sender (get owner deposit-info)) ERR_UNAUTHORIZED)
    (asserts! (not (get yield-claimed deposit-info)) ERR_YIELD_ALREADY_CLAIMED)
    (asserts! (>= block-height (get unlock-height deposit-info)) ERR_TIME_LOCK_ACTIVE)
    
    ;; Add yield to user balance
    (map-set user-balances tx-sender (+ current-balance total-yield))
    
    ;; Mark yield as claimed
    (map-set time-locked-deposits deposit-id 
      (merge deposit-info {yield-claimed: true})
    )
    
    ;; Update total wrapped BTC
    (var-set total-wrapped-btc (+ (var-get total-wrapped-btc) total-yield))
    
    (print {
      action: "claim-time-locked-yield",
      deposit-id: deposit-id,
      user: tx-sender,
      base-yield: base-yield,
      bonus-yield: bonus-yield,
      total-yield: total-yield
    })
    
    (ok total-yield)
  )
)

;; Multi-Signature Unwrapping Functions
(define-public (request-unwrap (amount uint) (btc-address (string-ascii 64)))
  (let (
    (current-balance (default-to u0 (map-get? user-balances tx-sender)))
    (request-id (+ (var-get unwrap-request-counter) u1))
  )
    (asserts! (not (var-get contract-paused)) ERR_UNAUTHORIZED)
    (asserts! (>= current-balance amount) ERR_INSUFFICIENT_BALANCE)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    
    ;; Deduct from user balance (escrowed until unwrap completes)
    (map-set user-balances tx-sender (- current-balance amount))
    
    ;; Create unwrap request
    (map-set multisig-unwrap-requests request-id {
      requester: tx-sender,
      amount: amount,
      btc-address: btc-address,
      signatures: (list),
      signature-count: u0,
      executed: false,
      created-at: block-height
    })
    
    ;; Update counter
    (var-set unwrap-request-counter request-id)
    
    (print {
      action: "request-unwrap",
      request-id: request-id,
      user: tx-sender,
      amount: amount,
      btc-address: btc-address
    })
    
    (ok request-id)
  )
)

(define-public (sign-unwrap-request (request-id uint))
  (let (
    (request-info (unwrap! (map-get? multisig-unwrap-requests request-id) ERR_DEPOSIT_NOT_FOUND))
    (current-signatures (get signatures request-info))
    (signature-count (get signature-count request-info))
  )
    (asserts! (is-authorized-signer tx-sender) ERR_UNAUTHORIZED)
    (asserts! (not (get executed request-info)) ERR_UNAUTHORIZED)
    
    ;; Check if already signed
    (asserts! (is-none (index-of current-signatures tx-sender)) ERR_ALREADY_SIGNED)
    
    ;; Add signature
    (let (
      (new-signatures (unwrap! (as-max-len? (append current-signatures tx-sender) u10) ERR_INVALID_SIGNATURE))
      (new-signature-count (+ signature-count u1))
    )
      (map-set multisig-unwrap-requests request-id
        (merge request-info {
          signatures: new-signatures,
          signature-count: new-signature-count
        })
      )
      
      (print {
        action: "sign-unwrap-request",
        request-id: request-id,
        signer: tx-sender,
        signature-count: new-signature-count,
        required: (var-get required-signatures)
      })
      
      (ok new-signature-count)
    )
  )
)

(define-public (execute-unwrap (request-id uint))
  (let (
    (request-info (unwrap! (map-get? multisig-unwrap-requests request-id) ERR_DEPOSIT_NOT_FOUND))
  )
    (asserts! (is-authorized-signer tx-sender) ERR_UNAUTHORIZED)
    (asserts! (not (get executed request-info)) ERR_UNAUTHORIZED)
    (asserts! (>= (get signature-count request-info) (var-get required-signatures)) ERR_INSUFFICIENT_SIGNATURES)
    
    ;; Mark as executed
    (map-set multisig-unwrap-requests request-id
      (merge request-info {executed: true})
    )
    
    ;; Update total wrapped BTC
    (var-set total-wrapped-btc (- (var-get total-wrapped-btc) (get amount request-info)))
    
    (print {
      action: "execute-unwrap",
      request-id: request-id,
      requester: (get requester request-info),
      amount: (get amount request-info),
      btc-address: (get btc-address request-info),
      executor: tx-sender
    })
    
    (ok (get amount request-info))
  )
)

;; Transfer Functions
(define-public (transfer (amount uint) (recipient principal))
  (let (
    (sender-balance (default-to u0 (map-get? user-balances tx-sender)))
    (recipient-balance (default-to u0 (map-get? user-balances recipient)))
  )
    (asserts! (not (var-get contract-paused)) ERR_UNAUTHORIZED)
    (asserts! (>= sender-balance amount) ERR_INSUFFICIENT_BALANCE)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (not (is-eq tx-sender recipient)) ERR_INVALID_AMOUNT)
    
    ;; Update balances
    (map-set user-balances tx-sender (- sender-balance amount))
    (map-set user-balances recipient (+ recipient-balance amount))
    
    (print {
      action: "transfer",
      from: tx-sender,
      to: recipient,
      amount: amount
    })
    
    (ok amount)
  )
)

;; View Functions
(define-read-only (get-user-balance (user principal))
  (default-to u0 (map-get? user-balances user))
)

(define-read-only (get-total-wrapped-btc)
  (var-get total-wrapped-btc)
)

(define-read-only (get-time-locked-deposit (deposit-id uint))
  (map-get? time-locked-deposits deposit-id)
)

(define-read-only (get-unwrap-request (request-id uint))
  (map-get? multisig-unwrap-requests request-id)
)

(define-read-only (get-user-yield-info (user principal))
  (map-get? user-yield-info user)
)

(define-read-only (calculate-pending-yield (user principal))
  (let (
    (user-balance (default-to u0 (map-get? user-balances user)))
    (yield-info (default-to 
      {last-claim-height: block-height, total-earned: u0, pending-yield: u0}
      (map-get? user-yield-info user)
    ))
    (blocks-since-claim (- block-height (get last-claim-height yield-info)))
  )
    (calculate-yield user-balance blocks-since-claim)
  )
)

(define-read-only (get-contract-info)
  {
    total-wrapped-btc: (var-get total-wrapped-btc),
    base-yield-rate: (var-get base-yield-rate),
    required-signatures: (var-get required-signatures),
    contract-paused: (var-get contract-paused),
    deposit-counter: (var-get deposit-counter),
    unwrap-request-counter: (var-get unwrap-request-counter)
  }
)

(define-read-only (is-authorized-signer-check (signer principal))
  (is-authorized-signer signer)
)

(define-read-only (is-contract-paused)
  (var-get contract-paused)
)