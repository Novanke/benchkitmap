///|
pub(all) struct ProjectedOrder {
  id : String
  kit : String
  requested : Int32
  buildable_now : Int32
  buildable_after_priced_purchases : Int32
}

///|
pub(all) struct Projection {
  orders : Array[ProjectedOrder]
  purchase_complete : Bool
  purchase_total_cents : Int64
}

///|
/// Reallocate from the original stock plus all priced purchases, in the same
/// order priority. An earlier order that becomes buildable can leave fewer
/// parts for a later order. Unpriced shortages are never added to stock.
pub fn project_after_purchase(
  manifest : Manifest,
) -> Projection raise PlanError {
  let current = plan(manifest)
  let purchased : Map[String, Int32] = Map([])
  for line in current.purchases {
    if line.purchase is Some(purchase) {
      purchased[line.part] = purchase.ordered
    }
  }
  let now = current.allocation.orders
  let after = if purchased.is_empty() {
    now
  } else {
    let parts = manifest.parts.map(part => {
      let stock = part.stock + purchased.get(part.id).unwrap_or(0)
      { ..part, stock, }
    })
    allocate({ ..manifest, parts, }).orders
  }
  let orders : Array[ProjectedOrder] = []
  for index, order in now {
    orders.push({
      id: order.id,
      kit: order.kit,
      requested: order.requested,
      buildable_now: order.buildable,
      buildable_after_priced_purchases: after[index].buildable,
    })
  }
  {
    orders,
    purchase_complete: current.purchase_complete,
    purchase_total_cents: current.purchase_total_cents,
  }
}
