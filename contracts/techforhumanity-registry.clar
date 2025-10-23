(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-exists (err u102))
(define-constant err-unauthorized (err u103))
(define-constant err-invalid-input (err u104))
(define-constant err-insufficient-funds (err u105))
(define-constant err-innovation-locked (err u106))

(define-data-var innovation-id-nonce uint u1)
(define-data-var organization-id-nonce uint u1)
(define-data-var collaboration-id-nonce uint u1)
(define-data-var total-funding uint u0)

(define-map innovators principal
  {
    name: (string-ascii 50),
    expertise: (string-ascii 100),
    reputation-score: uint,
    innovations-count: uint,
    registered-at: uint
  })

(define-map organizations uint
  {
    name: (string-ascii 100),
    focus-area: (string-ascii 100),
    founder: principal,
    members-count: uint,
    total-contributions: uint,
    created-at: uint,
    active: bool
  })

(define-map innovations uint
  {
    title: (string-ascii 200),
    description: (string-ascii 500),
    category: (string-ascii 50),
    humanitarian-impact: (string-ascii 300),
    creator: principal,
    organization-id: (optional uint),
    funding-goal: uint,
    current-funding: uint,
    backers-count: uint,
    innovation-score: uint,
    development-stage: (string-ascii 30),
    open-source: bool,
    created-at: uint,
    last-updated: uint,
    verified: bool,
    completed: bool
  })

(define-map innovation-backers {innovation-id: uint, backer: principal}
  {
    amount: uint,
    backed-at: uint,
    message: (optional (string-ascii 200))
  })

(define-map collaborations uint
  {
    innovation-id: uint,
    collaborator: principal,
    contribution-type: (string-ascii 50),
    description: (string-ascii 300),
    status: (string-ascii 20),
    proposed-at: uint,
    accepted-at: (optional uint)
  })

(define-map innovation-reviews {innovation-id: uint, reviewer: principal}
  {
    score: uint,
    feedback: (string-ascii 400),
    reviewed-at: uint
  })

(define-map humanitarian-metrics uint
  {
    lives-impacted: uint,
    communities-served: uint,
    sustainability-score: uint,
    scalability-potential: uint,
    verified-impact: bool,
    last-assessment: uint
  })

(define-public (register-innovator (name (string-ascii 50)) (expertise (string-ascii 100)))
  (let ((caller tx-sender))
    (asserts! (is-none (map-get? innovators caller)) err-already-exists)
    (ok (map-set innovators caller {
      name: name,
      expertise: expertise,
      reputation-score: u0,
      innovations-count: u0,
      registered-at: stacks-block-height
    }))))

(define-public (create-organization (name (string-ascii 100)) (focus-area (string-ascii 100)))
  (let (
    (org-id (var-get organization-id-nonce))
    (caller tx-sender)
  )
    (map-set organizations org-id {
      name: name,
      focus-area: focus-area,
      founder: caller,
      members-count: u1,
      total-contributions: u0,
      created-at: stacks-block-height,
      active: true
    })
    (var-set organization-id-nonce (+ org-id u1))
    (ok org-id)))

(define-public (submit-innovation 
  (title (string-ascii 200))
  (description (string-ascii 500))
  (category (string-ascii 50))
  (humanitarian-impact (string-ascii 300))
  (funding-goal uint)
  (development-stage (string-ascii 30))
  (open-source bool)
  (organization-id (optional uint)))
  (let (
    (innovation-id (var-get innovation-id-nonce))
    (caller tx-sender)
  )
    (asserts! (is-some (map-get? innovators caller)) err-unauthorized)
    (asserts! (> funding-goal u0) err-invalid-input)
    (map-set innovations innovation-id {
      title: title,
      description: description,
      category: category,
      humanitarian-impact: humanitarian-impact,
      creator: caller,
      organization-id: organization-id,
      funding-goal: funding-goal,
      current-funding: u0,
      backers-count: u0,
      innovation-score: u0,
      development-stage: development-stage,
      open-source: open-source,
      created-at: stacks-block-height,
      last-updated: stacks-block-height,
      verified: false,
      completed: false
    })
    (map-set humanitarian-metrics innovation-id {
      lives-impacted: u0,
      communities-served: u0,
      sustainability-score: u0,
      scalability-potential: u0,
      verified-impact: false,
      last-assessment: stacks-block-height
    })
    (let ((innovator (unwrap-panic (map-get? innovators caller))))
      (map-set innovators caller (merge innovator {innovations-count: (+ (get innovations-count innovator) u1)})))
    (var-set innovation-id-nonce (+ innovation-id u1))
    (ok innovation-id)))

(define-public (back-innovation (innovation-id uint) (amount uint) (message (optional (string-ascii 200))))
  (let (
    (caller tx-sender)
    (innovation (unwrap! (map-get? innovations innovation-id) err-not-found))
  )
    (asserts! (is-some (map-get? innovators caller)) err-unauthorized)
    (asserts! (> amount u0) err-invalid-input)
    (asserts! (not (get completed innovation)) err-innovation-locked)
    (try! (stx-transfer? amount caller (as-contract tx-sender)))
    (map-set innovation-backers {innovation-id: innovation-id, backer: caller} {
      amount: amount,
      backed-at: stacks-block-height,
      message: message
    })
    (map-set innovations innovation-id (merge innovation {
      current-funding: (+ (get current-funding innovation) amount),
      backers-count: (+ (get backers-count innovation) u1),
      last-updated: stacks-block-height
    }))
    (var-set total-funding (+ (var-get total-funding) amount))
    (ok true)))

(define-public (propose-collaboration (innovation-id uint) (contribution-type (string-ascii 50)) (description (string-ascii 300)))
  (let (
    (collaboration-id (var-get collaboration-id-nonce))
    (caller tx-sender)
    (innovation (unwrap! (map-get? innovations innovation-id) err-not-found))
  )
    (asserts! (is-some (map-get? innovators caller)) err-unauthorized)
    (asserts! (not (is-eq caller (get creator innovation))) err-invalid-input)
    (map-set collaborations collaboration-id {
      innovation-id: innovation-id,
      collaborator: caller,
      contribution-type: contribution-type,
      description: description,
      status: "proposed",
      proposed-at: stacks-block-height,
      accepted-at: none
    })
    (var-set collaboration-id-nonce (+ collaboration-id u1))
    (ok collaboration-id)))

(define-public (accept-collaboration (collaboration-id uint))
  (let (
    (collaboration (unwrap! (map-get? collaborations collaboration-id) err-not-found))
    (innovation (unwrap! (map-get? innovations (get innovation-id collaboration)) err-not-found))
    (caller tx-sender)
  )
    (asserts! (is-eq caller (get creator innovation)) err-unauthorized)
    (asserts! (is-eq (get status collaboration) "proposed") err-invalid-input)
    (map-set collaborations collaboration-id (merge collaboration {
      status: "accepted",
      accepted-at: (some stacks-block-height)
    }))
    (ok true)))

(define-public (review-innovation (innovation-id uint) (score uint) (feedback (string-ascii 400)))
  (let (
    (caller tx-sender)
    (innovation (unwrap! (map-get? innovations innovation-id) err-not-found))
  )
    (asserts! (is-some (map-get? innovators caller)) err-unauthorized)
    (asserts! (and (>= score u1) (<= score u10)) err-invalid-input)
    (asserts! (not (is-eq caller (get creator innovation))) err-invalid-input)
    (map-set innovation-reviews {innovation-id: innovation-id, reviewer: caller} {
      score: score,
      feedback: feedback,
      reviewed-at: stacks-block-height
    })
    (let ((current-score (get innovation-score innovation)))
      (map-set innovations innovation-id (merge innovation {
        innovation-score: (if (is-eq current-score u0) score (/ (+ current-score score) u2)),
        last-updated: stacks-block-height
      })))
    (ok true)))

(define-public (update-humanitarian-impact 
  (innovation-id uint)
  (lives-impacted uint)
  (communities-served uint)
  (sustainability-score uint)
  (scalability-potential uint))
  (let (
    (caller tx-sender)
    (innovation (unwrap! (map-get? innovations innovation-id) err-not-found))
  )
    (asserts! (is-eq caller (get creator innovation)) err-unauthorized)
    (asserts! (and (<= sustainability-score u100) (<= scalability-potential u100)) err-invalid-input)
    (map-set humanitarian-metrics innovation-id {
      lives-impacted: lives-impacted,
      communities-served: communities-served,
      sustainability-score: sustainability-score,
      scalability-potential: scalability-potential,
      verified-impact: false,
      last-assessment: stacks-block-height
    })
    (ok true)))

(define-public (verify-innovation (innovation-id uint))
  (let ((innovation (unwrap! (map-get? innovations innovation-id) err-not-found)))
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set innovations innovation-id (merge innovation {
      verified: true,
      last-updated: stacks-block-height
    }))
    (let ((metrics (unwrap-panic (map-get? humanitarian-metrics innovation-id))))
      (map-set humanitarian-metrics innovation-id (merge metrics {verified-impact: true})))
    (ok true)))

(define-public (mark-innovation-complete (innovation-id uint))
  (let (
    (innovation (unwrap! (map-get? innovations innovation-id) err-not-found))
    (caller tx-sender)
  )
    (asserts! (is-eq caller (get creator innovation)) err-unauthorized)
    (asserts! (get verified innovation) err-unauthorized)
    (map-set innovations innovation-id (merge innovation {
      completed: true,
      last-updated: stacks-block-height
    }))
    (let ((innovator (unwrap-panic (map-get? innovators caller))))
      (map-set innovators caller (merge innovator {
        reputation-score: (+ (get reputation-score innovator) u10)
      })))
    (ok true)))

(define-public (deactivate-organization (org-id uint))
  (let ((org (unwrap! (map-get? organizations org-id) err-not-found)))
    (asserts! (is-eq tx-sender (get founder org)) err-unauthorized)
    (map-set organizations org-id (merge org {active: false}))
    (ok true)))

(define-read-only (get-innovator (innovator principal))
  (map-get? innovators innovator))

(define-read-only (get-organization (org-id uint))
  (map-get? organizations org-id))

(define-read-only (get-innovation (innovation-id uint))
  (map-get? innovations innovation-id))

(define-read-only (get-innovation-backing (innovation-id uint) (backer principal))
  (map-get? innovation-backers {innovation-id: innovation-id, backer: backer}))

(define-read-only (get-collaboration (collaboration-id uint))
  (map-get? collaborations collaboration-id))

(define-read-only (get-innovation-review (innovation-id uint) (reviewer principal))
  (map-get? innovation-reviews {innovation-id: innovation-id, reviewer: reviewer}))

(define-read-only (get-humanitarian-metrics (innovation-id uint))
  (map-get? humanitarian-metrics innovation-id))

(define-read-only (get-platform-stats)
  {
    total-innovations: (- (var-get innovation-id-nonce) u1),
    total-organizations: (- (var-get organization-id-nonce) u1),
    total-collaborations: (- (var-get collaboration-id-nonce) u1),
    total-funding: (var-get total-funding),
    contract-owner: contract-owner
  })

(define-read-only (get-innovation-funding-progress (innovation-id uint))
  (match (map-get? innovations innovation-id)
    innovation (some {
      funding-goal: (get funding-goal innovation),
      current-funding: (get current-funding innovation),
      funding-percentage: (if (> (get funding-goal innovation) u0)
        (/ (* (get current-funding innovation) u100) (get funding-goal innovation))
        u0),
      backers-count: (get backers-count innovation)
    })
    none))
