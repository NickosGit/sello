"use client";

import { useRouter } from "next/navigation";
import { useCallback, useEffect, useRef, useState } from "react";

import { GENERIC_ERROR } from "@/lib/errors";

/** Asks /api/draft for a draft. Runs once on mount when `auto`, or on click. */
export function GenerateDraft({
  proofId,
  auto = false,
  label = "Ordenar con IA",
}: {
  proofId: string;
  auto?: boolean;
  label?: string;
}) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const started = useRef(false);

  const run = useCallback(async () => {
    setBusy(true);
    setError(null);
    try {
      const res = await fetch("/api/draft", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ proof_id: proofId }),
      });
      if (!res.ok) {
        const body = await res.json().catch(() => null);
        setError(typeof body?.error === "string" ? body.error : GENERIC_ERROR);
        setBusy(false);
        return;
      }
      router.refresh();
    } catch {
      setError(GENERIC_ERROR);
      setBusy(false);
    }
  }, [proofId, router]);

  useEffect(() => {
    if (auto && !started.current) {
      started.current = true;
      void run();
    }
  }, [auto, run]);

  return (
    <div className="flex flex-col gap-2">
      {busy ? (
        <p role="status" className="rounded-2xl border border-ai/30 bg-ai-soft p-4 text-ai">
          Ordenando tu evidencia en frases… (unos segundos)
        </p>
      ) : (
        <button
          type="button"
          onClick={run}
          className="rounded-2xl border border-ink py-3 font-bold text-ink"
        >
          {label}
        </button>
      )}
      {error && (
        <p role="alert" className="rounded-xl bg-bad-soft p-3 text-bad">
          {error}
        </p>
      )}
    </div>
  );
}
