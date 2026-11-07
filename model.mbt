///|
/// A component of a kit. The item can name a part or another kit.
pub(all) struct ItemNeed {
  item : String
  quantity : Int32
}

///|
/// A vendor's fixed size pack, priced in cents in the manifest's currency.
pub(all) struct PackOption {
  id : String
  quantity : Int32
  cost_cents : Int32
}

///|
pub(all) struct Part {
  id : String
  stock : Int32
  packs : Array[PackOption]
}

///|
pub(all) struct Kit {
  id : String
  items : Array[ItemNeed]
}

///|
pub(all) struct Order {
  id : String
  kit : String
  quantity : Int32
}

///|
/// An inventory snapshot and orders in descending priority.
pub(all) struct Manifest {
  parts : Array[Part]
  kits : Array[Kit]
  orders : Array[Order]
}

///|
pub(all) struct PartIssue {
  part : String
  required : Int32
  issued : Int32
}

///|
pub(all) struct OrderPlan {
  id : String
  kit : String
  requested : Int32
  buildable : Int32
  items : Array[PartIssue]
}

///|
pub(all) struct PartBalance {
  part : String
  stock : Int32
  required : Int32
  issued : Int32
  remaining_stock : Int32
  shortage : Int32
}

///|
pub(all) struct Allocation {
  orders : Array[OrderPlan]
  parts : Array[PartBalance]
}

///|
pub(all) struct PackCount {
  id : String
  quantity : Int32
  count : Int32
  unit_cost_cents : Int32
}

///|
pub(all) struct Purchase {
  shortage : Int32
  ordered : Int32
  cost_cents : Int64
  packs : Array[PackCount]
}

///|
/// A missing recommendation identifies a part with no purchasing options.
pub(all) struct PurchaseLine {
  part : String
  shortage : Int32
  purchase : Purchase?
}

///|
pub(all) struct Plan {
  allocation : Allocation
  purchases : Array[PurchaseLine]
  purchase_total_cents : Int64
  purchase_complete : Bool
}

///|
pub(all) enum OutputFormat {
  JsonReport
  PickCsv
  BuyCsv
}

///|
pub(all) suberror PlanError {
  Invalid(String)
}

///|
let max_quantity : Int32 = 1_000_000

///|
fn id_alphanumeric(c : Char) -> Bool {
  (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')
}

///|
// This alphabet also keeps identifiers inert as cells in the CSV reports.
fn valid_id(id : String) -> Bool {
  if id.length() < 1 || id.length() > 64 {
    return false
  }
  for i, c in id {
    if !id_alphanumeric(c) && (i == 0 || (c != '_' && c != '-' && c != '.')) {
      return false
    }
  }
  true
}
