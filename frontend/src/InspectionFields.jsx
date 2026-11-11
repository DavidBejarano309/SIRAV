import { Plus, Trash2 } from "lucide-react";
import { Field } from "./components";
export const emptyInspection = () => ({
  danos: [],
  evidencias: [],
  observaciones: "",
});
export default function InspectionFields({ value, onChange }) {
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
        label="Referencias de evidencias (una por línea)"
        type="textarea"
        value={value.evidencias.join("\n")}
        onChange={(e) =>
          onChange({ ...value, evidencias: e.target.value.split("\n") })
        }
      />
      <p className="muted">
        Puedes guardar una inspección sin daños. Las evidencias son rutas o
        referencias a archivos.
      </p>
    </section>
  );
}
