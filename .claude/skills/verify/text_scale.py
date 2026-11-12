"""Give the running debug app a system text scale, as the platform would.

    python text_scale.py ws://127.0.0.1:PORT/TOKEN=/ws 1.4

Only that process sees it, and only until it quits or the desktop's own
settings change: nothing on the desktop is touched. Pass 1 to put it back.
"""

import asyncio
import json
import sys

import websockets


async def main(url, scale):
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

        async def evaluate(expression):
            result = await call(
                'evaluate', isolateId=isolate, targetId=ui, expression=expression
            )
            if result.get('type') == '@Error':
                sys.exit(f'{expression}: {result.get("message")}')
            return result.get('valueAsString')

        # What the engine sends on flutter/settings; the app is dark only.
        settings = json.dumps(
            {
                'textScaleFactor': scale,
                'alwaysUse24HourFormat': True,
                'platformBrightness': 'dark',
                'nativeSpellCheckServiceDefined': False,
                'supportsShowingSystemContextMenu': False,
                'brieflyShowPassword': False,
            }
        )
        before = await evaluate('PlatformDispatcher.instance.textScaleFactor')
        # Private to dart:ui, which is why the expression is evaluated there.
        await evaluate(
            f'PlatformDispatcher.instance._updateUserSettingsData({json.dumps(settings)})'
        )
        after = await evaluate('PlatformDispatcher.instance.textScaleFactor')
        print(f'text scale {before} -> {after}')


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    asyncio.run(main(sys.argv[1], float(sys.argv[2])))
