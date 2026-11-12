import { useEffect, useState } from "react";
import { CarFront, LogOut } from "lucide-react";
import { api, setToken } from "./api";
import Auth from "./views/Auth";
import Catalog from "./views/Catalog";
import Operations from "./views/Operations";
import Management from "./views/Management";
import Inspections from "./views/Inspections";
import Reports from "./views/Reports";
import Users from "./views/Users";
import Profile from "./views/Profile";
import Charges from "./views/Charges";
import History from "./views/History";

export default function App() {
  const [user, setUser] = useState(null);
  const [section, setSection] = useState("catalog");
  const [revision, setRevision] = useState(0);
  const [notice, setNotice] = useState("");
  const [tab, setTab] = useState("");
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
  if (!user)
    return (
      <Auth
        onLogin={(value) => {
          setUser(value);
          setSection("catalog");
          setTab("");
        }}
      />
    );
  const menus = [
    ["catalog", "Nuestra flota"],
    ["reservations", "Reservas"],
    ["rentals", "Alquileres e inspecciones"],
    ["charges", "Cobros simulados"],
  ];
  if (staff)
    menus.push(
      ["maintenance", "Mantenimiento"],
      ["reports", "Historial y reportes"],
    );
  if (admin) menus.push(["users", "Usuarios y perfiles"]);
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
          <button
            className="button secondary"
            onClick={() => setSection("profile")}
          >
            Mi perfil
          </button>
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
            onClick={() => {
              setSection(key);
              setTab("");
            }}
          >
            {label}
          </button>
        ))}
      </nav>
      <main className="content">
        {section === "catalog" && admin && (
          <div className="form-footer">
            <button className="button secondary" onClick={() => setTab("")}>
              Flota
            </button>
            <button
              className="button secondary"
              onClick={() => setTab("rates")}
            >
              Tarifas y categorías
            </button>
          </div>
        )}
        {section === "reservations" && staff && (
          <div className="form-footer">
            <button className="button secondary" onClick={() => setTab("")}>
              Reservas
            </button>
            <button
              className="button secondary"
              onClick={() => setTab("clients")}
            >
              Clientes
            </button>
          </div>
        )}
        {section === "rentals" && staff && (
          <div className="form-footer">
            <button className="button secondary" onClick={() => setTab("")}>
              Alquileres
            </button>
            <button
              className="button secondary"
              onClick={() => setTab("inspections")}
            >
              Inspecciones
            </button>
          </div>
        )}
        {section === "reports" && staff && (
          <div className="form-footer">
            <button className="button secondary" onClick={() => setTab("")}>
              Reportes
            </button>
            <button
              className="button secondary"
              onClick={() => setTab("history")}
            >
              Historial
            </button>
          </div>
        )}
        {section === "users" && admin && (
          <Users revision={revision} changed={changed} />
        )}
        {section === "profile" && (
          <Profile user={user} setUser={setUser} changed={changed} />
        )}
        {section === "charges" && <Charges revision={revision} />}
        {section === "catalog" && tab !== "rates" && (
          <Catalog
            admin={admin}
            staff={staff}
            revision={revision}
            changed={changed}
          />
        )}
        {["reservations", "rentals"].includes(section) && !tab && (
          <Operations
            key={section}
            rentals={section === "rentals"}
            staff={staff}
            revision={revision}
            changed={changed}
          />
        )}
        {staff &&
          (section === "maintenance" ||
            (section === "reservations" && tab === "clients") ||
            (section === "catalog" && tab === "rates")) && (
            <Management
              key={tab || section}
              section={tab || section}
              admin={admin}
              revision={revision}
              changed={changed}
            />
          )}
        {staff && section === "rentals" && tab === "inspections" && (
          <Inspections admin={admin} revision={revision} changed={changed} />
        )}
        {staff && section === "reports" && !tab && (
          <Reports revision={revision} />
        )}
        {staff && section === "reports" && tab === "history" && (
          <History admin={admin} revision={revision} />
        )}
      </main>
      {notice && (
        <div className="toast" role="status">
          {notice}
        </div>
      )}
    </div>
  );
}
