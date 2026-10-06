#!/usr/bin/env python3
"""Count AX text tokens in exported replay files, excluding all screenshots.

Generate a replay with OPEN_COMPUTER_USE_AX_REPLAY_OUTPUT set while running
AXSnapshotDiffTests/testLocalChangeTokenReplay. Requires tiktoken==0.12.0.
"""
import argparse
import difflib
import json


def measure(document, encoder):
    rows = []
    for scenario in document["scenarios"]:
        full_tokens = auto_tokens = line_tokens = 0
        previous = None
        for observation in scenario["observations"]:
            full, auto = observation["full"], observation["auto"]
            # Ignore the changing protocol ID when comparing rendered tree lines.
            body = full.partition("\n")[2]
            line_diff = full if previous is None else "AX text diff\n" + "\n".join(
                difflib.unified_diff(previous.splitlines(), body.splitlines(), n=1, lineterm="")
            )
            full_tokens += len(encoder.encode(full, disallowed_special=()))
            auto_tokens += len(encoder.encode(auto, disallowed_special=()))
            line_tokens += len(encoder.encode(line_diff, disallowed_special=()))
            previous = body
        rows.append({"scenario": scenario["name"], "observations": len(scenario["observations"]),
                     "full_tokens": full_tokens, "line_diff_tokens": line_tokens,
                     "contextual_auto_tokens": auto_tokens,
                     "auto_reduction_percent": round(100 * (1 - auto_tokens / full_tokens), 2) if full_tokens else 0})
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("replay")
    parser.add_argument("--encoding", default="o200k_base")
    args = parser.parse_args()
    import tiktoken
    with open(args.replay, encoding="utf-8") as stream:
        document = json.load(stream)
    print(json.dumps({"source": document["source"], "encoding": args.encoding,
                      "screenshots_included": False, "results": measure(document, tiktoken.get_encoding(args.encoding))}, indent=2))


if __name__ == "__main__":
    main()
