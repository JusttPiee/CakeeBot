// Where the app starts: the browser loads index.html, which loads this file.
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { saveTokenFromUrl } from "./api/client";
import { App } from "./App";
import "./styles/global.css";

// Before anything asks the bot a question: pick up ?token=... from the address, if it is there.
saveTokenFromUrl();

// Put the <App /> component inside <div id="root"> of index.html. From here on, React owns the page.
// StrictMode only does something while developing: it runs extra checks that catch common mistakes.
createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
