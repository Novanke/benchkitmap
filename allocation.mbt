///|
const ALLOCATION_LIMIT : Int32 = 256

///|
fn allocation_check_length(
  label : String,
  count : Int32,
) -> Unit raise PlanError {
  if count < 1 || count > ALLOCATION_LIMIT {
    raise Invalid("\{label} must contain 1..\{ALLOCATION_LIMIT} entries")
  }
}

///|
fn allocation_check_quantity(
  label : String,
  quantity : Int32,
  minimum : Int32,
) -> Unit raise PlanError {
  if quantity < minimum || quantity > max_quantity {
    raise Invalid("\{label} must be in \{minimum}..\{max_quantity}")
  }
}

///|
fn allocation_add_scaled(
  total : Int32,
  count : Int32,
  scale : Int32,
  part : String,
  context : String,
) -> Int32 raise PlanError {
  let result = total.to_int64() + count.to_int64() * scale.to_int64()
  if result > max_quantity.to_int64() {
    raise Invalid(
      "demand exceeds \{max_quantity} for part \{part} in \{context}",
    )
  }
  result.to_int()
}

///|
fn allocation_expand(
  manifest : Manifest,
  part_indices : Map[String, Int32],
  kit_indices : Map[String, Int32],
  index : Int32,
  visiting : Array[Bool],
  memo : Array[Array[Int32]?],
) -> Array[Int32] raise PlanError {
  if memo[index] is Some(expanded) {
    return expanded
  }
  let kit = manifest.kits[index]
  if visiting[index] {
    raise Invalid("kit dependency cycle at \{kit.id}")
  }
  visiting[index] = true
  let totals = Array::make(manifest.parts.length(), 0)
  let seen : Map[String, Bool] = Map([])
  allocation_check_length("items of kit \{kit.id}", kit.items.length())
  for need in kit.items {
    allocation_check_quantity(
      "quantity of \{need.item} in kit \{kit.id}",
      need.quantity,
      1,
    )
    if seen.contains(need.item) {
      raise Invalid("duplicate child \{need.item} in kit \{kit.id}")
    }
    seen[need.item] = true
    match part_indices.get(need.item) {
      Some(part_index) =>
        totals[part_index] = allocation_add_scaled(
          totals[part_index],
          need.quantity,
          1,
          need.item,
          kit.id,
        )
      None =>
        match kit_indices.get(need.item) {
          None => raise Invalid("unknown item \{need.item} in kit \{kit.id}")
          Some(child_index) => {
            let child = allocation_expand(
              manifest, part_indices, kit_indices, child_index, visiting, memo,
            )
            for part_index, count in child {
              if count > 0 {
                totals[part_index] = allocation_add_scaled(
                  totals[part_index],
                  count,
                  need.quantity,
                  manifest.parts[part_index].id,
                  kit.id,
                )
              }
            }
          }
        }
    }
  }
  memo[index] = Some(totals)
  visiting[index] = false
  totals
}

///|
/// Expand nested bills of materials and issue stock to whole kits in order.
/// Balances use full requested demand, even when an order cannot be fulfilled.
pub fn allocate(manifest : Manifest) -> Allocation raise PlanError {
  allocation_check_length("parts", manifest.parts.length())
  allocation_check_length("kits", manifest.kits.length())
  allocation_check_length("orders", manifest.orders.length())

  let part_indices : Map[String, Int32] = Map([])
  let kit_indices : Map[String, Int32] = Map([])
  for index, part in manifest.parts {
    if !valid_id(part.id) || part_indices.contains(part.id) {
      raise Invalid("invalid or duplicate part id: \{part.id}")
    }
    allocation_check_quantity("stock for part \{part.id}", part.stock, 0)
    part_indices[part.id] = index
  }
  for index, kit in manifest.kits {
    if !valid_id(kit.id) ||
      part_indices.contains(kit.id) ||
      kit_indices.contains(kit.id) {
      raise Invalid("invalid or duplicate kit id: \{kit.id}")
    }
    kit_indices[kit.id] = index
  }

  let visiting = Array::make(manifest.kits.length(), false)
  let memo : Array[Array[Int32]?] = Array::make(manifest.kits.length(), None)
  for index in 0..<manifest.kits.length() {
    ignore(
      allocation_expand(
        manifest, part_indices, kit_indices, index, visiting, memo,
      ),
    )
  }

  let remaining = manifest.parts.map(part => part.stock)
  let required = Array::make(manifest.parts.length(), 0)
  let seen_orders : Map[String, Bool] = Map([])
  let orders : Array[OrderPlan] = []
  for order in manifest.orders {
    if !valid_id(order.id) || seen_orders.contains(order.id) {
      raise Invalid("invalid or duplicate order id: \{order.id}")
    }
    seen_orders[order.id] = true
    allocation_check_quantity(
      "quantity of order \{order.id}",
      order.quantity,
      1,
    )
    let kit_index = match kit_indices.get(order.kit) {
      Some(index) => index
      None => raise Invalid("unknown kit \{order.kit} in order \{order.id}")
    }
    let per_kit = memo[kit_index].unwrap()
    let mut buildable = order.quantity
    for part_index, count in per_kit {
      if count > 0 {
        let available = remaining[part_index] / count
        if available < buildable {
          buildable = available
        }
      }
    }
    let items : Array[PartIssue] = []
    for part_index, count in per_kit {
      if count > 0 {
        let part_id = manifest.parts[part_index].id
        let requested = allocation_add_scaled(
          0,
          count,
          order.quantity,
          part_id,
          order.id,
        )
        required[part_index] = allocation_add_scaled(
          required[part_index],
          requested,
          1,
          part_id,
          order.id,
        )
        let issued = (count.to_int64() * buildable.to_int64()).to_int()
        let available_before = remaining[part_index]
        let limits_order = buildable < order.quantity &&
          available_before / count == buildable
        remaining[part_index] -= issued
        items.push({
          part: part_id,
          units_per_kit: count,
          available_before,
          required: requested,
          issued,
          limits_order,
        })
      }
    }
    orders.push({
      id: order.id,
      kit: order.kit,
      requested: order.quantity,
      buildable,
      items,
    })
  }

  let parts : Array[PartBalance] = []
  for index, part in manifest.parts {
    let demand = required[index]
    parts.push({
      part: part.id,
      stock: part.stock,
      required: demand,
      issued: part.stock - remaining[index],
      remaining_stock: remaining[index],
      shortage: if demand > part.stock {
        demand - part.stock
      } else {
        0
      },
    })
  }
  { orders, parts, }
}
