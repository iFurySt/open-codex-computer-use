# Prefer regular applications during name resolution

## User request

Prepare the generally useful app-resolution improvement as an independent upstream contribution.

## Changes and intent

Name lookup now prefers regular application display names, then regular executable names, then background application names and executable names. An active helper with the same executable name no longer wins over the intended regular application. Ties retain descriptor order; explicit bundle identifier lookup and blocked-app filtering are unchanged.

The change is limited to `AppDiscovery.swift`, its regression tests, and the feature release note. The tests cover every pair of priority levels in both orders, case-insensitive matching, missing executable names, stable ties, and unmatched queries.
