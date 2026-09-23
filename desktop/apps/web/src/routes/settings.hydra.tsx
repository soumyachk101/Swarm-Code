import { createFileRoute } from "@tanstack/react-router";
import { HydraSettingsPanel } from "../components/settings/HydraSettingsPanel";

function SettingsHydraRoute() {
  return <HydraSettingsPanel />;
}

export const Route = createFileRoute("/settings/hydra")({
  component: SettingsHydraRoute,
});
