import {
  SWARM_PROJECT_FILE_NAME,
  type EnvironmentId,
  type SwarmCodeProjectFile,
  type SwarmCodeProjectFileScript,
} from "@swarmcode/contracts";
import { parseSwarmCodeProjectFile } from "@swarmcode/shared/swarmCodeProjectFile";
import { useMemo } from "react";

import { useProjectFileQuery } from "~/components/files/projectFilesQueryState";

const NO_SCRIPTS: ReadonlyArray<SwarmCodeProjectFileScript> = [];

export interface SwarmCodeProjectFileState {
  /**
   * - `valid`: swarmCode.json exists and decoded.
   * - `invalid`: swarmCode.json exists but fails to decode (the server then ignores
   *   the whole file, including `iconPath` and every script).
   * - `missing`: no readable swarmCode.json at the workspace root.
   * - `loading`: the file query has not settled yet.
   */
  status: "loading" | "missing" | "invalid" | "valid";
  /** The decoded file when status is `valid`, null otherwise. */
  file: SwarmCodeProjectFile | null;
  scripts: ReadonlyArray<SwarmCodeProjectFileScript>;
}

/**
 * Decoded state of the project's checked-in `swarmCode.json`, including whether the
 * file exists but is broken — which the runtime otherwise swallows silently.
 */
export function useSwarmCodeProjectFileState(
  environmentId: EnvironmentId,
  cwd: string | null,
): SwarmCodeProjectFileState {
  const query = useProjectFileQuery(environmentId, cwd ?? "", SWARM_PROJECT_FILE_NAME, cwd !== null);
  const contents = query.data && !query.data.truncated ? query.data.contents : null;
  const isPending = query.isPending;
  return useMemo(() => {
    if (contents === null) {
      return {
        status: isPending ? "loading" : "missing",
        file: null,
        scripts: NO_SCRIPTS,
      } as const;
    }
    const file = parseSwarmCodeProjectFile(contents);
    if (file === null) {
      return { status: "invalid", file: null, scripts: NO_SCRIPTS } as const;
    }
    return { status: "valid", file, scripts: file.scripts ?? NO_SCRIPTS } as const;
  }, [contents, isPending]);
}

/**
 * Scripts declared in the project's checked-in `swarmCode.json`, offered in the
 * scripts menu for import. Missing, truncated, or invalid files resolve to
 * an empty list.
 */
export function useSwarmCodeProjectFileScripts(
  environmentId: EnvironmentId,
  cwd: string | null,
): ReadonlyArray<SwarmCodeProjectFileScript> {
  return useSwarmCodeProjectFileState(environmentId, cwd).scripts;
}
