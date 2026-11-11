import { useEffect, useState } from "react";
import { CarFront, LogOut } from "lucide-react";
import { api, setToken } from "./api";
import Auth from "./views/Auth";
import Catalog from "./views/Catalog";
import Operations from "./views/Operations";
import Management from "./views/Management";
import Inspections from "./views/Inspections";
import Reports from "./views/Reports";

export default function App() {
  const [user, setUser] = useState(null);
  const [section, setSection] = useState("catalog");
  const [revision, setRevision] = useState(0);
  const [notice, setNotice] = useState("");
  const admin = user?.roles.includes("ADMIN");
  const staff = admin || user?.roles.includes("OPERADOR");
  useEffect(() => {
    const expired = () => {
      setToken(null);
      setUser(null);
    };
    window.addEventListener("sirav-session-expired", expired);
    return () => window.removeEventListener("sirav-session-expired", expired);
  }, []);
  useEffect(() => {
    if (!notice) return;
    const timeout = setTimeout(() => setNotice(""), 5000);
    return () => clearTimeout(timeout);
  }, [notice]);
  function changed(message) {
    setRevision((n) => n + 1);
    setNotice(message);
  }
  async function logout() {
    try {
      await api("/auth/logout", { method: "POST" });
    } finally {
      setToken(null);
      setUser(null);
      setSection("catalog");
    }
  }
  if (!user) return <Auth onLogin={setUser} />;
  const menus = [
    ["catalog", "Nuestra flota"],
    ["reservations", "Reservas y alquileres"],
  ];
  if (staff)
    menus.push(
      ["clients", "Clientes"],
      ["maintenance", "Mantenimiento"],
      ["inspections", "Inspecciones"],
      ["reports", "Reportes"],
    );
  if (admin) menus.push(["rates", "Tarifas y categorías"]);
  return (
    <div className="app">
      <header className="app-header">
        <a
          href="#"
          onClick={(e) => {
            e.preventDefault();
            setSection("catalog");
          }}
          className="brand"
        >
          <CarFront /> SIRAV
        </a>
        <div className="account">
          <span>
            {user.nombre} · {user.roles.join(", ")}
          </span>
          <button
            className="button secondary"
            onClick={() => logout().catch((e) => setNotice(e.message))}
          >
            <LogOut size={16} />
            Salir
          </button>
        </div>
      </header>
      <nav aria-label="Menú principal">
        {menus.map(([key, label]) => (
          <button
            key={key}
            className={section === key ? "active" : ""}
            onClick={() => setSection(key)}
          >
            {label}
          </button>
        ))}
      </nav>
      <main className="content">
        {section === "catalog" && (
          <Catalog
            admin={admin}
            staff={staff}
            revision={revision}
            changed={changed}
          />
        )}
        {section === "reservations" && (
          <Operations staff={staff} revision={revision} changed={changed} />
        )}
        {staff && ["clients", "maintenance", "rates"].includes(section) && (
          <Management
            key={section}
            section={section}
            admin={admin}
            revision={revision}
            changed={changed}
          />
        )}
        {staff && section === "inspections" && (
          <Inspections admin={admin} revision={revision} changed={changed} />
        )}
        {staff && section === "reports" && <Reports revision={revision} />}
      </main>
      {notice && (
        <div className="toast" role="status">
          {notice}
        </div>
      )}
    </div>
  );
}
