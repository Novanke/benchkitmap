///|
test "purchase mixes pack sizes to minimize price" {
  let purchase = recommend_purchase(13, [
    { id: "four", quantity: 4, cost_cents: 320, },
    { id: "five", quantity: 5, cost_cents: 370, },
    { id: "seven", quantity: 7, cost_cents: 690, },
  ]).unwrap()
  assert_eq(
    (purchase.shortage, purchase.ordered, purchase.cost_cents),
    (13, 13, 1010L),
  )
  assert_eq(purchase.packs.map(fn(pack) { (pack.id, pack.count) }), [
    ("four", 2),
    ("five", 1),
  ])
}

///|
test "purchase tie order is excess, count, then declaration order" {
  let exact = recommend_purchase(3, [
    { id: "extra", quantity: 5, cost_cents: 7, },
    { id: "exact", quantity: 3, cost_cents: 7, },
  ]).unwrap()
  assert_eq(exact.ordered, 3)
  let fewer = recommend_purchase(6, [
    { id: "small", quantity: 2, cost_cents: 4, },
    { id: "large", quantity: 6, cost_cents: 12, },
  ]).unwrap()
  assert_eq(fewer.packs.map(fn(pack) { (pack.id, pack.count) }), [("large", 1)])
  let declared = recommend_purchase(6, [
    { id: "z", quantity: 2, cost_cents: 4, },
    { id: "a", quantity: 3, cost_cents: 6, },
    { id: "large", quantity: 4, cost_cents: 8, },
  ]).unwrap()
  assert_eq(declared.packs.map(fn(pack) { (pack.id, pack.count) }), [
    ("z", 1),
    ("large", 1),
  ])
}

///|
test "purchase uses a closed form and preserves exact large prices" {
  let purchase = recommend_purchase(1_000_000, [
    { id: "each", quantity: 1, cost_cents: 1_000_000_000, },
  ]).unwrap()
  assert_eq(purchase.ordered, 1_000_000)
  assert_eq(purchase.cost_cents, 1_000_000_000_000_000L)
  assert_eq(purchase.packs[0].count, 1_000_000)
  let scaled = recommend_purchase(100_001, [
    { id: "ten", quantity: 10_000, cost_cents: 30, },
    { id: "twentyfive", quantity: 25_000, cost_cents: 70, },
  ]).unwrap()
  assert_eq((scaled.ordered, scaled.cost_cents), (105_000, 300L))
}

///|
test "purchase validates even when no order is needed" {
  assert_true(recommend_purchase(0, []) is None)
  assert_true(recommend_purchase(1, []) is None)
  let malformed : Array[Array[PackOption]] = [
    [{ id: "zero", quantity: 0, cost_cents: 0, }],
    [{ id: "negative", quantity: 1, cost_cents: -1, }],
    [{ id: "large", quantity: 1_000_001, cost_cents: 0, }],
    [{ id: "large", quantity: 1, cost_cents: 1_000_000_001, }],
    [{ id: "", quantity: 1, cost_cents: 0, }],
    [
      { id: "duplicate", quantity: 1, cost_cents: 0, },
      { id: "duplicate", quantity: 2, cost_cents: 0, },
    ],
  ]
  for options in malformed {
    let failed = try {
      ignore(recommend_purchase(0, options))
      false
    } catch {
      Invalid(_) => true
    }
    assert_true(failed)
  }
  let over_budget = try {
    ignore(
      recommend_purchase(100_000, [
        { id: "each", quantity: 1, cost_cents: 1, },
        { id: "pair", quantity: 2, cost_cents: 1, },
      ]),
    )
    false
  } catch {
    Invalid(message) => message.contains("100,000 states")
  }
  assert_true(over_budget)
}

///|
test "purchase scores agree with an exhaustive small integer oracle" {
  for seed in 0..<64 {
    let shortage = seed % 10 + 1
    let size_a = seed % 5 + 1
    let size_b = seed / 3 % 5 + 1
    let price_a = seed * 13 % 11
    let price_b = (seed * 7 + 3) % 13
    let result = recommend_purchase(shortage, [
      { id: "a", quantity: size_a, cost_cents: price_a, },
      { id: "b", quantity: size_b, cost_cents: price_b, },
    ]).unwrap()
    let mut best_cost = 1000
    let mut best_order = 0
    let mut best_count = 0
    let mut best_a = 0
    for a in 0..<(shortage + 1) {
      for b in 0..<(shortage + 1) {
        let order = a * size_a + b * size_b
        let cost = a * price_a + b * price_b
        let count = a + b
        if order >= shortage &&
          (
            cost < best_cost ||
            (cost == best_cost && order < best_order) ||
            (cost == best_cost && order == best_order && count < best_count) ||
            (
              cost == best_cost &&
              order == best_order &&
              count == best_count &&
              a > best_a
            )
          ) {
          best_cost = cost
          best_order = order
          best_count = count
          best_a = a
        }
      }
    }
    let mut actual_a = 0
    let mut actual_count = 0
    let mut actual_order = 0
    let mut actual_cost = 0
    for pack in result.packs {
      if pack.id == "a" {
        actual_a = pack.count
      }
      actual_count += pack.count
      actual_order += pack.quantity * pack.count
      actual_cost += pack.unit_cost_cents * pack.count
    }
    assert_eq(result.cost_cents, best_cost.to_int64())
    assert_eq(result.ordered, best_order)
    assert_eq(
      (actual_cost, actual_order, actual_count, actual_a),
      (best_cost, best_order, best_count, best_a),
    )
  }
}
