;; Liquid Gold Vault - Precious Metals Tokenization Platform
;; Features: Secure Vaults, Multi-Guardian Redemption, Premium Staking Rewards

;; Constants
(define-constant VAULT_MASTER tx-sender)
(define-constant ERR_ACCESS_DENIED (err u501))
(define-constant ERR_INVALID_QUANTITY (err u502))
(define-constant ERR_INSUFFICIENT_HOLDINGS (err u503))
(define-constant ERR_VAULT_SEALED (err u504))
(define-constant ERR_INVALID_GUARDIAN (err u505))
(define-constant ERR_DUPLICATE_APPROVAL (err u506))
(define-constant ERR_INSUFFICIENT_APPROVALS (err u507))
(define-constant ERR_VAULT_NOT_FOUND (err u508))
(define-constant ERR_INVALID_PREMIUM_RATE (err u509))
(define-constant ERR_REWARDS_ALREADY_HARVESTED (err u510))

;; Data Variables
(define-data-var total-tokenized-gold uint u0)
(define-data-var premium-staking-rate uint u750) ;; 7.5% annual premium rate
(define-data-var system-active bool true)
(define-data-var minimum-guardian-approvals uint u3) ;; Default 3-of-5 multi-guardian

;; Data Maps
(define-map investor-portfolios principal uint)
(define-map secured-treasure-vaults 
  uint 
  {
    vault-keeper: principal,
    gold-quantity: uint,
    release-block: uint,
    vault-created: uint,
    premium-harvested: bool
  }
)

(define-map guardian-redemption-orders
  uint
  {
    order-creator: principal,
    redemption-amount: uint,
    delivery-address: (string-ascii 128),
    guardian-approvals: (list 15 principal),
    approval-tally: uint,
    order-fulfilled: bool,
    order-timestamp: uint
  }
)

(define-map certified-guardians principal bool)
(define-map investor-premium-tracking
  principal
  {
    last-harvest-block: uint,
    lifetime-earnings: uint,
    accumulated-rewards: uint
  }
)

;; Counters
(define-data-var vault-sequence uint u0)
(define-data-var redemption-sequence uint u0)

;; Authorization Functions
(define-private (is-vault-master)
  (is-eq tx-sender VAULT_MASTER)
)

(define-private (is-certified-guardian (guardian principal))
  (default-to false (map-get? certified-guardians guardian))
)

;; Administrative Functions
(define-public (certify-guardian (new-guardian principal))
  (begin
    (asserts! (is-vault-master) ERR_ACCESS_DENIED)
    (ok (map-set certified-guardians new-guardian true))
  )
)

(define-public (revoke-guardian-certification (guardian principal))
  (begin
    (asserts! (is-vault-master) ERR_ACCESS_DENIED)
    (ok (map-delete certified-guardians guardian))
  )
)

(define-public (adjust-guardian-threshold (new-threshold uint))
  (begin
    (asserts! (is-vault-master) ERR_ACCESS_DENIED)
    (asserts! (and (> new-threshold u0) (<= new-threshold u15)) ERR_INVALID_QUANTITY)
    (ok (var-set minimum-guardian-approvals new-threshold))
  )
)

(define-public (update-premium-staking-rate (new-premium-rate uint))
  (begin
    (asserts! (is-vault-master) ERR_ACCESS_DENIED)
    (asserts! (<= new-premium-rate u3000) ERR_INVALID_PREMIUM_RATE) ;; Max 30% premium
    (ok (var-set premium-staking-rate new-premium-rate))
  )
)

(define-public (toggle-system-status)
  (begin
    (asserts! (is-vault-master) ERR_ACCESS_DENIED)
    (ok (var-set system-active (not (var-get system-active))))
  )
)

;; Core Tokenization Functions
(define-public (mint-liquid-gold (quantity uint) (metal-certificate (string-ascii 96)))
  (let (
    (current-portfolio (default-to u0 (map-get? investor-portfolios tx-sender)))
  )
    (asserts! (var-get system-active) ERR_ACCESS_DENIED)
    (asserts! (> quantity u0) ERR_INVALID_QUANTITY)
    
    ;; Update investor portfolio
    (map-set investor-portfolios tx-sender (+ current-portfolio quantity))
    
    ;; Update total tokenized gold
    (var-set total-tokenized-gold (+ (var-get total-tokenized-gold) quantity))
    
    ;; Initialize premium tracking
    (map-set investor-premium-tracking tx-sender {
      last-harvest-block: block-height,
      lifetime-earnings: u0,
      accumulated-rewards: u0
    })
    
    (print {
      event: "mint-liquid-gold",
      investor: tx-sender,
      quantity: quantity,
      certificate: metal-certificate,
      new-portfolio-balance: (+ current-portfolio quantity)
    })
    
    (ok quantity)
  )
)

;; Secured Treasure Vault Functions
(define-public (seal-treasure-vault (gold-amount uint) (lock-duration uint))
  (let (
    (current-portfolio (default-to u0 (map-get? investor-portfolios tx-sender)))
    (vault-id (+ (var-get vault-sequence) u1))
    (release-block (+ block-height lock-duration))
  )
    (asserts! (var-get system-active) ERR_ACCESS_DENIED)
    (asserts! (>= current-portfolio gold-amount) ERR_INSUFFICIENT_HOLDINGS)
    (asserts! (> gold-amount u0) ERR_INVALID_QUANTITY)
    (asserts! (>= lock-duration u1008) ERR_INVALID_QUANTITY) ;; Minimum 7 days lock
    
    ;; Deduct from investor portfolio
    (map-set investor-portfolios tx-sender (- current-portfolio gold-amount))
    
    ;; Create secured treasure vault
    (map-set secured-treasure-vaults vault-id {
      vault-keeper: tx-sender,
      gold-quantity: gold-amount,
      release-block: release-block,
      vault-created: block-height,
      premium-harvested: false
    })
    
    ;; Update sequence counter
    (var-set vault-sequence vault-id)
    
    (print {
      event: "seal-treasure-vault",
      vault-id: vault-id,
      keeper: tx-sender,
      gold-amount: gold-amount,
      release-block: release-block
    })
    
    (ok vault-id)
  )
)

(define-public (open-treasure-vault (vault-id uint))
  (let (
    (vault-details (unwrap! (map-get? secured-treasure-vaults vault-id) ERR_VAULT_NOT_FOUND))
    (current-portfolio (default-to u0 (map-get? investor-portfolios tx-sender)))
  )
    (asserts! (is-eq tx-sender (get vault-keeper vault-details)) ERR_ACCESS_DENIED)
    (asserts! (>= block-height (get release-block vault-details)) ERR_VAULT_SEALED)
    
    ;; Return gold to investor portfolio
    (map-set investor-portfolios tx-sender (+ current-portfolio (get gold-quantity vault-details)))
    
    ;; Remove the vault record
    (map-delete secured-treasure-vaults vault-id)
    
    (print {
      event: "open-treasure-vault",
      vault-id: vault-id,
      keeper: tx-sender,
      recovered-gold: (get gold-quantity vault-details)
    })
    
    (ok (get gold-quantity vault-details))
  )
)

;; Premium Staking Rewards Functions
(define-private (compute-staking-rewards (principal-gold uint) (blocks-staked uint))
  (let (
    (annual-blocks u52560) ;; Approximate blocks per year
    (premium-rate (var-get premium-staking-rate))
  )
    ;; rewards = (principal * rate * blocks_staked) / (annual_blocks * 10000)
    (/ (* (* principal-gold premium-rate) blocks-staked) (* annual-blocks u10000))
  )
)

(define-public (harvest-staking-rewards)
  (let (
    (investor-portfolio (default-to u0 (map-get? investor-portfolios tx-sender)))
    (premium-data (default-to 
      {last-harvest-block: block-height, lifetime-earnings: u0, accumulated-rewards: u0}
      (map-get? investor-premium-tracking tx-sender)
    ))
    (blocks-since-harvest (- block-height (get last-harvest-block premium-data)))
    (earned-premium (compute-staking-rewards investor-portfolio blocks-since-harvest))
  )
    (asserts! (> investor-portfolio u0) ERR_INSUFFICIENT_HOLDINGS)
    (asserts! (> blocks-since-harvest u1008) ERR_INVALID_QUANTITY) ;; Minimum 7 days between harvests
    
    ;; Update investor portfolio with premium rewards
    (map-set investor-portfolios tx-sender (+ investor-portfolio earned-premium))
    
    ;; Update premium tracking
    (map-set investor-premium-tracking tx-sender {
      last-harvest-block: block-height,
      lifetime-earnings: (+ (get lifetime-earnings premium-data) earned-premium),
      accumulated-rewards: u0
    })
    
    ;; Update total tokenized gold (premium increases supply)
    (var-set total-tokenized-gold (+ (var-get total-tokenized-gold) earned-premium))
    
    (print {
      event: "harvest-staking-rewards",
      investor: tx-sender,
      premium-earned: earned-premium,
      blocks-staked: blocks-since-harvest
    })
    
    (ok earned-premium)
  )
)

(define-public (harvest-vault-premium-bonus (vault-id uint))
  (let (
    (vault-details (unwrap! (map-get? secured-treasure-vaults vault-id) ERR_VAULT_NOT_FOUND))
    (blocks-vaulted (- block-height (get vault-created vault-details)))
    (bonus-multiplier u200) ;; 100% bonus for vaulted gold
    (base-premium (compute-staking-rewards (get gold-quantity vault-details) blocks-vaulted))
    (bonus-premium (/ (* base-premium bonus-multiplier) u100))
    (total-premium (+ base-premium bonus-premium))
    (current-portfolio (default-to u0 (map-get? investor-portfolios tx-sender)))
  )
    (asserts! (is-eq tx-sender (get vault-keeper vault-details)) ERR_ACCESS_DENIED)
    (asserts! (not (get premium-harvested vault-details)) ERR_REWARDS_ALREADY_HARVESTED)
    (asserts! (>= block-height (get release-block vault-details)) ERR_VAULT_SEALED)
    
    ;; Add premium to investor portfolio
    (map-set investor-portfolios tx-sender (+ current-portfolio total-premium))
    
    ;; Mark premium as harvested
    (map-set secured-treasure-vaults vault-id 
      (merge vault-details {premium-harvested: true})
    )
    
    ;; Update total tokenized gold
    (var-set total-tokenized-gold (+ (var-get total-tokenized-gold) total-premium))
    
    (print {
      event: "harvest-vault-premium-bonus",
      vault-id: vault-id,
      investor: tx-sender,
      base-premium: base-premium,
      bonus-premium: bonus-premium,
      total-premium: total-premium
    })
    
    (ok total-premium)
  )
)

;; Multi-Guardian Redemption Functions
(define-public (initiate-redemption-order (gold-amount uint) (delivery-address (string-ascii 128)))
  (let (
    (current-portfolio (default-to u0 (map-get? investor-portfolios tx-sender)))
    (order-id (+ (var-get redemption-sequence) u1))
  )
    (asserts! (var-get system-active) ERR_ACCESS_DENIED)
    (asserts! (>= current-portfolio gold-amount) ERR_INSUFFICIENT_HOLDINGS)
    (asserts! (> gold-amount u0) ERR_INVALID_QUANTITY)
    
    ;; Deduct from investor portfolio (escrowed until redemption completes)
    (map-set investor-portfolios tx-sender (- current-portfolio gold-amount))
    
    ;; Create redemption order
    (map-set guardian-redemption-orders order-id {
      order-creator: tx-sender,
      redemption-amount: gold-amount,
      delivery-address: delivery-address,
      guardian-approvals: (list),
      approval-tally: u0,
      order-fulfilled: false,
      order-timestamp: block-height
    })
    
    ;; Update sequence counter
    (var-set redemption-sequence order-id)
    
    (print {
      event: "initiate-redemption-order",
      order-id: order-id,
      creator: tx-sender,
      gold-amount: gold-amount,
      delivery-address: delivery-address
    })
    
    (ok order-id)
  )
)

(define-public (approve-redemption-order (order-id uint))
  (let (
    (order-details (unwrap! (map-get? guardian-redemption-orders order-id) ERR_VAULT_NOT_FOUND))
    (current-approvals (get guardian-approvals order-details))
    (approval-count (get approval-tally order-details))
  )
    (asserts! (is-certified-guardian tx-sender) ERR_ACCESS_DENIED)
    (asserts! (not (get order-fulfilled order-details)) ERR_ACCESS_DENIED)
    
    ;; Check if guardian already approved
    (asserts! (is-none (index-of current-approvals tx-sender)) ERR_DUPLICATE_APPROVAL)
    
    ;; Add guardian approval
    (let (
      (new-approvals (unwrap! (as-max-len? (append current-approvals tx-sender) u15) ERR_INVALID_GUARDIAN))
      (new-approval-count (+ approval-count u1))
    )
      (map-set guardian-redemption-orders order-id
        (merge order-details {
          guardian-approvals: new-approvals,
          approval-tally: new-approval-count
        })
      )
      
      (print {
        event: "approve-redemption-order",
        order-id: order-id,
        guardian: tx-sender,
        approval-count: new-approval-count,
        required-approvals: (var-get minimum-guardian-approvals)
      })
      
      (ok new-approval-count)
    )
  )
)

(define-public (fulfill-redemption-order (order-id uint))
  (let (
    (order-details (unwrap! (map-get? guardian-redemption-orders order-id) ERR_VAULT_NOT_FOUND))
  )
    (asserts! (is-certified-guardian tx-sender) ERR_ACCESS_DENIED)
    (asserts! (not (get order-fulfilled order-details)) ERR_ACCESS_DENIED)
    (asserts! (>= (get approval-tally order-details) (var-get minimum-guardian-approvals)) ERR_INSUFFICIENT_APPROVALS)
    
    ;; Mark order as fulfilled
    (map-set guardian-redemption-orders order-id
      (merge order-details {order-fulfilled: true})
    )
    
    ;; Update total tokenized gold
    (var-set total-tokenized-gold (- (var-get total-tokenized-gold) (get redemption-amount order-details)))
    
    (print {
      event: "fulfill-redemption-order",
      order-id: order-id,
      order-creator: (get order-creator order-details),
      gold-amount: (get redemption-amount order-details),
      delivery-address: (get delivery-address order-details),
      fulfilling-guardian: tx-sender
    })
    
    (ok (get redemption-amount order-details))
  )
)

;; View Functions
(define-read-only (get-investor-portfolio (investor principal))
  (default-to u0 (map-get? investor-portfolios investor))
)

(define-read-only (get-total-tokenized-gold)
  (var-get total-tokenized-gold)
)

(define-read-only (get-treasure-vault-details (vault-id uint))
  (map-get? secured-treasure-vaults vault-id)
)

(define-read-only (get-redemption-order-details (order-id uint))
  (map-get? guardian-redemption-orders order-id)
)

(define-read-only (get-investor-premium-data (investor principal))
  (map-get? investor-premium-tracking investor)
)

(define-read-only (calculate-pending-premium (investor principal))
  (let (
    (investor-portfolio (default-to u0 (map-get? investor-portfolios investor)))
    (premium-data (default-to 
      {last-harvest-block: block-height, lifetime-earnings: u0, accumulated-rewards: u0}
      (map-get? investor-premium-tracking investor)
    ))
    (blocks-since-harvest (- block-height (get last-harvest-block premium-data)))
  )
    (compute-staking-rewards investor-portfolio blocks-since-harvest)
  )
)

(define-read-only (get-vault-system-status)
  {
    total-tokenized-gold: (var-get total-tokenized-gold),
    premium-staking-rate: (var-get premium-staking-rate),
    minimum-guardian-approvals: (var-get minimum-guardian-approvals),
    system-active: (var-get system-active),
    vault-sequence: (var-get vault-sequence),
    redemption-sequence: (var-get redemption-sequence)
  }
)