///|
/// Allocate today's stock and independently price each part's total shortage.
/// Unpriced shortages remain explicit in the returned purchase lines.
pub fn plan(manifest : Manifest) -> Plan raise PlanError {
  let allocation = allocate(manifest)
  let purchases = []
  let mut purchase_total_cents = 0L
  let mut purchase_complete = true
  for i, balance in allocation.parts {
    let recommendation = recommend_purchase(
      balance.shortage,
      manifest.parts[i].packs,
    ) catch {
      Invalid(detail) => raise Invalid("part " + balance.part + ": " + detail)
    }
    if balance.shortage == 0 {
      continue
    }
    match recommendation {
      Some(purchase) => purchase_total_cents += purchase.cost_cents
      None => purchase_complete = false
    }
    purchases.push({
      part: balance.part,
      shortage: balance.shortage,
      purchase: recommendation,
    })
  }
  { allocation, purchases, purchase_total_cents, purchase_complete, }
}
