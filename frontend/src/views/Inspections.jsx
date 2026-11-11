import { useState } from "react";
import { api, date } from "../api";
import {
  ErrorBox,
  Field,
  Form,
  Loading,
  Modal,
  PageHead,
  Table,
  useResource,
} from "../components";
import InspectionFields from "../InspectionFields";
export default function Inspections({ admin, revision, changed }) {
  const [severe, setSevere] = useState(false);
  const [selected, setSelected] = useState(null);
  const resource = useResource("/inspections?severe=" + severe, revision);
  return (
    <>
      <PageHead
        title="Inspecciones"
        description="Entrega y devolución de vehículos, con sus observaciones y daños."
      />
      <label className="checkbox-label">
        <input
          type="checkbox"
          checked={severe}
          onChange={(e) => setSevere(e.target.checked)}
        />
        Solo daños de severidad alta
      </label>
      <section className="panel">
        {resource.loading ? (
          <Loading />
        ) : resource.error ? (
          <ErrorBox>{resource.error}</ErrorBox>
        ) : (
          <Table
            rows={resource.data}
            onRow={setSelected}
            columns={[
              { key: "alquilerId", label: "Alquiler" },
              { key: "vehiculoId", label: "Vehículo" },
              { key: "tipo", label: "Tipo" },
              { key: "fecha", label: "Fecha", render: (r) => date(r.fecha) },
              { key: "kilometraje", label: "Km" },
              { key: "combustible", label: "Combustible (%)" },
              { key: "danos", label: "Daños", render: (r) => r.danos.length },
            ]}
          />
        )}
      </section>
      {selected && (
        <Edit
          record={selected}
          admin={admin}
          onClose={() => setSelected(null)}
          onDone={() => {
            setSelected(null);
            changed("Inspección actualizada");
          }}
        />
      )}
    </>
  );
}
function Edit({ record: r, admin, onClose, onDone }) {
  const [annul, setAnnul] = useState(false);
  const [inspection, setInspection] = useState({
    danos: r.danos,
    evidencias: r.evidencias,
    observaciones: r.observaciones || "",
  });
  async function submit(data) {
    return api(
      `/inspections/${r._id}`,
      annul
        ? { method: "DELETE", body: { motivo: data.motivo } }
        : {
            method: "PUT",
            body: {
              version: r.version,
              inspeccion: {
                ...inspection,
                evidencias: inspection.evidencias
                  .map((v) => v.trim())
                  .filter(Boolean),
              },
            },
          },
    );
  }
  return (
    <Modal
      title={annul ? "Anular inspección" : "Corregir inspección"}
      subtitle={`Alquiler #${r.alquilerId} · ${r.tipo}`}
      onClose={onClose}
    >
      <Form
        onSubmit={submit}
        onDone={onDone}
        onCancel={onClose}
        submit={annul ? "Anular" : "Guardar corrección"}
      >
        {annul ? (
          <Field
            label="Motivo"
            name="motivo"
            type="textarea"
            minLength={5}
            maxLength={1000}
            required
          />
        ) : (
          <>
            <p>
              {r.kilometraje} km · Combustible: {r.combustible}%
            </p>
            <InspectionFields value={inspection} onChange={setInspection} />
            {admin && (
              <button
                className="link danger-text"
                type="button"
                onClick={() => setAnnul(true)}
              >
                Anular esta inspección
              </button>
            )}
          </>
        )}
      </Form>
    </Modal>
  );
}
