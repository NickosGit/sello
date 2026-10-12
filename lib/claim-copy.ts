import type { ClaimInput } from "./schemas";

/** Plain-Spanish labels for each claim field, shared by the editor and the read views. */
export const FIELD_LABELS: Record<keyof ClaimInput, string> = {
  text: "La frase",
  scope: "Qué cubre",
  conditions: "En qué condiciones",
  ai_assistance: "¿Usaste IA u otra ayuda para hacer el trabajo?",
  revisions: "Correcciones que hiciste",
  missing_info: "Qué dato la haría más fuerte",
  cannot_infer: "Qué NO se puede concluir",
};
