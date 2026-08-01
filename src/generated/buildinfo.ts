// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of Proofhouse

// The stamp recipe rewrites this file during a build and puts the committed
// copy back afterwards. That copy carries the unstamped fallbacks, so a plain
// source checkout typechecks and runs without a build ever having happened.

/** Short git SHA the build came from, empty when nothing stamped it. */
export const COMMIT: string = "";

/** Calendar date of the build, "unknown" when nothing stamped it. */
export const DATE: string = "unknown";
