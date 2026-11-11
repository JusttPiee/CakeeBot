// A helper for component tests: render a component inside the providers every page relies on
// (language, toasts, the router), so each test file doesn't have to repeat them.
import { render } from "@testing-library/react";
import type { ReactElement } from "react";
import { MemoryRouter } from "react-router-dom";
import { ToastProvider } from "../components/Toast";
import { LanguageProvider } from "../i18n/LanguageContext";

/** route: the address the pretend browser is at, for components that read it. */
export function renderWithApp(ui: ReactElement, route = "/") {
  return render(
    <LanguageProvider>
      <ToastProvider>
        <MemoryRouter initialEntries={[route]}>{ui}</MemoryRouter>
      </ToastProvider>
    </LanguageProvider>,
  );
}
