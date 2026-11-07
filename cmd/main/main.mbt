///|
priv struct CliOptions {
  input : String
  format : @kit.OutputFormat
  output : String?
}

///|
let usage : String = "BenchKitMap plans lab kits from a local inventory snapshot.\n" +
  "Usage: plan INPUT [--format json|pick-csv|buy-csv] [--out NEW_FILE]\n" +
  "       project INPUT [--out NEW_FILE]\n" +
  "       refresh-stock INPUT COUNTS.csv [--out NEW_FILE]\n" +
  "       issue INPUT ORDER QUANTITY [--out NEW_FILE]\n" +
  "Reads a regular UTF-8 JSON file up to 2 MiB. Prints the report by default.\n" +
  "--out publishes to a new file on a filesystem that supports hard links.\n" +
  "Exit 0: plan produced (possibly with shortages). Exit 2: input or I/O error.\n"

///|
fn parse_options(
  args : FixedArray[String],
  positionals : Int32,
  allow_format : Bool,
) -> CliOptions raise @kit.PlanError {
  let first_option = positionals + 1
  if args.length() < first_option {
    raise @kit.Invalid(args[0] + " is missing required arguments")
  }
  for i in 1..<first_option {
    if args[i] == "" || args[i].has_prefix("--") {
      raise @kit.Invalid(args[0] + " is missing required arguments")
    }
  }
  let mut format : @kit.OutputFormat? = None
  let mut output : String? = None
  let mut index = first_option
  while index < args.length() {
    let option = args[index]
    if (option != "--format" || !allow_format) && option != "--out" {
      raise @kit.Invalid("unexpected argument: " + option)
    }
    if index + 1 >= args.length() ||
      args[index + 1] == "" ||
      args[index + 1].has_prefix("--") {
      raise @kit.Invalid("missing value for " + option)
    }
    let value = args[index + 1]
    if option == "--format" {
      if format is Some(_) {
        raise @kit.Invalid("duplicate --format")
      }
      format = Some(
        match value {
          "json" => @kit.JsonReport
          "pick-csv" => @kit.PickCsv
          "buy-csv" => @kit.BuyCsv
          _ => raise @kit.Invalid("--format must be json, pick-csv, or buy-csv")
        },
      )
    } else {
      if output is Some(_) {
        raise @kit.Invalid("duplicate --out")
      }
      output = Some(value)
    }
    index += 2
  }
  { input: args[1], format: format.unwrap_or(@kit.JsonReport), output, }
}

///|
#external
priv type FileResult

///|
extern "js" fn FileResult::error(self : Self) -> String =
  #| result => result.error

///|
extern "js" fn FileResult::text(self : Self) -> String =
  #| result => result.text

///|
extern "js" fn FileResult::warning(self : Self) -> String =
  #| result => result.warning

///|
extern "js" fn read_utf8(input : String) -> FileResult =
  #| input => {
  #|   const limit = 2 * 1024 * 1024;
  #|   try {
  #|     const fs = process.getBuiltinModule("node:fs");
  #|     if (!fs.lstatSync(input).isFile()) throw Error("input must be a regular file");
  #|     const flags = fs.constants.O_RDONLY | (fs.constants.O_NOFOLLOW ?? 0) |
  #|       (fs.constants.O_NONBLOCK ?? 0);
  #|     const fd = fs.openSync(input, flags);
  #|     try {
  #|       const before = fs.fstatSync(fd, { bigint: true });
  #|       if (!before.isFile()) throw Error("input must be a regular file");
  #|       if (before.size > BigInt(limit)) throw Error("input exceeds 2 MiB");
  #|       const buffer = Buffer.allocUnsafe(Number(before.size) + 1);
  #|       let used = 0;
  #|       while (used < buffer.length) {
  #|         const count = fs.readSync(fd, buffer, used, buffer.length - used, used);
  #|         if (count === 0) break;
  #|         used += count;
  #|       }
  #|       const after = fs.fstatSync(fd, { bigint: true });
  #|       if (BigInt(used) !== before.size || after.size !== before.size ||
  #|           after.mtimeNs !== before.mtimeNs || after.ctimeNs !== before.ctimeNs) {
  #|         throw Error("input changed while reading");
  #|       }
  #|       let text;
  #|       try {
  #|         text = new TextDecoder("utf-8", { fatal: true }).decode(buffer.subarray(0, used));
  #|       } catch {
  #|         throw Error("input is not valid UTF-8");
  #|       }
  #|       return { error: "", text, warning: "" };
  #|     } finally {
  #|       fs.closeSync(fd);
  #|     }
  #|   } catch (error) {
  #|     return { error: String(error.message ?? error), text: "", warning: "" };
  #|   }
  #| }

///|
extern "js" fn write_new(output : String, text : String) -> FileResult =
  #| (output, text) => {
  #|   const fs = process.getBuiltinModule("node:fs");
  #|   const path = process.getBuiltinModule("node:path");
  #|   let stage, stagedFile, stageIdentity;
  #|   let ownsFile = false;
  #|   let failure = "", warning = "";
  #|   try {
  #|     const requested = path.resolve(output);
  #|     const parent = fs.realpathSync(path.dirname(requested));
  #|     const target = path.join(parent, path.basename(requested));
  #|     stage = fs.mkdtempSync(path.join(parent, ".benchkitmap-"));
  #|     stageIdentity = fs.lstatSync(stage, { bigint: true });
  #|     stagedFile = path.join(stage, "report");
  #|     const fd = fs.openSync(stagedFile, "wx", 0o600);
  #|     ownsFile = true;
  #|     try {
  #|       fs.writeFileSync(fd, text, "utf8");
  #|       fs.fsyncSync(fd);
  #|     } finally {
  #|       fs.closeSync(fd);
  #|     }
  #|     // A hard link publishes the complete file and fails if the target exists.
  #|     fs.linkSync(stagedFile, target);
  #|   } catch (error) {
  #|     failure = error.code === "EEXIST"
  #|       ? "output already exists"
  #|       : String(error.message ?? error);
  #|   }
  #|   if (stage !== undefined) {
  #|     try {
  #|       const current = fs.lstatSync(stage, { bigint: true });
  #|       if (!stageIdentity || !current.isDirectory() || current.dev !== stageIdentity.dev ||
  #|           current.ino !== stageIdentity.ino || current.birthtimeNs !== stageIdentity.birthtimeNs) {
  #|         throw Error("staging directory identity changed");
  #|       }
  #|       if (ownsFile) fs.unlinkSync(stagedFile);
  #|       fs.rmdirSync(stage);
  #|     } catch (error) {
  #|       warning = "could not clean staging path " + stage + ": " + String(error.message ?? error);
  #|     }
  #|   }
  #|   return { error: failure, text: "", warning };
  #| }

///|
extern "js" fn arguments() -> FixedArray[String] =
  #| () => process.argv.slice(2)

///|
extern "js" fn write_stdout(text : String) -> Unit =
  #| text => { process.stdout.write(text); }

///|
extern "js" fn write_stderr(text : String) -> Unit =
  #| text => { process.stderr.write(text + "\n"); }

///|
extern "js" fn set_exit_code(code : Int32) -> Unit =
  #| code => { process.exitCode = code; }

///|
fn load_text(input : String) -> String raise @kit.PlanError {
  let file = read_utf8(input)
  if file.error() != "" {
    raise @kit.Invalid(file.error())
  }
  file.text()
}

///|
fn publish_report(text : String, output : String?) -> Unit raise @kit.PlanError {
  let text = if text.has_suffix("\n") { text } else { text + "\n" }
  match output {
    None => write_stdout(text)
    Some(path) => {
      let written = write_new(path, text)
      if written.warning() != "" {
        write_stderr("warning: " + written.warning())
      }
      if written.error() != "" {
        raise @kit.Invalid(written.error())
      }
    }
  }
}

///|
fn issue_quantity(text : String) -> Int32 raise @kit.PlanError {
  let mut value = 0
  for digit in text.iter() {
    if digit < '0' || digit > '9' {
      raise @kit.Invalid("issue quantity must be a positive decimal integer")
    }
    value = value * 10 + digit.to_int() - '0'.to_int()
    if value > 1_000_000 {
      raise @kit.Invalid("issue quantity exceeds 1000000")
    }
  }
  if value == 0 {
    raise @kit.Invalid("issue quantity must be positive")
  }
  value
}

///|
fn run(args : FixedArray[String]) -> Unit raise @kit.PlanError {
  match args {
    [] | ["help"] | ["--help"] | ["-h"] | ["plan", "--help"] | ["plan", "-h"] =>
      write_stdout(usage)
    ["plan", ..] => {
      let options = parse_options(args, 1, true)
      let result = @kit.plan(@kit.parse_manifest(load_text(options.input)))
      publish_report(@kit.render_plan(result, options.format), options.output)
    }
    ["project", ..] => {
      let options = parse_options(args, 1, false)
      let result = @kit.project_after_purchase(
        @kit.parse_manifest(load_text(options.input)),
      )
      publish_report(@kit.render_projection(result), options.output)
    }
    ["refresh-stock", ..] => {
      let options = parse_options(args, 2, false)
      let manifest = @kit.parse_manifest(load_text(options.input))
      let updated = @kit.refresh_stock(manifest, load_text(args[2]))
      ignore(@kit.allocate(updated))
      publish_report(@kit.encode_manifest(updated), options.output)
    }
    ["issue", ..] => {
      let options = parse_options(args, 3, false)
      let quantity = issue_quantity(args[3])
      let manifest = @kit.parse_manifest(load_text(options.input))
      let updated = @kit.record_issue(manifest, args[2], quantity)
      publish_report(@kit.encode_manifest(updated), options.output)
    }
    [command, ..] => raise @kit.Invalid("unknown command: " + command)
  }
}

///|
fn main {
  run(arguments()) catch {
    @kit.Invalid(message) => {
      write_stderr("BenchKitMap: " + message)
      set_exit_code(2)
    }
  }
}
