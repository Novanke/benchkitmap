///|
/// Whole packs counted in one physical delivery. A pack ID is scoped to its part.
pub(all) struct PackDelivery {
  part : String
  pack : String
  count : Int32
}

///|
const DELIVERY_LIMIT : Int32 = 4096

///|
/// Read a bounded CSV with columns part,pack,count and positive whole-pack counts.
pub fn parse_deliveries_csv(
  csv : String,
) -> Array[PackDelivery] raise PlanError {
  let deliveries : Array[PackDelivery] = []
  let rows = walk_inventory_csv(csv, "delivery CSV", DELIVERY_LIMIT, fn(
    line,
    row,
  ) raise PlanError {
    let context = "delivery CSV row \{row}"
    let cells = csv_cells(line, 3, context)
    if row == 1 {
      if cells[0] != "part" || cells[1] != "pack" || cells[2] != "count" {
        raise Invalid("delivery CSV header must be part,pack,count")
      }
      return
    }
    let part = cells[0]
    let pack = cells[1]
    if !valid_id(part) || !valid_id(pack) {
      raise Invalid("\{context} has an invalid part or pack ID")
    }
    let count = csv_quantity(cells[2], context, "pack count")
    if count == 0 {
      raise Invalid("\{context} pack count must be positive")
    }
    deliveries.push({ part, pack, count, })
  })
  if rows < 2 {
    raise Invalid("delivery CSV requires a header and at least one delivery")
  }
  deliveries
}

///|
/// Add the packs actually received, using sizes in the current manifest.
/// A repeated part/pack pair is rejected. Apply each delivery once to the
/// latest snapshot. The input snapshot and pending orders are preserved.
pub fn receive_packs(
  manifest : Manifest,
  deliveries : Array[PackDelivery],
) -> Manifest raise PlanError {
  if deliveries.is_empty() || deliveries.length() > DELIVERY_LIMIT {
    raise Invalid("a delivery must contain 1..\{DELIVERY_LIMIT} rows")
  }
  ignore(allocate(manifest))
  check_pack_catalog(manifest)
  let indices : Map[String, Int32] = Map([])
  for index, part in manifest.parts {
    indices[part.id] = index
  }
  let stocks = manifest.parts.map(part => part.stock)
  let seen : Map[(String, String), Bool] = Map([])
  for delivery in deliveries {
    let index = match indices.get(delivery.part) {
      Some(index) => index
      None => raise Invalid("unknown part in delivery: \{delivery.part}")
    }
    let key = (delivery.part, delivery.pack)
    if seen.contains(key) {
      raise Invalid("duplicate delivery for \{delivery.part}/\{delivery.pack}")
    }
    seen[key] = true
    allocation_check_quantity(
      "received count for \{delivery.pack}",
      delivery.count,
      1,
    )
    let mut pack_size = 0
    for pack in manifest.parts[index].packs {
      if pack.id == delivery.pack {
        pack_size = pack.quantity
        break
      }
    }
    if pack_size == 0 {
      raise Invalid("unknown pack \{delivery.pack} for part \{delivery.part}")
    }
    let total = stocks[index].to_int64() +
      pack_size.to_int64() * delivery.count.to_int64()
    if total > max_quantity.to_int64() {
      raise Invalid(
        "stock for \{delivery.part} would exceed \{max_quantity} units",
      )
    }
    stocks[index] = total.to_int()
  }
  snapshot_with_stocks(manifest, stocks)
}
