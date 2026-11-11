# BenchKitMap

BenchKitMap 是一个离线实验套件备料工具。把零件库存、可嵌套的物料清单、供应包装和课次需求放进一张清单，就能得到每个课次今天能配齐几套、应该领多少零件，以及还要买哪些整包。

例如，两节课共用传感器和线材，先给需要机壳的课次配整套。遇到机壳缺货时，工具保留余下传感器给后续课次，采购建议仍覆盖所有尚未满足的净需求。没有报价的缺口会单独标出。

## 运行

安装 [MoonBit 工具链](https://www.moonbitlang.com/download/)，使用 moonc 0.10.16 或更高版本与 Node.js 22.16 或更高版本。核心只使用标准库，支持 Wasm GC 和 JavaScript。磁盘命令使用 Node.js。

```sh
moon build --target js --release --deny-warn
node _build/js/release/build/cmd/main/main.js plan examples/workshop.json
node _build/js/release/build/cmd/main/main.js plan examples/workshop.json --format pick-csv --out pick.csv
node _build/js/release/build/cmd/main/main.js plan examples/workshop.json --format buy-csv --out buy.csv
```

样例里，现场实验的 6 套先配齐 4 套，随后桌面实验的 8 套能配齐 2 套。还缺 8 个传感器，3 件包和 5 件包各买一包共 1,790 分，比任一种包装单独采购便宜。已报价项合计 3,110 分，另有 2 个机壳缺报价。领料 CSV 中的 `pick_units` 是本次可领数量，`required_units` 是原始需求。采购 CSV 的同一零件可以有多条包装行，其中 `shortage_units` 是零件级缺口，无需按行相加。

JSON 每个订单的 `items` 包含每套用量、订单开始时可用库存和 `limits_order`。当订单未配齐时，`limits_order` 标出限制本轮能配齐几套的零件；多种零件并列时会全部标出。

## 继续处理同一批备料

```sh
# 假设所有已报价包装到货，看看各课次能配齐多少套
node _build/js/release/build/cmd/main/main.js project examples/workshop.json

# 供应商分两批到货，每次只把实际收到的整包记入库存
node _build/js/release/build/cmd/main/main.js receive examples/workshop.json examples/delivery-first.csv --out received-first.json
node _build/js/release/build/cmd/main/main.js plan received-first.json
node _build/js/release/build/cmd/main/main.js receive received-first.json examples/delivery-second.csv --out received-second.json
node _build/js/release/build/cmd/main/main.js plan received-second.json

# 从盘点表更新指定库存，生成可继续规划的新清单
node _build/js/release/build/cmd/main/main.js refresh-stock examples/workshop.json examples/recount.csv --out recounted.json

# 实际已领 3 套，生成包含扣减库存与待领数量的新清单
node _build/js/release/build/cmd/main/main.js issue examples/workshop.json field-session 3 --out next.json
node _build/js/release/build/cmd/main/main.js plan next.json
```

`project` 按原优先顺序重新分配假设到货的库存。遇到未报价的缺口，它保留待询价状态。靠后的订单有可能让出原来可领的部分库存，因为到货后靠前的订单开始能够配齐。

`receive` 读取 `part,pack,count` CSV。`part` 是零件 ID，`pack` 是该零件在当前清单中的包装 ID，`count` 是实际到货的整包数。命令按包内件数累加库存，保留订单及物料清单，输出可直接用于 `plan` 的新快照。第一批到货后，样例中两课次可配齐 4 套和 5 套。第二批后为 4 套和 8 套，只剩 2 个机壳缺口。

到货表最多 4,096 行数据，支持 LF、CRLF、UTF-8 BOM 和单行双引号。同一零件的不同包装可以各写一行。同一零件和包装的多箱到货合并成一行。未知包装、非正整包数或累计库存超限会拒绝整批。每批请只对最新快照应用一次。文件不记录到货单号，同一张到货表重复用于新快照会再次增加库存。散件或盘点修正可通过 `refresh-stock` 记录实际库存。

`refresh-stock` 支持表头为 `part,stock` 的两列 CSV，可使用 LF 或 CRLF、UTF-8 BOM 和单行双引号。未列出的零件保留原盘点数。未知或重复 ID、非整数量、带嵌入分隔符或多行的单元格会报错。

`issue` 以当前快照的优先分配为准，校验实际领用的整套数，扣减每种零件并更新待领订单。全部领完的订单会移除。每次确认实际领用后，下一次操作应使用刚生成的快照。同一份旧清单可生成不同的试算分支。

三个库存更新命令都会在输出前校验快照结构，包括物料引用、库存范围和包装 ID。生成的 JSON 如果超过 2 MiB，命令报错且不创建文件。JSON 恰好为 2 MiB 时省略末尾换行，后续命令仍可读取。

默认输出 JSON 到 stdout。`plan` 的格式可选 `json`、`pick-csv` 或 `buy-csv`。退出码 0 表示已生成结果，规划报告可能包含缺料。输入或 I/O 错误返回 2，并写入 stderr。使用 `--out` 时，输出父目录须已存在并支持硬链接。程序先完成暂存写入再发布新文件，拒绝覆盖已有目标。强制结束进程可能留下隐藏的 `.benchkitmap-*` 暂存目录。

## 输入

清单 schema 为 `benchkitmap/v1`，文件必须为 UTF-8，最多 2 MiB。字段见 [完整样例](examples/workshop.json)。

| 字段 | 内容 |
| --- | --- |
| `parts` | 零件 `id`、可用库存 `stock` 和供应包装 `packs`。包装有 `id`、每包 `quantity` 和整包 `cost_cents`。未知报价用空数组。 |
| `kits` | 套件 `id` 及 `items`。每项的 `item` 可引用零件或子套件，`quantity` 是每套所需数量。 |
| `orders` | 课次或订单 `id`、所用 `kit` 和计划套数 `quantity`。数组顺序即领料优先级。完成全部待领订单后的快照可用空数组。 |

ID 大小写敏感，长度 1 到 64，只允许 ASCII 字母、数字、下划线、点和连字符，首字符须为字母或数字。零件与套件共用 ID 空间。清单拒绝重复 JSON 键、未知字段、重复子件边、未知引用和循环依赖。数量和成本采用非负十进制整数。除库存与价格可为零外，输入数量须为正。使用同一币种的分作为价格单位，报告的总价字段用十进制字符串保留完整精度。

计划先展开每个套件需要的实际零件，再按课次顺序从库存分配能配齐的整套。剩余需求减去剩余库存，得到采购缺口。对每个有报价的缺口，按最低总价、最少超买量、最少包数、报价顺序选定包装组合。采购建议为本次缺口的快照，可用于确认采购单和重新盘点。报价按不限量、同币种的整包计算，采购总价不含运费、税费或阶梯价。

输入限制为最多 256 种零件、256 种套件、256 个订单、每套 256 项和每零件 16 种报价。每包件数、每行到货包数、订单套数和展开后的单零件累计需求上限为 1,000,000。单零件库存上限为 1,999,999，可保留按建议采购到货后超买的实际件数。额外到货或盘点仍须遵守库存上限。每包价格上限为 1,000,000,000 分。每个零件的报价若具有相同包内件数，直接选最低价，价格相同选最先列出的报价，可处理完整需求上限。混合包内件数的报价精确求解使用最多 100,000 个经最大公约数缩放后的状态，超限返回明确错误。

库存超过 1,000,000 件的快照需使用 0.2.2 或更高版本读取。

## MoonBit SDK

```sh
moon add Novanke/benchkitmap@0.2.3
```

在使用方的 `moon.pkg` 导入 `"Novanke/benchkitmap" @kit`。使用 `@kit.parse_manifest(text)` 解析清单，`@kit.plan(manifest)` 生成计划，`@kit.render_plan(plan, @kit.JsonReport)` 导出。若调用方已有结构化数据，可直接构造 `Manifest`，规划入口仍会验证引用、数量和报价。纯核心示例见 [examples/sdk](examples/sdk/main.mbt)。

SDK 同时提供 `project_after_purchase`、`refresh_stock`、`record_issue` 和 `encode_manifest`。记录到货可直接构造 `PackDelivery`，也可以先调用 `parse_deliveries_csv`，再把结果交给 `receive_packs`。复现数据见 [验证记录](docs/verification.md)。

```sh
moon test --target wasm-gc --deny-warn
moon test --target js --deny-warn
moon run examples/sdk --target wasm-gc --release --deny-warn
moon run examples/sdk --target js --release --deny-warn
python scripts/cli_smoke.py
```

使用 Apache-2.0 许可证。样例使用合成物料和报价。
