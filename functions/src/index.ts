/**
 * Aktenwerk RAG-Backend für die Normen-Bibliothek.
 *
 * Zwei Funktionen:
 *  - `indexNormPdf` (Firestore-Trigger): Wird ausgelöst, sobald die App
 *    ein Dokument unter `norm_pdfs/{key}` mit `status='pending'` schreibt.
 *    Lädt die hinterlegte PDF aus Firebase Storage, extrahiert seitenweise
 *    Text, chunked ihn, erzeugt Embeddings via Vertex AI und legt jeden
 *    Chunk als eigenes Dokument unter `norm_chunks/{chunkId}` ab.
 *
 *  - `normChat` (HTTPS Callable): Empfängt eine Frage, embedded sie,
 *    macht eine Vector-Search gegen `norm_chunks`, baut den Prompt mit den
 *    Top-K Chunks und ruft Gemini 2.5. Gibt Antwort + Quellen-Liste
 *    zurück (norm-id, nummer, seite, snippet) für Klick-Highlighting.
 *
 * Region: europe-west1 (gleiche Region wie die Vertex-AI-Aufrufe in der App).
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

import { embedTexts, generateAnswer } from "./vertex";
import { extractPdfChunks } from "./pdf";

setGlobalOptions({ region: "europe-west1", maxInstances: 5 });

initializeApp();

const TOP_K = 8;
const EMBEDDING_DIMS = 768;

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

    // Sofort auf "indexing" setzen, damit Re-Triggers nicht doppelt starten.
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
      const storagePath = (after.storagePath as string) || pathFromUrl(after.storageUrl as string);
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

      // Alte Chunks dieses Keys entfernen (Re-Indexing).
      await deleteExistingChunks(db, key);

      const embeddings = await embedTexts(chunks.map((c) => c.text));
      if (embeddings.length !== chunks.length) {
        throw new Error("Embeddings-Länge passt nicht zur Chunk-Anzahl.");
      }

      const normId = after.normId as number | undefined;
      const nummer = (after.nummer as string | undefined) ?? "";
      const titel = (after.titel as string | undefined) ?? "";
      const gewerk = (after.gewerk as string | undefined) ?? "";
      const orgId = (after.orgId as string | undefined) ?? "";

      const chunksCol = db.collection("norm_chunks");
      let batch = db.batch();
      for (let i = 0; i < chunks.length; i++) {
        const chunk = chunks[i];
        const embedding = embeddings[i];
        const chunkId = `${key}_${String(i).padStart(4, "0")}`;
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
        indexedAt: FieldValue.serverTimestamp(),
        errorMessage: FieldValue.delete(),
      });
      logger.info(`Indexed ${chunks.length} chunks for ${key}`);
    } catch (err) {
      logger.error(`Indexierung fehlgeschlagen für ${key}`, err);
      try {
        await pdfRef.update({
          status: "failed",
          errorMessage: (err instanceof Error ? err.message : String(err)).slice(0, 500),
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
  const snap = await db.collection("norm_chunks").where("pdfKey", "==", key).get();
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

      // 1) Alle existierenden norm_pdfs durchgehen und auf status: "pending" setzen
      const snap = await db.collection("norm_pdfs").get();
      let updated = 0;

      for (const doc of snap.docs) {
        await doc.ref.update({
          status: "pending",
          updatedAt: FieldValue.serverTimestamp(),
        });
        updated++;
      }

      // 2) Zusätzlich: Storage durchsuchen nach PDFs unter 'normen/', falls noch kein doc existiert
      const bucket = getStorage().bucket();
      const [files] = await bucket.getFiles({ prefix: "normen/" });
      let neuRegistriert = 0;

      for (const file of files) {
        if (!file.name.endsWith(".pdf")) continue;
        const filename = file.name.split("/").pop() || "";
        const cleanName = filename.replace(/\.pdf$/i, "");
        const docKey = `norm_storage_${cleanName.replace(/[^A-Za-z0-9._\-]/g, "_")}`;
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
// 2) Chat-Endpoint (HTTPS Callable)
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
  normId: string;  // serialisiert als String, um Int64-Issues auf dart2js zu umgehen
  nummer: string;
  titel: string;
  page: string;
  snippet: string;
}

interface ChatResponse {
  antwort: string;
  quellen: ChatQuelle[];
  modell: string;
  dauerMs: string;
  anzahlChunks: string;
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
    const anhaenge = (data.anhaenge ?? []).map((a) => ({
      mimeType: a.mimeType ?? "",
      base64Data: a.base64Data ?? "",
    })).filter((a) => a.mimeType && a.base64Data);

    const db = getFirestore();
    const t0 = Date.now();

    // OCR Pre-pass für Vektorsuche, falls Fotos/Dokumente angehängt sind
    let searchPrompt = frage;
    if (anhaenge.length > 0) {
      try {
        const ocrText = await generateAnswer({
          system:
            "Du bist ein OCR- und Text-Extrahierer. Lies sämtlichen Text, Fragen, Norm-Nummern (z.B. DIN 18360, VOB/C) und Fachbegriffe aus den angehängten Bildern/Dokumenten exakt aus.",
          userPrompt: "Lies den Inhalt und alle Fachbegriffe/Normen aus den Dokumenten/Bildern aus.",
          anhaenge,
        });
        if (ocrText && ocrText.trim().length > 0) {
          searchPrompt = `${frage}\n\n[Inhalt aus Anhang]:\n${ocrText.trim()}`;
        }
      } catch (err) {
        logger.warn("Fehler beim OCR-Prepass für Vektorsuche in normChat", err);
      }
    }

    // 1) Frage embedden
    const [embedding] = await embedTexts([searchPrompt]);
    if (!embedding || embedding.length !== EMBEDDING_DIMS) {
      throw new HttpsError("internal", "Embedding der Frage fehlgeschlagen.");
    }

    // 2) Vector-Search
    let query: FirebaseFirestore.Query = db.collection("norm_chunks");
    if (filterOrgId) {
      query = query.where("orgId", "==", filterOrgId);
    }
    if (filterNormIds.length > 0 && filterNormIds.length <= 30) {
      query = query.where("normId", "in", filterNormIds);
    }
    const vectorQuery = query.findNearest({
      vectorField: "embedding",
      queryVector: FieldValue.vector(embedding),
      limit: TOP_K,
      distanceMeasure: "COSINE",
    });
    const snap = await vectorQuery.get();

    if (snap.empty) {
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

    // 3) Prompt bauen
    const quellen: ChatQuelle[] = [];
    const kontextBlocks: string[] = [];
    for (const doc of snap.docs) {
      const d = doc.data();
      const nummer = (d.nummer as string) ?? "";
      const page = (d.page as number) ?? 0;
      const snippet = (d.text as string) ?? "";
      kontextBlocks.push(`[Quelle: ${nummer} · S. ${page}]\n${snippet}`);
      quellen.push({
        chunkId: doc.id,
        normId: typeof d.normId === "number" ? String(d.normId) : "",
        nummer,
        titel: (d.titel as string) ?? "",
        page: String(page),
        snippet: snippet.slice(0, 500),
      });
    }

    let systemAnweisung =
      "Du bist ein Bauwesen-Sachverständigen-Assistent. Du beantwortest Fragen " +
      "zu DIN-/EN-/ISO-Normen auf Basis der untenstehenden Auszüge aus der Normen-Bibliothek " +
      "sowie den vom Nutzer bereitgestellten Fotos oder Dokumenten. Regeln:\n" +
      "1. Antworte fachlich präzise und in deutscher Sachverständigen-Sprache.\n" +
      "2. Zitiere immer die Quelle in eckigen Klammern: [Norm · Seite].\n" +
      "3. Falls der Nutzer Fotos/Dokumente angehängt hat, beziehe diese direkt in deine Analyse ein (z. B. Baustellenfoto, Schaden, Fenster, Bewehrung).\n" +
      "4. Wenn die Auszüge die Frage nicht eindeutig beantworten, sag das offen " +
      "und schlage konkret vor, welche weitere Norm hilfreich wäre.\n" +
      "5. Erfinde KEINE Norm-Inhalte.";

    if (fastMode) {
      systemAnweisung +=
        "\n\nWICHTIG — FAST-MODUS AKTIV:\n" +
        "- Bei Multiple-Choice-Fragen: Gib NUR kurz die Lösungsnummer/Buchstabe an und eine ganz kurze (max. 1 Satz) Begründung zur richtigen Antwort.\n" +
        "- Bei freien Fragen (Textantwort): Antworte extrem kurz, prägnant und in Stichpunkten. Nur das absolut Essenzielle und Wichtigste sehr schnell antworten.";
    }

    const kontext = kontextBlocks.join("\n\n---\n\n");
    const userPrompt = `Auszüge aus der Normen-Bibliothek:\n\n${kontext}\n\nFrage: ${frage}\n\nAntwort:`;

    const antwortRaw = await generateAnswer({
      system: systemAnweisung,
      historie: historie.slice(-6),
      userPrompt,
      anhaenge,
    });
    const antwort = antwortRaw.trim();

    // Nur Quellen zurückgeben, die in der Antwort tatsächlich zitiert oder erwähnt werden
    const relevanteQuellen = quellen.filter((q) => {
      if (!q.nummer) return false;
      const antwortLow = antwort.toLowerCase();
      const numLow = q.nummer.trim().toLowerCase();
      const titleLow = q.titel.trim().toLowerCase();
      return (
        antwortLow.includes(numLow) ||
        (titleLow.length > 5 && antwortLow.includes(titleLow))
      );
    });

    return {
      antwort,
      quellen: relevanteQuellen,
      modell: "gemini-3.5-flash",
      dauerMs: String(Date.now() - t0),
      anzahlChunks: String(snap.size),
    };
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
    // Auth-Check via Bearer-Token (Firebase ID Token)
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

    const data = (req.body ?? {}) as ChatRequestData;
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
    const t0 = Date.now();

    try {
      // OCR Pre-pass für Vektorsuche, falls Fotos/Dokumente angehängt sind
      let searchPrompt = frage;
      if (anhaenge.length > 0) {
        try {
          const ocrText = await generateAnswer({
            system:
              "Du bist ein OCR- und Text-Extrahierer. Lies sämtlichen Text, Fragen, Norm-Nummern (z.B. DIN 18360, VOB/C) und Fachbegriffe aus den angehängten Bildern/Dokumenten exakt aus.",
            userPrompt: "Lies den Inhalt und alle Fachbegriffe/Normen aus den Dokumenten/Bildern aus.",
            anhaenge,
          });
          if (ocrText && ocrText.trim().length > 0) {
            searchPrompt = `${frage}\n\n[Inhalt aus Anhang]:\n${ocrText.trim()}`;
          }
        } catch (err) {
          logger.warn("Fehler beim OCR-Prepass für Vektorsuche in normChatHttp", err);
        }
      }

      const [embedding] = await embedTexts([searchPrompt]);
      if (!embedding || embedding.length !== EMBEDDING_DIMS) {
        res.status(500).json({ error: "embedding_failed" });
        return;
      }

      let query: FirebaseFirestore.Query = db.collection("norm_chunks");
      if (filterOrgId) {
        query = query.where("orgId", "==", filterOrgId);
      }
      if (filterNormIds.length > 0 && filterNormIds.length <= 30) {
        query = query.where("normId", "in", filterNormIds);
      }
      const vectorQuery = query.findNearest({
        vectorField: "embedding",
        queryVector: FieldValue.vector(embedding),
        limit: TOP_K,
        distanceMeasure: "COSINE",
      });
      const snap = await vectorQuery.get();

      if (snap.empty) {
        res.json({
          antwort:
            "Ich habe in der Normen-Bibliothek keine passenden Stellen gefunden. " +
            "Wenn the Norm hochgeladen ist, prüfe bitte, ob ihre Indexierung abgeschlossen ist.",
          quellen: [],
          modell: "gemini-3.5-flash",
          dauerMs: String(Date.now() - t0),
          anzahlChunks: "0",
        });
        return;
      }

      const quellen: ChatQuelle[] = [];
      const kontextBlocks: string[] = [];
      for (const doc of snap.docs) {
        const d = doc.data();
        const nummer = (d.nummer as string) ?? "";
        const page = (d.page as number) ?? 0;
        const snippet = (d.text as string) ?? "";
        kontextBlocks.push(`[Quelle: ${nummer} · S. ${page}]\n${snippet}`);
        quellen.push({
          chunkId: doc.id,
          normId: typeof d.normId === "number" ? String(d.normId) : "",
          nummer,
          titel: (d.titel as string) ?? "",
          page: String(page),
          snippet: snippet.slice(0, 500),
        });
      }

      let systemAnweisung =
        "Du bist ein Bauwesen-Sachverständigen-Assistent. Du beantwortest Fragen " +
        "zu DIN-/EN-/ISO-Normen auf Basis der untenstehenden Auszüge aus der Normen-Bibliothek " +
        "sowie den vom Nutzer bereitgestellten Fotos oder Dokumenten. Regeln:\n" +
        "1. Antworte fachlich präzise und in deutscher Sachverständigen-Sprache.\n" +
        "2. Zitiere immer die Quelle in eckigen Klammern: [Norm · Seite].\n" +
        "3. Falls der Nutzer Fotos/Dokumente angehängt hat, beziehe diese direkt in deine Analyse ein (z. B. Baustellenfoto, Schaden, Fenster, Bewehrung).\n" +
        "4. Wenn die Auszüge die Frage nicht eindeutig beantworten, sag das offen " +
        "und schlage konkret vor, welche weitere Norm hilfreich wäre.\n" +
        "5. Erfinde KEINE Norm-Inhalte.";

      if (fastMode) {
        systemAnweisung +=
          "\n\nWICHTIG — FAST-MODUS AKTIV:\n" +
          "- Bei Multiple-Choice-Fragen: Gib NUR kurz die Lösungsnummer/Buchstabe an und eine ganz kurze (max. 1 Satz) Begründung zur richtigen Antwort.\n" +
          "- Bei freien Fragen (Textantwort): Antworte extrem kurz, prägnant und in Stichpunkten. Nur das absolut Essenzielle und Wichtigste sehr schnell antworten.";
      }

      const kontext = kontextBlocks.join("\n\n---\n\n");
      const userPrompt = `Auszüge aus der Normen-Bibliothek:\n\n${kontext}\n\nFrage: ${frage}\n\nAntwort:`;

      const antwortRaw = await generateAnswer({
        system: systemAnweisung,
        historie: historie.slice(-6),
        userPrompt,
        anhaenge,
      });
      const antwort = antwortRaw.trim();

      // Nur Quellen zurückgeben, die tatsächlich in der Antwort zitiert werden
      const relevanteQuellen = quellen.filter((q) => {
        if (!q.nummer) return false;
        const antwortLow = antwort.toLowerCase();
        const numLow = q.nummer.trim().toLowerCase();
        const titleLow = q.titel.trim().toLowerCase();
        return (
          antwortLow.includes(numLow) ||
          (titleLow.length > 5 && antwortLow.includes(titleLow))
        );
      });

      res.json({
        antwort,
        quellen: relevanteQuellen,
        modell: "gemini-3.5-flash",
        dauerMs: String(Date.now() - t0),
        anzahlChunks: String(snap.size),
      });
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
//
// Destatis liefert keine CORS-Header, daher kann der Flutter-Web-Client
// die API nicht direkt aufrufen. Wir tunneln durch eine Cloud Function.
// Body: { username, password, tableId }, Response: CSV als Text.
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

    // Auth-Check via Bearer-Token (Firebase ID Token)
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
      // Destatis liefert auch bei API-Fehlern HTTP 200 mit Fehlertext im
      // Body — wir reichen die Original-Response durch, der Client parst.
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
