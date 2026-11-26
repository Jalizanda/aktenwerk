/**
 * Vertex-AI-Aufrufe via REST (Embeddings, Reranking, Gemini Generation).
 * Wir nutzen den Standard-Service-Account der Cloud Function
 * (Application Default Credentials) für Auth.
 */

import { GoogleAuth } from "google-auth-library";

const PROJECT_ID = process.env.GCLOUD_PROJECT ?? "aktenwerk-88c35";
const EMBED_LOCATION = "europe-west1";
const EMBEDDING_MODEL = "text-multilingual-embedding-002";
const GEN_LOCATION = process.env.GEN_LOCATION ?? "europe-west1";
const GEN_MODEL = "gemini-2.5-flash";
const RANKING_MODEL = "semantic-ranker-default@latest";

export type EmbeddingTaskType = "RETRIEVAL_DOCUMENT" | "RETRIEVAL_QUERY";

let cachedToken: string | undefined;
let cachedTokenExpiresAt = 0;

async function getAuthHeader(forceRefresh = false): Promise<string> {
  const now = Date.now();
  if (
    !forceRefresh &&
    cachedToken &&
    cachedTokenExpiresAt > now + 60_000
  ) {
    return `Bearer ${cachedToken}`;
  }
  const auth = new GoogleAuth({
    scopes: ["https://www.googleapis.com/auth/cloud-platform"],
  });
  const client = await auth.getClient();
  const tokenResp = await client.getAccessToken();
  if (!tokenResp.token) {
    throw new Error("Kein Access-Token von ADC erhalten.");
  }
  cachedToken = tokenResp.token;
  cachedTokenExpiresAt = (tokenResp.res?.data?.expires_in as number | undefined)
    ? now + (tokenResp.res!.data.expires_in as number) * 1000
    : now + 30 * 60_000;
  return `Bearer ${cachedToken}`;
}

function invalidateTokenCache(): void {
  cachedToken = undefined;
  cachedTokenExpiresAt = 0;
}

/**
 * Embedded Texte mit `text-multilingual-embedding-002` (768 Dimensionen,
 * optimiert für deutsche Fachtexte & Normen).
 *
 * WICHTIG:
 * - Beim Indexieren von Norm-Chunks: `taskType = "RETRIEVAL_DOCUMENT"`
 * - Beim Suchen einer Nutzerfrage:   `taskType = "RETRIEVAL_QUERY"`
 */
export async function embedTexts(
  texts: string[],
  taskType: EmbeddingTaskType = "RETRIEVAL_DOCUMENT"
): Promise<number[][]> {
  if (texts.length === 0) return [];
  const url = `https://${EMBED_LOCATION}-aiplatform.googleapis.com/v1/projects/${PROJECT_ID}/locations/${EMBED_LOCATION}/publishers/google/models/${EMBEDDING_MODEL}:predict`;

  const out: number[][] = [];
  for (let i = 0; i < texts.length; i += 12) {
    const batch = texts.slice(i, i + 12);
    const body = {
      instances: batch.map((content) => ({
        content,
        task_type: taskType,
      })),
    };
    const data = await fetchWithRetry(url, body, "Embedding");
    const predictions =
      (data as { predictions?: { embeddings?: { values: number[] } }[] })
        .predictions ?? [];
    for (const p of predictions) {
      const values = p.embeddings?.values;
      if (!values) throw new Error("Embedding-Antwort ohne values");
      out.push(values);
    }
  }
  return out;
}

export interface RankCandidate {
  id: string;
  title: string;
  content: string;
}

export interface RankedResult {
  id: string;
  score: number;
}

/**
 * Ruft die Vertex AI Ranking API (`semantic-ranker-default@latest`) auf,
 * um die aus Firestore geladenen Kandidaten-Chunks mittels Cross-Encoder
 * präzise nach Relevanz zur Frage neu zu sortieren.
 */
export async function rerankCandidates(
  query: string,
  candidates: RankCandidate[],
  topN: number
): Promise<RankedResult[]> {
  if (candidates.length === 0) return [];
  if (candidates.length === 1) {
    return [{ id: candidates[0].id, score: 1.0 }];
  }

  const url = `https://discoveryengine.googleapis.com/v1/projects/${PROJECT_ID}/locations/global/rankingConfigs/default_ranking_config:rank`;
  const body = {
    model: RANKING_MODEL,
    query: query.slice(0, 2000),
    records: candidates.slice(0, 100).map((c) => ({
      id: c.id,
      title: c.title.slice(0, 300),
      content: c.content.slice(0, 4000),
    })),
    topN: Math.min(topN, candidates.length),
    ignoreRecordDetailsInResponse: true,
  };

  try {
    const auth = await getAuthHeader();
    const resp = await fetch(url, {
      method: "POST",
      headers: {
        Authorization: auth,
        "Content-Type": "application/json",
        "X-Goog-User-Project": PROJECT_ID,
      },
      body: JSON.stringify(body),
    });
    if (!resp.ok) {
      return candidates.slice(0, topN).map((c, idx) => ({
        id: c.id,
        score: Math.max(0.1, 1 - idx * 0.03),
      }));
    }
    const data = (await resp.json()) as {
      records?: { id: string; score?: number }[];
    };
    const records = data.records ?? [];
    if (records.length === 0) {
      return candidates.slice(0, topN).map((c, idx) => ({
        id: c.id,
        score: Math.max(0.1, 1 - idx * 0.03),
      }));
    }
    return records.map((r) => ({
      id: r.id,
      score: typeof r.score === "number" ? r.score : 0.5,
    }));
  } catch {
    // Graceful Fallback, falls Ranking-API kurzzeitig nicht erreichbar ist
    return candidates.slice(0, topN).map((c, idx) => ({
      id: c.id,
      score: Math.max(0.1, 1 - idx * 0.03),
    }));
  }
}

/**
 * POST mit exponentiellem Backoff bei 429/503/500 UND bei Netzwerk-Fehlern
 * ("fetch failed", ECONNRESET, ETIMEDOUT, …). Wartet 2s, 4s, 8s, 16s, 32s.
 */
async function fetchWithRetry(
  url: string,
  body: unknown,
  label: string,
  maxAttempts = 5
): Promise<unknown> {
  let lastErr = "";
  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    try {
      const auth = await getAuthHeader(attempt > 0);
      const resp = await fetch(url, {
        method: "POST",
        headers: { Authorization: auth, "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
      if (resp.ok) {
        return await resp.json();
      }
      const text = await resp.text();
      lastErr = `${resp.status}: ${text.slice(0, 300)}`;
      if (resp.status === 401) {
        invalidateTokenCache();
      }
      const retriable =
        resp.status === 401 ||
        resp.status === 429 ||
        resp.status === 503 ||
        resp.status === 500;
      if (!retriable || attempt === maxAttempts - 1) {
        throw new Error(`${label} fehlgeschlagen (${lastErr})`);
      }
    } catch (err) {
      const isFetchEx =
        err instanceof Error &&
        (err.message.includes("fetch failed") ||
          err.message.includes("ECONNRESET") ||
          err.message.includes("ETIMEDOUT") ||
          err.message.includes("ENOTFOUND") ||
          err.message.includes("EAI_AGAIN"));
      if (!isFetchEx) {
        throw err;
      }
      lastErr = `network: ${(err as Error).message}`;
      if (attempt === maxAttempts - 1) {
        throw new Error(`${label} fehlgeschlagen (${lastErr})`);
      }
    }
    const baseMs = 2000 * Math.pow(2, attempt);
    const jitter = Math.floor(Math.random() * 1000);
    await new Promise((r) => setTimeout(r, baseMs + jitter));
  }
  throw new Error(
    `${label} fehlgeschlagen nach ${maxAttempts} Versuchen (${lastErr})`
  );
}

export interface ChatAnhangPayload {
  mimeType: string;
  base64Data: string;
}

export interface AnswerArgs {
  system: string;
  historie?: { rolle: string; text: string }[];
  userPrompt: string;
  anhaenge?: ChatAnhangPayload[];
  temperature?: number;
  maxOutputTokens?: number;
  responseMimeType?: string;
}

/**
 * Ruft Gemini 3.5 Flash via Vertex AI an und liefert den Antworttext zurück.
 * Unterstützt multimodale Eingaben (Bilder, Dokumente, PDFs).
 */
export async function generateAnswer(args: AnswerArgs): Promise<string> {
  const host =
    GEN_LOCATION === "global"
      ? "aiplatform.googleapis.com"
      : `${GEN_LOCATION}-aiplatform.googleapis.com`;
  const url = `https://${host}/v1/projects/${PROJECT_ID}/locations/${GEN_LOCATION}/publishers/google/models/${GEN_MODEL}:generateContent`;
  const auth = await getAuthHeader();

  const contents: { role: string; parts: unknown[] }[] = [];
  for (const turn of args.historie ?? []) {
    const role = turn.rolle === "user" ? "user" : "model";
    if (turn.text && turn.text.trim().length > 0) {
      contents.push({ role, parts: [{ text: turn.text }] });
    }
  }

  const userParts: unknown[] = [{ text: args.userPrompt }];
  if (args.anhaenge && args.anhaenge.length > 0) {
    for (const a of args.anhaenge) {
      if (a.base64Data && a.mimeType) {
        userParts.push({
          inlineData: {
            mimeType: a.mimeType,
            data: a.base64Data,
          },
        });
      }
    }
  }

  contents.push({ role: "user", parts: userParts });

  const body = {
    systemInstruction: { role: "system", parts: [{ text: args.system }] },
    contents,
    generationConfig: {
      temperature: args.temperature ?? 0.15,
      maxOutputTokens: args.maxOutputTokens ?? 8192,
      ...(args.responseMimeType
        ? { responseMimeType: args.responseMimeType }
        : {}),
    },
  };
  const resp = await fetch(url, {
    method: "POST",
    headers: { Authorization: auth, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!resp.ok) {
    const errText = await resp.text();
    throw new Error(
      `Gemini-Aufruf fehlgeschlagen (${resp.status}): ${errText.slice(0, 500)}`
    );
  }
  const data = (await resp.json()) as {
    candidates?: { content?: { parts?: { text?: string }[] } }[];
  };
  const cand = data.candidates?.[0];
  const text = cand?.content?.parts?.map((p) => p.text ?? "").join("") ?? "";
  return text;
}
