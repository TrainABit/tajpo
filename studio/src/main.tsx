import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { App } from "./App";
import { StudioProvider } from "./state/store";
import "./styles.css";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <StudioProvider>
      <App />
    </StudioProvider>
  </StrictMode>,
);
