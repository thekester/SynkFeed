import fastify, { type FastifyInstance } from "fastify";
import jwt from "@fastify/jwt";
import rateLimit from "@fastify/rate-limit";
import cors from "@fastify/cors";
import { ZodError } from "zod";
import type { AppConfig } from "./config.js";
import type { Database } from "./database/pool.js";
import { registerAuthRoutes } from "./auth/routes.js";
import { registerDeviceRoutes } from "./devices/routes.js";
import { registerSyncRoutes } from "./sync/routes.js";
import { registerSubscriptionRoutes } from "./subscriptions/routes.js";
import { registerArticleRoutes } from "./articles/routes.js";
import "./types.js";

export async function buildApp(config: AppConfig, database: Database): Promise<FastifyInstance> {
  const app = fastify({
    logger: config.NODE_ENV === "test" ? false : { level: config.LOG_LEVEL },
    bodyLimit: 1_048_576,
    requestIdHeader: "x-request-id",
  });

  await app.register(jwt, { secret: config.JWT_SECRET });
  await app.register(rateLimit, { max: 100, timeWindow: "1 minute" });
  if (config.CORS_ALLOWED_ORIGINS.length > 0) {
    await app.register(cors, { origin: config.CORS_ALLOWED_ORIGINS });
  }

  app.get("/health/live", async () => ({ status: "ok" }));
  app.get("/health/ready", async (_request, reply) => {
    try {
      await database.query("SELECT 1");
      return { status: "ready" };
    } catch {
      return reply.code(503).send({ status: "unavailable" });
    }
  });

  registerAuthRoutes(app, database, config);
  registerDeviceRoutes(app, database);
  registerSubscriptionRoutes(app, database);
  registerArticleRoutes(app, database);
  registerSyncRoutes(app, database);

  app.setErrorHandler((error, request, reply) => {
    if (error instanceof ZodError) {
      return reply.code(400).send({
        code: "invalid_request",
        issues: error.issues.map((issue) => ({ path: issue.path.join("."), message: issue.message })),
      });
    }
    request.log.error({ err: error }, "request failed");
    return reply.code(500).send({ code: "internal_error" });
  });

  app.addHook("onClose", async () => database.close());
  return app;
}
