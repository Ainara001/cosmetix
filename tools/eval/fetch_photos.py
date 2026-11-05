"""Download the evaluation photos listed in a manifest and verify them.

All photos are from Wikimedia Commons under CC0 / CC BY / CC BY-SA (licence and
author of each one are in the manifest; CC BY(-SA) needs attribution if you
republish). They are saved at 800 px width into data/<set>/, which is git-ignored:
the photos themselves are not committed.

Every file is checked: it must be a real JPEG and, when the manifest has a
`sha256`, its hash must match, otherwise the download is rejected (Commons can
change or delete a file, or answer with an HTML error page). A file already on
disk is re-checked, not trusted.

    python3 tools/eval/fetch_photos.py                       # main set (photos_manifest.json)
    python3 tools/eval/fetch_photos.py photos_holdout_manifest.json holdout
    python3 tools/eval/fetch_photos.py --record-hashes       # write sha256 into the manifest
"""
import hashlib
import json
import os
import sys
import time
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
UA = {'User-Agent': 'cosmetix-eval/0.2 (student project; face-zone evaluation)'}


def get(url, tries=5):
    for k in range(tries):
        try:
            return urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60).read()
        except Exception as e:  # network hiccups and rate limits
            print('  retry', k + 1, e)
            time.sleep(3 * (k + 1))
    raise SystemExit('download failed: ' + url)


def problem(data: bytes, want_sha: str | None) -> str | None:
    if not data.startswith(b'\xff\xd8\xff'):
        return 'not a JPEG (an error page?)'
    if want_sha and hashlib.sha256(data).hexdigest() != want_sha:
        return 'sha256 differs from the manifest'
    return None


def main(argv):
    record = '--record-hashes' in argv
    args = [a for a in argv if not a.startswith('--')]
    manifest_name = args[0] if args else 'photos_manifest.json'
    set_name = args[1] if len(args) > 1 else 'photos'
    manifest_path = os.path.join(HERE, manifest_name)
    items = json.load(open(manifest_path, encoding='utf-8'))
    out = os.path.join(HERE, 'data', set_name)
    os.makedirs(out, exist_ok=True)
    bad = 0
    for item in items:
        dst = os.path.join(out, item['file'])
        data = open(dst, 'rb').read() if os.path.exists(dst) else None
        if data is not None and problem(data, item.get('sha256')) is None:
            pass
        else:
            if data is not None:
                print('re-downloading', item['file'], '-', problem(data, item.get('sha256')))
            q = urllib.parse.urlencode({'action': 'query', 'format': 'json', 'titles': item['commons_title'],
                                        'prop': 'imageinfo', 'iiprop': 'url', 'iiurlwidth': 800})
            page = next(iter(json.loads(get('https://commons.wikimedia.org/w/api.php?' + q))['query']['pages'].values()))
            info = page.get('imageinfo')
            if not info:
                print('MISSING on Commons:', item['commons_title'])
                bad += 1
                continue
            data = get(info[0].get('thumburl') or info[0]['url'])
            why = problem(data, item.get('sha256'))
            if why:
                print('REJECTED', item['file'], '-', why)
                bad += 1
                continue
            open(dst, 'wb').write(data)
            print('saved', item['file'], item['license'])
            time.sleep(0.6)
        if record:
            item['sha256'] = hashlib.sha256(data).hexdigest()
    if record:
        json.dump(items, open(manifest_path, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
        print('hashes written to', manifest_name)
    if bad:
        raise SystemExit(f'{bad} file(s) failed')


if __name__ == '__main__':
    main(sys.argv[1:])
