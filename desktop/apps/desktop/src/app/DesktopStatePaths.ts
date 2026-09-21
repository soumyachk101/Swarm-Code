import * as Option from "effect/Option";

export type JoinPath = (first: string, ...segments: string[]) => string;

function normalizeConfiguredBaseDir(swarmcodeHome: Option.Option<string>): Option.Option<string> {
  if (Option.isNone(swarmcodeHome)) {
    return Option.none();
  }
  const trimmed = swarmcodeHome.value.trim();
  return trimmed.length > 0 ? Option.some(trimmed) : Option.none();
}

export function resolveDesktopBaseDir(input: {
  readonly homeDirectory: string;
  readonly joinPath: JoinPath;
  readonly swarmcodeHome: Option.Option<string>;
}): string {
  return Option.getOrElse(normalizeConfiguredBaseDir(input.swarmcodeHome), () =>
    input.joinPath(input.homeDirectory, ".swarmcode"),
  );
}

export function resolveDesktopStateDir(input: {
  readonly baseDir: string;
  readonly isDevelopment: boolean;
  readonly joinPath: JoinPath;
  readonly swarmcodeHome: Option.Option<string>;
}): string {
  const useDevSubdir =
    input.isDevelopment && Option.isNone(normalizeConfiguredBaseDir(input.swarmcodeHome));
  return input.joinPath(input.baseDir, useDevSubdir ? "dev" : "userdata");
}
