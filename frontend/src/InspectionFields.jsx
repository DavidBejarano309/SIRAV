import { Plus, Trash2 } from "lucide-react";
import { Field } from "./components";
import { useState } from "react";
import { uploadEvidence, openEvidence } from "./api";
import { ErrorBox } from "./components";
export function EvidenceList({ references = [], onRemove }) {
  const [error, setError] = useState("");
  return (
    <div>
      {references.map((ref, i) => (
        <div className="form-footer" key={ref}>
          <button
            type="button"
            className="button secondary"
            onClick={() => openEvidence(ref).catch((e) => setError(e.message))}
          >
            Descargar evidencia {i + 1}
          </button>
          {onRemove && (
            <button
              type="button"
              className="button secondary"
              onClick={() => onRemove(i)}
            >
              Quitar evidencia {i + 1}
            </button>
          )}
        </div>
      ))}
      {error && <ErrorBox>{error}</ErrorBox>}
    </div>
  );
}
export const emptyInspection = () => ({
  danos: [],
  evidencias: [],
  observaciones: "",
});
export default function InspectionFields({
  value,
  onChange,
  uploadPath,
  onBusyChange,
}) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  async function upload(event) {
    const file = event.target.files[0];
    if (!file) return;
    setBusy(true);
    onBusyChange?.(true);
    setError("");
    try {
      const result = await uploadEvidence(uploadPath, file);
      onChange({
        ...value,
        evidencias: [...value.evidencias, result.referencia],
      });
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
      onBusyChange?.(false);
      event.target.value = "";
    }
  }
  function damage(index, key, text) {
    onChange({
      ...value,
      danos: value.danos.map((item, i) =>
        i === index ? { ...item, [key]: text } : item,
      ),
    });
  }
  return (
    <section>
      <h3>Inspección del vehículo</h3>
      {value.danos.map((item, i) => (
        <div className="damage-row" key={i}>
          <Field
            label="Zona"
            required
            maxLength={60}
            value={item.zona}
            onChange={(e) => damage(i, "zona", e.target.value)}
          />
          <Field
            label="Severidad"
            options={["BAJA", "MEDIA", "ALTA"].map((v) => ({
              value: v,
              label: v,
            }))}
            value={item.severidad}
            onChange={(e) => damage(i, "severidad", e.target.value)}
          />
          <Field
            label="Descripción"
            required
            maxLength={500}
            value={item.descripcion}
            onChange={(e) => damage(i, "descripcion", e.target.value)}
          />
          <button
            type="button"
            className="icon-button"
            aria-label="Eliminar daño"
            onClick={() =>
              onChange({
                ...value,
                danos: value.danos.filter((_, j) => j !== i),
              })
            }
          >
            <Trash2 size={18} />
          </button>
        </div>
      ))}
      <button
        type="button"
        className="button secondary"
        disabled={value.danos.length >= 50}
        onClick={() =>
          onChange({
            ...value,
            danos: [
              ...value.danos,
              { zona: "", severidad: "BAJA", descripcion: "" },
            ],
          })
        }
      >
        <Plus size={16} />
        Agregar daño
      </button>
      <Field
        label="Observaciones de la inspección"
        type="textarea"
        maxLength={2000}
        value={value.observaciones || ""}
        onChange={(e) => onChange({ ...value, observaciones: e.target.value })}
      />
      <Field
        label={
          busy
            ? "Subiendo imagen…"
            : "Adjuntar evidencia (PNG o JPEG, máximo 5 MB)"
        }
        type="file"
        accept="image/png,image/jpeg"
        disabled={busy || value.evidencias.length >= 10}
        onChange={upload}
      />
      {error && <ErrorBox>{error}</ErrorBox>}
      <EvidenceList
        references={value.evidencias}
        onRemove={(i) =>
          onChange({
            ...value,
            evidencias: value.evidencias.filter((_, j) => i !== j),
          })
        }
      />
      <p className="muted">
        Puedes guardar una inspección sin daños. Espera a que termine la carga
        de imágenes antes de guardar.
      </p>
    </section>
  );
}
