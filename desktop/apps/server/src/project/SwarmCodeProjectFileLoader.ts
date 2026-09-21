/**
 * SwarmCodeProjectFileLoader - Effect service that loads the checked-in `swarmCode.json`
 * project file from a workspace root.
 *
 * Loading is best-effort: a missing file resolves to `Option.none`, and
 * unreadable or invalid files are logged and treated as absent so callers
 * can fall back to their defaults.
 *
 * @module SwarmCodeProjectFileLoader
 */
import * as Context from "effect/Context";
import * as Effect from "effect/Effect";
import * as FileSystem from "effect/FileSystem";
import * as Layer from "effect/Layer";
import * as Option from "effect/Option";
import * as Path from "effect/Path";
import * as Schema from "effect/Schema";

import { SWARM_PROJECT_FILE_NAME, type SwarmCodeProjectFile } from "@swarmcode/contracts";
import { SwarmCodeProjectFileFromJson } from "@swarmcode/shared/swarmCodeProjectFile";

const decodeSwarmCodeProjectFileJson = Schema.decodeEffect(SwarmCodeProjectFileFromJson);

export class SwarmCodeProjectFileLoadError extends Schema.TaggedError<SwarmCodeProjectFileLoadError>()(
  "SwarmCodeProjectFileLoadError",
  {
    operation: Schema.Literals(["read", "decode"]),
    workspaceRoot: Schema.String,
    filePath: Schema.String,
    cause: Schema.Defect(),
  },
) {
  override get message(): string {
    return `Failed to ${this.operation} ${SWARM_PROJECT_FILE_NAME} at ${this.filePath}.`;
  }
}

/** Service tag for swarmCode.json project file loading. */
export class SwarmCodeProjectFileLoader extends Context.Service<
  SwarmCodeProjectFileLoader,
  {
    /**
     * Load and decode `swarmCode.json` at the workspace root.
     *
     * Never fails: missing, unreadable, or invalid files resolve to
     * `Option.none` (invalid files are logged as warnings).
     */
    readonly load: (workspaceRoot: string) => Effect.Effect<Option.Option<SwarmCodeProjectFile>>;
  }
>()("swarmCode/project/SwarmCodeProjectFileLoader") {}

const logSwarmCodeProjectFileLoadError = (error: SwarmCodeProjectFileLoadError) =>
  Effect.logWarning(error).pipe(
    Effect.annotateLogs({
      operation: error.operation,
      workspaceRoot: error.workspaceRoot,
      filePath: error.filePath,
      errorTag: error._tag,
    }),
  );

/** @public Service construction is part of the canonical Effect module API. */
export const make = Effect.gen(function* () {
  const fileSystem = yield* FileSystem.FileSystem;
  const path = yield* Path.Path;

  const load: SwarmCodeProjectFileLoader["Service"]["load"] = Effect.fn("SwarmCodeProjectFileLoader.load")(
    function* (workspaceRoot) {
      const filePath = path.join(workspaceRoot, SWARM_PROJECT_FILE_NAME);
      const raw = yield* fileSystem.readFileString(filePath).pipe(
        Effect.map(Option.some),
        Effect.catchTags({
          PlatformError: (error) =>
            error.reason._tag === "NotFound"
              ? Effect.succeed(Option.none<string>())
              : logSwarmCodeProjectFileLoadError(
                  new SwarmCodeProjectFileLoadError({
                    operation: "read",
                    workspaceRoot,
                    filePath,
                    cause: error,
                  }),
                ).pipe(Effect.as(Option.none<string>())),
        }),
      );
      if (Option.isNone(raw)) {
        return Option.none<SwarmCodeProjectFile>();
      }
      return yield* decodeSwarmCodeProjectFileJson(raw.value).pipe(
        Effect.map(Option.some),
        Effect.catchTags({
          SchemaError: (error) =>
            logSwarmCodeProjectFileLoadError(
              new SwarmCodeProjectFileLoadError({
                operation: "decode",
                workspaceRoot,
                filePath,
                cause: error,
              }),
            ).pipe(Effect.as(Option.none<SwarmCodeProjectFile>())),
        }),
      );
    },
  );

  return SwarmCodeProjectFileLoader.of({ load });
});

export const layer = Layer.effect(SwarmCodeProjectFileLoader, make);
