"""Offline checks: never contact a provider or need a credential."""
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('api_benchmark', Path(__file__).with_name('api-benchmark.py'))
bench = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bench)


class Response(io.BytesIO):
    headers = {'request-id': 'offline-test'}


class BenchmarkTests(unittest.TestCase):
    def test_stream_preserves_creation_and_read_when_delta_updates_output(self):
        events = [
            {'type': 'message_start', 'message': {'model': 'test-model', 'usage': {
                'input_tokens': 11, 'cache_creation_input_tokens': 4096,
                'cache_read_input_tokens': 2048, 'output_tokens': 1}}},
            {'type': 'content_block_delta', 'delta': {'type': 'text_delta', 'text': 'ok'}},
            {'type': 'message_delta', 'usage': {'output_tokens': 8}},
            {'type': 'message_stop'},
        ]
        with tempfile.TemporaryDirectory() as tmp:
            result = Path(tmp) / 'raw.json'
            request = Path(tmp) / 'request.json'
            bench.dump(request, {'id': 'test', 'body': {}, 'result_path': str(result)})
            stream = ''.join('data: ' + json.dumps(e) + '\n\n' for e in events).encode()
            with patch.object(bench, 'request', return_value=Response(stream)):
                self.assertEqual(bench.worker(request), 0)
            raw = json.loads(result.read_text())
            self.assertEqual(raw['usage'], {'input_tokens': 11, 'cache_creation_input_tokens': 4096,
                                           'cache_read_input_tokens': 2048, 'output_tokens': 8})
            self.assertEqual(raw['events'], events)
            self.assertIsNotNone(raw['ttft_seconds'])

    def test_partial_stream_is_not_reported_as_success(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = Path(tmp) / 'raw.json'
            request = Path(tmp) / 'request.json'
            bench.dump(request, {'id': 'test', 'body': {}, 'result_path': str(result)})
            with patch.object(bench, 'request', return_value=Response(b'data: {"type":"ping"}\n\n')):
                self.assertEqual(bench.worker(request), 1)
            self.assertIn('Incomplete SSE', json.loads(result.read_text())['error'])

    def test_default_mode_cannot_make_network_calls(self):
        with patch('sys.argv', ['api-benchmark.py']), patch.object(bench, 'request', side_effect=AssertionError('network forbidden')):
            self.assertEqual(bench.main(), 0)

    def test_full_schedule_and_budget_stop_with_fake_provider(self):
        # Synthetic fixture only: no real usage or prices are produced by this test.
        with tempfile.TemporaryDirectory() as tmp:
            prices = Path(tmp) / 'prices.json'
            bench.dump(prices, dict(model='test', input=1, write_5m=1.25, read=0.1,
                                    output=5, checked='test-fixture', source='https://example.test'))
            def count(endpoint, body):
                self.assertEqual(endpoint, 'messages/count_tokens')
                return Response(b'{"input_tokens": 5000}')
            seen = set()
            def launch(args, check):
                spec = json.loads(Path(args[-1]).read_text())
                prefix = spec['body']['system'][0]['text']
                warm = prefix in seen
                seen.add(prefix)
                bench.dump(spec['result_path'], {'usage': {
                    'input_tokens': 10, 'cache_creation_input_tokens': 0 if warm else 4990,
                    'cache_read_input_tokens': 4990 if warm else 0, 'output_tokens': 8},
                    'model': 'test', 'elapsed_seconds': 0.1, 'ttft_seconds': 0.05})
                return type('Completed', (), {'returncode': 0})()
            out = Path(tmp) / 'results'
            args = ['api-benchmark.py', '--run', '--model', 'test', '--prices', str(prices), '--out', str(out)]
            with patch('sys.argv', args), patch.dict('os.environ', {'ANTHROPIC_API_KEY': 'fake'}), \
                    patch.object(bench, 'git', return_value='fixture'), patch.object(bench, 'request', side_effect=count), patch.object(bench.subprocess, 'run', side_effect=launch), \
                    patch.object(bench.time, 'sleep'), patch('sys.stdout', new_callable=io.StringIO):
                self.assertEqual(bench.main(), 0)
            manifest = json.loads((out / 'manifest.json').read_text())
            self.assertEqual(manifest['completed_requests'], 111)
            self.assertEqual(manifest['status'], 'complete')
            self.assertLess(manifest['usage_priced_usd'], 3)
            # A small budget must stop before launching any billed Messages call.
            args[-1] = str(Path(tmp) / 'blocked')
            with patch('sys.argv', args + ['--budget', '0.000001']), \
                    patch.dict('os.environ', {'ANTHROPIC_API_KEY': 'fake'}), \
                    patch.object(bench, 'git', return_value='fixture'), patch.object(bench, 'request', side_effect=count), \
                    patch.object(bench.subprocess, 'run', side_effect=AssertionError('must not launch')), \
                    patch('sys.stderr', new_callable=io.StringIO):
                self.assertEqual(bench.main(), 1)
            self.assertFalse(list((Path(tmp) / 'blocked').glob('*.raw.json')))

    def test_missing_key_stops_before_network(self):
        with patch('sys.argv', ['api-benchmark.py', '--run']), patch.dict('os.environ', {}, clear=True), \
                patch.object(bench, 'request', side_effect=AssertionError('network forbidden')):
            with self.assertRaises(SystemExit) as exit_info:
                bench.main()
            self.assertEqual(exit_info.exception.code, 2)


if __name__ == '__main__':
    unittest.main()
