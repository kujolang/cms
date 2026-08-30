import { readFile } from "node:fs/promises";
import { basename } from "node:path";

const [file, altText = ""] = process.argv.slice(2);
if (!file) throw new Error("file is required");
process.stdout.write(JSON.stringify({ filename: basename(file), data_base64: (await readFile(file)).toString("base64"), alt_text: altText }));
