///|
const STOCK_CSV_BYTES : Int32 = 2_097_152

///|
fn stock_csv_cell(raw : StringView, row : Int32) -> String raise PlanError {
  let len = raw.length()
  if len > 0 && raw[0] == '"' {
    if len < 2 || raw[len - 1] != '"' {
      raise Invalid("stock CSV row \{row} contains an unterminated quoted cell")
    }
    raw[1:len - 1].to_owned()
  } else {
    raw.to_owned()
  }
}

///|
fn stock_csv_cells(
  line : StringView,
  row : Int32,
) -> (String, String) raise PlanError {
  match line.split_once(",") {
    Some((left, right)) =>
      if right.contains(",") {
        raise Invalid("stock CSV row \{row} must have exactly two cells")
      } else {
        (stock_csv_cell(left, row), stock_csv_cell(right, row))
      }
    None => raise Invalid("stock CSV row \{row} must have exactly two cells")
  }
}

///|
fn stock_csv_quantity(digits : String, row : Int32) -> Int32 raise PlanError {
  if digits.length() == 0 {
    raise Invalid("stock CSV row \{row} has an empty stock count")
  }
  let mut value = 0
  for c in digits {
    if c < '0' || c > '9' {
      raise Invalid(
        "stock CSV row \{row} must use an unsigned decimal stock count",
      )
    }
    // value has already passed the previous bound check, so this step
    // cannot overflow even if the cell has an excessive number of digits.
    value = value * 10 + c.to_int() - '0'.to_int()
    if value > max_quantity {
      raise Invalid("stock CSV row \{row} exceeds \{max_quantity} units")
    }
  }
  value
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
  let bom = csv.length() > 0 && csv[0] == '\u{FEFF}'
  // The accepted grammar is ASCII except for the optional three-byte BOM.
  if csv.length() > STOCK_CSV_BYTES - (if bom { 2 } else { 0 }) {
    raise Invalid("stock CSV exceeds 2 MiB")
  }
  let part_indices : Map[String, Int32] = Map([])
  for index, part in manifest.parts {
    if !valid_id(part.id) || part_indices.contains(part.id) {
      raise Invalid("invalid or duplicate manifest part id: " + part.id)
    }
    part_indices[part.id] = index
  }
  let replacements : Array[Int32?] = Array::make(manifest.parts.length(), None)
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
    if row > 257 {
      raise Invalid("stock CSV supports at most 256 updates")
    }
    let (id, count) = stock_csv_cells(csv[start:end], row)
    start = index + 1
    if row == 1 {
      if id != "part" || count != "stock" {
        raise Invalid("stock CSV header must be part,stock")
      }
      continue
    }
    if !valid_id(id) {
      raise Invalid("stock CSV row \{row} has an invalid part ID")
    }
    let part_index = match part_indices.get(id) {
      Some(part_index) => part_index
      None =>
        raise Invalid("stock CSV row \{row} references unknown part " + id)
    }
    if replacements[part_index] is Some(_) {
      raise Invalid("stock CSV row \{row} repeats part " + id)
    }
    replacements[part_index] = Some(stock_csv_quantity(count, row))
  }
  if row < 2 {
    raise Invalid("stock CSV requires a header and at least one update")
  }
  let parts = []
  for index, part in manifest.parts {
    parts.push({
      id: part.id,
      stock: replacements[index].unwrap_or(part.stock),
      packs: part.packs.copy(),
    })
  }
  {
    parts,
    kits: manifest.kits.map(kit => { id: kit.id, items: kit.items.copy(), }),
    orders: manifest.orders.copy(),
  }
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
