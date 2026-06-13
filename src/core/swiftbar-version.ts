// SwiftBar version gate.
//
// SwiftBar 2.0.1 (CFBundleVersion 536) carries upstream bug #442: it
// intermittently persists "NSStatusItem VisibleCC <plugin>" = 0 and the menu-bar
// icon vanishes, staying gone across relaunches. The fix
// (cleanupStatusItemVisibility) first shipped in 2.1.0-beta-1; we require the
// beta-2 build (576) which `.config/install.sh` pins by URL + SHA-256. There is
// no stable 2.1.0 cask, so a `brew upgrade --cask swiftbar` can silently revert
// to 2.0.1 — this gate lets the doctor catch that regression.
export const SWIFTBAR_MIN_BUILD = 576;

export interface SwiftBarVerdict {
  status: 'ok' | 'warn';
  detail: string;
}

/**
 * Decide whether an installed SwiftBar build is acceptable.
 * @param build CFBundleVersion as a number, or null when SwiftBar.app is absent.
 * @returns a verdict, or null when build is null (no app ⇒ nothing to flag here;
 *          the caller decides whether a missing app is itself worth reporting).
 */
export function evaluateSwiftBarBuild(build: number | null): SwiftBarVerdict | null {
  if (build === null) return null;
  if (build >= SWIFTBAR_MIN_BUILD) {
    return { status: 'ok', detail: `SwiftBar build ${build}` };
  }
  return {
    status: 'warn',
    detail:
      `SwiftBar build ${build} < ${SWIFTBAR_MIN_BUILD} (2.1.0-beta-2). ` +
      `2.0.1 has bug #442 (menu icon vanishes). Re-run .config/install.sh to ` +
      `restore the pinned build; avoid 'brew upgrade --cask swiftbar'.`,
  };
}
