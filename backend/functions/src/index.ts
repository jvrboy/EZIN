import { initializeApp } from "firebase-admin/app";
import { getAuth, type DecodedIdToken } from "firebase-admin/auth";
import { FieldValue, getFirestore, Timestamp } from "firebase-admin/firestore";
import { onRequest } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions";
import { z } from "zod";

initializeApp();
const db = getFirestore();

const calendarEventSchema = z.object({
  source: z.string().min(1),
  externalId: z.string().min(1),
  title: z.string().min(1),
  currency: z.string().min(3).max(8),
  impact: z.enum(["none", "low", "medium", "high"]),
  startsAt: z.string().datetime(),
  actual: z.string().optional(),
  forecast: z.string().optional(),
  previous: z.string().optional(),
  revised: z.boolean().default(false)
});

const newsItemSchema = z.object({
  source: z.string().min(1),
  url: z.string().url(),
  title: z.string().min(1),
  summary: z.string().default(""),
  publishedAt: z.string().datetime(),
  symbols: z.array(z.string()).default([]),
  sentiment: z.number().min(-1).max(1).default(0)
});

const riskEventSchema = z.object({
  userId: z.string().min(1),
  broker: z.string().min(1),
  marginLevel: z.number().finite(),
  equity: z.number().finite(),
  threshold: z.number().finite()
});

type CalendarEvent = z.infer<typeof calendarEventSchema>;
type NewsItem = z.infer<typeof newsItemSchema>;

function stableDocumentId(source: string, externalId: string): string {
  return `${source.trim().toLowerCase().replace(/[^a-z0-9]+/g, "-")}_${externalId.trim().toLowerCase().replace(/[^a-z0-9]+/g, "-")}`.slice(0, 512);
}

async function appendAuditLog(userId: string, action: string, parameters: Record<string, unknown>, result: string): Promise<void> {
  await db.collection("users").doc(userId).collection("audit_log").add({
    userId,
    action,
    parameters,
    result,
    createdAt: FieldValue.serverTimestamp()
  });
}

async function upsertCalendarEvent(event: CalendarEvent): Promise<void> {
  const id = stableDocumentId(event.source, event.externalId);
  await db.collection("calendar_events").doc(id).set({
    ...event,
    startsAt: Timestamp.fromDate(new Date(event.startsAt)),
    updatedAt: FieldValue.serverTimestamp()
  }, { merge: true });
}

async function upsertNewsItem(item: NewsItem): Promise<void> {
  const id = stableDocumentId(item.source, item.url);
  await db.collection("news_items").doc(id).set({
    ...item,
    publishedAt: Timestamp.fromDate(new Date(item.publishedAt)),
    updatedAt: FieldValue.serverTimestamp()
  }, { merge: true });
}

async function requireFirebaseUser(req: Parameters<Parameters<typeof onRequest>[0]>[0]): Promise<DecodedIdToken> {
  const authorization = req.header("authorization") ?? "";
  const match = authorization.match(/^Bearer (.+)$/i);
  if (!match) {
    throw new Error("Missing Firebase bearer token");
  }
  const idToken = match[1];
  if (!idToken) {
    throw new Error("Missing Firebase bearer token");
  }
  return getAuth().verifyIdToken(idToken);
}

export const calendarSyncWorker = onSchedule("every 15 minutes", async () => {
  logger.info("calendarSyncWorker started");
  await db.collection("server_health").doc("calendar-sync-worker").set({
    status: "configured",
    checkedAt: FieldValue.serverTimestamp(),
    cadence: "every 15 minutes"
  }, { merge: true });
});

export const newsIngestionWorker = onSchedule("every 5 minutes", async () => {
  logger.info("newsIngestionWorker started");
  await db.collection("server_health").doc("news-ingestion-worker").set({
    status: "configured",
    checkedAt: FieldValue.serverTimestamp(),
    cadence: "every 5 minutes"
  }, { merge: true });
});

export const ingestCalendarEvent = onRequest({ cors: false }, async (req, res) => {
  try {
    const token = await requireFirebaseUser(req);
    if (token.admin !== true) {
      res.status(403).json({ error: "admin claim required" });
      return;
    }
    const event = calendarEventSchema.parse(req.body);
    await upsertCalendarEvent(event);
    await appendAuditLog(token.uid, "calendar_event_ingested", { source: event.source, externalId: event.externalId }, "accepted");
    res.status(202).json({ status: "accepted" });
  } catch (error) {
    logger.error("ingestCalendarEvent failed", error);
    res.status(400).json({ error: error instanceof Error ? error.message : "invalid request" });
  }
});

export const ingestNewsItem = onRequest({ cors: false }, async (req, res) => {
  try {
    const token = await requireFirebaseUser(req);
    if (token.admin !== true) {
      res.status(403).json({ error: "admin claim required" });
      return;
    }
    const item = newsItemSchema.parse(req.body);
    await upsertNewsItem(item);
    await appendAuditLog(token.uid, "news_item_ingested", { source: item.source, url: item.url }, "accepted");
    res.status(202).json({ status: "accepted" });
  } catch (error) {
    logger.error("ingestNewsItem failed", error);
    res.status(400).json({ error: error instanceof Error ? error.message : "invalid request" });
  }
});

export const riskMonitorWebhook = onRequest({ cors: false }, async (req, res) => {
  try {
    const token = await requireFirebaseUser(req);
    const event = riskEventSchema.parse(req.body);
    if (token.uid !== event.userId && token.admin !== true) {
      res.status(403).json({ error: "user mismatch" });
      return;
    }
    const breached = event.marginLevel <= event.threshold;
    await appendAuditLog(event.userId, "risk_margin_check", {
      broker: event.broker,
      marginLevel: event.marginLevel,
      threshold: event.threshold
    }, breached ? "breached" : "clear");
    res.status(200).json({ status: breached ? "breached" : "clear" });
  } catch (error) {
    logger.error("riskMonitorWebhook failed", error);
    res.status(400).json({ error: error instanceof Error ? error.message : "invalid request" });
  }
});

export const llmProxyWorker = onRequest({ cors: false, timeoutSeconds: 120 }, async (req, res) => {
  try {
    const token = await requireFirebaseUser(req);
    await appendAuditLog(token.uid, "llm_proxy_request", { method: req.method }, "rejected_without_provider_configuration");
    res.status(503).json({
      error: "LLM proxy is deployed but provider routing is not configured for this environment. Configure Secret Manager provider keys before enabling traffic."
    });
  } catch (error) {
    logger.error("llmProxyWorker failed", error);
    res.status(401).json({ error: error instanceof Error ? error.message : "unauthorized" });
  }
});
