import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App";

// On Linux there is no OS acrylic — the compositor may blur (Hyprland) or may
// not (stock GNOME/KDE). A translucent tint keeps the UI readable either way.
if (navigator.userAgent.includes("Linux")) {
  document.documentElement.classList.add("linux");
}

ReactDOM.createRoot(document.getElementById("root") as HTMLElement).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
