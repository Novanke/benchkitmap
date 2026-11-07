///|
test "expand diamond BOM and issue only complete kits before the next order" {
  let input : Manifest = {
    parts: [
      { id: "tape", stock: 4, packs: [], },
      { id: "chip", stock: 10, packs: [], },
      { id: "unused", stock: 2, packs: [], },
    ],
    kits: [
      {
        id: "bundle",
        items: [{ item: "left", quantity: 1, }, { item: "right", quantity: 1, }],
      },
      {
        id: "left",
        items: [
          { item: "leaf", quantity: 1, },
          { item: "chip", quantity: 2, },
          { item: "tape", quantity: 1, },
        ],
      },
      {
        id: "right",
        items: [{ item: "leaf", quantity: 1, }, { item: "tape", quantity: 2, }],
      },
      { id: "leaf", items: [{ item: "chip", quantity: 2, }], },
    ],
    orders: [
      { id: "first", kit: "bundle", quantity: 2, },
      { id: "second", kit: "leaf", quantity: 2, },
    ],
  }
  let plan = allocate(input)
  assert_eq(plan.orders[0].buildable, 1)
  assert_eq(plan.orders[0].items[0].part, "tape")
  assert_eq(plan.orders[0].items[0].required, 6)
  assert_eq(plan.orders[0].items[0].issued, 3)
  assert_eq(plan.orders[0].items[1].part, "chip")
  assert_eq(plan.orders[0].items[1].required, 12)
  assert_eq(plan.orders[0].items[1].issued, 6)
  assert_eq(plan.orders[1].buildable, 2)
  assert_eq(plan.orders[1].items[0].issued, 4)
  assert_eq(plan.parts[0].remaining_stock, 1)
  assert_eq(plan.parts[0].shortage, 2)
  assert_eq(plan.parts[1].required, 16)
  assert_eq(plan.parts[1].shortage, 6)
  assert_eq(plan.parts[1].remaining_stock, 0)
  assert_eq(plan.parts[2].part, "unused")
  assert_eq(plan.parts[2].required, 0)
  assert_eq(plan.parts[2].remaining_stock, 2)
  assert_eq(input.parts[1].stock, 10)
}

///|
test "reject dependency cycle and unknown references even in unused kits" {
  let base : Manifest = {
    parts: [{ id: "bolt", stock: 4, packs: [], }],
    kits: [{ id: "active", items: [{ item: "bolt", quantity: 1, }], }],
    orders: [{ id: "request", kit: "active", quantity: 1, }],
  }
  for
    (extra, expected) in [
      (
        [
          { id: "a", items: [{ item: "b", quantity: 1, }], },
          { id: "b", items: [{ item: "a", quantity: 1, }], },
        ],
        "kit dependency cycle at a",
      ),
      (
        [{ id: "unused", items: [{ item: "missing", quantity: 1, }], }],
        "unknown item missing in kit unused",
      ),
    ] {
    let kits = base.kits.copy()
    for kit in extra {
      kits.push(kit)
    }
    let invalid : Manifest = { ..base, kits, }
    let actual = try {
      ignore(allocate(invalid))
      ""
    } catch {
      Invalid(message) => message
    }
    assert_eq(actual, expected)
  }
}

///|
test "bound multiplicative demand and combined demand across orders" {
  let base : Manifest = {
    parts: [{ id: "bolt", stock: 0, packs: [], }],
    kits: [{ id: "bulk", items: [{ item: "bolt", quantity: 600000, }], }],
    orders: [
      { id: "a", kit: "bulk", quantity: 1, },
      { id: "b", kit: "bulk", quantity: 1, },
    ],
  }
  for
    (invalid, context) in [
      (base, "b"),
      (
        { ..base, orders: [{ id: "scale", kit: "bulk", quantity: 1000000, }], },
        "scale",
      ),
    ] {
    let actual = try {
      ignore(allocate(invalid))
      ""
    } catch {
      Invalid(message) => message
    }
    assert_eq(actual, "demand exceeds 1000000 for part bolt in \{context}")
  }
}
