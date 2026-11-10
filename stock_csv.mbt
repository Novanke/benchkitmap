///|
const CSV_BYTES : Int32 = 2_097_152

///|
fn csv_cell(raw : StringView, context : String) -> String raise PlanError {
  let len = raw.length()
  if len > 0 && raw[0] == '"' {
    if len < 2 || raw[len - 1] != '"' {
      raise Invalid("\{context} contains an unterminated quoted cell")
    }
    raw[1:len - 1].to_owned()
  } else {
    raw.to_owned()
  }
}

///|
fn csv_cells(
  line : StringView,
  columns : Int32,
  context : String,
) -> Array[String] raise PlanError {
  let cells = []
  let mut rest = line
  let detail = "\{context} must have exactly \{columns} cells"
  for _ in 1..<columns {
    match rest.split_once(",") {
      Some((left, right)) => {
        cells.push(csv_cell(left, context))
        rest = right
      }
      None => raise Invalid(detail)
    }
  }
  if rest.contains(",") {
    raise Invalid(detail)
  }
  cells.push(csv_cell(rest, context))
  cells
}

///|
fn csv_quantity(
  digits : String,
  context : String,
  name : String,
  maximum : Int32,
) -> Int32 raise PlanError {
  if digits.length() == 0 {
    raise Invalid("\{context} has an empty \{name}")
  }
  let mut value = 0
  for c in digits {
    if c < '0' || c > '9' {
      raise Invalid("\{context} must use an unsigned decimal \{name}")
    }
    // value has already passed the previous bound check, so this step
    // cannot overflow even if the cell has an excessive number of digits.
    value = value * 10 + c.to_int() - '0'.to_int()
    if value > maximum {
      raise Invalid("\{context} exceeds \{maximum} units")
    }
  }
  value
}

///|
fn walk_inventory_csv(
  csv : String,
  label : String,
  limit : Int32,
  accept : (StringView, Int32) -> Unit raise PlanError,
) -> Int32 raise PlanError {
  let bom = csv.length() > 0 && csv[0] == '\u{FEFF}'
  // The accepted grammar is ASCII except for the optional three-byte BOM.
  if csv.length() > CSV_BYTES - (if bom { 2 } else { 0 }) {
    raise Invalid("\{label} exceeds 2 MiB")
  }
  let mut start = if bom { 1 } else { 0 }
  let mut row = 0
  for index in start..<(csv.length() + 1) {
    let at_end = index == csv.length()
    if !at_end && csv[index] != '\n' {
      continue
    }
    if at_end && start == index {
      break
    }
    let end = if !at_end && index > start && csv[index - 1] == '\r' {
      index - 1
    } else {
      index
    }
    row += 1
    if row > limit + 1 {
      raise Invalid("\{label} supports at most \{limit} updates")
    }
    accept(csv[start:end], row)
    start = index + 1
  }
  row
}

///|
fn snapshot_with_stocks(manifest : Manifest, stocks : Array[Int32]) -> Manifest {
  let parts = []
  for index, part in manifest.parts {
    parts.push({ ..part, stock: stocks[index], packs: part.packs.copy(), })
  }
  {
    parts,
    kits: manifest.kits.map(kit => { ..kit, items: kit.items.copy(), }),
    orders: manifest.orders.copy(),
  }
}

///|
/// Replace listed stock counts from a two-column `part,stock` CSV.
/// Accepts LF or CRLF, an optional UTF-8 BOM, and optionally quoted cells.
/// IDs and counts use a single-line ASCII alphabet; embedded quotes,
/// delimiters, and multiline cells are rejected. Returns independent arrays.
pub fn refresh_stock(
  manifest : Manifest,
  csv : String,
) -> Manifest raise PlanError {
  let part_indices : Map[String, Int32] = Map([])
  for index, part in manifest.parts {
    if !valid_id(part.id) || part_indices.contains(part.id) {
      raise Invalid("invalid or duplicate manifest part id: " + part.id)
    }
    part_indices[part.id] = index
  }
  let stocks = manifest.parts.map(part => part.stock)
  let seen = Array::make(manifest.parts.length(), false)
  let rows = walk_inventory_csv(csv, "stock CSV", 256, fn(
    line,
    row,
  ) raise PlanError {
    let context = "stock CSV row \{row}"
    let cells = csv_cells(line, 2, context)
    let id = cells[0]
    let count = cells[1]
    if row == 1 {
      if id != "part" || count != "stock" {
        raise Invalid("stock CSV header must be part,stock")
      }
      return
    }
    if !valid_id(id) {
      raise Invalid("stock CSV row \{row} has an invalid part ID")
    }
    let part_index = match part_indices.get(id) {
      Some(part_index) => part_index
      None =>
        raise Invalid("stock CSV row \{row} references unknown part " + id)
    }
    if seen[part_index] {
      raise Invalid("stock CSV row \{row} repeats part " + id)
    }
    seen[part_index] = true
    stocks[part_index] = csv_quantity(count, context, "stock count", max_stock)
  })
  if rows < 2 {
    raise Invalid("stock CSV requires a header and at least one update")
  }
  let updated = snapshot_with_stocks(manifest, stocks)
  ignore(allocate(updated))
  check_pack_catalog(updated)
  updated
}

///|
fn manifest_number(value : Int32) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}

///|
/// Encode a validated snapshot using the same schema read by `parse_manifest`.
pub fn encode_manifest(manifest : Manifest) -> String {
  let parts = manifest.parts.map(part => {
    Json::object(
      Map([
        ("id", Json::string(part.id)),
        ("stock", manifest_number(part.stock)),
        (
          "packs",
          Json::array(
            part.packs.map(pack => {
              Json::object(
                Map([
                  ("id", Json::string(pack.id)),
                  ("quantity", manifest_number(pack.quantity)),
                  ("cost_cents", manifest_number(pack.cost_cents)),
                ]),
              )
            }),
          ),
        ),
      ]),
    )
  })
  let kits = manifest.kits.map(kit => {
    Json::object(
      Map([
        ("id", Json::string(kit.id)),
        (
          "items",
          Json::array(
            kit.items.map(item => {
              Json::object(
                Map([
                  ("item", Json::string(item.item)),
                  ("quantity", manifest_number(item.quantity)),
                ]),
              )
            }),
          ),
        ),
      ]),
    )
  })
  let orders = manifest.orders.map(order => {
    Json::object(
      Map([
        ("id", Json::string(order.id)),
        ("kit", Json::string(order.kit)),
        ("quantity", manifest_number(order.quantity)),
      ]),
    )
  })
  Json::object(
    Map([
      ("schema", Json::string("benchkitmap/v1")),
      ("parts", Json::array(parts)),
      ("kits", Json::array(kits)),
      ("orders", Json::array(orders)),
    ]),
  ).stringify()
}
