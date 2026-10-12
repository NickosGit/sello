import { DemoLabel } from "@/components/Labels";

import { NewProofForm } from "./NewProofForm";

export default function NewProofPage() {
  return (
    <main className="flex flex-col gap-5 pt-6">
      <div className="flex flex-col gap-2">
        <h1 className="text-2xl font-extrabold">Nueva prueba de tu trabajo</h1>
        <p className="text-muted">
          Pega algo que ya hiciste. Lo vamos a ordenar en frases cortas que tú revisas antes de guardar.
        </p>
        <DemoLabel />
      </div>
      <NewProofForm />
    </main>
  );
}
