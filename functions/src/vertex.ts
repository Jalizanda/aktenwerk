/**
 * Vertex-AI-Aufrufe via REST. Wir nutzen den Standard-Service-Account
 * der Cloud Function (Application Default Credentials) für Auth.
 */

import { GoogleAuth } from "google-auth-library";

const PROJECT_ID = process.env.GCLOUD_PROJECT ?? "aktenwerk-88c35";
const LOCATION = "europe-west1";
const EMBEDDING_MODEL = "text-embedding-004";
const GEN_MODEL = "gemini-2.5-flash";

let cachedToken: string | undefined;
let cachedTokenExpiresAt = 0;

async function getAuthHeader(): Promise<string> {
  const now = Date.now();
  if (cachedToken && cachedTokenExpiresAt > now + 60_000) {
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
    : now + 50 * 60_000; // konservativ: 50 min
  return `Bearer ${cachedToken}`;
}

/**
 * Embedded Texte in Batches mit automatischem Retry bei Quota-Limits (429).
 * Vertex-Limit: 250 pro Request — wir nehmen 5 für ein gutes Verhältnis aus
 * Latenz und Token-Kosten. Bei 429 (Quota-Erschöpfung) warten wir
 * exponentiell länger und versuchen es bis zu 5 mal — so überleben wir auch
 * kurzfristige Spitzen, wenn mehrere Functions parallel laufen.
 */
export async function embedTexts(texts: string[]): Promise<number[][]> {
  if (texts.length === 0) return [];
  const url = `https://${LOCATION}-aiplatform.googleapis.com/v1/projects/${PROJECT_ID}/locations/${LOCATION}/publishers/google/models/${EMBEDDING_MODEL}:predict`;

  const out: number[][] = [];
  for (let i = 0; i < texts.length; i += 5) {
    const batch = texts.slice(i, i + 5);
    const body = {
      instances: batch.map((content) => ({ content, task_type: "RETRIEVAL_DOCUMENT" })),
    };
    const data = await fetchWithRetry(url, body, "Embedding");
    const predictions = (data as { predictions?: { embeddings?: { values: number[] } }[] })
      .predictions ?? [];
    for (const p of predictions) {
      const values = p.embeddings?.values;
      if (!values) throw new Error("Embedding-Antwort ohne values");
      out.push(values);
    }
  }
  return out;
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
      const auth = await getAuthHeader();
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
      const retriable =
        resp.status === 429 || resp.status === 503 || resp.status === 500;
      if (!retriable || attempt === maxAttempts - 1) {
        throw new Error(`${label} fehlgeschlagen (${lastErr})`);
      }
    } catch (err) {
      // Netzwerk-Exception (z.B. "fetch failed" / DNS / Timeout) — retriable.
      const isFetchEx =
        err instanceof Error &&
        (err.message.includes("fetch failed") ||
          err.message.includes("ECONNRESET") ||
          err.message.includes("ETIMEDOUT") ||
          err.message.includes("ENOTFOUND") ||
          err.message.includes("EAI_AGAIN"));
      if (!isFetchEx) {
        throw err; // schon vom Status-Block geworfen, oder echter Bug
      }
      lastErr = `network: ${(err as Error).message}`;
      if (attempt === maxAttempts - 1) {
        throw new Error(`${label} fehlgeschlagen (${lastErr})`);
      }
    }
    // Exponentielles Backoff mit etwas Jitter
    const baseMs = 2000 * Math.pow(2, attempt);
    const jitter = Math.floor(Math.random() * 1000);
    await new Promise((r) => setTimeout(r, baseMs + jitter));
  }
  throw new Error(
    `${label} fehlgeschlagen nach ${maxAttempts} Versuchen (${lastErr})`
  );
}

interface AnswerArgs {
  system: string;
  historie: { rolle: string; text: string }[];
  userPrompt: string;
}

/**
 * Ruft Gemini 2.5 Flash via Vertex AI an und liefert den Antworttext zurück.
 */
export async function generateAnswer(args: AnswerArgs): Promise<string> {
  const url = `https://${LOCATION}-aiplatform.googleapis.com/v1/projects/${PROJECT_ID}/locations/${LOCATION}/publishers/google/models/${GEN_MODEL}:generateContent`;
  const auth = await getAuthHeader();

  const contents: { role: string; parts: { text: string }[] }[] = [];
  for (const turn of args.historie) {
    const role = turn.rolle === "user" ? "user" : "model";
    if (turn.text && turn.text.trim().length > 0) {
      contents.push({ role, parts: [{ text: turn.text }] });
    }
  }
  contents.push({ role: "user", parts: [{ text: args.userPrompt }] });

  const body = {
    systemInstruction: { role: "system", parts: [{ text: args.system }] },
    contents,
    generationConfig: {
      temperature: 0.2,
      maxOutputTokens: 2048,
    },
  };
  const resp = await fetch(url, {
    method: "POST",
    headers: { Authorization: auth, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!resp.ok) {
    const errText = await resp.text();
    throw new Error(`Gemini-Aufruf fehlgeschlagen (${resp.status}): ${errText.slice(0, 500)}`);
  }
  const data = (await resp.json()) as {
    candidates?: { content?: { parts?: { text?: string }[] } }[];
  };
  const cand = data.candidates?.[0];
  const text = cand?.content?.parts?.map((p) => p.text ?? "").join("") ?? "";
  return text;
}
