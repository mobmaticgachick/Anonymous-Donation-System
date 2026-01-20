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
(define-constant err-matching-pool-not-found (err u111))
(define-constant err-matching-pool-inactive (err u112))
(define-constant err-invalid-multiplier (err u113))
(define-constant err-insufficient-pool-balance (err u114))
(define-constant err-duplicate-commitment-hash (err u115))

;; Campaign Errors
(define-constant err-campaign-not-found (err u200))
(define-constant err-campaign-ended (err u201))
(define-constant err-campaign-active (err u202))
(define-constant err-target-not-reached (err u203))
(define-constant err-target-reached (err u204))
(define-constant err-already-claimed (err u205))
(define-constant err-pledge-not-found (err u206))

(define-data-var next-recipient-id uint u1)
(define-data-var next-commitment-id uint u1)
(define-data-var total-donations uint u0)
(define-data-var contract-fee-rate uint u250)
(define-data-var next-matching-pool-id uint u1)

;; Campaign Vars
(define-data-var next-campaign-id uint u1)
(define-data-var total-campaign-funds uint u0)

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

(define-map commitment-index
  { commitment-hash: (buff 32) }
  { commitment-id: uint }
)

(define-map anonymous-balances
  { commitment-hash: (buff 32) }
  { balance: uint }
)

(define-map recipient-withdrawals
  { recipient-id: uint }
  { total-withdrawn: uint }
)

(define-map matching-pools
  { pool-id: uint }
  {
    creator: principal,
    recipient-id: uint,
    multiplier: uint,
    active: bool,
    pool-balance: uint,
    start-block: uint,
    end-block: uint
  }
)

;; Campaign Maps
(define-map campaigns
  { campaign-id: uint }
  {
    recipient-id: uint,
    target-amount: uint,
    raised-amount: uint,
    deadline: uint,
    claimed: bool,
    active: bool
  }
)

(define-map campaign-pledges
  { campaign-id: uint, donor: principal }
  { amount: uint }
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

(define-read-only (get-commitment-by-hash (commitment-hash (buff 32)))
  (match (map-get? commitment-index { commitment-hash: commitment-hash })
    entry (get-commitment (get commitment-id entry))
    none
  )
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

(define-read-only (get-matching-pool (pool-id uint))
  (map-get? matching-pools { pool-id: pool-id })
)

(define-read-only (is-matching-pool-active (pool-id uint))
  (match (get-matching-pool pool-id)
    pool
    (and
      (get active pool)
      (< stacks-block-height (get end-block pool))
      (>= stacks-block-height (get start-block pool))
    )
    false
  )
)

(define-read-only (calculate-matched-amount (pool-id uint) (base-amount uint))
  (match (get-matching-pool pool-id)
    pool
    (if (is-matching-pool-active pool-id)
      (let
        (
          (pool-balance (get pool-balance pool))
          (multiplier (get multiplier pool))
          (match-amount (* base-amount (- multiplier u1)))
        )
        (if (>= pool-balance match-amount)
          match-amount
          u0
        )
      )
      u0
    )
    u0
  )
)

;; Campaign Read-Only
(define-read-only (get-campaign (campaign-id uint))
  (map-get? campaigns { campaign-id: campaign-id })
)

(define-read-only (get-pledge (campaign-id uint) (donor principal))
  (default-to { amount: u0 } (map-get? campaign-pledges { campaign-id: campaign-id, donor: donor }))
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
    (asserts! (is-none (map-get? commitment-index { commitment-hash: commitment-hash })) err-duplicate-commitment-hash)
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
    (map-set commitment-index
      { commitment-hash: commitment-hash }
      { commitment-id: commitment-id }
    )
    (var-set next-commitment-id (+ commitment-id u1))
    (ok commitment-id)
  )
)

(define-public (reveal-and-donate (commitment-id uint) (nonce uint) (amount uint) (pool-id (optional uint)))
  (let
    (
      (commitment-data (unwrap! (get-commitment commitment-id) err-commitment-not-found))
      (expected-hash (sha256 (concat (concat (unwrap-panic (to-consensus-buff? nonce))
                                            (unwrap-panic (to-consensus-buff? amount)))
                                    (unwrap-panic (to-consensus-buff? tx-sender)))))
      (recipient-id (get recipient-id commitment-data))
      (fee-amount (calculate-fee amount))
      (net-amount (- amount fee-amount))
      (match-amount (if (is-some pool-id)
                      (calculate-matched-amount (unwrap-panic pool-id) net-amount)
                      u0
                    ))
      (total-to-recipient (+ net-amount match-amount))
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
          (merge recipient { total-received: (+ (get total-received recipient) total-to-recipient) })
        )

        (if (> match-amount u0)
          (let
            (
              (pool-id-val (unwrap-panic pool-id))
              (pool-data (unwrap-panic (get-matching-pool pool-id-val)))
            )
            (map-set matching-pools
              { pool-id: pool-id-val }
              (merge pool-data { pool-balance: (- (get pool-balance pool-data) match-amount) })
            )
          )
          true
        )

        (var-set total-donations (+ (var-get total-donations) amount))

        (ok total-to-recipient)
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

(define-public (anonymous-donate (commitment-hash (buff 32)) (recipient-id uint) (amount uint) (reveal-nonce uint) (pool-id (optional uint)))
  (let
    (
      (current-balance (get-anonymous-balance commitment-hash))
      (expected-hash (sha256 (concat (unwrap-panic (to-consensus-buff? reveal-nonce))
                                    (unwrap-panic (to-consensus-buff? amount)))))
      (fee-amount (calculate-fee amount))
      (net-amount (- amount fee-amount))
      (match-amount (if (is-some pool-id)
                      (calculate-matched-amount (unwrap-panic pool-id) net-amount)
                      u0
                    ))
      (total-to-recipient (+ net-amount match-amount))
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
          (merge recipient { total-received: (+ (get total-received recipient) total-to-recipient) })
        )

        (if (> match-amount u0)
          (let
            (
              (pool-id-val (unwrap-panic pool-id))
              (pool-data (unwrap-panic (get-matching-pool pool-id-val)))
            )
            (map-set matching-pools
              { pool-id: pool-id-val }
              (merge pool-data { pool-balance: (- (get pool-balance pool-data) match-amount) })
            )
          )
          true
        )

        (var-set total-donations (+ (var-get total-donations) amount))

        (ok total-to-recipient)
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

(define-public (create-matching-pool (recipient-id uint) (multiplier uint) (pool-amount uint) (duration-blocks uint))
  (let
    (
      (pool-id (var-get next-matching-pool-id))
      (start-block stacks-block-height)
      (end-block (+ stacks-block-height duration-blocks))
    )
    (asserts! (is-some (get-recipient recipient-id)) err-recipient-not-found)
    (asserts! (and (>= multiplier u2) (<= multiplier u10)) err-invalid-multiplier)
    (asserts! (> pool-amount u0) err-invalid-amount)

    (try! (stx-transfer? pool-amount tx-sender (as-contract tx-sender)))

    (map-set matching-pools
      { pool-id: pool-id }
      {
        creator: tx-sender,
        recipient-id: recipient-id,
        multiplier: multiplier,
        active: true,
        pool-balance: pool-amount,
        start-block: start-block,
        end-block: end-block
      }
    )

    (var-set next-matching-pool-id (+ pool-id u1))

    (ok pool-id)
  )
)

(define-public (deactivate-matching-pool (pool-id uint))
  (match (get-matching-pool pool-id)
    pool
    (begin
      (asserts! (is-eq tx-sender (get creator pool)) err-owner-only)

      (map-set matching-pools
        { pool-id: pool-id }
        (merge pool { active: false })
      )

      (ok true)
    )
    err-matching-pool-not-found
  )
)

(define-public (refund-matching-pool (pool-id uint))
  (match (get-matching-pool pool-id)
    pool
    (let
      (
        (remaining-balance (get pool-balance pool))
      )
      (asserts! (is-eq tx-sender (get creator pool)) err-owner-only)
      (asserts! (not (get active pool)) err-matching-pool-inactive)
      (asserts! (> remaining-balance u0) err-insufficient-pool-balance)

      (try! (as-contract (stx-transfer? remaining-balance tx-sender (get creator pool))))

      (map-set matching-pools
        { pool-id: pool-id }
        (merge pool { pool-balance: u0 })
      )

      (ok remaining-balance)
    )
    err-matching-pool-not-found
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

;; Campaign Functions

(define-public (create-campaign (recipient-id uint) (target-amount uint) (duration uint))
  (let
    (
      (campaign-id (var-get next-campaign-id))
      (recipient (unwrap! (get-recipient recipient-id) err-recipient-not-found))
    )
    (asserts! (is-eq tx-sender (get owner recipient)) err-owner-only)
    (asserts! (> target-amount u0) err-invalid-amount)
    (asserts! (> duration u0) err-invalid-amount)

    (map-set campaigns
      { campaign-id: campaign-id }
      {
        recipient-id: recipient-id,
        target-amount: target-amount,
        raised-amount: u0,
        deadline: (+ stacks-block-height duration),
        claimed: false,
        active: true
      }
    )

    (var-set next-campaign-id (+ campaign-id u1))
    (ok campaign-id)
  )
)

(define-public (pledge-to-campaign (campaign-id uint) (amount uint))
  (let
    (
      (campaign (unwrap! (get-campaign campaign-id) err-campaign-not-found))
      (current-pledge (get-pledge campaign-id tx-sender))
    )
    (asserts! (get active campaign) err-campaign-ended)
    (asserts! (< stacks-block-height (get deadline campaign)) err-campaign-ended)
    (asserts! (> amount u0) err-invalid-amount)

    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))

    (map-set campaign-pledges
      { campaign-id: campaign-id, donor: tx-sender }
      { amount: (+ (get amount current-pledge) amount) }
    )

    (map-set campaigns
      { campaign-id: campaign-id }
      (merge campaign { raised-amount: (+ (get raised-amount campaign) amount) })
    )

    (var-set total-campaign-funds (+ (var-get total-campaign-funds) amount))

    (ok true)
  )
)

(define-public (claim-campaign-funds (campaign-id uint))
  (let
    (
      (campaign (unwrap! (get-campaign campaign-id) err-campaign-not-found))
      (recipient (unwrap! (get-recipient (get recipient-id campaign)) err-recipient-not-found))
    )
    (asserts! (is-eq tx-sender (get owner recipient)) err-owner-only)
    (asserts! (>= (get raised-amount campaign) (get target-amount campaign)) err-target-not-reached)
    (asserts! (not (get claimed campaign)) err-already-claimed)

    (try! (as-contract (stx-transfer? (get raised-amount campaign) tx-sender (get owner recipient))))

    (map-set campaigns
      { campaign-id: campaign-id }
      (merge campaign { claimed: true, active: false })
    )

    (var-set total-campaign-funds (- (var-get total-campaign-funds) (get raised-amount campaign)))

    (ok (get raised-amount campaign))
  )
)

(define-public (refund-pledge (campaign-id uint))
  (let
    (
      (campaign (unwrap! (get-campaign campaign-id) err-campaign-not-found))
      (pledge (get-pledge campaign-id tx-sender))
    )
    (asserts! (>= stacks-block-height (get deadline campaign)) err-campaign-active)
    (asserts! (< (get raised-amount campaign) (get target-amount campaign)) err-target-reached)
    (asserts! (> (get amount pledge) u0) err-pledge-not-found)

    (try! (as-contract (stx-transfer? (get amount pledge) tx-sender tx-sender)))

    (map-set campaign-pledges
      { campaign-id: campaign-id, donor: tx-sender }
      { amount: u0 }
    )

    (var-set total-campaign-funds (- (var-get total-campaign-funds) (get amount pledge)))

    (ok (get amount pledge))
  )
)

(define-public (collect-fees)
  (let
    (
      (contract-balance (stx-get-balance (as-contract tx-sender)))
      (total-recipient-balances (fold calculate-total-recipient-balances (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10) u0))
      (campaign-funds (var-get total-campaign-funds))
      (available-fees (- contract-balance (+ total-recipient-balances campaign-funds)))
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
