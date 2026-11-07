///|
test "reject duplicate keys, fractions disguised by floating rounding and typos" {
  for
    stock in [
      "\"stock\":0,\"stock\":1", "\"stock\":1.000000000000000000000001", "\"stock\":1e0",
      "\"stock\":1000001", "\"stcok\":1",
    ] {
    let prefix = "{\"schema\":\"benchkitmap/v1\",\"parts\":[{\"id\":\"wire\","
    let suffix = ",\"packs\":[]}],\"kits\":[{\"id\":\"a\",\"items\":[{\"item\":\"wire\",\"quantity\":1}]}],\"orders\":[{\"id\":\"o\",\"kit\":\"a\",\"quantity\":1}]}"
    let manifest = prefix + stock + suffix
    let rejected = try {
      ignore(parse_manifest(manifest))
      false
    } catch {
      Invalid(_) => true
    }
    assert_true(rejected)
  }
}

///|
test "price only sourced shortages and preserve inventory snapshot" {
  let input = parse_manifest(
    (
      #|{"schema":"benchkitmap/v1",
      #| "parts":[{"id":"wire","stock":1,"packs":[]},
      #|          {"id":"led","stock":0,"packs":[{"id":"pack","quantity":2,"cost_cents":125}]}],
      #| "kits":[{"id":"lamp","items":[{"item":"wire","quantity":1},{"item":"led","quantity":1}]}],
      #| "orders":[{"id":"class","kit":"lamp","quantity":2}]}
    ),
  )
  let result = plan(input)
  assert_eq(result.allocation.orders[0].buildable, 0)
  assert_eq(result.allocation.parts[0].remaining_stock, 1)
  assert_eq(result.purchases[0].shortage, 1)
  assert_true(result.purchases[0].purchase is None)
  assert_eq(result.purchases[1].purchase.unwrap().ordered, 2)
  assert_eq(result.purchase_total_cents, 125L)
  assert_false(result.purchase_complete)
  assert_eq(input.parts[0].stock, 1)
}

///|
test "validate unused vendor offers in typed SDK input" {
  let input : Manifest = {
    parts: [
      {
        id: "wire",
        stock: 10,
        packs: [{ id: "bad", quantity: 0, cost_cents: 1, }],
      },
    ],
    kits: [{ id: "kit", items: [{ item: "wire", quantity: 1, }], }],
    orders: [{ id: "order", kit: "kit", quantity: 1, }],
  }
  let rejected = try {
    ignore(plan(input))
    false
  } catch {
    Invalid(detail) => detail.has_prefix("part wire: ")
  }
  assert_true(rejected)
}
