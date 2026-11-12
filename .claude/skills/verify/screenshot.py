"""Save a PNG of the running debug app's frame, through the widget inspector.

    python screenshot.py ws://127.0.0.1:PORT/TOKEN=/ws out.png

The image is in physical pixels; the device pixel ratio is printed beside it.
"""

import asyncio
import base64
import json
import sys

import websockets

# Larger than any window, so the frame is never scaled down to fit.
LIMIT = '16384'


async def main(url, out):
    async with websockets.connect(url, max_size=None) as ws:
        sent = 0

        async def call(method, **params):
            nonlocal sent
            sent += 1
            await ws.send(
                json.dumps(
                    {'jsonrpc': '2.0', 'id': sent, 'method': method, 'params': params}
                )
            )
            while True:
                reply = json.loads(await ws.recv())
                if reply.get('id') == sent:
                    if 'error' in reply:
                        sys.exit(f'{method}: {json.dumps(reply["error"])[:400]}')
                    return reply['result']

        isolate = (await call('getVM'))['isolates'][0]['id']
        info = await call('getIsolate', isolateId=isolate)
        ui = next(l['id'] for l in info['libraries'] if l['uri'] == 'dart:ui')
        ratio = await call(
            'evaluate',
            isolateId=isolate,
            targetId=ui,
            expression='PlatformDispatcher.instance.views.first.devicePixelRatio',
        )
        root = await call(
            'ext.flutter.inspector.getRootWidgetTree',
            isolateId=isolate,
            groupName='verify',
            isSummaryTree='true',
            withPreviews='false',
        )
        shot = await call(
            'ext.flutter.inspector.screenshot',
            isolateId=isolate,
            id=root['result']['valueId'],
            width=LIMIT,
            height=LIMIT,
            maxPixelRatio='1',
        )
        if not shot.get('result'):
            sys.exit('no image: is the window on screen?')
        with open(out, 'wb') as f:
            f.write(base64.b64decode(shot['result']))
        print(f'{out} (device pixel ratio {ratio.get("valueAsString")})')


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    asyncio.run(main(sys.argv[1], sys.argv[2]))
