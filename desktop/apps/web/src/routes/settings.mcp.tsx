import { createFileRoute } from "@tanstack/react-router";
import { MCPSettingsPanel } from "../components/settings/MCPSettingsPanel";

export const Route = createFileRoute("/settings/mcp")({
  component: MCPSettingsPanel,
});
