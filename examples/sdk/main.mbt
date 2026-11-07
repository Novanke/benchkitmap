///|
fn main raise {
  let input =
    #|{"schema":"benchkitmap/v1",
    #| "parts":[{"id":"led","stock":3,"packs":[{"id":"bag-4","quantity":4,"cost_cents":220}]}],
    #| "kits":[{"id":"badge","items":[{"item":"led","quantity":2}]}],
    #| "orders":[{"id":"class-a","kit":"badge","quantity":3}]}
  let result = @kit.plan(@kit.parse_manifest(input))
  assert_eq(result.allocation.orders[0].buildable, 1)
  assert_eq(result.allocation.parts[0].shortage, 3)
  assert_eq(result.purchases[0].purchase.unwrap().ordered, 4)
  assert_eq(result.purchase_total_cents, 220L)
  println(@kit.render_plan(result, @kit.JsonReport))
}
