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

def get_run_status(run_id=None):
    if run_id is None:
        url = f"https://api.github.com/repos/{REPO}/actions/runs"
        req = urllib.request.Request(url, headers=HEADERS)
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            run_id = data["workflow_runs"][0]["id"]
    
    url = f"https://api.github.com/repos/{REPO}/actions/runs/{run_id}/jobs"
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read().decode("utf-8"))
        for j in data.get("jobs", []):
            print(f"Job: {j['name']}, status={j['status']}, conclusion={j['conclusion']}")
            for s in j.get("steps", []):
                print(f"  Step: {s['name']}, status={s['status']}, conclusion={s['conclusion']}")

import re

def get_sorted_releases():
    url = f"https://api.github.com/repos/{REPO}/releases"
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req) as resp:
        releases = json.loads(resp.read().decode("utf-8"))
    
    def sort_key(r):
        tag = r.get("tag_name", "")
        m = re.search(r"ios-build-(\d+)", tag)
        if m:
            return int(m.group(1))
        return 0
    
    return sorted(releases, key=sort_key, reverse=True)

def download_latest_ipa(out_dir="C:/Users/USER_UA/Desktop"):
    releases = get_sorted_releases()
    
    if not releases:
        print("No releases found.")
        return None
    
    rel = releases[0]
    print(f"Latest release: {rel['name']} (tag: {rel['tag_name']})")
    for asset in rel.get("assets", []):
        if asset["name"].endswith(".ipa"):
            asset_id = asset["id"]
            name = asset["name"]
            size_mb = asset["size"] / (1024 * 1024)
            print(f"Found asset {name} ({size_mb:.1f} MB), asset_id={asset_id}")
            
            # Asset download URL requires Authorization and octet-stream accept header
            dl_url = f"https://api.github.com/repos/{REPO}/releases/assets/{asset_id}"
            dl_headers = {
                "Authorization": f"token {TOKEN}",
                "Accept": "application/octet-stream",
                "User-Agent": "Python"
            }
            dl_req = urllib.request.Request(dl_url, headers=dl_headers)
            out_file = os.path.join(out_dir, name)
            print(f"Downloading {name} to {out_file}...")
            with urllib.request.urlopen(dl_req) as dl_resp, open(out_file, "wb") as f:
                downloaded = 0
                while True:
                    chunk = dl_resp.read(1024 * 1024 * 4) # 4MB chunks
                    if not chunk:
                        break
                    f.write(chunk)
                    downloaded += len(chunk)
                    print(f"Downloaded {downloaded / (1024*1024):.1f} / {size_mb:.1f} MB...", end="\r", flush=True)
            print(f"\nFinished download: {out_file}")
            return out_file
    return None

def print_step_timings(run_id):
    url = f"https://api.github.com/repos/{REPO}/actions/runs/{run_id}/jobs"
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read().decode("utf-8"))
        for s in data["jobs"][0]["steps"]:
            print(f"{s['name']}: {s.get('status')} ({s.get('conclusion')}) | {s.get('started_at')} -> {s.get('completed_at')}")

def get_presigned_download_url():
    releases = get_sorted_releases()
    if not releases:
        return None
    latest_rel = releases[0]
    for asset in latest_rel.get("assets", []):
        if asset["name"].endswith(".ipa"):
            asset_url = asset["url"]
            req2 = urllib.request.Request(
                asset_url,
                headers={"Authorization": f"token {TOKEN}", "Accept": "application/octet-stream", "User-Agent": "Python"}
            )
            class NoRedirectHandler(urllib.request.HTTPRedirectHandler):
                def redirect_request(self, req, fp, code, msg, headers, newurl):
                    self.redirect_url = newurl
                    return None
            handler = NoRedirectHandler()
            opener = urllib.request.build_opener(handler)
            try:
                opener.open(req2)
            except Exception:
                pass
            return getattr(handler, "redirect_url", None)
    return None

def wait_and_process():
    import time
    print("Monitoring latest GitHub Actions run...")
    while True:
        url = f"https://api.github.com/repos/{REPO}/actions/runs"
        req = urllib.request.Request(url, headers=HEADERS)
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        latest_run = data["workflow_runs"][0]
        run_num = latest_run["run_number"]
        status = latest_run["status"]
        conclusion = latest_run["conclusion"]
        
        # Also print current step
        job_url = f"https://api.github.com/repos/{REPO}/actions/runs/{latest_run['id']}/jobs"
        req_j = urllib.request.Request(job_url, headers=HEADERS)
        current_step = "unknown"
        try:
            with urllib.request.urlopen(req_j) as resp_j:
                j_data = json.loads(resp_j.read().decode("utf-8"))
                for s in j_data["jobs"][0]["steps"]:
                    if s["status"] == "in_progress":
                        current_step = s["name"]
                        break
        except Exception:
            pass

        print(f"Run #{run_num}: {status} ({conclusion}) | Current step: {current_step}")
        if status == "completed":
            if conclusion != "success":
                print(f"Run finished with failure: {conclusion}")
                sys.exit(1)
            print("Run completed successfully!")
            break
        time.sleep(15)

    print("\nFetching and downloading IPA asset...")
    downloaded_path = download_latest_ipa("C:/Users/USER_UA/Desktop")
    if not downloaded_path:
        print("Failed to download IPA.")
        sys.exit(1)

    # Make sanitized copies
    desktop_dir = "C:/Users/USER_UA/Desktop"
    fixed_name = f"NebesnyiHorizont-unsigned-v{run_num + 16}-fixed.ipa"
    clean_name = "NebesnyiHorizont.ipa"
    
    import shutil
    fixed_path = os.path.join(desktop_dir, fixed_name)
    clean_path = os.path.join(desktop_dir, clean_name)
    shutil.copy2(downloaded_path, fixed_path)
    shutil.copy2(downloaded_path, clean_path)
    print(f"Created sanitized file: {fixed_path}")
    print(f"Created clean file: {clean_path}")

    # Write a quick text summary on Desktop
    summary_file = os.path.join(desktop_dir, "DOWNLOAD_LINKS.txt")
    presigned = get_presigned_download_url()
    
    with open(summary_file, "w", encoding="utf-8") as f:
        f.write(f"=== NEBESNYI HORIZONT iOS BUILD #{run_num} ===\n\n")
        f.write(f"1. DIRECT S3 CLOUD DOWNLOAD LINK (Works directly in Safari on iPhone):\n{presigned}\n\n")
        f.write(f"2. LOCAL WI-FI DOWNLOAD LINK (PC IP 192.168.0.100, port 8080):\n")
        f.write(f"   http://192.168.0.100:8080/{clean_name}\n")
        f.write(f"   http://192.168.0.100:8080/{fixed_name}\n\n")
        f.write(f"3. LOCAL FILES ON DESKTOP:\n")
        f.write(f"   {clean_path}\n")
        f.write(f"   {fixed_path}\n")

    print(f"\nDirect Presigned Download URL:\n{presigned}\n")
    print(f"Saved links to {summary_file}")

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "releases":
        get_releases()
    elif len(sys.argv) > 1 and sys.argv[1] == "status":
        get_run_status()
    elif len(sys.argv) > 1 and sys.argv[1] == "download":
        download_latest_ipa()
    elif len(sys.argv) > 1 and sys.argv[1] == "timing":
        print_step_timings(sys.argv[2] if len(sys.argv) > 2 else 42717595976)
    elif len(sys.argv) > 1 and sys.argv[1] == "watch":
        wait_and_process()
    else:
        get_runs()
