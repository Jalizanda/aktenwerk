/**
 * Layout- und tabellenerhaltende PDF-Text-Extraktion mit pdfjs-dist
 * (inkl. Koordinaten-Gruppierung für DIN-/VOB-Tabellen) sowie
 * automatischem Gemini-OCR-Fallback für gescannte Normen/Merkblätter.
 */

import * as pdfjs from "pdfjs-dist/legacy/build/pdf.mjs";
import { generateAnswer } from "./vertex";

export interface NormChunk {
  page: number;
  text: string;
}

const CHUNK_WORD_TARGET = 450;
const CHUNK_WORD_OVERLAP = 80;
const MIN_CHUNK_WORDS = 15;

interface PositionedTextItem {
  str: string;
  x: number;
  y: number;
  width: number;
  height: number;
}

export async function extractPdfChunks(buffer: Buffer): Promise<NormChunk[]> {
  const pageTexts: { page: number; text: string }[] = [];
  let nonEmptyPages = 0;

  try {
    const data = new Uint8Array(buffer);
    const loadingTask = pdfjs.getDocument({
      data,
      disableFontFace: true,
      isEvalSupported: false,
      useSystemFonts: false,
      stopAtErrors: false,
    });
    const doc = await loadingTask.promise;
    const numPages = doc.numPages;

    for (let i = 1; i <= numPages; i++) {
      try {
        const page = await doc.getPage(i);
        const content = await page.getTextContent();
        const structured = reconstructPageWithTables(content.items as any[]);
        if (structured.length >= 40) {
          nonEmptyPages++;
        }
        if (structured) {
          pageTexts.push({ page: i, text: structured });
        }
      } catch {
        // Einzelne beschädigte Seite überspringen
      }
    }
    await doc.destroy();
  } catch {
    // Falls pdfjs bei beschädigter XRef-Tabelle o.ä. wirft -> Fallback auf Gemini-OCR unten
  }

  // Falls das PDF ein Scan ohne eingebetteten Text ist (oder pdfjs wegen beschädigtem XRef-Header abbrach):
  // Einmaliger multimodaler Gemini-Pass zu strukturiertem Markdown mit Seitentrennern.
  if (nonEmptyPages === 0 && buffer.byteLength <= 20 * 1024 * 1024) {
    try {
      const ocrPages = await extractScannedPdfWithGemini(buffer);
      if (ocrPages.length > 0) {
        const ocrChunks: NormChunk[] = [];
        for (const p of ocrPages) {
          pushLineAwareChunks(ocrChunks, p.page, p.text);
        }
        if (ocrChunks.length > 0) {
          return ocrChunks;
        }
      }
    } catch {
      // Fallback auf vorhandene pdfjs-Ergebnisse
    }
  }

  const chunks: NormChunk[] = [];
  for (const p of pageTexts) {
    pushLineAwareChunks(chunks, p.page, p.text);
  }
  return chunks;
}

/**
 * Rekonstruiert aus den X/Y-Koordinaten der PDF-Text-Elemente echte Zeilen
 * und erkennt Spaltenabstände in Tabellen (`Spalte 1 | Spalte 2 | Spalte 3`).
 */
function reconstructPageWithTables(rawItems: any[]): string {
  const items: PositionedTextItem[] = [];
  for (const it of rawItems) {
    if (!it || typeof it.str !== "string") continue;
    const str = it.str.replace(/\u00a0/g, " ").trim();
    if (!str) continue;
    const tr = Array.isArray(it.transform) ? it.transform : [1, 0, 0, 1, 0, 0];
    const x = typeof tr[4] === "number" ? tr[4] : 0;
    const y = typeof tr[5] === "number" ? tr[5] : 0;
    const width = typeof it.width === "number" ? it.width : str.length * 4.5;
    const height =
      typeof it.height === "number" && it.height > 0
        ? it.height
        : Math.abs(typeof tr[3] === "number" ? tr[3] : 10);
    items.push({ str, x, y, width, height });
  }

  if (items.length === 0) return "";

  // Nach Y absteigend (in PDF-Koordinaten ist oben = größeres Y), bei gleichem Y nach X aufsteigend
  items.sort((a, b) => {
    if (Math.abs(b.y - a.y) > 3.5) {
      return b.y - a.y;
    }
    return a.x - b.x;
  });

  // In Zeilen gruppieren (Toleranz 3.5 pt)
  const rows: { y: number; items: PositionedTextItem[] }[] = [];
  for (const item of items) {
    const lastRow = rows[rows.length - 1];
    if (lastRow && Math.abs(lastRow.y - item.y) <= 3.5) {
      lastRow.items.push(item);
    } else {
      rows.push({ y: item.y, items: [item] });
    }
  }

  const lines: string[] = [];
  let prevY: number | null = null;

  for (const row of rows) {
    row.items.sort((a, b) => a.x - b.x);

    // Prüfen, ob die Zeile größere horizontale Sprünge (Tabellenspalten) aufweist
    let gapCount = 0;
    const segments: string[] = [];
    let currentSegment = row.items[0].str;
    let prevEnd = row.items[0].x + row.items[0].width;

    for (let i = 1; i < row.items.length; i++) {
      const curr = row.items[i];
      const gap = curr.x - prevEnd;
      if (gap > 16) {
        gapCount++;
        segments.push(currentSegment.trim());
        currentSegment = curr.str;
      } else if (gap < -1.5) {
        currentSegment += curr.str;
      } else {
        currentSegment +=
          currentSegment.endsWith("-") && /^[a-zäöüß]/.test(curr.str)
            ? curr.str
            : ` ${curr.str}`;
      }
      prevEnd = Math.max(prevEnd, curr.x + curr.width);
    }
    segments.push(currentSegment.trim());

    const lineText =
      gapCount >= 1 && segments.length >= 2
        ? `| ${segments.join(" | ")} |`
        : segments.join(" ");

    if (prevY !== null && prevY - row.y > 18) {
      lines.push("");
    }
    lines.push(lineText);
    prevY = row.y;
  }

  return lines
    .join("\n")
    .replace(/[ \t]+/g, " ")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

/**
 * Zerlegt den Seitentext zeilenbewusst in Chunks, sodass Tabellenzeilen
 * nicht mitten in der Zeile zerschnitten werden.
 */
function pushLineAwareChunks(
  out: NormChunk[],
  page: number,
  pageText: string
): void {
  const countWords = (s: string) =>
    s
      .trim()
      .split(/\s+/)
      .filter((w) => w.length > 0).length;

  const totalWords = countWords(pageText);
  if (totalWords === 0) return;
  if (totalWords <= CHUNK_WORD_TARGET) {
    out.push({ page, text: pageText });
    return;
  }

  const lines = pageText.split("\n");
  let currentLines: string[] = [];
  let currentWords = 0;
  let lastTableHeader: string | null = null;

  for (const line of lines) {
    const lineWords = countWords(line);
    if (line.startsWith("|") && !lastTableHeader) {
      lastTableHeader = line;
    } else if (!line.startsWith("|") && line.trim().length > 0) {
      lastTableHeader = null;
    }

    if (
      currentWords + lineWords > CHUNK_WORD_TARGET &&
      currentWords >= MIN_CHUNK_WORDS
    ) {
      out.push({ page, text: currentLines.join("\n").trim() });

      // Überlappung aus den letzten Zeilen aufbauen
      const overlapLines: string[] = [];
      let overlapWords = 0;
      for (let i = currentLines.length - 1; i >= 0; i--) {
        const w = countWords(currentLines[i]);
        if (overlapWords + w > CHUNK_WORD_OVERLAP && overlapLines.length > 0) {
          break;
        }
        overlapLines.unshift(currentLines[i]);
        overlapWords += w;
      }
      if (
        lastTableHeader &&
        line.startsWith("|") &&
        !overlapLines.includes(lastTableHeader)
      ) {
        overlapLines.unshift(lastTableHeader);
      }
      currentLines = overlapLines;
      currentWords = overlapWords;
    }

    currentLines.push(line);
    currentWords += lineWords;
  }

  if (currentLines.length > 0 && currentWords >= MIN_CHUNK_WORDS) {
    out.push({ page, text: currentLines.join("\n").trim() });
  } else if (currentLines.length > 0 && out.length > 0 && out[out.length - 1].page === page) {
    out[out.length - 1].text += "\n" + currentLines.join("\n").trim();
  } else if (currentLines.length > 0) {
    out.push({ page, text: currentLines.join("\n").trim() });
  }
}

async function extractScannedPdfWithGemini(
  buffer: Buffer
): Promise<{ page: number; text: string }[]> {
  const base64Data = buffer.toString("base64");
  const md = await generateAnswer({
    system:
      "Du bist ein präziser technischer Dokumenten-Parser für DIN-/EN-Normen und Richtlinien. " +
      "Extrahiere den gesamten Text seitenweise vollständig als Markdown. " +
      "Formatiere alle Tabellen zwingend als Markdown-Tabellen (| Spalte 1 | Spalte 2 |). " +
      "Beginne jede Seite exakt mit einer Zeile '===SEITE <Nummer>==='.",
    userPrompt:
      "Extrahiere alle Seiten dieses technischen Dokuments vollständig inkl. aller Tabellen, Fußnoten, Formeln und Maßangaben. Nutze '===SEITE <Nummer>===' vor jeder Seite.",
    anhaenge: [{ mimeType: "application/pdf", base64Data }],
    temperature: 0.0,
    maxOutputTokens: 8192,
  });

  const result: { page: number; text: string }[] = [];
  const parts = md.split(/===SEITE\s+(\d+)===/i);
  if (parts.length >= 3) {
    for (let i = 1; i < parts.length; i += 2) {
      const pageNum = parseInt(parts[i], 10) || Math.ceil(i / 2);
      const body = (parts[i + 1] ?? "").trim();
      if (body) {
        result.push({ page: pageNum, text: body });
      }
    }
  } else if (md.trim().length > 0) {
    result.push({ page: 1, text: md.trim() });
  }
  return result;
}
