/**
 * Postgres errors never reach the screen. The DB raises `sello:<code>`; we map
 * the codes we expect to plain Spanish and everything else to one generic line.
 */
const MESSAGES: Record<string, string> = {
  not_signed_in: "Tu sesión terminó. Vuelve a entrar.",
  own_invite: "Este enlace es para que otra persona confirme tu trabajo. Tú no puedes respaldarte a ti mismo.",
  invite_not_found: "Este enlace no existe o está incompleto.",
  invite_used: "Este enlace ya lo usó otra persona. Pide uno nuevo.",
  no_invite: "Necesitas abrir el enlace de invitación primero.",
  cannot_vouch_own_claim: "No puedes respaldar tu propio trabajo.",
  only_declared_can_be_vouched: "Esta frase ya tiene respaldo o revisión.",
  relationship_length: "Escribe cómo conoces a la persona (2 a 120 caracteres).",
  what_they_saw_length: "Cuenta qué viste con al menos 20 caracteres (máximo 800).",
  reviewer_not_approved: "Tu cuenta aún no está aprobada como revisor.",
  reviewer_is_owner: "No puedes revisar tu propio trabajo.",
  reviewer_conflict_of_interest:
    "No puedes revisar esta prueba porque respaldaste a esta persona. La revisión tiene que ser de alguien independiente.",
  review_not_claimed: "Primero toma esta solicitud de revisión.",
  claim_requires_no_prior_relationship: "Para revisar, confirma que no conoces a esta persona ni has trabajado con ella.",
  scope_required: "Escribe qué revisaste exactamente (10 a 800 caracteres).",
  cannot_infer_required: "Escribe qué NO se puede concluir (10 a 800 caracteres).",
  reason_required: "Escribe la razón (10 a 800 caracteres).",
  already_verified: "Esta frase ya está verificada.",
  not_verified: "Esta frase no está verificada.",
  claim_locked: "Esta frase ya tiene respaldo o revisión, así que ya no se puede editar.",
  proof_locked: "La evidencia ya fue revisada, así que ya no se puede cambiar.",
  link_not_found: "Este enlace no existe.",
  own_link: "Este enlace es para quien decide, no para ti.",
  not_opened: "Primero abre la prueba.",
  already_decided: "Ya se registró una decisión para este enlace.",
  bad_decision: "Elige una de las tres opciones.",
  note_too_long: "La nota puede tener máximo 500 caracteres.",
};

export const GENERIC_ERROR = "Algo salió mal. Intenta otra vez en un momento.";

export function friendlyError(err: { message?: string } | null | undefined): string {
  const m = err?.message?.match(/^sello:([a-z_]+)$/);
  return (m && MESSAGES[m[1]]) || GENERIC_ERROR;
}
