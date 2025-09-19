(define-constant contract-owner tx-sender)

(define-constant err-owner-only (err u100))
(define-constant err-invalid-amount (err u101))
(define-constant err-recipient-not-found (err u102))
(define-constant err-insufficient-balance (err u103))
(define-constant err-transfer-failed (err u104))
(define-constant err-already-registered (err u105))
(define-constant err-invalid-commitment (err u106))
(define-constant err-commitment-not-found (err u107))
(define-constant err-already-revealed (err u108))
(define-constant err-invalid-reveal (err u109))
(define-constant err-reveal-period-ended (err u110))

(define-data-var next-recipient-id uint u1)
(define-data-var next-commitment-id uint u1)
(define-data-var total-donations uint u0)
(define-data-var contract-fee-rate uint u250)

(define-map recipients
  { recipient-id: uint }
  {
    owner: principal,
    name: (string-ascii 64),
    description: (string-ascii 256),
    total-received: uint,
    active: bool
  }
)

(define-map recipient-by-owner
  { owner: principal }
  { recipient-id: uint }
)

(define-map donation-commitments
  { commitment-id: uint }
  {
    commitment-hash: (buff 32),
    stacks-block-height: uint,
    revealed: bool,
    recipient-id: uint,
    amount: uint
  }
)

(define-map anonymous-balances
  { commitment-hash: (buff 32) }
  { balance: uint }
)

(define-map recipient-withdrawals
  { recipient-id: uint }
  { total-withdrawn: uint }
)

(define-read-only (get-recipient (recipient-id uint))
  (map-get? recipients { recipient-id: recipient-id })
)

(define-read-only (get-recipient-by-owner (owner principal))
  (match (map-get? recipient-by-owner { owner: owner })
    entry (get-recipient (get recipient-id entry))
    none
  )
)

(define-read-only (get-total-donations)
  (var-get total-donations)
)

(define-read-only (get-contract-fee-rate)
  (var-get contract-fee-rate)
)

(define-read-only (get-commitment (commitment-id uint))
  (map-get? donation-commitments { commitment-id: commitment-id })
)

(define-read-only (get-anonymous-balance (commitment-hash (buff 32)))
  (default-to u0 (get balance (map-get? anonymous-balances { commitment-hash: commitment-hash })))
)

(define-read-only (get-recipient-total-withdrawn (recipient-id uint))
  (default-to u0 (get total-withdrawn (map-get? recipient-withdrawals { recipient-id: recipient-id })))
)

(define-read-only (calculate-fee (amount uint))
  (/ (* amount (var-get contract-fee-rate)) u10000)
)

(define-read-only (get-available-balance (recipient-id uint))
  (match (get-recipient recipient-id)
    recipient
    (let
      (
        (total-received (get total-received recipient))
        (total-withdrawn (get-recipient-total-withdrawn recipient-id))
      )
      (- total-received total-withdrawn)
    )
    u0
  )
)

(define-public (register-recipient (name (string-ascii 64)) (description (string-ascii 256)))
  (let
    (
      (recipient-id (var-get next-recipient-id))
      (caller tx-sender)
    )
    (asserts! (is-none (map-get? recipient-by-owner { owner: caller })) err-already-registered)
    
    (map-set recipients
      { recipient-id: recipient-id }
      {
        owner: caller,
        name: name,
        description: description,
        total-received: u0,
        active: true
      }
    )
    
    (map-set recipient-by-owner
      { owner: caller }
      { recipient-id: recipient-id }
    )
    
    (var-set next-recipient-id (+ recipient-id u1))
    
    (ok recipient-id)
  )
)

(define-public (update-recipient-status (recipient-id uint) (active bool))
  (match (get-recipient recipient-id)
    recipient
    (begin
      (asserts! (is-eq tx-sender (get owner recipient)) err-owner-only)
      
      (map-set recipients
        { recipient-id: recipient-id }
        (merge recipient { active: active })
      )
      
      (ok true)
    )
    err-recipient-not-found
  )
)

(define-public (commit-donation (commitment-hash (buff 32)) (recipient-id uint))
  (let
    (
      (commitment-id (var-get next-commitment-id))
    )
    (asserts! (is-some (get-recipient recipient-id)) err-recipient-not-found)
    (asserts! (is-none (map-get? donation-commitments { commitment-id: commitment-id })) err-invalid-commitment)
    
    (map-set donation-commitments
      { commitment-id: commitment-id }
      {
        commitment-hash: commitment-hash,
        stacks-block-height: stacks-block-height,
        revealed: false,
        recipient-id: recipient-id,
        amount: u0
      }
    )
    
    (var-set next-commitment-id (+ commitment-id u1))
    
    (ok commitment-id)
  )
)

(define-public (reveal-and-donate (commitment-id uint) (nonce uint) (amount uint))
  (let
    (
      (commitment-data (unwrap! (get-commitment commitment-id) err-commitment-not-found))
      (expected-hash (sha256 (concat (concat (unwrap-panic (to-consensus-buff? nonce)) 
                                            (unwrap-panic (to-consensus-buff? amount)))
                                    (unwrap-panic (to-consensus-buff? tx-sender)))))
      (recipient-id (get recipient-id commitment-data))
      (fee-amount (calculate-fee amount))
      (net-amount (- amount fee-amount))
    )
    (asserts! (not (get revealed commitment-data)) err-already-revealed)
    (asserts! (is-eq expected-hash (get commitment-hash commitment-data)) err-invalid-reveal)
    (asserts! (< (- stacks-block-height (get stacks-block-height commitment-data)) u100) err-reveal-period-ended)
    (asserts! (> amount u0) err-invalid-amount)
    
    (match (get-recipient recipient-id)
      recipient
      (begin
        (asserts! (get active recipient) err-recipient-not-found)
        
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        
        (map-set donation-commitments
          { commitment-id: commitment-id }
          (merge commitment-data { revealed: true, amount: amount })
        )
        
        (map-set recipients
          { recipient-id: recipient-id }
          (merge recipient { total-received: (+ (get total-received recipient) net-amount) })
        )
        
        (var-set total-donations (+ (var-get total-donations) amount))
        
        (ok net-amount)
      )
      err-recipient-not-found
    )
  )
)

(define-public (deposit-anonymous (commitment-hash (buff 32)) (amount uint))
  (begin
    (asserts! (> amount u0) err-invalid-amount)
    
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    (map-set anonymous-balances
      { commitment-hash: commitment-hash }
      { balance: (+ (get-anonymous-balance commitment-hash) amount) }
    )
    
    (ok true)
  )
)

(define-public (anonymous-donate (commitment-hash (buff 32)) (recipient-id uint) (amount uint) (reveal-nonce uint))
  (let
    (
      (current-balance (get-anonymous-balance commitment-hash))
      (expected-hash (sha256 (concat (unwrap-panic (to-consensus-buff? reveal-nonce))
                                    (unwrap-panic (to-consensus-buff? amount)))))
      (fee-amount (calculate-fee amount))
      (net-amount (- amount fee-amount))
    )
    (asserts! (>= current-balance amount) err-insufficient-balance)
    (asserts! (> amount u0) err-invalid-amount)
    (asserts! (is-eq commitment-hash expected-hash) err-invalid-reveal)
    
    (match (get-recipient recipient-id)
      recipient
      (begin
        (asserts! (get active recipient) err-recipient-not-found)
        
        (map-set anonymous-balances
          { commitment-hash: commitment-hash }
          { balance: (- current-balance amount) }
        )
        
        (map-set recipients
          { recipient-id: recipient-id }
          (merge recipient { total-received: (+ (get total-received recipient) net-amount) })
        )
        
        (var-set total-donations (+ (var-get total-donations) amount))
        
        (ok net-amount)
      )
      err-recipient-not-found
    )
  )
)

(define-public (withdraw-donations (recipient-id uint) (amount uint))
  (match (get-recipient recipient-id)
    recipient
    (let
      (
        (available-balance (get-available-balance recipient-id))
        (current-withdrawn (get-recipient-total-withdrawn recipient-id))
      )
      (asserts! (is-eq tx-sender (get owner recipient)) err-owner-only)
      (asserts! (>= available-balance amount) err-insufficient-balance)
      (asserts! (> amount u0) err-invalid-amount)
      
      (try! (as-contract (stx-transfer? amount tx-sender (get owner recipient))))
      
      (map-set recipient-withdrawals
        { recipient-id: recipient-id }
        { total-withdrawn: (+ current-withdrawn amount) }
      )
      
      (ok amount)
    )
    err-recipient-not-found
  )
)

(define-public (withdraw-anonymous-balance (commitment-hash (buff 32)) (amount uint) (reveal-nonce uint))
  (let
    (
      (current-balance (get-anonymous-balance commitment-hash))
      (expected-hash (sha256 (concat (unwrap-panic (to-consensus-buff? reveal-nonce))
                                    (unwrap-panic (to-consensus-buff? amount)))))
    )
    (asserts! (>= current-balance amount) err-insufficient-balance)
    (asserts! (> amount u0) err-invalid-amount)
    (asserts! (is-eq commitment-hash expected-hash) err-invalid-reveal)
    
    (map-set anonymous-balances
      { commitment-hash: commitment-hash }
      { balance: (- current-balance amount) }
    )
    
    (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
    
    (ok amount)
  )
)

(define-public (set-fee-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (<= new-rate u1000) err-invalid-amount)
    
    (var-set contract-fee-rate new-rate)
    
    (ok new-rate)
  )
)

(define-public (collect-fees)
  (let
    (
      (contract-balance (stx-get-balance (as-contract tx-sender)))
      (total-recipient-balances (fold calculate-total-recipient-balances (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10) u0))
      (available-fees (- contract-balance total-recipient-balances))
    )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (> available-fees u0) err-insufficient-balance)
    
    (try! (as-contract (stx-transfer? available-fees tx-sender contract-owner)))
    
    (ok available-fees)
  )
)

(define-private (calculate-total-recipient-balances (recipient-id uint) (acc uint))
  (+ acc (get-available-balance recipient-id))
)
