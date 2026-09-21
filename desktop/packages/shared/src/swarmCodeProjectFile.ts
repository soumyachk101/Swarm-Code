import * as Exit from "effect/Exit";
import * as Schema from "effect/Schema";

import { SwarmCodeProjectFile, SWARM_PROJECT_FILE_SCHEMA_URL } from "@swarmcode/contracts";

import { fromLenientJson } from "./schemaJson.ts";

/**
 * Codec between the raw `swarmCode.json` file contents (lenient JSONC string) and the
 * decoded {@link SwarmCodeProjectFile}.
 */
export const SwarmCodeProjectFileFromJson = fromLenientJson(SwarmCodeProjectFile);

const decodeSwarmCodeProjectFile = Schema.decodeExit(SwarmCodeProjectFileFromJson);

/**
 * Decode raw `swarmCode.json` contents, treating invalid or malformed files as
 * absent. Clients use this to read optional defaults (scripts, thread env
 * mode) without surfacing decode errors to the user.
 */
export function parseSwarmCodeProjectFile(contents: string): SwarmCodeProjectFile | null {
  const decoded = decodeSwarmCodeProjectFile(contents);
  return Exit.isSuccess(decoded) ? decoded.value : null;
}

/**
 * Build the publishable JSON Schema document for `swarmCode.json` (draft 2020-12).
 *
 * Served from the marketing site at {@link SWARM_PROJECT_FILE_SCHEMA_URL} so
 * editors get LSP support via a `$schema` reference.
 */
export function buildSwarmCodeProjectFileJsonSchema(): Record<string, unknown> {
  // Closed objects, as before effect rc.113 changed the generator default;
  // editors then flag unknown keys in swarmCode.json.
  const document = Schema.toJsonSchemaDocument(SwarmCodeProjectFile, { onExcessProperty: "error" });
  const jsonSchema: Record<string, unknown> = {
    $schema: "https://json-schema.org/draft/2020-12/schema",
    $id: SWARM_PROJECT_FILE_SCHEMA_URL,
    ...document.schema,
  };
  if (document.definitions && Object.keys(document.definitions).length > 0) {
    jsonSchema.$defs = document.definitions;
  }
  return jsonSchema;
}
