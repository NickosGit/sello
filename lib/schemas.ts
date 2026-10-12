import { z } from "zod";

/**
 * Same limits as the CHECK constraints in supabase/migrations/001_sello.sql.
 * Used by the forms (client), the server actions and the API routes.
 * If you change one, change the other.
 */
export const LIMITS = {
  title: { min: 3, max: 120 },
  rawEvidence: { min: 20, max: 4000 },
  evidenceLink: { max: 500 },
  decisionMaker: { max: 120 },
  intendedDecision: { max: 200 },
  claimText: { min: 3, max: 400 },
  claimField: { max: 800 },
  maxClaims: 6,
} as const;

const optionalText = (max: number) =>
  z
    .string()
    .trim()
    .max(max)
    .transform((s) => (s === "" ? null : s))
    .nullable()
    .optional()
    .transform((v) => v ?? null);

export const proofInputSchema = z.object({
  title: z.string().trim().min(LIMITS.title.min).max(LIMITS.title.max),
  raw_evidence: z.string().trim().min(LIMITS.rawEvidence.min).max(LIMITS.rawEvidence.max),
  evidence_link: z
    .string()
    .trim()
    .max(LIMITS.evidenceLink.max)
    .transform((s) => (s === "" ? null : s))
    .nullable()
    .optional()
    .transform((v) => v ?? null)
    .refine((v) => v === null || /^https?:\/\//i.test(v), { message: "link" }),
  intended_decision_maker: optionalText(LIMITS.decisionMaker.max),
  intended_decision: optionalText(LIMITS.intendedDecision.max),
});
export type ProofInput = z.infer<typeof proofInputSchema>;

/** One claim as the worker approves it. No `status` field on purpose. */
export const claimInputSchema = z.object({
  text: z.string().trim().min(LIMITS.claimText.min).max(LIMITS.claimText.max),
  scope: optionalText(LIMITS.claimField.max),
  conditions: optionalText(LIMITS.claimField.max),
  ai_assistance: optionalText(LIMITS.claimField.max),
  revisions: optionalText(LIMITS.claimField.max),
  missing_info: optionalText(LIMITS.claimField.max),
  cannot_infer: optionalText(LIMITS.claimField.max),
});
export type ClaimInput = z.infer<typeof claimInputSchema>;

export const CLAIM_FIELDS = [
  "text",
  "scope",
  "conditions",
  "ai_assistance",
  "revisions",
  "missing_info",
  "cannot_infer",
] as const satisfies readonly (keyof ClaimInput)[];

export const approveInputSchema = z.object({
  proof_id: z.uuid(),
  claims: z.array(claimInputSchema).min(1).max(LIMITS.maxClaims),
});

export const draftRequestSchema = z.object({ proof_id: z.uuid() });

/**
 * What we accept back from Gemini. Strings are trimmed and cut to the DB
 * limits; anything with the wrong shape is rejected and we fall back to the
 * simulated draft.
 */
const aiText = (max: number) =>
  z
    .string()
    .nullable()
    .optional()
    .transform((s) => {
      const t = (s ?? "").trim().slice(0, max);
      return t === "" ? null : t;
    });

export const aiDraftSchema = z.object({
  claims: z
    .array(
      z.object({
        text: z
          .string()
          .transform((s) => s.trim().slice(0, LIMITS.claimText.max))
          .pipe(z.string().min(LIMITS.claimText.min)),
        scope: aiText(LIMITS.claimField.max),
        conditions: aiText(LIMITS.claimField.max),
        ai_assistance: aiText(LIMITS.claimField.max),
        revisions: aiText(LIMITS.claimField.max),
        missing_info: aiText(LIMITS.claimField.max),
        cannot_infer: aiText(LIMITS.claimField.max),
      }),
    )
    .min(1)
    .max(LIMITS.maxClaims),
  overclaim_flags: z
    .array(
      z.object({
        claim_index: z.number().int().min(0).max(LIMITS.maxClaims - 1),
        term: z.string().trim().min(1).max(60),
        message: z.string().trim().min(1).max(300),
      }),
    )
    .max(30)
    .default([]),
});
export type AiDraft = z.infer<typeof aiDraftSchema>;
export type DraftClaim = AiDraft["claims"][number];

export type OverclaimFlag = {
  claim_index: number;
  term: string;
  message: string;
  source: "ai" | "rule";
};
