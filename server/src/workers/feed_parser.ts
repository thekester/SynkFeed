import { XMLParser } from "fast-xml-parser";

export interface CollectedFeed {
  title: string;
  siteUrl: string | null;
  description: string | null;
  articles: CollectedArticle[];
}

export interface CollectedArticle {
  externalId: string;
  canonicalUrl: string;
  title: string;
  author: string | null;
  summary: string | null;
  contentHtml: string | null;
  publishedAt: Date | null;
  updatedAt: Date | null;
}

const parser = new XMLParser({ ignoreAttributes: false, attributeNamePrefix: "@_" });

export function parseFeed(source: string, feedUrl: string): CollectedFeed {
  const parsed = parser.parse(source) as Record<string, unknown>;
  if (isRecord(parsed.rss)) return parseRss(parsed.rss, feedUrl);
  if (isRecord(parsed.feed)) return parseAtom(parsed.feed, feedUrl);
  throw new Error("unsupported_feed_format");
}

function parseRss(rss: Record<string, unknown>, feedUrl: string): CollectedFeed {
  const channel = isRecord(rss.channel) ? rss.channel : rss;
  return {
    title: text(channel.title) ?? new URL(feedUrl).hostname,
    siteUrl: httpUrl(text(channel.link)),
    description: text(channel.description),
    articles: array(channel.item).filter(isRecord).map((item) => {
      const link = httpUrl(text(item.link)) ?? feedUrl;
      const summary = text(item.description);
      return {
        externalId: text(item.guid) ?? link,
        canonicalUrl: link,
        title: text(item.title) ?? link,
        author: text(item.author),
        summary,
        contentHtml: text(item["content:encoded"]) ?? summary,
        publishedAt: date(text(item.pubDate)),
        updatedAt: date(text(item.pubDate)),
      };
    }),
  };
}

function parseAtom(feed: Record<string, unknown>, feedUrl: string): CollectedFeed {
  return {
    title: text(feed.title) ?? new URL(feedUrl).hostname,
    siteUrl: atomLink(feed.link),
    description: text(feed.subtitle),
    articles: array(feed.entry).filter(isRecord).map((entry) => {
      const link = atomLink(entry.link) ?? feedUrl;
      const summary = text(entry.summary);
      const author = isRecord(entry.author) ? text(entry.author.name) : null;
      return {
        externalId: text(entry.id) ?? link,
        canonicalUrl: link,
        title: text(entry.title) ?? link,
        author,
        summary,
        contentHtml: text(entry.content) ?? summary,
        publishedAt: date(text(entry.published)),
        updatedAt: date(text(entry.updated) ?? text(entry.published)),
      };
    }),
  };
}

function atomLink(value: unknown): string | null {
  for (const link of array(value)) {
    if (isRecord(link) && (link["@_rel"] === undefined || link["@_rel"] === "alternate")) {
      const result = httpUrl(text(link["@_href"]));
      if (result !== null) return result;
    }
  }
  return null;
}

function text(value: unknown): string | null {
  if (typeof value === "string" || typeof value === "number") return String(value).trim();
  if (isRecord(value)) return text(value["#text"]);
  return null;
}

function array(value: unknown): unknown[] {
  if (value === undefined || value === null) return [];
  return Array.isArray(value) ? value : [value];
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function httpUrl(value: string | null): string | null {
  if (value === null) return null;
  try {
    const url = new URL(value);
    return url.protocol === "http:" || url.protocol === "https:" ? url.toString() : null;
  } catch {
    return null;
  }
}

function date(value: string | null): Date | null {
  if (value === null) return null;
  const result = new Date(value);
  return Number.isNaN(result.valueOf()) ? null : result;
}
