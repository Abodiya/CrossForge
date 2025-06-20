;; Basic sBTC Cross-Chain Wrapper Contract
;; Features: Simple wrapping/unwrapping with basic balance tracking

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u401))
(define-constant ERR_INVALID_AMOUNT (err u402))
(define-constant ERR_INSUFFICIENT_BALANCE (err u403))
(define-constant ERR_UNWRAP_REQUEST_NOT_FOUND (err u404))

;; Data Variables
(define-data-var total-wrapped-btc uint u0)
(define-data-var contract-paused bool false)

;; Data Maps
(define-map user-balances principal uint)
(define-map unwrap-requests
  uint
  {
    requester: principal,
    amount: uint,
    btc-address: (string-ascii 64),
    executed: bool,
    created-at: uint
  }
)

;; Counters
(define-data-var unwrap-request-counter uint u0)

;; Authorization Functions
(define-private (is-contract-owner)
  (is-eq tx-sender CONTRACT_OWNER)
)

;; Admin Functions
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

;; Basic Unwrapping Functions
(define-public (request-unwrap (amount uint) (btc-address (string-ascii 64)))
  (let (
    (current-balance (default-to u0 (map-get? user-balances tx-sender)))
    (request-id (+ (var-get unwrap-request-counter) u1))
  )
    (asserts! (not (var-get contract-paused)) ERR_UNAUTHORIZED)
    (asserts! (>= current-balance amount) ERR_INSUFFICIENT_BALANCE)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    
    ;; Deduct from user balance
    (map-set user-balances tx-sender (- current-balance amount))
    
    ;; Create unwrap request
    (map-set unwrap-requests request-id {
      requester: tx-sender,
      amount: amount,
      btc-address: btc-address,
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

(define-public (execute-unwrap (request-id uint))
  (let (
    (request-info (unwrap! (map-get? unwrap-requests request-id) ERR_UNWRAP_REQUEST_NOT_FOUND))
  )
    (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
    (asserts! (not (get executed request-info)) ERR_UNAUTHORIZED)
    
    ;; Mark as executed
    (map-set unwrap-requests request-id
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

(define-read-only (get-unwrap-request (request-id uint))
  (map-get? unwrap-requests request-id)
)

(define-read-only (get-contract-info)
  {
    total-wrapped-btc: (var-get total-wrapped-btc),
    contract-paused: (var-get contract-paused),
    unwrap-request-counter: (var-get unwrap-request-counter)
  }
)

(define-read-only (is-contract-paused)
  (var-get contract-paused)
)