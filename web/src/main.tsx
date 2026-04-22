import React from "react";
import ReactDOM from "react-dom/client";
import { App } from "./App";
import { applyTheme, loadThemePref, resolveTheme } from "./lib/theme";
import "./styles.css";

// Apply the theme synchronously before the first paint to avoid a
// light-to-dark flash when the user's preference (or system) is dark.
applyTheme(resolveTheme(loadThemePref()));

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
