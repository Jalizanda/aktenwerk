/**
 * Aktenwerk RAG-Backend für die Normen-Bibliothek (Hybrid Search + Vertex AI Reranker).
 *
 * Funktionen:
 *  - `indexNormPdf` (Firestore-Trigger): Wird ausgelöst, sobald die App
 *    ein Dokument unter `norm_pdfs/{key}` mit `status='pending'` schreibt.
 *    Lädt die hinterlegte PDF aus Firebase Storage, extrahiert seitenweise
 *    Text inkl. Markdown-Tabellen (`| Spalte 1 | Spalte 2 |`), erzeugt
 *    kontextangereicherte Multilingual-Embeddings (`RETRIEVAL_DOCUMENT`)
 *    und legt jeden Chunk unter `norm_chunks/{chunkId}` ab.
 *
 *  - `normChat` / `normChatHttp`:
 *    1. Bettet Suchanfragen mit `RETRIEVAL_QUERY` in `text-multilingual-embedding-002` ein.
 *    2. Führt eine Hybrid-Suche durch (Firestore Vector Search + gezielter Abruf
 *       explizit genannter DIN-/EN-/ISO-/VOB-Normen).
 *    3. Sortiert die Kandidaten über die **Vertex AI Ranking API**
 *       (`semantic-ranker-default@latest`) + lexikalischem Fachbegriff-Boost
 *       präzise nach Relevanz.
 *    4. Generiert die fundierte Antwort mit Gemini 3.5 Flash inkl. exakter
 *       Quellen-Zitate für Klick-Highlighting.
 */

import { initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { onCall, HttpsError, CallableRequest, onRequest, Request } from "firebase-functions/v2/https";
import { onDocumentWritten, FirestoreEvent, Change, DocumentSnapshot } from "firebase-functions/v2/firestore";
import { getAuth } from "firebase-admin/auth";
import type { Response } from "express";
import { setGlobalOptions } from "firebase-functions/v2";
import * as logger from "firebase-functions/logger";

import { embedTexts, generateAnswer, rerankCandidates, RankCandidate } from "./vertex";
import { extractPdfChunks } from "./pdf";

setGlobalOptions({ region: "europe-west1", maxInstances: 5 });

initializeApp();

const VECTOR_CANDIDATES_K = 24;
const FINAL_TOP_K = 10;
const EMBEDDING_DIMS = 768;

/**
 * Extrahiert normalisierte Norm-Kennungen aus einem Text oder Normtitel
 * (z.B. "DIN EN 1090-2" -> ["din en 1090-2", "1090-2", "1090", "en 1090-2"]).
 */
function extractNormTokens(input: string): string[] {
  const low = input.toLowerCase();
  const tokens = new Set<string>();

  const normRegex =
    /\b(?:din\s+en\s+iso|din\s+en|din\s+iso|din|en\s+iso|en|iso|vob\s*\/?\s*[abc]|asr|etag|ead|ral|trgs|trbs|dvgw|vdi|vde|zdb|bki|mo)[-\s./]*([a-z0-9]+(?:[-./][a-z0-9]+)*)/gi;
  let m: RegExpExecArray | null;
  while ((m = normRegex.exec(low)) !== null) {
    const full = m[0].replace(/\s+/g, " ").trim();
    const compact = full.replace(/[\s\-./]/g, "");
    const numPart = (m[1] ?? "").trim();
    if (full.length >= 3) tokens.add(full);
    if (compact.length >= 3) tokens.add(compact);
    if (numPart.length >= 2) {
      tokens.add(numPart);
      const baseNum = numPart.split(/[-./]/)[0];
      if (baseNum.length >= 3) tokens.add(baseNum);
    }
  }
  return Array.from(tokens).slice(0, 25);
}

// ---------------------------------------------------------------------------
// 1) PDF Indexierung (Firestore-Trigger)
// ---------------------------------------------------------------------------

export const indexNormPdf = onDocumentWritten(
  {
    document: "norm_pdfs/{key}",
    timeoutSeconds: 540,
    memory: "4GiB",
  },
  async (event: FirestoreEvent<Change<DocumentSnapshot> | undefined, { key: string }>) => {
    const after = event.data?.after.data();
    if (!after) return;
    if (after.status !== "pending") return;

    const key = event.params.key;
    const db = getFirestore();
    const pdfRef = db.collection("norm_pdfs").doc(key);

    try {
      await pdfRef.update({
        status: "indexing",
        indexingStartedAt: FieldValue.serverTimestamp(),
      });
    } catch (err) {
      logger.error("Konnte Status nicht auf 'indexing' setzen", err);
      return;
    }

    try {
      const storagePath =
        (after.storagePath as string) || pathFromUrl(after.storageUrl as string);
      if (!storagePath) {
        throw new Error("Weder storagePath noch storageUrl im Doc gesetzt.");
      }

      const bucket = getStorage().bucket();
      const file = bucket.file(storagePath);
      const [exists] = await file.exists();
      if (!exists) {
        throw new Error(`Datei nicht in Storage: ${storagePath}`);
      }
      const [pdfBuffer] = await file.download();

      const chunks = await extractPdfChunks(pdfBuffer);
      if (chunks.length === 0) {
        throw new Error("Keine Text-Chunks aus PDF extrahiert.");
      }

      await deleteExistingChunks(db, key);

      const normId = after.normId as number | undefined;
      const nummer = (after.nummer as string | undefined) ?? "";
      const titel = (after.titel as string | undefined) ?? "";
      const gewerk = (after.gewerk as string | undefined) ?? "";
      const orgId = (after.orgId as string | undefined) ?? "";

      // Kontext-Header in den Embedding-Text einbetten, damit jeder Vektor
      // die Norm-Nummer, den Titel und die Seitenzahl semantisch kennt.
      const textsForEmbedding = chunks.map(
        (c) =>
          `Norm/Regelwerk: ${nummer}${titel ? ` — ${titel}` : ""}${
            gewerk ? ` (${gewerk})` : ""
          } | Seite ${c.page}\n${c.text}`
      );

      const embeddings = await embedTexts(
        textsForEmbedding,
        "RETRIEVAL_DOCUMENT"
      );
      if (embeddings.length !== chunks.length) {
        throw new Error("Embeddings-Länge passt nicht zur Chunk-Anzahl.");
      }

      const docTokens = extractNormTokens(`${nummer} ${titel}`);

      const chunksCol = db.collection("norm_chunks");
      let batch = db.batch();
      for (let i = 0; i < chunks.length; i++) {
        const chunk = chunks[i];
        const embedding = embeddings[i];
        const chunkId = `${key}_${String(i).padStart(4, "0")}`;
        const chunkTokens = Array.from(
          new Set([...docTokens, ...extractNormTokens(chunk.text.slice(0, 600))])
        ).slice(0, 30);

        batch.set(chunksCol.doc(chunkId), {
          pdfKey: key,
          normId: normId ?? null,
          nummer,
          titel,
          gewerk,
          orgId,
          page: chunk.page,
          chunkIdx: i,
          text: chunk.text,
          normTokens: chunkTokens,
          embedding: FieldValue.vector(embedding),
          createdAt: FieldValue.serverTimestamp(),
        });
        if ((i + 1) % 400 === 0) {
          await batch.commit();
          batch = db.batch();
        }
      }
      await batch.commit();

      await pdfRef.update({
        status: "indexed",
        chunkCount: chunks.length,
        embeddingModel: "text-multilingual-embedding-002",
        indexedAt: FieldValue.serverTimestamp(),
        errorMessage: FieldValue.delete(),
      });
      logger.info(`Indexed ${chunks.length} chunks for ${key}`);
    } catch (err) {
      logger.error(`Indexierung fehlgeschlagen für ${key}`, err);
      try {
        await pdfRef.update({
          status: "failed",
          errorMessage: (err instanceof Error ? err.message : String(err)).slice(
            0,
            500
          ),
        });
      } catch {
        // ignore
      }
    }
  }
);

function pathFromUrl(url: string | undefined): string | undefined {
  if (!url) return undefined;
  try {
    const m = url.match(/\/o\/([^?]+)/);
    if (!m) return undefined;
    return decodeURIComponent(m[1]);
  } catch {
    return undefined;
  }
}

async function deleteExistingChunks(
  db: FirebaseFirestore.Firestore,
  key: string
): Promise<void> {
  const snap = await db
    .collection("norm_chunks")
    .where("pdfKey", "==", key)
    .get();
  if (snap.empty) return;
  let batch = db.batch();
  let i = 0;
  for (const doc of snap.docs) {
    batch.delete(doc.ref);
    i++;
    if (i % 400 === 0) {
      await batch.commit();
      batch = db.batch();
    }
  }
  await batch.commit();
}

// ---------------------------------------------------------------------------
// 1b) Hintergrund-Re-Indexierung aller gespeicherten Dokumente & PDFs
// ---------------------------------------------------------------------------

export const reindexAllNormPdfs = onRequest(
  {
    timeoutSeconds: 300,
    memory: "512MiB",
    cors: true,
  },
  async (req: Request, res: Response) => {
    try {
      const db = getFirestore();
      const onlyFailed = req.query.onlyFailed === "true";
      const snap = await db.collection("norm_pdfs").get();
      let updated = 0;

      for (const doc of snap.docs) {
        const st = doc.data().status as string | undefined;
        if (onlyFailed && st === "indexed") continue;
        await doc.ref.update({
          status: "pending",
          updatedAt: FieldValue.serverTimestamp(),
        });
        updated++;
      }

      const bucket = getStorage().bucket();
      const [files] = await bucket.getFiles({ prefix: "normen/" });
      let neuRegistriert = 0;

      for (const file of files) {
        if (!file.name.endsWith(".pdf")) continue;
        const filename = file.name.split("/").pop() || "";
        const cleanName = filename.replace(/\.pdf$/i, "");
        const docKey = `norm_storage_${cleanName.replace(
          /[^A-Za-z0-9._\-]/g,
          "_"
        )}`;
        const docRef = db.collection("norm_pdfs").doc(docKey);
        const docSnap = await docRef.get();

        if (!docSnap.exists) {
          await docRef.set({
            nummer: cleanName,
            titel: cleanName,
            storagePath: file.name,
            status: "pending",
            updatedAt: FieldValue.serverTimestamp(),
          });
          neuRegistriert++;
        }
      }

      res.json({
        success: true,
        message: `Hintergrund-Indexierung gestartet: ${updated} bestehende Dokumente zurückgesetzt, ${neuRegistriert} neue Storage-PDFs registriert.`,
        updated,
        neuRegistriert,
      });
    } catch (err) {
      logger.error("reindexAllNormPdfs failed", err);
      res.status(500).json({ error: (err as Error).message });
    }
  }
);

export const getNormIndexProgress = onRequest(
  {
    timeoutSeconds: 30,
    memory: "256MiB",
    cors: true,
  },
  async (req: Request, res: Response) => {
    try {
      const db = getFirestore();
      const snap = await db.collection("norm_pdfs").get();
      const counts: Record<string, number> = {
        indexed: 0,
        indexing: 0,
        pending: 0,
        failed: 0,
        gesamt: snap.size,
      };
      for (const doc of snap.docs) {
        const st = (doc.data().status as string) || "unbekannt";
        counts[st] = (counts[st] || 0) + 1;
      }
      const chunkSnap = await db.collection("norm_chunks").count().get();
      counts["chunksGesamt"] = chunkSnap.data().count;

      res.json(counts);
    } catch (err) {
      res.status(500).json({ error: (err as Error).message });
    }
  }
);

// ---------------------------------------------------------------------------
// 2) Chat-Endpoint (HTTPS Callable & HTTP)
// ---------------------------------------------------------------------------

interface ChatAnhangItem {
  dateiname?: string;
  mimeType?: string;
  base64Data?: string;
}

interface ChatRequestData {
  frage?: string;
  historie?: { rolle: string; text: string }[];
  normIds?: number[];
  orgId?: string;
  fastMode?: boolean;
  anhaenge?: ChatAnhangItem[];
}

interface ChatQuelle {
  chunkId: string;
  pdfKey?: string;
  normId: string;
  nummer: string;
  titel: string;
  page: string;
  snippet: string;
  storageUrl?: string;
}

function filterUndAnreichernQuellen(
  quellen: ChatQuelle[],
  antwort: string,
  urlMap: Map<string, string>
): ChatQuelle[] {
  const antwortLow = antwort.toLowerCase();
  const antwortCompact = antwortLow.replace(/[\s\-_./]/g, "");

  const gefiltert = quellen.filter((q) => {
    if (!q.nummer) return false;
    const numLow = q.nummer.trim().toLowerCase();
    const numCompact = numLow.replace(/[\s\-_./]/g, "");
    const titleLow = q.titel.trim().toLowerCase();
    const baseNum = numLow.split("-")[0].trim();

    return (
      antwortLow.includes(numLow) ||
      (numCompact.length >= 4 && antwortCompact.includes(numCompact)) ||
      (baseNum.length >= 5 &&
        antwortLow.includes(baseNum) &&
        antwortLow.includes(`s. ${q.page}`)) ||
      (titleLow.length > 5 && antwortLow.includes(titleLow))
    );
  });

  const ergebnis = gefiltert.length > 0 ? gefiltert : quellen.slice(0, 3);
  const seen = new Set<string>();
  const deduped: ChatQuelle[] = [];
  for (const q of ergebnis) {
    const key = `${q.pdfKey || q.nummer}_${q.page}`;
    if (seen.has(key)) continue;
    seen.add(key);
    deduped.push({
      ...q,
      storageUrl:
        (q.pdfKey ? urlMap.get(q.pdfKey) : undefined) ?? q.storageUrl ?? "",
    });
  }
  return deduped;
}

async function ladePdfUrls(
  db: FirebaseFirestore.Firestore,
  quellen: ChatQuelle[]
): Promise<Map<string, string>> {
  const urlMap = new Map<string, string>();
  const keys = Array.from(
    new Set(
      quellen
        .map((q) => q.pdfKey || (q.normId ? `norm_${q.normId}` : ""))
        .filter((k) => k.length > 0)
    )
  );
  if (keys.length === 0) return urlMap;
  try {
    const refs = keys.map((k) => db.collection("norm_pdfs").doc(k));
    const snaps = await db.getAll(...refs);
    for (const s of snaps) {
      if (!s.exists) continue;
      const d = s.data();
      const url = (d?.storageUrl as string) || "";
      if (url) {
        urlMap.set(s.id, url);
      }
    }
  } catch (err) {
    logger.warn("Konnte storageUrls aus norm_pdfs nicht nachladen", err);
  }
  return urlMap;
}

/**
 * Berechnet einen lexikalischen Präzisions-Boost (BM25-ähnlich) für exakte
 * Normnummern, Tabellenreferenzen ("Tab. 6.12", "Tabelle B.3") und Schlüsselwörter.
 */
function computeLexicalBoost(
  query: string,
  nummer: string,
  titel: string,
  text: string
): number {
  const qLow = query.toLowerCase();
  const docFull = `${nummer} ${titel} ${text}`.toLowerCase();
  const docCompact = docFull.replace(/[\s\-./]/g, "");
  let boost = 0;

  // 1) Exakte Norm-Tokens aus der Anfrage im Chunk prüfen
  const qNormTokens = extractNormTokens(query);
  for (const tok of qNormTokens) {
    const tokCompact = tok.replace(/[\s\-./]/g, "");
    if (
      nummer.toLowerCase().includes(tok) ||
      nummer.toLowerCase().replace(/[\s\-./]/g, "").includes(tokCompact)
    ) {
      boost += 0.25;
    } else if (docFull.includes(tok) || docCompact.includes(tokCompact)) {
      boost += 0.12;
    }
  }

  // 2) Tabellen- oder Abschnittsreferenzen (z.B. "Tabelle 3", "Tab. 6.12", "Abschnitt 5.1")
  const tabMatches = qLow.match(/\b(?:tabelle|tab\.|abschnitt|abs\.|anhang)\s*[a-z0-9.]+/gi) ?? [];
  for (const tm of tabMatches) {
    if (docFull.includes(tm.toLowerCase())) {
      boost += 0.2;
    }
  }

  // 3) Fachbegriffe (>= 5 Zeichen) aus der Anfrage
  const words = qLow
    .replace(/[^a-zäöüß0-9\s-]/g, " ")
    .split(/\s+/)
    .filter((w) => w.length >= 5);
  if (words.length > 0) {
    let hits = 0;
    for (const w of words) {
      if (docFull.includes(w)) hits++;
    }
    boost += (hits / words.length) * 0.15;
  }

  return Math.min(boost, 0.45);
}

interface ChatResponse {
  antwort: string;
  quellen: ChatQuelle[];
  modell: string;
  dauerMs: string;
  anzahlChunks: string;
}

/**
 * Gemeinsame Hybrid-RAG-Pipeline mit Vertex AI Cross-Encoder Reranking.
 */
async function fuehreNormChatAus(
  db: FirebaseFirestore.Firestore,
  params: {
    frage: string;
    historie: { rolle: string; text: string }[];
    filterNormIds: number[];
    filterOrgId?: string;
    fastMode: boolean;
    anhaenge: { mimeType: string; base64Data: string }[];
  }
): Promise<ChatResponse> {
  const { frage, historie, filterNormIds, filterOrgId, fastMode, anhaenge } =
    params;
  const t0 = Date.now();

  // 1) Schnelle OCR- & Fragen-Extraktion für Vektorsuche, falls Fotos/Dokumente angehängt sind
  let ocrVolltext = "";
  let suchAnfragen: string[] = [frage];

  if (anhaenge.length > 0) {
    try {
      const ocrText = await generateAnswer({
        system:
          "Du bist ein schneller, präziser OCR- und Fragen-Extrahierer. " +
          "Lies alle Fragen (inkl. Nummer und Antwortoptionen A/B/C/D), Norm-Nummern und Fachbegriffe exakt aus. " +
          "Wenn mehrere Fragen auf dem Blatt stehen, trenne jede Frage mit '---FRAGE---'.",
        userPrompt:
          "Extrahiere alle Fragen, Antwortoptionen, Maßangaben und Normen aus dem Anhang. Trenne mehrere Fragen mit '---FRAGE---'.",
        anhaenge,
        temperature: 0.0,
        maxOutputTokens: 1536,
      });
      if (ocrText && ocrText.trim().length > 0) {
        ocrVolltext = ocrText.trim();
        const teile = ocrVolltext
          .split(/---FRAGE---/i)
          .map((s) => s.trim())
          .filter((s) => s.length >= 8);
        if (teile.length > 1) {
          suchAnfragen = teile
            .slice(0, 15)
            .map((teil) => `${frage}\n${teil}`);
        } else {
          suchAnfragen = [`${frage}\n\n[Inhalt aus Anhang]:\n${ocrVolltext}`];
        }
      }
    } catch (err) {
      logger.warn("Fehler beim OCR-Prepass für Vektorsuche", err);
    }
  } else {
    const textTeile = frage
      .split(/\n(?=\s*(?:Frage\s*)?\d+[\.)]\s+)/i)
      .map((s) => s.trim())
      .filter((s) => s.length >= 12);
    if (textTeile.length > 1 && textTeile.length <= 15) {
      suchAnfragen = textTeile;
    }
  }

  const combinedSearchQuery = ocrVolltext
    ? `${frage}\n${ocrVolltext}`
    : frage;

  // 2) Alle Suchanfragen als RETRIEVAL_QUERY in `text-multilingual-embedding-002` einbetten
  const embeddings = await embedTexts(suchAnfragen, "RETRIEVAL_QUERY");
  const validEmbeddings = embeddings.filter(
    (e) => e && e.length === EMBEDDING_DIMS
  );
  if (validEmbeddings.length === 0) {
    throw new Error("Embedding der Frage fehlgeschlagen.");
  }

  // 3) Hybrid Search:
  //    a) Parallele Firestore Vector Search (Top-24 Kandidaten)
  //    b) Gezielte Abfrage explizit genannter Normen (falls in Frage erwähnt)
  let baseQuery: FirebaseFirestore.Query = db.collection("norm_chunks");
  if (filterOrgId) {
    baseQuery = baseQuery.where("orgId", "==", filterOrgId);
  }
  if (filterNormIds.length > 0 && filterNormIds.length <= 30) {
    baseQuery = baseQuery.where("normId", "in", filterNormIds);
  }

  const limitProFrage =
    validEmbeddings.length === 1
      ? VECTOR_CANDIDATES_K
      : Math.max(4, Math.ceil(32 / validEmbeddings.length));

  const vectorPromises = validEmbeddings.map((emb) =>
    baseQuery
      .findNearest({
        vectorField: "embedding",
        queryVector: FieldValue.vector(emb),
        limit: limitProFrage,
        distanceMeasure: "COSINE",
      })
      .get()
  );

  // Explizite Norm-Tokens aus der Frage für direkten Hybrid-Abruf
  const explicitNormTokens = extractNormTokens(combinedSearchQuery).slice(0, 10);
  const keywordPromise =
    explicitNormTokens.length > 0 && filterNormIds.length === 0
      ? (filterOrgId
          ? db
              .collection("norm_chunks")
              .where("orgId", "==", filterOrgId)
              .where("normTokens", "array-contains-any", explicitNormTokens)
              .limit(12)
              .get()
          : db
              .collection("norm_chunks")
              .where("normTokens", "array-contains-any", explicitNormTokens)
              .limit(12)
              .get()
        ).catch(() => null)
      : Promise.resolve(null);

  const [vectorSnaps, keywordSnap] = await Promise.all([
    Promise.all(vectorPromises),
    keywordPromise,
  ]);

  // Alle Kandidaten-Dokumente deduplizieren (max. 36 Kandidaten für den Reranker)
  const candidateDocsMap = new Map<
    string,
    FirebaseFirestore.QueryDocumentSnapshot
  >();
  if (keywordSnap && !keywordSnap.empty) {
    for (const doc of keywordSnap.docs) {
      candidateDocsMap.set(doc.id, doc);
    }
  }
  for (const s of vectorSnaps) {
    for (const doc of s.docs) {
      if (!candidateDocsMap.has(doc.id) && candidateDocsMap.size < 36) {
        candidateDocsMap.set(doc.id, doc);
      }
    }
  }

  const candidateDocs = Array.from(candidateDocsMap.values());

  if (candidateDocs.length === 0) {
    return {
      antwort:
        "Ich habe in der Normen-Bibliothek keine passenden Stellen gefunden. " +
        "Wenn die Norm hochgeladen ist, prüfe bitte, ob ihre Indexierung abgeschlossen ist.",
      quellen: [],
      modell: "gemini-3.5-flash",
      dauerMs: String(Date.now() - t0),
      anzahlChunks: "0",
    };
  }

  // 4) Cross-Encoder Reranking via Vertex AI Ranking API (`semantic-ranker-default@latest`)
  //    kombiniert mit lexikalischem Fachbegriff-/Normnummern-Boost
  const targetTopK =
    suchAnfragen.length > 1
      ? Math.min(18, Math.max(FINAL_TOP_K, suchAnfragen.length * 2))
      : FINAL_TOP_K;

  const rankCandidatesList: RankCandidate[] = candidateDocs.map((doc) => {
    const d = doc.data();
    const nummer = (d.nummer as string) ?? "";
    const titel = (d.titel as string) ?? "";
    const page = (d.page as number) ?? 0;
    const text = (d.text as string) ?? "";
    return {
      id: doc.id,
      title: `${nummer}${titel ? ` — ${titel}` : ""} (S. ${page})`,
      content: text,
    };
  });

  const reranked = await rerankCandidates(
    combinedSearchQuery,
    rankCandidatesList,
    candidateDocs.length
  );

  const scoreMap = new Map<string, number>();
  for (const r of reranked) {
    scoreMap.set(r.id, r.score);
  }

  const scoredDocs = candidateDocs
    .map((doc) => {
      const d = doc.data();
      const semanticScore = scoreMap.get(doc.id) ?? 0.2;
      const lexicalBoost = computeLexicalBoost(
        combinedSearchQuery,
        (d.nummer as string) ?? "",
        (d.titel as string) ?? "",
        (d.text as string) ?? ""
      );
      return {
        doc,
        totalScore: semanticScore + lexicalBoost,
      };
    })
    .sort((a, b) => b.totalScore - a.totalScore)
    .slice(0, targetTopK)
    .map((item) => item.doc);

  // 5) Kontext & Quellen-Metadaten aufbauen
  const quellen: ChatQuelle[] = [];
  const kontextBlocks: string[] = [];
  for (const doc of scoredDocs) {
    const d = doc.data();
    const nummer = (d.nummer as string) ?? "";
    const titel = (d.titel as string) ?? "";
    const page = (d.page as number) ?? 0;
    const snippet = (d.text as string) ?? "";
    const pdfKey =
      (d.pdfKey as string) ??
      (typeof d.normId === "number" ? `norm_${d.normId}` : "");
    kontextBlocks.push(
      `[Quelle: ${nummer}${titel ? ` (${titel})` : ""} · S. ${page}]\n${snippet}`
    );
    quellen.push({
      chunkId: doc.id,
      pdfKey,
      normId: typeof d.normId === "number" ? String(d.normId) : "",
      nummer,
      titel,
      page: String(page),
      snippet: snippet.slice(0, 650),
    });
  }

  let systemAnweisung =
    "Du bist ein Bauwesen-Sachverständigen-Assistent. Du beantwortest Fragen " +
    "zu DIN-/EN-/ISO-Normen und VOB auf Basis der untenstehenden Auszüge aus der Normen-Bibliothek " +
    "sowie den vom Nutzer bereitgestellten Fotos oder Dokumenten.\n\n" +
    "WICHTIGE REGELN FÜR FRAGEBÖGEN, MULTIPLE-CHOICE- UND OFFENE FRAGEN:\n" +
    "1. Wenn ein Blatt mit einer oder mehreren Fragen fotografiert oder eingegeben wurde, arbeite JEDE Frage der Reihe nach vollständig ab (keine Frage auslassen!).\n" +
    "2. Bei Multiple-Choice-Fragen: Gib sofort als Kurzantwort die Fragenummer, den/die richtigen Antwortbuchstaben (A, B, C, D...) mit dem Zusatz 'Richtig' und eine ganz kurze Begründung inkl. Quelle an:\n" +
    "   Format: **Frage <Nr.>: Antwort <A/B/C/...> – Richtig** (<Stichwort/Wortlaut der Option>) – <kurze Begründung in max. 1 Satz> [Norm · S. Seite]\n" +
    "   (Falls bei einer Frage mehrere Antworten zutreffen oder jede Option bewertet werden soll, nenne alle zutreffenden Buchstaben klar, z.B. **Frage <Nr.>: A = Richtig, B = Falsch, C = Richtig**).\n" +
    "3. Bei offenen Fragen (Freitextfragen): Gib die Fragenummer und direkt dahinter eine kurze, präzise Antwort auf den Punkt (konkrete Maße, Zahlen, Grenzwerte in 1–2 Sätzen oder knappen Stichpunkten) inkl. Quelle:\n" +
    "   Format: **Frage <Nr.>:** <Kurze, präzise Antwort auf den Punkt> [Norm · S. Seite]\n" +
    "4. Zitiere bei jedem Punkt die exakte Quelle in eckigen Klammern exakt wie in der Überschrift angegeben: [Norm · S. Seite].\n" +
    "5. Falls der Nutzer ein Baustellenfoto/Bauteil ohne Fragebogen geschickt hat, analysiere es präzise anhand der Normen mit Quellenangabe [Norm · S. Seite].\n" +
    "6. Wenn für eine einzelne Teilfrage auf einem Fragebogen kein direkter Norm-Auszug vorliegt, beantworte auch diese Frage kurz und fachlich korrekt nach geltendem DIN-/VOB-Fachwissen.";

  if (fastMode) {
    systemAnweisung +=
      "\n\nWICHTIG — FAST-MODUS AKTIV (MAXIMALE KÜRZE & DIREKTHEIT):\n" +
      "- Kein Vorgeplänkel, keine Einleitung, keine Wiederholung der kompletten Fragestellung.\n" +
      "- Bei Multiple-Choice-Fragen: Pro Frage kompakt:\n" +
      "  **Frage <Nr.>: Antwort <A/B/C/...> – Richtig** – <kurze Kernaussage/Begründung in max. 1 Satz> [Norm · S. Seite]\n" +
      "- Bei offenen Fragen: Pro Frage direkt die kurze, präzise Antwort auf den Punkt (max. 1–3 Sätze oder kurze Stichpunkte mit exakten Werten) + [Norm · S. Seite].";
  }

  const kontext = kontextBlocks.join("\n\n---\n\n");
  const ocrHinweis = ocrVolltext
    ? `\n\nErkannter Text / Fragen auf dem fotografierten Blatt:\n${ocrVolltext}`
    : "";
  const userPrompt = `Auszüge aus der Normen-Bibliothek:\n\n${kontext}${ocrHinweis}\n\nFrage / Auftrag: ${frage}\n\nAntwort:`;

  const [antwortRaw, urlMap] = await Promise.all([
    generateAnswer({
      system: systemAnweisung,
      historie: historie.slice(-6),
      userPrompt,
      anhaenge,
    }),
    ladePdfUrls(db, quellen),
  ]);
  const antwort = antwortRaw.trim();
  const relevanteQuellen = filterUndAnreichernQuellen(quellen, antwort, urlMap);

  return {
    antwort,
    quellen: relevanteQuellen,
    modell: "gemini-2.5-flash",
    dauerMs: String(Date.now() - t0),
    anzahlChunks: String(scoredDocs.length),
  };
}

export const normChat = onCall(
  {
    timeoutSeconds: 120,
    memory: "512MiB",
    cors: true,
  },
  async (req: CallableRequest<ChatRequestData>): Promise<ChatResponse> => {
    if (!req.auth?.uid) {
      throw new HttpsError("unauthenticated", "Bitte zuerst anmelden.");
    }

    const data = req.data ?? {};
    const frage = (data.frage ?? "").trim();
    if (!frage) {
      throw new HttpsError("invalid-argument", "Feld 'frage' ist erforderlich.");
    }

    const historie = data.historie ?? [];
    const filterNormIds = data.normIds ?? [];
    const filterOrgId = data.orgId;
    const fastMode = !!data.fastMode;
    const anhaenge = (data.anhaenge ?? [])
      .map((a) => ({
        mimeType: a.mimeType ?? "",
        base64Data: a.base64Data ?? "",
      }))
      .filter((a) => a.mimeType && a.base64Data);

    const db = getFirestore();
    try {
      return await fuehreNormChatAus(db, {
        frage,
        historie,
        filterNormIds,
        filterOrgId,
        fastMode,
        anhaenge,
      });
    } catch (err) {
      logger.error("normChat failed", err);
      throw new HttpsError(
        "internal",
        err instanceof Error ? err.message : String(err)
      );
    }
  }
);

// ---------------------------------------------------------------------------
// 3) Chat-Endpoint als HTTP (umgeht cloud_functions Web-Plugin / Int64-Bug)
// ---------------------------------------------------------------------------

export const normChatHttp = onRequest(
  {
    timeoutSeconds: 120,
    memory: "512MiB",
    cors: true,
  },
  async (req: Request, res: Response) => {
    if (req.method !== "POST") {
      res.status(405).json({ error: "method_not_allowed" });
      return;
    }
    const auth = req.headers.authorization;
    if (!auth?.startsWith("Bearer ")) {
      res.status(401).json({ error: "missing_auth_header" });
      return;
    }
    try {
      await getAuth().verifyIdToken(auth.slice(7));
    } catch (err) {
      logger.warn("Token verification failed", err);
      res.status(401).json({ error: "invalid_token" });
      return;
    }

    const data = (req.body ?? {}) as ChatRequestData & {
      mode?: string;
      system?: string;
      prompt?: string;
    };

    if (data.mode === "direct_json") {
      try {
        const system = String(data.system ?? "").trim();
        const prompt = String(data.prompt ?? data.frage ?? "").trim();
        if (!prompt) {
          res.status(400).json({ error: "prompt_required" });
          return;
        }
        const rawJson = await generateAnswer({
          system,
          userPrompt: prompt,
          temperature: 0.1,
          maxOutputTokens: 8192,
          responseMimeType: "application/json",
        });
        res.json({
          antwort: rawJson,
          quellen: [],
          modell: "gemini-2.5-flash",
          dauerMs: "0",
          anzahlChunks: "0",
        });
        return;
      } catch (err) {
        logger.error("normChatHttp direct_json failed", err);
        res.status(500).json({
          error: "internal",
          message: err instanceof Error ? err.message : String(err),
        });
        return;
      }
    }

    const frage = (data.frage ?? "").trim();
    if (!frage) {
      res.status(400).json({ error: "frage_required" });
      return;
    }

    const historie = data.historie ?? [];
    const filterNormIds = data.normIds ?? [];
    const filterOrgId = data.orgId;
    const fastMode = !!data.fastMode;
    const anhaenge = (data.anhaenge ?? [])
      .map((a: any) => ({
        mimeType: String(a?.mimeType ?? ""),
        base64Data: String(a?.base64Data ?? ""),
      }))
      .filter((a) => a.mimeType && a.base64Data);

    const db = getFirestore();

    try {
      const result = await fuehreNormChatAus(db, {
        frage,
        historie,
        filterNormIds,
        filterOrgId,
        fastMode,
        anhaenge,
      });
      res.json(result);
    } catch (err) {
      logger.error("normChatHttp failed", err);
      res.status(500).json({
        error: "internal",
        message: err instanceof Error ? err.message : String(err),
      });
    }
  }
);

// ---------------------------------------------------------------------------
// 4) Destatis GENESIS-Online Proxy (CORS-Workaround)
// ---------------------------------------------------------------------------

interface DestatisRequest {
  username?: string;
  password?: string;
  tableId?: string;
}

export const destatisProxy = onRequest(
  {
    timeoutSeconds: 60,
    memory: "256MiB",
    cors: true,
  },
  async (req: Request, res: Response) => {
    if (req.method !== "POST") {
      res.status(405).json({ error: "method_not_allowed" });
      return;
    }

    const auth = req.headers.authorization;
    if (!auth?.startsWith("Bearer ")) {
      res.status(401).json({ error: "missing_auth_header" });
      return;
    }
    try {
      await getAuth().verifyIdToken(auth.slice(7));
    } catch (err) {
      logger.warn("Token verification failed", err);
      res.status(401).json({ error: "invalid_token" });
      return;
    }

    const data = (req.body ?? {}) as DestatisRequest;
    const username = (data.username ?? "").trim();
    const password = data.password ?? "";
    const tableId = (data.tableId ?? "61261-0001").trim();
    if (!username || !password) {
      res.status(400).json({ error: "credentials_required" });
      return;
    }

    const params = new URLSearchParams({
      username,
      password,
      name: tableId,
      area: "all",
      format: "csv",
      compress: "false",
      transpose: "false",
      language: "de",
    });
    const url = `https://www-genesis.destatis.de/genesisWS/rest/2020/data/tablefile?${params.toString()}`;

    try {
      const r = await fetch(url, { method: "GET" });
      const body = await r.text();
      res
        .status(r.status)
        .set("Content-Type", "text/csv; charset=utf-8")
        .send(body);
    } catch (err) {
      logger.error("destatisProxy failed", err);
      res.status(502).json({
        error: "upstream_failed",
        message: err instanceof Error ? err.message : String(err),
      });
    }
  }
);
