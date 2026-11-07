///|
fn issue_fixture() -> Manifest {
  {
    parts: [
      { id: "board", stock: 8, packs: [], },
      { id: "lead", stock: 10, packs: [], },
    ],
    kits: [
      { id: "double-board", items: [{ item: "board", quantity: 2, }], },
      {
        id: "sensor",
        items: [{ item: "board", quantity: 1, }, { item: "lead", quantity: 2, }],
      },
      { id: "spare", items: [{ item: "lead", quantity: 1, }], },
    ],
    orders: [
      { id: "first", kit: "double-board", quantity: 3, },
      { id: "second", kit: "sensor", quantity: 2, },
      { id: "third", kit: "spare", quantity: 1, },
    ],
  }
}

///|
test "partial and complete issue preserve remaining priority and stock" {
  let input = issue_fixture()
  let partial = record_issue(input, "second", 1)
  assert_eq(partial.parts[0].stock, 7)
  assert_eq(partial.parts[1].stock, 8)
  assert_eq(partial.orders[1].quantity, 1)
  assert_eq(allocate(partial).orders[0].buildable, 3)

  let completed = record_issue(partial, "second", 1)
  assert_eq(completed.parts[0].stock, 6)
  assert_eq(completed.parts[1].stock, 6)
  assert_eq(completed.orders.length(), 2)
  assert_eq(completed.orders[0].id, "first")
  assert_eq(completed.orders[1].id, "third")
  assert_eq(input.parts[0].stock, 8)
  assert_eq(input.orders[1].quantity, 2)

  let final_order : Manifest = { ..completed, orders: [completed.orders[0]], }
  let finished = record_issue(final_order, "first", 3)
  assert_eq(finished.parts[0].stock, 0)
  assert_eq(allocate(finished).orders.length(), 0)
}

///|
test "issue cannot spend units allocated to a higher-priority order" {
  let base = issue_fixture()
  let input : Manifest = {
    ..base,
    orders: [base.orders[0], { ..base.orders[1], quantity: 3, }, base.orders[2]],
  }
  for
    (id, quantity, expected) in [
      ("second", 3, "order second can issue at most 2 complete kits"),
      ("missing", 1, "unknown order: missing"),
      ("second", 0, "issue quantity must be positive"),
    ] {
    let actual = try {
      ignore(record_issue(input, id, quantity))
      ""
    } catch {
      Invalid(message) => message
    }
    assert_eq(actual, expected)
  }
  assert_eq(input.parts[0].stock, 8)
  assert_eq(input.orders[1].quantity, 3)
}
