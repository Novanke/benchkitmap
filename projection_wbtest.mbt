///|
test "partial purchasing reruns priorities without inventing unpriced stock" {
  let input : Manifest = {
    parts: [
      { id: "board", stock: 1, packs: [], },
      {
        id: "sensor",
        stock: 0,
        packs: [{ id: "single", quantity: 1, cost_cents: 115, }],
      },
    ],
    kits: [
      {
        id: "instrument",
        items: [
          { item: "board", quantity: 1, },
          { item: "sensor", quantity: 1, },
        ],
      },
      { id: "practice", items: [{ item: "board", quantity: 1, }], },
    ],
    orders: [
      { id: "priority", kit: "instrument", quantity: 1, },
      { id: "later", kit: "practice", quantity: 1, },
    ],
  }
  let result = project_after_purchase(input)
  assert_false(result.purchase_complete)
  assert_eq(result.purchase_total_cents, 115L)
  assert_eq(result.orders.length(), 2)
  assert_eq(result.orders[0].id, "priority")
  assert_eq(result.orders[0].buildable_now, 0)
  assert_eq(result.orders[0].buildable_after_priced_purchases, 1)
  assert_eq(result.orders[1].id, "later")
  assert_eq(result.orders[1].buildable_now, 1)
  assert_eq(result.orders[1].buildable_after_priced_purchases, 0)
  assert_eq(input.parts[0].stock, 1)
  assert_eq(input.parts[1].stock, 0)
}

///|
test "all sourced demand remains covered when a pack exceeds the stock limit" {
  let input : Manifest = {
    parts: [
      {
        id: "bolt",
        stock: 999_999,
        packs: [{ id: "pair", quantity: 2, cost_cents: 125, }],
      },
    ],
    kits: [{ id: "bundle", items: [{ item: "bolt", quantity: 1, }], }],
    orders: [
      { id: "first", kit: "bundle", quantity: 999_998, },
      { id: "last", kit: "bundle", quantity: 2, },
    ],
  }
  let result = project_after_purchase(input)
  assert_true(result.purchase_complete)
  assert_eq(result.purchase_total_cents, 125L)
  assert_eq(result.orders[0].buildable_now, 999_998)
  assert_eq(result.orders[0].buildable_after_priced_purchases, 999_998)
  assert_eq(result.orders[1].requested, 2)
  assert_eq(result.orders[1].buildable_now, 1)
  assert_eq(result.orders[1].buildable_after_priced_purchases, 2)
}
