import { buildApp } from "./app.js";
import { loadConfig } from "./config.js";
import { createDatabase } from "./database/pool.js";

const config = loadConfig();
const database = createDatabase(config.DATABASE_URL);
const app = await buildApp(config, database);

for (const signal of ["SIGINT", "SIGTERM"] as const) {
  process.on(signal, () => {
    void app.close().finally(() => process.exit(0));
  });
}

await app.listen({ host: config.HOST, port: config.PORT });
