///|
fn object_fields(
  value : Json,
  path : String,
  keys : Array[String],
) -> Map[String, Json] raise PlanError {
  let fields = match value {
    Object(fields) => fields
    _ => raise Invalid(path + " must be an object")
  }
  for key, _ in fields {
    if !keys.contains(key) {
      raise Invalid(path + " contains an unknown field: " + key)
    }
  }
  fields
}

///|
fn field_text(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> String raise PlanError {
  match fields.get(key) {
    Some(String(value)) => value
    _ => raise Invalid(path + "." + key + " must be a string")
  }
}

///|
fn field_integer(
  fields : Map[String, Json],
  key : String,
  path : String,
  minimum : Int32,
  maximum : Int32,
) -> Int32 raise PlanError {
  let name = path + "." + key
  let digits = match fields.get(key) {
    Some(Number(_, repr=Some(digits))) => digits
    _ => raise Invalid(name + " must be a decimal integer")
  }
  let mut value = 0L
  for c in digits.iter() {
    if c < '0' || c > '9' {
      raise Invalid(name + " must be a nonnegative decimal integer")
    }
    value = value * 10L + (c.to_int() - '0'.to_int()).to_int64()
    if value > maximum.to_int64() {
      raise Invalid(name + " exceeds " + maximum.to_string())
    }
  }
  if value < minimum.to_int64() {
    raise Invalid(name + " must be at least " + minimum.to_string())
  }
  value.to_int()
}

///|
fn field_array(
  fields : Map[String, Json],
  key : String,
  path : String,
  minimum : Int32,
  maximum : Int32,
) -> Array[Json] raise PlanError {
  match fields.get(key) {
    Some(Array(items)) if items.length() >= minimum && items.length() <= maximum =>
      items
    _ =>
      raise Invalid(
        path +
        "." +
        key +
        " must contain " +
        minimum.to_string() +
        ".." +
        maximum.to_string() +
        " items",
      )
  }
}

///|
fn decode_pack(value : Json, path : String) -> PackOption raise PlanError {
  let row = object_fields(value, path, ["id", "quantity", "cost_cents"])
  {
    id: field_text(row, "id", path),
    quantity: field_integer(row, "quantity", path, 1, max_quantity),
    cost_cents: field_integer(row, "cost_cents", path, 0, 1_000_000_000),
  }
}

///|
fn decode_part(value : Json, path : String) -> Part raise PlanError {
  let row = object_fields(value, path, ["id", "stock", "packs"])
  let packs = []
  for i, item in field_array(row, "packs", path, 0, 16) {
    packs.push(decode_pack(item, path + ".packs[" + i.to_string() + "]"))
  }
  {
    id: field_text(row, "id", path),
    stock: field_integer(row, "stock", path, 0, max_quantity),
    packs,
  }
}

///|
fn decode_kit(value : Json, path : String) -> Kit raise PlanError {
  let row = object_fields(value, path, ["id", "items"])
  let items = []
  for i, value in field_array(row, "items", path, 1, 256) {
    let at = path + ".items[" + i.to_string() + "]"
    let item = object_fields(value, at, ["item", "quantity"])
    items.push({
      item: field_text(item, "item", at),
      quantity: field_integer(item, "quantity", at, 1, max_quantity),
    })
  }
  { id: field_text(row, "id", path), items, }
}

///|
fn decode_order(value : Json, path : String) -> Order raise PlanError {
  let row = object_fields(value, path, ["id", "kit", "quantity"])
  {
    id: field_text(row, "id", path),
    kit: field_text(row, "kit", path),
    quantity: field_integer(row, "quantity", path, 1, max_quantity),
  }
}

///|
/// Decode the versioned worksheet. The planner separately checks identities,
/// references, aggregate quantities and purchase feasibility.
pub fn parse_manifest(text : String) -> Manifest raise PlanError {
  if text.length() > 2_097_152 {
    raise Invalid("manifest text exceeds the input limit")
  }
  let value = @json.parse(
    text,
    max_nesting_depth=12,
    reject_duplicate_keys=true,
    preserve_number_repr=true,
  ) catch {
    _ =>
      raise Invalid("invalid JSON, duplicate object key, or excessive nesting")
  }
  let root = object_fields(value, "manifest", [
    "schema", "parts", "kits", "orders",
  ])
  if field_text(root, "schema", "manifest") != "benchkitmap/v1" {
    raise Invalid("manifest.schema must be benchkitmap/v1")
  }
  let parts = []
  let kits = []
  let orders = []
  for i, value in field_array(root, "parts", "manifest", 1, 256) {
    parts.push(decode_part(value, "parts[" + i.to_string() + "]"))
  }
  for i, value in field_array(root, "kits", "manifest", 1, 256) {
    kits.push(decode_kit(value, "kits[" + i.to_string() + "]"))
  }
  for i, value in field_array(root, "orders", "manifest", 1, 256) {
    orders.push(decode_order(value, "orders[" + i.to_string() + "]"))
  }
  { parts, kits, orders, }
}
