import { readdir, readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { createDatabase } from "./pool.js";
import { loadConfig } from "../config.js";

export async function migrate(): Promise<void> {
  const config = loadConfig();
  const database = createDatabase(config.DATABASE_URL);
  const migrationsDirectory = join(dirname(fileURLToPath(import.meta.url)), "migrations");
  try {
    await database.query(`
      CREATE TABLE IF NOT EXISTS schema_migrations (
        name text PRIMARY KEY,
        applied_at timestamptz NOT NULL DEFAULT now()
      )
    `);
    const files = (await readdir(migrationsDirectory))
      .filter((name) => name.endsWith(".sql"))
      .sort();
    for (const name of files) {
      const applied = await database.query(
        "SELECT 1 FROM schema_migrations WHERE name = $1",
        [name],
      );
      if (applied.rowCount !== 0) continue;
      const sql = await readFile(join(migrationsDirectory, name), "utf8");
      await database.transaction(async (client) => {
        await client.query(sql);
        await client.query("INSERT INTO schema_migrations(name) VALUES ($1)", [name]);
      });
      process.stdout.write(`Applied migration ${name}\n`);
    }
  } finally {
    await database.close();
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  await migrate();
}
