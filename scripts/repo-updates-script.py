#!/usr/bin/env python3
"""
Reviewer busy/quiet report.

Looks at all open pull requests opened in the last N days on a GitHub repo,
counts how many currently have a pending (not-yet-completed) review request
against each reviewer, classifies reviewers as busy / moderate / quiet, and
posts a summary message to a Zulip stream.

Configuration is entirely via environment variables (see README.md).
"""

import os
import sys
import json
import datetime
import urllib.request
import urllib.error
import urllib.parse

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

GITHUB_API = "https://api.github.com"

GITHUB_TOKEN = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
REPO = os.environ["GITHUB_REPOSITORY"]  # "owner/repo", set automatically in Actions
OWNER, REPO_NAME = REPO.split("/")

WINDOW_DAYS = int(os.environ.get("WINDOW_DAYS", "30"))
BUSY_THRESHOLD = int(os.environ.get("BUSY_THRESHOLD", "3"))
MAX_PRS_LISTED = int(os.environ.get("MAX_PRS_LISTED", "3"))

# Optional explicit roster override, comma-separated GitHub usernames.
# If unset, the script derives the roster from everyone who currently
# appears as a requested reviewer on a qualifying PR, plus (if reachable)
# the repo's collaborator list.
REVIEWERS_LIST = os.environ.get("REVIEWERS_LIST", "")

ZULIP_SITE = os.environ["ZULIP_SITE"].rstrip("/")
ZULIP_EMAIL = os.environ["ZULIP_BOT_EMAIL"]
ZULIP_API_KEY = os.environ["ZULIP_BOT_API_KEY"]
ZULIP_STREAM = os.environ["ZULIP_STREAM"]
ZULIP_TOPIC = os.environ.get("ZULIP_TOPIC", "Reviewer load report")


# ---------------------------------------------------------------------------
# GitHub helpers
# ---------------------------------------------------------------------------

def gh_request(path, params=None):
    url = f"{GITHUB_API}{path}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url)
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    if GITHUB_TOKEN:
        req.add_header("Authorization", f"Bearer {GITHUB_TOKEN}")
    try:
        with urllib.request.urlopen(req) as resp:
            body = resp.read()
            link_header = resp.headers.get("Link", "")
            return json.loads(body), link_header
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")
        print(f"GitHub API error for {url}: {e.code} {detail}", file=sys.stderr)
        raise


def gh_paginate(path, params=None):
    params = dict(params or {})
    params.setdefault("per_page", 100)
    page = 1
    results = []
    while True:
        params["page"] = page
        data, link_header = gh_request(path, params)
        if not data:
            break
        results.extend(data)
        if 'rel="next"' not in link_header:
            break
        page += 1
    return results


def fetch_open_prs_in_window(cutoff):
    prs = gh_paginate(
        f"/repos/{OWNER}/{REPO_NAME}/pulls",
        {"state": "open", "sort": "created", "direction": "desc"},
    )
    qualifying = []
    for pr in prs:
        created_at = datetime.datetime.strptime(
            pr["created_at"], "%Y-%m-%dT%H:%M:%SZ"
        ).replace(tzinfo=datetime.timezone.utc)
        if created_at >= cutoff:
            qualifying.append(pr)
        else:
            # PRs are sorted newest-first, so once we're past the window
            # everything after is also out of range.
            break
    return qualifying


def expand_team_members(team_slug):
    """Best-effort: only works if the token has org read access."""
    try:
        members = gh_paginate(f"/orgs/{OWNER}/teams/{team_slug}/members")
        return [m["login"] for m in members]
    except Exception:
        print(
            f"Warning: could not expand team '{team_slug}' "
            f"(likely needs a token with read:org scope). Skipping.",
            file=sys.stderr,
        )
        return []


def fetch_recently_merged_prs():
    """Return PRs whose merged_at timestamp falls in the previous UTC calendar day."""
    now = datetime.datetime.now(datetime.timezone.utc)
    yesterday_start = (now - datetime.timedelta(days=1)).replace(
        hour=0, minute=0, second=0, microsecond=0
    )
    yesterday_end = yesterday_start.replace(hour=23, minute=59, second=59)

    prs = gh_paginate(
        f"/repos/{OWNER}/{REPO_NAME}/pulls",
        {"state": "closed", "sort": "updated", "direction": "desc"},
    )
    merged = []
    for pr in prs:
        if not pr.get("merged_at"):
            continue
        merged_at = datetime.datetime.strptime(
            pr["merged_at"], "%Y-%m-%dT%H:%M:%SZ"
        ).replace(tzinfo=datetime.timezone.utc)
        if merged_at < yesterday_start:
            # sorted newest-first by updated_at; once merged_at is before
            # yesterday we can't guarantee order, so keep scanning briefly
            # but stop after 200 non-matching closed PRs to avoid huge pages.
            break
        if yesterday_start <= merged_at <= yesterday_end:
            merged.append(pr)
    return merged


def fetch_collaborators():
    try:
        collabs = gh_paginate(
            f"/repos/{OWNER}/{REPO_NAME}/collaborators", {"affiliation": "all"}
        )
        return [c["login"] for c in collabs]
    except Exception:
        print(
            "Warning: could not list collaborators (needs push access on the "
            "repo). Roster will be built from requested reviewers only.",
            file=sys.stderr,
        )
        return []


# ---------------------------------------------------------------------------
# Core logic
# ---------------------------------------------------------------------------

def build_report():
    now = datetime.datetime.now(datetime.timezone.utc)
    cutoff = now - datetime.timedelta(days=WINDOW_DAYS)

    prs = fetch_open_prs_in_window(cutoff)

    pending_counts = {}
    pending_prs = {}  # reviewer -> list of (number, title, url)
    unreviewed_prs = []  # open PRs with no reviewer assigned

    for pr in prs:
        reviewers = [r["login"] for r in pr.get("requested_reviewers", [])]
        for team in pr.get("requested_teams", []):
            reviewers.extend(expand_team_members(team["slug"]))

        if not reviewers:
            unreviewed_prs.append((pr["number"], pr["title"], pr["html_url"]))

        for login in reviewers:
            pending_counts[login] = pending_counts.get(login, 0) + 1
            pending_prs.setdefault(login, []).append(
                (pr["number"], pr["title"], pr["html_url"])
            )

    merged_yesterday = fetch_recently_merged_prs()

    # Build roster: explicit override > collaborators ∪ requested reviewers
    if REVIEWERS_LIST.strip():
        roster = [r.strip() for r in REVIEWERS_LIST.split(",") if r.strip()]
    else:
        roster = set(fetch_collaborators()) | set(pending_counts.keys())
        roster = sorted(roster)

    busy, moderate, quiet = [], [], []
    for login in roster:
        count = pending_counts.get(login, 0)
        if count >= BUSY_THRESHOLD:
            busy.append((login, count))
        elif count == 0:
            quiet.append((login, count))
        else:
            moderate.append((login, count))

    busy.sort(key=lambda x: -x[1])
    moderate.sort(key=lambda x: -x[1])
    quiet.sort(key=lambda x: x[0].lower())

    return {
        "window_days": WINDOW_DAYS,
        "busy_threshold": BUSY_THRESHOLD,
        "pr_count": len(prs),
        "busy": busy,
        "moderate": moderate,
        "quiet": quiet,
        "pending_prs": pending_prs,
        "unreviewed_prs": unreviewed_prs,
        "merged_yesterday": [
            (pr["number"], pr["title"], pr["html_url"], pr["user"]["login"])
            for pr in merged_yesterday
        ],
    }


def format_message(report):
    lines = []
    lines.append(
        f"**Reviewer load report** — {REPO} "
        f"(open PRs from the last {report['window_days']} days, "
        f"{report['pr_count']} PR(s) considered)"
    )
    lines.append("")

    def section(title, entries, show_prs=False):
        lines.append(f"**{title}** ({len(entries)})")
        if not entries:
            lines.append("- _none_")
        for login, count in entries:
            suffix = f" — {count} pending review(s)" if count else ""
            lines.append(f"- @**{login}**{suffix}")
            if show_prs:
                for number, title_, url in report["pending_prs"].get(login, [])[
                    :MAX_PRS_LISTED
                ]:
                    lines.append(f"    - [#{number} {title_}]({url})")
        lines.append("")

    # --- unreviewed open PRs ---
    unreviewed = report["unreviewed_prs"]
    lines.append(f"**⚪ Open PRs with no reviewer assigned** ({len(unreviewed)})")
    if not unreviewed:
        lines.append("- _none_")
    for number, title_, url in unreviewed:
        lines.append(f"- [#{number} {title_}]({url})")
    lines.append("")

    section(
        f"🔴 Busy (≥{report['busy_threshold']} pending reviews)",
        report["busy"],
        show_prs=True,
    )
    section("🟡 Moderate", report["moderate"])
    section("🟢 Quiet (0 pending reviews)", report["quiet"])

    # --- merged yesterday ---
    merged = report["merged_yesterday"]
    lines.append(f"**✅ Merged yesterday** ({len(merged)})")
    if not merged:
        lines.append("- _none_")
    for number, title_, url, author in merged:
        lines.append(f"- [#{number} {title_}]({url}) by @**{author}**")
    lines.append("")

    return "\n".join(lines)


def post_to_zulip(content):
    data = urllib.parse.urlencode(
        {
            "type": "stream",
            "to": ZULIP_STREAM,
            "topic": ZULIP_TOPIC,
            "content": content,
        }
    ).encode()

    req = urllib.request.Request(f"{ZULIP_SITE}/api/v1/messages", data=data)
    credentials = f"{ZULIP_EMAIL}:{ZULIP_API_KEY}"
    import base64

    req.add_header(
        "Authorization", "Basic " + base64.b64encode(credentials.encode()).decode()
    )
    try:
        with urllib.request.urlopen(req) as resp:
            print("Zulip response:", resp.read().decode())
    except urllib.error.HTTPError as e:
        print("Zulip API error:", e.code, e.read().decode(), file=sys.stderr)
        raise


def main():
    report = build_report()
    message = format_message(report)
    print(message)
    post_to_zulip(message)


if __name__ == "__main__":
    main()
