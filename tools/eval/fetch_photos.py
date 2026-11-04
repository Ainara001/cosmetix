"""Download the evaluation photos listed in photos_manifest.json.

All photos are from Wikimedia Commons under CC0 / CC BY / CC BY-SA (the licence
and author of each one is in the manifest; CC BY(-SA) needs attribution if you
republish). They are saved at 800 px width into tools/eval/data/photos, which is
git-ignored: the photos themselves are not committed.

    python3 tools/eval/fetch_photos.py
"""
import json
import os
import time
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'data', 'photos')
UA = {'User-Agent': 'cosmetix-eval/0.1 (student project; face-zone evaluation)'}


def get(url, tries=5):
    for k in range(tries):
        try:
            return urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60).read()
        except Exception as e:  # network hiccups and rate limits
            print('  retry', k + 1, e)
            time.sleep(3 * (k + 1))
    raise SystemExit('download failed: ' + url)


def main():
    os.makedirs(OUT, exist_ok=True)
    for item in json.load(open(os.path.join(HERE, 'photos_manifest.json'))):
        dst = os.path.join(OUT, item['file'])
        if os.path.exists(dst):
            continue
        q = urllib.parse.urlencode({'action': 'query', 'format': 'json', 'titles': item['commons_title'],
                                    'prop': 'imageinfo', 'iiprop': 'url', 'iiurlwidth': 800})
        data = json.loads(get('https://commons.wikimedia.org/w/api.php?' + q))
        page = next(iter(data['query']['pages'].values()))
        open(dst, 'wb').write(get(page['imageinfo'][0]['thumburl']))
        print('saved', item['file'], item['license'])
        time.sleep(0.6)


if __name__ == '__main__':
    main()
