///|
fn stock_csv_fixture() -> Manifest {
  {
    parts: [
      {
        id: "wire",
        stock: 5,
        packs: [{ id: "roll", quantity: 1_000_000, cost_cents: 1_000_000_000, }],
      },
      { id: "switch", stock: 1, packs: [], },
      { id: "screw", stock: 3, packs: [], },
    ],
    kits: [
      {
        id: "lamp",
        items: [
          { item: "wire", quantity: 1, },
          { item: "switch", quantity: 1, },
        ],
      },
    ],
    orders: [{ id: "class", kit: "lamp", quantity: 4, }],
  }
}

///|
test "refresh spreadsheet counts, preserve manifest order and round trip" {
  let input = stock_csv_fixture()
  let output = refresh_stock(
    input, "\u{FEFF}\"part\",\"stock\"\r\n\"switch\",\"0004\"\r\n\"wire\",\"1000000\"\r\n",
  )
  assert_eq(output.parts.map(part => (part.id, part.stock)), [
    ("wire", 1_000_000),
    ("switch", 4),
    ("screw", 3),
  ])
  assert_eq(input.parts.map(part => part.stock), [5, 1, 3])
  assert_eq(output.kits[0].items.map(item => (item.item, item.quantity)), [
    ("wire", 1),
    ("switch", 1),
  ])
  assert_eq(
    (output.orders[0].id, output.orders[0].kit, output.orders[0].quantity),
    ("class", "lamp", 4),
  )
  let encoded = encode_manifest(output)
  let decoded = parse_manifest(encoded)
  assert_eq(decoded.parts[0].packs[0].cost_cents, 1_000_000_000)
  assert_eq(decoded.parts[0].packs[0].quantity, 1_000_000)
  assert_eq(encode_manifest(decoded), encoded)
  assert_eq(allocate(input).orders[0].buildable, 1)
  assert_eq(allocate(output).orders[0].buildable, 4)
  // SDK callers may reuse and change either snapshot independently.
  output.parts[0].packs[0] = { id: "other", quantity: 1, cost_cents: 0, }
  output.kits[0].items[0] = { item: "screw", quantity: 1, }
  output.orders[0] = { id: "changed", kit: "lamp", quantity: 1, }
  assert_eq(input.parts[0].packs[0].id, "roll")
  assert_eq(input.kits[0].items[0].item, "wire")
  assert_eq(input.orders[0].id, "class")
}

///|
test "refresh rejects invalid, ambiguous and unsupported stock CSV rows" {
  let input = stock_csv_fixture()
  for
    csv in [
      "", "part,stock\n", "stock,part\n1,wire", "part,stock\nwire,5\nwire,6", "part,stock\nunknown,1",
      "part,stock\n=wire,1", "part,stock\nwire,", "part,stock\nwire,-1", "part,stock\nwire,1e0",
      "part,stock\nwire,1000001", "part,stock\nwire,1,2", "part,stock\nwire,1\r",
      "part,stock\nwire,\"1\n2\"", "part,stock\nwire,1\n\n",
    ] {
    let rejected = try {
      ignore(refresh_stock(input, csv))
      false
    } catch {
      Invalid(_) => true
    }
    assert_true(rejected)
  }
  assert_eq(input.parts.map(part => part.stock), [5, 1, 3])
  assert_eq(refresh_stock(input, "part,stock\nwire,0").parts[0].stock, 0)
}

///|
test "refresh rejects bytes beyond the CSV input limit" {
  let csv = "part,stock\nwire," + "0".repeat(CSV_BYTES)
  let rejected = try {
    ignore(refresh_stock(stock_csv_fixture(), csv))
    false
  } catch {
    Invalid(detail) => detail == "stock CSV exceeds 2 MiB"
  }
  assert_true(rejected)
}
