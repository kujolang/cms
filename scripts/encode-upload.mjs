import { readFile } from "node:fs/promises";

const [file, active = "false"] = process.argv.slice(2);
if (!file) throw new Error("file is required");
process.stdout.write(JSON.stringify({ data_base64: (await readFile(file)).toString("base64"), activate: active === "active" || active === "true" }));
