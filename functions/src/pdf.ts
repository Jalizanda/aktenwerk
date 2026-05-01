/**
 * PDF-Text-Extraktion mit pdfjs-dist (Mozilla PDF.js).
 * Liefert seitenweise Text und chunked ihn mit Überlappung.
 */

import * as pdfjs from "pdfjs-dist/legacy/build/pdf.mjs";

export interface NormChunk {
  page: number;
  text: string;
}

const CHUNK_TOKEN_TARGET = 500; // ungefähr 500 Wörter / Tokens
const CHUNK_OVERLAP = 80;
const MIN_CHUNK_WORDS = 20;

export async function extractPdfChunks(buffer: Buffer): Promise<NormChunk[]> {
  // pdfjs-dist erwartet Uint8Array; aus dem Buffer kopieren wir.
  const data = new Uint8Array(buffer);
  // `disableWorker` und `isEvalSupported` sind in der serverlosen Umgebung
  // nötig, um den Web-Worker-Pfad zu vermeiden.
  const loadingTask = pdfjs.getDocument({
    data,
    disableFontFace: true,
    isEvalSupported: false,
    useSystemFonts: false,
  });
  const doc = await loadingTask.promise;

  const chunks: NormChunk[] = [];
  for (let i = 1; i <= doc.numPages; i++) {
    const page = await doc.getPage(i);
    const content = await page.getTextContent();
    const raw = content.items
      .map((item: any) => (typeof item.str === "string" ? item.str : ""))
      .join(" ");
    const cleaned = normalizeWhitespace(raw);
    if (!cleaned) continue;
    pushChunksFromPage(chunks, i, cleaned);
  }
  await doc.destroy();
  return chunks;
}

function pushChunksFromPage(out: NormChunk[], page: number, text: string): void {
  const words = text.split(/\s+/);
  if (words.length <= CHUNK_TOKEN_TARGET) {
    out.push({ page, text });
    return;
  }
  const step = CHUNK_TOKEN_TARGET - CHUNK_OVERLAP;
  for (let start = 0; start < words.length; start += step) {
    const end = Math.min(start + CHUNK_TOKEN_TARGET, words.length);
    if (end - start < MIN_CHUNK_WORDS && start > 0) break;
    out.push({ page, text: words.slice(start, end).join(" ") });
    if (end === words.length) break;
  }
}

function normalizeWhitespace(text: string): string {
  return text
    .replace(/ /g, " ")
    .replace(/[ \t]+/g, " ")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}
