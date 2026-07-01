#!/usr/bin/env python3

import json

from record_and_replay_baseline_contract import (
    NPM_STAGED_SKILL_REPO_SMOKE_REQUIRED_KEYS,
    NPM_STAGED_SKILL_REPO_SUMMARY_EVIDENCE_KEYS,
    REQUIRED_BASELINE_CHECKS,
    STANDALONE_SKILL_REPO_SMOKE_REQUIRED_KEYS,
    STANDALONE_SKILL_REPO_SUMMARY_EVIDENCE_KEYS,
)


LIFECYCLE_SUMMARY_RENAMES = {
    "checkedOneActive": "checkedLifecycleOneActive",
    "checkedIdempotentStop": "checkedLifecycleIdempotentStop",
    "checkedFinalStatus": "checkedLifecycleFinalStatus",
}


def assert_no_duplicates(label: str, values: tuple[str, ...]) -> None:
    seen = set()
    duplicates = []
    for value in values:
        if value in seen:
            duplicates.append(value)
        seen.add(value)
    assert not duplicates, f"{label} has duplicate keys: {duplicates}"


def renamed_standalone_summary_keys() -> tuple[str, ...]:
    return tuple(
        LIFECYCLE_SUMMARY_RENAMES.get(key, key)
        for key in STANDALONE_SKILL_REPO_SMOKE_REQUIRED_KEYS
    )


def main() -> None:
    constants = {
        "REQUIRED_BASELINE_CHECKS": REQUIRED_BASELINE_CHECKS,
        "STANDALONE_SKILL_REPO_SMOKE_REQUIRED_KEYS": STANDALONE_SKILL_REPO_SMOKE_REQUIRED_KEYS,
        "NPM_STAGED_SKILL_REPO_SMOKE_REQUIRED_KEYS": NPM_STAGED_SKILL_REPO_SMOKE_REQUIRED_KEYS,
        "STANDALONE_SKILL_REPO_SUMMARY_EVIDENCE_KEYS": STANDALONE_SKILL_REPO_SUMMARY_EVIDENCE_KEYS,
        "NPM_STAGED_SKILL_REPO_SUMMARY_EVIDENCE_KEYS": NPM_STAGED_SKILL_REPO_SUMMARY_EVIDENCE_KEYS,
    }
    for label, values in constants.items():
        assert values, f"{label} is empty"
        assert_no_duplicates(label, values)

    assert NPM_STAGED_SKILL_REPO_SUMMARY_EVIDENCE_KEYS == NPM_STAGED_SKILL_REPO_SMOKE_REQUIRED_KEYS
    assert STANDALONE_SKILL_REPO_SUMMARY_EVIDENCE_KEYS == renamed_standalone_summary_keys()

    for smoke_key, summary_key in LIFECYCLE_SUMMARY_RENAMES.items():
        assert smoke_key in STANDALONE_SKILL_REPO_SMOKE_REQUIRED_KEYS
        assert smoke_key not in STANDALONE_SKILL_REPO_SUMMARY_EVIDENCE_KEYS
        assert summary_key in STANDALONE_SKILL_REPO_SUMMARY_EVIDENCE_KEYS
        assert summary_key not in STANDALONE_SKILL_REPO_SMOKE_REQUIRED_KEYS

    assert set(NPM_STAGED_SKILL_REPO_SUMMARY_EVIDENCE_KEYS) == set(NPM_STAGED_SKILL_REPO_SMOKE_REQUIRED_KEYS)
    assert set(STANDALONE_SKILL_REPO_SUMMARY_EVIDENCE_KEYS) == set(renamed_standalone_summary_keys())

    print(
        json.dumps(
            {
                "ok": True,
                "checkedRequiredBaselineChecks": True,
                "checkedNoDuplicateRequiredBaselineChecks": True,
                "checkedStandaloneSmokeRequiredKeys": True,
                "checkedStandaloneSummaryEvidenceKeys": True,
                "checkedStandaloneLifecycleSummaryRenames": True,
                "checkedNpmStagedSmokeRequiredKeys": True,
                "checkedNpmStagedSummaryEvidenceKeys": True,
                "checkedNpmStagedSummaryMatchesSmoke": True,
            },
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
