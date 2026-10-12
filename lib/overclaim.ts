import type { OverclaimFlag } from "./schemas";

/**
 * Deterministic overclaim check (packet test 3). Runs on every draft whether
 * or not Gemini answered, and again live while the worker edits.
 * It only warns; it never blocks and never touches status.
 */
const RULES: { pattern: RegExp; term: string; message: string }[] = [
  {
    pattern: /\b(verificad[oa]s?|verified|comprobad[oa]s?)\b/,
    term: "verificado",
    message:
      "Solo una persona independiente puede verificar algo. Quita esta palabra: Sello pone el estado por ti.",
  },
  {
    pattern: /\b(certificad[oa]s?|certified|certificacion)\b/,
    term: "certificado",
    message: "Suena a un papel oficial que la evidencia no muestra. Di qué hiciste, no qué título tienes.",
  },
  {
    pattern: /\b(expert[oa]s?|expert)\b/,
    term: "experto",
    message: "«Experto» es una opinión. Mejor di cuánto tiempo y cuánto volumen manejaste.",
  },
  {
    pattern: /\b(garantizad[oa]s?|garantizo|garantia|guaranteed)\b/,
    term: "garantizado",
    message: "Nadie puede garantizar el futuro. Cuenta lo que ya pasó.",
  },
  {
    pattern: /\bcualquier[a]?\b/,
    term: "cualquier",
    message: "«Cualquier» promete demasiado. Nombra los casos concretos que sí te tocaron.",
  },
  {
    pattern: /\bsiempre\b/,
    term: "siempre",
    message: "«Siempre» es difícil de comprobar. ¿Cuántas veces, en qué periodo?",
  },
  {
    pattern: /\b(todos|todas)\b/,
    term: "todos",
    message: "«Todos» es difícil de comprobar. Mejor da un número aproximado.",
  },
  {
    pattern: /\b100\s?(%|por ?ciento)/,
    term: "100%",
    message: "Un 100% casi nunca se puede demostrar. Usa el dato real aunque sea menor.",
  },
];

/** Lowercase and strip accents so "Experta", "EXPERTA" and "expérta" all match. */
export function normalize(s: string): string {
  return s.normalize("NFD").replace(/\p{Diacritic}/gu, "").toLowerCase();
}

export function ruleFlags(claims: { text: string; scope?: string | null }[]): OverclaimFlag[] {
  const flags: OverclaimFlag[] = [];
  claims.forEach((c, i) => {
    const hay = normalize([c.text, c.scope ?? ""].join(" "));
    for (const r of RULES) {
      if (r.pattern.test(hay)) {
        flags.push({ claim_index: i, term: r.term, message: r.message, source: "rule" });
      }
    }
  });
  return flags;
}

/** AI flags + rule flags, without repeating the same term on the same claim. */
export function mergeFlags(ai: Omit<OverclaimFlag, "source">[], rule: OverclaimFlag[]): OverclaimFlag[] {
  const seen = new Set<string>();
  const out: OverclaimFlag[] = [];
  for (const f of [...rule, ...ai.map((f) => ({ ...f, source: "ai" as const }))]) {
    const key = f.claim_index + ":" + normalize(f.term);
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(f);
  }
  return out;
}
