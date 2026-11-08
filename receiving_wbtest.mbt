///|
fn receiving_fixture() -> Manifest {
  {
    parts: [
      {
        id: "sensor",
        stock: 2,
        packs: [
          { id: "small", quantity: 3, cost_cents: 740, },
          { id: "large", quantity: 5, cost_cents: 1050, },
        ],
      },
      {
        id: "lead",
        stock: 1,
        packs: [{ id: "small", quantity: 10, cost_cents: 350, }],
      },
    ],
    kits: [
      {
        id: "kit",
        items: [
          { item: "sensor", quantity: 1, },
          { item: "lead", quantity: 2, },
        ],
      },
    ],
    orders: [{ id: "class", kit: "kit", quantity: 6, }],
  }
}

///|
test "receive confirmed packs in two deliveries without changing prior snapshots" {
  let source = receiving_fixture()
  let first = receive_packs(
    source,
    parse_deliveries_csv(
      "\u{FEFF}\"part\",\"pack\",\"count\"\r\nsensor,small,1\r\n\"lead\",\"small\",\"01\"\r\n",
    ),
  )
  assert_eq(first.parts.map(part => part.stock), [5, 11])
  assert_eq(allocate(first).orders[0].buildable, 5)
  let second = receive_packs(first, [
    { part: "sensor", pack: "large", count: 1, },
    { part: "lead", pack: "small", count: 1, },
  ])
  assert_eq(second.parts.map(part => part.stock), [10, 21])
  let roundtrip = parse_manifest(encode_manifest(second))
  assert_eq(allocate(roundtrip).orders[0].buildable, 6)
  assert_eq(roundtrip.orders[0].quantity, 6)
  assert_eq(source.parts.map(part => part.stock), [2, 1])
  assert_eq(first.parts.map(part => part.stock), [5, 11])
  second.parts[0].packs.clear()
  second.kits[0].items.clear()
  second.orders.clear()
  assert_eq(first.parts[0].packs.length(), 2)
  assert_eq(first.kits[0].items.length(), 2)
  assert_eq(first.orders.length(), 1)
}

///|
test "receive rejects duplicate or unknown deliveries and aggregate overflow" {
  let source = receiving_fixture()
  source.parts[0] = { ..source.parts[0], stock: 999_995, }
  let small : PackDelivery = { part: "sensor", pack: "small", count: 1, }
  let large : PackDelivery = { ..small, pack: "large", }
  assert_eq(receive_packs(source, [large]).parts[0].stock, 1_000_000)
  for
    (deliveries, detail) in [
      ([small, large], "would exceed"),
      ([small, small], "duplicate delivery"),
      ([small, { ..small, part: "absent", }], "unknown part"),
      ([small, { ..large, part: "lead", }], "unknown pack"),
      ([{ ..small, count: -1, }], "must be in"),
      ([{ ..small, count: 1_000_000, }], "would exceed"),
    ] {
    let rejected = try {
      ignore(receive_packs(source, deliveries))
      false
    } catch {
      Invalid(message) => message.contains(detail)
    }
    assert_true(rejected)
  }
  assert_eq(source.parts.map(part => part.stock), [999_995, 1])
}

///|
test "delivery CSV rejects invalid headers, counts and row shapes" {
  for
    csv in [
      "part,pack,count\n", "part,stock,count\nsensor,small,1", "part,pack,count\nsensor,small,0",
      "part,pack,count\nsensor,small,1.5", "part,pack,count\nsensor,small,1000001",
      "part,pack,count\nsensor,small,1,2", "part,pack,count\nsensor,\"small,1", "part,pack,count\nsensor,small,\"1\n2\"",
    ] {
    let rejected = try {
      ignore(parse_deliveries_csv(csv))
      false
    } catch {
      Invalid(_) => true
    }
    assert_true(rejected)
  }
}
