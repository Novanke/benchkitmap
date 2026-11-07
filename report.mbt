///|
fn report_number(value : Int32) -> Json {
  Json::number(value.to_double())
}

///|
fn issue_json(issue : PartIssue) -> Json {
  Json::object(
    Map([
      ("part", Json::string(issue.part)),
      ("required", report_number(issue.required)),
      ("issued", report_number(issue.issued)),
    ]),
  )
}

///|
fn order_json(order : OrderPlan) -> Json {
  Json::object(
    Map([
      ("id", Json::string(order.id)),
      ("kit", Json::string(order.kit)),
      ("requested", report_number(order.requested)),
      ("buildable", report_number(order.buildable)),
      ("waiting", report_number(order.requested - order.buildable)),
      ("items", Json::array(order.items.map(issue_json))),
    ]),
  )
}

///|
fn balance_json(part : PartBalance) -> Json {
  Json::object(
    Map([
      ("part", Json::string(part.part)),
      ("stock", report_number(part.stock)),
      ("required", report_number(part.required)),
      ("issued", report_number(part.issued)),
      ("remaining_stock", report_number(part.remaining_stock)),
      ("shortage", report_number(part.shortage)),
    ]),
  )
}

///|
fn pack_json(pack : PackCount) -> Json {
  Json::object(
    Map([
      ("id", Json::string(pack.id)),
      ("quantity", report_number(pack.quantity)),
      ("count", report_number(pack.count)),
      ("unit_cost_cents", report_number(pack.unit_cost_cents)),
    ]),
  )
}

///|
fn purchase_json(line : PurchaseLine) -> Json {
  let fields = Map([
    ("part", Json::string(line.part)),
    ("shortage", report_number(line.shortage)),
  ])
  match line.purchase {
    None => fields["status"] = Json::string("unsourced")
    Some(purchase) => {
      fields["status"] = Json::string("priced")
      fields["ordered"] = report_number(purchase.ordered)
      fields["excess"] = report_number(purchase.ordered - purchase.shortage)
      // Amounts can exceed the exact integer range of a JavaScript number.
      fields["cost_cents"] = Json::string(purchase.cost_cents.to_string())
      fields["packs"] = Json::array(purchase.packs.map(pack_json))
    }
  }
  Json::object(fields)
}

///|
fn plan_json(result : Plan) -> Json {
  Json::object(
    Map([
      ("schema", Json::string("benchkitmap/plan-v1")),
      ("orders", Json::array(result.allocation.orders.map(order_json))),
      ("parts", Json::array(result.allocation.parts.map(balance_json))),
      ("purchases", Json::array(result.purchases.map(purchase_json))),
      (
        "purchase_total_cents",
        Json::string(result.purchase_total_cents.to_string()),
      ),
      ("purchase_complete", Json::boolean(result.purchase_complete)),
    ]),
  )
}

///|
fn csv_row(output : StringBuilder, fields : Array[String]) -> Unit {
  for i, field in fields {
    if i > 0 {
      output.write_char(',')
    }
    output.write_char('"')
    for c in field.iter() {
      if c == '"' {
        output.write_char('"')
      }
      output.write_char(c)
    }
    output.write_char('"')
  }
  output.write_string("\r\n")
}

///|
fn pick_csv(result : Plan) -> String {
  let output = StringBuilder()
  csv_row(output, [
    "order", "kit", "requested_kits", "buildable_kits", "part", "required_units",
    "pick_units",
  ])
  for order in result.allocation.orders {
    for line in order.items {
      csv_row(output, [
        order.id,
        order.kit,
        order.requested.to_string(),
        order.buildable.to_string(),
        line.part,
        line.required.to_string(),
        line.issued.to_string(),
      ])
    }
  }
  output.to_string()
}

///|
fn buy_csv(result : Plan) -> String {
  let output = StringBuilder()
  csv_row(output, [
    "part", "shortage_units", "status", "pack", "units_per_pack", "pack_count", "ordered_units",
    "pack_price_cents", "line_price_cents",
  ])
  for line in result.purchases {
    match line.purchase {
      None =>
        csv_row(output, [
          line.part,
          line.shortage.to_string(),
          "unsourced",
          "",
          "",
          "",
          "",
          "",
          "",
        ])
      Some(purchase) =>
        for pack in purchase.packs {
          csv_row(output, [
            line.part,
            line.shortage.to_string(),
            "priced",
            pack.id,
            pack.quantity.to_string(),
            pack.count.to_string(),
            (pack.quantity * pack.count).to_string(),
            pack.unit_cost_cents.to_string(),
            (pack.unit_cost_cents.to_int64() * pack.count.to_int64()).to_string(),
          ])
        }
    }
  }
  output.to_string()
}

///|
/// Serialize a plan created by `plan`. JSON uses strings for aggregate cents.
pub fn render_plan(result : Plan, format : OutputFormat) -> String {
  match format {
    JsonReport => plan_json(result).stringify(indent=2) + "\n"
    PickCsv => pick_csv(result)
    BuyCsv => buy_csv(result)
  }
}
