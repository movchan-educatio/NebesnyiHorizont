import urllib.request
import json
import os
import sys

TOKEN = "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"
REPO = "movchan-educatio/NebesnyiHorizont"
HEADERS = {
    "Authorization": f"token {TOKEN}",
    "Accept": "application/vnd.github.v3+json",
    "User-Agent": "Python"
}

def get_runs():
    url = f"https://api.github.com/repos/{REPO}/actions/runs"
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read().decode("utf-8"))
        print(f"Total runs: {data.get('total_count')}")
        for r in data.get("workflow_runs", [])[:8]:
            msg = r.get("head_commit", {}).get("message", "").split("\n")[0]
            print(f"Run #{r.get('run_number')} (id={r.get('id')}): status={r.get('status')}, conclusion={r.get('conclusion')}, commit='{msg}'")

def get_releases():
    url = f"https://api.github.com/repos/{REPO}/releases"
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read().decode("utf-8"))
        print(f"Total releases: {len(data)}")
        for rel in data[:5]:
            print(f"Release: tag={rel.get('tag_name')}, name={rel.get('name')}")
            for asset in rel.get("assets", []):
                print(f"  Asset: {asset.get('name')}, size={asset.get('size')}, url={asset.get('browser_download_url')}")

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "releases":
        get_releases()
    else:
        get_runs()
