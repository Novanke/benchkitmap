///|
fn main raise {
  let input =
    #|{"schema":"benchkitmap/v1",
    #| "parts":[{"id":"led","stock":3,"packs":[{"id":"bag-4","quantity":4,"cost_cents":220}]}],
    #| "kits":[{"id":"badge","items":[{"item":"led","quantity":2}]}],
    #| "orders":[{"id":"class-a","kit":"badge","quantity":3}]}
  let manifest = @kit.parse_manifest(input)
  let result = @kit.plan(manifest)
  assert_eq(result.allocation.orders[0].buildable, 1)
  assert_eq(result.allocation.parts[0].shortage, 3)
  assert_eq(result.purchases[0].purchase.unwrap().ordered, 4)
  assert_eq(result.purchase_total_cents, 220L)
  let delivered = @kit.parse_deliveries_csv("part,pack,count\nled,bag-4,1")
  let received = @kit.receive_packs(manifest, delivered)
  assert_eq(manifest.parts[0].stock, 3)
  assert_eq(received.parts[0].stock, 7)
  assert_eq(@kit.plan(received).allocation.orders[0].buildable, 3)
  println(@kit.render_plan(result, @kit.JsonReport))
}
