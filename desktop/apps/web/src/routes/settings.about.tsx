import { createFileRoute } from "@tanstack/react-router";

import { AboutSettingsPanel } from "../components/settings/AboutSettingsPanel";

function SettingsAboutRoute() {
  return <AboutSettingsPanel />;
}

export const Route = createFileRoute("/settings/about")({
  component: SettingsAboutRoute,
});
