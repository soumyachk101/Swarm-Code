import * as Schema from "effect/Schema";
import * as SchemaTransformation from "effect/SchemaTransformation";

import { ThreadEnvMode } from "./environment.ts";
import { ProjectScriptIcon } from "./orchestration.ts";

/** File name of the checked-in Swarm Code project file, resolved at the workspace root. */
export const SWARM_PROJECT_FILE_NAME = "swarmCode.json";

/** Public URL of the published JSON Schema for {@link SwarmCodeProjectFile}. */
export const SWARM_PROJECT_FILE_SCHEMA_URL = "https://swarmcode.vercel.app/schema/swarmCode.json";

const SWARM_PROJECT_FILE_PATH_MAX_LENGTH = 512;
const SWARM_PROJECT_FILE_MAX_SCRIPTS = 50;

// Annotations go on the encoded (string) side so they survive into the
// published JSON Schema; decoding still trims and re-validates non-emptiness.
const trimmedNonEmpty = (annotations: { readonly description: string }, maxLength?: number) => {
  const annotated = Schema.String.annotate(annotations);
  const encoded =
    maxLength === undefined
      ? annotated.check(Schema.isNonEmpty())
      : annotated.check(Schema.isNonEmpty(), Schema.isMaxLength(maxLength));
  return encoded.pipe(Schema.decodeTo(encoded, SchemaTransformation.trim()));
};

export const SwarmCodeProjectFileScript = Schema.Struct({
  name: trimmedNonEmpty({
    description: "Display name for the script, shown in the Swarm Code scripts menu.",
  }),
  command: trimmedNonEmpty({
    description: "Shell command executed in a Swarm Code terminal at the project root.",
  }),
  icon: Schema.optionalKey(
    ProjectScriptIcon.annotate({
      description: 'Icon shown next to the script in the scripts menu. Defaults to "play".',
    }),
  ),
  runOnWorktreeCreate: Schema.optionalKey(
    Schema.Boolean.annotate({
      description:
        "When true, the script runs automatically after a worktree is created for a new thread.",
    }),
  ),
  async: Schema.optionalKey(
    Schema.Boolean.annotate({
      description:
        "Only for runOnWorktreeCreate scripts. When true (the default), the agent starts while the script is still running. Set false to hold the agent until the script exits.",
    }),
  ),
  previewUrl: Schema.optionalKey(
    trimmedNonEmpty({
      description:
        "URL opened in the in-app browser preview when this script runs. Only honored on the desktop build.",
    }),
  ),
  autoOpenPreview: Schema.optionalKey(
    Schema.Boolean.annotate({
      description:
        "When true, automatically open the preview panel at `previewUrl` the moment the script starts.",
    }),
  ),
}).annotate({
  description: "A project script that team members can import into Swarm Code.",
});
export type SwarmCodeProjectFileScript = typeof SwarmCodeProjectFileScript.Type;

export const SwarmCodeProjectFile = Schema.Struct({
  $schema: Schema.optionalKey(
    Schema.String.annotate({
      description: `URL of the JSON Schema for this file, typically "${SWARM_PROJECT_FILE_SCHEMA_URL}".`,
    }),
  ),
  iconPath: Schema.optionalKey(
    trimmedNonEmpty(
      {
        description:
          'Workspace-relative path to the project icon (e.g. "assets/logo.svg"). Checked before Swarm Code\'s built-in icon locations.',
      },
      SWARM_PROJECT_FILE_PATH_MAX_LENGTH,
    ),
  ),
  defaultThreadEnvMode: Schema.optionalKey(
    ThreadEnvMode.annotate({
      description:
        'Where new threads start for this repository: "worktree" for a fresh git worktree, "local" for the current checkout. A per-project setting in Swarm Code overrides this; when neither is set, the global default applies.',
    }),
  ),
  scripts: Schema.optionalKey(
    Schema.Array(SwarmCodeProjectFileScript)
      .annotate({
        description: "Project scripts shared with everyone who opens this repository in Swarm Code.",
      })
      .check(Schema.isMaxLength(SWARM_PROJECT_FILE_MAX_SCRIPTS)),
  ),
}).annotate({
  title: "Swarm Code project file",
  description:
    "Checked-in project configuration for Swarm Code (swarmCode.json at the repository root). See https://swarmcode.vercel.app for documentation.",
});
export type SwarmCodeProjectFile = typeof SwarmCodeProjectFile.Type;
