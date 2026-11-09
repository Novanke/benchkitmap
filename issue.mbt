///|
/// Record the issue of complete kits already allocatable to the given order.
/// The returned inventory and pending orders form a new planning snapshot.
pub fn record_issue(
  manifest : Manifest,
  order_id : String,
  quantity : Int32,
) -> Manifest raise PlanError {
  if quantity <= 0 {
    raise Invalid("issue quantity must be positive")
  }
  let allocation = allocate(manifest)
  check_pack_catalog(manifest)
  for row in allocation.orders {
    if row.id != order_id {
      continue
    }
    if quantity > row.buildable {
      raise Invalid(
        "order \{order_id} can issue at most \{row.buildable} complete kits",
      )
    }
    let consumed : Map[String, Int32] = Map([])
    for item in row.items {
      // The issued count is no larger than the bounded original demand.
      consumed[item.part] = item.units_per_kit * quantity
    }
    let parts = manifest.parts.map(fn(part) {
      {
        ..part,
        stock: part.stock - consumed.get(part.id).unwrap_or(0),
        packs: part.packs.copy(),
      }
    })
    let kits = manifest.kits.map(fn(kit) { { ..kit, items: kit.items.copy(), } })
    let orders : Array[Order] = []
    for order in manifest.orders {
      if order.id != order_id {
        orders.push(order)
      } else if quantity < order.quantity {
        orders.push({ ..order, quantity: order.quantity - quantity, })
      }
    }
    return { parts, kits, orders, }
  }
  raise Invalid("unknown order: \{order_id}")
}
