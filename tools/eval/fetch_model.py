"""Download the MediaPipe face_landmarker.task model and check its SHA-256.

    python3 tools/eval/fetch_model.py
"""
import hashlib
import os
import urllib.request

URL = ('https://storage.googleapis.com/mediapipe-models/face_landmarker/'
       'face_landmarker/float16/1/face_landmarker.task')
SHA256 = '64184e229b263107bc2b804c6625db1341ff2bb731874b0bcc2fe6544e0bc9ff'
DST = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'models', 'face_landmarker.task')


def main():
    os.makedirs(os.path.dirname(DST), exist_ok=True)
    if not os.path.exists(DST):
        urllib.request.urlretrieve(URL, DST)
    got = hashlib.sha256(open(DST, 'rb').read()).hexdigest()
    if got != SHA256:
        os.remove(DST)
        raise SystemExit(f'sha256 mismatch ({got}); the file was removed. Expected {SHA256}')
    print('model ok', DST, got)


if __name__ == '__main__':
    main()
