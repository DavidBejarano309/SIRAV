import { useState } from "react";
import { money } from "../api";
import {
  Badge,
  ErrorBox,
  Loading,
  Modal,
  PageHead,
  Table,
  useResource,
} from "../components";
import { RentalDetails } from "./Operations";
export default function Charges({ revision }) {
  const resource = useResource("/charges", revision);
  const [selected, setSelected] = useState(null);
  return (
    <>
      <PageHead
        title="Cobros simulados"
        description="Valores en COP. Base por días, cargo por retraso y pago generado al devolver el vehículo."
      />
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
              { key: "id_alquiler", label: "Alquiler" },
              { key: "cliente", label: "Cliente" },
              { key: "placa", label: "Vehículo" },
              ...[
                ["costo_base", "Base"],
                ["cargos", "Cargos"],
                ["total_simulado", "Total simulado"],
                ["pagado", "Pago simulado"],
              ].map(([key, label]) => ({
                key,
                label,
                render: (r) => money(r[key]),
              })),
              {
                key: "estado_alquiler",
                label: "Estado",
                render: (r) => <Badge value={r.estado_alquiler} />,
              },
            ]}
          />
        )}
      </section>
      {selected && (
        <Modal
          title={`Cobro del alquiler #${selected.id_alquiler}`}
          onClose={() => setSelected(null)}
        >
          <RentalDetails id={selected.id_alquiler} />
        </Modal>
      )}
    </>
  );
}
