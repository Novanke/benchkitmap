///|
let max_purchase_states : Int32 = 100_000

///|
fn check_pack_catalog(manifest : Manifest) -> Unit raise PlanError {
  for part in manifest.parts {
    // A zero shortage validates options without running the optimizer.
    ignore(recommend_purchase(0, part.packs)) catch {
      Invalid(detail) => raise Invalid("part " + part.id + ": " + detail)
    }
  }
}

///|
fn pack_gcd(a : Int32, b : Int32) -> Int32 {
  let mut left = a
  let mut right = b
  while right != 0 {
    let remainder = left % right
    left = right
    right = remainder
  }
  left
}

///|
/// Minimize price, then excess units, then pack count. Equal solutions favor
/// the earlier declared offers. Return None when nothing can be recommended.
/// Equal-size offers use a direct price comparison. For mixed sizes the exact
/// search is limited to 100,000 states after common-divisor scaling.
pub fn recommend_purchase(
  shortage : Int32,
  packs : Array[PackOption],
) -> Purchase? raise PlanError {
  if shortage < 0 || shortage > max_quantity {
    raise Invalid("shortage must be between 0 and 1,000,000")
  }
  if packs.length() > 16 {
    raise Invalid("at most 16 pack options are supported")
  }
  let mut largest = 0
  let mut divisor = 0
  for index, pack in packs {
    if !valid_id(pack.id) {
      raise Invalid("invalid pack option ID: " + pack.id)
    }
    if pack.quantity <= 0 || pack.quantity > max_quantity {
      raise Invalid("pack quantity must be between 1 and 1,000,000: " + pack.id)
    }
    if pack.cost_cents < 0 || pack.cost_cents > 1_000_000_000 {
      raise Invalid(
        "pack cost must be between 0 and 1,000,000,000 cents: " + pack.id,
      )
    }
    for earlier in 0..<index {
      if packs[earlier].id == pack.id {
        raise Invalid("duplicate pack option ID: " + pack.id)
      }
    }
    if pack.quantity > largest {
      largest = pack.quantity
    }
    divisor = pack_gcd(divisor, pack.quantity)
  }
  if shortage == 0 || packs.length() == 0 {
    return None
  }
  if packs.all(pack => pack.quantity == packs[0].quantity) {
    let mut pack = packs[0]
    for offer in packs {
      if offer.cost_cents < pack.cost_cents {
        pack = offer
      }
    }
    let count = (shortage - 1) / pack.quantity + 1
    return Some({
      shortage,
      ordered: count * pack.quantity,
      cost_cents: count.to_int64() * pack.cost_cents.to_int64(),
      packs: [
        {
          id: pack.id,
          quantity: pack.quantity,
          count,
          unit_cost_cents: pack.cost_cents,
        },
      ],
    })
  }
  let target = (shortage - 1) / divisor + 1
  // Beyond this bound at least one pack can be removed without underfilling.
  // Removing it cannot raise the price and always reduces the excess.
  let upper = target + largest / divisor - 1
  if upper >= max_purchase_states {
    raise Invalid(
      "pack options exceed the exact optimization budget of 100,000 states",
    )
  }
  let units = packs.map(fn(pack) { pack.quantity / divisor })
  let prices = packs.map(fn(pack) { pack.cost_cents.to_int64() })
  let costs = Array::make(upper + 1, -1L)
  let counts = Array::make(upper + 1, 0)
  let choices = Array::make(upper + 1, -1)
  costs[0] = 0L
  for ordered in 1..<(upper + 1) {
    for index, size in units {
      let remaining = ordered - size
      if remaining < 0 || costs[remaining] < 0L {
        continue
      }
      let cost = costs[remaining] + prices[index]
      let count = counts[remaining] + 1
      // Keeping the earlier offer on a tie gives the lexicographically
      // earliest sequence of offers, since the suffix is already optimal.
      if costs[ordered] < 0L ||
        cost < costs[ordered] ||
        (cost == costs[ordered] && count < counts[ordered]) {
        costs[ordered] = cost
        counts[ordered] = count
        choices[ordered] = index
      }
    }
  }
  // Ascending totals leave the least excess in place on equal prices.
  let mut best = -1
  for ordered in target..<(upper + 1) {
    if costs[ordered] >= 0L && (best < 0 || costs[ordered] < costs[best]) {
      best = ordered
    }
  }
  // Repeating any one offer gives a feasible total within the bound.
  if best < 0 {
    raise Invalid("no feasible pack combination")
  }
  let totals = Array::make(packs.length(), 0)
  let mut remaining = best
  while remaining > 0 {
    let index = choices[remaining]
    totals[index] += 1
    remaining -= units[index]
  }
  let selected : Array[PackCount] = []
  for index, pack in packs {
    if totals[index] > 0 {
      selected.push({
        id: pack.id,
        quantity: pack.quantity,
        count: totals[index],
        unit_cost_cents: pack.cost_cents,
      })
    }
  }
  Some({
    shortage,
    ordered: best * divisor,
    cost_cents: costs[best],
    packs: selected,
  })
}
